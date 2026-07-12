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
    NavigationStack {
      content
        .background(GamingPalette.background)
        .navigationTitle("クリップボード")
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              refresh()
            } label: {
              Image(systemName: "arrow.clockwise")
                .foregroundStyle(themeStore.accentColor)
            }
          }
        }
        .onAppear {
          connectionManager.onClipboardHistory = { entries in
            items = entries
          }
          refresh()
        }
    }
  }

  // MARK: - 一覧表示

  @ViewBuilder
  private var content: some View {
    if items.isEmpty {
      emptyState
    } else {
      List(items) { item in
        row(for: item)
          .listRowBackground(GamingPalette.card.opacity(0.55))
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .background(GamingPalette.background)
    }
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: "doc.on.clipboard")
        .font(.system(size: 40))
        .foregroundStyle(GamingPalette.mutedForeground)
      Text("コピー履歴がありません")
        .foregroundStyle(GamingPalette.mutedForeground)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(GamingPalette.background)
  }

  private func row(for item: ClipboardHistoryEntry) -> some View {
    HStack(spacing: 12) {
      preview(for: item)

      Spacer()

      Text(item.timestamp, format: .relative(presentation: .named))
        .font(.caption2)
        .foregroundStyle(GamingPalette.mutedForeground)

      if pastingItemId == item.id {
        ProgressView()
          .controlSize(.small)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      paste(item)
    }
  }

  @ViewBuilder
  private func preview(for item: ClipboardHistoryEntry) -> some View {
    switch item.kind {
    case .text:
      Image(systemName: "doc.text")
        .font(.title3)
        .foregroundStyle(themeStore.accentColor)
        .frame(width: 28)
      Text(item.textPreview ?? "")
        .lineLimit(3)
        .foregroundStyle(GamingPalette.foreground)

    case .image:
      if let base64 = item.imageThumbnailBase64,
         let data = Data(base64Encoded: base64),
         let uiImage = UIImage(data: data) {
        Image(uiImage: uiImage)
          .resizable()
          .scaledToFit()
          .frame(width: 44, height: 44)
          .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
      } else {
        Image(systemName: "photo")
          .font(.title3)
          .foregroundStyle(themeStore.accentColor)
          .frame(width: 28)
      }
      Text("画像")
        .foregroundStyle(GamingPalette.foreground)
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

#Preview {
  ClipboardView(connectionManager: ConnectionManager())
    .environment(ThemeStore())
}
