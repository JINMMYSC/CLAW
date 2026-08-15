//
//  IOSNativeLayout.swift
//
//  ClawTalk "iOS Native Layout" geometry service.
//  Design space: 375 x (paddingV + 3*(rowH+gapV) + rowH) = 190.4.
//  All panels output design-space rects; IOSNativeKeyboardView scales to fit.
//

import CoreGraphics
import UIKit

// MARK: - Design constants

public enum IOSNativeDesign {
  public static let width: CGFloat = 375
  public static let paddingH: CGFloat = 3.5
  public static let paddingV: CGFloat = 4
  public static let gapH: CGFloat = 5.5
  public static let gapV: CGFloat = 8.8
  public static let rowH: CGFloat = 40
  public static let radius: CGFloat = 6
  public static let height: CGFloat = paddingV + 3 * (rowH + gapV) + rowH
}

// MARK: - Panel enum

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

// MARK: - Key model

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

// MARK: - Global state

public enum IOSNativeState {
  /// Last QWERTY keyboard type (used by p8/p9 "ABC" back action).
  public static var lastQWERTYType: KeyboardType = .chinese(.lowercased)
}

// MARK: - Layout service

public enum IOSNativeLayout {
  /// Current keyboard type -> native panel.
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

  // MARK: - Helpers

  private static var p: CGFloat { IOSNativeDesign.paddingH }
  private static var pv: CGFloat { IOSNativeDesign.paddingV }
  private static var gh: CGFloat { IOSNativeDesign.gapH }
  private static var gv: CGFloat { IOSNativeDesign.gapV }
  private static var rowH: CGFloat { IOSNativeDesign.rowH }
  private static var W: CGFloat { IOSNativeDesign.width }

  /// Function-key width on English panels (Shift / backspace / #+= / 123).
  private static let enFuncW: CGFloat = 43.3
  /// Function-key width on English bottom row (123 / ABC / emoji).
  private static let enBottomFuncW: CGFloat = 41.3
  /// Symbol-key width on Chinese-symbol row 3.
  private static let cnSymUnit: CGFloat = 39.5
  /// Function-key width on Chinese-symbol bottom row (pinyin / send).
  private static let cnBottomFuncW: CGFloat = 88

  private static func fiveUnit() -> CGFloat {
    (W - 2 * p - 4 * gh) / 5
  }

  private static func tenUnit() -> CGFloat {
    (W - 2 * p - 9 * gh) / 10
  }

  /// Y coordinate of the given row index (0-based).
  private static func rowY(_ index: Int) -> CGFloat {
    pv + CGFloat(index) * (rowH + gv)
  }

  /// X origin of the English QWERTY row-2 letter block (Z left edge), centered between Shift and backspace.
  private static func enLetterBlockX() -> CGFloat {
    let blockW = 7 * tenUnit() + 6 * gh
    return W / 2 - blockW / 2
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

  // MARK: - p1 Pinyin 9-key

  private static func pinyin9Keys(context: KeyboardContext) -> [IOSNativeKey] {
    let unit = fiveUnit()
    var result: [IOSNativeKey] = []
    func row(_ items: [(String, String)], _ y: CGFloat, _ make: (String) -> IOSNativeKey) {
      for (i, item) in items.enumerated() {
        let k = key(make(item.0), p + CGFloat(i) * (unit + gh), y, unit, rowH)
        result.append(IOSNativeKey(action: k.action, displayText: item.1, rect: k.rect, isSend: false, isInputAction: k.isInputAction))
      }
    }
    row([("123", "123"), ("，。？！", "，。？！"), ("ABC", "ABC"), ("DEF", "DEF")], rowY(0)) {
      switch $0 {
      case "123": return IOSNativeKey(action: .keyboardType(.numericNineGrid), displayText: nil, rect: .zero)
      case "，。？！": return IOSNativeKey(action: .character(","), displayText: nil, rect: .zero)
      default: return nineKey($0)
      }
    }
    result.append(key(IOSNativeKey(action: .backspace, displayText: "⌫", rect: .zero), p + 4 * (unit + gh), rowY(0), unit, rowH))
    row([("#@¥", "#@¥"), ("GHI", "GHI"), ("JKL", "JKL"), ("MNO", "MNO"), ("^_^", "^_^")], rowY(1)) {
      switch $0 {
      case "#@¥": return IOSNativeKey(action: .keyboardType(.classifySymbolic), displayText: nil, rect: .zero)
      case "^_^": return IOSNativeKey(action: .character("^_^"), displayText: nil, rect: .zero)
      default: return nineKey($0)
      }
    }
    row([("ABC2", "ABC"), ("PQRS", "PQRS"), ("TUV", "TUV"), ("WXYZ", "WXYZ")], rowY(2)) {
      switch $0 {
      case "ABC2": return IOSNativeKey(action: .keyboardType(.chinese(.lowercased)), displayText: nil, rect: .zero)
      default: return nineKey($0)
      }
    }
    // Row-2 col-5: send, spanning rows 2-3.
    result.append(key(IOSNativeKey(action: .primary(.return), displayText: "发送", rect: .zero, isSend: true), p + 4 * (unit + gh), rowY(2), unit, 2 * rowH + gv))
    // Row 3: emoji | select-pinyin | space (2 columns).
    result.append(key(IOSNativeKey(action: .keyboardType(.emojis), displayText: "😀", rect: .zero), p, rowY(3), unit, rowH))
    result.append(key(IOSNativeKey(action: .custom(named: "iosNative.noop"), displayText: "选拼音", rect: .zero), p + unit + gh, rowY(3), unit, rowH))
    result.append(key(IOSNativeKey(action: .space, displayText: "空格", rect: .zero), p + 2 * unit + 2 * gh, rowY(3), 2 * unit + gh, rowH))
    return result
  }

  // MARK: - p2 Number 9-key

  private static func numberKeys(context: KeyboardContext) -> [IOSNativeKey] {
    let unit = fiveUnit()
    var result: [IOSNativeKey] = []
    func row(_ items: [(String, String)], _ y: CGFloat, _ make: (String) -> IOSNativeKey) {
      for (i, item) in items.enumerated() {
        let k = key(make(item.0), p + CGFloat(i) * (unit + gh), y, unit, rowH)
        result.append(IOSNativeKey(action: k.action, displayText: item.1, rect: k.rect, isSend: false, isInputAction: k.isInputAction))
      }
    }
    row([("拼音", "拼音"), ("1", "1"), ("2", "2"), ("3", "3")], rowY(0)) {
      switch $0 {
      case "拼音": return IOSNativeKey(action: .keyboardType(.chineseNineGrid), displayText: nil, rect: .zero)
      default: return charKey($0)
      }
    }
    result.append(key(IOSNativeKey(action: .backspace, displayText: "⌫", rect: .zero), p + 4 * (unit + gh), rowY(0), unit, rowH))
    row([("#@¥", "#@¥"), ("4", "4"), ("5", "5"), ("6", "6")], rowY(1)) {
      switch $0 {
      case "#@¥": return IOSNativeKey(action: .keyboardType(.classifySymbolic), displayText: nil, rect: .zero)
      default: return charKey($0)
      }
    }
    result.append(key(IOSNativeKey(action: .keyboardType(.chineseNumeric), displayText: "更多", rect: .zero), p + 4 * (unit + gh), rowY(1), unit, rowH))
    row([("ABC", "ABC"), ("7", "7"), ("8", "8"), ("9", "9")], rowY(2)) {
      switch $0 {
      case "ABC": return IOSNativeKey(action: .keyboardType(.chinese(.lowercased)), displayText: nil, rect: .zero)
      default: return charKey($0)
      }
    }
    result.append(key(IOSNativeKey(action: .primary(.return), displayText: "发送", rect: .zero, isSend: true), p + 4 * (unit + gh), rowY(2), unit, 2 * rowH + gv))
    result.append(key(IOSNativeKey(action: .keyboardType(.emojis), displayText: "😀", rect: .zero), p, rowY(3), unit, rowH))
    result.append(key(IOSNativeKey(action: .character("."), displayText: ". , :", rect: .zero), p + unit + gh, rowY(3), unit, rowH))
    result.append(key(IOSNativeKey(action: .character("0"), displayText: "0", rect: .zero), p + 2 * unit + 2 * gh, rowY(3), unit, rowH))
    result.append(key(IOSNativeKey(action: .space, displayText: "空格", rect: .zero), p + 3 * unit + 3 * gh, rowY(3), unit, rowH))
    return result
  }

  // MARK: - p3 Number more

  private static func numberMoreKeys(context: KeyboardContext) -> [IOSNativeKey] {
    let unit = fiveUnit()
    var result: [IOSNativeKey] = []
    func row(_ items: [(String, String)], _ y: CGFloat, _ make: (String) -> IOSNativeKey) {
      for (i, item) in items.enumerated() {
        let k = key(make(item.0), p + CGFloat(i) * (unit + gh), y, unit, rowH)
        result.append(IOSNativeKey(action: k.action, displayText: item.1, rect: k.rect, isSend: false, isInputAction: k.isInputAction))
      }
    }
    row([("拼音", "拼音"), ("\u00a5", "\u00a5"), ("\u2103", "\u2103"), ("%", "%")], rowY(0)) {
      switch $0 {
      case "拼音": return IOSNativeKey(action: .keyboardType(.chineseNineGrid), displayText: nil, rect: .zero)
      default: return charKey($0)
      }
    }
    result.append(key(IOSNativeKey(action: .backspace, displayText: "⌫", rect: .zero), p + 4 * (unit + gh), rowY(0), unit, rowH))
    row([("#@¥", "#@¥"), (",", ","), ("+", "+"), ("-", "-")], rowY(1)) {
      switch $0 {
      case "#@¥": return IOSNativeKey(action: .keyboardType(.classifySymbolic), displayText: nil, rect: .zero)
      default: return charKey($0)
      }
    }
    result.append(key(IOSNativeKey(action: .keyboardType(.numericNineGrid), displayText: "更多", rect: .zero), p + 4 * (unit + gh), rowY(1), unit, rowH))
    row([("ABC", "ABC"), (":", ":"), ("/", "/"), ("=", "=")], rowY(2)) {
      switch $0 {
      case "ABC": return IOSNativeKey(action: .keyboardType(.chinese(.lowercased)), displayText: nil, rect: .zero)
      default: return charKey($0)
      }
    }
    result.append(key(IOSNativeKey(action: .primary(.return), displayText: "发送", rect: .zero, isSend: true), p + 4 * (unit + gh), rowY(2), unit, 2 * rowH + gv))
    result.append(key(IOSNativeKey(action: .keyboardType(.emojis), displayText: "😀", rect: .zero), p, rowY(3), unit, rowH))
    result.append(key(IOSNativeKey(action: .character("."), displayText: ".", rect: .zero), p + unit + gh, rowY(3), unit, rowH))
    result.append(key(IOSNativeKey(action: .character("_"), displayText: "_", rect: .zero), p + 2 * unit + 2 * gh, rowY(3), unit, rowH))
    result.append(key(IOSNativeKey(action: .space, displayText: "空格", rect: .zero), p + 3 * unit + 3 * gh, rowY(3), unit, rowH))
    return result
  }

  // MARK: - p4/p5 Chinese symbols (10 columns)

  private static func cnSymbolKeys(context: KeyboardContext, page: Int) -> [IOSNativeKey] {
    let unit = tenUnit()
    var result: [IOSNativeKey] = []
    func addRow10(_ items: [String], _ y: CGFloat) {
      for (i, ch) in items.enumerated() {
        result.append(key(charKey(ch), p + CGFloat(i) * (unit + gh), y, unit, rowH))
      }
    }
    if page == 1 {
      addRow10(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"], rowY(0))
      addRow10(["-", "/", ":", ";", "(", ")", "¥", "@", "“", "”"], rowY(1))
    } else {
      addRow10(["【", "】", "{", "}", "#", "%", "^", "*", "+", "="], rowY(0))
      addRow10(["_", "—", "\\", "|", "~", "《", "》", "$", "&", "."], rowY(1))
    }
    // Row 3: #+=/123 (43.3) | 6 symbols (39.5, centered) | backspace (43.3).
    let y3 = rowY(2)
    let switchKey = page == 1 ? "#@¥" : "123"
    let switchAction: KeyboardAction = page == 1 ? .keyboardType(.chineseSymbolic) : .keyboardType(.classifySymbolic)
    result.append(key(IOSNativeKey(action: switchAction, displayText: switchKey, rect: .zero), p, y3, enFuncW, rowH))
    let symStart = W / 2 - (6 * cnSymUnit + 5 * gh) / 2
    let syms = page == 1 ? ["。", ",", "、", "？", "！", "."] : ["…", ",", "^_^", "？", "！", "’"]
    for (i, ch) in syms.enumerated() {
      result.append(key(charKey(ch), symStart + CGFloat(i) * (cnSymUnit + gh), y3, cnSymUnit, rowH))
    }
    result.append(key(IOSNativeKey(action: .backspace, displayText: "⌫", rect: .zero), W - p - enFuncW, y3, enFuncW, rowH))
    // Row 4: pinyin (88) | space | send (88).
    let y4 = rowY(3)
    result.append(key(IOSNativeKey(action: .keyboardType(.chineseNineGrid), displayText: "拼音", rect: .zero), p, y4, cnBottomFuncW, rowH))
    let spaceX = p + cnBottomFuncW + gh
    let spaceW = W - 2 * p - 2 * cnBottomFuncW - 2 * gh
    result.append(key(IOSNativeKey(action: .space, displayText: "空格", rect: .zero), spaceX, y4, spaceW, rowH))
    result.append(key(IOSNativeKey(action: .primary(.return), displayText: "发送", rect: .zero, isSend: true), spaceX + spaceW + gh, y4, cnBottomFuncW, rowH))
    return result
  }

  private static func cnSymbol1Keys(context: KeyboardContext) -> [IOSNativeKey] {
    cnSymbolKeys(context: context, page: 1)
  }

  private static func cnSymbol2Keys(context: KeyboardContext) -> [IOSNativeKey] {
    cnSymbolKeys(context: context, page: 2)
  }

  // MARK: - p6/p7 English QWERTY

  private static func enKeys(context: KeyboardContext, uppercase: Bool) -> [IOSNativeKey] {
    let unitW = tenUnit()
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
    push(r0, p, rowY(0))
    push(r1, p + (unitW + gh) / 2, rowY(1))
    // Row 3: Shift | ZXCVBNM (centered) | backspace.
    let y2 = rowY(2)
    let blockX = enLetterBlockX()
    let shiftAction = shiftAction(context: context)
    result.append(key(IOSNativeKey(action: shiftAction, displayText: "⬆", rect: .zero), p, y2, enFuncW, rowH))
    push(r2, blockX, y2)
    result.append(key(IOSNativeKey(action: .backspace, displayText: "⌫", rect: .zero), W - p - enFuncW, y2, enFuncW, rowH))
    // Row 4: 123 | emoji | space | send.
    let y4 = rowY(3)
    let nRight = blockX + 5 * (unitW + gh) + unitW
    let mLeft = blockX + 6 * (unitW + gh)
    let emojiX = p + enBottomFuncW + gh
    result.append(key(IOSNativeKey(action: .keyboardType(.numeric), displayText: "123", rect: .zero), p, y4, enBottomFuncW, rowH))
    result.append(key(IOSNativeKey(action: .keyboardType(.emojis), displayText: "😀", rect: .zero), emojiX, y4, enBottomFuncW, rowH))
    let spaceX = emojiX + enBottomFuncW + gh
    result.append(key(IOSNativeKey(action: .space, displayText: "space", rect: .zero), spaceX, y4, nRight - spaceX, rowH))
    result.append(key(IOSNativeKey(action: .primary(.return), displayText: "send", rect: .zero, isSend: true), mLeft, y4, W - p - mLeft, rowH))
    IOSNativeState.lastQWERTYType = context.keyboardType
    return result
  }

  // MARK: - p8/p9 English number/symbol (10 columns)

  private static func enNumberSymbolKeys(context: KeyboardContext, page: Int) -> [IOSNativeKey] {
    let unit = tenUnit()
    var result: [IOSNativeKey] = []
    func addRow10(_ items: [String], _ y: CGFloat) {
      for (i, ch) in items.enumerated() {
        result.append(key(charKey(ch), p + CGFloat(i) * (unit + gh), y, unit, rowH))
      }
    }
    if page == 1 {
      addRow10(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"], rowY(0))
      addRow10(["-", "/", ":", ";", "(", ")", "$", "&", "@", "”"], rowY(1))
    } else {
      addRow10(["[", "]", "{", "}", "#", "%", "^", "*", "+", "="], rowY(0))
      addRow10(["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "."], rowY(1))
    }
    // Row 3: #+=/123 (43.3) | 5 symbols (Z-left to M-right) | backspace (43.3).
    let y3 = rowY(2)
    let blockX = enLetterBlockX()
    let zLeft = blockX
    let mRight = blockX + 6 * (unit + gh) + unit
    let symW = (mRight - zLeft - 4 * gh) / 5
    let switchKey = page == 1 ? "#@¥" : "123"
    let switchAction: KeyboardAction = page == 1 ? .keyboardType(.symbolic) : .keyboardType(.numeric)
    result.append(key(IOSNativeKey(action: switchAction, displayText: switchKey, rect: .zero), p, y3, enFuncW, rowH))
    let syms = page == 1 ? [".", ",", "?", "!", "’"] : [".", ",", "?", "!", "'"]
    for (i, ch) in syms.enumerated() {
      result.append(key(charKey(ch), zLeft + CGFloat(i) * (symW + gh), y3, symW, rowH))
    }
    result.append(key(IOSNativeKey(action: .backspace, displayText: "⌫", rect: .zero), W - p - enFuncW, y3, enFuncW, rowH))
    // Row 4: ABC | emoji | space | send (same geometry as English 26-key).
    let y4 = rowY(3)
    let nRight = blockX + 5 * (unit + gh) + unit
    let mLeft = blockX + 6 * (unit + gh)
    let emojiX = p + enBottomFuncW + gh
    result.append(key(IOSNativeKey(action: .keyboardType(IOSNativeState.lastQWERTYType), displayText: "ABC", rect: .zero), p, y4, enBottomFuncW, rowH))
    result.append(key(IOSNativeKey(action: .keyboardType(.emojis), displayText: "😀", rect: .zero), emojiX, y4, enBottomFuncW, rowH))
    let spaceX = emojiX + enBottomFuncW + gh
    result.append(key(IOSNativeKey(action: .space, displayText: "space", rect: .zero), spaceX, y4, nRight - spaceX, rowH))
    result.append(key(IOSNativeKey(action: .primary(.return), displayText: "send", rect: .zero, isSend: true), mLeft, y4, W - p - mLeft, rowH))
    return result
  }

  private static func enNumberKeys(context: KeyboardContext) -> [IOSNativeKey] {
    enNumberSymbolKeys(context: context, page: 1)
  }

  private static func enSymbolKeys(context: KeyboardContext) -> [IOSNativeKey] {
    enNumberSymbolKeys(context: context, page: 2)
  }
}
