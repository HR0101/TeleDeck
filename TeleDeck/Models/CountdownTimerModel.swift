//
//  CountdownTimerModel.swift
//  TeleDeck
//
//  カウントダウン系機能（タイマー/ポモドーロ）が共通で使う実行状態と時間管理ロジック。
//

import Foundation
import Observation

/// タイマー・ストップウォッチ・ポモドーロで共通して使う実行状態
enum TimerRunState {
  case idle
  case running
  case paused
  case finished
}

@Observable
final class CountdownTimerModel {
  private(set) var remainingSeconds: Int
  private(set) var runState: TimerRunState = .idle

  /// カウントダウンが0に達した時に呼ばれる（ポモドーロのフェーズ自動切り替えなどで利用）
  var onFinish: (() -> Void)?

  private var totalSeconds: Int
  private var timer: Timer?

  private static let tickInterval: TimeInterval = 1.0

  init(totalSeconds: Int) {
    self.totalSeconds = totalSeconds
    self.remainingSeconds = totalSeconds
  }

  /// カウントダウンの総時間を設定し直す。実行中でない場合は残り時間にも即座に反映する
  func configure(totalSeconds: Int) {
    self.totalSeconds = totalSeconds
    if runState == .idle {
      remainingSeconds = totalSeconds
    }
  }

  func start() {
    guard runState != .running else { return }
    if runState == .finished {
      reset()
    }
    runState = .running
    scheduleTimer()
  }

  func pause() {
    guard runState == .running else { return }
    runState = .paused
    invalidateTimer()
  }

  func reset() {
    invalidateTimer()
    remainingSeconds = totalSeconds
    runState = .idle
  }

  private func scheduleTimer() {
    invalidateTimer()
    timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
      self?.tick()
    }
  }

  private func tick() {
    guard remainingSeconds > 0 else { return }
    remainingSeconds -= 1
    if remainingSeconds == 0 {
      runState = .finished
      invalidateTimer()
      onFinish?()
    }
  }

  private func invalidateTimer() {
    timer?.invalidate()
    timer = nil
  }

  deinit {
    timer?.invalidate()
  }
}
