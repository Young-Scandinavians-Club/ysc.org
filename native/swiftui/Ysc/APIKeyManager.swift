//
//  APIKeyManager.swift
//  Ysc
//
//  Manages API key storage and retrieval using iOS Keychain
//

import Foundation
import Security

class APIKeyManager {
    private static let service = Bundle.main.bundleIdentifier ?? "com.ysc.app"
    private static let account = "native_api_key"

    /// Store API key in Keychain
    /// - Parameter key: The API key to store
    /// - Returns: true if successful, false otherwise
    static func storeAPIKey(_ key: String) -> Bool {
        // Delete any existing key first
        deleteAPIKey()

        guard let data = key.data(using: .utf8) else {
            return false
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecSuccess {
            return true
        } else {
            print("Error storing API key: \(status)")
            return false
        }
    }

    /// Retrieve API key from Keychain
    /// - Returns: The API key if found, nil otherwise
    static func getAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess {
            if let data = result as? Data,
                let key = String(data: data, encoding: .utf8)
            {
                return key
            }
        }

        return nil
    }

    /// Check if API key exists in Keychain
    /// - Returns: true if key exists, false otherwise
    static func hasAPIKey() -> Bool {
        return getAPIKey() != nil
    }

    /// Delete API key from Keychain
    /// - Returns: true if successful, false otherwise
    static func deleteAPIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)

        return status == errSecSuccess || status == errSecItemNotFound
    }
}
