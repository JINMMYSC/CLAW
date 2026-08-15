//
//  IOSNativeKeyboardView.swift
//
//  ClawTalk「IOS 原生布局」键盘视图
//
//  按 IOSNativeLayout 输出设计空间点位，用 Auto Layout 约束布局键位。
//  面板切换通过 keyboardContext.keyboardType（.keyboardType action）完成；
//  KeyboardRootView 在 keyboardType 变化时重建本视图。
//

import Combine
import HamsterKit
import HamsterUIKit
import OSLog
import UIKit

/// iOS 原生布局按键：支持覆盖文本标签并随按压状态变色
private class IOSNativeButton: KeyboardButton {
  var overlayLabel: UILabel?
  var overlayNormalBG: UIColor?
  var overlayPressedBG: UIColor?
  var overlayNormalFG: UIColor?
  var overlayPressedFG: UIColor?

  override func updateButtonStyle(isPressed: Bool) {
    super.updateButtonStyle(isPressed: isPressed)
    guard let label = overlayLabel else { return }
    label.backgroundColor = isPressed ? (overlayPressedBG ?? overlayNormalBG) : overlayNormalBG
    label.textColor = isPressed ? (overlayPressedFG ?? overlayNormalFG) : overlayNormalFG
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
  }

  private var entries: [KeyEntry] = []
  private var currentPanel: IOSNativePanel = .pinyin9
  private var layoutConstraints: [NSLayoutConstraint] = []
  private var lastLayoutBounds: CGRect = .zero

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
    setupAppearance()
  }

  deinit {
    entries.forEach { $0.button.removeFromSuperview() }
  }

  override public func setupAppearance() {
    ClawPanelPalette.sync(with: keyboardContext)
    backgroundColor = ClawPanelPalette.keyboardBackground
    contentMode = .redraw
  }

  /// 高度与设计空间一致（182pt）：
  /// 与 EmojisKeyboard 相同策略，让系统按内容高度撑起键盘（否则键盘高度崩溃为空白）
  override public var intrinsicContentSize: CGSize {
    CGSize(width: UIView.noIntrinsicMetric, height: IOSNativeDesign.height)
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

      let label = makeOverlayLabelIfNeeded(for: spec, on: button)
      entries.append(KeyEntry(button: button, spec: spec, label: label))
    }
    setNeedsLayout()
  }

  private func rowIndex(for rect: CGRect) -> Int {
    let y = rect.midY
    let rowH = IOSNativeDesign.rowH
    let gv = IOSNativeDesign.gapV
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

  /// 是否需要覆盖文本标签（标准文本与目标不同/为空/是图标时）
  private func needsOverlay(for spec: IOSNativeKey) -> Bool {
    guard let text = spec.displayText else { return false }
    if spec.action == .backspace { return false }
    let standard = appearance.buttonText(for: spec.action) ?? ""
    if standard.isEmpty { return true }
    return standard != text
  }

  private func overlayFontSize(for spec: IOSNativeKey) -> CGFloat {
    if spec.isSend { return 16 }
    let text = spec.displayText ?? ""
    if text == "，。？！" { return 14 }
    if text == ". , :" || text == ". . :" { return 15 }
    if text == "😀" { return 20 }
    if text == "⬆" { return 18 }
    if !spec.isInputAction { return 14 }
    return 18
  }

  private func makeOverlayLabelIfNeeded(for spec: IOSNativeKey, on button: IOSNativeButton) -> UILabel? {
    guard needsOverlay(for: spec), let text = spec.displayText else { return nil }

    let style = button.normalButtonStyle
    let label = UILabel(frame: .zero)
    label.text = text
    label.textAlignment = .center
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.4
    label.numberOfLines = 1
    label.isUserInteractionEnabled = false
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = UIFont.systemFont(ofSize: overlayFontSize(for: spec))
    label.textColor = spec.isSend ? .white : style.foregroundColor
    label.backgroundColor = style.backgroundColor
    if let radius = style.cornerRadius {
      label.layer.cornerRadius = radius
      label.layer.masksToBounds = true
    }
    button.addSubview(label)
    NSLayoutConstraint.activate([
      label.topAnchor.constraint(equalTo: button.topAnchor),
      label.leadingAnchor.constraint(equalTo: button.leadingAnchor),
      label.trailingAnchor.constraint(equalTo: button.trailingAnchor),
      label.bottomAnchor.constraint(equalTo: button.bottomAnchor)
    ])

    button.overlayLabel = label
    button.overlayNormalBG = style.backgroundColor
    button.overlayPressedBG = button.pressedButtonStyle.backgroundColor
    button.overlayNormalFG = spec.isSend ? .white : style.foregroundColor
    button.overlayPressedFG = button.pressedButtonStyle.foregroundColor
    return label
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
    let designH = IOSNativeDesign.height

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
