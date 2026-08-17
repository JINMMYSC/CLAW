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

/// 单键配色：按压仅改变背景色（变深），文字颜色保持不变
private struct IOSNativeKeyColors {
  let normal: UIColor
  let pressed: UIColor
  let foreground: UIColor

  static func solid(_ normal: UIColor, _ foreground: UIColor) -> IOSNativeKeyColors {
    IOSNativeKeyColors(normal: normal, pressed: iosDarker(normal), foreground: foreground)
  }
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

  /// 当前系统深浅色下的 P 图配色（随 keyboardContext.colorScheme 实时切换）
  private var palette: IOSNativePalette {
    IOSNativePalette.current(dark: keyboardContext.hasDarkColorScheme)
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
  /// 拼音9键 第4行第2列「选拼音」键：候选拼音逐个跳选
  private var selectPinyinEntry: KeyEntry?
  private var selectPinyinIndex = 0
  private var userInterfaceStyle: UIUserInterfaceStyle = .unspecified
  /// 9 键长按选字母：当前触摸跟踪（同一时刻只能一个键弹出）
  private final class T9Track {
    let touch: UITouch
    let entry: KeyEntry
    let letters: [String]
    /// 按下起点（判断手指是否真的滑动过）
    let pressStart: CGPoint
    var calloutShown = false
    /// 手指是否滑出过按键（只有真正滑出过，松开才输入）
    var hasLeftKey = false
    /// 手指是否从按下点位移超过阈值（长按不滑动不输入）
    var hasMoved = false
    var cancelled = false
    var selectedIndex: Int?
    var fourthTimerToken: UUID?

    init(touch: UITouch, entry: KeyEntry, letters: [String], pressStart: CGPoint) {
      self.touch = touch
      self.entry = entry
      self.letters = letters
      self.pressStart = pressStart
    }
  }

  private var t9Track: T9Track?
  private var t9Bubble: IOST9CalloutView?
  /// 长按 0.35s 弹出气泡（明哥规格）
  private let t9LongPressDelay: TimeInterval = 0.35
  /// 4 字母键在上滑区域再长按 0.3s 选中第四个字母
  private let t9FourthLetterDelay: TimeInterval = 0.3

  /// 当前是否大写锁定（英文26键双击 Shift 进入）
  private var isCapsLocked: Bool {
    if case .alphabetic(.capsLocked) = keyboardContext.keyboardType { return true }
    if case .chinese(.capsLocked) = keyboardContext.keyboardType { return true }
    return false
  }

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
    dismissT9Callout()
    entries.forEach { $0.button.removeFromSuperview() }
  }

  override public func setupAppearance() {
    backgroundColor = palette.board
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
    } else {
      // 输入框失焦/键盘收起：全部重置
      dismissT9Callout()
    }
  }

  // MARK: - 构建

  private func rebuild() {
    entries.forEach { $0.button.removeFromSuperview() }
    entries.removeAll()
    dismissT9Callout()
    // 记录进入 emoji 面板前的面板语言族（决定 emoji 返回键文字 ABC/拼音）
    IOSNativeEmojiReturnState.lastPanelWasEnglish = isEnglishPanelLanguage()

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
    selectPinyinEntry = entries.first { $0.spec.displayText == "选拼音" }
    // 修复 P 图圆角：底色层显式设置圆角（appearance.style 未配时默认直角）
    for entry in entries {
      entry.button.buttonContentView.layer.cornerRadius = IOSNativeDesign.radius
      entry.button.buttonContentView.layer.masksToBounds = true
    }
    refreshOverlays()
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
      ? IOSNativeKeyColors.solid(palette.sendBlue, palette.textWhite)
      : IOSNativeKeyColors.solid(palette.funcGray, palette.textDark)
    label.text = spec.displayText ?? ""
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
    // 组字态：分隔键（A2 契约保证 .delimiter 链路可用）；空闲态：^_^ 字符
    entry.button.item.action = isTyping ? .delimiter : .character("^_^")
    label.text = isTyping ? "分隔" : "^_^"
    // ^_^ / 分隔 双态都白色（P 图要求），按压用字符键按压色
    let normal = palette.char
    let pressed = palette.charPressed
    entry.button.overlayNormalBG = normal
    entry.button.overlayPressedBG = pressed
    entry.button.overlayNormalFG = palette.textDark
    entry.button.overlayPressedFG = palette.textDark
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
        return .solid(palette.sendBlue, palette.textWhite)
      case .gray:
        return .solid(palette.funcGray, palette.textDark)
      }
    }
    if spec.isSend {
      if isBlueSendPanel() {
        return .solid(palette.sendBlue, palette.textWhite)
      }
      // 灰底黑字
      return IOSNativeKeyColors(
        normal: palette.funcGray,
        pressed: iosDarker(palette.funcGray),
        foreground: palette.textDark
      )
    }
    switch spec.action {
    case .space:
      return IOSNativeKeyColors(
        normal: palette.char,
        pressed: palette.charPressed,
        foreground: palette.textDark
      )
    case .backspace:
      return .solid(palette.funcGray, palette.textDark)
    case .keyboardType, .custom:
      // 03 数字更多第2行第5键「更多」浅灰
      if currentPanel == .numberMore, spec.displayText == "更多" {
        return IOSNativeKeyColors(
          normal: palette.lightGray,
          pressed: iosDarker(palette.lightGray),
          foreground: palette.textDark
        )
      }
      // 拼音9键第4行「选拼音」键：白色（P 图要求），点按逐个跳选候选拼音
      if currentPanel == .pinyin9, spec.displayText == "选拼音" {
        return IOSNativeKeyColors(
          normal: palette.char,
          pressed: palette.charPressed,
          foreground: palette.textDark
        )
      }
      // 拼音9键「，。？！ 」标点循环键：白色（P 图要求），按一次换一个标点
      if currentPanel == .pinyin9, spec.displayText == "，。？！" {
        return IOSNativeKeyColors(
          normal: palette.char,
          pressed: palette.charPressed,
          foreground: palette.textDark
        )
      }
      // 英文大写 Shift 白、小写 Shift 灰
      if spec.displayText == "⬆" {
        if currentPanel == .enUpper {
          return IOSNativeKeyColors(
            normal: palette.char,
            pressed: palette.charPressed,
            foreground: palette.textDark
          )
        }
        return .solid(palette.funcGray, palette.textDark)
      }
      return .solid(palette.funcGray, palette.textDark)
    case .character, .chineseNineGrid:
      return IOSNativeKeyColors(
        normal: palette.char,
        pressed: palette.charPressed,
        foreground: palette.textDark
      )
    default:
      return .solid(palette.funcGray, palette.textDark)
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

  private func isEnglishPanelLanguage() -> Bool {
    switch keyboardContext.keyboardType {
    case .alphabetic, .numeric, .symbolic:
      return true
    default:
      return false
    }
  }


  /// P 图图标键：退格/Shift/表情 使用裁切自 P 图的单色图标（设计空间 pt，不随 sx 缩放）
  private struct IOSNativeIconSpec {
    let asset: String?
    let systemName: String?
    let size: CGSize

    init(asset: String? = nil, systemName: String? = nil, size: CGSize) {
      self.asset = asset
      self.systemName = systemName
      self.size = size
    }
  }

  private func iconSpec(for spec: IOSNativeKey) -> IOSNativeIconSpec? {
    if spec.action == .backspace {
      return IOSNativeIconSpec(asset: "clawIconBackspace", size: CGSize(width: 25, height: 22))
    }
    let text = spec.displayText ?? ""
    if text == "\u{2B06}" || text == "⬆" {
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
  }

  private func makeOverlayViewIfNeeded(for spec: IOSNativeKey, on button: IOSNativeButton) -> (UILabel?, UIImageView?) {
    guard needsOverlay(for: spec), let text = spec.displayText else { return (nil, nil) }
    let colors = keyColors(for: spec)
    if let icon = iconSpec(for: spec) {
      var image: UIImage?
      if let asset = icon.asset {
        image = UIImage(named: asset, in: .hamsterKeyboard, with: .none)
      } else if let systemName = icon.systemName {
        image = UIImage(systemName: systemName)
      }
      if let image = image {
        let view: UIImageView
        if icon.systemName != nil {
          view = UIImageView(image: image.withRenderingMode(.alwaysTemplate))
          view.tintColor = colors.foreground
        } else {
          view = UIImageView(image: image)
        }
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

  // MARK: - 覆盖层配色刷新

  /// 统一刷新所有覆盖层配色（深浅色切换 / rebuild 后调用）
  /// send / 分隔 两键有独立动态配色，跳过不覆盖
  private func refreshOverlays() {
    for entry in entries {
      if entry.button === sendReturnEntry?.button || entry.button === separatorEntry?.button {
        continue
      }
      let colors = keyColors(for: entry.spec)
      entry.button.overlayNormalBG = colors.normal
      entry.button.overlayPressedBG = colors.pressed
      entry.button.overlayNormalFG = colors.foreground
      entry.button.overlayPressedFG = colors.foreground
      if let label = entry.label {
        label.backgroundColor = colors.normal
        label.textColor = colors.foreground
      }
      if let icon = entry.icon {
        icon.backgroundColor = colors.normal
        if icon.image?.renderingMode == .alwaysTemplate {
          icon.tintColor = colors.foreground
        }
      }
    }
  }

  // MARK: - 选拼音跳选

  override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    if let track = t9Track, touches.contains(track.touch) {
      if track.calloutShown, !track.cancelled, track.hasMoved, let index = track.selectedIndex {
        // 松开：把选中的字母作为输入（与 9 键点按同一发送路径：insertText）
        let letter = track.letters[index].lowercased()
        actionHandler.handle(.release, on: .character(letter))
      }
      dismissT9Callout()
    }
    if let touch = touches.first {
      let point = touch.location(in: self)
      if let entry = selectPinyinEntry, entry.button.frame.contains(point) {
        handleSelectPinyinTap()
      }
    }
    super.touchesEnded(touches, with: event)
  }

  override public func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    if let track = t9Track, touches.contains(track.touch) {
      dismissT9Callout()
    }
    super.touchesCancelled(touches, with: event)
  }

  // MARK: - 9 键长按选字母

  override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesBegan(touches, with: event)
    for touch in touches {
      // 新触摸顶掉旧长按（同一时刻只能一个键弹出）
      if let track = t9Track, track.touch != touch {
        dismissT9Callout()
      }
      guard t9Track == nil else { continue }
      let point = touch.location(in: self)
      guard let button = findNearestView(point) as? IOSNativeButton,
            let entry = entries.first(where: { $0.button === button }),
            let letters = t9Letters(for: entry.spec) else { continue }
      let track = T9Track(touch: touch, entry: entry, letters: letters, pressStart: point)
      t9Track = track
      DispatchQueue.main.asyncAfter(deadline: .now() + t9LongPressDelay) { [weak self] in
        guard let self = self, let current = self.t9Track, current === track else { return }
        self.showT9Callout(for: current)
      }
    }
  }

  override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesMoved(touches, with: event)
    guard let track = t9Track,
          let touch = touches.first(where: { $0 == track.touch }) else { return }
    let point = touch.location(in: self)
    if !track.calloutShown {
      // 长按未弹出前手指滑出按键区域（留余量）→ 取消长按
      let expand = track.entry.button.frame.insetBy(dx: -16, dy: -16)
      if !expand.contains(point) {
        cancelT9FourthTimer(track)
        t9Track = nil
      }
      return
    }
    updateT9Selection(track, point: point)
  }

  /// 按键对应的可选字母（.chineseNineGrid 键 / number 面板数字键）
  private func t9Letters(for spec: IOSNativeKey) -> [String]? {
    switch spec.action {
    case .chineseNineGrid(let symbol):
      return IOST9LetterMap.gridKeyLetters[symbol.char]
    case .character(let char):
      return IOST9LetterMap.digitLetters[char]
    default:
      return nil
    }
  }

  /// 长按到时弹出气泡（挂到 superview，允许覆盖候选栏区域，与官方行为一致）
  private func showT9Callout(for track: T9Track) {
    guard window != nil else { return }
    track.calloutShown = true
    // 气泡生效后按键松开不再发普通字符（数字）
    track.entry.button.shouldApplyReleaseAction = false

    let bubble = IOST9CalloutView(letters: track.letters, dark: keyboardContext.hasDarkColorScheme)
    let size = IOST9CalloutView.calloutSize(letterCount: track.letters.count)
    let container = superview ?? self
    let keyFrame = track.entry.button.frame
    let keyFrameInContainer = convert(keyFrame, to: container)
    var x = keyFrameInContainer.midX - size.width / 2
    x = min(max(x, 2), max(2, container.bounds.width - size.width - 2))
    // 默认在按键上方弹出（官方行为）；顶部放不下（首行按键）时改为在按键下方弹出，
    // 避免气泡跑出键盘顶部被裁切（FIX-HMSTR-028：9 键第一行长按看不见）
    let aboveY = keyFrameInContainer.minY - size.height - 6
    let fitsAbove = aboveY >= container.bounds.minY
    let y = fitsAbove ? aboveY : keyFrameInContainer.maxY + 6
    bubble.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
    bubble.updateSelection(index: nil)
    container.addSubview(bubble)
    t9Bubble = bubble
  }

  /// 按手指位置更新选中字母；滑回键上 / 滑出菜单外 = 取消
  private func updateT9Selection(_ track: T9Track, point: CGPoint) {
    guard track.calloutShown, !track.cancelled, let bubble = t9Bubble else { return }
    if hypot(point.x - track.pressStart.x, point.y - track.pressStart.y) >= 8 {
      track.hasMoved = true
    }
    let keyFrame = track.entry.button.frame
    let onKey = keyFrame.contains(point)
    if onKey {
      // 滑回键上 = 取消（手指从未滑出过按键时不算，避免原地抖动误取消）
      if track.hasLeftKey {
        cancelT9Callout(track)
        return
      }
    } else {
      track.hasLeftKey = true
    }

    // 滑出菜单外 = 取消
    let bubbleFrame = bubble.superview == nil ? bubble.frame : convert(bubble.frame, from: bubble.superview!)
    if !bubbleFrame.contains(point) {
      cancelT9Callout(track)
      return
    }

    let dx = point.x - keyFrame.midX
    let dy = point.y - keyFrame.midY
    let threshold: CGFloat = 12
    let upDist = max(0, -dy - threshold)
    let leftDist = max(0, -dx - threshold)
    let rightDist = max(0, dx - threshold)
    let maxDist = max(upDist, max(leftDist, rightDist))

    var index = 0
    if maxDist > 0 {
      if leftDist == maxDist {
        index = 1 // 左滑 = 第二个字母
      } else if rightDist == maxDist {
        index = 2 // 右滑 = 第三个字母
      } else {
        index = 0 // 上滑 = 第一个字母
      }
    }

    // 4 字母键：上滑区域长按 0.3s 选中第四个字母
    if index == 0, upDist > 0 {
      startT9FourthTimer(track)
    } else {
      cancelT9FourthTimer(track)
    }

    track.selectedIndex = index
    bubble.updateSelection(index: index)
  }

  private func startT9FourthTimer(_ track: T9Track) {
    guard track.fourthTimerToken == nil else { return }
    let token = UUID()
    track.fourthTimerToken = token
    DispatchQueue.main.asyncAfter(deadline: .now() + t9FourthLetterDelay) { [weak self] in
      guard let self = self,
            let current = self.t9Track,
            current === track,
            track.fourthTimerToken == token else { return }
      track.fourthTimerToken = nil
      guard track.letters.count == 4 else { return }
      track.selectedIndex = 3
      self.t9Bubble?.updateSelection(index: 3)
    }
  }

  private func cancelT9FourthTimer(_ track: T9Track) {
    track.fourthTimerToken = nil
  }

  private func cancelT9Callout(_ track: T9Track) {
    guard !track.cancelled else { return }
    track.cancelled = true
    cancelT9FourthTimer(track)
    t9Bubble?.removeFromSuperview()
    t9Bubble = nil
  }

  /// 收起气泡并清空跟踪（面板切换 / 失焦 / 触摸结束）
  private func dismissT9Callout() {
    if let track = t9Track {
      cancelT9FourthTimer(track)
    }
    t9Bubble?.removeFromSuperview()
    t9Bubble = nil
    t9Track = nil
  }

  /// 记录上次跳选时的输入串：输入变化则从首个候选重新开始
  private var selectPinyinInputKey = ""

  /// 选拼音键：在候选拼音列表中循环跳选，并替换当前拼音编码
  private func handleSelectPinyinTap() {
    let candidates = rimeContext.getPinyinCandidates()
    guard !candidates.isEmpty else { return }
    let inputKeys = rimeContext.getInputKeys()
    if inputKeys != selectPinyinInputKey {
      selectPinyinIndex = 0
      selectPinyinInputKey = inputKeys
    }
    selectPinyinIndex = (selectPinyinIndex + 1) % candidates.count
    let pinyin = candidates[selectPinyinIndex]
    _ = rimeContext.tryHandleReplaceInputTexts(pinyin, startPos: 0, count: inputKeys.utf8.count)
  }

  // MARK: - 布局

  override public func layoutSubviews() {
    super.layoutSubviews()
    guard bounds.width > 0, bounds.height > 0 else { return }
    if userInterfaceStyle != traitCollection.userInterfaceStyle {
      userInterfaceStyle = traitCollection.userInterfaceStyle
      setupAppearance()
      refreshOverlays()
      updateSeparatorKeyState()
      updateChatSendKeyState()
    }
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





