//
//  RimeLoggerViewController.swift
//
//
//  Created by morse on 2023/11/8.
//

import HamsterUIKit
import UIKit

class RimeLoggerViewController: NibLessViewController {
  private let finderViewModel: FinderViewModel

  lazy var rimeLoggerFileBrowseView: FileBrowserView = {
    // 防止文件夹被删除而产生异常
    try? FileManager.createDirectory(override: false, dst: FileManager.sandboxRimeLogDirectory)
    let fileBrowserViewModel = FileBrowserViewModel(rootURL: FileManager.sandboxRimeLogDirectory, enableEditorState: false)
    return FileBrowserView(finderViewModel: finderViewModel, fileBrowserViewModel: fileBrowserViewModel)
  }()

  init(finderViewModel: FinderViewModel) {
    self.finderViewModel = finderViewModel
    super.init()
  }

  override func loadView() {
    // FIX-HMSTR-029：AppGroup 的 rime-diag.log 含键盘扩展诊断（App 进程看不到），
    // 复制到沙盒 RIME 日志目录一并展示，便于定位「候选栏空白」断点。
    try? FileManager.createDirectory(override: false, dst: FileManager.sandboxRimeLogDirectory)
    let appGroupDiag = FileManager.appGroupUserDataDirectoryURL.appendingPathComponent("rime-diag.log")
    let diagDest = FileManager.sandboxRimeLogDirectory.appendingPathComponent("rime-diag-appgroup.log")
    if FileManager.default.fileExists(atPath: appGroupDiag.path),
       let data = try? Data(contentsOf: appGroupDiag) {
      try? data.write(to: diagDest)
    }
    view = rimeLoggerFileBrowseView
    title = "RIME 日志"
    // FIX-HMSTR-031：分享（TXT）+ 清除直接显示，分享比复制更快；不用宽文字按钮避免被折叠进「…」
    navigationItem.rightBarButtonItems = [
      UIBarButtonItem(
        barButtonSystemItem: .action,
        target: self,
        action: #selector(shareAllLogs(_:))
      ),
      UIBarButtonItem(
        image: UIImage(systemName: "trash"),
        style: .plain,
        target: self,
        action: #selector(clearLogs(_:))
      ),
    ]
  }

  /// 分享全部日志（含扩展侧 rime-diag-appgroup.log）为 .txt 文件，微信可直接接收
  @objc private func shareAllLogs(_ sender: UIBarButtonItem) {
    let text = Self.collectAllLogs()
    guard !text.isEmpty else { return }
    let url = Self.writeTemporaryLogTXT(text: text, baseName: "ClawTalk-RIME日志")
    let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    if let popover = activity.popoverPresentationController {
      popover.barButtonItem = sender
    }
    present(activity, animated: true)
  }

  /// 清除 RIME 日志目录下全部文件（含 AppGroup 扩展侧日志），带确认弹窗
  @objc private func clearLogs(_ sender: UIBarButtonItem) {
    let alert = UIAlertController(title: "清除日志", message: "确定删除全部 RIME 日志文件？", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "清除", style: .destructive) { [weak self] _ in
      self?.deleteAllLogs()
      self?.reloadFileBrowser()
    })
    present(alert, animated: true)
  }

  private func deleteAllLogs() {
    let fm = FileManager.default
    let sandboxDir = FileManager.sandboxRimeLogDirectory
    for name in (try? fm.contentsOfDirectory(atPath: sandboxDir.path)) ?? [] {
      try? fm.removeItem(at: sandboxDir.appendingPathComponent(name))
    }
    let appGroupDiag = FileManager.appGroupUserDataDirectoryURL.appendingPathComponent("rime-diag.log")
    try? fm.removeItem(at: appGroupDiag)
  }

  private func reloadFileBrowser() {
    try? FileManager.createDirectory(override: false, dst: FileManager.sandboxRimeLogDirectory)
    rimeLoggerFileBrowseView = FileBrowserView(
      finderViewModel: finderViewModel,
      fileBrowserViewModel: FileBrowserViewModel(rootURL: FileManager.sandboxRimeLogDirectory, enableEditorState: false)
    )
    view = rimeLoggerFileBrowseView
  }

  /// 将日志文本写入临时 .txt 文件（微信等 App 只能接收文件，不能接收纯文本）
  private static func writeTemporaryLogTXT(text: String, baseName: String) -> URL {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let stamp = formatter.string(from: Date())
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(baseName)-\(stamp).txt")
    try? text.data(using: .utf8)?.write(to: url)
    return url
  }

  /// 收集 RIME 日志目录下所有文件内容（含扩展侧 rime-diag-appgroup.log），合并为一段文本
  private static func collectAllLogs() -> String {
    var parts: [String] = []
    let fm = FileManager.default
    let sandboxDir = FileManager.sandboxRimeLogDirectory
    let files = ((try? fm.contentsOfDirectory(atPath: sandboxDir.path)) ?? []).sorted()
    for name in files {
      let url = sandboxDir.appendingPathComponent(name)
      if let data = try? Data(contentsOf: url),
         let content = String(data: data, encoding: .utf8),
         !content.isEmpty {
        parts.append("===== \(name) =====")
        parts.append(content)
      }
    }
    return parts.joined(separator: "\n\n")
  }
}
