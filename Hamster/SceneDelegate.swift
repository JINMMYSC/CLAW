//
//  SceneDelegate.swift
//  Hamster
//
//  Created by morse on 2023/6/5.
//

import HamsteriOS
import HamsterKit
import CoreSpotlight
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate, UISceneDelegate {
  var window: UIWindow?
  private var openedVoiceDeepLinkInCurrentActivation = false

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = (scene as? UIWindowScene) else { return }

    if window == nil {
#if DEBUG
      // Startup smoke regression hook: exercise the legacy v1 migration path.
      if ProcessInfo.processInfo.arguments.contains("-clawTalkForceV1Migration") {
        UserDefaults.hamster._setFirstRunningForV1(false)
      }
#endif
      let window = UIWindow(windowScene: windowScene)
      window.rootViewController = HamsterAppDependencyContainer.shared.makeRootController()
      window.tintColor = ClawTalkTheme.accent
      // 主程序外观偏好（系统 / 浅色 / 深色），与键盘扩展共用同一份 App Group 值。
      window.overrideUserInterfaceStyle = ClawAppearanceService.style.userInterfaceStyle
      self.window = window
      window.makeKeyAndVisible()
#if DEBUG
      let args = ProcessInfo.processInfo.arguments
      if let index = args.firstIndex(of: "-clawComposerScreenshot"), index + 1 < args.count {
        if args[index + 1] == "dark" { window.overrideUserInterfaceStyle = .dark }
        // Drive the real assistant root, rather than a separate mock screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          HamsterAppDependencyContainer.shared.mainViewModel.navigation(.clawTalk)
        }
      }
#endif
      // ClawTalk 品牌启动层：与 LaunchScreen 视觉一致，1.5s 淡出
      SplashOverlayView().presentAndDismiss(in: window)
    }

    /// 外部导入 zip 文件
    if let url = connectionOptions.urlContexts.first?.url {
      if url.pathExtension.lowercased() == "zip" {
        Task {
          HamsterAppDependencyContainer.shared.mainViewModel.navigationToInputSchema()
          await HamsterAppDependencyContainer.shared.inputSchemaViewModel.importZipFile(fileURL: url)
        }
        return
      }

      // url.query(): 获取 `URL` 查询参数
      // url.lastPathComponent 获取 `URL` 中 `/a/b` 中最后一个 b
      if url.query?.contains("voiceInput=1") == true {
        openedVoiceDeepLinkInCurrentActivation = true
        UserDefaults(suiteName: HamsterConstants.appGroupName)?
          .set(true, forKey: HamsterConstants.clawVoiceInputLaunchKey)
        NotificationCenter.default.post(name: .clawVoiceInputRequested, object: nil)
      }
      if url.query?.contains("voiceCall=1") == true {
        UserDefaults(suiteName: HamsterConstants.appGroupName)?
          .set(true, forKey: HamsterConstants.clawVoiceCallLaunchKey)
        NotificationCenter.default.post(name: .clawVoiceCallRequested, object: nil)
      }
      let components = url.lastPathComponent
      if let subView = SettingsSubView(rawValue: components) {
        HamsterAppDependencyContainer.shared.mainViewModel.navigation(subView)
      }
    }

    // 通过快捷方式打开
    if let shortItem = connectionOptions.shortcutItem,
       let shortItemType = ShortcutItemType(rawValue: shortItem.localizedTitle),
       shortItemType != .none
    {
      HamsterAppDependencyContainer.shared.mainViewModel.navigationToRIME()
      HamsterAppDependencyContainer.shared.mainViewModel.execShortcutCommand(shortItemType)
    }
  }

  // 通过URL打开App
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    guard let windowScene = (scene as? UIWindowScene) else { return }

    if window == nil {
      let window = UIWindow(windowScene: windowScene)
      window.rootViewController = HamsterAppDependencyContainer.shared.makeRootController()
      window.tintColor = ClawTalkTheme.accent
      self.window = window
      window.makeKeyAndVisible()
    }

    /// 外部导入 zip 文件
    if let url = URLContexts.first?.url {
      if url.pathExtension.lowercased() == "zip" {
        Task {
          HamsterAppDependencyContainer.shared.mainViewModel.navigationToInputSchema()
          await HamsterAppDependencyContainer.shared.inputSchemaViewModel.importZipFile(fileURL: url)
        }
        return
      }

      // url.query(): 获取 `URL` 查询参数
      // url.lastPathComponent 获取 `URL` 中 `/a/b` 中最后一个 b
      if url.query?.contains("voiceInput=1") == true {
        openedVoiceDeepLinkInCurrentActivation = true
        UserDefaults(suiteName: HamsterConstants.appGroupName)?
          .set(true, forKey: HamsterConstants.clawVoiceInputLaunchKey)
        NotificationCenter.default.post(name: .clawVoiceInputRequested, object: nil)
      }
      if url.query?.contains("voiceCall=1") == true {
        UserDefaults(suiteName: HamsterConstants.appGroupName)?
          .set(true, forKey: HamsterConstants.clawVoiceCallLaunchKey)
        NotificationCenter.default.post(name: .clawVoiceCallRequested, object: nil)
      }
      let components = url.lastPathComponent
      if let subView = SettingsSubView(rawValue: components) {
        HamsterAppDependencyContainer.shared.mainViewModel.navigation(subView)
      }
    }
  }

  func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    guard userActivity.activityType == CSSearchableItemActionType,
          userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String != nil else { return }
    HamsterAppDependencyContainer.shared.mainViewModel.navigation(.clawTalk)
  }

  /// 程序已启动下，通过 quick action 打开
  func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
    guard let window = window else { return }
    guard let rootController = window.rootViewController else { return }
    guard let mainViewController = rootController as? MainViewController else { return }

    mainViewController.navigationController?.popViewController(animated: false)

    // 通过快捷方式打开
    if let shortItemType = ShortcutItemType(rawValue: shortcutItem.localizedTitle), shortItemType != .none {
      HamsterAppDependencyContainer.shared.mainViewModel.navigationToRIME()
      HamsterAppDependencyContainer.shared.mainViewModel.execShortcutCommand(shortItemType)
    }
  }

  func sceneDidDisconnect(_ scene: UIScene) {
    // Called as the scene is being released by the system.
    // This occurs shortly after the scene enters the background, or when its session is discarded.
    // Release any resources associated with this scene that can be re-created the next time the scene connects.
    // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
    // Called when the scene has moved from an inactive state to an active state.
    // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    if !openedVoiceDeepLinkInCurrentActivation,
       ClawVoiceDictationHandoff.shared.snapshot.state == .pending {
      DispatchQueue.main.async {
        NotificationCenter.default.post(name: .clawVoiceInputRequested, object: nil)
        HamsterAppDependencyContainer.shared.mainViewModel.navigation(.clawTalk)
      }
    }
  }

  /// 应用注册 quick action
  func sceneWillResignActive(_ scene: UIScene) {
    openedVoiceDeepLinkInCurrentActivation = false
    let application = UIApplication.shared
    let rimeDeploy = UIApplicationShortcutItem(type: "RIME", localizedTitle: ShortcutItemType.rimeDeploy.rawValue)
    let rimeSync = UIApplicationShortcutItem(type: "RIME", localizedTitle: ShortcutItemType.rimeSync.rawValue)
//    let rimeReset = UIApplicationShortcutItem(type: "RIME", localizedTitle: ShortcutItemType.rimeReset.rawValue)
    application.shortcutItems = [rimeDeploy, rimeSync]
  }

  func sceneWillEnterForeground(_ scene: UIScene) {
    // Called as the scene transitions from the background to the foreground.
    // Use this method to undo the changes made on entering the background.
  }

  func sceneDidEnterBackground(_ scene: UIScene) {
    // Called as the scene transitions from the foreground to the background.
    ClawBackgroundWork.scheduleAll()
  }
}
