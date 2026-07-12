//
//  PanelView.swift
//  TeleDeck
//
//  Stream Deck風のボタングリッド画面。長押しで編集モードに入り、ボタンの追加・編集・削除ができる。
//  フォルダーボタンによる階層化と、フォアグラウンドアプリに応じたプロファイル自動切替に対応する。
//

import SwiftUI

struct PanelView: View {
  let connectionManager: ConnectionManager

  @Environment(ThemeStore.self) private var themeStore
  @State private var profileStore = ProfileStore()
  @State private var isEditMode = false
  @State private var editingButton: ButtonConfig?
  @State private var newButtonPosition: GridPosition?
  @State private var buttonPendingDeletion: ButtonConfig?
  /// 空 = プロファイル直下。末尾の要素が現在いるフォルダーのid。無限階層に対応するためスタックで管理する
  @State private var folderStack: [UUID] = []

  private let columns = Array(repeating: GridItem(.flexible()), count: ProfileStore.gridCols)

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

      ScrollView {
        LazyVGrid(columns: columns, spacing: 16) {
          ForEach(0..<(ProfileStore.gridRows * ProfileStore.gridCols), id: \.self) { index in
            let row = index / ProfileStore.gridCols
            let col = index % ProfileStore.gridCols
            gridCell(row: row, col: col)
          }
        }
        .padding(20)
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
    VStack(spacing: 12) {
      HStack(spacing: 12) {
        profileMenu
        Spacer()
        Button {
          withAnimation(.easeOut(duration: 0.18)) {
            isEditMode.toggle()
          }
        } label: {
          Label(isEditMode ? "編集を完了" : "パネルを編集", systemImage: isEditMode ? "checkmark" : "pencil")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor, cornerRadius: 10))
      }

      HStack(spacing: 8) {
        breadcrumb
        Spacer()
        if isEditMode {
          Label("ボタンをタップして編集。＋で追加", systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(GamingPalette.mutedForeground)
        }
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
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
      VStack(alignment: .leading, spacing: 3) {
        Text("プロファイル")
          .font(.caption2.weight(.medium))
          .foregroundStyle(GamingPalette.mutedForeground)
        HStack(spacing: 7) {
          Text(profileStore.activeProfile.name)
            .font(.headline)
            .foregroundStyle(GamingPalette.foreground)
          Image(systemName: "chevron.down")
            .font(.caption2.weight(.bold))
            .foregroundStyle(themeStore.accentColor)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
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

  @ViewBuilder
  private func gridCell(row: Int, col: Int) -> some View {
    if let button = visibleButtons.first(where: { $0.row == row && $0.col == col }) {
      buttonCell(button)
    } else if isEditMode {
      addCell(row: row, col: col)
    } else {
      Color.clear.frame(minHeight: 80)
    }
  }

  @ViewBuilder
  private func buttonCell(_ button: ButtonConfig) -> some View {
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
        VStack(spacing: 8) {
          AnimatedIconView(
            iconKind: button.iconKind,
            iconName: button.iconName,
            iconImageFileName: button.iconImageFileName
          )
          .font(.system(size: 28))
          .frame(width: 28, height: 28)
          .foregroundStyle(themeStore.accentColor)
          Text(button.label)
            .font(.caption)
            .foregroundStyle(GamingPalette.foreground)
        }
        .frame(maxWidth: .infinity, minHeight: 92)
        .gamingCard(accentColor: themeStore.accentColor)
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

  private func addCell(row: Int, col: Int) -> some View {
    Button {
      newButtonPosition = GridPosition(row: row, col: col)
    } label: {
      Image(systemName: "plus")
        .font(.system(size: 24))
        .foregroundStyle(GamingPalette.mutedForeground)
        .frame(maxWidth: .infinity, minHeight: 92)
        .gamingCard(accentColor: themeStore.accentColor)
    }
    .buttonStyle(.plain)
  }
}

private struct PanelTileButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .opacity(configuration.isPressed ? 0.86 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

/// 新規ボタンを追加する先のグリッド座標（シート表示の`item:`にはIdentifiableが必要なため用意）
private struct GridPosition: Identifiable {
  let row: Int
  let col: Int
  var id: String { "\(row)-\(col)" }
}

#Preview {
  PanelView(connectionManager: ConnectionManager())
    .environment(ThemeStore())
}
