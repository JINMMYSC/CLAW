import CryptoKit
import Foundation
import ZIPFoundation

public struct ClawMemoryArchiveFile: Codable, Equatable, Sendable {
  public var path: String
  public var sha256: String
  public var byteCount: Int
  public var recordCount: Int?
}

public struct ClawMemoryArchiveManifestV2: Codable, Equatable, Sendable {
  public var format: String
  public var version: Int
  public var schemaVersion: Int
  public var exportedAt: Date
  public var files: [ClawMemoryArchiveFile]

  public init(exportedAt: Date, files: [ClawMemoryArchiveFile]) {
    self.format = "clawmemory"
    self.version = 2
    self.schemaVersion = MemorySchemaVersion.current
    self.exportedAt = exportedAt
    self.files = files
  }
}

public struct ClawMemoryArchiveSnapshot: Codable, Equatable {
  public var memories: [MemoryV2Record]
  public var rawEvents: [RawMemoryEvent]
  public var audits: [MemoryAuditRecord]
  public var attachments: [String: Data]

  public init(memories: [MemoryV2Record], rawEvents: [RawMemoryEvent], audits: [MemoryAuditRecord], attachments: [String: Data] = [:]) {
    self.memories = memories
    self.rawEvents = rawEvents
    self.audits = audits
    self.attachments = attachments
  }
}

public enum ClawMemoryArchiveV2Error: Error, Equatable {
  case missingManifest
  case unsupportedVersion(Int)
  case missingFile(String)
  case checksumMismatch(String)
  case unsafePath(String)
}

/// Builds and verifies the canonical V2 backup before any data reaches the store.
public struct ClawMemoryArchiveV2 {
  public init() {}

  public func export(snapshot: ClawMemoryArchiveSnapshot, attachments: [URL] = [], now: Date = Date()) throws -> URL {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("clawmemory-v2-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    let encoder = Self.encoder
    var files: [ClawMemoryArchiveFile] = []
    try add(encoder.encode(snapshot.memories), path: "memory/records.json", count: snapshot.memories.count, root: root, files: &files)
    try add(encoder.encode(snapshot.rawEvents), path: "memory/raw-events.json", count: snapshot.rawEvents.count, root: root, files: &files)
    try add(encoder.encode(snapshot.audits), path: "memory/audit.json", count: snapshot.audits.count, root: root, files: &files)
    let markdown = snapshot.memories.map { "- [\($0.type.rawValue)] \($0.content)" }.joined(separator: "\n") + "\n"
    try add(Data(markdown.utf8), path: "memory/README.md", count: snapshot.memories.count, root: root, files: &files)

    for source in attachments {
      let safeName = source.lastPathComponent.replacingOccurrences(of: "..", with: "_")
      try add(Data(contentsOf: source), path: "attachments/\(safeName)", count: nil, root: root, files: &files)
    }
    let manifest = ClawMemoryArchiveManifestV2(exportedAt: now, files: files.sorted { $0.path < $1.path })
    try encoder.encode(manifest).write(to: root.appendingPathComponent("manifest.json"), options: .atomic)

    let destination = fm.temporaryDirectory.appendingPathComponent("CLAW-Memory-\(Int(now.timeIntervalSince1970)).clawmemory")
    try? fm.removeItem(at: destination)
    try fm.zipItem(at: root, to: destination, shouldKeepParent: false)
    return destination
  }

  public func verifyAndDecode(_ archiveURL: URL) throws -> ClawMemoryArchiveSnapshot {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("clawmemory-verify-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    try fm.unzipItem(at: archiveURL, to: root)
    let manifestURL = root.appendingPathComponent("manifest.json")
    guard fm.fileExists(atPath: manifestURL.path) else { throw ClawMemoryArchiveV2Error.missingManifest }
    let manifest = try Self.decoder.decode(ClawMemoryArchiveManifestV2.self, from: Data(contentsOf: manifestURL))
    guard manifest.version == 2 else { throw ClawMemoryArchiveV2Error.unsupportedVersion(manifest.version) }
    for file in manifest.files {
      guard Self.isSafeRelativePath(file.path) else { throw ClawMemoryArchiveV2Error.unsafePath(file.path) }
      let url = root.appendingPathComponent(file.path)
      guard fm.fileExists(atPath: url.path) else { throw ClawMemoryArchiveV2Error.missingFile(file.path) }
      guard Self.sha256(try Data(contentsOf: url)) == file.sha256 else {
        throw ClawMemoryArchiveV2Error.checksumMismatch(file.path)
      }
    }
    let attachments = try Dictionary(uniqueKeysWithValues: manifest.files.filter { $0.path.hasPrefix("attachments/") }.map { file in
      (URL(fileURLWithPath: file.path).lastPathComponent, try Data(contentsOf: root.appendingPathComponent(file.path)))
    })
    return ClawMemoryArchiveSnapshot(
      memories: try decode([MemoryV2Record].self, at: "memory/records.json", root: root),
      rawEvents: try decode([RawMemoryEvent].self, at: "memory/raw-events.json", root: root),
      audits: try decode([MemoryAuditRecord].self, at: "memory/audit.json", root: root),
      attachments: attachments
    )
  }

  private func decode<T: Decodable>(_ type: T.Type, at path: String, root: URL) throws -> T {
    try Self.decoder.decode(type, from: Data(contentsOf: root.appendingPathComponent(path)))
  }

  private func add(_ data: Data, path: String, count: Int?, root: URL, files: inout [ClawMemoryArchiveFile]) throws {
    guard Self.isSafeRelativePath(path) else { throw ClawMemoryArchiveV2Error.unsafePath(path) }
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: [.atomic, .completeFileProtection])
    files.append(.init(path: path, sha256: Self.sha256(data), byteCount: data.count, recordCount: count))
  }

  private static var encoder: JSONEncoder {
    let value = JSONEncoder(); value.outputFormatting = [.prettyPrinted, .sortedKeys]; value.dateEncodingStrategy = .secondsSince1970; return value
  }
  private static var decoder: JSONDecoder {
    let value = JSONDecoder(); value.dateDecodingStrategy = .secondsSince1970; return value
  }
  private static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
  private static func isSafeRelativePath(_ path: String) -> Bool {
    !path.isEmpty && !path.hasPrefix("/") && !path.hasPrefix("\\") && !path.split(separator: "/").contains("..")
  }
}
