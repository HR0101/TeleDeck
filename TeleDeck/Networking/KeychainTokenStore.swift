//
//  KeychainTokenStore.swift
//  TeleDeck
//
//  セッショントークン（認証情報）をKeychainへ安全に保存・取得するための最小限のラッパー。
//

import Foundation
import Security

enum KeychainTokenStore {
  private static let service = "com.HR.TeleDeck.sessionToken"

  static func save(_ token: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service
    ]
    SecItemDelete(query as CFDictionary)

    var addQuery = query
    addQuery[kSecValueData as String] = Data(token.utf8)
    let status = SecItemAdd(addQuery as CFDictionary, nil)
    if status != errSecSuccess {
      print("セッショントークンのKeychain保存に失敗しました: \(status)")
    }
  }

  static func load() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func delete() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service
    ]
    SecItemDelete(query as CFDictionary)
  }
}
