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
      FlipUnitGroup(value: Calendar.current.component(.hour, from: date))

      Text(":")
        .font(.system(size: 64, weight: .bold, design: .rounded))
        .foregroundStyle(themeStore.accentColor)
        .offset(y: -4)

      FlipUnitGroup(value: Calendar.current.component(.minute, from: date))

      Text(":")
        .font(.system(size: 64, weight: .bold, design: .rounded))
        .foregroundStyle(themeStore.accentColor)
        .offset(y: -4)

      FlipUnitGroup(value: Calendar.current.component(.second, from: date))
    }
    .shadow(color: themeStore.accentColor.opacity(0.2), radius: 20)
  }
}

private struct FlipUnitGroup: View {
  let value: Int

  var body: some View {
    HStack(spacing: 6) {
      FlipDigit(digit: value / 10)
      FlipDigit(digit: value % 10)
    }
  }
}

private struct FlipDigit: View {
  @Environment(ThemeStore.self) private var themeStore
  let digit: Int

  var body: some View {
    ZStack {
      Text("\(digit)")
        .font(.system(size: 110, weight: .bold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(themeStore.accentColor)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(
          RoundedRectangle(cornerRadius: 12)
            .fill(GamingPalette.background)
            .overlay(
              RoundedRectangle(cornerRadius: 12)
                .stroke(themeStore.accentColor.opacity(0.3), lineWidth: 1)
            )
        )
        .overlay(
          Rectangle()
            .fill(GamingPalette.background)
            .frame(height: 2)
            .shadow(color: .black.opacity(0.5), radius: 1, y: 1),
          alignment: .center
        )
        .drawingGroup()
    }
    .id(digit)
    .transition(
      .asymmetric(
        insertion: .modifier(
          active: FlipTransition(angle: 90), identity: FlipTransition(angle: 0)),
        removal: .modifier(
          active: FlipTransition(angle: -90), identity: FlipTransition(angle: 0))
      )
    )
    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: digit)
  }
}

private struct FlipTransition: ViewModifier {
  let angle: Double
  func body(content: Content) -> some View {
    content
      .rotation3DEffect(
        .degrees(angle),
        axis: (x: 1, y: 0, z: 0),
        anchor: .center,
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
