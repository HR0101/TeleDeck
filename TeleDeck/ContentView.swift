//
//  ContentView.swift
//  TeleDeck
//
//  Created by hara ryuto   on 2026/07/12.
//

import Foundation
import SwiftUI
import UIKit

struct ContentView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var connectionManager = ConnectionManager()
  @State private var themeStore = ThemeStore()
  /// Mac接続に依存しない時計機能を、ペアリングなしでも単体で使えるようにするための表示状態
  @State private var isShowingStandaloneClock = false
  /// 再接続バナーを実際に表示するかどうか。connectionManager.stateを直接見ずにこれを介することで、
  /// 一瞬の瞬断では表示させず（デバウンス）、ペアリング状態に戻った瞬間は即座に消す
  @State private var isShowingReconnectBanner = false
  /// 表示保留中のバナーをキャンセルするための参照（.pairedへ戻った場合や状態が再度変わった場合に使う）
  @State private var reconnectBannerShowWorkItem: DispatchWorkItem?
  /// 初回起動時の案内を表示済みかどうか。Mac側アプリと権限が必要なことを先に伝える
  @AppStorage("onboarding.completed") private var hasCompletedOnboarding = false
  /// 再接続バナーを表示するまでの猶予時間。この秒数より短い瞬断ではバナーを点滅させない
  private static let reconnectBannerShowDelay: TimeInterval = 0.6

  var body: some View {
    LandscapeLayoutGuard {
      ZStack {
        GamingBackground(
          accentColor: themeStore.accentColor,
          showsGlow: themeStore.backgroundGlowEnabled
        )

        Group {
          // Mac側アプリと権限が必要なことを知らないまま探索画面だけを見せられても
          // 何をすればよいか分からないため、初回だけ手順を先に案内する
          if !hasCompletedOnboarding {
            OnboardingView {
              hasCompletedOnboarding = true
            }
          }
          // 一度ペアリング済みになった後の瞬断（Mac側アプリの再起動など）でPairingViewへ
          // 引き戻すと画面が点滅して見えるため、hasPairedBefore中は裏側で再接続を試みつつ
          // MainTabViewの表示を維持し、上部に小さな再接続バナーだけを出す
          else if connectionManager.state == .paired || connectionManager.hasPairedBefore {
            MainTabView(connectionManager: connectionManager)
              .overlay(alignment: .top) {
                if isShowingReconnectBanner {
                  reconnectingBanner
                }
              }
          } else {
            PairingView(connectionManager: connectionManager) {
              isShowingStandaloneClock = true
            }
          }
        }
      }
    }
    .environment(themeStore)
    .preferredColorScheme(themeStore.preferredColorScheme)
    .tint(themeStore.accentColor)
    .onAppear {
      applySystemLowPowerMode()
      connectionManager.setApplicationActive(scenePhase == .active)
      // 既にペアリング済みで起動した場合、バナーを一瞬たりとも点滅させないよう初期状態を合わせる
      updateReconnectBannerVisibility(for: connectionManager.state)
      applyIdleTimerSetting(isActive: scenePhase == .active)
    }
    .onChange(of: connectionManager.state) { _, newState in
      updateReconnectBannerVisibility(for: newState)
    }
    // 卓上に置いたまま画面が消灯するとデッキとして機能しないため、設定に応じて自動ロックを抑止する
    .onChange(of: themeStore.keepsScreenAwake) { _, _ in
      applyIdleTimerSetting()
    }
    .onChange(of: themeStore.followsSystemLowPowerMode) { _, _ in
      connectionManager.setLowPowerModeEnabled(themeStore.isEnergySavingModeEnabled)
      applyIdleTimerSetting(isActive: scenePhase == .active)
    }
    .onChange(of: scenePhase) { _, newPhase in
      let isActive = newPhase == .active
      // バックグラウンドでは画面点灯の抑止とネットワーク処理を止め、復帰時だけ再接続する
      applyIdleTimerSetting(isActive: isActive)
      connectionManager.setApplicationActive(isActive)
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
      applySystemLowPowerMode()
    }
    .fullScreenCover(isPresented: $isShowingStandaloneClock) {
      standaloneClock
    }
  }

  /// 設定と現在のシーン状態から、画面の自動ロックを抑止するかどうかを反映する
  private func applyIdleTimerSetting(isActive: Bool = true) {
    UIApplication.shared.isIdleTimerDisabled = themeStore.keepsScreenAwake
      && isActive
      && !themeStore.isEnergySavingModeEnabled
  }

  /// iPadの低電力モードを表示と接続管理へ同時に反映する。
  private func applySystemLowPowerMode() {
    themeStore.setSystemLowPowerModeEnabled(ProcessInfo.processInfo.isLowPowerModeEnabled)
    connectionManager.setLowPowerModeEnabled(themeStore.isEnergySavingModeEnabled)
    applyIdleTimerSetting(isActive: scenePhase == .active)
  }

  /// 再接続バナーの表示状態を接続状態に合わせて更新する。
  /// .pairedへ戻った場合は保留中の表示予約をキャンセルして即座に非表示にし、
  /// それ以外の状態はreconnectBannerShowDelay秒後まで表示を保留することで、
  /// 一瞬の瞬断がバナーの点滅として見えてしまうのを防ぐ
  private func updateReconnectBannerVisibility(for state: ConnectionManager.ConnectionState) {
    reconnectBannerShowWorkItem?.cancel()
    reconnectBannerShowWorkItem = nil

    guard state != .paired else {
      isShowingReconnectBanner = false
      return
    }

    let workItem = DispatchWorkItem {
      isShowingReconnectBanner = true
    }
    reconnectBannerShowWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.reconnectBannerShowDelay, execute: workItem)
  }

  /// ペアリング前でも単体で使える時計画面。MainTabView内と違い下部タブバーが無いため、
  /// 閉じてペアリング画面へ戻るためのボタンを重ねて表示する
  private var standaloneClock: some View {
    LandscapeLayoutGuard {
      ClockView()
        .environment(themeStore)
        .overlay(alignment: .topTrailing) {
          Button {
            isShowingStandaloneClock = false
          } label: {
            Image(systemName: "xmark.circle.fill")
              .symbolRenderingMode(.palette)
              .foregroundStyle(.white, .black.opacity(0.4))
              .font(.title2)
              .padding()
          }
          .accessibilityLabel("閉じる")
        }
    }
  }

  private var reconnectingBanner: some View {
    HStack(spacing: 8) {
      ProgressView()
        .tint(GamingPalette.foreground)
      Text("Macに再接続しています…")
        .font(.caption.weight(.medium))
        .foregroundStyle(GamingPalette.foreground)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .background(.ultraThinMaterial, in: Capsule())
    .overlay(Capsule().stroke(themeStore.accentColor.opacity(0.5), lineWidth: 1))
    .padding(.top, 8)
    .transition(.move(edge: .top).combined(with: .opacity))
    .animation(themeStore.isEnergySavingModeEnabled ? nil : .easeOut(duration: 0.2), value: isShowingReconnectBanner)
  }
}

/// TeleDeckの操作面は横向きで最適化しているため、縦向きではレイアウトを隠して
/// 端末を回転するまで明確な案内を表示する。Split Viewなど縦長のウインドウにも同じ判定を使う。
private struct LandscapeLayoutGuard<Content: View>: View {
  @Environment(ThemeStore.self) private var themeStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    GeometryReader { proxy in
      let isPortrait = proxy.size.height > proxy.size.width

      ZStack {
        content
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .accessibilityHidden(isPortrait)

        if isPortrait {
          portraitWarning
            .transition(.opacity)
            .zIndex(10)
        }
      }
      .animation(
        reduceMotion || themeStore.isEnergySavingModeEnabled ? nil : .easeOut(duration: 0.18),
        value: isPortrait
      )
    }
  }

  private var portraitWarning: some View {
    ZStack {
      GamingBackground(
        accentColor: themeStore.accentColor,
        showsGlow: false
      )

      VStack(spacing: 22) {
        ZStack {
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(themeStore.accentColor.opacity(0.16))
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(themeStore.accentColor.opacity(0.55), lineWidth: 1.5)
          Image(systemName: "ipad.landscape")
            .font(.system(size: 54, weight: .medium))
            .foregroundStyle(themeStore.accentColor)
        }
        .frame(width: 116, height: 92)

        VStack(spacing: 8) {
          Text("iPadを横向きにしてください")
            .font(.title2.weight(.bold))
            .foregroundStyle(GamingPalette.foreground)
          Text("TeleDeckは横向きでの操作に最適化されています")
            .font(.body)
            .foregroundStyle(GamingPalette.mutedForeground)
            .multilineTextAlignment(.center)
        }

        Label("画面を回転すると自動的に戻ります", systemImage: "rotate.right")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(themeStore.accentColor)
      }
      .padding(.horizontal, 44)
      .padding(.vertical, 38)
      .background(
        RoundedRectangle(cornerRadius: 30, style: .continuous)
          .fill(GamingPalette.card.opacity(0.92))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 30, style: .continuous)
          .stroke(themeStore.accentColor.opacity(0.45), lineWidth: 1)
      )
      .shadow(color: themeStore.accentColor.opacity(0.3), radius: 28)
      .padding(32)
    }
    .ignoresSafeArea()
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isModal)
  }
}

#Preview {
  ContentView()
}
