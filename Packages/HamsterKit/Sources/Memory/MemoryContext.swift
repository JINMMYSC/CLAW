import Foundation

public struct MemoryRecallRequest: Equatable {
  public var query: String
  public var personID: UUID?
  public var projectID: UUID?
  public var scope: MemoryScope
  public var limit: Int

  public init(query: String, personID: UUID? = nil, projectID: UUID? = nil, scope: MemoryScope, limit: Int = 40) {
    self.query = query
    self.personID = personID
    self.projectID = projectID
    self.scope = scope
    self.limit = limit
  }
}

public struct MemoryContextRequest: Equatable {
  public var recall: MemoryRecallRequest
  public var includeEvidence: Bool

  public init(recall: MemoryRecallRequest, includeEvidence: Bool = true) {
    self.recall = recall
    self.includeEvidence = includeEvidence
  }
}

public struct MemoryContext: Equatable {
  public var records: [MemoryV2Record]
  public var evidence: [RawMemoryEvent]

  public init(records: [MemoryV2Record] = [], evidence: [RawMemoryEvent] = []) {
    self.records = records
    self.evidence = evidence
  }
}

public enum ForgetMode: Equatable {
  case removeEvidence
  case invalidateDerivedFacts
  case archive
  case fullDelete
}

public struct MemoryFlushSession: Equatable {
  public var sessionID: UUID
  public var records: [MemoryV2Record]
  public var rawEvents: [RawMemoryEvent]

  public init(sessionID: UUID, records: [MemoryV2Record], rawEvents: [RawMemoryEvent] = []) {
    self.sessionID = sessionID
    self.records = records
    self.rawEvents = rawEvents
  }
}
