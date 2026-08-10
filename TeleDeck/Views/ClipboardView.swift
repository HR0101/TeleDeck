//
//  ClipboardView.swift
//  TeleDeck
//
//  Mac側のコピー履歴を一覧表示し、タップした項目を即座にMacのクリップボードへセットして
//  貼り付け（Cmd+V）まで実行する画面。
//

import SwiftUI

struct ClipboardView: View {
  let connectionManager: ConnectionManager

  @Environment(ThemeStore.self) private var themeStore
  @State private var items: [ClipboardHistoryEntry] = []
  @State private var pastingItemId: UUID?

  var body: some View {
    // 独立したナビゲーションバーは設けず、更新は一覧のプル操作（.refreshable）と、
    // 空状態の明示的なボタンで行えるようにする。
    content
      .background(GamingPalette.background)
      .onAppear {
        connectionManager.onClipboardHistory = { entries in
          items = entries
        }
        refresh()
      }
  }

  // MARK: - 一覧表示

  @ViewBuilder
  private var content: some View {
    if items.isEmpty {
      emptyState
    } else {
      ScrollView {
        LazyVStack(spacing: 12) {
          ForEach(items) { item in
            row(for: item)
          }
        }
        // 横長のiPadでもカードが画面いっぱいに間延びしない読みやすい幅に留める。
        // この幅なら右上のフローティング設定ボタンとも干渉しない。
        .frame(maxWidth: 980)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
      }
      .background(GamingPalette.background)
      .refreshable { refresh() }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 16) {
      ZStack {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .fill(themeStore.accentColor.opacity(0.14))
        Image(systemName: "doc.on.clipboard")
          .font(.system(size: 38, weight: .medium))
          .foregroundStyle(themeStore.accentColor)
      }
      .frame(width: 86, height: 86)

      VStack(spacing: 5) {
        Text("コピー履歴がありません")
          .font(.headline)
          .foregroundStyle(GamingPalette.foreground)
        Text("Macでコピーしたテキストや画像がここに表示されます")
          .font(.subheadline)
          .foregroundStyle(GamingPalette.mutedForeground)
      }

      Button {
        refresh()
      } label: {
        Label("更新", systemImage: "arrow.clockwise")
          .font(.subheadline.weight(.semibold))
      }
      .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor))
    }
    .padding(.horizontal, 48)
    .padding(.vertical, 40)
    .gamingCard(accentColor: themeStore.accentColor, cornerRadius: 24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(GamingPalette.background)
  }

  private func row(for item: ClipboardHistoryEntry) -> some View {
    Button {
      paste(item)
    } label: {
      HStack(spacing: 16) {
        preview(for: item)

        Spacer(minLength: 16)

        VStack(alignment: .trailing, spacing: 8) {
          Text(item.timestamp, format: .relative(presentation: .named))
            .font(.caption)
            .foregroundStyle(GamingPalette.mutedForeground)
            .environment(\.locale, Locale(identifier: "ja_JP"))

          if pastingItemId == item.id {
            HStack(spacing: 6) {
              ProgressView()
                .controlSize(.small)
                .tint(themeStore.accentColor)
              Text("Macへ貼り付け中")
                .font(.caption2.weight(.medium))
                .foregroundStyle(themeStore.accentColor)
            }
          } else {
            Label("タップして貼り付け", systemImage: "arrow.up.doc")
              .font(.caption2.weight(.medium))
              .foregroundStyle(themeStore.accentColor)
          }
        }
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 14)
      .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
      .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .gamingCard(
        accentColor: themeStore.accentColor,
        cornerRadius: 18,
        isEmphasized: pastingItemId == item.id
      )
    }
    .buttonStyle(ClipboardRowButtonStyle())
    .accessibilityHint("Macのクリップボードへ設定して貼り付けます")
  }

  @ViewBuilder
  private func preview(for item: ClipboardHistoryEntry) -> some View {
    switch item.kind {
    case .text:
      ZStack {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(themeStore.accentColor.opacity(0.14))
        Image(systemName: "doc.text")
          .font(.title3)
          .foregroundStyle(themeStore.accentColor)
      }
      .frame(width: 52, height: 52)

      VStack(alignment: .leading, spacing: 4) {
        Text("テキスト")
          .font(.caption.weight(.medium))
          .foregroundStyle(GamingPalette.mutedForeground)
        Text(item.textPreview ?? "")
          .font(.body.weight(.medium))
          .lineLimit(2)
          .foregroundStyle(GamingPalette.foreground)
      }

    case .image:
      if let base64 = item.imageThumbnailBase64,
         let data = Data(base64Encoded: base64),
         let uiImage = UIImage(data: data) {
        Image(uiImage: uiImage)
          .resizable()
          .scaledToFill()
          .frame(width: 64, height: 52)
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      } else {
        ZStack {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(themeStore.accentColor.opacity(0.14))
          Image(systemName: "photo")
            .font(.title3)
            .foregroundStyle(themeStore.accentColor)
        }
        .frame(width: 64, height: 52)
      }

      VStack(alignment: .leading, spacing: 4) {
        Text("画像")
          .font(.caption.weight(.medium))
          .foregroundStyle(GamingPalette.mutedForeground)
        Text("画像をMacへ貼り付け")
          .font(.body.weight(.medium))
          .foregroundStyle(GamingPalette.foreground)
      }
    }
  }

  // MARK: - Macとの通信

  private func refresh() {
    connectionManager.requestClipboardHistory()
  }

  private func paste(_ item: ClipboardHistoryEntry) {
    pastingItemId = item.id
    connectionManager.pasteClipboardItem(id: item.id) { _ in
      pastingItemId = nil
    }
  }
}

private struct ClipboardRowButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.985 : 1)
      .opacity(configuration.isPressed ? 0.88 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

#Preview {
  ClipboardView(connectionManager: ConnectionManager())
    .environment(ThemeStore())
}
