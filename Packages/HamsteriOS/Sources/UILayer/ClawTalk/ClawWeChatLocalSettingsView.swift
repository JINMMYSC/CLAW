import HamsterKit
import SwiftUI

/// User-facing readiness screen for the optional on-device WeChat bridge.
/// It must never display "online" unless a real, authorized provider transport
/// has started and is servicing incoming messages. The initial state is a
/// deliberately honest, disconnected feature gate.
struct ClawWeChatLocalSettingsView: View {
  @State private var state: ClawWeChatLocalConnectionState = .disconnected

  private var stateTitle: String {
    switch state {
    case .disconnected: return "尚未连接"
    case .awaitingAuthorization: return "等待微信授权"
    case .authorizedPaused: return "已授权 · 本机暂停"
    case .active: return "本机正在处理消息"
    case .recovering: return "正在尝试恢复"
    case .expired: return "授权已过期"
    case .failed: return "连接异常"
    }
  }

  private var stateSymbol: String {
    state == .active ? "checkmark.circle.fill" : "pause.circle"
  }

  var body: some View {
    Form {
      Section {
        HStack(spacing: 10) {
          Image(systemName: stateSymbol)
            .font(.title2)
            .foregroundColor(state == .active ? .green : .secondary)
          VStack(alignment: .leading, spacing: 4) {
            Text(stateTitle).font(.headline)
            Text("微信 ClawBot · 本机按需模式")
              .font(.caption).foregroundColor(.secondary)
          }
        }
        .accessibilityElement(children: .combine)
        Text("目前仅已具备消息处理接口和测试骨架；扫码授权、腾讯实际收发及媒体转写尚未实现。")
          .font(.footnote).foregroundColor(.secondary)
      } header: {
        Text("连接状态")
      }

      Section("设计中的使用能力") {
        Label("文字：获取消息并生成 CLAW 回复", systemImage: "text.bubble")
        Label("图片：下载 → 校验 → OCR/视觉理解", systemImage: "photo")
        Label("语音：下载 → 解码 → 语音转文字", systemImage: "waveform")
        Label("人物记忆：选择授权范围后查询", systemImage: "person.crop.rectangle")
      }
      .foregroundColor(.secondary)

      Section {
        Text("仅使用 iPhone 的前台 CLAW 或正在显示且获“完全访问”的 CLAW 键盘时，才有机会执行本机连接器。")
        Text("切换到微信而键盘未显示时，即使屏幕仍然亮着，也不能保证 CLAW 在后台继续处理。")
        Text("微信里的 ClawBot 不等同于普通微信好友；不会自动读取您与其他好友的聊天记录。")
      } header: {
        Text("iOS 运行边界")
      }

      Section {
        Label("等待腾讯独立接入许可与实际可用性验证", systemImage: "exclamationmark.shield")
          .foregroundColor(.orange)
        Text("正式验证前不展示无效二维码，也不要求你提交个人微信登录凭证。")
          .font(.footnote).foregroundColor(.secondary)
      } header: {
        Text("授权与隐私")
      }
    }
    .navigationTitle("微信 AI 助手")
    .navigationBarTitleDisplayMode(.inline)
  }
}
