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
  /// 手机端 Evolution Engine 从真实采用结果中学习出的附加规则。
  public var learnedDirective: String?
  public var acceptedCount: Int
  public var regeneratedCount: Int
  public var editedCount: Int
  /// Optional declarative runtime metadata. Missing fields keep older saved Skills compatible.
  public var triggers: [ClawSkillTrigger]?
  public var workflow: [ClawSkillStep]?
  public var toolIDs: [String]?
  /// Human-readable contracts used by the declarative runtime and import UI.
  public var inputContract: String?
  public var outputContract: String?

  public init(
    id: String,
    name: String,
    summary: String,
    systemPrompt: String,
    version: Int = 1,
    enabled: Bool = true,
    permissions: [String] = [],
    learnedDirective: String? = nil,
    acceptedCount: Int = 0,
    regeneratedCount: Int = 0,
    editedCount: Int = 0,
    triggers: [ClawSkillTrigger]? = nil,
    workflow: [ClawSkillStep]? = nil,
    toolIDs: [String]? = nil,
    inputContract: String? = nil,
    outputContract: String? = nil
  ) {
    self.id = id
    self.name = name
    self.summary = summary
    self.systemPrompt = systemPrompt
    self.version = version
    self.enabled = enabled
    self.permissions = permissions
    self.learnedDirective = learnedDirective
    self.acceptedCount = acceptedCount
    self.regeneratedCount = regeneratedCount
    self.editedCount = editedCount
    self.triggers = triggers
    self.workflow = workflow
    self.toolIDs = toolIDs
    self.inputContract = inputContract
    self.outputContract = outputContract
  }

  public var effectivePrompt: String {
    guard let learnedDirective, !learnedDirective.isEmpty else { return systemPrompt }
    return systemPrompt + "\n\n用户长期反馈学习规则：\n" + learnedDirective
  }
}

public enum ClawSkillTrigger: String, Codable, CaseIterable {
  case manual
  case keyboardHelpReply
  case keyboardRewrite
  case screenshotImported
  case assistant
  case dailyReview
}

public enum ClawSkillStepKind: String, Codable {
  case context
  case instruction
  case tool
}

/// Declarative-only step interpreted by CLAW's built-in runtime. It never executes downloaded Swift/scripts.
public struct ClawSkillStep: Codable, Equatable, Identifiable {
  public var id: UUID
  public var kind: ClawSkillStepKind
  public var value: String

  public init(id: UUID = UUID(), kind: ClawSkillStepKind, value: String) {
    self.id = id
    self.kind = kind
    self.value = value
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
      """,
      """
      CREATE TABLE IF NOT EXISTS raw_events (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        content TEXT NOT NULL,
        source_app TEXT,
        source_ref TEXT,
        occurred_at REAL NOT NULL,
        ingested_at REAL NOT NULL,
        idempotency_key TEXT
      );
      """,
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_raw_events_idem ON raw_events(idempotency_key) WHERE idempotency_key IS NOT NULL;",
      """
      CREATE TABLE IF NOT EXISTS memory_v2 (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        state TEXT NOT NULL,
        scope TEXT NOT NULL,
        content TEXT NOT NULL,
        normalized_key TEXT,
        person_id TEXT,
        project_id TEXT,
        session_id TEXT,
        confidence REAL NOT NULL,
        importance REAL NOT NULL,
        cloud_permission TEXT NOT NULL,
        version INTEGER NOT NULL,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL,
        confirmed_at REAL,
        expires_at REAL,
        payload BLOB NOT NULL
      );
      """,
      "CREATE INDEX IF NOT EXISTS idx_memory_v2_scope ON memory_v2(scope, person_id, state);",
      "CREATE INDEX IF NOT EXISTS idx_memory_v2_updated ON memory_v2(type, updated_at DESC);",
      "CREATE VIRTUAL TABLE IF NOT EXISTS memory_v2_fts USING fts5(id UNINDEXED, content, normalized_key);",
      """
      CREATE TABLE IF NOT EXISTS memory_evidence (
        id TEXT PRIMARY KEY,
        memory_id TEXT NOT NULL,
        raw_event_id TEXT NOT NULL,
        locator TEXT,
        excerpt TEXT
      );
      """,
      "CREATE INDEX IF NOT EXISTS idx_memory_evidence_memory ON memory_evidence(memory_id);",
      """
      CREATE TABLE IF NOT EXISTS memory_versions (
        id TEXT PRIMARY KEY,
        memory_id TEXT NOT NULL,
        version INTEGER NOT NULL,
        payload BLOB NOT NULL,
        created_at REAL NOT NULL
      );
      """,
      "CREATE INDEX IF NOT EXISTS idx_memory_versions_memory ON memory_versions(memory_id, version DESC);",
      """
      CREATE TABLE IF NOT EXISTS memory_lineage (
        id TEXT PRIMARY KEY,
        memory_id TEXT NOT NULL,
        parent_memory_id TEXT,
        raw_event_id TEXT,
        source_memory_id TEXT
      );
      """,
      "CREATE INDEX IF NOT EXISTS idx_memory_lineage_memory ON memory_lineage(memory_id);",
      """
      CREATE TABLE IF NOT EXISTS memory_audit (
        id TEXT PRIMARY KEY,
        memory_id TEXT NOT NULL,
        run_id TEXT,
        kind TEXT NOT NULL,
        payload BLOB NOT NULL,
        created_at REAL NOT NULL
      );
      """,
      "CREATE INDEX IF NOT EXISTS idx_memory_audit_memory ON memory_audit(memory_id, created_at);",
      "CREATE INDEX IF NOT EXISTS idx_memory_audit_run ON memory_audit(run_id, created_at);",
      """
      CREATE TABLE IF NOT EXISTS standing_intents (
        id TEXT PRIMARY KEY,
        payload BLOB NOT NULL,
        is_active INTEGER NOT NULL,
        expires_at REAL,
        created_at REAL NOT NULL
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS memory_conflicts (
        id TEXT PRIMARY KEY,
        payload BLOB NOT NULL,
        is_resolved INTEGER NOT NULL,
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
    try executeUnlocked(sql)
  }

  private func executeUnlocked(_ sql: String) throws {
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
    try upsertMemoryUnlocked(item)
    return item
  }

  private func upsertMemoryUnlocked(_ item: ClawMemoryItem) throws {
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
  }

  public func memories(scope: String? = nil, subjectID: UUID? = nil, limit: Int = 200) throws -> [ClawMemoryItem] {
    try loadMemories(scope: scope, subjectID: subjectID, limit: max(1, limit))
  }

  /// Returns every active memory matching the optional scope without applying a UI-oriented limit.
  public func allMemories(scope: String? = nil, subjectID: UUID? = nil) throws -> [ClawMemoryItem] {
    try loadMemories(scope: scope, subjectID: subjectID, limit: nil)
  }

  /// Includes archived and superseded rows for one-time V2 migration and audit tools.
  public func allMemoryItems() throws -> [ClawMemoryItem] {
    try loadMemories(scope: nil, subjectID: nil, limit: nil, activeOnly: false)
  }

  public func memoryCount(scope: String? = nil, subjectID: UUID? = nil) throws -> Int {
    lock.lock(); defer { lock.unlock() }
    var clauses = ["status = 'active'"]
    if scope != nil { clauses.append("scope = ?") }
    if subjectID != nil { clauses.append("subject_id = ?") }
    let sql = "SELECT COUNT(*) FROM memory_items WHERE \(clauses.joined(separator: " AND "));"
    let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
    var index: Int32 = 1
    if let scope { bindText(scope, at: index, in: statement); index += 1 }
    if let subjectID { bindText(subjectID.uuidString, at: index, in: statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
    return Int(sqlite3_column_int64(statement, 0))
  }

  public func activeMemoryCount(ids: Set<UUID>) throws -> Int {
    guard !ids.isEmpty else { return 0 }
    lock.lock(); defer { lock.unlock() }
    let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
    let statement = try prepare(
      "SELECT COUNT(*) FROM memory_items WHERE status = 'active' AND id IN (\(placeholders));"
    )
    defer { sqlite3_finalize(statement) }
    for (offset, id) in ids.enumerated() {
      bindText(id.uuidString, at: Int32(offset + 1), in: statement)
    }
    guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
    return Int(sqlite3_column_int64(statement, 0))
  }

  public func activeMemorySourceTypes() throws -> [String] {
    lock.lock(); defer { lock.unlock() }
    let statement = try prepare(
      "SELECT DISTINCT source_type FROM memory_items WHERE status = 'active' ORDER BY source_type COLLATE NOCASE;"
    )
    defer { sqlite3_finalize(statement) }
    var result: [String] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      if let sourceType = text(statement, 0), !sourceType.isEmpty {
        result.append(sourceType)
      }
    }
    return result
  }

  private func loadMemories(
    scope: String?,
    subjectID: UUID?,
    limit: Int?,
    activeOnly: Bool = true
  ) throws -> [ClawMemoryItem] {
    lock.lock(); defer { lock.unlock() }
    var clauses: [String] = activeOnly ? ["status = 'active'"] : []
    if scope != nil { clauses.append("scope = ?") }
    if subjectID != nil { clauses.append("subject_id = ?") }
    let limitClause = limit == nil ? "" : " LIMIT ?"
    let whereClause = clauses.isEmpty ? "" : " WHERE \(clauses.joined(separator: " AND "))"
    let sql = "SELECT id,kind,scope,subject_id,content,normalized_key,source_type,source_ref,confidence,created_at,updated_at,last_observed_at,status FROM memory_items\(whereClause) ORDER BY last_observed_at DESC\(limitClause);"
    let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
    var index: Int32 = 1
    if let scope { bindText(scope, at: index, in: statement); index += 1 }
    if let subjectID { bindText(subjectID.uuidString, at: index, in: statement); index += 1 }
    if let limit { sqlite3_bind_int(statement, index, Int32(limit)) }
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

  public func memory(id: UUID) throws -> ClawMemoryItem? {
    try memories(limit: 50_000).first(where: { $0.id == id })
  }

  @discardableResult
  public func updateMemory(id: UUID, content: String, confidence: Double? = nil) throws -> Bool {
    guard var item = try memory(id: id) else { return false }
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    item.content = trimmed
    item.confidence = confidence ?? item.confidence
    item.updatedAt = Date()
    item.lastObservedAt = Date()
    try upsertMemory(item)
    return true
  }

  @discardableResult
  public func setMemoryStatus(id: UUID, status: ClawMemoryStatus) throws -> Bool {
    lock.lock(); defer { lock.unlock() }
    let statement = try prepare("UPDATE memory_items SET status = ?, updated_at = ? WHERE id = ?;")
    defer { sqlite3_finalize(statement) }
    bindText(status.rawValue, at: 1, in: statement)
    sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
    bindText(id.uuidString, at: 3, in: statement)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw ClawMemoryStoreError.sqlite(message: String(cString: sqlite3_errmsg(try requireDB())))
    }
    return sqlite3_changes(try requireDB()) > 0
  }

  @discardableResult
  public func deleteMemory(id: UUID) throws -> Bool {
    lock.lock(); defer { lock.unlock() }
    let statement = try prepare("DELETE FROM memory_items WHERE id = ?;")
    defer { sqlite3_finalize(statement) }
    bindText(id.uuidString, at: 1, in: statement)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw ClawMemoryStoreError.sqlite(message: String(cString: sqlite3_errmsg(try requireDB())))
    }
    return sqlite3_changes(try requireDB()) > 0
  }

  @discardableResult
  public func deleteMemories(sourceType: String) throws -> Int {
    lock.lock(); defer { lock.unlock() }
    let statement = try prepare("DELETE FROM memory_items WHERE source_type = ?;")
    defer { sqlite3_finalize(statement) }
    bindText(sourceType, at: 1, in: statement)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw ClawMemoryStoreError.sqlite(message: String(cString: sqlite3_errmsg(try requireDB())))
    }
    return Int(sqlite3_changes(try requireDB()))
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

  /// Full timeline across all contacts, used only for explicit backup/export flows.
  public func allConversation(limit: Int = 20_000) throws -> [ClawConversationMessage] {
    lock.lock(); defer { lock.unlock() }
    let statement = try prepare("SELECT id,contact_id,speaker,sender_name,content,occurred_at,source_type,source_ref,confidence FROM conversation_messages ORDER BY occurred_at ASC LIMIT ?;")
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_int(statement, 1, Int32(max(1, limit)))
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
    return rows
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

  public func tasks(status: ClawTaskStatus? = .open, limit: Int = 100) throws -> [ClawSecretaryTask] {
    lock.lock(); defer { lock.unlock() }
    let whereClause = status == nil ? "" : " WHERE status = ?"
    let sql = "SELECT id,kind,status,title,details,contact_id,due_at,created_at,source_type,source_ref FROM secretary_tasks\(whereClause) ORDER BY CASE WHEN due_at IS NULL THEN 1 ELSE 0 END, due_at ASC, created_at DESC LIMIT ?;"
    let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
    var index: Int32 = 1
    if let status { bindText(status.rawValue, at: index, in: statement); index += 1 }
    sqlite3_bind_int(statement, index, Int32(max(1, limit)))
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

  public func allTasks() throws -> [ClawSecretaryTask] {
    try tasks(status: nil, limit: 20_000)
  }

  @discardableResult
  public func setTaskStatus(id: UUID, status: ClawTaskStatus) throws -> Bool {
    lock.lock(); defer { lock.unlock() }
    let statement = try prepare("UPDATE secretary_tasks SET status = ? WHERE id = ?;")
    defer { sqlite3_finalize(statement) }
    bindText(status.rawValue, at: 1, in: statement)
    bindText(id.uuidString, at: 2, in: statement)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw ClawMemoryStoreError.sqlite(message: String(cString: sqlite3_errmsg(try requireDB())))
    }
    return sqlite3_changes(try requireDB()) > 0
  }

  @discardableResult
  public func snoozeTask(id: UUID, until: Date) throws -> Bool {
    lock.lock(); defer { lock.unlock() }
    let statement = try prepare("UPDATE secretary_tasks SET due_at = ? WHERE id = ?;")
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_double(statement, 1, until.timeIntervalSince1970)
    bindText(id.uuidString, at: 2, in: statement)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw ClawMemoryStoreError.sqlite(message: String(cString: sqlite3_errmsg(try requireDB())))
    }
    return sqlite3_changes(try requireDB()) > 0
  }

  /// Reassigns every contact-bound record atomically. Passing `nil` preserves
  /// the records as global data when a profile is deleted.
  public func reassignContactReferences(from sourceID: UUID, to destinationID: UUID?) throws {
    guard sourceID != destinationID else { return }
    lock.lock(); defer { lock.unlock() }
    try executeUnlocked("BEGIN IMMEDIATE;")
    do {
      try rebindContactColumn(
        table: "memory_items",
        column: "subject_id",
        sourceID: sourceID,
        destinationID: destinationID,
        additionalSet: destinationID == nil ? ", scope = 'global'" : ""
      )
      try rebindContactColumn(table: "conversation_messages", column: "contact_id", sourceID: sourceID, destinationID: destinationID)
      try rebindContactColumn(table: "secretary_tasks", column: "contact_id", sourceID: sourceID, destinationID: destinationID)
      try rebindContactColumn(table: "evolution_feedback", column: "contact_id", sourceID: sourceID, destinationID: destinationID)
      try reassignMemoryV2Contacts(from: sourceID, to: destinationID)
      try executeUnlocked("COMMIT;")
    } catch {
      try? executeUnlocked("ROLLBACK;")
      throw error
    }
  }

  private func rebindContactColumn(
    table: String,
    column: String,
    sourceID: UUID,
    destinationID: UUID?,
    additionalSet: String = ""
  ) throws {
    // Table and column names are fixed internal call-site constants above.
    let statement = try prepare("UPDATE \(table) SET \(column) = ?\(additionalSet) WHERE \(column) = ?;")
    defer { sqlite3_finalize(statement) }
    bindText(destinationID?.uuidString, at: 1, in: statement)
    bindText(sourceID.uuidString, at: 2, in: statement)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw ClawMemoryStoreError.sqlite(message: String(cString: sqlite3_errmsg(try requireDB())))
    }
  }

  private func reassignMemoryV2Contacts(from sourceID: UUID, to destinationID: UUID?) throws {
    let select = try prepare("SELECT payload FROM memory_v2 WHERE person_id = ?;")
    bindText(sourceID.uuidString, at: 1, in: select)
    var records: [MemoryV2Record] = []
    while sqlite3_step(select) == SQLITE_ROW, let blob = sqlite3_column_blob(select, 0) {
      let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(select, 0)))
      if var record = try? JSONDecoder().decode(MemoryV2Record.self, from: data) {
        record.personID = destinationID
        if destinationID == nil, record.scope == .person || record.scope == .relationship {
          record.scope = .global
        }
        record.version += 1
        record.updatedAt = Date()
        records.append(record)
      }
    }
    sqlite3_finalize(select)
    for record in records {
      let payload = try JSONEncoder().encode(record)
      try upsertMemoryV2Row(record, payload: payload)
      try insertMemoryVersion(record, payload: payload)
    }
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

  public func feedback(skillID: String, limit: Int = 200) throws -> [ClawEvolutionFeedback] {
    lock.lock(); defer { lock.unlock() }
    let statement = try prepare("SELECT id,skill_id,contact_id,action,original_text,final_text,created_at FROM evolution_feedback WHERE skill_id = ? ORDER BY created_at DESC LIMIT ?;")
    defer { sqlite3_finalize(statement) }
    bindText(skillID, at: 1, in: statement)
    sqlite3_bind_int(statement, 2, Int32(max(1, limit)))
    var result: [ClawEvolutionFeedback] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let idText = text(statement, 0), let id = UUID(uuidString: idText),
            let storedSkillID = text(statement, 1),
            let actionText = text(statement, 3), let action = ClawFeedbackAction(rawValue: actionText)
      else { continue }
      result.append(ClawEvolutionFeedback(
        id: id,
        skillID: storedSkillID,
        contactID: text(statement, 2).flatMap(UUID.init(uuidString:)),
        action: action,
        originalText: text(statement, 4),
        finalText: text(statement, 5),
        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
      ))
    }
    return result
  }

  /// Deletes every user-owned Memory Core record in one transaction, then restores
  /// the built-in Skill definitions so the store has fresh-install behavior.
  public func clearAllUserData() throws {
    do {
      try execute("""
        BEGIN IMMEDIATE;
        DELETE FROM memory_evidence;
        DELETE FROM memory_versions;
        DELETE FROM memory_lineage;
        DELETE FROM memory_v2_fts;
        DELETE FROM memory_audit;
        DELETE FROM standing_intents;
        DELETE FROM memory_conflicts;
        DELETE FROM memory_v2;
        DELETE FROM raw_events;
        DELETE FROM evolution_feedback;
        DELETE FROM skills;
        DELETE FROM secretary_tasks;
        DELETE FROM conversation_messages;
        DELETE FROM memory_items;
        COMMIT;
        """)
    } catch {
      try? execute("ROLLBACK;")
      throw error
    }
    seedBuiltInSkillsIfNeeded()
  }

  // MARK: - Memory V2

  /// 写入一条结构化记忆，并同步保存版本快照、证据与血缘。
  @discardableResult
  public func saveMemoryV2(
    _ record: MemoryV2Record,
    rawEvents: [RawMemoryEvent] = [],
    legacyProjection: ClawMemoryItem? = nil
  ) throws -> MemoryV2Record {
    lock.lock(); defer { lock.unlock() }
    try executeUnlocked("BEGIN IMMEDIATE;")
    do {
      try insertRawEvents(rawEvents)
      let payload = try JSONEncoder().encode(record)
      try upsertMemoryV2Row(record, payload: payload)
      try insertMemoryVersion(record, payload: payload)
      try replaceMemoryEvidence(record)
      try insertMemoryLineage(record)
      if let legacyProjection { try upsertMemoryUnlocked(legacyProjection) }
      try executeUnlocked("COMMIT;")
      return record
    } catch {
      try? executeUnlocked("ROLLBACK;")
      throw error
    }
  }

  /// 按 id 读取一条 V2 记忆。
  public func memoryV2(id: UUID) throws -> MemoryV2Record? {
    lock.lock(); defer { lock.unlock() }
    let statement = try prepare("SELECT payload FROM memory_v2 WHERE id = ?;")
    defer { sqlite3_finalize(statement) }
    bindText(id.uuidString, at: 1, in: statement)
    guard sqlite3_step(statement) == SQLITE_ROW,
          let blob = sqlite3_column_blob(statement, 0) else { return nil }
    let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 0)))
    return try? JSONDecoder().decode(MemoryV2Record.self, from: data)
  }

  /// 按作用域/人物/状态筛选 V2 记忆，按最近更新排序。
  public func memoryV2(
    scope: MemoryScope? = nil,
    personID: UUID? = nil,
    state: MemoryState? = nil,
    limit: Int = 200
  ) throws -> [MemoryV2Record] {
    lock.lock(); defer { lock.unlock() }
    var sql = "SELECT payload FROM memory_v2 WHERE 1=1"
    if scope != nil { sql += " AND scope = ?" }
    if personID != nil { sql += " AND person_id = ?" }
    if state != nil { sql += " AND state = ?" }
    sql += " ORDER BY updated_at DESC LIMIT ?;"
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    var index: Int32 = 1
    if let scope { bindText(scope.rawValue, at: index, in: statement); index += 1 }
    if let personID { bindText(personID.uuidString, at: index, in: statement); index += 1 }
    if let state { bindText(state.rawValue, at: index, in: statement); index += 1 }
    sqlite3_bind_int(statement, index, Int32(max(1, limit)))
    var result: [MemoryV2Record] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let blob = sqlite3_column_blob(statement, 0) else { continue }
      let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 0)))
      if let record = try? JSONDecoder().decode(MemoryV2Record.self, from: data) {
        result.append(record)
      }
    }
    return result
  }

  /// V2 记忆条数，供迁移与压力测试校验。
  public func memoryV2Count() throws -> Int {
    lock.lock(); defer { lock.unlock() }
    let statement = try prepare("SELECT COUNT(*) FROM memory_v2;")
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
    return Int(sqlite3_column_int(statement, 0))
  }

  public func memoryV2VersionCount(id: UUID) throws -> Int {
    lock.lock(); defer { lock.unlock() }
    let statement = try prepare("SELECT COUNT(*) FROM memory_versions WHERE memory_id = ?;")
    defer { sqlite3_finalize(statement) }
    bindText(id.uuidString, at: 1, in: statement)
    guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
    return Int(sqlite3_column_int(statement, 0))
  }

  /// FTS5-backed candidate collection. The router performs scope guards and
  /// final hybrid ranking. Empty or tokenization-incompatible queries fall back
  /// to the full recent set so CJK and punctuation-heavy input remain usable.
  public func searchMemoryV2(query: String, limit: Int = 200) throws -> [MemoryV2Record] {
    lock.lock(); defer { lock.unlock() }
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return try memoryV2(limit: limit) }
    let tokens = trimmed.split { $0.isWhitespace || $0.isPunctuation }.map { "\($0)*" }
    guard !tokens.isEmpty else { return try memoryV2(limit: limit) }
    let statement: OpaquePointer?
    do {
      statement = try prepare("SELECT memory_v2.payload FROM memory_v2_fts JOIN memory_v2 ON memory_v2.id = memory_v2_fts.id WHERE memory_v2_fts MATCH ? ORDER BY bm25(memory_v2_fts) LIMIT ?;")
    } catch {
      return try memoryV2(limit: limit)
    }
    defer { sqlite3_finalize(statement) }
    bindText(tokens.joined(separator: " OR "), at: 1, in: statement)
    sqlite3_bind_int(statement, 2, Int32(max(1, limit)))
    var result: [MemoryV2Record] = []
    while sqlite3_step(statement) == SQLITE_ROW, let blob = sqlite3_column_blob(statement, 0) {
      let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 0)))
      if let record = try? JSONDecoder().decode(MemoryV2Record.self, from: data) { result.append(record) }
    }
    if result.isEmpty {
      result = try memoryV2(limit: limit).filter { $0.content.localizedCaseInsensitiveContains(trimmed) || ($0.normalizedKey?.localizedCaseInsensitiveContains(trimmed) ?? false) }
    }
    // Include recent non-matches for global defaults; ranking will put matches first.
    let recent = try memoryV2(limit: limit)
    let ids = Set(result.map(\.id))
    result.append(contentsOf: recent.filter { !ids.contains($0.id) })
    return Array(result.prefix(max(1, limit)))
  }

  public func saveMemoryAudit(_ audit: MemoryAuditRecord) throws {
    lock.lock(); defer { lock.unlock() }
    let payload = try JSONEncoder().encode(audit)
    let statement = try prepare("INSERT OR REPLACE INTO memory_audit (id,memory_id,run_id,kind,payload,created_at) VALUES (?,?,?,?,?,?);")
    defer { sqlite3_finalize(statement) }
    bindText(audit.id.uuidString, at: 1, in: statement)
    bindText(audit.memoryID.uuidString, at: 2, in: statement)
    bindText(audit.runID?.uuidString, at: 3, in: statement)
    bindText(audit.kind.rawValue, at: 4, in: statement)
    payload.withUnsafeBytes { _ = sqlite3_bind_blob(statement, 5, $0.baseAddress, Int32(payload.count), transient) }
    sqlite3_bind_double(statement, 6, audit.createdAt.timeIntervalSince1970)
    guard sqlite3_step(statement) == SQLITE_DONE else { throw ClawMemoryStoreError.sqlite(message: String(cString: sqlite3_errmsg(try requireDB()))) }
  }

  public func memoryAuditRecord(id: UUID) throws -> MemoryAuditRecord? {
    lock.lock(); defer { lock.unlock() }
    let statement = try prepare("SELECT payload FROM memory_audit WHERE id = ?;")
    defer { sqlite3_finalize(statement) }
    bindText(id.uuidString, at: 1, in: statement)
    guard sqlite3_step(statement) == SQLITE_ROW, let blob = sqlite3_column_blob(statement, 0) else { return nil }
    return try? JSONDecoder().decode(MemoryAuditRecord.self, from: Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 0))))
  }

  public func memoryAuditRecords(memoryID: UUID) throws -> [MemoryAuditRecord] {
    try memoryAuditRecords(column: "memory_id", value: memoryID)
  }

  public func memoryAuditRecords(runID: UUID) throws -> [MemoryAuditRecord] {
    try memoryAuditRecords(column: "run_id", value: runID)
  }

  private func memoryAuditRecords(column: String, value: UUID) throws -> [MemoryAuditRecord] {
    lock.lock(); defer { lock.unlock() }
    let statement = try prepare("SELECT payload FROM memory_audit WHERE \(column) = ? ORDER BY created_at;")
    defer { sqlite3_finalize(statement) }
    bindText(value.uuidString, at: 1, in: statement)
    var result: [MemoryAuditRecord] = []
    while sqlite3_step(statement) == SQLITE_ROW, let blob = sqlite3_column_blob(statement, 0) {
      let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 0)))
      if let item = try? JSONDecoder().decode(MemoryAuditRecord.self, from: data) { result.append(item) }
    }
    return result
  }

  public func saveStandingIntent(_ intent: StandingIntent) throws {
    lock.lock(); defer { lock.unlock() }
    let payload = try JSONEncoder().encode(intent)
    let statement = try prepare("INSERT OR REPLACE INTO standing_intents (id,payload,is_active,expires_at,created_at) VALUES (?,?,?,?,?);")
    defer { sqlite3_finalize(statement) }
    bindText(intent.id.uuidString, at: 1, in: statement)
    payload.withUnsafeBytes { _ = sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32(payload.count), transient) }
    sqlite3_bind_int(statement, 3, intent.isActive ? 1 : 0)
    if let expiresAt = intent.expiresAt { sqlite3_bind_double(statement, 4, expiresAt.timeIntervalSince1970) } else { sqlite3_bind_null(statement, 4) }
    sqlite3_bind_double(statement, 5, intent.createdAt.timeIntervalSince1970)
    guard sqlite3_step(statement) == SQLITE_DONE else { throw ClawMemoryStoreError.sqlite(message: String(cString: sqlite3_errmsg(try requireDB()))) }
  }

  public func standingIntents() throws -> [StandingIntent] {
    lock.lock(); defer { lock.unlock() }
    let statement = try prepare("SELECT payload FROM standing_intents ORDER BY created_at;")
    defer { sqlite3_finalize(statement) }
    var result: [StandingIntent] = []
    while sqlite3_step(statement) == SQLITE_ROW, let blob = sqlite3_column_blob(statement, 0) {
      let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 0)))
      if let item = try? JSONDecoder().decode(StandingIntent.self, from: data) { result.append(item) }
    }
    return result
  }

  public func cancelStandingIntent(id: UUID) throws {
    guard var intent = try standingIntents().first(where: { $0.id == id }) else { return }
    intent.isActive = false
    try saveStandingIntent(intent)
  }

  public func saveMemoryConflict(_ conflict: MemoryConflict) throws {
    lock.lock(); defer { lock.unlock() }
    let payload = try JSONEncoder().encode(conflict)
    let statement = try prepare("INSERT OR REPLACE INTO memory_conflicts (id,payload,is_resolved,created_at) VALUES (?,?,?,?);")
    defer { sqlite3_finalize(statement) }
    bindText(conflict.id.uuidString, at: 1, in: statement)
    payload.withUnsafeBytes { _ = sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32(payload.count), transient) }
    sqlite3_bind_int(statement, 3, conflict.isResolved ? 1 : 0)
    sqlite3_bind_double(statement, 4, conflict.createdAt.timeIntervalSince1970)
    guard sqlite3_step(statement) == SQLITE_DONE else { throw ClawMemoryStoreError.sqlite(message: String(cString: sqlite3_errmsg(try requireDB()))) }
  }

  public func memoryConflicts(includeResolved: Bool = false) throws -> [MemoryConflict] {
    lock.lock(); defer { lock.unlock() }
    let sql = includeResolved ? "SELECT payload FROM memory_conflicts ORDER BY created_at DESC;" : "SELECT payload FROM memory_conflicts WHERE is_resolved = 0 ORDER BY created_at DESC;"
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    var result: [MemoryConflict] = []
    while sqlite3_step(statement) == SQLITE_ROW, let blob = sqlite3_column_blob(statement, 0) {
      let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 0)))
      if let item = try? JSONDecoder().decode(MemoryConflict.self, from: data) { result.append(item) }
    }
    return result
  }

  public func resolveMemoryConflict(id: UUID) throws {
    guard var conflict = try memoryConflicts(includeResolved: true).first(where: { $0.id == id }) else { return }
    conflict.isResolved = true
    try saveMemoryConflict(conflict)
  }

  /// 按 id 读取原始证据事件。
  public func rawEvents(ids: [UUID]) throws -> [RawMemoryEvent] {
    lock.lock(); defer { lock.unlock() }
    guard !ids.isEmpty else { return [] }
    let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
    let sql = "SELECT id,kind,content,source_app,source_ref,occurred_at,ingested_at,idempotency_key FROM raw_events WHERE id IN (\(placeholders));"
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    for (offset, id) in ids.enumerated() {
      bindText(id.uuidString, at: Int32(offset + 1), in: statement)
    }
    var result: [RawMemoryEvent] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let idText = text(statement, 0), let id = UUID(uuidString: idText),
            let kind = text(statement, 1), let content = text(statement, 2) else { continue }
      result.append(RawMemoryEvent(
        id: id,
        kind: kind,
        content: content,
        sourceApp: text(statement, 3),
        sourceRef: text(statement, 4),
        occurredAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
        ingestedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
        idempotencyKey: text(statement, 7)
      ))
    }
    return result
  }

  private func insertRawEvents(_ events: [RawMemoryEvent]) throws {
    guard !events.isEmpty else { return }
    let sql = "INSERT OR IGNORE INTO raw_events (id,kind,content,source_app,source_ref,occurred_at,ingested_at,idempotency_key) VALUES (?,?,?,?,?,?,?,?);"
    for event in events {
      let statement = try prepare(sql)
      defer { sqlite3_finalize(statement) }
      bindText(event.id.uuidString, at: 1, in: statement)
      bindText(event.kind, at: 2, in: statement)
      bindText(event.content, at: 3, in: statement)
      bindText(event.sourceApp, at: 4, in: statement)
      bindText(event.sourceRef, at: 5, in: statement)
      sqlite3_bind_double(statement, 6, event.occurredAt.timeIntervalSince1970)
      sqlite3_bind_double(statement, 7, event.ingestedAt.timeIntervalSince1970)
      bindText(event.idempotencyKey, at: 8, in: statement)
      guard sqlite3_step(statement) == SQLITE_DONE else {
        throw ClawMemoryStoreError.sqlite(message: String(cString: sqlite3_errmsg(try requireDB())))
      }
    }
  }

  private func upsertMemoryV2Row(_ record: MemoryV2Record, payload: Data) throws {
    let sql = """
    INSERT INTO memory_v2 (id,type,state,scope,content,normalized_key,person_id,project_id,session_id,confidence,importance,cloud_permission,version,created_at,updated_at,confirmed_at,expires_at,payload)
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ON CONFLICT(id) DO UPDATE SET type=excluded.type,state=excluded.state,scope=excluded.scope,content=excluded.content,normalized_key=excluded.normalized_key,person_id=excluded.person_id,project_id=excluded.project_id,session_id=excluded.session_id,confidence=excluded.confidence,importance=excluded.importance,cloud_permission=excluded.cloud_permission,version=excluded.version,updated_at=excluded.updated_at,confirmed_at=excluded.confirmed_at,expires_at=excluded.expires_at,payload=excluded.payload;
    """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    bindText(record.id.uuidString, at: 1, in: statement)
    bindText(record.type.rawValue, at: 2, in: statement)
    bindText(record.state.rawValue, at: 3, in: statement)
    bindText(record.scope.rawValue, at: 4, in: statement)
    bindText(record.content, at: 5, in: statement)
    bindText(record.normalizedKey, at: 6, in: statement)
    bindText(record.personID?.uuidString, at: 7, in: statement)
    bindText(record.projectID?.uuidString, at: 8, in: statement)
    bindText(record.sessionID?.uuidString, at: 9, in: statement)
    sqlite3_bind_double(statement, 10, record.confidence)
    sqlite3_bind_double(statement, 11, record.importance)
    bindText(record.cloudPermission.rawValue, at: 12, in: statement)
    sqlite3_bind_int(statement, 13, Int32(record.version))
    sqlite3_bind_double(statement, 14, record.createdAt.timeIntervalSince1970)
    sqlite3_bind_double(statement, 15, record.updatedAt.timeIntervalSince1970)
    if let confirmedAt = record.confirmedAt {
      sqlite3_bind_double(statement, 16, confirmedAt.timeIntervalSince1970)
    } else {
      sqlite3_bind_null(statement, 16)
    }
    if let expiresAt = record.expiresAt {
      sqlite3_bind_double(statement, 17, expiresAt.timeIntervalSince1970)
    } else {
      sqlite3_bind_null(statement, 17)
    }
    payload.withUnsafeBytes { bytes in
      _ = sqlite3_bind_blob(statement, 18, bytes.baseAddress, Int32(payload.count), transient)
    }
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw ClawMemoryStoreError.sqlite(message: String(cString: sqlite3_errmsg(try requireDB())))
    }
    try? syncMemoryFTS(record)
  }

  private func syncMemoryFTS(_ record: MemoryV2Record) throws {
    let removeFTS = try prepare("DELETE FROM memory_v2_fts WHERE id = ?;")
    bindText(record.id.uuidString, at: 1, in: removeFTS)
    _ = sqlite3_step(removeFTS)
    sqlite3_finalize(removeFTS)
    let insertFTS = try prepare("INSERT INTO memory_v2_fts (id,content,normalized_key) VALUES (?,?,?);")
    bindText(record.id.uuidString, at: 1, in: insertFTS)
    bindText(record.content, at: 2, in: insertFTS)
    bindText(record.normalizedKey, at: 3, in: insertFTS)
    guard sqlite3_step(insertFTS) == SQLITE_DONE else {
      let message = String(cString: sqlite3_errmsg(try requireDB()))
      sqlite3_finalize(insertFTS)
      throw ClawMemoryStoreError.sqlite(message: message)
    }
    sqlite3_finalize(insertFTS)
  }

  private func insertMemoryVersion(_ record: MemoryV2Record, payload: Data) throws {
    let existing = try prepare("SELECT 1 FROM memory_versions WHERE memory_id = ? AND version = ? LIMIT 1;")
    bindText(record.id.uuidString, at: 1, in: existing)
    sqlite3_bind_int(existing, 2, Int32(record.version))
    let alreadyStored = sqlite3_step(existing) == SQLITE_ROW
    sqlite3_finalize(existing)
    if alreadyStored { return }
    let sql = "INSERT INTO memory_versions (id,memory_id,version,payload,created_at) VALUES (?,?,?,?,?);"
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    bindText(UUID().uuidString, at: 1, in: statement)
    bindText(record.id.uuidString, at: 2, in: statement)
    sqlite3_bind_int(statement, 3, Int32(record.version))
    payload.withUnsafeBytes { bytes in
      _ = sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(payload.count), transient)
    }
    sqlite3_bind_double(statement, 5, Date().timeIntervalSince1970)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw ClawMemoryStoreError.sqlite(message: String(cString: sqlite3_errmsg(try requireDB())))
    }
  }

  private func replaceMemoryEvidence(_ record: MemoryV2Record) throws {
    let deleteStatement = try prepare("DELETE FROM memory_evidence WHERE memory_id = ?;")
    bindText(record.id.uuidString, at: 1, in: deleteStatement)
    guard sqlite3_step(deleteStatement) == SQLITE_DONE else {
      let message = String(cString: sqlite3_errmsg(try requireDB()))
      sqlite3_finalize(deleteStatement)
      throw ClawMemoryStoreError.sqlite(message: message)
    }
    sqlite3_finalize(deleteStatement)

    let sql = "INSERT INTO memory_evidence (id,memory_id,raw_event_id,locator,excerpt) VALUES (?,?,?,?,?);"
    for evidence in record.evidence {
      let statement = try prepare(sql)
      defer { sqlite3_finalize(statement) }
      bindText(evidence.id.uuidString, at: 1, in: statement)
      bindText(record.id.uuidString, at: 2, in: statement)
      bindText(evidence.rawEventID.uuidString, at: 3, in: statement)
      bindText(evidence.locator, at: 4, in: statement)
      bindText(evidence.excerpt, at: 5, in: statement)
      guard sqlite3_step(statement) == SQLITE_DONE else {
        throw ClawMemoryStoreError.sqlite(message: String(cString: sqlite3_errmsg(try requireDB())))
      }
    }
  }

  private func insertMemoryLineage(_ record: MemoryV2Record) throws {
    let deleteStatement = try prepare("DELETE FROM memory_lineage WHERE memory_id = ?;")
    bindText(record.id.uuidString, at: 1, in: deleteStatement)
    guard sqlite3_step(deleteStatement) == SQLITE_DONE else {
      let message = String(cString: sqlite3_errmsg(try requireDB()))
      sqlite3_finalize(deleteStatement)
      throw ClawMemoryStoreError.sqlite(message: message)
    }
    sqlite3_finalize(deleteStatement)

    let sql = "INSERT INTO memory_lineage (id,memory_id,parent_memory_id,raw_event_id,source_memory_id) VALUES (?,?,?,?,?);"
    func insertEdge(parent: UUID?, rawEvent: UUID?, source: UUID?) throws {
      let statement = try prepare(sql)
      defer { sqlite3_finalize(statement) }
      bindText(UUID().uuidString, at: 1, in: statement)
      bindText(record.id.uuidString, at: 2, in: statement)
      bindText(parent?.uuidString, at: 3, in: statement)
      bindText(rawEvent?.uuidString, at: 4, in: statement)
      bindText(source?.uuidString, at: 5, in: statement)
      guard sqlite3_step(statement) == SQLITE_DONE else {
        throw ClawMemoryStoreError.sqlite(message: String(cString: sqlite3_errmsg(try requireDB())))
      }
    }
    if let parentID = record.lineage.parentID {
      try insertEdge(parent: parentID, rawEvent: nil, source: nil)
    }
    for rawEventID in record.lineage.rawEventIDs {
      try insertEdge(parent: nil, rawEvent: rawEventID, source: nil)
    }
    for sourceID in record.lineage.derivedFromMemoryIDs {
      try insertEdge(parent: nil, rawEvent: nil, source: sourceID)
    }
  }

  private func seedBuiltInSkillsIfNeeded() {
    let builtIns = [
      ClawSkillDefinition(id: "reply", name: "帮你回", summary: "结合当前聊天、对象关系与用户表达习惯生成回复", systemPrompt: "理解对方真实意图和情绪，生成自然、简洁、像用户本人会说的话。", permissions: ["memory.global", "memory.contact", "conversation.current"], triggers: [.manual, .keyboardHelpReply, .screenshotImported], toolIDs: ["memory.search", "conversation.current"], inputContract: "当前聊天内容，可选联系人/截图上下文", outputContract: "可直接发送的短回复候选"),
      ClawSkillDefinition(id: "rewrite", name: "超会说", summary: "保留原意并优化表达", systemPrompt: "保留用户原意，减少 AI 腔，让表达自然、有分寸，并优先遵循用户长期语言习惯。", permissions: ["memory.global", "memory.contact"], triggers: [.manual, .keyboardRewrite], toolIDs: ["memory.search"], inputContract: "用户原始表达", outputContract: "可直接替换原文的优化版本"),
      ClawSkillDefinition(id: "screenshot-chat", name: "聊天截图理解", summary: "把聊天截图转成结构化时间线", systemPrompt: "识别聊天对象、发言方、顺序、时间和正文，不臆造不可见内容。", permissions: ["photos.selected", "memory.contact"], triggers: [.screenshotImported], toolIDs: ["conversation.write"], inputContract: "一张或多张聊天截图", outputContract: "结构化 Conversation Timeline"),
      ClawSkillDefinition(id: "contact-profile", name: "人物画像", summary: "从有来源的互动中更新联系人画像", systemPrompt: "只从可追溯证据提炼稳定特征，区分事实与推断。", permissions: ["memory.contact"], triggers: [.screenshotImported, .dailyReview], toolIDs: ["memory.contact"], inputContract: "联系人历史互动", outputContract: "带来源的稳定人物/关系画像"),
      ClawSkillDefinition(id: "task-extract", name: "任务提取", summary: "从对话识别承诺、等待、截止日期和下一步", systemPrompt: "只在语义足够明确时创建任务或承诺，并保留来源。", permissions: ["conversation.current", "tasks.write"], triggers: [.screenshotImported, .assistant], toolIDs: ["tasks.write"], inputContract: "当前聊天消息", outputContract: "Task / Commitment / WaitingFor / Deadline / NextAction"),
      ClawSkillDefinition(id: "daily-secretary", name: "今日秘书", summary: "整理当天重要事项和下一步", systemPrompt: "优先未完成承诺、截止日期、等待回复和高相关近期事件，避免无意义打扰。", permissions: ["memory.global", "memory.contact", "tasks.read"], triggers: [.dailyReview, .manual], toolIDs: ["memory.search", "tasks.read"], inputContract: "今日记忆、任务和近期互动", outputContract: "按优先级排序的 briefing 与下一步"),
    ]
    let existing = (try? skills()) ?? []
    for builtIn in builtIns {
      if var old = existing.first(where: { $0.id == builtIn.id }) {
        var changed = false
        if old.triggers == nil {
          old.triggers = builtIn.triggers
          changed = true
        }
        if old.toolIDs == nil {
          old.toolIDs = builtIn.toolIDs
          changed = true
        }
        if old.workflow == nil, builtIn.workflow != nil {
          old.workflow = builtIn.workflow
          changed = true
        }
        if old.inputContract == nil, builtIn.inputContract != nil {
          old.inputContract = builtIn.inputContract
          changed = true
        }
        if old.outputContract == nil, builtIn.outputContract != nil {
          old.outputContract = builtIn.outputContract
          changed = true
        }
        if changed { try? saveSkill(old) }
      } else {
        try? saveSkill(builtIn)
      }
    }
  }

  private static func fingerprint(contactID: UUID?, speaker: ClawConversationSpeaker, content: String, occurredAt: Date) -> String {
    // 截图往往没有精确时间。以分钟粒度 + 正文去重，避免连续截图重复写入。
    let minute = Int(occurredAt.timeIntervalSince1970 / 60)
    let normalized = content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    return "\(contactID?.uuidString ?? "global")|\(speaker.rawValue)|\(minute)|\(normalized)"
  }
}
