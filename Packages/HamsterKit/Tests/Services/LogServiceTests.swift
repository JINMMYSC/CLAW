import XCTest
@testable import HamsterKit

final class LogServiceTests: XCTestCase {
  func testClawFailuresUseErrorLevelAndUnifiedTagWithoutSensitiveContext() throws {
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-log-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let logger = LogService(fileURL: fileURL)
    for failure in LogService.ClawFailure.allCases {
      logger.log(failure)
    }

    let deadline = Date().addingTimeInterval(2)
    while logger.entries().count < LogService.ClawFailure.allCases.count,
          Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }

    let entries = logger.entries()
    XCTAssertEqual(entries.count, LogService.ClawFailure.allCases.count)
    XCTAssertTrue(entries.allSatisfy { $0.contains("[ERROR] [CLAW]") })
    let expectedMessages: Set<String> = [
      "Voice authorization failed",
      "Voice recognizer unavailable",
      "Voice audio input unavailable",
      "Voice recognition failed",
      "Voice audio session start failed",
      "iCloud copy failed",
      "iCloud restore failed",
      "SmartFreq AI request failed",
    ]
    let messages = Set(entries.compactMap { $0.components(separatedBy: "[CLAW] ").last })
    XCTAssertEqual(messages, expectedMessages)

    let exported = logger.exportText()
    XCTAssertFalse(exported.contains("sk-secret-api-key"))
    XCTAssertFalse(exported.contains("这是用户完整识别内容"))
    XCTAssertFalse(exported.contains("用户输入记录"))
  }
}
