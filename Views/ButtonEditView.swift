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
        Section {
          TextField("ラベル", text: $draft.label)
            .foregroundStyle(GamingPalette.foreground)
          iconPicker
        } header: {
          Text("表示")
            .foregroundStyle(GamingPalette.mutedForeground)
        }
        .listRowBackground(GamingPalette.card.opacity(0.6))

        Section {
          Picker("種別", selection: $draft.action.type) {
            Text("アプリ起動").tag(ActionType.launchApp)
            Text("URLを開く").tag(ActionType.openURL)
            Text("ホットキー").tag(ActionType.hotkey)
            Text("定型文入力").tag(ActionType.typeText)
            Text("音量調整").tag(ActionType.setVolume)
            Text("マルチアクション").tag(ActionType.multiAction)
            Text("フォルダー").tag(ActionType.openFolder)
            Text("ウィンドウ配置").tag(ActionType.windowLayout)
          }
          .foregroundStyle(GamingPalette.foreground)
          .onChange(of: draft.action.type) { _, newType in
            // 初めてウィンドウ配置に切り替えた時点でプリセットを既定値に確定させ、保存時にnilのままにならないようにする
            if newType == .windowLayout, draft.action.preset == nil {
              draft.action.preset = WindowLayoutPreset.leftHalf.rawValue
            }
          }

          actionParameterFields
        } header: {
          Text("アクション")
            .foregroundStyle(GamingPalette.mutedForeground)
        }
        .listRowBackground(GamingPalette.card.opacity(0.6))
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
      .navigationTitle("ボタン編集")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
            .foregroundStyle(GamingPalette.mutedForeground)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            onSave(draft)
            dismiss()
          }
          .foregroundStyle(themeStore.accentColor)
        }
      }
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
    case .activateApplication:
      TextField("アプリ名 または Bundle ID", text: targetBinding)
        .foregroundStyle(GamingPalette.foreground)
    case .windowLayout:
      windowLayoutFields
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
    case .multiAction, .openFolder, .activateTab, .closeTab, .activateApplication, .windowLayout:
      // マルチアクションのステップにはフォルダー・タブ操作・ウィンドウ配置・入れ子のマルチアクションを登録できない
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
