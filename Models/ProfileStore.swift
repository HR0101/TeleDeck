//
//  ProfileStore.swift
//  TeleDeck
//
//  プロファイル構成を保持するストア。Macがプロファイル設定の本体（source of truth）のため、
//  ここではオフライン時の表示キャッシュとしてDocuments配下のJSONに保存しつつ、
//  Macから`profileSync`が届いたらその内容で上書きする。ローカル編集は即座に反映（楽観的更新）した上で
//  `onLocalChange`経由でMacへ反映依頼する。
//

import Foundation
import Observation

@Observable
final class ProfileStore {
  private(set) var profiles: [ProfileConfig]
  private(set) var activeProfileId: UUID

  /// ローカルでの編集が行われた際に呼ばれる（Mac側へ変更を反映依頼するためのフック）
  var onLocalChange: (([ProfileConfig], UUID) -> Void)?

  /// activeProfileIdに一致するプロファイル。見つからなければ先頭のプロファイルを返す
  var activeProfile: ProfileConfig {
    profiles.first { $0.id == activeProfileId } ?? profiles[0]
  }

  private let fileURL: URL

  init() {
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let url = documentsURL.appendingPathComponent("profile.json")
    fileURL = url

    let cached = Self.loadFromDisk(at: url)
    let resolvedProfiles = cached ?? Self.defaultProfiles
    profiles = resolvedProfiles
    activeProfileId = resolvedProfiles[0].id
  }

  // MARK: - Macからの同期

  /// Macから届いた最新のプロファイル一覧で上書きする（Macが本体のため、そのまま反映しキャッシュを更新する）
  func applySync(profiles: [ProfileConfig], activeProfileId: UUID) {
    self.profiles = profiles
    self.activeProfileId = activeProfileId
    cacheToDisk()
  }

  // MARK: - ローカル編集（現在のactiveProfileに対して行う）

  /// iPad上で選択したプロファイルへ切り替え、Mac側にも選択状態を同期する
  func setActiveProfile(id: UUID) {
    guard profiles.contains(where: { $0.id == id }), id != activeProfileId else { return }
    activeProfileId = id
    notifyLocalChange()
  }

  func addButton(_ button: ButtonConfig) {
    guard let profileIndex = profiles.firstIndex(where: { $0.id == activeProfileId }) else { return }
    profiles[profileIndex].buttons.append(button)
    notifyLocalChange()
  }

  func updateButton(_ button: ButtonConfig) {
    guard let profileIndex = profiles.firstIndex(where: { $0.id == activeProfileId }) else { return }
    guard let buttonIndex = profiles[profileIndex].buttons.firstIndex(where: { $0.id == button.id }) else { return }
    profiles[profileIndex].buttons[buttonIndex] = button
    notifyLocalChange()
  }

  func deleteButton(id: UUID) {
    guard let profileIndex = profiles.firstIndex(where: { $0.id == activeProfileId }) else { return }
    profiles[profileIndex].buttons.removeAll { $0.id == id }
    notifyLocalChange()
  }

  private func notifyLocalChange() {
    cacheToDisk()
    onLocalChange?(profiles, activeProfileId)
  }

  // MARK: - オフライン表示用キャッシュ

  private func cacheToDisk() {
    do {
      let data = try JSONEncoder().encode(profiles)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      print("プロファイルのキャッシュ保存に失敗しました: \(error.localizedDescription)")
    }
  }

  private static func loadFromDisk(at url: URL) -> [ProfileConfig]? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode([ProfileConfig].self, from: data)
  }

  private static let defaultButtons: [ButtonConfig] = [
    ButtonConfig(row: 0, col: 0, label: "Chrome", iconName: "globe", action: ActionPayload(type: .launchApp, target: "Google Chrome")),
    ButtonConfig(row: 0, col: 1, label: "Safari", iconName: "safari", action: ActionPayload(type: .launchApp, target: "Safari")),
    ButtonConfig(row: 0, col: 2, label: "リンクを開く", iconName: "link", action: ActionPayload(type: .openURL, target: "https://example.com")),
    ButtonConfig(row: 0, col: 3, label: "コピー", iconName: "doc.on.doc", action: ActionPayload(type: .hotkey, keys: ["cmd", "c"])),
    ButtonConfig(row: 0, col: 4, label: "ペースト", iconName: "clipboard", action: ActionPayload(type: .hotkey, keys: ["cmd", "v"]))
  ]

  private static let chromeProfileButtons: [ButtonConfig] = [
    ButtonConfig(row: 0, col: 0, label: "新しいタブ", iconName: "plus.square", action: ActionPayload(type: .hotkey, keys: ["cmd", "t"])),
    ButtonConfig(row: 0, col: 1, label: "タブを閉じる", iconName: "xmark.square", action: ActionPayload(type: .hotkey, keys: ["cmd", "w"]))
  ]

  private static let defaultProfiles: [ProfileConfig] = [
    ProfileConfig(name: "デフォルト", triggerAppBundleId: nil, buttons: defaultButtons),
    ProfileConfig(name: "Chrome用", triggerAppBundleId: "com.google.Chrome", buttons: chromeProfileButtons)
  ]
}
