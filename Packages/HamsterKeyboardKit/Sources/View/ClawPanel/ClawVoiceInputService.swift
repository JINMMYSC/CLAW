import AVFoundation
import Foundation
import HamsterKit
import Speech

public enum ClawVoiceLanguageMode: String, CaseIterable {
  case automatic
  case mandarin
  case cantonese
  case english

  public var displayName: String {
    switch self {
    case .automatic: return "自动"
    case .mandarin: return "普通话"
    case .cantonese: return "粤语"
    case .english: return "English"
    }
  }
}

enum ClawVoiceLaunchAction: Equatable {
  case openHostDictation
  case recordLocally
  case showPermissionDenied
  case showPermissionRequired
}

enum ClawVoiceLaunchPolicy {
  static func action(
    isKeyboardExtension: Bool,
    authorization: ClawVoiceInputService.ClawVoiceAuth
  ) -> ClawVoiceLaunchAction {
    // Custom keyboard extensions do not receive microphone access on iOS. Always
    // hand dictation to the containing app, which owns the Speech and microphone
    // permission prompts as well as the AVAudioSession.
    if isKeyboardExtension { return .openHostDictation }
    switch authorization {
    case .authorized: return .recordLocally
    case .denied: return .showPermissionDenied
    case .undetermined: return .showPermissionRequired
    }
  }
}

/// 语音输入服务：按住说话 / 连续语音 → Speech 转文字。
public final class ClawVoiceInputService: NSObject {
  public static let shared = ClawVoiceInputService()

  private let defaults = UserDefaults(suiteName: HamsterConstants.appGroupName)
  private let languageModeKey = "claw_voice_language_mode_v1"
  private let silenceIntervalKey = "claw_voice_silence_interval_v1"
  private let preferOnDeviceKey = "claw_voice_prefer_on_device_v1"
  private var audioEngine: AVAudioEngine?
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var sessionGeneration: UInt = 0
  /// Keep the best partial result until Speech finishes after endAudio().
  /// Some devices never deliver isFinal, so the stop watchdog must complete once.
  private var oneShotPartialText = ""
  private var oneShotCompletion: ((Result<String, Error>) -> Void)?

  /// 是否正在录音
  public private(set) var isRecording = false

  public var languageMode: ClawVoiceLanguageMode {
    get {
      guard let raw = defaults?.string(forKey: languageModeKey),
            let mode = ClawVoiceLanguageMode(rawValue: raw) else { return .automatic }
      return mode
    }
    set { defaults?.set(newValue.rawValue, forKey: languageModeKey) }
  }

  /// 连续语音静音断句阈值。默认 1.0 秒，比旧版 1.2 秒更接近自然对话。
  public var silenceInterval: TimeInterval {
    get {
      let stored = defaults?.double(forKey: silenceIntervalKey) ?? 0
      return stored > 0 ? min(1.8, max(0.7, stored)) : 1.0
    }
    set { defaults?.set(min(1.8, max(0.7, newValue)), forKey: silenceIntervalKey) }
  }

  /// 默认优先可靠性，不强制本地识别。用户明确开启后才要求 on-device。
  public var preferOnDeviceRecognition: Bool {
    get { defaults?.bool(forKey: preferOnDeviceKey) ?? false }
    set { defaults?.set(newValue, forKey: preferOnDeviceKey) }
  }

  private var streamingPartial: ((String) -> Void)?
  private var streamingSegment: ((String) -> Void)?
  private var streamingError: ((Error) -> Void)?
  private var silenceWorkItem: DispatchWorkItem?
  private var pendingCleanupWorkItem: DispatchWorkItem?

  private override init() {
    super.init()
  }

  /// 语音权限状态（只读，不在键盘扩展里弹系统权限框，避免闪退）
  public enum ClawVoiceAuth {
    case authorized
    case denied
    case undetermined
  }

  public var authorizationStatus: ClawVoiceAuth {
    let speech = SFSpeechRecognizer.authorizationStatus()
    let mic = AVAudioSession.sharedInstance().recordPermission
    if speech == .authorized, mic == .granted { return .authorized }
    if speech == .denied || speech == .restricted || mic == .denied {
      return .denied
    }
    return .undetermined
  }

  /// 仅主 App 调用。键盘扩展不会主动弹权限框。
  public func requestAuthorization(completion: @escaping (Bool) -> Void) {
    guard !isKeyboardExtensionRuntime else {
      LogService.shared.log(.voiceAuthorizationFailed)
      completion(false)
      return
    }
    SFSpeechRecognizer.requestAuthorization { speechStatus in
      guard speechStatus == .authorized else {
        LogService.shared.log(.voiceAuthorizationFailed)
        DispatchQueue.main.async { completion(false) }
        return
      }
      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        if !granted {
          LogService.shared.log(.voiceAuthorizationFailed)
        }
        DispatchQueue.main.async { completion(granted) }
      }
    }
  }

  private var isKeyboardExtensionRuntime: Bool {
    Bundle.main.bundleURL.pathExtension.lowercased() == "appex"
  }

  /// 开始录音；停止后通过 completion 返回最终识别文本
  /// 键盘扩展同样走这条路：前提是主程序已经授权麦克风与语音识别，
  /// 并且键盘已开启「允许完全访问」。扩展里不能弹权限框，所以授权必须在主程序完成。
  public func start(completion: @escaping (Result<String, Error>) -> Void) {
    guard !isKeyboardExtensionRuntime else {
      completion(.failure(ClawVoiceError.keyboardExtensionUnsupported))
      return
    }
    let generation = resetForNewSession()
    guard let recognizer = makeRecognizer(), recognizer.isAvailable else {
      LogService.shared.log(.voiceRecognizerUnavailable)
      completion(.failure(ClawVoiceError.recognizerUnavailable))
      return
    }

    let audioEngine = AVAudioEngine()
    let request = Self.makeOneShotRequest()
    if preferOnDeviceRecognition, recognizer.supportsOnDeviceRecognition {
      request.requiresOnDeviceRecognition = true
    }

    do {
      try activateMicrophoneSession()
    } catch {
      LogService.shared.log(.voiceSessionStartFailed)
      completion(.failure(error))
      return
    }
    let inputNode = audioEngine.inputNode
    let format = inputNode.outputFormat(forBus: 0)
    guard format.sampleRate > 0 else {
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      LogService.shared.log(.voiceAudioUnavailable)
      completion(.failure(ClawVoiceError.audioUnavailable))
      return
    }

    self.audioEngine = audioEngine
    self.recognitionRequest = request
    oneShotPartialText = ""
    oneShotCompletion = completion
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
      request.append(buffer)
    }

    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      DispatchQueue.main.async {
        guard let self, self.sessionGeneration == generation else { return }
        if let result {
          let text = result.bestTranscription.formattedString
          if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.oneShotPartialText = text
          }
          if result.isFinal {
            let callback = self.oneShotCompletion
            self.finishSession(generation, cancelTask: false, clearStreamingCallbacks: true)
            callback?(.success(text))
            return
          }
        }
        if let error {
          // An error following endAudio can still contain a usable transcript.
          let partial = self.oneShotPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
          let stopped = !self.isRecording
          let callback = self.oneShotCompletion
          self.finishSession(generation, cancelTask: false, clearStreamingCallbacks: true)
          LogService.shared.log(.voiceRecognitionFailed)
          if stopped && !partial.isEmpty {
            callback?(.success(partial))
          } else {
            callback?(.failure(error))
          }
        }
      }
    }

    do {
      audioEngine.prepare()
      try audioEngine.start()
      isRecording = true
    } catch {
      finishSession(generation, cancelTask: true, clearStreamingCallbacks: true)
      LogService.shared.log(.voiceSessionStartFailed)
      completion(.failure(error))
    }
  }

  /// 流式听写（实时通话模式）：持续收音，静音停顿自动断句
  /// - onPartial: 实时转写中间结果（输入框预览）
  /// - onSegment: 每段完整识别（静音停顿后触发），触发后本服务自动停止，由调用方决定是否续听
  /// - onError: 识别失败
  public func startStreaming(
    onPartial: @escaping (String) -> Void,
    onSegment: @escaping (String) -> Void,
    onError: @escaping (Error) -> Void
  ) {
    guard !isKeyboardExtensionRuntime else {
      onError(ClawVoiceError.keyboardExtensionUnsupported)
      return
    }
    let generation = resetForNewSession()
    streamingPartial = onPartial
    streamingSegment = onSegment
    streamingError = onError

    guard let recognizer = makeRecognizer(), recognizer.isAvailable else {
      clearStreamingCallbacks()
      LogService.shared.log(.voiceRecognizerUnavailable)
      onError(ClawVoiceError.recognizerUnavailable)
      return
    }

    let audioEngine = AVAudioEngine()
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    if preferOnDeviceRecognition, recognizer.supportsOnDeviceRecognition {
      request.requiresOnDeviceRecognition = true
    }

    do {
      try activateMicrophoneSession()
    } catch {
      clearStreamingCallbacks()
      LogService.shared.log(.voiceSessionStartFailed)
      onError(error)
      return
    }
    let inputNode = audioEngine.inputNode
    let format = inputNode.outputFormat(forBus: 0)
    guard format.sampleRate > 0 else {
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      clearStreamingCallbacks()
      LogService.shared.log(.voiceAudioUnavailable)
      onError(ClawVoiceError.audioUnavailable)
      return
    }

    self.audioEngine = audioEngine
    self.recognitionRequest = request
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
      request.append(buffer)
    }

    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      guard let self, self.sessionGeneration == generation else { return }
      if let result {
        let text = result.bestTranscription.formattedString
        if result.isFinal {
let onSegment = self.streamingSegment
self.finishSession(generation, cancelTask: false, clearStreamingCallbacks: true)
onSegment?(text)
        } else {
self.restartSilenceTimer(for: generation)
self.streamingPartial?(text)
        }
      } else if let error {
        let onError = self.streamingError
        self.finishSession(generation, cancelTask: false, clearStreamingCallbacks: true)
        LogService.shared.log(.voiceRecognitionFailed)
        onError?(error)
      }
    }

    do {
      audioEngine.prepare()
      try audioEngine.start()
      isRecording = true
    } catch {
      let callback = streamingError
      finishSession(generation, cancelTask: true, clearStreamingCallbacks: true)
      LogService.shared.log(.voiceSessionStartFailed)
      callback?(error)
    }
  }

  /// 静音停顿达到阈值后断句：结束当前段，等待 final 结果。
  private func restartSilenceTimer(for generation: UInt) {
    silenceWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      guard let self,
  self.sessionGeneration == generation,
  self.isRecording else { return }
      self.stop()
    }
    silenceWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + silenceInterval, execute: item)
  }

  public var activeLocaleIdentifier: String {
    switch languageMode {
    case .mandarin:
      return "zh-Hans"
    case .cantonese:
      return "yue-Hant-HK"
    case .english:
      return "en-US"
    case .automatic:
      let preferred = Locale.preferredLanguages.joined(separator: ",").lowercased()
      if preferred.contains("yue") || preferred.contains("zh-hk") || preferred.contains("zh-mo") {
        return "yue-Hant-HK"
      }
      if preferred.hasPrefix("en") { return "en-US" }
      return "zh-Hans"
    }
  }

  private func makeRecognizer() -> SFSpeechRecognizer? {
    SFSpeechRecognizer(locale: Locale(identifier: activeLocaleIdentifier))
  }

  /// One-shot dictation also needs interim transcripts. Some iOS Speech
  /// sessions never emit an isFinal callback after endAudio(), so stop() can
  /// fall back to the last nonempty partial result instead of losing speech.
  static func makeOneShotRequest() -> SFSpeechAudioBufferRecognitionRequest {
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    return request
  }

  /// iOS can report a zero-Hz input format until AVAudioSession is active.
  /// Configure and activate *before* inspecting AVAudioEngine.inputNode.
  private func activateMicrophoneSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.record, mode: .measurement, options: [])
    try session.setActive(true, options: .notifyOthersOnDeactivation)
  }

  private func clearStreamingCallbacks() {
    streamingPartial = nil
    streamingSegment = nil
    streamingError = nil
  }

  /// 停止采集并 endAudio，但保留 recognition task/callback，给 Speech final result 收尾机会。
  public func stop() {
    silenceWorkItem?.cancel()
    silenceWorkItem = nil
    pendingCleanupWorkItem?.cancel()
    pendingCleanupWorkItem = nil

    guard recognitionRequest != nil || recognitionTask != nil || audioEngine != nil else {
      isRecording = false
      clearStreamingCallbacks()
      return
    }

    let generation = sessionGeneration
    recognitionRequest?.endAudio()
    if let audioEngine {
      audioEngine.stop()
      audioEngine.inputNode.removeTap(onBus: 0)
    }
    audioEngine = nil
    isRecording = false

    // Speech must finish processing buffered audio before AVAudioSession is
    // deactivated in teardown. Slow devices may need several seconds to finalise.
    let cleanup = DispatchWorkItem { [weak self] in
      guard let self, self.sessionGeneration == generation else { return }
      let callback = self.oneShotCompletion
      let partial = self.oneShotPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
      self.finishSession(generation, cancelTask: true, clearStreamingCallbacks: true)
      if !partial.isEmpty {
        callback?(.success(partial))
      } else {
        callback?(.failure(ClawVoiceError.noTranscriptAfterStop))
      }
    }
    pendingCleanupWorkItem = cleanup
    DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: cleanup)
  }

  /// 新会话开始前强制取消上一会话；generation 让上一 task 的迟到 callback 自动失效。
  @discardableResult
  private func resetForNewSession() -> UInt {
    sessionGeneration &+= 1
    teardown(cancelTask: true, clearStreamingCallbacks: true)
    return sessionGeneration
  }

  private func finishSession(
    _ generation: UInt,
    cancelTask: Bool,
    clearStreamingCallbacks: Bool
  ) {
    guard sessionGeneration == generation else { return }
    sessionGeneration &+= 1
    teardown(cancelTask: cancelTask, clearStreamingCallbacks: clearStreamingCallbacks)
  }

  private func teardown(cancelTask: Bool, clearStreamingCallbacks: Bool) {
    silenceWorkItem?.cancel()
    silenceWorkItem = nil
    pendingCleanupWorkItem?.cancel()
    pendingCleanupWorkItem = nil

    recognitionRequest?.endAudio()
    if let audioEngine {
      audioEngine.stop()
      audioEngine.inputNode.removeTap(onBus: 0)
    }
    if cancelTask {
      recognitionTask?.cancel()
    }

    audioEngine = nil
    recognitionRequest = nil
    recognitionTask = nil
    oneShotCompletion = nil
    oneShotPartialText = ""
    isRecording = false
    if clearStreamingCallbacks {
      self.clearStreamingCallbacks()
    }
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}

public enum ClawVoiceError: LocalizedError {
  case recognizerUnavailable
  case audioUnavailable
  case keyboardExtensionUnsupported
  case noTranscriptAfterStop
  case unknown

  public var errorDescription: String? {
    switch self {
    case .recognizerUnavailable: return "语音识别不可用，请检查系统设置"
    case .audioUnavailable: return "麦克风不可用"
    case .keyboardExtensionUnsupported: return "键盘扩展无法直接使用麦克风，请切换到系统键盘使用听写"
    case .noTranscriptAfterStop: return "录音已结束，但没有识别到文字，请检查语音识别权限和网络后重试"
    case .unknown: return "语音识别失败"
    }
  }
}
