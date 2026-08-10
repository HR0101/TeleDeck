//
//  IconImageStore.swift
//  TeleDeck
//
//  ボタンアイコン用に選択された画像/GIFのDataをDocuments/Icons/配下へ保存・読込・削除するユーティリティ。
//

import Foundation

enum IconImageStore {

  enum StoreError: LocalizedError {
    case directoryCreationFailed(Error)
    case writeFailed(Error)

    var errorDescription: String? {
      switch self {
      case .directoryCreationFailed(let error):
        return "アイコン保存用フォルダーの作成に失敗しました: \(error.localizedDescription)"
      case .writeFailed(let error):
        return "アイコン画像の保存に失敗しました: \(error.localizedDescription)"
      }
    }
  }

  /// 保存先ディレクトリ名（Documents直下）
  private static let directoryName = "Icons"

  /// Documents/Icons/ のURL。取得できない場合はnil
  private static var iconsDirectoryURL: URL? {
    guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
      return nil
    }
    return documentsURL.appendingPathComponent(directoryName, isDirectory: true)
  }

  /// 画像/GIFのDataをDocuments/Icons/へ保存し、保存後のファイル名を返す
  static func save(data: Data, suggestedExtension: String) throws -> String {
    guard let directoryURL = iconsDirectoryURL else {
      throw StoreError.directoryCreationFailed(CocoaError(.fileNoSuchFile))
    }

    if !FileManager.default.fileExists(atPath: directoryURL.path) {
      do {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
      } catch {
        throw StoreError.directoryCreationFailed(error)
      }
    }

    let fileName = "\(UUID().uuidString).\(suggestedExtension)"
    let fileURL = directoryURL.appendingPathComponent(fileName)

    do {
      try data.write(to: fileURL, options: .atomic)
    } catch {
      throw StoreError.writeFailed(error)
    }

    return fileName
  }

  /// 保存済みファイル名からURLを解決する。フォルダーが無い・ファイルが存在しない場合はnil
  static func url(forFileName fileName: String) -> URL? {
    guard let directoryURL = iconsDirectoryURL else { return nil }
    let fileURL = directoryURL.appendingPathComponent(fileName)
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
    return fileURL
  }

  /// 保存済みファイルを削除する。存在しない場合や削除に失敗した場合は無視する（呼び出し側のUIをブロックしないため）
  static func delete(fileName: String) {
    guard let directoryURL = iconsDirectoryURL else { return }
    let fileURL = directoryURL.appendingPathComponent(fileName)
    try? FileManager.default.removeItem(at: fileURL)
  }
}
