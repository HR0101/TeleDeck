//
//  GamingTheme.swift
//  TeleDeck
//
//  紫ベースのゲーミングデバイス風ビジュアル（ダーク背景・グロー・グラスカード）を
//  アプリ全体で共通利用するためのスタイル定義。アクセントカラーはThemeStoreの選択に追随する。
//

import SwiftUI

/// アプリ全体で固定のダークトーン（アクセントカラーの選択に関わらず変わらない構造色）
enum GamingPalette {
  // OLED/LCDどちらでも黒を基準に見せ、静的背景でも階層が分かる程度の差だけ残す。
  static let background = Color(hex: 0x050507)
  static let backgroundElevated = Color(hex: 0x0D0D12)
  static let card = Color(hex: 0x16161D)
  static let muted = Color(hex: 0x24242D)
  static let foreground = Color(hex: 0xE2E8F0)
  static let mutedForeground = Color(hex: 0x94A3B8)
  static let destructive = Color(hex: 0xEF4444)
  /// アクションが正常に実行できたことを示す成功色
  static let success = Color(hex: 0x22C55E)
}

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }
}

/// 画面全体に敷く、紫を基調にしたダークグラデーション背景。
/// 中央付近にアクセントカラーのグロー（ぼかし光）を淡く配置し、単調な単色背景にならないようにする。
/// モーション低減設定が有効な場合はグローのアニメーションを止める。
struct GamingBackground: View {
  var accentColor: Color = GamingPalette.muted
  /// 電池消費の大きいぼかしグローを表示するかどうか。OFF時は静的な黒ベースの背景だけを描画する。
  var showsGlow = false

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var animate = false

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [GamingPalette.background, GamingPalette.backgroundElevated],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      if showsGlow {
        Circle()
          .fill(accentColor.opacity(0.28))
          .frame(width: 420, height: 420)
          .blur(radius: 120)
          .offset(x: animate ? -80 : -140, y: animate ? -220 : -180)

        Circle()
          .fill(accentColor.opacity(0.18))
          .frame(width: 360, height: 360)
          .blur(radius: 120)
          .offset(x: animate ? 140 : 100, y: animate ? 260 : 300)
      }
    }
    .ignoresSafeArea()
    .onAppear {
      startGlowAnimationIfNeeded()
    }
    .onChange(of: showsGlow) { _, enabled in
      if enabled {
        startGlowAnimationIfNeeded()
      } else {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
          animate = false
        }
      }
    }
  }

  private func startGlowAnimationIfNeeded() {
    guard showsGlow, !reduceMotion else { return }
    withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
      animate = true
    }
  }
}

/// カード状の面（ボタン・行など）に共通のガラス風グロー装飾を与えるモディファイア
private struct GamingCardModifier: ViewModifier {
  var accentColor: Color
  var cornerRadius: CGFloat
  var isEmphasized: Bool

  func body(content: Content) -> some View {
    content
      .background(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(.ultraThinMaterial)
      )
      .background(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(GamingPalette.card.opacity(0.55))
      )
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(accentColor.opacity(isEmphasized ? 0.9 : 0.45), lineWidth: isEmphasized ? 1.5 : 1)
      )
      .shadow(color: accentColor.opacity(isEmphasized ? 0.5 : 0.25), radius: isEmphasized ? 14 : 8)
  }
}

extension View {
  /// ゲーミングデバイス風のガラスカード装飾を適用する
  func gamingCard(accentColor: Color, cornerRadius: CGFloat = 14, isEmphasized: Bool = false) -> some View {
    modifier(GamingCardModifier(accentColor: accentColor, cornerRadius: cornerRadius, isEmphasized: isEmphasized))
  }
}

/// ボタン全般に使う、押下時にグローが強まるゲーミング風ButtonStyle
struct GamingButtonStyle: ButtonStyle {
  var accentColor: Color
  var cornerRadius: CGFloat = 14

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(GamingPalette.foreground)
      .background(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(configuration.isPressed ? accentColor.opacity(0.35) : GamingPalette.muted.opacity(0.9))
      )
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(accentColor.opacity(configuration.isPressed ? 0.95 : 0.5), lineWidth: 1.2)
      )
      .shadow(color: accentColor.opacity(configuration.isPressed ? 0.65 : 0.3), radius: configuration.isPressed ? 12 : 6)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }
}
