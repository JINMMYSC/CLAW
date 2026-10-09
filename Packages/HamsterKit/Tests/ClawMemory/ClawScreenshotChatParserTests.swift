import Foundation
import XCTest
@testable import HamsterKit

final class ClawScreenshotChatParserTests: XCTestCase {
  func testReversedOCRCallbackOrderStillProducesChronologicalMessages() {
    let capturedAt = Date(timeIntervalSince1970: 2_000_000_000)
    let lines: [VisionOCRService.OCRLine] = [
      .init(text: "第二句", boundingBox: .init(x: 0.10, y: 0.30, width: 0.25, height: 0.04), confidence: 0.99),
      .init(text: "聊天对象", boundingBox: .init(x: 0.35, y: 0.90, width: 0.30, height: 0.04), confidence: 0.99),
      .init(text: "第一句", boundingBox: .init(x: 0.10, y: 0.60, width: 0.25, height: 0.04), confidence: 0.99)
    ]
    let result = ClawScreenshotChatParser().parse(
      lines: lines, contactID: nil, contactName: "聊天对象", capturedAt: capturedAt
    )
    XCTAssertEqual(result.messages.map(\.content), ["第一句", "第二句"])
    XCTAssertLessThan(result.messages[0].occurredAt, result.messages[1].occurredAt)
    XCTAssertEqual(result.rawText, "聊天对象\n第一句\n第二句")
  }

  func testSameHeightOCRFragmentsReadLeftToRight() {
    let lines: [VisionOCRService.OCRLine] = [
      .init(text: "世界", boundingBox: .init(x: 0.27, y: 0.50, width: 0.12, height: 0.04), confidence: 0.98),
      .init(text: "你好", boundingBox: .init(x: 0.10, y: 0.50, width: 0.12, height: 0.04), confidence: 0.98)
    ]
    let result = ClawScreenshotChatParser().parse(lines: lines, contactID: nil, contactName: nil)
    XCTAssertEqual(result.messages.map(\.content), ["你好 世界"])
  }
}
