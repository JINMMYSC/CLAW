import Foundation

/// Only high-confidence software troubleshooting requests route to local
/// telemetry; ordinary conversation stays with the normal assistant.
public enum ClawDiagnosticIntent: Equatable {
  case none
  case overview
  case voice
  case sync
}

public enum ClawDiagnosticIntentRouter {
  public static func match(_ input: String) -> ClawDiagnosticIntent {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if text == "/自检" || text == "/diagnose" { return .overview }
    if text == "/查语音" { return .voice }
    if text == "/查同步" { return .sync }
    guard text.count < 160 else { return .none }

    let symptoms = ["失败", "故障", "出错", "异常", "不能用", "用不了",
                    "没反应", "无法", "不工作", "识别不了", "没声音", "为什么"]
    guard symptoms.contains(where: text.contains) else {
      if ["检查软件状态", "软件今天有没有问题", "检查运行状态", "软件自检"]
        .contains(where: text.contains) { return .overview }
      return .none
    }
    if ["icloud", "云备份", "云同步", "云端同步", "云端备份"]
      .contains(where: text.contains) {
      return .sync
    }
    if ["语音识别", "语音输入", "录音", "麦克风", "语音"].contains(where: text.contains) {
      return .voice
    }
    return .none
  }
}
