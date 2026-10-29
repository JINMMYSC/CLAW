import Foundation
import XCTest
@testable import HamsterKit

private actor SendApprovalTransport: ClawWeChatLocalTransport {
  private var sent: [String] = []

  func fetch(after cursor: String?) async throws -> ClawWeChatLocalBatch {
    ClawWeChatLocalBatch(messages: [
      ClawWeChatLocalMessage(
        messageID: "approval-case", conversationID: "approved-chat", senderID: "owner",
        kind: .text, text: "Please help draft a reply"
      )
    ], nextCursor: "next-page")
  }

  func downloadMedia(reference: String, maximumBytes: Int) async throws -> Data { Data() }

  func sendText(_ text: String, conversationID: String) async throws {
    sent.append("\(conversationID):\(text)")
  }

  func sentMessages() -> [String] { sent }
}

private struct SendApprovalProcessor: ClawWeChatLocalMessageProcessor {
  func makeReply(to message: ClawWeChatLocalMessage, media: Data?) async throws -> String? {
    "AI draft, not user-confirmed"
  }
}

private actor SendApprovalDecision: ClawWeChatLocalSendApproval {
  let approved: Bool
  private var requests: [String] = []

  init(approved: Bool) { self.approved = approved }

  func confirmSend(reply: String, to message: ClawWeChatLocalMessage) async -> Bool {
    requests.append("\(message.conversationID):\(reply)")
    return approved
  }

  func requestedReplies() -> [String] { requests }
}

final class ClawWeChatLocalSendApprovalTests: XCTestCase {
  private func makePump(
    transport: SendApprovalTransport,
    approval: ClawWeChatLocalSendApproval? = nil
  ) -> ClawWeChatLocalPump {
    ClawWeChatLocalPump(
      transport: transport, processor: SendApprovalProcessor(),
      allowedSenderID: "owner", allowedConversationID: "approved-chat",
      sendApproval: approval
    )
  }

  func testDefaultWithoutExplicitApprovalNeverSendsGeneratedReply() async throws {
    let transport = SendApprovalTransport()
    let pump = makePump(transport: transport)
    await pump.setConnection(.active)

    let handled = try await pump.pollOnce(
      hostForeground: true, keyboardVisible: false, keyboardFullAccess: false
    )

    XCTAssertEqual(handled, 1)
    let sent = await transport.sentMessages()
    XCTAssertTrue(sent.isEmpty, "Generating a reply must not grant permission to send it")
  }

  func testExplicitReplyApprovalAllowsOnlyThatReplyToSend() async throws {
    let transport = SendApprovalTransport()
    let approval = SendApprovalDecision(approved: true)
    let pump = makePump(transport: transport, approval: approval)
    await pump.setConnection(.active)

    _ = try await pump.pollOnce(
      hostForeground: true, keyboardVisible: false, keyboardFullAccess: false
    )

    let requests = await approval.requestedReplies()
    let sent = await transport.sentMessages()
    XCTAssertEqual(requests, ["approved-chat:AI draft, not user-confirmed"])
    XCTAssertEqual(sent, ["approved-chat:AI draft, not user-confirmed"])
  }

  func testExplicitRejectionNeverSendsGeneratedReply() async throws {
    let transport = SendApprovalTransport()
    let approval = SendApprovalDecision(approved: false)
    let pump = makePump(transport: transport, approval: approval)
    await pump.setConnection(.active)

    _ = try await pump.pollOnce(
      hostForeground: true, keyboardVisible: false, keyboardFullAccess: false
    )

    let requests = await approval.requestedReplies()
    let sent = await transport.sentMessages()
    XCTAssertEqual(requests.count, 1)
    XCTAssertTrue(sent.isEmpty)
  }
}
