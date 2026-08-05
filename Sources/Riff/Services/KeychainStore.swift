import Foundation
import LocalAuthentication
import Security

enum KeychainStore {
    static let serviceName = "Riff"

    static func set(_ value: String, account: String) {
        let data = Data(value.utf8)
        var match = baseQuery(service: serviceName, account: account)
        match[kSecUseAuthenticationContext as String] = nonInteractiveContext()

        if value.isEmpty {
            let status = SecItemDelete(match as CFDictionary)
            DiagnosticLogger.shared.log("keychain", "delete account=\(account) status=\(status)")
            return
        }

        let updateStatus = SecItemUpdate(
            match as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            DiagnosticLogger.shared.log("keychain", "update account=\(account) status=\(updateStatus)")
            return
        }

        guard updateStatus == errSecItemNotFound else {
            DiagnosticLogger.shared.log("keychain", "update blocked account=\(account) status=\(updateStatus)")
            return
        }

        var add = baseQuery(service: serviceName, account: account)
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "Riff \(account) API Key"
        add[kSecAttrDescription as String] = "Riff AI Provider API Key"
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        DiagnosticLogger.shared.log("keychain", "add account=\(account) status=\(addStatus)")
    }

    static func get(account: String) -> String {
        let current = read(service: serviceName, account: account)
        if current.status == errSecSuccess {
            return current.value
        }
        DiagnosticLogger.shared.log(
            "keychain",
            "read unavailable account=\(account) status=\(current.status)"
        )
        return ""
    }

    private static func read(service: String, account: String) -> (status: OSStatus, value: String) {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = nonInteractiveContext()
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return (status, "")
        }
        return (status, String(data: data, encoding: .utf8) ?? "")
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func nonInteractiveContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }
}
