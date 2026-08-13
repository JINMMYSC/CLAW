//
//  File.swift
//
//
//  Created by morse on 2023/7/6.
//

import Combine
import Foundation
import HamsterKit
import HamsterKeyboardKit
import OSLog
import ProgressHUD
import UIKit

public class AppleCloudViewModel: ObservableObject {
  public enum SyncState {
    case idle
    case syncing
    case finished(success: Bool, message: String)
  }

  public let settingsViewModel: SettingsViewModel

  @Published public var syncState: SyncState = .idle

  // MARK: - Last Sync Status (persisted in UserDefaults)

  private let lastSyncTimeKey = "icloud_last_sync_time"
  private let lastSyncSuccessKey = "icloud_last_sync_success"

  public var lastSyncDescription: String {
    guard let date = UserDefaults.standard.object(forKey: lastSyncTimeKey) as? Date else { return "" }
    let success = UserDefaults.standard.bool(forKey: lastSyncSuccessKey)
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return (success ? "上次同步成功：" : "上次同步失败：") + formatter.string(from: date)
  }

  public var regexOnCopyFile: String {
    get {
      HamsterConfigurationStore.shared.configuration.general?.regexOnCopyFile?.joined(separator: ",") ?? ""
    }
    set {
      HamsterConfigurationStore.shared.configuration.general?.regexOnCopyFile = (newValue.split(separator: ",").map { String($0) })
      HamsterConfigurationStore.shared.applicationConfiguration.general?.regexOnCopyFile = (newValue.split(separator: ",").map { String($0) })
    }
  }

  lazy var settings: [SettingItemModel] = [
    .init(
      text: "iCloud",
      type: .toggle,
      toggleValue: { [unowned self] in settingsViewModel.enableAppleCloud },
      toggleHandled: { [unowned self] in
        settingsViewModel.enableAppleCloud = $0
      }
    ),
    .init(
      text: "拷贝应用文件至iCloud",
      type: .button,
      buttonAction: { [unowned self] in
        Task { await copyFileToiCloud() }
      }
    ),
    .init(
      text: "从 iCloud 恢复",
      type: .button,
      buttonAction: { [unowned self] in
        Task { await restoreFromiCloud() }
      }
    ),
    .init(
      text: "正则过滤",
      textValue: { [unowned self] in regexOnCopyFile },
      textHandled: { [unowned self] in
        regexOnCopyFile = $0
      }
    )
  ]

  init(settingsViewModel: SettingsViewModel) {
    self.settingsViewModel = settingsViewModel
  }

  func copyFileToiCloud() async {
    await MainActor.run { syncState = .syncing }
    await ProgressHUD.animate("拷贝中……", interaction: false)
    do {
      let regexList = regexOnCopyFile.split(separator: ",").map { String($0) }
      try FileManager.copySandboxSharedSupportDirectoryToAppleCloud(regexList)
      try FileManager.copySandboxUserDataDirectoryToAppleCloud(regexList)
      UserDefaults.standard.set(Date(), forKey: lastSyncTimeKey)
      UserDefaults.standard.set(true, forKey: lastSyncSuccessKey)
      await ProgressHUD.dismiss()
      await MainActor.run { syncState = .finished(success: true, message: "文件已成功拷贝至 iCloud") }
    } catch {
      Logger.statistics.error("apple cloud copy to iCloud error: \(error)")
      UserDefaults.standard.set(Date(), forKey: lastSyncTimeKey)
      UserDefaults.standard.set(false, forKey: lastSyncSuccessKey)
      await ProgressHUD.dismiss()
      await MainActor.run { syncState = .finished(success: false, message: error.localizedDescription) }
    }
  }
}
  /// 从 iCloud 恢复文件至本地（SharedSupport + UserData）
  func restoreFromiCloud() async {
    await MainActor.run { syncState = .syncing }
    await ProgressHUD.animate("从 iCloud 恢复中……", interaction: false)
    do {
      _ = URL.iCloudDocumentURL
      try FileManager.copyAppleCloudSharedSupportDirectoryToSandbox()
      try FileManager.copyAppleCloudUserDataDirectoryToSandbox()
      UserDefaults.standard.set(Date(), forKey: lastSyncTimeKey)
      UserDefaults.standard.set(true, forKey: lastSyncSuccessKey)
      await ProgressHUD.dismiss()
      await MainActor.run { syncState = .finished(success: true, message: "已从 iCloud 恢复，请执行「重新部署」生效") }
    } catch {
      Logger.statistics.error("apple cloud restore error: \(error)")
      UserDefaults.standard.set(Date(), forKey: lastSyncTimeKey)
      UserDefaults.standard.set(false, forKey: lastSyncSuccessKey)
      await ProgressHUD.dismiss()
      await MainActor.run { syncState = .finished(success: false, message: error.localizedDescription) }
    }
  }

