import Foundation
import Security

/// Small Keychain wrapper used for CLAW credentials.
///
/// Host app and keyboard extension keep independent device-bound copies.
/// AIService coordinates migration between them through the shared App Group.
public final class ClawSecureStore {
  public static let shared = ClawSecureStore()

  private let service = "app.lgm.7517.claw.secure"

  private init() {}

  public func string(for account: String) throws -> String? {
    var query = baseQuery(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw SecureStoreError.status(status) }
    guard let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  public func setString(_ value: String, for account: String) throws {
    guard let data = value.data(using: .utf8) else { throw SecureStoreError.encoding }
    let query = baseQuery(account: account)
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else { throw SecureStoreError.status(updateStatus) }

    var add = query
    add.merge(attributes) { _, new in new }
    let addStatus = SecItemAdd(add as CFDictionary, nil)
    guard addStatus == errSecSuccess else { throw SecureStoreError.status(addStatus) }
  }

  public func remove(_ account: String) throws {
    let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw SecureStoreError.status(status)
    }
  }

  private func baseQuery(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: false,
    ]
  }
}

public enum SecureStoreError: LocalizedError {
  case encoding
  case status(OSStatus)

  public var errorDescription: String? {
    switch self {
    case .encoding:
      return "无法编码安全数据"
    case .status(let status):
      return SecCopyErrorMessageString(status, nil) as String? ?? "Keychain 错误 \(status)"
    }
  }
}
