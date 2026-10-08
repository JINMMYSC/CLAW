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

  func testVisibleValueKeepsRightAlignedWithoutLabelsInterceptingTouches() {
    let cell = PullDownMenuCell(style: .default, reuseIdentifier: nil)

    XCTAssertEqual(cell.valueLabel.textAlignment, .right)
    XCTAssertFalse(cell.titleLabel.isUserInteractionEnabled)
    XCTAssertFalse(cell.valueLabel.isUserInteractionEnabled)
    XCTAssertTrue(cell.valueButton.isAccessibilityElement)
    XCTAssertFalse(cell.titleLabel.isAccessibilityElement)
    XCTAssertFalse(cell.valueLabel.isAccessibilityElement)
  }

  func testAccessibleMenuButtonDescribesSettingAndSelectedValue() {
    let cell = PullDownMenuCell(style: .default, reuseIdentifier: nil)
    cell.updateWithSettingItem(SettingItemModel(text: "候选文字方向", textValue: { "横向" }))
    cell.updateConfiguration(using: cell.configurationState)

    XCTAssertEqual(cell.valueButton.accessibilityLabel, "候选文字方向")
    XCTAssertEqual(cell.valueButton.accessibilityValue, "横向")
  }

  func testLongTitleAndValueDoNotOverlapInNarrowRow() {
    let cell = PullDownMenuCell(style: .default, reuseIdentifier: nil)
    cell.frame = CGRect(x: 0, y: 0, width: 240, height: 52)
    cell.updateWithSettingItem(
      SettingItemModel(
        text: "一个非常长的设置项目标题",
        textValue: { "一个同样非常长的当前选项值" }
      )
    )
    cell.updateConfiguration(using: cell.configurationState)
    cell.layoutIfNeeded()

    guard let valueLabel = cell.contentView.subviews
      .compactMap({ $0 as? UILabel })
      .first(where: { $0.accessibilityIdentifier == "PullDownMenuCell.valueLabel" })
    else {
      return XCTFail("Expected an independently constrained value label")
    }

    XCTAssertLessThanOrEqual(cell.titleLabel.frame.maxX, valueLabel.frame.minX)
    XCTAssertLessThan(valueLabel.frame.maxX, cell.contentView.bounds.maxX - 8)
    XCTAssertEqual(valueLabel.textAlignment, .right)
  }
}
