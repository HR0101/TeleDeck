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

private enum ClockDesignStyle: String, CaseIterable, Identifiable {
  case digital = "デジタル"
  case flip = "パタパタ"
  case analog = "アナログ"

  var id: String { rawValue }
}

/// 焼き付き防止のため時刻表示をずらす間隔（秒）
private let burnInProtectionInterval: TimeInterval = 30
/// 焼き付き防止でずらす最大幅（ポイント）。表示が破綻しない程度のごくわずかな量にとどめる
private let burnInProtectionMaxOffset: CGFloat = 12
/// 操作がない状態で時計表示へ戻るまでの時間
private let clockControlsAutoHideDelay: TimeInterval = 4

struct ClockView: View {
  @Environment(ThemeStore.self) private var themeStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var now = Date()
  @State private var selectedMode: ClockToolMode = .timer
  @AppStorage("clockDesignStyle") private var clockStyle: ClockDesignStyle = .digital
  @State private var clockOffsetX: CGFloat = 0
  @State private var clockOffsetY: CGFloat = 0
  @State private var areControlsVisible = true
  @State private var lastInteraction = Date()

  private let clockTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
  private let burnInProtectionTicker = Timer.publish(
    every: burnInProtectionInterval, on: .main, in: .common
  ).autoconnect()

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        GamingBackground(accentColor: themeStore.accentColor)

        VStack(spacing: 0) {
          if areControlsVisible {
            clockSection(in: proxy.size)

            Spacer(minLength: 24)

            toolSection
              .frame(maxWidth: 640)
              .padding(.horizontal, 28)
              .padding(.bottom, 28)
              .transition(.move(edge: .bottom).combined(with: .opacity))
          } else {
            Spacer()

            clockSection(in: proxy.size)

            Spacer()
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(Rectangle())
      .simultaneousGesture(
        TapGesture().onEnded {
          revealControls()
        }
      )
    }
    .ignoresSafeArea()
    .onReceive(clockTicker) { tickedDate in
      now = tickedDate
      if areControlsVisible,
         tickedDate.timeIntervalSince(lastInteraction) >= clockControlsAutoHideDelay {
        hideControls()
      }
    }
    .onReceive(burnInProtectionTicker) { _ in
      shiftClockPosition()
    }
  }

  // MARK: - 時刻表示

  private func clockSection(in size: CGSize) -> some View {
    VStack(spacing: 18) {
      if areControlsVisible {
        VStack(spacing: 16) {
          HStack(spacing: 10) {
            Capsule()
              .fill(themeStore.accentColor)
              .frame(width: 28, height: 3)

            Text("TELEDECK CLOCK")
              .font(.system(size: 13, weight: .semibold, design: .rounded))
              .tracking(3.2)
              .foregroundStyle(themeStore.accentColor)

            Capsule()
              .fill(themeStore.accentColor)
              .frame(width: 28, height: 3)
          }

          Picker("デザイン", selection: $clockStyle) {
            ForEach(ClockDesignStyle.allCases) { style in
              Text(style.rawValue).tag(style)
            }
          }
          .pickerStyle(.segmented)
          .frame(width: 240)
        }
      }

      Group {
        switch clockStyle {
        case .digital:
          Text(
            now,
            format: .dateTime
              .hour(.twoDigits(amPM: .omitted))
              .minute(.twoDigits)
              .second(.twoDigits)
          )
          .lineLimit(1)
          .minimumScaleFactor(0.5)
          .font(
            .system(
              size: min(
                max(size.width * (areControlsVisible ? 0.16 : 0.25), areControlsVisible ? 84 : 120),
                areControlsVisible ? 176 : 260
              ),
              weight: .medium,
              design: .rounded
            )
          )
          .monospacedDigit()
          .tracking(-2)
          .foregroundStyle(
            LinearGradient(
              colors: [GamingPalette.foreground, themeStore.accentColor],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .shadow(color: themeStore.accentColor.opacity(0.35), radius: 22)
        case .flip:
          FlipClockView(date: now)
            .scaleEffect(areControlsVisible ? 0.75 : 1.0)
            .animation(
              reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 1),
              value: areControlsVisible
            )
            .padding(.vertical, areControlsVisible ? 0 : 20)
        case .analog:
          AnalogClockView(date: now)
            .scaleEffect(areControlsVisible ? 0.35 : 1.0)
            .frame(width: areControlsVisible ? 224 : 640, height: areControlsVisible ? 224 : 640)
            .animation(
              reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 1),
              value: areControlsVisible
            )
            .padding(.vertical, areControlsVisible ? 0 : 20)
        }
      }

      Text(now, format: .dateTime.year().month().day().weekday(.wide))
        .font(.system(size: 20, weight: .medium, design: .rounded))
        .foregroundStyle(GamingPalette.mutedForeground)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, areControlsVisible ? 64 : 0)
    .offset(x: clockOffsetX, y: clockOffsetY)
    .animation(
      reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 1),
      value: areControlsVisible
    )
  }

  private func revealControls() {
    lastInteraction = Date()
    guard !areControlsVisible else { return }
    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 1)) {
      areControlsVisible = true
    }
  }

  private func hideControls() {
    guard areControlsVisible else { return }
    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 1)) {
      areControlsVisible = false
    }
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
      .padding(.horizontal, 20)
      .padding(.vertical, 16)
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
      .font(.title3.weight(.bold))
      .padding(.horizontal, 32)
      .padding(.vertical, 14)
      .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor))

      Button("リセット") {
        model.reset()
      }
      .font(.title3.weight(.bold))
      .padding(.horizontal, 32)
      .padding(.vertical, 14)
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
        .font(.title3.weight(.bold))
        .padding(.horizontal, 32)
        .padding(.vertical, 14)
        .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor))

        Button("リセット") {
          model.reset()
        }
        .font(.title3.weight(.bold))
        .padding(.horizontal, 32)
        .padding(.vertical, 14)
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
        .font(.title3.weight(.bold))
        .padding(.horizontal, 32)
        .padding(.vertical, 14)
        .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor))

        Button("リセット") {
          model.reset()
        }
        .font(.title3.weight(.bold))
        .padding(.horizontal, 32)
        .padding(.vertical, 14)
        .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor))
      }
    }
  }
}

#Preview {
  ClockView()
    .environment(ThemeStore())
}
