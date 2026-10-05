import Foundation

/// 从联系人可追溯聊天时间线提炼画像。结果与手工 bio 分开保存，可随时重建/删除。
public final class ClawContactProfileLearner {
  public static let shared = ClawContactProfileLearner()

  private let store: ClawMemoryStore
  private let aiService: AIService
  private let queue = DispatchQueue(label: "com.desgemini.claw.profile-learner", qos: .utility)
  private var inFlight = Set<UUID>()

  public init(store: ClawMemoryStore = .shared, aiService: AIService = .shared) {
    self.store = store
    self.aiService = aiService
  }

  /// 有足够新聊天证据时自动刷新。不会因为一两句聊天就给人物下结论。
  public func refreshIfNeeded(profileID: UUID, minimumMessages: Int = 6) {
    queue.async { [weak self] in
      guard let self else { return }
      guard !self.inFlight.contains(profileID) else { return }
      guard let profile = HeartTargetService.shared.profiles.first(where: { $0.id == profileID }) else { return }
      let timeline = (try? self.store.conversation(contactID: profileID, limit: 40)) ?? []
      guard timeline.count >= minimumMessages else { return }

      let existingMemory = ((try? self.store.memories(scope: "contact", subjectID: profileID, limit: 100)) ?? [])
        .first(where: { $0.normalizedKey == "contact-profile-summary" })
      if let last = existingMemory?.lastObservedAt,
         Date().timeIntervalSince(last) < 6 * 60 * 60 {
        return
      }
      let provider = self.aiService.selectedProvider
      let model = self.aiService.selectedModel
      guard !self.aiService.apiKey(for: provider).isEmpty else { return }

      self.inFlight.insert(profileID)
      let rows = timeline.suffix(30).map { message -> String in
        let who = message.speaker == .me ? "我" : (message.senderName ?? profile.displayName)
        return "\(who)：\(message.content)"
      }.joined(separator: "\n")

      let prompt = """
      你是 CLAW 的人物画像 Skill。只根据下面真实聊天证据，提炼这个人与用户之间长期有用、相对稳定的沟通画像。
      要求：
      1. 区分事实与推断，不确定的不要写；
      2. 不做心理诊断，不贴侮辱性标签；
      3. 关注关系、沟通方式、偏好、近期稳定主题、用户与 TA 的相处方式；
      4. 最多 120 个汉字，直接输出画像正文，不要标题。

      联系人：\(profile.displayName)
      用户手工备注：\(profile.bio)
      聊天证据：
      ---
      \(rows)
      ---
      """

      self.aiService.chat(
        messages: [AIMessage(role: "system", content: prompt)],
        provider: provider,
        model: model
      ) { [weak self] result in
        guard let self else { return }
        self.queue.async { self.inFlight.remove(profileID) }
        guard case .success(let reply) = result else { return }
        let summary = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return }

        var updated = profile
        updated.learnedSummary = String(summary.prefix(240))
        _ = HeartTargetService.shared.upsert(updated)

        let now = Date()
        var memory = ClawMemoryItem(
          kind: .contactStyle,
          scope: "contact",
          subjectID: profileID,
          content: updated.learnedSummary,
          normalizedKey: "contact-profile-summary",
          sourceType: "contact-profile-learner",
          sourceRef: "timeline:last-\(timeline.count)",
          confidence: 0.78,
          lastObservedAt: now
        )
        if let existingMemory {
          memory.id = existingMemory.id
          memory.createdAt = existingMemory.createdAt
          memory.updatedAt = now
        }
        try? self.store.upsertMemory(memory)
      }
    }
  }
}
