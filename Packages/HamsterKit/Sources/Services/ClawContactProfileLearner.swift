import Foundation

/// 从联系人可追溯聊天时间线提炼画像。结果与手工 bio 分开保存，可随时重建/删除。
public final class ClawContactProfileLearner {
  public static let shared = ClawContactProfileLearner()

  /// Explicit opt-in is required before reading a private contact timeline.
  static func isAuthorizedForLearning(
    profileID: UUID, consentStore: ClawContactProfileLearningConsentStore
  ) -> Bool {
    consentStore.isGranted(for: profileID)
  }

  private let store: ClawMemoryStore
  private let aiService: AIService
  private let consentStore: ClawContactProfileLearningConsentStore
  private let queue = DispatchQueue(label: "com.desgemini.claw.profile-learner", qos: .utility)
  private var inFlight = Set<UUID>()

  public init(
    store: ClawMemoryStore = .shared,
    aiService: AIService = .shared,
    consentStore: ClawContactProfileLearningConsentStore = .shared
  ) {
    self.store = store
    self.aiService = aiService
    self.consentStore = consentStore
  }

  /// Only verified human conversation bubbles are evidence for a person's
  /// learned profile. Imported system/assistant/unknown rows must never be
  /// attributed to the contact or satisfy the minimum-evidence threshold.
  static func humanEvidence(from messages: [ClawConversationMessage]) -> [ClawConversationMessage] {
    messages.filter { message in
      // A misclassified speaker must not make generated/system content into
      // evidence about a real contact. Source provenance is an independent
      // gate, not a substitute for the human-speaker check below.
      // Unicode format markers are invisible in source labels but can split
      // a generated namespace such as "tool\u{200B}:ocr" before denylist checks.
      // This includes bidirectional marks and isolates (e.g. U+200E, U+202E,
      // U+2066), not just the zero-width characters in older import formats.
      // Remove them from provenance labels only, never from message content.
      let invisibleSourceMarkers = CharacterSet(
        charactersIn: "\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}"
      )
      let sourceWithoutInvisibleMarkers = String(String.UnicodeScalarView(
        message.sourceType.unicodeScalars.filter {
          !invisibleSourceMarkers.contains($0) &&
            $0.properties.generalCategory != .format
        }
      ))
      let normalizedSourceType = sourceWithoutInvisibleMarkers
        .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Imported source labels sometimes insert spaces around a namespace
        // separator (e.g. "tool : ocr"). Canonicalize before checking the
        // generated-source denylist, without changing reviewed human labels.
        .replacingOccurrences(
          of: #"\s*([:/._-])\s*"#, with: "$1", options: .regularExpression
        )
      // Invalid or unverified confidence must not turn an imported/OCR row
      // into evidence about a real person, even with a human speaker label.
      guard message.confidence.isFinite,
            message.confidence > 0,
            message.confidence <= 1 else { return false }
      // Without provenance, a forged human speaker is not enough to make
      // imported content safe evidence for an individual's learned profile.
      guard !normalizedSourceType.isEmpty else { return false }
      // A canonical "screenshot" row can only enter through explicit review.
      // Legacy namespaced OCR labels did not pass that boundary, even when
      // their speaker was marked as human. Never learn a profile from them.
      let unreviewedScreenshotPrefixes = [
        "screenshot:", "screenshot/", "screenshot.",
        "screenshot_", "screenshot-"
      ]
      guard !unreviewedScreenshotPrefixes.contains(where: {
        normalizedSourceType.hasPrefix($0)
      }) else { return false }
      let nonHumanSources: Set<String> = [
        "assistant", "assistant-generated", "system", "ai-generated",
        "ai", "model", "llm", "generated",
        // Some importers omit the namespace suffix from tool-origin rows.
        // A forged human speaker must not turn these into contact evidence.
        "tool", "plugin", "automation", "skill"
      ]
      guard !nonHumanSources.contains(normalizedSourceType) else { return false }
      // Generated messages can carry a namespaced source (e.g. tool:ocr)
      // while still being mislabeled as a human speaker. Do not learn a
      // contact profile from these unverified tool or model outputs.
      let nonHumanSourcePrefixes = [
        "assistant:", "system:", "ai:", "model:", "llm:",
        "tool:", "plugin:", "automation:", "generated:"
      ]
      guard !nonHumanSourcePrefixes.contains(where: { normalizedSourceType.hasPrefix($0) }) else {
        return false
      }
      // Skill tools can write messages with a human speaker label even when
      // their content is generated or otherwise unverified. Never promote
      // those tool outputs into evidence for another person's AI profile.
      guard !normalizedSourceType.hasPrefix("skill:") else { return false }
      // Some importers use path, dot, hyphen, or underscore namespaces
      // instead of a colon. An underscore must not promote tool_ocr output
      // with a forged human speaker into private contact-profile evidence.
      // Treat these as generated provenance too, even if the speaker is forged
      // as a human. Keep reviewed screenshot and keyboard sources eligible.
      let generatedSourceRoots = [
        "assistant", "system", "ai", "model", "llm",
        "tool", "plugin", "automation", "skill", "generated"
      ]
      let generatedSourceSeparators = ["/", ".", "-", "_"]
      guard !generatedSourceRoots.contains(where: { root in
        generatedSourceSeparators.contains(where: { separator in
          normalizedSourceType.hasPrefix(root + separator)
        })
      }) else { return false }
      return (message.speaker == .me || message.speaker == .other) &&
        !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  /// Defense in depth: a malformed/imported conversation query must not
  /// disclose a different person's messages in this contact's AI prompt.
  static func humanEvidence(
    from messages: [ClawConversationMessage], for contactID: UUID
  ) -> [ClawConversationMessage] {
    humanEvidence(from: messages.filter { message in message.contactID == contactID })
  }

  /// A person's profile must not be inferred solely from what the user said.
  /// This gate accepts only the already filtered humanEvidence timeline and
  /// requires two actual contact replies for the normal six-message threshold.
  static func hasSufficientContactEvidence(
    _ timeline: [ClawConversationMessage], minimumMessages: Int
  ) -> Bool {
    // Only the latest 30 rows are sent to AI. Older contact replies must not
    // authorize a prompt that contains only the user's own statements.
    let recentEvidence = timeline.suffix(30)
    // Callers may request a stricter threshold, never weaken the six-message
    // and two-contact-reply privacy floor by passing zero or a small number.
    let requiredTotal = max(6, minimumMessages)
    guard recentEvidence.count >= requiredTotal else { return false }
    let requiredContactReplies = 2
    return recentEvidence.filter { $0.speaker == .other }.count >= requiredContactReplies
  }

  /// Group conversations contain messages from multiple people. Never
  /// collapse their speakers into an individual contact's learned profile.
  static func isEligibleForIndividualLearning(_ profile: HeartTargetProfile) -> Bool {
    return !profile.isGroup
  }

  /// Re-read the persisted contact immediately before dispatching private
  /// evidence to AI. The contact may have been deleted or reclassified as a
  /// group after the initial timeline read in another process.
  static func isCurrentIndividualProfile(
    _ profileID: UUID, in service: HeartTargetService, expectedUpdatedAt: Date? = nil
  ) -> Bool {
    guard let currentProfile = service.profile(id: profileID) else { return false }
    guard isEligibleForIndividualLearning(currentProfile) else { return false }
    // A concurrent edit may replace the private bio/name after the prompt
    // snapshot was read. Never dispatch the old snapshot to AI in that case.
    if let expectedUpdatedAt {
      return currentProfile.updatedAt == expectedUpdatedAt
    }
    return true
  }

  /// Build rows only from already authorized, human-filtered evidence. OCR or
  /// imported senderName is not an authenticated identity: in an individual
  /// conversation it must not disclose another person's name to the AI.
  static func promptEvidenceRows(
    from timeline: [ClawConversationMessage], contactDisplayName: String
  ) -> String {
    // Imported/OCR content and contact display names are untrusted text.
    // Keep one physical prompt line per actual message so embedded line
    // breaks cannot impersonate a new speaker, delimiter, or instruction.
    let safeContactName = contactDisplayName.replacingOccurrences(of: "\r\n", with: "\n")
      .components(separatedBy: .newlines)
      .joined(separator: " ↵ ")
    return timeline.suffix(30).map { message -> String in
      let who = message.speaker == .me ? "我" : safeContactName
      let safeContent = message.content.replacingOccurrences(of: "\r\n", with: "\n")
        .components(separatedBy: .newlines)
        .joined(separator: " ↵ ")
      return "\(who)：\(safeContent)"
    }.joined(separator: "\n")
  }

  /// Profile names and notes may originate from imports or OCR. Keep them
  /// inside their own prompt fields instead of allowing a newline to forge
  /// an additional instruction, section, or conversation row.
  static func safePromptMetadata(_ value: String) -> String {
    value.replacingOccurrences(of: "\r\n", with: "\n")
      .components(separatedBy: .newlines)
      .joined(separator: " ↵ ")
  }

  /// 有足够新聊天证据时自动刷新。不会因为一两句聊天就给人物下结论。
  public func refreshIfNeeded(profileID: UUID, minimumMessages: Int = 6) {
    queue.async { [weak self] in
      guard let self else { return }
      guard !self.inFlight.contains(profileID) else { return }
      guard Self.isAuthorizedForLearning(profileID: profileID, consentStore: self.consentStore) else { return }
      guard let authorizationToken = self.consentStore.authorizationToken(for: profileID) else { return }
      // A keyboard/host process may have deleted this contact while the
      // singleton's cached list still contains it. Do not read its private
      // timeline or send it to AI unless the contact still exists on disk.
      guard let profile = HeartTargetService.shared.profile(id: profileID) else { return }
      guard Self.isEligibleForIndividualLearning(profile) else { return }
      let authorizedTimeline = self.consentStore.withAuthorization(
        for: profileID,
        authorizationToken: authorizationToken
      ) {
        (try? self.store.conversation(contactID: profileID, limit: 40)) ?? []
      }
      guard let authorizedTimeline else { return }
      let timeline = Self.humanEvidence(from: authorizedTimeline, for: profileID)
      guard Self.hasSufficientContactEvidence(timeline, minimumMessages: minimumMessages) else { return }

      let authorizedExistingMemory = self.consentStore.withAuthorization(
        for: profileID,
        authorizationToken: authorizationToken
      ) {
        ((try? self.store.memories(scope: "contact", subjectID: profileID, limit: 100)) ?? [])
          .first(where: { $0.normalizedKey == "contact-profile-summary" })
      }
      guard let existingMemorySnapshot = authorizedExistingMemory else { return }
      let existingMemory = existingMemorySnapshot
      if let last = existingMemory?.lastObservedAt,
         Date().timeIntervalSince(last) < 6 * 60 * 60 {
        return
      }
      let provider = self.aiService.selectedProvider
      let model = self.aiService.selectedModel
      guard !self.aiService.apiKey(for: provider).isEmpty else { return }

      self.inFlight.insert(profileID)
      let rows = Self.promptEvidenceRows(
        from: timeline, contactDisplayName: profile.displayName
      )
      let safeDisplayName = Self.safePromptMetadata(profile.displayName)
      let safeBio = Self.safePromptMetadata(profile.bio)

      let prompt = """
      你是 CLAW 的人物画像 Skill。只根据下面真实聊天证据，提炼这个人与用户之间长期有用、相对稳定的沟通画像。
      要求：
      1. 区分事实与推断，不确定的不要写；
      2. 不做心理诊断，不贴侮辱性标签；
      3. 关注关系、沟通方式、偏好、近期稳定主题、用户与 TA 的相处方式；
      4. 最多 120 个汉字，直接输出画像正文，不要标题。

      联系人：\(safeDisplayName)
      用户手工备注：\(safeBio)
      聊天证据：
      ---
      \(rows)
      ---
      """

      var didDispatch = false
      let didStartRequest = self.consentStore.performIfGranted(
        for: profileID,
        authorizationToken: authorizationToken
      ) {
        guard Self.isCurrentIndividualProfile(
          profileID, in: HeartTargetService.shared, expectedUpdatedAt: profile.updatedAt
        ) else { return }
        didDispatch = true
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

          self.consentStore.performIfGranted(
            for: profileID,
            authorizationToken: authorizationToken
          ) {
            let learnedSummary = String(summary.prefix(240))
            // The contact may have been deleted or manually edited while AI
            // was responding. Do not recreate it or overwrite newer fields.
            guard HeartTargetService.shared.updateLearnedSummary(
              learnedSummary, for: profileID, expectedUpdatedAt: profile.updatedAt
            ) else { return }

            let now = Date()
            var memory = ClawMemoryItem(
              kind: .contactStyle,
              scope: "contact",
              subjectID: profileID,
              content: learnedSummary,
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
            try? DefaultMemorySDK(store: self.store).rememberLegacy(memory)
          }
        }
      }
      if !didStartRequest || !didDispatch {
        self.inFlight.remove(profileID)
      }
    }
  }
}
