//
//  GuruMorePanel.swift
//  GuruIM 的 R 键更多功能面板
//
//  Created by Codex 2026/8/12.
//

import UIKit

/// R 键弹出的 5 项快捷功能
class GuruMorePanel: UIView {
  var onSelect: ((String) -> Void)?

  private let items: [(title: String, route: String, icon: String)] = [
    ("打开咕噜App", "main", "app.badge"),
    ("GURU数据", "guru", "brain.head.profile"),
    ("剪贴板", "guru", "doc.on.clipboard"),
    ("常用语", "rime", "text.quote"),
    ("设置", "keyboardSettings", "gearshape"),
  ]

  private lazy var stackView: UIStackView = {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 0
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    setup()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setup() {
    backgroundColor = .secondarySystemBackground
    layer.cornerRadius = 12
    layer.masksToBounds = true

    addSubview(stackView)
    NSLayoutConstraint.activate([
      stackView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
      stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
      stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
      stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
    ])

    for (index, item) in items.enumerated() {
      let row = makeRow(title: item.title, icon: item.icon, tag: index)
      stackView.addArrangedSubview(row)
    }
  }

  private func makeRow(title: String, icon: String, tag: Int) -> UIButton {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle(title, for: .normal)
    button.setImage(UIImage(systemName: icon), for: .normal)
    button.tintColor = .label
    button.setTitleColor(.label, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 15)
    button.contentHorizontalAlignment = .leading
    button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 12)
    button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 0)
    button.tag = tag
    button.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)
    button.heightAnchor.constraint(equalToConstant: 38).isActive = true
    return button
  }

  @objc private func rowTapped(_ sender: UIButton) {
    let index = sender.tag
    guard index >= 0, index < items.count else { return }
    onSelect?(items[index].route)
  }

  /// 面板期望高度
  static var preferredHeight: CGFloat {
    6 + 5 * 38 + 6
  }
}
