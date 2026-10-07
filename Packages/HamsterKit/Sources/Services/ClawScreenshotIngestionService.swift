import Foundation

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
    sourceRef: String? = nil
  ) throws -> ClawScreenshotIngestionResult {
    let preview = parser.parse(lines: lines, contactID: selectedProfile?.id, contactName: selectedProfile?.displayName, capturedAt: capturedAt, sourceRef: sourceRef)
    let resolution = selectedProfile.map { ClawContactResolution(profile: $0, confidence: 1, created: false, reason: "selected") }
      ?? ClawContactIdentityResolver.shared.resolve(displayTitle: preview.detectedTitle, allowCreate: true)
    let parsed = parser.parse(lines: lines, contactID: resolution.profile?.id, contactName: resolution.profile?.displayName, capturedAt: capturedAt, sourceRef: sourceRef)
    let hasUnknownSpeaker = parsed.messages.contains { $0.speaker == .unknown }
    let weakOCR = parsed.messages.contains { $0.confidence < 0.70 }
    let requiresReview = resolution.confidence < 0.75 || hasUnknownSpeaker || weakOCR || parsed.messages.isEmpty
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
}
