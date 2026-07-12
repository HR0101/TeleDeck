//
//  AnalogClockView.swift
//  TeleDeck
//
//  アナログ時計デザインのビュー。
//

import SwiftUI

struct AnalogClockView: View {
  @Environment(ThemeStore.self) private var themeStore
  let date: Date

  var body: some View {
    let calendar = Calendar.current
    let components = calendar.dateComponents([.hour, .minute, .second], from: date)
    let hour = Double(components.hour ?? 0)
    let minute = Double(components.minute ?? 0)
    let second = Double(components.second ?? 0)

    // 角度の計算
    let secondAngle = second * 6.0
    let minuteAngle = minute * 6.0 + (second / 10.0)
    let hourAngle = (hour.truncatingRemainder(dividingBy: 12)) * 30.0 + (minute / 2.0)

    ZStack {
      // 文字盤の背景
      Circle()
        .fill(GamingPalette.background)
        .shadow(color: themeStore.accentColor.opacity(0.2), radius: 40)

      // 文字盤の縁
      Circle()
        .stroke(themeStore.accentColor.opacity(0.3), lineWidth: 8)

      // 目盛り
      ForEach(0..<60) { tick in
        let isHour = tick % 5 == 0
        Rectangle()
          .fill(isHour ? themeStore.accentColor : GamingPalette.mutedForeground)
          .frame(width: isHour ? 8 : 4, height: isHour ? 32 : 16)
          .offset(y: -280)
          .rotationEffect(.degrees(Double(tick) * 6))
      }

      // 短針（時）
      Capsule()
        .fill(GamingPalette.foreground)
        .frame(width: 16, height: 180)
        .offset(y: -70)
        .rotationEffect(.degrees(hourAngle))

      // 長針（分）
      Capsule()
        .fill(GamingPalette.foreground)
        .frame(width: 12, height: 260)
        .offset(y: -110)
        .rotationEffect(.degrees(minuteAngle))

      // 秒針
      Capsule()
        .fill(themeStore.accentColor)
        .frame(width: 6, height: 300)
        .offset(y: -120) // 少し反対側にも伸びるようにする
        .rotationEffect(.degrees(secondAngle))

      // 中心点
      Circle()
        .fill(themeStore.accentColor)
        .frame(width: 32, height: 32)

      // 中心のさらに内側の点
      Circle()
        .fill(GamingPalette.background)
        .frame(width: 12, height: 12)
    }
    .frame(width: 640, height: 640)
  }
}

#Preview {
  AnalogClockView(date: Date())
    .environment(ThemeStore())
    .padding()
    .background(Color.black)
}
