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

  /// 是否正在录音
  public private(set) var isRecording = false

  private var streamingPartial: ((String) -> Void)?
  private var streamingSegment: ((String) -> Void)?
  private var streamingError: ((Error) -> Void)?
  private var silenceWorkItem: DispatchWorkItem?

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

  /// 开始录音；停止后通过 completion 返回最终识别文本
  public func start(completion: @escaping (Result<String, Error>) -> Void) {
    stop()
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
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
      request.append(buffer)
    }

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .measurement, options: [])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
      audioEngine.prepare()
      try audioEngine.start()
    } catch {
      inputNode.removeTap(onBus: 0)
      completion(.failure(error))
      return
    }

    self.audioEngine = audioEngine
    self.recognitionRequest = request
    isRecording = true

    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      guard let self else { return }
      if let result, result.isFinal {
        self.cleanup()
        completion(.success(result.bestTranscription.formattedString))
      } else if error != nil {
        self.cleanup()
        completion(.failure(error ?? ClawVoiceError.unknown))
      }
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
    stop()
    streamingPartial = onPartial
    streamingSegment = onSegment
    streamingError = onError

    guard let recognizer, recognizer.isAvailable else {
      onError(ClawVoiceError.recognizerUnavailable)
      return
    }

    let audioEngine = AVAudioEngine()
    let inputNode = audioEngine.inputNode
    let format = inputNode.outputFormat(forBus: 0)
    guard format.sampleRate > 0 else {
      onError(ClawVoiceError.audioUnavailable)
      return
    }
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      self?.recognitionRequest?.append(buffer)
    }

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .measurement, options: [])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
      audioEngine.prepare()
      try audioEngine.start()
    } catch {
      inputNode.removeTap(onBus: 0)
      onError(error)
      return
    }

    self.audioEngine = audioEngine
    isRecording = true

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = false
    recognitionRequest = request
    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      guard let self else { return }
      if let result {
        let text = result.bestTranscription.formattedString
        if result.isFinal {
          self.silenceWorkItem?.cancel()
          self.silenceWorkItem = nil
          self.cleanup()
          self.streamingSegment?(text)
        } else {
          self.restartSilenceTimer()
          self.streamingPartial?(text)
        }
      } else if let error {
        self.silenceWorkItem?.cancel()
        self.silenceWorkItem = nil
        self.cleanup()
        self.streamingError?(error)
      }
    }
  }

  /// 静音停顿 1.2s 判定断句：结束当前段，触发 final 结果
  private func restartSilenceTimer() {
    silenceWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      guard let self, self.isRecording else { return }
      self.recognitionRequest?.endAudio()
    }
    silenceWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
  }

  private func clearStreamingCallbacks() {
    streamingPartial = nil
    streamingSegment = nil
    streamingError = nil
  }

  /// 停止录音，触发最终识别回调
  public func stop() {
    silenceWorkItem?.cancel()
    silenceWorkItem = nil
    clearStreamingCallbacks()
    guard isRecording else { return }
    recognitionRequest?.endAudio()
    audioEngine?.stop()
    audioEngine?.inputNode.removeTap(onBus: 0)
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    audioEngine = nil
    recognitionRequest = nil
    isRecording = false
  }

  private func cleanup() {
    silenceWorkItem?.cancel()
    silenceWorkItem = nil
    audioEngine?.stop()
    audioEngine?.inputNode.removeTap(onBus: 0)
    audioEngine = nil
    recognitionRequest = nil
    recognitionTask = nil
    isRecording = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}

public enum ClawVoiceError: LocalizedError {
  case recognizerUnavailable
  case audioUnavailable
  case unknown

  public var errorDescription: String? {
    switch self {
    case .recognizerUnavailable: return "语音识别不可用，请检查系统设置"
    case .audioUnavailable: return "麦克风不可用"
    case .unknown: return "语音识别失败"
    }
  }
}
