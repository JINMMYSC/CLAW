import Foundation
import SQLite3

public enum ClawMemoryKind: String, Codable, CaseIterable {
  case fact
  case globalStyle
  case languagePreference
  case communicationPreference
  case contactStyle
  case relationship
  case event
  case procedure
  case negativePreference
  case reusablePhrase
  case correction
  case project
}

public enum ClawMemoryStatus: String, Codable {
  case active
  case archived
  case superseded
}

public struct ClawMemoryItem: Codable, Identifiable, Equatable {
  public var id: UUID
  public var kind: ClawMemoryKind
  public var scope: String
  public var subjectID: UUID?
  public var content: String
  public var normalizedKey: String?
  public var sourceType: String
  public var sourceRef: String?
  public var confidence: Double
  public var createdAt: Date
  public var updatedAt: Date
  public var lastObservedAt: Date
  public var status: ClawMemoryStatus

  public init(
    id: UUID = UUID(),
    kind: ClawMemoryKind,
    scope: String = "global",
    subjectID: UUID? = nil,
    content: String,
    normalizedKey: String? = nil,
    sourceType: String,
    sourceRef: String? = nil,
    confidence: Double = 1,
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    lastObservedAt: Date = Date(),
    status: ClawMemoryStatus = .active
  ) {
    self.id = id
    self.kind = kind
    self.scope = scope
    self.subjectID = subjectID
    self.content = content
    self.normalizedKey = normalizedKey
    self.sourceType = sourceType
    self.sourceRef = sourceRef
    self.confidence = confidence
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.lastObservedAt = lastObservedAt
    self.status = status
  }
}

public enum ClawConversationSpeaker: String, Codable {
  case me
  case other
  case assistant
  case system
  case unknown
}

public struct ClawConversationMessage: Codable, Identifiable, Equatable {
  public var id: UUID
  public var contactID: UUID?
  public var speaker: ClawConversationSpeaker
  public var senderName: String?
  public var content: String
  public var occurredAt: Date
  public var sourceType: String
  public var sourceRef: String?
  public var confidence: Double

  public init(
    id: UUID = UUID(),
    contactID: UUID?,
    speaker: ClawConversationSpeaker,
    senderName: String? = nil,
    content: String,
    occurredAt: Date = Date(),
    sourceType: String,
    sourceRef: String? = nil,
    confidence: Double = 1
  ) {
    self.id = id
    self.contactID = contactID
    self.speaker = speaker
    self.senderName = senderName
    self.content = content
    self.occurredAt = occurredAt
    self.sourceType = sourceType
    self.sourceRef = sourceRef
    self.confidence = confidence
  }
}

public enum ClawTaskKind: String, Codable {
  case task
  case commitment
  case waitingFor
  case deadline
  case nextAction
}

public enum ClawTaskStatus: String, Codable {
  case open
  case done
  case cancelled
}

public struct ClawSecretaryTask: Codable, Identifiable, Equatable {
  public var id: UUID
  public var kind: ClawTaskKind
  public var status: ClawTaskStatus
  public var title: String
  public var details: String?
  public var contactID: UUID?
  public var dueAt: Date?
  public var createdAt: Date
  public var sourceType: String
  public var sourceRef: String?

  public init(
    id: UUID = UUID(),
    kind: ClawTaskKind = .task,
    status: ClawTaskStatus = .open,
    title: String,
    details: String? = nil,
    contactID: UUID? = nil,
    dueAt: Date? = nil,
    createdAt: Date = Date(),
    sourceType: String,
    sourceRef: String? = nil
  ) {
    self.id = id
    self.kind = kind
    self.status = status
    self.title = title
    self.details = details
    self.contactID = contactID
    self.dueAt = dueAt
    self.createdAt = createdAt
    self.sourceType = sourceType
    self.sourceRef = sourceRef
  }
}

public struct ClawSkillDefinition: Codable, Identifiable, Equatable {
  public var id: String
  public var name: String
  public var summary: String
  public var systemPrompt: String
  public var version: Int
  public var enabled: Bool
  public var permissions: [String]
  public var acceptedCount: Int
  public var regeneratedCount: Int
  public var editedCount: Int

  public init(
    id: String,
    name: String,
    summary: String,
    systemPrompt: String,
    version: Int = 1,
    enabled: Bool = true,
    permissions: [String] = [],
    acceptedCount: Int = 0,
    regeneratedCount: Int = 0,
    editedCount: Int = 0
  ) {
    self.id = id
    self.name = name
    self.summary = summary
    self.systemPrompt = systemPrompt
    self.version = version
    self.enabled = enabled
    self.permissions = permissions
    self.acceptedCount = acceptedCount
    self.regeneratedCount = regeneratedCount
    self.editedCount = editedCount
  }
}

public enum ClawFeedbackAction: String, Codable {
  case accepted
  case edited
  case regenerated
  case dismissed
}

public struct ClawEvolutionFeedback: Codable, Identifiable, Equatable {
  public var id: UUID
  public var skillID: String
  public var contactID: UUID?
  public var action: ClawFeedbackAction
  public var originalText: String?
  public var finalText: String?
  public var createdAt: Date

  public init(
    id: UUID = UUID(),
    skillID: String,
    contactID: UUID? = nil,
    action: ClawFeedbackAction,
    originalText: String? = nil,
    finalText: String? = nil,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.skillID = skillID
    self.contactID = contactID
    self.action = action
    self.originalText = originalText
    self.finalText = finalText
    self.createdAt = createdAt
  }
}

public enum ClawMemoryStoreError: Error, LocalizedError {
  case databaseUnavailable
  case sqlite(message: String)

  public var errorDescription: String? {
    switch self {
    case .databaseUnavailable: return "CLAW Memory database is unavailable"
    case .sqlite(let message): return message
    }
  }
}

/// 手机 CLAW 的结构化记忆源。主 App 与键盘扩展通过 App Group 共享同一个 SQLite 数据库。
public final class ClawMemoryStore {
  public static let shared = ClawMemoryStore()

  private var db: OpaquePointer?
  private let lock = NSRecursiveLock()
  public let databaseURL: URL

  public convenience init() {
    let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: HamsterConstants.appGroupName)
    let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    self.init(databaseURL: (groupURL ?? fallback).appendingPathComponent("claw-memory.sqlite"))
  }

  public init(databaseURL: URL) {
    self.databaseURL = databaseURL
    try? FileManager.default.createDirectory(
      at: databaseURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    openDatabase()
    migrate()
    seedBuiltInSkillsIfNeeded()
  }

  deinit {
    if let db { sqlite3_close(db) }
  }

  private func openDatabase() {
    guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
      db = nil
      return
    }
    _ = sqlite3_busy_timeout(db, 3_000)
    try? execute("PRAGMA journal_mode=WAL;")
    try? execute("PRAGMA synchronous=NORMAL;")
    try? execute("PRAGMA foreign_keys=ON;")
  }

  private func migrate() {
    let statements = [
      """
      CREATE TABLE IF NOT EXISTS memory_items (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        scope TEXT NOT NULL,
        subject_id TEXT,
        content TEXT NOT NULL,
        normalized_key TEXT,
        source_type TEXT NOT NULL,
        source_ref TEXT,
        confidence REAL NOT NULL,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL,
        last_observed_at REAL NOT NULL,
        status TEXT NOT NULL
      );
      """,
      "CREATE INDEX IF NOT EXISTS idx_memory_scope ON memory_items(scope, subject_id, status);",
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_memory_dedupe ON memory_items(kind, scope, IFNULL(subject_id,''), IFNULL(normalized_key,''), content);",
      """
      CREATE TABLE IF NOT EXISTS conversation_messages (
        id TEXT PRIMARY KEY,
        contact_id TEXT,
        speaker TEXT NOT NULL,
        sender_name TEXT,
        content TEXT NOT NULL,
        occurred_at REAL NOT NULL,
        source_type TEXT NOT NULL,
        source_ref TEXT,
        confidence REAL NOT NULL,
        fingerprint TEXT NOT NULL UNIQUE
      );
      """,
      "CREATE INDEX IF NOT EXISTS idx_conversation_contact_time ON conversation_messages(contact_id, occurred_at DESC);",
      """
      CREATE TABLE IF NOT EXISTS secretary_tasks (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        status TEXT NOT NULL,
        title TEXT NOT NULL,
        details TEXT,
        contact_id TEXT,
        due_at REAL,
        created_at REAL NOT NULL,
        source_type TEXT NOT NULL,
        source_ref TEXT
      );
      """,
      "CREATE INDEX IF NOT EXISTS idx_tasks_status_due ON secretary_tasks(status, due_at);",
      """
      CREATE TABLE IF NOT EXISTS skills (
        id TEXT PRIMARY KEY,
        payload BLOB NOT NULL,
        updated_at REAL NOT NULL
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS evolution_feedback (
        id TEXT PRIMARY KEY,
        skill_id TEXT NOT NULL,
        contact_id TEXT,
        action TEXT NOT NULL,
        original_text TEXT,
        final_text TEXT,
        created_at REAL NOT NULL
      );
      """
    ]
    for statement in statements { try? execute(statement) }
  }

  private func requireDB() throws -> OpaquePointer {
    guard let db else { throw ClawMemoryStoreError.databaseUnavailable }
    return db
  }

  private func execute(_ sql: String) throws {
    lock.lock(); defer { lock.unlock() }
    let db = try requireDB()
    var error: UnsafeMutablePointer<Int8>?
    guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
      let message = error.map { String(cString: $0) } ?? "SQLite error"
      sqlite3_free(error)
      throw ClawMemoryStoreError.sqlite(message: message)
    }
  }

  private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  private func bindText(_ value: String?, at index: Int32, in statement: OpaquePointer?) {
    if let value {
      value.withCString { pointer in
        _ = sqlite3_bind_text(statement, index, pointer, -1, transient)
      }
    } else {
      sqlite3_bind_null(statement, index)
    }
  }

  private func text(_ statement: OpaquePointer?, _ index: Int32) -> String? {
    guard let ptr = sqlite3_column_text(statement, index) else { return nil }
    return String(cString: ptr)
  }

  private func prepare(_ sql: String) throws -> OpaquePointer? {
    let db = try requireDB()
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw ClawMemoryStoreError.sqlite(message: String(cString: sqlite3_errmsg(db)))
    }
    return statement
  }

  @discardableResult
  public func upsertMemory(_ item: ClawMemoryItem) throws -> ClawMemoryItem {
    lock.lock(); defer { lock.unlock() }
    let sql = """
      INSERT INTO memory_items
      (id,kind,scope,subject_id,content,normalized_key,source_type,source_ref,confidence,created_at,updated_at,last_observed_at,status)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET kind=excluded.kind,scope=excluded.scope,subject_id=excluded.subject_id,
      content=excluded.content,normalized_key=excluded.normalized_key,source_type=excluded.source_type,
      source_ref=excluded.source_ref,confidence=excluded.confidence,updated_at=excluded.updated_at,
      last_observed_at=excluded.last_observed_at,status=excluded.status;
    """
    let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
    bindText(item.id.uuidString, at: 1, in: statement)
    bindText(item.kind.rawValue, at: 2, in: statement)
    bindText(item.scope, at: 3, in: statement)
    bindText(item.subjectID?.uuidString, at: 4, in: statement)
    bindText(item.content, at: 5, in: statement)
    bindText(item.normalizedKey, at: 6, in: statement)
    bindText(item.sourceType, at: 7, in: statement)
    bindText(item.sourceRef, at: 8, in: statement)
    sqlite3_bind_double(statement, 9, item.confidence)
    sqlite3_bind_double(statement, 10, item.createdAt.timeIntervalSince1970)
    sqlite3_bind_double(statement, 11, item.updatedAt.timeIntervalSince1970)
    sqlite3_bind_double(statement, 12, item.lastObservedAt.timeIntervalSince1970)
    bindText(item.status.rawValue, at: 13, in: statement)
    let rc = sqlite3_step(statement)
    if rc != SQLITE_DONE && rc != SQLITE_CONSTRAINT {
      throw ClawMemoryStoreError.sqlite(message: String(cString: sqlite3_errmsg(try requireDB())))
    }
    return item
  }

  public func memories(scope: String? = nil, subjectID: UUID? = nil, limit: Int = 200) throws -> [ClawMemoryItem] {
    lock.lock(); defer { lock.unlock() }
    var clauses = ["status = 'active'"]
    if scope != nil { clauses.append("scope = ?") }
    if subjectID != nil { clauses.append("subject_id = ?") }
    let sql = "SELECT id,kind,scope,subject_id,content,normalized_key,source_type,source_ref,confidence,created_at,updated_at,last_observed_at,status FROM memory_items WHERE \(clauses.joined(separator: " AND ")) ORDER BY last_observed_at DESC LIMIT ?;"
    let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
    var index: Int32 = 1
    if let scope { bindText(scope, at: index, in: statement); index += 1 }
    if let subjectID { bindText(subjectID.uuidString, at: index, in: statement); index += 1 }
    sqlite3_bind_int(statement, index, Int32(max(1, limit)))
    var result: [ClawMemoryItem] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let idText = text(statement, 0), let id = UUID(uuidString: idText),
            let kindText = text(statement, 1), let kind = ClawMemoryKind(rawValue: kindText),
            let statusText = text(statement, 12), let status = ClawMemoryStatus(rawValue: statusText),
            let content = text(statement, 4), let sourceType = text(statement, 6)
      else { continue }
      result.append(ClawMemoryItem(
        id: id,
        kind: kind,
        scope: text(statement, 2) ?? "global",
        subjectID: text(statement, 3).flatMap(UUID.init(uuidString:)),
        content: content,
        normalizedKey: text(statement, 5),
        sourceType: sourceType,
        sourceRef: text(statement, 7),
        confidence: sqlite3_column_double(statement, 8),
        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
        updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 10)),
        lastObservedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 11)),
        status: status
      ))
    }
    return result
  }

  @discardableResult
  public func appendConversation(_ message: ClawConversationMessage) throws -> Bool {
    let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    lock.lock(); defer { lock.unlock() }
    let fingerprint = Self.fingerprint(
      contactID: message.contactID,
      speaker: message.speaker,
      content: trimmed,
      occurredAt: message.occurredAt
    )
    let sql = "INSERT OR IGNORE INTO conversation_messages (id,contact_id,speaker,sender_name,content,occurred_at,source_type,source_ref,confidence,fingerprint) VALUES (?,?,?,?,?,?,?,?,?,?);"
    let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
    bindText(message.id.uuidString, at: 1, in: statement)
    bindText(message.contactID?.uuidString, at: 2, in: statement)
    bindText(message.speaker.rawValue, at: 3, in: statement)
    bindText(message.senderName, at: 4, in: statement)
    bindText(trimmed, at: 5, in: statement)
    sqlite3_bind_double(statement, 6, message.occurredAt.timeIntervalSince1970)
    bindText(message.sourceType, at: 7, in: statement)
    bindText(message.sourceRef, at: 8, in: statement)
    sqlite3_bind_double(statement, 9, message.confidence)
    bindText(fingerprint, at: 10, in: statement)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw ClawMemoryStoreError.sqlite(message: String(cString: sqlite3_errmsg(try requireDB())))
    }
    return sqlite3_changes(try requireDB()) > 0
  }

  public func conversation(contactID: UUID?, limit: Int = 80) throws -> [ClawConversationMessage] {
    lock.lock(); defer { lock.unlock() }
    let sql: String
    if contactID == nil {
      sql = "SELECT id,contact_id,speaker,sender_name,content,occurred_at,source_type,source_ref,confidence FROM conversation_messages WHERE contact_id IS NULL ORDER BY occurred_at DESC LIMIT ?;"
    } else {
      sql = "SELECT id,contact_id,speaker,sender_name,content,occurred_at,source_type,source_ref,confidence FROM conversation_messages WHERE contact_id = ? ORDER BY occurred_at DESC LIMIT ?;"
    }
    let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
    var index: Int32 = 1
    if let contactID { bindText(contactID.uuidString, at: index, in: statement); index += 1 }
    sqlite3_bind_int(statement, index, Int32(max(1, limit)))
    var rows: [ClawConversationMessage] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let idText = text(statement, 0), let id = UUID(uuidString: idText),
            let speakerText = text(statement, 2), let speaker = ClawConversationSpeaker(rawValue: speakerText),
            let content = text(statement, 4), let sourceType = text(statement, 6)
      else { continue }
      rows.append(ClawConversationMessage(
        id: id,
        contactID: text(statement, 1).flatMap(UUID.init(uuidString:)),
        speaker: speaker,
        senderName: text(statement, 3),
        content: content,
        occurredAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
        sourceType: sourceType,
        sourceRef: text(statement, 7),
        confidence: sqlite3_column_double(statement, 8)
      ))
    }
    return rows.reversed()
  }

  @discardableResult
  public func upsertTask(_ task: ClawSecretaryTask) throws -> ClawSecretaryTask {
    lock.lock(); defer { lock.unlock() }
    let sql = """
      INSERT INTO secretary_tasks (id,kind,status,title,details,contact_id,due_at,created_at,source_type,source_ref)
      VALUES (?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET kind=excluded.kind,status=excluded.status,title=excluded.title,
      details=excluded.details,contact_id=excluded.contact_id,due_at=excluded.due_at,source_type=excluded.source_type,source_ref=excluded.source_ref;
    """
    let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
    bindText(task.id.uuidString, at: 1, in: statement)
    bindText(task.kind.rawValue, at: 2, in: statement)
    bindText(task.status.rawValue, at: 3, in: statement)
    bindText(task.title, at: 4, in: statement)
    bindText(task.details, at: 5, in: statement)
    bindText(task.contactID?.uuidString, at: 6, in: statement)
    if let dueAt = task.dueAt { sqlite3_bind_double(statement, 7, dueAt.timeIntervalSince1970) } else { sqlite3_bind_null(statement, 7) }
    sqlite3_bind_double(statement, 8, task.createdAt.timeIntervalSince1970)
    bindText(task.sourceType, at: 9, in: statement)
    bindText(task.sourceRef, at: 10, in: statement)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw ClawMemoryStoreError.sqlite(message: String(cString: sqlite3_errmsg(try requireDB())))
    }
    return task
  }

  public func tasks(status: ClawTaskStatus = .open, limit: Int = 100) throws -> [ClawSecretaryTask] {
    lock.lock(); defer { lock.unlock() }
    let sql = "SELECT id,kind,status,title,details,contact_id,due_at,created_at,source_type,source_ref FROM secretary_tasks WHERE status = ? ORDER BY CASE WHEN due_at IS NULL THEN 1 ELSE 0 END, due_at ASC, created_at DESC LIMIT ?;"
    let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
    bindText(status.rawValue, at: 1, in: statement)
    sqlite3_bind_int(statement, 2, Int32(max(1, limit)))
    var result: [ClawSecretaryTask] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let idText = text(statement, 0), let id = UUID(uuidString: idText),
            let kindText = text(statement, 1), let kind = ClawTaskKind(rawValue: kindText),
            let statusText = text(statement, 2), let rowStatus = ClawTaskStatus(rawValue: statusText),
            let title = text(statement, 3), let sourceType = text(statement, 8)
      else { continue }
      let dueAt = sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
      result.append(ClawSecretaryTask(
        id: id, kind: kind, status: rowStatus, title: title, details: text(statement, 4),
        contactID: text(statement, 5).flatMap(UUID.init(uuidString:)), dueAt: dueAt,
        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 7)), sourceType: sourceType, sourceRef: text(statement, 9)
      ))
    }
    return result
  }

  public func saveSkill(_ skill: ClawSkillDefinition) throws {
    lock.lock(); defer { lock.unlock() }
    let payload = try JSONEncoder().encode(skill)
    let sql = "INSERT INTO skills (id,payload,updated_at) VALUES (?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload,updated_at=excluded.updated_at;"
    let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
    bindText(skill.id, at: 1, in: statement)
    payload.withUnsafeBytes { bytes in
      _ = sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(payload.count), transient)
    }
    sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw ClawMemoryStoreError.sqlite(message: String(cString: sqlite3_errmsg(try requireDB())))
    }
  }

  public func skills() throws -> [ClawSkillDefinition] {
    lock.lock(); defer { lock.unlock() }
    let statement = try prepare("SELECT payload FROM skills ORDER BY id;"); defer { sqlite3_finalize(statement) }
    var result: [ClawSkillDefinition] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let blob = sqlite3_column_blob(statement, 0) else { continue }
      let count = Int(sqlite3_column_bytes(statement, 0))
      let data = Data(bytes: blob, count: count)
      if let skill = try? JSONDecoder().decode(ClawSkillDefinition.self, from: data) { result.append(skill) }
    }
    return result
  }

  public func recordFeedback(_ feedback: ClawEvolutionFeedback) throws {
    lock.lock(); defer { lock.unlock() }
    let statement = try prepare("INSERT INTO evolution_feedback (id,skill_id,contact_id,action,original_text,final_text,created_at) VALUES (?,?,?,?,?,?,?);")
    defer { sqlite3_finalize(statement) }
    bindText(feedback.id.uuidString, at: 1, in: statement)
    bindText(feedback.skillID, at: 2, in: statement)
    bindText(feedback.contactID?.uuidString, at: 3, in: statement)
    bindText(feedback.action.rawValue, at: 4, in: statement)
    bindText(feedback.originalText, at: 5, in: statement)
    bindText(feedback.finalText, at: 6, in: statement)
    sqlite3_bind_double(statement, 7, feedback.createdAt.timeIntervalSince1970)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw ClawMemoryStoreError.sqlite(message: String(cString: sqlite3_errmsg(try requireDB())))
    }
    if var skill = try skills().first(where: { $0.id == feedback.skillID }) {
      switch feedback.action {
      case .accepted: skill.acceptedCount += 1
      case .edited: skill.editedCount += 1
      case .regenerated: skill.regeneratedCount += 1
      case .dismissed: break
      }
      try saveSkill(skill)
    }
  }

  private func seedBuiltInSkillsIfNeeded() {
    guard (try? skills().isEmpty) == true else { return }
    let builtIns = [
      ClawSkillDefinition(id: "reply", name: "帮你回", summary: "结合当前聊天、对象关系与用户表达习惯生成回复", systemPrompt: "理解对方真实意图和情绪，生成自然、简洁、像用户本人会说的话。", permissions: ["memory.global", "memory.contact", "conversation.current"]),
      ClawSkillDefinition(id: "rewrite", name: "超会说", summary: "保留原意并优化表达", systemPrompt: "保留用户原意，减少 AI 腔，让表达自然、有分寸，并优先遵循用户长期语言习惯。", permissions: ["memory.global", "memory.contact"]),
      ClawSkillDefinition(id: "screenshot-chat", name: "聊天截图理解", summary: "把聊天截图转成结构化时间线", systemPrompt: "识别聊天对象、发言方、顺序、时间和正文，不臆造不可见内容。", permissions: ["photos.selected", "memory.contact"]),
      ClawSkillDefinition(id: "contact-profile", name: "人物画像", summary: "从有来源的互动中更新联系人画像", systemPrompt: "只从可追溯证据提炼稳定特征，区分事实与推断。", permissions: ["memory.contact"]),
      ClawSkillDefinition(id: "task-extract", name: "任务提取", summary: "从对话识别承诺、等待、截止日期和下一步", systemPrompt: "只在语义足够明确时创建任务或承诺，并保留来源。", permissions: ["conversation.current", "tasks.write"]),
      ClawSkillDefinition(id: "daily-secretary", name: "今日秘书", summary: "整理当天重要事项和下一步", systemPrompt: "优先未完成承诺、截止日期、等待回复和高相关近期事件，避免无意义打扰。", permissions: ["memory.global", "memory.contact", "tasks.read"]),
    ]
    for skill in builtIns { try? saveSkill(skill) }
  }

  private static func fingerprint(contactID: UUID?, speaker: ClawConversationSpeaker, content: String, occurredAt: Date) -> String {
    // 截图往往没有精确时间。以分钟粒度 + 正文去重，避免连续截图重复写入。
    let minute = Int(occurredAt.timeIntervalSince1970 / 60)
    let normalized = content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    return "\(contactID?.uuidString ?? "global")|\(speaker.rawValue)|\(minute)|\(normalized)"
  }
}
Process exited with code 0.