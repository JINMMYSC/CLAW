//
//  IOSNativeLayout.swift
//
//  ClawTalk "iOS Native Layout" geometry service.
//  Design space: 375 宽；纵向 rowH/gapV 按面板区分（9键族 50/6，紧凑族 46/10）。
//  All panels output design-space rects; IOSNativeKeyboardView scales to fit.
//

import CoreGraphics
import UIKit

// MARK: - Design constants

public enum IOSNativeGeometry {
  /// 9键族（p1 拼音9 / p2 数字9 / p3 更多）：P 图实测 rowH=50 gapV=6
  case nineGrid
  /// 紧凑族（p4-p9 中英文符号 / QWERTY）：P 图实测 rowH=46 gapV=10
  case compact
}

public enum IOSNativeDesign {
  public static let width: CGFloat = 375
  public static let paddingH: CGFloat = 3.5
  public static let paddingV: CGFloat = 4
  public static let gapH: CGFloat = 5.5
  public static let radius: CGFloat = 6

  public static func rowH(for panel: IOSNativePanel) -> CGFloat {
    panel.geometry == .nineGrid ? 50 : 46
  }

  public static func gapV(for panel: IOSNativePanel) -> CGFloat {
    panel.geometry == .nineGrid ? 6 : 10
  }

  public static func height(for panel: IOSNativePanel) -> CGFloat {
    paddingV + 3 * (rowH(for: panel) + gapV(for: panel)) + rowH(for: panel)
  }
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

  public var geometry: IOSNativeGeometry {
    switch self {
    case .pinyin9, .number, .numberMore: return .nineGrid
    case .cnSymbol1, .cnSymbol2, .enUpper, .enLower, .enNumber, .enSymbol: return .compact
    }
  }
}

// MARK: - Key model

  /// return 键强制配色：搜索/前往/继续=蓝，完成/换行=灰；nil 时按面板规则
public enum IOSNativeTint {
  case blue
  case gray
}

public struct IOSNativeKey {
  public let action: KeyboardAction
  public let displayText: String?
  public let rect: CGRect
  public let isSend: Bool
  public let isInputAction: Bool
  public let tintOverride: IOSNativeTint?

  public init(action: KeyboardAction, displayText: String?, rect: CGRect, isSend: Bool = false, isInputAction: Bool = false, tintOverride: IOSNativeTint? = nil) {
    self.action = action
    self.displayText = displayText
    self.rect = rect
    self.isSend = isSend
    self.isInputAction = isInputAction
    self.tintOverride = tintOverride
  }
}

// MARK: - Global state

public enum IOSNativeState {
  /// Last QWERTY keyboard type (used by p8/p9 "ABC" back action).
  public static var lastQWERTYType: KeyboardType = .chinese(.lowercased)
}

// MARK: - Custom action ids（与 StandardKeyboardActionHandler 的 custom 分支契约）

/// IOS 原生布局自定义按键 action id
public enum IOSNativeCustomAction {
  /// 「，。？！ 」标点循环键：每按一次 逗号→句号→问号→叹号→回到逗号。
  /// 注意：绝不经 Rime 键路径发送 ,/.（避免 key_binder paging_with_comma_period 在组字态把 ,/. 当翻页键）。
  public static let punctCycle = "iosNative.punctCycle"
  /// 「选拼音」占位键：由 IOSNativeKeyboardView 视图层自行处理，handler 不响应。
  public static let noop = "iosNative.noop"
}

// 简繁切换：官方 iOS 键盘没有「键盘内简繁键」（简体/繁体是两个独立键盘），因此本布局不添加该键；
// 设置入口由 A4 决定。Rime 侧 API 已存在并保持不动：
// RimeContext.switchTraditionalSimplifiedChinese / syncTraditionalSimplifiedChineseMode（traditionalization option）。

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
    case .alphabetic(.uppercased), .alphabetic(.capsLocked), .chinese(.uppercased), .chinese(.capsLocked): return .enUpper
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
  private static var W: CGFloat { IOSNativeDesign.width }

  /// 面板纵向几何（rowH/gapV 按 P 图区分 9键族/紧凑族），行 Y 由 grid 计算
  private struct IOSNativeGrid {
    let rowH: CGFloat
    let gapV: CGFloat
    func rowY(_ index: Int) -> CGFloat {
      IOSNativeDesign.paddingV + CGFloat(index) * (rowH + gapV)
    }
  }

  private static func grid(for panel: IOSNativePanel) -> IOSNativeGrid {
    IOSNativeGrid(rowH: IOSNativeDesign.rowH(for: panel), gapV: IOSNativeDesign.gapV(for: panel))
  }

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

  /// return 键文案/配色：按宿主 returnKeyType 动态
  /// - chat(send) 保持面板规则（P 图：01/02/04/05 灰，03/06-09 蓝）
  /// - 搜索/前往/继续 强制蓝；完成/换行 强制灰
  private static func returnKeyLabel(context: KeyboardContext, isEnglish: Bool) -> (text: String, isSend: Bool, tint: IOSNativeTint?) {
    switch context.textDocumentProxy.returnKeyType {
    case .search, .google, .yahoo:
      return isEnglish ? ("Search", true, .blue) : ("搜索", true, .blue)
    case .go, .route:
      return isEnglish ? ("Go", true, .blue) : ("前往", true, .blue)
    case .send, .join:
      return isEnglish ? ("Send", true, nil) : ("发送", true, nil)
    case .continue:
      return isEnglish ? ("Continue", true, .blue) : ("继续", true, .blue)
    case .done:
      return isEnglish ? ("Done", false, .gray) : ("完成", false, .gray)
    case .next:
      return isEnglish ? ("Next", false, .gray) : ("下一项", false, .gray)
    case .emergencyCall:
      return ("紧急", false, .gray)
    default:
      return isEnglish ? ("return", false, .gray) : ("换行", false, .gray)
    }
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
    IOSNativeKey(action: k.action, displayText: k.displayText, rect: rect(x, y, w, h), isSend: k.isSend, isInputAction: k.isInputAction, tintOverride: k.tintOverride)
  }

  private static func shiftAction(context: KeyboardContext) -> KeyboardAction {
    // 使用 .shift 动作：单击切大小写、双击（StandardKeyboardBehavior）锁定大写
    let t = context.keyboardType
    switch t {
    case .chinese(let state): return .shift(currentCasing: state)
    case .alphabetic(let state): return .shift(currentCasing: state)
    default: return .shift(currentCasing: .lowercased)
    }
  }

  // MARK: - p1 Pinyin 9-key

  private static func pinyin9Keys(context: KeyboardContext) -> [IOSNativeKey] {
    let g = grid(for: .pinyin9)
    let returnKey = returnKeyLabel(context: context, isEnglish: false)
    let unit = fiveUnit()
    var result: [IOSNativeKey] = []
    func row(_ items: [(String, String)], _ y: CGFloat, _ make: (String) -> IOSNativeKey) {
      for (i, item) in items.enumerated() {
        let k = key(make(item.0), p + CGFloat(i) * (unit + gh), y, unit, g.rowH)
        result.append(IOSNativeKey(action: k.action, displayText: item.1, rect: k.rect, isSend: false, isInputAction: k.isInputAction))
      }
    }
    row([("123", "123"), ("，。？！", "，。？！"), ("ABC", "ABC"), ("DEF", "DEF")], g.rowY(0)) {
      switch $0 {
      case "123": return IOSNativeKey(action: .keyboardType(.numericNineGrid), displayText: nil, rect: .zero)
      case "，。？！": return IOSNativeKey(action: .custom(named: IOSNativeCustomAction.punctCycle), displayText: nil, rect: .zero)
      default: return nineKey($0)
      }
    }
    result.append(key(IOSNativeKey(action: .backspace, displayText: "⌫", rect: .zero), p + 4 * (unit + gh), g.rowY(0), unit, g.rowH))
    row([("#+=", "#+="), ("GHI", "GHI"), ("JKL", "JKL"), ("MNO", "MNO"), ("^_^", "^_^")], g.rowY(1)) {
      switch $0 {
      case "#+=": return IOSNativeKey(action: .keyboardType(.classifySymbolic), displayText: nil, rect: .zero)
      case "^_^": return IOSNativeKey(action: .character("^_^"), displayText: nil, rect: .zero)
      default: return nineKey($0)
      }
    }
    row([("ABC2", "ABC"), ("PQRS", "PQRS"), ("TUV", "TUV"), ("WXYZ", "WXYZ")], g.rowY(2)) {
      switch $0 {
      case "ABC2": return IOSNativeKey(action: .keyboardType(.chinese(.lowercased)), displayText: nil, rect: .zero)
      default: return nineKey($0)
      }
    }
    // Row-2 col-5: send, spanning rows 2-3.
    result.append(key(IOSNativeKey(action: .primary(.return), displayText: returnKey.text, rect: .zero, isSend: returnKey.isSend, tintOverride: returnKey.tint), p + 4 * (unit + gh), g.rowY(2), unit, 2 * g.rowH + g.gapV))
    // Row 3: emoji | select-pinyin | space (2 columns).
    result.append(key(IOSNativeKey(action: .keyboardType(.emojis), displayText: "😀", rect: .zero), p, g.rowY(3), unit, g.rowH))
    result.append(key(IOSNativeKey(action: .custom(named: IOSNativeCustomAction.noop), displayText: "选拼音", rect: .zero), p + unit + gh, g.rowY(3), unit, g.rowH))
    result.append(key(IOSNativeKey(action: .space, displayText: "空格", rect: .zero), p + 2 * unit + 2 * gh, g.rowY(3), 2 * unit + gh, g.rowH))
    return result
  }

  // MARK: - p2 Number 9-key

  private static func numberKeys(context: KeyboardContext) -> [IOSNativeKey] {
    let g = grid(for: .number)
    let returnKey = returnKeyLabel(context: context, isEnglish: false)
    let unit = fiveUnit()
    var result: [IOSNativeKey] = []
    func row(_ items: [(String, String)], _ y: CGFloat, _ make: (String) -> IOSNativeKey) {
      for (i, item) in items.enumerated() {
        let k = key(make(item.0), p + CGFloat(i) * (unit + gh), y, unit, g.rowH)
        result.append(IOSNativeKey(action: k.action, displayText: item.1, rect: k.rect, isSend: false, isInputAction: k.isInputAction))
      }
    }
    row([("拼音", "拼音"), ("1", "1"), ("2", "2"), ("3", "3")], g.rowY(0)) {
      switch $0 {
      case "拼音": return IOSNativeKey(action: .keyboardType(.chineseNineGrid), displayText: nil, rect: .zero)
      default: return charKey($0)
      }
    }
    result.append(key(IOSNativeKey(action: .backspace, displayText: "⌫", rect: .zero), p + 4 * (unit + gh), g.rowY(0), unit, g.rowH))
    row([("#+=", "#+="), ("4", "4"), ("5", "5"), ("6", "6")], g.rowY(1)) {
      switch $0 {
      case "#+=": return IOSNativeKey(action: .keyboardType(.classifySymbolic), displayText: nil, rect: .zero)
      default: return charKey($0)
      }
    }
    result.append(key(IOSNativeKey(action: .keyboardType(.chineseNumeric), displayText: "更多", rect: .zero), p + 4 * (unit + gh), g.rowY(1), unit, g.rowH))
    row([("ABC", "ABC"), ("7", "7"), ("8", "8"), ("9", "9")], g.rowY(2)) {
      switch $0 {
      case "ABC": return IOSNativeKey(action: .keyboardType(.chinese(.lowercased)), displayText: nil, rect: .zero)
      default: return charKey($0)
      }
    }
    result.append(key(IOSNativeKey(action: .primary(.return), displayText: returnKey.text, rect: .zero, isSend: returnKey.isSend, tintOverride: returnKey.tint), p + 4 * (unit + gh), g.rowY(2), unit, 2 * g.rowH + g.gapV))
    result.append(key(IOSNativeKey(action: .keyboardType(.emojis), displayText: "😀", rect: .zero), p, g.rowY(3), unit, g.rowH))
    result.append(key(IOSNativeKey(action: .character("."), displayText: ". , :", rect: .zero), p + unit + gh, g.rowY(3), unit, g.rowH))
    result.append(key(IOSNativeKey(action: .character("0"), displayText: "0", rect: .zero), p + 2 * unit + 2 * gh, g.rowY(3), unit, g.rowH))
    result.append(key(IOSNativeKey(action: .space, displayText: "空格", rect: .zero), p + 3 * unit + 3 * gh, g.rowY(3), unit, g.rowH))
    return result
  }

  // MARK: - p3 Number more

  private static func numberMoreKeys(context: KeyboardContext) -> [IOSNativeKey] {
    let g = grid(for: .numberMore)
    let returnKey = returnKeyLabel(context: context, isEnglish: false)
    let unit = fiveUnit()
    var result: [IOSNativeKey] = []
    func row(_ items: [(String, String)], _ y: CGFloat, _ make: (String) -> IOSNativeKey) {
      for (i, item) in items.enumerated() {
        let k = key(make(item.0), p + CGFloat(i) * (unit + gh), y, unit, g.rowH)
        result.append(IOSNativeKey(action: k.action, displayText: item.1, rect: k.rect, isSend: false, isInputAction: k.isInputAction))
      }
    }
    row([("拼音", "拼音"), ("¥", "¥"), ("℃", "℃"), ("%", "%")], g.rowY(0)) {
      switch $0 {
      case "拼音": return IOSNativeKey(action: .keyboardType(.chineseNineGrid), displayText: nil, rect: .zero)
      default: return charKey($0)
      }
    }
    result.append(key(IOSNativeKey(action: .backspace, displayText: "⌫", rect: .zero), p + 4 * (unit + gh), g.rowY(0), unit, g.rowH))
    row([("#+=", "#+="), (",", ","), ("+", "+"), ("-", "-")], g.rowY(1)) {
      switch $0 {
      case "#+=": return IOSNativeKey(action: .keyboardType(.classifySymbolic), displayText: nil, rect: .zero)
      default: return charKey($0)
      }
    }
    result.append(key(IOSNativeKey(action: .keyboardType(.numericNineGrid), displayText: "更多", rect: .zero), p + 4 * (unit + gh), g.rowY(1), unit, g.rowH))
    row([("ABC", "ABC"), (":", ":"), ("/", "/"), ("=", "=")], g.rowY(2)) {
      switch $0 {
      case "ABC": return IOSNativeKey(action: .keyboardType(.chinese(.lowercased)), displayText: nil, rect: .zero)
      default: return charKey($0)
      }
    }
    result.append(key(IOSNativeKey(action: .primary(.return), displayText: returnKey.text, rect: .zero, isSend: returnKey.isSend, tintOverride: returnKey.tint), p + 4 * (unit + gh), g.rowY(2), unit, 2 * g.rowH + g.gapV))
    result.append(key(IOSNativeKey(action: .keyboardType(.emojis), displayText: "😀", rect: .zero), p, g.rowY(3), unit, g.rowH))
    result.append(key(IOSNativeKey(action: .character("."), displayText: ".", rect: .zero), p + unit + gh, g.rowY(3), unit, g.rowH))
    result.append(key(IOSNativeKey(action: .character("_"), displayText: "_", rect: .zero), p + 2 * unit + 2 * gh, g.rowY(3), unit, g.rowH))
    result.append(key(IOSNativeKey(action: .space, displayText: "空格", rect: .zero), p + 3 * unit + 3 * gh, g.rowY(3), unit, g.rowH))
    return result
  }

  // MARK: - p4/p5 Chinese symbols (10 columns)

  private static func cnSymbolKeys(context: KeyboardContext, page: Int) -> [IOSNativeKey] {
    let g = grid(for: .cnSymbol1)
    let returnKey = returnKeyLabel(context: context, isEnglish: false)
    let unit = tenUnit()
    var result: [IOSNativeKey] = []
    func addRow10(_ items: [String], _ y: CGFloat) {
      for (i, ch) in items.enumerated() {
        result.append(key(charKey(ch), p + CGFloat(i) * (unit + gh), y, unit, g.rowH))
      }
    }
    if page == 1 {
      addRow10(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"], g.rowY(0))
      addRow10(["-", "/", ":", ";", "(", ")", "¥", "@", "“", "”"], g.rowY(1))
    } else {
      addRow10(["【", "】", "{", "}", "#", "%", "^", "*", "+", "="], g.rowY(0))
      addRow10(["_", "—", "\\", "|", "~", "《", "》", "$", "&", "."], g.rowY(1))
    }
    // Row 3: #+=/123 (43.3) | 6 symbols (39.5, centered) | backspace (43.3).
    let y3 = g.rowY(2)
    let switchKey = page == 1 ? "#+=" : "123"
    let switchAction: KeyboardAction = page == 1 ? .keyboardType(.chineseSymbolic) : .keyboardType(.classifySymbolic)
    result.append(key(IOSNativeKey(action: switchAction, displayText: switchKey, rect: .zero), p, y3, enFuncW, g.rowH))
    let symStart = W / 2 - (6 * cnSymUnit + 5 * gh) / 2
    let syms = page == 1 ? ["。", ",", "、", "？", "！", "."] : ["…", ",", "^_^", "？", "！", "’"]
    for (i, ch) in syms.enumerated() {
      result.append(key(charKey(ch), symStart + CGFloat(i) * (cnSymUnit + gh), y3, cnSymUnit, g.rowH))
    }
    result.append(key(IOSNativeKey(action: .backspace, displayText: "⌫", rect: .zero), W - p - enFuncW, y3, enFuncW, g.rowH))
    // Row 4: pinyin (88) | space | send (88).
    let y4 = g.rowY(3)
    result.append(key(IOSNativeKey(action: .keyboardType(.chineseNineGrid), displayText: "拼音", rect: .zero), p, y4, cnBottomFuncW, g.rowH))
    let spaceX = p + cnBottomFuncW + gh
    let spaceW = W - 2 * p - 2 * cnBottomFuncW - 2 * gh
    result.append(key(IOSNativeKey(action: .space, displayText: "空格", rect: .zero), spaceX, y4, spaceW, g.rowH))
    result.append(key(IOSNativeKey(action: .primary(.return), displayText: returnKey.text, rect: .zero, isSend: returnKey.isSend, tintOverride: returnKey.tint), spaceX + spaceW + gh, y4, cnBottomFuncW, g.rowH))
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
    let g = grid(for: .enUpper)
    let unitW = tenUnit()
    let returnKey = returnKeyLabel(context: context, isEnglish: true)
    var result: [IOSNativeKey] = []
    let letters = uppercase ? "QWERTYUIOPASDFGHJKLZXCVBNM" : "qwertyuiopasdfghjklzxcvbnm"
    let r0 = Array(letters.prefix(10)).map(String.init)
    let r1 = Array(letters.dropFirst(10).prefix(9)).map(String.init)
    let r2 = Array(letters.dropFirst(19)).map(String.init)
    func push(_ chars: [String], _ offsetX: CGFloat, _ y: CGFloat, _ w: CGFloat = unitW) {
      for (i, ch) in chars.enumerated() {
        result.append(key(charKey(ch), offsetX + CGFloat(i) * (w + gh), y, w, g.rowH))
      }
    }
    push(r0, p, g.rowY(0))
    push(r1, p + (unitW + gh) / 2, g.rowY(1))
    // Row 3
    let y2 = g.rowY(2)
    let y4 = g.rowY(3)
    let shiftAction = shiftAction(context: context)
    switch context.inputEnvironment {
    case .url:
      // 网址键盘：Shift(38) | 7字母 + / + .com 等宽 | 退格(38)；底部 123 | 空格 | 前往
      let urlFuncW: CGFloat = 38
      let blockW = W - 2 * p - 2 * urlFuncW - 2 * gh
      let urlUnit = (blockW - 8 * gh) / 9
      result.append(key(IOSNativeKey(action: shiftAction, displayText: "\u{2B06}", rect: .zero), p, y2, urlFuncW, g.rowH))
      push(r2, p + urlFuncW + gh, y2, urlUnit)
      result.append(key(IOSNativeKey(action: .character("/"), displayText: "/", rect: .zero), p + urlFuncW + gh + 7 * (urlUnit + gh), y2, urlUnit, g.rowH))
      result.append(key(IOSNativeKey(action: .character(".com"), displayText: ".com", rect: .zero), p + urlFuncW + gh + 8 * (urlUnit + gh), y2, urlUnit, g.rowH))
      result.append(key(IOSNativeKey(action: .backspace, displayText: "\u{232B}", rect: .zero), W - p - urlFuncW, y2, urlFuncW, g.rowH))
      let retW: CGFloat = enBottomFuncW
      result.append(key(IOSNativeKey(action: .keyboardType(.numeric), displayText: "123", rect: .zero), p, y4, enBottomFuncW, g.rowH))
      let retX = W - p - retW
      let spaceW = retX - gh - (p + enBottomFuncW + gh)
      result.append(key(IOSNativeKey(action: .space, displayText: "space", rect: .zero), p + enBottomFuncW + gh, y4, spaceW, g.rowH))
      result.append(key(IOSNativeKey(action: .primary(.return), displayText: returnKey.text, rect: .zero, isSend: returnKey.isSend, tintOverride: returnKey.tint), retX, y4, retW, g.rowH))
    case .email:
      // 邮箱键盘：底部 123 | @ | 空格 | return
      let blockX = enLetterBlockX()
      result.append(key(IOSNativeKey(action: shiftAction, displayText: "\u{2B06}", rect: .zero), p, y2, enFuncW, g.rowH))
      push(r2, blockX, y2)
      result.append(key(IOSNativeKey(action: .backspace, displayText: "\u{232B}", rect: .zero), W - p - enFuncW, y2, enFuncW, g.rowH))
      result.append(key(IOSNativeKey(action: .keyboardType(.numeric), displayText: "123", rect: .zero), p, y4, enBottomFuncW, g.rowH))
      let atX = p + enBottomFuncW + gh
      result.append(key(IOSNativeKey(action: .character("@"), displayText: "@", rect: .zero), atX, y4, enBottomFuncW, g.rowH))
      let retX = W - p - enBottomFuncW
      let spaceW = retX - gh - (atX + enBottomFuncW + gh)
      result.append(key(IOSNativeKey(action: .space, displayText: "space", rect: .zero), atX + enBottomFuncW + gh, y4, spaceW, g.rowH))
      result.append(key(IOSNativeKey(action: .primary(.return), displayText: returnKey.text, rect: .zero, isSend: returnKey.isSend, tintOverride: returnKey.tint), retX, y4, enBottomFuncW, g.rowH))
    default:
      // 标准/搜索：123 | 😀 | 空格 | return
      let blockX = enLetterBlockX()
      result.append(key(IOSNativeKey(action: shiftAction, displayText: "\u{2B06}", rect: .zero), p, y2, enFuncW, g.rowH))
      push(r2, blockX, y2)
      result.append(key(IOSNativeKey(action: .backspace, displayText: "\u{232B}", rect: .zero), W - p - enFuncW, y2, enFuncW, g.rowH))
      let nRight = blockX + 5 * (unitW + gh) + unitW
      let mLeft = blockX + 6 * (unitW + gh)
      let emojiX = p + enBottomFuncW + gh
      result.append(key(IOSNativeKey(action: .keyboardType(.numeric), displayText: "123", rect: .zero), p, y4, enBottomFuncW, g.rowH))
      result.append(key(IOSNativeKey(action: .keyboardType(.emojis), displayText: "\u{1F600}", rect: .zero), emojiX, y4, enBottomFuncW, g.rowH))
      let spaceX = emojiX + enBottomFuncW + gh
      result.append(key(IOSNativeKey(action: .space, displayText: "space", rect: .zero), spaceX, y4, nRight - spaceX, g.rowH))
      result.append(key(IOSNativeKey(action: .primary(.return), displayText: returnKey.text, rect: .zero, isSend: returnKey.isSend, tintOverride: returnKey.tint), mLeft, y4, W - p - mLeft, g.rowH))
    }
    IOSNativeState.lastQWERTYType = context.keyboardType
    return result
  }

  // MARK: - p8/p9 English number/symbol (10 columns)

  private static func enNumberSymbolKeys(context: KeyboardContext, page: Int) -> [IOSNativeKey] {
    let g = grid(for: .enNumber)
    let returnKey = returnKeyLabel(context: context, isEnglish: true)
    let unit = tenUnit()
    var result: [IOSNativeKey] = []
    func addRow10(_ items: [String], _ y: CGFloat) {
      for (i, ch) in items.enumerated() {
        result.append(key(charKey(ch), p + CGFloat(i) * (unit + gh), y, unit, g.rowH))
      }
    }
    if page == 1 {
      addRow10(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"], g.rowY(0))
      addRow10(["-", "/", ":", ";", "(", ")", "$", "&", "@", "”"], g.rowY(1))
    } else {
      addRow10(["[", "]", "{", "}", "#", "%", "^", "*", "+", "="], g.rowY(0))
      addRow10(["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "."], g.rowY(1))
    }
    // Row 3: #+=/123 (43.3) | 5 symbols (Z-left to M-right) | backspace (43.3).
    let y3 = g.rowY(2)
    let blockX = enLetterBlockX()
    let zLeft = blockX
    let mRight = blockX + 6 * (unit + gh) + unit
    let symW = (mRight - zLeft - 4 * gh) / 5
    let switchKey = page == 1 ? "#+=" : "123"
    let switchAction: KeyboardAction = page == 1 ? .keyboardType(.symbolic) : .keyboardType(.numeric)
    result.append(key(IOSNativeKey(action: switchAction, displayText: switchKey, rect: .zero), p, y3, enFuncW, g.rowH))
    let syms = page == 1 ? [".", ",", "?", "!", "’"] : [".", ",", "?", "!", "'"]
    for (i, ch) in syms.enumerated() {
      result.append(key(charKey(ch), zLeft + CGFloat(i) * (symW + gh), y3, symW, g.rowH))
    }
    result.append(key(IOSNativeKey(action: .backspace, displayText: "⌫", rect: .zero), W - p - enFuncW, y3, enFuncW, g.rowH))
    // Row 4: ABC | emoji | space | send (same geometry as English 26-key).
    let y4 = g.rowY(3)
    let nRight = blockX + 5 * (unit + gh) + unit
    let mLeft = blockX + 6 * (unit + gh)
    let emojiX = p + enBottomFuncW + gh
    result.append(key(IOSNativeKey(action: .keyboardType(IOSNativeState.lastQWERTYType), displayText: "ABC", rect: .zero), p, y4, enBottomFuncW, g.rowH))
    result.append(key(IOSNativeKey(action: .keyboardType(.emojis), displayText: "😀", rect: .zero), emojiX, y4, enBottomFuncW, g.rowH))
    let spaceX = emojiX + enBottomFuncW + gh
    result.append(key(IOSNativeKey(action: .space, displayText: "space", rect: .zero), spaceX, y4, nRight - spaceX, g.rowH))
    result.append(key(IOSNativeKey(action: .primary(.return), displayText: returnKey.text, rect: .zero, isSend: returnKey.isSend, tintOverride: returnKey.tint), mLeft, y4, W - p - mLeft, g.rowH))
    return result
  }

  private static func enNumberKeys(context: KeyboardContext) -> [IOSNativeKey] {
    enNumberSymbolKeys(context: context, page: 1)
  }

  private static func enSymbolKeys(context: KeyboardContext) -> [IOSNativeKey] {
    enNumberSymbolKeys(context: context, page: 2)
  }
}



