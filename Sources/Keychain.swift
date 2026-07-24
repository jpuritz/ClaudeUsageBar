import Foundation
import Security

struct OAuthCredentials {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let subscriptionType: String?
}

enum KeychainError: Error, LocalizedError {
    case notFound
    case accessDenied
    case unreadable(OSStatus)
    case badFormat

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "No Claude Code credentials found. Sign in with the Claude Code CLI first."
        case .accessDenied:
            return "Keychain access denied. Relaunch and click “Always Allow”."
        case .unreadable(let status):
            return "Keychain error (\(status))."
        case .badFormat:
            return "Credentials found but in an unexpected format."
        }
    }
}

enum KeychainReader {
    /// Optional claude.ai session cookie, stored under "Claudar-cookie".
    ///
    /// When present this is preferred over the Claude Code credentials, because
    /// it's an item this app OWNS — reading it never triggers an authorization
    /// prompt. Reading Claude Code's item does, and that grant is wiped every
    /// time the CLI renews the token (~every 8h), which is the whole reason this
    /// mode exists.
    static func readCookie() -> String? {
        guard let data = readData(service: "Claudar-cookie"),
              let s = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty
        else { return nil }
        return s
    }

    /// Saves a claude.ai Cookie header (written by the embedded sign-in).
    static func writeCookie(_ header: String) {
        guard let data = header.data(using: .utf8) else { return }
        writeData(data, service: "Claudar-cookie")
    }

    static func clearCookie() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claudar-cookie",
        ] as CFDictionary)
    }

    /// Optional user-provided long-lived token, stored under "Claudar-token".
    static func readCustomToken() -> String? {
        guard let data = readData(service: "Claudar-token"),
              let token = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else { return nil }
        return token
    }

    /// Reads (read-only) the OAuth credentials Claude Code stores under
    /// "Claude Code-credentials". This app never writes to that item.
    static func readClaudeCredentials() throws -> OAuthCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess: break
        case errSecItemNotFound: throw KeychainError.notFound
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            throw KeychainError.accessDenied
        default: throw KeychainError.unreadable(status)
        }
        guard let data = item as? Data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { throw KeychainError.badFormat }

        var expires: Date?
        if let ms = oauth["expiresAt"] as? Double {
            expires = Date(timeIntervalSince1970: ms / 1000.0)
        }
        return OAuthCredentials(
            accessToken: token,
            refreshToken: oauth["refreshToken"] as? String,
            expiresAt: expires,
            subscriptionType: oauth["subscriptionType"] as? String
        )
    }

    // MARK: - App-private session store ("Claudar-session")
    //
    // Holds refreshed tokens the app mints itself. Completely separate from the
    // Claude Code credential item, which this app only ever reads.

    static func readSession() -> OAuthCredentials? {
        guard let data = readData(service: "Claudar-session"),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["accessToken"] as? String
        else { return nil }
        var expires: Date?
        if let t = obj["expiresAt"] as? Double { expires = Date(timeIntervalSince1970: t) }
        return OAuthCredentials(
            accessToken: access,
            refreshToken: obj["refreshToken"] as? String,
            expiresAt: expires,
            subscriptionType: obj["subscriptionType"] as? String
        )
    }

    static func writeSession(
        accessToken: String, refreshToken: String?, expiresAt: Date, subscription: String? = nil
    ) {
        var obj: [String: Any] = [
            "accessToken": accessToken,
            "expiresAt": expiresAt.timeIntervalSince1970,
        ]
        if let refreshToken { obj["refreshToken"] = refreshToken }
        if let subscription { obj["subscriptionType"] = subscription }
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        writeData(data, service: "Claudar-session")
    }

    static func clearSession() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claudar-session",
        ] as CFDictionary)
    }

    // MARK: - Generic helpers (own items only)

    private static func readData(service: String) -> Data? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ] as CFDictionary, &item)
        return status == errSecSuccess ? item as? Data : nil
    }

    private static func writeData(_ data: Data, service: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let updated = SecItemUpdate(
            base as CFDictionary, [kSecValueData as String: data] as CFDictionary
        )
        if updated == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccount as String] = "claudar"
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
