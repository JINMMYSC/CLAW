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
  }
}
