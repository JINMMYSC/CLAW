//
//  IOSNativePalette.swift
//
//  System-aligned palette for ClawTalk's existing "iOS 原生布局".
//  Light and dark appearances are calibrated independently; pressed states are explicit.
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

/// Visual tokens for the existing native-layout mode.
/// Every state is explicit so light/dark can be calibrated independently from device screenshots.
struct IOSNativePalette {
  let board: UIColor
  let char: UIColor
  let charPressed: UIColor
  let funcGray: UIColor
  let funcPressed: UIColor
  let lightGray: UIColor
  let lightGrayPressed: UIColor
  let sendBlue: UIColor
  let sendPressed: UIColor
  let textDark: UIColor
  let textWhite: UIColor
  let secondaryText: UIColor
  let separator: UIColor
  let candidateSelected: UIColor
  let toolbarControl: UIColor
  let toolbarControlSelected: UIColor
  let keyShadow: UIColor
  let keyShadowOpacity: Float

  init(dark: Bool) {
    if dark {
      board = iosRGB(0x1C1C1E)
      char = iosRGB(0x636366)
      charPressed = iosRGB(0x7A7A7F)
      funcGray = iosRGB(0x3A3A3C)
      funcPressed = iosRGB(0x545458)
      lightGray = iosRGB(0x48484A)
      lightGrayPressed = iosRGB(0x5A5A5E)
      sendBlue = iosRGB(0x0A84FF)
      sendPressed = iosRGB(0x006EDC)
      textDark = UIColor.white
      textWhite = UIColor.white
      secondaryText = iosRGB(0xAEAEB2)
      separator = iosRGB(0x38383A)
      candidateSelected = iosRGB(0x2C2C2E)
      toolbarControl = iosRGB(0x2C2C2E)
      toolbarControlSelected = iosRGB(0x48484A)
      // IOSNativeButton restores the legacy 0.32 layer opacity after a press.
      // Keep that layer opacity stable and encode the calibrated dark/light
      // difference in the shadow color alpha so the shadow does not jump.
      keyShadow = UIColor.black.withAlphaComponent(0.6875)
      keyShadowOpacity = 0.32
    } else {
      board = iosRGB(0xD1D4DA)
      char = UIColor.white
      charPressed = iosRGB(0xB7BDC6)
      funcGray = iosRGB(0xADB3BC)
      funcPressed = iosRGB(0x9299A4)
      lightGray = iosRGB(0xE4E7EB)
      lightGrayPressed = iosRGB(0xC9CED5)
      sendBlue = iosRGB(0x007AFF)
      sendPressed = iosRGB(0x0062CC)
      textDark = UIColor.black
      textWhite = UIColor.white
      secondaryText = iosRGB(0x6C6C70)
      separator = iosRGB(0xB8BDC5)
      candidateSelected = UIColor.white
      toolbarControl = iosRGB(0xE4E7EB)
      toolbarControlSelected = UIColor.white
      keyShadow = iosRGB(0x7A7F87).withAlphaComponent(0.875)
      keyShadowOpacity = 0.32
    }
  }

  static func current(dark: Bool) -> IOSNativePalette {
    IOSNativePalette(dark: dark)
  }
}
