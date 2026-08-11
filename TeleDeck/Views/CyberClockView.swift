//
//  CyberClockView.swift
//  TeleDeck
//
//  SF/HUD風の凝ったデザインの時計。多重リングの回転・レーダー状のスキャン光・
//  時/分/秒それぞれの進捗を表す同心円弧・四隅のブラケットを組み合わせている。
//

import SwiftUI

struct CyberClockView: View {
  @Environment(ThemeStore.self) private var themeStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let date: Date

  @State private var outerRingRotation: Double = 0
  @State private var innerRingRotation: Double = 0
  @State private var scanAngle: Double = 0

  var body: some View {
    let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
    let hour = components.hour ?? 0
    let minute = components.minute ?? 0
    let second = components.second ?? 0

    ZStack {
      backdrop
      cyberGrid

      outerTickRing
        .rotationEffect(.degrees(outerRingRotation))

      innerTickRing
        .rotationEffect(.degrees(-innerRingRotation))

      scanWedge
        .rotationEffect(.degrees(scanAngle))

      progressArcs(hour: hour, minute: minute, second: second)

      cornerBrackets

      centerReadout(hour: hour, minute: minute, second: second)
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
    withAnimation(.linear(duration: 40).repeatForever(autoreverses: false)) {
      outerRingRotation = 360
    }
    withAnimation(.linear(duration: 26).repeatForever(autoreverses: false)) {
      innerRingRotation = 360
    }
    withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
      scanAngle = 360
    }
  }

  private func stopAnimations() {
    var transaction = Transaction()
    transaction.animation = nil
    withTransaction(transaction) {
      outerRingRotation = 0
      innerRingRotation = 0
      scanAngle = 0
    }
  }

  // MARK: - 背景

  private var backdrop: some View {
    Circle()
      .fill(
        RadialGradient(
          colors: [GamingPalette.background.opacity(0.65), GamingPalette.background.opacity(0.1)],
          center: .center,
          startRadius: 0,
          endRadius: 320
        )
      )
      .frame(width: 620, height: 620)
  }

  private var cyberGrid: some View {
    ZStack {
      ForEach([0.9, 0.7, 0.5, 0.3], id: \.self) { scale in
        Circle()
          .stroke(themeStore.accentColor.opacity(0.08), lineWidth: 1)
          .scaleEffect(scale)
      }
      ForEach(0..<12) { index in
        Rectangle()
          .fill(themeStore.accentColor.opacity(0.05))
          .frame(width: 1, height: 620)
          .rotationEffect(.degrees(Double(index) * 15))
      }
    }
    .frame(width: 620, height: 620)
  }

  // MARK: - 回転リング

  private var outerTickRing: some View {
    ZStack {
      Circle()
        .stroke(themeStore.accentColor.opacity(0.25), lineWidth: 1.5)
        .frame(width: 560, height: 560)

      ForEach(0..<72, id: \.self) { tick in
        let isMajor = tick % 6 == 0
        Rectangle()
          .fill(themeStore.accentColor.opacity(isMajor ? 0.9 : 0.35))
          .frame(width: isMajor ? 3 : 1, height: isMajor ? 18 : 8)
          .offset(y: -280)
          .rotationEffect(.degrees(Double(tick) * 5))
      }
    }
  }

  private var innerTickRing: some View {
    Circle()
      .stroke(themeStore.accentColor.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [2, 14]))
      .frame(width: 460, height: 460)
  }

  // MARK: - レーダー状のスキャン光

  private var scanWedge: some View {
    RadarWedgeShape(spanDegrees: 26)
      .fill(
        AngularGradient(
          colors: [themeStore.accentColor.opacity(0), themeStore.accentColor.opacity(0.4)],
          center: .center,
          startAngle: .degrees(0),
          endAngle: .degrees(26)
        )
      )
      .frame(width: 560, height: 560)
  }

  // MARK: - 時/分/秒の進捗アーク

  private func progressArcs(hour: Int, minute: Int, second: Int) -> some View {
    ZStack {
      progressArc(progress: Double(hour % 12) / 12, diameter: 400, lineWidth: 10, opacity: 1.0)
      progressArc(progress: Double(minute) / 60, diameter: 356, lineWidth: 8, opacity: 0.75)
      progressArc(progress: Double(second) / 60, diameter: 316, lineWidth: 5, opacity: 0.55)
    }
  }

  private func progressArc(progress: Double, diameter: CGFloat, lineWidth: CGFloat, opacity: Double) -> some View {
    Circle()
      // 進捗0でもごく薄いスリバーが見えるようにして、常に3本のリングがあることが分かるようにする
      .trim(from: 0, to: max(progress, 0.0015))
      .stroke(themeStore.accentColor.opacity(opacity), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
      .frame(width: diameter, height: diameter)
      .rotationEffect(.degrees(-90))
      .shadow(color: themeStore.accentColor.opacity(opacity * 0.6), radius: 8)
  }

  // MARK: - 四隅のHUDブラケット

  private var cornerBrackets: some View {
    ZStack {
      cornerBracket(rotation: 0).offset(x: -260, y: -260)
      cornerBracket(rotation: 90).offset(x: 260, y: -260)
      cornerBracket(rotation: 180).offset(x: 260, y: 260)
      cornerBracket(rotation: 270).offset(x: -260, y: 260)
    }
  }

  private func cornerBracket(rotation: Double) -> some View {
    CornerBracketShape()
      .stroke(themeStore.accentColor.opacity(0.6), lineWidth: 3)
      .frame(width: 36, height: 36)
      .rotationEffect(.degrees(rotation))
  }

  // MARK: - 中央のデジタル表示

  private func centerReadout(hour: Int, minute: Int, second: Int) -> some View {
    VStack(spacing: 6) {
      HStack(spacing: 8) {
        Circle()
          .fill(themeStore.accentColor)
          .frame(width: 6, height: 6)
        Text("SYNC")
          .font(.system(size: 13, weight: .bold, design: .monospaced))
          .tracking(6)
        Circle()
          .fill(themeStore.accentColor)
          .frame(width: 6, height: 6)
      }
      .foregroundStyle(themeStore.accentColor.opacity(0.75))

      Text(String(format: "%02d:%02d", hour, minute))
        .font(.system(size: 92, weight: .bold, design: .monospaced))
        .monospacedDigit()
        .foregroundStyle(
          LinearGradient(colors: [GamingPalette.foreground, themeStore.accentColor], startPoint: .top, endPoint: .bottom)
        )
        .shadow(color: themeStore.accentColor.opacity(0.5), radius: 18)

      Text(String(format: "%02d", second))
        .font(.system(size: 22, weight: .semibold, design: .monospaced))
        .monospacedDigit()
        .tracking(4)
        .foregroundStyle(themeStore.accentColor)
    }
  }
}

/// レーダーのスキャン光のような、扇形（くさび形）のシェイプ
private struct RadarWedgeShape: Shape {
  let spanDegrees: Double

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let radius = min(rect.width, rect.height) / 2
    path.move(to: center)
    path.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(spanDegrees), clockwise: false)
    path.closeSubpath()
    return path
  }
}

/// カメラのビューファインダーのような、四隅に置くL字ブラケット
private struct CornerBracketShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: 0, y: rect.height))
    path.addLine(to: CGPoint(x: 0, y: 0))
    path.addLine(to: CGPoint(x: rect.width, y: 0))
    return path
  }
}

#Preview {
  CyberClockView(date: Date())
    .environment(ThemeStore())
    .padding()
    .background(Color.black)
}
