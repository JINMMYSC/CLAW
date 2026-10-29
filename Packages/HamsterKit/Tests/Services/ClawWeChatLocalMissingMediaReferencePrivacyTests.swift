import Foundation
import XCTest
@testable import HamsterKit

private actor MissingMediaReferenceTransport: ClawWeChatLocalTransport {
  let message: ClawWeChatLocalMessage
  private var downloads = 0
  private var sends = 0

  init(message: ClawWeChatLocalMessage) { self.message = message }

  func fetch(after cursor: String?) async throws -> ClawWeChatLocalBatch {
    ClawWeChatLocalBatch(messages: [message], nextCursor: "after-invalid-media")
  }

  func downloadMedia(reference: String, maximumBytes: Int) async throws -> Data {
    downloads += 1
    return Data([1])
  }

  func sendText(_ text: String, conversationID: String) async throws { sends += 1 }

  func activity() -> (downloads: Int, sends: Int) { (downloads, sends) }
}

private actor MissingMediaReferenceProcessor: ClawWeChatLocalMessageProcessor {
  private var calls = 0

  func makeReply(to message: ClawWeChatLocalMessage, media: Data?) async throws -> String? {
    calls += 1
    return "unapproved reply"
  }

  func callCount() -> Int { calls }
}

final class ClawWeChatLocalMissingMediaReferencePrivacyTests: XCTestCase {
  func testMissingOrBlankMediaReferenceFailsWithoutProcessingOrAcknowledging() async throws {
    for (kind, reference) in [
      (ClawWeChatLocalMessageKind.image, Optional<String>.none),
      (.voice, Optional(" \t "))
    ] {
      let message = ClawWeChatLocalMessage(
        messageID: UUID().uuidString, conversationID: "approved-chat",
        senderID: "owner", kind: kind, mediaReference: reference
      )
      let transport = MissingMediaReferenceTransport(message: message)
      let processor = MissingMediaReferenceProcessor()
      let pump = ClawWeChatLocalPump(
        transport: transport, processor: processor,
        allowedSenderID: "owner", allowedConversationID: "approved-chat"
      )
      await pump.setConnection(.active)

      do {
        _ = try await pump.pollOnce(
          hostForeground: true, keyboardVisible: false, keyboardFullAccess: false
        )
        XCTFail("Invalid media references must be rejected before any processing")
      } catch ClawWeChatLocalPumpError.invalidMediaReference { }

      let activity = await transport.activity()
      let processed = await processor.callCount()
      let cursor = await pump.lastCursor()
      XCTAssertEqual(activity.downloads, 0)
      XCTAssertEqual(activity.sends, 0)
      XCTAssertEqual(processed, 0)
      XCTAssertNil(cursor)
    }
  }
}
