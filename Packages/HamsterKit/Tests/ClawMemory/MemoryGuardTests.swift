import CryptoKit
import XCTest
@testable import HamsterKit

final class MemoryGuardTests: XCTestCase {
  func testGuardEnforcesCloudAndPersonScopesBeforeRedactingPII() {
    let person = UUID()
    let other = UUID()
    let allowed = record(content: "联系 me@example.com 或 13800138000", personID: person)
    let privateRecord = record(content: "本机", permission: .localOnly)
    let unrelated = record(content: "另一个人", personID: other)

    let decision = MemoryGuard().evaluate(
      [allowed, privateRecord, unrelated],
      personID: person,
      temporaryMode: false
    )

    XCTAssertEqual(decision.allowed.map(\.id), [allowed.id])
    XCTAssertEqual(decision.allowed[0].content, "联系 [邮箱已隐藏] 或 [手机号已隐藏]")
    XCTAssertEqual(decision.rejected[privateRecord.id], .localOnly)
    XCTAssertEqual(decision.rejected[unrelated.id], .wrongPerson)
  }

  func testTemporaryModeRejectsEveryRecord() {
    let value = record(content: "普通记忆")
    let decision = MemoryGuard().evaluate([value], temporaryMode: true)
    XCTAssertTrue(decision.allowed.isEmpty)
    XCTAssertEqual(decision.rejected[value.id], .temporaryMode)
  }

  func testEncryptedAttachmentRoundTripAndWrongKeyFails() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("encrypted-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let key = SymmetricKey(size: .bits256)
    let store = EncryptedAttachmentStore(root: root, keyProvider: { key })
    let url = try store.write(Data("secret".utf8))
    XCTAssertEqual(try store.read(from: url), Data("secret".utf8))

    let wrongStore = EncryptedAttachmentStore(root: root, keyProvider: { SymmetricKey(size: .bits256) })
    XCTAssertThrowsError(try wrongStore.read(from: url))
  }

  func testAtRestMigrationEncryptsAndDeletesLegacyAttachment() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID())")
    let legacy = root.appendingPathComponent("legacy", isDirectory: true)
    let encrypted = root.appendingPathComponent("encrypted", isDirectory: true)
    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = legacy.appendingPathComponent("photo.jpg")
    try Data("private-image".utf8).write(to: source)
    let store = EncryptedAttachmentStore(root: encrypted, keyProvider: { SymmetricKey(size: .bits256) })
    let report = try MemoryAtRestMigrator(attachmentStore: store).migrate(databaseURL: nil, legacyAttachmentRoot: legacy)
    XCTAssertEqual(report.encryptedAttachments, 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: encrypted, includingPropertiesForKeys: nil).first?.pathExtension, "clawenc")
  }

  private func record(
    content: String,
    personID: UUID? = nil,
    permission: MemoryCloudPermission = .aiAllowed
  ) -> MemoryV2Record {
    MemoryV2Record(
      type: .semantic,
      state: .active,
      scope: personID == nil ? .global : .person,
      content: content,
      personID: personID,
      provenance: MemoryProvenance(originType: .userExplicit, ingestionMethod: "test"),
      cloudPermission: permission
    )
  }
}
