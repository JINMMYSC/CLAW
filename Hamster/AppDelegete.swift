//
//  AppDelegete.swift
//  Hamster
//
//  Created by morse on 2023/6/5.
//

import UIKit
import UserNotifications
import HamsteriOS
#if DEBUG
import ObjectiveC
import Speech
#endif

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    #if DEBUG
    ClawSpeechAuthorizationSmokeTrace.installIfRequested()
    #endif
    UNUserNotificationCenter.current().delegate = self
    // ClawTalk theme: system fonts + red/black/white appearance
    ClawTalkTheme.applyGlobalAppearance()
    ClawBackgroundWork.register()
    ClawBackgroundWork.scheduleAll()
    return true
  }

  // MARK: UISceneSession Lifecycle

  func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
  }

  func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
  }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
  /// App 在前台时也显示通知 banner 并写入通知中心
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound, .list])
  }
}

#if DEBUG
/// Simulator-only diagnostic. Installed exclusively by Startup Smoke's launch
/// argument; Release builds and ordinary Debug launches never swizzle Speech.
/// This captures *all* Speech authorization requests, not only our voice wrapper.
private enum ClawSpeechAuthorizationSmokeTrace {
  static func installIfRequested() {
    guard ProcessInfo.processInfo.arguments.contains("-clawSmokeTraceSpeechAuthorization") else { return }
    guard let original = class_getClassMethod(
      SFSpeechRecognizer.self, #selector(SFSpeechRecognizer.requestAuthorization(_:))
    ), let traced = class_getClassMethod(
      SFSpeechRecognizer.self, #selector(SFSpeechRecognizer.clawSmokeTracedRequestAuthorization(_:))
    ) else {
      FileHandle.standardError.write(Data("[clawSpeechHook] installation unavailable\n".utf8))
      return
    }
    method_exchangeImplementations(original, traced)
    FileHandle.standardError.write(Data("[clawSpeechHook] installed\n".utf8))
  }
}

extension SFSpeechRecognizer {
  @objc class func clawSmokeTracedRequestAuthorization(
    _ handler: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void
  ) {
    // No audio, transcription, personal data or authorization callback content.
    let stack = Thread.callStackSymbols.prefix(20).joined(separator: " | ")
    FileHandle.standardError.write(Data("[clawSpeechHook] requestAuthorization stack=\(stack)\n".utf8))
    // After the exchange this selector points to Apple's original implementation.
    clawSmokeTracedRequestAuthorization(handler)
  }
}
#endif
