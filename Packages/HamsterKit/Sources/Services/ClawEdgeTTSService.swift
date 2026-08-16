//
//  ClawEdgeTTSService.swift
//  ClawTalk Edge TTS 语音服务（免费非官方接口，SwiftEdgeTTS vendor）
//
//  - 音色/语速/音调从 App Group 设置读取，键盘扩展与主程序共享
//  - 合成 mp3 → AVAudioPlayer 播放；失败自动降级系统 AVSpeechSynthesizer
//
import AVFoundation
import Foundation

/// ClawTalk 语音设置存储键
public enum ClawVoiceSettings {
  public static let voiceKey = "claw_tts_voice"
  public static let rateKey = "claw_tts_rate" // Int -50...50（百分比）
  public static let pitchKey = "claw_tts_pitch" // Int -50...50（Hz）

  public static let defaultVoice = "zh-CN-XiaoxiaoNeural"
}

public final class ClawEdgeTTSService: NSObject, AVAudioPlayerDelegate {
  public static let shared = ClawEdgeTTSService()

  /// 播放状态变化回调（用于通话模式循环接听）
  public var onSpeakingChange: ((Bool) -> Void)?

  public private(set) var isSpeaking = false {
    didSet {
      if oldValue != isSpeaking { onSpeakingChange?(isSpeaking) }
    }
  }

  private let defaults = UserDefaults(suiteName: HamsterConstants.appGroupName)
  private let edgeTTS = EdgeTTSService()
  private let synthesizer = AVSpeechSynthesizer()
  private var player: AVAudioPlayer?

  private override init() {
    super.init()
  }

  // MARK: - 设置读取

  public var voice: String {
    get { defaults?.string(forKey: ClawVoiceSettings.voiceKey) ?? ClawVoiceSettings.defaultVoice }
    set { defaults?.set(newValue, forKey: ClawVoiceSettings.voiceKey) }
  }

  public var ratePercent: Int {
    get { defaults?.object(forKey: ClawVoiceSettings.rateKey) as? Int ?? 0 }
    set { defaults?.set(newValue, forKey: ClawVoiceSettings.rateKey) }
  }

  public var pitchHz: Int {
    get { defaults?.object(forKey: ClawVoiceSettings.pitchKey) as? Int ?? 0 }
    set { defaults?.set(newValue, forKey: ClawVoiceSettings.pitchKey) }
  }

  // MARK: - 朗读

  /// 朗读一段文字（Edge TTS 主链路，失败自动降级系统语音）
  public func speak(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    stop()
    // STT 录音后会话可能停留在 .record 类别，读前切回播放类别
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    try? session.setActive(true, options: [.notifyOthersOnDeactivation])
    isSpeaking = true
    Task {
      do {
        let rate = ratePercent >= 0 ? "+\(ratePercent)%" : "\(ratePercent)%"
        let pitch = pitchHz >= 0 ? "+\(pitchHz)Hz" : "\(pitchHz)Hz"
        let url = FileManager.default.temporaryDirectory
          .appendingPathComponent("claw_tts_\(UUID().uuidString).mp3")
        let out = try await edgeTTS.synthesize(text: trimmed, voice: voice, outputURL: url, rate: rate, volume: nil, pitch: pitch)
        await MainActor.run {
          guard self.isSpeaking else { return }
          self.player = try? AVAudioPlayer(contentsOf: out)
          self.player?.delegate = self
          if self.player?.play() != true {
            self.fallbackSpeak(trimmed)
          }
        }
      } catch {
        await MainActor.run { self.fallbackSpeak(trimmed) }
      }
    }
  }

  /// 停止播放
  public func stop() {
    player?.stop()
    player = nil
    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }
    isSpeaking = false
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
  }

  /// 降级：系统 AVSpeechSynthesizer（离线/网络失败时保证能出声）
  private func fallbackSpeak(_ text: String) {
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
    let baseRate = AVSpeechUtteranceDefaultSpeechRate
    utterance.rate = baseRate * (1 + Float(ratePercent) / 100)
    utterance.pitchMultiplier = 1 + Float(pitchHz) / 200
    synthesizer.delegate = self
    synthesizer.speak(utterance)
  }

  // MARK: - AVAudioPlayerDelegate

  public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    self.player = nil
    isSpeaking = false
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
  }
}

// MARK: - AVSpeechSynthesizerDelegate

extension ClawEdgeTTSService: AVSpeechSynthesizerDelegate {
  public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    isSpeaking = false
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
  }

  public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    isSpeaking = false
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
  }
}