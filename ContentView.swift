//
//  ContentView.swift
//  TeleDeck
//
//  Created by hara ryuto   on 2026/07/12.
//

import SwiftUI

struct ContentView: View {
  @State private var connectionManager = ConnectionManager()
  @State private var themeStore = ThemeStore()

  var body: some View {
    ZStack {
      GamingBackground(accentColor: themeStore.accentColor)

      Group {
        if connectionManager.state == .paired {
          MainTabView(connectionManager: connectionManager)
        } else {
          PairingView(connectionManager: connectionManager)
        }
      }
    }
    .environment(themeStore)
    .preferredColorScheme(themeStore.preferredColorScheme)
    .tint(themeStore.accentColor)
    .onAppear {
      connectionManager.connect()
    }
  }
}

#Preview {
  ContentView()
}
