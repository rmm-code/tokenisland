import Foundation
import LocalAuthentication
import Security

struct ClaudeUsageCredential: Sendable {
    let accessToken: String
    let expiresAt: Date?
}

protocol ClaudeUsageCredentialProviding: Sendable {
    func load(allowsInteraction: Bool) async throws -> ClaudeUsageCredential
}

/// Read-only login access. Credentials are read afresh for each request so
/// login rotation/account switches cannot leave a process-lifetime token.
struct ClaudeUsageCredentials: ClaudeUsageCredentialProviding {
    enum KeychainResult: Sendable {
        case data(Data)
        case notFound
        case failed(ClaudeUsageIssue)
    }
    var fileURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
    var readKeychain: @Sendable (Bool) -> KeychainResult = Self.readKeychain

    func load(allowsInteraction: Bool) async throws -> ClaudeUsageCredential {
        // macOS Claude Code's active login is in Keychain. An obsolete
        // credentials file must not shadow that account or token.
        switch readKeychain(allowsInteraction) {
        case .data(let data): return try Self.decode(data)
        case .failed(let issue): throw issue
        case .notFound:
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  let data = try? Data(contentsOf: fileURL)
            else { throw ClaudeUsageIssue.signInRequired }
            return try Self.decode(data)
        }
    }

    private static func readKeychain(allowsInteraction: Bool) -> KeychainResult {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(keychainQuery(allowsInteraction: allowsInteraction) as CFDictionary, &item)
        AppLog.app.info("Claude usage credential lookup status: \(status, privacy: .public)")
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return .failed(.signInRequired) }
            return .data(data)
        case errSecInteractionNotAllowed, errSecAuthFailed:
            return .failed(.accessRequired)
        case errSecUserCanceled:
            return .failed(.accessDenied)
        case errSecItemNotFound:
            return .notFound
        default:
            return .failed(.keychainUnavailable)
        }
    }

    static func keychainQuery(allowsInteraction: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if !allowsInteraction {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        return query
    }

    static func decode(_ data: Data) throws -> ClaudeUsageCredential {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else {
            AppLog.app.notice("Claude usage credential record has no usable claude.ai access token")
            throw ClaudeUsageIssue.signInRequired
        }
        var expiresAt: Date?
        if let expires = (oauth["expiresAt"] as? NSNumber)?.doubleValue, expires.isFinite {
            // Support seconds and milliseconds without turning a seconds
            // timestamp into a spurious 1970 expiry.
            expiresAt = Date(timeIntervalSince1970: expires > 100_000_000_000 ? expires / 1000 : expires)
        }
        return ClaudeUsageCredential(accessToken: token, expiresAt: expiresAt)
    }
}
