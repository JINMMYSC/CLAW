import Foundation

public enum MemoryAuditKind: String, Codable, Equatable {
  case forget
  case dream
  case rollback
}

public struct MemoryAuditRecord: Codable, Equatable, Identifiable {
  public var id: UUID
  public var memoryID: UUID
  public var runID: UUID?
  public var kind: MemoryAuditKind
  public var before: MemoryV2Record?
  public var after: MemoryV2Record?
  public var createdAt: Date

  public init(id: UUID = UUID(), memoryID: UUID, runID: UUID? = nil, kind: MemoryAuditKind, before: MemoryV2Record?, after: MemoryV2Record?, createdAt: Date = Date()) {
    self.id = id
    self.memoryID = memoryID
    self.runID = runID
    self.kind = kind
    self.before = before
    self.after = after
    self.createdAt = createdAt
  }
}

public struct MemoryConflict: Codable, Equatable, Identifiable {
  public var id: UUID
  public var existingMemoryID: UUID
  public var incomingMemoryID: UUID
  public var createdAt: Date
  public var isResolved: Bool

  public init(id: UUID = UUID(), existingMemoryID: UUID, incomingMemoryID: UUID, createdAt: Date = Date(), isResolved: Bool = false) {
    self.id = id
    self.existingMemoryID = existingMemoryID
    self.incomingMemoryID = incomingMemoryID
    self.createdAt = createdAt
    self.isResolved = isResolved
  }
}

public enum MemoryConflictResolution: Equatable {
  case keepExisting
  case acceptIncoming
  case needsReview(MemoryConflict)
}

public struct MemoryPromotionEngine {
  public init() {}

  public func evaluate(_ record: MemoryV2Record, observationCount: Int, distinctSourceCount: Int) -> MemoryV2Record {
    var result = record
    let explicit = record.provenance.originType == .userExplicit || record.provenance.originType == .userCorrection
    if record.state == .candidate,
       (explicit || (observationCount >= 3 && distinctSourceCount >= 2)) {
      result.state = .active
      result.updatedAt = Date()
    }
    return result
  }

  public func decay(_ record: MemoryV2Record, now: Date = Date()) -> MemoryV2Record {
    var result = record
    if record.state == .active,
       now.timeIntervalSince(record.updatedAt) >= 180 * 86_400,
       record.importance < 0.9 {
      result.state = .stale
      result.updatedAt = now
    }
    return result
  }
}

public struct MemoryConflictResolver {
  public init() {}

  public func resolve(existing: MemoryV2Record, incoming: MemoryV2Record) -> MemoryConflictResolution {
    if existing.provenance.originType == .userCorrection || existing.provenance.trustLevel >= incoming.provenance.trustLevel + 40 {
      return .keepExisting
    }
    if incoming.provenance.originType == .userCorrection || incoming.provenance.trustLevel >= existing.provenance.trustLevel + 40 {
      return .acceptIncoming
    }
    return .needsReview(MemoryConflict(existingMemoryID: existing.id, incomingMemoryID: incoming.id))
  }
}

public final class MemoryForgetEngine {
  private let sdk: MemorySDK
  private let store: ClawMemoryStore

  public init(sdk: MemorySDK = DefaultMemorySDK.shared, store: ClawMemoryStore = .shared) {
    self.sdk = sdk
    self.store = store
  }

  public func forget(id: UUID, mode: ForgetMode) throws {
    // A full erase must not keep an undo snapshot containing the secret in
    // memory_audit (or it would still be recoverable from the local database).
    if mode == .fullDelete {
      try sdk.forget(id: id, mode: mode)
      return
    }
    var before = try store.memoryV2(id: id)
    try sdk.forget(id: id, mode: mode)
    let after = try store.memoryV2(id: id)
    if mode == .removeEvidence {
      before?.evidence = []
      before?.lineage.rawEventIDs = []
    }
    try store.saveMemoryAudit(MemoryAuditRecord(memoryID: id, kind: .forget, before: before, after: after))
  }

  public func rollback(auditID: UUID) throws {
    guard let audit = try store.memoryAuditRecord(id: auditID), let before = audit.before else {
      throw MemorySDKError.missingMemory(auditID)
    }
    try sdk.remember(before, evidence: before.evidence)
    try store.saveMemoryAudit(MemoryAuditRecord(memoryID: before.id, runID: audit.runID, kind: .rollback, before: audit.after, after: before))
  }
}

