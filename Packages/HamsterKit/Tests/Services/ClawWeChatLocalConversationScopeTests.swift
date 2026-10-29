import XCTest
@testable import HamsterKit

private actor ConversationScopeTransport: ClawWeChatLocalTransport {
  private let messages: [ClawWeChatLocalMessage]
  private var downloads: [String] = []
  private var sent: [String] = []

  init(messages: [ClawWeChatLocalMessage]) {
    self.messages = messages
  }

  func fetch(after cursor: String?) async throws -> ClawWeChatLocalBatch {
    ClawWeChatLocalBatch(messages: messages, nextCursor: "next-page")
  }

  func downloadMedia(reference: String, maximumBytes: Int) async throws -> Data {
    downloads.append(reference)
    return Data([1])
  }

  func sendText(_ text: String, conversationID: String) async throws {
    sent.append("\(conversationID):\(text)")
  }

  func downloadedReferences() -> [String] { downloads }
  func sentMessages() -> [String] { sent }
}

private actor ConversationScopeProcessor: ClawWeChatLocalMessageProcessor {
  private var processedIDs: [String] = []

  func makeReply(to message: ClawWeChatLocalMessage, media: Data?) async throws -> String? {
    processedIDs.append(message.messageID)
    return "reply"
  }

  func processedMessageIDs() -> [String] { processedIDs }
}

final class ClawWeChatLocalConversationScopeTests: XCTestCase {
  func testBlankAuthorizationScopeCannotStartPollingOrSend() async throws {
    for (senderID, conversationID) in [
      ("", "approved-chat"),
      ("owner", ""),
      ("  ", "approved-chat"),
      ("owner", "\t")
    ] {
      let transport = ConversationScopeTransport(messages: [
        ClawWeChatLocalMessage(
          messageID: "empty-scope", conversationID: conversationID,
          senderID: senderID, kind: .text, text: "private message"
        )
      ])
      let processor = ConversationScopeProcessor()
      let pump = ClawWeChatLocalPump(
        transport: transport, processor: processor,
        allowedSenderID: senderID, allowedConversationID: conversationID
      )
      await pump.setConnection(.active)

      do {
        _ = try await pump.pollOnce(
          hostForeground: true, keyboardVisible: false, keyboardFullAccess: false
        )
        XCTFail("Blank authorization IDs must not permit a poll")
      } catch ClawWeChatLocalPumpError.notRunning { }

      let processed = await processor.processedMessageIDs()
      let sent = await transport.sentMessages()
      XCTAssertTrue(processed.isEmpty)
      XCTAssertTrue(sent.isEmpty)
    }
  }

  func testOwnerMessagesFromAnotherConversationNeverReachMediaOrAI() async throws {
    let transport = ConversationScopeTransport(messages: [
      ClawWeChatLocalMessage(
        messageID: "foreign-text", conversationID: "other-chat", senderID: "owner",
        kind: .text, text: "private text"
      ),
      ClawWeChatLocalMessage(
        messageID: "foreign-image", conversationID: "other-chat", senderID: "owner",
        kind: .image, mediaReference: "private-media"
      )
    ])
    let processor = ConversationScopeProcessor()
    let pump = ClawWeChatLocalPump(
      transport: transport,
      processor: processor,
      allowedSenderID: "owner",
      allowedConversationID: "approved-chat"
    )
    await pump.setConnection(.active)

    let handled = try await pump.pollOnce(
      hostForeground: true, keyboardVisible: false, keyboardFullAccess: false
    )

    let downloads = await transport.downloadedReferences()
    let processed = await processor.processedMessageIDs()
    let sent = await transport.sentMessages()
    let cursor = await pump.lastCursor()
    XCTAssertEqual(handled, 0)
    XCTAssertTrue(downloads.isEmpty)
    XCTAssertTrue(processed.isEmpty)
    XCTAssertTrue(sent.isEmpty)
    XCTAssertEqual(cursor, "next-page", "Ignored foreign conversations must not stall cursor progress.")
  }
}
