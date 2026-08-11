//
//  RelaxingClockView.swift
//  TeleDeck
//
//  癒し（マインドフルネス）を感じられる、ゆっくりと呼吸するように動くオーブと
//  細くてクリーンなフォントを組み合わせた時計デザイン。
//

import SwiftUI

struct RelaxingClockView: View {
  @Environment(ThemeStore.self) private var themeStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let date: Date

  @State private var phase1 = false
  @State private var phase2 = false
  @State private var phase3 = false

  var body: some View {
    ZStack {
      // ぼんやりとした光のオーブ1
      Circle()
        .fill(themeStore.accentColor.opacity(0.15))
        .frame(width: 400, height: 400)
        .blur(radius: 80)
        .offset(x: phase1 ? 80 : -80, y: phase1 ? -50 : 50)
        .scaleEffect(phase1 ? 1.2 : 0.8)

      // ぼんやりとした光のオーブ2（少し寒色系を混ぜて透明感を出す）
      Circle()
        .fill(Color.blue.opacity(0.10))
        .frame(width: 350, height: 350)
        .blur(radius: 90)
        .offset(x: phase2 ? -90 : 90, y: phase2 ? 70 : -70)
        .scaleEffect(phase2 ? 1.1 : 0.9)

      // ぼんやりとした光のオーブ3
      Circle()
        .fill(Color.purple.opacity(0.15))
        .frame(width: 300, height: 300)
        .blur(radius: 70)
        .offset(x: phase3 ? 20 : -20, y: phase3 ? 100 : -100)
        .scaleEffect(phase3 ? 1.3 : 0.8)

      // 時計の文字盤
      VStack(spacing: -10) {
        Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
          .font(.system(size: 160, weight: .ultraLight, design: .default))
          .tracking(8) // 文字間隔を広げてゆったりとした印象に
          .lineLimit(1)
          .minimumScaleFactor(0.5)
          .foregroundStyle(.white.opacity(0.8))
          .shadow(color: themeStore.accentColor.opacity(0.2), radius: 20)

        Text(date, format: .dateTime.second(.twoDigits))
          .font(.system(size: 40, weight: .light, design: .default))
          .tracking(4)
          .foregroundStyle(themeStore.accentColor.opacity(0.6))
          .blendMode(.screen)
      }
    }
    .frame(width: 640, height: 640)
    .onAppear {
      startAnimationsIfNeeded()
    }
    .onChange(of: themeStore.isEnergySavingModeEnabled) { _, isEnabled in
      if isEnabled {
        stopAnimations()
      } else {
        startAnimationsIfNeeded()
      }
    }
  }

  private func startAnimationsIfNeeded() {
    guard !reduceMotion, !themeStore.isEnergySavingModeEnabled else { return }
    // それぞれ異なるテンポでゆったりとアニメーションさせる（マインドフルネスの呼吸のリズムに近い速度）
    withAnimation(.easeInOut(duration: 7.0).repeatForever(autoreverses: true)) {
      phase1 = true
    }
    withAnimation(.easeInOut(duration: 9.0).repeatForever(autoreverses: true)) {
      phase2 = true
    }
    withAnimation(.easeInOut(duration: 11.0).repeatForever(autoreverses: true)) {
      phase3 = true
    }
  }

  private func stopAnimations() {
    var transaction = Transaction()
    transaction.animation = nil
    withTransaction(transaction) {
      phase1 = false
      phase2 = false
      phase3 = false
    }
  }
}

#Preview {
  RelaxingClockView(date: Date())
    .environment(ThemeStore())
    .padding()
    .background(Color.black)
}
