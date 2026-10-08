import SwiftUI
import UIKit

enum ClawComposerMode: Equatable {
  case text, voice, emoji, more
}

enum ClawComposerAction {
  case photo, file, clipboard, call, language
}

#if DEBUG
enum ClawComposerScreenshotFixture {
  static var state: String? {
    let args = ProcessInfo.processInfo.arguments
    guard let index = args.firstIndex(of: "-clawComposerScreenshot"), index + 1 < args.count else { return nil }
    let state = args[index + 1]
    return ["empty", "text", "multiline", "voice", "emoji", "more", "dark"].contains(state) ? state : nil
  }

  static var mode: ClawComposerMode {
    switch state {
    case "voice": return .voice
    case "emoji": return .emoji
    case "more": return .more
    default: return .text
    }
  }
}
#endif

/// UIKit owns inputView and markedText, SwiftUI owns the conversation draft.
struct ClawChatComposer: UIViewRepresentable {
  @Binding var text: String
  let isSending: Bool
  let voiceActive: Bool
  let voiceWillCancel: Bool
  let onSend: (String) -> Void
  let onAction: (ClawComposerAction) -> Void
  let onVoiceBegin: () -> Void
  let onVoiceMove: (CGFloat) -> Void
  let onVoiceEnd: (Bool) -> Void
  let onHeightChange: (CGFloat) -> Void
#if DEBUG
  var screenshotMode: ClawComposerMode? = nil
#endif

  func makeUIView(context: Context) -> ClawChatComposerBar {
    ClawChatComposerBar()
  }

  func updateUIView(_ bar: ClawChatComposerBar, context: Context) {
    bar.onTextChange = { value in
      if text != value { text = value }
    }
    bar.onSend = onSend
    bar.onAction = onAction
    bar.onVoiceBegin = onVoiceBegin
    bar.onVoiceMove = onVoiceMove
    bar.onVoiceEnd = onVoiceEnd
    bar.onHeightChange = { height in
      DispatchQueue.main.async { onHeightChange(height) }
    }
    bar.configure(text: text, isSending: isSending, voiceActive: voiceActive, voiceWillCancel: voiceWillCancel)
#if DEBUG
    if screenshotMode != nil || ClawComposerScreenshotFixture.state != nil {
      let requestedMode = screenshotMode ?? ClawComposerScreenshotFixture.mode
      if bar.mode != requestedMode { bar.setMode(requestedMode) }
    }
#endif
  }
}

final class ClawChatComposerBar: UIView, UITextViewDelegate {
  static let maximumHeight: CGFloat = 132

  private(set) var mode: ClawComposerMode = .text
  private(set) var preferredHeight: CGFloat = 56
  var isSendVisible: Bool { mode != .voice && !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  var onTextChange: ((String) -> Void)?
  var onSend: ((String) -> Void)?
  var onAction: ((ClawComposerAction) -> Void)?
  var onVoiceBegin: (() -> Void)?
  var onVoiceMove: ((CGFloat) -> Void)?
  var onVoiceEnd: ((Bool) -> Void)?
  var onHeightChange: ((CGFloat) -> Void)?

  let textView = UITextView()
  private let inputShell = UIView()
  private let holdButton = UIButton(type: .custom)
  private let voiceButton = UIButton(type: .system)
  private let emojiButton = UIButton(type: .system)
  private let trailingButton = UIButton(type: .system)
  private let stack = UIStackView()
  private var inputHeightConstraint: NSLayoutConstraint!
  private var trailingWidthConstraint: NSLayoutConstraint!
  private var isSending = false
  private var voiceActive = false
  private var voiceWillCancel = false
  private var updatingText = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    buildUI()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    buildUI()
  }

  override var intrinsicContentSize: CGSize {
    CGSize(width: UIView.noIntrinsicMetric, height: preferredHeight)
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil && (mode == .emoji || mode == .more) {
      DispatchQueue.main.async { [weak self] in
        guard let self, self.window != nil else { return }
        self.textView.becomeFirstResponder()
      }
    }
  }

  private func buildUI() {
    backgroundColor = UIColor { traits in
      traits.userInterfaceStyle == .dark ? UIColor(white: 0.14, alpha: 1) : UIColor(red: 247/255, green: 247/255, blue: 247/255, alpha: 1)
    }
    preservesSuperviewLayoutMargins = false

    stack.axis = .horizontal
    stack.alignment = .bottom
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
    ])

    for button in [voiceButton, emojiButton, trailingButton] {
      button.tintColor = .label
      button.translatesAutoresizingMaskIntoConstraints = false
      button.heightAnchor.constraint(equalToConstant: 40).isActive = true
    }
    voiceButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
    emojiButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
    trailingWidthConstraint = trailingButton.widthAnchor.constraint(equalToConstant: 34)
    trailingWidthConstraint.isActive = true

    voiceButton.setImage(Self.icon(.voice), for: .normal)
    emojiButton.setImage(Self.icon(.emoji), for: .normal)
    trailingButton.setImage(Self.icon(.more), for: .normal)
    voiceButton.accessibilityIdentifier = "claw.composer.voice"
    emojiButton.accessibilityIdentifier = "claw.composer.emoji"
    trailingButton.accessibilityIdentifier = "claw.composer.more"
    voiceButton.addTarget(self, action: #selector(toggleVoice), for: .touchUpInside)
    emojiButton.addTarget(self, action: #selector(toggleEmoji), for: .touchUpInside)
    trailingButton.addTarget(self, action: #selector(tapTrailing), for: .touchUpInside)

    inputShell.backgroundColor = .secondarySystemGroupedBackground
    inputShell.layer.cornerRadius = 5
    inputShell.layer.borderWidth = 0.5
    inputShell.layer.borderColor = UIColor.separator.cgColor
    inputShell.translatesAutoresizingMaskIntoConstraints = false
    inputHeightConstraint = inputShell.heightAnchor.constraint(equalToConstant: 40)
    inputHeightConstraint.isActive = true
    inputShell.setContentHuggingPriority(.defaultLow, for: .horizontal)

    textView.font = .systemFont(ofSize: 16)
    textView.backgroundColor = .clear
    textView.textColor = .label
    textView.tintColor = .label
    textView.returnKeyType = .send
    textView.textContainerInset = UIEdgeInsets(top: 8, left: 2, bottom: 8, right: 2)
    textView.textContainer.lineFragmentPadding = 2
    textView.isScrollEnabled = false
    textView.delegate = self
    textView.accessibilityIdentifier = "claw.composer.text"
    textView.translatesAutoresizingMaskIntoConstraints = false
    let returnToKeyboard = UITapGestureRecognizer(target: self, action: #selector(tappedTextField))
    returnToKeyboard.cancelsTouchesInView = false
    textView.addGestureRecognizer(returnToKeyboard)
    inputShell.addSubview(textView)

    holdButton.backgroundColor = .clear
    holdButton.setTitle("按住 说话", for: .normal)
    holdButton.setTitleColor(.label, for: .normal)
    holdButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
    holdButton.accessibilityIdentifier = "claw.composer.hold"
    holdButton.isHidden = true
    holdButton.translatesAutoresizingMaskIntoConstraints = false
    inputShell.addSubview(holdButton)
    NSLayoutConstraint.activate([
      textView.leadingAnchor.constraint(equalTo: inputShell.leadingAnchor),
      textView.trailingAnchor.constraint(equalTo: inputShell.trailingAnchor),
      textView.topAnchor.constraint(equalTo: inputShell.topAnchor),
      textView.bottomAnchor.constraint(equalTo: inputShell.bottomAnchor),
      holdButton.leadingAnchor.constraint(equalTo: inputShell.leadingAnchor),
      holdButton.trailingAnchor.constraint(equalTo: inputShell.trailingAnchor),
      holdButton.topAnchor.constraint(equalTo: inputShell.topAnchor),
      holdButton.bottomAnchor.constraint(equalTo: inputShell.bottomAnchor)
    ])
    let gesture = UILongPressGestureRecognizer(target: self, action: #selector(holdGesture(_:)))
    gesture.minimumPressDuration = 0
    gesture.allowableMovement = CGFloat.greatestFiniteMagnitude
    holdButton.addGestureRecognizer(gesture)

    for v in [voiceButton, inputShell, emojiButton, trailingButton] { stack.addArrangedSubview(v) }
    updateControls()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    updateHeight()
  }

  func configure(text: String, isSending: Bool, voiceActive: Bool, voiceWillCancel: Bool) {
    self.isSending = isSending
    self.voiceActive = voiceActive
    self.voiceWillCancel = voiceWillCancel
    // Never clobber an in-progress Chinese/Japanese IME composition.
    if textView.markedTextRange == nil && textView.text != text {
      updatingText = true
      let oldSelection = textView.selectedRange
      textView.text = text
      textView.selectedRange = NSRange(location: min(oldSelection.location, (text as NSString).length), length: 0)
      updatingText = false
    }
    updateControls()
    updateHeight()
  }

  func setMode(_ newMode: ClawComposerMode) {
    mode = newMode
    if newMode == .voice { textView.resignFirstResponder() }
    textView.inputView = newMode == .emoji || newMode == .more ? makePanel(newMode) : nil
    if newMode != .voice {
      if textView.isFirstResponder { textView.reloadInputViews() }
      else if newMode != .text { textView.becomeFirstResponder() }
    }
    updateControls()
    updateHeight()
  }

  @objc private func toggleVoice() {
    setMode(mode == .voice ? .text : .voice)
    if mode == .text { textView.becomeFirstResponder() }
  }

  @objc private func tappedTextField() {
    if mode == .emoji || mode == .more { setMode(.text) }
  }

  @objc private func toggleEmoji() {
    setMode(mode == .emoji ? .text : .emoji)
    if mode == .text { textView.becomeFirstResponder() }
  }

  @objc private func tapTrailing() {
    if isSendVisible {
      guard !isSending else { return }
      onSend?(textView.text)
    } else {
      setMode(mode == .more ? .text : .more)
      if mode == .text { textView.becomeFirstResponder() }
    }
  }

  @objc private func holdGesture(_ recognizer: UILongPressGestureRecognizer) {
    let movement = recognizer.translationY(in: holdButton)
    switch recognizer.state {
    case .began: onVoiceBegin?()
    case .changed: onVoiceMove?(movement)
    case .ended: onVoiceEnd?(false)
    case .cancelled, .failed: onVoiceEnd?(true)
    default: break
    }
  }

  private func updateControls() {
    let voice = mode == .voice
    textView.isHidden = voice
    holdButton.isHidden = !voice
    holdButton.setTitle(voiceActive ? (voiceWillCancel ? "松开取消" : "松开发送 · 上滑取消") : "按住 说话", for: .normal)
    holdButton.setTitleColor(voiceWillCancel ? .systemRed : .label, for: .normal)
    voiceButton.setImage(Self.icon(voice ? .keyboard : .voice), for: .normal)
    let send = isSendVisible
    trailingWidthConstraint.constant = send ? 52 : 34
    trailingButton.setTitle(send ? "发送" : nil, for: .normal)
    trailingButton.setImage(send ? nil : Self.icon(.more), for: .normal)
    trailingButton.accessibilityIdentifier = send ? "claw.composer.send" : "claw.composer.more"
    trailingButton.backgroundColor = send ? UIColor(red: 7/255, green: 193/255, blue: 96/255, alpha: 1) : .clear
    trailingButton.layer.cornerRadius = send ? 5 : 0
    trailingButton.setTitleColor(.white, for: .normal)
    trailingButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
    trailingButton.isEnabled = !isSending
  }

  private func updateHeight() {
    let availableWidth = textView.bounds.width > 40 ? textView.bounds.width : max(120, bounds.width - 158)
    let desired: CGFloat
    if mode == .voice {
      desired = 40
    } else {
      desired = max(40, min(Self.maximumHeight - 16, ceil(textView.sizeThatFits(
        CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
      ).height)))
    }
    textView.isScrollEnabled = desired >= Self.maximumHeight - 16
    guard abs(inputHeightConstraint.constant - desired) > 0.5 || abs(preferredHeight - desired - 16) > 0.5 else { return }
    inputHeightConstraint.constant = desired
    preferredHeight = desired + 16
    invalidateIntrinsicContentSize()
    onHeightChange?(preferredHeight)
  }

  func textViewDidChange(_ textView: UITextView) {
    guard !updatingText else { return }
    onTextChange?(textView.text)
    updateControls()
    updateHeight()
  }

  func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
    guard text == "\n", textView.markedTextRange == nil else { return true }
    if mode != .voice && !isSending {
      let content = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !content.isEmpty { onSend?(textView.text) }
    }
    return false
  }

  private func makePanel(_ panelMode: ClawComposerMode) -> UIView {
    let panel = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 236))
    panel.backgroundColor = backgroundColor
    let layout = UIStackView()
    layout.axis = .vertical
    layout.spacing = 15
    layout.distribution = .fillEqually
    layout.translatesAutoresizingMaskIntoConstraints = false
    panel.addSubview(layout)
    NSLayoutConstraint.activate([
      layout.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
      layout.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
      layout.topAnchor.constraint(equalTo: panel.topAnchor, constant: 18),
      layout.bottomAnchor.constraint(lessThanOrEqualTo: panel.bottomAnchor, constant: -16)
    ])
    if panelMode == .emoji {
      let symbols = ["😀", "😂", "🥰", "😍", "🤔", "😭", "😡", "👍", "👏", "🙏", "🎉", "❤️", "🔥", "✨", "😅", "😴", "🤝", "👌", "💪", "🙌", "🌹"]
      for start in stride(from: 0, to: symbols.count, by: 7) {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        for symbol in symbols[start..<min(start + 7, symbols.count)] {
          let button = UIButton(type: .system)
          button.setTitle(symbol, for: .normal)
          button.titleLabel?.font = .systemFont(ofSize: 27)
          button.addAction(UIAction { [weak self] _ in
            guard let self, let range = self.textView.selectedTextRange else { return }
            self.textView.replace(range, withText: symbol)
            self.textViewDidChange(self.textView)
          }, for: .touchUpInside)
          row.addArrangedSubview(button)
        }
        // Keep the last row aligned with the rows above.
        while row.arrangedSubviews.count < 7 { row.addArrangedSubview(UIView()) }
        layout.addArrangedSubview(row)
      }
    } else {
      let actions: [(String, String, ClawComposerAction)] = [
        ("照片", "photo", .photo), ("文件", "folder", .file),
        ("剪贴板", "doc.on.clipboard", .clipboard), ("语音通话", "phone", .call),
        ("语音语言", "globe", .language)
      ]
      for start in stride(from: 0, to: actions.count, by: 4) {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        for (title, glyph, action) in actions[start..<min(start + 4, actions.count)] {
          let button = UIButton(type: .system)
          var config = UIButton.Configuration.plain()
          config.image = UIImage(systemName: glyph)
          config.title = title
          config.imagePlacement = .top
          config.imagePadding = 10
          config.baseForegroundColor = .label
          button.configuration = config
          button.addAction(UIAction { [weak self] _ in self?.onAction?(action) }, for: .touchUpInside)
          row.addArrangedSubview(button)
        }
        while row.arrangedSubviews.count < 4 { row.addArrangedSubview(UIView()) }
        layout.addArrangedSubview(row)
      }
    }
    return panel
  }

  private enum Glyph { case voice, keyboard, emoji, more }

  /// Original stroked vector shapes, independent of SF Symbols changes.
  private static func icon(_ glyph: Glyph) -> UIImage {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 30)).image { _ in
      UIColor.black.setStroke()
      let p = UIBezierPath()
      p.lineWidth = 1.8
      p.lineCapStyle = .round
      p.lineJoinStyle = .round
      switch glyph {
      case .voice:
        p.addArc(withCenter: CGPoint(x: 15, y: 15), radius: 12.3, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        p.move(to: CGPoint(x: 10, y: 11)); p.addLine(to: CGPoint(x: 10, y: 19))
        p.move(to: CGPoint(x: 15, y: 9)); p.addLine(to: CGPoint(x: 15, y: 21))
        p.move(to: CGPoint(x: 20, y: 12)); p.addLine(to: CGPoint(x: 20, y: 18))
      case .keyboard:
        p.append(UIBezierPath(roundedRect: CGRect(x: 3, y: 6, width: 24, height: 18), cornerRadius: 3))
        for y in [CGFloat(12), CGFloat(17)] {
          for x in [CGFloat(9), CGFloat(15), CGFloat(21)] {
            p.move(to: CGPoint(x: x - 1.2, y: y)); p.addLine(to: CGPoint(x: x + 1.2, y: y))
          }
        }
        p.move(to: CGPoint(x: 10, y: 21)); p.addLine(to: CGPoint(x: 20, y: 21))
      case .emoji:
        p.addArc(withCenter: CGPoint(x: 15, y: 15), radius: 12.3, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        p.move(to: CGPoint(x: 10.5, y: 12)); p.addLine(to: CGPoint(x: 10.5, y: 13))
        p.move(to: CGPoint(x: 19.5, y: 12)); p.addLine(to: CGPoint(x: 19.5, y: 13))
        p.move(to: CGPoint(x: 9.5, y: 18))
        p.addQuadCurve(to: CGPoint(x: 20.5, y: 18), control: CGPoint(x: 15, y: 25))
      case .more:
        p.addArc(withCenter: CGPoint(x: 15, y: 15), radius: 12.3, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        p.move(to: CGPoint(x: 15, y: 8)); p.addLine(to: CGPoint(x: 15, y: 22))
        p.move(to: CGPoint(x: 8, y: 15)); p.addLine(to: CGPoint(x: 22, y: 15))
      }
      p.stroke()
    }
    return image.withRenderingMode(.alwaysTemplate)
  }
}

private extension UILongPressGestureRecognizer {
  func translationY(in view: UIView) -> CGFloat {
    let point = location(in: view)
    return point.y - view.bounds.midY
  }
}
