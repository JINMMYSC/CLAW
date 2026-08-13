import UIKit

/// ClawTalk 键盘/面板配色（参考图逐像素采样）
public enum ClawPanelPalette {
  /// 键盘背景 #B7BCC7
  public static let keyboardBackground = UIColor(red: 183 / 255, green: 188 / 255, blue: 199 / 255, alpha: 1)
  /// 白色按键 #FCFCFC
  public static let keyWhite = UIColor(red: 252 / 255, green: 252 / 255, blue: 252 / 255, alpha: 1)
  /// 九键字母文字 #8D909A
  public static let keyLabel = UIColor(red: 141 / 255, green: 144 / 255, blue: 154 / 255, alpha: 1)
  /// 主蓝 #5E75FA（读懂TA / 优化 / 发送 / 选中态）
  public static let brandBlue = UIColor(red: 94 / 255, green: 117 / 255, blue: 250 / 255, alpha: 1)
  /// AI 圆未选中底 #D5DCFE
  public static let aiCircle = UIColor(red: 213 / 255, green: 220 / 255, blue: 254 / 255, alpha: 1)
  /// 胶囊选中底 #DBE2FE
  public static let capsuleSelected = UIColor(red: 219 / 255, green: 226 / 255, blue: 254 / 255, alpha: 1)
  /// 胶囊未选中底 #F0F0FC
  public static let capsuleNormal = UIColor(red: 240 / 255, green: 240 / 255, blue: 252 / 255, alpha: 1)
  /// 右侧装饰块 #DCE0FE
  public static let decoBlock = UIColor(red: 220 / 255, green: 224 / 255, blue: 254 / 255, alpha: 1)
  /// 面板底 #EFF0FA
  public static let panelBackground = UIColor(red: 239 / 255, green: 240 / 255, blue: 250 / 255, alpha: 1)
  /// 输入框底 #F6F7FF
  public static let inputBackground = UIColor(red: 246 / 255, green: 247 / 255, blue: 255 / 255, alpha: 1)
  /// 输入框占位文字 #C8D0FD
  public static let inputPlaceholder = UIColor(red: 200 / 255, green: 208 / 255, blue: 253 / 255, alpha: 1)
  /// 标题蓝 #6D76FB
  public static let titleBlue = UIColor(red: 109 / 255, green: 118 / 255, blue: 251 / 255, alpha: 1)
  /// 深蓝图标 #1933C6
  public static let deepBlue = UIColor(red: 25 / 255, green: 51 / 255, blue: 198 / 255, alpha: 1)
  /// 工具栏/功能行背景（参考图 Tab 栏区域采样 #F7FAFF）
  public static let toolbarBackground = UIColor(red: 247 / 255, green: 250 / 255, blue: 255 / 255, alpha: 1)
  /// 发送禁用灰（同键盘底 #B7BCC7）
  public static let sendDisabled = UIColor(red: 183 / 255, green: 188 / 255, blue: 199 / 255, alpha: 1)
  /// 符号键灰底 #AAB0BA（明哥确认）
  public static let symbolKeyGray = UIColor(red: 170 / 255, green: 176 / 255, blue: 186 / 255, alpha: 1)
  /// 候选栏文字
  public static let candidateText = UIColor(red: 17 / 255, green: 17 / 255, blue: 20 / 255, alpha: 1)
  /// 遮罩半透明
  public static let overlayMask = UIColor.black.withAlphaComponent(0.25)
}