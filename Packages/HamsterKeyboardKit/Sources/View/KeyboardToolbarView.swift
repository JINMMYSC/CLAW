//
//  KeyboardToolbarView.swift
//
//
//  Created by morse on 2023/8/19.
//
//  咕噜改版：R / 更多 / 大脑AI / 眼睛开关 / 下拉收起

import Combine
import HamsterKit
import HamsterUIKit
import UIKit

class KeyboardToolbarView: NibLessView {
  private let appearance: KeyboardAppearance
  private let actionHandler: KeyboardActionHandler
  private let keyboardContext: KeyboardContext
  private var rimeContext: RimeContext
  /// 所属键盘根视图（用于在其上弹浮层面板）
  weak var rootView: KeyboardRootView?
  private var style: CandidateBarStyle
  private var userInterfaceStyle: UIUserInterfaceStyle
  private var oldBounds: CGRect = .zero
  private var subscriptions = Set<AnyCancellable>()

  /// R 键：弹出更多功能面板
  lazy var moreButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "r.circle"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 17), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.layer.cornerRadius = 6
    button.addTarget(self, action: #selector(moreButtonTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(moreButtonTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// 大脑 AI 键：弹出智能建议面板
  lazy var guruButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "brain.head.profile"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 17), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.layer.cornerRadius = 6
    button.addTarget(self, action: #selector(guruButtonTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(guruButtonTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// 眼睛键：隐私采集开关（点击切换，长按看说明）
  lazy var privacyButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 17), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.layer.cornerRadius = 6
    button.addTarget(self, action: #selector(privacyButtonTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(privacyButtonTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(privacyLongPress(_:)))
    button.addGestureRecognizer(longPress)
    return button
  }()

  /// 下拉收起键：收起/展开候选栏
  lazy var dismissKeyboardButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "chevron.down"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 17), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.layer.cornerRadius = 6
    button.addTarget(self, action: #selector(dismissKeyboardTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(dismissKeyboardTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// 候选栏视图
  lazy var candidateBarView: CandidateBarView = {
    let view = CandidateBarView(
      style: style,
      actionHandler: actionHandler,
      keyboardContext: keyboardContext,
      rimeContext: rimeContext,
      showControlState: false
    )
    return view
  }()

  /// R 面板
  lazy var morePanel: GuruMorePanel = {
    let panel = GuruMorePanel()
    panel.translatesAutoresizingMaskIntoConstraints = false
    panel.alpha = 0
    panel.onSelect = { [weak self] route in
      self?.openSubView(route)
      self?.closeMorePanel()
    }
    return panel
  }()

  /// AI 面板
  lazy var aiPanel: GuruAIPanel = {
    let panel = GuruAIPanel()
    panel.translatesAutoresizingMaskIntoConstraints = false
    panel.alpha = 0
    panel.onInsert = { [weak self] text in
      self?.keyboardContext.textDocumentProxy.insertText(text)
      self?.closeAIPanel()
    }
    panel.onClose = { [weak self] in
      self?.closeAIPanel()
    }
    return panel
  }()

  /// 轻提示
  private lazy var toastLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 11)
    label.textColor = .white
    label.textAlignment = .center
    label.backgroundColor = UIColor.black.withAlphaComponent(0.75)
    label.layer.cornerRadius = 5
    label.clipsToBounds = true
    label.alpha = 0
    return label
  }()

  private var isMorePanelOpen = false
  private var isAIPanelOpen = false

  init(appearance: KeyboardAppearance, actionHandler: KeyboardActionHandler, keyboardContext: KeyboardContext, rimeContext: RimeContext) {
    self.appearance = appearance
    self.actionHandler = actionHandler
    self.keyboardContext = keyboardContext
    self.rimeContext = rimeContext
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
  }

  override func constructViewHierarchy() {
    addSubview(candidateBarView)
    addSubview(moreButton)
    addSubview(guruButton)
    addSubview(privacyButton)
    addSubview(dismissKeyboardButton)
    addSubview(toastLabel)
    updatePrivacyButtonAppearance()
  }

  override func activateViewConstraints() {
    let buttonSize: CGFloat = 26
    NSLayoutConstraint.activate([
      // R 键置于最左侧
      moreButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
      moreButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      moreButton.widthAnchor.constraint(equalToConstant: buttonSize),
      moreButton.heightAnchor.constraint(equalToConstant: buttonSize),

      // 下拉收起键置于最右侧
      dismissKeyboardButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
      dismissKeyboardButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      dismissKeyboardButton.widthAnchor.constraint(equalToConstant: buttonSize),
      dismissKeyboardButton.heightAnchor.constraint(equalToConstant: buttonSize),

      // 眼睛开关
      privacyButton.trailingAnchor.constraint(equalTo: dismissKeyboardButton.leadingAnchor, constant: -2),
      privacyButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      privacyButton.widthAnchor.constraint(equalToConstant: buttonSize),
      privacyButton.heightAnchor.constraint(equalToConstant: buttonSize),

      // 大脑 AI 键
      guruButton.trailingAnchor.constraint(equalTo: privacyButton.leadingAnchor, constant: -2),
      guruButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      guruButton.widthAnchor.constraint(equalToConstant: buttonSize),
      guruButton.heightAnchor.constraint(equalToConstant: buttonSize),

      // 候选区
      candidateBarView.leadingAnchor.constraint(equalTo: moreButton.trailingAnchor, constant: 4),
      candidateBarView.trailingAnchor.constraint(equalTo: guruButton.leadingAnchor, constant: -4),
      candidateBarView.topAnchor.constraint(equalTo: topAnchor),
      candidateBarView.bottomAnchor.constraint(equalTo: bottomAnchor),

      // 轻提示
      toastLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      toastLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3),
      toastLabel.heightAnchor.constraint(equalToConstant: 20),
      toastLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),
    ])
  }

  override func setupAppearance() {
    self.style = appearance.candidateBarStyle
    moreButton.tintColor = style.toolbarButtonFrontColor
    guruButton.tintColor = style.toolbarButtonFrontColor
    dismissKeyboardButton.tintColor = style.toolbarButtonFrontColor
    updatePrivacyButtonAppearance()
    candidateBarView.setStyle(self.style)
  }

  func updatePrivacyButtonAppearance() {
    let collecting = GURUPrivacyService.shared.isCollectionEnabled
    let icon = collecting ? "eye" : "eye.slash"
    privacyButton.setImage(UIImage(systemName: icon), for: .normal)
    privacyButton.tintColor = collecting ? style.toolbarButtonFrontColor : .systemOrange
    guruButton.alpha = collecting ? 1 : 0.4
  }

  private func updateDismissButtonIcon() {
    let collapsed = keyboardContext.candidatesViewState.isCollapse()
    dismissKeyboardButton.setImage(UIImage(systemName: collapsed ? "chevron.up" : "chevron.down"), for: .normal)
  }

  func combine() {
    rimeContext.userInputKeyPublished
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in
        guard let self = self else { return }
        let isEmpty = $0.isEmpty
        if self.keyboardContext.keyboardType.isChineseNineGrid {
          self.candidateBarView.phoneticLabel.text = self.rimeContext.t9UserInputKey
        } else {
          self.candidateBarView.phoneticLabel.text = $0
        }
        // 输入内容为空时隐藏拼音标签
        self.candidateBarView.phoneticLabel.isHidden = isEmpty
      }
      .store(in: &subscriptions)

    keyboardContext.$candidatesViewState
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateDismissButtonIcon()
      }
      .store(in: &subscriptions)
  }

  // MARK: - 按钮事件

  @objc private func openSubView(_ route: String) {
    let url = URL(string: "hamster://app.lgm.7517/\(route)")
    if let url {
      actionHandler.handle(.release, on: .url(url, id: "openGuruSubView"))
    }
  }

  @objc func moreButtonTouchDownAction() {
    moreButton.backgroundColor = style.toolbarButtonPressedBackgroundColor
  }

  @objc func moreButtonTouchUpAction() {
    moreButton.backgroundColor = style.toolbarButtonBackgroundColor
    toggleMorePanel()
  }

  @objc func guruButtonTouchDownAction() {
    guruButton.backgroundColor = style.toolbarButtonPressedBackgroundColor
  }

  @objc func guruButtonTouchUpAction() {
    guruButton.backgroundColor = style.toolbarButtonBackgroundColor
    guard GURUPrivacyService.shared.isCollectionEnabled else {
      showToast("已暂停采集，请先打开采集")
      return
    }
    toggleAIPanel()
  }

  @objc func privacyButtonTouchDownAction() {
    privacyButton.backgroundColor = style.toolbarButtonPressedBackgroundColor
  }

  @objc func privacyButtonTouchUpAction() {
    privacyButton.backgroundColor = style.toolbarButtonBackgroundColor
    let collecting = GURUPrivacyService.shared.toggle()
    updatePrivacyButtonAppearance()
    showToast(collecting ? "已开启采集" : "已暂停采集，隐私模式")
  }

  @objc func privacyLongPress(_ gesture: UILongPressGestureRecognizer) {
    guard gesture.state == .began else { return }
    showToast("开启=采集输入记录；关闭=隐私模式暂停采集")
  }

  @objc func dismissKeyboardTouchDownAction() {
    dismissKeyboardButton.backgroundColor = style.toolbarButtonPressedBackgroundColor
  }

  @objc func dismissKeyboardTouchUpAction() {
    dismissKeyboardButton.backgroundColor = style.toolbarButtonBackgroundColor
    let next: CandidateBarView.State = keyboardContext.candidatesViewState.isCollapse() ? .expand : .collapse
    keyboardContext.candidatesViewState = next
    updateDismissButtonIcon()
  }

  @objc func touchCancel() {
    moreButton.backgroundColor = style.toolbarButtonBackgroundColor
    guruButton.backgroundColor = style.toolbarButtonBackgroundColor
    privacyButton.backgroundColor = style.toolbarButtonBackgroundColor
    dismissKeyboardButton.backgroundColor = style.toolbarButtonBackgroundColor
  }

  private func toggleMorePanel() {
    if isMorePanelOpen {
      closeMorePanel()
    } else {
      openMorePanel()
    }
  }

  private func openMorePanel() {
    closeAIPanel()
    isMorePanelOpen = true
    rootView?.presentOverlayPanel(morePanel, below: moreButton, width: 224, height: GuruMorePanel.preferredHeight, leadingConstant: 8, topOffset: 4)
  }

  private func closeMorePanel() {
    guard isMorePanelOpen else { return }
    isMorePanelOpen = false
    rootView?.dismissOverlayPanel(morePanel)
  }

  private func toggleAIPanel() {
    if isAIPanelOpen {
      closeAIPanel()
    } else {
      openAIPanel()
    }
  }

  private func openAIPanel() {
    closeMorePanel()
    isAIPanelOpen = true
    rootView?.presentOverlayPanel(aiPanel, below: guruButton, width: 250, height: GuruAIPanel.preferredHeight, trailingConstant: -8, topOffset: 4)
    requestAISuggestions()
  }

  private func closeAIPanel() {
    guard isAIPanelOpen else { return }
    isAIPanelOpen = false
    rootView?.dismissOverlayPanel(aiPanel)
  }

  private func requestAISuggestions() {
    let pinyin: String
    if keyboardContext.keyboardType.isChineseNineGrid {
      pinyin = rimeContext.t9UserInputKey
    } else {
      pinyin = rimeContext.userInputKey
    }
    aiPanel.requestSuggestions(pinyin: pinyin)
  }

  // MARK: - Toast

  private func showToast(_ text: String) {
    toastLabel.text = text
    UIView.animate(withDuration: 0.15) {
      self.toastLabel.alpha = 1
    }
    NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideToast), object: nil)
    perform(#selector(hideToast), with: nil, afterDelay: 1.6)
  }

  @objc private func hideToast() {
    UIView.animate(withDuration: 0.2) {
      self.toastLabel.alpha = 0
    }
  }
}
