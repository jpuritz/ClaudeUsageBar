import SwiftUI
import AppKit

/// Layout constants for `UsagePanelView`, in one place because
/// `UsageWindowController.sizeToFitContent()` has to compute the panel's height
/// arithmetically (AppKit's measurement APIs over-report badly for this layout —
/// see the note there). Two copies of these numbers would silently drift.
enum PanelMetrics {
    static let padding: CGFloat = 14
    static let compactPadding: CGFloat = 12
    static let stackSpacing: CGFloat = 10

    // LimitRow internals.
    static let rowSpacing: CGFloat = 3
    static let labelHeight: CGFloat = 16     // a 12 pt label, rendered
    static let barHeight: CGFloat = 6
    static let resetHeight: CGFloat = 13     // a 10 pt line, rendered

    static let loadingHeight: CGFloat = 16
    static let errorHeight: CGFloat = 30     // allows for a second wrapped line
    static let footerHeight: CGFloat = 18
    static let bottomBreathingRoom: CGFloat = 12

    static func rowHeight(hasReset: Bool) -> CGFloat {
        labelHeight + rowSpacing + barHeight
            + (hasReset ? rowSpacing + resetHeight : 0)
    }
}

struct LimitRow: View {
    let limit: UsageLimit

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) {
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
            .frame(height: PanelMetrics.barHeight)
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
        VStack(alignment: .leading, spacing: PanelMetrics.stackSpacing) {
            // Without the title there's nothing to balance the badge against, so
            // the whole row is dropped and the badge moves to the footer.
            if showsTitle {
                HStack {
                    Text("Claudar")
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
        .padding(compact ? PanelMetrics.compactPadding : PanelMetrics.padding)
        .frame(width: fixedWidth, alignment: .leading)
        .frame(maxWidth: fixedWidth == nil ? .infinity : nil, alignment: .leading)
    }
}

// The frosted-glass chrome that used to wrap this view is gone: the usage window
// is now a standard titled window and uses the system's own window background.
