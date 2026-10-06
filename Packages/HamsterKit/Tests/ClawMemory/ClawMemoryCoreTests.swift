import XCTest
@testable import HamsterKit

final class ClawMemoryCoreTests: XCTestCase {
  private var root: URL!
  private var store: ClawMemoryStore!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("claw-memory-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
  }

  override func tearDownWithError() throws {
    store = nil
    try? FileManager.default.removeItem(at: root)
  }

  func testMemoryCanRoundTripByScopeAndContact() throws {
    let contact = UUID()
    let global = ClawMemoryItem(
      kind: .communicationPreference,
      content: "回复偏好简短直接",
      normalizedKey: "reply-short",
      sourceType: "test"
    )
    let scoped = ClawMemoryItem(
      kind: .relationship,
      scope: "contact",
      subjectID: contact,
      content: "这是一个工作客户",
      normalizedKey: "relationship",
      sourceType: "test"
    )
    try store.upsertMemory(global)
    try store.upsertMemory(scoped)

    XCTAssertEqual(try store.memories(scope: "global").map(\.content), ["回复偏好简短直接"])
    XCTAssertEqual(try store.memories(scope: "contact", subjectID: contact).map(\.content), ["这是一个工作客户"])
  }

  func testConversationScreenshotRowsAreDeduplicatedWithinMinute() throws {
    let contact = UUID()
    let time = Date(timeIntervalSince1970: 1_800_000_000)
    let message = ClawConversationMessage(
      contactID: contact,
      speaker: .other,
      senderName: "张三",
      content: "明天我把方案发你",
      occurredAt: time,
      sourceType: "screenshot"
    )
    XCTAssertTrue(try store.appendConversation(message))
    XCTAssertFalse(try store.appendConversation(ClawConversationMessage(
      contactID: contact,
      speaker: .other,
      senderName: "张三",
      content: "明天我把方案发你",
      occurredAt: time.addingTimeInterval(20),
      sourceType: "screenshot"
    )))
    XCTAssertEqual(try store.conversation(contactID: contact).count, 1)
  }

  func testSecretaryExtractorOnlyCreatesTaskForExplicitTimeAndAction() {
    let explicit = ClawConversationMessage(
      contactID: UUID(),
      speaker: .me,
      content: "我明天把方案发给你",
      sourceType: "screenshot"
    )
    let vague = ClawConversationMessage(
      contactID: UUID(),
      speaker: .me,
      content: "这个方案看起来不错",
      sourceType: "screenshot"
    )
    let tasks = ClawSecretaryExtractor.shared.extractTasks(from: explicit, now: Date(timeIntervalSince1970: 1_800_000_000))
    XCTAssertEqual(tasks.count, 1)
    XCTAssertEqual(tasks.first?.kind, .commitment)
    XCTAssertNotNil(tasks.first?.dueAt)
    XCTAssertTrue(ClawSecretaryExtractor.shared.extractTasks(from: vague).isEmpty)
  }

  func testMarkdownImportCreatesStructuredCandidatesWithoutDirectWrite() throws {
    let exchange = ClawMemoryExchangeService(store: store)
    let markdown = """
    # Agent Memory
    - 用户习惯回复简短直接
    - 正在开发 CLAW 项目
    - 不要在普通聊天里使用太正式的措辞
    """
    let preview = try exchange.previewImport(data: Data(markdown.utf8), fileName: "MEMORY.md")
    XCTAssertEqual(preview.candidates.count, 3)
    XCTAssertTrue(try store.memories().isEmpty)
    XCTAssertEqual(try exchange.commit(preview), 3)
    XCTAssertEqual(try store.memories().count, 3)
  }

  func testImportPreviewSeparatesDuplicatesAndConflicts() throws {
    let existing = ClawMemoryItem(
      kind: .communicationPreference,
      content: "客户消息偏好简短",
      normalizedKey: "reply-style-client",
      sourceType: "manual"
    )
    try store.upsertMemory(existing)
    let exchange = ClawMemoryExchangeService(store: store)
    let duplicate = ClawMemoryItem(
      kind: .communicationPreference,
      content: "客户消息偏好简短",
      normalizedKey: "reply-style-client",
      sourceType: "agent-import"
    )
    let conflict = ClawMemoryItem(
      kind: .communicationPreference,
      content: "客户消息偏好详细解释",
      normalizedKey: "reply-style-client",
      sourceType: "agent-import"
    )
    let fresh = ClawMemoryItem(
      kind: .project,
      content: "正在开发 CLAW",
      normalizedKey: "project-claw",
      sourceType: "agent-import"
    )
    let envelope = ClawMemoryExchangeEnvelope(
      version: 1,
      exportedAt: Date(),
      memories: [duplicate, conflict, fresh],
      tasks: []
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let preview = try exchange.previewImport(data: encoder.encode(envelope), fileName: "memory.json")

    XCTAssertEqual(preview.duplicateCount, 1)
    XCTAssertEqual(preview.conflictCount, 1)
    XCTAssertEqual(preview.candidates.map(\.content), ["正在开发 CLAW"])
    XCTAssertEqual(try exchange.commit(preview), 1)
  }

  func testSkillPackageInstallAndEvolutionUseAcceptedReplies() throws {
    let skill = ClawSkillDefinition(
      id: "custom-reply",
      name: "自定义回复",
      summary: "测试 Skill",
      systemPrompt: "自然回复",
      permissions: ["memory.global"]
    )
    let package = ClawSkillPackage(skills: [skill])
    let data = try JSONEncoder().encode(package)
    let installer = ClawSkillImportService(store: store)
    let preview = try installer.preview(data: data)
    XCTAssertEqual(preview.map(\.id), ["custom-reply"])
    XCTAssertEqual(try installer.install(preview), 1)

    for text in ["好的，明天聊", "可以，我晚点发你", "行，我看完回复你"] {
      try store.recordFeedback(ClawEvolutionFeedback(
        skillID: "custom-reply",
        action: .accepted,
        originalText: "测试",
        finalText: text
      ))
    }
    let engine = ClawEvolutionEngine(store: store)
    let snapshot = engine.evolveIfNeeded(skillID: "custom-reply")
    XCTAssertNotNil(snapshot?.learnedDirective)
    XCTAssertEqual(snapshot?.version, 2)
    XCTAssertTrue((try store.memories(scope: "global")).contains { $0.sourceType == "evolution-engine" })
  }
}
