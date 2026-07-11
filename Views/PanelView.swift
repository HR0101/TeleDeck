//
//  PanelView.swift
//  TeleDeck
//
//  Stream Deck風のボタングリッド画面（フェーズ1: 固定プロファイルのみ）。
//

import SwiftUI

struct PanelView: View {
  let connectionManager: ConnectionManager

  private let columns = [
    GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()),
    GridItem(.flexible()), GridItem(.flexible())
  ]

  private let buttons: [PanelButton] = [
    PanelButton(label: "Chrome", systemImage: "globe", action: ActionPayload(type: .launchApp, target: "Google Chrome")),
    PanelButton(label: "Safari", systemImage: "safari", action: ActionPayload(type: .launchApp, target: "Safari")),
    PanelButton(label: "リンクを開く", systemImage: "link", action: ActionPayload(type: .openURL, target: "https://example.com")),
    PanelButton(label: "コピー", systemImage: "doc.on.doc", action: ActionPayload(type: .hotkey, keys: ["cmd", "c"])),
    PanelButton(label: "ペースト", systemImage: "clipboard", action: ActionPayload(type: .hotkey, keys: ["cmd", "v"]))
  ]

  var body: some View {
    VStack {
      Text("TeleDeck")
        .font(.headline)
        .padding(.top)

      LazyVGrid(columns: columns, spacing: 16) {
        ForEach(buttons) { button in
          Button {
            connectionManager.execute(button.action)
          } label: {
            VStack(spacing: 8) {
              Image(systemName: button.systemImage)
                .font(.system(size: 28))
              Text(button.label)
                .font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
          }
          .buttonStyle(.plain)
        }
      }
      .padding()

      Spacer()
    }
  }
}

private struct PanelButton: Identifiable {
  let id = UUID()
  let label: String
  let systemImage: String
  let action: ActionPayload
}

#Preview {
  PanelView(connectionManager: ConnectionManager())
}
