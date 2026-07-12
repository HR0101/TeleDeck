//
//  TrackpadView.swift
//  TeleDeck
//
//  iPadの指の動きでMacのマウスカーソルを操作する画面。
//

import SwiftUI

struct TrackpadView: View {
  let connectionManager: ConnectionManager

  @Environment(ThemeStore.self) private var themeStore

  var body: some View {
    VStack(spacing: 16) {
      Text("トラックパッド")
        .font(.headline)
        .foregroundStyle(GamingPalette.foreground)
        .padding(.top)

      RoundedRectangle(cornerRadius: 20)
        .fill(Color.clear)
        .gamingCard(accentColor: themeStore.accentColor, cornerRadius: 20)
        .overlay {
          VStack(spacing: 8) {
            Image(systemName: "hand.point.up.left")
              .font(.system(size: 40))
              .foregroundStyle(themeStore.accentColor)
            Text("1本指ドラッグ: カーソル移動 / 1本指タップ: 左クリック\n2本指タップ: 右クリック / 2本指ドラッグ: スクロール\n3本指スワイプ: 左右でスペース切替、上下でMission Control等")
              .font(.caption)
              .foregroundStyle(GamingPalette.mutedForeground)
              .multilineTextAlignment(.center)
          }
        }
        .overlay {
          TrackpadSurfaceView(
            onMove: { dx, dy in
              connectionManager.sendTrackpadMove(dx: dx, dy: dy)
            },
            onScroll: { dx, dy in
              connectionManager.sendTrackpadScroll(dx: dx, dy: dy)
            },
            onLeftClick: {
              connectionManager.sendTrackpadClick(button: "left")
            },
            onRightClick: {
              connectionManager.sendTrackpadClick(button: "right")
            },
            onThreeFingerSwipeLeft: {
              // 3本指左スワイプ = 次のスペースへ（Control+右矢印と同等）
              connectionManager.execute(ActionPayload(type: .hotkey, keys: ["ctrl", "right"]))
            },
            onThreeFingerSwipeRight: {
              // 3本指右スワイプ = 前のスペースへ（Control+左矢印と同等）
              connectionManager.execute(ActionPayload(type: .hotkey, keys: ["ctrl", "left"]))
            },
            onThreeFingerSwipeUp: {
              // 3本指上スワイプ = Mission Control（Control+上矢印と同等）
              connectionManager.execute(ActionPayload(type: .hotkey, keys: ["ctrl", "up"]))
            },
            onThreeFingerSwipeDown: {
              // 3本指下スワイプ = Application Exposé（Control+下矢印と同等）
              connectionManager.execute(ActionPayload(type: .hotkey, keys: ["ctrl", "down"]))
            }
          )
        }
        .padding()

      HStack(spacing: 24) {
        Button("左クリック") {
          connectionManager.sendTrackpadClick(button: "left")
        }
        .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor))

        Button("右クリック") {
          connectionManager.sendTrackpadClick(button: "right")
        }
        .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor))
      }
      .padding(.bottom)
    }
  }
}

#Preview {
  TrackpadView(connectionManager: ConnectionManager())
    .environment(ThemeStore())
}
