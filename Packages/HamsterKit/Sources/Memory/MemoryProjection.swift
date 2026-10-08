import Foundation

public enum MemoryProjectionKind: String, Codable, CaseIterable, Equatable {
  case relationship
  case project
  case episode
  case knowledge
  case communication
}

public struct MemoryProjection: Equatable {
  public var kind: MemoryProjectionKind
  public var records: [MemoryV2Record]
  public var generatedAt: Date

  public init(kind: MemoryProjectionKind, records: [MemoryV2Record], generatedAt: Date = Date()) {
    self.kind = kind
    self.records = records
    self.generatedAt = generatedAt
  }
}
