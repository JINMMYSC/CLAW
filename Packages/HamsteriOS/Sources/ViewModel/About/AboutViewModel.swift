//
//  File.swift
//
//
//  Created by morse on 2023/7/7.
//

import Combine
import HamsterKeyboardKit
import HamsterKit
import ProgressHUD
import UIKit

public class AboutViewModel: ObservableObject {
  private let rimeContext: RimeContext

  init(rimeContext: RimeContext) {
    self.rimeContext = rimeContext
  }

  @Published
  public var displayOpenSourceView = false

  private let restUISettingsSubject = PassthroughSubject<() -> Void, Never>()
  public var restUISettingsPublished: AnyPublisher<() -> Void, Never> {
    restUISettingsSubject.eraseToAnyPublisher()
  }

  private let exportConfigurationSubject = PassthroughSubject<URL, Never>()
  public var exportConfigurationPublished: AnyPublisher<URL, Never> {
    exportConfigurationSubject.eraseToAnyPublisher()
  }

  private let resetRequestSubject = PassthroughSubject<ClawResetMode, Never>()
  var resetRequestPublished: AnyPublisher<ClawResetMode, Never> {
    resetRequestSubject.eraseToAnyPublisher()
  }

  private let resetCompletedSubject = PassthroughSubject<ClawResetReport, Never>()
  var resetCompletedPublished: AnyPublisher<ClawResetReport, Never> {
    resetCompletedSubject.eraseToAnyPublisher()
  }

  lazy var settingItems: [SettingSectionModel] = [
    .init(items: [
      .init(text: "RIME版本", secondaryText: AppInfo.rimeVersion, type: .settings, buttonAction: {
        UIPasteboard.general.string = AppInfo.rimeVersion
        await ProgressHUD.success("复制成功", interaction: false, delay: 1.5)
      }),
    ]),
    .init(
      title: "数据与重置",
      footer: "重置操作不可撤销。API Key 和输入方案文件始终保留。",
      items: [
        .init(text: "重置输入法学习", type: .settings, buttonAction: { [weak self] in
          self?.resetRequestSubject.send(.inputLearningOnly)
        }),
        .init(text: "重置 App", textTintColor: .systemRed, type: .settings, buttonAction: { [weak self] in
          self?.resetRequestSubject.send(.full)
        }),
      ]
    ),
  ]

  func performReset(_ mode: ClawResetMode) {
    let service = ClawResetService(actions: .init(
      stopRime: { [rimeContext] in rimeContext.shutdown() },
      clearApplicationData: {
        try ClawMemoryStore.shared.clearAllUserData()
        HeartTargetService.shared.deleteAllProfiles()
        ClawChatService.shared.clearAllConversations()
        ClawTalkDataService.shared.deleteAllEntries()
        ClipboardMonitorService.shared.deleteAllEntries()
        ClawPrivacyVaultService.shared.clearProtectedMemories()
        UserDefaults(suiteName: HamsterConstants.appGroupName)?.removeObject(forKey: "ai_prompts")
      },
      clearInputLearning: {
        try ClawResetService.removeInputLearningFiles(in: [
          FileManager.sandboxUserDataDirectory,
          FileManager.appGroupUserDataDirectoryURL,
        ])
        SmartFreqService.shared.resetAllRules()
      },
      resetConfiguration: {
        HamsterConfigurationStore.shared.reset()
        let defaults = UserDefaults(suiteName: HamsterConstants.appGroupName)
        defaults?.removeObject(forKey: ClawAppearanceService.key)
        defaults?.removeObject(forKey: ClawVoiceSettings.voiceKey)
        defaults?.removeObject(forKey: ClawVoiceSettings.rateKey)
        defaults?.removeObject(forKey: ClawVoiceSettings.pitchKey)
      },
      redeployRime: { [rimeContext] in
        var configuration = HamsterConfigurationStore.shared.configuration
        try rimeContext.deployment(configuration: &configuration, forceFullCheck: true)
        HamsterConfigurationStore.shared.configuration = configuration
      }
    ))
    resetCompletedSubject.send(service.perform(mode))
  }
}
