//
//  SettingsView.swift
//  TeleDeck
//
//  外観（ダーク/ライト/システム準拠）とアクセントカラーを設定するシート画面。
//

import SwiftUI

struct SettingsView: View {
  @Bindable var themeStore: ThemeStore
  @Environment(\.dismiss) private var dismiss

  init(themeStore: ThemeStore) {
    self.themeStore = themeStore
  }

  var body: some View {
    NavigationStack {
      Form {
        appearanceSection
        accentColorSection
      }
      .scrollContentBackground(.hidden)
      .background(GamingPalette.background)
      .navigationTitle("設定")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("閉じる") {
            dismiss()
          }
          .foregroundStyle(themeStore.accentColor)
        }
      }
    }
  }

  // MARK: - 外観設定

  private var appearanceSection: some View {
    Section {
      Picker("外観", selection: $themeStore.colorScheme) {
        ForEach(AppColorScheme.allCases) { option in
          Text(option.displayName).tag(option)
        }
      }
      .pickerStyle(.segmented)
    } header: {
      Text("外観")
        .foregroundStyle(GamingPalette.mutedForeground)
    }
    .listRowBackground(GamingPalette.card.opacity(0.55))
  }

  // MARK: - アクセントカラー設定

  private var accentColorSection: some View {
    Section {
      ForEach(AccentColorOption.allCases) { option in
        accentColorRow(option)
      }
    } header: {
      Text("アクセントカラー")
        .foregroundStyle(GamingPalette.mutedForeground)
    }
    .listRowBackground(GamingPalette.card.opacity(0.55))
  }

  private func accentColorRow(_ option: AccentColorOption) -> some View {
    Button {
      themeStore.accentColorOption = option
    } label: {
      HStack {
        Circle()
          .fill(option.color)
          .frame(width: 24, height: 24)
          .overlay(
            Circle()
              .stroke(
                themeStore.accentColorOption == option ? themeStore.accentColor : Color.clear,
                lineWidth: 2
              )
              .padding(-3)
          )

        Text(option.displayName)
          .foregroundStyle(GamingPalette.foreground)

        Spacer()

        if themeStore.accentColorOption == option {
          Image(systemName: "checkmark")
            .foregroundStyle(themeStore.accentColor)
        }
      }
    }
    .buttonStyle(.plain)
  }
}

#Preview {
  SettingsView(themeStore: ThemeStore())
}
