//
//  IOST9CalloutProvider.swift
//
//  ClawTalk「IOS 原生布局」9 键长按选字母气泡
//
//  长按中文 9 键（pinyin9/number 面板的数字字母键）0.35s 弹出气泡，
//  手指位置决定选择：上滑=第一个字母、左滑=第二个、右滑=第三个；
//  4 字母键（PQRS/WXYZ）在上滑区域再长按 0.3s 选中第四个字母。
//  滑回键上 / 滑出菜单外 = 取消；松开时把选中字母作为输入。
//  触摸跟踪由 IOSNativeKeyboardView 完成，本文件只提供气泡视图与字母表。
//

import UIKit

// MARK: - 9 键字母表

enum IOST9LetterMap {
  /// pinyin9 面板 .chineseNineGrid 键：键面字符 -> 可选字母
  static let gridKeyLetters: [String: [String]] = [
    "ABC": ["A", "B", "C"],
    "DEF": ["D", "E", "F"],
    "GHI": ["G", "H", "I"],
    "JKL": ["J", "K", "L"],
    "MNO": ["M", "N", "O"],
    "PQRS": ["P", "Q", "R", "S"],
    "TUV": ["T", "U", "V"],
    "WXYZ": ["W", "X", "Y", "Z"],
  ]

  /// number 面板数字键：数字 -> 可选字母
  static let digitLetters: [String: [String]] = [
    "2": ["A", "B", "C"],
    "3": ["D", "E", "F"],
    "4": ["G", "H", "I"],
    "5": ["J", "K", "L"],
    "6": ["M", "N", "O"],
    "7": ["P", "Q", "R", "S"],
    "8": ["T", "U", "V"],
    "9": ["W", "X", "Y", "Z"],
  ]
}

// MARK: - 气泡视图

/// 9 键长按选字母气泡：白/深圆角底 + 底部小尾巴 + 一排字母，选中字母蓝圆高亮
final class IOST9CalloutView: UIView {
  /// 键面对应的可选字母（大写展示，输入时转小写）
  let letters: [String]
  /// 当前选中的字母下标
  private(set) var selectedIndex: Int?

  private let bgView: UIView
  private let tailView: UIView
  private let labels: [UILabel]
  private let dark: Bool

  /// 单个字母位宽
  private static let itemWidth: CGFloat = 34
  private static let paddingX: CGFloat = 9
  private static let contentHeight: CGFloat = 48
  private static let tailHeight: CGFloat = 6

  static func calloutSize(letterCount: Int) -> CGSize {
    let width = paddingX * 2 + itemWidth * CGFloat(max(letterCount, 3))
    return CGSize(width: width, height: contentHeight + tailHeight)
  }

  init(letters: [String], dark: Bool) {
    self.letters = letters
    self.dark = dark

    let size = Self.calloutSize(letterCount: letters.count)
    let bg = UIView(frame: CGRect(x: 0, y: 0, width: size.width, height: Self.contentHeight))
    bg.backgroundColor = dark ? iosRGB(0x3A3A3C) : UIColor.white
    bg.layer.cornerRadius = 14
    bg.layer.masksToBounds = true
    self.bgView = bg

    let tail = UIView(frame: CGRect(x: size.width / 2 - 6, y: Self.contentHeight - 5, width: 12, height: 12))
    tail.backgroundColor = bg.backgroundColor
    tail.layer.cornerRadius = 3
    tail.transform = CGAffineTransform(rotationAngle: .pi / 4)
    self.tailView = tail

    var labels: [UILabel] = []
    for (index, letter) in letters.enumerated() {
      let label = UILabel(frame: CGRect(
        x: Self.paddingX + CGFloat(index) * Self.itemWidth,
        y: (Self.contentHeight - 34) / 2,
        width: Self.itemWidth,
        height: 34
      ))
      label.text = letter
      label.textAlignment = .center
      label.font = UIFont.systemFont(ofSize: 19, weight: .medium)
      label.textColor = dark ? UIColor.white : UIColor.black
      label.layer.cornerRadius = 17
      label.layer.masksToBounds = true
      labels.append(label)
    }
    self.labels = labels

    super.init(frame: CGRect(origin: .zero, size: size))

    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.22
    layer.shadowRadius = 5
    layer.shadowOffset = CGSize(width: 0, height: 3)

    addSubview(bg)
    addSubview(tail)
    labels.forEach(addSubview)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func updateSelection(index: Int?) {
    selectedIndex = index
    for (i, label) in labels.enumerated() {
      let isSelected = i == index
      label.backgroundColor = isSelected ? UIColor.systemBlue : .clear
      label.textColor = isSelected ? UIColor.white : (dark ? UIColor.white : UIColor.black)
    }
  }
}

// MARK: - emoji 返回键语言记忆

/// 进入 emoji 面板前最近一次原生面板是否英文族（英文26键及其 123/#+=）
/// IOSNativeKeyboardView 渲染面板时写入，EmojisKeyboard 读取决定返回键文字（ABC / 拼音）
enum IOSNativeEmojiReturnState {
  static var lastPanelWasEnglish: Bool = false
}
