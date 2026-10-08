import UIKit
import XCTest
@testable import HamsteriOS

final class ClawChatComposerTests: XCTestCase {
  func testEmptyBarHeightIs56AtCommonWidths() {
    for width in [320.0, 393.0, 430.0] {
      let bar = ClawChatComposerBar(frame: CGRect(x: 0, y: 0, width: width, height: 56))
      bar.configure(text: "", isSending: false, voiceActive: false, voiceWillCancel: false)
      bar.layoutIfNeeded()
      XCTAssertEqual(bar.preferredHeight, 56, accuracy: 0.5)
      XCTAssertEqual(bar.mode, .text)
    }
  }

  func testMultilineGrowsCapsAndReturnsToSingleLine() {
    let bar = ClawChatComposerBar(frame: CGRect(x: 0, y: 0, width: 393, height: 56))
    bar.layoutIfNeeded()
    bar.configure(text: "one\ntwo\nthree", isSending: false, voiceActive: false, voiceWillCancel: false)
    bar.layoutIfNeeded()
    XCTAssertGreaterThan(bar.preferredHeight, 56)
    bar.configure(text: Array(repeating: "text", count: 20).joined(separator: "\n"), isSending: false, voiceActive: false, voiceWillCancel: false)
    bar.layoutIfNeeded()
    XCTAssertLessThanOrEqual(bar.preferredHeight, ClawChatComposerBar.maximumHeight)
    bar.configure(text: "", isSending: false, voiceActive: false, voiceWillCancel: false)
    bar.layoutIfNeeded()
    XCTAssertEqual(bar.preferredHeight, 56, accuracy: 0.5)
  }

  func testVoiceModePreservesDraftButDisablesSend() {
    let bar = ClawChatComposerBar(frame: CGRect(x: 0, y: 0, width: 393, height: 56))
    bar.configure(text: "未发出的草稿", isSending: false, voiceActive: false, voiceWillCancel: false)
    XCTAssertTrue(bar.isSendVisible)
    bar.setMode(.voice)
    XCTAssertEqual(bar.mode, .voice)
    XCTAssertFalse(bar.isSendVisible)
    XCTAssertEqual(bar.textView.text, "未发出的草稿")
    bar.setMode(.text)
    XCTAssertTrue(bar.isSendVisible)
  }

  func testAccessoryToggleRestoresTextModeWithoutLosingDraft() {
    let bar = ClawChatComposerBar(frame: CGRect(x: 0, y: 0, width: 393, height: 56))
    bar.configure(text: "你好", isSending: false, voiceActive: false, voiceWillCancel: false)
    bar.setMode(.emoji)
    XCTAssertNotNil(bar.textView.inputView)
    bar.setMode(.text)
    XCTAssertNil(bar.textView.inputView)
    bar.setMode(.more)
    XCTAssertNotNil(bar.textView.inputView)
    bar.setMode(.text)
    XCTAssertEqual(bar.textView.text, "你好")
  }

  func testReturnSubmitsOnceAndVoiceModeNeverSubmitsHiddenDraft() {
    let bar = ClawChatComposerBar(frame: CGRect(x: 0, y: 0, width: 393, height: 56))
    bar.configure(text: "你好", isSending: false, voiceActive: false, voiceWillCancel: false)
    var sent: [String] = []
    bar.onSend = { sent.append($0) }
    XCTAssertFalse(bar.textView(bar.textView, shouldChangeTextIn: NSRange(location: 2, length: 0), replacementText: "\n"))
    XCTAssertEqual(sent, ["你好"])
    bar.setMode(.voice)
    XCTAssertFalse(bar.textView(bar.textView, shouldChangeTextIn: NSRange(location: 2, length: 0), replacementText: "\n"))
    XCTAssertEqual(sent, ["你好"])
  }

  func testAttachmentsRemainAccessibleWhileTypingWithoutReplacingDraft() {
    let bar = ClawChatComposerBar(frame: CGRect(x: 0, y: 0, width: 320, height: 56))
    bar.configure(text: "仍未发送的文字", isSending: false, voiceActive: false, voiceWillCancel: false)
    bar.layoutIfNeeded()
    let attachments = bar.subviews.compactMap { $0 as? UIStackView }
      .flatMap { $0.arrangedSubviews }
      .compactMap { $0 as? UIButton }
      .first(where: { $0.accessibilityIdentifier == "claw.composer.attachments" })
    XCTAssertNotNil(attachments, "Attachment action must remain visible when send is active")
    XCTAssertTrue(attachments?.isEnabled == true)
    XCTAssertFalse(attachments?.isHidden ?? true)
    // No UIApplicationMain runs in this unit-test target. Invoke the real
    // control action directly; sendActions would never reach its target.
    bar.toggleAttachments()
    XCTAssertEqual(bar.mode, .more)
    XCTAssertEqual(bar.textView.text, "仍未发送的文字")
    XCTAssertTrue(bar.isSendVisible)
  }

  func testNativeLayoutScreenshotAttachment() {
    let bar = ClawChatComposerBar(frame: CGRect(x: 0, y: 0, width: 393, height: 56))
    bar.configure(text: "你好，CLAW", isSending: false, voiceActive: false, voiceWillCancel: false)
    bar.layoutIfNeeded()
    let screenshot = UIGraphicsImageRenderer(size: bar.bounds.size).image { context in
      bar.layer.render(in: context.cgContext)
    }
    let attachment = XCTAttachment(image: screenshot)
    attachment.name = "claw-composer-393-text"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
