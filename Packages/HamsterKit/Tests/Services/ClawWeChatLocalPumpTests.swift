import Foundation
import XCTest
@testable import HamsterKit

private actor FakeWeChatTransport: ClawWeChatLocalTransport {
  var messages: [ClawWeChatLocalMessage] = []
  var sendFailures = 0
  var downloaded: [String] = []
  var sent: [String] = []
  var cursors: [String?] = []

  func setMessages(_ value: [ClawWeChatLocalMessage]) { messages = value }
  func failNextSend() { sendFailures += 1 }
  func fetch(after cursor: String?) async throws -> ClawWeChatLocalBatch {
    cursors.append(cursor)
    return ClawWeChatLocalBatch(messages: messages, nextCursor: "next-page")
  }
  func downloadMedia(reference: String) async throws -> Data {
    downloaded.append(reference)
    return Data(repeating: 1, count: 8)
  }
  func sendText(_ text: String, conversationID: String) async throws {
    if sendFailures > 0 {
      sendFailures -= 1
      throw URLError(.timedOut)
    }
    sent.append(conversationID + ":" + text)
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
}
