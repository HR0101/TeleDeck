//
//  PomodoroModel.swift
//  TeleDeck
//
//  作業25分/休憩5分を自動で繰り返すポモドーロタイマー。
//  内部の時間管理はCountdownTimerModelに委譲し、完了時にフェーズを自動で切り替える。
//

import Foundation
import Observation

/// ポモドーロの現在フェーズ
enum PomodoroPhase {
  case work
  case breakTime

  var label: String {
    switch self {
    case .work:
      return "作業中"
    case .breakTime:
      return "休憩中"
    }
  }
}

@Observable
final class PomodoroModel {
  private static let secondsPerMinute = 60
  private static let workMinutes = 25
  private static let breakMinutes = 5

  private static let workDurationSeconds = workMinutes * secondsPerMinute
  private static let breakDurationSeconds = breakMinutes * secondsPerMinute

  private(set) var phase: PomodoroPhase = .work

  private let countdown: CountdownTimerModel

  var runState: TimerRunState { countdown.runState }
  var remainingSeconds: Int { countdown.remainingSeconds }

  init() {
    countdown = CountdownTimerModel(totalSeconds: Self.workDurationSeconds)
    countdown.onFinish = { [weak self] in
      self?.advanceToNextPhase()
    }
  }

  func start() {
    countdown.start()
  }

  func pause() {
    countdown.pause()
  }

  func reset() {
    phase = .work
    countdown.configure(totalSeconds: Self.workDurationSeconds)
    countdown.reset()
  }

  /// 作業⇄休憩を切り替え、次のフェーズのカウントダウンを自動で開始する
  private func advanceToNextPhase() {
    phase = (phase == .work) ? .breakTime : .work
    let nextDuration = (phase == .work) ? Self.workDurationSeconds : Self.breakDurationSeconds
    countdown.configure(totalSeconds: nextDuration)
    countdown.start()
  }
}
