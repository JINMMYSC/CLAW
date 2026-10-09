//
//  SettingsViewController.swift
//
//  Created by morse on 2023/6/12.
//

import HamsterKit
import HamsterUIKit
import OSLog
import ProgressHUD
import UIKit

protocol SettingsViewModelFactory {
  func makeSettingsViewModel() -> SettingsViewModel
}

public class SettingsViewController: NibLessViewController {
  // MARK: - properties

  private var settingsViewModel: SettingsViewModel
  private var rimeViewModel: RimeViewModel
  private var backupViewModel: BackupViewModel
  // Deployment is app lifecycle work, not a side effect of opening Settings.
  private var didStartAppDataBootstrap = false

  init(settingsViewModel: SettingsViewModel, rimeViewModel: RimeViewModel, backupViewModel: BackupViewModel) {
    self.settingsViewModel = settingsViewModel
    self.rimeViewModel = rimeViewModel
    self.backupViewModel = backupViewModel
    super.init()
  }
}

// MARK: override UIViewController

public extension SettingsViewController {
  override func loadView() {
    title = "设置"
    view = SettingsRootView(settingsViewModel: settingsViewModel, rimeViewModel: rimeViewModel, backupViewModel: backupViewModel)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    startAppDataBootstrapIfNeeded()
  }

  /// Invoke from the application's root controller even when the initial
  /// screen is CLAW rather than legacy Settings. Running deployment exactly
  /// once preserves first-launch resource setup and the keyboard's RIME data.
  func startAppDataBootstrapIfNeeded() {
    guard !didStartAppDataBootstrap else { return }
    didStartAppDataBootstrap = true
    Task {
      do {
        try await self.settingsViewModel.loadAppData()
      } catch {
        // Allow an explicit retry when the user returns to Settings, without
        // spinning in an unattended retry loop during a failing first launch.
        self.didStartAppDataBootstrap = false
        ProgressHUD.failed("导入数据异常", interaction: false, delay: 2)
        Logger.statistics.error("load app data error: \(error)")
      }
    }
  }
}
