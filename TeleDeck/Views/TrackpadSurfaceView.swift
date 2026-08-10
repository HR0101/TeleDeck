//
//  TrackpadSurfaceView.swift
//  TeleDeck
//
//  トラックパッド操作面。SwiftUI標準のDragGestureは1本指しか判定できないため、
//  1本指=移動・2本指=スクロール・1本指タップ=左クリック・2本指タップ=右クリック・
//  3本指左右スワイプ=Macのスペース切替を
//  UIKitのジェスチャーレコグナイザーで判定しUIViewRepresentable経由でSwiftUIへ橋渡しする。
//
//  移動/スクロール/3本指スワイプは単一のUIPanGestureRecognizer（最大3本指まで許容）に統合している。
//  別々のレコグナイザーに分けると、指の着地タイミングが数十ミリ秒でもずれた場合に
//  移動用ジェスチャーが先に認識を開始してタッチ列を横取りしてしまい、3本指スワイプが
//  永久に成立しなくなる（UIGestureRecognizerは同一ビュー上で基本的に排他的なため）。
//  さらにUISwipeGestureRecognizerは全指が同時・同速で直線移動しないと無言で失敗する弱点があり、
//  この2つが重なって「3本指スワイプが効いたり効かなかったり」する原因になっていた。
//

import SwiftUI
import UIKit

/// iPadOSはUndo/Redo用に3本指スワイプ・3本指タップ・3本指ピンチをシステムレベルで予約しており、
/// responder chain上にundoManagerが存在すると自動的にこのシステムジェスチャーが割り込み、
/// アプリ側のジェスチャーレコグナイザーより先にタッチを横取りしてしまう（3本指スワイプが「全く反応しない」原因）。
/// undoManagerをnilにしてresponder chainを断ち切ることで、このシステムジェスチャーの介入を防ぐ。
private final class TrackpadTouchView: UIView {
  override var undoManager: UndoManager? { nil }
}

struct TrackpadSurfaceView: UIViewRepresentable {
  var onMove: (CGFloat, CGFloat) -> Void
  var onScroll: (CGFloat, CGFloat) -> Void
  var onLeftClick: () -> Void
  var onRightClick: () -> Void
  var onThreeFingerSwipeLeft: () -> Void
  var onThreeFingerSwipeRight: () -> Void
  var onThreeFingerSwipeUp: () -> Void
  var onThreeFingerSwipeDown: () -> Void

  func makeUIView(context: Context) -> UIView {
    let view = TrackpadTouchView()
    view.backgroundColor = .clear
    view.isMultipleTouchEnabled = true

    let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
    // maximumNumberOfTouchesを超えるタッチがあるとジェスチャー全体が認識されなくなる（Appleの仕様）。
    // 実機で3本指を置くと手のひらの縁などが微妙に4本目として検知されることがあり、
    // それだけで3本指スワイプ自体が発火しなくなっていたため、上限に余裕を持たせる。
    // ロジック側は既にnumberOfTouches >= 3をまとめて「3本指以上」として扱うため、挙動は変わらない。
    pan.maximumNumberOfTouches = 5

    let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
    singleTap.numberOfTouchesRequired = 1

    let twoFingerTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTwoFingerTap(_:)))
    twoFingerTap.numberOfTouchesRequired = 2

    // 2本指タップの瞬間に1本指タップが誤って先に成立しないようにする
    singleTap.require(toFail: twoFingerTap)

    view.addGestureRecognizer(pan)
    view.addGestureRecognizer(singleTap)
    view.addGestureRecognizer(twoFingerTap)

    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    context.coordinator.parent = self
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  final class Coordinator: NSObject {
    var parent: TrackpadSurfaceView
    private var lastPanTranslation: CGPoint = .zero
    /// 3本指スワイプの判定基準点（3本指になった瞬間のtranslationを起点にすることで、
    /// 1〜2本指で既に動かしていた分の移動量を誤って含めないようにする）
    private var threeFingerSwipeBaseline: CGPoint?
    /// 1回のジェスチャー中に1度だけスワイプを発火させるためのフラグ
    private var hasFiredThreeFingerSwipe = false

    /// この距離（pt）を超えて動いたら3本指スワイプとして発火する
    private static let threeFingerSwipeThreshold: CGFloat = 80

    init(parent: TrackpadSurfaceView) {
      self.parent = parent
    }

    @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
      guard let view = recognizer.view else { return }

      switch recognizer.state {
      case .began:
        lastPanTranslation = .zero
        threeFingerSwipeBaseline = nil
        hasFiredThreeFingerSwipe = false

      case .changed:
        let translation = recognizer.translation(in: view)

        if recognizer.numberOfTouches >= 3 {
          handleThreeFingerSwipe(translation: translation)
          return
        }

        // 3本指から指を離して2本以下に戻った場合に備えてリセットしておく
        threeFingerSwipeBaseline = nil

        let dx = translation.x - lastPanTranslation.x
        let dy = translation.y - lastPanTranslation.y
        lastPanTranslation = translation

        if recognizer.numberOfTouches == 2 {
          parent.onScroll(dx, dy)
        } else {
          parent.onMove(dx, dy)
        }

      default:
        break
      }
    }

    private func handleThreeFingerSwipe(translation: CGPoint) {
      guard !hasFiredThreeFingerSwipe else { return }

      let baseline = threeFingerSwipeBaseline ?? translation
      if threeFingerSwipeBaseline == nil {
        threeFingerSwipeBaseline = translation
      }

      let dx = translation.x - baseline.x
      let dy = translation.y - baseline.y

      // 水平方向の移動距離が垂直方向より大きい場合は左右スワイプ
      if abs(dx) > abs(dy) {
        if dx <= -Self.threeFingerSwipeThreshold {
          hasFiredThreeFingerSwipe = true
          parent.onThreeFingerSwipeLeft()
        } else if dx >= Self.threeFingerSwipeThreshold {
          hasFiredThreeFingerSwipe = true
          parent.onThreeFingerSwipeRight()
        }
      } else {
        // 垂直方向の移動距離が大きい場合は上下スワイプ (UIKitではy軸は下向きが正)
        if dy <= -Self.threeFingerSwipeThreshold {
          hasFiredThreeFingerSwipe = true
          parent.onThreeFingerSwipeUp()
        } else if dy >= Self.threeFingerSwipeThreshold {
          hasFiredThreeFingerSwipe = true
          parent.onThreeFingerSwipeDown()
        }
      }
    }

    @objc func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
      parent.onLeftClick()
      Self.resetTouchState(of: recognizer)
    }

    @objc func handleTwoFingerTap(_ recognizer: UITapGestureRecognizer) {
      parent.onRightClick()
      Self.resetTouchState(of: recognizer)
    }

    /// UITapGestureRecognizerはnumberOfTouchesRequiredの内部状態を認識後も保持し続けることがあり、
    /// 「2本指タップ→1本指タップ」のように本数が変わる連続操作で次のタップの本数を誤判定する原因になる。
    /// isEnabledをfalse→trueと切り替えることでUIKitに内部のタッチ追跡を強制的に破棄させ、リセットする。
    private static func resetTouchState(of recognizer: UIGestureRecognizer) {
      recognizer.isEnabled = false
      recognizer.isEnabled = true
    }
  }
}
