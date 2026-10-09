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

public struct ClawScreenshotImportReceipt: Equatable {
  public let personID: UUID
  public let messageIDs: [UUID]

  public init(personID: UUID, messageIDs: [UUID]) {
    self.personID = personID
    self.messageIDs = messageIDs
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

  public init(store: ClawMemoryStore = .shared, parser: ClawScreenshotChatParser = .shared) {
    self.store = store
    self.parser = parser
  }

  public func ingest(
    lines: [VisionOCRService.OCRLine],
    selectedProfile: HeartTargetProfile?,
    capturedAt: Date = Date(),
    sourceRef: String? = nil,
    // Kept for existing callers. A false value is no longer permission to
    // write screenshot-derived memories or tasks without explicit approval.
    requireUserReview: Bool = true
  ) throws -> ClawScreenshotIngestionResult {
    let preview = parser.parse(lines: lines, contactID: selectedProfile?.id, contactName: selectedProfile?.displayName, capturedAt: capturedAt, sourceRef: sourceRef)
    let resolution = selectedProfile.map { ClawContactResolution(profile: $0, confidence: 1, created: false, reason: "selected") }
      // Screenshot OCR is not an authorization to create a person. Unknown or
      // ambiguously matched titles must remain in review until the user chooses
      // a person explicitly. Avoid changing the current person as a side effect.
      ?? ClawContactIdentityResolver.shared.resolve(displayTitle: preview.detectedTitle, allowCreate: false)
    let parsed = parser.parse(lines: lines, contactID: resolution.profile?.id, contactName: resolution.profile?.displayName, capturedAt: capturedAt, sourceRef: sourceRef)
    // OCR confidence and even an explicitly selected person do not constitute
    // consent to save private conversations, derive tasks or build a profile.
    // This API is preview-only. Persistence is exclusively performed by the
    // explicit confirmReviewed* methods after per-message speaker review.
    // The legacy requireUserReview flag is intentionally ignored for safety.
    _ = requireUserReview
    return ClawScreenshotIngestionResult(
      profile: resolution.profile, messages: parsed.messages,
      requiresReview: true, rawText: parsed.rawText
    )
  }

  /// Explicit user-approved import. An uncertain parse never writes to memory
  /// until a known person and every message's speaker/content are confirmed.
  /// Repeated screenshots must not create duplicate derived tasks or memories.
  @discardableResult
  public func confirmReviewed(
    messages: [ClawConversationMessage],
    for profile: HeartTargetProfile
  ) throws -> Int {
    try confirmReviewedWithReceipt(messages: messages, for: profile).messageIDs.count
  }

  /// Returns only message IDs freshly inserted by this action; re-imported or
  /// overlapping bubbles are excluded, so undo cannot erase older imports.
  public func confirmReviewedWithReceipt(
    messages: [ClawConversationMessage],
    for profile: HeartTargetProfile
  ) throws -> ClawScreenshotImportReceipt {
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
    // Build a candidate batch without modifying storage; the store commits
    // bubbles, related memories and tasks atomically or rolls everything back.
    var candidates: [ClawConversationMessage] = []
    var seen = try store.conversation(contactID: profile.id, limit: 250)
    for item in approved {
      if ClawScreenshotOverlapPolicy.isOverlap(item, among: seen) { continue }
      candidates.append(item)
      seen.append(item)
    }
    let inserted = try store.commitScreenshotImport(candidates, personID: profile.id)
    return ClawScreenshotImportReceipt(
      personID: profile.id, messageIDs: inserted.map(\.id)
    )
  }

  /// Undo only a specific, verified import receipt. Duplicate messages from
  /// earlier imports were not in the receipt and remain untouched.
  public func undo(_ receipt: ClawScreenshotImportReceipt) throws -> Int {
    try store.undoScreenshotImport(
      messageIDs: receipt.messageIDs, personID: receipt.personID
    )
  }
}
