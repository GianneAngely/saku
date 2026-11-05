import Foundation
import Security

/// API keys Angel types in herself, kept in the login keychain (never in plain settings).
/// QA runs use memory only, so tests never touch the keychain.
@MainActor
enum Secrets {
    static var inMemory = false
    private static var memory: [String: String] = [:]
    private static let service = "local.saku.app"

    static func get(_ name: String) -> String {
        if inMemory { return memory[name] ?? "" }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: name, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return "" }
        return String(decoding: d, as: UTF8.self)
    }

    static func set(_ name: String, _ value: String) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if inMemory { memory[name] = v.isEmpty ? nil : v; return }
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: name]
        SecItemDelete(base as CFDictionary)
        guard !v.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(v.utf8)
        add[kSecAttrLabel as String] = "Saku: \(name)"
        SecItemAdd(add as CFDictionary, nil)
    }

    static func has(_ name: String) -> Bool { !get(name).isEmpty }
}
