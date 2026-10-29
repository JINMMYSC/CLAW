import Foundation
import XCTest
@testable import HamsterKit

private actor ApprovalRevocationTransport: ClawWeChatLocalTransport {
  private var sent: [String] = []

  func fetch(after cursor: String?) async throws -> ClawWeChatLocalBatch {
    ClawWeChatLocalBatch(messages: [
      ClawWeChatLocalMessage(
        messageID: "revocation-case", conversationID: "approved-chat", senderID: "owner",
        kind: .text, text: "Help me reply"
      )
    ], nextCursor: "next-page")
  }

  func downloadMedia(reference: String, maximumBytes: Int) async throws -> Data { Data() }

  func sendText(_ text: String, conversationID: String) async throws {
    sent.append(text)
  }

  func sentMessages() -> [String] { sent }
}

private struct ApprovalRevocationProcessor: ClawWeChatLocalMessageProcessor {
  func makeReply(to message: ClawWeChatLocalMessage, media: Data?) async throws -> String? {
    "Proposed reply"
  }
}

private actor SuspendedSendApproval: ClawWeChatLocalSendApproval {
  private var pending: CheckedContinuation<Bool, Never>?
  private var enteredWaiter: CheckedContinuation<Void, Never>?

  func confirmSend(reply: String, to message: ClawWeChatLocalMessage) async -> Bool {
    await withCheckedContinuation { continuation in
      pending = continuation
      enteredWaiter?.resume()
      enteredWaiter = nil
    }
  }

  func waitUntilAsked() async {
    if pending != nil { return }
    await withCheckedContinuation { continuation in enteredWaiter = continuation }
  }

  func approve() {
    pending?.resume(returning: true)
    pending = nil
  }
}

final class ClawWeChatLocalApprovalRevocationTests: XCTestCase {
  func testPauseThenReactivateInvalidatesEarlierPendingSendApproval() async throws {
    let transport = ApprovalRevocationTransport()
    let approval = SuspendedSendApproval()
    let pump = ClawWeChatLocalPump(
      transport: transport, processor: ApprovalRevocationProcessor(),
      allowedSenderID: "owner", allowedConversationID: "approved-chat",
      sendApproval: approval
    )
    await pump.setConnection(.active)

    let poll = Task {
      try await pump.pollOnce(
        hostForeground: true, keyboardVisible: false, keyboardFullAccess: false
      )
    }
    await approval.waitUntilAsked()
    await pump.setConnection(.authorizedPaused)
    await pump.setConnection(.active)
    await approval.approve()

    do {
      _ = try await poll.value
      XCTFail("An old approval must not survive a pause/re-authorization cycle")
    } catch ClawWeChatLocalPumpError.notRunning { }

    let sent = await transport.sentMessages()
    let cursor = await pump.lastCursor()
    XCTAssertTrue(sent.isEmpty)
    XCTAssertNil(cursor)
  }
}
