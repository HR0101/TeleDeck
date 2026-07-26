//
//  PanelView.swift
//  TeleDeck
//
//  Stream Deck風のボタングリッド画面。長押しで編集モードに入り、ボタンの追加・編集・削除ができる。
//  フォルダーボタンによる階層化と、フォアグラウンドアプリに応じたプロファイル自動切替に対応する。
//

import SwiftUI
import UIKit

struct PanelView: View {
  let connectionManager: ConnectionManager
  /// パネル固有の編集モードを、左側のコントロールレールから切り替えるため親と状態を共有する。
  @Binding var isEditMode: Bool
  /// 設定シートの表示はMainTabViewが管理するため、タップ時の処理だけを受け取る。
  var onOpenSettings: () -> Void

  @Environment(ThemeStore.self) private var themeStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage("panelView.sidebarVisible") private var isSidebarVisible = true
  @State private var profileStore = ProfileStore()
  @State private var editingButton: ButtonConfig?
  @State private var newButtonPosition: GridPosition?
  @State private var buttonPendingDeletion: ButtonConfig?
  @State private var profileChangeNotice: String?
  /// 空 = プロファイル直下。末尾の要素が現在いるフォルダーのid。無限階層に対応するためスタックで管理する
  @State private var folderStack: [UUID] = []

  /// グリッドの余白（セル間隔・外周パディング）
  private static let gridSpacing: CGFloat = 16
  private static let gridPadding: CGFloat = 20
  /// ボタンが小さくなりすぎて操作しづらくならないよう設ける下限サイズ
  private static let minimumCellSize: CGFloat = 64

  /// 現在のフォルダー階層に属するボタンのみ
  private var visibleButtons: [ButtonConfig] {
    profileStore.activeProfile.buttons.filter { $0.folderId == folderStack.last }
  }

  private var folderPath: [(id: UUID, name: String)] {
    folderStack.compactMap { id in
      profileStore.activeProfile.buttons.first(where: { $0.id == id }).map { (id, $0.label) }
    }
  }

  var body: some View {
    HStack(spacing: 0) {
      if isSidebarVisible {
        panelSidebar
          .transition(.move(edge: .leading).combined(with: .opacity))
      } else {
        collapsedSidebarRail
          .transition(.move(edge: .leading).combined(with: .opacity))
      }

      ZStack {
        GamingPalette.background.opacity(0.72)

        GeometryReader { proxy in
          ScrollView([.horizontal, .vertical], showsIndicators: false) {
            gridBody(availableSize: proxy.size)
          }
        }
      }
    }
    .background(GamingPalette.background.opacity(0.45))
    .sheet(item: $editingButton) { button in
      ButtonEditView(button: button, connectionManager: connectionManager) { updated in
        profileStore.updateButton(updated)
      }
    }
    .sheet(item: $newButtonPosition) { position in
      ButtonEditView(
        button: ButtonConfig(
          row: position.row,
          col: position.col,
          label: "新しいボタン",
          iconName: "square.grid.2x2",
          action: ActionPayload(type: .launchApp, target: ""),
          folderId: folderStack.last
        ),
        connectionManager: connectionManager
      ) { created in
        profileStore.addButton(created)
      }
    }
    .confirmationDialog(
      "「\(buttonPendingDeletion?.label ?? "ボタン")」を削除しますか？",
      isPresented: Binding(
        get: { buttonPendingDeletion != nil },
        set: { if !$0 { buttonPendingDeletion = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("削除", role: .destructive) {
        if let button = buttonPendingDeletion {
          profileStore.deleteButton(id: button.id)
        }
        buttonPendingDeletion = nil
      }
      Button("キャンセル", role: .cancel) {
        buttonPendingDeletion = nil
      }
    }
    .alert("プロファイルが切り替わりました", isPresented: Binding(
      get: { profileChangeNotice != nil },
      set: { if !$0 { profileChangeNotice = nil } }
    )) {
      Button("OK", role: .cancel) { profileChangeNotice = nil }
    } message: {
      Text(profileChangeNotice ?? "")
    }
    .onAppear {
      connectionManager.onProfileSync = { profiles, activeProfileId in
        let previousActiveId = profileStore.activeProfileId
        let previousActiveName = profileStore.activeProfile.name
        profileStore.applySync(profiles: profiles, activeProfileId: activeProfileId)
        if previousActiveId != activeProfileId,
           !profiles.contains(where: { $0.id == previousActiveId }),
           let newProfile = profiles.first(where: { $0.id == activeProfileId }) {
          profileChangeNotice = "Mac側で使用中だった「\(previousActiveName)」が削除されたため、「\(newProfile.name)」に切り替えました。"
        }
        // プロファイルが切り替わった場合に前のプロファイルのフォルダー階層に居続けないようリセットする
        folderStack = []
      }
      profileStore.onLocalChange = { profiles, activeProfileId in
        connectionManager.sendProfileUpdate(profiles: profiles, activeProfileId: activeProfileId)
      }
    }
  }

  private var panelSidebar: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 8) {
        Label("パネル", systemImage: "square.grid.3x3.fill")
          .font(.headline.weight(.semibold))
          .foregroundStyle(GamingPalette.foreground)
          .symbolRenderingMode(.hierarchical)

        Spacer(minLength: 0)

        sidebarToggleButton
      }

      profileMenu

      folderNavigator
        .frame(maxHeight: .infinity, alignment: .top)

      if isEditMode {
        Label("タップで編集\nドラッグで移動・＋で追加", systemImage: "pencil.and.list.clipboard")
          .font(.caption.weight(.medium))
          .foregroundStyle(GamingPalette.mutedForeground)
          .fixedSize(horizontal: false, vertical: true)
          .padding(10)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            themeStore.accentColor.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
          )
      }

      editModeButton
      settingsButton
    }
    .padding(14)
    .frame(width: 240)
    .background(.ultraThinMaterial)
    .background(GamingPalette.card.opacity(0.7))
    .overlay(alignment: .trailing) {
      Rectangle()
        .fill(themeStore.accentColor.opacity(isEditMode ? 0.7 : 0.24))
        .frame(width: 1)
    }
  }

  private var collapsedSidebarRail: some View {
    VStack {
      sidebarToggleButton
      Spacer()
    }
    .padding(.vertical, 8)
    .frame(width: 56)
    .background(.ultraThinMaterial)
    .background(GamingPalette.card.opacity(0.7))
    .overlay(alignment: .trailing) {
      Rectangle()
        .fill(themeStore.accentColor.opacity(0.24))
        .frame(width: 1)
    }
  }

  private var sidebarToggleButton: some View {
    Button {
      toggleSidebar()
    } label: {
      Image(systemName: "sidebar.left")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(themeStore.accentColor)
        .frame(width: 44, height: 44)
        .background(
          GamingPalette.muted.opacity(0.58),
          in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(PanelToolbarButtonStyle())
    .accessibilityLabel(isSidebarVisible ? "サイドバーを非表示" : "サイドバーを表示")
  }

  private func toggleSidebar() {
    if reduceMotion {
      isSidebarVisible.toggle()
    } else {
      withAnimation(.easeOut(duration: 0.2)) {
        isSidebarVisible.toggle()
      }
    }
  }

  private var profileMenu: some View {
    Menu {
      ForEach(profileStore.profiles) { profile in
        Button {
          profileStore.setActiveProfile(id: profile.id)
          folderStack = []
          isEditMode = false
        } label: {
          if profile.id == profileStore.activeProfileId {
            Label(profile.name, systemImage: "checkmark")
          } else {
            Text(profile.name)
          }
        }
      }
      Divider()
      Label("新規作成・編集はMacで管理", systemImage: "desktopcomputer")
    } label: {
      HStack(spacing: 9) {
        Image(systemName: "square.grid.3x3.fill")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(themeStore.accentColor)

        VStack(alignment: .leading, spacing: 1) {
          Text("プロファイル")
            .font(.caption2)
            .foregroundStyle(GamingPalette.mutedForeground)
          Text(profileStore.activeProfile.name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(GamingPalette.foreground)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.82)
        }

        Spacer(minLength: 4)

        Image(systemName: "chevron.down")
          .font(.caption2.weight(.bold))
          .foregroundStyle(themeStore.accentColor)
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54)
      .background(
        GamingPalette.card.opacity(0.78),
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(themeStore.accentColor.opacity(0.34), lineWidth: 1)
      }
    }
    .buttonStyle(PanelToolbarButtonStyle())
    .accessibilityLabel("プロファイルを切り替える")
    .accessibilityValue(profileStore.activeProfile.name)
  }

  private var folderNavigator: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("場所")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(GamingPalette.mutedForeground)
        .padding(.horizontal, 4)

      ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 4) {
          folderRow(
            title: "ホーム",
            systemImage: "house",
            isCurrent: folderStack.isEmpty,
            indentation: 0
          ) {
            folderStack = []
          }

          ForEach(Array(folderPath.enumerated()), id: \.offset) { index, folder in
            folderRow(
              title: folder.name,
              systemImage: "folder",
              isCurrent: index == folderPath.count - 1,
              indentation: CGFloat(min(index + 1, 4)) * 8
            ) {
              folderStack = Array(folderStack.prefix(index + 1))
            }
          }
        }
      }
    }
  }

  private func folderRow(
    title: String,
    systemImage: String,
    isCurrent: Bool,
    indentation: CGFloat,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 9) {
        Image(systemName: systemImage)
          .font(.system(size: 13, weight: .semibold))
          .frame(width: 18)

        Text(title)
          .font(.subheadline.weight(isCurrent ? .semibold : .regular))
          .lineLimit(1)
          .truncationMode(.middle)

        Spacer(minLength: 4)

        if isCurrent {
          Image(systemName: "checkmark")
            .font(.caption.weight(.bold))
        }
      }
      .foregroundStyle(isCurrent ? themeStore.accentColor : GamingPalette.mutedForeground)
      .padding(.leading, 10 + indentation)
      .padding(.trailing, 10)
      .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
      .background(
        isCurrent ? themeStore.accentColor.opacity(0.13) : Color.clear,
        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
      )
      .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .buttonStyle(PanelToolbarButtonStyle())
    .disabled(isCurrent)
  }

  private var editModeButton: some View {
    Button {
      withAnimation(.easeOut(duration: 0.18)) {
        isEditMode.toggle()
      }
    } label: {
      HStack(spacing: 9) {
        Image(systemName: isEditMode ? "checkmark" : "pencil")
          .font(.system(size: 15, weight: .semibold))

        Text(isEditMode ? "編集を完了" : "パネルを編集")
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)

        Spacer(minLength: 0)
      }
      .foregroundStyle(isEditMode ? Color.white : GamingPalette.foreground)
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, minHeight: 44)
      .background(
        isEditMode ? themeStore.accentColor : GamingPalette.muted.opacity(0.75),
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(themeStore.accentColor.opacity(isEditMode ? 0.9 : 0.28), lineWidth: 1)
      }
    }
    .buttonStyle(PanelToolbarButtonStyle())
    .accessibilityValue(isEditMode ? "編集中" : "")
  }

  private var settingsButton: some View {
    Button {
      onOpenSettings()
    } label: {
      HStack(spacing: 9) {
        Image(systemName: "gearshape")
          .font(.system(size: 15, weight: .semibold))

        Text("設定")
          .font(.subheadline.weight(.semibold))

        Spacer(minLength: 0)
      }
      .foregroundStyle(GamingPalette.foreground)
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, minHeight: 44)
      .background(
        GamingPalette.muted.opacity(0.58),
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      )
    }
    .buttonStyle(PanelToolbarButtonStyle())
  }

  /// 行数・列数と使える表示領域から、隙間が大きくなりすぎない正方形ボタンの一辺のサイズを求める。
  /// 幅・高さ双方の制約のうち小さい方に合わせることで、グリッド全体を余白なく敷き詰める
  private func cellSize(availableSize: CGSize, rows: Int, columns: Int) -> CGFloat {
    guard rows > 0, columns > 0 else { return Self.minimumCellSize }

    let availableWidth = availableSize.width - Self.gridPadding * 2
    let availableHeight = availableSize.height - Self.gridPadding * 2

    let widthPerCell = (availableWidth - Self.gridSpacing * CGFloat(columns - 1)) / CGFloat(columns)
    let heightPerCell = (availableHeight - Self.gridSpacing * CGFloat(rows - 1)) / CGFloat(rows)

    return min(max(min(widthPerCell, heightPerCell), Self.minimumCellSize), 148)
  }

  private func gridBody(availableSize: CGSize) -> some View {
    let rows = profileStore.activeProfile.gridRows
    let gridColumns = profileStore.activeProfile.gridColumns
    let size = cellSize(availableSize: availableSize, rows: rows, columns: gridColumns)
    let columns = Array(repeating: GridItem(.fixed(size), spacing: Self.gridSpacing), count: gridColumns)

    return LazyVGrid(columns: columns, spacing: Self.gridSpacing) {
      ForEach(0..<(rows * gridColumns), id: \.self) { index in
        let row = index / gridColumns
        let col = index % gridColumns
        gridCell(row: row, col: col, size: size)
      }
    }
    .padding(Self.gridPadding)
    .frame(
      minWidth: availableSize.width,
      minHeight: availableSize.height,
      alignment: .top
    )
    // 行数・列数が変わった際にLazyVGridが古いセルサイズのレイアウトを使い回してしまうことがあるため、
    // グリッドの形が変わるたびに別のビューとして扱われるよう明示的にidを与え、必ず作り直させる
    .id("\(rows)x\(gridColumns)")
  }

  @ViewBuilder
  private func gridCell(row: Int, col: Int, size: CGFloat) -> some View {
    Group {
      if let button = visibleButtons.first(where: { $0.row == row && $0.col == col }) {
        buttonCell(button, size: size)
      } else if isEditMode {
        addCell(row: row, col: col, size: size)
      } else {
        Color.clear.frame(width: size, height: size)
      }
    }
    // 編集モード中のみ、他のボタンをこのマスへドラッグ&ドロップして移動できるようにする
    .dropDestination(for: String.self) { items, _ in
      guard isEditMode, let draggedIdString = items.first else { return false }
      moveButton(withIdString: draggedIdString, toRow: row, col: col)
      return true
    }
  }

  /// ドラッグされたボタンを指定マスへ移動する。移動先に既にボタンがある場合は元の位置と入れ替える
  private func moveButton(withIdString draggedIdString: String, toRow row: Int, col: Int) {
    guard let draggedId = UUID(uuidString: draggedIdString),
          let draggedButton = visibleButtons.first(where: { $0.id == draggedId }),
          draggedButton.row != row || draggedButton.col != col
    else { return }

    if let targetButton = visibleButtons.first(where: { $0.row == row && $0.col == col }) {
      var swappedTarget = targetButton
      swappedTarget.row = draggedButton.row
      swappedTarget.col = draggedButton.col
      profileStore.updateButton(swappedTarget)
    }

    var movedButton = draggedButton
    movedButton.row = row
    movedButton.col = col
    profileStore.updateButton(movedButton)
  }

  @ViewBuilder
  private func buttonCell(_ button: ButtonConfig, size: CGFloat) -> some View {
    ZStack(alignment: .topTrailing) {
      // .draggableはこのボタン単体にのみ付与する。ZStack全体に付与すると、上に重なる
      // 削除ボタンのタップまでドラッグの当たり判定に飲み込まれてしまうため
      contentButton(button, size: size)

      if isEditMode {
        Button {
          buttonPendingDeletion = button
        } label: {
          Image(systemName: "xmark.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, GamingPalette.destructive)
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .offset(x: 6, y: -6)
        .accessibilityLabel("\(button.label)を削除")
      }

      if !isEditMode, button.action.type == .openFolder {
        Image(systemName: "chevron.right.circle.fill")
          .foregroundStyle(themeStore.accentColor)
          .padding(8)
      }
    }
    .onLongPressGesture {
      isEditMode = true
    }
  }

  @ViewBuilder
  private func contentButton(_ button: ButtonConfig, size: CGFloat) -> some View {
    let core = Button {
      if isEditMode {
        editingButton = button
      } else if button.action.type == .openFolder {
        folderStack.append(button.id)
      } else {
        connectionManager.execute(button.action)
      }
    } label: {
      VStack(spacing: Self.iconLabelSpacing(for: size)) {
        panelIcon(for: button, size: size)
        Text(button.label)
          .font(.system(size: Self.labelFontSize(for: size), weight: .semibold))
          .foregroundStyle(GamingPalette.foreground)
          .shadow(color: .black.opacity(0.65), radius: 2, y: 1)
      }
      .frame(width: size, height: size)
      .streamDeckGlassTile(
        accentColor: themeStore.accentColor,
        isEditing: isEditMode
      )
    }
    .buttonStyle(PanelTileButtonStyle())

    // 通常モードでの長押し（編集モードへの切替）とドラッグ操作が競合しないよう、
    // ドラッグでの移動は編集モード中のみ有効にする
    if isEditMode {
      core.draggable(button.id.uuidString)
    } else {
      core
    }
  }

  @ViewBuilder
  private func panelIcon(for button: ButtonConfig, size: CGFloat) -> some View {
    let iconSize = Self.iconSize(for: size)

    if button.action.type == .launchApp || button.action.type == .openURL,
       let iconData = button.applicationIconPNGData,
       let icon = UIImage(data: iconData) {
      Image(uiImage: icon)
        .resizable()
        .scaledToFit()
        .frame(width: iconSize, height: iconSize)
        .clipShape(RoundedRectangle(cornerRadius: Self.iconCornerRadius(for: size), style: .continuous))
    } else {
      AnimatedIconView(
        iconKind: button.iconKind,
        iconName: button.iconName,
        iconImageFileName: button.iconImageFileName
      )
      .font(.system(size: iconSize * 0.74))
      .frame(width: iconSize, height: iconSize)
      .foregroundStyle(themeStore.accentColor)
    }
  }

  /// ボタンの一辺のサイズに応じてアイコン・文字・余白を比例させ、グリッドの列数・行数を変えても
  /// 中身が小さすぎたり不釣り合いに大きすぎたりしないようにする
  private static func iconSize(for cellSize: CGFloat) -> CGFloat {
    min(max(cellSize * 0.42, 24), 64)
  }

  private static func iconCornerRadius(for cellSize: CGFloat) -> CGFloat {
    min(max(cellSize * 0.1, 6), 12)
  }

  private static func labelFontSize(for cellSize: CGFloat) -> CGFloat {
    min(max(cellSize * 0.13, 10), 16)
  }

  private static func iconLabelSpacing(for cellSize: CGFloat) -> CGFloat {
    min(max(cellSize * 0.09, 4), 10)
  }

  private func addCell(row: Int, col: Int, size: CGFloat) -> some View {
    Button {
      newButtonPosition = GridPosition(row: row, col: col)
    } label: {
      Image(systemName: "plus")
        .font(.system(size: min(max(size * 0.26, 18), 32)))
        .foregroundStyle(GamingPalette.mutedForeground)
        .frame(width: size, height: size)
        .streamDeckGlassTile(
          accentColor: themeStore.accentColor,
          isEditing: true,
          isEmpty: true
        )
    }
    .buttonStyle(.plain)
    .accessibilityLabel("ボタンを追加")
  }
}

private struct PanelToolbarButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .opacity(configuration.isPressed ? 0.84 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

private struct PanelTileButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .opacity(configuration.isPressed ? 0.82 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

private struct StreamDeckGlassTileModifier: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  let accentColor: Color
  let isEditing: Bool
  let isEmpty: Bool

  func body(content: Content) -> some View {
    content
      .background {
        ZStack {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
              LinearGradient(
                colors: [
                  Color.white.opacity(isEmpty ? 0.035 : 0.10),
                  GamingPalette.card.opacity(isEmpty ? 0.34 : 0.88),
                  Color.black.opacity(isEmpty ? 0.22 : 0.58)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )

          if !reduceTransparency {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .fill(.ultraThinMaterial)
              .opacity(isEmpty ? 0.16 : 0.34)
          }

          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
              LinearGradient(
                stops: [
                  .init(color: .white.opacity(isEmpty ? 0.04 : 0.22), location: 0),
                  .init(color: .white.opacity(isEmpty ? 0.01 : 0.055), location: 0.38),
                  .init(color: .clear, location: 0.62)
                ],
                startPoint: .top,
                endPoint: .bottom
              )
            )
        }
      }
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(
            LinearGradient(
              colors: [
                Color.white.opacity(isEmpty ? 0.14 : 0.52),
                accentColor.opacity(isEditing ? 0.8 : 0.34),
                Color.black.opacity(0.72)
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            style: StrokeStyle(lineWidth: isEditing ? 1.5 : 1.1, dash: isEmpty ? [5, 4] : [])
          )
      }
      .overlay {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
          .inset(by: 3)
          .stroke(Color.white.opacity(isEmpty ? 0.025 : 0.075), lineWidth: 0.8)
      }
      .overlay(alignment: .top) {
        Capsule()
          .fill(Color.white.opacity(isEmpty ? 0.08 : 0.34))
          .frame(width: 34, height: 2)
          .blur(radius: 0.4)
          .padding(.top, 5)
      }
      .shadow(color: .black.opacity(isEmpty ? 0.2 : 0.48), radius: 10, y: 6)
      .shadow(color: accentColor.opacity(isEmpty ? 0.08 : 0.2), radius: 14, y: 2)
  }
}

private extension View {
  func streamDeckGlassTile(
    accentColor: Color,
    isEditing: Bool = false,
    isEmpty: Bool = false
  ) -> some View {
    modifier(
      StreamDeckGlassTileModifier(
        accentColor: accentColor,
        isEditing: isEditing,
        isEmpty: isEmpty
      )
    )
  }
}

/// 新規ボタンを追加する先のグリッド座標（シート表示の`item:`にはIdentifiableが必要なため用意）
private struct GridPosition: Identifiable {
  let row: Int
  let col: Int
  var id: String { "\(row)-\(col)" }
}

#Preview {
  PanelView(connectionManager: ConnectionManager(), isEditMode: .constant(false), onOpenSettings: {})
    .environment(ThemeStore())
}
