//
//  ButtonEditView.swift
//  TeleDeck
//
//  パネルのボタン1つを編集するシート。
//

import SwiftUI
import PhotosUI

private let commonSFSymbols = [
  "globe", "safari", "link", "doc.on.doc", "clipboard", "terminal", "folder",
  "message", "envelope", "music.note", "play.fill", "speaker.wave.2",
  "text.cursor", "keyboard", "gearshape", "star", "bolt", "square.grid.2x2"
]

private let modifierKeys = ["cmd", "shift", "opt", "ctrl"]

private enum ButtonEditStep {
  case action
  case appearance
}

private struct ActionChoice: Identifiable {
  let type: ActionType
  /// mediaKey用。同じActionType内で複数の選択肢（音量を上げる/下げる等）を区別するためのキー
  let mediaKey: String?
  /// systemAction用。同じActionType内で複数の選択肢（スリープ/ロック等）を区別するためのキー
  let systemAction: String?
  let title: String
  let description: String
  let systemImage: String

  init(
    type: ActionType,
    mediaKey: String? = nil,
    systemAction: String? = nil,
    title: String,
    description: String,
    systemImage: String
  ) {
    self.type = type
    self.mediaKey = mediaKey
    self.systemAction = systemAction
    self.title = title
    self.description = description
    self.systemImage = systemImage
  }

  var id: String {
    let suffix = mediaKey ?? systemAction
    return suffix.map { "\(type.rawValue)-\($0)" } ?? type.rawValue
  }
}

private struct ActionChoiceGroup: Identifiable {
  let title: String
  let choices: [ActionChoice]

  var id: String { title }
}

private let actionChoiceGroups = [
  ActionChoiceGroup(
    title: "システム",
    choices: [
      ActionChoice(type: .openURL, title: "Webサイト", description: "指定したURLをブラウザで開きます", systemImage: "globe"),
      ActionChoice(type: .hotkey, title: "ホットキー", description: "キーボードショートカットを送信します", systemImage: "keyboard"),
      ActionChoice(type: .launchApp, title: "アプリケーションを開く", description: "Macのアプリケーションを起動します", systemImage: "macwindow"),
      ActionChoice(type: .quitApplication, title: "アプリケーションを終了", description: "起動中のMacアプリケーションを終了します", systemImage: "xmark.app"),
      ActionChoice(type: .typeText, title: "テキスト", description: "登録したテキストを入力します", systemImage: "text.cursor"),
      ActionChoice(type: .openFinderFolder, title: "Finderでフォルダを開く", description: "指定したフォルダをFinderで開きます", systemImage: "folder")
    ]
  ),
  ActionChoiceGroup(
    title: "オーディオ・画面",
    choices: [
      ActionChoice(type: .setVolume, title: "音量を設定", description: "Macの出力音量を変更します", systemImage: "speaker.wave.2"),
      ActionChoice(type: .mediaKey, mediaKey: "volumeUp", title: "音量を上げる", description: "1段階、音量を上げます", systemImage: "speaker.wave.3"),
      ActionChoice(type: .mediaKey, mediaKey: "volumeDown", title: "音量を下げる", description: "1段階、音量を下げます", systemImage: "speaker.wave.1"),
      ActionChoice(type: .mediaKey, mediaKey: "mute", title: "ミュート切り替え", description: "出力音量のミュートを切り替えます", systemImage: "speaker.slash"),
      ActionChoice(type: .mediaKey, mediaKey: "brightnessUp", title: "画面を明るく", description: "1段階、画面の明るさを上げます", systemImage: "sun.max"),
      ActionChoice(type: .mediaKey, mediaKey: "brightnessDown", title: "画面を暗く", description: "1段階、画面の明るさを下げます", systemImage: "sun.min"),
      ActionChoice(type: .mediaKey, mediaKey: "keyboardBacklightUp", title: "キーボードを明るく", description: "キーボードバックライトを明るくします", systemImage: "keyboard.badge.ellipsis"),
      ActionChoice(type: .mediaKey, mediaKey: "keyboardBacklightDown", title: "キーボードを暗く", description: "キーボードバックライトを暗くします", systemImage: "keyboard")
    ]
  ),
  ActionChoiceGroup(
    title: "メディア再生",
    choices: [
      ActionChoice(type: .mediaKey, mediaKey: "playPause", title: "再生/一時停止", description: "再生中のメディアを再生・一時停止します", systemImage: "playpause.fill"),
      ActionChoice(type: .mediaKey, mediaKey: "nextTrack", title: "次のトラック", description: "次のトラックにスキップします", systemImage: "forward.end.fill"),
      ActionChoice(type: .mediaKey, mediaKey: "previousTrack", title: "前のトラック", description: "前のトラックに戻ります", systemImage: "backward.end.fill")
    ]
  ),
  ActionChoiceGroup(
    title: "電源・画面キャプチャ",
    choices: [
      ActionChoice(type: .systemAction, systemAction: "sleep", title: "スリープ", description: "Macをスリープさせます", systemImage: "moon.fill"),
      ActionChoice(type: .systemAction, systemAction: "lockScreen", title: "画面をロック", description: "画面をロックします", systemImage: "lock.fill"),
      ActionChoice(type: .systemAction, systemAction: "screenSaver", title: "スクリーンセーバーを開始", description: "スクリーンセーバーをすぐに開始します", systemImage: "sparkles"),
      ActionChoice(type: .systemAction, systemAction: "screenshotFull", title: "スクリーンショット（全画面）", description: "画面全体のスクリーンショットを撮ります", systemImage: "camera.viewfinder"),
      ActionChoice(type: .systemAction, systemAction: "screenshotSelection", title: "スクリーンショット（範囲選択）", description: "選択した範囲のスクリーンショットを撮ります", systemImage: "crop")
    ]
  ),
  ActionChoiceGroup(
    title: "操作",
    choices: [
      ActionChoice(type: .multiAction, title: "マルチアクション", description: "複数の操作を順番に実行します", systemImage: "list.number"),
      ActionChoice(type: .openFolder, title: "フォルダを作成", description: "パネル内にボタンの階層を作ります", systemImage: "folder"),
      ActionChoice(type: .windowLayout, title: "ウィンドウ配置", description: "前面のウィンドウを指定位置へ移動します", systemImage: "rectangle.split.2x1")
    ]
  )
]

/// ウィンドウ配置アクションのプリセット。rawValueはMac側WindowLayoutManagerが解釈する文字列と一致させる
private enum WindowLayoutPreset: String, CaseIterable, Identifiable {
  case leftHalf = "left-half"
  case rightHalf = "right-half"
  case maximize = "maximize"
  case centered = "centered"
  case threeSplit = "three-split"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .leftHalf: return "左半分"
    case .rightHalf: return "右半分"
    case .maximize: return "最大化"
    case .centered: return "中央寄せ"
    case .threeSplit: return "3分割"
    }
  }
}

struct ButtonEditView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(ThemeStore.self) private var themeStore
  @State private var draft: ButtonConfig
  @State private var editStep: ButtonEditStep = .action
  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var photoLoadErrorMessage: String?

  let onSave: (ButtonConfig) -> Void

  init(button: ButtonConfig, onSave: @escaping (ButtonConfig) -> Void) {
    _draft = State(initialValue: button)
    self.onSave = onSave
  }

  var body: some View {
    NavigationStack {
      Form {
        if editStep == .action {
          actionSelectionSections
          Section {
            actionParameterFields
          } header: {
            Text("アクションの設定")
              .foregroundStyle(GamingPalette.mutedForeground)
          }
          .listRowBackground(GamingPalette.card.opacity(0.6))
        } else {
          Section {
            Label(selectedActionTitle, systemImage: selectedActionImage)
              .foregroundStyle(GamingPalette.foreground)
          } header: {
            Text("選択したアクション")
              .foregroundStyle(GamingPalette.mutedForeground)
          }
          .listRowBackground(GamingPalette.card.opacity(0.6))

          Section {
            TextField("ラベル", text: $draft.label)
              .foregroundStyle(GamingPalette.foreground)
            iconPicker
          } header: {
            Text("表示")
              .foregroundStyle(GamingPalette.mutedForeground)
          }
          .listRowBackground(GamingPalette.card.opacity(0.6))
        }
      }
      .scrollContentBackground(.hidden)
      .background(
        LinearGradient(
          colors: [GamingPalette.background, GamingPalette.backgroundElevated],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
      )
      .tint(themeStore.accentColor)
      .navigationTitle(editStep == .action ? "アクションを選択" : "表示を設定")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(editStep == .action ? "キャンセル" : "戻る") {
            if editStep == .action {
              dismiss()
            } else {
              editStep = .action
            }
          }
            .foregroundStyle(GamingPalette.mutedForeground)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(editStep == .action ? "次へ" : "保存") {
            if editStep == .action {
              editStep = .appearance
            } else {
              onSave(draft)
              dismiss()
            }
          }
          .foregroundStyle(themeStore.accentColor)
        }
      }
    }
  }

  @ViewBuilder
  private var actionSelectionSections: some View {
    ForEach(actionChoiceGroups) { group in
      Section {
        ForEach(group.choices) { choice in
          Button {
            selectAction(choice)
          } label: {
            HStack(spacing: 12) {
              Image(systemName: choice.systemImage)
                .font(.title3)
                .foregroundStyle(themeStore.accentColor)
                .frame(width: 28)
              VStack(alignment: .leading, spacing: 3) {
                Text(choice.title)
                  .font(.body.weight(.medium))
                  .foregroundStyle(GamingPalette.foreground)
                Text(choice.description)
                  .font(.caption)
                  .foregroundStyle(GamingPalette.mutedForeground)
              }
              Spacer()
              if draft.action.type == choice.type,
                 draft.action.mediaKey == choice.mediaKey,
                 draft.action.systemAction == choice.systemAction {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(themeStore.accentColor)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      } header: {
        Text(group.title)
          .foregroundStyle(GamingPalette.mutedForeground)
      }
      .listRowBackground(GamingPalette.card.opacity(0.6))
    }
  }

  private var selectedActionChoice: ActionChoice? {
    actionChoiceGroups.flatMap(\.choices).first {
      $0.type == draft.action.type && $0.mediaKey == draft.action.mediaKey && $0.systemAction == draft.action.systemAction
    }
  }

  private var selectedActionTitle: String {
    selectedActionChoice?.title ?? "アクション"
  }

  private var selectedActionImage: String {
    selectedActionChoice?.systemImage ?? "bolt"
  }

  private func selectAction(_ choice: ActionChoice) {
    draft.action.type = choice.type
    draft.action.mediaKey = choice.mediaKey
    draft.action.systemAction = choice.systemAction
    if choice.type == .windowLayout, draft.action.preset == nil {
      draft.action.preset = WindowLayoutPreset.leftHalf.rawValue
    }
  }

  // MARK: - アイコン選択

  private var iconPicker: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        AnimatedIconView(
          iconKind: draft.iconKind,
          iconName: draft.iconName,
          iconImageFileName: draft.iconImageFileName
        )
        .font(.system(size: 28))
        .frame(width: 40, height: 40)

        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
          Label("写真から選択", systemImage: "photo.on.rectangle")
        }
        .foregroundStyle(themeStore.accentColor)
      }

      LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
        ForEach(commonSFSymbols, id: \.self) { symbol in
          let isSelected = draft.iconKind == .sfSymbol && draft.iconName == symbol
          Image(systemName: symbol)
            .font(.system(size: 20))
            .foregroundStyle(isSelected ? themeStore.accentColor : GamingPalette.mutedForeground)
            .frame(width: 36, height: 36)
            .background(
              isSelected ? themeStore.accentColor.opacity(0.3) : GamingPalette.muted.opacity(0.5),
              in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
              RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? themeStore.accentColor.opacity(0.9) : Color.clear, lineWidth: 1.2)
            )
            .onTapGesture {
              draft.iconKind = .sfSymbol
              draft.iconName = symbol
            }
        }
      }
      TextField("SF Symbol名を直接入力", text: $draft.iconName)
        .font(.caption)
        .foregroundStyle(GamingPalette.foreground)

      if let photoLoadErrorMessage {
        Text(photoLoadErrorMessage)
          .font(.caption)
          .foregroundStyle(GamingPalette.destructive)
      }
    }
    .onChange(of: selectedPhotoItem) { _, newItem in
      guard let newItem else { return }
      Task { await loadSelectedPhoto(newItem) }
    }
  }

  /// 選択された写真（画像/GIF）を読み込み、IconImageStoreへ保存してdraftへ反映する
  @MainActor
  private func loadSelectedPhoto(_ item: PhotosPickerItem) async {
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else {
        photoLoadErrorMessage = "画像の読み込みに失敗しました。別の画像を選び直してください"
        return
      }
      let fileExtension = resolvedFileExtension(for: item, data: data)
      let fileName = try IconImageStore.save(data: data, suggestedExtension: fileExtension)
      draft.iconKind = .image
      draft.iconImageFileName = fileName
      photoLoadErrorMessage = nil
    } catch {
      photoLoadErrorMessage = "画像の保存に失敗しました: \(error.localizedDescription)"
    }
  }

  /// GIFの先頭シグネチャ（"GIF8"）。PhotosPickerItemがcontent typeを返さない場合のフォールバック判定に使う
  private static let gifSignatureBytes: [UInt8] = [0x47, 0x49, 0x46, 0x38]

  private func resolvedFileExtension(for item: PhotosPickerItem, data: Data) -> String {
    if let type = item.supportedContentTypes.first, let ext = type.preferredFilenameExtension {
      return ext
    }
    if data.starts(with: Self.gifSignatureBytes) {
      return "gif"
    }
    return "png"
  }

  // MARK: - アクション種別ごとの入力欄

  @ViewBuilder
  private var actionParameterFields: some View {
    switch draft.action.type {
    case .launchApp:
      TextField("アプリ名 または Bundle ID", text: targetBinding)
        .foregroundStyle(GamingPalette.foreground)
    case .openURL:
      TextField("URL", text: targetBinding)
        .foregroundStyle(GamingPalette.foreground)
    case .hotkey:
      hotkeyFields
    case .typeText:
      TextField("入力するテキスト", text: textBinding, axis: .vertical)
        .lineLimit(3...6)
        .foregroundStyle(GamingPalette.foreground)
    case .setVolume:
      Stepper("音量: \(draft.action.volume ?? 50)", value: volumeBinding, in: 0...100, step: 5)
        .foregroundStyle(GamingPalette.foreground)
    case .multiAction:
      MultiActionStepsEditor(steps: stepsBinding)
    case .delay:
      Stepper("待機時間: \(draft.action.ms ?? 500) ms", value: msBinding, in: 0...10000, step: 100)
        .foregroundStyle(GamingPalette.foreground)
    case .openFolder:
      Text("このボタンをタップすると中のボタン一覧を開きます")
        .font(.caption)
        .foregroundStyle(GamingPalette.mutedForeground)
    case .activateTab, .closeTab:
      // タブ一覧画面から生成されるアクションのため、この汎用エディタでは編集項目を出さない
      Text("タブ一覧画面から設定されるアクションです")
        .font(.caption)
        .foregroundStyle(GamingPalette.mutedForeground)
    case .activateApplication, .quitApplication:
      TextField("アプリ名 または Bundle ID", text: targetBinding)
        .foregroundStyle(GamingPalette.foreground)
    case .windowLayout:
      windowLayoutFields
    case .mediaKey, .systemAction:
      Text("「\(selectedActionTitle)」を送信します")
        .font(.caption)
        .foregroundStyle(GamingPalette.mutedForeground)
    case .openFinderFolder:
      TextField("Mac上のフォルダのパス", text: targetBinding)
        .foregroundStyle(GamingPalette.foreground)
    }
  }

  private var windowLayoutFields: some View {
    Picker("配置プリセット", selection: presetBinding) {
      ForEach(WindowLayoutPreset.allCases) { preset in
        Text(preset.displayName).tag(preset.rawValue)
      }
    }
    .foregroundStyle(GamingPalette.foreground)
  }

  private var presetBinding: Binding<String> {
    Binding(
      get: { draft.action.preset ?? WindowLayoutPreset.leftHalf.rawValue },
      set: { draft.action.preset = $0 }
    )
  }

  private var hotkeyFields: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        ForEach(modifierKeys, id: \.self) { modifier in
          let isSelected = (draft.action.keys ?? []).contains(modifier)
          Button(modifier) {
            toggleModifier(modifier)
          }
          .font(.callout)
          .foregroundStyle(isSelected ? Color.white : GamingPalette.foreground)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(isSelected ? themeStore.accentColor : GamingPalette.muted)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .stroke(themeStore.accentColor.opacity(isSelected ? 0.9 : 0.3), lineWidth: 1)
          )
        }
      }
      TextField("キー（例: c）", text: keyBinding)
        .foregroundStyle(GamingPalette.foreground)
    }
  }

  private func toggleModifier(_ modifier: String) {
    var keys = draft.action.keys ?? []
    if let index = keys.firstIndex(of: modifier) {
      keys.remove(at: index)
    } else {
      keys.append(modifier)
    }
    draft.action.keys = keys
  }

  // MARK: - Optionalフィールド用のBinding

  private var targetBinding: Binding<String> {
    Binding(get: { draft.action.target ?? "" }, set: { draft.action.target = $0 })
  }

  private var textBinding: Binding<String> {
    Binding(get: { draft.action.text ?? "" }, set: { draft.action.text = $0 })
  }

  private var volumeBinding: Binding<Int> {
    Binding(get: { draft.action.volume ?? 50 }, set: { draft.action.volume = $0 })
  }

  private var msBinding: Binding<Int> {
    Binding(get: { draft.action.ms ?? 500 }, set: { draft.action.ms = $0 })
  }

  private var stepsBinding: Binding<[ActionPayload]> {
    Binding(get: { draft.action.steps ?? [] }, set: { draft.action.steps = $0 })
  }

  private var keyBinding: Binding<String> {
    Binding(
      get: {
        (draft.action.keys ?? []).first { !modifierKeys.contains($0) } ?? ""
      },
      set: { newKey in
        let currentModifiers = (draft.action.keys ?? []).filter { modifierKeys.contains($0) }
        draft.action.keys = currentModifiers + (newKey.isEmpty ? [] : [newKey.lowercased()])
      }
    )
  }
}

// MARK: - マルチアクションのステップ編集

private struct MultiActionStepsEditor: View {
  @Environment(ThemeStore.self) private var themeStore
  @Binding var steps: [ActionPayload]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(steps.indices, id: \.self) { index in
        StepRow(step: $steps[index]) {
          steps.remove(at: index)
        }
      }

      Button {
        steps.append(ActionPayload(type: .launchApp, target: ""))
      } label: {
        Label("ステップを追加", systemImage: "plus.circle")
      }
      .foregroundStyle(themeStore.accentColor)
    }
  }
}

private struct StepRow: View {
  @Environment(ThemeStore.self) private var themeStore
  @Binding var step: ActionPayload
  let onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Picker("", selection: $step.type) {
          Text("アプリ起動").tag(ActionType.launchApp)
          Text("URLを開く").tag(ActionType.openURL)
          Text("ホットキー").tag(ActionType.hotkey)
          Text("定型文入力").tag(ActionType.typeText)
          Text("音量調整").tag(ActionType.setVolume)
          Text("待機").tag(ActionType.delay)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .foregroundStyle(GamingPalette.foreground)

        Spacer()

        Button(role: .destructive) {
          onDelete()
        } label: {
          Image(systemName: "trash")
            .foregroundStyle(GamingPalette.destructive)
        }
      }

      stepParameterField
    }
    .padding(8)
    .gamingCard(accentColor: themeStore.accentColor, cornerRadius: 10)
  }

  @ViewBuilder
  private var stepParameterField: some View {
    switch step.type {
    case .launchApp:
      TextField("アプリ名", text: targetBinding)
        .foregroundStyle(GamingPalette.foreground)
    case .openURL:
      TextField("URL", text: targetBinding)
        .foregroundStyle(GamingPalette.foreground)
    case .hotkey:
      TextField("キー（例: cmd,c）", text: keysBinding)
        .foregroundStyle(GamingPalette.foreground)
    case .typeText:
      TextField("入力するテキスト", text: textBinding)
        .foregroundStyle(GamingPalette.foreground)
    case .setVolume:
      Stepper("音量: \(step.volume ?? 50)", value: volumeBinding, in: 0...100, step: 5)
        .foregroundStyle(GamingPalette.foreground)
    case .delay:
      Stepper("待機: \(step.ms ?? 500) ms", value: msBinding, in: 0...10000, step: 100)
        .foregroundStyle(GamingPalette.foreground)
    case .multiAction, .openFolder, .activateTab, .closeTab, .activateApplication, .windowLayout, .mediaKey,
         .quitApplication, .openFinderFolder, .systemAction:
      // マルチアクションのステップには一部の高度なアクション・入れ子のマルチアクションを登録できない
      Text("マルチアクション内には登録できません")
        .font(.caption)
        .foregroundStyle(GamingPalette.mutedForeground)
    }
  }

  private var targetBinding: Binding<String> {
    Binding(get: { step.target ?? "" }, set: { step.target = $0 })
  }

  private var textBinding: Binding<String> {
    Binding(get: { step.text ?? "" }, set: { step.text = $0 })
  }

  private var volumeBinding: Binding<Int> {
    Binding(get: { step.volume ?? 50 }, set: { step.volume = $0 })
  }

  private var msBinding: Binding<Int> {
    Binding(get: { step.ms ?? 500 }, set: { step.ms = $0 })
  }

  private var keysBinding: Binding<String> {
    Binding(
      get: { (step.keys ?? []).joined(separator: ",") },
      set: { step.keys = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
    )
  }
}

#Preview {
  ButtonEditView(button: ButtonConfig(row: 0, col: 0, label: "Chrome", iconName: "globe", action: ActionPayload(type: .launchApp, target: "Google Chrome"))) { _ in }
    .environment(ThemeStore())
}
