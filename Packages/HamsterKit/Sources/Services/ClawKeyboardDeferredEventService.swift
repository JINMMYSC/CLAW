import Foundation

/// A very small App Group queue used by the Keyboard Extension.
///
/// The keyboard must stay lightweight: it records the final session here and exits.
/// SQLite writes, task extraction, contact learning and Evolution feedback are drained
/// later by the host app, where memory and execution budgets are much less constrained.
public struct ClawDeferredKeyboardSession: Codable, Identifiable, Equatable {
  public let id: UUID
  public var contactID: UUID?
  public var text: String
  public var occurredAt: Date
  public var sourceRef: String

  public init(
    id: UUID = UUID(),
    contactID: UUID?,
    text: String,
    occurredAt: Date,
    sourceRef: String
  ) {
    self.id = id
    self.contactID = contactID
    self.text = text
    self.occurredAt = occurredAt
    self.sourceRef = sourceRef
  }
}

public final class ClawKeyboardDeferredEventService {
  public static let shared = ClawKeyboardDeferredEventService()

  private let defaults = UserDefaults(suiteName: HamsterConstants.appGroupName)
  private let key = "claw_keyboard_deferred_sessions_v1"
  private let lock = NSLock()

  private init() {}

  public func enqueue(_ event: ClawDeferredKeyboardSession) {
    let trimmed = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    lock.lock()
    defer { lock.unlock() }
    var rows = load()
    rows.append(event)
    // Bound extension-side storage. Raw CLAW TALK records remain the canonical fallback.
    rows = Array(rows.suffix(200))
    defaults?.set(try? JSONEncoder().encode(rows), forKey: key)
  }

  /// Host-app only. Returns the number of queued keyboard sessions successfully consumed.
  @discardableResult
  public func drainIntoHostServices() -> Int {
    guard Bundle.main.bundleURL.pathExtension.lowercased() != "appex" else { return 0 }

    lock.lock()
    let snapshot = load()
    lock.unlock()
    guard !snapshot.isEmpty else { return 0 }

    var consumed = Set<UUID>()
    for event in snapshot {
      let trimmed = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        consumed.insert(event.id)
        continue
      }

      _ = ClawGeneratedOutputTracker.shared.reconcile(finalSessionText: trimmed, now: Date())

      let message = ClawConversationMessage(
        contactID: event.contactID,
        speaker: .me,
        senderName: "我",
        content: trimmed,
        occurredAt: event.occurredAt,
        sourceType: "keyboard-session",
        sourceRef: event.sourceRef,
        confidence: 1
      )
      if (try? ClawMemoryStore.shared.appendConversation(message)) == true {
        ClawSecretaryExtractor.shared.persistExtractedTasks(from: message)
        if let contactID = event.contactID {
          ClawContactProfileLearner.shared.refreshIfNeeded(profileID: contactID)
        }
      }
      consumed.insert(event.id)
    }

    lock.lock()
    var current = load()
    current.removeAll { consumed.contains($0.id) }
    defaults?.set(try? JSONEncoder().encode(current), forKey: key)
    lock.unlock()
    return consumed.count
  }

  private func load() -> [ClawDeferredKeyboardSession] {
    guard let data = defaults?.data(forKey: key),
          let rows = try? JSONDecoder().decode([ClawDeferredKeyboardSession].self, from: data)
    else { return [] }
    return rows
  }
}
