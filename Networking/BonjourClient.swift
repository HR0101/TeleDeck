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
  /// 現在接続中/接続済みのエンドポイント。NWBrowserのbrowseResultsChangedHandlerは
  /// 同じMacを指したままでも（Bonjourレコードの更新等により）何度も呼ばれることがあるため、
  /// 実際にエンドポイントが変わった場合のみ接続を張り直すよう、これと比較して重複接続を防ぐ
  private var currentEndpoint: NWEndpoint?

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
      guard let self else { return }
      // includePeerToPeerが有効なため、iPadとMacが同一Wi-Fiに加えてBluetooth/AWDLの
      // ピアツーピア圏内にもある場合（同室にいる時など）、NWBrowserは同じMacを
      // 経路ごとに異なる複数のNWEndpointとして報告することがある。resultsの並び順は
      // 電波状況等でこれら同等に有効なエンドポイント間で入れ替わることがあり、
      // 単純にresults.firstだけを見ると「Macが変わった」と誤認して、実際には
      // 生きている接続を切って張り直してしまう（＝再接続バナーが点滅する原因）。
      // そのため、現在のエンドポイントがresultsの中に残っている限りは何もしない
      if let currentEndpoint = self.currentEndpoint, results.contains(where: { $0.endpoint == currentEndpoint }) {
        return
      }
      // 同じエンドポイントへの再接続が繰り返されると、そのたびに既存の接続を切って
      // 張り直すことになり、状態が点滅してペアリング画面のPIN入力欄が
      // フォーカスを失う等の不安定さにつながるため、エンドポイントが実際に変わった時だけ接続する
      guard let firstResult = results.first, firstResult.endpoint != self.currentEndpoint else { return }
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
    currentEndpoint = nil
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

  /// Keep-Alive用にWebSocketのpingフレームを送信する（Mac側はautoReplyPingで自動応答する）
  func sendPing() {
    guard let connection else { return }
    let metadata = NWProtocolWebSocket.Metadata(opcode: .ping)
    let context = NWConnection.ContentContext(identifier: "ping", metadata: [metadata])
    connection.send(content: Data(), contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
  }

  // MARK: - 接続処理

  private func connect(to endpoint: NWEndpoint) {
    currentEndpoint = endpoint
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
