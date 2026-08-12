//
//  ClawTalkTheme.swift
//  ClawTalk keyboard app theme (red / black / white)
//

import UIKit
import ObjectiveC.runtime

/// ClawTalk brand palette & typography, ported from the ClawTalk iOS app.
enum ClawTalkTheme {
  // MARK: - Brand colors (light / dark adaptive)
  static let accentLight = UIColor(red: 183 / 255, green: 56 / 255, blue: 51 / 255, alpha: 1)   // #B73833
  static let accentDark = UIColor(red: 198 / 255, green: 62 / 255, blue: 56 / 255, alpha: 1)     // #C63E38
  static let accentHotLight = UIColor(red: 204 / 255, green: 75 / 255, blue: 69 / 255, alpha: 1) // #CC4B45
  static let accentHotDark = UIColor(red: 232 / 255, green: 92 / 255, blue: 86 / 255, alpha: 1)  // #E85C56
  static let voidLight = UIColor(red: 246 / 255, green: 247 / 255, blue: 249 / 255, alpha: 1)    // #F6F7F9
  static let voidDark = UIColor(red: 11 / 255, green: 12 / 255, blue: 17 / 255, alpha: 1)        // #0B0C11
  static let obsidianLight = UIColor.white                                                       // #FFFFFF
  static let obsidianDark = UIColor(red: 19 / 255, green: 21 / 255, blue: 28 / 255, alpha: 1)    // #13151C

  static var accent: UIColor { adaptive(light: accentLight, dark: accentDark) }
  static var accentHot: UIColor { adaptive(light: accentHotLight, dark: accentHotDark) }
  static var void: UIColor { adaptive(light: voidLight, dark: voidDark) }
  static var obsidian: UIColor { adaptive(light: obsidianLight, dark: obsidianDark) }

  static func adaptive(light: UIColor, dark: UIColor) -> UIColor {
    UIColor { trait in trait.userInterfaceStyle == .dark ? dark : light }
  }

  // MARK: - Fonts
  static let bodyFontName = "Inter-Regular"
  static let titleFontName = "RedHatDisplay-Regular"
  static let monoFontName = "JetBrainsMono-Regular"

  static func bodyFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
    font(name: bodyFontName, size: size, weight: weight) ?? .systemFont(ofSize: size, weight: weight)
  }

  static func titleFont(size: CGFloat, weight: UIFont.Weight = .bold) -> UIFont {
    font(name: titleFontName, size: size, weight: weight) ?? .systemFont(ofSize: size, weight: weight)
  }

  static func monoFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
    font(name: monoFontName, size: size, weight: weight) ?? .systemFont(ofSize: size, weight: weight)
  }

  private static func font(name: String, size: CGFloat, weight: UIFont.Weight) -> UIFont? {
    guard let base = UIFont(name: name, size: size) else { return nil }
    guard weight != .regular else { return base }
    let traits = [UIFontDescriptor.TraitKey.weight: weight]
    let descriptor = base.fontDescriptor.addingAttributes([.traits: traits])
    return UIFont(descriptor: descriptor, size: size)
  }

  // MARK: - Global appearance (red / black / white)
  static func applyGlobalAppearance() {
    let navAppearance = UINavigationBarAppearance()
    navAppearance.configureWithOpaqueBackground()
    navAppearance.backgroundColor = void
    navAppearance.titleTextAttributes = [
      .foregroundColor: UIColor.label,
      .font: titleFont(size: 17, weight: .semibold),
    ]
    navAppearance.largeTitleTextAttributes = [
      .foregroundColor: UIColor.label,
      .font: titleFont(size: 34, weight: .heavy),
    ]
    UINavigationBar.appearance().standardAppearance = navAppearance
    UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
    UINavigationBar.appearance().compactAppearance = navAppearance
    UINavigationBar.appearance().tintColor = accent

    let toolAppearance = UIToolbarAppearance()
    toolAppearance.configureWithOpaqueBackground()
    toolAppearance.backgroundColor = void
    UIToolbar.appearance().standardAppearance = toolAppearance
    UIToolbar.appearance().compactAppearance = toolAppearance
    UIToolbar.appearance().tintColor = accent

    let tabAppearance = UITabBarAppearance()
    tabAppearance.configureWithOpaqueBackground()
    tabAppearance.backgroundColor = void
    UITabBar.appearance().standardAppearance = tabAppearance
    UITabBar.appearance().tintColor = accent
  }
}

// MARK: - Force all system fonts to Inter (hard swap)
extension UIFont {
  private static var clawFontSwizzled = false

  /// Swaps UIFont.systemFont factory methods so the whole app renders with Inter.
  /// Chinese glyphs fall back to PingFang automatically via CoreText.
  static func clawApplyGlobalFont() {
    guard !clawFontSwizzled else { return }
    clawFontSwizzled = true
    let cls: AnyClass = UIFont.self
    let pairs: [(Selector, Selector)] = [
      (#selector(UIFont.systemFont(ofSize:)), #selector(UIFont.clawSystemFont(ofSize:))),
      (#selector(UIFont.systemFont(ofSize:weight:)), #selector(UIFont.clawSystemFont(ofSize:weight:))),
      (#selector(UIFont.boldSystemFont(ofSize:)), #selector(UIFont.clawBoldSystemFont(ofSize:))),
      (#selector(UIFont.italicSystemFont(ofSize:)), #selector(UIFont.clawItalicSystemFont(ofSize:))),
    ]
    for (original, swizzled) in pairs {
      guard
        let m1 = class_getClassMethod(cls, original),
        let m2 = class_getClassMethod(cls, swizzled)
      else { continue }
      method_exchangeImplementations(m1, m2)
    }
  }

  @objc static func clawSystemFont(ofSize size: CGFloat) -> UIFont {
    ClawTalkTheme.bodyFont(size: size) 
  }

  @objc static func clawSystemFont(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
    ClawTalkTheme.bodyFont(size: size, weight: weight)
  }

  @objc static func clawBoldSystemFont(ofSize size: CGFloat) -> UIFont {
    ClawTalkTheme.bodyFont(size: size, weight: .bold)
  }

  @objc static func clawItalicSystemFont(ofSize size: CGFloat) -> UIFont {
    let base = ClawTalkTheme.bodyFont(size: size)
    let descriptor = base.fontDescriptor.withSymbolicTraits(.traitItalic) ?? base.fontDescriptor
    return UIFont(descriptor: descriptor, size: size)
  }
}
