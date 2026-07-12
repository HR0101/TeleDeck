//
//  TabsView.swift
//  TeleDeck
//
//  Mac側で開いているブラウザタブの一覧を表示し、切り替え・クローズができる画面。
//

import SwiftUI

struct TabsView: View {
  let connectionManager: ConnectionManager

  @Environment(ThemeStore.self) private var themeStore
  @State private var tabs: [TabInfo] = []
  @State private var searchText = ""

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        searchBar
        content
      }
      .background(GamingPalette.background)
      .navigationTitle("タブ")
      .onAppear {
        fetchTabs()
      }
    }
  }

  // MARK: - 検索バー

  private var searchBar: some View {
    HStack {
      TextField("タブを検索", text: $searchText)
        .foregroundStyle(GamingPalette.foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .gamingCard(accentColor: themeStore.accentColor, cornerRadius: 10)

      Button {
        fetchTabs()
      } label: {
        Image(systemName: "arrow.clockwise")
          .foregroundStyle(themeStore.accentColor)
      }
    }
    .padding()
  }

  // MARK: - 一覧表示

  @ViewBuilder
  private var content: some View {
    if filteredTabs.isEmpty {
      emptyState
    } else {
      List {
        ForEach(groupedTabs, id: \.browser) { group in
          DisclosureGroup("\(group.browser) (\(group.tabs.count))") {
            ForEach(group.tabs, id: \.tabId) { tab in
              tabRow(tab)
            }
          }
          .foregroundStyle(GamingPalette.foreground)
          .listRowBackground(GamingPalette.card.opacity(0.55))
        }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .background(GamingPalette.background)
    }
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: "rectangle.on.rectangle")
        .font(.system(size: 40))
        .foregroundStyle(GamingPalette.mutedForeground)
      Text("タブがありません")
        .foregroundStyle(GamingPalette.mutedForeground)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(GamingPalette.background)
  }

  private func tabRow(_ tab: TabInfo) -> some View {
    HStack {
      Image(systemName: tab.active ? "circle.fill" : "circle")
        .font(.caption)
        .foregroundStyle(tab.active ? themeStore.accentColor : GamingPalette.mutedForeground)

      Text(tab.title)
        .fontWeight(tab.active ? .bold : .regular)
        .foregroundStyle(tab.active ? themeStore.accentColor : GamingPalette.foreground)
        .lineLimit(1)

      Spacer()

      Button {
        closeTab(tab)
      } label: {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(GamingPalette.mutedForeground)
      }
      .buttonStyle(.plain)
    }
    .contentShape(Rectangle())
    .onTapGesture {
      activateTab(tab)
    }
  }

  // MARK: - フィルタ・グルーピング

  private var filteredTabs: [TabInfo] {
    guard !searchText.isEmpty else { return tabs }
    return tabs.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
  }

  private var groupedTabs: [(browser: String, tabs: [TabInfo])] {
    let grouped = Dictionary(grouping: filteredTabs, by: \.browser)
    return grouped
      .map { (browser: $0.key, tabs: $0.value) }
      .sorted { $0.browser < $1.browser }
  }

  // MARK: - Macとの通信

  private func fetchTabs() {
    connectionManager.requestTabs { fetchedTabs in
      tabs = fetchedTabs
    }
  }

  private func activateTab(_ tab: TabInfo) {
    connectionManager.execute(ActionPayload(type: .activateTab, browser: tab.browser, tabId: tab.tabId))
  }

  private func closeTab(_ tab: TabInfo) {
    connectionManager.execute(ActionPayload(type: .closeTab, browser: tab.browser, tabId: tab.tabId)) { _ in
      fetchTabs()
    }
  }
}

#Preview {
  TabsView(connectionManager: ConnectionManager())
    .environment(ThemeStore())
}
