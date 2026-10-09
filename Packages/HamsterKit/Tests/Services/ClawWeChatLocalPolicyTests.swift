import XCTest
@testable import HamsterKit

final class ClawWeChatLocalPolicyTests: XCTestCase {
  func testTextImageVoiceAreRecognizedAsDistinctPayloads() {
    let cases: [(ClawWeChatLocalMessageKind, String?, String?)] = [
      (.text, "你好", nil),
      (.image, nil, "media-image-1"),
      (.voice, nil, "media-voice-1")
    ]
    for (kind, text, media) in cases {
      let message = ClawWeChatLocalMessage(
        messageID: "m1", conversationID: "chat", senderID: "sender",
        kind: kind, text: text, mediaReference: media
      )
      XCTAssertTrue(message.isStructurallyValid)
    }
    XCTAssertFalse(ClawWeChatLocalMessage(messageID: "m", conversationID: "c", senderID: "u", kind: .voice).isStructurallyValid)
    XCTAssertFalse(ClawWeChatLocalMessage(messageID: "m", conversationID: "c", senderID: "u", kind: .text, text: "   ").isStructurallyValid)
  }

  func testKeyboardNeedsVisibilityAndFullAccessButHostDoesNot() {
    XCTAssertTrue(ClawWeChatLocalRuntimePolicy.canPoll(connection: .active, hostForeground: true, keyboardVisible: false, keyboardFullAccess: false))
    XCTAssertTrue(ClawWeChatLocalRuntimePolicy.canPoll(connection: .active, hostForeground: false, keyboardVisible: true, keyboardFullAccess: true))
    XCTAssertFalse(ClawWeChatLocalRuntimePolicy.canPoll(connection: .active, hostForeground: false, keyboardVisible: true, keyboardFullAccess: false))
    XCTAssertFalse(ClawWeChatLocalRuntimePolicy.canPoll(connection: .active, hostForeground: false, keyboardVisible: false, keyboardFullAccess: true))
    XCTAssertFalse(ClawWeChatLocalRuntimePolicy.canPoll(connection: .authorizedPaused, hostForeground: true, keyboardVisible: true, keyboardFullAccess: true))
  }

  func testDuplicateMediaMessagesDoNotGetProcessedTwice() {
    var guardStore = ClawWeChatLocalInboxGuard()
    let voice = ClawWeChatLocalMessage(messageID: "voice1", conversationID: "chat", senderID: "user", kind: .voice, mediaReference: "opaque-token")
    XCTAssertEqual(guardStore.admit(voice, bridgeActive: true), .accepted)
    XCTAssertEqual(guardStore.admit(voice, bridgeActive: true), .duplicate)
    XCTAssertEqual(guardStore.admit(voice, bridgeActive: false), .paused)
  }

  func testSameMessageIDInSeparateConversationsDoesNotCollide() {
    var guardStore = ClawWeChatLocalInboxGuard()
    let one = ClawWeChatLocalMessage(messageID: "m", conversationID: "c1", senderID: "u", kind: .text, text: "hello")
    let two = ClawWeChatLocalMessage(messageID: "m", conversationID: "c2", senderID: "u", kind: .text, text: "hello")
    XCTAssertEqual(guardStore.admit(one, bridgeActive: true), .accepted)
    XCTAssertEqual(guardStore.admit(two, bridgeActive: true), .accepted)
  }

  func testBoundedDedupRetentionAndSafeReplay() {
    var guardStore = ClawWeChatLocalInboxGuard(capacity: 2)
    func message(_ id: String) -> ClawWeChatLocalMessage {
      ClawWeChatLocalMessage(messageID: id, conversationID: "c", senderID: "u", kind: .text, text: "x")
    }
    XCTAssertEqual(guardStore.admit(message("1"), bridgeActive: true), .accepted)
    XCTAssertEqual(guardStore.admit(message("2"), bridgeActive: true), .accepted)
    XCTAssertEqual(guardStore.admit(message("3"), bridgeActive: true), .accepted)
    XCTAssertEqual(guardStore.admit(message("2"), bridgeActive: true), .duplicate)
    XCTAssertEqual(guardStore.admit(message("1"), bridgeActive: true), .accepted)
  }
}
