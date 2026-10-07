import Foundation
import HamsterKeyboardKit
import HamsterKit

public enum SmartFreqApplyError: LocalizedError {
  case noAcceptedPhrases
  case noSelectedSchema
  case invalidSchemaIdentifier
  case noSnapshot

  public var errorDescription: String? {
    switch self {
    case .noAcceptedPhrases: return "没有已通过校验的词条可应用"
    case .noSelectedSchema: return "请先选择一个输入方案"
    case .invalidSchemaIdentifier: return "输入方案标识不安全，已停止写入"
    case .noSnapshot: return "没有可回滚的 SmartFreq 快照"
    }
  }
}

public struct SmartFreqApplySummary: Equatable, Sendable {
  public let schemaNames: [String]
  public let phraseCount: Int
  public let rolledBack: Bool

  public init(schemaNames: [String], phraseCount: Int, rolledBack: Bool) {
    self.schemaNames = schemaNames
    self.phraseCount = phraseCount
    self.rolledBack = rolledBack
  }
}

/// Owns the reversible host-app transition from validated drafts to deployed RIME data.
@MainActor
public final class SmartFreqApplyService {
  public static let shared = SmartFreqApplyService()

  private struct SnapshotManifest: Codable {
    let schemaIDs: [String]
    let phraseExisted: Bool
    let customFilesExisted: [String: Bool]
  }

  private let fileManager: FileManager
  private let container: HamsterAppDependencyContainer

  public init(
    fileManager: FileManager = .default,
    container: HamsterAppDependencyContainer = .shared
  ) {
    self.fileManager = fileManager
    self.container = container
  }

  public var canRollback: Bool {
    fileManager.fileExists(atPath: snapshotManifestURL.path)
  }

  public func apply() throws -> SmartFreqApplySummary {
    let source = SmartFreqService.phrasesFileURL
    let phrases = SmartFreqService.shared.loadAcceptedPhrases(from: source)
    guard !phrases.isEmpty else { throw SmartFreqApplyError.noAcceptedPhrases }

    let schemas = container.rimeContext.selectSchemas
    guard !schemas.isEmpty else { throw SmartFreqApplyError.noSelectedSchema }
    try schemas.forEach { try validate(schemaID: $0.schemaId) }

    var configuration = HamsterConfigurationStore.shared.configuration
    let cloudWasEnabled = configuration.general?.enableAppleCloud == true
    if cloudWasEnabled {
      _ = URL.iCloudDocumentURL
      try? FileManager.copyAppleCloudSharedSupportDirectoryToSandbox()
      try? FileManager.copyAppleCloudUserDataDirectoryToSandbox()
      configuration.general?.enableAppleCloud = false
    }

    try createSnapshot(schemaIDs: schemas.map(\.schemaId))
    do {
      try fileManager.createDirectory(at: FileManager.sandboxUserDataDirectory, withIntermediateDirectories: true)
      try replaceFile(at: sandboxPhraseURL, with: source)
      for schema in schemas {
        let customURL = schemaCustomURL(schema.schemaId)
        let existing = try? String(contentsOf: customURL, encoding: .utf8)
        let patched = try SmartFreqValidator.schemaPatchYAML(existing: existing)
        try patched.write(to: customURL, atomically: true, encoding: .utf8)
      }
      try container.rimeContext.deployment(configuration: &configuration, forceFullCheck: true)
      if cloudWasEnabled { configuration.general?.enableAppleCloud = true }
      HamsterConfigurationStore.shared.configuration = configuration
    } catch {
      try? restoreSnapshot(deploy: false)
      throw error
    }

    return SmartFreqApplySummary(
      schemaNames: schemas.map(\.schemaName),
      phraseCount: phrases.count,
      rolledBack: false
    )
  }

  public func rollback() throws -> SmartFreqApplySummary {
    let manifest = try restoreSnapshot(deploy: true)
    let namesByID = Dictionary(uniqueKeysWithValues: container.rimeContext.schemas.map { ($0.schemaId, $0.schemaName) })
    return SmartFreqApplySummary(
      schemaNames: manifest.schemaIDs.map { namesByID[$0] ?? $0 },
      phraseCount: 0,
      rolledBack: true
    )
  }

  private var snapshotDirectory: URL {
    FileManager.sandboxBackupDirectory.appendingPathComponent("SmartFreq/latest", isDirectory: true)
  }

  private var snapshotManifestURL: URL { snapshotDirectory.appendingPathComponent("manifest.json") }
  private var sandboxPhraseURL: URL { FileManager.sandboxUserDataDirectory.appendingPathComponent("claw_smart_freq.txt") }

  private func schemaCustomURL(_ schemaID: String) -> URL {
    FileManager.sandboxUserDataDirectory.appendingPathComponent("\(schemaID).custom.yaml")
  }

  private func createSnapshot(schemaIDs: [String]) throws {
    if fileManager.fileExists(atPath: snapshotDirectory.path) {
      try fileManager.removeItem(at: snapshotDirectory)
    }
    try fileManager.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
    let phraseExisted = fileManager.fileExists(atPath: sandboxPhraseURL.path)
    if phraseExisted {
      try fileManager.copyItem(at: sandboxPhraseURL, to: snapshotDirectory.appendingPathComponent("claw_smart_freq.txt"))
    }
    var customFilesExisted: [String: Bool] = [:]
    for schemaID in schemaIDs {
      let source = schemaCustomURL(schemaID)
      let existed = fileManager.fileExists(atPath: source.path)
      customFilesExisted[schemaID] = existed
      if existed {
        try fileManager.copyItem(at: source, to: snapshotDirectory.appendingPathComponent("\(schemaID).custom.yaml"))
      }
    }
    let manifest = SnapshotManifest(
      schemaIDs: schemaIDs,
      phraseExisted: phraseExisted,
      customFilesExisted: customFilesExisted
    )
    try JSONEncoder().encode(manifest).write(to: snapshotManifestURL, options: .atomic)
  }

  @discardableResult
  private func restoreSnapshot(deploy: Bool) throws -> SnapshotManifest {
    guard let data = try? Data(contentsOf: snapshotManifestURL),
          let manifest = try? JSONDecoder().decode(SnapshotManifest.self, from: data)
    else { throw SmartFreqApplyError.noSnapshot }

    try restore(
      destination: sandboxPhraseURL,
      backup: snapshotDirectory.appendingPathComponent("claw_smart_freq.txt"),
      existed: manifest.phraseExisted
    )
    for schemaID in manifest.schemaIDs {
      try restore(
        destination: schemaCustomURL(schemaID),
        backup: snapshotDirectory.appendingPathComponent("\(schemaID).custom.yaml"),
        existed: manifest.customFilesExisted[schemaID] == true
      )
    }
    if deploy {
      var configuration = HamsterConfigurationStore.shared.configuration
      let cloudWasEnabled = configuration.general?.enableAppleCloud == true
      if cloudWasEnabled { configuration.general?.enableAppleCloud = false }
      try container.rimeContext.deployment(configuration: &configuration, forceFullCheck: true)
      if cloudWasEnabled { configuration.general?.enableAppleCloud = true }
      HamsterConfigurationStore.shared.configuration = configuration
    }
    return manifest
  }

  private func restore(destination: URL, backup: URL, existed: Bool) throws {
    if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
    if existed { try fileManager.copyItem(at: backup, to: destination) }
  }

  private func replaceFile(at destination: URL, with source: URL) throws {
    if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
    try fileManager.copyItem(at: source, to: destination)
  }

  private func validate(schemaID: String) throws {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
    guard !schemaID.isEmpty, schemaID.unicodeScalars.allSatisfy(allowed.contains) else {
      throw SmartFreqApplyError.invalidSchemaIdentifier
    }
  }
}
