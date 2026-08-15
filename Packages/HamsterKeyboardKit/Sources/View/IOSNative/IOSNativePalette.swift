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
    }
  }

  static func current(dark: Bool) -> IOSNativePalette {
    IOSNativePalette(dark: dark)
  }
}
