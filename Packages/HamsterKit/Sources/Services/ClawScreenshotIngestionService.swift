import Foundation

public enum ClawScreenshotReviewError: LocalizedError {
  case missingPerson, emptyMessages, unresolvedMessage

  public var errorDescription: String? {
    switch self {
    case .missingPerson: return "请先确认聊天对象"
    case .emptyMessages: return "截图中没有可以归档的消息"
    case .unresolvedMessage: return "请检查每条消息的文字和发言者"
    }
  }
}

public struct ClawScreenshotIngestionResult: Equatable {
  public var profile: HeartTargetProfile?
  public var messages: [ClawConversationMessage]
  public var requiresReview: Bool
  public var rawText: String

  public init(profile: HeartTargetProfile?, messages: [ClawConversationMessage], requiresReview: Bool, rawText: String) {
    self.profile = profile
    self.messages = messages
    self.requiresReview = requiresReview
    self.rawText = rawText
  }
}

/// Conservative exact-match rule for overlapping chat screenshots. A
/// frequent short reply such as "好的" is never collapsed; compare only long
/// phrases from two distinct screenshots of the *same person* and speaker.
public enum ClawScreenshotOverlapPolicy {
  public static func isOverlap(
    _ candidate: ClawConversationMessage,
    among existing: [ClawConversationMessage]
  ) -> Bool {
    guard candidate.sourceType == "screenshot",
          let source = candidate.sourceRef, source.hasPrefix("screenshot-digest:") else {
      return false
    }
    let value = candidate.content.lowercased().filter { !$0.isWhitespace }
    guard value.count >= 16 else { return false }
    return existing.contains { old in
      guard old.contactID == candidate.contactID,
            old.speaker == candidate.speaker, old.sourceType == "screenshot",
            let prior = old.sourceRef, prior.hasPrefix("screenshot-digest:"),
            prior != source,
            abs(old.occurredAt.timeIntervalSince(candidate.occurredAt)) <= 172_800 else {
        return false
      }
      return old.content.lowercased().filter { !$0.isWhitespace } == value
    }
  }
}

/// End-to-end screenshot ingestion boundary. It resolves identity, routes
/// uncertain parses to review, and only persists high-confidence timelines.
public final class ClawScreenshotIngestionService {
  private let store: ClawMemoryStore
  private let parser: ClawScreenshotChatParser
  private let sdk: DefaultMemorySDK

  public init(store: ClawMemoryStore = .shared, parser: ClawScreenshotChatParser = .shared) {
    self.store = store
    self.parser = parser
    self.sdk = DefaultMemorySDK(store: store)
  }

  public func ingest(
    lines: [VisionOCRService.OCRLine],
    selectedProfile: HeartTargetProfile?,
    capturedAt: Date = Date(),
    sourceRef: String? = nil,
    requireUserReview: Bool = false
  ) throws -> ClawScreenshotIngestionResult {
    let preview = parser.parse(lines: lines, contactID: selectedProfile?.id, contactName: selectedProfile?.displayName, capturedAt: capturedAt, sourceRef: sourceRef)
    let resolution = selectedProfile.map { ClawContactResolution(profile: $0, confidence: 1, created: false, reason: "selected") }
      // Screenshot OCR is not an authorization to create a person. Unknown or
      // ambiguously matched titles must remain in review until the user chooses
      // a person explicitly. Avoid changing the current person as a side effect.
      ?? ClawContactIdentityResolver.shared.resolve(displayTitle: preview.detectedTitle, allowCreate: false)
    let parsed = parser.parse(lines: lines, contactID: resolution.profile?.id, contactName: resolution.profile?.displayName, capturedAt: capturedAt, sourceRef: sourceRef)
    let hasUnknownSpeaker = parsed.messages.contains { $0.speaker == .unknown }
    let weakOCR = parsed.messages.contains { $0.confidence < 0.70 }
    let requiresReview: Bool
    if selectedProfile != nil {
      // A user-selected person is an explicit routing decision. Preserve OCR
      // confidence on each message for later review, but import the timeline
      // directly as long as at least one bubble was recognized.
      requiresReview = requireUserReview || hasUnknownSpeaker || weakOCR || parsed.messages.isEmpty
    } else {
      // Fuzzy title matches (0.82) are suggestions, not verified identities.
      requiresReview = requireUserReview || resolution.profile == nil || resolution.confidence < 0.90 || hasUnknownSpeaker || weakOCR || parsed.messages.isEmpty
    }
    let result = ClawScreenshotIngestionResult(profile: resolution.profile, messages: parsed.messages, requiresReview: requiresReview, rawText: parsed.rawText)
    guard !requiresReview else { return result }

    // Auto-approved screenshots still share the same idempotent write
    // boundary as user-reviewed imports: only *new* bubbles derive memory
    // and tasks. Never persist an unowned screenshot to global context.
    if let profile = resolution.profile {
      _ = try confirmReviewed(messages: parsed.messages, for: profile)
    }
    return result
  }

  /// Explicit user-approved import. An uncertain parse never writes to memory
  /// until a known person and every message's speaker/content are confirmed.
  /// Repeated screenshots must not create duplicate derived tasks or memories.
  @discardableResult
  public func confirmReviewed(
    messages: [ClawConversationMessage],
    for profile: HeartTargetProfile
  ) throws -> Int {
    guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ClawScreenshotReviewError.missingPerson
    }
    guard !messages.isEmpty else { throw ClawScreenshotReviewError.emptyMessages }
    guard messages.allSatisfy({
      !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      $0.speaker != .unknown
    }) else { throw ClawScreenshotReviewError.unresolvedMessage }

    let approved = messages.enumerated().map { entry -> ClawConversationMessage in
      var item = entry.element
      item.contactID = profile.id
      item.content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
      item.confidence = 1
      if let source = item.sourceRef, source.hasPrefix("screenshot-digest:") {
        item.sourceRef = "\(source)#row=\(entry.offset)"
      }
      return item
    }
    var inserted: [ClawConversationMessage] = []
    // Fetch a bounded window once, rather than perform an extra database
    // query for every OCR bubble. Dedup never crosses a person boundary.
    var seen = try store.conversation(contactID: profile.id, limit: 250)
    for item in approved {
      if ClawScreenshotOverlapPolicy.isOverlap(item, among: seen) { continue }
      if try store.appendConversation(item) {
        inserted.append(item)
        seen.append(item)
      }
    }
    guard !inserted.isEmpty else { return 0 }
    let flush = MemoryFlushService().extract(
      sessionID: UUID(), messages: inserted, personID: profile.id
    )
    for record in flush.records { try sdk.remember(record, evidence: record.evidence) }
    for task in flush.tasks { try sdk.createTask(task) }
    return inserted.count
  }
}
