//
//  AboutViewController.swift
//  Hamster
//
//  Created by morse on 2023/6/15.
//

import Combine
import HamsterKit
import HamsterUIKit
import ProgressHUD
import UIKit

protocol AboutViewModelFactory {
  func makeAboutViewModel() -> AboutViewModel
}

protocol OpenSourceViewControllerFactory {
  func makeOpenSourceViewController() -> OpenSourceViewController
}

class AboutViewController: NibLessViewController, UIDocumentPickerDelegate {
  private let aboutViewModel: AboutViewModel
  private let openSourceViewController: OpenSourceViewController
  private var subscriptions = Set<AnyCancellable>()

  init(aboutViewModelFactory: AboutViewModelFactory, openSourceViewControllerFactory: OpenSourceViewControllerFactory) {
    self.aboutViewModel = aboutViewModelFactory.makeAboutViewModel()
    self.openSourceViewController = openSourceViewControllerFactory.makeOpenSourceViewController()
    super.init()

    combine()
  }

  override func loadView() {
    title = "关于"
    view = AboutRootView(aboutViewModel: aboutViewModel)
  }

  func combine() {
    aboutViewModel.$displayOpenSourceView
      .receive(on: DispatchQueue.main)
      .sink { [unowned self] in
        guard $0 else { return }
        presentOpenSourceView()
      }
      .store(in: &subscriptions)

    // 重置 UI 设置 confirm 对话框
    aboutViewModel.restUISettingsPublished
      .receive(on: DispatchQueue.main)
      .sink { [unowned self] callback in
        self.alertConfirm(alertTitle: "重置 UI 设置", message: "确认重置 UI 交互生成的设置吗？", confirmTitle: "确定", confirmCallback: {
          callback()
          ProgressHUD.success("重置成功", interaction: false, delay: 1.5)
        })
      }
      .store(in: &subscriptions)

    // 导出配置文件
    aboutViewModel.exportConfigurationPublished
      .receive(on: DispatchQueue.main)
      .sink { [unowned self] exportURL in
        let pickerVC = UIDocumentPickerViewController(forExporting: [exportURL])
        pickerVC.modalPresentationStyle = .formSheet
        pickerVC.shouldShowFileExtensions = true
        pickerVC.delegate = self
        present(pickerVC, animated: true)
      }
      .store(in: &subscriptions)

    aboutViewModel.resetRequestPublished
      .receive(on: DispatchQueue.main)
      .sink { [weak self] mode in
        self?.confirmReset(mode)
      }
      .store(in: &subscriptions)

    aboutViewModel.resetCompletedPublished
      .receive(on: DispatchQueue.main)
      .sink { [weak self] report in
        self?.presentResetResult(report)
      }
      .store(in: &subscriptions)
  }

  private func confirmReset(_ mode: ClawResetMode) {
    let title: String
    let message: String
    switch mode {
    case .inputLearningOnly:
      title = "重置输入法学习"
      message = "将删除 RIME 用户词典、自造词和智能调频规则。长期记忆、人物、任务、会话、API Key 与输入方案文件都会保留。此操作不可撤销。"
    case .full:
      title = "重置 App"
      message = "将删除长期记忆、聊天时间线、任务、人物档案、Skill 与反馈、输入和剪贴板记录、会话历史、隐私保险箱内容及输入法学习，并恢复默认设置。API Key 与输入方案文件会保留。此操作不可撤销。"
    }
    alertConfirm(alertTitle: title, message: message, confirmTitle: "确认重置") { [weak self] in
      Task { @MainActor in
        await ProgressHUD.animate("正在重置…", interaction: false)
        self?.aboutViewModel.performReset(mode)
      }
    }
  }

  private func presentResetResult(_ report: ClawResetReport) {
    if report.succeeded {
      ProgressHUD.success(report.userMessage, interaction: false, delay: 1.5)
      if report.mode == .full {
        navigationController?.popToRootViewController(animated: true)
      } else {
        (view as? AboutRootView)?.reloadData()
      }
      return
    }
    ProgressHUD.dismiss()
    let alert = UIAlertController(title: "重置未完整完成", message: report.userMessage, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "知道了", style: .default))
    present(alert, animated: true)
  }

  func presentOpenSourceView() {
    navigationController?.pushViewController(openSourceViewController, animated: true)
  }
}

