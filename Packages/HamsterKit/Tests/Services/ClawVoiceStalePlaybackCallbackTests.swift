import AVFoundation
import XCTest
@testable import HamsterKit

final class ClawVoiceStalePlaybackCallbackTests: XCTestCase {
  func testUnrelatedSpeechCallbacksDoNotInterruptCurrentOfflineSpeech() {
    let service = ClawEdgeTTSService.shared
    let previousCloudConsent = service.allowsCloudTTS
    service.allowsCloudTTS = false
    defer {
      service.stop()
      service.allowsCloudTTS = previousCloudConsent
    }

    // This exercises the real service delegate, without uploading any text.
    service.speak(String(repeating: "本地语音播放回归测试。", count: 40))
    XCTAssertTrue(service.isSpeaking)

    // An AVSpeechSynthesizer may deliver a cancellation from an older
    // utterance after a new playback request has already begun.
    let staleUtterance = AVSpeechUtterance(string: "older request")
    let unrelatedSynthesizer = AVSpeechSynthesizer()
    service.speechSynthesizer(unrelatedSynthesizer, didCancel: staleUtterance)
    XCTAssertTrue(service.isSpeaking, "stale cancellation stopped current playback")

    service.speechSynthesizer(unrelatedSynthesizer, didFinish: staleUtterance)
    XCTAssertTrue(service.isSpeaking, "stale completion stopped current playback")
  }
}
