import Combine
import HamsterKit
import PhotosUI
import UIKit

// MARK: - UIView 辅助：沿 responder 链找所属视图控制器

extension UIView {
  var clawParentViewController: UIViewController? {
    var responder: UIResponder? = self
    while let r = responder {
      if let vc = r as? UIViewController { return vc }
      responder = r.next
    }
    return nil
  }
}

// MARK: - 业务面板覆盖层（AI语音助手 / 帮你回 / 超会说）

public final class ClawPanelOverlayView: UIView {
  /// 键盘 AI 面板分档高度。任何 tab 都不会膨胀成半屏聊天窗口。
  public static let compactHeight: CGFloat = 140
  public static let normalHeight: CGFloat = 175
  public static let expandedHeight: CGFloat = 205

  public static func preferredHeight(for tab: Int) -> CGFloat {
    switch tab {
    case PanelTab.ai.rawValue: return expandedHeight
    case PanelTab.helpReply.rawValue: return normalHeight
    case PanelTab.superTalk.rawValue: return 160
    default: return 0
    }
  }

  enum PanelTab: Int {
    case ai = 0
    case helpReply = 1
    case superTalk = 2
  }

  private let keyboardContext: KeyboardContext
  private let actionHandler: KeyboardActionHandler
  private var subscriptions = Set<AnyCancellable>()

  // 标题
  private let titleLabel = UILabel()
  private let closeButton = UIButton(type: .system)
  private let screenshotButton = UIButton(type: .system)
  private let styleButton = UIButton(type: .system)

  private enum ToneStyle: String, CaseIterable {
    case likeMe
    case natural
    case concise
    case considerate
    case formal
    case humorous

    var title: String {
      switch self {
      case .likeMe: return "更像我"
      case .natural: return "自然"
      case .concise: return "简短"
      case .considerate: return "有分寸"
      case .formal: return "正式"
      case .humorous: return "幽默"
      }
    }

    var instruction: String {
      switch self {
      case .likeMe: return "优先模仿用户长期确认过的表达习惯与最终修改版本。"
      case .natural: return "表达自然口语化，不要模板腔。"
      case .concise: return "尽量压缩到最少必要文字，直接表达核心意思。"
      case .considerate: return "语气有分寸，照顾对方感受，但不要过度讨好。"
      case .formal: return "语气专业、清晰、正式，但避免官话。"
      case .humorous: return "允许轻度幽默和松弛感，但不要油腻或冒犯。"
      }
    }
  }

  private var selectedToneStyle: ToneStyle = .likeMe

  // 内容区（按 tab 切换）

  // 输入区：多行可滚动输入框 + 语音按钮 + 动作按钮
  private let inputRow = UIView()
  private let inputTextView = UITextView()
  private let micButton = UIButton(type: .system)
  private let actionButton = UIButton(type: .system)
  private let phoneButton = UIButton(type: .system)

  // 结果展示：可滚动/可选中复制 + 复制按钮
  private let resultTextView = UITextView()
  private let copyButton = UIButton(type: .system)
  /// “帮你回”专用多候选卡。与“超会说”的单结果视图分开，避免三个 tab 只是换标题。
  private let replyCandidatesScrollView = UIScrollView()
  private let replyCandidatesStack = UIStackView()
  private var replyCandidatesHeightConstraint: NSLayoutConstraint!
  private var currentReplyCandidates: [String] = []
  private var lastAnalysisInput = ""
  private var currentExperimentVariantID: String?
  /// 每次分析的请求标识，用于丢弃被替换或已关闭面板的过期结果。
  private var currentAnalysisRequestID = UUID()

  // 实时建议条（右侧空余区域）
  private let suggestionStrip = ClawSuggestionStripView()
  private var suggestionStripWidthConstraint: NSLayoutConstraint!

  // 聊天对象
  private let heartTargetButton = UIButton(type: .system)

  // AI tab: DeepSeek voice chat list
  private let chatListView = UIScrollView()
  private let chatStackView = UIStackView()
  private let newChatButton = UIButton(type: .system)
  private let speakToggleButton = UIButton(type: .system)
  private var chatListHeightConstraint: NSLayoutConstraint!
  private var chatListBottomToInput: NSLayoutConstraint!
  private var inputRowHeightConstraint: NSLayoutConstraint!
  private var inputRowTopToTitle: NSLayoutConstraint!
  private var inputRowTopToChatList: NSLayoutConstraint!
  private var inputRowBottomToPanel: NSLayoutConstraint!
  private var resultBottomToHeart: NSLayoutConstraint!
  private var resultMinHeight: NSLayoutConstraint!
  private var resultHeightZero: NSLayoutConstraint!
  private var heartHeightConstraint: NSLayoutConstraint!
  private var suggestionBottomToHeart: NSLayoutConstraint!
  private var suggestionHeightZero: NSLayoutConstraint!
  private var micLeadingToPhone: NSLayoutConstraint!
  private var micLeadingToText: NSLayoutConstraint!

  // 语音起伏动画条（录音中 / 空会话时显示）
  private let aiWaveContainer = UIView()
  private var barStack: [UIView] = []
  private var waveHeightConstraint: NSLayoutConstraint!
  /// 波形条顶部钉标题（聊天列表显示时的默认位置）
  private var aiWaveTopToTitle: NSLayoutConstraint!
  /// 波形条垂直居中面板（空会话波形条模式）
  private var aiWaveCenterY: NSLayoutConstraint!

  // AI 分析状态
  private var isLoading = false
  // 语音状态
  private var isMicHeld = false
  private var isListening = false
  // 实时通话（方案 A）状态
  private var isCallActive = false
  private var pendingCallSegments: [String] = []

  /// 当前面板是否为 AI 语音助手 tab
  private var isAITab: Bool { keyboardContext.clawPanelTab == PanelTab.ai.rawValue }

  // AI tab 布局常量
  private enum AILayout {
    static let inputRowHeight: CGFloat = 48
    static let waveHeight: CGFloat = 40
    static let bubbleMinWidth: CGFloat = 120
    static let bubbleMaxWidth: CGFloat = 260
  }

  public init(
    appearance: KeyboardAppearance,
    actionHandler: KeyboardActionHandler,
    keyboardContext: KeyboardContext
  ) {
    self.actionHandler = actionHandler
    self.keyboardContext = keyboardContext
    super.init(frame: .zero)

    setupViews()
    setupConstraints()
    bind()

    keyboardContext.$clawPanelTab
      .receive(on: DispatchQueue.main)
      .sink { [weak self] tab in
        if tab < 0 {
          self?.inputTextView.resignFirstResponder()
          ClawVoiceInputService.shared.stop()
          ClawChatService.shared.stopSpeaking()
          self?.stopCallIfActive()
          self?.stopWaveAnimation()
          self?.aiWaveContainer.isHidden = true
        }
        self?.refresh(for: tab)
      }
      .store(in: &subscriptions)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - 视图构建

  private func setupViews() {
    backgroundColor = .clear

    // 主题卡片
    layer.cornerRadius = 20
    layer.masksToBounds = true
    backgroundColor = ClawPanelPalette.keyWhite

    titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
    titleLabel.textColor = ClawPanelPalette.titleBlue
    titleLabel.text = "AI语音助手"

    closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
    closeButton.tintColor = ClawPanelPalette.titleBlue
    closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

    screenshotButton.setImage(UIImage(systemName: "photo.on.rectangle"), for: .normal)
    screenshotButton.tintColor = ClawPanelPalette.brandBlue
    screenshotButton.accessibilityLabel = "导入聊天截图"
    screenshotButton.addTarget(self, action: #selector(screenshotTapped), for: .touchUpInside)

    styleButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
    styleButton.setTitleColor(ClawPanelPalette.deepBlue, for: .normal)
    styleButton.backgroundColor = ClawPanelPalette.capsuleNormal
    styleButton.layer.cornerRadius = 10
    styleButton.showsMenuAsPrimaryAction = true
    refreshStyleMenu()

    newChatButton.setTitle("新对话", for: .normal)
    newChatButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
    newChatButton.setTitleColor(ClawPanelPalette.deepBlue, for: .normal)
    newChatButton.addTarget(self, action: #selector(newChatTapped), for: .touchUpInside)

    speakToggleButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
    speakToggleButton.setTitleColor(ClawPanelPalette.deepBlue, for: .normal)
    speakToggleButton.addTarget(self, action: #selector(speakToggleTapped), for: .touchUpInside)
    updateSpeakToggleTitle()

    // 语音起伏动画条：9 根蓝色竖条（录音中/空会话时显示）
    for _ in 0..<9 {
      let bar = UIView()
      bar.backgroundColor = ClawPanelPalette.brandBlue
      bar.layer.cornerRadius = 2.5
      bar.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin]
      aiWaveContainer.addSubview(bar)
      barStack.append(bar)
    }
    aiWaveContainer.isHidden = true

    // AI chat list: vertical bubble stack inside a scroll view
    chatListView.alwaysBounceVertical = true
    chatListView.showsVerticalScrollIndicator = false
    chatListView.translatesAutoresizingMaskIntoConstraints = false
    chatStackView.axis = .vertical
    chatStackView.spacing = 6
    chatStackView.alignment = .fill
    chatStackView.translatesAutoresizingMaskIntoConstraints = false
    chatListView.addSubview(chatStackView)


    // 多行可滚动输入框：键盘按键直输（inputView 置空禁系统键盘，保留长按粘贴菜单）
    inputTextView.font = .systemFont(ofSize: 15)
    inputTextView.textColor = ClawPanelPalette.candidateText
    inputTextView.backgroundColor = ClawPanelPalette.inputBackground
    inputTextView.layer.cornerRadius = 10
    inputTextView.layer.masksToBounds = true
    inputTextView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
    inputTextView.isScrollEnabled = true
    inputTextView.alwaysBounceVertical = false
    inputTextView.inputView = UIView()
    inputTextView.delegate = self

    micButton.setImage(UIImage(systemName: "mic.fill"), for: .normal)
    micButton.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 16), scale: .default), forImageIn: .normal)
    micButton.tintColor = ClawPanelPalette.brandBlue
    micButton.backgroundColor = ClawPanelPalette.inputBackground
    micButton.layer.cornerRadius = 18
    micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)
    let micLongPress = UILongPressGestureRecognizer(target: self, action: #selector(micLongPressed(_:)))
    micLongPress.minimumPressDuration = 0.3
    micButton.addGestureRecognizer(micLongPress)

    phoneButton.setImage(UIImage(systemName: "phone.fill"), for: .normal)
    phoneButton.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 15), scale: .default), forImageIn: .normal)
    phoneButton.tintColor = ClawPanelPalette.brandBlue
    phoneButton.backgroundColor = ClawPanelPalette.inputBackground
    phoneButton.layer.cornerRadius = 18
    phoneButton.addTarget(self, action: #selector(phoneTapped), for: .touchUpInside)

    actionButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
    actionButton.setTitleColor(.white, for: .normal)
    actionButton.backgroundColor = ClawPanelPalette.brandBlue
    actionButton.layer.cornerRadius = 10
    actionButton.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(actionButtonLongPressed(_:)))
    longPress.minimumPressDuration = 0.5
    actionButton.addGestureRecognizer(longPress)

    // 结果区：可滚动、可选中复制
    resultTextView.font = .systemFont(ofSize: 13)
    resultTextView.textColor = ClawPanelPalette.candidateText
    resultTextView.backgroundColor = .clear
    resultTextView.isEditable = false
    resultTextView.isSelectable = true
    resultTextView.isScrollEnabled = true
    resultTextView.textContainerInset = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 44)
    resultTextView.isHidden = true

    replyCandidatesScrollView.showsHorizontalScrollIndicator = false
    replyCandidatesScrollView.alwaysBounceHorizontal = true
    replyCandidatesScrollView.isHidden = true
    replyCandidatesStack.axis = .horizontal
    replyCandidatesStack.alignment = .fill
    replyCandidatesStack.spacing = 8
    replyCandidatesStack.translatesAutoresizingMaskIntoConstraints = false
    replyCandidatesScrollView.addSubview(replyCandidatesStack)

    copyButton.setTitle("插入", for: .normal)
    copyButton.setTitleColor(ClawPanelPalette.brandBlue, for: .normal)
    copyButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
    copyButton.backgroundColor = ClawPanelPalette.capsuleNormal
    copyButton.layer.cornerRadius = 10
    copyButton.layer.masksToBounds = true
    copyButton.isHidden = true
    copyButton.addTarget(self, action: #selector(copyResultTapped), for: .touchUpInside)

    suggestionStrip.onSend = { text in
      ClawPanelInputBridge.shared.send(text)
    }
    suggestionStrip.onCopy = { text in
      UIPasteboard.general.string = text
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    suggestionStrip.isHidden = true

    heartTargetButton.setTitleColor(ClawPanelPalette.deepBlue, for: .normal)
    heartTargetButton.titleLabel?.font = .systemFont(ofSize: 13)
    heartTargetButton.showsMenuAsPrimaryAction = true
    refreshHeartTargetMenu()
  }

  private func setupConstraints() {
    [titleLabel, closeButton, screenshotButton, styleButton, aiWaveContainer, inputRow, resultTextView, copyButton, replyCandidatesScrollView, suggestionStrip, heartTargetButton, chatListView, newChatButton, speakToggleButton].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      addSubview($0)
    }
    [inputTextView, phoneButton, micButton, actionButton].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      inputRow.addSubview($0)
    }

    suggestionStripWidthConstraint = suggestionStrip.widthAnchor.constraint(equalToConstant: 0)
    replyCandidatesHeightConstraint = replyCandidatesScrollView.heightAnchor.constraint(equalToConstant: 0)
    chatListHeightConstraint = chatListView.heightAnchor.constraint(equalToConstant: 0)
    chatListBottomToInput = chatListView.bottomAnchor.constraint(equalTo: inputRow.topAnchor, constant: -6)
    inputRowHeightConstraint = inputRow.heightAnchor.constraint(equalToConstant: AILayout.inputRowHeight)
    inputRowTopToTitle = inputRow.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6)
    inputRowTopToChatList = inputRow.topAnchor.constraint(equalTo: chatListView.bottomAnchor, constant: 6)
    inputRowBottomToPanel = inputRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
    resultBottomToHeart = resultTextView.bottomAnchor.constraint(equalTo: heartTargetButton.topAnchor, constant: -6)
    resultMinHeight = resultTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 28)
    resultHeightZero = resultTextView.heightAnchor.constraint(equalToConstant: 0)
    heartHeightConstraint = heartTargetButton.heightAnchor.constraint(equalToConstant: 20)
    suggestionBottomToHeart = suggestionStrip.bottomAnchor.constraint(equalTo: heartTargetButton.topAnchor, constant: -6)
    suggestionHeightZero = suggestionStrip.heightAnchor.constraint(equalToConstant: 0)
    waveHeightConstraint = aiWaveContainer.heightAnchor.constraint(equalToConstant: 0)
    aiWaveTopToTitle = aiWaveContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6)
    aiWaveCenterY = aiWaveContainer.centerYAnchor.constraint(equalTo: centerYAnchor)
    micLeadingToPhone = micButton.leadingAnchor.constraint(equalTo: phoneButton.trailingAnchor, constant: 6)
    micLeadingToText = micButton.leadingAnchor.constraint(equalTo: inputTextView.trailingAnchor, constant: 6)

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      closeButton.widthAnchor.constraint(equalToConstant: 26),
      closeButton.heightAnchor.constraint(equalToConstant: 26),
      screenshotButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      screenshotButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
      screenshotButton.widthAnchor.constraint(equalToConstant: 28),
      screenshotButton.heightAnchor.constraint(equalToConstant: 28),
      styleButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      styleButton.trailingAnchor.constraint(equalTo: screenshotButton.leadingAnchor, constant: -6),
      styleButton.widthAnchor.constraint(equalToConstant: 64),
      styleButton.heightAnchor.constraint(equalToConstant: 24),
      speakToggleButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      speakToggleButton.trailingAnchor.constraint(equalTo: screenshotButton.leadingAnchor, constant: -8),
      newChatButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      newChatButton.trailingAnchor.constraint(equalTo: speakToggleButton.leadingAnchor, constant: -8),

      aiWaveTopToTitle,
      aiWaveContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      aiWaveContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      waveHeightConstraint,

      chatListView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
      chatListView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      chatListView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      chatListHeightConstraint,

      chatStackView.topAnchor.constraint(equalTo: chatListView.contentLayoutGuide.topAnchor),
      chatStackView.bottomAnchor.constraint(equalTo: chatListView.contentLayoutGuide.bottomAnchor),
      chatStackView.leadingAnchor.constraint(equalTo: chatListView.contentLayoutGuide.leadingAnchor),
      chatStackView.trailingAnchor.constraint(equalTo: chatListView.contentLayoutGuide.trailingAnchor),
      chatStackView.widthAnchor.constraint(equalTo: chatListView.widthAnchor),

      inputRowTopToTitle,
      inputRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      inputRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      inputRowHeightConstraint,

      inputTextView.topAnchor.constraint(equalTo: inputRow.topAnchor),
      inputTextView.bottomAnchor.constraint(equalTo: inputRow.bottomAnchor),
      inputTextView.leadingAnchor.constraint(equalTo: inputRow.leadingAnchor),

      phoneButton.leadingAnchor.constraint(equalTo: inputTextView.trailingAnchor, constant: 6),
      phoneButton.centerYAnchor.constraint(equalTo: inputRow.centerYAnchor),
      phoneButton.widthAnchor.constraint(equalToConstant: 36),
      phoneButton.heightAnchor.constraint(equalToConstant: 36),

      micLeadingToPhone,
      micButton.centerYAnchor.constraint(equalTo: inputRow.centerYAnchor),
      micButton.widthAnchor.constraint(equalToConstant: 36),
      micButton.heightAnchor.constraint(equalToConstant: 36),

      actionButton.leadingAnchor.constraint(equalTo: micButton.trailingAnchor, constant: 6),
      actionButton.trailingAnchor.constraint(equalTo: inputRow.trailingAnchor),
      actionButton.centerYAnchor.constraint(equalTo: inputRow.centerYAnchor),
      actionButton.widthAnchor.constraint(equalToConstant: 84),
      actionButton.heightAnchor.constraint(equalToConstant: 40),

      resultTextView.topAnchor.constraint(equalTo: inputRow.bottomAnchor, constant: 6),
      resultTextView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      resultTextView.trailingAnchor.constraint(equalTo: suggestionStrip.leadingAnchor, constant: -8),
      resultBottomToHeart,
      resultMinHeight,

      copyButton.topAnchor.constraint(equalTo: resultTextView.topAnchor, constant: 2),
      copyButton.trailingAnchor.constraint(equalTo: resultTextView.trailingAnchor, constant: -4),
      copyButton.widthAnchor.constraint(equalToConstant: 48),
      copyButton.heightAnchor.constraint(equalToConstant: 24),

      replyCandidatesScrollView.topAnchor.constraint(equalTo: inputRow.bottomAnchor, constant: 6),
      replyCandidatesScrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      replyCandidatesScrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      replyCandidatesHeightConstraint,

      replyCandidatesStack.topAnchor.constraint(equalTo: replyCandidatesScrollView.contentLayoutGuide.topAnchor),
      replyCandidatesStack.bottomAnchor.constraint(equalTo: replyCandidatesScrollView.contentLayoutGuide.bottomAnchor),
      replyCandidatesStack.leadingAnchor.constraint(equalTo: replyCandidatesScrollView.contentLayoutGuide.leadingAnchor),
      replyCandidatesStack.trailingAnchor.constraint(equalTo: replyCandidatesScrollView.contentLayoutGuide.trailingAnchor),
      replyCandidatesStack.heightAnchor.constraint(equalTo: replyCandidatesScrollView.frameLayoutGuide.heightAnchor),

      suggestionStrip.topAnchor.constraint(equalTo: inputRow.bottomAnchor, constant: 6),
      suggestionStrip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      suggestionBottomToHeart,
      suggestionStripWidthConstraint,

      heartTargetButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      heartTargetButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
      heartHeightConstraint,
    ])
  }

  private func bind() {
    // 聊天对象档案变化时刷新选择菜单
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(heartProfilesDidChange),
      name: .heartTargetProfilesDidChange,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(memoryPolicyDidChange),
      name: .clawMemoryPolicyDidChange,
      object: nil
    )

    // 实时建议条跟随建议引擎
    ClawSuggestionEngine.shared.$suggestions
      .receive(on: DispatchQueue.main)
      .sink { [weak self] suggestions in
        guard let self else { return }
        self.suggestionStrip.update(suggestions: suggestions)
        let showStrip = !suggestions.isEmpty && !self.isAITab && self.currentReplyCandidates.isEmpty
        self.suggestionStrip.isHidden = !showStrip
        self.suggestionStripWidthConstraint.constant = showStrip ? 140 : 0
        self.layoutIfNeeded()
      }
      .store(in: &subscriptions)

    // AI voice chat: rebuild bubbles on message/status change
    ClawChatService.shared.$messages
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.rebuildChatBubbles()
        self?.updateWaveVisibility()
      }
      .store(in: &subscriptions)
    ClawChatService.shared.$isSending
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.rebuildChatBubbles()
        self?.flushPendingCallSegments()
        self?.resumeCallIfIdle()
      }
      .store(in: &subscriptions)
    ClawChatService.shared.$isSpeaking
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateSpeakToggleTitle()
        self?.resumeCallIfIdle()
      }
      .store(in: &subscriptions)
  }

  @objc private func heartProfilesDidChange() {
    DispatchQueue.main.async { [weak self] in
      self?.refreshHeartTargetMenu()
    }
  }

  @objc private func memoryPolicyDidChange() {
    DispatchQueue.main.async { [weak self] in
      self?.refreshHeartTargetMenu()
    }
  }

  private func refreshStyleMenu() {
    styleButton.setTitle(selectedToneStyle.title, for: .normal)
    styleButton.menu = UIMenu(title: "表达风格", children: ToneStyle.allCases.map { style in
      UIAction(title: style.title, state: style == selectedToneStyle ? .on : .off) { [weak self] _ in
        guard let self else { return }
        self.selectedToneStyle = style
        self.refreshStyleMenu()
        if !self.lastAnalysisInput.isEmpty, !self.isAITab {
          self.runAnalysis(text: self.lastAnalysisInput, isRegeneration: true)
        }
      }
    })
  }

  // MARK: - Tab 刷新

  func refresh(for tab: Int) {
    // 面板配色跟随当前键盘主题
    ClawPanelPalette.sync(with: keyboardContext)
    guard let panelTab = PanelTab(rawValue: tab) else { return }
    let isHelp = panelTab == .helpReply
    let isSuper = panelTab == .superTalk
    let isAI = panelTab == .ai
    styleButton.isHidden = isAI
    refreshStyleMenu()
    inputRow.isHidden = false
    actionButton.setTitle(isAI ? "发送" : (isHelp ? "帮我回" : "优化"), for: .normal)
    titleLabel.text = panelTab == .ai ? "AI语音助手" : (isHelp ? "帮你回" : "超会说")
    screenshotButton.isHidden = isSuper
    if isAI {
      screenshotButton.setImage(UIImage(systemName: "arrow.up.forward.app"), for: .normal)
      screenshotButton.accessibilityLabel = "在主 App 继续"
    } else {
      screenshotButton.setImage(UIImage(systemName: "photo.on.rectangle"), for: .normal)
      screenshotButton.accessibilityLabel = "导入聊天截图"
    }
    newChatButton.isHidden = !isAI
    speakToggleButton.isHidden = !isAI
    if isCallActive { stopCall() }
    phoneButton.isHidden = !isAI
    if isAI {
      NSLayoutConstraint.deactivate([micLeadingToText])
      NSLayoutConstraint.activate([micLeadingToPhone])
    } else {
      NSLayoutConstraint.deactivate([micLeadingToPhone])
      NSLayoutConstraint.activate([micLeadingToText])
    }
    inputTextView.text = ""
    resultTextView.text = ""
    resultTextView.isHidden = true
    copyButton.isHidden = true
    currentReplyCandidates = []
    replyCandidatesStack.arrangedSubviews.forEach { view in
      replyCandidatesStack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }
    replyCandidatesScrollView.isHidden = true
    replyCandidatesHeightConstraint.constant = 0
    isListening = false
    isMicHeld = false
    micButton.tintColor = ClawPanelPalette.brandBlue
    inputRowHeightConstraint.constant = AILayout.inputRowHeight
    if isAI {
      // AI tab：聊天列表弹性占位，输入行贴底；聊天对象与结果区不占空间
      heartTargetButton.isHidden = true
      heartHeightConstraint.constant = 0
      NSLayoutConstraint.deactivate([inputRowTopToTitle, resultBottomToHeart, resultMinHeight, suggestionBottomToHeart])
      NSLayoutConstraint.activate([inputRowTopToChatList, inputRowBottomToPanel, resultHeightZero, suggestionHeightZero])
      rebuildChatBubbles()
      updateWaveVisibility()
    } else {
      heartTargetButton.isHidden = false
      heartHeightConstraint.constant = 20
      NSLayoutConstraint.deactivate([inputRowTopToChatList, inputRowBottomToPanel, resultHeightZero, suggestionHeightZero, chatListBottomToInput])
      NSLayoutConstraint.activate([inputRowTopToTitle, resultBottomToHeart, resultMinHeight, suggestionBottomToHeart, chatListHeightConstraint])
      chatListView.isHidden = true
      aiWaveContainer.isHidden = true
      stopWaveAnimation()
    }
  }

  /// AI tab 波形条显隐：录音中或空会话时显示，聊天列表让位
  private func updateWaveVisibility() {
    guard isAITab else {
      aiWaveContainer.isHidden = true
      stopWaveAnimation()
      return
    }
    let showWave = isListening || isCallActive || ClawChatService.shared.messages.isEmpty
    aiWaveContainer.isHidden = !showWave
    chatListView.isHidden = showWave
    if showWave {
      waveHeightConstraint.constant = AILayout.waveHeight
      // 波形条模式：输入行不挂聊天列表，避免三约束冲突导致重叠；波形条垂直居中面板，不顶着标题
      NSLayoutConstraint.deactivate([chatListBottomToInput, inputRowTopToChatList, aiWaveTopToTitle])
      NSLayoutConstraint.activate([chatListHeightConstraint, aiWaveCenterY])
      layoutIfNeeded()
      startWaveAnimation()
    } else {
      waveHeightConstraint.constant = 0
      NSLayoutConstraint.deactivate([chatListHeightConstraint, aiWaveCenterY])
      NSLayoutConstraint.activate([chatListBottomToInput, inputRowTopToChatList, aiWaveTopToTitle])
      stopWaveAnimation()
    }
  }

  // MARK: - 语音起伏动画（9 根竖条）

  private func startWaveAnimation() {
    guard barStack.count == 9 else { return }
    let containerWidth = aiWaveContainer.bounds.width
    let midY = aiWaveContainer.bounds.midY
    let totalWidth: CGFloat = 8 * 22 + 5
    let startX = max(0, (containerWidth - totalWidth) / 2)
    for (index, bar) in barStack.enumerated() {
      let base: CGFloat = 14 + CGFloat((index % 3) * 8)
      bar.frame = CGRect(x: startX + CGFloat(index) * 22, y: midY - base / 2, width: 5, height: base)
      let anim = CABasicAnimation(keyPath: "bounds.size.height")
      anim.fromValue = base
      anim.toValue = base + 22 + CGFloat(index % 4) * 6
      anim.duration = 0.5 + Double(index) * 0.09
      anim.autoreverses = true
      anim.repeatCount = .infinity
      bar.layer.add(anim, forKey: "wave")
    }
  }

  private func stopWaveAnimation() {
    barStack.forEach { $0.layer.removeAnimation(forKey: "wave") }
  }


  // MARK: - 输入框（键盘按键直输）

  /// 键盘按键/候选上屏注入面板输入框
  private func appendTextToInput(_ text: String) {
    let current = inputTextView.text ?? ""
    let selectedRange = inputTextView.selectedRange
    var newText = current
    if selectedRange.location != NSNotFound, selectedRange.length > 0 {
      let ns = newText as NSString
      newText = ns.replacingCharacters(in: selectedRange, with: text)
    } else {
      let ns = newText as NSString
      let location = min(selectedRange.location, ns.length)
      newText = ns.replacingCharacters(in: NSRange(location: location, length: 0), with: text)
    }
    inputTextView.text = newText
    let cursor = (newText as NSString).length
    inputTextView.selectedRange = NSRange(location: cursor, length: 0)
    scrollInputToBottom()
    ClawSuggestionEngine.shared.feed(newText)
  }

  /// 键盘退格 → 面板输入框
  private func deleteLastCharFromInput() {
    let current = inputTextView.text ?? ""
    let ns = current as NSString
    let selectedRange = inputTextView.selectedRange
    var newText: String
    if selectedRange.location != NSNotFound, selectedRange.length > 0 {
      newText = ns.replacingCharacters(in: selectedRange, with: "")
    } else {
      let location = min(selectedRange.location, ns.length)
      guard location > 0 else { return }
      newText = ns.replacingCharacters(in: NSRange(location: location - 1, length: 1), with: "")
    }
    inputTextView.text = newText
    inputTextView.selectedRange = NSRange(location: (newText as NSString).length, length: 0)
    scrollInputToBottom()
    ClawSuggestionEngine.shared.feed(newText)
  }

  private func scrollInputToBottom() {
    let range = NSRange(location: (inputTextView.text as NSString).length, length: 0)
    inputTextView.scrollRangeToVisible(range)
  }

  // MARK: - 交互

  // MARK: - AI voice chat (DeepSeek + STT + TTS)

  private func sendChatMessage() {
    let text = inputTextView.text ?? ""
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !ClawChatService.shared.isSending else { return }
    ClawChatService.shared.send(trimmed)
    inputTextView.text = ""
  }

  @objc private func newChatTapped() {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    ClawChatService.shared.clearHistory()
  }

  @objc private func speakToggleTapped() {
    if ClawChatService.shared.isSpeaking {
      ClawChatService.shared.stopSpeaking()
    } else {
      ClawChatService.shared.autoSpeak.toggle()
    }
    updateSpeakToggleTitle()
  }

  private func updateSpeakToggleTitle() {
    if ClawChatService.shared.isSpeaking {
      speakToggleButton.setTitle("停止", for: .normal)
    } else {
      speakToggleButton.setTitle(ClawChatService.shared.autoSpeak ? "自动朗读" : "静音", for: .normal)
    }
  }

  private func rebuildChatBubbles() {
    chatStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
    chatListView.layoutIfNeeded()
    let chat = ClawChatService.shared
    // 键盘里只保留最近两轮，完整会话在主 App 展开。
    for message in chat.messages.suffix(4) {
      chatStackView.addArrangedSubview(makeBubble(for: message))
    }
    if chat.isSending {
      chatStackView.addArrangedSubview(makeThinkingBubble())
    }
    scrollChatToBottom()
  }

  private func makeBubble(for message: ClawChatMessage) -> UIView {
    let isUser = message.role == "user"
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false
    let bubble = UIView()
    bubble.translatesAutoresizingMaskIntoConstraints = false
    bubble.backgroundColor = isUser ? ClawPanelPalette.brandBlue : ClawPanelPalette.inputBackground
    bubble.layer.cornerRadius = 12
    bubble.layer.masksToBounds = true
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.numberOfLines = 0
    label.font = .systemFont(ofSize: 14)
    label.text = message.content
    label.textColor = isUser ? .white : ClawPanelPalette.candidateText
    bubble.addSubview(label)
    container.addSubview(bubble)
    let bubbleWidth = max(AILayout.bubbleMinWidth, min(chatListView.bounds.width * 0.82, AILayout.bubbleMaxWidth))
    NSLayoutConstraint.activate([
      label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
      label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
      label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
      label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
      bubble.topAnchor.constraint(equalTo: container.topAnchor),
      bubble.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      bubble.widthAnchor.constraint(lessThanOrEqualToConstant: bubbleWidth),
    ])
    if isUser {
      bubble.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true
      bubble.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor).isActive = true
    } else {
      bubble.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
      bubble.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor).isActive = true
      container.isUserInteractionEnabled = true
      container.accessibilityLabel = message.content
      let tap = UITapGestureRecognizer(target: self, action: #selector(bubbleTapped(_:)))
      container.addGestureRecognizer(tap)
    }
    return container
  }

  private func makeThinkingBubble() -> UIView {
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false
    let bubble = UIView()
    bubble.translatesAutoresizingMaskIntoConstraints = false
    bubble.backgroundColor = ClawPanelPalette.inputBackground
    bubble.layer.cornerRadius = 12
    bubble.layer.masksToBounds = true
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13)
    label.textColor = ClawPanelPalette.candidateText
    label.text = "正在思考…"
    bubble.addSubview(label)
    container.addSubview(bubble)
    NSLayoutConstraint.activate([
      label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
      label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
      label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
      label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
      bubble.topAnchor.constraint(equalTo: container.topAnchor),
      bubble.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      bubble.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      bubble.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
    ])
    return container
  }

  private func scrollChatToBottom() {
    chatListView.layoutIfNeeded()
    let bottom = chatListView.contentSize.height - chatListView.bounds.height
    if bottom > 0 {
      chatListView.setContentOffset(CGPoint(x: 0, y: bottom), animated: true)
    }
  }

  @objc private func bubbleTapped(_ sender: UITapGestureRecognizer) {
    guard let container = sender.view, let text = container.accessibilityLabel else { return }
    ClawChatService.shared.speak(text)
  }
  @objc private func closeTapped() {
    keyboardContext.clawPanelTab = -1
  }

  @objc private func actionButtonTapped() {
    if isCallActive {
      stopCall()
      return
    }
    if isAITab {
      sendChatMessage()
      return
    }
    guard !isLoading else { return }
    let previousResult = !currentReplyCandidates.isEmpty
      ? currentReplyCandidates.joined(separator: "\n")
      : (resultTextView.isHidden ? "" : (resultTextView.text ?? ""))
    let text = inputTextView.text ?? ""
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      showResultMessage("请先输入或粘贴内容")
      return
    }
    runAnalysis(text: trimmed, isRegeneration: !previousResult.isEmpty && previousResult != "分析中…")
  }

  @objc private func actionButtonLongPressed(_ sender: UILongPressGestureRecognizer) {
    guard sender.state == .began, !isLoading else { return }
    presentPhotoPicker()
  }

  @objc private func screenshotTapped() {
    guard !isLoading else { return }
    if isAITab {
      actionHandler.handle(
        .release,
        on: .url(URL(string: HamsterConstants.appURLForGuru), id: "openClawAssistant")
      )
      return
    }
    presentPhotoPicker()
  }

  private var isKeyboardExtensionRuntime: Bool {
  Bundle.main.bundleURL.pathExtension.lowercased() == "appex"
}

@objc private func micTapped() {
  guard !isCallActive else { return }
  if isListening {
    isMicHeld = false
    ClawVoiceInputService.shared.stop()
    isListening = false
    updateMicUI(recording: false)
  } else {
    isMicHeld = true
    startVoiceInput()
  }
}

@objc private func micLongPressed(_ sender: UILongPressGestureRecognizer) {
    switch sender.state {
    case .began:
      guard !isListening, !isCallActive else { return }
      isMicHeld = true
      startVoiceInput()
    case .ended, .cancelled, .failed:
      isMicHeld = false
      ClawVoiceInputService.shared.stop()
      if isListening {
        isListening = false
        updateMicUI(recording: false)
      }
    default:
      break
    }
  }

  /// 语音输入：主程序内直接听写；键盘扩展必须跳到包含它的主程序采音。
  /// iOS 不给第三方键盘扩展麦克风输入，主程序即使已经授权也不会改变这一限制。
  private func startVoiceInput() {
    switch ClawVoiceLaunchPolicy.action(
      isKeyboardExtension: isKeyboardExtensionRuntime,
      authorization: ClawVoiceInputService.shared.authorizationStatus
    ) {
    case .openHostDictation:
      isMicHeld = false
      isListening = false
      updateMicUI(recording: false)
      showResultMessage("正在打开 CLAW 语音输入…")
      actionHandler.handle(
        .release,
        on: .url(URL(string: HamsterConstants.appURLForGuruVoiceInput), id: "openClawVoiceInput")
      )
      return
    case .showPermissionDenied:
      isMicHeld = false
      showResultMessage("麦克风/语音识别权限未开启，请到 ClawTalk 主程序或系统设置中开启")
      return
    case .showPermissionRequired:
      isMicHeld = false
      showResultMessage("请先在 ClawTalk 主程序中授权麦克风与语音识别")
      return
    case .recordLocally:
      break
    }
    guard isMicHeld else { return }
    isListening = true
    updateMicUI(recording: true)
    ClawVoiceInputService.shared.start { [weak self] result in
      DispatchQueue.main.async {
        guard let self else { return }
        self.isMicHeld = false
        self.isListening = false
        self.updateMicUI(recording: false)
        switch result {
        case .success(let text):
          let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
          if !trimmed.isEmpty {
            if self.isAITab {
              ClawChatService.shared.send(trimmed)
              self.inputTextView.text = ""
            } else {
              self.appendTextToInput(trimmed)
            }
          }
        case .failure(let error):
          if self.isAITab {
            ClawChatService.shared.postAssistant("语音识别失败：\(error.localizedDescription)")
          } else {
            self.showResultMessage("语音识别失败：\(error.localizedDescription)")
          }
        }
      }
    }
  }

  // MARK: - 实时通话（方案 A：伪实时轮转，点按接通 / 再点挂断）

  @objc private func phoneTapped() {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    if isCallActive {
      stopCall()
    } else {
      startCall()
    }
  }

  private func startCall() {
    guard !isCallActive else { return }
    if isKeyboardExtensionRuntime {
      actionHandler.handle(
        .release,
        on: .url(URL(string: HamsterConstants.appURLForGuruVoice), id: "openClawVoiceCall")
      )
      return
    }
    switch ClawVoiceInputService.shared.authorizationStatus {
    case .denied:
      ClawChatService.shared.postAssistant("麦克风/语音识别权限未开启，请到 ClawTalk 主程序或系统设置中开启")
      return
    case .undetermined:
      ClawChatService.shared.postAssistant("请先在 ClawTalk 主程序中授权麦克风与语音识别")
      return
    case .authorized:
      break
    }
    isCallActive = true
    pendingCallSegments = []
    ClawChatService.shared.stopSpeaking()
    updateCallUI()
    beginCallListening()
  }

  private func stopCall() {
    guard isCallActive else { return }
    isCallActive = false
    pendingCallSegments = []
    ClawVoiceInputService.shared.stop()
    ClawChatService.shared.stopSpeaking()
    if isListening { isListening = false }
    updateMicUI(recording: false)
    updateCallUI()
    updateWaveVisibility()
  }

  private func stopCallIfActive() {
    if isCallActive { stopCall() }
  }

  /// 接通后开始收音；每段静音停顿自动断句
  private func beginCallListening() {
    guard isCallActive, !isListening else { return }
    isListening = true
    updateMicUI(recording: true)
    ClawVoiceInputService.shared.startStreaming(
      onPartial: { [weak self] text in
        DispatchQueue.main.async {
          guard let self, self.isCallActive else { return }
          self.inputTextView.text = text
        }
      },
      onSegment: { [weak self] text in
        DispatchQueue.main.async {
          guard let self, self.isCallActive else { return }
          self.isListening = false
          self.updateMicUI(recording: false)
          let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty else {
            self.resumeCallIfIdle()
            return
          }
          self.inputTextView.text = ""
          self.handleCallSegment(trimmed)
        }
      },
      onError: { [weak self] error in
        DispatchQueue.main.async {
          guard let self else { return }
          self.isListening = false
          self.updateMicUI(recording: false)
          if self.isCallActive {
            ClawChatService.shared.postAssistant("语音识别中断：\(error.localizedDescription)")
            self.stopCall()
          }
        }
      }
    )
  }

  /// 通话期间收到一句话：AI 还在回复则排队，空闲后逐个发出
  private func handleCallSegment(_ text: String) {
    if ClawChatService.shared.isSending {
      pendingCallSegments.append(text)
      return
    }
    ClawChatService.shared.send(text, forceSpeak: true)
  }

  /// AI 回复读完且无排队 → 继续收音
  private func resumeCallIfIdle() {
    guard isCallActive, !isListening, !ClawChatService.shared.isSending, !ClawChatService.shared.isSpeaking else { return }
    beginCallListening()
  }

  private func flushPendingCallSegments() {
    guard isCallActive, !ClawChatService.shared.isSending, !ClawChatService.shared.isSpeaking, !pendingCallSegments.isEmpty else { return }
    let next = pendingCallSegments.removeFirst()
    ClawChatService.shared.send(next, forceSpeak: true)
  }

  private func updateCallUI() {
    phoneButton.tintColor = isCallActive ? .white : ClawPanelPalette.brandBlue
    phoneButton.backgroundColor = isCallActive ? .systemRed : ClawPanelPalette.inputBackground
  }

  private func updateMicUI(recording: Bool) {
    micButton.tintColor = recording ? .systemRed : ClawPanelPalette.brandBlue
    if isCallActive {
      actionButton.setTitle("挂断", for: .normal)
      updateWaveVisibility()
      return
    }
    let tab = keyboardContext.clawPanelTab
    if recording {
      actionButton.setTitle("松开发送…", for: .normal)
    } else if isAITab {
      actionButton.setTitle("发送", for: .normal)
    } else {
      actionButton.setTitle(tab == PanelTab.helpReply.rawValue ? "帮我回" : "优化", for: .normal)
    }
    updateWaveVisibility()
  }

  /// 帮你回截图入口：上传聊天截图 → 本地 OCR/结构化时间线 → 文本填入输入框。
  private func presentPhotoPicker() {
    var config = PHPickerConfiguration()
    config.filter = .images
    config.selectionLimit = 6
    config.selection = .ordered
    let picker = PHPickerViewController(configuration: config)
    picker.delegate = self
    guard let vc = clawParentViewController else { return }
    vc.present(picker, animated: true)
  }

  /// AI 分析（帮你回 / 超会说），统一注入 Memory Core 检索出的相关上下文。
  private func runAnalysis(text: String, isRegeneration: Bool = false) {
    // 准备阶段要查 Memory / Skill / Keychain，全部放到后台执行，
    // 主线程只负责立刻给出加载反馈、发起网络请求和渲染结果。
    let requestID = UUID()
    currentAnalysisRequestID = requestID

    let panelTab = keyboardContext.clawPanelTab
    let isHelpTab = panelTab == PanelTab.helpReply.rawValue
    let skillID = isHelpTab ? "reply" : "rewrite"
    let trigger: ClawSkillTrigger = isHelpTab ? .keyboardHelpReply : .keyboardRewrite
    let contactID = HeartTargetService.shared.selectedProfile?.id
    let contactName = HeartTargetService.shared.selectedProfile?.displayName
    let memoryContext = HeartTargetService.shared.selectedProfile?.memoryContext ?? ""
    let styleInstruction = selectedToneStyle.instruction
    let previousExperimentVariantID = currentExperimentVariantID
    let fallbackPrompt = isHelpTab
      ? "你是 CLAW 的帮你回 Skill。根据当前聊天内容、聊天对象关系和用户自己的表达习惯生成可直接发送的回复。"
      : "你是 CLAW 的超会说 Skill。保留用户原意，把这句话改得更自然、更有分寸、更像用户本人会说的话。"
    let formatInstruction = isHelpTab
      ? "\n本次输出格式要求：恰好 3 条候选，分别偏自然、有分寸、简短；严格只返回 JSON 字符串数组，不要 Markdown、编号或解释。"
      : "\n不要解释，不要加标题，只输出可直接替换原文的最终版本。"

    lastAnalysisInput = text
    isLoading = true
    currentReplyCandidates = []
    replyCandidatesScrollView.isHidden = true
    resultTextView.isHidden = false
    resultTextView.text = "分析中…"
    copyButton.isHidden = true
    actionButton.isEnabled = false

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      if isRegeneration {
        ClawSkillRuntime.shared.recordExperimentFeedback(
          skillID: skillID,
          variantID: previousExperimentVariantID,
          action: .regenerated
        )
      }
      let invocation = try? ClawSkillRuntime.shared.prepare(
        skillID: skillID,
        trigger: trigger,
        input: text,
        contactID: contactID
      )
      var systemPrompt = invocation?.systemPrompt ?? fallbackPrompt
      systemPrompt += "\n当前风格要求：\(styleInstruction)"
      systemPrompt += formatInstruction
      if let contactName, !memoryContext.isEmpty {
        systemPrompt += "\n当前聊天对象：\(contactName)\n\(memoryContext)"
      }
      let requestConfiguration = AIService.shared.currentRequestConfiguration

      DispatchQueue.main.async {
        guard let self, self.currentAnalysisRequestID == requestID else { return }
        self.currentExperimentVariantID = invocation?.experimentVariantID
        AIService.shared.chat(
          messages: [
            AIMessage(role: "system", content: systemPrompt),
            AIMessage(role: "user", content: text),
          ],
          configuration: requestConfiguration
        ) { [weak self] result in
          guard let self, self.currentAnalysisRequestID == requestID else { return }
          self.isLoading = false
          self.actionButton.isEnabled = true
          switch result {
          case .success(let reply):
            let cleaned = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            if isHelpTab {
              let candidates = self.parseReplyCandidates(cleaned)
              self.currentReplyCandidates = candidates
              self.showReplyCandidates(candidates)
            } else {
              self.resultTextView.text = cleaned
              self.resultTextView.isHidden = false
              self.copyButton.isHidden = false
              self.replyCandidatesScrollView.isHidden = true
            }
            self.actionButton.setTitle("换一批", for: .normal)
            if isRegeneration {
              try? ClawMemoryStore.shared.recordFeedback(ClawEvolutionFeedback(
                skillID: skillID,
                contactID: contactID,
                action: .regenerated,
                originalText: text,
                finalText: cleaned
              ))
            }
          case .failure(let error):
            self.resultTextView.text = "分析失败：\(error.localizedDescription)"
          }
        }
      }
    }
  }

  /// 结果区提示消息
  private func showResultMessage(_ message: String) {
    resultTextView.isHidden = false
    resultTextView.text = message
    copyButton.isHidden = true
  }

  @objc private func copyResultTapped() {
    guard let text = resultTextView.text, !text.isEmpty else { return }
    acceptGeneratedText(text)
  }

  private func acceptGeneratedText(_ text: String) {
    let original = lastAnalysisInput.isEmpty ? inputTextView.text : lastAnalysisInput
    ClawPanelInputBridge.shared.send(text)
    let skillID = keyboardContext.clawPanelTab == PanelTab.helpReply.rawValue ? "reply" : "rewrite"
    ClawGeneratedOutputTracker.shared.markInserted(
      skillID: skillID,
      contactID: HeartTargetService.shared.selectedProfile?.id,
      sourceText: original,
      generatedText: text,
      style: selectedToneStyle.rawValue,
      experimentVariantID: currentExperimentVariantID
    )
    try? ClawMemoryStore.shared.recordFeedback(ClawEvolutionFeedback(
      skillID: skillID,
      contactID: HeartTargetService.shared.selectedProfile?.id,
      action: .accepted,
      originalText: original,
      finalText: text
    ))
    ClawSkillRuntime.shared.recordExperimentFeedback(
      skillID: skillID,
      variantID: currentExperimentVariantID,
      action: .accepted
    )
    _ = ClawEvolutionEngine.shared.evolveIfNeeded(skillID: skillID)
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    keyboardContext.clawPanelTab = -1
  }

  private func parseReplyCandidates(_ raw: String) -> [String] {
    let stripped = raw
      .replacingOccurrences(of: "```json", with: "")
      .replacingOccurrences(of: "```", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if let data = stripped.data(using: .utf8),
       let values = try? JSONSerialization.jsonObject(with: data) as? [String] {
      let cleaned = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
      if !cleaned.isEmpty { return Array(cleaned.prefix(3)) }
    }
    let lines = stripped
      .components(separatedBy: .newlines)
      .map { line in
        line.replacingOccurrences(of: #"^\s*[-*\d.、)]+\s*"#, with: "", options: .regularExpression)
          .trimmingCharacters(in: .whitespacesAndNewlines)
      }
      .filter { !$0.isEmpty }
    return Array((lines.isEmpty ? [stripped] : lines).prefix(3))
  }

  private func showReplyCandidates(_ candidates: [String]) {
    replyCandidatesStack.arrangedSubviews.forEach { view in
      replyCandidatesStack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }
    let labels = ["自然", "有分寸", "简短"]
    for (index, text) in candidates.enumerated() {
      let button = UIButton(type: .system)
      button.translatesAutoresizingMaskIntoConstraints = false
      button.tag = index
      button.titleLabel?.font = .systemFont(ofSize: 12)
      button.titleLabel?.numberOfLines = 3
      button.titleLabel?.textAlignment = .left
      button.contentHorizontalAlignment = .leading
      button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
      button.backgroundColor = ClawPanelPalette.inputBackground
      button.layer.cornerRadius = 10
      button.clipsToBounds = true
      let label = labels.indices.contains(index) ? labels[index] : "候选"
      button.setTitle("\(label)\n\(text)", for: .normal)
      button.setTitleColor(ClawPanelPalette.candidateText, for: .normal)
      button.addTarget(self, action: #selector(replyCandidateTapped(_:)), for: .touchUpInside)
      NSLayoutConstraint.activate([
        button.widthAnchor.constraint(equalToConstant: 172),
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
      ])
      replyCandidatesStack.addArrangedSubview(button)
    }
    resultTextView.isHidden = true
    copyButton.isHidden = true
    suggestionStrip.isHidden = true
    replyCandidatesHeightConstraint.constant = candidates.isEmpty ? 0 : 54
    replyCandidatesScrollView.isHidden = candidates.isEmpty
  }

  @objc private func replyCandidateTapped(_ sender: UIButton) {
    guard currentReplyCandidates.indices.contains(sender.tag) else { return }
    acceptGeneratedText(currentReplyCandidates[sender.tag])
  }

  // MARK: - 聊天对象

  private func refreshHeartTargetMenu() {
    let profiles = HeartTargetService.shared.profiles
    let profile = HeartTargetService.shared.selectedProfile
    let selected = profile?.displayName ?? "全局"
    let pack = ClawContextBuilder.shared.build(contactID: profile?.id, includeTasks: false)
    let screenshotCount = pack.recentConversation.filter { $0.sourceType.lowercased().contains("screenshot") }.count
    let contextText = ClawMemoryPolicyService.shared.temporaryMode
      ? "临时模式"
      : "🧠习惯\(pack.globalMemories.count)/对象\(pack.contactMemories.count) · 💬\(pack.recentConversation.count) · 📷\(screenshotCount)"
    heartTargetButton.setTitle("👤 \(selected) · \(contextText)", for: .normal)

    var actions: [UIAction] = [
      UIAction(title: "全局（不混联系人）", state: HeartTargetService.shared.selectedProfile == nil ? .on : .off) { _ in
        HeartTargetService.shared.clearSelection()
        self.refreshHeartTargetMenu()
      },
    ]
    actions.append(contentsOf: profiles.enumerated().map { index, profile in
      UIAction(title: profile.displayName, state: index == HeartTargetService.shared.selectedIndex ? .on : .off) { _ in
        HeartTargetService.shared.select(at: index)
        self.refreshHeartTargetMenu()
      }
    })
    heartTargetButton.menu = UIMenu(children: actions)
  }
}

// MARK: - UITextViewDelegate（键盘按键直输 + 建议触发）

extension ClawPanelOverlayView: UITextViewDelegate {
  public func textViewDidBeginEditing(_ textView: UITextView) {
    keyboardContext.clawPanelInputActive = true
    ClawPanelInputBridge.shared.panelInsert = { [weak self] text in
      self?.appendTextToInput(text)
    }
    ClawPanelInputBridge.shared.panelDelete = { [weak self] in
      self?.deleteLastCharFromInput()
    }
  }

  public func textViewDidEndEditing(_ textView: UITextView) {
    keyboardContext.clawPanelInputActive = false
    ClawPanelInputBridge.shared.panelInsert = nil
    ClawPanelInputBridge.shared.panelDelete = nil
  }

  public func textViewDidChange(_ textView: UITextView) {
    ClawSuggestionEngine.shared.feed(textView.text)
  }
}

// MARK: - PHPickerViewControllerDelegate（上传聊天截图）

extension ClawPanelOverlayView: PHPickerViewControllerDelegate {
  public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard !results.isEmpty else { return }
    showResultMessage("正在识别 1/\(results.count)…")
    processScreenshotResults(results, index: 0, transcripts: [], insertedTotal: 0)
  }

  private func processScreenshotResults(
    _ results: [PHPickerResult],
    index: Int,
    transcripts: [String],
    insertedTotal: Int
  ) {
    guard index < results.count else {
      let combined = transcripts
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      refreshHeartTargetMenu()
      guard !combined.isEmpty else {
        showResultMessage("这些截图没有识别到可用聊天文字")
        return
      }
      inputTextView.text = combined
      ClawSuggestionEngine.shared.feed(combined)
      showResultMessage("已归档 \(insertedTotal) 条聊天记录，正在生成回复…")
      runAnalysis(text: combined)
      return
    }

    let provider = results[index].itemProvider
    guard provider.canLoadObject(ofClass: UIImage.self) else {
      processScreenshotResults(results, index: index + 1, transcripts: transcripts, insertedTotal: insertedTotal)
      return
    }
    provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
      guard let self else { return }
      guard let image = object as? UIImage else {
        DispatchQueue.main.async {
          self.processScreenshotResults(
            results,
            index: index + 1,
            transcripts: transcripts,
            insertedTotal: insertedTotal
          )
        }
        return
      }
      let sourceRef = image.jpegData(compressionQuality: 0.88)
        .flatMap { ClawScreenshotEvidenceStore.shared.saveJPEG($0) }
        ?? "screenshot:\(UUID().uuidString)"
      VisionOCRService.shared.recognizeLines(in: image) { result in
        DispatchQueue.main.async {
          switch result {
          case .success(let lines):
            let selected = HeartTargetService.shared.selectedProfile
            let firstPass = ClawScreenshotChatParser.shared.parse(
              lines: lines,
              contactID: selected?.id,
              contactName: selected?.displayName,
              sourceRef: sourceRef
            )
            let resolution = ClawContactIdentityResolver.shared.resolve(
              displayTitle: firstPass.detectedTitle,
              allowCreate: true
            )
            let profile = resolution.profile ?? selected
            if let profile { HeartTargetService.shared.select(id: profile.id) }
            let parsed = ClawScreenshotChatParser.shared.parse(
              lines: lines,
              contactID: profile?.id,
              contactName: profile?.displayName,
              sourceRef: sourceRef
            )
            var inserted = 0
            for message in parsed.messages {
              if (try? ClawMemoryStore.shared.appendConversation(message)) == true {
                inserted += 1
                ClawSecretaryExtractor.shared.persistExtractedTasks(from: message)
              }
            }
            if inserted > 0, let profileID = profile?.id {
              ClawContactProfileLearner.shared.refreshIfNeeded(profileID: profileID)
            }
            let transcript = parsed.messages.map { message -> String in
              let speaker: String
              switch message.speaker {
              case .me: speaker = "我"
              case .other: speaker = message.senderName ?? profile?.displayName ?? "对方"
              case .assistant: speaker = "CLAW"
              case .system: speaker = "系统"
              case .unknown: speaker = message.senderName ?? "未知"
              }
              return "\(speaker)：\(message.content)"
            }.joined(separator: "\n")
            var next = transcripts
            let text = transcript.isEmpty ? parsed.rawText : transcript
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { next.append(text) }
            self.showResultMessage("正在识别 \(min(index + 2, results.count))/\(results.count)…")
            self.processScreenshotResults(
              results,
              index: index + 1,
              transcripts: next,
              insertedTotal: insertedTotal + inserted
            )
          case .failure:
            self.processScreenshotResults(
              results,
              index: index + 1,
              transcripts: transcripts,
              insertedTotal: insertedTotal
            )
          }
        }
      }
    }
  }
}
