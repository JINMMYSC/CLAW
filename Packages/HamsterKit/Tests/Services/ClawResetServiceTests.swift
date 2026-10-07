import XCTest
@testable import HamsterKit

final class ClawResetServiceTests: XCTestCase {
  func testFullResetClearsApprovedDataAndPreservesKeysAndSchemas() {
    let state = ResetState()
    let service = ClawResetService(actions: .init(
      stopRime: { state.events.append("stop") },
      clearApplicationData: {
        state.memories = 0
        state.people = 0
        state.tasks = 0
        state.conversations = 0
        state.events.append("data")
      },
      clearInputLearning: {
        state.userDictionaryEntries = 0
        state.smartFrequencyRules = 0
        state.events.append("learning")
      },
      resetConfiguration: { state.events.append("configuration") },
      redeployRime: { state.events.append("redeploy") }
    ))

    let report = service.perform(.full)

    XCTAssertTrue(report.succeeded)
    XCTAssertEqual(state.memories, 0)
    XCTAssertEqual(state.people, 0)
    XCTAssertEqual(state.tasks, 0)
    XCTAssertEqual(state.conversations, 0)
    XCTAssertEqual(state.userDictionaryEntries, 0)
    XCTAssertEqual(state.smartFrequencyRules, 0)
    XCTAssertEqual(state.apiKey, "secret-key")
    XCTAssertEqual(state.inputSchemas, ["custom.schema.yaml"])
    XCTAssertEqual(state.events, ["stop", "data", "learning", "configuration", "redeploy"])
  }

  func testLearningOnlyResetLeavesApplicationDataUntouched() {
    let state = ResetState()
    let service = ClawResetService(actions: .init(
      stopRime: { state.events.append("stop") },
      clearApplicationData: { XCTFail("Learning reset must not clear application data") },
      clearInputLearning: {
        state.userDictionaryEntries = 0
        state.smartFrequencyRules = 0
        state.events.append("learning")
      },
      resetConfiguration: { XCTFail("Learning reset must not reset configuration") },
      redeployRime: { state.events.append("redeploy") }
    ))

    let report = service.perform(.inputLearningOnly)

    XCTAssertTrue(report.succeeded)
    XCTAssertEqual(state.memories, 3)
    XCTAssertEqual(state.people, 2)
    XCTAssertEqual(state.tasks, 4)
    XCTAssertEqual(state.conversations, 5)
    XCTAssertEqual(state.userDictionaryEntries, 0)
    XCTAssertEqual(state.smartFrequencyRules, 0)
    XCTAssertEqual(state.events, ["stop", "learning", "redeploy"])
    XCTAssertEqual(report.results.map(\.step), [.stopRime, .clearInputLearning, .redeployRime])
  }

  func testResetReportsEachStepAndContinuesAfterFailure() {
    enum ExpectedFailure: Error { case unavailable }
    let state = ResetState()
    let service = ClawResetService(actions: .init(
      stopRime: { state.events.append("stop") },
      clearApplicationData: {
        state.events.append("data")
        throw ExpectedFailure.unavailable
      },
      clearInputLearning: { state.events.append("learning") },
      resetConfiguration: { state.events.append("configuration") },
      redeployRime: { state.events.append("redeploy") }
    ))

    let report = service.perform(.full)

    XCTAssertFalse(report.succeeded)
    XCTAssertEqual(report.results.count, 5)
    XCTAssertEqual(report.results.filter { !$0.succeeded }.map(\.step), [.clearApplicationData])
    XCTAssertNotNil(report.results.first { $0.step == .clearApplicationData }?.errorDescription)
    XCTAssertEqual(state.events, ["stop", "data", "learning", "configuration", "redeploy"])
  }

  func testLearningFileCleanupPreservesInputSchemaFiles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let schema = root.appendingPathComponent("custom.schema.yaml")
    let dictionary = root.appendingPathComponent("custom.dict.yaml")
    let learning = root.appendingPathComponent("custom.userdb", isDirectory: true)
    try FileManager.default.createDirectory(at: learning, withIntermediateDirectories: true)
    try Data("schema".utf8).write(to: schema)
    try Data("dictionary".utf8).write(to: dictionary)
    try Data("learned".utf8).write(to: learning.appendingPathComponent("data.bin"))

    try ClawResetService.removeInputLearningFiles(in: [root])

    XCTAssertTrue(FileManager.default.fileExists(atPath: schema.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: dictionary.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: learning.path))
  }

  func testMemoryStoreResetClearsUserRowsAndRestoresBuiltInSkills() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    try store.upsertMemory(ClawMemoryItem(kind: .fact, content: "private", sourceType: "test"))
    try store.appendConversation(ClawConversationMessage(speaker: .me, content: "hello", sourceType: "test"))
    try store.upsertTask(ClawSecretaryTask(title: "todo", sourceType: "test"))
    try store.saveSkill(ClawSkillDefinition(
      id: "custom-reset-test",
      name: "Custom",
      summary: "Custom",
      systemPrompt: "Custom",
      permissions: []
    ))

    try store.clearAllUserData()

    XCTAssertTrue(try store.memories().isEmpty)
    XCTAssertTrue(try store.allConversation().isEmpty)
    XCTAssertTrue(try store.tasks().isEmpty)
    let skills = try store.skills()
    XCTAssertFalse(skills.contains { $0.id == "custom-reset-test" })
    XCTAssertTrue(skills.contains { $0.id == "reply" })
  }
}

private final class ResetState {
  var memories = 3
  var people = 2
  var tasks = 4
  var conversations = 5
  var userDictionaryEntries = 6
  var smartFrequencyRules = 7
  var apiKey = "secret-key"
  var inputSchemas = ["custom.schema.yaml"]
  var events: [String] = []
}
