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
  func projection(_ kind: MemoryProjectionKind, personID: UUID?, projectID: UUID?, limit: Int) throws -> MemoryProjection
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

  /// Compatibility inlet for features still producing the legacy value type.
  /// The write still crosses the SDK boundary and creates the V2 source of truth.
  public func rememberLegacy(_ item: ClawMemoryItem) throws {
    let type: MemoryType
    switch item.kind {
    case .communicationPreference, .globalStyle, .languagePreference, .negativePreference, .reusablePhrase:
      type = .preference
    case .contactStyle, .relationship:
      type = .people
    case .event:
      type = .episodic
    case .project:
      type = .project
    case .procedure:
      type = .task
    default:
      type = .semantic
    }
    let scope: MemoryScope = item.subjectID == nil ? (MemoryScope(rawValue: item.scope) ?? .global) : .person
    let state: MemoryState = item.status == .active ? .active : (item.status == .archived ? .archived : .invalidated)
    let record = MemoryV2Record(
      id: item.id,
      type: type,
      state: state,
      scope: scope,
      content: item.content,
      normalizedKey: item.normalizedKey,
      personID: item.subjectID,
      confidence: item.confidence,
      provenance: MemoryProvenance(originType: .systemObserved, sourceApp: item.sourceType, observedAt: item.lastObservedAt, ingestionMethod: item.sourceType),
      createdAt: item.createdAt,
      updatedAt: item.updatedAt
    )
    try store.saveMemoryV2(record, legacyProjection: item)
  }

  /// Transitional, scope-safe projection for older views while their models
  /// still render ClawMemoryItem. New and corrected V2 entries take precedence;
  /// legacy-only rows remain visible until all writers are migrated.
  /// No caller outside the SDK should combine legacy and V2 reads.
  public func contextualMemories(
    scope: String,
    personID: UUID? = nil,
    limit: Int = 80
  ) throws -> [ClawMemoryItem] {
    let count = max(1, limit)
    let legacy = try store.memories(
      scope: scope,
      subjectID: scope == "contact" ? personID : nil,
      limit: count
    )
    let candidates: [MemoryV2Record]
    if scope == "global" {
      // Use the existing SQLite scope index before applying the context limit:
      // scanning 80 most-recent rows across all users hides old global facts.
      candidates = try store.memoryV2(scope: .global, limit: count)
        .filter { $0.personID == nil }
    } else if scope == "contact", let personID {
      // Restrict each query by person_id in SQL; never sample all persons'
      // recent memories and filter afterward.
      let people = try store.memoryV2(scope: .person, personID: personID, limit: count)
      let relations = try store.memoryV2(scope: .relationship, personID: personID, limit: count)
      candidates = (people + relations).sorted { $0.updatedAt > $1.updatedAt }
    } else if scope == "contact" {
      return []
    } else {
      return legacy
    }
    let now = Date()
    let permitted = candidates.filter {
      ($0.state == .active || $0.state == .confirmed) &&
        ($0.expiresAt == nil || $0.expiresAt! > now)
    }
    // Check all selected legacy IDs against the V2 primary-key index, not just
    // the limited recent V2 candidates. Old invalidated or relocated rows must
    // not reappear if they fall outside the top-N V2 selection.
    let v2AuthoritativeIDs = try store.memoryV2ExistingIDs(Set(legacy.map(\.id)))
    let legacyByID = Dictionary(uniqueKeysWithValues: legacy.map { ($0.id, $0) })
    var seen = Set<UUID>()
    var merged: [ClawMemoryItem] = []
    for record in permitted {
      var item = legacyProjection(record)
      // Preserve trusted source metadata when a V2 write updated the same
      // legacy row, but never replace newer V2 content or scope with stale data.
      if let old = legacyByID[record.id] {
        item.kind = old.kind
        item.sourceType = old.sourceType
        item.sourceRef = old.sourceRef
      }
      if scope == "contact" { item.scope = "contact" }
      if seen.insert(item.id).inserted { merged.append(item) }
    }
    for item in legacy where !v2AuthoritativeIDs.contains(item.id) && seen.insert(item.id).inserted {
      merged.append(item)
    }
    return Array(merged.sorted { $0.lastObservedAt > $1.lastObservedAt }.prefix(count))
  }

  public func recall(_ request: MemoryRecallRequest) throws -> [MemoryV2Record] {
    try MemoryRouter(store: store).recall(request)
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
    if mode == .fullDelete {
      try store.purgeMemoryV2(id: id)
      return
    }
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
    }
    try store.saveMemoryV2(record)
    _ = try? store.setMemoryStatus(id: id, status: mode == .archive ? .archived : .superseded)
  }

  public func createTask(_ task: ClawSecretaryTask) throws {
    try store.upsertTask(task)
  }

  public func createIntent(_ intent: StandingIntent) throws {
    try store.saveStandingIntent(intent)
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
    let scoped = session.records.map { record -> MemoryV2Record in
      var item = record
      item.sessionID = item.sessionID ?? session.sessionID
      return item
    }
    // The same memory can be refined repeatedly in one session. Do not
    // crash on a repeated UUID; the final projection wins for that ID.
    var projections: [UUID: ClawMemoryItem] = [:]
    for item in scoped { projections[item.id] = legacyProjection(item) }
    try store.saveMemoryV2Batch(
      scoped, rawEvents: session.rawEvents, legacyProjections: projections
    )
  }

  public func projection(_ kind: MemoryProjectionKind, personID: UUID? = nil, projectID: UUID? = nil, limit: Int = 100) throws -> MemoryProjection {
    let records = try store.memoryV2(limit: max(limit * 4, limit)).filter { record in
      guard record.state == .active || record.state == .confirmed else { return false }
      if let personID, record.personID != personID { return false }
      if let projectID, record.projectID != projectID { return false }
      switch kind {
      case .relationship: return record.type == .people || record.scope == .relationship
      case .project: return record.type == .project || record.scope == .project
      case .episode: return record.type == .episodic
      case .knowledge: return record.type == .knowledge || record.type == .semantic
      case .communication: return record.type == .communication || record.type == .preference
      }
    }
    return MemoryProjection(kind: kind, records: Array(records.prefix(max(1, limit))))
  }

  /// Internal compatibility projection used by the transactional screenshot
  /// importer while migrating legacy view consumers to the Memory SDK.
  func legacyProjection(_ record: MemoryV2Record) -> ClawMemoryItem {
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

