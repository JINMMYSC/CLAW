import Foundation
import XCTest
@testable import HamsterKit

private actor FakeWeChatTransport: ClawWeChatLocalTransport {
  var messages: [ClawWeChatLocalMessage] = []
  var sendFailures = 0
  var ackLostFailures = 0
  var deliveredKeys: Set<String> = []
  var attemptedKeys: [String] = []
  var downloaded: [String] = []
  var sent: [String] = []
  var cursors: [String?] = []
  var mediaSize = 8
  var fetchHook: (() async -> Void)?
  var downloadHook: (() async -> Void)?
  var maxDownloadBytes: [Int] = []

  func setMessages(_ value: [ClawWeChatLocalMessage]) { messages = value }
  func setFetchHook(_ hook: (() async -> Void)?) { fetchHook = hook }
  func setDownloadHook(_ hook: (() async -> Void)?) { downloadHook = hook }
  func setMediaSize(_ size: Int) { mediaSize = size }
  func downloadLimits() -> [Int] { maxDownloadBytes }
  func failNextSend() { sendFailures += 1 }
  func acceptThenLoseAcknowledgement() { ackLostFailures += 1 }
  func sendAttempts() -> [String] { attemptedKeys }
  func fetch(after cursor: String?) async throws -> ClawWeChatLocalBatch {
    cursors.append(cursor)
    if let fetchHook { await fetchHook() }
    return ClawWeChatLocalBatch(messages: messages, nextCursor: "next-page")
  }
  func downloadMedia(reference: String, maximumBytes: Int) async throws -> Data {
    downloaded.append(reference)
    maxDownloadBytes.append(maximumBytes)
    if let downloadHook { await downloadHook() }
    guard mediaSize <= maximumBytes else { throw ClawWeChatLocalPumpError.mediaTooLarge }
    return Data(repeating: 1, count: mediaSize)
  }
  func sendText(_ text: String, conversationID: String, idempotencyKey: String) async throws {
    attemptedKeys.append(idempotencyKey)
    if sendFailures > 0 {
      sendFailures -= 1
      throw URLError(.timedOut)
    }
    if deliveredKeys.insert(idempotencyKey).inserted {
      sent.append(conversationID + ":" + text)
    }
    if ackLostFailures > 0 {
      ackLostFailures -= 1
      throw URLError(.timedOut)
    }
  }
  func sentMessages() -> [String] { sent }
  func downloadedMedia() -> [String] { downloaded }
  func fetchedCursors() -> [String?] { cursors }
}

private actor FakeWeChatProcessor: ClawWeChatLocalMessageProcessor {
  var processed: [ClawWeChatLocalMessageKind] = []
  func makeReply(to message: ClawWeChatLocalMessage, media: Data?) async throws -> String? {
    if message.kind != .text && media == nil { throw URLError(.cannotDecodeContentData) }
    processed.append(message.kind)
    return "已处理"
  }
  func processedKinds() -> [ClawWeChatLocalMessageKind] { processed }
}

final class ClawWeChatLocalPumpTests: XCTestCase {
  private func message(
    _ id: String,
    kind: ClawWeChatLocalMessageKind,
    sender: String = "owner"
  ) -> ClawWeChatLocalMessage {
    ClawWeChatLocalMessage(
      messageID: id, conversationID: "chat", senderID: sender,
      kind: kind, text: kind == .text ? "问 CLAW" : nil,
      mediaReference: kind == .text ? nil : "opaque-\(id)"
    )
  }

  func testTextImageAndVoiceEachGetProcessedAndRepliedOnce() async throws {
    let transport = FakeWeChatTransport(), processor = FakeWeChatProcessor()
    await transport.setMessages([
      message("a", kind: .text),
      message("b", kind: .image),
      message("c", kind: .voice)
    ])
    let pump = ClawWeChatLocalPump(transport: transport, processor: processor, allowedSenderID: "owner")
    await pump.setConnection(.active)
    let first = try await pump.pollOnce(hostForeground: true, keyboardVisible: false, keyboardFullAccess: false)
    XCTAssertEqual(first, 3)
    let downloads = await transport.downloadedMedia()
    let sentAfterFirst = await transport.sentMessages()
    let kinds = await processor.processedKinds()
    XCTAssertEqual(downloads, ["opaque-b", "opaque-c"])
    let limits = await transport.downloadLimits()
    XCTAssertEqual(limits, [12 * 1024 * 1024, 12 * 1024 * 1024])
    XCTAssertEqual(sentAfterFirst.count, 3)
    XCTAssertEqual(kinds, [.text, .image, .voice])
    let second = try await pump.pollOnce(hostForeground: true, keyboardVisible: false, keyboardFullAccess: false)
    XCTAssertEqual(second, 0)
    let sentAfterSecond = await transport.sentMessages()
    let cursors = await transport.fetchedCursors()
    XCTAssertEqual(sentAfterSecond.count, 3)
    XCTAssertEqual(cursors.compactMap { $0 }.last, "next-page")
  }

  func testPausedKeyboardCannotPollAndUnknownSenderIsIgnored() async throws {
    let transport = FakeWeChatTransport(), processor = FakeWeChatProcessor()
    await transport.setMessages([message("x", kind: .text, sender: "stranger")])
    let pump = ClawWeChatLocalPump(transport: transport, processor: processor, allowedSenderID: "owner")
    await pump.setConnection(.active)
    do {
      _ = try await pump.pollOnce(hostForeground: false, keyboardVisible: true, keyboardFullAccess: false)
      XCTFail("Keyboard without full access must not poll")
    } catch ClawWeChatLocalPumpError.notRunning {}
    let count = try await pump.pollOnce(hostForeground: false, keyboardVisible: true, keyboardFullAccess: true)
    XCTAssertEqual(count, 0)
    let sent = await transport.sentMessages()
    XCTAssertTrue(sent.isEmpty)
  }

  func testFailedSendDoesNotAdvanceCursorAndRetryCanRecover() async throws {
    let transport = FakeWeChatTransport(), processor = FakeWeChatProcessor()
    await transport.setMessages([message("r", kind: .voice)])
    await transport.failNextSend()
    let pump = ClawWeChatLocalPump(transport: transport, processor: processor, allowedSenderID: "owner")
    await pump.setConnection(.active)
    do {
      _ = try await pump.pollOnce(hostForeground: true, keyboardVisible: false, keyboardFullAccess: false)
      XCTFail("Expected failure")
    } catch { }
    let cursorAfterFailure = await pump.lastCursor()
    XCTAssertNil(cursorAfterFailure)
    let count = try await pump.pollOnce(hostForeground: true, keyboardVisible: false, keyboardFullAccess: false)
    XCTAssertEqual(count, 1)
    let sent = await transport.sentMessages()
    XCTAssertEqual(sent.count, 1)
  }
  func testPauseDuringFetchLeavesCursorAndMessagesUntouched() async throws {
    let transport = FakeWeChatTransport(), processor = FakeWeChatProcessor()
    await transport.setMessages([message("pause", kind: .image)])
    let pump = ClawWeChatLocalPump(
      transport: transport, processor: processor, allowedSenderID: "owner"
    )
    await transport.setFetchHook {
      await pump.setConnection(.authorizedPaused)
    }
    await pump.setConnection(.active)
    do {
      _ = try await pump.pollOnce(hostForeground: true, keyboardVisible: false, keyboardFullAccess: false)
      XCTFail("A paused connection must not acknowledge a fetched batch")
    } catch ClawWeChatLocalPumpError.notRunning { }
    let pausedCursor = await pump.lastCursor()
    let sentWhilePaused = await transport.sentMessages()
    XCTAssertNil(pausedCursor)
    XCTAssertTrue(sentWhilePaused.isEmpty)

    await transport.setFetchHook(nil)
    await pump.setConnection(.active)
    let recovered = try await pump.pollOnce(
      hostForeground: true, keyboardVisible: false, keyboardFullAccess: false
    )
    XCTAssertEqual(recovered, 1)
    let sent = await transport.sentMessages()
    XCTAssertEqual(sent.count, 1)
  }

  func testOversizedImageIsRejectedWithoutAdvancingCursor() async throws {
    let transport = FakeWeChatTransport(), processor = FakeWeChatProcessor()
    await transport.setMessages([message("huge", kind: .image)])
    await transport.setMediaSize(32)
    let pump = ClawWeChatLocalPump(
      transport: transport, processor: processor, allowedSenderID: "owner", maximumMediaBytes: 16
    )
    await pump.setConnection(.active)
    do {
      _ = try await pump.pollOnce(hostForeground: true, keyboardVisible: false, keyboardFullAccess: false)
      XCTFail("Oversized media must be rejected")
    } catch ClawWeChatLocalPumpError.mediaTooLarge { }
    let cursor = await pump.lastCursor()
    let processed = await processor.processedKinds()
    XCTAssertNil(cursor)
    XCTAssertTrue(processed.isEmpty)
  }

  func testAcknowledgedSendWithLostResponseIsNotDuplicatedOnRetryOrRestart() async throws {
    let transport = FakeWeChatTransport(), processor = FakeWeChatProcessor()
    await transport.setMessages([message("lost-ack", kind: .voice)])
    await transport.acceptThenLoseAcknowledgement()
    let pump = ClawWeChatLocalPump(
      transport: transport, processor: processor, allowedSenderID: "owner"
    )
    await pump.setConnection(.active)
    do {
      _ = try await pump.pollOnce(
        hostForeground: true, keyboardVisible: false, keyboardFullAccess: false
      )
      XCTFail("Expected simulated lost acknowledgement")
    } catch { }
    let cursor = await pump.lastCursor()
    XCTAssertNil(cursor)
    let count = try await pump.pollOnce(
      hostForeground: true, keyboardVisible: false, keyboardFullAccess: false
    )
    XCTAssertEqual(count, 1)
    let restarted = ClawWeChatLocalPump(
      transport: transport, processor: processor, allowedSenderID: "owner"
    )
    await restarted.setConnection(.active)
    _ = try await restarted.pollOnce(
      hostForeground: true, keyboardVisible: false, keyboardFullAccess: false
    )
    let sent = await transport.sentMessages()
    let attempts = await transport.sendAttempts()
    XCTAssertEqual(sent.count, 1)
    XCTAssertEqual(attempts.count, 3)
    XCTAssertEqual(Set(attempts).count, 1)
  }

  func testRevokedConnectionDuringMediaDownloadDoesNotInvokeAIOrSend() async throws {
    let transport = FakeWeChatTransport(), processor = FakeWeChatProcessor()
    await transport.setMessages([message("revoked", kind: .image)])
    let pump = ClawWeChatLocalPump(
      transport: transport, processor: processor, allowedSenderID: "owner"
    )
    await transport.setDownloadHook {
      await pump.setConnection(.expired)
    }
    await pump.setConnection(.active)
    do {
      _ = try await pump.pollOnce(
        hostForeground: true, keyboardVisible: false, keyboardFullAccess: false
      )
      XCTFail("A revoked connection must not process downloaded media")
    } catch ClawWeChatLocalPumpError.notRunning { }
    let processed = await processor.processedKinds()
    let sent = await transport.sentMessages()
    let cursor = await pump.lastCursor()
    XCTAssertTrue(processed.isEmpty)
    XCTAssertTrue(sent.isEmpty)
    XCTAssertNil(cursor)
  }

}
