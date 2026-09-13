import AVFoundation
import Foundation
import Speech

/// 语音输入服务：按住说话 → SFSpeechRecognizer（zh-Hans）转文字
public final class ClawVoiceInputService: NSObject {
  public static let shared = ClawVoiceInputService()

  private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans"))
  private var audioEngine: AVAudioEngine?
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var sessionGeneration: UInt = 0

  /// 是否正在录音
  public private(set) var isRecording = false

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

  private var isKeyboardExtensionRuntime: Bool {
    Bundle.main.bundleURL.pathExtension.lowercased() == "appex"
  }

  /// 开始录音；停止后通过 completion 返回最终识别文本
  public func start(completion: @escaping (Result<String, Error>) -> Void) {
    guard !isKeyboardExtensionRuntime else {
      completion(.failure(ClawVoiceError.keyboardExtensionUnsupported))
      return
    }

    let generation = resetForNewSession()
    guard let recognizer, recognizer.isAvailable else {
      completion(.failure(ClawVoiceError.recognizerUnavailable))
      return
    }

    let audioEngine = AVAudioEngine()
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = false
    request.requiresOnDeviceRecognition = false

    let inputNode = audioEngine.inputNode
    let format = inputNode.outputFormat(forBus: 0)
    guard format.sampleRate > 0 else {
      completion(.failure(ClawVoiceError.audioUnavailable))
      return
    }

    self.audioEngine = audioEngine
    self.recognitionRequest = request
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
      request.append(buffer)
    }

    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      guard let self, self.sessionGeneration == generation else { return }
      if let result, result.isFinal {
        let text = result.bestTranscription.formattedString
        self.finishSession(generation, cancelTask: false, clearStreamingCallbacks: true)
        completion(.success(text))
      } else if let error {
        self.finishSession(generation, cancelTask: false, clearStreamingCallbacks: true)
        completion(.failure(error))
      }
    }

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .measurement, options: [])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
      audioEngine.prepare()
      try audioEngine.start()
      isRecording = true
    } catch {
      finishSession(generation, cancelTask: true, clearStreamingCallbacks: true)
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

    guard let recognizer, recognizer.isAvailable else {
      clearStreamingCallbacks()
      onError(ClawVoiceError.recognizerUnavailable)
      return
    }

    let audioEngine = AVAudioEngine()
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = false

    let inputNode = audioEngine.inputNode
    let format = inputNode.outputFormat(forBus: 0)
    guard format.sampleRate > 0 else {
      clearStreamingCallbacks()
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
        onError?(error)
      }
    }

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .measurement, options: [])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
      audioEngine.prepare()
      try audioEngine.start()
      isRecording = true
    } catch {
      let callback = streamingError
      finishSession(generation, cancelTask: true, clearStreamingCallbacks: true)
      callback?(error)
    }
  }

  /// 静音停顿 1.2s 判定断句：结束当前段，等待 final 结果
  private func restartSilenceTimer(for generation: UInt) {
    silenceWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      guard let self,
  self.sessionGeneration == generation,
  self.isRecording else { return }
      self.stop()
    }
    silenceWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
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
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

    // 正常情况下 Speech 会很快返回 final；兜底避免无 final 时 task/callback 长期滞留。
    let cleanup = DispatchWorkItem { [weak self] in
      guard let self, self.sessionGeneration == generation else { return }
      self.finishSession(generation, cancelTask: true, clearStreamingCallbacks: true)
    }
    pendingCleanupWorkItem = cleanup
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: cleanup)
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
  case unknown

  public var errorDescription: String? {
    switch self {
    case .recognizerUnavailable: return "语音识别不可用，请检查系统设置"
    case .audioUnavailable: return "麦克风不可用"
    case .keyboardExtensionUnsupported: return "键盘扩展无法直接使用麦克风，请切换到系统键盘使用听写"
    case .unknown: return "语音识别失败"
    }
  }
}
