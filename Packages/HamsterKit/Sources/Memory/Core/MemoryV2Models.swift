import Foundation

/// Memory V2 基础类型。这里是 CLAW Memory OS 的公共词汇表：
/// 所有功能入口（输入法、帮你回、超会说、语音、截图、主助手）都应通过这些类型
/// 读写记忆，而不是各自拼装自己的字段。

/// 记忆作用域：记住某件事不等于任何场景都可以拿出来用。
public enum MemoryScope: String, Codable, CaseIterable, Equatable {
  case global
  case person
  case relationship
  case group
  case project
  case app
  case session
  case localOnly
}

/// 记忆生命周期状态。模型猜测只能停在 candidate，不能直接进入长期记忆。
public enum MemoryState: String, Codable, CaseIterable, Equatable {
  case candidate
  case active
  case confirmed
  case stale
  case archived
  case invalidated
}

/// 记忆类型分类，对应交接稿中的十一类记忆。
public enum MemoryType: String, Codable, CaseIterable, Equatable {
  case raw
  case working
  case episodic
  case semantic
  case people
  case communication
  case preference
  case project
  case task
  case intent
  case knowledge
}

/// 来源类型，决定这条记忆的可信上限。
public enum MemoryOriginType: String, Codable, CaseIterable, Equatable {
  case userExplicit
  case userCorrection
  case userBehavior
  case contactDirect
  case systemObserved
  case clawInference
  case connectedService
  case externalContent
  case unknown

  /// 可信等级，取值沿用交接稿中的 0-100 方案。
  public var trustLevel: Int {
    switch self {
    case .userExplicit: return 100
    case .userCorrection: return 100
    case .userBehavior: return 90
    case .contactDirect: return 80
    case .systemObserved: return 70
    case .clawInference: return 60
    case .connectedService: return 50
    case .externalContent: return 30
    case .unknown: return 10
    }
  }

  /// 只有用户明确表达、纠正以及长期行为可以跳过人工确认。
  public var canAutoConfirm: Bool {
    switch self {
    case .userExplicit, .userCorrection, .userBehavior: return true
    default: return false
    }
  }
}

/// 云端发送权限。所有出网请求都要先过这一层。
public enum MemoryCloudPermission: String, Codable, CaseIterable, Equatable {
  case localOnly
  case privateCloud
  case aiAllowed
  case neverSend
  case temporary
}

/// 记忆来源信息：这条记忆是怎么知道的。
public struct MemoryProvenance: Codable, Equatable {
  public var originType: MemoryOriginType
  public var sourceApp: String?
  public var sourcePersonID: UUID?
  public var sourceSessionID: UUID?
  public var trustLevel: Int
  public var observedAt: Date
  public var ingestionMethod: String

  public init(
    originType: MemoryOriginType,
    sourceApp: String? = nil,
    sourcePersonID: UUID? = nil,
    sourceSessionID: UUID? = nil,
    trustLevel: Int? = nil,
    observedAt: Date = Date(),
    ingestionMethod: String
  ) {
    self.originType = originType
    self.sourceApp = sourceApp
    self.sourcePersonID = sourcePersonID
    self.sourceSessionID = sourceSessionID
    self.trustLevel = trustLevel ?? originType.trustLevel
    self.observedAt = observedAt
    self.ingestionMethod = ingestionMethod
  }
}

/// 证据：这条记忆能追溯到哪条原始记录。
public struct MemoryEvidence: Codable, Equatable, Identifiable {
  public var id: UUID
  public var rawEventID: UUID
  public var locator: String?
  public var excerpt: String?

  public init(
    id: UUID = UUID(),
    rawEventID: UUID,
    locator: String? = nil,
    excerpt: String? = nil
  ) {
    self.id = id
    self.rawEventID = rawEventID
    self.locator = locator
    self.excerpt = excerpt
  }
}

/// 血缘：派生记忆的来源链，用于可追溯遗忘。
public struct MemoryLineage: Codable, Equatable {
  public var parentID: UUID?
  public var rawEventIDs: [UUID]
  public var derivedFromMemoryIDs: [UUID]

  public init(
    parentID: UUID? = nil,
    rawEventIDs: [UUID] = [],
    derivedFromMemoryIDs: [UUID] = []
  ) {
    self.parentID = parentID
    self.rawEventIDs = rawEventIDs
    self.derivedFromMemoryIDs = derivedFromMemoryIDs
  }
}

/// 原始事件：证据层，原则上只追加。
public struct RawMemoryEvent: Codable, Equatable, Identifiable {
  public var id: UUID
  public var kind: String
  public var content: String
  public var sourceApp: String?
  public var sourceRef: String?
  public var occurredAt: Date
  public var ingestedAt: Date
  public var idempotencyKey: String?

  public init(
    id: UUID = UUID(),
    kind: String,
    content: String,
    sourceApp: String? = nil,
    sourceRef: String? = nil,
    occurredAt: Date = Date(),
    ingestedAt: Date = Date(),
    idempotencyKey: String? = nil
  ) {
    self.id = id
    self.kind = kind
    self.content = content
    self.sourceApp = sourceApp
    self.sourceRef = sourceRef
    self.occurredAt = occurredAt
    self.ingestedAt = ingestedAt
    self.idempotencyKey = idempotencyKey
  }
}

/// 结构化记忆的统一载体。
public struct MemoryV2Record: Codable, Equatable, Identifiable {
  public var id: UUID
  public var type: MemoryType
  public var state: MemoryState
  public var scope: MemoryScope
  public var content: String
  public var normalizedKey: String?
  public var personID: UUID?
  public var projectID: UUID?
  public var sessionID: UUID?
  public var confidence: Double
  public var importance: Double
  public var provenance: MemoryProvenance
  public var evidence: [MemoryEvidence]
  public var lineage: MemoryLineage
  public var cloudPermission: MemoryCloudPermission
  public var version: Int
  public var createdAt: Date
  public var updatedAt: Date
  public var confirmedAt: Date?
  public var expiresAt: Date?

  public init(
    id: UUID = UUID(),
    type: MemoryType,
    state: MemoryState = .candidate,
    scope: MemoryScope,
    content: String,
    normalizedKey: String? = nil,
    personID: UUID? = nil,
    projectID: UUID? = nil,
    sessionID: UUID? = nil,
    confidence: Double = 0.5,
    importance: Double = 0.5,
    provenance: MemoryProvenance,
    evidence: [MemoryEvidence] = [],
    lineage: MemoryLineage = MemoryLineage(),
    cloudPermission: MemoryCloudPermission = .aiAllowed,
    version: Int = 1,
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    confirmedAt: Date? = nil,
    expiresAt: Date? = nil
  ) {
    self.id = id
    self.type = type
    self.state = state
    self.scope = scope
    self.content = content
    self.normalizedKey = normalizedKey
    self.personID = personID
    self.projectID = projectID
    self.sessionID = sessionID
    self.confidence = confidence
    self.importance = importance
    self.provenance = provenance
    self.evidence = evidence
    self.lineage = lineage
    self.cloudPermission = cloudPermission
    self.version = version
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.confirmedAt = confirmedAt
    self.expiresAt = expiresAt
  }

  /// 是否允许进入云端模型请求。
  public var isCloudEligible: Bool {
    switch cloudPermission {
    case .localOnly, .neverSend, .temporary: return false
    case .privateCloud, .aiAllowed: return true
    }
  }
}

/// 未来意图记忆：条件触发，而非固定时间提醒。
public struct StandingIntent: Codable, Equatable, Identifiable {
  public var id: UUID
  public var trigger: String
  public var personID: UUID?
  public var projectID: UUID?
  public var context: String
  public var condition: String
  public var action: String
  public var expiresAt: Date?
  public var isActive: Bool
  public var createdAt: Date
  public var provenance: MemoryProvenance

  public init(
    id: UUID = UUID(),
    trigger: String,
    personID: UUID? = nil,
    projectID: UUID? = nil,
    context: String,
    condition: String,
    action: String,
    expiresAt: Date? = nil,
    isActive: Bool = true,
    createdAt: Date = Date(),
    provenance: MemoryProvenance
  ) {
    self.id = id
    self.trigger = trigger
    self.personID = personID
    self.projectID = projectID
    self.context = context
    self.condition = condition
    self.action = action
    self.expiresAt = expiresAt
    self.isActive = isActive
    self.createdAt = createdAt
    self.provenance = provenance
  }
}

/// Memory V2 表结构版本，迁移逻辑以此判断是否需要升级。
public enum MemorySchemaVersion {
  public static let current = 2
  public static let key = "claw_memory_schema_version_v1"
}
