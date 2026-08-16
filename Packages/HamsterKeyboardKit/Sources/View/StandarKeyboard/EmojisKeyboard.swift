//
//  EmojisKeyboard.swift
//
//
//  Created by morse on 2023/9/5.
//

import HamsterUIKit
import UIKit

/// Emojis 表情键盘（官方化）：顶部搜索栏 + 4 行表情网格 + 底部 tab 栏 + 返回/删除胶囊键
/// - 搜索栏实时过滤网格内容；分类 tab 圆形底座，手指点到哪个分类选中态跟到哪；
/// - 返回键胶囊动态文字：英文26键（含 123/#+=）进入显示 "ABC"，中文面板进入显示 "拼音"；
/// - 长按可换肤色的 emoji 弹出 5 肤色变体菜单，选后输入并记住肤色偏好（UserDefaults）。
class EmojisKeyboard: NibLessView {
  private let keyboardContext: KeyboardContext
  private let actionHandler: KeyboardActionHandler
  private let appearance: KeyboardAppearance

  /// 当前选中的分类
  private var selectedCategory: EmojiCategory = .frequent {
    didSet { reloadEmojis() }
  }

  /// 当前显示的 emoji 列表（已按搜索词过滤）
  private var currentEmojis: [Emoji] = []

  /// 搜索词：变化时实时过滤网格
  private var searchText = "" {
    didSet { reloadEmojis() }
  }

  /// 上次布局宽度，用于检测宽度变化时刷新 cell 尺寸
  private var lastLayoutWidth: CGFloat = 0

  // MARK: - 肤色偏好

  /// 肤色变体：默认（无修饰）+ 5 个 Fitzpatrick 肤色
  private static let skinToneModifiers = ["", "🏻", "🏼", "🏽", "🏾", "🏿"]
  private static let skinToneKey = "clawtalk.emojiSkinTone"

  /// 当前长按中的肤色基底 emoji
  private var skinToneBase: String?
  /// 肤色菜单是否激活（长按手势期间抑制普通 cell 选择）
  private var skinToneActive = false

  // MARK: - Subviews

  private lazy var searchField: UITextField = {
    let tf = UITextField()
    tf.placeholder = "搜索"
    tf.attributedPlaceholder = NSAttributedString(
      string: "搜索",
      attributes: [.foregroundColor: UIColor.secondaryLabel]
    )
    tf.font = .systemFont(ofSize: 14)
    tf.textColor = .label
    tf.backgroundColor = .systemBackground
    tf.layer.cornerRadius = 8
    tf.layer.masksToBounds = true
    tf.clearButtonMode = .whileEditing
    tf.autocorrectionType = .no
    tf.spellCheckingType = .no
    tf.autocapitalizationType = .none
    // 面板内输入框惯例：inputView 置空禁系统键盘（保留长按粘贴菜单）
    tf.inputView = UIView()
    let spacer = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
    tf.leftView = spacer
    tf.leftViewMode = .always
    tf.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
    tf.translatesAutoresizingMaskIntoConstraints = false
    return tf
  }()

  private lazy var flowLayout: UICollectionViewFlowLayout = {
    let layout = UICollectionViewFlowLayout()
    layout.minimumInteritemSpacing = 4
    layout.minimumLineSpacing = 4
    layout.sectionInset = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
    return layout
  }()

  private lazy var collectionView: UICollectionView = {
    let cv = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
    cv.translatesAutoresizingMaskIntoConstraints = false
    cv.backgroundColor = .clear
    cv.dataSource = self
    cv.delegate = self
    cv.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.id)
    cv.showsVerticalScrollIndicator = false
    cv.addGestureRecognizer(skinLongPress)
    return cv
  }()

  private lazy var categoryScrollView: UIScrollView = {
    let sv = UIScrollView()
    sv.translatesAutoresizingMaskIntoConstraints = false
    sv.showsHorizontalScrollIndicator = false
    sv.showsVerticalScrollIndicator = false
    sv.alwaysBounceHorizontal = true
    sv.delegate = self
    return sv
  }()

  private lazy var categoryBar: UIStackView = {
    let sv = UIStackView()
    sv.axis = .horizontal
    sv.distribution = .fill
    sv.alignment = .center
    sv.spacing = 4
    sv.translatesAutoresizingMaskIntoConstraints = false
    return sv
  }()

  private lazy var bottomBar: UIView = {
    let v = UIView()
    v.translatesAutoresizingMaskIntoConstraints = false
    return v
  }()

  /// 返回键：胶囊样式，动态文字（ABC / 拼音），返回上一个面板
  private lazy var backButton: UIButton = {
    let btn = UIButton(type: .system)
    btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
    btn.translatesAutoresizingMaskIntoConstraints = false
    btn.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
    return btn
  }()

  private lazy var deleteButton: UIButton = {
    let btn = UIButton(type: .system)
    btn.setImage(UIImage(systemName: "delete.left"), for: .normal)
    btn.translatesAutoresizingMaskIntoConstraints = false
    btn.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
    return btn
  }()

  private lazy var skinLongPress: UILongPressGestureRecognizer = {
    let g = UILongPressGestureRecognizer(target: self, action: #selector(skinLongPressed(_:)))
    g.minimumPressDuration = 0.45
    return g
  }()

  /// 肤色变体菜单：默认 + 5 肤色横排气泡
  private lazy var skinTonePopup: UIView = {
    let v = UIView()
    v.backgroundColor = .secondarySystemBackground
    v.layer.cornerRadius = 18
    v.layer.shadowColor = UIColor.black.cgColor
    v.layer.shadowOpacity = 0.25
    v.layer.shadowRadius = 8
    v.layer.shadowOffset = CGSize(width: 0, height: 4)
    v.isHidden = true
    v.isUserInteractionEnabled = false
    return v
  }()

  private var skinToneLabels: [UILabel] = []

  // MARK: - Init

  init(keyboardContext: KeyboardContext, actionHandler: KeyboardActionHandler, appearance: KeyboardAppearance) {
    self.keyboardContext = keyboardContext
    self.actionHandler = actionHandler
    self.appearance = appearance
    super.init(frame: .zero)
    setupView()
    reloadEmojis()
  }

  // MARK: - Setup

  private func setupView() {
    backgroundColor = appearance.backgroundStyle.backgroundColor

    addSubview(searchField)
    addSubview(collectionView)
    addSubview(bottomBar)
    bottomBar.addSubview(backButton)
    bottomBar.addSubview(deleteButton)
    bottomBar.addSubview(categoryScrollView)
    categoryScrollView.addSubview(categoryBar)

    // 分类 tab：圆形底座
    var tabConstraints: [NSLayoutConstraint] = []
    for (index, category) in EmojiCategory.allCases.enumerated() {
      let btn = UIButton(type: .system)
      btn.setTitle(category.fallbackDisplayEmoji.char, for: .normal)
      btn.titleLabel?.font = .systemFont(ofSize: 19)
      btn.tag = index
      btn.layer.cornerRadius = 17
      btn.clipsToBounds = true
      btn.addTarget(self, action: #selector(categoryTapped(_:)), for: .touchUpInside)
      tabConstraints.append(btn.widthAnchor.constraint(equalToConstant: 34))
      tabConstraints.append(btn.heightAnchor.constraint(equalToConstant: 34))
      categoryBar.addArrangedSubview(btn)
    }
    NSLayoutConstraint.activate(tabConstraints)
    updateCategoryHighlight()

    // 手指跟手：在分类栏上滑动时，高亮跟随手指位置实时切换分类
    let categoryPan = UIPanGestureRecognizer(target: self, action: #selector(categoryPan(_:)))
    categoryPan.cancelsTouchesInView = false
    categoryPan.delegate = self
    categoryScrollView.addGestureRecognizer(categoryPan)

    // 肤色菜单标签
    let popupW = Self.skinTonePopupWidth
    let popupH = Self.skinTonePopupHeight
    for index in 0..<Self.skinToneModifiers.count {
      let label = UILabel(frame: CGRect(
        x: 6 + CGFloat(index) * 32,
        y: (popupH - 32) / 2,
        width: 32,
        height: 32
      ))
      label.textAlignment = .center
      label.font = .systemFont(ofSize: 24)
      label.layer.cornerRadius = 16
      label.layer.masksToBounds = true
      skinTonePopup.addSubview(label)
      skinToneLabels.append(label)
    }
    skinTonePopup.frame = CGRect(x: 0, y: 0, width: popupW, height: popupH)
    addSubview(skinTonePopup)

    let style = appearance.candidateBarStyle
    deleteButton.tintColor = style.toolbarButtonFrontColor
    styleCapsule(deleteButton)
    styleCapsule(backButton)
    backButton.setTitleColor(style.toolbarButtonFrontColor, for: .normal)

    NSLayoutConstraint.activate([
      searchField.topAnchor.constraint(equalTo: topAnchor, constant: 6),
      searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      searchField.heightAnchor.constraint(equalToConstant: 32),

      collectionView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 4),
      collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
      collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
      collectionView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

      bottomBar.leadingAnchor.constraint(equalTo: leadingAnchor),
      bottomBar.trailingAnchor.constraint(equalTo: trailingAnchor),
      bottomBar.bottomAnchor.constraint(equalTo: bottomAnchor),
      bottomBar.heightAnchor.constraint(equalToConstant: 40),

      backButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 6),
      backButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
      backButton.widthAnchor.constraint(equalToConstant: 58),
      backButton.heightAnchor.constraint(equalToConstant: 34),

      deleteButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -6),
      deleteButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
      deleteButton.widthAnchor.constraint(equalToConstant: 46),
      deleteButton.heightAnchor.constraint(equalToConstant: 34),

      categoryScrollView.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4),
      categoryScrollView.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -4),
      categoryScrollView.topAnchor.constraint(equalTo: bottomBar.topAnchor),
      categoryScrollView.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor),

      categoryBar.topAnchor.constraint(equalTo: categoryScrollView.topAnchor),
      categoryBar.bottomAnchor.constraint(equalTo: categoryScrollView.bottomAnchor),
      categoryBar.leadingAnchor.constraint(equalTo: categoryScrollView.leadingAnchor),
      categoryBar.widthAnchor.constraint(equalToConstant: 38 * CGFloat(EmojiCategory.allCases.count) - 4),
    ])
  }

  private static var skinTonePopupWidth: CGFloat {
    6 * 2 + 32 * CGFloat(skinToneModifiers.count)
  }

  private static var skinTonePopupHeight: CGFloat {
    40
  }

  /// 胶囊底样式（圆角全高）
  private func styleCapsule(_ button: UIButton) {
    button.backgroundColor = .secondarySystemFill
    button.layer.cornerRadius = 17
    button.layer.masksToBounds = true
  }

  // MARK: - Layout

  override var intrinsicContentSize: CGSize {
    // 搜索栏 + 4 行表情网格 + 底部 tab 栏 ≈ 5 行按键高度
    let config = KeyboardLayoutConfiguration.standard(for: keyboardContext)
    let rowHeight = config.rowHeight
    return CGSize(width: UIView.noIntrinsicMetric, height: rowHeight * 5)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if bounds.width != lastLayoutWidth && bounds.width > 0 {
      lastLayoutWidth = bounds.width
      flowLayout.invalidateLayout()
    }
  }

  // MARK: - Data

  /// 搜索词匹配：表情字符子串 + 常见 emoji 英文/中文关键词
  private func emojiMatches(_ char: String, query: String) -> Bool {
    if char.contains(query) { return true }
    guard let keywords = Self.emojiKeywords[char] else { return false }
    return keywords.contains { $0.contains(query) }
  }

  private var filteredEmojis: [Emoji] {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return selectedCategory.emojis }
    return EmojiCategory.allCases
      .flatMap { $0.emojis }
      .filter { emojiMatches($0.char, query: trimmed) }
  }

  private func reloadEmojis() {
    currentEmojis = filteredEmojis
    collectionView.reloadData()
    if !currentEmojis.isEmpty {
      collectionView.scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: false)
    }
    updateCategoryHighlight()
  }

  private func updateCategoryHighlight() {
    let selectedIndex = EmojiCategory.allCases.firstIndex(of: selectedCategory) ?? 0
    for (i, view) in categoryBar.arrangedSubviews.enumerated() {
      let selected = i == selectedIndex
      view.backgroundColor = selected ? UIColor.systemGray4 : .clear
      view.alpha = selected ? 1.0 : 0.45
    }
  }

  // MARK: - Actions

  @objc private func searchChanged() {
    searchText = searchField.text ?? ""
  }

  @objc private func categoryTapped(_ sender: UIButton) {
    dismissSkinTonePopup()
    let index = sender.tag
    guard index < EmojiCategory.allCases.count else { return }
    selectedCategory = EmojiCategory.allCases[index]
    let offsetX = CGFloat(index) * 38 - (categoryScrollView.bounds.width - 38) / 2
    let clamped = min(max(offsetX, 0), categoryScrollView.contentSize.width - categoryScrollView.bounds.width)
    categoryScrollView.setContentOffset(CGPoint(x: max(clamped, 0), y: 0), animated: true)
  }

  @objc private func categoryPan(_ pan: UIPanGestureRecognizer) {
    let itemWidth: CGFloat = 38
    let loc = pan.location(in: categoryScrollView)
    let contentX = loc.x + categoryScrollView.contentOffset.x
    let idx = min(max(Int(contentX / itemWidth), 0), EmojiCategory.allCases.count - 1)
    let target = EmojiCategory.allCases[idx]
    if target != selectedCategory {
      selectedCategory = target
    }
    if pan.state == .ended || pan.state == .cancelled || pan.state == .failed {
      let offsetX = CGFloat(idx) * itemWidth - (categoryScrollView.bounds.width - itemWidth) / 2
      let maxOffset = max(0, categoryScrollView.contentSize.width - categoryScrollView.bounds.width)
      categoryScrollView.setContentOffset(CGPoint(x: min(max(offsetX, 0), maxOffset), y: 0), animated: true)
    }
  }

  /// 返回上一个面板（.returnLastKeyboard 走主键盘类型栈）
  @objc private func backTapped() {
    dismissSkinTonePopup()
    actionHandler.handle(.release, on: .returnLastKeyboard)
  }

  @objc private func deleteTapped() {
    dismissSkinTonePopup()
    // 搜索框聚焦或有搜索词时退格删搜索内容（避免误删正文文档）
    if searchField.isFirstResponder || !searchText.isEmpty {
      searchField.deleteBackward()
      return
    }
    keyboardContext.textDocumentProxy.deleteBackward()
  }

  /// 返回键文字：英文族面板（英文26键及 123/#+=）="ABC"，中文面板="拼音"
  private var backLabel: String {
    if keyboardContext.useIOSNativeLayout {
      return IOSNativeEmojiReturnState.lastPanelWasEnglish ? "ABC" : "拼音"
    }
    // 标准布局兜底：主键盘为中文族显示拼音
    switch keyboardContext.selectKeyboard {
    case .alphabetic, .numeric, .symbolic:
      return "ABC"
    default:
      return "拼音"
    }
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      backButton.setTitle(backLabel, for: .normal)
    }
  }

  // MARK: - 肤色变体

  /// 是否可换肤色：常见手/人 emoji（单码位，可去掉尾部 VS16）
  private static let skinToneCapableBases: Set<String> = [
    // 手
    "👋", "🤚", "🖐", "✋", "🖖", "👌", "🤌", "🤏", "✌", "🤞", "🤟", "🤘", "🤙",
    "👈", "👉", "👆", "👇", "☝", "✊", "👊", "🤛", "🤜", "👏", "🙌", "👐", "🤲",
    "🤝", "🙏", "💪", "🦾", "🦵", "🦶", "💅", "🤳", "🫰", "🫱", "🫲", "🫳", "🫴", "🫶",
    // 人
    "👶", "🧒", "👦", "👧", "🧑", "👨", "👩", "🧔", "👵", "🧓", "👴", "👲", "👳",
    "🧕", "👮", "👷", "💂", "🕵", "🧙", "🧚", "🧛", "🧜", "🧝", "🧞", "🧟", "🦸",
    "🦹", "🙋", "🙇", "🤦", "🤷", "💁", "🙅", "🙆", "🙎", "🙍", "💇", "💆", "🧖",
    "🧘", "🧗", "🧎", "🏃", "🚶", "💃", "🕺", "🏋", "🤸", "🤺", "🤾", "🏇", "🤼",
    "🚣", "🏊", "🏄", "🏌", "🤹", "🧍", "👰", "🤵", "👸", "🤴", "🥷", "🕴", "🦻",
  ]

  private func skinToneBase(of char: String) -> String? {
    var scalars = Array(char.unicodeScalars)
    if scalars.count == 2, scalars.last == "\u{FE0F}" {
      scalars.removeLast()
    }
    guard scalars.count == 1 else { return nil }
    let base = String(scalars[0])
    return Self.skinToneCapableBases.contains(base) ? base : nil
  }

  @objc private func skinLongPressed(_ gesture: UILongPressGestureRecognizer) {
    switch gesture.state {
    case .began:
      let point = gesture.location(in: collectionView)
      guard let indexPath = collectionView.indexPathForItem(at: point) else { return }
      let emoji = currentEmojis[indexPath.item]
      guard let base = skinToneBase(of: emoji.char) else { return }
      skinToneActive = true
      showSkinTonePopup(for: indexPath, base: base)
    case .changed:
      guard skinToneActive else { return }
      let p = gesture.location(in: skinTonePopup)
      updateSkinToneHighlight(index: skinToneIndex(at: p))
    case .ended:
      guard skinToneActive else { return }
      let p = gesture.location(in: skinTonePopup)
      if let idx = skinToneIndex(at: p) {
        insertSkinToneVariant(idx)
      }
      dismissSkinTonePopup()
    case .cancelled, .failed:
      dismissSkinTonePopup()
    default:
      break
    }
  }

  private func showSkinTonePopup(for indexPath: IndexPath, base: String) {
    guard let cell = collectionView.cellForItem(at: indexPath) else { return }
    skinToneBase = base
    for (i, modifier) in Self.skinToneModifiers.enumerated() {
      skinToneLabels[i].text = base + modifier
    }
    let stored = UserDefaults.standard.string(forKey: Self.skinToneKey) ?? ""
    updateSkinToneHighlight(index: Self.skinToneModifiers.firstIndex(of: stored) ?? 0)

    let cellFrame = cell.frame
    let popupSize = skinTonePopup.bounds.size
    var x = cellFrame.midX - popupSize.width / 2
    x = min(max(x, 4), max(4, bounds.width - popupSize.width - 4))
    let cvTop = collectionView.frame.minY
    let aboveY = cellFrame.minY + cvTop - popupSize.height - 8
    let y = aboveY >= cvTop + 4 ? aboveY : (cellFrame.maxY + cvTop + 8)
    skinTonePopup.frame = CGRect(x: x, y: y, width: popupSize.width, height: popupSize.height)
    skinTonePopup.isHidden = false
    bringSubviewToFront(skinTonePopup)
  }

  private func skinToneIndex(at point: CGPoint) -> Int? {
    guard skinTonePopup.bounds.insetBy(dx: -8, dy: -8).contains(point) else { return nil }
    let idx = Int((point.x - 6) / 32)
    return min(max(idx, 0), Self.skinToneModifiers.count - 1)
  }

  private func updateSkinToneHighlight(index: Int?) {
    for (i, label) in skinToneLabels.enumerated() {
      let selected = i == index
      label.backgroundColor = selected ? UIColor.systemBlue : .clear
      label.layer.cornerRadius = selected ? 16 : 0
    }
  }

  private func insertSkinToneVariant(_ index: Int) {
    guard let base = skinToneBase else { return }
    let modifier = Self.skinToneModifiers[index]
    let char = base + modifier
    UserDefaults.standard.set(modifier, forKey: Self.skinToneKey)
    keyboardContext.textDocumentProxy.insertText(char)
    EmojiCategory.frequentEmojiProvider.registerEmoji(Emoji(char))
  }

  private func dismissSkinTonePopup() {
    skinTonePopup.isHidden = true
    skinToneBase = nil
    skinToneActive = false
  }

  /// 输入 emoji：可换肤色的应用记住的肤色偏好（官方行为）
  private func insertEmoji(_ emoji: Emoji) {
    if let base = skinToneBase(of: emoji.char) {
      let modifier = UserDefaults.standard.string(forKey: Self.skinToneKey) ?? ""
      let char = base + modifier
      keyboardContext.textDocumentProxy.insertText(char)
      EmojiCategory.frequentEmojiProvider.registerEmoji(Emoji(char))
      return
    }
    keyboardContext.textDocumentProxy.insertText(emoji.char)
    EmojiCategory.frequentEmojiProvider.registerEmoji(emoji)
  }

  // MARK: - 常见 emoji 搜索关键词（英文/中文）

  private static let emojiKeywords: [String: [String]] = [
    "😀": ["smile", "happy", "笑"],
    "😂": ["laugh", "joy", "哭笑"],
    "😅": ["sweat", "汗"],
    "😊": ["blush", "smile", "害羞"],
    "😍": ["love", "heart eyes", "爱"],
    "😘": ["kiss", "亲"],
    "😭": ["cry", "哭"],
    "😡": ["angry", "生气"],
    "😱": ["scream", "惊"],
    "👍": ["thumbs", "ok", "赞"],
    "👎": ["thumbs down", "差"],
    "👏": ["clap", "鼓掌"],
    "🙏": ["pray", "拜托"],
    "👋": ["wave", "hi", "挥手"],
    "❤️": ["heart", "心"],
    "💔": ["broken heart", "心碎"],
    "💯": ["100", "满分"],
    "✨": ["sparkle", "闪"],
    "🎉": ["party", "庆祝"],
    "🎂": ["birthday", "蛋糕"],
    "🌸": ["flower", "花"],
    "🌹": ["rose", "玫瑰"],
    "☀️": ["sun", "太阳"],
    "🌙": ["moon", "月亮"],
    "⭐": ["star", "星"],
    "🍎": ["apple", "苹果"],
    "🍔": ["burger", "汉堡"],
    "🍕": ["pizza", "披萨"],
    "☕": ["coffee", "咖啡"],
    "🍺": ["beer", "啤酒"],
    "🚗": ["car", "车"],
    "✈️": ["plane", "飞机"],
    "🚀": ["rocket", "火箭"],
    "⏰": ["clock", "闹钟"],
    "💡": ["bulb", "灯", "idea"],
    "📱": ["phone", "手机"],
    "💻": ["computer", "电脑"],
    "🎵": ["music", "音乐"],
    "⚽": ["football", "soccer", "球"],
    "🏀": ["basketball", "篮球"],
    "🐶": ["dog", "狗"],
    "🐱": ["cat", "猫"],
    "🐼": ["panda", "熊猫"],
    "🦊": ["fox", "狐狸"],
    "🐰": ["rabbit", "兔"],
    "🎁": ["gift", "礼物"],
  ]
}

// MARK: - UIGestureRecognizerDelegate

extension EmojisKeyboard: UIGestureRecognizerDelegate {
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
    // 允许分类栏的滚动与手指跟手同时生效
    true
  }
}

// MARK: - UICollectionViewDataSource

extension EmojisKeyboard: UICollectionViewDataSource {
  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    currentEmojis.count
  }

  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCell.id, for: indexPath) as! EmojiCell
    cell.configure(with: currentEmojis[indexPath.item])
    return cell
  }
}

// MARK: - UICollectionViewDelegate

extension EmojisKeyboard: UICollectionViewDelegate {
  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    collectionView.deselectItem(at: indexPath, animated: true)
    // 长按肤色菜单手势期间不触发普通选择
    guard !skinToneActive else { return }
    insertEmoji(currentEmojis[indexPath.item])
  }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension EmojisKeyboard: UICollectionViewDelegateFlowLayout {
  func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
    // 4 行网格，一行约 8 个，gap 4
    let columns: CGFloat = 8
    let spacing: CGFloat = 4
    let hInset: CGFloat = 8
    let availableWidth = collectionView.bounds.width - hInset * 2 - spacing * (columns - 1)
    guard availableWidth > 0 else { return CGSize(width: 36, height: 36) }
    let width = floor(availableWidth / columns)
    let height = floor((collectionView.bounds.height - spacing * 3) / 4)
    return CGSize(width: width, height: max(height, 30))
  }
}

// MARK: - Emoji Cell

private class EmojiCell: UICollectionViewCell {
  static let id = "EmojiCell"

  private let label: UILabel = {
    let l = UILabel()
    l.font = .systemFont(ofSize: 24)
    l.textAlignment = .center
    l.translatesAutoresizingMaskIntoConstraints = false
    return l
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) { fatalError() }

  func configure(with emoji: Emoji) {
    label.text = emoji.char
  }

  override var isHighlighted: Bool {
    didSet {
      contentView.backgroundColor = isHighlighted ? UIColor.systemGray4 : .clear
      contentView.layer.cornerRadius = 8
    }
  }
}

// MARK: - UIScrollViewDelegate

extension EmojisKeyboard: UIScrollViewDelegate {
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    // 网格滚动时收起肤色菜单
    if skinToneActive {
      dismissSkinTonePopup()
    }
    guard scrollView == categoryScrollView,
          categoryScrollView.isDragging || categoryScrollView.isDecelerating
    else { return }
    let itemWidth: CGFloat = 38
    let idx = Int(round(scrollView.contentOffset.x / itemWidth))
    let clamped = min(max(idx, 0), EmojiCategory.allCases.count - 1)
    let target = EmojiCategory.allCases[clamped]
    if target != selectedCategory {
      selectedCategory = target
    }
  }
}
