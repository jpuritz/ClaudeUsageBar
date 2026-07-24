import Foundation
import SwiftUI

/// Overall Statuspage indicator, worst-first.
enum ServiceHealth: String {
    case none        // all operational
    case minor
    case major
    case critical
    case maintenance
    case unknown

    init(indicator: String) {
        self = ServiceHealth(rawValue: indicator) ?? .unknown
    }

    var isOperational: Bool { self == .none }

    /// Reuses the usage palette so a yellow incident dot is the same yellow as a
    /// 60%-full bar. `unknown` has no severity — it means "not measured yet".
    var severity: Severity? {
        switch self {
        case .none: return .ok
        case .minor, .maintenance: return .notice
        case .major: return .warning
        case .critical: return .critical
        case .unknown: return nil
        }
    }

    var color: Color { severity?.color ?? Color.secondary }

    var nsColor: NSColor { severity?.nsColor ?? .secondaryLabelColor }
}

struct ServiceComponent: Identifiable {
    let id: String
    let name: String
    let status: String   // operational, degraded_performance, partial_outage, major_outage
    var isOperational: Bool { status == "operational" }
}

/// Polls the public Claude Statuspage feed (no auth) and publishes overall
/// health plus per-component status. Independent of the usage endpoint.
@MainActor
final class StatusModel: ObservableObject {
    @Published var health: ServiceHealth = .unknown
    @Published var summary: String = ""
    @Published var components: [ServiceComponent] = []
    @Published var lastUpdated: Date?

    /// Components we surface / alert on — the ones a Claude Code user relies on.
    /// Matched by prefix, since the feed appends URLs, e.g.
    /// "Claude API (api.anthropic.com)". Statuspage also lists Cowork/Government,
    /// which we skip. Display uses the short name.
    private static let relevant: [(match: String, short: String)] = [
        ("claude.ai", "claude.ai"),
        ("Claude API", "Claude API"),
        ("Claude Code", "Claude Code"),
        ("Claude Console", "Claude Console"),
    ]

    private let endpoint = URL(string: "https://status.claude.com/api/v2/summary.json")!
    private var previouslyDown: Set<String> = []

    func refresh() {
        Task { await fetch() }
    }

    private func fetch() async {
        var req = URLRequest(url: endpoint)
        req.timeoutInterval = 15
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        if let status = root["status"] as? [String: Any] {
            health = ServiceHealth(indicator: status["indicator"] as? String ?? "unknown")
            summary = status["description"] as? String ?? ""
        }

        var comps: [ServiceComponent] = []
        if let list = root["components"] as? [[String: Any]] {
            for c in list {
                guard let rawName = c["name"] as? String,
                      let id = c["id"] as? String,
                      let st = c["status"] as? String,
                      (c["group"] as? Bool) != true,
                      let match = Self.relevant.first(where: { rawName.hasPrefix($0.match) })
                else { continue }
                comps.append(ServiceComponent(id: id, name: match.short, status: st))
            }
        }
        // Preserve a stable display order.
        components = Self.relevant.compactMap { entry in
            comps.first(where: { $0.name == entry.short })
        }
        lastUpdated = Date()

        alertOnNewOutages()
    }

    /// Notify once when a relevant service transitions into a non-operational
    /// state, and note when it recovers.
    private func alertOnNewOutages() {
        guard Prefs.notifyStatus else { previouslyDown = []; return }
        let downNow = Set(components.filter { !$0.isOperational }.map(\.name))
        let newlyDown = downNow.subtracting(previouslyDown)
        let recovered = previouslyDown.subtracting(downNow)

        for name in newlyDown.sorted() {
            let comp = components.first(where: { $0.name == name })
            NotificationManager.shared.post(
                id: "status-down-\(name)-\(Int(Date().timeIntervalSince1970))",
                title: "\(name) issue",
                body: comp.map { statusLabel($0.status) } ?? "Service disruption reported."
            )
        }
        if !recovered.isEmpty && newlyDown.isEmpty {
            NotificationManager.shared.post(
                id: "status-up-\(Int(Date().timeIntervalSince1970))",
                title: "Claude services recovered",
                body: "\(recovered.sorted().joined(separator: ", ")) back to normal."
            )
        }
        previouslyDown = downNow
    }

    func statusLabel(_ status: String) -> String {
        switch status {
        case "operational": return "Operational"
        case "degraded_performance": return "Degraded performance"
        case "partial_outage": return "Partial outage"
        case "major_outage": return "Major outage"
        case "under_maintenance": return "Under maintenance"
        default: return status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
