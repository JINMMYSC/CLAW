import Foundation

/// Keeps selected screenshot bytes as optional local evidence while structured messages remain canonical.
public final class ClawScreenshotEvidenceStore {
  public static let shared = ClawScreenshotEvidenceStore()

  private let fileManager = FileManager.default

  private var baseURL: URL {
    let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: HamsterConstants.appGroupName)
    let fallback = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    return (group ?? fallback)
      .appendingPathComponent("ClawMemory", isDirectory: true)
      .appendingPathComponent("Evidence", isDirectory: true)
  }

  public init() {
    try? fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
  }

  /// Returns a stable sourceRef suitable for ClawConversationMessage / ClawMemoryItem.
  public func saveJPEG(_ data: Data) -> String? {
    guard !data.isEmpty else { return nil }
    let id = UUID().uuidString
    let url = baseURL.appendingPathComponent(id + ".jpg")
    do {
      try data.write(to: url, options: .atomic)
      return "screenshot-evidence:\(id)"
    } catch {
      return nil
    }
  }

  public func url(for sourceRef: String) -> URL? {
    let prefix = "screenshot-evidence:"
    guard sourceRef.hasPrefix(prefix) else { return nil }
    let id = String(sourceRef.dropFirst(prefix.count))
    let url = baseURL.appendingPathComponent(id + ".jpg")
    return fileManager.fileExists(atPath: url.path) ? url : nil
  }
}

