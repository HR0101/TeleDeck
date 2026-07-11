//
//  BonjourClient.swift
//  TeleDeck
//
//  Bonjourで`_teledeck._tcp`を探索し、発見したMacと直接WebSocket接続を確立するクラス。
//  Mac側（BonjourServer）と対称的に、NWConnectionへ直接WebSocketオプションを載せて接続する。
//  文字列のURLを経由しないため、IPv6リンクローカルアドレス（ゾーンID付き）でも問題なく接続できる。
//

import Foundation
import Network

final class BonjourClient {
  var onConnected: (() -> Void)?
  var onDisconnected: (() -> Void)?
  var onFailure: ((String) -> Void)?
  var onMessage: ((Data) -> Void)?

  private static let serviceType = "_teledeck._tcp"

  private var browser: NWBrowser?
  private var connection: NWConnection?

  /// Bonjour探索を開始する
  func start() {
    stop()

    let browserParameters = NWParameters()
    browserParameters.includePeerToPeer = true
    let newBrowser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: browserParameters)

    newBrowser.stateUpdateHandler = { [weak self] state in
      if case .failed(let error) = state {
        self?.onFailure?("Macの探索に失敗しました: \(error.localizedDescription)")
      }
    }

    newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
      guard let self, let firstResult = results.first else { return }
      self.connect(to: firstResult.endpoint)
    }

    newBrowser.start(queue: .main)
    browser = newBrowser
  }

  func stop() {
    browser?.cancel()
    browser = nil
    connection?.cancel()
    connection = nil
  }

  func send(data: Data) {
    guard let connection else { return }
    let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
    let context = NWConnection.ContentContext(identifier: "message", metadata: [metadata])
    connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { [weak self] error in
      if let error {
        self?.onFailure?("送信に失敗しました: \(error.localizedDescription)")
      }
    })
  }

  // MARK: - 接続処理

  private func connect(to endpoint: NWEndpoint) {
    connection?.cancel()

    let webSocketOptions = NWProtocolWebSocket.Options()
    webSocketOptions.autoReplyPing = true

    let parameters = NWParameters.tcp
    parameters.includePeerToPeer = true
    parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)

    let newConnection = NWConnection(to: endpoint, using: parameters)

    newConnection.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .ready:
        self.onConnected?()
        self.receiveNextMessage()
      case .failed(let error):
        self.onFailure?("接続に失敗しました: \(error.localizedDescription)")
      case .cancelled:
        self.onDisconnected?()
      default:
        break
      }
    }

    newConnection.start(queue: .main)
    connection = newConnection
  }

  private func receiveNextMessage() {
    connection?.receiveMessage { [weak self] data, _, _, error in
      guard let self else { return }

      if let error {
        self.onFailure?("受信に失敗しました: \(error.localizedDescription)")
        return
      }

      if let data, !data.isEmpty {
        self.onMessage?(data)
      }

      if self.connection?.state == .ready {
        self.receiveNextMessage()
      }
    }
  }
}
