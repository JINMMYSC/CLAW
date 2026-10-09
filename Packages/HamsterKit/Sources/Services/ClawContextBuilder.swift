import Foundation
import NaturalLanguage

public struct ClawContextPack: Equatable {
  public var globalMemories: [ClawMemoryItem]
  public var contactMemories: [ClawMemoryItem]
  public var recentConversation: [ClawConversationMessage]
  public var openTasks: [ClawSecretaryTask]
  public var resolvedContactID: UUID?
  public var contactDisplayName: String?

  public init(
    globalMemories: [ClawMemoryItem] = [],
    contactMemories: [ClawMemoryItem] = [],
    recentConversation: [ClawConversationMessage] = [],
    openTasks: [ClawSecretaryTask] = [],
    resolvedContactID: UUID? = nil,
    contactDisplayName: String? = nil
  ) {
    self.globalMemories = globalMemories
    self.contactMemories = contactMemories
    self.recentConversation = recentConversation
    self.openTasks = openTasks
    self.resolvedContactID = resolvedContactID
    self.contactDisplayName = contactDisplayName
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
      let title = contactDisplayName.map { "\($0)相关记忆" } ?? "当前聊天对象相关记忆"
      sections.append("\(title)：\n" + contactMemories.prefix(12).map { "- \($0.content)" }.joined(separator: "\n"))
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
  private let profilesProvider: () -> [HeartTargetProfile]
  private let personResolver: ClawQueryPersonResolver

  public init(
    store: ClawMemoryStore = .shared,
    profilesProvider: @escaping () -> [HeartTargetProfile] = { HeartTargetService.shared.profiles },
    personResolver: ClawQueryPersonResolver = ClawQueryPersonResolver()
  ) {
    self.store = store
    self.profilesProvider = profilesProvider
    self.personResolver = personResolver
  }

  public func build(contactID: UUID?, includeTasks: Bool = true, query: String? = nil) -> ClawContextPack {
    if ClawMemoryPolicyService.shared.temporaryMode {
      return ClawContextPack()
    }
    let policy = ClawMemoryPolicyService.shared
    let vault = ClawPrivacyVaultService.shared
    let profiles = profilesProvider()
    let effectiveContactID = contactID ?? personResolver.resolve(query: query, profiles: profiles)
    let resolvedProfile = effectiveContactID.flatMap { id in profiles.first(where: { $0.id == id }) }
    let sdk = DefaultMemorySDK(store: store)
    let rawGlobals = ((try? sdk.contextualMemories(scope: "global", limit: 80)) ?? [])
      .filter { policy.isSourceEnabled($0.sourceType) && vault.isVisibleToAI($0) }
    let globals = rank(rawGlobals, query: query).prefix(40).map { $0 }
    let contactMemories: [ClawMemoryItem]
    let timeline: [ClawConversationMessage]
    if let effectiveContactID {
      let rawContact = ((try? sdk.contextualMemories(scope: "contact", personID: effectiveContactID, limit: 80)) ?? [])
        .filter { policy.isSourceEnabled($0.sourceType) && vault.isVisibleToAI($0) }
      contactMemories = rank(rawContact, query: query).prefix(40).map { $0 }
      timeline = (try? store.conversation(contactID: effectiveContactID, limit: 32)) ?? []
    } else {
      contactMemories = []
      timeline = []
    }
    let allTasks = includeTasks ? ((try? store.tasks(status: .open, limit: 40)) ?? []) : []
    let relevantTasks = allTasks.filter { task in
      // Unresolved global queries must not inherit person-private tasks.
      guard let taskContactID = task.contactID else { return true }
      return effectiveContactID.map { $0 == taskContactID } ?? false
    }
    return ClawContextPack(
      globalMemories: globals,
      contactMemories: contactMemories,
      recentConversation: timeline,
      openTasks: relevantTasks,
      resolvedContactID: effectiveContactID,
      contactDisplayName: resolvedProfile?.displayName
    )
  }

  private func rank(_ items: [ClawMemoryItem], query: String?) -> [ClawMemoryItem] {
    guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return items.sorted { $0.lastObservedAt > $1.lastObservedAt }
    }
    let queryTokens = tokens(query)
    // Avoid allocating on-device sentence embeddings inside a keyboard
    // extension: all per-keystroke context ranking stays lexical and bounded.
    // The host app may still use semantic ranking on demand.
    let isKeyboardExtension = Bundle.main.bundleURL.pathExtension.lowercased() == "appex"
    let semantic = isKeyboardExtension ? nil : semanticQuery(query)
    let now = Date()
    return items.sorted { lhs, rhs in
      score(lhs, queryTokens: queryTokens, semantic: semantic, now: now)
        > score(rhs, queryTokens: queryTokens, semantic: semantic, now: now)
    }
  }

  private func score(
    _ item: ClawMemoryItem,
    queryTokens: Set<String>,
    semantic: SemanticQuery?,
    now: Date
  ) -> Double {
    let memoryTokens = tokens(item.content)
    let overlap = Double(queryTokens.intersection(memoryTokens).count)
    let ageDays = max(0, now.timeIntervalSince(item.lastObservedAt) / 86_400)
    let recency = exp(-ageDays / 90)
    let exactKeyBoost = item.normalizedKey.map { key in
      queryTokens.contains(where: { key.lowercased().contains($0) }) ? 1.5 : 0
    } ?? 0
    let semanticBoost = semanticSimilarity(item.content, using: semantic) * 4
    return overlap * 2.5 + semanticBoost + item.confidence * 1.5 + recency + exactKeyBoost
  }

  private struct SemanticQuery {
    let embedding: NLEmbedding
    let vector: [Double]
  }

  /// Apple's on-device sentence embeddings give CLAW true semantic retrieval
  /// without sending the user's Memory Core to a cloud embedding endpoint.
  /// Unsupported languages/devices simply fall back to the lexical ranker.
  private func semanticQuery(_ query: String) -> SemanticQuery? {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(query)
    let language = recognizer.dominantLanguage ?? .simplifiedChinese
    guard
      let embedding = NLEmbedding.sentenceEmbedding(for: language),
      let vector = embedding.vector(for: query),
      !vector.isEmpty
    else { return nil }
    return SemanticQuery(embedding: embedding, vector: vector)
  }

  private func semanticSimilarity(_ text: String, using query: SemanticQuery?) -> Double {
    guard let query, let candidate = query.embedding.vector(for: text), candidate.count == query.vector.count else {
      return 0
    }
    var dot = 0.0
    var left = 0.0
    var right = 0.0
    for index in candidate.indices {
      dot += query.vector[index] * candidate[index]
      left += query.vector[index] * query.vector[index]
      right += candidate[index] * candidate[index]
    }
    guard left > 0, right > 0 else { return 0 }
    return max(0, min(1, dot / (sqrt(left) * sqrt(right))))
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
