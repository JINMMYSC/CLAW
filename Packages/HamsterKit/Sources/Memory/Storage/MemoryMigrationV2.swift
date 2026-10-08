import Foundation

public struct MemoryMigrationV2Report: Equatable {
  public var legacyMemories: Int
  public var conversations: Int
  public var tasks: Int
  public var people: Int
  public var totalV2Records: Int

  public init(
    legacyMemories: Int,
    conversations: Int,
    tasks: Int,
    people: Int,
    totalV2Records: Int
  ) {
    self.legacyMemories = legacyMemories
    self.conversations = conversations
    self.tasks = tasks
    self.people = people
    self.totalV2Records = totalV2Records
  }
}

/// Idempotently projects legacy rows into V2 while retaining their stable IDs.
/// Each record is independently transactional, so an interrupted run can resume.
public final class MemoryMigrationV2 {
  private let store: ClawMemoryStore

  public init(store: ClawMemoryStore = .shared) {
    self.store = store
  }

  @discardableResult
  public func run(profiles: [HeartTargetProfile] = []) throws -> MemoryMigrationV2Report {
    let memories = try store.allMemoryItems()
    let conversations = try store.allConversation()
    let tasks = try store.allTasks()

    for item in memories { try store.saveMemoryV2(Self.record(from: item)) }
    for message in conversations {
      let raw = RawMemoryEvent(
        id: message.id,
        kind: "legacy-conversation",
        content: message.content,
        sourceApp: message.sourceType,
        sourceRef: message.sourceRef,
        occurredAt: message.occurredAt,
        ingestedAt: message.occurredAt,
        idempotencyKey: "legacy-conversation:\(message.id.uuidString)"
      )
      let evidence = MemoryEvidence(
        id: message.id,
        rawEventID: raw.id,
        locator: message.sourceRef,
        excerpt: message.content
      )
      let record = MemoryV2Record(
        id: message.id,
        type: .episodic,
        state: .active,
        scope: message.contactID == nil ? .global : .person,
        content: message.content,
        personID: message.contactID,
        confidence: message.confidence,
        provenance: MemoryProvenance(
          originType: message.speaker == .me ? .userExplicit : .contactDirect,
          sourcePersonID: message.contactID,
          observedAt: message.occurredAt,
          ingestionMethod: message.sourceType
        ),
        evidence: [evidence],
        lineage: MemoryLineage(rawEventIDs: [raw.id]),
        createdAt: message.occurredAt,
        updatedAt: message.occurredAt
      )
      try store.saveMemoryV2(record, rawEvents: [raw])
    }
    for task in tasks {
      let state: MemoryState = task.status == .open ? .active : .archived
      try store.saveMemoryV2(MemoryV2Record(
        id: task.id,
        type: .task,
        state: state,
        scope: task.contactID == nil ? .global : .person,
        content: task.title,
        personID: task.contactID,
        confidence: 1,
        importance: task.dueAt == nil ? 0.6 : 0.85,
        provenance: MemoryProvenance(
          originType: .systemObserved,
          sourcePersonID: task.contactID,
          observedAt: task.createdAt,
          ingestionMethod: task.sourceType
        ),
        createdAt: task.createdAt,
        updatedAt: task.createdAt,
        expiresAt: task.dueAt
      ))
    }
    for profile in profiles {
      let details = profile.memoryContext.isEmpty ? profile.displayName : "\(profile.displayName)\n\(profile.memoryContext)"
      try store.saveMemoryV2(MemoryV2Record(
        id: profile.id,
        type: .people,
        state: .confirmed,
        scope: .person,
        content: details,
        personID: profile.id,
        confidence: profile.autoCreated ? 0.7 : 1,
        importance: 0.8,
        provenance: MemoryProvenance(
          originType: profile.autoCreated ? .clawInference : .userExplicit,
          sourcePersonID: profile.id,
          observedAt: profile.updatedAt,
          ingestionMethod: "legacy-profile"
        ),
        createdAt: profile.updatedAt,
        updatedAt: profile.updatedAt,
        confirmedAt: profile.autoCreated ? nil : profile.updatedAt
      ))
    }

    return MemoryMigrationV2Report(
      legacyMemories: memories.count,
      conversations: conversations.count,
      tasks: tasks.count,
      people: profiles.count,
      totalV2Records: try store.memoryV2Count()
    )
  }

  private static func record(from item: ClawMemoryItem) -> MemoryV2Record {
    let type: MemoryType
    switch item.kind {
    case .relationship, .contactStyle: type = .people
    case .communicationPreference, .globalStyle, .languagePreference: type = .communication
    case .project: type = .project
    case .event: type = .episodic
    case .procedure: type = .knowledge
    default: type = .preference
    }
    let state: MemoryState
    switch item.status {
    case .active: state = .active
    case .archived: state = .archived
    case .superseded: state = .invalidated
    }
    let scope = MemoryScope(rawValue: item.scope == "contact" ? "person" : item.scope) ?? .global
    return MemoryV2Record(
      id: item.id,
      type: type,
      state: state,
      scope: scope,
      content: item.content,
      normalizedKey: item.normalizedKey,
      personID: item.subjectID,
      confidence: item.confidence,
      provenance: MemoryProvenance(
        originType: .systemObserved,
        sourcePersonID: item.subjectID,
        observedAt: item.lastObservedAt,
        ingestionMethod: item.sourceType
      ),
      createdAt: item.createdAt,
      updatedAt: item.updatedAt
    )
  }
}
