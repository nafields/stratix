// TokenStore.swift
// Defines the Keychain-backed token store used for Microsoft and Xbox auth state.
//

import Foundation
import Security

// MARK: - Token Store (Keychain-backed)

/// Stores and retrieves auth and stream tokens from the platform Keychain.
public actor TokenStore {
    private static let allKeys = [
        Keys.msaToken,
        Keys.refreshToken,
        Keys.lptToken,
        Keys.lptExpiry,
        Keys.xhomeToken,
        Keys.xhomeHost,
        Keys.xcloudToken,
        Keys.xcloudHost,
        Keys.xcloudF2PToken,
        Keys.xcloudF2PHost,
        Keys.webToken,
        Keys.webTokenUHS
    ]

    private static let legacyKeys = [
        LegacyKeys.msaToken,
        LegacyKeys.refreshToken,
        LegacyKeys.lptToken,
        LegacyKeys.lptExpiry,
        LegacyKeys.xhomeToken,
        LegacyKeys.xhomeHost,
        LegacyKeys.xcloudToken,
        LegacyKeys.xcloudHost,
        LegacyKeys.xcloudF2PToken,
        LegacyKeys.xcloudF2PHost,
        LegacyKeys.webToken,
        LegacyKeys.webTokenUHS
    ]

    private enum Keys {
        static let msaToken = "stratix.msa_token"
        static let refreshToken = "stratix.refresh_token"
        static let lptToken = "stratix.lpt_token"
        static let lptExpiry = "stratix.lpt_expiry"
        static let xhomeToken = "stratix.xhome_token"
        static let xhomeHost = "stratix.xhome_host"
        static let xcloudToken = "stratix.xcloud_token"
        static let xcloudHost = "stratix.xcloud_host"
        static let xcloudF2PToken = "stratix.xcloud_f2p_token"
        static let xcloudF2PHost = "stratix.xcloud_f2p_host"
        static let webToken = "stratix.web_token"
        static let webTokenUHS = "stratix.web_token_uhs"
    }

    // Legacy Keychain keys from the project's pre-open-source development phase.
    // TokenStore reads from these keys and migrates values to the stratix.* namespace
    // on first access, so existing local installs retain their auth state across updates.
    private enum LegacyKeys {
        static let msaToken = "greenlight.msa_token"
        static let refreshToken = "greenlight.refresh_token"
        static let lptToken = "greenlight.lpt_token"
        static let lptExpiry = "greenlight.lpt_expiry"
        static let xhomeToken = "greenlight.xhome_token"
        static let xhomeHost = "greenlight.xhome_host"
        static let xcloudToken = "greenlight.xcloud_token"
        static let xcloudHost = "greenlight.xcloud_host"
        static let xcloudF2PToken = "greenlight.xcloud_f2p_token"
        static let xcloudF2PHost = "greenlight.xcloud_f2p_host"
        static let webToken = "greenlight.web_token"
        static let webTokenUHS = "greenlight.web_token_uhs"
    }

    /// Creates an empty token store wrapper over the shared Keychain services APIs.
    public init() {}

    // MARK: - MSA

    /// Persists the current Microsoft access token.
    public func saveMSAToken(_ token: String) throws {
        try saveMigratedValue(token, key: Keys.msaToken, legacyKey: LegacyKeys.msaToken)
    }

    /// Loads the persisted Microsoft access token when one is available.
    public func loadMSAToken() -> String? {
        loadMigratedValue(key: Keys.msaToken, legacyKey: LegacyKeys.msaToken)
    }

    /// Persists the current Microsoft refresh token.
    public func saveRefreshToken(_ token: String) throws {
        try saveMigratedValue(token, key: Keys.refreshToken, legacyKey: LegacyKeys.refreshToken)
    }

    /// Loads the persisted Microsoft refresh token when one is available.
    public func loadRefreshToken() -> String? {
        loadMigratedValue(key: Keys.refreshToken, legacyKey: LegacyKeys.refreshToken)
    }

    /// Persists the current long-lived token together with its optional expiry timestamp.
    public func saveLPTToken(_ token: String, expiresAt: Date?) throws {
        try saveMigratedValue(token, key: Keys.lptToken, legacyKey: LegacyKeys.lptToken)
        if let expiresAt {
            try saveMigratedValue(
                String(expiresAt.timeIntervalSince1970),
                key: Keys.lptExpiry,
                legacyKey: LegacyKeys.lptExpiry
            )
        } else {
            delete(key: Keys.lptExpiry)
            delete(key: LegacyKeys.lptExpiry)
        }
    }

    /// Loads the persisted long-lived token when one is available.
    public func loadLPTToken() -> String? {
        loadMigratedValue(key: Keys.lptToken, legacyKey: LegacyKeys.lptToken)
    }

    /// Loads the expiry associated with the persisted long-lived token.
    public func loadLPTTokenExpiry() -> Date? {
        guard let raw = loadMigratedValue(key: Keys.lptExpiry, legacyKey: LegacyKeys.lptExpiry),
              let seconds = TimeInterval(raw) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Removes the long-lived token and its expiry metadata.
    public func clearLPTToken() {
        delete(key: Keys.lptToken)
        delete(key: Keys.lptExpiry)
        delete(key: LegacyKeys.lptToken)
        delete(key: LegacyKeys.lptExpiry)
    }

    // MARK: - Stream Tokens

    /// Persists the current xHome, xCloud, and web token bundle.
    public func saveStreamTokens(_ tokens: StreamTokens) throws {
        try saveMigratedValue(tokens.xhomeToken, key: Keys.xhomeToken, legacyKey: LegacyKeys.xhomeToken)
        try saveMigratedValue(tokens.xhomeHost, key: Keys.xhomeHost, legacyKey: LegacyKeys.xhomeHost)
        try saveOptionalMigratedValue(tokens.xcloudToken, key: Keys.xcloudToken, legacyKey: LegacyKeys.xcloudToken)
        try saveOptionalMigratedValue(tokens.xcloudHost, key: Keys.xcloudHost, legacyKey: LegacyKeys.xcloudHost)
        try saveOptionalMigratedValue(
            tokens.xcloudF2PToken,
            key: Keys.xcloudF2PToken,
            legacyKey: LegacyKeys.xcloudF2PToken
        )
        try saveOptionalMigratedValue(
            tokens.xcloudF2PHost,
            key: Keys.xcloudF2PHost,
            legacyKey: LegacyKeys.xcloudF2PHost
        )
        try saveOptionalMigratedValue(tokens.webToken, key: Keys.webToken, legacyKey: LegacyKeys.webToken)
        try saveOptionalMigratedValue(tokens.webTokenUHS, key: Keys.webTokenUHS, legacyKey: LegacyKeys.webTokenUHS)
    }

    /// Loads the current stream-token bundle when the required xHome fields exist.
    public func loadStreamTokens() -> StreamTokens? {
        guard
            let xhomeToken = loadMigratedValue(key: Keys.xhomeToken, legacyKey: LegacyKeys.xhomeToken),
            let xhomeHost = loadMigratedValue(key: Keys.xhomeHost, legacyKey: LegacyKeys.xhomeHost)
        else { return nil }
        return StreamTokens(
            xhomeToken: xhomeToken,
            xhomeHost: xhomeHost,
            xcloudToken: loadMigratedValue(key: Keys.xcloudToken, legacyKey: LegacyKeys.xcloudToken),
            xcloudHost: loadMigratedValue(key: Keys.xcloudHost, legacyKey: LegacyKeys.xcloudHost),
            xcloudF2PToken: loadMigratedValue(key: Keys.xcloudF2PToken, legacyKey: LegacyKeys.xcloudF2PToken),
            xcloudF2PHost: loadMigratedValue(key: Keys.xcloudF2PHost, legacyKey: LegacyKeys.xcloudF2PHost),
            webToken: loadMigratedValue(key: Keys.webToken, legacyKey: LegacyKeys.webToken),
            webTokenUHS: loadMigratedValue(key: Keys.webTokenUHS, legacyKey: LegacyKeys.webTokenUHS)
        )
    }

    // MARK: - Clear

    /// Removes all persisted auth and stream tokens from the Keychain.
    public func clearAll() throws {
        for key in Self.allKeys {
            delete(key: key)
        }
        for key in Self.legacyKeys {
            delete(key: key)
        }
    }

    // MARK: - Low-level Keychain

    private func saveMigratedValue(_ value: String, key: String, legacyKey: String) throws {
        try save(key: key, value: value)
        delete(key: legacyKey)
    }

    private func saveOptionalMigratedValue(_ value: String?, key: String, legacyKey: String) throws {
        guard let value else {
            delete(key: key)
            delete(key: legacyKey)
            return
        }
        try saveMigratedValue(value, key: key, legacyKey: legacyKey)
    }

    private func loadMigratedValue(key: String, legacyKey: String) -> String? {
        if let currentValue = load(key: key) {
            return currentValue
        }
        guard let legacyValue = load(key: legacyKey) else { return nil }
        try? save(key: key, value: legacyValue)
        delete(key: legacyKey)
        return legacyValue
    }

    private func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }

        delete(key: key)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            throw AuthError.networkError("Keychain save failed: \(status)")
        }
    }

    private func load(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
