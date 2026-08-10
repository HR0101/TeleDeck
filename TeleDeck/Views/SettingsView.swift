//
//  SettingsView.swift
//  TeleDeck
//
//  外観（ダーク/ライト/システム準拠）とアクセントカラーを設定するシート画面。
//

import SwiftUI

struct SettingsView: View {
  @Bindable var themeStore: ThemeStore
  /// 接続状態の表示と、手動での切断・再ペアリングを行うために受け取る
  let connectionManager: ConnectionManager
  @Environment(\.dismiss) private var dismiss

  @State private var isShowingUnpairConfirmation = false

  init(themeStore: ThemeStore, connectionManager: ConnectionManager) {
    self.themeStore = themeStore
    self.connectionManager = connectionManager
  }

  var body: some View {
    NavigationStack {
      Form {
        connectionSection
        displaySection
        appearanceSection
        backgroundSection
        accentColorSection
        appIconGridSection
        tabOrderSection
      }
      // タブ並び替えセクションのドラッグハンドルを、「編集」ボタンを押さなくても
      // 最初から常に見えるようにする
      .environment(\.editMode, .constant(.active))
      .scrollContentBackground(.hidden)
      .background(GamingPalette.background)
      .navigationTitle("設定")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("閉じる") {
            dismiss()
          }
          .foregroundStyle(themeStore.accentColor)
        }
      }
    }
  }

  // MARK: - 接続

  /// 接続先と接続状態、そして手動での切断・ペアリング解除をまとめる。
  /// これまでペアリング解除がMac側にしか無く、iPadだけを手元に持っている場面で操作できなかった
  private var connectionSection: some View {
    Section {
      LabeledContent("状態") {
        HStack(spacing: 7) {
          Circle()
            .fill(connectionStatusColor)
            .frame(width: 8, height: 8)
          Text(connectionStatusText)
            .foregroundStyle(GamingPalette.mutedForeground)
        }
      }
      .foregroundStyle(GamingPalette.foreground)

      Button {
        connectionManager.connect()
      } label: {
        Label("再接続する", systemImage: "arrow.clockwise")
      }
      .foregroundStyle(themeStore.accentColor)
      .disabled(connectionManager.isConnected)

      Button(role: .destructive) {
        isShowingUnpairConfirmation = true
      } label: {
        Label("ペアリングを解除", systemImage: "xmark.shield")
      }
      .foregroundStyle(GamingPalette.destructive)
    } header: {
      Text("接続")
        .foregroundStyle(GamingPalette.mutedForeground)
    } footer: {
      Text("ペアリングを解除すると保存済みの接続情報が消え、次回はMacのPIN入力からやり直します")
        .foregroundStyle(GamingPalette.mutedForeground)
    }
    .listRowBackground(GamingPalette.card.opacity(0.55))
    .confirmationDialog(
      "ペアリングを解除しますか？",
      isPresented: $isShowingUnpairConfirmation,
      titleVisibility: .visible
    ) {
      Button("解除", role: .destructive) {
        connectionManager.unpair()
        dismiss()
      }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("保存済みの接続情報を破棄し、Macに表示されるPINで接続し直します。")
    }
  }

  private var connectionStatusColor: Color {
    switch connectionManager.state {
    case .paired: return GamingPalette.success
    case .failed: return GamingPalette.destructive
    default: return themeStore.accentColor
    }
  }

  private var connectionStatusText: String {
    switch connectionManager.state {
    case .paired: return "接続済み"
    case .searching, .disconnected: return "Macを探しています"
    case .resuming: return "再接続しています"
    case .waitingForPairing: return "ペアリング待ち"
    case .failed(let message): return message
    }
  }

  // MARK: - 画面表示

  private var displaySection: some View {
    Section {
      Toggle(isOn: $themeStore.keepsScreenAwake) {
        VStack(alignment: .leading, spacing: 3) {
          Text("画面を消灯しない")
            .foregroundStyle(GamingPalette.foreground)
          Text("卓上のデッキとして置いたままでも自動ロックしません。電池を節約する場合はオフにしてください")
            .font(.caption)
            .foregroundStyle(GamingPalette.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .tint(themeStore.accentColor)
    } header: {
      Text("画面")
        .foregroundStyle(GamingPalette.mutedForeground)
    }
    .listRowBackground(GamingPalette.card.opacity(0.55))
  }

  // MARK: - 外観設定

  private var appearanceSection: some View {
    Section {
      Picker("外観", selection: $themeStore.colorScheme) {
        ForEach(AppColorScheme.allCases) { option in
          Text(option.displayName).tag(option)
        }
      }
      .pickerStyle(.segmented)
    } header: {
      Text("外観")
        .foregroundStyle(GamingPalette.mutedForeground)
    }
    .listRowBackground(GamingPalette.card.opacity(0.55))
  }

  // MARK: - 背景エフェクト設定

  private var backgroundSection: some View {
    Section {
      Toggle(isOn: $themeStore.backgroundGlowEnabled) {
        VStack(alignment: .leading, spacing: 3) {
          Text("動くグロー背景")
            .foregroundStyle(GamingPalette.foreground)
          Text("オンにすると、ぼかし光がゆっくり動きます。電池を節約する場合はオフがおすすめです")
            .font(.caption)
            .foregroundStyle(GamingPalette.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .tint(themeStore.accentColor)
    } header: {
      Text("背景")
        .foregroundStyle(GamingPalette.mutedForeground)
    }
    .listRowBackground(GamingPalette.card.opacity(0.55))
  }

  // MARK: - アクセントカラー設定

  private var accentColorSection: some View {
    Section {
      ForEach(AccentColorOption.allCases) { option in
        accentColorRow(option)
      }
    } header: {
      Text("アクセントカラー")
        .foregroundStyle(GamingPalette.mutedForeground)
    }
    .listRowBackground(GamingPalette.card.opacity(0.55))
  }

  // MARK: - アプリ一覧のアイコンサイズ設定

  private var appIconGridSection: some View {
    Section {
      Stepper(
        "1行あたりのアイコン数: \(themeStore.appIconGridColumns)",
        value: $themeStore.appIconGridColumns,
        in: ThemeStore.appIconGridColumnsRange
      )
      Text("数を減らすほど「アプリ」タブのアイコンが大きく表示されます")
        .font(.caption)
        .foregroundStyle(GamingPalette.mutedForeground)
    } header: {
      Text("アプリ一覧の表示")
        .foregroundStyle(GamingPalette.mutedForeground)
    }
    .listRowBackground(GamingPalette.card.opacity(0.55))
  }

  // MARK: - 下部タブの並び順設定

  private var tabOrderSection: some View {
    Section {
      ForEach(themeStore.tabOrder) { tab in
        Label(tab.title, systemImage: tab.systemImage)
          .foregroundStyle(GamingPalette.foreground)
      }
      .onMove { indices, newOffset in
        themeStore.tabOrder.move(fromOffsets: indices, toOffset: newOffset)
      }
    } header: {
      Text("下部タブの順番")
        .foregroundStyle(GamingPalette.mutedForeground)
    } footer: {
      Text("右側のハンドルをドラッグして並び替えられます")
        .foregroundStyle(GamingPalette.mutedForeground)
    }
    .listRowBackground(GamingPalette.card.opacity(0.55))
  }

  private func accentColorRow(_ option: AccentColorOption) -> some View {
    Button {
      themeStore.accentColorOption = option
    } label: {
      HStack {
        Circle()
          .fill(option.color)
          .frame(width: 24, height: 24)
          .overlay(
            Circle()
              .stroke(
                themeStore.accentColorOption == option ? themeStore.accentColor : Color.clear,
                lineWidth: 2
              )
              .padding(-3)
          )

        Text(option.displayName)
          .foregroundStyle(GamingPalette.foreground)

        Spacer()

        if themeStore.accentColorOption == option {
          Image(systemName: "checkmark")
            .foregroundStyle(themeStore.accentColor)
        }
      }
    }
    .buttonStyle(.plain)
  }
}

#Preview {
  SettingsView(themeStore: ThemeStore(), connectionManager: ConnectionManager())
}
