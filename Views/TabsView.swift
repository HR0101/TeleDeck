//
//  TabsView.swift
//  TeleDeck
//
//  Mac側で起動中のアプリケーションを表示し、切り替えができる画面。
//

import SwiftUI
import UIKit

struct TabsView: View {
  let connectionManager: ConnectionManager

  @Environment(ThemeStore.self) private var themeStore
  @State private var applications: [MacApplicationInfo] = []
  @State private var searchText = ""
  @State private var isLoadingApplications = false
  @State private var applicationRequestId = UUID()
  @State private var isShowingActivationError = false
  @State private var activationErrorMessage = ""

  private static let gridSpacing: CGFloat = 20
  private static let gridPadding: CGFloat = 20
  /// アイコンが小さくなりすぎて操作しづらくならないよう設ける下限サイズ
  private static let minimumTileSize: CGFloat = 64

  var body: some View {
    // MainTabViewでは設定ボタンだけを右上へ重ねるため、独立したナビゲーションバーは設けない。
    VStack(spacing: 0) {
      searchBar
      content
    }
    .background(GamingPalette.background)
    .onAppear {
      fetchApplications()
    }
    .alert("アプリの切り替えに失敗しました", isPresented: $isShowingActivationError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(activationErrorMessage)
    }
  }

  // MARK: - 検索バー

  private var searchBar: some View {
    HStack {
      TextField("アプリを検索", text: $searchText)
        .foregroundStyle(GamingPalette.foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .gamingCard(accentColor: themeStore.accentColor, cornerRadius: 10)

      Button {
        fetchApplications()
      } label: {
        Image(systemName: "arrow.clockwise")
          .foregroundStyle(themeStore.accentColor)
      }
    }
    .padding(.leading, 16)
    .padding(.vertical, 16)
    // 右上のフローティング設定ボタンと更新ボタンが重ならない幅だけを空ける。
    .padding(.trailing, 72)
  }

  // MARK: - 一覧表示

  @ViewBuilder
  private var content: some View {
    GeometryReader { proxy in
      ScrollView {
        if isLoadingApplications {
          HStack(spacing: 10) {
            ProgressView()
            Text("Macから取得中…")
              .foregroundStyle(GamingPalette.mutedForeground)
          }
          .padding(.top, 40)
        } else if filteredApplications.isEmpty {
          Text(searchText.isEmpty ? "起動中のアプリを取得できませんでした" : "検索に一致するアプリがありません")
            .foregroundStyle(GamingPalette.mutedForeground)
            .padding(.top, 40)
        } else {
          let tileSize = tileSize(availableWidth: proxy.size.width)
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
    .buttonStyle(ApplicationTileButtonStyle())
    .accessibilityLabel(application.name)
    .accessibilityValue(application.active ? "Macで使用中" : "")
    .contextMenu {
      Text(application.name)
      Button("Macで開く") {
        activateApplication(application)
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

  // MARK: - フィルタ

  private var filteredApplications: [MacApplicationInfo] {
    guard !searchText.isEmpty else { return applications }
    return applications.filter {
      $0.name.localizedCaseInsensitiveContains(searchText)
        || $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
    }
  }

  // MARK: - Macとの通信

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
}

private struct ApplicationTileButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.94 : 1)
      .opacity(configuration.isPressed ? 0.82 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

#Preview {
  TabsView(connectionManager: ConnectionManager())
    .environment(ThemeStore())
}
