from pathlib import Path


def read(path: str) -> str:
    return Path(path).read_text()


def write(path: str, text: str) -> None:
    Path(path).write_text(text)


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one match, found {count}: {old[:100]!r}")
    write(path, text.replace(old, new, 1))


def replace_all(path: str, old: str, new: str, minimum: int = 1) -> None:
    text = read(path)
    count = text.count(old)
    if count < minimum:
        raise SystemExit(f"{path}: expected >= {minimum} matches, found {count}: {old[:100]!r}")
    write(path, text.replace(old, new))


palette_path = "Packages/HamsterKeyboardKit/Sources/View/IOSNative/IOSNativePalette.swift"
write(
    palette_path,
    '''//
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
      keyShadow = UIColor.black
      keyShadowOpacity = 0.22
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
      keyShadow = iosRGB(0x7A7F87)
      keyShadowOpacity = 0.28
    }
  }

  static func current(dark: Bool) -> IOSNativePalette {
    IOSNativePalette(dark: dark)
  }
}
''',
)

metrics_path = "Packages/HamsterKeyboardKit/Sources/View/IOSNative/IOSNativeSystemMetrics.swift"
write(
    metrics_path,
    '''//
//  IOSNativeSystemMetrics.swift
//
//  Central calibration surface for the existing iOS-native keyboard mode.
//  Geometry may expand with the device, while typography and symbol point sizes stay stable.
//

import CoreGraphics

struct IOSNativeSystemMetrics {
  let viewWidth: CGFloat
  let safeAreaBottom: CGFloat

  private var horizontalEdge: CGFloat {
    if viewWidth >= 428 { return 4 }
    if viewWidth >= 390 { return 3.5 }
    return 3
  }

  private var referenceContentWidth: CGFloat {
    IOSNativeDesign.width - 2 * IOSNativeDesign.paddingH
  }

  private var contentScale: CGFloat {
    guard referenceContentWidth > 0 else { return 1 }
    return max(0.85, (viewWidth - 2 * horizontalEdge) / referenceContentWidth)
  }

  func x(_ designX: CGFloat) -> CGFloat {
    horizontalEdge + (designX - IOSNativeDesign.paddingH) * contentScale
  }

  func width(_ designWidth: CGFloat) -> CGFloat {
    designWidth * contentScale
  }

  /// UIKit normally owns the full Home Indicator inset; native mode only keeps a small visual breathing space.
  var bottomKeyInset: CGFloat {
    safeAreaBottom > 0 ? 4 : 0
  }

  var cornerRadius: CGFloat {
    viewWidth >= 428 ? 6 : 5.5
  }

  /// System keyboard typography is point based rather than proportional to screen width.
  func fontSize(_ base: CGFloat) -> CGFloat {
    base
  }
}
''',
)

layout = "Packages/HamsterKeyboardKit/Sources/View/IOSNative/IOSNativeLayout.swift"
replace_once(layout, "public static let paddingV: CGFloat = 6", "public static let paddingV: CGFloat = 5.5")
replace_once(layout, "panel.geometry == .nineGrid ? 48 : 42", "panel.geometry == .nineGrid ? 48 : 43")
replace_once(layout, "panel.geometry == .nineGrid ? 7 : 11", "panel.geometry == .nineGrid ? 7 : 10")

appearance = "Packages/HamsterKeyboardKit/Sources/KeyboardKit/Appearance/StandardKeyboardAppearance.swift"
replace_once(
    appearance,
    '''  open var backgroundStyle: KeyboardBackgroundStyle {
    var style = KeyboardBackgroundStyle.standard
    style.backgroundColor = ClawPanelPalette.keyboardBackground

    // 中文九宫格：跟随主题（默认=苹果原生）键盘底色
    if keyboardContext.keyboardType.isChineseNineGrid {
      style.backgroundColor = ClawPanelPalette.keyboardBackground
    }

    // 开启键盘配色
    if let hamsterColor = hamsterColor() {
      style.backgroundColor = hamsterColor.backColor
    }

    return style
  }''',
    '''  open var backgroundStyle: KeyboardBackgroundStyle {
    var style = KeyboardBackgroundStyle.standard

    // Existing “iOS 原生布局” stays system-like even when a custom Hamster theme is enabled.
    if keyboardContext.useIOSNativeLayout {
      style.backgroundColor = IOSNativePalette.current(dark: keyboardContext.hasDarkColorScheme).board
      return style
    }

    style.backgroundColor = ClawPanelPalette.keyboardBackground
    if keyboardContext.keyboardType.isChineseNineGrid {
      style.backgroundColor = ClawPanelPalette.keyboardBackground
    }
    if let hamsterColor = hamsterColor() {
      style.backgroundColor = hamsterColor.backColor
    }
    return style
  }''',
)
replace_once(
    appearance,
    '''    if keyboardContext.useIOSNativeLayout {
      let dark = keyboardContext.hasDarkColorScheme
      // 候选栏底色统一取键盘按钮间隙色（palette.board），与键盘板完全同色
      let boardColor = IOSNativePalette.current(dark: dark).board
      let textColor = dark ? UIColor.white : UIColor(red: 17/255, green: 17/255, blue: 17/255, alpha: 1)
      let grayColor = UIColor(red: 142/255, green: 142/255, blue: 147/255, alpha: 1)
      let preferredBackground = dark
        ? UIColor(red: 44/255, green: 44/255, blue: 46/255, alpha: 1)
        : UIColor.white
      return CandidateBarStyle(
        phoneticTextColor: textColor,
        phoneticTextFont: UIFont.systemFont(ofSize: 15),
        preferredCandidateTextColor: textColor,
        preferredCandidateCommentTextColor: grayColor,
        preferredCandidateBackgroundColor: preferredBackground,
        preferredCandidateLabelColor: grayColor,
        candidateTextColor: textColor,
        candidateCommentTextColor: grayColor,
        candidateLabelColor: grayColor,
        candidateLabelFont: UIFont.systemFont(ofSize: 11),
        candidateTextFont: UIFont.systemFont(ofSize: 17),
        candidateCommentFont: UIFont.systemFont(ofSize: 12),
        toolbarButtonFrontColor: textColor,
        toolbarButtonBackgroundColor: .clear,
        toolbarButtonPressedBackgroundColor: boardColor
      )
    }''',
    '''    if keyboardContext.useIOSNativeLayout {
      let palette = IOSNativePalette.current(dark: keyboardContext.hasDarkColorScheme)
      return CandidateBarStyle(
        phoneticTextColor: palette.secondaryText,
        phoneticTextFont: UIFont.systemFont(ofSize: 13, weight: .regular),
        preferredCandidateTextColor: palette.textDark,
        preferredCandidateCommentTextColor: palette.secondaryText,
        preferredCandidateBackgroundColor: palette.candidateSelected,
        preferredCandidateLabelColor: palette.secondaryText,
        candidateTextColor: palette.textDark,
        candidateCommentTextColor: palette.secondaryText,
        candidateLabelColor: palette.secondaryText,
        candidateLabelFont: UIFont.systemFont(ofSize: 10, weight: .regular),
        candidateTextFont: UIFont.systemFont(ofSize: 18, weight: .regular),
        candidateCommentFont: UIFont.systemFont(ofSize: 11, weight: .regular),
        toolbarButtonFrontColor: palette.textDark,
        toolbarButtonBackgroundColor: .clear,
        toolbarButtonPressedBackgroundColor: palette.funcPressed
      )
    }''',
)

keyboard = "Packages/HamsterKeyboardKit/Sources/View/IOSNative/IOSNativeKeyboardView.swift"
replace_once(
    keyboard,
    '''  static func solid(_ normal: UIColor, _ foreground: UIColor) -> IOSNativeKeyColors {
    IOSNativeKeyColors(normal: normal, pressed: iosDarker(normal), foreground: foreground)
  }''',
    '''  static func solid(_ normal: UIColor, _ foreground: UIColor, pressed: UIColor? = nil) -> IOSNativeKeyColors {
    IOSNativeKeyColors(normal: normal, pressed: pressed ?? iosDarker(normal), foreground: foreground)
  }''',
)
replace_once(
    keyboard,
    '''  private var lastLayoutBounds: CGRect = .zero
  private var subscriptions = Set<AnyCancellable>()''',
    '''  private var lastLayoutBounds: CGRect = .zero
  private var lastSafeAreaBottom: CGFloat = -1
  private var subscriptions = Set<AnyCancellable>()''',
)
replace_once(
    keyboard,
    '''  /// 发送键蓝/灰分界（按 P 图）：03/06/07/08/09 蓝；01/02/04/05 灰
  private func isBlueSendPanel() -> Bool {
    [.numberMore, .enUpper, .enLower, .enNumber, .enSymbol].contains(currentPanel)
  }

''',
    '',
)
replace_once(
    keyboard,
    '''    if spec.isSend {
      if isBlueSendPanel() {
        return .solid(palette.sendBlue, palette.textWhite)
      }
      // 灰底黑字
      return IOSNativeKeyColors(
        normal: palette.funcGray,
        pressed: iosDarker(palette.funcGray),
        foreground: palette.textDark
      )
    }''',
    '''    if spec.isSend {
      let active = keyboardContext.textDocumentProxy.hasText
      return active
        ? .solid(palette.sendBlue, palette.textWhite, pressed: palette.sendPressed)
        : .solid(palette.funcGray, palette.textDark, pressed: palette.funcPressed)
    }''',
)
replace_all(keyboard, ".solid(palette.sendBlue, palette.textWhite)", ".solid(palette.sendBlue, palette.textWhite, pressed: palette.sendPressed)")
replace_all(keyboard, ".solid(palette.funcGray, palette.textDark)", ".solid(palette.funcGray, palette.textDark, pressed: palette.funcPressed)")
replace_all(keyboard, "pressed: iosDarker(palette.lightGray)", "pressed: palette.lightGrayPressed")

marker = '''  private func isEnglishPanelLanguage() -> Bool {'''
replace_once(
    keyboard,
    marker,
    '''  private func overlayFontWeight(for spec: IOSNativeKey) -> UIFont.Weight {
    if spec.isSend || spec.action == .primary(.return) { return .regular }
    if spec.isInputAction {
      return currentPanel.geometry == .nineGrid ? .medium : .regular
    }
    switch spec.action {
    case .keyboardType, .custom, .backspace:
      return .medium
    default:
      return .regular
    }
  }

''' + marker,
)
replace_once(
    keyboard,
    "label.font = UIFont.systemFont(ofSize: overlayFontSize(for: spec), weight: .regular)",
    "label.font = UIFont.systemFont(ofSize: overlayFontSize(for: spec), weight: overlayFontWeight(for: spec))",
)
replace_once(
    keyboard,
    '''  private func iconSpec(for spec: IOSNativeKey) -> IOSNativeIconSpec? {
    if spec.action == .backspace {
      return IOSNativeIconSpec(asset: "clawIconBackspace", size: CGSize(width: 25, height: 22))
    }
    let text = spec.displayText ?? ""
    if text == "\\u{2B06}" || text == "⬆" {
      // 双击 Shift 进入大写锁定：P 图为实心箭头+底部横线（SF Symbol capslock.fill 兜底）
      if isCapsLocked {
        return IOSNativeIconSpec(systemName: "capslock.fill", size: CGSize(width: 20, height: 23))
      }
      return IOSNativeIconSpec(asset: "clawIconShift", size: CGSize(width: 20, height: 23))
    }
    if text == "😀" {
      return IOSNativeIconSpec(asset: "clawIconEmoji", size: CGSize(width: 24, height: 24))
    }
    return nil
  }''',
    '''  private func iconSpec(for spec: IOSNativeKey) -> IOSNativeIconSpec? {
    if spec.action == .backspace {
      return IOSNativeIconSpec(systemName: "delete.left", size: CGSize(width: 24, height: 20))
    }
    let text = spec.displayText ?? ""
    if text == "\\u{2B06}" || text == "⬆" {
      if isCapsLocked {
        return IOSNativeIconSpec(systemName: "capslock.fill", size: CGSize(width: 20, height: 22))
      }
      let symbol = currentPanel == .enUpper ? "shift.fill" : "shift"
      return IOSNativeIconSpec(systemName: symbol, size: CGSize(width: 20, height: 22))
    }
    if text == "😀" {
      return IOSNativeIconSpec(systemName: "face.smiling", size: CGSize(width: 22, height: 22))
    }
    return nil
  }''',
)
replace_once(
    keyboard,
    '''      } else if let systemName = icon.systemName {
        image = UIImage(systemName: systemName)
      }''',
    '''      } else if let systemName = icon.systemName {
        let pointSize = min(icon.size.width, icon.size.height)
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular, scale: .medium)
        image = UIImage(systemName: systemName, withConfiguration: configuration)
      }''',
)
replace_once(
    keyboard,
    "entry.button.layer.shadowOpacity = IOSNativeDesign.keyShadowOpacity",
    "entry.button.layer.shadowOpacity = palette.keyShadowOpacity",
)
replace_once(
    keyboard,
    '''    if lastLayoutBounds == bounds { return }
    lastLayoutBounds = bounds
    applyLayoutConstraints()
    updateLabelFonts()''',
    '''    let safeBottom = safeAreaInsets.bottom
    if lastLayoutBounds == bounds, abs(lastSafeAreaBottom - safeBottom) < 0.5 { return }
    lastLayoutBounds = bounds
    lastSafeAreaBottom = safeBottom
    applyLayoutConstraints()
    updateLabelFonts()''',
)
replace_once(
    keyboard,
    '''  private func applyLayoutConstraints() {
    NSLayoutConstraint.deactivate(layoutConstraints)
    layoutConstraints.removeAll()

    let sx = bounds.width / IOSNativeDesign.width
    let designH = IOSNativeDesign.height(for: currentPanel)

    for entry in entries {
      let r = entry.spec.rect
      let b = entry.button
      layoutConstraints.append(b.leadingAnchor.constraint(equalTo: leadingAnchor, constant: r.minX * sx))
      layoutConstraints.append(b.widthAnchor.constraint(equalToConstant: r.width * sx))
      if r.maxY >= designH - 0.01 {
        // 末行/跨行按键：顶部固定 + 底部贴视图底（决定总高度）
        layoutConstraints.append(b.topAnchor.constraint(equalTo: topAnchor, constant: r.minY))
        layoutConstraints.append(b.bottomAnchor.constraint(equalTo: bottomAnchor))
      } else {
        layoutConstraints.append(b.topAnchor.constraint(equalTo: topAnchor, constant: r.minY))
        layoutConstraints.append(b.heightAnchor.constraint(equalToConstant: r.height))
      }
    }
    NSLayoutConstraint.activate(layoutConstraints)
  }

  private func updateLabelFonts() {
    let sx = bounds.width / IOSNativeDesign.width
    for entry in entries {
      guard let label = entry.label else { continue }
      label.font = UIFont.systemFont(ofSize: overlayFontSize(for: entry.spec) * sx, weight: .regular)
    }
  }''',
    '''  private func applyLayoutConstraints() {
    NSLayoutConstraint.deactivate(layoutConstraints)
    layoutConstraints.removeAll()

    let metrics = IOSNativeSystemMetrics(viewWidth: bounds.width, safeAreaBottom: safeAreaInsets.bottom)
    let designH = IOSNativeDesign.height(for: currentPanel)

    for entry in entries {
      let r = entry.spec.rect
      let b = entry.button
      layoutConstraints.append(b.leadingAnchor.constraint(equalTo: leadingAnchor, constant: metrics.x(r.minX)))
      layoutConstraints.append(b.widthAnchor.constraint(equalToConstant: metrics.width(r.width)))
      if r.maxY >= designH - 0.01 {
        layoutConstraints.append(b.topAnchor.constraint(equalTo: topAnchor, constant: r.minY))
        layoutConstraints.append(b.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -metrics.bottomKeyInset))
      } else {
        layoutConstraints.append(b.topAnchor.constraint(equalTo: topAnchor, constant: r.minY))
        layoutConstraints.append(b.heightAnchor.constraint(equalToConstant: r.height))
      }
      b.buttonContentView.layer.cornerRadius = metrics.cornerRadius
      b.layer.cornerRadius = metrics.cornerRadius
      entry.label?.layer.cornerRadius = metrics.cornerRadius
      entry.icon?.layer.cornerRadius = metrics.cornerRadius
    }
    NSLayoutConstraint.activate(layoutConstraints)
  }

  private func updateLabelFonts() {
    let metrics = IOSNativeSystemMetrics(viewWidth: bounds.width, safeAreaBottom: safeAreaInsets.bottom)
    for entry in entries {
      guard let label = entry.label else { continue }
      label.font = UIFont.systemFont(
        ofSize: metrics.fontSize(overlayFontSize(for: entry.spec)),
        weight: overlayFontWeight(for: entry.spec)
      )
    }
  }''',
)

candidate = "Packages/HamsterKeyboardKit/Sources/View/CandidateBarView.swift"
replace_once(
    candidate,
    "    let buttonInsets = layoutConfig.buttonInsets\n    let codingAreaHeight: CGFloat = keyboardContext.useIOSNativeLayout ? 15 : keyboardContext.heightOfCodingArea",
    "    var buttonInsets = layoutConfig.buttonInsets\n    if keyboardContext.useIOSNativeLayout {\n      buttonInsets.left = 8\n      buttonInsets.right = 4\n    }\n    let codingAreaHeight: CGFloat = keyboardContext.useIOSNativeLayout ? 20 : keyboardContext.heightOfCodingArea",
)
replace_once(candidate, "separatorLine.heightAnchor.constraint(equalToConstant: 1)", "separatorLine.heightAnchor.constraint(equalToConstant: 0.5)")
replace_once(
    candidate,
    '''    if keyboardContext.useIOSNativeLayout {
      // 分隔线：浅色 #C7C7CC / 深色 #48484A
      separatorLine.backgroundColor = UIColor { trait in
        trait.userInterfaceStyle == .dark
          ? UIColor(red: 72 / 255, green: 72 / 255, blue: 74 / 255, alpha: 1)
          : UIColor(red: 199 / 255, green: 199 / 255, blue: 204 / 255, alpha: 1)
      }
      updateSyllableChips()
    }''',
    '''    if keyboardContext.useIOSNativeLayout {
      let palette = IOSNativePalette.current(dark: keyboardContext.hasDarkColorScheme)
      backgroundColor = palette.board
      separatorLine.backgroundColor = palette.separator
      verticalLine.backgroundColor = palette.separator
      stateImageView.tintColor = palette.secondaryText
      updateSyllableChips()
    }''',
)
replace_once(candidate, "button.layer.cornerRadius = 6", "button.layer.cornerRadius = 5")
replace_once(
    candidate,
    "button.contentEdgeInsets = UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)",
    "button.contentEdgeInsets = UIEdgeInsets(top: 1.5, left: 7, bottom: 1.5, right: 7)",
)

toolbar = "Packages/HamsterKeyboardKit/Sources/View/KeyboardToolbarView.swift"
replace_once(
    toolbar,
    '''    if keyboardContext.useIOSNativeLayout {
      backgroundColor = IOSNativePalette.current(dark: keyboardContext.hasDarkColorScheme).board
    } else {
      backgroundColor = ClawPanelPalette.toolbarBackground
    }
    candidateBarView.setStyle(self.style)
    candidateBarView.backgroundColor = backgroundColor

    updateEntryButtonStates()
    updateEyeButtonState()''',
    '''    if keyboardContext.useIOSNativeLayout {
      let palette = IOSNativePalette.current(dark: keyboardContext.hasDarkColorScheme)
      backgroundColor = palette.board
      commonFunctionBar.backgroundColor = palette.board
      candidateBarView.backgroundColor = palette.board
      eyeButton.tintColor = palette.textDark
      emojiButton.tintColor = palette.textDark
      dismissKeyboardButton.tintColor = palette.textDark
    } else {
      backgroundColor = ClawPanelPalette.toolbarBackground
      commonFunctionBar.backgroundColor = .clear
    }
    candidateBarView.setStyle(self.style)
    candidateBarView.backgroundColor = backgroundColor

    updateEntryButtonStates()
    updateEyeButtonState()''',
)
replace_once(
    toolbar,
    '''  func updateEntryButtonStates() {
    let tab = keyboardContext.clawPanelTab
    let aiSelected = tab == 0''',
    '''  func updateEntryButtonStates() {
    let tab = keyboardContext.clawPanelTab
    if keyboardContext.useIOSNativeLayout {
      let palette = IOSNativePalette.current(dark: keyboardContext.hasDarkColorScheme)
      let aiSelected = tab == 0
      aiButton.glassTintColor = aiSelected ? palette.toolbarControlSelected : palette.toolbarControl
      aiButton.setTitleColor(palette.textDark, for: .normal)

      let helpSelected = tab == 1
      helpReplyButton.backgroundColor = helpSelected ? palette.toolbarControlSelected : palette.toolbarControl
      helpReplyButton.setTitleColor(palette.textDark, for: .normal)

      let superSelected = tab == 2
      superTalkButton.backgroundColor = superSelected ? palette.toolbarControlSelected : palette.toolbarControl
      superTalkButton.setTitleColor(palette.textDark, for: .normal)
      eyeButton.tintColor = palette.textDark
      emojiButton.tintColor = palette.textDark
      dismissKeyboardButton.tintColor = palette.textDark
      return
    }
    let aiSelected = tab == 0''',
)
replace_once(
    toolbar,
    '''  func updateEyeButtonState() {
    let collecting = ClawTalkPrivacyService.shared.isCollectionEnabled
    eyeButton.setImage(UIImage(systemName: collecting ? "eye" : "eye.slash"), for: .normal)
    eyeButton.tintColor = collecting ? ClawPanelPalette.deepBlue : .systemOrange
  }''',
    '''  func updateEyeButtonState() {
    let collecting = ClawTalkPrivacyService.shared.isCollectionEnabled
    eyeButton.setImage(UIImage(systemName: collecting ? "eye" : "eye.slash"), for: .normal)
    if keyboardContext.useIOSNativeLayout {
      let palette = IOSNativePalette.current(dark: keyboardContext.hasDarkColorScheme)
      eyeButton.tintColor = collecting ? palette.textDark : .systemOrange
    } else {
      eyeButton.tintColor = collecting ? ClawPanelPalette.deepBlue : .systemOrange
    }
  }''',
)

test_path = "Packages/HamsterKeyboardKit/Tests/KeyboardKit/Appearance/IOSNativeSystemMetricsTest.swift"
write(
    test_path,
    '''import XCTest

@testable import HamsterKeyboardKit

final class IOSNativeSystemMetricsTest: XCTestCase {
  func testTypographyDoesNotScaleWithPhoneWidth() {
    let compact = IOSNativeSystemMetrics(viewWidth: 375, safeAreaBottom: 0)
    let max = IOSNativeSystemMetrics(viewWidth: 430, safeAreaBottom: 0)
    XCTAssertEqual(compact.fontSize(22), 22, accuracy: 0.001)
    XCTAssertEqual(max.fontSize(22), 22, accuracy: 0.001)
  }

  func testPhoneWidthsStayInsideNativeEdges() {
    for width: CGFloat in [375, 390, 393, 402, 414, 430] {
      let metrics = IOSNativeSystemMetrics(viewWidth: width, safeAreaBottom: 0)
      XCTAssertGreaterThanOrEqual(metrics.x(IOSNativeDesign.paddingH), 3)
      XCTAssertLessThanOrEqual(
        metrics.x(IOSNativeDesign.width - IOSNativeDesign.paddingH),
        width - 3 + 0.01
      )
    }
  }

  func testSafeAreaUsesOnlyVisualBreathingSpace() {
    XCTAssertEqual(IOSNativeSystemMetrics(viewWidth: 390, safeAreaBottom: 0).bottomKeyInset, 0)
    XCTAssertEqual(IOSNativeSystemMetrics(viewWidth: 390, safeAreaBottom: 34).bottomKeyInset, 4)
  }
}
''',
)

checks = {
    palette_path: ["funcPressed", "sendPressed", "keyShadowOpacity"],
    metrics_path: ["fontSize(_ base", "bottomKeyInset", "horizontalEdge"],
    keyboard: ["IOSNativeSystemMetrics", "overlayFontWeight", "delete.left", "palette.sendPressed"],
    candidate: ["codingAreaHeight: CGFloat = keyboardContext.useIOSNativeLayout ? 20", "palette.separator"],
    toolbar: ["palette.toolbarControlSelected", "commonFunctionBar.backgroundColor = palette.board"],
    appearance: ["style.backgroundColor = IOSNativePalette.current", "palette.candidateSelected"],
}
for path, needles in checks.items():
    text = read(path)
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"{path}: missing expected marker {needle!r}")

print("iOS native alignment patch applied")
