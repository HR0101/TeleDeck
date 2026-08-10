//
//  PairingView.swift
//  TeleDeck
//
//  Mac探索中〜ペアリング完了までの状態を表示する画面。
//

import SwiftUI

struct PairingView: View {
  let connectionManager: ConnectionManager
  /// Macとのペアリングなしでも、Mac接続に依存しない時計機能だけは単体で使えるようにする入口
  var onOpenClock: () -> Void

  @Environment(ThemeStore.self) private var themeStore
  @State private var pinInput: String = ""
  /// QR読み取りシートの表示状態
  @State private var isShowingScanner = false

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

          Button(connectionManager.isPairingReconnecting ? "再接続後に登録" : "接続する") {
            connectionManager.pair(pin: pinInput)
          }
          .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor))
          .disabled(pinInput.filter(\.isNumber).count != 6 || connectionManager.isPairingReconnecting)

          Text("または")
            .font(.caption)
            .foregroundStyle(GamingPalette.mutedForeground)

          Button {
            isShowingScanner = true
          } label: {
            Label("QRコードで接続", systemImage: "qrcode.viewfinder")
          }
          .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor))
          .disabled(connectionManager.isPairingReconnecting)
        }
      }

      if case .failed = connectionManager.state, !connectionManager.isPairingInProgress {
        Button("再試行") {
          connectionManager.connect()
        }
        .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor))
      }

      Divider()
        .frame(maxWidth: 200)

      Button {
        onOpenClock()
      } label: {
        Label("時計だけ使う", systemImage: "clock")
          .font(.subheadline)
      }
      .foregroundStyle(GamingPalette.mutedForeground)
    }
    .padding()
    .sheet(isPresented: $isShowingScanner) {
      QRScannerSheet { pin in
        // 手入力欄にも反映しておくと、接続に失敗したときそのまま「接続する」で再試行できる
        pinInput = pin
        connectionManager.pair(pin: pin)
      }
    }
  }

  private var isWaitingForPairing: Bool {
    if connectionManager.isPairingInProgress { return true }
    if case .waitingForPairing = connectionManager.state { return true }
    if case .failed = connectionManager.state { return true }
    return false
  }

  @ViewBuilder
  private var statusText: some View {
    switch connectionManager.state {
    case .disconnected, .searching:
      Text(connectionManager.isPairingInProgress
        ? "接続が切れました。PINを保持してMacへ再接続しています…"
        : "Macを探しています…")
        .foregroundStyle(GamingPalette.mutedForeground)
    case .resuming:
      Text("前回の接続情報で再接続しています…")
        .foregroundStyle(GamingPalette.mutedForeground)
    case .waitingForPairing:
      Text(connectionManager.isPairingReconnecting
        ? "接続が切れました。PINを保持したまま再接続しています…"
        : "Mac側に表示されたPINを入力してください")
        .foregroundStyle(GamingPalette.foreground)
    case .paired:
      Text("接続済み")
        .foregroundStyle(GamingPalette.foreground)
    case .failed(let message):
      Text(connectionManager.isPairingInProgress
        ? "\(message)\n接続が戻るまでPINを保持します。"
        : message)
        .foregroundStyle(GamingPalette.destructive)
    }
  }
}

#Preview {
  PairingView(connectionManager: ConnectionManager(), onOpenClock: {})
    .environment(ThemeStore())
}
