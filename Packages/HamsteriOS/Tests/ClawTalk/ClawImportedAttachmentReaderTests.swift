import XCTest
import UIKit
@testable import HamsteriOS

final class ClawImportedAttachmentReaderTests: XCTestCase {
  func testPlainTextIsBoundedWithoutLoadingTheWholeFile() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-attachment-\(UUID()).txt")
    defer { try? FileManager.default.removeItem(at: url) }
    try String(repeating: "甲", count: 9_000).write(to: url, atomically: true, encoding: .utf8)
    let text = ClawImportedAttachmentReader.readText(from: url, maxCharacters: 120)
    XCTAssertEqual(text, String(repeating: "甲", count: 120))
  }

  func testTextBearingPDFImportsItsReadableText() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-attachment-\(UUID()).pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 420, height: 320))
    let pdfData = renderer.pdfData { context in
      context.beginPage()
      ("CLAW PDF report content" as NSString).draw(
        at: CGPoint(x: 32, y: 30),
        withAttributes: [.font: UIFont.systemFont(ofSize: 17)]
      )
    }
    try pdfData.write(to: url)
    XCTAssertTrue(ClawImportedAttachmentReader.readText(from: url)?
      .contains("CLAW PDF report content") == true)
  }

  func testImageOnlyPDFDoesNotPretendToContainReadableText() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-attachment-\(UUID()).pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 420, height: 320))
    try renderer.pdfData { context in context.beginPage() }.write(to: url)
    XCTAssertNil(ClawImportedAttachmentReader.readText(from: url))
  }
}
