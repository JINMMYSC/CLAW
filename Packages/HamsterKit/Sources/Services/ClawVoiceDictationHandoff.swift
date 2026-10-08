import Foundation

/// Transfers *text only* from the containing app to the keyboard extension.
/// No audio or transcript is sent to a server. Results expire after 10 minutes
/// and are inserted only on an explicit tap in the keyboard.
public final class ClawVoiceDictationHandoff {
  public enum State: String, Codable {
    case idle, pending, ready, failed
  }

  public struct Snapshot: Equatable {
    public let state: State
    public let id: UUID?
    public let text: String?
    public let error: String?
  }

  private struct Record: Codable {
    var id: UUID
    var createdAt: Date
    var state: State
    var text: String?
    var error: String?
  }

  private let defaults: UserDefaults
  private let storageKey = "claw_voice_dictation_handoff_v1"
  private let maxAge: TimeInterval = 600
  public let isSharedAvailable: Bool

  public static let shared: ClawVoiceDictationHandoff = {
    if let group = UserDefaults(suiteName: HamsterConstants.appGroupName) {
      return ClawVoiceDictationHandoff(defaults: group)
    }
    return ClawVoiceDictationHandoff(defaults: .standard, isSharedAvailable: false)
  }()

  public init(defaults: UserDefaults, isSharedAvailable: Bool = true) {
    self.defaults = defaults
    self.isSharedAvailable = isSharedAvailable
  }

  public var snapshot: Snapshot { snapshot(at: Date()) }

  public func snapshot(at now: Date) -> Snapshot {
    guard let record = validRecord(at: now) else {
      return Snapshot(state: .idle, id: nil, text: nil, error: nil)
    }
    return Snapshot(state: record.state, id: record.id, text: record.text, error: record.error)
  }

  @discardableResult
  public func begin(at now: Date = Date()) -> UUID {
    let id = UUID()
    write(Record(id: id, createdAt: now, state: .pending, text: nil, error: nil))
    return id
  }

  /// A second keyboard tap must not replace the UUID held by the host recorder.
  /// Only an idle handoff may be created. A failure must be explicitly dismissed.
  @discardableResult
  public func beginIfIdle(at now: Date = Date()) -> UUID? {
    guard snapshot(at: now).state == .idle else { return nil }
    return begin(at: now)
  }

  @discardableResult
  public func complete(id: UUID, text: String) -> Bool {
    guard var record = validRecord(at: Date()), record.id == id, record.state == .pending else { return false }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    record.state = .ready
    record.text = trimmed
    write(record)
    return true
  }

  @discardableResult
  public func fail(id: UUID, reason: String) -> Bool {
    guard var record = validRecord(at: Date()), record.id == id, record.state == .pending else { return false }
    record.state = .failed
    record.error = reason
    write(record)
    return true
  }

  public func cancel(id: UUID) {
    guard validRecord(at: Date())?.id == id else { return }
    clear()
  }

  /// Consume once. Do not auto-insert into a different application's field.
  public func consume() -> String? {
    guard let record = validRecord(at: Date()), record.state == .ready else { return nil }
    clear()
    return record.text
  }

  public func dismissFailure() {
    guard snapshot.state == .failed else { return }
    clear()
  }

  private func validRecord(at now: Date) -> Record? {
    guard let data = defaults.data(forKey: storageKey),
          let record = try? JSONDecoder().decode(Record.self, from: data) else { return nil }
    guard now.timeIntervalSince(record.createdAt) >= 0,
          now.timeIntervalSince(record.createdAt) < maxAge else {
      clear()
      return nil
    }
    return record
  }

  private func write(_ record: Record) {
    guard let data = try? JSONEncoder().encode(record) else { return }
    defaults.set(data, forKey: storageKey)
  }

  private func clear() {
    defaults.removeObject(forKey: storageKey)
  }
}
