import SwiftUI
import AppKit

// MARK: - Shared pieces

func severityColor(_ pct: Double) -> Color {
    switch pct {
    case ..<50: return Color(red: 0.22, green: 0.72, blue: 0.45)
    case ..<75: return Color(red: 0.95, green: 0.77, blue: 0.06)
    case ..<90: return Color(red: 0.96, green: 0.55, blue: 0.14)
    default: return Color(red: 0.91, green: 0.26, blue: 0.21)
    }
}

struct LimitRow: View {
    let limit: UsageLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.label)
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 8)
                Text(UsageFormat.percent(limit.utilization))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(severityColor(limit.utilization))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(severityColor(limit.utilization))
                        .frame(width: max(4, geo.size.width * limit.utilization / 100))
                }
            }
            .frame(height: 6)
            if limit.resetsAt != nil {
                Text(UsageFormat.resetString(limit.resetsAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct UsagePanelView: View {
    @ObservedObject var model: UsageModel
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Claude Usage")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                if let sub = model.subscription, !sub.isEmpty {
                    Text(sub.capitalized)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.12)))
                        .foregroundStyle(.secondary)
                }
            }
            if model.limits.isEmpty && model.errorMessage == nil {
                Text("Loading…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            ForEach(model.limits) { limit in
                LimitRow(limit: limit)
            }
            if let err = model.errorMessage {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let updated = model.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(compact ? 12 : 14)
        .frame(width: 264, alignment: .leading)
    }
}

// MARK: - Desktop widget chrome

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct DesktopWidgetView: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        UsagePanelView(model: model, compact: true)
            .background(VisualEffectBackground())
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
    }
}
