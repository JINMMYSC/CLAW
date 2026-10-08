import XCTest
@testable import HamsterKit

final class ClawChatServiceTests: XCTestCase {
  func testMessageTraceRoundTripsAndLegacyHistoryStillDecodes() throws {
    let requestID = UUID()
    let message = ClawChatMessage(
      role: "assistant",
      content: "完成",
      trace: ClawChatTrace(
        requestID: requestID,
        provider: "OpenAI",
        model: "gpt-test",
        regenerated: true
      )
    )

    let decoded = try JSONDecoder().decode(
      ClawChatMessage.self,
      from: JSONEncoder().encode(message)
    )
    XCTAssertEqual(decoded.trace?.requestID, requestID)
    XCTAssertEqual(decoded.trace?.model, "gpt-test")
    XCTAssertEqual(decoded.trace?.regenerated, true)

    let legacy = """
    {"id":"00000000-0000-0000-0000-000000000001","role":"assistant","content":"旧消息","date":0}
    """.data(using: .utf8)!
    let legacyDecoded = try JSONDecoder().decode(ClawChatMessage.self, from: legacy)
    XCTAssertNil(legacyDecoded.trace)
    XCTAssertFalse(legacyDecoded.excludeFromContext)
  }
}
