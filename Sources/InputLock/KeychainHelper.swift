import Foundation
import Security

/// Keychain 读写工具，用于安全持久化激活序列号
enum KeychainHelper {

    // MARK: - 公共接口

    /// 将字符串写入 Keychain
    /// - Parameters:
    ///   - value: 要存储的字符串值
    ///   - key: Keychain 条目的唯一标识符
    /// - Returns: 操作是否成功
    @discardableResult
    static func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // 先删除旧条目，再写入新条目
        delete(forKey: key)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// 从 Keychain 读取字符串
    /// - Parameter key: Keychain 条目的唯一标识符
    /// - Returns: 存储的字符串，若不存在则返回 nil
    static func load(forKey key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    /// 删除 Keychain 中的条目
    /// - Parameter key: 要删除的条目标识符
    @discardableResult
    static func delete(forKey key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
