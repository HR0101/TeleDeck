//
//  MainTab.swift
//  TeleDeck
//
//  下部タブバーに表示する画面の種類。表示順序はThemeStore.tabOrderとして
//  設定画面から並び替えられるため、MainTabView専用の内部定義ではなく共有モデルとして切り出している。
//

import Foundation

enum MainTab: String, CaseIterable, Codable, Identifiable {
  case panel
  case clock
  case tabs
  case keyboard
  case clipboard

  var id: String { rawValue }

  var title: String {
    switch self {
    case .panel: return "パネル"
    case .clock: return "時計"
    case .tabs: return "アプリ"
    case .keyboard: return "キーボード"
    case .clipboard: return "クリップボード"
    }
  }

  var systemImage: String {
    switch self {
    case .panel: return "square.grid.3x3.fill"
    case .clock: return "clock"
    case .tabs: return "macwindow"
    case .keyboard: return "keyboard"
    case .clipboard: return "doc.on.clipboard"
    }
  }
}
