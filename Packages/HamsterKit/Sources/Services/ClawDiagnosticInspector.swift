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
}
