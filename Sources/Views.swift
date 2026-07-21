import SwiftUI
import AppKit

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
    /// Menus need an intrinsic width; the resizable window passes nil to flex.
    var fixedWidth: CGFloat? = 264
    /// The window puts the name in its title bar, so it hides this one.
    var showsTitle: Bool = true

    @ViewBuilder private var subscriptionBadge: some View {
        if let sub = model.subscription, !sub.isEmpty {
            Text(sub.capitalized)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.12)))
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Without the title there's nothing to balance the badge against, so
            // the whole row is dropped and the badge moves to the footer.
            if showsTitle {
                HStack {
                    Text("Claude Usage")
                        .font(.system(size: 12, weight: .bold))
                    Spacer()
                    subscriptionBadge
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
            HStack(alignment: .center) {
                if let updated = model.lastUpdated {
                    Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                if !showsTitle {
                    Spacer()
                    subscriptionBadge
                }
            }
        }
        .padding(compact ? 12 : 14)
        .frame(width: fixedWidth, alignment: .leading)
        .frame(maxWidth: fixedWidth == nil ? .infinity : nil, alignment: .leading)
    }
}

// The frosted-glass chrome that used to wrap this view is gone: the usage window
// is now a standard titled window and uses the system's own window background.
