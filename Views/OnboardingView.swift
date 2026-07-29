//
//  OnboardingView.swift
//  TeleDeck
//
//  初回起動時に、Macエージェントの起動からPIN入力までの流れを案内する画面。
//  ペアリング画面だけを見せられても「Mac側にもアプリが必要」であることが伝わらないため、
//  接続に必要な前提を先に示す。
//

import SwiftUI

struct OnboardingView: View {
  /// 案内を読み終えてペアリングへ進むときに呼ばれる
  var onFinish: () -> Void

  @Environment(ThemeStore.self) private var themeStore

  private struct Step: Identifiable {
    let id = UUID()
    let number: Int
    let title: String
    let detail: String
    let systemImage: String
  }

  private static let steps: [Step] = [
    Step(
      number: 1,
      title: "MacでTeleDeckを起動する",
      detail: "Mac版のTeleDeckを開くと、メニューバーにアイコンが常駐します。iPadから操作するにはこのアプリが動いている必要があります。",
      systemImage: "menubar.rectangle"
    ),
    Step(
      number: 2,
      title: "Macで操作の権限を許可する",
      detail: "メニューバーのTeleDeckを開き、アクセシビリティの権限を許可します。許可しないとキー送信やウィンドウ操作が動作しません。",
      systemImage: "checkmark.shield"
    ),
    Step(
      number: 3,
      title: "同じWi-Fiに接続する",
      detail: "iPadとMacを同じネットワークにつなぐと、TeleDeckが自動でMacを見つけます。",
      systemImage: "wifi"
    ),
    Step(
      number: 4,
      title: "PINまたはQRで接続する",
      detail: "Macに表示された6桁のPINをiPadで入力するか、QRコードを読み取ると接続が完了します。",
      systemImage: "qrcode.viewfinder"
    )
  ]

  var body: some View {
    ZStack {
      GamingBackground(
        accentColor: themeStore.accentColor,
        showsGlow: themeStore.backgroundGlowEnabled
      )

      VStack(spacing: 0) {
        header
          .padding(.top, 32)
          .padding(.bottom, 22)

        ScrollView {
          VStack(spacing: 12) {
            ForEach(Self.steps) { step in
              stepRow(step)
            }
          }
          .frame(maxWidth: 720)
          .padding(.horizontal, 32)
          .padding(.bottom, 20)
          .frame(maxWidth: .infinity)
        }

        Button {
          onFinish()
        } label: {
          Text("はじめる")
            .font(.headline)
            .frame(maxWidth: 320)
        }
        .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor))
        .padding(.bottom, 30)
      }
    }
  }

  private var header: some View {
    VStack(spacing: 10) {
      ZStack {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .fill(themeStore.accentColor.opacity(0.16))
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .stroke(themeStore.accentColor.opacity(0.5), lineWidth: 1.5)
        Image(systemName: "rectangle.grid.3x2.fill")
          .font(.system(size: 34, weight: .medium))
          .foregroundStyle(themeStore.accentColor)
      }
      .frame(width: 84, height: 72)

      Text("TeleDeckへようこそ")
        .font(.title.weight(.bold))
        .foregroundStyle(GamingPalette.foreground)

      Text("iPadをMacのコントロールパッドとして使うための準備をします")
        .font(.subheadline)
        .foregroundStyle(GamingPalette.mutedForeground)
        .multilineTextAlignment(.center)
    }
    .padding(.horizontal, 32)
  }

  private func stepRow(_ step: Step) -> some View {
    HStack(alignment: .top, spacing: 16) {
      ZStack {
        Circle()
          .fill(themeStore.accentColor.opacity(0.18))
        Text("\(step.number)")
          .font(.headline.monospacedDigit())
          .foregroundStyle(themeStore.accentColor)
      }
      .frame(width: 38, height: 38)

      VStack(alignment: .leading, spacing: 5) {
        Label(step.title, systemImage: step.systemImage)
          .font(.headline)
          .foregroundStyle(GamingPalette.foreground)

        Text(step.detail)
          .font(.subheadline)
          .foregroundStyle(GamingPalette.mutedForeground)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .gamingCard(accentColor: themeStore.accentColor, cornerRadius: 16)
    .accessibilityElement(children: .combine)
  }
}

#Preview {
  OnboardingView(onFinish: {})
    .environment(ThemeStore())
}
