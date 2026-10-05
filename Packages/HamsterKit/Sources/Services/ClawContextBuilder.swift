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

  public func build(contactID: UUID?, includeTasks: Bool = true) -> ClawContextPack {
    let globals = (try? store.memories(scope: "global", limit: 40)) ?? []
    let contactMemories: [ClawMemoryItem]
    let timeline: [ClawConversationMessage]
    if let contactID {
      contactMemories = (try? store.memories(scope: "contact", subjectID: contactID, limit: 40)) ?? []
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
}
Process exited with code 0.