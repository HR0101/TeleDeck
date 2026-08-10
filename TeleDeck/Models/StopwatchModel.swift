//
//  StopwatchModel.swift
//  TeleDeck
//
//  0から加算していくストップウォッチのロジック。
//

import Foundation
import Observation

@Observable
final class StopwatchModel {
  private(set) var elapsedSeconds = 0
  private(set) var runState: TimerRunState = .idle

  private var timer: Timer?

  private static let tickInterval: TimeInterval = 1.0

  func start() {
    guard runState != .running else { return }
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
    elapsedSeconds = 0
    runState = .idle
  }

  private func scheduleTimer() {
    invalidateTimer()
    timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
      self?.elapsedSeconds += 1
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
