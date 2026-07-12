//
//  KeyboardView.swift
//  TeleDeck
//
//  US ANSI配列を模した仮想キーボード画面。既存のhotkeyアクション（ActionExecutor.sendHotkey）を
//  そのまま利用し、修飾キー（Shift/Ctrl/Opt/Cmd）はタップでON/OFFする一時的なトグルキーとして扱う。
//

import SwiftUI

/// 修飾キーの種類
private enum ModifierKey: String, CaseIterable {
  case shift
  case ctrl
  case opt
  case cmd

  var label: String {
    switch self {
    case .shift: return "shift"
    case .ctrl: return "ctrl"
    case .opt: return "opt"
    case .cmd: return "cmd"
    }
  }
}

/// キーボード上の1キー分の定義
private struct KeyDefinition: Identifiable {
  let id = UUID()
  let label: String
  /// ActionExecutor.keyCodesに対応するキー名
  let keyName: String
  /// 通常キーに対する相対幅（1が標準キー1つ分）
  var widthWeight: CGFloat = 1
}

struct KeyboardView: View {
  let connectionManager: ConnectionManager

  @Environment(ThemeStore.self) private var themeStore

  /// 現在ONになっている修飾キー（キー送信時にまとめて使い、送信後は自動でOFFに戻す）
  @State private var activeModifiers: Set<ModifierKey> = []

  var body: some View {
    VStack(spacing: 12) {
      Text("キーボード（US配列）")
        .font(.headline)
        .foregroundStyle(GamingPalette.foreground)
        .padding(.top)

      VStack(spacing: 6) {
        keyRow(Self.numberRow)
        keyRow(Self.qwertyRow)
        keyRow(Self.homeRow)
        bottomLetterRow
        modifierRow
      }
      .padding()

      Spacer()
    }
  }

  // MARK: - 行のレイアウト

  @ViewBuilder
  private func keyRow(_ keys: [KeyDefinition]) -> some View {
    HStack(spacing: 6) {
      ForEach(keys) { key in
        keyButton(key)
      }
    }
  }

  private var bottomLetterRow: some View {
    HStack(spacing: 6) {
      modifierButton(.shift, widthWeight: 2.2)
      ForEach(Self.bottomLetterKeys) { key in
        keyButton(key)
      }
      modifierButton(.shift, widthWeight: 2.2)
    }
  }

  private var modifierRow: some View {
    HStack(spacing: 6) {
      modifierButton(.ctrl)
      modifierButton(.opt)
      modifierButton(.cmd)

      keyButton(KeyDefinition(label: "space", keyName: "space", widthWeight: 5))

      modifierButton(.cmd)
      modifierButton(.opt)

      keyButton(KeyDefinition(label: "←", keyName: "left"))
      keyButton(KeyDefinition(label: "↑", keyName: "up"))
      keyButton(KeyDefinition(label: "↓", keyName: "down"))
      keyButton(KeyDefinition(label: "→", keyName: "right"))
    }
  }

  // MARK: - ボタン

  private func keyButton(_ key: KeyDefinition) -> some View {
    Button {
      sendKey(key.keyName)
    } label: {
      Text(key.label)
        .font(.system(size: 15))
        .foregroundStyle(GamingPalette.foreground)
        .frame(maxWidth: .infinity, minHeight: 40)
    }
    .buttonStyle(GamingKeyButtonStyle(accentColor: themeStore.accentColor, isActive: false))
    .frame(maxWidth: .infinity)
    .layoutPriority(key.widthWeight)
    .frame(minWidth: 32 * key.widthWeight)
  }

  private func modifierButton(_ modifier: ModifierKey, widthWeight: CGFloat = 1.5) -> some View {
    let isActive = activeModifiers.contains(modifier)
    return Button {
      toggleModifier(modifier)
    } label: {
      Text(modifier.label)
        .font(.system(size: 15))
        .foregroundStyle(isActive ? Color.white : GamingPalette.foreground)
        .frame(maxWidth: .infinity, minHeight: 40)
    }
    .buttonStyle(GamingKeyButtonStyle(accentColor: themeStore.accentColor, isActive: isActive))
    .frame(maxWidth: .infinity)
    .layoutPriority(widthWeight)
    .frame(minWidth: 32 * widthWeight)
  }

  // MARK: - キー送信

  private func toggleModifier(_ modifier: ModifierKey) {
    if activeModifiers.contains(modifier) {
      activeModifiers.remove(modifier)
    } else {
      activeModifiers.insert(modifier)
    }
  }

  /// Caps Lockはトグル状態自体をmacOS側が保持するため、単独キーとして送信する
  private func sendKey(_ keyName: String) {
    var keys = activeModifiers.map(\.label)
    keys.append(keyName)
    connectionManager.execute(ActionPayload(type: .hotkey, keys: keys))

    // iOS標準キーボードのShiftキーと同様、送信後は修飾キーを自動でOFFに戻す
    activeModifiers.removeAll()
  }

  // MARK: - US ANSI配列のキー定義

  private static let numberRow: [KeyDefinition] = [
    KeyDefinition(label: "`", keyName: "`"),
    KeyDefinition(label: "1", keyName: "1"), KeyDefinition(label: "2", keyName: "2"),
    KeyDefinition(label: "3", keyName: "3"), KeyDefinition(label: "4", keyName: "4"),
    KeyDefinition(label: "5", keyName: "5"), KeyDefinition(label: "6", keyName: "6"),
    KeyDefinition(label: "7", keyName: "7"), KeyDefinition(label: "8", keyName: "8"),
    KeyDefinition(label: "9", keyName: "9"), KeyDefinition(label: "0", keyName: "0"),
    KeyDefinition(label: "-", keyName: "-"), KeyDefinition(label: "=", keyName: "="),
    KeyDefinition(label: "delete", keyName: "delete", widthWeight: 2)
  ]

  private static let qwertyRow: [KeyDefinition] = [
    KeyDefinition(label: "tab", keyName: "tab", widthWeight: 1.5),
    KeyDefinition(label: "Q", keyName: "q"), KeyDefinition(label: "W", keyName: "w"),
    KeyDefinition(label: "E", keyName: "e"), KeyDefinition(label: "R", keyName: "r"),
    KeyDefinition(label: "T", keyName: "t"), KeyDefinition(label: "Y", keyName: "y"),
    KeyDefinition(label: "U", keyName: "u"), KeyDefinition(label: "I", keyName: "i"),
    KeyDefinition(label: "O", keyName: "o"), KeyDefinition(label: "P", keyName: "p"),
    KeyDefinition(label: "[", keyName: "["), KeyDefinition(label: "]", keyName: "]"),
    KeyDefinition(label: "\\", keyName: "\\", widthWeight: 1.5)
  ]

  private static let homeRow: [KeyDefinition] = [
    KeyDefinition(label: "caps", keyName: "capslock", widthWeight: 1.8),
    KeyDefinition(label: "A", keyName: "a"), KeyDefinition(label: "S", keyName: "s"),
    KeyDefinition(label: "D", keyName: "d"), KeyDefinition(label: "F", keyName: "f"),
    KeyDefinition(label: "G", keyName: "g"), KeyDefinition(label: "H", keyName: "h"),
    KeyDefinition(label: "J", keyName: "j"), KeyDefinition(label: "K", keyName: "k"),
    KeyDefinition(label: "L", keyName: "l"), KeyDefinition(label: ";", keyName: ";"),
    KeyDefinition(label: "'", keyName: "'"),
    KeyDefinition(label: "return", keyName: "return", widthWeight: 1.8)
  ]

  private static let bottomLetterKeys: [KeyDefinition] = [
    KeyDefinition(label: "Z", keyName: "z"), KeyDefinition(label: "X", keyName: "x"),
    KeyDefinition(label: "C", keyName: "c"), KeyDefinition(label: "V", keyName: "v"),
    KeyDefinition(label: "B", keyName: "b"), KeyDefinition(label: "N", keyName: "n"),
    KeyDefinition(label: "M", keyName: "m"), KeyDefinition(label: ",", keyName: ","),
    KeyDefinition(label: ".", keyName: "."), KeyDefinition(label: "/", keyName: "/")
  ]
}

/// ゲーミングキーボード風のキー用ButtonStyle。
/// 通常キーはGamingPalette.mutedの背景と薄いボーダー、修飾キーがONの時はアクセントカラーで強く光らせる
private struct GamingKeyButtonStyle: ButtonStyle {
  var accentColor: Color
  var isActive: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(
            isActive
              ? accentColor.opacity(configuration.isPressed ? 0.95 : 0.8)
              : GamingPalette.muted.opacity(configuration.isPressed ? 0.9 : 0.7)
          )
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(
            isActive ? accentColor.opacity(0.95) : GamingPalette.mutedForeground.opacity(0.25),
            lineWidth: isActive ? 1.5 : 1
          )
      )
      .shadow(color: accentColor.opacity(isActive ? 0.6 : 0), radius: isActive ? 10 : 0)
      .scaleEffect(configuration.isPressed ? 0.95 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

#Preview {
  KeyboardView(connectionManager: ConnectionManager())
    .environment(ThemeStore())
}
