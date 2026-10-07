import AppKit
import Combine
import SwiftUI

/// Borderless floating panel that stays on all Spaces (also over full-screen apps)
/// and never activates the app when clicked.
final class EdgePanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 30, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        becomesKeyOnlyIfNeeded = true
    }

    // Needed so the "new session" text field can receive keyboard input.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that reports mouse enter/exit for the whole panel.
final class RailHostingView: NSHostingView<AnyView> {
    var onMouseEnter: (() -> Void)?
    var onMouseExit: (() -> Void)?
    private var hoverArea: NSTrackingArea?

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if event.trackingArea === hoverArea { onMouseEnter?() }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if event.trackingArea === hoverArea { onMouseExit?() }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class EdgeRailController: ObservableObject {
    @Published private(set) var isExpanded = false
    @Published private(set) var isAdding = false
    /// RailItem.id of the session whose title is being edited.
    @Published private(set) var renamingID: String?
    @Published var showArchive = false

    private var isTextInputActive: Bool { isAdding || renamingID != nil }

    let store: Store
    private let panel = EdgePanel()
    private var hosting: RailHostingView!
    private let settings = SettingsWindowController()

    private var contentSize = CGSize(width: 26, height: 40)
    private var collapseWork: DispatchWorkItem?
    private var isMenuOpen = false
    private var previousApp: NSRunningApplication?
    private var cancellables = Set<AnyCancellable>()

    init(store: Store) {
        self.store = store

        hosting = RailHostingView(rootView: AnyView(RailRootView(store: store, rail: self)))
        hosting.sizingOptions = []
        hosting.onMouseEnter = { [weak self] in self?.mouseEntered() }
        hosting.onMouseExit = { [weak self] in self?.scheduleCollapse() }
        panel.contentView = hosting

        // Edge/position changes move the panel.
        store.$data
            .map { ($0.edge, $0.position) }
            .removeDuplicates(by: ==)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.relayout() } }
            .store(in: &cancellables)

        let nc = NotificationCenter.default
        nc.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.relayout() }
            .store(in: &cancellables)
        nc.publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] _ in self?.isMenuOpen = true }
            .store(in: &cancellables)
        nc.publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] _ in
                self?.isMenuOpen = false
                self?.scheduleCollapse()
            }
            .store(in: &cancellables)
        nc.publisher(for: NSWindow.didResignKeyNotification, object: panel)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.isAdding { self.endAdding(restoreFocus: false) }
                if self.renamingID != nil { self.endRename(restoreFocus: false) }
            }
            .store(in: &cancellables)
    }

    func show() {
        relayout()
        panel.orderFrontRegardless()
    }

    // MARK: Hover

    private var isMouseInside: Bool {
        panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }

    private func mouseEntered() {
        collapseWork?.cancel()
        if !isExpanded { isExpanded = true }
    }

    private func scheduleCollapse() {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isExpanded, !self.isTextInputActive, !self.isMenuOpen, !self.isMouseInside else { return }
            self.isExpanded = false
            self.showArchive = false
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    // MARK: Text input (adding, renaming)

    func beginAdding() {
        renamingID = nil
        startTextInput()
        isAdding = true
    }

    func endAdding(restoreFocus: Bool = true) {
        isAdding = false
        finishTextInput(restoreFocus: restoreFocus)
    }

    func beginRename(_ itemID: String) {
        isAdding = false
        startTextInput()
        renamingID = itemID
    }

    func endRename(restoreFocus: Bool = true) {
        renamingID = nil
        finishTextInput(restoreFocus: restoreFocus)
    }

    private func startTextInput() {
        if !isTextInputActive {
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front == NSRunningApplication.current ? nil : front
        }
        collapseWork?.cancel()
        isExpanded = true
        panel.makeKey()
    }

    private func finishTextInput(restoreFocus: Bool) {
        if restoreFocus {
            // Hand keyboard focus back to whatever app was in front before.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
            previousApp?.activate()
        }
        previousApp = nil
        scheduleCollapse()
    }

    func openSettings() {
        settings.show(store: store)
    }

    // MARK: Layout

    func contentSizeDidChange(_ size: CGSize) {
        DispatchQueue.main.async { [weak self] in
            self?.contentSize = size
            self?.relayout()
        }
    }

    private func relayout() {
        guard let screen = NSScreen.screens.first else { return }
        let vf = screen.visibleFrame
        let size = CGSize(width: ceil(contentSize.width), height: ceil(contentSize.height))
        let margin: CGFloat = 40
        let edge = store.data.edge
        let position = store.data.position

        var origin = CGPoint.zero
        if edge.isVertical {
            origin.x = edge == .left ? vf.minX : vf.maxX - size.width
            switch position {
            case .start: origin.y = vf.maxY - margin - size.height
            case .center: origin.y = vf.midY - size.height / 2
            case .end: origin.y = vf.minY + margin
            }
        } else {
            origin.y = edge == .top ? vf.maxY - size.height : vf.minY
            switch position {
            case .start: origin.x = vf.minX + margin
            case .center: origin.x = vf.midX - size.width / 2
            case .end: origin.x = vf.maxX - margin - size.width
            }
        }
        origin.x = origin.x.rounded()
        origin.y = origin.y.rounded()

        let frame = NSRect(origin: origin, size: size)
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(store: Store) {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = "Agent Sessions – Assistenten"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: AssistantsSettingsView(store: store))
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
