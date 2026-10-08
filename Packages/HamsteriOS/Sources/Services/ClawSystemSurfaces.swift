import AVFoundation
import BackgroundTasks
import Contacts
import CoreLocation
import CoreSpotlight
import EventKit
import Foundation
import HamsterKit
import Speech
import UserNotifications
import UniformTypeIdentifiers

public enum ClawPermissionStep: String, CaseIterable, Identifiable, Sendable {
  case contacts, calendars, reminders, location, notifications, microphone, speech
  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .contacts: return "通讯录"
    case .calendars: return "日历"
    case .reminders: return "提醒事项"
    case .location: return "位置"
    case .notifications: return "通知"
    case .microphone: return "麦克风"
    case .speech: return "语音识别"
    }
  }
}

public final class ClawPermissionCoordinator: NSObject, CLLocationManagerDelegate {
  public static let shared = ClawPermissionCoordinator()
  private let events = EKEventStore()
  private let location = CLLocationManager()
  private var locationCompletion: (() -> Void)?
  override public init() { super.init(); location.delegate = self }

  public func request(_ step: ClawPermissionStep, completion: @escaping () -> Void) {
    switch step {
    case .contacts: CNContactStore().requestAccess(for: .contacts) { _, _ in DispatchQueue.main.async(execute: completion) }
    case .calendars: events.requestAccess(to: .event) { _, _ in DispatchQueue.main.async(execute: completion) }
    case .reminders: events.requestAccess(to: .reminder) { _, _ in DispatchQueue.main.async(execute: completion) }
    case .location: locationCompletion = completion; location.requestWhenInUseAuthorization()
    case .notifications: UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in DispatchQueue.main.async(execute: completion) }
    case .microphone: AVAudioSession.sharedInstance().requestRecordPermission { _ in DispatchQueue.main.async(execute: completion) }
    case .speech: SFSpeechRecognizer.requestAuthorization { _ in DispatchQueue.main.async(execute: completion) }
    }
  }

  public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard manager.authorizationStatus != .notDetermined else { return }
    let completion = locationCompletion; locationCompletion = nil; completion?()
  }
}

public enum ClawBackgroundWork {
  public static let refreshIdentifier = "dev.fuxiao.app.hamster.claw.refresh"
  public static let maintenanceIdentifier = "dev.fuxiao.app.hamster.claw.maintenance"

  public static func register() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshIdentifier, using: nil) { backgroundTask in
      guard let task = backgroundTask as? BGAppRefreshTask else { backgroundTask.setTaskCompleted(success: false); return }
      scheduleRefresh()
      let work = Task { await AutoInsightService.shared.runIfNeeded(); task.setTaskCompleted(success: true) }
      task.expirationHandler = { work.cancel() }
    }
    BGTaskScheduler.shared.register(forTaskWithIdentifier: maintenanceIdentifier, using: nil) { backgroundTask in
      guard let task = backgroundTask as? BGProcessingTask else { backgroundTask.setTaskCompleted(success: false); return }
      scheduleMaintenance()
      let work = Task {
        SmartFreqService.shared.pruneStalePhrases()
        await SmartFreqService.shared.runIfNeeded()
        task.setTaskCompleted(success: true)
      }
      task.expirationHandler = { work.cancel() }
    }
  }

  public static func scheduleAll() { scheduleRefresh(); scheduleMaintenance() }
  private static func scheduleRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
    request.earliestBeginDate = Date().addingTimeInterval(4 * 60 * 60)
    try? BGTaskScheduler.shared.submit(request)
  }
  private static func scheduleMaintenance() {
    guard SmartFreqMaintenancePolicy().shouldSchedule(isEnabled: SmartFreqService.shared.config.isEnabled, isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled, hasExternalPower: true) else { return }
    let request = BGProcessingTaskRequest(identifier: maintenanceIdentifier)
    request.requiresExternalPower = true
    request.requiresNetworkConnectivity = true
    request.earliestBeginDate = Date().addingTimeInterval(12 * 60 * 60)
    try? BGTaskScheduler.shared.submit(request)
  }
}

public struct ClawSpotlightItem: Sendable {
  public var id: String; public var title: String; public var description: String; public var deepLink: URL
  public init(id: String, title: String, description: String, deepLink: URL) { self.id = id; self.title = title; self.description = description; self.deepLink = deepLink }
}

public enum ClawSpotlightIndexer {
  public static func index(_ items: [ClawSpotlightItem]) {
    CSSearchableIndex.default().indexSearchableItems(items.map { item in
      let attributes = CSSearchableItemAttributeSet(contentType: .content)
      attributes.title = item.title; attributes.contentDescription = item.description; attributes.contentURL = item.deepLink
      return CSSearchableItem(uniqueIdentifier: item.id, domainIdentifier: "claw.memory", attributeSet: attributes)
    })
  }
}

public struct ClawWidgetSnapshot: Codable, Equatable, Sendable {
  public var generatedAt: Date; public var summary: String; public var openTaskCount: Int
  public init(generatedAt: Date = Date(), summary: String, openTaskCount: Int) { self.generatedAt = generatedAt; self.summary = summary; self.openTaskCount = openTaskCount }
}

public enum ClawWidgetSnapshotStore {
  private static let key = "claw_widget_snapshot_v1"
  public static func save(_ snapshot: ClawWidgetSnapshot) { UserDefaults(suiteName: HamsterConstants.appGroupName)?.set(try? JSONEncoder().encode(snapshot), forKey: key) }
  public static func load() -> ClawWidgetSnapshot? {
    guard let data = UserDefaults(suiteName: HamsterConstants.appGroupName)?.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(ClawWidgetSnapshot.self, from: data)
  }
}
