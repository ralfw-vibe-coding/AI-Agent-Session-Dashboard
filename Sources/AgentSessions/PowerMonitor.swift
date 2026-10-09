import AppKit
import IOKit

/// Tells whether the app should pause its periodic work: while the system sleeps,
/// the displays are off, the screen is locked or the lid is closed.
/// The app never holds a power assertion, so it never keeps the Mac awake.
@MainActor
final class PowerMonitor {
    private(set) var isPaused = false
    var onChange: ((Bool) -> Void)?

    private var systemAsleep = false
    private var screensAsleep = false
    private var screenLocked = false
    private var lidClosed = PowerMonitor.isLidClosed()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.systemAsleep = true }
        observe(workspace, NSWorkspace.didWakeNotification) {
            $0.systemAsleep = false
            $0.lidClosed = PowerMonitor.isLidClosed()
        }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.screensAsleep = false }

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.screenLocked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.screenLocked = false }

        // Closing or opening the lid adds or removes the built-in display.
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) {
            $0.lidClosed = PowerMonitor.isLidClosed()
        }

        update()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ change: @escaping (PowerMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                change(self)
                self.update()
            }
        }
        observers.append((center, token))
    }

    private func update() {
        let paused = systemAsleep || screensAsleep || screenLocked || lidClosed
        guard paused != isPaused else { return }
        isPaused = paused
        onChange?(paused)
    }

    /// Lid state from the power management root domain; false on Macs without a lid.
    private static func isLidClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (value as? Bool) ?? false
    }
}
