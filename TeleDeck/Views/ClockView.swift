//
//  ClockView.swift
//  TeleDeck
//
//  デジタル時計画面。大型の時刻表示に加えて、タイマー/ストップウォッチ/ポモドーロを
//  セグメントで切り替えて使える。
//

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
  case relax = "癒し"
  case cyber = "サイバー"

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
  /// 「時計のみ表示」（コントロール非表示）になったことを親へ伝え、下部タブバーも連動して隠すためのフラグ。
  /// MainTabView以外（単体表示・プレビュー）ではタブバーが無いため、デフォルトのダミーBindingでそのままでOK
  @Binding private var isImmersive: Bool

  init(isImmersive: Binding<Bool> = .constant(false)) {
    _isImmersive = isImmersive
  }

  private var shouldReduceMotion: Bool {
    reduceMotion || themeStore.isEnergySavingModeEnabled
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        GamingBackground(
          accentColor: themeStore.accentColor,
          showsGlow: themeStore.backgroundGlowEnabled
        )

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
    // 通常時は秒単位、低電力表示中は分単位だけ時刻を更新する。
    .task(id: themeStore.isEnergySavingModeEnabled) {
      await updateCurrentTimeUntilCancelled()
    }
    // コントロールの自動非表示は毎秒タイマーではなく、操作ごとの1回だけの待機で処理する。
    .task(id: lastInteraction) {
      await hideControlsAfterDelay()
    }
    // 低電力表示中・操作コントロール表示中は焼き付き防止の位置アニメーションを停止する。
    .task(id: shouldRunBurnInProtection) {
      await runBurnInProtectionUntilCancelled()
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
          .frame(width: 300)
          .disabled(themeStore.isEnergySavingModeEnabled)

          if themeStore.isEnergySavingModeEnabled {
            Label("低電力モード中はデジタル表示になります", systemImage: "leaf.fill")
              .font(.caption.weight(.medium))
              .foregroundStyle(GamingPalette.success)
          }
        }
      }

      Group {
        if themeStore.isEnergySavingModeEnabled {
          Text(
            now,
            format: .dateTime
              .hour(.twoDigits(amPM: .omitted))
              .minute(.twoDigits)
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
          .foregroundStyle(GamingPalette.foreground)
        } else {
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
                shouldReduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1),
                value: areControlsVisible
              )
              .padding(.vertical, areControlsVisible ? 0 : 20)
          case .analog:
            AnalogClockView(date: now)
              .scaleEffect(areControlsVisible ? 0.35 : 1.0)
              .frame(width: areControlsVisible ? 224 : 640, height: areControlsVisible ? 224 : 640)
              .animation(
                shouldReduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1),
                value: areControlsVisible
              )
              .padding(.vertical, areControlsVisible ? 0 : 20)
          case .relax:
            RelaxingClockView(date: now)
              .scaleEffect(areControlsVisible ? 0.35 : 1.0)
              .frame(width: areControlsVisible ? 224 : 640, height: areControlsVisible ? 224 : 640)
              .animation(
                shouldReduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1),
                value: areControlsVisible
              )
              .padding(.vertical, areControlsVisible ? 0 : 20)
          case .cyber:
            CyberClockView(date: now)
              .scaleEffect(areControlsVisible ? 0.35 : 1.0)
              .frame(width: areControlsVisible ? 224 : 640, height: areControlsVisible ? 224 : 640)
              .animation(
                shouldReduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1),
                value: areControlsVisible
              )
              .padding(.vertical, areControlsVisible ? 0 : 20)
          }
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
      shouldReduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1),
      value: areControlsVisible
    )
  }

  private func updateCurrentTimeUntilCancelled() async {
    let updateInterval: UInt64 = themeStore.isEnergySavingModeEnabled
      ? 60_000_000_000
      : 1_000_000_000

    while !Task.isCancelled {
      now = Date()
      do {
        try await Task.sleep(nanoseconds: updateInterval)
      } catch {
        return
      }
    }
  }

  private func hideControlsAfterDelay() async {
    do {
      try await Task.sleep(nanoseconds: UInt64(clockControlsAutoHideDelay * 1_000_000_000))
    } catch {
      return
    }
    guard !Task.isCancelled, areControlsVisible else { return }
    hideControls()
  }

  private func runBurnInProtectionUntilCancelled() async {
    guard shouldRunBurnInProtection else {
      clockOffsetX = 0
      clockOffsetY = 0
      return
    }

    while !Task.isCancelled {
      do {
        try await Task.sleep(nanoseconds: UInt64(burnInProtectionInterval * 1_000_000_000))
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      shiftClockPosition()
    }
  }

  private var shouldRunBurnInProtection: Bool {
    !themeStore.isEnergySavingModeEnabled && !areControlsVisible
  }

  private func revealControls() {
    lastInteraction = Date()
    guard !areControlsVisible else { return }
    withAnimation(shouldReduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1)) {
      areControlsVisible = true
      isImmersive = false
    }
  }

  private func hideControls() {
    guard areControlsVisible else { return }
    withAnimation(shouldReduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1)) {
      areControlsVisible = false
      isImmersive = true
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
      Button {
        if model.runState == .running {
          model.pause()
        } else {
          model.start()
        }
      } label: {
        Text(model.runState == .running ? "一時停止" : "開始")
      }
      .buttonStyle(PrimaryActionButtonStyle(accentColor: themeStore.accentColor))

      Button {
        model.reset()
      } label: {
        Text("リセット")
      }
      .buttonStyle(SecondaryActionButtonStyle())
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
        Button {
          if model.runState == .running {
            model.pause()
          } else {
            model.start()
          }
        } label: {
          Text(model.runState == .running ? "一時停止" : "開始")
        }
        .buttonStyle(PrimaryActionButtonStyle(accentColor: themeStore.accentColor))

        Button {
          model.reset()
        } label: {
          Text("リセット")
        }
        .buttonStyle(SecondaryActionButtonStyle())
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
        Button {
          if model.runState == .running {
            model.pause()
          } else {
            model.start()
          }
        } label: {
          Text(model.runState == .running ? "一時停止" : "開始")
        }
        .buttonStyle(PrimaryActionButtonStyle(accentColor: themeStore.accentColor))

        Button {
          model.reset()
        } label: {
          Text("リセット")
        }
        .buttonStyle(SecondaryActionButtonStyle())
      }
    }
  }
}

// MARK: - ツール用ボタンスタイル

private struct PrimaryActionButtonStyle: ButtonStyle {
  @Environment(ThemeStore.self) private var themeStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var accentColor: Color

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.title3.weight(.bold))
      .foregroundStyle(Color(hex: 0x0F0F23)) // 背景色に近い暗色にしてコントラストを高くする
      .frame(maxWidth: .infinity)
      .padding(.vertical, 18)
      .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(accentColor.opacity(configuration.isPressed ? 0.7 : 1.0))
      )
      .shadow(
        color: themeStore.isEnergySavingModeEnabled ? .clear : accentColor.opacity(0.4),
        radius: themeStore.isEnergySavingModeEnabled ? 0 : (configuration.isPressed ? 4 : 12),
        y: themeStore.isEnergySavingModeEnabled ? 0 : (configuration.isPressed ? 2 : 6)
      )
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .animation(
        reduceMotion || themeStore.isEnergySavingModeEnabled ? nil : .easeOut(duration: 0.15),
        value: configuration.isPressed
      )
  }
}

private struct SecondaryActionButtonStyle: ButtonStyle {
  @Environment(ThemeStore.self) private var themeStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.title3.weight(.bold))
      .foregroundStyle(GamingPalette.foreground)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 18)
      .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(GamingPalette.muted.opacity(0.8))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(GamingPalette.mutedForeground.opacity(0.2), lineWidth: 1)
      )
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .animation(
        reduceMotion || themeStore.isEnergySavingModeEnabled ? nil : .easeOut(duration: 0.15),
        value: configuration.isPressed
      )
  }
}

#Preview {
  ClockView()
    .environment(ThemeStore())
}
