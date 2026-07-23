import AppKit
import SwiftUI
import Combine

/// A standard titled window showing the full usage breakdown.
///
/// This replaces the old borderless desktop-level panel. That panel sat at
/// desktop-icon level, so it was invisible to Mission Control and the window
/// switcher and got buried behind everything. A real window shows up in all the
/// usual places, can be moved/resized/minimised normally, and remembers its
/// frame. The at-a-glance role now belongs to the WidgetKit widget.
@MainActor
final class UsageWindowController: NSObject, NSWindowDelegate {
    private let model: UsageModel
    private let window: NSWindow
    private var cancellable: AnyCancellable?
    private static let frameAutosave = "ClaudeUsageWindowFrame"
    private static let floatKey = "UsageWindowFloats"

    /// True once the user has a remembered/manually-set frame, so we stop
    /// auto-fitting and respect their size.
    private var hasUserFrame = false

    /// Called when the user closes the window, so the menu checkmark stays honest.
    var onVisibilityChange: (() -> Void)?

    init(model: UsageModel) {
        self.model = model
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 210),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Usage"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.minSize = NSSize(width: 260, height: 180)
        window.contentView = NSHostingView(
            rootView: UsagePanelView(model: model, fixedWidth: nil, showsTitle: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        )
        // Show on every Space — it's a reference window, not a document.
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        super.init()
        window.delegate = self

        hasUserFrame = window.setFrameUsingName(Self.frameAutosave)
        if !hasUserFrame {
            positionTopRight()
        }
        window.setFrameAutosaveName(Self.frameAutosave)
        applyFloating(Self.floats)

        // Keep the window title showing the headline number at a glance.
        cancellable = model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let pct = model.menuBarUtilization {
                        self.window.title = "Claude Usage — \(UsageFormat.percent(pct))"
                    } else {
                        self.window.title = "Claude Usage"
                    }
                }
            }
    }

    var isVisible: Bool { window.isVisible }

    func show() {
        // Snug the window to its content on first open, so there's no dead space
        // below the limits. Once the user resizes (or a saved frame exists), we
        // leave their size alone.
        if !hasUserFrame { sizeToFitContent() }
        // The app is an accessory (no Dock icon), so it isn't active by default;
        // activate explicitly or the window opens behind the current app.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Sizes the window's height to exactly wrap the current content, keeping the
    /// top-left corner fixed. Measured with a throwaway hosting view at the
    /// current width (the live content view is pinned top for resize behavior,
    /// which makes its own fittingSize unhelpful).
    private func sizeToFitContent() {
        let width = window.contentView?.bounds.width ?? 300
        let probe = NSHostingView(
            rootView: UsagePanelView(model: model, fixedWidth: nil, showsTitle: false)
                .frame(width: width)
        )
        let height = probe.fittingSize.height
        guard height > 0 else { return }
        // A little breathing room below the last row.
        let maxH = (NSScreen.main?.visibleFrame.height ?? 900) - 40
        let clamped = min(max(height + 18, window.minSize.height), maxH)
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(NSSize(width: width, height: clamped))
        window.setFrameTopLeftPoint(topLeft)
    }

    func hide() { window.orderOut(nil) }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    // MARK: - Float on top

    static var floats: Bool {
        get { UserDefaults.standard.object(forKey: floatKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: floatKey) }
    }

    func applyFloating(_ on: Bool) {
        window.level = on ? .floating : .normal
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Closing is just hiding; report it so the menu updates.
        DispatchQueue.main.async { [weak self] in self?.onVisibilityChange?() }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        // The user chose a size — stop auto-fitting and respect it from now on.
        hasUserFrame = true
    }

    private func positionTopRight() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        window.setFrameTopLeftPoint(NSPoint(x: vf.maxX - window.frame.width - 24, y: vf.maxY - 24))
    }
}
