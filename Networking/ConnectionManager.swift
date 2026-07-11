//
//  ConnectionManager.swift
//  TeleDeck
//
//  Mac側との接続状態・ペアリング状態を管理し、Viewからの唯一の窓口となるクラス。
//

import Foundation
import Observation
import UIKit

@Observable
final class ConnectionManager {

  enum ConnectionState: Equatable {
    case disconnected
    case searching
    case waitingForPairing
    case paired
    case failed(String)
  }

  private(set) var state: ConnectionState = .disconnected

  private let bonjourClient: BonjourClient
  private var sessionToken: String?
  private var pendingRequests: [String: (Result<Void, Error>) -> Void] = [:]
  private let deviceName = UIDevice.current.name

  init() {
    bonjourClient = BonjourClient()

    bonjourClient.onConnected = { [weak self] in
      self?.state = .waitingForPairing
    }
    bonjourClient.onDisconnected = { [weak self] in
      self?.state = .disconnected
    }
    bonjourClient.onFailure = { [weak self] message in
      self?.state = .failed(message)
    }
    bonjourClient.onMessage = { [weak self] data in
      self?.handleIncoming(data: data)
    }
  }

  /// Mac探索〜WebSocket接続を開始する
  func connect() {
    state = .searching
    bonjourClient.start()
  }

  func disconnect() {
    bonjourClient.stop()
    state = .disconnected
    sessionToken = nil
  }

  /// PINを送信してペアリングを行う
  func pair(pin: String) {
    send(PairMessage(deviceName: deviceName, pin: pin))
  }

  /// アクションの実行をMacへ依頼する
  func execute(_ action: ActionPayload, completion: @escaping (Result<Void, Error>) -> Void = { _ in }) {
    let requestId = UUID().uuidString
    pendingRequests[requestId] = completion
    send(ExecuteMessage(requestId: requestId, action: action))
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
      default:
        break
      }
    } catch {
      print("受信メッセージの解析に失敗しました: \(error.localizedDescription)")
    }
  }

  private func handlePairResult(_ response: PairResultMessage) {
    if response.success {
      sessionToken = response.token
      state = .paired
    } else {
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
