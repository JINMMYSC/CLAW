import Foundation
import CoreFoundation

/// ClawTalk 隐私开关服务
/// 控制是否采集输入记录和剪贴板，状态持久化存储在 App Group UserDefaults
/// 默认关闭：只有明确的布尔授权才允许采集。

public extension Notification.Name {
  /// 隐私采集状态变化通知（键盘眼睛按钮等 UI 刷新用）
  static let clawPrivacyDidChange = Notification.Name("clawTalk_privacy_did_change")
}

public final class ClawTalkPrivacyService {
  public static let shared = ClawTalkPrivacyService()

  private let defaults: UserDefaults?
  private let key = "clawTalk_collection_enabled"

  public init(defaults: UserDefaults? = UserDefaults(suiteName: HamsterConstants.appGroupName)) {
    self.defaults = defaults
  }

  /// NSNumber bridges numeric 0/1 to Swift Bool. Verify the CoreFoundation
  /// boolean type instead, so malformed integers or strings cannot grant consent.
  private static func explicitlyConsented(_ raw: Any?) -> Bool {
    guard let value = raw as? NSNumber,
          CFGetTypeID(value) == CFBooleanGetTypeID() else {
      return false
    }
    return value.boolValue
  }

  /// 迁移旧 key（guru_collection_enabled → clawTalk_collection_enabled），一次性。
  /// A legacy numeric or malformed value must never become opt-in.
  private func migrateLegacyKeyIfNeeded() {
    guard let defaults else { return }
    let legacyKey = "guru_collection_enabled"
    guard defaults.object(forKey: key) == nil,
          let legacy = defaults.object(forKey: legacyKey) else { return }
    defaults.set(Self.explicitlyConsented(legacy), forKey: key)
    defaults.removeObject(forKey: legacyKey)
  }

  /// 是否允许采集（true = 用户明确开启，false = 隐私模式暂停采集）
  public var isCollectionEnabled: Bool {
    get {
      migrateLegacyKeyIfNeeded()
      return Self.explicitlyConsented(defaults?.object(forKey: key))
    }
    set {
      defaults?.set(newValue, forKey: key)
    }
  }

  /// 切换采集状态，返回切换后的新值
  @discardableResult
  public func toggle() -> Bool {
    // A keyboard extension may be denied access to its App Group container.
    // Never report success or notify observers when the write cannot persist.
    guard let defaults else { return false }
    let previous = isCollectionEnabled
    defaults.set(!previous, forKey: key)
    let persisted = isCollectionEnabled
    if persisted != previous {
      NotificationCenter.default.post(name: .clawPrivacyDidChange, object: nil)
    }
    return persisted
  }
}
