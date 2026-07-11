//
//  ContentView.swift
//  TeleDeck
//
//  Created by hara ryuto   on 2026/07/12.
//

import SwiftUI

struct ContentView: View {
  @State private var connectionManager = ConnectionManager()

  var body: some View {
    Group {
      if connectionManager.state == .paired {
        PanelView(connectionManager: connectionManager)
      } else {
        PairingView(connectionManager: connectionManager)
      }
    }
    .onAppear {
      connectionManager.connect()
    }
  }
}

#Preview {
  ContentView()
}
