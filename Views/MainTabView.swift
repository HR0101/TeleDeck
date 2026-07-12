//
//  MainTabView.swift
//  TeleDeck
//
//  ペアリング完了後のメイン画面。パネル/時計/タブ/トラックパッド/キーボード/クリップボードの6画面を、
//  下部の自作タブバーのタップのみで切り替える（トラックパッド画面の3本指スワイプ操作と
//  ジェスチャーが競合しないよう、横スワイプでの画面切り替えは行わない）。
//

import SwiftUI

private enum MainTab: Int, CaseIterable {
  case panel
  case clock
  case tabs
  case trackpad
  case keyboard
  case clipboard

  var title: String {
    switch self {
    case .panel: return "パネル"
    case .clock: return "時計"
    case .tabs: return "タブ"
    case .trackpad: return "トラックパッド"
    case .keyboard: return "キーボード"
    case .clipboard: return "クリップボード"
    }
  }

  var systemImage: String {
    switch self {
    case .panel: return "square.grid.3x3.fill"
    case .clock: return "clock"
    case .tabs: return "rectangle.on.rectangle"
    case .trackpad: return "rectangle.and.hand.point.up.left.filled"
    case .keyboard: return "keyboard"
    case .clipboard: return "doc.on.clipboard"
    }
  }
}

struct MainTabView: View {
  let connectionManager: ConnectionManager

  @Environment(ThemeStore.self) private var themeStore
  @State private var isShowingSettings = false
  @State private var selectedTab: MainTab = .panel
  @State private var isPanelEditMode = false

  var body: some View {
    VStack(spacing: 0) {
      // NavigationStackの標準ツールバーはタイトルが無くても上部に大きな最小高さを確保してしまうため、
      // 使わずに自作の薄いバーへ置き換えて上部の余白を最小限にする
      if selectedTab != .clock {
        customTopBar
      }

      // TabView(pageスタイル)によるスワイプ切り替えは廃止し、selectedTabの値に応じて
      // 表示ビューを直接切り替える（下部の自作タブバーのタップのみで画面遷移させるため）
      Group {
        switch selectedTab {
        case .panel:
          PanelView(connectionManager: connectionManager, isEditMode: $isPanelEditMode)

        case .clock:
          ClockView()

        case .tabs:
          TabsView(connectionManager: connectionManager)

        case .trackpad:
          TrackpadView(connectionManager: connectionManager)

        case .keyboard:
          KeyboardView(connectionManager: connectionManager)

        case .clipboard:
          ClipboardView(connectionManager: connectionManager)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      customTabBar
    }
    .statusBarHidden(selectedTab == .clock)
    .onChange(of: selectedTab) { _, newTab in
      // パネル以外のタブへ移動したら編集モードを解除しておく
      if newTab != .panel {
        isPanelEditMode = false
      }
    }
    .sheet(isPresented: $isShowingSettings) {
      SettingsView(themeStore: themeStore)
    }
  }

  private var customTopBar: some View {
    HStack(spacing: 10) {
      Spacer()
      if selectedTab == .panel {
        Button {
          withAnimation(.easeOut(duration: 0.18)) {
            isPanelEditMode.toggle()
          }
        } label: {
          Label(isPanelEditMode ? "編集を完了" : "パネルを編集", systemImage: isPanelEditMode ? "checkmark" : "pencil")
            .font(.subheadline.weight(.semibold))
        }
        .tint(themeStore.accentColor)
      }
      Button {
        isShowingSettings = true
      } label: {
        Image(systemName: "gearshape")
      }
      .tint(themeStore.accentColor)
    }
    .padding(.horizontal, 20)
    .padding(.top, 6)
    .padding(.bottom, 4)
  }

  private var customTabBar: some View {
    HStack {
      ForEach(MainTab.allCases, id: \.self) { tab in
        Button {
          withAnimation {
            selectedTab = tab
          }
        } label: {
          VStack(spacing: 4) {
            Image(systemName: tab.systemImage)
              .font(.system(size: 20))
            Text(tab.title)
              .font(.caption2)
          }
          .foregroundStyle(selectedTab == tab ? themeStore.accentColor : GamingPalette.mutedForeground)
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.vertical, 10)
    .background(
      Rectangle()
        .fill(.ultraThinMaterial)
        .overlay(GamingPalette.card.opacity(0.55))
        .overlay(alignment: .top) {
          Rectangle()
            .fill(themeStore.accentColor.opacity(0.4))
            .frame(height: 1)
        }
    )
  }
}

#Preview {
  MainTabView(connectionManager: ConnectionManager())
    .environment(ThemeStore())
}
