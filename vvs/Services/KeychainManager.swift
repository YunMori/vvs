import Foundation
import Security

/// Keychain을 통해 Claude API 키를 안전하게 저장/로드/삭제한다.
final class KeychainManager: Sendable {

    static let shared = KeychainManager()

    private let serviceName = "com.codesolve.claudeapi"
    private let accountName = "claude-api-key"

    private init() {}

    // MARK: - 저장

    /// API 키를 Keychain에 저장한다. 이미 존재하면 업데이트한다.
    /// - Parameter apiKey: 저장할 Claude API 키
    func saveAPIKey(_ apiKey: String) throws {
        guard let data = apiKey.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // 기존 항목 삭제 후 새로 추가 (upsert 패턴)
        deleteAPIKey()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    // MARK: - 로드

    /// Keychain에서 API 키를 로드한다.
    /// - Returns: 저장된 API 키. 없으면 nil.
    func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    // MARK: - 삭제

    /// Keychain에서 API 키를 삭제한다.
    @discardableResult
    func deleteAPIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - 확인

    /// API 키가 Keychain에 저장되어 있는지 확인한다.
    var hasAPIKey: Bool {
        loadAPIKey() != nil
    }
}

// MARK: - Errors

enum KeychainError: LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "API 키 인코딩에 실패했습니다."
        case .saveFailed(let status):
            return "Keychain 저장 실패 (OSStatus: \(status))"
        case .loadFailed(let status):
            return "Keychain 로드 실패 (OSStatus: \(status))"
        }
    }
}
