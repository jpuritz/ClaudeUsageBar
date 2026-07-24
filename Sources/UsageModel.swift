import Foundation
import Combine
import WidgetKit

@MainActor
final class UsageModel: ObservableObject {
    @Published var limits: [UsageLimit] = []
    @Published var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published var subscription: String?

    private var inFlight = false
    private var nextAttemptAllowed = Date.distantPast
    private var consecutive429s = 0
    /// Guards against re-invoking the CLI in a tight loop if it can't fix things.
    private var lastCLIRefresh = Date.distantPast

    /// What the menu bar shows: the 5-hour session limit, since that's the one
    /// that bites during a working session. Falls back to the highest limit if
    /// the session window isn't in the response.
    var menuBarUtilization: Double? {
        limits.first(where: { $0.id == "five_hour" })?.utilization
            ?? limits.map(\.utilization).max()
    }

    func refresh(force: Bool = false) {
        guard !inFlight else { return }
        if !force && Date() < nextAttemptAllowed { return }
        inFlight = true
        Task {
            await self.fetch()
            self.inFlight = false
        }
    }

    /// Hands fresh data to the widget extension. The widget is sandboxed and
    /// can't fetch or reach the Keychain itself, so the app writes a snapshot to
    /// the shared App Group container and asks WidgetKit to reload.
    private func publishToWidget(_ limits: [UsageLimit]) {
        SharedStore.write(UsageSnapshot(
            limits: limits, updated: Date(), subscription: subscription
        ))
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Refresh only if the data is older than `seconds` (used on menu close).
    func refreshIfStale(seconds: TimeInterval) {
        if let updated = lastUpdated, Date().timeIntervalSince(updated) < seconds { return }
        refresh()
    }

    // MARK: - Fetch

    nonisolated private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let preferCurlKey = "PreferCurlTransport"

    private struct ResolvedToken {
        let token: String
        let isCustom: Bool
        let subscription: String?
    }

    // MARK: - claude.ai cookie mode

    /// Matches a real browser. claude.ai sits behind Cloudflare; requests must
    /// look like a browser AND come from a TLS stack Cloudflare accepts.
    /// URLSession works here where curl and Python get a 403 challenge page —
    /// so cookie mode deliberately never uses the curl fallback.
    nonisolated static let browserUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    private static let orgIDKey = "ClaudeOrgID"
    private static let planKey = "ClaudeOrgPlan"

    /// claude.ai reports the plan as an org capability, e.g. ["claude_pro", "chat"].
    nonisolated static func planLabel(from capabilities: [String]) -> String? {
        if capabilities.contains("claude_max") { return "Max" }
        if capabilities.contains("claude_pro") { return "Pro" }
        if capabilities.contains("claude_team") { return "Team" }
        if capabilities.contains("claude_enterprise") { return "Enterprise" }
        return nil
    }

    nonisolated static func browserRequest(_ url: URL, cookie: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
        req.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "Referer")
        req.timeoutInterval = 25
        return req
    }

    /// The cookie carries `lastActiveOrg`, so we can usually skip a lookup.
    nonisolated static func orgID(fromCookie cookie: String) -> String? {
        for piece in cookie.split(separator: ";") {
            let kv = piece.trimmingCharacters(in: .whitespaces)
            guard kv.hasPrefix("lastActiveOrg=") else { continue }
            let raw = String(kv.dropFirst("lastActiveOrg=".count))
            let value = raw.removingPercentEncoding ?? raw
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// Resolves (and caches) the organization UUID and plan label. Both are
    /// cached in UserDefaults, so the extra lookup happens at most once — the
    /// org alone is usually in the cookie, but the plan only comes from the API.
    private func resolveOrgInfo(cookie: String) async -> (org: String, plan: String?)? {
        let cachedOrg = UserDefaults.standard.string(forKey: Self.orgIDKey)
        let cachedPlan = UserDefaults.standard.string(forKey: Self.planKey)
        if let cachedOrg, !cachedOrg.isEmpty, cachedPlan != nil {
            return (cachedOrg, cachedPlan)
        }

        // One lookup gets both the uuid and the plan capabilities.
        let req = Self.browserRequest(URL(string: "https://claude.ai/api/organizations")!,
                                      cookie: cookie)
        if let (data, resp) = try? await URLSession.shared.data(for: req),
           (resp as? HTTPURLResponse)?.statusCode == 200,
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let org = arr.first {
            let uuid = (org["uuid"] as? String) ?? cachedOrg ?? Self.orgID(fromCookie: cookie)
            let plan = Self.planLabel(from: org["capabilities"] as? [String] ?? [])
            if let uuid { UserDefaults.standard.set(uuid, forKey: Self.orgIDKey) }
            if let plan { UserDefaults.standard.set(plan, forKey: Self.planKey) }
            if let uuid { return (uuid, plan ?? cachedPlan) }
        }

        // Lookup failed — fall back to the org embedded in the cookie.
        if let org = cachedOrg ?? Self.orgID(fromCookie: cookie), !org.isEmpty {
            UserDefaults.standard.set(org, forKey: Self.orgIDKey)
            return (org, cachedPlan)
        }
        return nil
    }

    /// Picks the access token to use, minimizing reads of Claude Code's Keychain
    /// item. Priority:
    ///   1. A user-set long-lived token (`ClaudeUsage-token`).
    ///   2. Our own cached copy of the CLI token (`ClaudeUsage-session`).
    ///   3. Claude Code's credentials — read once to bootstrap, then cached in (2).
    ///
    /// Why the cache: reading Claude Code's item is a *cross-app* Keychain access,
    /// which macOS gates with an authorization prompt (and re-prompts whenever our
    /// signature changes). Reading our OWN item never prompts. So normal polling
    /// and wake-refreshes read the cache and stay silent; we only touch Claude
    /// Code's item on first launch and after a 401 (see the 401 handler, which
    /// clears the cache so the freshly-renewed credential is re-read).
    ///
    /// We deliberately IGNORE `expiresAt` and use the token until the server
    /// rejects it — the server is the authority, and tokens are often accepted
    /// past their nominal expiry.
    private func resolveToken() async throws -> ResolvedToken {
        // (1) User-set long-lived token.
        if let custom = await Task.detached(priority: .userInitiated, operation: {
            KeychainReader.readCustomToken()
        }).value {
            return ResolvedToken(token: custom, isCustom: true, subscription: nil)
        }

        // (2) Our own cached copy — no authorization prompt.
        if let session = await Task.detached(priority: .userInitiated, operation: {
            KeychainReader.readSession()
        }).value {
            return ResolvedToken(token: session.accessToken, isCustom: false,
                                 subscription: session.subscriptionType)
        }

        // (3) Bootstrap from Claude Code's item (may prompt once), then cache.
        let creds = try await Task.detached(priority: .userInitiated) {
            try KeychainReader.readClaudeCredentials()
        }.value
        KeychainReader.writeSession(
            accessToken: creds.accessToken,
            refreshToken: creds.refreshToken,
            expiresAt: creds.expiresAt ?? .distantFuture,
            subscription: creds.subscriptionType
        )
        return ResolvedToken(token: creds.accessToken, isCustom: false,
                             subscription: creds.subscriptionType)
    }

    /// Triggers the CLI to renew its stored credential, then the app re-reads it.
    ///
    /// The app can't call the OAuth refresh endpoint itself (it blocks non-browser
    /// clients), but the CLI renews the token as a side effect of a real API call
    /// and writes the result back to the Keychain. Note `claude auth status` does
    /// NOT work here: it only reports locally-stored state and never hits the
    /// network. So we make the smallest real call possible (haiku, two-word
    /// prompt, no session file) — a negligible number of tokens, ~3x a day.
    nonisolated private static func runCLIAuthRefresh() async -> Bool {
        let candidates = [
            NSHomeDirectory() + "/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        guard let path = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else { return false }

        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = [
                    "-p", "hi",
                    "--model", "haiku",
                    "--no-session-persistence",
                ]
                p.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
                // Strip nested-session guards so it runs from any context.
                var env = ProcessInfo.processInfo.environment
                for key in ["CLAUDECODE", "CLAUDE_CODE_CHILD_SESSION",
                            "CLAUDE_CODE_SESSION_ACCESS_TOKEN"] {
                    env.removeValue(forKey: key)
                }
                p.environment = env
                p.standardOutput = Pipe()
                p.standardError = Pipe()
                do { try p.run() } catch {
                    cont.resume(returning: false); return
                }
                // Don't let a stalled CLI hang the app.
                DispatchQueue.global().asyncAfter(deadline: .now() + 45) {
                    if p.isRunning { p.terminate() }
                }
                p.waitUntilExit()
                cont.resume(returning: p.terminationStatus == 0)
            }
        }
    }

    private func fetch() async {
        // Cookie mode takes priority: it reads only Keychain items this app owns,
        // so it never triggers an authorization prompt.
        if let cookie = await Task.detached(priority: .userInitiated, operation: {
            KeychainReader.readCookie()
        }).value {
            await fetchViaCookie(cookie)
            return
        }
        await fetchViaBearer()
    }

    /// claude.ai path — same limit fields as the OAuth endpoint, so the existing
    /// parser handles the response unchanged.
    private func fetchViaCookie(_ cookie: String) async {
        guard let info = await resolveOrgInfo(cookie: cookie) else {
            errorMessage = "Couldn't determine your organization from the saved cookie."
            return
        }
        if let plan = info.plan { subscription = plan }
        let url = URL(string: "https://claude.ai/api/organizations/\(info.org)/usage")!
        let req = Self.browserRequest(url, cookie: cookie)

        let data: Data, http: HTTPURLResponse
        do {
            let (d, resp) = try await URLSession.shared.data(for: req)
            guard let h = resp as? HTTPURLResponse else { return }
            data = d; http = h
        } catch {
            errorMessage = "Network error: \(error.localizedDescription)"
            return
        }

        switch http.statusCode {
        case 200:
            let parsed = Self.parseLimits(from: data)
            if parsed.isEmpty {
                errorMessage = "Usage response had no limit data."
            } else {
                let previous = limits
                limits = parsed
                lastUpdated = Date()
                errorMessage = nil
                consecutive429s = 0
                nextAttemptAllowed = .distantPast
                AlertEngine.shared.evaluate(previous: previous, current: parsed)
                publishToWidget(parsed)
            }
        case 401:
            errorMessage = "claude.ai session expired — re-copy your Cookie (see README)."
        case 403:
            // Cloudflare serves an HTML challenge when cf_clearance goes stale.
            let body = String(data: data.prefix(200), encoding: .utf8) ?? ""
            errorMessage = body.contains("Just a moment")
                ? "Cloudflare challenge — your cf_clearance cookie expired; re-copy your Cookie."
                : "claude.ai refused the request (403)."
            Self.appendLog("cookie mode HTTP 403")
        case 429:
            consecutive429s += 1
            var delay = min(3600.0, 300.0 * pow(2, Double(consecutive429s - 1)))
            if let ra = http.value(forHTTPHeaderField: "Retry-After"), let s = Double(ra) {
                delay = max(delay, s)
            }
            nextAttemptAllowed = Date(timeIntervalSinceNow: delay)
            let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
            errorMessage = "Rate limited — retrying after \(f.string(from: nextAttemptAllowed))."
        default:
            errorMessage = "claude.ai returned HTTP \(http.statusCode)."
            Self.appendLog("cookie mode HTTP \(http.statusCode)")
        }
    }

    private func fetchViaBearer() async {
        let accessToken: String
        var usingCustomToken = false
        do {
            let resolved = try await resolveToken()
            accessToken = resolved.token
            usingCustomToken = resolved.isCustom
            subscription = resolved.subscription
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let creds = OAuthCredentials(
            accessToken: accessToken, refreshToken: nil, expiresAt: nil, subscriptionType: subscription
        )

        var status: Int?
        var body = Data()
        var retryAfter: Double?
        var transport = "urlsession"

        // If curl previously succeeded where URLSession was blocked, lead with curl.
        if UserDefaults.standard.bool(forKey: Self.preferCurlKey),
           let r = await Self.curlFetch(token: creds.accessToken) {
            (status, body) = r
            transport = "curl"
        }

        if status == nil {
            var request = URLRequest(url: Self.endpoint)
            request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 20
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { return }
                status = http.statusCode
                body = data
                if let ra = http.value(forHTTPHeaderField: "Retry-After") {
                    retryAfter = Double(ra)
                }
            } catch {
                errorMessage = "Network error: \(error.localizedDescription)"
                return
            }

            // URLSession blocked? Try once through curl — a different TLS stack,
            // in case the edge is fingerprinting the client.
            if status == 429, let alt = await Self.curlFetch(token: creds.accessToken) {
                Self.appendLog("URLSession got 429; curl attempt returned \(alt.0)")
                if alt.0 == 200 {
                    (status, body) = alt
                    transport = "curl"
                    retryAfter = nil
                    UserDefaults.standard.set(true, forKey: Self.preferCurlKey)
                }
            }
        }

        guard let status else {
            errorMessage = "Request failed with no response."
            return
        }

        switch status {
        case 200:
            let parsed = Self.parseLimits(from: body)
            if parsed.isEmpty {
                errorMessage = "Usage response had no limit data."
            } else {
                let previous = limits
                limits = parsed
                lastUpdated = Date()
                errorMessage = nil
                consecutive429s = 0
                nextAttemptAllowed = .distantPast
                AlertEngine.shared.evaluate(previous: previous, current: parsed)
                publishToWidget(parsed)
            }
        case 401, 403:
            if usingCustomToken {
                errorMessage = "Long-lived token rejected — remove the ClaudeUsage-token Keychain item to fall back."
            } else if Date().timeIntervalSince(lastCLIRefresh) > 300,
                      await Self.runCLIAuthRefresh() {
                // Our cached token was rejected. The CLI owns this credential's
                // lifecycle and can reach the refresh endpoint (which blocks this
                // app directly), so it just renewed Claude Code's item. Drop our
                // stale cache so the retry re-reads and re-caches the fresh token.
                KeychainReader.clearSession()
                Self.appendLog("401 → triggered CLI to renew credential.")
                errorMessage = "Refreshing sign-in…"
                lastCLIRefresh = Date()
                refresh(force: true)   // retry immediately with the new token
            } else {
                errorMessage = "Sign-in expired — run `claude` in Terminal, then /login."
            }
        case 429:
            consecutive429s += 1
            // Exponential backoff: 5, 10, 20, 40, 60, 60… minutes,
            // or the server's Retry-After if longer.
            var delay = min(3600.0, 300.0 * pow(2, Double(consecutive429s - 1)))
            if let retryAfter { delay = max(delay, retryAfter) }
            nextAttemptAllowed = Date(timeIntervalSinceNow: delay)
            let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
            errorMessage = "Rate limited (via \(transport)) — retrying after \(f.string(from: nextAttemptAllowed))."
            let raText = retryAfter.map { String(Int($0)) } ?? "none"
            let bodyText = String(data: body.prefix(500), encoding: .utf8) ?? ""
            Self.appendLog("HTTP 429 via \(transport), retry-after header: \(raText)\n\(bodyText)")
        default:
            errorMessage = "Usage endpoint returned HTTP \(status)."
            Self.appendLog("HTTP \(status) via \(transport)\n\(String(data: body.prefix(1000), encoding: .utf8) ?? "<non-UTF8>")")
        }
    }

    /// Fetches via /usr/bin/curl. Headers go through stdin (never argv, so the
    /// token is not visible in the process list). Returns (status, body).
    nonisolated private static func curlFetch(token: String) async -> (Int, Data)? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                // --http1.1 + axios-style Accept headers: mirror the Claude Code
                // CLI's request shape exactly (Node speaks HTTP/1.1; the edge
                // appears to classify clients partly on this).
                p.arguments = [
                    "-s", "-m", "20", "--http1.1", "--compressed",
                    "-H", "@-",
                    "-w", "\nHTTPSTATUS:%{http_code}",
                    endpoint.absoluteString,
                ]
                let stdin = Pipe(), stdout = Pipe()
                p.standardInput = stdin
                p.standardOutput = stdout
                p.standardError = Pipe()
                do { try p.run() } catch {
                    cont.resume(returning: nil)
                    return
                }
                let headers = """
                Authorization: Bearer \(token)
                anthropic-beta: oauth-2025-04-20
                Content-Type: application/json
                User-Agent: \(userAgent)
                Accept: application/json, text/plain, */*
                """
                stdin.fileHandleForWriting.write(headers.data(using: .utf8)!)
                stdin.fileHandleForWriting.closeFile()
                let out = stdout.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                guard let s = String(data: out, encoding: .utf8),
                      let marker = s.range(of: "\nHTTPSTATUS:", options: .backwards),
                      let code = Int(s[marker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)),
                      code > 0
                else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: (code, Data(s[..<marker.lowerBound].utf8)))
            }
        }
    }

    /// Matches the User-Agent the Claude Code CLI sends ("claude-code/<version>") —
    /// the usage endpoint rejects unrecognized user agents. Reads the installed CLI
    /// version from the ~/.local/bin/claude symlink when possible.
    nonisolated static let userAgent: String = {
        let fallback = "claude-code/2.1.63"
        let link = NSHomeDirectory() + "/.local/bin/claude"
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: link) else {
            return fallback
        }
        let version = (dest as NSString).lastPathComponent
        let looksLikeVersion = version.range(
            of: #"^\d+\.\d+\.\d+"#, options: .regularExpression
        ) != nil
        return looksLikeVersion ? "claude-code/\(version)" : fallback
    }()

    /// Appends diagnostics to ~/Library/Logs (kept under ~100 KB).
    nonisolated static func appendLog(_ message: String) {
        let path = NSHomeDirectory() + "/Library/Logs/ClaudeUsage-last-error.txt"
        var existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        if existing.count > 100_000 { existing = String(existing.suffix(50_000)) }
        let text = existing + "[\(Date())] \(message)\n"
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Parsing

    private static let labelMap: [String: String] = [
        "five_hour": "Session (5 h)",
        "seven_day": "Weekly · all models",
        "seven_day_sonnet": "Weekly · Sonnet",
        "seven_day_opus": "Weekly · Opus",
        "seven_day_oauth_apps": "Weekly · OAuth apps",
        "extra_usage": "Extra usage",
    ]

    private static let preferredOrder = [
        "five_hour", "seven_day", "seven_day_sonnet", "seven_day_opus",
        "seven_day_oauth_apps", "extra_usage",
    ]

    /// Parses the /api/oauth/usage payload defensively: any top-level (or one level
    /// nested) object containing a numeric "utilization" is treated as a limit.
    static func parseLimits(from data: Data) -> [UsageLimit] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return []
        }
        var found: [String: UsageLimit] = [:]

        func scan(_ dict: [String: Any]) {
            for (key, value) in dict {
                guard let entry = value as? [String: Any] else { continue }
                if let num = entry["utilization"] as? NSNumber {
                    let label = labelMap[key] ?? key
                        .replacingOccurrences(of: "_", with: " ")
                        .capitalized
                    found[key] = UsageLimit(
                        id: key,
                        label: label,
                        utilization: min(max(num.doubleValue, 0), 100),
                        resetsAt: (entry["resets_at"] as? String).flatMap(parseISODate)
                    )
                } else {
                    scan(entry)
                }
            }
        }
        scan(root)

        var ordered: [UsageLimit] = []
        for key in preferredOrder {
            if let l = found.removeValue(forKey: key) { ordered.append(l) }
        }
        ordered.append(contentsOf: found.values.sorted { $0.id < $1.id })
        return ordered
    }

    static func parseISODate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
