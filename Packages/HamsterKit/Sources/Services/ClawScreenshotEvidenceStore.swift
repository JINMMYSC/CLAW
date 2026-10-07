import Foundation
import CryptoKit

/// Keeps selected screenshot bytes as optional local evidence while structured messages remain canonical.
public final class ClawScreenshotEvidenceStore {
  public static let shared = ClawScreenshotEvidenceStore()

  private let fileManager = FileManager.default
  private let keyAccount = "claw-attachment-key-v1"

  private var baseURL: URL {
    let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: HamsterConstants.appGroupName)
    let fallback = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    return (group ?? fallback)
      .appendingPathComponent("ClawMemory", isDirectory: true)
      .appendingPathComponent("Evidence", isDirectory: true)
  }

  private var encryptedURL: URL { baseURL.deletingLastPathComponent().appendingPathComponent("EncryptedEvidence", isDirectory: true) }
  private var encryptedStore: EncryptedAttachmentStore { EncryptedAttachmentStore(root: encryptedURL, keyProvider: attachmentKey) }

  public init() {
    try? fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
    try? fileManager.createDirectory(at: encryptedURL, withIntermediateDirectories: true)
    _ = try? MemoryAtRestMigrator(attachmentStore: encryptedStore).migrate(
      databaseURL: ClawMemoryStore.shared.databaseURL,
      legacyAttachmentRoot: baseURL
    )
  }

  /// Returns a stable sourceRef suitable for ClawConversationMessage / ClawMemoryItem.
  public func saveJPEG(_ data: Data) -> String? {
    guard !data.isEmpty else { return nil }
    let id = UUID().uuidString
    do {
      _ = try encryptedStore.write(data, id: UUID(uuidString: id)!)
      return "screenshot-evidence:\(id)"
    } catch {
      return nil
    }
  }

  public func url(for sourceRef: String) -> URL? {
    let prefix = "screenshot-evidence:"
    guard sourceRef.hasPrefix(prefix) else { return nil }
    let id = String(sourceRef.dropFirst(prefix.count))
    let url = encryptedURL.appendingPathComponent(id + ".clawenc")
    return fileManager.fileExists(atPath: url.path) ? url : nil
  }

  public func data(for sourceRef: String) -> Data? {
    guard let url = url(for: sourceRef) else { return nil }
    return try? encryptedStore.read(from: url)
  }

  public func materializeForExport(_ sourceRef: String) -> URL? {
    guard let data = data(for: sourceRef) else { return nil }
    let id = String(sourceRef.dropFirst("screenshot-evidence:".count))
    let url = fileManager.temporaryDirectory.appendingPathComponent(id + ".jpg")
    do { try data.write(to: url, options: [.atomic, .completeFileProtection]); return url } catch { return nil }
  }

  public func importAttachment(name: String, data: Data) throws {
    guard let id = UUID(uuidString: URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent) else { return }
    _ = try encryptedStore.write(data, id: id)
  }

  private func attachmentKey() throws -> SymmetricKey {
    if let saved = try ClawSecureStore.shared.string(for: keyAccount), let data = Data(base64Encoded: saved) {
      return SymmetricKey(data: data)
    }
    let key = SymmetricKey(size: .bits256)
    let data = key.withUnsafeBytes { Data($0) }
    try ClawSecureStore.shared.setString(data.base64EncodedString(), for: keyAccount)
    return key
  }
}

