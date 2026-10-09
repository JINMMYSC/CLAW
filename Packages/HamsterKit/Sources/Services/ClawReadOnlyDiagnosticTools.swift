import Foundation

/// Read-only tools may observe only already-recorded, privacy-safe telemetry.
/// They never ask for microphone access, read user Memory content or change
/// iCloud/keyboard state. Unknown must never be upgraded to "healthy".
public enum ClawDiagnosticToolStatus: String, Codable {
  case ok, fault, unknown, unavailable
}

public struct ClawDiagnosticToolResult: Codable {
  public let name: String
  public let status: ClawDiagnosticToolStatus
  public let observedAt: Date?
  public let sourceCommit: String?
  public let message: String
  public let evidenceTraceIDs: [UUID]
  public let errorDomain: String?
  public let errorCode: Int?
}

/// Typed, allowlisted entry points for Claw's in-app assistant.
/// This is stage 1; callers must not assert real-time microphone/keyboard
/// status based merely on absence of logged failures.
public struct ClawReadOnlyDiagnosticTools {
  private let capture: ClawDiagnosticCapture
  private let now: Date
  private let version: String
  private let commit: String?
  private let voiceObservation: ClawDiagnosticCapabilityObservation?
  private let syncObservation: ClawDiagnosticCapabilityObservation?

  public init(
    capture: ClawDiagnosticCapture,
    now: Date = Date(),
    version: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
    commit: String? = Bundle.main.object(forInfoDictionaryKey: "ClawSourceCommit") as? String,
    voiceObservation: ClawDiagnosticCapabilityObservation? = nil,
    syncObservation: ClawDiagnosticCapabilityObservation? = nil
  ) {
    self.capture = capture
    self.now = now
    self.version = version
    self.commit = commit
    self.voiceObservation = voiceObservation
    self.syncObservation = syncObservation
  }

  public static func current() -> ClawReadOnlyDiagnosticTools {
    ClawReadOnlyDiagnosticTools(
      capture: ClawDiagnosticsCaptureService.captureCurrent(),
      voiceObservation: ClawRuntimeCapabilityInspector.inspectVoice(),
      syncObservation: ClawRuntimeCapabilityInspector.inspectSync()
    )
  }

  private func result(
    _ name: String, status: ClawDiagnosticToolStatus, message: String,
    evidence: [ClawDiagnosticEvent] = [],
    capability: ClawDiagnosticCapabilityObservation? = nil
  ) -> ClawDiagnosticToolResult {
    let last = evidence.last(where: { $0.severity == "error" })
    return ClawDiagnosticToolResult(
      name: name, status: status,
      observedAt: capability?.checkedAt ?? evidence.last?.timestamp,
      sourceCommit: commit,
      message: message,
      evidenceTraceIDs: Array(Set(evidence.map(\.traceID))).prefix(10).sorted {
        $0.uuidString < $1.uuidString
      },
      errorDomain: last?.errorDomain, errorCode: last?.errorCode
    )
  }

  public func getAppStatus() -> ClawDiagnosticToolResult {
    let buildAvailable = version != "unknown" && !(commit ?? "").isEmpty
    return result("getAppStatus", status: buildAvailable ? .ok : .unknown,
      message: buildAvailable
        ? "检测到本机构建 \(version)，源码标识 \(commit!)；只证明版本元数据可读取。"
        : "本机构建号 \(version)；未嵌入或无法读取对应源码 SHA，不能精确定位当前版本。")
  }

  public func getRecentErrors(since: TimeInterval = 600) -> ClawDiagnosticToolResult {
    let earliest = now.addingTimeInterval(-min(max(1, since), 86_400))
    let errors = capture.events.filter { $0.severity == "error" && $0.timestamp >= earliest }
    guard !errors.isEmpty else {
      return result("getRecentErrors", status: .unknown,
        message: "最近检查窗口无已记录 ERROR；可能缺少探针、键盘已终止或事件已轮转，不能据此证明功能正常。")
    }
    let last = errors.last!
    return result("getRecentErrors", status: .fault,
      message: "观察到 \(errors.count) 条错误；最近一次 \(last.module)/\(last.action)，调用点 \(last.file):\(last.line)。",
      evidence: Array(errors.suffix(30)))
  }

  public func getModuleHealth(_ module: String) -> ClawDiagnosticToolResult {
    let allowed: Set<String> = ["voice", "icloud", "keyboard", "ui", "ai", "memory", "clipboard", "autoinsight"]
    guard allowed.contains(module) else {
      return result("getModuleHealth", status: .unavailable, message: "未定义该模块的诊断探针。")
    }
    let relevant = capture.events.filter {
      $0.module == module && $0.timestamp >= now.addingTimeInterval(-1_800)
    }
    let errors = relevant.filter { $0.severity == "error" }
    if let error = errors.last {
      return result("getModuleHealth", status: .fault,
        message: "\(module) 最近存在失败：\(error.action)；没有证据表明已成功恢复。",
        evidence: relevant)
    }
    if module == "keyboard" && capture.keyboardState != .recent {
      return result("getModuleHealth", status: .unknown,
        message: "键盘只有 \(capture.keyboardState.rawValue) 快照，不能宣称扩展正在运行。")
    }
    // Presence of non-error events is not enough to assert functional health.
    return result("getModuleHealth", status: .unknown,
      message: relevant.isEmpty
        ? "\(module) 最近没有可验证事件，状态未知。"
        : "\(module) 有 \(relevant.count) 条事件，但未完成独立功能自检，健康状态尚未确认。",
      evidence: relevant)
  }

  public func inspectVoice() -> ClawDiagnosticToolResult {
    let observed = getModuleHealth("voice")
    let check = voiceObservation
    let status: ClawDiagnosticToolStatus =
      observed.status == .fault ? .fault : check?.status ?? .unknown
    return result("inspectVoice", status: status,
      message: observed.message + " " + (check?.message ?? "麦克风/语音识别系统授权尚未实时检测。") +
        " 当前音频路由及识别引擎运行情况尚未检测；不会启动录音。",
      evidence: capture.events.filter { $0.module == "voice" }, capability: check)
  }

  public func inspectSync() -> ClawDiagnosticToolResult {
    let observed = getModuleHealth("icloud")
    let check = syncObservation
    let status: ClawDiagnosticToolStatus =
      observed.status == .fault ? .fault : check?.status ?? .unknown
    return result("inspectSync", status: status,
      message: observed.message + " " + (check?.message ?? "iCloud 签名和身份状态尚未实时检测。") +
        " 尚未检查实际云文件读写与本地数据一致性。",
      evidence: capture.events.filter { $0.module == "icloud" }, capability: check)
  }

  public func inspectNavigation() -> ClawDiagnosticToolResult {
    let observed = getModuleHealth("ui")
    return result("inspectNavigation", status: observed.status,
      message: observed.message + " 此处仅包含已记录页面事件，不是完整 UIView/SwiftUI 视图树。",
      evidence: capture.events.filter { $0.module == "ui" })
  }

  public func inspectMemory() -> ClawDiagnosticToolResult {
    let observed = getModuleHealth("memory")
    return result("inspectMemory", status: observed.status,
      message: observed.message + " 未读取用户的记忆正文、聊天和私人联系人。",
      evidence: capture.events.filter { $0.module == "memory" })
  }

  public func runSelfTest() -> [ClawDiagnosticToolResult] {
    // Strictly read-only. No calls to Speech.requestAuthorization, audio
    // session, database writes, iCloud writes or system clipboard.
    [getAppStatus(), getRecentErrors(), inspectVoice(),
     inspectNavigation(), inspectMemory(), inspectSync(),
     getModuleHealth("keyboard"), getModuleHealth("ai")]
  }

  public func describe(_ tool: ClawDiagnosticToolResult) -> String {
    let code = tool.errorCode.map(String.init) ?? "未记录"
    return """
    \(tool.name)：\(tool.status.rawValue)
    实际证据：\(tool.message)
    错误域：\(tool.errorDomain ?? "未记录")；错误码：\(code)
    Trace：\(tool.evidenceTraceIDs.prefix(3).map(\.uuidString).joined(separator: ", "))
    未经检测的部分不会显示为正常，根因仍需与同 SHA 源码核验。
    """
  }
}
