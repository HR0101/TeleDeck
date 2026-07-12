//
//  MainTabView.swift
//  TeleDeck
//
//  ペアリング完了後のメイン画面。パネル/時計/タブの3画面を、タブバーのタップと
//  横スワイプの両方で行き来できる（設計書4章「横スワイプまたは下部タブバーで3画面を行き来する」に対応）。
//

import SwiftUI

private enum MainTab: Int, CaseIterable {
  case panel
  case clock
  case tabs
  case trackpad
  case keyboard

  var title: String {
    switch self {
    case .panel: return "パネル"
    case .clock: return "時計"
    case .tabs: return "タブ"
    case .trackpad: return "トラックパッド"
    case .keyboard: return "キーボード"
    }
  }

  var systemImage: String {
    switch self {
    case .panel: return "square.grid.3x3.fill"
    case .clock: return "clock"
    case .tabs: return "rectangle.on.rectangle"
    case .trackpad: return "rectangle.and.hand.point.up.left.filled"
    case .keyboard: return "keyboard"
    }
  }
}

struct MainTabView: View {
  let connectionManager: ConnectionManager

  @Environment(ThemeStore.self) private var themeStore
  @State private var isShowingSettings = false
  @State private var selectedTab: MainTab = .panel

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // 標準のタブバー形式TabViewはタップのみでスワイプに対応しないため、
        // pageスタイル（スワイプ対応）+ 自作のタブバーを組み合わせている
        TabView(selection: $selectedTab) {
          PanelView(connectionManager: connectionManager)
            .tag(MainTab.panel)

          ClockView()
            .tag(MainTab.clock)

          TabsView(connectionManager: connectionManager)
            .tag(MainTab.tabs)

          TrackpadView(connectionManager: connectionManager)
            .tag(MainTab.trackpad)

          KeyboardView(connectionManager: connectionManager)
            .tag(MainTab.keyboard)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))

        customTabBar
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            isShowingSettings = true
          } label: {
            Image(systemName: "gearshape")
          }
        }
      }
      .toolbarBackground(.hidden, for: .navigationBar)
    }
    .sheet(isPresented: $isShowingSettings) {
      SettingsView(themeStore: themeStore)
    }
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
