//
//  ThemeStore.swift
//  TeleDeck
//
//  アプリ全体のカラースキーム（ダーク/ライト/システム準拠）とアクセントカラーを管理し、
//  UserDefaultsへ即座に永続化するストア。
//

import Foundation
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
    static let backgroundGlowEnabled = "themeStore.backgroundGlowEnabled"
    static let appIconGridColumns = "themeStore.appIconGridColumns"
    static let tabOrder = "themeStore.tabOrder"
    static let keepsScreenAwake = "themeStore.keepsScreenAwake"
    static let followsSystemLowPowerMode = "themeStore.followsSystemLowPowerMode"
  }

  /// 「アプリ」タブのアイコングリッドの列数として選べる範囲。列数を減らすほどアイコンが大きく表示される
  static let appIconGridColumnsRange = 2...8

  var colorScheme: AppColorScheme {
    didSet { persistColorScheme() }
  }

  var accentColorOption: AccentColorOption {
    didSet { persistAccentColorOption() }
  }

  /// 大きなぼかし円を動かす背景エフェクト。電池消費を抑えるため既定値はOFF。
  var backgroundGlowEnabled: Bool {
    didSet { persistBackgroundGlowEnabled() }
  }

  var appIconGridColumns: Int {
    didSet { persistAppIconGridColumns() }
  }

  /// 下部タブバーの表示順序。設定画面からドラッグで並び替えられる
  var tabOrder: [MainTab] {
    didSet { persistTabOrder() }
  }

  /// 卓上のデッキとして使う間に画面が消灯しないようにする。
  /// 電池消費を抑えるため既定値はOFF。卓上で常時表示したい場合だけ設定から有効にする。
  var keepsScreenAwake: Bool {
    didSet { persistKeepsScreenAwake() }
  }

  /// iPadの低電力モードに合わせて、描画と通信を省電力構成へ切り替える。
  /// ユーザーが意識せず使ってもOSの意図を尊重できるよう、既定値はON。
  var followsSystemLowPowerMode: Bool {
    didSet { persistFollowsSystemLowPowerMode() }
  }

  /// ProcessInfoの通知から更新される、現在のiPad側の低電力モード状態。
  private(set) var isSystemLowPowerModeEnabled: Bool

  private let userDefaults: UserDefaults

  init(
    userDefaults: UserDefaults = .standard,
    isSystemLowPowerModeEnabled: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
  ) {
    self.userDefaults = userDefaults
    self.isSystemLowPowerModeEnabled = isSystemLowPowerModeEnabled

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

    // 既存ユーザーも初回は省電力の静的背景になるよう、未保存時はOFFにする。
    backgroundGlowEnabled = userDefaults.object(forKey: StorageKey.backgroundGlowEnabled) == nil
      ? false
      : userDefaults.bool(forKey: StorageKey.backgroundGlowEnabled)

    let storedColumns = userDefaults.integer(forKey: StorageKey.appIconGridColumns)
    appIconGridColumns = storedColumns == 0 ? 4 : storedColumns

    // 初回起動時はiPadの自動ロックを尊重し、意図せず画面を点灯し続けないようOFFにする
    keepsScreenAwake = userDefaults.object(forKey: StorageKey.keepsScreenAwake) == nil
      ? false
      : userDefaults.bool(forKey: StorageKey.keepsScreenAwake)

    followsSystemLowPowerMode = userDefaults.object(forKey: StorageKey.followsSystemLowPowerMode) == nil
      ? true
      : userDefaults.bool(forKey: StorageKey.followsSystemLowPowerMode)

    if let storedTabOrderRawValues = userDefaults.array(forKey: StorageKey.tabOrder) as? [String] {
      let storedTabs = storedTabOrderRawValues.compactMap { MainTab(rawValue: $0) }
      // 保存後にアプリの更新でタブが追加された場合に備え、保存済みの順序に無いタブは末尾へ補う
      let missingTabs = MainTab.allCases.filter { !storedTabs.contains($0) }
      tabOrder = storedTabs + missingTabs
    } else {
      tabOrder = MainTab.allCases
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

  /// アプリ側で省電力構成を適用すべきかどうか。
  var isEnergySavingModeEnabled: Bool {
    followsSystemLowPowerMode && isSystemLowPowerModeEnabled
  }

  /// ユーザーがグローを有効にしていても、省電力中は大きなぼかし描画を強制停止する。
  var shouldShowBackgroundGlow: Bool {
    backgroundGlowEnabled && !isEnergySavingModeEnabled
  }

  func setSystemLowPowerModeEnabled(_ isEnabled: Bool) {
    isSystemLowPowerModeEnabled = isEnabled
  }

  // MARK: - 永続化

  private func persistColorScheme() {
    userDefaults.set(colorScheme.rawValue, forKey: StorageKey.colorScheme)
  }

  private func persistAccentColorOption() {
    userDefaults.set(accentColorOption.rawValue, forKey: StorageKey.accentColorOption)
  }

  private func persistBackgroundGlowEnabled() {
    userDefaults.set(backgroundGlowEnabled, forKey: StorageKey.backgroundGlowEnabled)
  }

  private func persistAppIconGridColumns() {
    userDefaults.set(appIconGridColumns, forKey: StorageKey.appIconGridColumns)
  }

  private func persistTabOrder() {
    userDefaults.set(tabOrder.map(\.rawValue), forKey: StorageKey.tabOrder)
  }

  private func persistKeepsScreenAwake() {
    userDefaults.set(keepsScreenAwake, forKey: StorageKey.keepsScreenAwake)
  }

  private func persistFollowsSystemLowPowerMode() {
    userDefaults.set(followsSystemLowPowerMode, forKey: StorageKey.followsSystemLowPowerMode)
  }
}
