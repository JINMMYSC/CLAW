import Foundation
import OSLog

/// Diagnostic metadata only. Never store user input, clipboard content, tokens,
/// memory text or error.userInfo / localizedDescription.
public struct ClawDiagnosticEvent: Codable, Equatable {
  public let timestamp: Date
  public let traceID: UUID
  public let process: String
  public let module: String
  public let action: String
  public let severity: String
  public let file: String
  public let function: String
  public let line: UInt
  public let errorDomain: String?
  public let errorCode: Int?
  public let buildVersion: String
  public let sourceCommit: String?
}

/// Separate process-local event stores. Host and Keyboard Extension must not
/// compete to write the same file; shared App Group lets the host merge later.
public final class ClawDiagnosticsCore {
  public static let shared = ClawDiagnosticsCore()
  public static let maxEvents = 2_000

  private let queue = DispatchQueue(label: "claw.diagnostics.events", qos: .utility)
  private let logger = Logger(subsystem: "app.clawtalk", category: "Diagnostics")
  private let fileURL: URL?
  private var buffer: [ClawDiagnosticEvent] = []
  public let process: String

  public init(storageURL: URL? = nil, processName: String? = nil) {
    let inferred = Bundle.main.bundleURL.pathExtension.lowercased() == "appex" ? "keyboard" : "host"
    process = processName == "keyboard" ? "keyboard" : (processName == "host" ? "host" : inferred)
    fileURL = storageURL ?? FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: HamsterConstants.appGroupName)?
      .appendingPathComponent("claw_diagnostics_\(process).json")
    if let url = fileURL,
       let data = try? Data(contentsOf: url),
       data.count <= 512 * 1024,
       let old = try? JSONDecoder().decode([ClawDiagnosticEvent].self, from: data) {
      buffer = Array(old.suffix(Self.maxEvents))
    }
  }

  /// Whitelist operational identifiers. Bad/unexpected strings are dropped.
  public static func identifier(_ value: String) -> String {
    let safe = CharacterSet(charactersIn:
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:/()-")
    guard !value.isEmpty, value.count <= 120,
          value.unicodeScalars.allSatisfy({ safe.contains($0) })
    else { return "redacted" }
    return value
  }

  public func record(
    module: String,
    action: String,
    severity: String = "info",
    traceID: UUID = UUID(),
    error: Error? = nil,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
  ) {
    let nsError = error.map { $0 as NSError }
    let level = ["info", "warning", "error"].contains(severity) ? severity : "warning"
    let commit = Bundle.main.object(forInfoDictionaryKey: "ClawSourceCommit") as? String
    let event = ClawDiagnosticEvent(
      timestamp: Date(), traceID: traceID, process: process,
      module: Self.identifier(module), action: Self.identifier(action),
      severity: level, file: Self.identifier(file),
      function: Self.identifier(function), line: line,
      errorDomain: nsError.map { Self.identifier($0.domain) },
      errorCode: nsError?.code,
      buildVersion: Self.identifier(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"),
      sourceCommit: commit.flatMap { Self.identifier($0) == "redacted" ? nil : $0 }
    )
    queue.async { [self] in
      buffer.append(event)
      if buffer.count > Self.maxEvents { buffer.removeFirst(buffer.count - Self.maxEvents) }
      if level != "info" { persist() }
      if level == "error" {
        logger.error("\(event.module, privacy: .public):\(event.action, privacy: .public) code=\(event.errorCode ?? 0, privacy: .public)")
      } else {
        logger.debug("\(event.module, privacy: .public):\(event.action, privacy: .public)")
      }
    }
  }

  public func recent(limit: Int = 100) -> [ClawDiagnosticEvent] {
    queue.sync { Array(buffer.suffix(max(0, min(limit, Self.maxEvents)))) }
  }

  /// No automatic upload: an explicit user action may export safe metadata.
  public func exportJSON(limit: Int = 500) -> Data? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try? encoder.encode(recent(limit: limit))
  }

  private func persist() {
    guard let fileURL else { return }
    let encoder = JSONEncoder()
    var count = min(300, buffer.count)
    while count > 0 {
      if let data = try? encoder.encode(Array(buffer.suffix(count))),
         data.count <= 512 * 1024 {
        try? data.write(to: fileURL, options: .atomic)
        return
      }
      count /= 2
    }
  }
}
