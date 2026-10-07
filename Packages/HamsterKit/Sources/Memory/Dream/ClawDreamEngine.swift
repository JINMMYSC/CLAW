import Foundation

public enum ClawDreamStage: String, Codable, Equatable {
  case light
  case rem
  case deep
  case audit
}

public struct ClawDreamBudget: Equatable {
  public var maxMutations: Int
  public init(maxMutations: Int = 20) { self.maxMutations = max(0, maxMutations) }
}

public struct ClawDreamMutation: Equatable, Identifiable {
  public var id: UUID
  public var memoryID: UUID
  public var requiresReview: Bool

  public init(id: UUID = UUID(), memoryID: UUID, requiresReview: Bool) {
    self.id = id
    self.memoryID = memoryID
    self.requiresReview = requiresReview
  }
}

public struct ClawDreamRun: Equatable, Identifiable {
  public var id: UUID
  public var completedStages: [ClawDreamStage]
  public var mutations: [ClawDreamMutation]

  public init(id: UUID = UUID(), completedStages: [ClawDreamStage], mutations: [ClawDreamMutation]) {
    self.id = id
    self.completedStages = completedStages
    self.mutations = mutations
  }
}

/// A deterministic, budgeted consolidation pass. Low-trust material is only
/// proposed for review; trusted duplicates may be archived and can be rolled back.
public final class ClawDreamEngine {
  private let store: ClawMemoryStore

  public init(store: ClawMemoryStore = .shared) { self.store = store }

  public func run(records: [MemoryV2Record], budget: ClawDreamBudget = .init()) throws -> ClawDreamRun {
    let runID = UUID()
    var mutations: [ClawDreamMutation] = []
    var seen = Set<String>()
    for record in records where mutations.count < budget.maxMutations {
      let key = record.normalizedKey ?? record.content.lowercased()
      let lowTrust = record.provenance.trustLevel < MemoryOriginType.clawInference.trustLevel
      if lowTrust {
        mutations.append(ClawDreamMutation(memoryID: record.id, requiresReview: true))
        continue
      }
      guard !seen.insert(key).inserted else { continue }
      var archived = record
      archived.state = .archived
      archived.version += 1
      archived.updatedAt = Date()
      try store.saveMemoryV2(archived)
      try store.saveMemoryAudit(MemoryAuditRecord(memoryID: record.id, runID: runID, kind: .dream, before: record, after: archived))
      mutations.append(ClawDreamMutation(memoryID: record.id, requiresReview: false))
    }
    return ClawDreamRun(id: runID, completedStages: [.light, .rem, .deep, .audit], mutations: mutations)
  }

  public func rollback(runID: UUID) throws {
    for audit in try store.memoryAuditRecords(runID: runID).reversed() {
      guard let before = audit.before else { continue }
      try store.saveMemoryV2(before)
      try store.saveMemoryAudit(MemoryAuditRecord(memoryID: before.id, runID: runID, kind: .rollback, before: audit.after, after: before))
    }
  }
}
