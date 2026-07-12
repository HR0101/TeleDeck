//
//  TrackpadSurfaceView.swift
//  TeleDeck
//
//  トラックパッド操作面。SwiftUI標準のDragGestureは1本指しか判定できないため、
//  1本指=移動・2本指=スクロール・1本指タップ=左クリック・2本指タップ=右クリックを
//  UIKitのジェスチャーレコグナイザーで判定しUIViewRepresentable経由でSwiftUIへ橋渡しする。
//

import SwiftUI
import UIKit

struct TrackpadSurfaceView: UIViewRepresentable {
  var onMove: (CGFloat, CGFloat) -> Void
  var onScroll: (CGFloat, CGFloat) -> Void
  var onLeftClick: () -> Void
  var onRightClick: () -> Void

  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    view.backgroundColor = .clear
    view.isMultipleTouchEnabled = true

    let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
    pan.maximumNumberOfTouches = 2

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

    init(parent: TrackpadSurfaceView) {
      self.parent = parent
    }

    @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
      guard let view = recognizer.view else { return }

      switch recognizer.state {
      case .began:
        lastPanTranslation = .zero
      case .changed:
        let translation = recognizer.translation(in: view)
        let dx = translation.x - lastPanTranslation.x
        let dy = translation.y - lastPanTranslation.y
        lastPanTranslation = translation

        if recognizer.numberOfTouches >= 2 {
          parent.onScroll(dx, dy)
        } else {
          parent.onMove(dx, dy)
        }
      default:
        break
      }
    }

    @objc func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
      parent.onLeftClick()
    }

    @objc func handleTwoFingerTap(_ recognizer: UITapGestureRecognizer) {
      parent.onRightClick()
    }
  }
}
