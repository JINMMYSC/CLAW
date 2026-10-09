import AVFoundation
import Foundation
import Speech

/// Fixed-key, content-free capability checks. Never requests authorization,
/// starts audio recording, touches user files or performs a cloud write.
public struct ClawDiagnosticCapabilityObservation {
  public let status: ClawDiagnosticToolStatus
  public let message: String
  public let checkedAt: Date

  public init(status: ClawDiagnosticToolStatus, message: String, checkedAt: Date = Date()) {
    self.status = status
    self.message = message
    self.checkedAt = checkedAt
  }
}

public enum ClawRuntimeCapabilityInspector {
  public static func voice(speech: String, microphone: String) -> ClawDiagnosticCapabilityObservation {
    let allowedSpeech: Set<String> = ["authorized", "denied", "restricted", "notDetermined"]
    let allowedMic: Set<String> = ["granted", "denied", "undetermined"]
    guard allowedSpeech.contains(speech), allowedMic.contains(microphone) else {
      return .init(status: .unknown, message: "语音或麦克风权限无法读取。")
    }
    if speech == "denied" || speech == "restricted" || microphone == "denied" {
      return .init(status: .fault, message: "实际权限检查：语音识别 \(speech)，麦克风 \(microphone)；录音前需要用户在系统设置中授权。")
    }
    return .init(status: .unknown, message: "实际权限检查：语音识别 \(speech)，麦克风 \(microphone)；这不代表音频引擎或识别服务已正常运行。")
  }

  public static func inspectVoice() -> ClawDiagnosticCapabilityObservation {
    guard Bundle.main.bundleURL.pathExtension.lowercased() != "appex" else {
      return .init(status: .unavailable, message: "键盘扩展无法直接使用麦克风，须通过主程序检查。")
    }
    let speech: String
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized: speech = "authorized"
    case .denied: speech = "denied"
    case .restricted: speech = "restricted"
    case .notDetermined: speech = "notDetermined"
    @unknown default: speech = "unknown"
    }
    let mic: String
    switch AVAudioSession.sharedInstance().recordPermission {
    case .granted: mic = "granted"
    case .denied: mic = "denied"
    case .undetermined: mic = "undetermined"
    @unknown default: mic = "unknown"
    }
    return voice(speech: speech, microphone: mic)
  }

  public static func sync(entitled: Bool?, signedIn: Bool?) -> ClawDiagnosticCapabilityObservation {
    if entitled == false {
      return .init(status: .fault,
        message: "实际安装包未具备 CLAW 所需 CloudDocuments 容器签名权限；云备份/恢复不可用，本地数据不受本次检查影响。")
    }
    guard let entitled else {
      return .init(status: .unknown, message: "安装包未提供可核验的 iCloud 能力标识，不能确认签名权限。")
    }
    guard let signedIn else {
      return .init(status: .unknown, message: "已读取 iCloud 签名权限，但无法确认设备 iCloud 身份状态。")
    }
    return .init(status: signedIn ? .unknown : .fault,
      message: signedIn
        ? "安装包具有 CloudDocuments 权限且系统有 iCloud 身份标识；尚未验证同步读写和数据一致性。"
        : "安装包具有 CloudDocuments 权限，但设备当前无可访问的 iCloud 身份标识。")
  }

  public static func inspectSync() -> ClawDiagnosticCapabilityObservation {
    guard Bundle.main.bundleURL.pathExtension.lowercased() != "appex" else {
      return .init(status: .unavailable, message: "键盘扩展不执行主程序 iCloud 文件复制。")
    }
    let entitled = Bundle.main.object(forInfoDictionaryKey: "ClawICloudContainerEntitled") as? Bool
    let signedIn = entitled == true ? FileManager.default.ubiquityIdentityToken != nil : nil
    return sync(entitled: entitled, signedIn: signedIn)
  }
}
