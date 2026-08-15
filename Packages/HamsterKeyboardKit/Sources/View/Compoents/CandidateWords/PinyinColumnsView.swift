//
//  PinyinColumnsView.swift
//
//  ClawTalk「IOS 原生布局」候选栏顶部拼音列
//  每个候选词上方一列拼音，列宽与候选词 cell 一致，横向滚动跟随候选词区。
//

import UIKit

/// IOS 原生布局：候选栏顶部拼音列（每个候选词上方一列拼音，与候选词列对齐）
final class PinyinColumnsView: UIScrollView {
  private let containerView = UIView()
  private var columnLabels: [UILabel] = []
  private var containerTrailing: NSLayoutConstraint?

  override init(frame: CGRect) {
    super.init(frame: frame)
    showsHorizontalScrollIndicator = false
    alwaysBounceHorizontal = true
    alwaysBounceVertical = false
    translatesAutoresizingMaskIntoConstraints = false
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

  /// 更新拼音列
  /// - Parameters:
  ///   - pinyins: 每列拼音文本（候选 subtitle）
  ///   - widths: 每列宽度（与候选词 cell 宽度一致）
  ///   - gap: 列间距（与候选词 cell 间距一致）
  func update(pinyins: [String], widths: [CGFloat], font: UIFont, textColor: UIColor, gap: CGFloat = 5) {
    columnLabels.forEach { $0.removeFromSuperview() }
    columnLabels.removeAll()
    if let trailing = containerTrailing {
      trailing.isActive = false
      containerTrailing = nil
    }

    var previous: UILabel?
    for (index, pinyin) in pinyins.enumerated() {
      let label = UILabel()
      label.text = pinyin
      label.font = font
      label.textColor = textColor
      label.textAlignment = .center
      label.adjustsFontSizeToFitWidth = true
      label.minimumScaleFactor = 0.5
      label.numberOfLines = 1
      label.translatesAutoresizingMaskIntoConstraints = false
      containerView.addSubview(label)
      columnLabels.append(label)

      let width = index < widths.count ? widths[index] : 0
      NSLayoutConstraint.activate([
        label.topAnchor.constraint(equalTo: containerView.topAnchor),
        label.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        label.widthAnchor.constraint(equalToConstant: width)
      ])
      if let previous = previous {
        label.leadingAnchor.constraint(equalTo: previous.trailingAnchor, constant: gap).isActive = true
      } else {
        label.leadingAnchor.constraint(equalTo: containerView.leadingAnchor)
      }
      previous = label
    }

    if let last = previous {
      containerTrailing = containerView.trailingAnchor.constraint(equalTo: last.trailingAnchor)
    } else {
      containerTrailing = containerView.trailingAnchor.constraint(equalTo: trailingAnchor)
    }
    containerTrailing?.isActive = true
    layoutIfNeeded()
  }
}
