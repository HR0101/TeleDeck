//
//  TabsView.swift
//  TeleDeck
//
//  Mac側の「起動中アプリ」と「ブラウザで開いているタブ」を切り替えて表示し、
//  タップでそれぞれをアクティブ化できる画面。
//

import SwiftUI
import UIKit

/// この画面で表示する対象。アプリ切替とブラウザタブは用途が近いため同じ画面にまとめ、
/// 上部のセグメントで切り替える
private enum TabsScope: String, CaseIterable, Identifiable {
  case applications
  case browserTabs

  var id: String { rawValue }

  var title: String {
    switch self {
    case .applications: return "アプリ"
    case .browserTabs: return "ブラウザタブ"
    }
  }
}

struct TabsView: View {
  let connectionManager: ConnectionManager

  @Environment(ThemeStore.self) private var themeStore
  @State private var scope: TabsScope = .applications
  @State private var applications: [MacApplicationInfo] = []
  @State private var browserTabs: [TabInfo] = []
  @State private var searchText = ""
  @State private var isLoading = false
  @State private var requestId = UUID()
  @State private var isShowingActivationError = false
  @State private var activationErrorMessage = ""

  private static let gridSpacing: CGFloat = 20
  private static let gridPadding: CGFloat = 20
  /// アイコンが小さくなりすぎて操作しづらくならないよう設ける下限サイズ
  private static let minimumTileSize: CGFloat = 64
  /// 応答が返らない場合に読み込み表示を解除するまでの時間
  private static let loadingTimeout: TimeInterval = 5

  var body: some View {
    // MainTabViewでは設定ボタンだけを右上へ重ねるため、独立したナビゲーションバーは設けない。
    VStack(spacing: 0) {
      scopePicker
      searchBar
      content
    }
    .background(GamingPalette.background)
    .onAppear {
      fetch()
    }
    .onChange(of: scope) { _, _ in
      searchText = ""
      fetch()
    }
    .alert("切り替えに失敗しました", isPresented: $isShowingActivationError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(activationErrorMessage)
    }
  }

  // MARK: - 表示対象の切り替え

  private var scopePicker: some View {
    Picker("表示", selection: $scope) {
      ForEach(TabsScope.allCases) { option in
        Text(option.title).tag(option)
      }
    }
    .pickerStyle(.segmented)
    .frame(maxWidth: 420)
    .padding(.horizontal, 16)
    .padding(.top, 14)
    // 右上のフローティング設定ボタンと重ならないよう、右側に余白を確保する
    .padding(.trailing, 56)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - 検索バー

  private var searchBar: some View {
    HStack {
      TextField(scope == .applications ? "アプリを検索" : "タブを検索", text: $searchText)
        .foregroundStyle(GamingPalette.foreground)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .gamingCard(accentColor: themeStore.accentColor, cornerRadius: 10)

      Button {
        fetch()
      } label: {
        Image(systemName: "arrow.clockwise")
          .foregroundStyle(themeStore.accentColor)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("再読み込み")
    }
    .padding(.leading, 16)
    .padding(.trailing, 16)
    .padding(.vertical, 12)
  }

  // MARK: - 一覧表示

  @ViewBuilder
  private var content: some View {
    GeometryReader { proxy in
      ScrollView {
        if isLoading {
          loadingIndicator
        } else if !connectionManager.isConnected {
          message("Macに接続されていません", systemImage: "wifi.slash")
        } else {
          switch scope {
          case .applications:
            applicationsContent(availableWidth: proxy.size.width)
          case .browserTabs:
            browserTabsContent
          }
        }
      }
      .refreshable { fetch() }
    }
  }

  private var loadingIndicator: some View {
    HStack(spacing: 10) {
      ProgressView()
      Text("Macから取得中…")
        .foregroundStyle(GamingPalette.mutedForeground)
    }
    .padding(.top, 40)
    .frame(maxWidth: .infinity)
  }

  private func message(_ text: String, systemImage: String) -> some View {
    VStack(spacing: 10) {
      Image(systemName: systemImage)
        .font(.system(size: 30))
        .foregroundStyle(GamingPalette.mutedForeground)
      Text(text)
        .foregroundStyle(GamingPalette.mutedForeground)
        .multilineTextAlignment(.center)
    }
    .padding(.top, 40)
    .padding(.horizontal, 32)
    .frame(maxWidth: .infinity)
  }

  // MARK: - アプリ一覧

  @ViewBuilder
  private func applicationsContent(availableWidth: CGFloat) -> some View {
    if filteredApplications.isEmpty {
      message(
        searchText.isEmpty ? "起動中のアプリを取得できませんでした" : "検索に一致するアプリがありません",
        systemImage: "macwindow"
      )
    } else {
      let tileSize = tileSize(availableWidth: availableWidth)
      let columns = Array(
        repeating: GridItem(.fixed(tileSize), spacing: Self.gridSpacing),
        count: themeStore.appIconGridColumns
      )
      LazyVGrid(columns: columns, spacing: Self.gridSpacing) {
        ForEach(filteredApplications) { application in
          applicationTile(application, tileSize: tileSize)
        }
      }
      .padding(Self.gridPadding)
      .frame(maxWidth: .infinity)
    }
  }

  /// 設定画面で指定した列数と使える幅から、アイコンタイルの一辺のサイズを求める
  private func tileSize(availableWidth: CGFloat) -> CGFloat {
    let columns = themeStore.appIconGridColumns
    guard columns > 0 else { return Self.minimumTileSize }

    let usableWidth = availableWidth - Self.gridPadding * 2
    let widthPerTile = (usableWidth - Self.gridSpacing * CGFloat(columns - 1)) / CGFloat(columns)
    return max(widthPerTile, Self.minimumTileSize)
  }

  private func applicationTile(_ application: MacApplicationInfo, tileSize: CGFloat) -> some View {
    Button {
      activateApplication(application)
    } label: {
      VStack(spacing: 6) {
        applicationIcon(application, tileSize: tileSize)
          .frame(width: tileSize, height: tileSize)
          .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
              .fill(application.active ? themeStore.accentColor.opacity(0.16) : GamingPalette.card.opacity(0.5))
          )
          .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
              .stroke(
                application.active ? themeStore.accentColor : GamingPalette.mutedForeground.opacity(0.18),
                lineWidth: application.active ? 2 : 1
              )
          )

        Text(application.name)
          .font(.caption)
          .foregroundStyle(application.active ? themeStore.accentColor : GamingPalette.mutedForeground)
          .lineLimit(1)
      }
    }
    .buttonStyle(TabsTileButtonStyle())
    .accessibilityLabel(application.name)
    .accessibilityValue(application.active ? "Macで使用中" : "")
    .contextMenu {
      Text(application.name)
      Button("Macで開く") {
        activateApplication(application)
      }
      Button("終了", role: .destructive) {
        quitApplication(application)
      }
    }
  }

  @ViewBuilder
  private func applicationIcon(_ application: MacApplicationInfo, tileSize: CGFloat) -> some View {
    let iconSize = tileSize * 0.75

    if let iconData = application.iconPNGData,
       let icon = UIImage(data: iconData) {
      Image(uiImage: icon)
        .resizable()
        .scaledToFit()
        .frame(width: iconSize, height: iconSize)
        .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.22, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
          if application.active {
            Circle()
              .fill(themeStore.accentColor)
              .frame(width: 16, height: 16)
              .overlay(Circle().stroke(GamingPalette.card, lineWidth: 2))
          }
        }
    } else {
      Image(systemName: application.active ? "macwindow.fill" : "macwindow")
        .font(.system(size: iconSize * 0.47))
        .foregroundStyle(application.active ? themeStore.accentColor : GamingPalette.mutedForeground)
        .frame(width: iconSize, height: iconSize)
    }
  }

  // MARK: - ブラウザタブ一覧

  @ViewBuilder
  private var browserTabsContent: some View {
    if filteredTabs.isEmpty {
      message(
        searchText.isEmpty
          ? "開いているタブが見つかりませんでした\nMac側でブラウザの操作を許可しているか確認してください"
          : "検索に一致するタブがありません",
        systemImage: "square.on.square"
      )
    } else {
      LazyVStack(alignment: .leading, spacing: 18) {
        // 設計書4.3のとおり、ブラウザごとにまとめて表示する
        ForEach(groupedTabs, id: \.browser) { group in
          VStack(alignment: .leading, spacing: 8) {
            Text("\(group.browser) (\(group.tabs.count))")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(themeStore.accentColor)
              .padding(.horizontal, 4)

            VStack(spacing: 8) {
              ForEach(group.tabs, id: \.tabId) { tab in
                tabRow(tab)
              }
            }
          }
        }
      }
      .frame(maxWidth: 900)
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity)
    }
  }

  private func tabRow(_ tab: TabInfo) -> some View {
    HStack(spacing: 12) {
      Button {
        activateTab(tab)
      } label: {
        HStack(spacing: 12) {
          Image(systemName: tab.active ? "square.fill.on.square.fill" : "square.on.square")
            .font(.system(size: 16))
            .foregroundStyle(tab.active ? themeStore.accentColor : GamingPalette.mutedForeground)
            .frame(width: 24)

          Text(tab.title.isEmpty ? "(無題のタブ)" : tab.title)
            .font(.subheadline)
            .foregroundStyle(tab.active ? GamingPalette.foreground : GamingPalette.mutedForeground)
            .lineLimit(1)
            .truncationMode(.middle)

          Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      Button {
        closeTab(tab)
      } label: {
        Image(systemName: "xmark")
          .font(.caption.weight(.bold))
          .foregroundStyle(GamingPalette.mutedForeground)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(tab.title)を閉じる")
    }
    .padding(.leading, 14)
    .padding(.trailing, 2)
    .frame(minHeight: 52)
    .background(
      GamingPalette.card.opacity(tab.active ? 0.8 : 0.5),
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(
          tab.active ? themeStore.accentColor.opacity(0.6) : GamingPalette.mutedForeground.opacity(0.16),
          lineWidth: 1
        )
    }
  }

  // MARK: - フィルタ

  private var filteredApplications: [MacApplicationInfo] {
    guard !searchText.isEmpty else { return applications }
    return applications.filter {
      $0.name.localizedCaseInsensitiveContains(searchText)
        || $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
    }
  }

  private var filteredTabs: [TabInfo] {
    guard !searchText.isEmpty else { return browserTabs }
    return browserTabs.filter {
      $0.title.localizedCaseInsensitiveContains(searchText)
        || $0.browser.localizedCaseInsensitiveContains(searchText)
    }
  }

  /// ブラウザ名ごとにまとめ、ブラウザ名の順で安定して並べる
  private var groupedTabs: [(browser: String, tabs: [TabInfo])] {
    Dictionary(grouping: filteredTabs, by: \.browser)
      .map { (browser: $0.key, tabs: $0.value) }
      .sorted { $0.browser.localizedStandardCompare($1.browser) == .orderedAscending }
  }

  // MARK: - Macとの通信

  private func fetch() {
    guard connectionManager.isConnected else {
      isLoading = false
      return
    }

    let currentRequestId = UUID()
    requestId = currentRequestId
    isLoading = true

    switch scope {
    case .applications:
      connectionManager.requestApplications { fetchedApplications in
        guard requestId == currentRequestId else { return }
        applications = fetchedApplications
        isLoading = false
      }

    case .browserTabs:
      connectionManager.requestTabs { fetchedTabs, fetchedApplications in
        guard requestId == currentRequestId else { return }
        browserTabs = fetchedTabs
        // タブ取得の応答にはアプリ一覧も含まれるため、併せて更新しておく
        if !fetchedApplications.isEmpty {
          applications = fetchedApplications
        }
        isLoading = false
      }
    }

    // AppleScript経由の取得は応答が返らないことがあるため、読み込み表示を必ず解除する
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.loadingTimeout) {
      guard requestId == currentRequestId, isLoading else { return }
      isLoading = false
    }
  }

  private func activateApplication(_ application: MacApplicationInfo) {
    execute(
      ActionPayload(type: .activateApplication, target: application.bundleIdentifier),
      failureTitle: "アプリの切り替えに失敗しました"
    )
  }

  private func quitApplication(_ application: MacApplicationInfo) {
    execute(
      ActionPayload(type: .quitApplication, target: application.bundleIdentifier),
      failureTitle: "アプリの終了に失敗しました"
    )
  }

  private func activateTab(_ tab: TabInfo) {
    execute(
      ActionPayload(type: .activateTab, browser: tab.browser, tabId: tab.tabId),
      failureTitle: "タブの切り替えに失敗しました"
    )
  }

  private func closeTab(_ tab: TabInfo) {
    execute(
      ActionPayload(type: .closeTab, browser: tab.browser, tabId: tab.tabId),
      failureTitle: "タブを閉じられませんでした"
    )
  }

  /// アクションを送り、成功したら一覧を取り直す。失敗時は理由をアラートで示す
  private func execute(_ action: ActionPayload, failureTitle: String) {
    guard connectionManager.isConnected else {
      activationErrorMessage = "Macに接続されていません。再接続を待っています"
      isShowingActivationError = true
      return
    }

    connectionManager.execute(action) { result in
      switch result {
      case .success:
        fetch()
      case .failure(let error):
        activationErrorMessage = "\(failureTitle)\n\(error.localizedDescription)"
        isShowingActivationError = true
      }
    }
  }
}

private struct TabsTileButtonStyle: ButtonStyle {
  @Environment(ThemeStore.self) private var themeStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.94 : 1)
      .opacity(configuration.isPressed ? 0.82 : 1)
      .animation(
        reduceMotion || themeStore.isEnergySavingModeEnabled ? nil : .easeOut(duration: 0.12),
        value: configuration.isPressed
      )
  }
}

#Preview {
  TabsView(connectionManager: ConnectionManager())
    .environment(ThemeStore())
}
