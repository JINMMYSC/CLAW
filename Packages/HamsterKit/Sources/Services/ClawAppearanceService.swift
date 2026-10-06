import Foundation
import UIKit

/// 主程序与键盘扩展共享的外观偏好（系统 / 浅色 / 深色）。
///
/// 存在 App Group 里，两个进程读同一个键：主程序用它设置窗口的
/// `overrideUserInterfaceStyle`，键盘扩展在每次同步上下文时套用同一份值，
/// 这样键盘配色能和主程序保持一致。
public enum ClawAppearanceStyle: String, CaseIterable {
  case system
  case light
  case dark

  public var displayName: String {
    switch self {
    case .system: return "系统"
    case .light: return "浅色"
    case .dark: return "深色"
    }
  }

  public var userInterfaceStyle: UIUserInterfaceStyle {
    switch self {
    case .system: return .unspecified
    case .light: return .light
    case .dark: return .dark
    }
  }
}

public enum ClawAppearanceService {
  public static let key = "claw_appearance_style_v1"

  private static var defaults: UserDefaults? {
    UserDefaults(suiteName: HamsterConstants.appGroupName)
  }

  /// 当前外观偏好，默认跟随系统。
  public static var style: ClawAppearanceStyle {
    get {
      guard let raw = defaults?.string(forKey: key),
            let value = ClawAppearanceStyle(rawValue: raw) else { return .system }
      return value
    }
    set {
      defaults?.set(newValue.rawValue, forKey: key)
    }
  }
}
