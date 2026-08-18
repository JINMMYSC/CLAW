@testable import HamsterKit

import Foundation
import XCTest

final class FileManagerTest: XCTestCase {
  func testResolveAppGroupContainerUsesSharedContainerWhenAvailable() {
    let sharedURL = URL(fileURLWithPath: "/shared")
    let fallbackURL = URL(fileURLWithPath: "/fallback")

    XCTAssertEqual(
      FileManager.resolveAppGroupContainerURL(sharedURL, fallbackURL: fallbackURL),
      sharedURL
    )
  }

  func testResolveAppGroupContainerUsesFallbackWhenUnavailable() {
    let fallbackURL = URL(fileURLWithPath: "/fallback")

    XCTAssertEqual(
      FileManager.resolveAppGroupContainerURL(nil, fallbackURL: fallbackURL),
      fallbackURL
    )
  }
}
