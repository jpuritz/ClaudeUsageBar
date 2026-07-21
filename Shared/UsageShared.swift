import Foundation
import SwiftUI

// MARK: - Model (shared by the app and the widget extension)

struct UsageLimit: Identifiable, Codable, Hashable {
    let id: String
    let label: String
    /// Percent, 0–100.
    let utilization: Double
    let resetsAt: Date?
}

/// What the host app hands to the widget through the App Group container.
struct UsageSnapshot: Codable {
    var limits: [UsageLimit]
    var updated: Date
    var subscription: String?

    /// The headline number: the 5-hour session window when present.
    var headline: UsageLimit? {
        limits.first(where: { $0.id == "five_hour" })
            ?? limits.max(by: { $0.utilization < $1.utilization })
    }

    static let empty = UsageSnapshot(limits: [], updated: .distantPast, subscription: nil)
}

// MARK: - App Group plumbing

enum SharedStore {
    /// On macOS an App Group id is team-prefixed, which isn't known until signing.
    /// Both targets carry it in Info.plist as `$(TeamIdentifierPrefix)group.…`,
    /// expanded at build time, so we just read it back here.
    static var appGroupID: String {
        (Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "group.com.jpuritz.claude-usage"
    }

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private static var snapshotURL: URL? {
        containerURL?.appendingPathComponent("usage-snapshot.json")
    }

    static func write(_ snapshot: UsageSnapshot) {
        guard let url = snapshotURL,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    static func read() -> UsageSnapshot? {
        guard let url = snapshotURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data)
        else { return nil }
        return snapshot
    }
}

// MARK: - Presentation helpers (shared)

enum UsageFormat {
    static func percent(_ v: Double) -> String {
        String(format: "%.0f%%", v.rounded())
    }

    static func resetString(_ date: Date?) -> String {
        guard let date else { return "" }
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "resetting…" }
        if interval < 36 * 3600 {
            let h = Int(interval) / 3600
            let m = (Int(interval) % 3600) / 60
            return h > 0 ? "resets in \(h)h \(m)m" : "resets in \(m)m"
        }
        let f = DateFormatter()
        f.dateFormat = "EEE h a"
        return "resets \(f.string(from: date))"
    }

    static func staleString(_ updated: Date) -> String {
        let mins = Int(Date().timeIntervalSince(updated) / 60)
        if mins < 2 { return "just now" }
        if mins < 60 { return "\(mins)m ago" }
        return "\(mins / 60)h ago"
    }
}

func severityColor(_ pct: Double) -> Color {
    switch pct {
    case ..<50: return Color(red: 0.22, green: 0.72, blue: 0.45)
    case ..<75: return Color(red: 0.95, green: 0.77, blue: 0.06)
    case ..<90: return Color(red: 0.96, green: 0.55, blue: 0.14)
    default: return Color(red: 0.91, green: 0.26, blue: 0.21)
    }
}
