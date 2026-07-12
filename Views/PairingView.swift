//
//  PairingView.swift
//  TeleDeck
//
//  Mac探索中〜ペアリング完了までの状態を表示する画面。
//

import SwiftUI

struct PairingView: View {
  let connectionManager: ConnectionManager

  @Environment(ThemeStore.self) private var themeStore
  @State private var pinInput: String = ""

  var body: some View {
    VStack(spacing: 24) {
      Image(systemName: "wifi")
        .font(.system(size: 48))
        .foregroundStyle(themeStore.accentColor)

      statusText

      if isWaitingForPairing {
        VStack(spacing: 12) {
          TextField("Macに表示されたPINを入力", text: $pinInput)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .foregroundStyle(GamingPalette.foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .gamingCard(accentColor: themeStore.accentColor, cornerRadius: 10)
            .frame(maxWidth: 200)

          Button("接続する") {
            connectionManager.pair(pin: pinInput)
          }
          .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor))
          .disabled(pinInput.count != 6)
        }
      }

      if case .failed = connectionManager.state {
        Button("再試行") {
          connectionManager.connect()
        }
        .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor))
      }
    }
    .padding()
  }

  private var isWaitingForPairing: Bool {
    if case .waitingForPairing = connectionManager.state {
      return true
    }
    return false
  }

  @ViewBuilder
  private var statusText: some View {
    switch connectionManager.state {
    case .disconnected, .searching:
      Text("Macを探しています…")
        .foregroundStyle(GamingPalette.mutedForeground)
    case .resuming:
      Text("前回の接続情報で再接続しています…")
        .foregroundStyle(GamingPalette.mutedForeground)
    case .waitingForPairing:
      Text("Mac側に表示されたPINを入力してください")
        .foregroundStyle(GamingPalette.foreground)
    case .paired:
      Text("接続済み")
        .foregroundStyle(GamingPalette.foreground)
    case .failed(let message):
      Text(message)
        .foregroundStyle(GamingPalette.destructive)
    }
  }
}

#Preview {
  PairingView(connectionManager: ConnectionManager())
    .environment(ThemeStore())
}
