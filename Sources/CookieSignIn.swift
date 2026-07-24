import AppKit
import WebKit

/// Embedded claude.ai sign-in for no-prompt mode (Mode 2).
///
/// Opens a real WebKit browser window pointed at claude.ai. Once the user is
/// signed in, it harvests the session cookies and saves them to a Keychain item
/// this app owns — so later usage reads never trigger an authorization prompt.
///
/// The WebView uses the SAME User-Agent our fetch uses, so the Cloudflare
/// clearance cookie (`cf_clearance`) it earns stays valid for the `URLSession`
/// requests that read usage. cf_clearance is bound to the User-Agent, so a
/// mismatch would get us a 403 challenge.
@MainActor
final class CookieSignInController: NSObject, WKNavigationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var pollTimer: Timer?
    private var saved = false
    private let onSaved: () -> Void

    init(onSaved: @escaping () -> Void) {
        self.onSaved = onSaved
        super.init()
    }

    func present() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        saved = false

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()   // persistent: remembers the login
        let wv = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 460, height: 680), configuration: config
        )
        wv.customUserAgent = UsageModel.browserUA
        wv.navigationDelegate = self
        webView = wv

        let win = NSWindow(
            contentRect: wv.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        win.title = "Sign in to claude.ai"
        win.contentView = wv
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        window = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        wv.load(URLRequest(url: URL(string: "https://claude.ai/login")!))

        // claude.ai is a single-page app, so a login can complete without a full
        // navigation. Poll the cookie store as well as reacting to navigations.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.harvestIfSignedIn() }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        harvestIfSignedIn()
    }

    // MARK: - Harvest

    private func harvestIfSignedIn() {
        guard !saved, let webView else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            // WKHTTPCookieStore invokes its completion on the main thread.
            MainActor.assumeIsolated {
                guard !self.saved else { return }
                let claude = cookies.filter { $0.domain.contains("claude.ai") }
                guard claude.contains(where: { $0.name == "sessionKey" && !$0.value.isEmpty })
                else { return }
                let header = claude.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                self.saved = true
                KeychainReader.writeCookie(header)
                self.onSaved()
                self.finishSuccess()
            }
        }
    }

    private func finishSuccess() {
        pollTimer?.invalidate(); pollTimer = nil
        let alert = NSAlert()
        alert.messageText = "No-prompt mode is on"
        alert.informativeText =
            "Signed in to claude.ai. Claudar now reads your usage without " +
            "password prompts. You can turn this off any time from the menu."
        alert.addButton(withTitle: "Done")
        alert.runModal()
        window?.close()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        pollTimer?.invalidate(); pollTimer = nil
        window = nil
        webView = nil
    }
}
