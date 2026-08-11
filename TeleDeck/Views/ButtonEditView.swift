//
//  ButtonEditView.swift
//  TeleDeck
//
//  パネルのボタン1つを編集するシート。
//

import SwiftUI
import PhotosUI
import UIKit

/// クイック選択できるSF Symbolsの一覧。ここに無いものは下の直接入力欄で指定する。
/// カテゴリーごとにまとめ、よく使うボタンの用途を一通りタップだけで選べるようにしている
private let commonSFSymbols = EditorIconCatalog.commonSFSymbols

private let modifierKeys = ["cmd", "shift", "opt", "ctrl"]

private enum ButtonEditStep {
  case action
  /// アクションを選んだ直後に表示する、そのアクション専用の入力画面
  /// （選択画面とURL入力等を同じ画面に詰め込むと見落とされやすいため分離している）
  case parameters
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
      ActionChoice(type: .openFinderFolder, title: "Finderでフォルダを開く", description: "指定したフォルダをFinderで開きます", systemImage: "folder"),
      ActionChoice(type: .createFinderFolder, title: "Macにフォルダを作成", description: "選んだ場所に新しいフォルダを作成します", systemImage: "folder.badge.plus")
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
      ActionChoice(type: .mediaKey, mediaKey: "keyboardBacklightDown", title: "キーボードを暗く", description: "キーボードバックライトを暗くします", systemImage: "keyboard"),
      ActionChoice(type: .mediaKey, mediaKey: "micMute", title: "マイクをミュート", description: "システム全体でマイクの入力をミュート/解除します（どのアプリ使用中でも効きます）", systemImage: "mic.slash")
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
      ActionChoice(type: .openFolder, title: "ボタン階層を作成", description: "パネル内にボタンの階層を作ります", systemImage: "folder"),
      ActionChoice(type: .windowLayout, title: "ウィンドウ配置", description: "前面のウィンドウを指定位置へ移動します", systemImage: "rectangle.split.2x1")
    ]
  )
]

struct ButtonEditView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(ThemeStore.self) private var themeStore
  @State private var draft: ButtonConfig
  @State private var editStep: ButtonEditStep = .action
  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var photoLoadErrorMessage: String?
  @State private var isRecordingHotkey = false
  @State private var hotkeyRecordingKeys: [String] = []
  @State private var hotkeyRecordingGeneration = 0
  @State private var automaticallyNamesButton: Bool
  /// アイコンを未カスタマイズ（新規ボタンの初期値のまま）の間だけ、選んだアクションに合わせてアイコンを自動で変える
  @State private var automaticallyPicksIcon: Bool
  @State private var isShowingApplicationPicker = false
  @State private var availableApplications: [MacApplicationInfo] = []
  @State private var isLoadingApplications = false
  /// テスト実行の状態と直近の結果
  @State private var isTestRunning = false
  @State private var testResultMessage: String?
  @State private var testSucceeded = false

  let connectionManager: ConnectionManager
  let onSave: (ButtonConfig) -> Void

  init(button: ButtonConfig, connectionManager: ConnectionManager, onSave: @escaping (ButtonConfig) -> Void) {
    _draft = State(initialValue: button)
    _automaticallyNamesButton = State(
      initialValue: button.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || button.label == "新しいボタン"
    )
    _automaticallyPicksIcon = State(
      initialValue: button.iconKind == .sfSymbol
        && (button.iconName.isEmpty || button.iconName == "square.grid.2x2")
    )
    self.onSave = onSave
    self.connectionManager = connectionManager
  }

  var body: some View {
    NavigationStack {
      Form {
        switch editStep {
        case .action:
          actionSelectionSections

        case .parameters:
          Section {
            Label(selectedActionTitle, systemImage: selectedActionImage)
              .foregroundStyle(GamingPalette.foreground)
          } header: {
            Text("選択したアクション")
              .foregroundStyle(GamingPalette.mutedForeground)
          }
          .listRowBackground(GamingPalette.card.opacity(0.6))

          Section {
            actionParameterFields
          } header: {
            Text(parameterSectionTitle)
              .foregroundStyle(GamingPalette.mutedForeground)
          } footer: {
            if let parameterSectionFooter {
              Text(parameterSectionFooter)
                .foregroundStyle(GamingPalette.mutedForeground)
            }
          }
          .listRowBackground(GamingPalette.card.opacity(0.6))

          testRunSection

        case .appearance:
          Section {
            TextField("ラベル", text: labelBinding)
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
      .navigationTitle(navigationTitleText)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(editStep == .action ? "キャンセル" : "戻る") {
            switch editStep {
            case .action:
              dismiss()
            case .parameters:
              editStep = .action
            case .appearance:
              editStep = .parameters
            }
          }
            .foregroundStyle(GamingPalette.mutedForeground)
        }
        if editStep != .action {
          ToolbarItem(placement: .confirmationAction) {
            Button(editStep == .parameters ? "次へ" : "保存") {
              if editStep == .parameters {
                prepareAppearance()
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
    .overlay(alignment: .topLeading) {
      // FormのUICollectionView配下に置くと、方向キーがフォーカス移動として先に処理される。
      // キャプチャ用responderはFormの外側に置き、UIKeyCommandでも方向キーを明示的に奪う。
      HotkeyHardwareKeyCapture(
        isActive: $isRecordingHotkey,
        onKeyPress: handleHardwareKeyPress,
        onDirectionalKeyPress: handleHardwareDirectionalKeyPress
      )
      .frame(width: 1, height: 1)
      .accessibilityHidden(true)
    }
    .sheet(isPresented: $isShowingApplicationPicker) {
      MacApplicationPicker(applications: availableApplications, isLoading: isLoadingApplications) { application in
        draft.action.target = application.bundleIdentifier
        draft.applicationIconPNGData = application.iconPNGData
        draft.iconKind = .sfSymbol
        draft.iconName = "macwindow"
        draft.label = application.name
        automaticallyNamesButton = true
        isShowingApplicationPicker = false
      }
    }
  }

  private var navigationTitleText: String {
    switch editStep {
    case .action: return "アクションを選択"
    case .parameters: return selectedActionTitle
    case .appearance: return "表示を設定"
    }
  }

  // MARK: - テスト実行

  /// 保存してパネルへ戻らないと動作を確認できないと、ホットキーやウィンドウ配置の
  /// 設定が正しいか分からないまま往復することになるため、その場で試せるようにする
  @ViewBuilder
  private var testRunSection: some View {
    // フォルダーとタブ操作はパネル上・タブ画面上の文脈でしか意味を持たないため対象外
    if draft.action.type != .openFolder,
       draft.action.type != .activateTab,
       draft.action.type != .closeTab {
      Section {
        Button {
          runTest()
        } label: {
          HStack(spacing: 10) {
            if isTestRunning {
              ProgressView()
                .controlSize(.small)
                .tint(themeStore.accentColor)
            } else {
              Image(systemName: "play.circle")
            }
            Text(isTestRunning ? "Macで実行中…" : "このアクションをテスト実行")
          }
          .foregroundStyle(themeStore.accentColor)
        }
        .disabled(isTestRunning || !connectionManager.isConnected)

        if let testResultMessage {
          Label(testResultMessage, systemImage: testSucceeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.caption)
            .foregroundStyle(testSucceeded ? GamingPalette.success : GamingPalette.destructive)
            .fixedSize(horizontal: false, vertical: true)
        }
      } header: {
        Text("動作確認")
          .foregroundStyle(GamingPalette.mutedForeground)
      } footer: {
        Text(connectionManager.isConnected
          ? "保存しなくても、今の設定のままMacで実行して確認できます"
          : "Macに接続されていないため実行できません")
          .foregroundStyle(GamingPalette.mutedForeground)
      }
      .listRowBackground(GamingPalette.card.opacity(0.6))
    }
  }

  private func runTest() {
    isTestRunning = true
    testResultMessage = nil

    connectionManager.execute(draft.action) { result in
      isTestRunning = false
      switch result {
      case .success:
        testSucceeded = true
        testResultMessage = "Macで実行しました"
      case .failure(let error):
        testSucceeded = false
        testResultMessage = error.localizedDescription
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
    let previousType = draft.action.type
    draft.action.type = choice.type
    draft.action.mediaKey = choice.mediaKey
    draft.action.systemAction = choice.systemAction
    if choice.type == .createFinderFolder, previousType != .createFinderFolder {
      // URLやアプリ名など、前のアクションのtargetを作成先として誤用しない
      draft.action.target = nil
      draft.action.folderName = nil
    }
    if choice.type == .windowLayout, draft.action.preset == nil {
      draft.action.preset = WindowLayoutPreset.leftHalf.rawValue
    }
    if choice.type == .launchApp {
      automaticallyNamesButton = true
    }
    if automaticallyPicksIcon, draft.iconKind == .sfSymbol {
      draft.iconName = choice.systemImage
    }
    // 選択直後にそのアクション専用の入力画面へ進む（選択画面に埋もれてURL入力欄などが
    // 見落とされないようにするため）
    withAnimation(.easeOut(duration: 0.18)) {
      editStep = .parameters
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

      if !recommendedSFSymbols.isEmpty {
        Text("このアクションのおすすめ")
          .font(.caption2)
          .foregroundStyle(GamingPalette.mutedForeground)
        iconGrid(recommendedSFSymbols)
      }

      Text("すべてのアイコン")
        .font(.caption2)
        .foregroundStyle(GamingPalette.mutedForeground)
      iconGrid(commonSFSymbols)

      TextField("SF Symbol名を直接入力", text: iconNameBinding)
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

  private func iconGrid(_ symbols: [String]) -> some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
      ForEach(symbols, id: \.self) { symbol in
        iconTile(symbol)
      }
    }
  }

  private func iconTile(_ symbol: String) -> some View {
    let isSelected = draft.iconKind == .sfSymbol && draft.iconName == symbol
    return Image(systemName: symbol)
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
        automaticallyPicksIcon = false
      }
  }

  private var iconNameBinding: Binding<String> {
    Binding(
      get: { draft.iconName },
      set: {
        draft.iconName = $0
        automaticallyPicksIcon = false
      }
    )
  }

  /// 選んでいるアクションの機能に合ったアイコン候補。アクションの種類ごとに、
  /// その機能を連想しやすいSF Symbolsだけを絞り込んで表示する
  private var recommendedSFSymbols: [String] {
    var candidates: [String] = []
    if let choiceImage = selectedActionChoice?.systemImage {
      candidates.append(choiceImage)
    }
    candidates.append(contentsOf: additionalRecommendedSFSymbols)

    var seen = Set<String>()
    return candidates.filter { seen.insert($0).inserted }
  }

  private var additionalRecommendedSFSymbols: [String] {
    switch draft.action.type {
    case .launchApp, .activateApplication:
      return ["macwindow", "app.fill", "desktopcomputer", "laptopcomputer", "bolt.fill"]
    case .quitApplication:
      return ["xmark.app", "power", "xmark.circle.fill"]
    case .openURL:
      return ["globe", "safari", "link", "network"]
    case .hotkey:
      return ["keyboard", "command"]
    case .typeText:
      return ["text.cursor", "textformat", "pencil"]
    case .openFinderFolder, .createFinderFolder:
      return ["folder.fill", "folder", "tray.full"]
    case .openFolder:
      return ["folder.fill", "square.grid.2x2", "list.bullet"]
    case .setVolume:
      return ["speaker.wave.2", "speaker.wave.3", "speaker.wave.1"]
    case .multiAction:
      return ["list.number", "list.bullet", "square.stack"]
    case .windowLayout:
      return ["rectangle.split.2x1", "macwindow"]
    case .delay:
      return ["clock", "hourglass", "timer"]
    case .activateTab, .closeTab:
      return ["link", "xmark"]
    case .mediaKey:
      return recommendedMediaKeySymbols
    case .systemAction:
      return recommendedSystemActionSymbols
    }
  }

  private var recommendedMediaKeySymbols: [String] {
    switch draft.action.mediaKey {
    case "volumeUp": return ["speaker.wave.3", "speaker.wave.2"]
    case "volumeDown": return ["speaker.wave.1", "speaker.wave.2"]
    case "mute": return ["speaker.slash", "speaker.wave.2"]
    case "brightnessUp": return ["sun.max", "sun.max.fill"]
    case "brightnessDown": return ["sun.min"]
    case "keyboardBacklightUp", "keyboardBacklightDown": return ["keyboard", "keyboard.badge.ellipsis"]
    case "micMute": return ["mic.slash", "mic", "mic.fill"]
    case "playPause": return ["playpause.fill", "play.fill", "pause.fill"]
    case "nextTrack": return ["forward.end.fill", "forward.fill"]
    case "previousTrack": return ["backward.end.fill", "backward.fill"]
    default: return ["speaker.wave.2"]
    }
  }

  private var recommendedSystemActionSymbols: [String] {
    switch draft.action.systemAction {
    case "sleep": return ["moon.fill", "moon"]
    case "lockScreen": return ["lock.fill", "lock"]
    case "screenSaver": return ["sparkles"]
    case "screenshotFull": return ["camera.viewfinder", "camera.fill"]
    case "screenshotSelection": return ["crop", "camera.viewfinder"]
    default: return ["power"]
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

  /// 「アクションの設定」セクションの見出し。何を入力すればいいかが一目でわかるよう、種別ごとに変える
  private var parameterSectionTitle: String {
    switch draft.action.type {
    case .launchApp, .activateApplication, .quitApplication: return "対象のアプリ"
    case .openURL: return "開くURL"
    case .openFinderFolder: return "対象のフォルダ"
    case .createFinderFolder: return "作成するフォルダ"
    case .hotkey: return "送信するキー"
    case .typeText: return "入力するテキスト"
    case .setVolume: return "音量"
    case .delay: return "待機時間"
    case .windowLayout: return "配置プリセット"
    case .multiAction: return "実行するステップ"
    case .openFolder, .activateTab, .closeTab, .mediaKey, .systemAction: return "アクションの設定"
    }
  }

  /// 入力例や補足の説明。入力形式が分かりにくいものにのみ表示する
  private var parameterSectionFooter: String? {
    switch draft.action.type {
    case .launchApp, .activateApplication, .quitApplication:
      return "アプリ名（例: Google Chrome）またはBundle ID（例: com.google.Chrome）を入力してください"
    case .openURL:
      return "例: https://www.google.com"
    case .openFinderFolder:
      return "Mac上の絶対パスを入力してください（例: /Users/name/Documents）"
    case .createFinderFolder:
      return "作成先は「Macで作成先を選択…」から選んでください"
    default:
      return nil
    }
  }

  @ViewBuilder
  private var actionParameterFields: some View {
    switch draft.action.type {
    case .launchApp:
      VStack(alignment: .leading, spacing: 10) {
        TextField("例: Google Chrome", text: targetBinding)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .foregroundStyle(GamingPalette.foreground)
        appSelectionButton
      }
    case .openURL:
      TextField("https://example.com", text: targetBinding)
        .keyboardType(.URL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
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
      VStack(alignment: .leading, spacing: 10) {
        TextField("例: Google Chrome", text: targetBinding)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .foregroundStyle(GamingPalette.foreground)
        appSelectionButton
      }
    case .windowLayout:
      windowLayoutFields
    case .mediaKey, .systemAction:
      Text("「\(selectedActionTitle)」を送信します")
        .font(.caption)
        .foregroundStyle(GamingPalette.mutedForeground)
    case .openFinderFolder:
      VStack(alignment: .leading, spacing: 10) {
        TextField("例: /Users/name/Documents", text: targetBinding)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .foregroundStyle(GamingPalette.foreground)
        Button {
          connectionManager.requestFolderSelection { path in
            guard let path else { return }
            draft.action.target = path
          }
        } label: {
          Label("Macでフォルダを選択…", systemImage: "folder.badge.gearshape")
            .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.bordered)
        .tint(themeStore.accentColor)
      }
    case .createFinderFolder:
      VStack(alignment: .leading, spacing: 10) {
        TextField("新しいフォルダ名", text: folderNameBinding)
          .autocorrectionDisabled()
          .foregroundStyle(GamingPalette.foreground)
        HStack(spacing: 8) {
          Image(systemName: "folder")
            .foregroundStyle(themeStore.accentColor)
          Text(draft.action.target ?? "作成先未選択")
            .font(.caption)
            .foregroundStyle(GamingPalette.mutedForeground)
            .lineLimit(2)
        }
        Button {
          connectionManager.requestFolderSelection { path in
            guard let path else { return }
            draft.action.target = path
          }
        } label: {
          Label("Macで作成先を選択…", systemImage: "folder.badge.plus")
            .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.bordered)
        .tint(themeStore.accentColor)
      }
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

  private var appSelectionButton: some View {
    Button {
      isLoadingApplications = true
      isShowingApplicationPicker = true
      connectionManager.requestApplications { applications in
        availableApplications = applications
        isLoadingApplications = false
      }
    } label: {
      Label("Macの起動中アプリから選択…", systemImage: "rectangle.3.group")
        .font(.subheadline.weight(.medium))
    }
    .buttonStyle(.bordered)
    .tint(themeStore.accentColor)
  }

  private var presetBinding: Binding<String> {
    Binding(
      get: { draft.action.preset ?? WindowLayoutPreset.leftHalf.rawValue },
      set: { draft.action.preset = $0 }
    )
  }

  private var hotkeyFields: some View {
    VStack(alignment: .leading, spacing: 10) {
      Button {
        isRecordingHotkey = true
        hotkeyRecordingKeys = []
        hotkeyRecordingGeneration += 1
      } label: {
        HStack(spacing: 10) {
          Image(systemName: isRecordingHotkey ? "record.circle.fill" : "keyboard.badge.ellipsis")
          VStack(alignment: .leading, spacing: 2) {
            Text(isRecordingHotkey ? "登録するキーを押してください" : "実際のキー入力を記録")
              .font(.body.weight(.semibold))
            Text(isRecordingHotkey ? recordingHotkeyDescription : recordedHotkeyDescription)
              .font(.caption)
              .foregroundStyle(GamingPalette.mutedForeground)
          }
          Spacer()
        }
        .foregroundStyle(isRecordingHotkey ? GamingPalette.foreground : themeStore.accentColor)
        .padding(12)
        .background(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isRecordingHotkey ? themeStore.accentColor.opacity(0.22) : GamingPalette.muted.opacity(0.45))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(themeStore.accentColor.opacity(isRecordingHotkey ? 0.9 : 0.35), lineWidth: 1)
        )
      }
      .buttonStyle(.plain)

      Text("修飾キー（任意）")
        .font(.caption)
        .foregroundStyle(GamingPalette.mutedForeground)

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

      Text("キー（タップして選択）")
        .font(.caption)
        .foregroundStyle(GamingPalette.mutedForeground)

      // キー名を直接入力させると存在しないキー名を打ち込みやすく分かりにくいため、
      // 実際のキーボード配列をそのままタップして選ばせることで登録ミスを防ぐ
      VStack(spacing: 5) {
        keyPickerRow(KeyboardView.numberRow)
        keyPickerRow(KeyboardView.qwertyRow)
        keyPickerRow(KeyboardView.homeRow)
        keyPickerRow(KeyboardView.bottomLetterKeys)
        keyPickerRow(KeyboardView.extraKeys)
      }

    }
  }

  private var recordedHotkeyDescription: String {
    let keys = draft.action.keys ?? []
    guard !keys.isEmpty else { return "押したキーの組み合わせをそのまま登録します" }
    return "現在: " + keys.map(hotkeyDisplayName).joined(separator: " + ")
  }

  private var recordingHotkeyDescription: String {
    guard !hotkeyRecordingKeys.isEmpty else { return "修飾キーと通常キーを同時に押します" }
    return "検出中: " + hotkeyRecordingKeys.map(hotkeyDisplayName).joined(separator: " + ")
  }

  private func hotkeyDisplayName(_ key: String) -> String {
    switch key {
    case "cmd": return "⌘"
    case "shift": return "⇧"
    case "opt": return "⌥"
    case "ctrl": return "⌃"
    case "return": return "Return"
    case "escape": return "Esc"
    case "delete": return "Delete"
    case "space": return "Space"
    case "tab": return "Tab"
    case "left": return "←"
    case "right": return "→"
    case "up": return "↑"
    case "down": return "↓"
    default: return key.uppercased()
    }
  }

  /// ハードウェアキーボードで検出したキー（修飾キー＋通常キー1つ）を、現在記録中の組み合わせへ反映する。
  /// 0.3秒キー入力が無ければ確定し、記録モードを終了する（複数キーを少しずつ押しても1つの組み合わせとして拾うため）
  private func commitDetectedHotkey(modifiers: [String], key: String) {
    guard isRecordingHotkey else { return }

    let existingRegularKeys = hotkeyRecordingKeys.filter { !modifierKeys.contains($0) }
    hotkeyRecordingKeys = modifiers + existingRegularKeys
    if !hotkeyRecordingKeys.contains(key) {
      hotkeyRecordingKeys.append(key)
    }

    hotkeyRecordingGeneration += 1
    let generation = hotkeyRecordingGeneration
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      guard generation == hotkeyRecordingGeneration, isRecordingHotkey else { return }
      draft.action.keys = hotkeyRecordingKeys
      isRecordingHotkey = false
    }
  }

  /// `HotkeyHardwareKeyCapture`（UIKitの`pressesBegan`ベース）から呼ばれる、物理キー入力の受け口
  private func handleHardwareKeyPress(modifiers: UIKeyModifierFlags, key: UIKey) {
    guard isRecordingHotkey, let keyName = recordedKeyName(for: key) else { return }
    commitDetectedHotkey(modifiers: modifierNames(from: modifiers), key: keyName)
  }

  /// UIKitが`pressesBegan`より先に解決する方向キーの`UIKeyCommand`からの受け口
  private func handleHardwareDirectionalKeyPress(modifiers: UIKeyModifierFlags, key: String) {
    guard isRecordingHotkey else { return }
    commitDetectedHotkey(modifiers: modifierNames(from: modifiers), key: key)
  }

  private func modifierNames(from flags: UIKeyModifierFlags) -> [String] {
    var modifiers: [String] = []
    if flags.contains(.command) { modifiers.append("cmd") }
    if flags.contains(.shift) { modifiers.append("shift") }
    if flags.contains(.alternate) { modifiers.append("opt") }
    if flags.contains(.control) { modifiers.append("ctrl") }
    return modifiers
  }

  private func recordedKeyName(for uiKey: UIKey) -> String? {
    switch uiKey.keyCode {
    case .keyboardReturnOrEnter, .keypadEnter: return "return"
    case .keyboardTab: return "tab"
    case .keyboardSpacebar: return "space"
    case .keyboardDeleteOrBackspace, .keyboardDeleteForward: return "delete"
    case .keyboardEscape: return "escape"
    case .keyboardLeftArrow: return "left"
    case .keyboardRightArrow: return "right"
    case .keyboardUpArrow: return "up"
    case .keyboardDownArrow: return "down"
    case .keyboardLeftGUI, .keyboardRightGUI,
         .keyboardLeftShift, .keyboardRightShift,
         .keyboardLeftAlt, .keyboardRightAlt,
         .keyboardLeftControl, .keyboardRightControl:
      // 修飾キー単体の押下は「メインキー」として扱わない。押されている修飾キー自体は
      // 直後（または同時）に届くメインキーのUIPressのmodifierFlagsから拾うため、ここではnilを返す
      return nil
    default:
      let character = uiKey.charactersIgnoringModifiers.lowercased()
      guard !character.isEmpty else { return nil }
      let supportedCharacters = "abcdefghijklmnopqrstuvwxyz0123456789-=[]\\;',./`"
      return supportedCharacters.contains(character) ? character : nil
    }
  }

  private func keyPickerRow(_ keys: [KeyDefinition]) -> some View {
    HStack(spacing: 4) {
      ForEach(keys) { key in
        let isSelected = keyBinding.wrappedValue == key.keyName
        Button {
          keyBinding.wrappedValue = key.keyName
        } label: {
          Text(key.label)
            .font(.caption2)
            .foregroundStyle(isSelected ? Color.white : GamingPalette.foreground)
            .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.plain)
        .background(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isSelected ? themeStore.accentColor : GamingPalette.muted.opacity(0.6))
        )
        .layoutPriority(key.widthWeight)
        .frame(minWidth: 24 * key.widthWeight)
      }
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

  private var labelBinding: Binding<String> {
    Binding(
      get: { draft.label },
      set: {
        draft.label = $0
        automaticallyNamesButton = false
      }
    )
  }

  // MARK: - ボタン名の自動命名

  /// 定型文からボタン名を作るときに残す最大文字数
  private static let maximumAutomaticNameLength = 12

  /// 自動命名が有効な間だけ、選んだアクションの内容に合わせてボタン名を決め直す
  private func prepareAppearance() {
    guard automaticallyNamesButton, let name = automaticButtonName() else { return }
    draft.label = name
  }

  /// 現在のアクション内容にふさわしいボタン名を返す（名前を決められない場合はnil）
  private func automaticButtonName() -> String? {
    switch draft.action.type {
    case .launchApp, .activateApplication:
      return draft.action.target.flatMap { applicationDisplayName(from: $0) } ?? selectedActionChoice?.title
    case .quitApplication:
      guard let applicationName = draft.action.target.flatMap({ applicationDisplayName(from: $0) }) else {
        return selectedActionChoice?.title
      }
      return "\(applicationName)を終了"
    case .openURL:
      return websiteDisplayName(from: draft.action.target) ?? selectedActionChoice?.title
    case .hotkey:
      let keys = draft.action.keys ?? []
      guard !keys.isEmpty else { return selectedActionChoice?.title }
      return keys.map(hotkeyDisplayName).joined(separator: " + ")
    case .typeText:
      return textDisplayName(from: draft.action.text) ?? selectedActionChoice?.title
    case .setVolume:
      // 既定値が二重定義にならないよう、入力欄と同じBindingから現在値を取る
      return "音量 \(volumeBinding.wrappedValue)%"
    case .delay:
      return "待機 \(msBinding.wrappedValue)ms"
    case .windowLayout:
      guard let preset = draft.action.preset.flatMap({ WindowLayoutPreset(rawValue: $0) }) else {
        return selectedActionChoice?.title
      }
      return preset.displayName
    case .openFinderFolder:
      return folderDisplayName(from: draft.action.target) ?? selectedActionChoice?.title
    case .createFinderFolder:
      guard let folderName = draft.action.folderName?.trimmingCharacters(in: .whitespacesAndNewlines),
            !folderName.isEmpty else {
        return selectedActionChoice?.title
      }
      return "\(folderName)を作成"
    case .multiAction, .openFolder, .mediaKey, .systemAction:
      return selectedActionChoice?.title
    case .activateTab, .closeTab:
      // タブ一覧画面から作られる際にタブのタイトルがラベルへ入るため、ここでは上書きしない
      return nil
    }
  }

  /// URLから「github.com」のような表示名を作る（先頭のwww.は省く）
  private func websiteDisplayName(from target: String?) -> String? {
    guard let trimmed = target?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
      return nil
    }
    // スキームを省略して入力されたURLでもホスト名を取り出せるようにする
    let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
    guard let host = URL(string: normalized)?.host else { return trimmed }
    let wwwPrefix = "www."
    return host.hasPrefix(wwwPrefix) ? String(host.dropFirst(wwwPrefix.count)) : host
  }

  /// 定型文の先頭だけを取り出してボタン名にする
  private func textDisplayName(from text: String?) -> String? {
    guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
      return nil
    }
    // 複数行の定型文でもボタン名は1行に収める
    let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
    guard firstLine.count > Self.maximumAutomaticNameLength else { return firstLine }
    return String(firstLine.prefix(Self.maximumAutomaticNameLength)) + "…"
  }

  /// フォルダのパスから末尾のフォルダ名を取り出す
  private func folderDisplayName(from target: String?) -> String? {
    guard let trimmed = target?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
      return nil
    }
    let folderName = URL(fileURLWithPath: trimmed).lastPathComponent
    return folderName.isEmpty ? trimmed : folderName
  }

  private func applicationDisplayName(from target: String) -> String? {
    let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let pathName = URL(fileURLWithPath: trimmed).deletingPathExtension().lastPathComponent
    if trimmed.contains("/") {
      return pathName
    }
    if trimmed.lowercased().hasSuffix(".app") {
      return String(trimmed.dropLast(4))
    }
    if trimmed.contains("."), let bundleName = trimmed.split(separator: ".").last {
      return String(bundleName)
    }
    return trimmed
  }

  private var targetBinding: Binding<String> {
    Binding(get: { draft.action.target ?? "" }, set: { draft.action.target = $0 })
  }

  private var textBinding: Binding<String> {
    Binding(get: { draft.action.text ?? "" }, set: { draft.action.text = $0 })
  }

  private var folderNameBinding: Binding<String> {
    Binding(get: { draft.action.folderName ?? "" }, set: { draft.action.folderName = $0 })
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

// MARK: - 実機キーボードでのホットキー記録（ハードウェアキー入力キャプチャ）

/// ハードウェアキーボードの物理キー入力を直接検知するための橋渡し。
/// Form内のフォーカス処理を避けるためNavigationStackのoverlayに置き、通常キーは`pressesBegan`、
/// 方向キーは優先度付き`UIKeyCommand`で受け取る。
private struct HotkeyHardwareKeyCapture: UIViewRepresentable {
  @Binding var isActive: Bool
  let onKeyPress: (UIKeyModifierFlags, UIKey) -> Void
  let onDirectionalKeyPress: (UIKeyModifierFlags, String) -> Void

  func makeUIView(context: Context) -> KeyCaptureUIView {
    let view = KeyCaptureUIView()
    view.onKeyPress = onKeyPress
    view.onDirectionalKeyPress = onDirectionalKeyPress
    view.backgroundColor = .clear
    view.isAccessibilityElement = false
    return view
  }

  func updateUIView(_ uiView: KeyCaptureUIView, context: Context) {
    uiView.onKeyPress = onKeyPress
    uiView.onDirectionalKeyPress = onDirectionalKeyPress
    uiView.isCaptureActive = isActive
  }
}

/// `pressesBegan`で物理キー入力を検知するだけの、見た目を持たない実体View
private final class KeyCaptureUIView: UIView {
  var onKeyPress: ((UIKeyModifierFlags, UIKey) -> Void)?
  var onDirectionalKeyPress: ((UIKeyModifierFlags, String) -> Void)?

  var isCaptureActive = false {
    didSet {
      guard isCaptureActive != oldValue else { return }
      if isCaptureActive {
        requestFirstResponder()
      } else {
        heldModifierFlags = []
        if isFirstResponder { resignFirstResponder() }
      }
    }
  }

  /// 修飾キー単体の押下/解放を自前で追跡した「現在押されている修飾キー」の集合。
  /// option+commandのように複数の修飾キーとメインキーがほぼ同時に押されると、OSが
  /// それらを1回の`pressesBegan`呼び出しへまとめて渡してくることがあり、その際
  /// メインキー側の`UIKey.modifierFlags`だけでは同じバッチ内の別の修飾キー分が
  /// 反映されないことがある。そのため自前で保持している状態と合成して確実に拾う
  private var heldModifierFlags: UIKeyModifierFlags = []

  override var canBecomeFirstResponder: Bool { true }

  /// 方向キーはForm/UICollectionViewのフォーカスエンジンが`pressesBegan`より前に解決する。
  /// 全修飾キーの組み合わせを明示的に登録し、システム動作より優先させて記録へ渡す。
  override var keyCommands: [UIKeyCommand]? {
    isCaptureActive ? Self.directionalKeyCommands : nil
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil, isCaptureActive { requestFirstResponder() }
  }

  private func requestFirstResponder() {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.isCaptureActive, self.window != nil, !self.isFirstResponder else { return }
      self.becomeFirstResponder()
    }
  }

  @objc private func captureDirectionalKeyCommand(_ command: UIKeyCommand) {
    guard isCaptureActive, let input = command.input,
          let key = Self.directionalKeyNames[input] else { return }
    onDirectionalKeyPress?(command.modifierFlags, key)
  }

  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    var handledAny = false

    // 1st pass: このバッチに含まれる修飾キー自体の押下を先にすべて反映しておく
    // （Setは順序不定のため、メインキー側の処理より先に全件を反映する必要がある）
    for press in presses {
      if let key = press.key, let flag = Self.modifierFlag(for: key.keyCode) {
        heldModifierFlags.insert(flag)
      }
    }

    // 2nd pass: イベント自身のmodifierFlagsと自前追跡分を合成して渡す
    for press in presses {
      if let key = press.key {
        onKeyPress?(key.modifierFlags.union(heldModifierFlags), key)
        handledAny = true
      }
    }

    if !handledAny {
      super.pressesBegan(presses, with: event)
    }
  }

  override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    for press in presses {
      if let key = press.key, let flag = Self.modifierFlag(for: key.keyCode) {
        heldModifierFlags.remove(flag)
      }
    }
    super.pressesEnded(presses, with: event)
  }

  override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    for press in presses {
      if let key = press.key, let flag = Self.modifierFlag(for: key.keyCode) {
        heldModifierFlags.remove(flag)
      }
    }
    super.pressesCancelled(presses, with: event)
  }

  /// 修飾キー単体のキーコードを対応する`UIKeyModifierFlags`のビットへ変換する
  private static func modifierFlag(for keyCode: UIKeyboardHIDUsage) -> UIKeyModifierFlags? {
    switch keyCode {
    case .keyboardLeftGUI, .keyboardRightGUI: return .command
    case .keyboardLeftShift, .keyboardRightShift: return .shift
    case .keyboardLeftAlt, .keyboardRightAlt: return .alternate
    case .keyboardLeftControl, .keyboardRightControl: return .control
    default: return nil
    }
  }

  private static let directionalKeyNames = [
    UIKeyCommand.inputLeftArrow: "left",
    UIKeyCommand.inputRightArrow: "right",
    UIKeyCommand.inputUpArrow: "up",
    UIKeyCommand.inputDownArrow: "down"
  ]

  private static let directionalKeyCommands: [UIKeyCommand] = {
    let modifierFlags: [UIKeyModifierFlags] = [.command, .shift, .alternate, .control]
    var combinations: [UIKeyModifierFlags] = [[]]
    for flag in modifierFlags {
      combinations += combinations.map { $0.union(flag) }
    }

    return directionalKeyNames.keys.flatMap { input in
      combinations.map { modifiers in
        let command = UIKeyCommand(
          input: input,
          modifierFlags: modifiers,
          action: #selector(captureDirectionalKeyCommand(_:))
        )
        command.wantsPriorityOverSystemBehavior = true
        command.allowsAutomaticLocalization = false
        command.allowsAutomaticMirroring = false
        return command
      }
    }
  }()
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
         .quitApplication, .openFinderFolder, .createFinderFolder, .systemAction:
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
  ButtonEditView(button: ButtonConfig(row: 0, col: 0, label: "Chrome", iconName: "globe", action: ActionPayload(type: .launchApp, target: "Google Chrome")), connectionManager: ConnectionManager()) { _ in }
    .environment(ThemeStore())
}

private struct MacApplicationPicker: View {
  let applications: [MacApplicationInfo]
  let isLoading: Bool
  let onSelect: (MacApplicationInfo) -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Group {
        if isLoading {
          ProgressView("Macから取得中…")
        } else if applications.isEmpty {
          ContentUnavailableView("起動中のアプリがありません", systemImage: "macwindow")
        } else {
          List(applications) { application in
            Button { onSelect(application) } label: {
              HStack(spacing: 12) {
                if let data = application.iconPNGData, let image = UIImage(data: data) {
                  Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                } else {
                  Image(systemName: "macwindow")
                    .frame(width: 34, height: 34)
                    .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                  Text(application.name)
                    .foregroundStyle(GamingPalette.foreground)
                  Text(application.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(GamingPalette.mutedForeground)
                }
                Spacer()
                if application.active { Image(systemName: "circle.fill").font(.caption2).foregroundStyle(.green) }
              }
            }
            .buttonStyle(.plain)
          }
        }
      }
      .navigationTitle("アプリを選択")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
      }
    }
  }
}
