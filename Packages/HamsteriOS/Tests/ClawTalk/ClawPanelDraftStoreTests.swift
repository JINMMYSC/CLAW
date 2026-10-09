import Foundation
import XCTest
@testable import HamsterKeyboardKit

final class ClawPanelDraftStoreTests: XCTestCase {
  func testThreePanelsRetainIndependentDrafts() {
    var store = ClawPanelDraftStore()
    let person = UUID()
    for (tab, text) in [(0, "请帮我总结"), (1, "对方刚刚发来的消息"), (2, "把我的话写自然一点")] {
      store.save(text, for: .init(personID: person, tab: tab))
    }
    XCTAssertEqual(store.text(for: .init(personID: person, tab: 0)), "请帮我总结")
    XCTAssertEqual(store.text(for: .init(personID: person, tab: 1)), "对方刚刚发来的消息")
    XCTAssertEqual(store.text(for: .init(personID: person, tab: 2)), "把我的话写自然一点")
  }

  func testPersonDraftsNeverLeakIntoGlobalOrOtherPerson() {
    var store = ClawPanelDraftStore()
    let first = UUID(), second = UUID()
    store.save("只属于联系人A", for: .init(personID: first, tab: 1))
    XCTAssertEqual(store.text(for: .init(personID: second, tab: 1)), "")
    XCTAssertEqual(store.text(for: .init(personID: nil, tab: 1)), "")
    XCTAssertEqual(store.text(for: .init(personID: first, tab: 1)), "只属于联系人A")
  }

  func testEmptyTextClearsOnlyMatchingDraft() {
    var store = ClawPanelDraftStore()
    let person = UUID()
    store.save("AI 草稿", for: .init(personID: person, tab: 0))
    store.save("帮你回草稿", for: .init(personID: person, tab: 1))
    store.save("", for: .init(personID: person, tab: 0))
    XCTAssertEqual(store.text(for: .init(personID: person, tab: 0)), "")
    XCTAssertEqual(store.text(for: .init(personID: person, tab: 1)), "帮你回草稿")
  }

  func testInvalidHiddenPanelNeverSavesOrRestores() {
    var store = ClawPanelDraftStore()
    store.save("ignore", for: .init(personID: nil, tab: -1))
    XCTAssertEqual(store.text(for: .init(personID: nil, tab: -1)), "")
  }
}
