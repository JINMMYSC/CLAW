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
  /// 面板展开高度（标题 + 内容区 + 输入行），压缩后不再遮挡聊天界面
  public static let panelHeight: CGFloat = 150

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

    copyButton.setTitle("复制", for: .normal)
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
    [titleLabel, closeButton, aiWaveContainer, inputRow, resultTextView, copyButton, suggestionStrip, heartTargetButton, chatListView, newChatButton, speakToggleButton].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      addSubview($0)
    }
    [inputTextView, phoneButton, micButton, actionButton].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      inputRow.addSubview($0)
    }

    suggestionStripWidthConstraint = suggestionStrip.widthAnchor.constraint(equalToConstant: 0)
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
    micLeadingToPhone = micButton.leadingAnchor.constraint(equalTo: phoneButton.trailingAnchor, constant: 6)
    micLeadingToText = micButton.leadingAnchor.constraint(equalTo: inputTextView.trailingAnchor, constant: 6)

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      closeButton.widthAnchor.constraint(equalToConstant: 26),
      closeButton.heightAnchor.constraint(equalToConstant: 26),
      speakToggleButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      speakToggleButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
      newChatButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      newChatButton.trailingAnchor.constraint(equalTo: speakToggleButton.leadingAnchor, constant: -8),

      aiWaveContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
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

    // 实时建议条跟随建议引擎
    ClawSuggestionEngine.shared.$suggestions
      .receive(on: DispatchQueue.main)
      .sink { [weak self] suggestions in
        guard let self else { return }
        self.suggestionStrip.update(suggestions: suggestions)
        let showStrip = !suggestions.isEmpty && !self.isAITab
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

  // MARK: - Tab 刷新

  func refresh(for tab: Int) {
    // 面板配色跟随当前键盘主题
    ClawPanelPalette.sync(with: keyboardContext)
    guard let panelTab = PanelTab(rawValue: tab) else { return }
    let isHelp = panelTab == .helpReply
    let isSuper = panelTab == .superTalk
    let isAI = panelTab == .ai
    inputRow.isHidden = false
    actionButton.setTitle(isAI ? "发送" : (isHelp ? "读懂TA" : "优化"), for: .normal)
    titleLabel.text = panelTab == .ai ? "AI语音助手" : (isHelp ? "帮你回" : "超会说")
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
      // 波形条模式：输入行不挂聊天列表，避免三约束冲突导致重叠
      NSLayoutConstraint.deactivate([chatListBottomToInput, inputRowTopToChatList])
      NSLayoutConstraint.activate([chatListHeightConstraint])
      layoutIfNeeded()
      startWaveAnimation()
    } else {
      waveHeightConstraint.constant = 0
      NSLayoutConstraint.deactivate([chatListHeightConstraint])
      NSLayoutConstraint.activate([chatListBottomToInput, inputRowTopToChatList])
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
    for message in chat.messages {
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
    let text = inputTextView.text ?? ""
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      showResultMessage("请先输入或粘贴内容")
      return
    }
    runAnalysis(text: trimmed)
  }

  @objc private func actionButtonLongPressed(_ sender: UILongPressGestureRecognizer) {
    guard sender.state == .began, !isLoading else { return }
    presentPhotoPicker()
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

  /// 语音输入：按住说话 → STT（zh-Hans）转文字填入输入框
  /// 权限只在主程序申请；键盘扩展只读状态，避免系统权限框在扩展进程闪退
  private func startVoiceInput() {
    switch ClawVoiceInputService.shared.authorizationStatus {
    case .denied:
      showResultMessage("麦克风/语音识别权限未开启，请到 ClawTalk 主程序或系统设置中开启")
      return
    case .undetermined:
      showResultMessage("请先在 ClawTalk 主程序中授权麦克风与语音识别")
      return
    case .authorized:
      break
    }
    guard isMicHeld else { return }
    isListening = true
    updateMicUI(recording: true)
    ClawVoiceInputService.shared.start { [weak self] result in
      DispatchQueue.main.async {
        guard let self else { return }
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
      actionButton.setTitle(tab == PanelTab.helpReply.rawValue ? "读懂TA" : "优化", for: .normal)
    }
    updateWaveVisibility()
  }

  /// 读懂TA 长按：上传聊天截图 → 本地 OCR → 文本填入输入框
  private func presentPhotoPicker() {
    var config = PHPickerConfiguration()
    config.filter = .images
    config.selectionLimit = 1
    let picker = PHPickerViewController(configuration: config)
    picker.delegate = self
    guard let vc = clawParentViewController else { return }
    vc.present(picker, animated: true)
  }

  /// AI 分析（读懂TA / 优化），prompt 注入聊天对象档案
  private func runAnalysis(text: String) {
    isLoading = true
    resultTextView.isHidden = false
    resultTextView.text = "分析中…"
    copyButton.isHidden = true
    actionButton.isEnabled = false

    let panelTab = keyboardContext.clawPanelTab
    let profile = HeartTargetService.shared.selectedProfile
    var systemPrompt: String
    if panelTab == 1 {
      systemPrompt = "你是情感沟通助手。请读懂对方的话，帮用户理解对方意图和情绪，并给出针对性的回复建议。保持简洁、有温度。"
    } else {
      systemPrompt = "你是表达优化助手。请帮用户把想说的话优化得更得体、更有说服力，保留原意。"
    }
    if let profile, !profile.bio.isEmpty {
      systemPrompt += "\n聊天对象背景：\(profile.bio)"
    }

    AIService.shared.chat(
      messages: [
        AIMessage(role: "system", content: systemPrompt),
        AIMessage(role: "user", content: text),
      ]
    ) { [weak self] result in
      guard let self else { return }
      self.isLoading = false
      self.actionButton.isEnabled = true
      switch result {
      case .success(let reply):
        self.resultTextView.text = reply
        self.copyButton.isHidden = false
      case .failure(let error):
        self.resultTextView.text = "分析失败：\(error.localizedDescription)"
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
    UIPasteboard.general.string = text
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    copyButton.setTitle("已复制", for: .normal)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
      self?.copyButton.setTitle("复制", for: .normal)
    }
  }

  // MARK: - 聊天对象

  private func refreshHeartTargetMenu() {
    let profiles = HeartTargetService.shared.profiles
    let selected = HeartTargetService.shared.selectedProfile?.displayName ?? "未选择"
    heartTargetButton.setTitle("聊天对象：\(selected) ⇄", for: .normal)

    if profiles.isEmpty {
      heartTargetButton.menu = UIMenu(children: [
        UIAction(title: "暂无档案，请到设置添加", attributes: .disabled) { _ in },
      ])
      return
    }
    let actions = profiles.enumerated().map { index, profile in
      UIAction(title: profile.displayName, state: index == HeartTargetService.shared.selectedIndex ? .on : .off) { _ in
        HeartTargetService.shared.select(at: index)
        self.refreshHeartTargetMenu()
      }
    }
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
    guard let itemProvider = results.first?.itemProvider,
          itemProvider.canLoadObject(ofClass: UIImage.self) else { return }
    itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
      guard let image = object as? UIImage else { return }
      VisionOCRService.shared.recognizeText(in: image) { result in
        guard let self else { return }
        switch result {
        case .success(let text):
          let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
          if trimmed.isEmpty {
            self.showResultMessage("未识别到文字")
          } else {
            self.appendTextToInput(trimmed)
          }
        case .failure(let error):
          self.showResultMessage("识别失败：\(error.localizedDescription)")
        }
      }
    }
  }
}
