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

  private let bonjourClient: BonjourClient
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

  private static let maxReconnectDelay: TimeInterval = 30
  private static let keepAliveInterval: TimeInterval = 20

  init() {
    bonjourClient = BonjourClient()

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

  /// Mac探索〜WebSocket接続を開始する
  func connect() {
    isManuallyDisconnected = false
    reconnectWorkItem?.cancel()
    state = .searching
    bonjourClient.start()
  }

  func disconnect() {
    isManuallyDisconnected = true
    reconnectWorkItem?.cancel()
    stopKeepAlive()
    bonjourClient.stop()
    state = .disconnected
    hasPairedBefore = false
    isPairingInProgress = false
    isPairingReconnecting = false
    pendingPairingPin = nil
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
    pendingRequests[requestId] = completion
    send(ExecuteMessage(requestId: requestId, action: action))
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
    pendingRequests[id.uuidString] = completion
    send(PasteClipboardItemMessage(itemId: id))
  }

  // MARK: - トラックパッド（高頻度・一方向のためAckを待たない）

  func sendTrackpadMove(dx: Double, dy: Double) {
    send(TrackpadMoveMessage(dx: dx, dy: dy))
  }

  func sendTrackpadClick(button: String) {
    send(TrackpadClickMessage(button: button))
  }

  func sendTrackpadScroll(dx: Double, dy: Double) {
    send(TrackpadScrollMessage(dx: dx, dy: dy))
  }

  // MARK: - 接続ライフサイクル

  private func handleConnected() {
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
    startKeepAlive()
  }

  private func handleDisconnected() {
    stopKeepAlive()
    if isPairingInProgress {
      isPairingReconnecting = true
      state = .waitingForPairing
    } else {
      state = .disconnected
    }
    scheduleReconnectIfNeeded()
  }

  private func handleFailure(_ message: String) {
    stopKeepAlive()
    if isPairingInProgress {
      isPairingReconnecting = true
    }
    state = .failed(message)
    scheduleReconnectIfNeeded()
  }

  /// 切断時に指数バックオフで自動再接続する（ユーザーが明示的に切断した場合は行わない）
  private func scheduleReconnectIfNeeded() {
    guard !isManuallyDisconnected else { return }
    reconnectWorkItem?.cancel()

    let delay = min(pow(2.0, Double(reconnectAttempt)), Self.maxReconnectDelay)
    reconnectAttempt += 1

    let workItem = DispatchWorkItem { [weak self] in
      self?.connect()
    }
    reconnectWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
  }

  private func startKeepAlive() {
    stopKeepAlive()
    keepAliveTimer = Timer.scheduledTimer(withTimeInterval: Self.keepAliveInterval, repeats: true) { [weak self] _ in
      self?.bonjourClient.sendPing()
    }
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
