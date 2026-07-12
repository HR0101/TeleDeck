//
//  AnimatedIconView.swift
//  TeleDeck
//
//  ボタンアイコンを表示するビュー。SF Symbolsに加え、Documents/Icons/配下に保存された
//  静止画・GIFアニメーションを表示できる。SwiftUIのImageはGIFを再生できないため、
//  GIFの場合はImageIOでフレームを読み出し自前でアニメーションさせる。
//

import SwiftUI
import ImageIO
import UIKit

struct AnimatedIconView: View {
  let iconKind: IconKind
  let iconName: String
  let iconImageFileName: String?

  var body: some View {
    switch iconKind {
    case .sfSymbol:
      Image(systemName: iconName)
    case .image:
      imageContent
    }
  }

  @ViewBuilder
  private var imageContent: some View {
    if let fileName = iconImageFileName,
       let url = IconImageStore.url(forFileName: fileName),
       let data = try? Data(contentsOf: url) {
      DecodedImageView(data: data)
    } else {
      // ファイルが見つからない・読み込みに失敗した場合はクラッシュせずフォールバック表示にする
      Image(systemName: "photo")
    }
  }
}

/// GIFの1フレーム分の画像と表示時間
private struct GIFFrame {
  let image: CGImage
  /// このフレームを表示し続ける時間（秒）
  let duration: TimeInterval
}

/// 画像データをデコードし、複数フレームあればGIFとして自前でアニメーション再生し、
/// 単一フレームであれば静止画としてそのまま表示するビュー
private struct DecodedImageView: View {
  let data: Data

  /// ImageIOがdelay情報を返さない・極端に短い場合のフォールバック秒数（多くのGIFビューアーの慣習に合わせた値）
  private static let defaultFrameDuration: TimeInterval = 0.1
  /// この値未満のdelayは多くのビューアーでdefaultFrameDurationに丸められる慣習がある
  private static let minimumFrameDuration: TimeInterval = 0.02

  @State private var frames: [GIFFrame] = []
  @State private var totalDuration: TimeInterval = 0
  @State private var staticImage: UIImage?
  @State private var startDate = Date()
  /// UIScreen.mainはiOS26で非推奨のため、SwiftUIの環境値から画面倍率を取得する
  @Environment(\.displayScale) private var displayScale

  var body: some View {
    Group {
      if !frames.isEmpty {
        TimelineView(.animation) { context in
          if let cgImage = currentFrame(at: context.date) {
            Image(decorative: cgImage, scale: displayScale)
              .resizable()
              .scaledToFit()
          } else {
            Image(systemName: "photo")
          }
        }
      } else if let staticImage {
        Image(uiImage: staticImage)
          .resizable()
          .scaledToFit()
      } else {
        Image(systemName: "photo")
      }
    }
    .onAppear(perform: decode)
  }

  private func decode() {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      staticImage = UIImage(data: data)
      return
    }

    let frameCount = CGImageSourceGetCount(source)
    guard frameCount > 1 else {
      staticImage = UIImage(data: data)
      return
    }

    var decodedFrames: [GIFFrame] = []
    for index in 0..<frameCount {
      guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
      decodedFrames.append(GIFFrame(image: cgImage, duration: Self.frameDuration(source: source, index: index)))
    }

    // 1枚もデコードできなければ静止画としてのフォールバックを試みる
    guard !decodedFrames.isEmpty else {
      staticImage = UIImage(data: data)
      return
    }

    frames = decodedFrames
    totalDuration = decodedFrames.reduce(0) { $0 + $1.duration }
    startDate = Date()
  }

  private static func frameDuration(source: CGImageSource, index: Int) -> TimeInterval {
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
          let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
      return defaultFrameDuration
    }

    let unclampedDelay = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
    let delay = gifProperties[kCGImagePropertyGIFDelayTime] as? TimeInterval
    let resolvedDelay = unclampedDelay ?? delay ?? defaultFrameDuration

    return resolvedDelay < minimumFrameDuration ? defaultFrameDuration : resolvedDelay
  }

  private func currentFrame(at date: Date) -> CGImage? {
    guard let firstFrame = frames.first else { return nil }
    guard totalDuration > 0 else { return firstFrame.image }

    let elapsed = date.timeIntervalSince(startDate).truncatingRemainder(dividingBy: totalDuration)
    var accumulated: TimeInterval = 0
    for frame in frames {
      accumulated += frame.duration
      if elapsed < accumulated {
        return frame.image
      }
    }
    return frames.last?.image ?? firstFrame.image
  }
}

#Preview {
  AnimatedIconView(iconKind: .sfSymbol, iconName: "globe", iconImageFileName: nil)
    .font(.system(size: 28))
}
