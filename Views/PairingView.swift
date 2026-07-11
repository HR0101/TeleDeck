//
//  PairingView.swift
//  TeleDeck
//
//  Mac探索中〜ペアリング完了までの状態を表示する画面。
//

import SwiftUI

struct PairingView: View {
  let connectionManager: ConnectionManager
  @State private var pinInput: String = ""

  var body: some View {
    VStack(spacing: 24) {
      Image(systemName: "wifi")
        .font(.system(size: 48))
        .foregroundStyle(.secondary)

      statusText

      if isWaitingForPairing {
        VStack(spacing: 12) {
          TextField("Macに表示されたPINを入力", text: $pinInput)
            .textFieldStyle(.roundedBorder)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 200)

          Button("接続する") {
            connectionManager.pair(pin: pinInput)
          }
          .buttonStyle(.borderedProminent)
          .disabled(pinInput.count != 6)
        }
      }

      if case .failed = connectionManager.state {
        Button("再試行") {
          connectionManager.connect()
        }
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
    case .waitingForPairing:
      Text("Mac側に表示されたPINを入力してください")
    case .paired:
      Text("接続済み")
    case .failed(let message):
      Text(message)
        .foregroundStyle(.red)
    }
  }
}

#Preview {
  PairingView(connectionManager: ConnectionManager())
}
