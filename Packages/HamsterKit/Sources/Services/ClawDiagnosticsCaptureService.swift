import Foundation
import ZIPFoundation

public enum ClawDiagnosticsSourceState: String, Codable {
  case recent, stale, missing, unavailable, corrupted
}

public struct ClawDiagnosticIncident: Codable {
  public let traceID: UUID
  public let failureModule: String
  public let failureAction: String
  public let errorDomain: String?
  public let errorCode: Int?
  public let observedAt: Date
  public let relatedEventCount: Int
}

public struct ClawDiagnosticCapture: Codable {
  public let schemaVersion: Int
  public let capturedAt: Date
  public let hostState: ClawDiagnosticsSourceState
  public let keyboardState: ClawDiagnosticsSourceState
  public let events: [ClawDiagnosticEvent]
  public let incidents: [ClawDiagnosticIncident]
}

/// Explicit on-device capture. The host only reads the keyboard's last
/// persisted snapshot: "recent" does not prove the extension is running.
public enum ClawDiagnosticsCaptureService {
  public static let snapshotLimit = 512 * 1024

  public static func readKeyboard(
    at url: URL?,
    now: Date = Date()
  ) -> (events: [ClawDiagnosticEvent], state: ClawDiagnosticsSourceState) {
    guard let url else { return ([], .unavailable) }
    guard FileManager.default.fileExists(atPath: url.path) else { return ([], .missing) }
    guard let data = try? Data(contentsOf: url), data.count <= snapshotLimit,
          let raw = try? JSONDecoder().decode([ClawDiagnosticEvent].self, from: data)
    else { return ([], .corrupted) }
    let events = raw.filter { $0.process == "keyboard" }
    guard let newest = events.map(\.timestamp).max() else { return ([], .missing) }
    let state: ClawDiagnosticsSourceState =
      now.timeIntervalSince(newest) <= 300 && now >= newest ? .recent : .stale
    return (Array(events.suffix(300)), state)
  }

  public static func capture(
    hostEvents: [ClawDiagnosticEvent],
    keyboardEvents: [ClawDiagnosticEvent],
    keyboardState: ClawDiagnosticsSourceState,
    now: Date = Date()
  ) -> ClawDiagnosticCapture {
    let combined = (hostEvents + keyboardEvents)
      .sorted { $0.timestamp < $1.timestamp }
      .suffix(2_000)
    let events = Array(combined)
    let errors = events.filter { $0.severity == "error" }.suffix(40)
    let incidents = errors.map { error in
      let matching = events.filter {
        $0.traceID == error.traceID ||
        ($0.timestamp >= error.timestamp.addingTimeInterval(-60) &&
         $0.timestamp <= error.timestamp.addingTimeInterval(30))
      }
      return ClawDiagnosticIncident(
        traceID: error.traceID,
        failureModule: error.module,
        failureAction: error.action,
        errorDomain: error.errorDomain,
        errorCode: error.errorCode,
        observedAt: error.timestamp,
        relatedEventCount: matching.count
      )
    }
    return ClawDiagnosticCapture(
      schemaVersion: 1,
      capturedAt: now,
      hostState: hostEvents.isEmpty ? .missing : .recent,
      keyboardState: keyboardState,
      events: events,
      incidents: incidents
    )
  }

  public static func captureCurrent() -> ClawDiagnosticCapture {
    let folder = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: HamsterConstants.appGroupName)
    let keyboard = readKeyboard(at: folder?.appendingPathComponent("claw_diagnostics_keyboard.json"))
    return capture(
      hostEvents: ClawDiagnosticsCore.shared.recent(limit: 1_500),
      keyboardEvents: keyboard.events,
      keyboardState: keyboard.state
    )
  }

  /// Bound lifetime of exported *diagnostic* ZIPs. Keep in-progress shares
  /// for at least an hour; never delete arbitrary temp directories or user files.
  static func pruneOldExports(
    in root: URL, now: Date = Date(), maxAge: TimeInterval = 24 * 3_600,
    keepLatest: Int = 5
  ) {
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(
      at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]
    ) else { return }
    let candidates: [(url: URL, timestamp: Date)] = entries.compactMap { url in
      let name = url.lastPathComponent
      guard name.hasPrefix("claw-report-"),
            UUID(uuidString: String(name.dropFirst("claw-report-".count))) != nil,
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
            fm.fileExists(atPath: url.appendingPathComponent("CLAW-Diagnostics.zip").path)
      else { return nil }
      let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))
        ?.contentModificationDate ?? now
      return (url, modified)
    }.sorted { $0.timestamp > $1.timestamp }
    for (index, candidate) in candidates.enumerated() {
      let age = now.timeIntervalSince(candidate.timestamp)
      guard age > maxAge || (index >= max(1, keepLatest) && age > 3_600) else {
        continue
      }
      try? fm.removeItem(at: candidate.url)
    }
  }

  /// Must only be invoked from an explicit share action in the Host App.
  /// The zip has no raw speech, input or clipboard payloads; contains only
  /// field-whitelisted events, metadata, and source availability warnings.
  public static func exportZip(capture: ClawDiagnosticCapture = captureCurrent()) throws -> URL {
    pruneOldExports(in: FileManager.default.temporaryDirectory)
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-report-" + UUID().uuidString, isDirectory: true)
    let staged = root.appendingPathComponent("claw-diagnostics", isDirectory: true)
    try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: staged) }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(capture).write(
      to: staged.appendingPathComponent("diagnostics.json"), options: .atomic)
    let notice = """
    CLAW Diagnostics - privacy-minimized on-device trace.
    No keyboard input, speech transcripts, clipboard text, contacts, API keys or private Memory.
    Keyboard status indicates last persisted event, NOT real-time process liveness.
    Callsite identifiers are logging locations, not proof of root cause.
    Native crash reports and dSYM must be collected separately if required.
    """
    try Data(notice.utf8).write(to: staged.appendingPathComponent("README.txt"), options: .atomic)
    let zip = root.appendingPathComponent("CLAW-Diagnostics.zip")
    try FileManager.default.zipItem(at: staged, to: zip)
    return zip
  }
}
