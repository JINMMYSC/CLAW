//
//  PullDownMenuCell.swift
//
//
//  Created by morse on 2023/10/18.
//

import HamsterUIKit
import UIKit

/// 下拉选择按钮
public class PullDownMenuCell: NibLessTableViewCell {
  static let identifier = "PullDownMenuCell"

  var settingItem: SettingItemModel?

  override public var configurationState: UICellConfigurationState {
    var state = super.configurationState
    state.settingItemModel = self.settingItem
    return state
  }

  lazy var titleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.isUserInteractionEnabled = false
    label.isAccessibilityElement = false
    label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    return label
  }()

  lazy var valueButton: UIButton = {
    let valueButton = UIButton(type: .custom)
    valueButton.translatesAutoresizingMaskIntoConstraints = false
    valueButton.isAccessibilityElement = true
    return valueButton
  }()

  lazy var valueLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.textColor = .secondaryLabel
    label.textAlignment = .right
    label.lineBreakMode = .byTruncatingTail
    label.isUserInteractionEnabled = false
    label.isAccessibilityElement = false
    label.accessibilityIdentifier = "PullDownMenuCell.valueLabel"
    label.setContentHuggingPriority(.defaultLow, for: .horizontal)
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return label
  }()

  lazy var chevronView: UIImageView = {
    let imageView = UIImageView(image: UIImage(systemName: "chevron.down"))
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.tintColor = .secondaryLabel
    imageView.isUserInteractionEnabled = false
    imageView.isAccessibilityElement = false
    return imageView
  }()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)

    setupContentView()
  }

  func setupContentView() {
    contentView.addSubview(valueButton)
    contentView.addSubview(titleLabel)
    contentView.addSubview(valueLabel)
    contentView.addSubview(chevronView)

    NSLayoutConstraint.activate([
      valueButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      valueButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      valueButton.topAnchor.constraint(equalTo: contentView.topAnchor),
      valueButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

      titleLabel.topAnchor.constraint(equalToSystemSpacingBelow: contentView.topAnchor, multiplier: 1),
      contentView.bottomAnchor.constraint(equalToSystemSpacingBelow: titleLabel.bottomAnchor, multiplier: 1),
      titleLabel.leadingAnchor.constraint(equalToSystemSpacingAfter: contentView.leadingAnchor, multiplier: 2),

      valueLabel.leadingAnchor.constraint(greaterThanOrEqualToSystemSpacingAfter: titleLabel.trailingAnchor, multiplier: 1),
      valueLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      chevronView.leadingAnchor.constraint(equalToSystemSpacingAfter: valueLabel.trailingAnchor, multiplier: 0.5),
      contentView.trailingAnchor.constraint(equalToSystemSpacingAfter: chevronView.trailingAnchor, multiplier: 1),
      chevronView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
    ])
  }

  func updateWithSettingItem(_ item: SettingItemModel) {
    guard settingItem != item else { return }
    self.settingItem = item
    setNeedsUpdateConfiguration()
  }

  override public func updateConfiguration(using state: UICellConfigurationState) {
    titleLabel.text = state.settingItemModel?.text
    let value = state.settingItemModel?.textValue?()
    valueLabel.text = value
    valueButton.accessibilityLabel = state.settingItemModel?.text
    valueButton.accessibilityValue = value
    if let actions = state.settingItemModel?.pullDownMenuActionsBuilder?() {
      valueButton.menu = UIMenu(title: "", children: actions)
      valueButton.showsMenuAsPrimaryAction = true
    }
  }
}
