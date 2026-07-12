//
//  ClockView.swift
//  TeleDeck
//
//  デジタル時計画面。大型の時刻表示に加えて、タイマー/ストップウォッチ/ポモドーロを
//  セグメントで切り替えて使える。
//

import Combine
import SwiftUI

/// 時間（分）を秒に変換する際の基準値
private let secondsPerMinute = 60

/// 秒数を"mm:ss"形式の文字列に整形する（タイマー/ストップウォッチ/ポモドーロで共通利用）
private func formattedMinutesSeconds(_ totalSeconds: Int) -> String {
  let minutes = totalSeconds / secondsPerMinute
  let seconds = totalSeconds % secondsPerMinute
  return String(format: "%02d:%02d", minutes, seconds)
}

private enum ClockToolMode: String, CaseIterable, Identifiable {
  case timer = "タイマー"
  case stopwatch = "ストップウォッチ"
  case pomodoro = "ポモドーロ"

  var id: String { rawValue }
}

/// 焼き付き防止のため時刻表示をずらす間隔（秒）
private let burnInProtectionInterval: TimeInterval = 30
/// 焼き付き防止でずらす最大幅（ポイント）。表示が破綻しない程度のごくわずかな量にとどめる
private let burnInProtectionMaxOffset: CGFloat = 12

struct ClockView: View {
  @Environment(ThemeStore.self) private var themeStore
  @State private var now = Date()
  @State private var selectedMode: ClockToolMode = .timer
  @State private var clockOffsetX: CGFloat = 0
  @State private var clockOffsetY: CGFloat = 0

  private let clockTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
  private let burnInProtectionTicker = Timer.publish(
    every: burnInProtectionInterval, on: .main, in: .common
  ).autoconnect()

  var body: some View {
    ScrollView {
      VStack(spacing: 32) {
        clockSection
        toolSection
      }
      .padding()
    }
    .onReceive(clockTicker) { tickedDate in
      now = tickedDate
    }
    .onReceive(burnInProtectionTicker) { _ in
      shiftClockPosition()
    }
  }

  // MARK: - 時刻表示

  private var clockSection: some View {
    VStack(spacing: 8) {
      Text(
        now,
        format: .dateTime
          .hour(.twoDigits(amPM: .omitted))
          .minute(.twoDigits)
          .second(.twoDigits)
      )
      .font(.system(size: 64, weight: .bold, design: .rounded))
      .monospacedDigit()
      .foregroundStyle(GamingPalette.foreground)

      Text(now, format: .dateTime.year().month().day().weekday(.wide))
        .font(.title3)
        .foregroundStyle(GamingPalette.mutedForeground)
    }
    .padding(.top, 32)
    .offset(x: clockOffsetX, y: clockOffsetY)
  }

  /// 画面焼き付き防止のため、時刻表示をごくわずかランダムな方向へなめらかにずらす
  private func shiftClockPosition() {
    withAnimation(.easeInOut) {
      clockOffsetX = CGFloat.random(in: -burnInProtectionMaxOffset...burnInProtectionMaxOffset)
      clockOffsetY = CGFloat.random(in: -burnInProtectionMaxOffset...burnInProtectionMaxOffset)
    }
  }

  // MARK: - タイマー/ストップウォッチ/ポモドーロ

  private var toolSection: some View {
    VStack(spacing: 20) {
      Picker("機能", selection: $selectedMode) {
        ForEach(ClockToolMode.allCases) { mode in
          Text(mode.rawValue).tag(mode)
        }
      }
      .pickerStyle(.segmented)

      Group {
        switch selectedMode {
        case .timer:
          TimerToolView()
        case .stopwatch:
          StopwatchToolView()
        case .pomodoro:
          PomodoroToolView()
        }
      }
      .padding()
      .gamingCard(accentColor: themeStore.accentColor)
    }
  }
}

// MARK: - タイマー

private struct TimerToolView: View {
  private static let defaultMinutes = 5
  private static let minMinutes = 1
  private static let maxMinutes = 60

  @Environment(ThemeStore.self) private var themeStore
  @State private var model = CountdownTimerModel(
    totalSeconds: TimerToolView.defaultMinutes * secondsPerMinute
  )
  @State private var selectedMinutes = TimerToolView.defaultMinutes

  var body: some View {
    VStack(spacing: 16) {
      Stepper(value: $selectedMinutes, in: Self.minMinutes...Self.maxMinutes) {
        Text("時間: \(selectedMinutes)分")
          .foregroundStyle(GamingPalette.foreground)
      }
      .disabled(model.runState == .running || model.runState == .paused)
      .onChange(of: selectedMinutes) { _, newValue in
        model.configure(totalSeconds: newValue * secondsPerMinute)
      }

      Text(formattedMinutesSeconds(model.remainingSeconds))
        .font(.system(size: 48, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(model.runState == .finished ? GamingPalette.destructive : GamingPalette.foreground)

      if model.runState == .finished {
        Text("終了しました")
          .font(.headline)
          .foregroundStyle(GamingPalette.destructive)
      }

      timerControls
    }
  }

  private var timerControls: some View {
    HStack(spacing: 16) {
      Button(model.runState == .running ? "一時停止" : "開始") {
        if model.runState == .running {
          model.pause()
        } else {
          model.start()
        }
      }
      .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor))

      Button("リセット") {
        model.reset()
      }
      .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor))
    }
  }
}

// MARK: - ストップウォッチ

private struct StopwatchToolView: View {
  @Environment(ThemeStore.self) private var themeStore
  @State private var model = StopwatchModel()

  var body: some View {
    VStack(spacing: 16) {
      Text(formattedMinutesSeconds(model.elapsedSeconds))
        .font(.system(size: 48, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(GamingPalette.foreground)

      HStack(spacing: 16) {
        Button(model.runState == .running ? "一時停止" : "開始") {
          if model.runState == .running {
            model.pause()
          } else {
            model.start()
          }
        }
        .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor))

        Button("リセット") {
          model.reset()
        }
        .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor))
      }
    }
  }
}

// MARK: - ポモドーロ

private struct PomodoroToolView: View {
  @Environment(ThemeStore.self) private var themeStore
  @State private var model = PomodoroModel()

  var body: some View {
    VStack(spacing: 16) {
      Text(model.phase.label)
        .font(.headline)
        .foregroundStyle(model.phase == .work ? themeStore.accentColor : GamingPalette.foreground)

      Text(formattedMinutesSeconds(model.remainingSeconds))
        .font(.system(size: 48, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(GamingPalette.foreground)

      HStack(spacing: 16) {
        Button(model.runState == .running ? "一時停止" : "開始") {
          if model.runState == .running {
            model.pause()
          } else {
            model.start()
          }
        }
        .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor))

        Button("リセット") {
          model.reset()
        }
        .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor))
      }
    }
  }
}

#Preview {
  ClockView()
    .environment(ThemeStore())
}
