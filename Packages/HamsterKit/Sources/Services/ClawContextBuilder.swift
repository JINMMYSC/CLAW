import Foundation

public struct ClawContextPack: Equatable {
  public var globalMemories: [ClawMemoryItem]
  public var contactMemories: [ClawMemoryItem]
  public var recentConversation: [ClawConversationMessage]
  public var openTasks: [ClawSecretaryTask]

  public init(
    globalMemories: [ClawMemoryItem] = [],
    contactMemories: [ClawMemoryItem] = [],
    recentConversation: [ClawConversationMessage] = [],
    openTasks: [ClawSecretaryTask] = []
  ) {
    self.globalMemories = globalMemories
    self.contactMemories = contactMemories
    self.recentConversation = recentConversation
    self.openTasks = openTasks
  }

  public var isEmpty: Bool {
    globalMemories.isEmpty && contactMemories.isEmpty && recentConversation.isEmpty && openTasks.isEmpty
  }

  public func promptBlock(maxCharacters: Int = 6_000) -> String {
    var sections: [String] = []
    if !globalMemories.isEmpty {
      sections.append("我的长期习惯：\n" + globalMemories.prefix(12).map { "- \($0.content)" }.joined(separator: "\n"))
    }
    if !contactMemories.isEmpty {
      sections.append("当前聊天对象相关记忆：\n" + contactMemories.prefix(12).map { "- \($0.content)" }.joined(separator: "\n"))
    }
    if !recentConversation.isEmpty {
      let rows = recentConversation.suffix(16).map { message in
        let who: String
        switch message.speaker {
        case .me: who = "我"
        case .other: who = message.senderName ?? "对方"
        case .assistant: who = "CLAW"
        case .system: who = "系统"
        case .unknown: who = message.senderName ?? "未知"
        }
        return "\(who)：\(message.content)"
      }
      sections.append("最近聊天时间线：\n" + rows.joined(separator: "\n"))
    }
    if !openTasks.isEmpty {
      sections.append("相关未完成事项：\n" + openTasks.prefix(8).map { "- [\($0.kind.rawValue)] \($0.title)" }.joined(separator: "\n"))
    }
    let result = sections.joined(separator: "\n\n")
    return String(result.prefix(maxCharacters))
  }
}

/// 所有 AI 功能共享的上下文检索 seam。避免每个页面各自拼接一套“记忆”。
public final class ClawContextBuilder {
  public static let shared = ClawContextBuilder()
  private let store: ClawMemoryStore

  public init(store: ClawMemoryStore = .shared) {
    self.store = store
  }

  public func build(contactID: UUID?, includeTasks: Bool = true, query: String? = nil) -> ClawContextPack {
    if ClawMemoryPolicyService.shared.temporaryMode {
      return ClawContextPack()
    }
    let policy = ClawMemoryPolicyService.shared
    let rawGlobals = ((try? store.memories(scope: "global", limit: 80)) ?? [])
      .filter { policy.isSourceEnabled($0.sourceType) }
    let globals = rank(rawGlobals, query: query).prefix(40).map { $0 }
    let contactMemories: [ClawMemoryItem]
    let timeline: [ClawConversationMessage]
    if let contactID {
      let rawContact = ((try? store.memories(scope: "contact", subjectID: contactID, limit: 80)) ?? [])
        .filter { policy.isSourceEnabled($0.sourceType) }
      contactMemories = rank(rawContact, query: query).prefix(40).map { $0 }
      timeline = (try? store.conversation(contactID: contactID, limit: 32)) ?? []
    } else {
      contactMemories = []
      timeline = []
    }
    let allTasks = includeTasks ? ((try? store.tasks(status: .open, limit: 40)) ?? []) : []
    let relevantTasks = contactID == nil ? allTasks : allTasks.filter { $0.contactID == nil || $0.contactID == contactID }
    return ClawContextPack(
      globalMemories: globals,
      contactMemories: contactMemories,
      recentConversation: timeline,
      openTasks: relevantTasks
    )
  }

  private func rank(_ items: [ClawMemoryItem], query: String?) -> [ClawMemoryItem] {
    guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return items.sorted { $0.lastObservedAt > $1.lastObservedAt }
    }
    let queryTokens = tokens(query)
    let now = Date()
    return items.sorted { lhs, rhs in
      score(lhs, queryTokens: queryTokens, now: now) > score(rhs, queryTokens: queryTokens, now: now)
    }
  }

  private func score(_ item: ClawMemoryItem, queryTokens: Set<String>, now: Date) -> Double {
    let memoryTokens = tokens(item.content)
    let overlap = Double(queryTokens.intersection(memoryTokens).count)
    let ageDays = max(0, now.timeIntervalSince(item.lastObservedAt) / 86_400)
    let recency = exp(-ageDays / 90)
    let exactKeyBoost = item.normalizedKey.map { key in
      queryTokens.contains(where: { key.lowercased().contains($0) }) ? 1.5 : 0
    } ?? 0
    return overlap * 3 + item.confidence * 1.5 + recency + exactKeyBoost
  }

  private func tokens(_ text: String) -> Set<String> {
    let normalized = text.lowercased()
    let words = normalized
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { $0.count >= 2 }
    let compact = String(normalized.unicodeScalars.filter {
      !CharacterSet.whitespacesAndNewlines.contains($0)
        && !CharacterSet.punctuationCharacters.contains($0)
    })
    let chars = Array(compact)
    var grams: [String] = []
    if chars.count >= 2 {
      for index in 0..<(chars.count - 1) {
        grams.append(String(chars[index...index + 1]))
      }
    }
    return Set(words + grams)
  }
}
