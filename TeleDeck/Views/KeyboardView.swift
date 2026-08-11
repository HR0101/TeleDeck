//
//  KeyboardView.swift
//  TeleDeck
//
//  US ANSI配列を模した仮想キーボード画面。既存のhotkeyアクション（ActionExecutor.sendHotkey）を
//  そのまま利用し、修飾キー（Shift/Ctrl/Opt/Cmd）はタップでON/OFFする一時的なトグルキーとして扱う。
//  キー配列の下にはトラックパッド（TrackpadSurfaceView）も統合しており、
//  画面の余白を使ってカーソル操作・クリックもこの1画面で完結できるようにしている。
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

/// キーボード上の1キー分の定義。ButtonEditView（ホットキー登録のキー選択グリッド）からも共用する
struct KeyDefinition: Identifiable {
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
  /// ダブルタップで固定した修飾キー。Cmdを押しっぱなしにするアプリスイッチャーのように、
  /// 1回のキー送信では解除したくない操作のために、通常のトグルとは別に保持する
  @State private var lockedModifiers: Set<ModifierKey> = []

  /// キーの文字サイズ。文字サイズ設定に追随させつつ、キー配列が崩れない範囲に収める
  @ScaledMetric(relativeTo: .body) private var keyFontSize: CGFloat = 15
  /// 英数/かなキーはラベルが2文字のため、通常キーよりわずかに小さくする
  @ScaledMetric(relativeTo: .body) private var inputSourceKeyFontSize: CGFloat = 13
  /// タップ領域がHIGの44pt未満にならないようにするキーの最低の高さ。
  /// 文字を大きくした場合はキーの高さも一緒に伸ばす
  @ScaledMetric(relativeTo: .body) private var minKeyHeight: CGFloat = 44

  var body: some View {
    VStack(spacing: 12) {
      header
        .padding(.top)

      VStack(spacing: 6) {
        keyRow(Self.numberRow)
        keyRow(Self.qwertyRow)
        keyRow(Self.homeRow)
        bottomLetterRow
        modifierRow
      }
      .padding()

      trackpadSection
        .frame(maxHeight: .infinity)
    }
  }

  // MARK: - ヘッダー

  private var header: some View {
    VStack(spacing: 6) {
      Text("キーボード＆トラックパッド（US配列）")
        .font(.headline)
        .foregroundStyle(GamingPalette.foreground)

      if connectionManager.isConnected {
        Text("修飾キーはタップで1回のみ有効・ダブルタップで固定されます")
          .font(.caption2)
          .foregroundStyle(GamingPalette.mutedForeground)
      } else {
        Label("Macに接続されていません", systemImage: "wifi.slash")
          .font(.caption.weight(.medium))
          .foregroundStyle(GamingPalette.destructive)
      }
    }
  }

  // MARK: - トラックパッド

  /// キー配列の下に配置する、TrackpadView由来のトラックパッド操作エリア。
  /// 画面上部をキーが占有するため、案内テキストはTrackpadView時代の複数行legendより
  /// 大幅に簡潔な一行のヒントに留めている
  private var trackpadSection: some View {
    VStack(spacing: 10) {
      RoundedRectangle(cornerRadius: 20)
        .fill(Color.clear)
        .gamingCard(accentColor: themeStore.accentColor, cornerRadius: 20)
        .overlay {
          Label("ドラッグでカーソル移動・タップでクリック", systemImage: "hand.point.up.left")
            .font(.caption2.weight(.medium))
            .foregroundStyle(GamingPalette.mutedForeground)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
        }
        .overlay {
          TrackpadSurfaceView(
            onMove: { dx, dy in
              connectionManager.sendTrackpadMove(dx: dx, dy: dy)
            },
            onScroll: { dx, dy in
              connectionManager.sendTrackpadScroll(dx: dx, dy: dy)
            },
            onLeftClick: {
              connectionManager.sendTrackpadClick(button: "left")
            },
            onRightClick: {
              connectionManager.sendTrackpadClick(button: "right")
            },
            onThreeFingerSwipeLeft: {
              // 3本指左スワイプ = 次のスペースへ（Control+右矢印と同等）
              connectionManager.execute(ActionPayload(type: .hotkey, keys: ["ctrl", "right"]))
            },
            onThreeFingerSwipeRight: {
              // 3本指右スワイプ = 前のスペースへ（Control+左矢印と同等）
              connectionManager.execute(ActionPayload(type: .hotkey, keys: ["ctrl", "left"]))
            },
            onThreeFingerSwipeUp: {
              // 3本指上スワイプ = Mission Control（Control+上矢印と同等）
              connectionManager.execute(ActionPayload(type: .hotkey, keys: ["ctrl", "up"]))
            },
            onThreeFingerSwipeDown: {
              // 3本指下スワイプ = Application Exposé（Control+下矢印と同等）
              connectionManager.execute(ActionPayload(type: .hotkey, keys: ["ctrl", "down"]))
            }
          )
        }
        .padding(.horizontal)

      HStack(spacing: 24) {
        Button("左クリック") {
          connectionManager.sendTrackpadClick(button: "left")
        }
        .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor))

        Button("右クリック") {
          connectionManager.sendTrackpadClick(button: "right")
        }
        .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor))
      }
      .padding(.bottom)
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

      // macOSのJISキーボードにある専用の英数/かなキーを送信する。
      // Commandキーの単独タップ設定には依存しない。
      inputSourceButton(label: "英数", keyName: "eisu")
      keyButton(KeyDefinition(label: "space", keyName: "space", widthWeight: 3.5))
      inputSourceButton(label: "かな", keyName: "kana")

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
        .font(.system(size: keyFontSize))
        .foregroundStyle(GamingPalette.foreground)
        .frame(maxWidth: .infinity, minHeight: minKeyHeight)
    }
    .buttonStyle(GamingKeyButtonStyle(accentColor: themeStore.accentColor, isActive: false))
    .frame(maxWidth: .infinity)
    .layoutPriority(key.widthWeight)
    .frame(minWidth: 32 * key.widthWeight)
  }

  private func modifierButton(_ modifier: ModifierKey, widthWeight: CGFloat = 1.5) -> some View {
    let isLocked = lockedModifiers.contains(modifier)
    let isActive = isLocked || activeModifiers.contains(modifier)

    return Button {
      toggleModifier(modifier)
    } label: {
      // 固定中は錠前を添えて、1回で解除される通常のONと区別できるようにする
      HStack(spacing: 3) {
        Text(modifier.label)
          .font(.system(size: keyFontSize))
        if isLocked {
          Image(systemName: "lock.fill")
            .font(.system(size: 9, weight: .bold))
        }
      }
      .foregroundStyle(isActive ? Color.white : GamingPalette.foreground)
      .frame(maxWidth: .infinity, minHeight: minKeyHeight)
    }
    .buttonStyle(GamingKeyButtonStyle(accentColor: themeStore.accentColor, isActive: isActive))
    // ダブルタップを先に判定させ、成立しなかった場合のみ通常のトグルとして扱う
    .simultaneousGesture(
      TapGesture(count: 2).onEnded {
        toggleModifierLock(modifier)
      }
    )
    .frame(maxWidth: .infinity)
    .layoutPriority(widthWeight)
    .frame(minWidth: 32 * widthWeight)
    .accessibilityValue(isLocked ? "固定中" : (isActive ? "オン" : "オフ"))
    .accessibilityHint("ダブルタップで固定します")
  }

  /// macOSの専用英数/かなキーを、トグル中の修飾キーとは独立して送信するボタン
  private func inputSourceButton(label: String, keyName: String, widthWeight: CGFloat = 1.3) -> some View {
    Button {
      sendInputSourceKey(keyName)
    } label: {
      Text(label)
        .font(.system(size: inputSourceKeyFontSize))
        .foregroundStyle(GamingPalette.foreground)
        .frame(maxWidth: .infinity, minHeight: minKeyHeight)
    }
    .buttonStyle(GamingKeyButtonStyle(accentColor: themeStore.accentColor, isActive: false))
    .frame(maxWidth: .infinity)
    .layoutPriority(widthWeight)
    .frame(minWidth: 32 * widthWeight)
  }

  // MARK: - キー送信

  /// 専用の英数/かなキーを送信する。トグル中の他の修飾キーとは合成しない独立した操作
  private func sendInputSourceKey(_ keyName: String) {
    connectionManager.execute(ActionPayload(type: .hotkey, keys: [keyName]))
  }

  private func toggleModifier(_ modifier: ModifierKey) {
    // 固定中のキーは、1回タップで固定を解除する（二段階でOFFにする手間を省く）
    if lockedModifiers.contains(modifier) {
      lockedModifiers.remove(modifier)
      activeModifiers.remove(modifier)
      return
    }

    if activeModifiers.contains(modifier) {
      activeModifiers.remove(modifier)
    } else {
      activeModifiers.insert(modifier)
    }
  }

  /// ダブルタップで修飾キーを固定する。固定中はキー送信後も解除されないため、
  /// Cmdを押しっぱなしにするアプリスイッチャーや、連続したショートカット操作が行える
  private func toggleModifierLock(_ modifier: ModifierKey) {
    if lockedModifiers.contains(modifier) {
      lockedModifiers.remove(modifier)
      activeModifiers.remove(modifier)
    } else {
      lockedModifiers.insert(modifier)
      activeModifiers.remove(modifier)
    }
  }

  /// Caps Lockはトグル状態自体をmacOS側が保持するため、単独キーとして送信する
  private func sendKey(_ keyName: String) {
    var keys = lockedModifiers.union(activeModifiers).map(\.label)
    keys.append(keyName)
    connectionManager.execute(ActionPayload(type: .hotkey, keys: keys))

    // iOS標準キーボードのShiftキーと同様、送信後は修飾キーを自動でOFFに戻す。
    // ただしダブルタップで固定したキーは、明示的に解除されるまで維持する
    activeModifiers.removeAll()
  }

  // MARK: - US ANSI配列のキー定義

  static let numberRow: [KeyDefinition] = [
    KeyDefinition(label: "`", keyName: "`"),
    KeyDefinition(label: "1", keyName: "1"), KeyDefinition(label: "2", keyName: "2"),
    KeyDefinition(label: "3", keyName: "3"), KeyDefinition(label: "4", keyName: "4"),
    KeyDefinition(label: "5", keyName: "5"), KeyDefinition(label: "6", keyName: "6"),
    KeyDefinition(label: "7", keyName: "7"), KeyDefinition(label: "8", keyName: "8"),
    KeyDefinition(label: "9", keyName: "9"), KeyDefinition(label: "0", keyName: "0"),
    KeyDefinition(label: "-", keyName: "-"), KeyDefinition(label: "=", keyName: "="),
    KeyDefinition(label: "delete", keyName: "delete", widthWeight: 2)
  ]

  static let qwertyRow: [KeyDefinition] = [
    KeyDefinition(label: "tab", keyName: "tab", widthWeight: 1.5),
    KeyDefinition(label: "Q", keyName: "q"), KeyDefinition(label: "W", keyName: "w"),
    KeyDefinition(label: "E", keyName: "e"), KeyDefinition(label: "R", keyName: "r"),
    KeyDefinition(label: "T", keyName: "t"), KeyDefinition(label: "Y", keyName: "y"),
    KeyDefinition(label: "U", keyName: "u"), KeyDefinition(label: "I", keyName: "i"),
    KeyDefinition(label: "O", keyName: "o"), KeyDefinition(label: "P", keyName: "p"),
    KeyDefinition(label: "[", keyName: "["), KeyDefinition(label: "]", keyName: "]"),
    KeyDefinition(label: "\\", keyName: "\\", widthWeight: 1.5)
  ]

  static let homeRow: [KeyDefinition] = [
    KeyDefinition(label: "caps", keyName: "capslock", widthWeight: 1.8),
    KeyDefinition(label: "A", keyName: "a"), KeyDefinition(label: "S", keyName: "s"),
    KeyDefinition(label: "D", keyName: "d"), KeyDefinition(label: "F", keyName: "f"),
    KeyDefinition(label: "G", keyName: "g"), KeyDefinition(label: "H", keyName: "h"),
    KeyDefinition(label: "J", keyName: "j"), KeyDefinition(label: "K", keyName: "k"),
    KeyDefinition(label: "L", keyName: "l"), KeyDefinition(label: ";", keyName: ";"),
    KeyDefinition(label: "'", keyName: "'"),
    KeyDefinition(label: "return", keyName: "return", widthWeight: 1.8)
  ]

  static let bottomLetterKeys: [KeyDefinition] = [
    KeyDefinition(label: "Z", keyName: "z"), KeyDefinition(label: "X", keyName: "x"),
    KeyDefinition(label: "C", keyName: "c"), KeyDefinition(label: "V", keyName: "v"),
    KeyDefinition(label: "B", keyName: "b"), KeyDefinition(label: "N", keyName: "n"),
    KeyDefinition(label: "M", keyName: "m"), KeyDefinition(label: ",", keyName: ","),
    KeyDefinition(label: ".", keyName: "."), KeyDefinition(label: "/", keyName: "/")
  ]

  /// numberRow/qwertyRow/homeRow/bottomLetterKeysに含まれない、ホットキー登録でよく使う特殊キー
  static let extraKeys: [KeyDefinition] = [
    KeyDefinition(label: "esc", keyName: "escape", widthWeight: 1.3),
    KeyDefinition(label: "space", keyName: "space", widthWeight: 2.4),
    KeyDefinition(label: "←", keyName: "left"),
    KeyDefinition(label: "↑", keyName: "up"),
    KeyDefinition(label: "↓", keyName: "down"),
    KeyDefinition(label: "→", keyName: "right")
  ]
}

/// ゲーミングキーボード風のキー用ButtonStyle。
/// 通常キーはGamingPalette.mutedの背景と薄いボーダー、修飾キーがONの時はアクセントカラーで強く光らせる
private struct GamingKeyButtonStyle: ButtonStyle {
  @Environment(ThemeStore.self) private var themeStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
      .shadow(
        color: themeStore.isEnergySavingModeEnabled ? .clear : accentColor.opacity(isActive ? 0.6 : 0),
        radius: themeStore.isEnergySavingModeEnabled ? 0 : (isActive ? 10 : 0)
      )
      .scaleEffect(configuration.isPressed ? 0.95 : 1)
      .animation(
        reduceMotion || themeStore.isEnergySavingModeEnabled ? nil : .easeOut(duration: 0.12),
        value: configuration.isPressed
      )
  }
}

#Preview {
  KeyboardView(connectionManager: ConnectionManager())
    .environment(ThemeStore())
}
