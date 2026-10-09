import Foundation

public final class StandingIntentStore {
  private let memoryStore: ClawMemoryStore

  public init(memoryStore: ClawMemoryStore = .shared) {
    self.memoryStore = memoryStore
  }

  public func save(_ intent: StandingIntent) throws { try memoryStore.saveStandingIntent(intent) }
  public func cancel(id: UUID) throws { try memoryStore.cancelStandingIntent(id: id) }

  public func match(trigger: String, personID: UUID? = nil, projectID: UUID? = nil, context: String? = nil, now: Date = Date()) throws -> [StandingIntent] {
    try memoryStore.standingIntents().filter { intent in
      guard intent.isActive, intent.expiresAt.map({ $0 > now }) ?? true else { return false }
      if let personID, intent.personID != personID { return false }
      if let projectID, intent.projectID != projectID { return false }
      let triggerMatches = intent.trigger.localizedCaseInsensitiveContains(trigger)
        || trigger.localizedCaseInsensitiveContains(intent.trigger)
      let contextMatches = context.map { intent.context.localizedCaseInsensitiveContains($0) || $0.localizedCaseInsensitiveContains(intent.context) } ?? true
      return triggerMatches && contextMatches
    }.sorted { $0.createdAt < $1.createdAt }
  }
}

public struct MemoryFlushResult: Equatable {
  public var records: [MemoryV2Record]
  public var tasks: [ClawSecretaryTask]

  public init(records: [MemoryV2Record], tasks: [ClawSecretaryTask]) {
    self.records = records
    self.tasks = tasks
  }
}

public struct MemoryFlushService {
  public init() {}

  public func extract(sessionID: UUID, messages: [ClawConversationMessage], personID: UUID?) -> MemoryFlushResult {
    var records: [MemoryV2Record] = []
    var tasks: [ClawSecretaryTask] = []
    for message in messages {
      let event = RawMemoryEvent(kind: "conversation", content: message.content, sourceApp: message.sourceType, sourceRef: message.sourceRef, occurredAt: message.occurredAt)
      let evidence = [MemoryEvidence(rawEventID: event.id, locator: message.id.uuidString, excerpt: message.content)]
      // Treat explicit commitments and delivery/reminder language as actionable
      // tasks while leaving ordinary conversational messages as timeline-only.
      let taskMarkers = ["答应", "截止", "提交", "交付", "完成", "提醒", "必须", "需要"]
      // "不要" contains the single word "要"; that was previously creating
      // a bogus task from a simple preference or refusal. An opt-out is not a
      // promise to deliver work, even if it mentions the word "提醒".
      let isOptOut = message.content.contains("不要") || message.content.contains("不需要")
      if !isOptOut && taskMarkers.contains(where: message.content.contains) {
        tasks.append(ClawSecretaryTask(kind: .commitment, title: message.content, contactID: personID, sourceType: message.sourceType, sourceRef: message.id.uuidString))
        records.append(record(type: .task, content: message.content, sessionID: sessionID, personID: personID, evidence: evidence))
      }
      if message.content.contains("喜欢") || message.content.contains("偏好") || message.content.contains("不要") {
        records.append(record(type: .preference, content: message.content, sessionID: sessionID, personID: personID, evidence: evidence))
      }
    }
    return MemoryFlushResult(records: records, tasks: tasks)
  }

  private func record(type: MemoryType, content: String, sessionID: UUID, personID: UUID?, evidence: [MemoryEvidence]) -> MemoryV2Record {
    MemoryV2Record(type: type, state: .candidate, scope: personID == nil ? .global : .person, content: content, personID: personID, sessionID: sessionID, provenance: MemoryProvenance(originType: .systemObserved, sourcePersonID: personID, sourceSessionID: sessionID, ingestionMethod: "conversation-flush"), evidence: evidence)
  }
}
