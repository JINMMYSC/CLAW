import Foundation

public struct ClawEvolutionSnapshot: Equatable {
  public var skillID: String
  public var version: Int
  public var accepted: Int
  public var edited: Int
  public var regenerated: Int
  public var learnedDirective: String?
}

/// 手机端轻量自我进化：只优化 Skill 配置/提示词，不下载或修改可执行 Swift 代码。
public final class ClawEvolutionEngine {
  public static let shared = ClawEvolutionEngine()
  private let store: ClawMemoryStore

  public init(store: ClawMemoryStore = .shared) {
    self.store = store
  }

  @discardableResult
  public func evolveIfNeeded(skillID: String) -> ClawEvolutionSnapshot? {
    guard var skill = try? store.skills().first(where: { $0.id == skillID }),
          let feedback = try? store.feedback(skillID: skillID, limit: 200)
    else { return nil }

    let acceptedRows = feedback.filter { $0.action == .accepted }.compactMap(\.finalText)
    guard acceptedRows.count >= 3 else {
      return snapshot(skill: skill, feedback: feedback)
    }

    let lengths = acceptedRows.map(\.count).sorted()
    let median = lengths[lengths.count / 2]
    let target: String
    switch median {
    case 0...18:
      target = "用户实际采用的回复通常很短。优先给 10～20 个汉字左右的直接表达；除非上下文明确需要，不主动扩写。"
    case 19...45:
      target = "用户实际采用的回复通常偏精炼。优先控制在一到两句话、约 20～45 个汉字，先给结论再补必要语气。"
    default:
      target = "用户接受较完整的表达，但仍应避免模板化和重复解释；优先保持自然段落与真实口语感。"
    }

    if skill.learnedDirective != target {
      skill.learnedDirective = target
      skill.version += 1
      try? store.saveSkill(skill)

      // 把稳定学习结果也写入全局记忆，供其它 Skill 共用，而不是只藏在单个 Prompt 里。
      let memory = ClawMemoryItem(
        kind: .communicationPreference,
        content: target,
        normalizedKey: "evolution:\(skillID):response-length",
        sourceType: "evolution-engine",
        sourceRef: "skill:\(skillID):v\(skill.version)",
        confidence: min(0.95, 0.65 + Double(acceptedRows.count) * 0.04)
      )
      try? store.upsertMemory(memory)
    }
    return snapshot(skill: skill, feedback: feedback)
  }

  public func snapshots() -> [ClawEvolutionSnapshot] {
    ((try? store.skills()) ?? []).compactMap { skill in
      let feedback = (try? store.feedback(skillID: skill.id, limit: 200)) ?? []
      return snapshot(skill: skill, feedback: feedback)
    }
  }

  private func snapshot(skill: ClawSkillDefinition, feedback: [ClawEvolutionFeedback]) -> ClawEvolutionSnapshot {
    ClawEvolutionSnapshot(
      skillID: skill.id,
      version: skill.version,
      accepted: feedback.filter { $0.action == .accepted }.count,
      edited: feedback.filter { $0.action == .edited }.count,
      regenerated: feedback.filter { $0.action == .regenerated }.count,
      learnedDirective: skill.learnedDirective
    )
  }
}
