import Foundation

public struct ClawSkillPackage: Codable, Equatable {
  public var format: String
  public var version: Int
  public var skills: [ClawSkillDefinition]

  public init(format: String = "clawskill", version: Int = 1, skills: [ClawSkillDefinition]) {
    self.format = format
    self.version = version
    self.skills = skills
  }
}

/// Skill 安装器。安装的是声明式能力包，不执行包内任意 Swift/脚本。
public final class ClawSkillImportService {
  public static let shared = ClawSkillImportService()
  private let store: ClawMemoryStore

  public init(store: ClawMemoryStore = .shared) {
    self.store = store
  }

  public func preview(data: Data) throws -> [ClawSkillDefinition] {
    let decoder = JSONDecoder()
    if let package = try? decoder.decode(ClawSkillPackage.self, from: data), package.format == "clawskill" {
      return package.skills.filter(validate)
    }
    if let skill = try? decoder.decode(ClawSkillDefinition.self, from: data), validate(skill) {
      return [skill]
    }
    if let skills = try? decoder.decode([ClawSkillDefinition].self, from: data) {
      return skills.filter(validate)
    }
    throw CocoaError(.fileReadCorruptFile)
  }

  @discardableResult
  public func install(_ skills: [ClawSkillDefinition]) throws -> Int {
    var count = 0
    let runtime = ClawSkillRuntime(store: store)
    for var skill in skills where validate(skill) {
      // External packages never install executable permissions. Unknown permission strings are
      // kept declarative and must still be mediated by CLAW's built-in tool layer.
      skill.version = max(1, skill.version)
      if let existing = try store.skills().first(where: { $0.id == skill.id }) {
        runtime.captureVersion(existing)
        skill.version = max(skill.version, existing.version + 1)
      }
      try store.saveSkill(skill)
      runtime.captureVersion(skill)
      count += 1
    }
    return count
  }

  public func exportPackage(skillIDs: [String]? = nil) throws -> Data {
    var skills = try store.skills()
    if let skillIDs { skills = skills.filter { skillIDs.contains($0.id) } }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(ClawSkillPackage(skills: skills))
  }

  private func validate(_ skill: ClawSkillDefinition) -> Bool {
    let id = skill.id.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = skill.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let prompt = skill.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty && id.count <= 80 && !name.isEmpty && name.count <= 80 && !prompt.isEmpty && prompt.count <= 20_000 else {
      return false
    }
    if let inputContract = skill.inputContract, inputContract.count > 2_000 { return false }
    if let outputContract = skill.outputContract, outputContract.count > 2_000 { return false }
    let tools = Set(skill.toolIDs ?? [])
    guard tools.isSubset(of: ClawSkillRuntime.shared.supportedTools) else { return false }
    let allowedPermissions: Set<String> = [
      "memory.global", "memory.contact", "conversation.current", "conversation.write",
      "tasks.read", "tasks.write", "photos.selected",
    ]
    return Set(skill.permissions).isSubset(of: allowedPermissions)
  }
}
