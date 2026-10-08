import Foundation

public struct ClawSkillDraftCandidate: Identifiable, Equatable {
  public var id: String { proposedSkill.id }
  public var baseSkillID: String
  public var contactID: UUID?
  public var sampleCount: Int
  public var reason: String
  public var proposedSkill: ClawSkillDefinition
}

/// Finds repeated successful behavior and proposes a declarative Skill draft.
///
/// Drafts are always disabled by default. CLAW may discover and prepare them
/// automatically, but only the user can enable/install the new capability.
public final class ClawSkillDiscoveryService {
  public static let shared = ClawSkillDiscoveryService()
  private let store: ClawMemoryStore

  public init(store: ClawMemoryStore = .shared) {
    self.store = store
  }

  public func discover(minimumSamples: Int = 5) -> [ClawSkillDraftCandidate] {
    let installed = (try? store.skills()) ?? []
    var candidates: [ClawSkillDraftCandidate] = []

    for base in installed where base.enabled {
      let rows = ((try? store.feedback(skillID: base.id, limit: 300)) ?? [])
        .filter { $0.action == .accepted || $0.action == .edited }
      guard rows.count >= minimumSamples else { continue }

      let groups = Dictionary(grouping: rows) { row in
        row.contactID?.uuidString ?? "global"
      }
      for (scopeKey, samples) in groups where samples.count >= minimumSamples {
        let contactID = scopeKey == "global" ? nil : UUID(uuidString: scopeKey)
        let suffix = contactID.map { String($0.uuidString.prefix(8)).lowercased() } ?? "global"
        let draftID = "auto-\(base.id)-\(suffix)"
        guard !installed.contains(where: { $0.id == draftID }) else { continue }

        let finalTexts = samples.compactMap(\.finalText).filter { !$0.isEmpty }
        guard !finalTexts.isEmpty else { continue }
        let avgLength = Int(finalTexts.map(\.count).reduce(0, +) / max(1, finalTexts.count))
        let emojiRate = Double(finalTexts.filter(Self.containsEmoji).count) / Double(finalTexts.count)
        let style = [
          "参考 \(samples.count) 次真实采用/修改结果",
          "平均最终长度约 \(avgLength) 字",
          emojiRate < 0.2 ? "默认少用 Emoji" : nil,
        ].compactMap { $0 }.joined(separator: "；")

        var permissions = base.permissions
        if contactID != nil, !permissions.contains("memory.contact") {
          permissions.append("memory.contact")
        }
        let name = contactID == nil ? "\(base.name) · 个性化" : "\(base.name) · 联系人专用"
        let prompt = base.systemPrompt + "\n\n自动发现草稿规则：\(style)。保持用户原意，不要臆造事实。"
        let draft = ClawSkillDefinition(
          id: draftID,
          name: name,
          summary: "CLAW 从重复成功行为中自动发现的 Skill 草稿，需用户确认后启用",
          systemPrompt: prompt,
          enabled: false,
          permissions: permissions,
          triggers: base.triggers,
          workflow: base.workflow,
          toolIDs: base.toolIDs,
          inputContract: base.inputContract,
          outputContract: base.outputContract
        )
        candidates.append(ClawSkillDraftCandidate(
          baseSkillID: base.id,
          contactID: contactID,
          sampleCount: samples.count,
          reason: style,
          proposedSkill: draft
        ))
      }
    }
    return candidates.sorted { $0.sampleCount > $1.sampleCount }
  }

  @discardableResult
  public func saveDraft(_ candidate: ClawSkillDraftCandidate) throws -> ClawSkillDefinition {
    var draft = candidate.proposedSkill
    draft.enabled = false
    try store.saveSkill(draft)
    return draft
  }

  private static func containsEmoji(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
      scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && scalar.value > 0x238C)
    }
  }
}
