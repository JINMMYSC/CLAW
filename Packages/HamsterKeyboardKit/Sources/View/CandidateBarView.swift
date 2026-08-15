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

  /// IOS 原生布局：上栏拼音列（每个候选词上方一列拼音）
  lazy var pinyinColumnsView: PinyinColumnsView = {
    let view = PinyinColumnsView()
    view.isUserInteractionEnabled = false
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
    if !keyboardContext.enableEmbeddedInputMode {
      addSubview(phoneticLabel)
      if keyboardContext.useIOSNativeLayout {
        // IOS 原生布局：单行拼音文本隐藏，改用逐列拼音 + 分隔线
        phoneticLabel.isHidden = true
        addSubview(separatorLine)
        addSubview(pinyinColumnsView)
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
    let codingAreaHeight: CGFloat = keyboardContext.heightOfCodingArea
    let controlStateHeight: CGFloat = keyboardContext.heightOfToolbar - (keyboardContext.enableEmbeddedInputMode ? 0 : codingAreaHeight)
    let candidatesView = keyboardContext.swipePaging ? candidatesArea : candidatesPagingArea

    /// 内嵌模式
    if keyboardContext.enableEmbeddedInputMode {
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
      // IOS 原生布局：上栏拼音列 + 分隔线 + 候选词区；其余布局保持原逻辑
      let isNative = keyboardContext.useIOSNativeLayout
      let topView = isNative ? separatorLine : phoneticLabel
      if isNative {
        NSLayoutConstraint.activate([
          pinyinColumnsView.topAnchor.constraint(equalTo: topAnchor),
          pinyinColumnsView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
          pinyinColumnsView.trailingAnchor.constraint(equalTo: trailingAnchor),
          pinyinColumnsView.heightAnchor.constraint(equalToConstant: codingAreaHeight),

          separatorLine.topAnchor.constraint(equalTo: pinyinColumnsView.bottomAnchor),
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
      updatePinyinColumns()
    }

    if keyboardContext.swipePaging {
      candidatesArea.setupStyle(style)
    } else {
      candidatesPagingArea.setupStyle(style)
    }
  }

  /// IOS 原生布局：候选词变化时刷新上栏拼音列；候选词横滑时同步滚动
  func combine() {
    guard keyboardContext.useIOSNativeLayout else { return }
    rimeContext.$suggestions
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updatePinyinColumns()
      }
      .store(in: &subscriptions)

    candidatesArea.publisher(for: \.contentOffset)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] offset in
        self?.pinyinColumnsView.contentOffset = offset
      }
      .store(in: &subscriptions)
  }

  /// 按候选词列宽生成上栏拼音列（宽度算法与候选词 cell 一致）
  func updatePinyinColumns() {
    guard keyboardContext.useIOSNativeLayout else { return }
    let pinyins = rimeContext.suggestions.map { $0.subtitle ?? "" }
    let widths = rimeContext.suggestions.map { suggestion -> CGFloat in
      let attr = suggestion.attributeString(showIndex: false, showComment: false, style: style)
      let size = UILabel.estimatedAttributeSize(attr, targetSize: CGSize(width: 1000, height: 0))
      var width = size.width + 14
      if attr.string.count == 1, let minWidth = UILabel.fontSizeAndMinWidthMapping[style.candidateTextFont.pointSize] {
        width = minWidth + 14
      }
      return width
    }
    pinyinColumnsView.update(
      pinyins: pinyins,
      widths: widths,
      font: style.phoneticTextFont,
      textColor: style.phoneticTextColor
    )
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
