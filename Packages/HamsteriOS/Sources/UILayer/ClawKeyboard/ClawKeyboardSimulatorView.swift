//
//  ClawKeyboardSimulatorView.swift
//
//  ClawTalk 多 Tab 上层业务面板 + 模拟键盘（SwiftUI，App 页面内部运行）
//
//  状态定义：
//    状态A：showTopPanel=false，仅显示键盘 + 顶部 Tab 标签
//    状态B：showTopPanel=true，展开业务面板，键盘右侧按钮切换为 删除/重输/换行
//  tabIndex：0=AI语音助手  1=帮你回  2=超会说
//
//  交互规则：
//    - 点击任意 Tab → showTopPanel=true，展开业务面板并切换 tabIndex
//    - 点击面板右上角 X → showTopPanel=false，收起面板回到状态A
//    - 面板展开/收起使用 withAnimation 平滑过渡
//

import SwiftUI
import UIKit

// MARK: - 页面配色（ClawTalk 红黑白主题 + 业务蓝）

private enum SimPanelPalette {
  static func adaptive(light: UIColor, dark: UIColor) -> Color {
    Color(uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark ? dark : light
    })
  }

  /// 页面背景：ClawTalk void
  static let pageBackground = adaptive(
    light: UIColor(red: 246 / 255, green: 247 / 255, blue: 249 / 255, alpha: 1), // #F6F7F9
    dark: UIColor(red: 11 / 255, green: 12 / 255, blue: 17 / 255, alpha: 1)      // #0B0C11
  )

  /// 面板卡片：ClawTalk obsidian
  static let cardBackground = adaptive(
    light: UIColor.white,                                                        // #FFFFFF
    dark: UIColor(red: 19 / 255, green: 21 / 255, blue: 28 / 255, alpha: 1)      // #13151C
  )

  /// 输入框底色
  static let inputBackground = adaptive(
    light: UIColor(red: 244 / 255, green: 245 / 255, blue: 247 / 255, alpha: 1), // #F4F5F7
    dark: UIColor(red: 28 / 255, green: 28 / 255, blue: 32 / 255, alpha: 1)      // #1C1C20
  )

  /// 关闭按钮底色
  static let closeBackground = adaptive(
    light: UIColor(red: 240 / 255, green: 240 / 255, blue: 242 / 255, alpha: 1),
    dark: UIColor(red: 40 / 255, green: 40 / 255, blue: 44 / 255, alpha: 1)
  )

  /// 波形占位底色
  static let waveBackground = adaptive(
    light: UIColor(red: 243 / 255, green: 247 / 255, blue: 255 / 255, alpha: 1), // #F3F7FF
    dark: UIColor(red: 22 / 255, green: 28 / 255, blue: 40 / 255, alpha: 1)      // #161C28
  )

  /// 业务蓝（参考图：发送 / 读懂TA / 波形 / 选中圈）
  static let blue = Color(red: 48 / 255, green: 120 / 255, blue: 246 / 255)      // #3078F6

  /// Tab 未选中文字
  static let tabNormalLabel = adaptive(
    light: UIColor(red: 110 / 255, green: 110 / 255, blue: 115 / 255, alpha: 1),
    dark: UIColor(red: 160 / 255, green: 160 / 255, blue: 165 / 255, alpha: 1)
  )

  /// AI 圆圈未选中底
  static let circleBackground = adaptive(
    light: UIColor(red: 232 / 255, green: 232 / 255, blue: 235 / 255, alpha: 1),
    dark: UIColor(red: 44 / 255, green: 44 / 255, blue: 48 / 255, alpha: 1)
  )

  /// 面板底部小字（心动对象 ⇄）
  static let caption = Color.secondary
}

// MARK: - 多 Tab 上层业务面板 + 模拟键盘主页面

struct ClawKeyboardSimulatorView: View {
  // MARK: 状态（任务规定的三个 @State 变量）
  @State private var showTopPanel: Bool = false
  @State private var tabIndex: Int = 0
  @State private var mainInput: String = ""

  var body: some View {
    VStack(spacing: 0) {
      // MARK: 顶部 Tab 栏（固定显示：AI / 帮你回 / 超会说）
      SimTabBarView(tabIndex: $tabIndex, isExpanded: showTopPanel) { index in
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
          showTopPanel = true
          tabIndex = index
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)

      // MARK: 上层业务面板（showTopPanel=true 时展开）
      if showTopPanel {
        BusinessPanelView(tabIndex: tabIndex, text: $mainInput) {
          withAnimation(.easeInOut(duration: 0.25)) {
            showTopPanel = false
          }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
      }

      // MARK: 模拟键盘（复用 CustomKeyboardView，右侧按钮随状态切换）
      CustomKeyboardView(showTopPanel: $showTopPanel, text: $mainInput)

      Spacer(minLength: 0)
    }
    .background(SimPanelPalette.pageBackground)
  }
}

// MARK: - 顶部 Tab 栏

private struct SimTabBarView: View {
  @Binding var tabIndex: Int
  let isExpanded: Bool
  let onSelect: (Int) -> Void

  var body: some View {
    HStack(spacing: 18) {
      // AI 标签（外圈圆圈，选中高亮蓝色）
      Button {
        onSelect(0)
      } label: {
        Text("AI")
          .font(.system(size: 14, weight: .bold))
          .foregroundColor(isSelected(0) ? Color.white : SimPanelPalette.tabNormalLabel)
          .frame(width: 34, height: 34)
          .background(
            Circle().fill(isSelected(0) ? SimPanelPalette.blue : SimPanelPalette.circleBackground)
          )
      }
      .buttonStyle(.plain)

      // 帮你回 / 超会说 文字标签
      tabLabel(index: 1, title: "帮你回")
      tabLabel(index: 2, title: "超会说")

      Spacer(minLength: 0)
    }
  }

  private func isSelected(_ index: Int) -> Bool {
    isExpanded && tabIndex == index
  }

  private func tabLabel(index: Int, title: String) -> some View {
    Button {
      onSelect(index)
    } label: {
      Text(title)
        .font(.system(size: 16, weight: isSelected(index) ? .semibold : .regular))
        .foregroundColor(isSelected(index) ? SimPanelPalette.blue : SimPanelPalette.tabNormalLabel)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - 上层业务面板

private struct BusinessPanelView: View {
  let tabIndex: Int
  @Binding var text: String
  let onClose: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      // 标题栏
      HStack {
        Text(title)
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(.primary)
        Spacer()
        // X 关闭按钮：收起面板回到状态A
        Button(action: onClose) {
          Image(systemName: "xmark")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.primary)
            .frame(width: 26, height: 26)
            .background(Circle().fill(SimPanelPalette.closeBackground))
        }
        .buttonStyle(.plain)
      }

      // Tab 内容
      content

      // 底部小字
      Text("心动对象 ⇄")
        .font(.system(size: 13))
        .foregroundColor(SimPanelPalette.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(16)
    .background(SimPanelPalette.cardBackground)
    .cornerRadius(20)
    .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
  }

  private var title: String {
    switch tabIndex {
    case 0: return "AI语音助手"
    case 1: return "帮你回"
    default: return "超会说"
    }
  }

  @ViewBuilder
  private var content: some View {
    switch tabIndex {
    case 0: aiContent
    case 1: helpReplyContent
    default: superTalkContent
    }
  }

  // MARK: tabIndex=0 —— AI语音助手
  private var aiContent: some View {
    WaveformPlaceholderView()
      .frame(height: 64)
      .frame(maxWidth: .infinity)
      .background(SimPanelPalette.waveBackground)
      .cornerRadius(14)
  }

  // MARK: tabIndex=1 —— 帮你回
  private var helpReplyContent: some View {
    HStack(spacing: 10) {
      TextField("+粘贴TA的话", text: $text)
        .font(.system(size: 15))
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(SimPanelPalette.inputBackground)
        .cornerRadius(10)
      Button(action: {}) {
        Text("读懂TA")
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.white)
          .padding(.horizontal, 16)
          .frame(height: 42)
          .background(SimPanelPalette.blue)
          .cornerRadius(10)
      }
      .buttonStyle(.plain)
    }
  }

  // MARK: tabIndex=2 —— 超会说
  private var superTalkContent: some View {
    HStack(spacing: 10) {
      TextField("输入你想说的话，我们帮你优化", text: $text)
        .font(.system(size: 15))
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(SimPanelPalette.inputBackground)
        .cornerRadius(10)
      Button(action: {}) {
        Text("优化")
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.white)
          .padding(.horizontal, 16)
          .frame(height: 42)
          .background(SimPanelPalette.blue)
          .cornerRadius(10)
      }
      .buttonStyle(.plain)
    }
  }
}

// MARK: - 蓝色音频波形占位视图
// 注：此处先用占位动画模拟波形，后续在此接入真实音频波形动画（如录音数据驱动）

private struct WaveformPlaceholderView: View {
  private let bars: [CGFloat] = [0.3, 0.55, 0.85, 0.5, 0.7, 0.35, 0.9, 0.45]

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
      let phase = timeline.date.timeIntervalSinceReferenceDate
      HStack(spacing: 5) {
        ForEach(0..<bars.count, id: \.self) { index in
          Capsule()
            .fill(SimPanelPalette.blue)
            .frame(width: 5, height: CGFloat(14 + 30 * abs(sin(phase * 2.2 + Double(index) * 0.8))))
        }
      }
    }
    .frame(height: 60)
  }
}
