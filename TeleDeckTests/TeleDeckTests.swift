//
//  TeleDeckTests.swift
//  TeleDeckTests
//
//  Created by hara ryuto   on 2026/07/12.
//

import Foundation
import Testing
@testable import TeleDeck

struct TeleDeckTests {

  @Test func screenAwakeDefaultsToOff() throws {
    let suiteName = "TeleDeckTests.ThemeStore.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    userDefaults.removePersistentDomain(forName: suiteName)
    defer { userDefaults.removePersistentDomain(forName: suiteName) }

    let themeStore = ThemeStore(userDefaults: userDefaults)

    #expect(themeStore.keepsScreenAwake == false)
  }

  @Test func systemLowPowerModeFollowingDefaultsToOn() throws {
    let suiteName = "TeleDeckTests.LowPowerMode.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    userDefaults.removePersistentDomain(forName: suiteName)
    defer { userDefaults.removePersistentDomain(forName: suiteName) }

    let themeStore = ThemeStore(
      userDefaults: userDefaults,
      isSystemLowPowerModeEnabled: true
    )

    #expect(themeStore.followsSystemLowPowerMode)
    #expect(themeStore.isEnergySavingModeEnabled)
    #expect(!themeStore.shouldShowBackgroundGlow)

    themeStore.followsSystemLowPowerMode = false
    #expect(!themeStore.isEnergySavingModeEnabled)
  }

  @Test func connectionLifecycleSuspendsEnergyUsingWork() {
    let bonjourClient = BonjourClientSpy()
    let connectionManager = ConnectionManager(
      bonjourClient: bonjourClient,
      isLowPowerModeEnabled: false
    )

    connectionManager.setApplicationActive(true)
    #expect(bonjourClient.startCallCount == 1)

    bonjourClient.onConnected?()
    #expect(bonjourClient.stopBrowsingCallCount == 1)
    #expect(connectionManager.isKeepAliveRunning)

    connectionManager.setLowPowerModeEnabled(true)
    #expect(!connectionManager.isKeepAliveRunning)

    connectionManager.setLowPowerModeEnabled(false)
    #expect(connectionManager.isKeepAliveRunning)

    connectionManager.setApplicationActive(false)
    #expect(bonjourClient.stopCallCount == 1)
    #expect(!connectionManager.isKeepAliveRunning)

    connectionManager.setApplicationActive(true)
    #expect(bonjourClient.startCallCount == 2)
  }

  @Test func manualDisconnectDoesNotReconnectOnForeground() {
    let bonjourClient = BonjourClientSpy()
    let connectionManager = ConnectionManager(
      bonjourClient: bonjourClient,
      isLowPowerModeEnabled: false
    )

    connectionManager.setApplicationActive(true)
    connectionManager.disconnect()
    connectionManager.setApplicationActive(false)
    connectionManager.setApplicationActive(true)

    #expect(bonjourClient.startCallCount == 1)
  }

}

private final class BonjourClientSpy: BonjourClientProtocol {
  var onConnected: (() -> Void)?
  var onDisconnected: (() -> Void)?
  var onFailure: ((String) -> Void)?
  var onMessage: ((Data) -> Void)?

  private(set) var startCallCount = 0
  private(set) var stopBrowsingCallCount = 0
  private(set) var stopCallCount = 0
  private(set) var sentPingCount = 0

  func start() {
    startCallCount += 1
  }

  func stopBrowsing() {
    stopBrowsingCallCount += 1
  }

  func stop() {
    stopCallCount += 1
  }

  func send(data: Data) {}

  func sendPing() {
    sentPingCount += 1
  }

}
