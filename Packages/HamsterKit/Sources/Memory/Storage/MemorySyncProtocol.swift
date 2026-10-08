import Foundation

public struct MemoryVersionVector: Codable, Equatable, Sendable {
  public var counters: [String: Int]
  public init(_ counters: [String: Int] = [:]) { self.counters = counters }

  public func incremented(on deviceID: String) -> Self {
    var next = self; next.counters[deviceID, default: 0] += 1; return next
  }

  public func relation(to other: Self) -> Relation {
    let keys = Set(counters.keys).union(other.counters.keys)
    let less = keys.contains { counters[$0, default: 0] < other.counters[$0, default: 0] }
    let greater = keys.contains { counters[$0, default: 0] > other.counters[$0, default: 0] }
    if less && greater { return .concurrent }
    if less { return .before }
    if greater { return .after }
    return .equal
  }

  public enum Relation: String, Codable { case before, after, equal, concurrent }
}

public enum MemorySyncOperationKind: Int, Codable, Sendable { case upsert = 0, correction = 1, delete = 2 }

public struct MemorySyncOperation: Codable, Equatable, Sendable, Identifiable {
  public var id: UUID
  public var deviceID: String
  public var memoryID: UUID
  public var kind: MemorySyncOperationKind
  public var record: MemoryV2Record?
  public var vector: MemoryVersionVector
  public var createdAt: Date
  public init(id: UUID = UUID(), deviceID: String, memoryID: UUID, kind: MemorySyncOperationKind, record: MemoryV2Record?, vector: MemoryVersionVector, createdAt: Date = Date()) {
    self.id = id; self.deviceID = deviceID; self.memoryID = memoryID; self.kind = kind; self.record = record; self.vector = vector; self.createdAt = createdAt
  }
}

public enum MemorySyncMergeResult: Equatable { case accepted(MemorySyncOperation), ignored, conflict(MemorySyncOperation, MemorySyncOperation) }

/// Deterministic, append-only merge. Delete/correction outrank inferred writes.
public struct MemorySyncMerger {
  public init() {}
  public func merge(local: MemorySyncOperation, remote: MemorySyncOperation) -> MemorySyncMergeResult {
    switch remote.vector.relation(to: local.vector) {
    case .after: return .accepted(remote)
    case .before, .equal: return .ignored
    case .concurrent:
      if remote.kind.rawValue != local.kind.rawValue {
        return remote.kind.rawValue > local.kind.rawValue ? .accepted(remote) : .ignored
      }
      if remote.createdAt != local.createdAt { return remote.createdAt > local.createdAt ? .accepted(remote) : .ignored }
      if remote.deviceID != local.deviceID { return remote.deviceID > local.deviceID ? .accepted(remote) : .ignored }
      return .conflict(local, remote)
    }
  }
}

public struct MemorySyncPolicy {
  public init() {}
  public func canSync(_ record: MemoryV2Record, isOptedIn: Bool) -> Bool {
    guard isOptedIn else { return false }
    switch record.cloudPermission {
    case .privateCloud, .aiAllowed: return record.scope != .session
    case .localOnly, .neverSend, .temporary: return false
    }
  }
}

/// Local append-only journal. A transport may upload this only after explicit opt-in.
public final class MemorySyncJournal {
  private let url: URL
  private let lock = NSLock()
  public init(url: URL) { self.url = url }

  public func append(_ operation: MemorySyncOperation) throws {
    lock.lock(); defer { lock.unlock() }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    var data = try encoder.encode(operation); data.append(0x0A)
    if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: [.atomic, .completeFileProtection]); return }
    let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
    try handle.seekToEnd(); try handle.write(contentsOf: data)
  }

  public func operations() throws -> [MemorySyncOperation] {
    lock.lock(); defer { lock.unlock() }
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    return try Data(contentsOf: url).split(separator: 0x0A).map { try decoder.decode(MemorySyncOperation.self, from: Data($0)) }
  }
}
