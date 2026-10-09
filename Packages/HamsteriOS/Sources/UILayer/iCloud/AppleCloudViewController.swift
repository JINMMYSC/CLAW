//
//  AppleCloudViewController.swift
//  Hamster
//
//  Created by morse on 2023/6/14.
//
import Combine
import HamsterUIKit
import UIKit

protocol AppleCloudViewModelFactory {
  func makeAppleCloudViewModel() -> AppleCloudViewModel
}

class AppleCloudViewController: NibLessViewController {
  // MARK: properties

  let appleCloudViewModelFactory: AppleCloudViewModelFactory
  private var viewModel: AppleCloudViewModel?
  private var cancellables = Set<AnyCancellable>()

  // MARK: methods

  init(appleCloudViewModelFactory: AppleCloudViewModelFactory) {
    self.appleCloudViewModelFactory = appleCloudViewModelFactory
    super.init()
  }
}

// MARK: override UIViewController

extension AppleCloudViewController {
  override func loadView() {
    title = "iCloud同步"
    let vm = appleCloudViewModelFactory.makeAppleCloudViewModel()
    viewModel = vm
    view = AppleCloudRootView(viewModel: vm)
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    viewModel?.$restoreConfirmationRequested
      .receive(on: DispatchQueue.main)
      .removeDuplicates()
      .sink { [weak self] requested in
        guard requested else { return }
        self?.showRestoreConfirmation()
      }
      .store(in: &cancellables)

    viewModel?.$syncState
      .receive(on: DispatchQueue.main)
      .sink { [weak self] state in
        guard case .finished(let success, let message) = state else { return }
        self?.showSyncResultAlert(success: success, message: message)
      }
      .store(in: &cancellables)
  }

  private func showRestoreConfirmation() {
    guard let vm = viewModel else { return }
    let alert = UIAlertController(
      title: "确认从 iCloud 恢复？",
      message: "此操作会覆盖本机输入方案和用户词库文件。请先将现有资料备份到其他位置，确认云端版本正确后再继续。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
      vm.restoreConfirmationRequested = false
    })
    alert.addAction(UIAlertAction(title: "确认覆盖本地文件", style: .destructive) { _ in
      vm.restoreConfirmationRequested = false
      Task { await vm.restoreFromiCloud() }
    })
    present(alert, animated: true)
  }

  private func showSyncResultAlert(success: Bool, message: String) {
    let alert = UIAlertController(
      title: success ? "同步成功" : "同步失败",
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
      (self?.view as? AppleCloudRootView)?.reloadSyncStatus()
    })
    present(alert, animated: true)
  }
}
