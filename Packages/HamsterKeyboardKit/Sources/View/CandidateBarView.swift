//
//  CandidateWordsView.swift
//
//
//  Created by morse on 2023/8/19.
//

import Combine
import HamsterKit
import HamsterUIKit
import UIKit

/**
 候选栏视图
 */
public class CandidateBarView: NibLessView {
  /// 候选区状态
  public enum State {
    /// 展开
    case expand
    /// 收起
    case collapse

    func isCollapse() -> Bool {
      return self == .collapse
    }
  }

  private var style: CandidateBarStyle
  private var actionHandler: KeyboardActionHandler
  private var keyboardContext: KeyboardContext
  private var rimeContext: RimeContext
  private var userInterfaceStyle: UIUserInterfaceStyle
  private var subscriptions = Set<AnyCancellable>()

  /// 拼音Label
  lazy var phoneticLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.textAlignment = .left
    label.numberOfLines = 1
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.5
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  /// 划动分页的候选文字区域
  lazy var candidatesArea: CandidateWordsCollectionView = {
    let view = CandidateWordsCollectionView(
      style: style,
      keyboardContext: keyboardContext,
      actionHandler: actionHandler,
      rimeContext: rimeContext)
    view.backgroundColor = .clear
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  /// 手动分页的候选文字区域
  lazy var candidatesPagingArea: CandidatesPagingCollectionView = {
    let view = CandidatesPagingCollectionView(
      style: style,
      keyboardContext: keyboardContext,
      actionHandler: actionHandler,
      rimeContext: rimeContext)
    view.backgroundColor = .clear
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  /// 状态图片视图
  lazy var stateImageView: UIImageView = {
    let view = UIImageView(frame: .zero)
    view.contentMode = .center
    view.translatesAutoresizingMaskIntoConstraints = false
    view.image = stateImage(.collapse)
    return view
  }()

  /// 竖线
  lazy var verticalLine: UIView = {
    let view = UIView(frame: .zero)
    view.backgroundColor = .secondarySystemFill
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  /// 候选区展开或收起控制按钮
  lazy var controlStateView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .clear
    view.addSubview(stateImageView)
    view.addSubview(verticalLine)

    NSLayoutConstraint.activate([
      verticalLine.topAnchor.constraint(equalTo: view.topAnchor, constant: 3),
      view.bottomAnchor.constraint(equalTo: verticalLine.bottomAnchor, constant: 3),
      view.leadingAnchor.constraint(equalTo: verticalLine.leadingAnchor),
      verticalLine.widthAnchor.constraint(equalToConstant: 1),

      stateImageView.leadingAnchor.constraint(equalTo: verticalLine.trailingAnchor),
      stateImageView.topAnchor.constraint(equalTo: view.topAnchor),
      stateImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      stateImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
    ])

    // 添加状态控制
    view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(changeState)))
    return view
  }()

  /// IOS 原生布局：上排音节 chips 条（横向滚动、点选筛选音节）
  lazy var syllableChipsView: SyllableChipsView = {
    let view = SyllableChipsView()
    view.onChipTap = { [weak self] index in
      self?.handleSyllableChipTap(index)
    }
    return view
  }()

  /// IOS 原生布局：上栏与下栏之间的分隔线
  lazy var separatorLine: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  // MARK: - 计算属性

  /// 布局配置
  private var layoutConfig: KeyboardLayoutConfiguration {
    .standard(for: keyboardContext)
  }

  init(style: CandidateBarStyle, actionHandler: KeyboardActionHandler, keyboardContext: KeyboardContext, rimeContext: RimeContext) {
    self.style = style
    self.actionHandler = actionHandler
    self.keyboardContext = keyboardContext
    self.rimeContext = rimeContext
    self.userInterfaceStyle = keyboardContext.colorScheme

    super.init(frame: .zero)

    setupContentView()
  }

  func setupContentView() {
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
    combine()
  }

  /// 构建视图层次
  override public func constructViewHierarchy() {
    // 非内嵌模式添加拼写区域
    if !keyboardContext.enableEmbeddedInputMode || keyboardContext.useIOSNativeLayout {
      addSubview(phoneticLabel)
      if keyboardContext.useIOSNativeLayout {
        // IOS 原生布局：单行拼音文本隐藏，改用音节 chips + 分隔线
        phoneticLabel.isHidden = true
        addSubview(separatorLine)
        addSubview(syllableChipsView)
      }
    }
    if keyboardContext.swipePaging {
      addSubview(candidatesArea)
      addSubview(controlStateView)
    } else {
      addSubview(candidatesPagingArea)
    }
  }

  /// 激活视图约束
  override public func activateViewConstraints() {
    let buttonInsets = layoutConfig.buttonInsets
    let codingAreaHeight: CGFloat = keyboardContext.useIOSNativeLayout ? 15 : keyboardContext.heightOfCodingArea
    let controlStateHeight: CGFloat = keyboardContext.heightOfToolbar - ((keyboardContext.enableEmbeddedInputMode && !keyboardContext.useIOSNativeLayout) ? 0 : codingAreaHeight)
    let candidatesView = keyboardContext.swipePaging ? candidatesArea : candidatesPagingArea

    /// 内嵌模式
    if keyboardContext.enableEmbeddedInputMode && !keyboardContext.useIOSNativeLayout {
      if keyboardContext.swipePaging {
        NSLayoutConstraint.activate([
          candidatesView.topAnchor.constraint(equalTo: topAnchor),
          candidatesView.bottomAnchor.constraint(equalTo: bottomAnchor),
          candidatesView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
          candidatesView.trailingAnchor.constraint(equalTo: controlStateView.leadingAnchor),

          controlStateView.heightAnchor.constraint(equalTo: controlStateView.widthAnchor, multiplier: 1.0),
          controlStateView.topAnchor.constraint(equalTo: topAnchor),
          controlStateView.trailingAnchor.constraint(equalTo: trailingAnchor),
          controlStateView.heightAnchor.constraint(equalToConstant: controlStateHeight)
        ])
      } else {
        NSLayoutConstraint.activate([
          candidatesView.topAnchor.constraint(equalTo: topAnchor),
          candidatesView.bottomAnchor.constraint(equalTo: bottomAnchor),
          candidatesView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
          candidatesView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -buttonInsets.right)
        ])
      }
    } else {
      // IOS 原生布局：上排音节条 + 分隔线 + 候选词区；其余布局保持原逻辑
      let isNative = keyboardContext.useIOSNativeLayout
      let topView = isNative ? separatorLine : phoneticLabel
      if isNative {
        NSLayoutConstraint.activate([
          syllableChipsView.topAnchor.constraint(equalTo: topAnchor),
          syllableChipsView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
          syllableChipsView.trailingAnchor.constraint(equalTo: trailingAnchor),
          syllableChipsView.heightAnchor.constraint(equalToConstant: codingAreaHeight),

          separatorLine.topAnchor.constraint(equalTo: syllableChipsView.bottomAnchor),
          separatorLine.leadingAnchor.constraint(equalTo: leadingAnchor),
          separatorLine.trailingAnchor.constraint(equalTo: trailingAnchor),
          separatorLine.heightAnchor.constraint(equalToConstant: 1)
        ])
      }
      if keyboardContext.swipePaging {
        NSLayoutConstraint.activate([
          phoneticLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
          phoneticLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
          phoneticLabel.topAnchor.constraint(equalTo: topAnchor),
          phoneticLabel.heightAnchor.constraint(equalToConstant: codingAreaHeight),

          candidatesView.topAnchor.constraint(equalTo: topView.bottomAnchor),
          candidatesView.bottomAnchor.constraint(equalTo: bottomAnchor),
          candidatesView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
          candidatesView.trailingAnchor.constraint(equalTo: controlStateView.leadingAnchor),

          controlStateView.heightAnchor.constraint(equalTo: controlStateView.widthAnchor, multiplier: 1.0),
          controlStateView.topAnchor.constraint(equalTo: topView.bottomAnchor),
          controlStateView.trailingAnchor.constraint(equalTo: trailingAnchor),
          controlStateView.heightAnchor.constraint(equalToConstant: controlStateHeight)
        ])
      } else {
        NSLayoutConstraint.activate([
          phoneticLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
          phoneticLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
          phoneticLabel.topAnchor.constraint(equalTo: topAnchor),
          phoneticLabel.heightAnchor.constraint(equalToConstant: codingAreaHeight),

          candidatesView.topAnchor.constraint(equalTo: topView.bottomAnchor),
          candidatesView.bottomAnchor.constraint(equalTo: bottomAnchor),
          candidatesView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
          candidatesView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -buttonInsets.right)
        ])
      }
    }
  }

  override public func setupAppearance() {
    phoneticLabel.font = style.phoneticTextFont
    phoneticLabel.textColor = style.phoneticTextColor
    stateImageView.tintColor = style.candidateTextColor

    if keyboardContext.useIOSNativeLayout {
      // 分隔线：浅色 #C7C7CC / 深色 #48484A
      separatorLine.backgroundColor = UIColor { trait in
        trait.userInterfaceStyle == .dark
          ? UIColor(red: 72 / 255, green: 72 / 255, blue: 74 / 255, alpha: 1)
          : UIColor(red: 199 / 255, green: 199 / 255, blue: 204 / 255, alpha: 1)
      }
      updateSyllableChips()
    }

    if keyboardContext.swipePaging {
      candidatesArea.setupStyle(style)
    } else {
      candidatesPagingArea.setupStyle(style)
    }
  }

  /// IOS 原生布局：候选变化/选中音节变化时刷新上排音节 chips
  func combine() {
    guard keyboardContext.useIOSNativeLayout else { return }
    rimeContext.$suggestions
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateSyllableChips()
      }
      .store(in: &subscriptions)

    rimeContext.$selectedSyllableIndex
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateSyllableChips()
      }
      .store(in: &subscriptions)
  }

  /// 按音节分组刷新上排 chips（含高亮）
  func updateSyllableChips() {
    guard keyboardContext.useIOSNativeLayout else { return }
    let groups = rimeContext.getSyllableCandidates()
    let selectedIndex = min(max(rimeContext.selectedSyllableIndex, 0), max(0, groups.count - 1))
    syllableChipsView.update(
      pinyins: groups.map { $0.pinyin },
      selectedIndex: selectedIndex,
      font: style.phoneticTextFont,
      normalTextColor: style.phoneticTextColor,
      selectedTextColor: style.preferredCandidateTextColor,
      selectedBackgroundColor: style.preferredCandidateBackgroundColor
    )
  }

  /// 点击音节 chip：替换输入串为该音节拼音（与选拼音键同法），
  /// Rime 重新组字后下排候选刷新为该音节的字
  func handleSyllableChipTap(_ index: Int) {
    guard keyboardContext.useIOSNativeLayout else { return }
    let groups = rimeContext.getSyllableCandidates()
    guard index >= 0, index < groups.count else { return }
    rimeContext.selectedSyllableIndex = index
    let replaceText = groups[index].pinyin.replacingOccurrences(of: " ", with: "")
    guard !replaceText.isEmpty else { return }
    let inputKeys = rimeContext.getInputKeys()
    _ = rimeContext.tryHandleReplaceInputTexts(replaceText, startPos: 0, count: inputKeys.utf8.count)
  }

  func setStyle(_ style: CandidateBarStyle) {
    self.style = style
    setupAppearance()
  }

  @objc func changeState() {
    let state: State = keyboardContext.candidatesViewState.isCollapse() ? .expand : .collapse
    stateImageView.image = stateImage(state)
    verticalLine.isHidden = state == .expand
    keyboardContext.candidatesViewState = state
  }

  // 状态图片
  func stateImage(_ state: State) -> UIImage? {
    let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular, scale: .default)
    return state == .collapse
      ? UIImage(systemName: "chevron.down", withConfiguration: config)
      : UIImage(systemName: "chevron.up", withConfiguration: config)
  }
}

/// IOS 原生布局：候选栏上排音节 chips 条
/// 横向滚动、点选高亮；点选回调由 CandidateBarView 处理（替换输入串）
final class SyllableChipsView: UIScrollView {
  private let containerView = UIView()
  private var chips: [UIButton] = []
  private var containerTrailing: NSLayoutConstraint?

  /// chip 点击回调（参数为音节分组索引）
  var onChipTap: ((Int) -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    showsHorizontalScrollIndicator = false
    alwaysBounceHorizontal = true
    alwaysBounceVertical = false
    containerView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(containerView)
    NSLayoutConstraint.activate([
      containerView.topAnchor.constraint(equalTo: topAnchor),
      containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
      containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
      containerView.heightAnchor.constraint(equalTo: heightAnchor)
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// 重建音节 chips
  /// - Parameters:
  ///   - pinyins: 音节拼音文本（可含空格，如 "ni hao"）
  ///   - selectedIndex: 当前高亮的分组索引
  func update(
    pinyins: [String],
    selectedIndex: Int,
    font: UIFont,
    normalTextColor: UIColor,
    selectedTextColor: UIColor,
    selectedBackgroundColor: UIColor
  ) {
    chips.forEach { $0.removeFromSuperview() }
    chips.removeAll()
    if let trailing = containerTrailing {
      trailing.isActive = false
      containerTrailing = nil
    }

    var previous: UIButton?
    for (index, pinyin) in pinyins.enumerated() {
      let isSelected = index == selectedIndex
      let button = UIButton(type: .custom)
      button.setTitle(pinyin, for: .normal)
      button.titleLabel?.font = font
      button.titleLabel?.adjustsFontSizeToFitWidth = true
      button.titleLabel?.minimumScaleFactor = 0.6
      let textColor = isSelected ? selectedTextColor : normalTextColor
      button.setTitleColor(textColor, for: .normal)
      button.setTitleColor(textColor, for: .highlighted)
      button.backgroundColor = isSelected ? selectedBackgroundColor : .clear
      button.layer.cornerRadius = 6
      button.clipsToBounds = true
      button.contentEdgeInsets = UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
      button.tag = index
      button.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
      button.translatesAutoresizingMaskIntoConstraints = false
      containerView.addSubview(button)
      chips.append(button)

      NSLayoutConstraint.activate([
        button.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 1.5),
        button.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -1.5)
      ])
      if let previous = previous {
        button.leadingAnchor.constraint(equalTo: previous.trailingAnchor, constant: 5).isActive = true
      } else {
        button.leadingAnchor.constraint(equalTo: containerView.leadingAnchor).isActive = true
      }
      previous = button
    }

    if let last = previous {
      containerTrailing = containerView.trailingAnchor.constraint(equalTo: last.trailingAnchor)
    } else {
      containerTrailing = containerView.trailingAnchor.constraint(equalTo: trailingAnchor)
    }
    containerTrailing?.isActive = true
    layoutIfNeeded()
  }

  @objc private func chipTapped(_ sender: UIButton) {
    onChipTap?(sender.tag)
  }
}
