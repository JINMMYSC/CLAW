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
    valueButton.setTitleColor(.secondaryLabel, for: .normal)
    valueButton.contentHorizontalAlignment = .trailing
    valueButton.translatesAutoresizingMaskIntoConstraints = false
    valueButton.tintColor = .secondaryLabel
    valueButton.isAccessibilityElement = true

    valueButton.configuration = UIButton.Configuration.plain()
    valueButton.configuration?.image = UIImage(systemName: "chevron.down")
    valueButton.configuration?.imagePlacement = .trailing

    valueButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    return valueButton
  }()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)

    setupContentView()
  }

  func setupContentView() {
    contentView.addSubview(valueButton)
    contentView.addSubview(titleLabel)

    NSLayoutConstraint.activate([
      valueButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      valueButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      valueButton.topAnchor.constraint(equalTo: contentView.topAnchor),
      valueButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

      titleLabel.topAnchor.constraint(equalToSystemSpacingBelow: contentView.topAnchor, multiplier: 1),
      contentView.bottomAnchor.constraint(equalToSystemSpacingBelow: titleLabel.bottomAnchor, multiplier: 1),
      titleLabel.leadingAnchor.constraint(equalToSystemSpacingAfter: contentView.leadingAnchor, multiplier: 2),
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
    valueButton.setTitle(value, for: .normal)
    valueButton.accessibilityLabel = state.settingItemModel?.text
    valueButton.accessibilityValue = value
    if let actions = state.settingItemModel?.pullDownMenuActionsBuilder?() {
      valueButton.menu = UIMenu(title: "", children: actions)
      valueButton.showsMenuAsPrimaryAction = true
    }
  }
}
