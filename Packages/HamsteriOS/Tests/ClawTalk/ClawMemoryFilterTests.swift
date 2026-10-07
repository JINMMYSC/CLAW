import XCTest
import HamsterKit

@testable import HamsteriOS

final class ClawMemoryFilterTests: XCTestCase {
  private let aliceID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
  private let bobID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

  func testFiltersByQueryAcrossContentAndSourceReference() {
    let items = [
      memory(content: "Alice prefers concise replies", sourceRef: "meeting-notes"),
      memory(content: "Bob likes coffee", sourceRef: "chat-import"),
    ]

    XCTAssertEqual(ClawMemoryFilter.apply(items, query: "concise").map(\.content), ["Alice prefers concise replies"])
    XCTAssertEqual(ClawMemoryFilter.apply(items, query: "CHAT-IMPORT").map(\.content), ["Bob likes coffee"])
  }

  func testFiltersByPersonSourceKindAndScopeTogether() {
    let matching = memory(
      kind: .relationship,
      scope: "contact",
      subjectID: aliceID,
      content: "Alice is a client",
      sourceType: "screenshot"
    )
    let items = [
      matching,
      memory(kind: .relationship, scope: "contact", subjectID: bobID, content: "Bob is a client", sourceType: "screenshot"),
      memory(kind: .fact, scope: "contact", subjectID: aliceID, content: "Alice prefers tea", sourceType: "manual"),
    ]

    let result = ClawMemoryFilter.apply(
      items,
      personID: aliceID,
      sourceType: "screenshot",
      kind: .relationship,
      scope: "contact"
    )

    XCTAssertEqual(result, [matching])
  }

  func testNilSelectionsLeaveCollectionUnfiltered() {
    let items = [memory(content: "one"), memory(content: "two")]
    XCTAssertEqual(ClawMemoryFilter.apply(items), items)
  }

  func testLockedProtectedMemoryDoesNotParticipateInTextSearch() {
    let secret = memory(content: "private launch code", sourceRef: "vault-note")
    let visible = memory(content: "public launch checklist")
    let items = [secret, visible]

    XCTAssertEqual(
      ClawMemoryFilter.apply(items, query: "launch", protectedIDs: [secret.id], includeProtectedContent: false),
      [visible]
    )
    XCTAssertEqual(
      ClawMemoryFilter.apply(items, query: "private", protectedIDs: [secret.id], includeProtectedContent: true),
      [secret]
    )
  }

  func testProtectedMemoryCanOnlyStayOpenWhileVaultIsUnlocked() {
    let secret = memory(content: "private")
    XCTAssertFalse(ClawMemoryVaultAccess.canOpen(secret, protectedIDs: [secret.id], isUnlocked: false))
    XCTAssertTrue(ClawMemoryVaultAccess.canOpen(secret, protectedIDs: [secret.id], isUnlocked: true))
    XCTAssertTrue(ClawMemoryVaultAccess.canOpen(memory(content: "public"), protectedIDs: [secret.id], isUnlocked: false))
  }

  private func memory(
    kind: ClawMemoryKind = .fact,
    scope: String = "global",
    subjectID: UUID? = nil,
    content: String,
    sourceType: String = "manual",
    sourceRef: String? = nil
  ) -> ClawMemoryItem {
    ClawMemoryItem(
      kind: kind,
      scope: scope,
      subjectID: subjectID,
      content: content,
      sourceType: sourceType,
      sourceRef: sourceRef
    )
  }
}
