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
