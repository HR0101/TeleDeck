//
//  TabsView.swift
//  TeleDeck
//
//  Mac側で起動中のアプリケーションとブラウザタブを表示し、切り替え・クローズができる画面。
//

import SwiftUI
import UIKit

struct TabsView: View {
  let connectionManager: ConnectionManager

  @Environment(ThemeStore.self) private var themeStore
  @State private var applications: [MacApplicationInfo] = []
  @State private var tabs: [TabInfo] = []
  @State private var searchText = ""
  @State private var isLoadingApplications = false
  @State private var applicationRequestId = UUID()
  @State private var isShowingActivationError = false
  @State private var activationErrorMessage = ""

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        searchBar
        content
      }
      .background(GamingPalette.background)
      .navigationTitle("タブ")
      .onAppear {
        refresh()
      }
      .alert("アプリの切り替えに失敗しました", isPresented: $isShowingActivationError) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(activationErrorMessage)
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
        refresh()
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
    List {
      Section("アプリケーション") {
        if isLoadingApplications {
          HStack(spacing: 10) {
            ProgressView()
            Text("Macから取得中…")
              .foregroundStyle(GamingPalette.mutedForeground)
          }
          .listRowBackground(GamingPalette.card.opacity(0.55))
        } else if filteredApplications.isEmpty {
          Text(searchText.isEmpty ? "起動中のアプリを取得できませんでした" : "検索に一致するアプリがありません")
            .foregroundStyle(GamingPalette.mutedForeground)
            .listRowBackground(GamingPalette.card.opacity(0.55))
        } else {
          ForEach(filteredApplications) { application in
            applicationRow(application)
          }
        }
      }

      if groupedTabs.isEmpty {
        Section("ブラウザタブ") {
          Text(searchText.isEmpty ? "開いているタブがありません" : "検索に一致するタブがありません")
            .foregroundStyle(GamingPalette.mutedForeground)
            .listRowBackground(GamingPalette.card.opacity(0.55))
        }
      } else {
        Section("ブラウザタブ") {
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
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
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

  private func applicationRow(_ application: MacApplicationInfo) -> some View {
    Button {
      activateApplication(application)
    } label: {
      HStack(spacing: 12) {
        applicationIcon(application)

        VStack(alignment: .leading, spacing: 3) {
          Text(application.name)
            .fontWeight(application.active ? .bold : .regular)
            .foregroundStyle(application.active ? themeStore.accentColor : GamingPalette.foreground)
          Text(application.bundleIdentifier)
            .font(.caption2)
            .foregroundStyle(GamingPalette.mutedForeground)
            .lineLimit(1)
        }

        Spacer()

        if application.active {
          Text("使用中")
            .font(.caption)
            .foregroundStyle(themeStore.accentColor)
        } else {
          Image(systemName: "arrow.up.forward.app")
            .foregroundStyle(GamingPalette.mutedForeground)
        }
      }
    }
    .buttonStyle(.plain)
    .listRowBackground(GamingPalette.card.opacity(0.55))
  }

  @ViewBuilder
  private func applicationIcon(_ application: MacApplicationInfo) -> some View {
    if let iconData = application.iconPNGData,
       let icon = UIImage(data: iconData) {
      Image(uiImage: icon)
        .resizable()
        .scaledToFit()
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
          if application.active {
            Circle()
              .fill(themeStore.accentColor)
              .frame(width: 10, height: 10)
              .overlay(Circle().stroke(GamingPalette.card, lineWidth: 2))
          }
        }
    } else {
      Image(systemName: application.active ? "macwindow.fill" : "macwindow")
        .font(.title3)
        .foregroundStyle(application.active ? themeStore.accentColor : GamingPalette.mutedForeground)
        .frame(width: 36, height: 36)
    }
  }

  // MARK: - フィルタ・グルーピング

  private var filteredTabs: [TabInfo] {
    guard !searchText.isEmpty else { return tabs }
    return tabs.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
  }

  private var filteredApplications: [MacApplicationInfo] {
    guard !searchText.isEmpty else { return applications }
    return applications.filter {
      $0.name.localizedCaseInsensitiveContains(searchText)
        || $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
    }
  }

  private var groupedTabs: [(browser: String, tabs: [TabInfo])] {
    let grouped = Dictionary(grouping: filteredTabs, by: \.browser)
    return grouped
      .map { (browser: $0.key, tabs: $0.value) }
      .sorted { $0.browser < $1.browser }
  }

  // MARK: - Macとの通信

  private func fetchTabs() {
    connectionManager.requestTabs { fetchedTabs, fetchedApplications in
      tabs = fetchedTabs
      // 旧Macエージェントのタブ応答にはアプリ一覧が含まれないため、空で上書きしない。
      if !fetchedApplications.isEmpty {
        applications = fetchedApplications
      }
    }
  }

  private func refresh() {
    fetchApplications()
    fetchTabs()
  }

  private func fetchApplications() {
    let requestId = UUID()
    applicationRequestId = requestId
    isLoadingApplications = true

    connectionManager.requestApplications { fetchedApplications in
      guard applicationRequestId == requestId else { return }
      applications = fetchedApplications
      isLoadingApplications = false
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
      guard applicationRequestId == requestId, isLoadingApplications else { return }
      isLoadingApplications = false
    }
  }

  private func activateApplication(_ application: MacApplicationInfo) {
    connectionManager.execute(
      ActionPayload(type: .activateApplication, target: application.bundleIdentifier)
    ) { result in
      switch result {
      case .success:
        fetchApplications()
      case .failure(let error):
        activationErrorMessage = error.localizedDescription
        isShowingActivationError = true
      }
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
