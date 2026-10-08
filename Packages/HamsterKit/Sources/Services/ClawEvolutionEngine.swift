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
  private let skillRuntime: ClawSkillRuntime

  public init(store: ClawMemoryStore = .shared) {
    self.store = store
    self.skillRuntime = ClawSkillRuntime(store: store)
  }

  @discardableResult
  public func evolveIfNeeded(skillID: String) -> ClawEvolutionSnapshot? {
    guard var skill = try? store.skills().first(where: { $0.id == skillID }),
          let feedback = try? store.feedback(skillID: skillID, limit: 200)
    else { return nil }

    let acceptedRows = feedback.filter { $0.action == .accepted }.compactMap(\.finalText)
    let editedRows = feedback.filter { $0.action == .edited }
    guard acceptedRows.count + editedRows.count >= 3 else {
      return snapshot(skill: skill, feedback: feedback)
    }

    let finalRows = acceptedRows + editedRows.compactMap(\.finalText)
    let lengths = finalRows.map(\.count).sorted()
    let median = lengths.isEmpty ? 24 : lengths[lengths.count / 2]
    var directives: [String] = []
    switch median {
    case 0...18:
      directives.append("用户实际采用的回复通常很短。优先给 10～20 个汉字左右的直接表达；除非上下文明确需要，不主动扩写。")
    case 19...45:
      directives.append("用户实际采用的回复通常偏精炼。优先控制在一到两句话、约 20～45 个汉字，先给结论再补必要语气。")
    default:
      directives.append("用户接受较完整的表达，但仍应避免模板化和重复解释；优先保持自然段落与真实口语感。")
    }

    let comparableEdits = editedRows.compactMap { row -> (String, String)? in
      guard let original = row.originalText, let final = row.finalText, !original.isEmpty, !final.isEmpty else { return nil }
      return (original, final)
    }
    if comparableEdits.count >= 2 {
      let ratios = comparableEdits.map { Double($0.1.count) / Double(max(1, $0.0.count)) }
      let avgRatio = ratios.reduce(0, +) / Double(ratios.count)
      if avgRatio < 0.82 {
        directives.append("用户经常把 AI 文案进一步删短；生成时减少解释和铺垫。")
      } else if avgRatio > 1.18 {
        directives.append("用户经常在 AI 文案上补充细节；必要时多保留一层事实信息，不要过度压缩。")
      }
      let honorificChanged = comparableEdits.filter { $0.0.contains("您") && !$0.1.contains("您") && $0.1.contains("你") }.count
      if honorificChanged * 2 >= comparableEdits.count {
        directives.append("用户通常把“您”改成“你”；除非关系明确需要正式称呼，优先使用“你”。")
      }
      let emojiRemoved = comparableEdits.filter { containsEmoji($0.0) && !containsEmoji($0.1) }.count
      if emojiRemoved * 2 >= comparableEdits.count {
        directives.append("用户常删除 AI 添加的 Emoji；默认少用或不用 Emoji。")
      }
    }
    let target = directives.joined(separator: "\n")

    if skill.learnedDirective != target {
      skillRuntime.captureVersion(skill)
      skill.learnedDirective = target
      skill.version += 1
      try? store.saveSkill(skill)
      skillRuntime.captureVersion(skill)

      // 把稳定学习结果也写入全局记忆，供其它 Skill 共用，而不是只藏在单个 Prompt 里。
      let memory = ClawMemoryItem(
        kind: .communicationPreference,
        content: target,
        normalizedKey: "evolution:\(skillID):response-length",
        sourceType: "evolution-engine",
        sourceRef: "skill:\(skillID):v\(skill.version)",
        confidence: min(0.95, 0.65 + Double(acceptedRows.count) * 0.04)
      )
      try? DefaultMemorySDK(store: store).rememberLegacy(memory)
    }

    // Per-contact edits stay contact-scoped, so one person's tone never contaminates another.
    let grouped = Dictionary(grouping: editedRows.compactMap { row -> ClawEvolutionFeedback? in
      row.contactID == nil ? nil : row
    }, by: { $0.contactID! })
    for (contactID, rows) in grouped where rows.count >= 3 {
      let finals = rows.compactMap(\.finalText)
      guard !finals.isEmpty else { continue }
      let medianLength = finals.map(\.count).sorted()[finals.count / 2]
      let contactDirective = "与该联系人沟通时，用户最终采用的表达长度通常约 \(medianLength) 个字；优先模仿这些已确认的最终版本。"
      try? DefaultMemorySDK(store: store).rememberLegacy(ClawMemoryItem(
        kind: .contactStyle,
        scope: "contact",
        subjectID: contactID,
        content: contactDirective,
        normalizedKey: "evolution:\(skillID):contact-style",
        sourceType: "evolution-engine",
        sourceRef: "feedback:\(rows.count)",
        confidence: min(0.95, 0.70 + Double(rows.count) * 0.04)
      ))
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

  private func containsEmoji(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
      scalar.properties.isEmojiPresentation || scalar.properties.isEmoji
    }
  }
}
