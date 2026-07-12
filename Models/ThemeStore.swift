//
//  ThemeStore.swift
//  TeleDeck
//
//  アプリ全体のカラースキーム（ダーク/ライト/システム準拠）とアクセントカラーを管理し、
//  UserDefaultsへ即座に永続化するストア。
//

import Observation
import SwiftUI

/// アプリの外観モード。systemの場合はOS設定（ダーク/ライトモード）にそのまま従う
enum AppColorScheme: String, Codable, CaseIterable, Identifiable {
  case system
  case light
  case dark

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .system: return "システム準拠"
    case .light: return "ライト"
    case .dark: return "ダーク"
    }
  }
}

/// アクセントカラーの選択肢
enum AccentColorOption: String, Codable, CaseIterable, Identifiable {
  case blue
  case purple
  case green
  case orange
  case pink

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .blue: return "ブルー"
    case .purple: return "パープル"
    case .green: return "グリーン"
    case .orange: return "オレンジ"
    case .pink: return "ピンク"
    }
  }

  var color: Color {
    switch self {
    case .blue: return .blue
    case .purple: return Color(hex: 0x7C3AED)
    case .green: return .green
    case .orange: return .orange
    case .pink: return .pink
    }
  }
}

@Observable
final class ThemeStore {
  private enum StorageKey {
    static let colorScheme = "themeStore.colorScheme"
    static let accentColorOption = "themeStore.accentColorOption"
  }

  var colorScheme: AppColorScheme {
    didSet { persistColorScheme() }
  }

  var accentColorOption: AccentColorOption {
    didSet { persistAccentColorOption() }
  }

  private let userDefaults: UserDefaults

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults

    if let storedColorSchemeRawValue = userDefaults.string(forKey: StorageKey.colorScheme),
      let storedColorScheme = AppColorScheme(rawValue: storedColorSchemeRawValue) {
      colorScheme = storedColorScheme
    } else {
      // 紫ベースのゲーミングテーマを活かすため既定値はダーク
      colorScheme = .dark
    }

    if let storedAccentRawValue = userDefaults.string(forKey: StorageKey.accentColorOption),
      let storedAccent = AccentColorOption(rawValue: storedAccentRawValue) {
      accentColorOption = storedAccent
    } else {
      accentColorOption = .purple
    }
  }

  // MARK: - Viewから使いやすい形の派生プロパティ

  /// `.preferredColorScheme()`にそのまま渡せる値。systemの場合はnilを返しOS設定に委ねる
  var preferredColorScheme: ColorScheme? {
    switch colorScheme {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
  }

  /// `.tint()`にそのまま渡せるアクセントカラー
  var accentColor: Color {
    accentColorOption.color
  }

  // MARK: - 永続化

  private func persistColorScheme() {
    userDefaults.set(colorScheme.rawValue, forKey: StorageKey.colorScheme)
  }

  private func persistAccentColorOption() {
    userDefaults.set(accentColorOption.rawValue, forKey: StorageKey.accentColorOption)
  }
}
