//
//  GuruAIPanel.swift
//  GuruIM 悬浮式 AI 建议面板
//
//  Created by Codex 2026/8/12.
//

import HamsterKit
import UIKit

/// 根据当前拼音请求 AI 建议 -> AIService -> 生成 3-5 条候选
class GuruAIPanel: UIView {
  var onInsert: ((String) -> Void)?
  var onClose: (() -> Void)?

  private var isLoading = false

  private lazy var titleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.text = "AI建议"
    label.font = .systemFont(ofSize: 13, weight: .semibold)
    label.textColor = .label
    return label
  }()

  private lazy var spinner: UIActivityIndicatorView = {
    let view = UIActivityIndicatorView(style: .medium)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.hidesWhenStopped = true
    return view
  }()

  private lazy var messageLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    label.textAlignment = .center
    return label
  }()

  private lazy var buttonsStack: UIStackView = {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 6
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

    addSubview(titleLabel)
    addSubview(spinner)
    addSubview(buttonsStack)
    addSubview(messageLabel)

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),

      spinner.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      spinner.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),

      buttonsStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
      buttonsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      buttonsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      buttonsStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),

      messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
      messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      messageLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),
    ])
  }

  func showLoading() {
    isLoading = true
    spinner.startAnimating()
    messageLabel.isHidden = true
    buttonsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    buttonsStack.isHidden = true
  }

  func showSuggestions(_ texts: [String]) {
    isLoading = false
    spinner.stopAnimating()
    messageLabel.isHidden = true
    buttonsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for text in texts {
      let button = makeSuggestionButton(text)
      buttonsStack.addArrangedSubview(button)
    }
    buttonsStack.isHidden = texts.isEmpty
    if texts.isEmpty {
      messageLabel.text = "未生成建议，请重试"
      messageLabel.isHidden = false
    }
  }

  func showMessage(_ text: String) {
    isLoading = false
    spinner.stopAnimating()
    buttonsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    buttonsStack.isHidden = true
    messageLabel.text = text
    messageLabel.isHidden = false
  }

  private func makeSuggestionButton(_ text: String) -> UIButton {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle(text, for: .normal)
    button.setTitleColor(.label, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 15)
    button.backgroundColor = .tertiarySystemBackground
    button.layer.cornerRadius = 8
    button.contentHorizontalAlignment = .leading
    button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
    button.heightAnchor.constraint(equalToConstant: 34).isActive = true
    button.addTarget(self, action: #selector(suggestionTapped(_:)), for: .touchUpInside)
    return button
  }

  @objc private func suggestionTapped(_ sender: UIButton) {
    guard let text = sender.title(for: .normal), !text.isEmpty else { return }
    onInsert?(text)
  }

  /// 请求 AI 建议
  func requestSuggestions(pinyin: String) {
    guard !isLoading else { return }
    showLoading()
    let trimmed = pinyin.trimmingCharacters(in: .whitespacesAndNewlines)
    let prompt = "用户正在用九宫格拼音输入，当前拼音：" + trimmed + "。请给出3-5个用户最可能想输入的中文词语或短句，只输出候选词，用中文顿号、分隔，不要任何解释和编号"
    AIService.shared.chat(messages: [AIMessage(role: "user", content: prompt)]) { [weak self] result in
      DispatchQueue.main.async {
        guard let self = self else { return }
        switch result {
        case .success(let text):
          let suggestions = self.parseSuggestions(text)
          if suggestions.isEmpty {
            self.showMessage("未生成建议，请重试")
          } else {
            self.showSuggestions(Array(suggestions.prefix(5)))
          }
        case .failure(let error):
          self.showMessage(self.errorText(error))
        }
      }
    }
  }

  private func parseSuggestions(_ text: String) -> [String] {
    let separators = CharacterSet(charactersIn: "、，。；：
,")
    let parts = text.components(separatedBy: separators)
    return parts
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && $0.count >= 1 && $0.count <= 12 }
  }

  private func errorText(_ error: Error) -> String {
    if let aiError = error as? AIService.AIError {
      switch aiError {
      case .noAPIKey:
        return "未配置AI 信息，请在咕噜App的AI设置中填写"
      default:
        break
      }
    }
    return "AI 请求失败，请稍后重试"
  }


  /// 面板期望高度（最多 5 条建议）
  static var preferredHeight: CGFloat {
    8 + 20 + 8 + 5 * 34 + 4 * 6 + 10
  }
}
