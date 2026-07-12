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
  /// 編集モードの切り替えボタンはMainTabViewのツールバー（設定ボタンの隣）に置くため、
  /// パネル自身の見出し行を圧縮できるよう親から状態を受け取る
  @Binding var isEditMode: Bool

  @Environment(ThemeStore.self) private var themeStore
  @State private var profileStore = ProfileStore()
  @State private var editingButton: ButtonConfig?
  @State private var newButtonPosition: GridPosition?
  @State private var buttonPendingDeletion: ButtonConfig?
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
    VStack(spacing: 0) {
      panelHeader

      GeometryReader { proxy in
        ScrollView {
          gridBody(availableSize: proxy.size)
        }
      }
    }
    .background(GamingPalette.background.opacity(0.45))
    .sheet(item: $editingButton) { button in
      ButtonEditView(button: button) { updated in
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
        )
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
    .onAppear {
      connectionManager.onProfileSync = { profiles, activeProfileId in
        profileStore.applySync(profiles: profiles, activeProfileId: activeProfileId)
        // プロファイルが切り替わった場合に前のプロファイルのフォルダー階層に居続けないようリセットする
        folderStack = []
      }
      profileStore.onLocalChange = { profiles, activeProfileId in
        connectionManager.sendProfileUpdate(profiles: profiles, activeProfileId: activeProfileId)
      }
    }
  }

  private var panelHeader: some View {
    HStack(spacing: 12) {
      profileMenu
      breadcrumb
      Spacer()
      if isEditMode {
        Label("ボタンをタップして編集。＋で追加", systemImage: "info.circle")
          .font(.caption)
          .foregroundStyle(GamingPalette.mutedForeground)
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 8)
    .background(.ultraThinMaterial)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(themeStore.accentColor.opacity(isEditMode ? 0.75 : 0.28))
        .frame(height: 1)
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
    } label: {
      HStack(spacing: 6) {
        Text(profileStore.activeProfile.name)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(GamingPalette.foreground)
        Image(systemName: "chevron.down")
          .font(.caption2.weight(.bold))
          .foregroundStyle(themeStore.accentColor)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .gamingCard(accentColor: themeStore.accentColor, cornerRadius: 10)
    }
    .accessibilityLabel("プロファイルを切り替える")
  }

  private var breadcrumb: some View {
    HStack(spacing: 5) {
      Button {
        folderStack = []
      } label: {
        Label("ホーム", systemImage: "square.grid.3x3")
      }
      .disabled(folderStack.isEmpty)

      ForEach(Array(folderPath.enumerated()), id: \.offset) { index, folder in
        Image(systemName: "chevron.right")
          .font(.caption2)
          .foregroundStyle(GamingPalette.mutedForeground)
        Button(folder.name) {
          folderStack = Array(folderStack.prefix(index + 1))
        }
        .disabled(index == folderPath.count - 1)
      }
    }
    .font(.caption.weight(.medium))
    .foregroundStyle(themeStore.accentColor)
  }

  /// 行数・列数と使える表示領域から、隙間が大きくなりすぎない正方形ボタンの一辺のサイズを求める。
  /// 幅・高さ双方の制約のうち小さい方に合わせることで、グリッド全体を余白なく敷き詰める
  private func cellSize(availableSize: CGSize, rows: Int, columns: Int) -> CGFloat {
    guard rows > 0, columns > 0 else { return Self.minimumCellSize }

    let availableWidth = availableSize.width - Self.gridPadding * 2
    let availableHeight = availableSize.height - Self.gridPadding * 2

    let widthPerCell = (availableWidth - Self.gridSpacing * CGFloat(columns - 1)) / CGFloat(columns)
    let heightPerCell = (availableHeight - Self.gridSpacing * CGFloat(rows - 1)) / CGFloat(rows)

    return max(min(widthPerCell, heightPerCell), Self.minimumCellSize)
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
    .frame(maxWidth: .infinity)
    // 行数・列数が変わった際にLazyVGridが古いセルサイズのレイアウトを使い回してしまうことがあるため、
    // グリッドの形が変わるたびに別のビューとして扱われるよう明示的にidを与え、必ず作り直させる
    .id("\(rows)x\(gridColumns)")
  }

  @ViewBuilder
  private func gridCell(row: Int, col: Int, size: CGFloat) -> some View {
    if let button = visibleButtons.first(where: { $0.row == row && $0.col == col }) {
      buttonCell(button, size: size)
    } else if isEditMode {
      addCell(row: row, col: col, size: size)
    } else {
      Color.clear.frame(width: size, height: size)
    }
  }

  @ViewBuilder
  private func buttonCell(_ button: ButtonConfig, size: CGFloat) -> some View {
    ZStack(alignment: .topTrailing) {
      Button {
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

      if isEditMode {
        Button {
          buttonPendingDeletion = button
        } label: {
          Image(systemName: "xmark.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, GamingPalette.destructive)
        }
        .offset(x: 6, y: -6)
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
  private func panelIcon(for button: ButtonConfig, size: CGFloat) -> some View {
    let iconSize = Self.iconSize(for: size)

    if button.action.type == .launchApp,
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
  PanelView(connectionManager: ConnectionManager(), isEditMode: .constant(false))
    .environment(ThemeStore())
}
