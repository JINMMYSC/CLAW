//
//  KeyboardToolbarView.swift
//
//  ClawTalk：候选栏 + 功能行（AI / 帮你回 / 超会说 + 眼睛 + 表情 + 下拉）+ 业务面板 + 实时建议条
//
//  功能行按钮：AI(点击=AI面板，长按=deep link 跳键盘设置页) / 帮你回 / 超会说 / 眼睛(隐私) / 表情 / 下拉
//

import Combine
import HamsterKit
import HamsterUIKit
import UIKit

/**
 键盘工具栏

 用于显示：
 1. 候选文字，包含横向部分文字显示及下拉显示全部文字
 2. 常用功能视图（ClawTalk 三入口 + 眼睛 + 表情 + 下拉）
 3. 实时 AI 建议条（右侧空余区域）
 */
class KeyboardToolbarView: NibLessView {
  private let appearance: KeyboardAppearance
  private let actionHandler: KeyboardActionHandler
  private let keyboardContext: KeyboardContext
  private var rimeContext: RimeContext
  private var style: CandidateBarStyle
  private var userInterfaceStyle: UIUserInterfaceStyle
  private var oldBounds: CGRect = .zero
  private var subscriptions = Set<AnyCancellable>()

  /// 最近一次输入状态（空/非空），用于面板收起后恢复候选栏显隐
  private var lastInputEmpty = true

  // MARK: - ClawTalk 入口按钮

  /// 当前聊天对象。全局模式只使用用户全局记忆，不混合多个联系人。
  lazy var contactButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
    // 胶囊按钮统一常态配色：与「帮你回」「超会说」保持一致，选中态才换成强调色底。
    button.setTitleColor(ClawPanelPalette.keyLabel, for: .normal)
    button.backgroundColor = ClawPanelPalette.capsuleNormal
    button.layer.cornerRadius = 15
    button.clipsToBounds = true
    button.showsMenuAsPrimaryAction = true
    refreshContactMenu(on: button)
    return button
  }()

  /// AI 语音助手入口：点击展开 AI 面板；长按 deep link 跳主程序键盘设置页
  /// ClawTalk 风格：红系 / 圆角 / 毛玻璃质感
  lazy var aiButton: ClawGlassButton = {
    let button = ClawGlassButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("AI", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
    button.setTitleColor(.white, for: .normal)
    button.layer.cornerRadius = 17
    button.clipsToBounds = true
    button.glassTintColor = ClawPanelPalette.brandBlue
    button.addTarget(self, action: #selector(aiButtonTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(aiButtonTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(aiButtonLongPressed(_:)))
    longPress.minimumPressDuration = 0.5
    button.addGestureRecognizer(longPress)
    return button
  }()

  /// 帮你回入口（胶囊）
  lazy var helpReplyButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("帮你回", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
    button.setTitleColor(ClawPanelPalette.keyLabel, for: .normal)
    button.backgroundColor = ClawPanelPalette.capsuleNormal
    button.layer.cornerRadius = 15
    button.clipsToBounds = true
    button.addTarget(self, action: #selector(helpReplyTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(helpReplyTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// 超会说入口（胶囊）
  lazy var superTalkButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("超会说", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
    button.setTitleColor(ClawPanelPalette.keyLabel, for: .normal)
    button.backgroundColor = ClawPanelPalette.capsuleNormal
    button.layer.cornerRadius = 15
    button.clipsToBounds = true
    button.addTarget(self, action: #selector(superTalkTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(superTalkTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// 眼睛按钮：隐私采集开关（原长按 AI 更多页，现移到功能行、表情按钮之前）
  lazy var eyeButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "eye"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = ClawPanelPalette.deepBlue
    button.backgroundColor = .clear
    button.addTarget(self, action: #selector(eyeButtonTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(eyeButtonTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// 表情按钮：打开表情键盘（表情按钮之前为眼睛按钮）
  lazy var emojiButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "face.smiling"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = ClawPanelPalette.deepBlue
    button.backgroundColor = .clear
    button.addTarget(self, action: #selector(emojiButtonTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(emojiButtonTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// 下拉按钮：收起键盘（功能行最右）
  lazy var dismissKeyboardButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "chevron.down.circle"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = ClawPanelPalette.deepBlue
    button.backgroundColor = .clear
    button.addTarget(self, action: #selector(dismissKeyboardTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(dismissKeyboardTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// 常驻“…”入口：保留低频但重要的 CLAW/语音/设置动作。
  lazy var moreButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = ClawPanelPalette.deepBlue
    button.showsMenuAsPrimaryAction = true
    button.accessibilityLabel = "更多工具"
    refreshMoreMenu(on: button)
    return button
  }()

  /// 候选词出现时仍常驻右侧的“…”入口，避免必须先退出候选再操作。
  /// 眼睛/表情/收起这三个动作和上方功能行重复，不再在候选区重复一遍。
  lazy var candidateEyeButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "eye"), for: .normal)
    button.tintColor = ClawPanelPalette.deepBlue
    button.addTarget(self, action: #selector(candidateEyeTapped), for: .touchUpInside)
    return button
  }()

  lazy var candidateEmojiButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "face.smiling"), for: .normal)
    button.tintColor = ClawPanelPalette.deepBlue
    button.addTarget(self, action: #selector(candidateEmojiTapped), for: .touchUpInside)
    return button
  }()

  lazy var candidateDismissButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "chevron.down.circle"), for: .normal)
    button.tintColor = ClawPanelPalette.deepBlue
    button.addTarget(self, action: #selector(candidateDismissTapped), for: .touchUpInside)
    return button
  }()

  lazy var candidateMoreButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
    button.tintColor = ClawPanelPalette.deepBlue
    button.showsMenuAsPrimaryAction = true
    button.accessibilityLabel = "更多工具"
    refreshMoreMenu(on: button)
    return button
  }()

  /// 候选行右侧只保留收起键盘按钮。
  /// 按规格：打字时应用图标那一组不显示，候选行只留候选词与最右侧的 `⌄`。
  lazy var candidateQuickToolsBar: UIStackView = {
    let stack = UIStackView(arrangedSubviews: [candidateDismissButton])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .horizontal
    stack.alignment = .fill
    stack.distribution = .fillEqually
    stack.spacing = 0
    stack.isHidden = true
    return stack
  }()

  /// 功能行容器
  lazy var commonFunctionBar: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  /// 业务面板覆盖层（AI语音助手 / 帮你回 / 超会说）
  lazy var panelOverlayView: ClawPanelOverlayView = {
    let view = ClawPanelOverlayView(
      appearance: appearance,
      actionHandler: actionHandler,
      keyboardContext: keyboardContext
    )
    view.translatesAutoresizingMaskIntoConstraints = false
    view.isHidden = true
    return view
  }()

  /// 实时 AI 建议条（候选栏右侧空余区域）
  lazy var suggestionBarView: ClawSuggestionStripView = {
    let view = ClawSuggestionStripView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.isHidden = true
    view.onSend = { text in
      ClawPanelInputBridge.shared.send(text)
    }
    view.onCopy = { text in
      UIPasteboard.general.string = text
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    return view
  }()

  /// 候选文字视图
  lazy var candidateBarView: CandidateBarView = {
    let view = CandidateBarView(
      style: style,
      actionHandler: actionHandler,
      keyboardContext: keyboardContext,
      rimeContext: rimeContext
    )
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  init(appearance: KeyboardAppearance, actionHandler: KeyboardActionHandler, keyboardContext: KeyboardContext, rimeContext: RimeContext) {
    self.appearance = appearance
    self.actionHandler = actionHandler
    self.keyboardContext = keyboardContext
    self.rimeContext = rimeContext
    // KeyboardToolbarView 为 candidateBarStyle 样式根节点, 这里生成一次，减少计算次数
    self.style = appearance.candidateBarStyle
    self.userInterfaceStyle = keyboardContext.colorScheme

    super.init(frame: .zero)

    setupSubview()

    combine()
  }

  func setupSubview() {
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    if userInterfaceStyle != keyboardContext.colorScheme {
      userInterfaceStyle = keyboardContext.colorScheme
      setupAppearance()
      candidateBarView.setStyle(self.style)
    }

    updateSuggestionBarHeight()
  }

  // MARK: - 视图层次

  override func constructViewHierarchy() {
    addSubview(panelOverlayView)
    addSubview(suggestionBarView)
    addSubview(candidateBarView)
    addSubview(candidateQuickToolsBar)
    addSubview(commonFunctionBar)
    commonFunctionBar.addSubview(contactButton)
    commonFunctionBar.addSubview(helpReplyButton)
    commonFunctionBar.addSubview(superTalkButton)
    commonFunctionBar.addSubview(aiButton)
    // 用户高频使用的次要动作直接展示，不再藏进“…”菜单。
    commonFunctionBar.addSubview(eyeButton)
    commonFunctionBar.addSubview(emojiButton)
    commonFunctionBar.addSubview(moreButton)
    commonFunctionBar.addSubview(dismissKeyboardButton)
  }

  private var panelHeightConstraint: NSLayoutConstraint!
  private var commonBarTopConstraint: NSLayoutConstraint!
  private var suggestionBarHeightConstraint: NSLayoutConstraint!
  /// 候选栏收起时贴在功能行那一条；展开时改为吃掉功能行上方的全部高度。
  private var candidateTopToFunctionBar: NSLayoutConstraint!
  private var candidateTopToPanel: NSLayoutConstraint!

  override func activateViewConstraints() {
    // 面板覆盖层：固定在工具栏顶部，高度随展开/收起变化
    panelHeightConstraint = panelOverlayView.heightAnchor.constraint(equalToConstant: 0)
    panelHeightConstraint.priority = .defaultHigh

    commonBarTopConstraint = commonFunctionBar.topAnchor.constraint(equalTo: panelOverlayView.bottomAnchor)

    suggestionBarHeightConstraint = suggestionBarView.heightAnchor.constraint(equalToConstant: 0)

    // 候选栏展开时，KeyboardRootView 会把整条工具栏加高（键区高度 + 工具栏高度）。
    // 之前候选栏被钉死在功能行那一条 50pt 内，多出来的高度变成空白，所以只能看到一行。
    candidateTopToFunctionBar = candidateBarView.topAnchor.constraint(equalTo: commonFunctionBar.topAnchor)
    candidateTopToPanel = candidateBarView.topAnchor.constraint(equalTo: panelOverlayView.bottomAnchor)
    candidateTopToPanel.isActive = false

    NSLayoutConstraint.activate([
      panelOverlayView.topAnchor.constraint(equalTo: topAnchor),
      panelOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
      panelOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
      panelHeightConstraint,

      commonBarTopConstraint,
      commonFunctionBar.bottomAnchor.constraint(equalTo: bottomAnchor),
      commonFunctionBar.leadingAnchor.constraint(equalTo: leadingAnchor),
      commonFunctionBar.trailingAnchor.constraint(equalTo: trailingAnchor),
      commonFunctionBar.heightAnchor.constraint(equalToConstant: keyboardContext.heightOfToolbar),

      candidateQuickToolsBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
      candidateQuickToolsBar.topAnchor.constraint(equalTo: commonFunctionBar.topAnchor),
      candidateQuickToolsBar.bottomAnchor.constraint(equalTo: commonFunctionBar.bottomAnchor),
      candidateQuickToolsBar.widthAnchor.constraint(equalToConstant: 40),

      candidateTopToFunctionBar,
      candidateBarView.bottomAnchor.constraint(equalTo: commonFunctionBar.bottomAnchor),
      candidateBarView.leadingAnchor.constraint(equalTo: leadingAnchor),
      candidateBarView.trailingAnchor.constraint(equalTo: candidateQuickToolsBar.leadingAnchor, constant: -2),

      suggestionBarView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
      suggestionBarView.topAnchor.constraint(equalTo: panelOverlayView.bottomAnchor, constant: 6),
      suggestionBarHeightConstraint,
      suggestionBarView.widthAnchor.constraint(equalToConstant: 150),

      contactButton.leadingAnchor.constraint(equalTo: commonFunctionBar.leadingAnchor, constant: 6),
      contactButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      contactButton.widthAnchor.constraint(equalToConstant: 64),
      contactButton.heightAnchor.constraint(equalToConstant: 30),

      helpReplyButton.leadingAnchor.constraint(equalTo: contactButton.trailingAnchor, constant: 3),
      helpReplyButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      helpReplyButton.widthAnchor.constraint(equalToConstant: 60),
      helpReplyButton.heightAnchor.constraint(equalToConstant: 30),

      superTalkButton.leadingAnchor.constraint(equalTo: helpReplyButton.trailingAnchor, constant: 3),
      superTalkButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      superTalkButton.widthAnchor.constraint(equalToConstant: 60),
      superTalkButton.heightAnchor.constraint(equalToConstant: 30),

      aiButton.leadingAnchor.constraint(equalTo: superTalkButton.trailingAnchor, constant: 3),
      aiButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      aiButton.widthAnchor.constraint(equalToConstant: 32),
      aiButton.heightAnchor.constraint(equalToConstant: 32),

      eyeButton.leadingAnchor.constraint(equalTo: aiButton.trailingAnchor, constant: 3),
      eyeButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      eyeButton.widthAnchor.constraint(equalToConstant: 26),
      eyeButton.heightAnchor.constraint(equalToConstant: 30),

      emojiButton.leadingAnchor.constraint(equalTo: eyeButton.trailingAnchor, constant: 3),
      emojiButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      emojiButton.widthAnchor.constraint(equalToConstant: 26),
      emojiButton.heightAnchor.constraint(equalToConstant: 30),

      moreButton.leadingAnchor.constraint(equalTo: emojiButton.trailingAnchor, constant: 3),
      moreButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      moreButton.widthAnchor.constraint(equalToConstant: 26),
      moreButton.heightAnchor.constraint(equalToConstant: 30),
    ])

    NSLayoutConstraint.activate([
      dismissKeyboardButton.leadingAnchor.constraint(equalTo: moreButton.trailingAnchor, constant: 3),
      dismissKeyboardButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      dismissKeyboardButton.widthAnchor.constraint(equalToConstant: 26),
      dismissKeyboardButton.heightAnchor.constraint(equalToConstant: 30),
      dismissKeyboardButton.trailingAnchor.constraint(lessThanOrEqualTo: commonFunctionBar.trailingAnchor, constant: -4),
    ])
  }

  // MARK: - 外观

  override func setupAppearance() {
    // 面板配色跟随当前键盘主题
    ClawPanelPalette.sync(with: keyboardContext)
    self.style = appearance.candidateBarStyle
    // 工具栏/功能行背景跟随主题（IOS 原生布局时与键盘板同色）
    if keyboardContext.useIOSNativeLayout {
      let palette = IOSNativePalette.current(dark: keyboardContext.hasDarkColorScheme)
      backgroundColor = palette.board
      commonFunctionBar.backgroundColor = palette.board
      candidateBarView.backgroundColor = palette.board
      eyeButton.tintColor = palette.textDark
      emojiButton.tintColor = palette.textDark
      contactButton.setTitleColor(palette.textDark, for: .normal)
      contactButton.backgroundColor = palette.toolbarControl
      dismissKeyboardButton.tintColor = palette.textDark
      candidateEyeButton.tintColor = palette.textDark
      candidateEmojiButton.tintColor = palette.textDark
      candidateMoreButton.tintColor = palette.textDark
      candidateDismissButton.tintColor = palette.textDark
      moreButton.tintColor = palette.textDark
    } else {
      backgroundColor = ClawPanelPalette.toolbarBackground
      commonFunctionBar.backgroundColor = .clear
    }
    candidateBarView.setStyle(self.style)
    candidateBarView.backgroundColor = backgroundColor

    updateEntryButtonStates()
    updateEyeButtonState()
  }

  /// 三入口按钮选中态（跟随当前面板 + 主题取色）
  func updateEntryButtonStates() {
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
      contactButton.backgroundColor = palette.toolbarControl
      contactButton.setTitleColor(palette.textDark, for: .normal)
      dismissKeyboardButton.tintColor = palette.textDark
      moreButton.tintColor = palette.textDark
      return
    }
    let aiSelected = tab == 0
    aiButton.glassTintColor = aiSelected ? ClawPanelPalette.brandBlue : ClawPanelPalette.aiCircle
    aiButton.setTitleColor(aiSelected ? .white : ClawPanelPalette.deepBlue, for: .normal)

    // 「全局」也需要跟随刷新，否则会停在初始化时的颜色，与另外两个胶囊不一致。
    contactButton.backgroundColor = ClawPanelPalette.capsuleNormal
    contactButton.setTitleColor(ClawPanelPalette.keyLabel, for: .normal)

    let helpSelected = tab == 1
    helpReplyButton.backgroundColor = helpSelected ? ClawPanelPalette.capsuleSelected : ClawPanelPalette.capsuleNormal
    helpReplyButton.setTitleColor(helpSelected ? ClawPanelPalette.currentColors.accentForeground : ClawPanelPalette.keyLabel, for: .normal)

    let superSelected = tab == 2
    superTalkButton.backgroundColor = superSelected ? ClawPanelPalette.capsuleSelected : ClawPanelPalette.capsuleNormal
    superTalkButton.setTitleColor(superSelected ? ClawPanelPalette.currentColors.accentForeground : ClawPanelPalette.keyLabel, for: .normal)
  }

  /// 眼睛按钮状态（隐私采集开/关）
  func updateEyeButtonState() {
    let collecting = ClawTalkPrivacyService.shared.isCollectionEnabled
    eyeButton.setImage(UIImage(systemName: collecting ? "eye" : "eye.slash"), for: .normal)
    candidateEyeButton.setImage(UIImage(systemName: collecting ? "eye" : "eye.slash"), for: .normal)
    if keyboardContext.useIOSNativeLayout {
      let palette = IOSNativePalette.current(dark: keyboardContext.hasDarkColorScheme)
      eyeButton.tintColor = collecting ? palette.textDark : .systemOrange
      candidateEyeButton.tintColor = collecting ? palette.textDark : .systemOrange
    } else {
      eyeButton.tintColor = collecting ? ClawPanelPalette.deepBlue : .systemOrange
      candidateEyeButton.tintColor = collecting ? ClawPanelPalette.deepBlue : .systemOrange
    }
  }

  /// 实时建议条显隐：有建议 + 面板收起 + 有输入时显示
  func updateSuggestionBarVisibility() {
    let hasSuggestions = !ClawSuggestionEngine.shared.suggestions.isEmpty
    let panelExpanded = keyboardContext.clawPanelTab >= 0
    let show = hasSuggestions && !panelExpanded && !lastInputEmpty
    suggestionBarView.isHidden = !show
    updateSuggestionBarHeight()
  }

  /// 建议条高度：候选栏右侧空余区域，最高 120pt
  private func updateSuggestionBarHeight() {
    let panelHeight = ClawPanelOverlayView.preferredHeight(for: keyboardContext.clawPanelTab)
    let available = max(0, bounds.height - keyboardContext.heightOfToolbar - panelHeight - 12)
    let show = !ClawSuggestionEngine.shared.suggestions.isEmpty && keyboardContext.clawPanelTab < 0 && !lastInputEmpty
    suggestionBarHeightConstraint.constant = show ? min(max(available, 0), 120) : 0
  }

  // MARK: - 状态联动

  func combine() {
    // 候选栏展开/收起：切换候选栏的上边界。
    // 收起时贴在功能行那一条；展开时从面板层下沿一直延伸，用满多出来的高度。
    keyboardContext.$candidatesViewState
      .receive(on: DispatchQueue.main)
      .sink { [weak self] state in
        guard let self else { return }
        let expanded = !state.isCollapse()
        self.candidateTopToFunctionBar?.isActive = !expanded
        self.candidateTopToPanel?.isActive = expanded
        self.layoutIfNeeded()
      }
      .store(in: &subscriptions)

    rimeContext.userInputKeyPublished
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in
        guard let self = self else { return }
        let isEmpty = $0.isEmpty
        self.lastInputEmpty = isEmpty
        self.commonFunctionBar.isHidden = !isEmpty
        self.candidateBarView.isHidden = isEmpty
        self.candidateQuickToolsBar.isHidden = isEmpty
        self.updateSuggestionBarVisibility()

        // 检测是否启用内嵌编码
        guard !keyboardContext.enableEmbeddedInputMode else { return }
        if self.keyboardContext.keyboardType.isChineseNineGrid {
          candidateBarView.phoneticLabel.text = self.rimeContext.t9UserInputKey
        } else {
          candidateBarView.phoneticLabel.text = $0
        }
      }
      .store(in: &subscriptions)

    // 面板展开/收起：控制覆盖层高度与键盘总高（配合 KeyboardRootView 联动）
    keyboardContext.$clawPanelTab
      .receive(on: DispatchQueue.main)
      .sink { [weak self] tab in
        guard let self else { return }
        let expanded = tab >= 0
        self.panelOverlayView.isHidden = !expanded
        // 面板展开时功能行保持显示，候选栏不遮挡面板
        if expanded {
          self.commonFunctionBar.isHidden = false
          self.candidateBarView.isHidden = true
          self.candidateQuickToolsBar.isHidden = true
        } else {
          self.commonFunctionBar.isHidden = !self.lastInputEmpty
          self.candidateBarView.isHidden = self.lastInputEmpty
          self.candidateQuickToolsBar.isHidden = self.lastInputEmpty
        }
        self.updateEntryButtonStates()
        self.updateSuggestionBarVisibility()
        let target = ClawPanelOverlayView.preferredHeight(for: tab)
        self.panelHeightConstraint.constant = target
        self.layoutIfNeeded()
      }
      .store(in: &subscriptions)

    // 实时建议：引擎输出 → 建议条
    ClawSuggestionEngine.shared.$suggestions
      .receive(on: DispatchQueue.main)
      .sink { [weak self] suggestions in
        guard let self else { return }
        self.suggestionBarView.update(suggestions: suggestions)
        self.updateSuggestionBarVisibility()
      }
      .store(in: &subscriptions)

    // 隐私状态变化 → 眼睛按钮图标刷新
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(privacyDidChange),
      name: .clawPrivacyDidChange,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(heartTargetsDidChange),
      name: .heartTargetProfilesDidChange,
      object: nil
    )
  }

  @objc private func privacyDidChange() {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.updateEyeButtonState()
      self.refreshMoreMenu(on: self.moreButton)
      self.refreshMoreMenu(on: self.candidateMoreButton)
    }
  }

  @objc private func heartTargetsDidChange() {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.refreshContactMenu(on: self.contactButton)
    }
  }

  private func refreshContactMenu(on button: UIButton) {
    let service = HeartTargetService.shared
    let selected = service.selectedProfile
    button.setTitle(selected.map { "👤 \($0.displayName)" } ?? "👤 全局", for: .normal)
    var actions: [UIAction] = [
      UIAction(title: "全局（不混联系人）", state: selected == nil ? .on : .off) { _ in
        service.clearSelection()
      },
    ]
    actions.append(contentsOf: service.profiles.map { profile in
      UIAction(title: profile.displayName, state: selected?.id == profile.id ? .on : .off) { _ in
        service.select(id: profile.id)
      }
    })
    button.menu = UIMenu(title: "当前聊天对象", children: actions)
  }

  private func refreshMoreMenu(on button: UIButton) {
    let collecting = ClawTalkPrivacyService.shared.isCollectionEnabled
    let openAssistant = UIAction(title: "打开 CLAW 助手", image: UIImage(systemName: "sparkles")) { [weak self] _ in
      guard let self else { return }
      self.actionHandler.handle(
        .release,
        on: .url(URL(string: HamsterConstants.appURLForGuru), id: "openClawAssistant")
      )
    }
    let voiceCall = UIAction(title: "语音通话", image: UIImage(systemName: "phone.fill")) { [weak self] _ in
      guard let self else { return }
      self.actionHandler.handle(
        .release,
        on: .url(URL(string: HamsterConstants.appURLForGuruVoice), id: "openClawVoiceCall")
      )
    }
    let privacy = UIAction(
      title: collecting ? "暂停输入记录" : "恢复输入记录",
      image: UIImage(systemName: collecting ? "eye.slash" : "eye")
    ) { [weak self] _ in
      ClawTalkPrivacyService.shared.toggle()
      self?.updateEyeButtonState()
      if let self {
        self.refreshMoreMenu(on: self.moreButton)
        self.refreshMoreMenu(on: self.candidateMoreButton)
      }
    }
    let settings = UIAction(title: "键盘设置", image: UIImage(systemName: "gearshape")) { [weak self] _ in
      guard let self else { return }
      self.actionHandler.handle(
        .release,
        on: .url(URL(string: HamsterConstants.appURLForKeyboardSettings), id: "openKeyboardSettings")
      )
    }
    button.menu = UIMenu(children: [openAssistant, voiceCall, privacy, settings])
  }

  // MARK: - 按钮动作

  @objc func dismissKeyboardTouchDownAction() {
    pressButton(dismissKeyboardButton)
  }

  @objc func dismissKeyboardTouchUpAction() {
    unpressButton(dismissKeyboardButton)
    actionHandler.handle(.release, on: .dismissKeyboard)
  }

  @objc func aiButtonTouchDownAction() {
    pressButton(aiButton)
  }

  @objc func aiButtonTouchUpAction() {
    unpressButton(aiButton)
    keyboardContext.clawPanelTab = 0
  }

  @objc func aiButtonLongPressed(_ sender: UILongPressGestureRecognizer) {
    guard sender.state == .began else { return }
    // 长按 AI：从键盘快捷助手无缝续接到主 App 的完整 CLAW 助手。
    actionHandler.handle(
      .release,
      on: .url(URL(string: HamsterConstants.appURLForGuru), id: "openClawAssistant")
    )
  }

  @objc func helpReplyTouchDownAction() {
    pressButton(helpReplyButton)
  }

  @objc func helpReplyTouchUpAction() {
    unpressButton(helpReplyButton)
    keyboardContext.clawPanelTab = 1
  }

  @objc func superTalkTouchDownAction() {
    pressButton(superTalkButton)
  }

  @objc func superTalkTouchUpAction() {
    unpressButton(superTalkButton)
    keyboardContext.clawPanelTab = 2
  }

  @objc func eyeButtonTouchDownAction() {
    pressButton(eyeButton)
  }

  @objc func eyeButtonTouchUpAction() {
    unpressButton(eyeButton)
    ClawTalkPrivacyService.shared.toggle()
    updateEyeButtonState()
  }

  @objc func emojiButtonTouchDownAction() {
    pressButton(emojiButton)
  }

  @objc func emojiButtonTouchUpAction() {
    unpressButton(emojiButton)
    if keyboardContext.keyboardType == .emojis {
      keyboardContext.setKeyboardType(keyboardContext.selectKeyboard)
    } else {
      keyboardContext.setKeyboardType(.emojis)
    }
  }

  @objc private func candidateEyeTapped() {
    ClawTalkPrivacyService.shared.toggle()
    updateEyeButtonState()
  }

  @objc private func candidateEmojiTapped() {
    emojiButtonTouchUpAction()
  }

  @objc private func candidateDismissTapped() {
    actionHandler.handle(.release, on: .dismissKeyboard)
  }

  private func pressButton(_ button: UIButton) {
    UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
      button.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
    }
  }

  private func unpressButton(_ button: UIButton) {
    UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
      button.transform = .identity
    }
  }

  @objc func touchCancel() {
    [contactButton, aiButton, helpReplyButton, superTalkButton, eyeButton, emojiButton, moreButton, dismissKeyboardButton].forEach { button in
      button.transform = .identity
    }
  }
}
