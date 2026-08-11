//
//  QRScannerView.swift
//  TeleDeck
//
//  Macに表示されたペアリングQRをカメラで読み取る画面。
//  読み取ったQR（PairingQRPayload）からPINを取り出し、PIN手入力の代わりに使う。
//

import AVFoundation
import SwiftUI
import UIKit

// MARK: - カメラ映像 + QR検出（AVFoundationのラッパー）

/// AVCaptureSessionでQRコードを検出し、検出した文字列を`onScan`で通知するビュー。
struct QRCameraView: UIViewControllerRepresentable {
  /// QRの文字列（＝JSON）を検出したときに呼ばれる
  var onScan: (String) -> Void
  /// カメラの初期化に失敗したときに呼ばれる
  var onSetupFailed: () -> Void

  func makeUIViewController(context: Context) -> QRScannerController {
    let controller = QRScannerController()
    controller.onScan = onScan
    controller.onSetupFailed = onSetupFailed
    return controller
  }

  func updateUIViewController(_ uiViewController: QRScannerController, context: Context) {}
}

/// カメラのセットアップ・プレビュー表示・QR検出を担当するUIViewController
final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  var onScan: ((String) -> Void)?
  var onSetupFailed: (() -> Void)?

  /// 同じQRを検出し続けても連続で通知しないよう、1度通知したらこの秒数だけ次の検出を抑止する
  private static let rescanSuppressInterval: TimeInterval = 1.5
  private static let scanAreaSideLength: CGFloat = 220

  private let session = AVCaptureSession()
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var metadataOutput: AVCaptureMetadataOutput?
  /// セッションの開始/停止はメインスレッドを塞がないよう専用キューで行う
  private let sessionQueue = DispatchQueue(label: "TeleDeck.QRScannerController.session")
  /// QR解析をUI更新から分離し、検出中のメインスレッド負荷を抑える
  private let metadataQueue = DispatchQueue(label: "TeleDeck.QRScannerController.metadata", qos: .userInitiated)
  /// 直近に検出済みで、次の検出を一時的に無視している状態か
  private var isSuppressingDetection = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    configureSession()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer?.frame = view.bounds
    updateRectOfInterest()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    startSession()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    stopSession()
  }

  private func configureSession() {
    session.beginConfiguration()
    defer { session.commitConfiguration() }

    if session.canSetSessionPreset(.medium) {
      session.sessionPreset = .medium
    }

    guard let device = AVCaptureDevice.default(for: .video),
          let input = try? AVCaptureDeviceInput(device: device),
          session.canAddInput(input) else {
      onSetupFailed?()
      return
    }
    session.addInput(input)

    let metadataOutput = AVCaptureMetadataOutput()
    guard session.canAddOutput(metadataOutput) else {
      onSetupFailed?()
      return
    }
    session.addOutput(metadataOutput)
    metadataOutput.setMetadataObjectsDelegate(self, queue: metadataQueue)
    metadataOutput.metadataObjectTypes = [.qr]
    self.metadataOutput = metadataOutput

    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    view.layer.addSublayer(layer)
    previewLayer = layer
  }

  /// 画面中央の読み取り枠だけをQR解析対象にし、フレーム全体を走査し続けないようにする。
  private func updateRectOfInterest() {
    guard let previewLayer, let metadataOutput, !view.bounds.isEmpty else { return }
    let sideLength = min(Self.scanAreaSideLength, min(view.bounds.width, view.bounds.height) * 0.7)
    let scanRect = CGRect(
      x: view.bounds.midX - sideLength / 2,
      y: view.bounds.midY - sideLength / 2,
      width: sideLength,
      height: sideLength
    )
    metadataOutput.rectOfInterest = previewLayer.metadataOutputRectConverted(fromLayerRect: scanRect)
  }

  private func startSession() {
    sessionQueue.async { [weak self] in
      guard let self, !self.session.isRunning else { return }
      self.session.startRunning()
    }
  }

  private func stopSession() {
    sessionQueue.async { [weak self] in
      guard let self, self.session.isRunning else { return }
      self.session.stopRunning()
    }
  }

  func metadataOutput(_ output: AVCaptureMetadataOutput,
                      didOutput metadataObjects: [AVMetadataObject],
                      from connection: AVCaptureConnection) {
    guard !isSuppressingDetection,
          let object = metadataObjects
            .compactMap({ $0 as? AVMetadataMachineReadableCodeObject })
            .first(where: { $0.type == .qr }),
          let stringValue = object.stringValue else {
      return
    }

    if isValidTeleDeckQR(stringValue) {
      // 有効なQRを得た時点でカメラを即停止し、シートが閉じるまでの余分なフレーム処理を防ぐ。
      isSuppressingDetection = true
      stopSession()
      DispatchQueue.main.async { [weak self] in
        self?.onScan?(stringValue)
      }
      return
    }

    // 無効なQRはメッセージ表示後に再読み取りできるよう、専用キュー上で一定時間だけ抑止する。
    isSuppressingDetection = true
    metadataQueue.asyncAfter(deadline: .now() + Self.rescanSuppressInterval) { [weak self] in
      self?.isSuppressingDetection = false
    }
    DispatchQueue.main.async { [weak self] in
      self?.onScan?(stringValue)
    }
  }

  private func isValidTeleDeckQR(_ string: String) -> Bool {
    guard let data = string.data(using: .utf8),
          let payload = try? JSONDecoder().decode(PairingQRPayload.self, from: data) else {
      return false
    }
    return payload.isValid
  }
}

// MARK: - ペアリングQR読み取りシート（カメラ権限の処理込み）

/// MacのペアリングQRをカメラで読み取り、取り出したPINを`onFoundPIN`で通知するシート。
/// カメラ権限の未決定/拒否も含めてハンドリングする。
struct QRScannerSheet: View {
  /// 有効なTeleDeckのQRから取り出したPINを通知する
  var onFoundPIN: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(ThemeStore.self) private var themeStore

  @State private var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
  @State private var message: String?

  var body: some View {
    NavigationStack {
      content
        .navigationTitle("QRで接続")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("閉じる") { dismiss() }
          }
        }
    }
    .task {
      await requestAccessIfNeeded()
    }
  }

  @ViewBuilder
  private var content: some View {
    switch authorizationStatus {
    case .authorized:
      scanner
    case .notDetermined:
      ProgressView("カメラを準備しています…")
    case .denied, .restricted:
      permissionDeniedView
    @unknown default:
      permissionDeniedView
    }
  }

  private var scanner: some View {
    ZStack {
      QRCameraView(
        onScan: handleScannedString,
        onSetupFailed: { message = "カメラを起動できませんでした" }
      )
      .ignoresSafeArea()

      // 読み取り位置の目安となる枠
      RoundedRectangle(cornerRadius: 20)
        .stroke(themeStore.accentColor, lineWidth: 3)
        .frame(width: 220, height: 220)

      VStack {
        Spacer()
        Text(message ?? "Macに表示されたQRコードを枠内に映してください")
          .font(.callout)
          .foregroundStyle(.white)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .background(.black.opacity(0.55), in: Capsule())
          .padding(.bottom, 40)
          .padding(.horizontal, 24)
      }
    }
  }

  private var permissionDeniedView: some View {
    VStack(spacing: 16) {
      Image(systemName: "camera.fill")
        .font(.system(size: 40))
        .foregroundStyle(GamingPalette.mutedForeground)
      Text("カメラへのアクセスが許可されていません")
        .font(.headline)
        .foregroundStyle(GamingPalette.foreground)
      Text("QRコードで接続するには、設定アプリでTeleDeckにカメラの使用を許可してください。PINの手入力でも接続できます。")
        .font(.callout)
        .foregroundStyle(GamingPalette.mutedForeground)
        .multilineTextAlignment(.center)
      Button("設定を開く") {
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
      }
      .buttonStyle(GamingButtonStyle(accentColor: themeStore.accentColor))
    }
    .padding(32)
  }

  /// カメラ権限が未決定なら要求し、結果を状態へ反映する
  private func requestAccessIfNeeded() async {
    guard authorizationStatus == .notDetermined else { return }
    let granted = await AVCaptureDevice.requestAccess(for: .video)
    authorizationStatus = granted ? .authorized : .denied
  }

  /// 読み取ったQR文字列をPairingQRPayloadとして解釈し、妥当ならPINを通知して閉じる
  private func handleScannedString(_ string: String) {
    guard let data = string.data(using: .utf8),
          let payload = try? JSONDecoder().decode(PairingQRPayload.self, from: data),
          payload.isValid else {
      message = "TeleDeckのペアリングQRではありません"
      return
    }
    onFoundPIN(payload.pin)
    dismiss()
  }
}
