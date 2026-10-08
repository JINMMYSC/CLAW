import XCTest

@testable import HamsterKeyboardKit

final class IOSNativeSystemMetricsTest: XCTestCase {
  func testTypographyDoesNotScaleWithPhoneWidth() {
    let compact = IOSNativeSystemMetrics(viewWidth: 375, safeAreaBottom: 0)
    let max = IOSNativeSystemMetrics(viewWidth: 430, safeAreaBottom: 0)
    XCTAssertEqual(compact.fontSize(22), 22, accuracy: 0.001)
    XCTAssertEqual(max.fontSize(22), 22, accuracy: 0.001)
  }

  func testPhoneWidthsStayInsideNativeEdges() {
    for width: CGFloat in [375, 390, 393, 402, 414, 430] {
      let metrics = IOSNativeSystemMetrics(viewWidth: width, safeAreaBottom: 0)
      XCTAssertGreaterThanOrEqual(metrics.x(IOSNativeDesign.paddingH), 3)
      XCTAssertLessThanOrEqual(
        metrics.x(IOSNativeDesign.width - IOSNativeDesign.paddingH),
        width - 3 + 0.01
      )
    }
  }

  func testSafeAreaUsesOnlyVisualBreathingSpace() {
    XCTAssertEqual(IOSNativeSystemMetrics(viewWidth: 390, safeAreaBottom: 0).bottomKeyInset, 0)
    XCTAssertEqual(IOSNativeSystemMetrics(viewWidth: 390, safeAreaBottom: 34).bottomKeyInset, 4)
  }
}
