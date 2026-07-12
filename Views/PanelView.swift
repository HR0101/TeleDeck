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
  /// 空 = プロファイル直下。末尾の要素が現在いるフォルダーのid。無限階層に対応するためスタックで管理する
  @State private var folderStack: [UUID] = []

  private let columns = Array(repeating: GridItem(.flexible()), count: ProfileStore.gridCols)

  /// 現在のフォルダー階層に属するボタンのみ
  private var visibleButtons: [ButtonConfig] {
    profileStore.activeProfile.buttons.filter { $0.folderId == folderStack.last }
  }

  var body: some View {
    VStack {
      HStack {
        Text("TeleDeck ｜ \(profileStore.activeProfile.name)")
          .font(.headline)
          .foregroundStyle(GamingPalette.foreground)
        Spacer()
        Button(isEditMode ? "完了" : "編集") {
          isEditMode.toggle()
        }
        .foregroundStyle(themeStore.accentColor)
      }
      .padding(.horizontal)
      .padding(.top)

      if !folderStack.isEmpty {
        HStack {
          Button {
            folderStack.removeLast()
          } label: {
            Label("戻る", systemImage: "chevron.left")
          }
          .foregroundStyle(themeStore.accentColor)
          Spacer()
        }
        .padding(.horizontal)
      }

      LazyVGrid(columns: columns, spacing: 16) {
        ForEach(0..<(ProfileStore.gridRows * ProfileStore.gridCols), id: \.self) { index in
          let row = index / ProfileStore.gridCols
          let col = index % ProfileStore.gridCols
          gridCell(row: row, col: col)
        }
      }
      .padding()

      Spacer()
    }
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
        .frame(maxWidth: .infinity, minHeight: 80)
        .gamingCard(accentColor: themeStore.accentColor)
      }
      .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor))

      if isEditMode {
        Button {
          profileStore.deleteButton(id: button.id)
        } label: {
          Image(systemName: "xmark.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, GamingPalette.destructive)
        }
        .offset(x: 6, y: -6)
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
        .frame(maxWidth: .infinity, minHeight: 80)
        .gamingCard(accentColor: themeStore.accentColor)
    }
    .buttonStyle(.plain)
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
