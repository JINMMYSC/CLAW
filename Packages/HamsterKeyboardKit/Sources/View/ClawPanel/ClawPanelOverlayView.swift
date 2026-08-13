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
  /// 面板展开高度（参考图面板区域约 130pt + 间距）
  public static let panelHeight: CGFloat = 170

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
  private let aiWaveContainer = UIView()
  private let inputRow = UIView()
  private let inputField = UITextField()
  private let actionButton = UIButton(type: .system)

  // 结果展示
  private let resultLabel = UILabel()

  // 聊天对象
  private let heartTargetButton = UIButton(type: .system)

  // AI 分析状态
  private var isLoading = false

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
      .sink { [weak self] _ in self?.refresh(for: keyboardContext.clawPanelTab) }
      .store(in: &subscriptions)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - 视图构建

  private func setupViews() {
    backgroundColor = .clear

    // 白色圆角卡片
    layer.cornerRadius = 20
    layer.masksToBounds = true
    backgroundColor = ClawPanelPalette.keyWhite

    titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
    titleLabel.textColor = ClawPanelPalette.titleBlue
    titleLabel.text = "AI语音助手"

    closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
    closeButton.tintColor = ClawPanelPalette.titleBlue
    closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

    // AI 波形占位（蓝色动态竖条，后续接真实音频）
    for _ in 0..<9 {
      let bar = UIView()
      bar.backgroundColor = ClawPanelPalette.brandBlue
      bar.layer.cornerRadius = 2.5
      bar.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin]
      aiWaveContainer.addSubview(bar)
      barStack.append(bar)
    }

    inputField.font = .systemFont(ofSize: 15)
    inputField.textColor = ClawPanelPalette.candidateText
    inputField.backgroundColor = ClawPanelPalette.inputBackground
    inputField.layer.cornerRadius = 10
    inputField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
    inputField.leftViewMode = .always
    // 键盘扩展内禁用系统键盘，保留长按粘贴菜单
    inputField.inputView = UIView()
    inputField.clearButtonMode = .whileEditing
    inputField.delegate = self

    actionButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
    actionButton.setTitleColor(.white, for: .normal)
    actionButton.backgroundColor = ClawPanelPalette.brandBlue
    actionButton.layer.cornerRadius = 10
    actionButton.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(actionButtonLongPressed(_:)))
    longPress.minimumPressDuration = 0.5
    actionButton.addGestureRecognizer(longPress)

    resultLabel.font = .systemFont(ofSize: 13)
    resultLabel.textColor = ClawPanelPalette.candidateText
    resultLabel.numberOfLines = 0
    resultLabel.isHidden = true

    heartTargetButton.setTitleColor(ClawPanelPalette.deepBlue, for: .normal)
    heartTargetButton.titleLabel?.font = .systemFont(ofSize: 13)
    heartTargetButton.showsMenuAsPrimaryAction = true
    refreshHeartTargetMenu()
  }

  private var barStack: [UIView] = []

  private func setupConstraints() {
    [titleLabel, closeButton, aiWaveContainer, inputRow, resultLabel, heartTargetButton].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      addSubview($0)
    }
    [inputField, actionButton].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      inputRow.addSubview($0)
    }

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      closeButton.widthAnchor.constraint(equalToConstant: 26),
      closeButton.heightAnchor.constraint(equalToConstant: 26),

      aiWaveContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
      aiWaveContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      aiWaveContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      aiWaveContainer.heightAnchor.constraint(equalToConstant: 56),

      inputRow.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
      inputRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      inputRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      inputRow.heightAnchor.constraint(equalToConstant: 44),

      inputField.topAnchor.constraint(equalTo: inputRow.topAnchor),
      inputField.bottomAnchor.constraint(equalTo: inputRow.bottomAnchor),
      inputField.leadingAnchor.constraint(equalTo: inputRow.leadingAnchor),
      actionButton.leadingAnchor.constraint(equalTo: inputField.trailingAnchor, constant: 10),
      actionButton.trailingAnchor.constraint(equalTo: inputRow.trailingAnchor),
      actionButton.topAnchor.constraint(equalTo: inputRow.topAnchor),
      actionButton.bottomAnchor.constraint(equalTo: inputRow.bottomAnchor),
      actionButton.widthAnchor.constraint(equalToConstant: 92),

      resultLabel.topAnchor.constraint(equalTo: inputRow.bottomAnchor, constant: 8),
      resultLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      resultLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

      heartTargetButton.topAnchor.constraint(greaterThanOrEqualTo: resultLabel.bottomAnchor, constant: 8),
      heartTargetButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      heartTargetButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
      heartTargetButton.heightAnchor.constraint(equalToConstant: 22),
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
  }

  @objc private func heartProfilesDidChange() {
    DispatchQueue.main.async { [weak self] in
      self?.refreshHeartTargetMenu()
    }
  }

  // MARK: - Tab 刷新

  func refresh(for tab: Int) {
    guard let panelTab = PanelTab(rawValue: tab) else { return }
    let isHelp = panelTab == .helpReply
    let isSuper = panelTab == .superTalk
    aiWaveContainer.isHidden = panelTab != .ai
    inputRow.isHidden = !isHelp && !isSuper
    actionButton.setTitle(isHelp ? "读懂TA" : "优化", for: .normal)
    titleLabel.text = panelTab == .ai ? "AI语音助手" : (isHelp ? "帮你回" : "超会说")
    inputField.placeholder = isHelp ? "+粘贴TA的话" : "输入你想说的话，我们帮你优化"
    inputField.text = ""
    resultLabel.isHidden = true
    if panelTab == .ai {
      startWaveAnimation()
    } else {
      stopWaveAnimation()
    }
  }

  // MARK: - 波形动画（占位）

  private func startWaveAnimation() {
    guard barStack.count == 9 else { return }
    let midY = aiWaveContainer.bounds.midY
    for (index, bar) in barStack.enumerated() {
      let base: CGFloat = 14 + CGFloat((index % 3) * 8)
      bar.frame = CGRect(x: CGFloat(index) * 22, y: midY - base / 2, width: 5, height: base)
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

  // MARK: - 交互

  @objc private func closeTapped() {
    keyboardContext.clawPanelTab = -1
  }

  @objc private func actionButtonTapped() {
    guard !isLoading else { return }
    let text = inputField.text ?? ""
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      resultLabel.isHidden = false
      resultLabel.text = "请先输入或粘贴内容"
      return
    }
    runAnalysis(text: trimmed)
  }

  @objc private func actionButtonLongPressed(_ sender: UILongPressGestureRecognizer) {
    guard sender.state == .began, !isLoading else { return }
    presentPhotoPicker()
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
    resultLabel.isHidden = false
    resultLabel.text = "分析中…"
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
        self.resultLabel.text = reply
      case .failure(let error):
        self.resultLabel.text = "分析失败：\(error.localizedDescription)"
      }
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

// MARK: - UITextFieldDelegate

extension ClawPanelOverlayView: UITextFieldDelegate {
  public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    textField.resignFirstResponder()
    return true
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
            self.resultLabel.isHidden = false
            self.resultLabel.text = "未识别到文字"
          } else {
            self.inputField.text = trimmed
          }
        case .failure(let error):
          self.resultLabel.isHidden = false
          self.resultLabel.text = "识别失败：\(error.localizedDescription)"
        }
      }
    }
  }
}

// MARK: - 更多设置页覆盖层（长按 AI 进入：R / 脑子 / 眼睛）

public final class ClawMorePanelOverlayView: UIView {
  private let keyboardContext: KeyboardContext
  private let actionHandler: KeyboardActionHandler
  private var subscriptions = Set<AnyCancellable>()

  private let backdropView = UIView()
  private let cardView = UIView()
  private let moreAppButton = UIButton(type: .system)
  private let moreGuruButton = UIButton(type: .system)
  private let morePrivacyButton = UIButton(type: .system)
  private let privacyHintLabel = UILabel()

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

    keyboardContext.$clawMorePanelVisible
      .receive(on: DispatchQueue.main)
      .sink { [weak self] visible in
        self?.isHidden = !visible
        self?.refreshPrivacy()
      }
      .store(in: &subscriptions)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupViews() {
    isHidden = true

    backdropView.backgroundColor = ClawPanelPalette.overlayMask
    backdropView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(maskTapped)))

    cardView.backgroundColor = ClawPanelPalette.keyWhite
    cardView.layer.cornerRadius = 20
    cardView.layer.shadowColor = UIColor.black.cgColor
    cardView.layer.shadowOpacity = 0.15
    cardView.layer.shadowRadius = 12
    cardView.layer.shadowOffset = CGSize(width: 0, height: 4)

    moreAppButton.setImage(UIImage(systemName: "r.circle"), for: .normal)
    moreAppButton.setTitle(" 打开输入法", for: .normal)
    moreAppButton.setTitleColor(ClawPanelPalette.deepBlue, for: .normal)
    moreAppButton.addTarget(self, action: #selector(moreAppTapped), for: .touchUpInside)

    moreGuruButton.setImage(UIImage(systemName: "brain.head.profile"), for: .normal)
    moreGuruButton.setTitle(" 打开数据", for: .normal)
    moreGuruButton.setTitleColor(ClawPanelPalette.deepBlue, for: .normal)
    moreGuruButton.addTarget(self, action: #selector(moreGuruTapped), for: .touchUpInside)

    morePrivacyButton.setTitleColor(ClawPanelPalette.deepBlue, for: .normal)
    morePrivacyButton.addTarget(self, action: #selector(morePrivacyTapped), for: .touchUpInside)

    privacyHintLabel.font = .systemFont(ofSize: 12)
    privacyHintLabel.textColor = ClawPanelPalette.candidateText
    privacyHintLabel.textAlignment = .center

    refreshPrivacy()
  }

  private func setupConstraints() {
    [backdropView, cardView].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      addSubview($0)
    }
    [moreAppButton, moreGuruButton, morePrivacyButton, privacyHintLabel].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      cardView.addSubview($0)
    }

    NSLayoutConstraint.activate([
      backdropView.topAnchor.constraint(equalTo: topAnchor),
      backdropView.bottomAnchor.constraint(equalTo: bottomAnchor),
      backdropView.leadingAnchor.constraint(equalTo: leadingAnchor),
      backdropView.trailingAnchor.constraint(equalTo: trailingAnchor),

      cardView.centerXAnchor.constraint(equalTo: centerXAnchor),
      cardView.centerYAnchor.constraint(equalTo: centerYAnchor),
      cardView.widthAnchor.constraint(equalToConstant: 280),
      cardView.heightAnchor.constraint(equalToConstant: 220),

      moreAppButton.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 28),
      moreAppButton.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
      moreAppButton.heightAnchor.constraint(equalToConstant: 44),

      moreGuruButton.topAnchor.constraint(equalTo: moreAppButton.bottomAnchor, constant: 8),
      moreGuruButton.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
      moreGuruButton.heightAnchor.constraint(equalToConstant: 44),

      morePrivacyButton.topAnchor.constraint(equalTo: moreGuruButton.bottomAnchor, constant: 8),
      morePrivacyButton.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
      morePrivacyButton.heightAnchor.constraint(equalToConstant: 44),

      privacyHintLabel.topAnchor.constraint(equalTo: morePrivacyButton.bottomAnchor, constant: 6),
      privacyHintLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
      privacyHintLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
    ])
  }

  private func refreshPrivacy() {
    let collecting = ClawTalkPrivacyService.shared.isCollectionEnabled
    let icon = collecting ? "eye" : "eye.slash"
    morePrivacyButton.setImage(UIImage(systemName: icon), for: .normal)
    morePrivacyButton.setTitle(collecting ? " 隐私采集中（点击暂停）" : " 隐私已暂停（点击采集）", for: .normal)
    morePrivacyButton.tintColor = collecting ? ClawPanelPalette.deepBlue : .systemOrange
    privacyHintLabel.text = collecting
      ? "正在采集输入用于本地分析"
      : "已暂停采集，输入不会被记录"
  }

  @objc private func maskTapped() {
    keyboardContext.clawMorePanelVisible = false
  }

  @objc private func moreAppTapped() {
    keyboardContext.clawMorePanelVisible = false
    actionHandler.handle(.release, on: .url(URL(string: HamsterConstants.appURLForMain), id: "openHamster"))
  }

  @objc private func moreGuruTapped() {
    keyboardContext.clawMorePanelVisible = false
    actionHandler.handle(.release, on: .url(URL(string: HamsterConstants.appURLForGuru), id: "openGuru"))
  }

  @objc private func morePrivacyTapped() {
    ClawTalkPrivacyService.shared.toggle()
    refreshPrivacy()
  }
}