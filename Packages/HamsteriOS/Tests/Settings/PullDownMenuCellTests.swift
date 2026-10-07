import UIKit
import XCTest

@testable import HamsteriOS

final class PullDownMenuCellTests: XCTestCase {
  func testMenuButtonCoversWholeContentRow() {
    let cell = PullDownMenuCell(style: .default, reuseIdentifier: nil)
    cell.frame = CGRect(x: 0, y: 0, width: 320, height: 52)
    cell.layoutIfNeeded()

    XCTAssertEqual(cell.valueButton.frame, cell.contentView.bounds)

    let leadingPoint = CGPoint(x: 4, y: cell.contentView.bounds.midY)
    XCTAssertTrue(cell.contentView.hitTest(leadingPoint, with: nil) === cell.valueButton)
  }

  func testMenuButtonKeepsValueRightAlignedWithoutTitleInterceptingTouches() {
    let cell = PullDownMenuCell(style: .default, reuseIdentifier: nil)

    XCTAssertEqual(cell.valueButton.contentHorizontalAlignment, .trailing)
    XCTAssertFalse(cell.titleLabel.isUserInteractionEnabled)
    XCTAssertTrue(cell.valueButton.isAccessibilityElement)
    XCTAssertFalse(cell.titleLabel.isAccessibilityElement)
  }

  func testAccessibleMenuButtonDescribesSettingAndSelectedValue() {
    let cell = PullDownMenuCell(style: .default, reuseIdentifier: nil)
    cell.updateWithSettingItem(SettingItemModel(text: "候选文字方向", textValue: { "横向" }))
    cell.updateConfiguration(using: cell.configurationState)

    XCTAssertEqual(cell.valueButton.accessibilityLabel, "候选文字方向")
    XCTAssertEqual(cell.valueButton.accessibilityValue, "横向")
  }
}
