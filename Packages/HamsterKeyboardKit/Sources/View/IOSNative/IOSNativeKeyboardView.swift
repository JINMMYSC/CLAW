//
//  IOSNativeKeyboardView.swift
//
//  ClawTalk「IOS 原生布局」键盘视图
//
//  按 IOSNativeLayout 输出设计空间点位，用 Auto Layout 约束布局键位。
//  面板切换通过 keyboardContext.keyboardType（.keyboardType action）完成；
//  KeyboardRootView 在 keyboardType 变化时重建本视图。
//  配色/字号按 P 图（AA 文件夹 9 张）硬编码，不依赖主题。
//

import Combine
import HamsterKit
import HamsterUIKit
import OSLog
import UIKit

// MARK: - P 图固定配色工具

private func iosRGB(_ hex: UInt32) -> UIColor {
  UIColor(
    red: CGFloat((hex >> 16) & 0xFF) / 255,
    green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255,
    alpha: 1
  )
}

private func iosDarker(_ color: UIColor, by factor: CGFloat = 0.85) -> UIColor {
  var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
  guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return color }
  return UIColor(red: r * factor, green: g * factor, blue: b * factor, alpha: a)
}

/// 单键配色：按压仅改变背景色（变深），文字颜色保持不变
private struct IOSNativeKeyColors {
  let normal: UIColor
  let pressed: UIColor
  let foreground: UIColor

  static func solid(_ normal: UIColor, _ foreground: UIColor) -> IOSNativeKeyColors {
    IOSNativeKeyColors(normal: normal, pressed: iosDarker(normal), foreground: foreground)
  }
}

/// 按 P 图硬编码的 iOS 原生配色
private enum IOSNativePalette {
  static let board = iosRGB(0xD1D4D9)
  static let char = UIColor.white
  static let charPressed = iosRGB(0xE8ECF0)
  static let funcGray = iosRGB(0xAAB0BA)
  static let lightGray = iosRGB(0xE8ECF0)
  static let sendBlue = iosRGB(0x007AFF)
  static let textDark = iosRGB(0x000000)
  static let textWhite = UIColor.white
}

/// iOS 原生布局按键：支持覆盖文本标签并随按压状态变色
private class IOSNativeButton: KeyboardButton {
  var overlayLabel: UILabel?
  var overlayIconView: UIImageView?
  var overlayNormalBG: UIColor?
  var overlayPressedBG: UIColor?
  var overlayNormalFG: UIColor?
  var overlayPressedFG: UIColor?

  override func updateButtonStyle(isPressed: Bool) {
    super.updateButtonStyle(isPressed: isPressed)
    if let label = overlayLabel {
      label.backgroundColor = isPressed ? (overlayPressedBG ?? overlayNormalBG) : overlayNormalBG
      label.textColor = isPressed ? (overlayPressedFG ?? overlayNormalFG) : overlayNormalFG
    }
    if let icon = overlayIconView {
      icon.backgroundColor = isPressed ? (overlayPressedBG ?? overlayNormalBG) : overlayNormalBG
    }
  }
}

public class IOSNativeKeyboardView: KeyboardTouchView {
  private let actionHandler: KeyboardActionHandler
  private let appearance: KeyboardAppearance
  private let keyboardContext: KeyboardContext
  private let rimeContext: RimeContext
  private let calloutContext: KeyboardCalloutContext

  private struct KeyEntry {
    let button: IOSNativeButton
    let spec: IOSNativeKey
    let label: UILabel?
    let icon: UIImageView?
  }

  private var entries: [KeyEntry] = []
  private var currentPanel: IOSNativePanel = .pinyin9
  private var layoutConstraints: [NSLayoutConstraint] = []
  private var lastLayoutBounds: CGRect = .zero
  private var subscriptions = Set<AnyCancellable>()
  /// p1 拼音9键 行1第5键：^_^ / 分隔 双态键
  private var separatorEntry: KeyEntry?
  /// 当前面板的 return/发送 键（聊天场景无字灰/有字蓝）
  private var sendReturnEntry: KeyEntry?
  private var chatSendTimer: Timer?

  public init(
    actionHandler: KeyboardActionHandler,
    appearance: KeyboardAppearance,
    keyboardContext: KeyboardContext,
    rimeContext: RimeContext,
    calloutContext: KeyboardCalloutContext?
  ) {
    self.actionHandler = actionHandler
    self.appearance = appearance
    self.keyboardContext = keyboardContext
    self.rimeContext = rimeContext
    self.calloutContext = calloutContext ?? .disabled
    super.init(frame: .zero)

    if let panel = IOSNativeLayout.panel(for: keyboardContext.keyboardType) {
      currentPanel = panel
    }
    rebuild()
    setupSeparatorKey()
    setupChatSendKey()
    setupAppearance()
  }

  deinit {
    chatSendTimer?.invalidate()
    entries.forEach { $0.button.removeFromSuperview() }
  }

  override public func setupAppearance() {
    backgroundColor = IOSNativePalette.board
    contentMode = .redraw
  }

  /// 高度按当前面板纵向几何（9键族 4+3*(50+6)+50=222；紧凑族 4+3*(46+10)+46=218）
  /// 与 EmojisKeyboard 相同策略，让系统按内容高度撑起键盘（否则键盘高度崩溃为空白）
  override public var intrinsicContentSize: CGSize {
    CGSize(width: UIView.noIntrinsicMetric, height: IOSNativeDesign.height(for: currentPanel))
  }

  override public func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      setNeedsLayout()
      layoutIfNeeded()
    }
  }

  // MARK: - 构建

  private func rebuild() {
    entries.forEach { $0.button.removeFromSuperview() }
    entries.removeAll()

    let specs = IOSNativeLayout.keys(for: currentPanel, context: keyboardContext)
    for (index, spec) in specs.enumerated() {
      let size = KeyboardLayoutItemSize(width: .points(spec.rect.width), height: spec.rect.height)
      let item = KeyboardLayoutItem(action: spec.action, size: size, insets: .zero, swipes: [], key: nil)
      let button = IOSNativeButton(
        row: rowIndex(for: spec.rect),
        column: index,
        item: item,
        actionHandler: actionHandler,
        keyboardContext: keyboardContext,
        rimeContext: rimeContext,
        calloutContext: calloutContext,
        appearance: appearance
      )
      button.translatesAutoresizingMaskIntoConstraints = false
      addSubview(button)

      let (label, icon) = makeOverlayViewIfNeeded(for: spec, on: button)
      entries.append(KeyEntry(button: button, spec: spec, label: label, icon: icon))
    }
    separatorEntry = entries.first { $0.spec.displayText == "^_^" }
    sendReturnEntry = entries.first { $0.spec.isSend }
    setNeedsLayout()
  }

  // MARK: - p1 双态键（^_^ / 分隔）

  private func setupSeparatorKey() {
    updateSeparatorKeyState()
    rimeContext.userInputKeyPublished
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateSeparatorKeyState()
      }
      .store(in: &subscriptions)
  }

  // MARK: - 聊天发送键动态色（无字灰 / 有字蓝，P 图行为）

  private func setupChatSendKey() {
    updateChatSendKeyState()
    chatSendTimer?.invalidate()
    chatSendTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      self?.updateChatSendKeyState()
    }
  }

  /// 仅聊天发送键（isSend 且无 tintOverride，即 returnKeyType .send/.join）：
  /// 输入框无字 -> 灰键无文字；有字 -> 蓝键显示 发送/send
  private func updateChatSendKeyState() {
    guard let entry = sendReturnEntry, let label = entry.label else { return }
    let spec = entry.spec
    guard spec.isSend, spec.tintOverride == nil else { return }
    let hasText = keyboardContext.textDocumentProxy.hasText
    let colors = hasText
      ? IOSNativeKeyColors.solid(IOSNativePalette.sendBlue, IOSNativePalette.textWhite)
      : IOSNativeKeyColors.solid(IOSNativePalette.funcGray, IOSNativePalette.textDark)
    label.text = hasText ? (spec.displayText ?? "") : nil
    entry.button.overlayNormalBG = colors.normal
    entry.button.overlayPressedBG = colors.pressed
    entry.button.overlayNormalFG = colors.foreground
    entry.button.overlayPressedFG = colors.foreground
    label.backgroundColor = colors.normal
    label.textColor = colors.foreground
  }

  private func updateSeparatorKeyState() {
    guard let entry = separatorEntry, let label = entry.label else { return }
    let isTyping = !rimeContext.userInputKey.isEmpty
    entry.button.item.action = isTyping ? .primary(.return) : .character("^_^")
    label.text = isTyping ? "分隔" : "^_^"
    let normal = isTyping ? IOSNativePalette.char : IOSNativePalette.funcGray
    let pressed = isTyping ? IOSNativePalette.charPressed : iosDarker(IOSNativePalette.funcGray)
    entry.button.overlayNormalBG = normal
    entry.button.overlayPressedBG = pressed
    entry.button.overlayNormalFG = IOSNativePalette.textDark
    entry.button.overlayPressedFG = IOSNativePalette.textDark
    label.backgroundColor = normal
  }

  private func rowIndex(for rect: CGRect) -> Int {
    let y = rect.midY
    let rowH = IOSNativeDesign.rowH(for: currentPanel)
    let gv = IOSNativeDesign.gapV(for: currentPanel)
    let pv = IOSNativeDesign.paddingV
    let rows = [pv, pv + rowH + gv, pv + 2 * (rowH + gv), pv + 3 * (rowH + gv)]
    var best = 0
    var bestDist = CGFloat.greatestFiniteMagnitude
    for (i, rowY) in rows.enumerated() {
      let dist = abs(y - (rowY + rowH / 2))
      if dist < bestDist {
        bestDist = dist
        best = i
      }
    }
    return best
  }

  /// 是否需要覆盖文本标签：所有带文字的键都覆盖，保证配色/字号完全按 P 图
  private func needsOverlay(for spec: IOSNativeKey) -> Bool {
    spec.displayText != nil
  }

  /// 发送键蓝/灰分界（按 P 图）：03/06/07/08/09 蓝；01/02/04/05 灰
  private func isBlueSendPanel() -> Bool {
    [.numberMore, .enUpper, .enLower, .enNumber, .enSymbol].contains(currentPanel)
  }

  /// 按面板 + 按键类型返回固定配色
  private func keyColors(for spec: IOSNativeKey) -> IOSNativeKeyColors {
    // return 键强制配色：搜索/前往/继续=蓝，完成/换行=灰；nil 走面板规则
    if let tint = spec.tintOverride {
      switch tint {
      case .blue:
        return .solid(IOSNativePalette.sendBlue, IOSNativePalette.textWhite)
      case .gray:
        return .solid(IOSNativePalette.funcGray, IOSNativePalette.textDark)
      }
    }
    if spec.isSend {
      if isBlueSendPanel() {
        return .solid(IOSNativePalette.sendBlue, IOSNativePalette.textWhite)
      }
      // 灰底黑字
      return IOSNativeKeyColors(
        normal: IOSNativePalette.funcGray,
        pressed: iosDarker(IOSNativePalette.funcGray),
        foreground: IOSNativePalette.textDark
      )
    }
    switch spec.action {
    case .space:
      return IOSNativeKeyColors(
        normal: IOSNativePalette.char,
        pressed: IOSNativePalette.charPressed,
        foreground: IOSNativePalette.textDark
      )
    case .backspace:
      return .solid(IOSNativePalette.funcGray, IOSNativePalette.textDark)
    case .keyboardType, .custom:
      // 03 数字更多第2行第5键「更多」浅灰
      if currentPanel == .numberMore, spec.displayText == "更多" {
        return IOSNativeKeyColors(
          normal: IOSNativePalette.lightGray,
          pressed: iosDarker(IOSNativePalette.lightGray),
          foreground: IOSNativePalette.textDark
        )
      }
      // 英文大写 Shift 白、小写 Shift 灰
      if spec.displayText == "⬆" {
        if currentPanel == .enUpper {
          return IOSNativeKeyColors(
            normal: IOSNativePalette.char,
            pressed: IOSNativePalette.charPressed,
            foreground: IOSNativePalette.textDark
          )
        }
        return .solid(IOSNativePalette.funcGray, IOSNativePalette.textDark)
      }
      return .solid(IOSNativePalette.funcGray, IOSNativePalette.textDark)
    case .character, .chineseNineGrid:
      // iOS 9键上的 ^_^ 是灰色功能键
      if spec.displayText == "^_^" {
        return .solid(IOSNativePalette.funcGray, IOSNativePalette.textDark)
      }
      return IOSNativeKeyColors(
        normal: IOSNativePalette.char,
        pressed: IOSNativePalette.charPressed,
        foreground: IOSNativePalette.textDark
      )
    default:
      return .solid(IOSNativePalette.funcGray, IOSNativePalette.textDark)
    }
  }

  private func overlayFontSize(for spec: IOSNativeKey) -> CGFloat {
    if spec.isSend { return 14 }
    if spec.action == .primary(.return) { return 14 }
    let text = spec.displayText ?? ""
    switch text {
    case "⌫": return 16
    case "空格", "space": return 13
    case "😀": return 20
    case "⬆": return 16
    case "，。？！": return 14
    case ". , :", ". . :": return 15
    case "^_^": return 15
    default: break
    }
    if spec.isInputAction {
      // 9键面板小字号；英文/10列符号面板大字号
      if currentPanel == .pinyin9 || currentPanel == .number || currentPanel == .numberMore {
        return 14
      }
      return 18
    }
    return 14
  }


  /// P 图图标键：退格/Shift/表情 使用裁切自 P 图的单色图标（设计空间 pt，不随 sx 缩放）
  private struct IOSNativeIconSpec {
    let asset: String
    let size: CGSize
  }

  private func iconSpec(for spec: IOSNativeKey) -> IOSNativeIconSpec? {
    if spec.action == .backspace {
      return IOSNativeIconSpec(asset: "clawIconBackspace", size: CGSize(width: 25, height: 22))
    }
    let text = spec.displayText ?? ""
    if text == "\u{2B06}" || text == "⬆" {
      return IOSNativeIconSpec(asset: "clawIconShift", size: CGSize(width: 20, height: 23))
    }
    if text == "😀" {
      return IOSNativeIconSpec(asset: "clawIconEmoji", size: CGSize(width: 24, height: 24))
    }
    return nil
  }

  private func makeOverlayViewIfNeeded(for spec: IOSNativeKey, on button: IOSNativeButton) -> (UILabel?, UIImageView?) {
    guard needsOverlay(for: spec), let text = spec.displayText else { return (nil, nil) }
    let colors = keyColors(for: spec)
    if let icon = iconSpec(for: spec), let image = UIImage(named: icon.asset, in: .hamsterKeyboard, with: .none) {
      let view = UIImageView(image: image)
      view.contentMode = .center
      view.isUserInteractionEnabled = false
      view.translatesAutoresizingMaskIntoConstraints = false
      view.backgroundColor = colors.normal
      view.layer.cornerRadius = IOSNativeDesign.radius
      view.layer.masksToBounds = true
      button.addSubview(view)
      NSLayoutConstraint.activate([
        view.topAnchor.constraint(equalTo: button.topAnchor),
        view.leadingAnchor.constraint(equalTo: button.leadingAnchor),
        view.trailingAnchor.constraint(equalTo: button.trailingAnchor),
        view.bottomAnchor.constraint(equalTo: button.bottomAnchor)
      ])
      button.overlayIconView = view
      button.overlayNormalBG = colors.normal
      button.overlayPressedBG = colors.pressed
      button.overlayNormalFG = colors.foreground
      button.overlayPressedFG = colors.foreground
      return (nil, view)
    }
    let label = UILabel(frame: .zero)
    label.text = text
    label.textAlignment = .center
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.4
    label.numberOfLines = 1
    label.isUserInteractionEnabled = false
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = UIFont.systemFont(ofSize: overlayFontSize(for: spec))
    label.textColor = colors.foreground
    label.backgroundColor = colors.normal
    label.layer.cornerRadius = IOSNativeDesign.radius
    label.layer.masksToBounds = true
    button.addSubview(label)
    NSLayoutConstraint.activate([
      label.topAnchor.constraint(equalTo: button.topAnchor),
      label.leadingAnchor.constraint(equalTo: button.leadingAnchor),
      label.trailingAnchor.constraint(equalTo: button.trailingAnchor),
      label.bottomAnchor.constraint(equalTo: button.bottomAnchor)
    ])
    button.overlayLabel = label
    button.overlayNormalBG = colors.normal
    button.overlayPressedBG = colors.pressed
    button.overlayNormalFG = colors.foreground
    button.overlayPressedFG = colors.foreground
    return (label, nil)
  }

  // MARK: - 布局

  override public func layoutSubviews() {
    super.layoutSubviews()
    guard bounds.width > 0, bounds.height > 0 else { return }
    if lastLayoutBounds == bounds { return }
    lastLayoutBounds = bounds
    applyLayoutConstraints()
    updateLabelFonts()
  }

  /// 用 Auto Layout 按设计点位约束按键；
  /// 纵向使用固定行高/间距（末行贴视图底），
  /// 形成确定高度链，与标准键盘一致；横向按实际宽度缩放填满
  private func applyLayoutConstraints() {
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
      label.font = UIFont.systemFont(ofSize: overlayFontSize(for: entry.spec) * sx)
    }
  }
}