import Foundation

public protocol MemorySDK {
  func remember(_ item: MemoryV2Record, evidence: [MemoryEvidence]) throws
  func recall(_ request: MemoryRecallRequest) throws -> [MemoryV2Record]
  func context(_ request: MemoryContextRequest) throws -> MemoryContext
  func correct(id: UUID, replacement: MemoryV2Record) throws
  func forget(id: UUID, mode: ForgetMode) throws
  func createTask(_ task: ClawSecretaryTask) throws
  func createIntent(_ intent: StandingIntent) throws
  func flush(_ session: MemoryFlushSession) throws
}

public enum MemorySDKError: LocalizedError {
  case missingMemory(UUID)

  public var errorDescription: String? {
    switch self {
    case .missingMemory(let id): return "Memory not found: \(id.uuidString)"
    }
  }
}

/// The single host-app boundary for V2 writes and scoped retrieval.
/// It keeps a legacy projection while older screens finish migrating.
public final class DefaultMemorySDK: MemorySDK {
  public static let shared = DefaultMemorySDK()
  private let store: ClawMemoryStore

  public init(store: ClawMemoryStore = .shared) {
    self.store = store
  }

  public func remember(_ item: MemoryV2Record, evidence: [MemoryEvidence] = []) throws {
    var record = item
    record.evidence = evidence
    try store.saveMemoryV2(record, legacyProjection: legacyProjection(record))
  }

  public func recall(_ request: MemoryRecallRequest) throws -> [MemoryV2Record] {
    let candidates = try store.memoryV2(
      scope: request.scope,
      personID: request.personID,
      limit: max(request.limit * 4, request.limit)
    ).filter { record in
      guard record.state == .active || record.state == .confirmed else { return false }
      if let projectID = request.projectID, record.projectID != projectID { return false }
      return true
    }
    let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
    let ranked = candidates.sorted { lhs, rhs in
      score(lhs, query: query) > score(rhs, query: query)
    }
    return Array(ranked.prefix(max(1, request.limit)))
  }

  public func context(_ request: MemoryContextRequest) throws -> MemoryContext {
    let recalled = try recall(request.recall)
    let records = MemoryGuard().evaluate(
      recalled,
      personID: request.recall.personID,
      projectID: request.recall.projectID,
      temporaryMode: ClawMemoryPolicyService.shared.temporaryMode
    ).allowed
    guard request.includeEvidence else { return MemoryContext(records: records) }
    let ids = records.flatMap { $0.evidence.map(\.rawEventID) }
    return MemoryContext(records: records, evidence: try store.rawEvents(ids: Array(Set(ids))))
  }

  public func correct(id: UUID, replacement: MemoryV2Record) throws {
    guard let existing = try store.memoryV2(id: id) else { throw MemorySDKError.missingMemory(id) }
    var corrected = replacement
    corrected.id = id
    corrected.version = existing.version + 1
    corrected.updatedAt = Date()
    corrected.state = .confirmed
    corrected.provenance.originType = .userCorrection
    corrected.provenance.trustLevel = MemoryOriginType.userCorrection.trustLevel
    try remember(corrected, evidence: corrected.evidence)
  }

  public func forget(id: UUID, mode: ForgetMode) throws {
    guard var record = try store.memoryV2(id: id) else { throw MemorySDKError.missingMemory(id) }
    record.version += 1
    record.updatedAt = Date()
    switch mode {
    case .removeEvidence:
      record.evidence = []
      record.lineage.rawEventIDs = []
    case .archive:
      record.state = .archived
    case .invalidateDerivedFacts, .fullDelete:
      record.state = .invalidated
      if mode == .fullDelete {
        record.content = ""
        record.evidence = []
        record.lineage = MemoryLineage()
      }
    }
    try store.saveMemoryV2(record)
    _ = try? store.setMemoryStatus(id: id, status: mode == .archive ? .archived : .superseded)
  }

  public func createTask(_ task: ClawSecretaryTask) throws {
    try store.upsertTask(task)
  }

  public func createIntent(_ intent: StandingIntent) throws {
    let record = MemoryV2Record(
      id: intent.id,
      type: .intent,
      state: .active,
      scope: intent.personID == nil ? .global : .person,
      content: intent.action,
      personID: intent.personID,
      projectID: intent.projectID,
      provenance: intent.provenance,
      expiresAt: intent.expiresAt
    )
    try remember(record)
  }

  public func flush(_ session: MemoryFlushSession) throws {
    for record in session.records {
      var scoped = record
      scoped.sessionID = scoped.sessionID ?? session.sessionID
      try store.saveMemoryV2(
        scoped,
        rawEvents: session.rawEvents,
        legacyProjection: legacyProjection(scoped)
      )
    }
  }

  private func score(_ record: MemoryV2Record, query: String) -> Double {
    let match = query.isEmpty || record.content.localizedCaseInsensitiveContains(query) ? 2.0 : 0
    return match + record.importance + record.confidence + Double(record.provenance.trustLevel) / 100
  }

  private func legacyProjection(_ record: MemoryV2Record) -> ClawMemoryItem {
    let kind: ClawMemoryKind
    switch record.type {
    case .preference: kind = .communicationPreference
    case .people, .communication: kind = .relationship
    case .task, .intent: kind = .procedure
    default: kind = .fact
    }
    let status: ClawMemoryStatus
    switch record.state {
    case .archived: status = .archived
    case .invalidated: status = .superseded
    default: status = .active
    }
    return ClawMemoryItem(
      id: record.id,
      kind: kind,
      scope: record.scope == .person ? "contact" : record.scope.rawValue,
      subjectID: record.personID,
      content: record.content,
      normalizedKey: record.normalizedKey,
      sourceType: record.provenance.ingestionMethod,
      confidence: record.confidence,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
      lastObservedAt: record.provenance.observedAt,
      status: status
    )
  }
}

