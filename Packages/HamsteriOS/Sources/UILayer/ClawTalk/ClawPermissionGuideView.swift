import SwiftUI

struct ClawPermissionGuideView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var index = 0
  @State private var requesting = false

  var body: some View {
    NavigationView {
      VStack(spacing: 20) {
        if index < ClawPermissionStep.allCases.count {
          let step = ClawPermissionStep.allCases[index]
          Image(systemName: icon(step)).font(.system(size: 44)).foregroundColor(.accentColor)
          Text(step.title).font(.title2.bold())
          Text(reason(step)).multilineTextAlignment(.center).foregroundColor(.secondary)
          Button(requesting ? "正在请求…" : "允许") { request(step) }
            .buttonStyle(.borderedProminent).disabled(requesting)
          Button("跳过") { advance() }.disabled(requesting)
          Text("\(index + 1) / \(ClawPermissionStep.allCases.count)").font(.caption).foregroundColor(.secondary)
        } else {
          Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundColor(.green)
          Text("权限设置完成").font(.title2.bold())
          Button("完成") { dismiss() }.buttonStyle(.borderedProminent)
        }
        Spacer()
      }
      .padding(28)
      .navigationTitle("CLAW 权限向导")
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
    }
  }

  private func request(_ step: ClawPermissionStep) {
    requesting = true
    ClawPermissionCoordinator.shared.request(step) { requesting = false; advance() }
  }
  private func advance() { index = min(index + 1, ClawPermissionStep.allCases.count) }
  private func icon(_ step: ClawPermissionStep) -> String {
    switch step { case .contacts: return "person.crop.circle"; case .calendars: return "calendar"; case .reminders: return "checklist"; case .location: return "location"; case .notifications: return "bell"; case .microphone: return "mic"; case .speech: return "waveform" }
  }
  private func reason(_ step: ClawPermissionStep) -> String {
    switch step {
    case .contacts: return "把记忆关联到正确的人。"
    case .calendars: return "在今日视图展示你授权的日程。"
    case .reminders: return "创建你确认过的提醒。"
    case .location: return "触发地点相关的提醒。"
    case .notifications: return "在合适时间提醒你。"
    case .microphone: return "只在你主动录音时采集声音。"
    case .speech: return "把主动录制的语音转换为文字。"
    }
  }
}
