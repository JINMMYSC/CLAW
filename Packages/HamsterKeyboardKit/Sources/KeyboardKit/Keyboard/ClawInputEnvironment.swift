//
//  ClawInputEnvironment.swift
//
//  宿主输入框语义环境：决定键盘布局变体与 return 键文案/颜色
//

import Foundation

/// 输入环境（由 KeyboardInputViewController 根据 textDocumentProxy 推断）
public enum ClawInputEnvironment: Equatable {
  /// 普通文本/多行文本（默认，return = 换行）
  case general
  /// 邮箱输入（return = 完成，英文键盘带 @ 键）
  case email
  /// 网址输入（return = 前往，英文键盘带 / 与 .com 键）
  case url
  /// 搜索输入（return = 搜索）
  case search
  /// 聊天发送（return = 发送，按 P 图面板蓝/灰规则）
  case chat
  /// 完成/下一项/继续 等动作（return = 完成，灰底）
  case action
  /// 数字输入（切数字9键）
  case number
  /// 安全数字输入（secure 标记 + numberPad 键盘）：切数字9键（.numericNineGrid）
  /// 契约（A2）：KeyboardInputViewController.detectInputEnvironment 中须在 .password 判断之前
  /// 检测 `proxy.isSecureTextEntry == true && proxy.keyboardType?.isNumberType == true`，
  /// 命中即返回本 case，保证 PIN/验证码等安全数字输入框走数字九宫格而不是英文键盘。
  case secureNumberPad
  /// 密码输入（强制英文键盘）
  case password
}
