//
//  ConnectionManager.swift
//  TeleDeck
//
//  Mac側との接続状態・ペアリング状態を管理し、Viewからの唯一の窓口となるクラス。
//  保存済みトークンによる自動再ペアリング、切断時の自動再接続、Keep-Alive pingにも対応する。
//

import Foundation
import Observation
import UIKit

@Observable
final class ConnectionManager {

  enum ConnectionState: Equatable {
    case disconnected
    case searching
    /// 保存済みトークンでの自動再ペアリングを試行中
    case resuming
    case waitingForPairing
    case paired
    case failed(String)
  }

  private(set) var state: ConnectionState = .disconnected

  /// Macへ操作を送れる状態か。切断中は送信内容が黙って捨てられるため、
  /// Viewはこの値を見て操作を止めるか、送れないことを明示する
  var isConnected: Bool { state == .paired }
  /// このセッション中に一度でもペアリングに成功したか。
  /// Mac側アプリの再起動などで一瞬切断された際に、ペアリング画面へ引き戻さず
  /// MainTabViewを維持したまま裏側で再接続できるようにするためのフラグ
  private(set) var hasPairedBefore = false
  /// PIN送信後のペアリング状態を保持する。瞬断しても入力欄を消さず、再接続後に自動再送する。
  private(set) var isPairingInProgress = false
  private(set) var isPairingReconnecting = false
  private var pendingPairingPin: String?

  /// Macから最新のプロファイル一覧が届いたときに呼ばれる（Macがプロファイル設定の本体のため）
  var onProfileSync: (([ProfileConfig], UUID) -> Void)?

  /// Macから最新のコピー履歴一覧が届いたときに呼ばれる（新規コピー検知時・取得要求への応答の両方でこの経路を通る）
  var onClipboardHistory: (([ClipboardHistoryEntry]) -> Void)?

  private let bonjourClient: any BonjourClientProtocol
  private var pendingRequests: [String: (Result<Void, Error>) -> Void] = [:]
  private var pendingTabsCompletion: (([TabInfo], [MacApplicationInfo]) -> Void)?
  private var pendingApplicationsCompletion: (([MacApplicationInfo]) -> Void)?
  private var pendingFolderSelectionCompletion: ((String?) -> Void)?
  private let deviceName = UIDevice.current.name

  /// ユーザー操作による切断かどうか（自動再接続を行うかどうかの判定に使う）
  private var isManuallyDisconnected = false
  private var reconnectAttempt = 0
  private var reconnectWorkItem: DispatchWorkItem?
  private var keepAliveTimer: Timer?
  private var trackpadFlushWorkItem: DispatchWorkItem?
  private var pendingTrackpadMove = (dx: 0.0, dy: 0.0)
  private var pendingTrackpadScroll = (dx: 0.0, dy: 0.0)
  private var isApplicationActive = false
  private var isLowPowerModeEnabled: Bool
  private var isTransportConnected = false

  private static let maxReconnectDelay: TimeInterval = 30
  private static let keepAliveInterval: TimeInterval = 120
  private static let keepAliveTolerance: TimeInterval = 30
  private static let normalTrackpadSendInterval: TimeInterval = 1.0 / 60.0
  private static let lowPowerTrackpadSendInterval: TimeInterval = 1.0 / 30.0
  /// ack（実行結果）を待つ上限時間。Macが応答できない状態でも、
  /// UIが「実行中」のまま固まらないようにするために設ける
  private static let requestTimeout: TimeInterval = 5

  /// Keep-Aliveが現在動作中か。接続ライフサイクルの診断とテストに利用する。
  var isKeepAliveRunning: Bool { keepAliveTimer != nil }

  init(
    bonjourClient: any BonjourClientProtocol = BonjourClient(),
    isLowPowerModeEnabled: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
  ) {
    self.bonjourClient = bonjourClient
    self.isLowPowerModeEnabled = isLowPowerModeEnabled

    bonjourClient.onConnected = { [weak self] in
      self?.handleConnected()
    }
    bonjourClient.onDisconnected = { [weak self] in
      self?.handleDisconnected()
    }
    bonjourClient.onFailure = { [weak self] message in
      self?.handleFailure(message)
    }
    bonjourClient.onMessage = { [weak self] data in
      self?.handleIncoming(data: data)
    }
  }

  deinit {
    reconnectWorkItem?.cancel()
    keepAliveTimer?.invalidate()
    trackpadFlushWorkItem?.cancel()
    bonjourClient.stop()
  }

  /// Mac探索〜WebSocket接続を開始する
  func connect() {
    guard isApplicationActive else { return }
    isManuallyDisconnected = false
    reconnectWorkItem?.cancel()
    reconnectWorkItem = nil
    stopKeepAlive()
    discardPendingTrackpadEvents()
    isTransportConnected = false
    state = .searching
    bonjourClient.start()
  }

  /// SwiftUIのscenePhaseに合わせてネットワーク処理を開始・停止する。
  /// 非アクティブ時は探索・接続・再接続予約をすべて解放し、復帰時だけ自動再接続する。
  func setApplicationActive(_ isActive: Bool) {
    guard isApplicationActive != isActive else {
      if isActive {
        startKeepAliveIfNeeded()
      }
      return
    }

    isApplicationActive = isActive

    if isActive {
      guard !isManuallyDisconnected else { return }
      connect()
    } else {
      reconnectWorkItem?.cancel()
      reconnectWorkItem = nil
      stopKeepAlive()
      discardPendingTrackpadEvents()
      isTransportConnected = false
      bonjourClient.stop()
      state = .disconnected
    }
  }

  /// 低電力モード中はWebSocket接続を維持しつつ、定期的なKeep-Alive送信だけを止める。
  func setLowPowerModeEnabled(_ isEnabled: Bool) {
    guard isLowPowerModeEnabled != isEnabled else { return }
    isLowPowerModeEnabled = isEnabled

    if isEnabled {
      stopKeepAlive()
    } else {
      startKeepAliveIfNeeded()
    }

    // 次の送信から新しい上限レートを確実に適用する。
    if trackpadFlushWorkItem != nil {
      trackpadFlushWorkItem?.cancel()
      trackpadFlushWorkItem = nil
      scheduleTrackpadFlushIfNeeded()
    }
  }

  func disconnect() {
    isManuallyDisconnected = true
    reconnectWorkItem?.cancel()
    reconnectWorkItem = nil
    stopKeepAlive()
    discardPendingTrackpadEvents()
    isTransportConnected = false
    bonjourClient.stop()
    state = .disconnected
    hasPairedBefore = false
    isPairingInProgress = false
    isPairingReconnecting = false
    pendingPairingPin = nil
  }

  /// 保存済みの接続情報を破棄し、PIN入力からのペアリングをやり直す。
  /// Mac側の信頼済みデバイス登録はそのまま残るが、トークンを失うため再度PINが必要になる
  func unpair() {
    KeychainTokenStore.delete()
    reconnectWorkItem?.cancel()
    reconnectWorkItem = nil
    stopKeepAlive()
    discardPendingTrackpadEvents()
    isTransportConnected = false
    bonjourClient.stop()
    hasPairedBefore = false
    isPairingInProgress = false
    isPairingReconnecting = false
    pendingPairingPin = nil
    state = .disconnected
    connect()
  }

  /// PINを送信してペアリングを行う
  func pair(pin: String) {
    let normalizedPin = pin.filter(\.isNumber)
    guard normalizedPin.count == 6 else { return }
    pendingPairingPin = normalizedPin
    isPairingInProgress = true
    isPairingReconnecting = false
    send(PairMessage(deviceName: deviceName, pin: normalizedPin))
  }

  /// アクションの実行をMacへ依頼する
  func execute(_ action: ActionPayload, completion: @escaping (Result<Void, Error>) -> Void = { _ in }) {
    let requestId = UUID().uuidString
    registerPendingRequest(id: requestId, completion: completion)
    send(ExecuteMessage(requestId: requestId, action: action))
  }

  /// 応答待ちのリクエストを登録し、requestTimeout秒以内にackが返らなければ失敗として完了させる。
  /// 併せてpendingRequestsからも取り除くため、応答の来ない要求が溜まり続けることもない
  private func registerPendingRequest(id: String, completion: @escaping (Result<Void, Error>) -> Void) {
    pendingRequests[id] = completion

    DispatchQueue.main.asyncAfter(deadline: .now() + Self.requestTimeout) { [weak self] in
      guard let self,
            let timedOutCompletion = self.pendingRequests.removeValue(forKey: id) else { return }
      let error = NSError(
        domain: "TeleDeck",
        code: -2,
        userInfo: [NSLocalizedDescriptionKey: "Macから応答がありません。接続を確認してください"]
      )
      timedOutCompletion(.failure(error))
    }
  }

  /// Mac側の開いているタブ一覧を取得する
  func requestTabs(completion: @escaping ([TabInfo], [MacApplicationInfo]) -> Void) {
    pendingTabsCompletion = completion
    send(GetTabsMessage())
  }

  /// Mac側で起動中のアプリケーション一覧を取得する
  func requestApplications(completion: @escaping ([MacApplicationInfo]) -> Void) {
    pendingApplicationsCompletion = completion
    send(GetApplicationsMessage())
  }

  /// MacのNSOpenPanelでフォルダーを選択してもらう。iPadからMacのパスを手入力する必要をなくす。
  func requestFolderSelection(completion: @escaping (String?) -> Void) {
    pendingFolderSelectionCompletion = completion
    send(PickFolderMessage())
  }

  /// iPad側での編集内容をMac（プロファイル設定の本体）へ反映依頼する
  func sendProfileUpdate(profiles: [ProfileConfig], activeProfileId: UUID) {
    send(UpdateProfilesMessage(profiles: profiles, activeProfileId: activeProfileId))
  }

  /// Mac側の現在のコピー履歴一覧を取得する
  func requestClipboardHistory() {
    send(GetClipboardHistoryMessage())
  }

  /// 指定した履歴アイテムをMacのクリップボードにセットし、貼り付けまで実行するよう依頼する
  func pasteClipboardItem(id: UUID, completion: @escaping (Result<Void, Error>) -> Void = { _ in }) {
    registerPendingRequest(id: id.uuidString, completion: completion)
    send(PasteClipboardItemMessage(itemId: id))
  }

  // MARK: - トラックパッド（高頻度・一方向のためAckを待たない）

  func sendTrackpadMove(dx: Double, dy: Double) {
    guard isTransportConnected, dx != 0 || dy != 0 else { return }
    pendingTrackpadMove.dx += dx
    pendingTrackpadMove.dy += dy
    scheduleTrackpadFlushIfNeeded()
  }

  func sendTrackpadClick(button: String) {
    guard isTransportConnected else { return }
    // 最後の移動よりクリックが先にMacへ届かないよう、保留中の移動を先に送る。
    flushPendingTrackpadEvents()
    send(TrackpadClickMessage(button: button))
  }

  func sendTrackpadScroll(dx: Double, dy: Double) {
    guard isTransportConnected, dx != 0 || dy != 0 else { return }
    pendingTrackpadScroll.dx += dx
    pendingTrackpadScroll.dy += dy
    scheduleTrackpadFlushIfNeeded()
  }

  /// イベントごとのJSON生成を避け、1フレーム分の移動量を1メッセージへまとめる。
  /// 待機WorkItemは常に1つだけなので、古いイベントが送信キューへ蓄積しない。
  private func scheduleTrackpadFlushIfNeeded() {
    guard trackpadFlushWorkItem == nil, hasPendingTrackpadEvents else { return }

    let interval = isLowPowerModeEnabled
      ? Self.lowPowerTrackpadSendInterval
      : Self.normalTrackpadSendInterval
    let workItem = DispatchWorkItem { [weak self] in
      self?.flushPendingTrackpadEvents()
    }
    trackpadFlushWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: workItem)
  }

  private var hasPendingTrackpadEvents: Bool {
    pendingTrackpadMove.dx != 0 || pendingTrackpadMove.dy != 0
      || pendingTrackpadScroll.dx != 0 || pendingTrackpadScroll.dy != 0
  }

  private func flushPendingTrackpadEvents() {
    trackpadFlushWorkItem?.cancel()
    trackpadFlushWorkItem = nil

    guard isApplicationActive, isTransportConnected else {
      discardPendingTrackpadEvents()
      return
    }

    let move = pendingTrackpadMove
    let scroll = pendingTrackpadScroll
    pendingTrackpadMove = (0, 0)
    pendingTrackpadScroll = (0, 0)

    if move.dx != 0 || move.dy != 0 {
      send(TrackpadMoveMessage(dx: move.dx, dy: move.dy))
    }
    if scroll.dx != 0 || scroll.dy != 0 {
      send(TrackpadScrollMessage(dx: scroll.dx, dy: scroll.dy))
    }
  }

  private func discardPendingTrackpadEvents() {
    trackpadFlushWorkItem?.cancel()
    trackpadFlushWorkItem = nil
    pendingTrackpadMove = (0, 0)
    pendingTrackpadScroll = (0, 0)
  }

  // MARK: - 接続ライフサイクル

  private func handleConnected() {
    guard isApplicationActive else {
      bonjourClient.stop()
      return
    }

    isTransportConnected = true
    // WebSocket確立後はBonjour探索を続ける必要がないため、接続だけを残して探索を停止する。
    bonjourClient.stopBrowsing()
    reconnectAttempt = 0
    isPairingReconnecting = false
    if let savedToken = KeychainTokenStore.load() {
      state = .resuming
      send(ResumeSessionMessage(token: savedToken))
    } else {
      state = .waitingForPairing
      if isPairingInProgress, let pendingPairingPin {
        // WebSocketのready通知直後に送信すると、NWConnectionの書き込みキューが
        // 切り替え中のことがあるため、次のrun loopで再送する。
        DispatchQueue.main.async { [weak self] in
          guard let self, self.isPairingInProgress else { return }
          self.send(PairMessage(deviceName: self.deviceName, pin: pendingPairingPin))
        }
      }
    }
    startKeepAliveIfNeeded()
  }

  private func handleDisconnected() {
    isTransportConnected = false
    stopKeepAlive()
    discardPendingTrackpadEvents()
    guard isApplicationActive else {
      state = .disconnected
      return
    }
    if isPairingInProgress {
      isPairingReconnecting = true
      state = .waitingForPairing
    } else {
      state = .disconnected
    }
    scheduleReconnectIfNeeded()
  }

  private func handleFailure(_ message: String) {
    isTransportConnected = false
    stopKeepAlive()
    discardPendingTrackpadEvents()
    guard isApplicationActive else {
      state = .disconnected
      return
    }
    if isPairingInProgress {
      isPairingReconnecting = true
    }
    state = .failed(message)
    scheduleReconnectIfNeeded()
  }

  /// 切断時に指数バックオフで自動再接続する（ユーザーが明示的に切断した場合は行わない）
  private func scheduleReconnectIfNeeded() {
    guard isApplicationActive, !isManuallyDisconnected else { return }
    reconnectWorkItem?.cancel()

    let delay = min(pow(2.0, Double(reconnectAttempt)), Self.maxReconnectDelay)
    reconnectAttempt += 1

    let workItem = DispatchWorkItem { [weak self] in
      guard let self, self.isApplicationActive, !self.isManuallyDisconnected else { return }
      self.connect()
    }
    reconnectWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
  }

  private func startKeepAliveIfNeeded() {
    guard isApplicationActive,
          !isLowPowerModeEnabled,
          isTransportConnected,
          keepAliveTimer == nil else { return }

    let timer = Timer.scheduledTimer(withTimeInterval: Self.keepAliveInterval, repeats: true) { [weak self] _ in
      self?.bonjourClient.sendPing()
    }
    timer.tolerance = Self.keepAliveTolerance
    keepAliveTimer = timer
  }

  private func stopKeepAlive() {
    keepAliveTimer?.invalidate()
    keepAliveTimer = nil
  }

  // MARK: - 送受信

  private func send<T: Encodable>(_ message: T) {
    do {
      let data = try JSONEncoder().encode(message)
      bonjourClient.send(data: data)
    } catch {
      state = .failed("送信に失敗しました: \(error.localizedDescription)")
    }
  }

  private func handleIncoming(data: Data) {
    do {
      let envelope = try JSONDecoder().decode(MessageEnvelope.self, from: data)
      switch envelope.type {
      case "pairResult":
        let response = try JSONDecoder().decode(PairResultMessage.self, from: data)
        handlePairResult(response)
      case "ack":
        let response = try JSONDecoder().decode(AckMessage.self, from: data)
        handleAck(response)
      case "profileSync":
        let message = try JSONDecoder().decode(ProfileSyncMessage.self, from: data)
        onProfileSync?(message.profiles, message.activeProfileId)
      case "tabsList":
        let message = try JSONDecoder().decode(TabsListMessage.self, from: data)
        pendingTabsCompletion?(message.tabs, message.applications ?? [])
        pendingTabsCompletion = nil
      case "applicationsList":
        let message = try JSONDecoder().decode(ApplicationsListMessage.self, from: data)
        pendingApplicationsCompletion?(message.applications)
        pendingApplicationsCompletion = nil
      case "folderSelection":
        let message = try JSONDecoder().decode(FolderSelectionMessage.self, from: data)
        pendingFolderSelectionCompletion?(message.path)
        pendingFolderSelectionCompletion = nil
      case "clipboardHistory":
        let message = try JSONDecoder().decode(ClipboardHistoryMessage.self, from: data)
        onClipboardHistory?(message.items)
      default:
        break
      }
    } catch {
      print("受信メッセージの解析に失敗しました: \(error.localizedDescription)")
    }
  }

  private func handlePairResult(_ response: PairResultMessage) {
    if response.success {
      if let token = response.token {
        KeychainTokenStore.save(token)
      }
      state = .paired
      hasPairedBefore = true
      isPairingInProgress = false
      isPairingReconnecting = false
      pendingPairingPin = nil
    } else if state == .resuming {
      // 保存済みトークンが無効だった場合はPIN入力へフォールバックする（新規ペアリングが必要なため
      // MainTabViewを維持する必要はなく、通常通りペアリング画面へ戻す）
      KeychainTokenStore.delete()
      state = .waitingForPairing
      hasPairedBefore = false
      isPairingInProgress = false
      isPairingReconnecting = false
      pendingPairingPin = nil
    } else {
      isPairingInProgress = false
      isPairingReconnecting = false
      state = .failed(response.errorMessage ?? "ペアリングに失敗しました")
    }
  }

  private func handleAck(_ response: AckMessage) {
    let completion = pendingRequests.removeValue(forKey: response.requestId)
    if response.success {
      completion?(.success(()))
    } else {
      let error = NSError(
        domain: "TeleDeck",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: response.errorMessage ?? "実行に失敗しました"]
      )
      completion?(.failure(error))
    }
  }
}
