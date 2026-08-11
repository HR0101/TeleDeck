//
//  FlipClockView.swift
//  TeleDeck
//
//  パタパタ時計（Flip Clock）デザインのビュー。
//

import SwiftUI

struct FlipClockView: View {
  @Environment(ThemeStore.self) private var themeStore
  let date: Date

  var body: some View {
    HStack(spacing: 16) {
      DoubleFlipPanel(value: Calendar.current.component(.hour, from: date))

      Text(":")
        .font(.system(size: 64, weight: .bold, design: .rounded))
        .foregroundStyle(themeStore.accentColor)
        .offset(y: -4)

      DoubleFlipPanel(value: Calendar.current.component(.minute, from: date))

      Text(":")
        .font(.system(size: 64, weight: .bold, design: .rounded))
        .foregroundStyle(themeStore.accentColor)
        .offset(y: -4)

      DoubleFlipPanel(value: Calendar.current.component(.second, from: date))
    }
    .shadow(color: themeStore.accentColor.opacity(0.2), radius: 20)
  }
}

private struct DoubleFlipPanel: View {
  let value: Int
  
  var body: some View {
    HStack(spacing: 8) {
      SingleFlipPanel(value: value / 10)
      SingleFlipPanel(value: value % 10)
    }
  }
}

private struct SingleFlipPanel: View {
  @Environment(ThemeStore.self) private var themeStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let value: Int

  var body: some View {
    ZStack {
      SingleFlipPanelContent(value: value)
        .id(value)
        .transition(
          .asymmetric(
            // 新しいパネルは手前側に跳ね上がった状態(90度)から、通常(0度)へパタンと降りてくる
            insertion: .modifier(
              active: FlipTopTransition(angle: 90), identity: FlipTopTransition(angle: 0)),
            // 古いパネルは通常(0度)から、奥へ(-90度)落ちるように消える
            removal: .modifier(
              active: FlipTopTransition(angle: -90), identity: FlipTopTransition(angle: 0))
          )
        )
    }
    // 少しゆっくりめにして、めくれる動きを見やすくする
    .animation(
      reduceMotion || themeStore.isEnergySavingModeEnabled
        ? nil
        : .spring(response: 0.5, dampingFraction: 0.75),
      value: value
    )
  }
}

private struct SingleFlipPanelContent: View {
  @Environment(ThemeStore.self) private var themeStore
  let value: Int

  var body: some View {
    Text("\(value)")
      .font(.system(size: 110, weight: .bold, design: .rounded))
      .monospacedDigit()
      .foregroundStyle(themeStore.accentColor)
      .padding(.horizontal, 16)
      .padding(.vertical, 18)
      .frame(minWidth: 80) // 1桁が安定して収まる幅
      .background(
        RoundedRectangle(cornerRadius: 16)
          .fill(GamingPalette.background)
          .overlay(
            RoundedRectangle(cornerRadius: 16)
              .stroke(themeStore.accentColor.opacity(0.3), lineWidth: 1)
          )
      )
      .drawingGroup()
  }
}

private struct FlipTopTransition: ViewModifier {
  let angle: Double
  func body(content: Content) -> some View {
    content
      .rotation3DEffect(
        .degrees(angle),
        axis: (x: 1, y: 0, z: 0),
        anchor: .top, // パネルの上端を軸にしてめくれる
        perspective: 0.6
      )
      .opacity(abs(angle) >= 90 ? 0 : 1)
  }
}

#Preview {
  FlipClockView(date: Date())
    .environment(ThemeStore())
    .padding()
    .background(Color.black)
}
