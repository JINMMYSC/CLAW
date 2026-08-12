//
//  ColorSchemaViewModel.swift
//
//
//  Created by morse on 14/7/2023.
//

import Combine
import HamsterKeyboardKit
import UIKit

/// 键盘配色 ViewModel：3 选 1（系统默认 / 日光熔金 / 昼熔月汐）
class KeyboardColorViewModel {
  public var enableColorSchema: Bool {
    get {
      HamsterConfigurationStore.shared.configuration.keyboard?.enableColorSchema ?? false
    }
    set {
      HamsterConfigurationStore.shared.configuration.keyboard?.enableColorSchema = newValue
      HamsterConfigurationStore.shared.applicationConfiguration.keyboard?.enableColorSchema = newValue
    }
  }

  public var useColorSchemaForLight: String {
    get {
      HamsterConfigurationStore.shared.configuration.keyboard?.useColorSchemaForLight ?? ""
    }
    set {
      HamsterConfigurationStore.shared.configuration.keyboard?.useColorSchemaForLight = newValue
      HamsterConfigurationStore.shared.applicationConfiguration.keyboard?.useColorSchemaForLight = newValue
    }
  }

  public var useColorSchemaForDark: String {
    get {
      HamsterConfigurationStore.shared.configuration.keyboard?.useColorSchemaForDark ?? ""
    }
    set {
      HamsterConfigurationStore.shared.configuration.keyboard?.useColorSchemaForDark = newValue
      HamsterConfigurationStore.shared.applicationConfiguration.keyboard?.useColorSchemaForDark = newValue
    }
  }

  /// 日光熔金（浅色：solarized_light）
  static let lightSchemaName = "solarized_light"
  /// 昼熔月汐（深色：solarized_dark）
  static let darkSchemaName = "solarized_dark"

  /// 当前选项：0=系统默认, 1=日光熔金, 2=昼熔月汐
  public var selectedIndex: Int {
    get {
      guard enableColorSchema else { return 0 }
      let light = useColorSchemaForLight
      let dark = useColorSchemaForDark
      if light == Self.darkSchemaName || (light.isEmpty && dark == Self.darkSchemaName) { return 2 }
      if light == Self.lightSchemaName || (light.isEmpty && dark == Self.lightSchemaName) { return 1 }
      return 0
    }
    set {
      switch newValue {
      case 0:
        // 系统默认：关闭配色
        enableColorSchema = false
      case 1:
        enableColorSchema = true
        useColorSchemaForLight = Self.lightSchemaName
        useColorSchemaForDark = Self.lightSchemaName
      case 2:
        enableColorSchema = true
        useColorSchemaForLight = Self.darkSchemaName
        useColorSchemaForDark = Self.darkSchemaName
      default:
        break
      }
    }
  }
}
