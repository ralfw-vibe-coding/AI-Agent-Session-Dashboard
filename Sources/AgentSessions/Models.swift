import AppKit
import SwiftUI

enum ScreenEdge: String, Codable, CaseIterable, Identifiable {
    case top, bottom, left, right

    var id: String { rawValue }

    var label: String {
        switch self {
        case .top: "Oben"
        case .bottom: "Unten"
        case .left: "Links"
        case .right: "Rechts"
        }
    }

    /// Left/right edges: the rail runs vertically.
    var isVertical: Bool { self == .left || self == .right }
}

enum EdgePosition: String, Codable, CaseIterable, Identifiable {
    case start, center, end

    var id: String { rawValue }

    func label(for edge: ScreenEdge) -> String {
        switch self {
        case .center: "Mitte"
        case .start: edge.isVertical ? "Oben" : "Links"
        case .end: edge.isVertical ? "Unten" : "Rechts"
        }
    }
}

struct Assistant: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    /// "#RRGGBB"
    var color: String

    static let defaults: [Assistant] = [
        Assistant(id: "claude-code", name: "Claude Code", color: "#D97757"),
        Assistant(id: "claude-cowork", name: "Claude Cowork", color: "#C9A227"),
        Assistant(id: "chatgpt-work", name: "ChatGPT Work", color: "#10A37F"),
        Assistant(id: "chatgpt-codex", name: "ChatGPT Codex", color: "#5B7CFA"),
        Assistant(id: "gemini", name: "Gemini", color: "#A970FF"),
        Assistant(id: "other", name: "Andere", color: "#8E8E93"),
    ]

    static let unknown = Assistant(id: "?", name: "Unbekannt", color: "#8E8E93")
}

struct Session: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    /// Assistant id, e.g. "claude-code".
    var assistant: String
    var createdAt: Date

    init(id: String = UUID().uuidString, title: String, assistant: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.assistant = assistant
        self.createdAt = createdAt
    }

    // Lenient decoding so the JSON file can be written by hand or by scripts.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        assistant = try c.decodeIfPresent(String.self, forKey: .assistant) ?? "other"
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
    }
}

struct AppData: Codable {
    var edge: ScreenEdge = .right
    var position: EdgePosition = .center
    var assistants: [Assistant] = Assistant.defaults
    var sessions: [Session] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        edge = (try? c.decodeIfPresent(ScreenEdge.self, forKey: .edge)) ?? .right
        position = (try? c.decodeIfPresent(EdgePosition.self, forKey: .position)) ?? .center
        assistants = try c.decodeIfPresent([Assistant].self, forKey: .assistants) ?? Assistant.defaults
        sessions = try c.decodeIfPresent([Session].self, forKey: .sessions) ?? []
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        guard s.count == 6, Scanner(string: s).scanHexInt64(&value) else {
            self = .gray
            return
        }
        self = Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#8E8E93" }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}

/// "jetzt", "12m", "3h", "2d"
func shortAge(from start: Date, to now: Date) -> String {
    let s = Int(now.timeIntervalSince(start))
    if s < 60 { return "jetzt" }
    if s < 3600 { return "\(s / 60)m" }
    if s < 86400 { return "\(s / 3600)h" }
    return "\(s / 86400)d"
}
