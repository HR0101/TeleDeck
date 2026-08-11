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

protocol BonjourClientProtocol: AnyObject {
  var onConnected: (() -> Void)? { get set }
  var onDisconnected: (() -> Void)? { get set }
  var onFailure: ((String) -> Void)? { get set }
  var onMessage: ((Data) -> Void)? { get set }

  func start()
  func stopBrowsing()
  func stop()
  func send(data: Data)
  func sendPing()
}

final class BonjourClient: BonjourClientProtocol {
  var onConnected: (() -> Void)?
  var onDisconnected: (() -> Void)?
  var onFailure: ((String) -> Void)?
  var onMessage: ((Data) -> Void)?

  private static let serviceType = "_teledeck._tcp"
  private static let peerToPeerFallbackDelay: TimeInterval = 4

  /// NWBrowser/NWConnectionと送受信をUI描画から分離する専用シリアルキュー。
  private let networkQueue = DispatchQueue(label: "TeleDeck.BonjourClient.network", qos: .utility)
  private var browser: NWBrowser?
  private var connection: NWConnection?
  private var peerToPeerFallbackWorkItem: DispatchWorkItem?
  private var isBrowsingWithPeerToPeer = false
  /// 現在接続中/接続済みのエンドポイント。NWBrowserのbrowseResultsChangedHandlerは
  /// 同じMacを指したままでも（Bonjourレコードの更新等により）何度も呼ばれることがあるため、
  /// 実際にエンドポイントが変わった場合のみ接続を張り直すよう、これと比較して重複接続を防ぐ
  private var currentEndpoint: NWEndpoint?

  /// Bonjour探索を開始する
  func start() {
    networkQueue.async { [weak self] in
      guard let self else { return }
      self.stopOnNetworkQueue()
      self.startBrowsingOnNetworkQueue(includePeerToPeer: false)
      self.schedulePeerToPeerFallbackOnNetworkQueue()
    }
  }

  func stop() {
    networkQueue.async { [weak self] in
      self?.stopOnNetworkQueue()
    }
  }

  /// 接続確立後はサービス探索が不要になるため、WebSocket接続を残したままBonjourだけ停止する。
  /// 接続が切れた場合はConnectionManagerがstart()を呼び、探索から再開する。
  func stopBrowsing() {
    networkQueue.async { [weak self] in
      self?.stopBrowsingOnNetworkQueue()
    }
  }

  func send(data: Data) {
    networkQueue.async { [weak self] in
      guard let self, let connection = self.connection else { return }
      let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
      let context = NWConnection.ContentContext(identifier: "message", metadata: [metadata])
      connection.send(
        content: data,
        contentContext: context,
        isComplete: true,
        completion: .contentProcessed { [weak self] error in
          if let error {
            self?.reportFailure("送信に失敗しました: \(error.localizedDescription)")
          }
        }
      )
    }
  }

  /// Keep-Alive用にWebSocketのpingフレームを送信する（Mac側はautoReplyPingで自動応答する）
  func sendPing() {
    networkQueue.async { [weak self] in
      guard let self, let connection = self.connection else { return }
      let metadata = NWProtocolWebSocket.Metadata(opcode: .ping)
      let context = NWConnection.ContentContext(identifier: "ping", metadata: [metadata])
      connection.send(
        content: Data(),
        contentContext: context,
        isComplete: true,
        completion: .contentProcessed { _ in }
      )
    }
  }

  // MARK: - 探索

  /// 同一Wi-Fiを先に探し、一定時間見つからない場合だけAWDL/Bluetoothを含む探索へ切り替える。
  private func startBrowsingOnNetworkQueue(includePeerToPeer: Bool) {
    browser?.cancel()
    browser = nil
    isBrowsingWithPeerToPeer = includePeerToPeer

    let browserParameters = NWParameters()
    browserParameters.includePeerToPeer = includePeerToPeer
    let newBrowser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: browserParameters)

    newBrowser.stateUpdateHandler = { [weak self, weak newBrowser] state in
      guard let self, let newBrowser, self.browser === newBrowser else { return }
      if case .failed(let error) = state {
        if includePeerToPeer {
          self.reportFailure("Macの探索に失敗しました: \(error.localizedDescription)")
        } else {
          self.startPeerToPeerFallbackOnNetworkQueue()
        }
      }
    }

    newBrowser.browseResultsChangedHandler = { [weak self, weak newBrowser] results, _ in
      guard let self, let newBrowser, self.browser === newBrowser else { return }
      if let currentEndpoint = self.currentEndpoint, results.contains(where: { $0.endpoint == currentEndpoint }) {
        return
      }
      guard let firstResult = results.first, firstResult.endpoint != self.currentEndpoint else { return }
      self.connectOnNetworkQueue(
        to: firstResult.endpoint,
        includePeerToPeer: includePeerToPeer
      )
    }

    browser = newBrowser
    newBrowser.start(queue: networkQueue)
  }

  private func schedulePeerToPeerFallbackOnNetworkQueue() {
    peerToPeerFallbackWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      self?.startPeerToPeerFallbackOnNetworkQueue()
    }
    peerToPeerFallbackWorkItem = workItem
    networkQueue.asyncAfter(
      deadline: .now() + Self.peerToPeerFallbackDelay,
      execute: workItem
    )
  }

  private func startPeerToPeerFallbackOnNetworkQueue() {
    guard !isBrowsingWithPeerToPeer else { return }
    peerToPeerFallbackWorkItem?.cancel()
    peerToPeerFallbackWorkItem = nil

    // 通常Wi-Fiで接続試行中の場合も一度破棄し、Peer-to-Peerを許可した条件で探し直す。
    let oldConnection = connection
    connection = nil
    currentEndpoint = nil
    oldConnection?.cancel()
    startBrowsingOnNetworkQueue(includePeerToPeer: true)
  }

  private func stopBrowsingOnNetworkQueue() {
    peerToPeerFallbackWorkItem?.cancel()
    peerToPeerFallbackWorkItem = nil
    let oldBrowser = browser
    browser = nil
    oldBrowser?.cancel()
  }

  private func stopOnNetworkQueue() {
    stopBrowsingOnNetworkQueue()
    let oldConnection = connection
    connection = nil
    currentEndpoint = nil
    oldConnection?.cancel()
  }

  // MARK: - 接続処理

  private func connectOnNetworkQueue(to endpoint: NWEndpoint, includePeerToPeer: Bool) {
    currentEndpoint = endpoint
    let oldConnection = connection
    connection = nil
    oldConnection?.cancel()

    let webSocketOptions = NWProtocolWebSocket.Options()
    webSocketOptions.autoReplyPing = true

    let parameters = NWParameters.tcp
    parameters.includePeerToPeer = includePeerToPeer
    parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)

    let newConnection = NWConnection(to: endpoint, using: parameters)

    newConnection.stateUpdateHandler = { [weak self, weak newConnection] state in
      guard let self,
            let newConnection,
            self.connection === newConnection else { return }
      switch state {
      case .ready:
        self.peerToPeerFallbackWorkItem?.cancel()
        self.peerToPeerFallbackWorkItem = nil
        self.reportConnected()
        self.receiveNextMessageOnNetworkQueue(from: newConnection)
      case .failed(let error):
        self.connection = nil
        self.currentEndpoint = nil
        if includePeerToPeer {
          self.reportFailure("接続に失敗しました: \(error.localizedDescription)")
        } else {
          self.startPeerToPeerFallbackOnNetworkQueue()
        }
      case .cancelled:
        self.connection = nil
        self.currentEndpoint = nil
        self.reportDisconnected()
      default:
        break
      }
    }

    connection = newConnection
    newConnection.start(queue: networkQueue)
  }

  private func receiveNextMessageOnNetworkQueue(from activeConnection: NWConnection) {
    activeConnection.receiveMessage { [weak self, weak activeConnection] data, _, _, error in
      guard let self,
            let activeConnection,
            self.connection === activeConnection else { return }

      if let error {
        self.connection = nil
        self.currentEndpoint = nil
        activeConnection.cancel()
        self.reportFailure("受信に失敗しました: \(error.localizedDescription)")
        return
      }

      if let data, !data.isEmpty {
        self.reportMessage(data)
      }

      if activeConnection.state == .ready {
        self.receiveNextMessageOnNetworkQueue(from: activeConnection)
      }
    }
  }

  // MARK: - メインキューへの通知

  private func reportConnected() {
    DispatchQueue.main.async { [weak self] in
      self?.onConnected?()
    }
  }

  private func reportDisconnected() {
    DispatchQueue.main.async { [weak self] in
      self?.onDisconnected?()
    }
  }

  private func reportFailure(_ message: String) {
    DispatchQueue.main.async { [weak self] in
      self?.onFailure?(message)
    }
  }

  private func reportMessage(_ data: Data) {
    DispatchQueue.main.async { [weak self] in
      self?.onMessage?(data)
    }
  }
}
