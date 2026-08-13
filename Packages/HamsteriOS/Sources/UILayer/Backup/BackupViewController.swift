//
//  BackupViewController.swift
//  Hamster
//
//  Created by morse on 2023/6/14.
//

import Combine
import HamsterUIKit
import ProgressHUD
import UIKit
import UniformTypeIdentifiers

class BackupViewController: NibLessViewController, UIDocumentPickerDelegate {
  // MARK: properties

  private let backupViewModel: BackupViewModel
  private var subscriptions = Set<AnyCancellable>()

  // MARK: methods

  init(backupViewModel: BackupViewModel) {
    self.backupViewModel = backupViewModel
    super.init()

    backupViewModel.$backupSwipeAction
      .receive(on: DispatchQueue.main)
      .sink { [unowned self] action in
        guard let action = action else { return }
        swipeActionHandled(action: action)
      }.store(in: &subscriptions)

    backupViewModel.$importBackupRequested
      .receive(on: DispatchQueue.main)
      .sink { [unowned self] requested in
        guard requested else { return }
        presentImportPicker()
      }.store(in: &subscriptions)

    backupViewModel.$shareFile
      .receive(on: DispatchQueue.main)
      .sink { [unowned self] fileInfo in
        guard let fileInfo = fileInfo else { return }
        presentShareActivity(fileInfo: fileInfo)
      }.store(in: &subscriptions)
  }

  override func loadView() {
    title = "备份与恢复"
    view = BackupRootView(backupViewModel: backupViewModel)
  }

  func swipeActionHandled(action: BackupSwipeAction) {
    switch action {
    case .delete:
      deleteBackupAction()
    case .rename:
      renameAction()
    }
  }

  func deleteBackupAction() {
    let alertController = UIAlertController(title: "是否删除？", message: "文件删除后无法恢复，确认删除？", preferredStyle: .alert)
    alertController.addAction(UIAlertAction(title: "确认", style: .destructive, handler: { [unowned self] _ in
      Task {
        guard let selectFile = backupViewModel.selectFile else { return }
        do {
          try self.backupViewModel.deleteBackupFile(selectFile.url)
        } catch {
          presentError(error: ErrorMessage(title: "删除文件", message: "删除失败"))
        }
        self.backupViewModel.loadBackupFiles()
      }
    }))
    alertController.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
    present(alertController, animated: true, completion: nil)
  }

  func renameAction() {
    let alertController = UIAlertController(title: "修改备份文件名称", message: nil, preferredStyle: .alert)
    alertController.addTextField { $0.placeholder = "新文件名称" }
    alertController.addAction(UIAlertAction(title: "确认", style: .destructive, handler: { [unowned self, alertController] _ in
      Task {
        guard let textFields = alertController.textFields else { return }
        guard let selectFile = backupViewModel.selectFile else { return }
        let newFileName = textFields[0].text ?? ""
        guard !newFileName.isEmpty else { return }
        try await self.backupViewModel.renameBackupFile(at: selectFile.url, newFileName: newFileName)
        self.backupViewModel.loadBackupFiles()
      }
    }))
    alertController.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
    present(alertController, animated: true)
  }

  /// 导入备份：打开文件选择器
  func presentImportPicker() {
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.zip])
    picker.delegate = self
    picker.allowsMultipleSelection = false
    present(picker, animated: true)
  }

  /// 分享备份文件
  func presentShareActivity(fileInfo: FileInfo) {
    let activity = UIActivityViewController(activityItems: [fileInfo.url], applicationActivities: nil)
    activity.popoverPresentationController?.sourceView = view
    present(activity, animated: true)
  }
}

// MARK: - UIDocumentPickerDelegate

extension BackupViewController: UIDocumentPickerDelegate {
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else { return }
    Task {
      do {
        try await backupViewModel.importBackup(from: url)
        await ProgressHUD.success("导入成功", interaction: false, delay: 1.5)
      } catch {
        await ProgressHUD.failed("导入失败", interaction: false, delay: 2)
      }
    }
  }
}
