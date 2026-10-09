import XCTest
@testable import HamsterKit

final class ClawChatScrollPolicyTests: XCTestCase {
  func testFollowsNewMessagesOnlyAtBottomOutsideSearch() {
    XCTAssertTrue(ClawChatScrollPolicy.shouldFollow(isAtBottom: true, isSearching: false))
    XCTAssertFalse(ClawChatScrollPolicy.shouldFollow(isAtBottom: false, isSearching: false))
    XCTAssertFalse(ClawChatScrollPolicy.shouldFollow(isAtBottom: true, isSearching: true))
  }
}
