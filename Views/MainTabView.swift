//
//  MainTabView.swift
//  TeleDeck
//
//  ペアリング完了後のメイン画面。パネル/時計/タブ/キーボード（トラックパッド統合）/クリップボードの5画面を、
//  下部の自作タブバーと、キーボード以外の画面では横スワイプでも切り替えられる。
//  キーボード画面はトラックパッドを内包しており、3本指操作との競合を避けるためタブバー操作に限定する。
//

import SwiftUI

struct MainTabView: View {
  let connectionManager: ConnectionManager

  @Environment(ThemeStore.self) private var themeStore
  @State private var isShowingSettings = false
  @State private var selectedTab: MainTab = .panel
  @State private var isPanelEditMode = false
  /// 時計タブが「時計のみ表示」（コントロール非表示）へ移行したかどうか。trueの間は下部タブバーも隠す
  @State private var isClockImmersive = false
  /// 選択中タブのハイライトを、タブ間で滑らかに移動させるための名前空間
  @Namespace private var tabSelectionNamespace

  var body: some View {
    VStack(spacing: 0) {
      // 表示ビューは直接切り替える。キーボード（トラックパッド統合）以外は下のスワイプジェスチャーを
      // 追加し、操作できる画面まで「フリーズ」に見えないようにする。
      Group {
        switch selectedTab {
        case .panel:
          PanelView(
            connectionManager: connectionManager,
            isEditMode: $isPanelEditMode,
            onOpenSettings: { isShowingSettings = true }
          )

        case .clock:
          ClockView(isImmersive: $isClockImmersive)

        case .tabs:
          TabsView(connectionManager: connectionManager)

        case .keyboard:
          KeyboardView(connectionManager: connectionManager)

        case .clipboard:
          ClipboardView(connectionManager: connectionManager)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      // 設定のためだけに上部の一行を確保せず、コンテンツ上へ小さなボタンを重ねる。
      // パネル画面は機能ヘッダー内に、時計画面は没入表示を優先しているため対象外。
      .overlay(alignment: .topTrailing) {
        if selectedTab != .clock && selectedTab != .panel {
          floatingSettingsButton
        }
      }
      .simultaneousGesture(
        DragGesture(minimumDistance: 45)
          .onEnded { value in
            switchTabBySwipe(value.translation.width, vertical: value.translation.height)
          }
      )

      // 時計タブが「時計のみ表示」へ移行したらタブバーも一緒に隠し、時計だけの画面にする。
      // 画面タップやスワイプでコントロールが復帰すると、タブバーも連動して戻ってくる
      if !(selectedTab == .clock && isClockImmersive) {
        customTabBar
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .statusBarHidden(selectedTab == .clock)
    .onChange(of: selectedTab) { _, newTab in
      // パネル以外のタブへ移動したら編集モードを解除しておく
      if newTab != .panel {
        isPanelEditMode = false
      }
      // 時計タブ以外へ移動したら没入状態を解除し、タブバーを確実に復帰させる
      if newTab != .clock {
        isClockImmersive = false
      }
    }
    .sheet(isPresented: $isShowingSettings) {
      SettingsView(themeStore: themeStore)
    }
  }

  private var floatingSettingsButton: some View {
    Button {
      isShowingSettings = true
    } label: {
      Image(systemName: "gearshape")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(themeStore.accentColor)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .background(.ultraThinMaterial, in: Circle())
        .overlay {
          Circle()
            .stroke(themeStore.accentColor.opacity(0.28), lineWidth: 1)
        }
    }
    .buttonStyle(FloatingSettingsButtonStyle())
    .padding(.top, 8)
    .padding(.trailing, 12)
    .accessibilityLabel("設定")
  }

  private func switchTabBySwipe(_ horizontal: CGFloat, vertical: CGFloat) {
    guard selectedTab != .keyboard,
          abs(horizontal) > abs(vertical),
          abs(horizontal) > 45 else { return }
    let order = themeStore.tabOrder
    guard let index = order.firstIndex(of: selectedTab) else { return }
    let nextIndex = horizontal < 0 ? index + 1 : index - 1
    guard order.indices.contains(nextIndex) else { return }
    withAnimation(.easeOut(duration: 0.2)) {
      selectedTab = order[nextIndex]
    }
  }

  private var customTabBar: some View {
    HStack(spacing: 4) {
      ForEach(themeStore.tabOrder) { tab in
        tabBarButton(for: tab)
      }
    }
    .padding(6)
    .frame(maxWidth: 920)
    .accessibilityElement(children: .contain)
    .background(
      .ultraThinMaterial,
      in: RoundedRectangle(cornerRadius: 22, style: .continuous)
    )
    .background(
      GamingPalette.card.opacity(0.74),
      in: RoundedRectangle(cornerRadius: 22, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(themeStore.accentColor.opacity(0.3), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.34), radius: 18, y: 8)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }

  private func tabBarButton(for tab: MainTab) -> some View {
    let isSelected = selectedTab == tab

    return Button {
      withAnimation(.easeOut(duration: 0.18)) {
        selectedTab = tab
      }
    } label: {
      VStack(spacing: 4) {
        Image(systemName: tab.systemImage)
          .symbolVariant(isSelected ? .fill : .none)
          .font(.system(size: 20))
        Text(tab.title)
          .font(.caption2)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      .foregroundStyle(isSelected ? GamingPalette.foreground : GamingPalette.mutedForeground)
      .frame(maxWidth: .infinity, minHeight: 44)
      .padding(.vertical, 2)
      .background {
        // 選択中のタブだけに、アクセントカラーで色付けした面を重ねる（ガラスは使わない）。
        // matchedGeometryEffectで同じIDを共有させることで、タブ切り替え時に
        // ハイライトが前のタブから新しいタブへ滑らかに移動する
        if isSelected {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(themeStore.accentColor.opacity(0.35))
            .matchedGeometryEffect(id: "tabBarSelectionPill", in: tabSelectionNamespace)
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(tab.title)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }
}

private struct FloatingSettingsButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .opacity(configuration.isPressed ? 0.82 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

#Preview {
  MainTabView(connectionManager: ConnectionManager())
    .environment(ThemeStore())
}
