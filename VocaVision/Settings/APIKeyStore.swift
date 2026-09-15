import Foundation
import Observation
import Security

/// Persists the Gemini API key in the Keychain and exposes a reactive cache
/// of its current state to SwiftUI. The store never holds the key in
/// `UserDefaults` or in plain memory longer than necessary for a request.
///
/// **Launch-time behaviour.** `init()` is intentionally trivial — it does
/// no I/O. The first `hasKey` reflection of the keychain happens
/// asynchronously via `hydrate()`, which runs on a utility-priority
/// queue. This avoids a synchronous Security framework round-trip on
/// the main thread during cold launch.
@Observable
final class APIKeyStore {
    private let service = "com.vocavision.app"
    private let account = "gemini.api.key"

    /// Reactive flag observed by `HomeView` and `SettingsView`. Starts
    /// `false` and flips to `true` once `hydrate()` confirms a stored
    /// key — typically within a few milliseconds of process start.
    private(set) var hasKey: Bool = false

    init() {
        // No I/O here on purpose — the main thread should not block on
        // SecItemCopyMatching during App launch.
        hydrate()
    }

    /// Reads the keychain off the main thread and updates `hasKey`. Safe
    /// to call repeatedly — only mutates state if the value changed.
    func hydrate() {
        let service = self.service
        let account = self.account
        Task.detached(priority: .utility) { [weak self] in
            let exists = Self.readFromKeychain(service: service, account: account) != nil
            await MainActor.run {
                guard let self else { return }
                if self.hasKey != exists { self.hasKey = exists }
            }
        }
    }

    /// Returns the stored key for in-flight network calls. Avoid retaining it.
    /// Synchronous because callers need the key immediately for a network
    /// request. Called from off-main contexts (e.g. orchestrator setup),
    /// so the Security cost is rarely on the UI thread.
    func currentKey() -> String? {
        Self.readFromKeychain(service: service, account: account)
    }

    /// Stores or replaces the Gemini API key in the Keychain.
    @discardableResult
    func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8) else { return false }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        let success = (status == errSecSuccess)
        if success { self.hasKey = true }
        return success
    }

    /// Removes the stored key.
    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        self.hasKey = false
    }

    nonisolated private static func readFromKeychain(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }
}
