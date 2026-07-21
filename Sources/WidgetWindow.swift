import AppKit
import SwiftUI
import Combine

/// SwiftUI hosting views intercept mouse events, which defeats
/// isMovableByWindowBackground — so start the window drag ourselves.
private final class DraggableHostingView: NSHostingView<DesktopWidgetView> {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

/// A borderless, non-activating panel pinned at desktop-icon level so it behaves
/// like a desktop widget: visible with the desktop, under all normal windows,
/// draggable anywhere, position remembered across launches.
@MainActor
final class WidgetWindowController {
    private let panel: NSPanel
    private let hosting: NSHostingView<DesktopWidgetView>
    private var cancellable: AnyCancellable?
    private static let frameKey = "ClaudeUsageWidgetOrigin"

    init(model: UsageModel) {
        hosting = DraggableHostingView(rootView: DesktopWidgetView(model: model))

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 264, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting

        sizeToFit()
        restoreOrigin()

        cancellable = model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.sizeToFit() }
            }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.saveOrigin() }
        }
    }

    var isVisible: Bool { panel.isVisible }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }

    private func sizeToFit() {
        let size = hosting.fittingSize
        guard size.height > 0 else { return }
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        panel.setContentSize(size)
        panel.setFrameTopLeftPoint(topLeft)
    }

    private func saveOrigin() {
        let o = panel.frame.origin
        UserDefaults.standard.set([o.x, o.y], forKey: Self.frameKey)
    }

    private func restoreOrigin() {
        if let saved = UserDefaults.standard.array(forKey: Self.frameKey) as? [Double],
           saved.count == 2 {
            let origin = NSPoint(x: saved[0], y: saved[1])
            // Only restore if still on some screen.
            if NSScreen.screens.contains(where: { $0.frame.insetBy(dx: -40, dy: -40).contains(origin) }) {
                panel.setFrameOrigin(origin)
                return
            }
        }
        // Default: top-right corner of the main screen, under the menu bar.
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(
                x: vf.maxX - panel.frame.width - 24,
                y: vf.maxY - 24
            ))
        }
    }
}
