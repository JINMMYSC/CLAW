//
//  IOSNativePalette.swift
//
//  ClawTalk「IOS 原生布局」P 图配色（浅/深两套，跟随系统深浅色）
//
//  浅色：board #D1D4D9 / char 白 / charPressed #E8ECF0 / funcGray #AAB0BA / sendBlue #007AFF
//  深色：board #1C1C1E / char #636366 / charPressed #48484A / funcGray #3A3A3C / sendBlue #0A84FF
//

import UIKit

func iosRGB(_ hex: UInt32) -> UIColor {
  UIColor(
    red: CGFloat((hex >> 16) & 0xFF) / 255,
    green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255,
    alpha: 1
  )
}

func iosDarker(_ color: UIColor, by factor: CGFloat = 0.85) -> UIColor {
  var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
  guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return color }
  return UIColor(red: r * factor, green: g * factor, blue: b * factor, alpha: a)
}

/// 按 P 图硬编码的 iOS 原生配色（浅/深双套，随系统切换）
struct IOSNativePalette {
  let board: UIColor
  let char: UIColor
  let charPressed: UIColor
  let funcGray: UIColor
  let lightGray: UIColor
  let sendBlue: UIColor
  let textDark: UIColor
  let textWhite: UIColor
  let separator: UIColor
  let candidateBackground: UIColor
  let windowCornerRadius: CGFloat
  let keyCornerRadius: CGFloat
  let candidateCornerRadius: CGFloat
  let edgeHighlightEnabled: Bool
  let edgeHighlightIntensity: CGFloat
  let isWeTypeEnhanced: Bool

  init(dark: Bool) {
    if dark {
      board = iosRGB(0x1C1C1E)
      char = iosRGB(0x636366)
      charPressed = iosRGB(0x48484A)
      funcGray = iosRGB(0x3A3A3C)
      lightGray = iosRGB(0x48484A)
      sendBlue = iosRGB(0x0A84FF)
      textDark = UIColor.white
      textWhite = UIColor.white
      separator = iosRGB(0x48484A)
      candidateBackground = iosRGB(0x2C2C2E)
    } else {
      board = iosRGB(0xD1D4D9)
      char = UIColor.white
      charPressed = iosRGB(0xE8ECF0)
      funcGray = iosRGB(0xAAB0BA)
      lightGray = iosRGB(0xE8ECF0)
      sendBlue = iosRGB(0x007AFF)
      textDark = UIColor.black
      textWhite = UIColor.white
      separator = iosRGB(0xC7C7CC)
      candidateBackground = .white
    }
    windowCornerRadius = 0
    keyCornerRadius = 8
    candidateCornerRadius = 5
    edgeHighlightEnabled = false
    edgeHighlightIntensity = 0
    isWeTypeEnhanced = false
  }

  static func current(dark: Bool) -> IOSNativePalette {
    let keyboard = HamsterConfigurationStore.shared.configuration.keyboard
    let schemaName = dark
      ? (keyboard?.useColorSchemaForDark ?? "")
      : (keyboard?.useColorSchemaForLight ?? "")

    if keyboard?.enableColorSchema == true,
       ClawTalkThemePresets.theme(forSchemaName: schemaName) == .weTypeEnhanced,
       let preset = ClawTalkThemePresets.preset(for: .weTypeEnhanced).weTypeStyle
    {
      let colors = ClawTalkThemePresets.preset(for: .weTypeEnhanced)
        .panelColors(userInterfaceStyle: dark ? .dark : .light)
      return IOSNativePalette(
        board: colors.keyboardBackground,
        char: colors.keycapBase,
        charPressed: colors.keycapPressed,
        funcGray: colors.keycapPressed,
        lightGray: colors.keycapPressed,
        sendBlue: colors.accent,
        textDark: colors.keycapText,
        textWhite: colors.accentForeground,
        separator: colors.accent.withAlphaComponent(0.18),
        candidateBackground: colors.accent.withAlphaComponent(preset.candidateBackgroundOpacity),
        windowCornerRadius: preset.windowCornerRadius,
        keyCornerRadius: preset.keyCornerRadius,
        candidateCornerRadius: preset.candidateCornerRadius,
        edgeHighlightEnabled: preset.edgeHighlightEnabled,
        edgeHighlightIntensity: preset.edgeHighlightIntensity,
        isWeTypeEnhanced: true
      )
    }

    return IOSNativePalette(dark: dark)
  }

  private init(
    board: UIColor,
    char: UIColor,
    charPressed: UIColor,
    funcGray: UIColor,
    lightGray: UIColor,
    sendBlue: UIColor,
    textDark: UIColor,
    textWhite: UIColor,
    separator: UIColor,
    candidateBackground: UIColor,
    windowCornerRadius: CGFloat,
    keyCornerRadius: CGFloat,
    candidateCornerRadius: CGFloat,
    edgeHighlightEnabled: Bool,
    edgeHighlightIntensity: CGFloat,
    isWeTypeEnhanced: Bool
  ) {
    self.board = board
    self.char = char
    self.charPressed = charPressed
    self.funcGray = funcGray
    self.lightGray = lightGray
    self.sendBlue = sendBlue
    self.textDark = textDark
    self.textWhite = textWhite
    self.separator = separator
    self.candidateBackground = candidateBackground
    self.windowCornerRadius = windowCornerRadius
    self.keyCornerRadius = keyCornerRadius
    self.candidateCornerRadius = candidateCornerRadius
    self.edgeHighlightEnabled = edgeHighlightEnabled
    self.edgeHighlightIntensity = edgeHighlightIntensity
    self.isWeTypeEnhanced = isWeTypeEnhanced
  }
}
