//
//  IOSNativeLayout.swift
//
//  ClawTalk “IOS 原生布局”几何服务
//
//  点位 1:1 复刻 keyboard-layout-preview-v2.html 的设计空间（375 x 182）：
//  W=375 H=182 paddingH=3 paddingV=4 gapH=4 gapV=6 rowH=40 radius=6 candH=40
//  所有面板输出设计空间内 rect，由 IOSNativeKeyboardView 按实际宽高缩放渲染。
//

import CoreGraphics
import UIKit

// MARK: - 设计常量

public enum IOSNativeDesign {
  public static let width: CGFloat = 375
  public static let height: CGFloat = 182
  public static let paddingH: CGFloat = 3
  public static let paddingV: CGFloat = 4
  public static let gapH: CGFloat = 4
  public static let gapV: CGFloat = 6
  public static let rowH: CGFloat = 40
  public static let radius: CGFloat = 6
}

// MARK: - 面板枚举

/// iOS 原生布局面板（对应预览 HTML p1~p9；p10 表情复用现有 EmojisKeyboard）
public enum IOSNativePanel: Equatable {
  case pinyin9
  case number
  case numberMore
  case cnSymbol1
  case cnSymbol2
  case enUpper
  case enLower
  case enNumber
  case enSymbol
}

// MARK: - 键位模型

public struct IOSNativeKey {
  public let action: KeyboardAction
  public let displayText: String?
  public let rect: CGRect
  public let isSend: Bool
  public let isInputAction: Bool

  public init(action: KeyboardAction, displayText: String?, rect: CGRect, isSend: Bool = false, isInputAction: Bool = false) {
    self.action = action
    self.displayText = displayText
    self.rect = rect
    self.isSend = isSend
    self.isInputAction = isInputAction
  }
}

// MARK: - 全局状态

public enum IOSNativeState {
  /// 中英 QWERTY 主键盘类型（用于 p8/p9 的 ABC 返回）
  public static var lastQWERTYType: KeyboardType = .chinese(.lowercased)
}

// MARK: - 布局服务

public enum IOSNativeLayout {
  /// 当前键盘类型 → iOS 原生面板
  public static func panel(for keyboardType: KeyboardType) -> IOSNativePanel? {
    switch keyboardType {
    case .chineseNineGrid: return .pinyin9
    case .numericNineGrid: return .number
    case .chineseNumeric: return .numberMore
    case .classifySymbolic: return .cnSymbol1
    case .chineseSymbolic: return .cnSymbol2
    case .alphabetic(.uppercased), .chinese(.uppercased): return .enUpper
    case .alphabetic(.lowercased), .chinese(.lowercased): return .enLower
    case .numeric: return .enNumber
    case .symbolic: return .enSymbol
    default: return nil
    }
  }

  public static func keys(for panel: IOSNativePanel, context: KeyboardContext) -> [IOSNativeKey] {
    switch panel {
    case .pinyin9: return pinyin9Keys(context: context)
    case .number: return numberKeys(context: context)
    case .numberMore: return numberMoreKeys(context: context)
    case .cnSymbol1: return cnSymbol1Keys(context: context)
    case .cnSymbol2: return cnSymbol2Keys(context: context)
    case .enUpper: return enKeys(context: context, uppercase: true)
    case .enLower: return enKeys(context: context, uppercase: false)
    case .enNumber: return enNumberKeys(context: context)
    case .enSymbol: return enSymbolKeys(context: context)
    }
  }

  // MARK: - 工具

  private static var p: CGFloat { IOSNativeDesign.paddingH }
  private static var pv: CGFloat { IOSNativeDesign.paddingV }
  private static var gh: CGFloat { IOSNativeDesign.gapH }
  private static var gv: CGFloat { IOSNativeDesign.gapV }
  private static var rowH: CGFloat { IOSNativeDesign.rowH }
  private static var W: CGFloat { IOSNativeDesign.width }

  private static func fiveUnit() -> CGFloat {
    (W - 2 * p - 4 * gh) / 5
  }

  private static func tenUnit() -> CGFloat {
    (W - 2 * p - 9 * gh) / 10
  }

  private static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: y, width: w, height: h)
  }

  private static func charKey(_ char: String) -> IOSNativeKey {
    IOSNativeKey(action: .character(char), displayText: char, rect: .zero, isInputAction: true)
  }

  private static func nineKey(_ chars: String) -> IOSNativeKey {
    IOSNativeKey(action: .chineseNineGrid(Symbol(char: chars)), displayText: chars, rect: .zero, isInputAction: true)
  }

  private static func key(_ k: IOSNativeKey, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> IOSNativeKey {
    IOSNativeKey(action: k.action, displayText: k.displayText, rect: rect(x, y, w, h), isSend: k.isSend, isInputAction: k.isInputAction)
  }

  private static func qwertyBackType(context: KeyboardContext) -> KeyboardType {
    let t = context.keyboardType
    if t.isChinesePrimaryKeyboard { return .chinese(.lowercased) }
    return .alphabetic(.lowercased)
  }

  private static func shiftAction(context: KeyboardContext) -> KeyboardAction {
    let t = context.keyboardType
    switch t {
    case .chinese(.lowercased): return .keyboardType(.chinese(.uppercased))
    case .chinese(.uppercased): return .keyboardType(.chinese(.lowercased))
    case .alphabetic(.lowercased): return .keyboardType(.alphabetic(.uppercased))
    case .alphabetic(.uppercased): return .keyboardType(.alphabetic(.lowercased))
    default: return .keyboardType(.alphabetic(.uppercased))
    }
  }

  // MARK: - p1 拼音9键

  private static func pinyin9Keys(context: KeyboardContext) -> [IOSNativeKey] {
    let unit = fiveUnit()
    var result: [IOSNativeKey] = []
    func row(_ items: [(String, String)], _ y: CGFloat, _ make: (String) -> IOSNativeKey) {
      for (i, item) in items.enumerated() {
        let k = key(make(item.0), p + CGFloat(i) * (unit + gh), y, unit, rowH)
        result.append(IOSNativeKey(action: k.action, displayText: item.1, rect: k.rect, isSend: false, isInputAction: k.isInputAction))
      }
    }
    row([("123", "123"), (",。？！", ",。？！"), ("ABC", "ABC"), ("DEF", "DEF")], pv) {
      switch $0 {
      case "123": return IOSNativeKey(action: .keyboardType(.numericNineGrid), displayText: nil, rect: .zero)
      case ",。？！": return IOSNativeKey(action: .character(","), displayText: nil, rect: .zero)
      default: return nineKey($0)
      }
    }
    // 行0第5列→退格键
    result.append(key(IOSNativeKey(action: .backspace, displayText: "⌫", rect: .zero), p + 4 * (unit + gh), pv, unit, rowH))
    row([("#@¥", "#@¥"), ("GHI", "GHI"), ("JKL", "JKL"), ("MNO", "MNO"), ("^_^", "^_^")], pv + rowH + gv) {
      switch $0 {
      case "#@¥": return IOSNativeKey(action: .keyboardType(.classifySymbolic), displayText: nil, rect: .zero)
      case "^_^": return IOSNativeKey(action: .character("^_^"), displayText: nil, rect: .zero)
      default: return nineKey($0)
      }
    }
    // 行2：ABC2 | PQRS | TUV | WXYZ | SEND(大)
    row([("ABC2", "ABC"), ("PQRS", "PQRS"), ("TUV", "TUV"), ("WXYZ", "WXYZ")], pv + 2 * (rowH + gv)) {
      switch $0 {
      case "ABC2": return IOSNativeKey(action: .keyboardType(.chinese(.lowercased)), displayText: nil, rect: .zero)
      default: return nineKey($0)
      }
    }
    let sendY = pv + 2 * (rowH + gv)
    result.append(key(IOSNativeKey(action: .primary(.return), displayText: "发送", rect: .zero, isSend: true), p + 4 * (unit + gh), sendY, unit, 2 * rowH + gv))
    let y4 = pv + 3 * (rowH + gv)
    result.append(key(IOSNativeKey(action: .keyboardType(.emojis), displayText: "😀", rect: .zero), p, y4, unit, rowH))
    result.append(key(IOSNativeKey(action: .custom(named: "iosNative.noop"), displayText: "选拼音", rect: .zero), p + unit + gh, y4, unit, rowH))
    result.append(key(IOSNativeKey(action: .space, displayText: "空格", rect: .zero), p + 2 * unit + 2 * gh, y4, 2 * unit + gh, rowH))
    return result
  }

  // MARK: - p2 数字面板

  private static func numberKeys(context: KeyboardContext) -> [IOSNativeKey] {
    let unit = fiveUnit()
    var result: [IOSNativeKey] = []
    func row(_ items: [(String, String)], _ y: CGFloat, _ make: (String) -> IOSNativeKey) {
      for (i, item) in items.enumerated() {
        let k = key(make(item.0), p + CGFloat(i) * (unit + gh), y, unit, rowH)
        result.append(IOSNativeKey(action: k.action, displayText: item.1, rect: k.rect, isSend: false, isInputAction: k.isInputAction))
      }
    }
    row([("拼音", "拼音"), ("1", "1"), ("2", "2"), ("3", "3")], pv) {
      switch $0 {
      case "拼音": return IOSNativeKey(action: .keyboardType(.chineseNineGrid), displayText: nil, rect: .zero)
      default: return charKey($0)
      }
    }
    result.append(key(IOSNativeKey(action: .backspace, displayText: "⌫", rect: .zero), p + 4 * (unit + gh), pv, unit, rowH))
    row([("#@¥", "#@¥"), ("4", "4"), ("5", "5"), ("6", "6")], pv + rowH + gv) {
      switch $0 {
      case "#@¥": return IOSNativeKey(action: .keyboardType(.classifySymbolic), displayText: nil, rect: .zero)
      default: return charKey($0)
      }
    }
    result.append(key(IOSNativeKey(action: .keyboardType(.chineseNumeric), displayText: "更多", rect: .zero), p + 4 * (unit + gh), pv + rowH + gv, unit, rowH))
    row([("ABC", "ABC"), ("7", "7"), ("8", "8"), ("9", "9")], pv + 2 * (rowH + gv)) {
      switch $0 {
      case "ABC": return IOSNativeKey(action: .keyboardType(.chinese(.lowercased)), displayText: nil, rect: .zero)
      default: return charKey($0)
      }
    }
    let sendY = pv + 2 * (rowH + gv)
    result.append(key(IOSNativeKey(action: .primary(.return), displayText: "发送", rect: .zero, isSend: true), p + 4 * (unit + gh), sendY, unit, 2 * rowH + gv))
    let y4 = pv + 3 * (rowH + gv)
    result.append(key(IOSNativeKey(action: .keyboardType(.emojis), displayText: "😀", rect: .zero), p, y4, unit, rowH))
    result.append(key(IOSNativeKey(action: .character("."), displayText: ". , :", rect: .zero), p + unit + gh, y4, unit, rowH))
    result.append(key(IOSNativeKey(action: .character("0"), displayText: "0", rect: .zero), p + 2 * unit + 2 * gh, y4, unit, rowH))
    result.append(key(IOSNativeKey(action: .space, displayText: "空格", rect: .zero), p + 3 * unit + 3 * gh, y4, unit, rowH))
    return result
  }

  // MARK: - p3 更多数字

  private static func numberMoreKeys(context: KeyboardContext) -> [IOSNativeKey] {
    let unit = fiveUnit()
    var result: [IOSNativeKey] = []
    func row(_ items: [(String, String)], _ y: CGFloat, _ make: (String) -> IOSNativeKey) {
      for (i, item) in items.enumerated() {
        let k = key(make(item.0), p + CGFloat(i) * (unit + gh), y, unit, rowH)
        result.append(IOSNativeKey(action: k.action, displayText: item.1, rect: k.rect, isSend: false, isInputAction: k.isInputAction))
      }
    }
    row([("拼音", "拼音"), ("¥", "¥"), ("℃", "℃"), ("%", "%")], pv) {
      switch $0 {
      case "拼音": return IOSNativeKey(action: .keyboardType(.chineseNineGrid), displayText: nil, rect: .zero)
      default: return charKey($0)
      }
    }
    result.append(key(IOSNativeKey(action: .backspace, displayText: "⌫", rect: .zero), p + 4 * (unit + gh), pv, unit, rowH))
    row([("#@¥", "#@¥"), (",", ","), ("+", "+"), ("-", "-")], pv + rowH + gv) {
      switch $0 {
      case "#@¥": return IOSNativeKey(action: .keyboardType(.classifySymbolic), displayText: nil, rect: .zero)
      default: return charKey($0)
      }
    }
    result.append(key(IOSNativeKey(action: .keyboardType(.numericNineGrid), displayText: "更多", rect: .zero), p + 4 * (unit + gh), pv + rowH + gv, unit, rowH))
    row([("ABC", "ABC"), (":", ":"), ("/", "/"), ("=", "=")], pv + 2 * (rowH + gv)) {
      switch $0 {
      case "ABC": return IOSNativeKey(action: .keyboardType(.chinese(.lowercased)), displayText: nil, rect: .zero)
      default: return charKey($0)
      }
    }
    let sendY = pv + 2 * (rowH + gv)
    result.append(key(IOSNativeKey(action: .primary(.return), displayText: "发送", rect: .zero, isSend: true), p + 4 * (unit + gh), sendY, unit, 2 * rowH + gv))
    let y4 = pv + 3 * (rowH + gv)
    result.append(key(IOSNativeKey(action: .keyboardType(.emojis), displayText: "😀", rect: .zero), p, y4, unit, rowH))
    result.append(key(IOSNativeKey(action: .character("."), displayText: ".", rect: .zero), p + unit + gh, y4, unit, rowH))
    result.append(key(IOSNativeKey(action: .character("_"), displayText: "_", rect: .zero), p + 2 * unit + 2 * gh, y4, unit, rowH))
    result.append(key(IOSNativeKey(action: .space, displayText: "空格", rect: .zero), p + 3 * unit + 3 * gh, y4, unit, rowH))
    return result
  }

  // MARK: - p4/p5 中文符号 10列

  private static func cnSymbolKeys(context: KeyboardContext, page: Int) -> [IOSNativeKey] {
    let unit = tenUnit()
    var result: [IOSNativeKey] = []
    func addRow10(_ items: [String], _ y: CGFloat) {
      for (i, ch) in items.enumerated() {
        result.append(key(charKey(ch), p + CGFloat(i) * (unit + gh), y, unit, rowH))
      }
    }
    if page == 1 {
      addRow10(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"], pv)
      addRow10(["-", "/", ":", ";", "(", ")", "¥", "@", "“", "”"], pv + rowH + gv)
    } else {
      addRow10(["【", "】", "{", "}", "#", "%", "^", "*", "+", "="], pv)
      addRow10(["_", "—", "\\", "|", "~", "《", "》", "$", "&", "."], pv + rowH + gv)
    }
    // 第3排：#+= 右缘=/ 键列中线，⌫ 左缘=“ 键列中线，6 个符号键加宽
    let y3 = pv + 2 * (rowH + gv)
    let midSlash = p + (unit + gh) + unit / 2
    let midQuote = p + 8 * (unit + gh) + unit / 2
    let funcW = midSlash - p
    let symStart = midSlash + gh
    let symEnd = midQuote - gh
    let symW = (symEnd - symStart - 5 * gh) / 6
    let switchKey = page == 1 ? "#+=" : "123"
    let switchAction: KeyboardAction = page == 1 ? .keyboardType(.chineseSymbolic) : .keyboardType(.classifySymbolic)
    result.append(key(IOSNativeKey(action: switchAction, displayText: switchKey, rect: .zero), p, y3, funcW, rowH))
    let syms = page == 1 ? ["。", ",", "、", "？", "！", "."] : ["…", ",", "^_^", "？", "！", "’"]
    for (i, ch) in syms.enumerated() {
      result.append(key(charKey(ch), symStart + CGFloat(i) * (symW + gh), y3, symW, rowH))
    }
    result.append(key(IOSNativeKey(action: .backspace, displayText: "⌫", rect: .zero), midQuote, y3, W - p - midQuote, rowH))
    // 第4排：拼音 | 空格 | 发送
    let y4 = pv + 3 * (rowH + gv)
    let pinyinRight = symStart + symW
    let dotLeft = symStart + 5 * (symW + gh)
    result.append(key(IOSNativeKey(action: .keyboardType(.chineseNineGrid), displayText: "拼音", rect: .zero), p, y4, pinyinRight - p, rowH))
    result.append(key(IOSNativeKey(action: .space, displayText: "空格", rect: .zero), pinyinRight + gh, y4, dotLeft - gh - (pinyinRight + gh), rowH))
    result.append(key(IOSNativeKey(action: .primary(.return), displayText: "发送", rect: .zero, isSend: true), dotLeft, y4, W - p - dotLeft, rowH))
    return result
  }

  private static func cnSymbol1Keys(context: KeyboardContext) -> [IOSNativeKey] {
    cnSymbolKeys(context: context, page: 1)
  }

  private static func cnSymbol2Keys(context: KeyboardContext) -> [IOSNativeKey] {
    cnSymbolKeys(context: context, page: 2)
  }

  // MARK: - p6/p7 英文 QWERTY

  private static func enKeys(context: KeyboardContext, uppercase: Bool) -> [IOSNativeKey] {
    let unitW = tenUnit()
    let shiftW = unitW * 1.55
    var result: [IOSNativeKey] = []
    let letters = uppercase ? "QWERTYUIOPASDFGHJKLZXCVBNM" : "qwertyuiopasdfghjklzxcvbnm"
    let r0 = Array(letters.prefix(10)).map(String.init)
    let r1 = Array(letters.dropFirst(10).prefix(9)).map(String.init)
    let r2 = Array(letters.dropFirst(19)).map(String.init)
    func push(_ chars: [String], _ offsetX: CGFloat, _ y: CGFloat) {
      for (i, ch) in chars.enumerated() {
        result.append(key(charKey(ch), offsetX + CGFloat(i) * (unitW + gh), y, unitW, rowH))
      }
    }
    push(r0, p, pv)
    push(r1, p + unitW / 2, pv + rowH + gv)
    let shiftAction = shiftAction(context: context)
    result.append(key(IOSNativeKey(action: shiftAction, displayText: "⬆", rect: .zero), p, pv + 2 * (rowH + gv), shiftW, rowH))
    push(r2, p + shiftW + gh, pv + 2 * (rowH + gv))
    result.append(key(IOSNativeKey(action: .backspace, displayText: "⌫", rect: .zero), W - p - shiftW, pv + 2 * (rowH + gv), shiftW, rowH))
    let y4 = pv + 3 * (rowH + gv)
    let emojiW = unitW
    let spaceX = p + shiftW + gh + emojiW + gh
    let nRight = p + shiftW + gh + 5 * (unitW + gh) + unitW
    let mLeft = p + shiftW + gh + 6 * (unitW + gh)
    let numberAction: KeyboardAction = context.keyboardType.isChinesePrimaryKeyboard ? .keyboardType(.numeric) : .keyboardType(.numeric)
    result.append(key(IOSNativeKey(action: numberAction, displayText: "123", rect: .zero), p, y4, shiftW, rowH))
    result.append(key(IOSNativeKey(action: .keyboardType(.emojis), displayText: "😀", rect: .zero), p + shiftW + gh, y4, emojiW, rowH))
    result.append(key(IOSNativeKey(action: .space, displayText: "space", rect: .zero), spaceX, y4, nRight - spaceX, rowH))
    result.append(key(IOSNativeKey(action: .primary(.return), displayText: "send", rect: .zero, isSend: true), mLeft, y4, W - p - mLeft, rowH))
    // 记录当前 QWERTY 类型，供 p8/p9 ABC 返回
    IOSNativeState.lastQWERTYType = context.keyboardType
    return result
  }

  // MARK: - p8/p9 英文数字/符号 10列

  private static func enNumberSymbolKeys(context: KeyboardContext, page: Int) -> [IOSNativeKey] {
    let unit = tenUnit()
    let shiftW3 = unit * 1.55
    var result: [IOSNativeKey] = []
    func addRow10(_ items: [String], _ y: CGFloat) {
      for (i, ch) in items.enumerated() {
        result.append(key(charKey(ch), p + CGFloat(i) * (unit + gh), y, unit, rowH))
      }
    }
    if page == 1 {
      addRow10(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"], pv)
      addRow10(["-", "/", ":", ";", "(", ")", "$", "&", "@", "”"], pv + rowH + gv)
    } else {
      addRow10(["[", "]", "{", "}", "#", "%", "^", "*", "+", "="], pv)
      addRow10(["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "."], pv + rowH + gv)
    }
    // 第3排：#+= 对齐 SHIFT，5 个符号键从 Z 左缘填到 M 右缘，⌫ 对齐 p6
    let y3 = pv + 2 * (rowH + gv)
    let zLeft = p + shiftW3 + gh
    let mRight = p + shiftW3 + gh + 6 * (unit + gh) + unit
    let symW = (mRight - zLeft - 4 * gh) / 5
    let switchKey = page == 1 ? "#+=" : "123"
    let switchAction: KeyboardAction = page == 1 ? .keyboardType(.symbolic) : .keyboardType(.numeric)
    result.append(key(IOSNativeKey(action: switchAction, displayText: switchKey, rect: .zero), p, y3, shiftW3, rowH))
    let syms = page == 1 ? [".", ",", "?", "!", "’"] : [".", ",", "?", "!", "'"]
    for (i, ch) in syms.enumerated() {
      result.append(key(charKey(ch), zLeft + CGFloat(i) * (symW + gh), y3, symW, rowH))
    }
    result.append(key(IOSNativeKey(action: .backspace, displayText: "⌫", rect: .zero), W - p - shiftW3, y3, shiftW3, rowH))
    // 第4排：ABC | 😀 | space | send
    let y4 = pv + 3 * (rowH + gv)
    let emojiW4 = unit
    let spaceX4 = p + shiftW3 + gh + emojiW4 + gh
    let nRight4 = p + shiftW3 + gh + 5 * (unit + gh) + unit
    let mLeft4 = p + shiftW3 + gh + 6 * (unit + gh)
    result.append(key(IOSNativeKey(action: .keyboardType(IOSNativeState.lastQWERTYType), displayText: "ABC", rect: .zero), p, y4, shiftW3, rowH))
    result.append(key(IOSNativeKey(action: .keyboardType(.emojis), displayText: "😀", rect: .zero), p + shiftW3 + gh, y4, emojiW4, rowH))
    result.append(key(IOSNativeKey(action: .space, displayText: "space", rect: .zero), spaceX4, y4, nRight4 - spaceX4, rowH))
    result.append(key(IOSNativeKey(action: .primary(.return), displayText: "send", rect: .zero, isSend: true), mLeft4, y4, W - p - mLeft4, rowH))
    return result
  }

  private static func enNumberKeys(context: KeyboardContext) -> [IOSNativeKey] {
    enNumberSymbolKeys(context: context, page: 1)
  }

  private static func enSymbolKeys(context: KeyboardContext) -> [IOSNativeKey] {
    enNumberSymbolKeys(context: context, page: 2)
  }
}