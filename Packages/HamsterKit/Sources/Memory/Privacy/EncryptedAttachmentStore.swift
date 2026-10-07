import CryptoKit
import Foundation

public enum EncryptedAttachmentStoreError: Error {
  case invalidSealedBox
}

public final class EncryptedAttachmentStore {
  private let root: URL
  private let keyProvider: () throws -> SymmetricKey
  private let fileManager: FileManager

  public init(
    root: URL,
    fileManager: FileManager = .default,
    keyProvider: @escaping () throws -> SymmetricKey
  ) {
    self.root = root
    self.fileManager = fileManager
    self.keyProvider = keyProvider
  }

  @discardableResult
  public func write(_ data: Data, id: UUID = UUID()) throws -> URL {
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let sealed = try AES.GCM.seal(data, using: keyProvider())
    guard let combined = sealed.combined else { throw EncryptedAttachmentStoreError.invalidSealedBox }
    let destination = root.appendingPathComponent(id.uuidString).appendingPathExtension("clawenc")
    try combined.write(to: destination, options: [.atomic, .completeFileProtection])
    return destination
  }

  public func read(from url: URL) throws -> Data {
    let combined = try Data(contentsOf: url)
    let box = try AES.GCM.SealedBox(combined: combined)
    return try AES.GCM.open(box, using: keyProvider())
  }

  public func remove(_ url: URL) throws {
    if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
  }
}

public struct MemoryAtRestMigrationReport: Equatable {
  public var protectedDatabase: Bool
  public var encryptedAttachments: Int
  public var skippedAttachments: Int
}

/// One-time migration for legacy plaintext files. SQLite receives iOS Data
/// Protection and attachments become independent AES-GCM envelopes.
public final class MemoryAtRestMigrator {
  private let fileManager: FileManager
  private let attachmentStore: EncryptedAttachmentStore

  public init(fileManager: FileManager = .default, attachmentStore: EncryptedAttachmentStore) {
    self.fileManager = fileManager
    self.attachmentStore = attachmentStore
  }

  public func migrate(databaseURL: URL?, legacyAttachmentRoot: URL) throws -> MemoryAtRestMigrationReport {
    var protected = false
    if let databaseURL, fileManager.fileExists(atPath: databaseURL.path) {
      try fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: databaseURL.path)
      protected = true
    }
    let files = (try? fileManager.contentsOfDirectory(at: legacyAttachmentRoot, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
    var encrypted = 0
    var skipped = 0
    for file in files {
      if file.pathExtension == "clawenc" { skipped += 1; continue }
      guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { skipped += 1; continue }
      let stableID = UUID(uuidString: file.deletingPathExtension().lastPathComponent) ?? UUID()
      _ = try attachmentStore.write(Data(contentsOf: file), id: stableID)
      try fileManager.removeItem(at: file)
      encrypted += 1
    }
    return .init(protectedDatabase: protected, encryptedAttachments: encrypted, skippedAttachments: skipped)
  }
}
