import Foundation
import ZIPFoundation

public struct ClawMemoryImportPreview: Equatable {
  public var candidates: [ClawMemoryItem]
  public var tasks: [ClawSecretaryTask]
  public var skills: [ClawSkillDefinition]
  public var duplicateCount: Int
  public var sourceName: String

  public init(
    candidates: [ClawMemoryItem],
    tasks: [ClawSecretaryTask] = [],
    skills: [ClawSkillDefinition] = [],
    duplicateCount: Int = 0,
    sourceName: String
  ) {
    self.candidates = candidates
    self.tasks = tasks
    self.skills = skills
    self.duplicateCount = duplicateCount
    self.sourceName = sourceName
  }
}

/// Agent 记忆交换层。Markdown 面向人/通用 Agent，JSON/JSONL 面向机器；内部 canonical store 仍是 SQLite。
public final class ClawMemoryExchangeService {
  public static let shared = ClawMemoryExchangeService()
  private let store: ClawMemoryStore

  public init(store: ClawMemoryStore = .shared) {
    self.store = store
  }

  public func exportMarkdown(includeContacts: Bool = true) throws -> String {
    var sections = ["# CLAW Memory Export", "", "Generated: \(ISO8601DateFormatter().string(from: Date()))", ""]
    let globals = try store.memories(scope: "global", limit: 5_000)
    sections.append("## Global Memory")
    sections.append(contentsOf: globals.map { "- [\($0.kind.rawValue)] \($0.content)" })

    if includeContacts {
      let contactMemories = try store.memories(scope: "contact", limit: 5_000)
      if !contactMemories.isEmpty {
        sections.append("\n## Contact-scoped Memory")
        sections.append(contentsOf: contactMemories.map { item in
          "- [\(item.kind.rawValue)] [contact:\(item.subjectID?.uuidString ?? "unknown")] \(item.content)"
        })
      }
    }

    let tasks = try store.tasks(status: .open, limit: 2_000)
    if !tasks.isEmpty {
      sections.append("\n## Open Tasks")
      sections.append(contentsOf: tasks.map { task in
        let due = task.dueAt.map { " due=\(ISO8601DateFormatter().string(from: $0))" } ?? ""
        return "- [\(task.kind.rawValue)] \(task.title)\(due)"
      })
    }
    return sections.joined(separator: "\n") + "\n"
  }

  public func exportJSON() throws -> Data {
    let envelope = ClawMemoryExchangeEnvelope(
      version: 1,
      exportedAt: Date(),
      memories: try store.memories(limit: 10_000),
      tasks: try store.tasks(status: .open, limit: 5_000)
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(envelope)
  }

  public func exportJSONL() throws -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try store.memories(limit: 10_000).map { item in
      String(data: try encoder.encode(item), encoding: .utf8) ?? ""
    }.joined(separator: "\n") + "\n"
  }

  /// Full-fidelity CLAW backup. The custom extension is a normal ZIP container with transparent JSON files.
  public func exportClawMemoryPackage() throws -> URL {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("claw-memory-package-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    let manifest: [String: Any] = [
      "format": "clawmemory",
      "version": 1,
      "exported_at": ISO8601DateFormatter().string(from: Date()),
    ]
    let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    try manifestData.write(to: root.appendingPathComponent("manifest.json"), options: .atomic)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(try store.memories(limit: 50_000)).write(to: root.appendingPathComponent("memories.json"), options: .atomic)
    try encoder.encode(try store.tasks(status: .open, limit: 20_000)).write(to: root.appendingPathComponent("tasks.json"), options: .atomic)
    try encoder.encode(try store.skills()).write(to: root.appendingPathComponent("skills.json"), options: .atomic)

    let target = fm.temporaryDirectory.appendingPathComponent("CLAW-Memory-\(Int(Date().timeIntervalSince1970)).clawmemory")
    try? fm.removeItem(at: target)
    try fm.zipItem(at: root, to: target, shouldKeepParent: false)
    return target
  }

  public func previewImport(data: Data, fileName: String) throws -> ClawMemoryImportPreview {
    let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
    switch ext {
    case "clawmemory", "zip":
      return try previewPackage(data: data, fileName: fileName)
    case "json":
      let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
      if let envelope = try? decoder.decode(ClawMemoryExchangeEnvelope.self, from: data) {
        return ClawMemoryImportPreview(candidates: envelope.memories, sourceName: fileName)
      }
      if let items = try? decoder.decode([ClawMemoryItem].self, from: data) {
        return ClawMemoryImportPreview(candidates: items, sourceName: fileName)
      }
      fallthrough
    case "jsonl":
      let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
      let text = String(decoding: data, as: UTF8.self)
      let rows = text.split(whereSeparator: \.isNewline).compactMap { line -> ClawMemoryItem? in
        try? decoder.decode(ClawMemoryItem.self, from: Data(line.utf8))
      }
      if !rows.isEmpty { return ClawMemoryImportPreview(candidates: rows, sourceName: fileName) }
      fallthrough
    default:
      return previewMarkdown(String(decoding: data, as: UTF8.self), sourceName: fileName)
    }
  }

  public func commit(_ preview: ClawMemoryImportPreview) throws -> Int {
    var inserted = 0
    for var item in preview.candidates {
      item.sourceType = item.sourceType.isEmpty ? "agent-import" : item.sourceType
      item.sourceRef = item.sourceRef ?? preview.sourceName
      _ = try store.upsertMemory(item)
      inserted += 1
    }
    for task in preview.tasks { try store.upsertTask(task) }
    for skill in preview.skills { try store.saveSkill(skill) }
    return inserted
  }

  private func previewPackage(data: Data, fileName: String) throws -> ClawMemoryImportPreview {
    let fm = FileManager.default
    let archiveURL = fm.temporaryDirectory.appendingPathComponent("claw-import-\(UUID().uuidString).zip")
    let folder = fm.temporaryDirectory.appendingPathComponent("claw-import-\(UUID().uuidString)", isDirectory: true)
    try data.write(to: archiveURL, options: .atomic)
    defer {
      try? fm.removeItem(at: archiveURL)
      try? fm.removeItem(at: folder)
    }
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    try fm.unzipItem(at: archiveURL, to: folder)
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let memoriesURL = folder.appendingPathComponent("memories.json")
    let tasksURL = folder.appendingPathComponent("tasks.json")
    let skillsURL = folder.appendingPathComponent("skills.json")
    let memories = (try? decoder.decode([ClawMemoryItem].self, from: Data(contentsOf: memoriesURL))) ?? []
    let tasks = (try? decoder.decode([ClawSecretaryTask].self, from: Data(contentsOf: tasksURL))) ?? []
    let skills = (try? decoder.decode([ClawSkillDefinition].self, from: Data(contentsOf: skillsURL))) ?? []
    guard !memories.isEmpty || !tasks.isEmpty || !skills.isEmpty else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return ClawMemoryImportPreview(candidates: memories, tasks: tasks, skills: skills, sourceName: fileName)
  }

  private func previewMarkdown(_ markdown: String, sourceName: String) -> ClawMemoryImportPreview {
    let lines = markdown.split(whereSeparator: \.isNewline)
    var items: [ClawMemoryItem] = []
    for raw in lines {
      var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty, !line.hasPrefix("#") else { continue }
      if line.hasPrefix("- ") { line.removeFirst(2) }
      if line.hasPrefix("* ") { line.removeFirst(2) }
      guard line.count >= 4 else { continue }
      let lower = line.lowercased()
      let kind: ClawMemoryKind
      if lower.contains("习惯") || lower.contains("preference") || lower.contains("style") { kind = .communicationPreference }
      else if lower.contains("项目") || lower.contains("project") { kind = .project }
      else if lower.contains("不要") || lower.contains("避免") || lower.contains("dislike") { kind = .negativePreference }
      else { kind = .fact }
      items.append(ClawMemoryItem(
        kind: kind,
        content: line,
        normalizedKey: line.lowercased(),
        sourceType: "agent-import",
        sourceRef: sourceName,
        confidence: 0.8
      ))
    }
    return ClawMemoryImportPreview(candidates: items, sourceName: sourceName)
  }
}

public struct ClawMemoryExchangeEnvelope: Codable, Equatable {
  public var version: Int
  public var exportedAt: Date
  public var memories: [ClawMemoryItem]
  public var tasks: [ClawSecretaryTask]

  public init(version: Int, exportedAt: Date, memories: [ClawMemoryItem], tasks: [ClawSecretaryTask]) {
    self.version = version
    self.exportedAt = exportedAt
    self.memories = memories
    self.tasks = tasks
  }
}
