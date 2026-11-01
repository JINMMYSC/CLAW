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

/// An explicit screenshot review authorizes only human messages belonging to
/// the selected contact. Imported IDs must not be silently reassigned.
public enum ClawScreenshotReviewScopePolicy {
  public static func permits(_ message: ClawConversationMessage, for contactID: UUID) -> Bool {
    guard message.contactID == nil || message.contactID == contactID else { return false }
    guard message.speaker == .me || message.speaker == .other else { return false }
    guard message.sourceType == "screenshot" else { return false }
    return !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

/// End-to-end screenshot ingestion boundary. It resolves identity, routes
/// uncertain parses to review, and only persists high-confidence timelines.
public final class ClawScreenshotIngestionService {
  private let store: ClawMemoryStore
  private let parser: ClawScreenshotChatParser
  private let profileLookup: (UUID) -> HeartTargetProfile?

  public init(store: ClawMemoryStore = .shared, parser: ClawScreenshotChatParser = .shared) {
    self.store = store
    self.parser = parser
    // Always resolve a fresh, persisted contact at the write boundary.
    self.profileLookup = { HeartTargetService.shared.profile(id: $0) }
  }

  // Internal dependency injection for isolated native tests. Production
  // callers use the public initializer and the live App Group profile store.
  init(
    store: ClawMemoryStore,
    parser: ClawScreenshotChatParser = .shared,
    profileLookup: @escaping (UUID) -> HeartTargetProfile?
  ) {
    self.store = store
    self.parser = parser
    self.profileLookup = profileLookup
  }

  private func isCurrentProfile(_ snapshot: HeartTargetProfile) -> Bool {
    guard let current = profileLookup(snapshot.id) else { return false }
    // An OCR-created or group profile is not confirmed individual authority.
    // Also reject snapshots whose confirmation state changed after review.
    return current.updatedAt == snapshot.updatedAt &&
      current.name == snapshot.name &&
      // Name/mtime equality is insufficient when an imported profile changes
      // identity hints without advancing its timestamp. Require fresh review.
      current.aliases == snapshot.aliases &&
      current.avatarFingerprint == snapshot.avatarFingerprint &&
      current.isGroup == snapshot.isGroup &&
      current.autoCreated == snapshot.autoCreated &&
      !current.isGroup && !current.autoCreated
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
    // A selected profile is a snapshot. It may have been deleted, renamed or
    // reclassified while the OCR sheet was open; never prefill private identity
    // from an outdated selection, even when its old title is still visible.
    let staleSelection = selectedProfile.map { !isCurrentProfile($0) } ?? false
    let trustedSelection = staleSelection ? nil : selectedProfile
    let preview = parser.parse(
      lines: lines, contactID: trustedSelection?.id,
      contactName: trustedSelection?.displayName,
      capturedAt: capturedAt, sourceRef: sourceRef
    )
    let resolution: ClawContactResolution
    if staleSelection {
      // Do not fall back to an OCR title match for a stale explicit selection.
      // Require the user to choose the current contact again.
      resolution = ClawContactResolution(
        profile: nil, confidence: 0, created: false, reason: "stale-selection"
      )
    } else if let trustedSelection {
      resolution = ClawContactResolution(
        profile: trustedSelection, confidence: 1, created: false, reason: "selected"
      )
    } else {
      // OCR is not authorization to create or change a person.
      resolution = ClawContactIdentityResolver.shared.resolve(
        displayTitle: preview.detectedTitle, allowCreate: false
      )
    }
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
    // A stale review sheet must not resurrect a deleted, renamed or
    // reclassified contact, even when the OCR speaker rows look valid.
    guard isCurrentProfile(profile) else { throw ClawScreenshotReviewError.missingPerson }
    guard !messages.isEmpty else { throw ClawScreenshotReviewError.emptyMessages }
    guard messages.allSatisfy({
      ClawScreenshotReviewScopePolicy.permits($0, for: profile.id)
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
    // Persist only explicitly reviewed screenshot bubbles. Deriving memories
    // or creating tasks requires a separate consent decision, not an import side effect.
    var candidates: [ClawConversationMessage] = []
    var seen = try store.conversation(contactID: profile.id, limit: 250)
    for item in approved {
      if ClawScreenshotOverlapPolicy.isOverlap(item, among: seen) { continue }
      candidates.append(item)
      seen.append(item)
    }
    // Reduce the race window after potentially slow overlap queries.
    // App Group defaults and SQLite cannot share a cross-process transaction.
    guard isCurrentProfile(profile) else { throw ClawScreenshotReviewError.missingPerson }
    let inserted = try store.appendConversationsBatch(candidates)
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
