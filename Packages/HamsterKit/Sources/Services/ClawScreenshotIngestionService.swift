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

    for message in parsed.messages {
      _ = try store.appendConversation(message)
    }
    let flush = MemoryFlushService().extract(sessionID: UUID(), messages: parsed.messages, personID: resolution.profile?.id)
    for record in flush.records { try sdk.remember(record, evidence: record.evidence) }
    for task in flush.tasks { try sdk.createTask(task) }
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

    let approved = messages.map { source -> ClawConversationMessage in
      var item = source
      item.contactID = profile.id
      item.content = source.content.trimmingCharacters(in: .whitespacesAndNewlines)
      item.confidence = 1
      return item
    }
    var inserted: [ClawConversationMessage] = []
    for item in approved {
      if try store.appendConversation(item) {
        inserted.append(item)
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
