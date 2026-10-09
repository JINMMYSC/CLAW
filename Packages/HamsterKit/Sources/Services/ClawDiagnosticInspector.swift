import Foundation

/// This report explicitly distinguishes observed events from unknown state.
/// It does not claim microphone permissions, keyboard liveness or cloud
/// availability unless a dedicated probe has actually supplied evidence.
public enum ClawDiagnosticInspector {
  public static func report(events: [ClawDiagnosticEvent] = ClawDiagnosticsCore.shared.recent()) -> String {
    let errors = events.filter { $0.severity == "error" }
    let voice = errors.filter { $0.module == "voice" }
    let cloud = errors.filter { $0.module == "icloud" }
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    let commit = Bundle.main.object(forInfoDictionaryKey: "ClawSourceCommit") as? String ?? "未提供"
    let last = errors.last
    let lastError = last.map {
      "最近错误：\($0.module)/\($0.action)，域：\($0.errorDomain ?? "未取得")，代码：\($0.errorCode.map(String.init) ?? "未取得")。"
    } ?? "没有发现当前进程已记录的 ERROR；不代表软件所有功能正常。"

    return """
    CLAW 本地只读自检（不访问私人聊天内容）
    当前构建：\(build)；源码版本：\(commit)
    实际检测：本进程已记录 \(events.count) 条事件、\(errors.count) 条错误（语音 \(voice.count)、iCloud \(cloud.count)）。
    \(lastError)
    根据证据推测：若有错误，可依据对应函数和系统错误码进一步排查，目前不能直接确认根因。
    尚未检测：未接入探针的权限与系统状态、键盘进程实时状态、系统全部崩溃报告。
    下一步：在出现故障时导出脱敏诊断记录，同构建版本复现并检查源码。
    """
  }
  /// Host + last persisted Keyboard Extension snapshot. Does not claim
  /// the extension is live, or that an unobserved module has passed a test.
  public static func report(capture: ClawDiagnosticCapture) -> String {
    let hostAndKeyboard = report(events: capture.events)
    let keyboardStatus: String
    switch capture.keyboardState {
    case .recent: keyboardStatus = "有最近五分钟的键盘事件；不代表进程现在仍在线"
    case .stale: keyboardStatus = "只有过期键盘快照，当前运行状态未知"
    case .missing: keyboardStatus = "没有发现键盘诊断事件"
    case .unavailable: keyboardStatus = "无法读取键盘共享诊断文件"
    case .corrupted: keyboardStatus = "键盘快照损坏，无法可靠分析"
    }
    return hostAndKeyboard + "\n跨进程证据：\(keyboardStatus)；故障现场 \(capture.incidents.count) 条。"
  }

}
