import Foundation
import Security

/// API keys and the Google sign-in, kept together in one login-keychain item (never in plain settings).
/// macOS ties a keychain item to the exact build of an ad-hoc signed app, so after an update it asks once for the
/// login password before the new build may read it; one item keeps that to a single question.
/// QA runs use memory only, so tests never touch the real item.
@MainActor
enum Secrets {
    static var inMemory = false { didSet { cache = nil } }
    /// The keychain service; the self-test points it at a throwaway one.
    static var service = "local.saku.app"
    private static var cache: [String: String]?
    private static let account = "secrets"
    /// Before 1.2.2 every key had its own item. Access tokens aren't carried over: the refresh token gets a new one.
    private static let oldItems = ["google-oauth-client-id", "google-oauth-client-secret", "google-tasks-refresh",
                                   "anthropic", "gemini", "deepl", "google-translate"]

    static func get(_ name: String) -> String { all()[name] ?? "" }

    static func set(_ name: String, _ value: String) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var values = all()
        values[name] = v.isEmpty ? nil : v
        cache = values
        if !inMemory { save(values) }
    }

    static func has(_ name: String) -> Bool { !get(name).isEmpty }

    private static func all() -> [String: String] {
        if let cache { return cache }
        var values: [String: String] = [:]
        if !inMemory {
            if let data = read(account) {
                values = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
            } else {
                for name in oldItems { if let data = read(name) { values[name] = String(decoding: data, as: UTF8.self) } }
                save(values)
                // Silent and best effort: an old item this build isn't allowed to touch stays where it is.
                SecKeychainSetUserInteractionAllowed(false)
                for name in oldItems + ["google-tasks-access", "google-tasks-expiry"] { SecItemDelete(query(name) as CFDictionary) }
                SecKeychainSetUserInteractionAllowed(true)
            }
        }
        cache = values
        return values
    }

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    private static func read(_ account: String) -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    /// Kept even when empty, so the move from the old items happens only once.
    private static func save(_ values: [String: String]) {
        SecItemDelete(query(account) as CFDictionary)
        guard let data = try? JSONEncoder().encode(values) else { return }
        var add = query(account)
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "Saku"
        SecItemAdd(add as CFDictionary, nil)
    }
}
