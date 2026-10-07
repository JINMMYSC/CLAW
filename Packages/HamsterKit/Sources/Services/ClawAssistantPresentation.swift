import Foundation

public struct ClawConversationSection: Equatable, Identifiable {
  public var day: Date
  public var messages: [ClawChatMessage]
  public var id: Date { day }

  public init(day: Date, messages: [ClawChatMessage]) {
    self.day = day
    self.messages = messages
  }
}

public enum ClawConversationPresentation {
  public static func group(_ messages: [ClawChatMessage], calendar: Calendar = .current) -> [ClawConversationSection] {
    Dictionary(grouping: messages) { calendar.startOfDay(for: $0.date) }
      .map { ClawConversationSection(day: $0.key, messages: $0.value.sorted { $0.date < $1.date }) }
      .sorted { $0.day < $1.day }
  }

  public static func search(_ messages: [ClawChatMessage], query: String) -> [ClawChatMessage] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return messages }
    return messages.filter { $0.content.localizedCaseInsensitiveContains(needle) }
  }
}

public final class ClawQuickPromptStore {
  private let defaults: UserDefaults
  private let key: String
  public private(set) var prompts: [String]

  public init(defaults: UserDefaults = .standard, key: String = "claw_quick_prompts_v1") {
    self.defaults = defaults
    self.key = key
    if let saved = defaults.stringArray(forKey: key) {
      prompts = saved
    } else {
      prompts = ["提醒我今天的待办", "帮我总结最近进展"]
      defaults.set(prompts, forKey: key)
    }
  }

  public func replace(_ values: [String]) {
    prompts = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    defaults.set(prompts, forKey: key)
  }

  public func move(from source: Int, to destination: Int) {
    guard prompts.indices.contains(source), destination >= 0, destination < prompts.count else { return }
    let value = prompts.remove(at: source)
    prompts.insert(value, at: destination)
    defaults.set(prompts, forKey: key)
  }
}

public enum ClawVoiceGestureOutcome: Equatable {
  case submit
  case cancel
}

public struct ClawVoiceGestureState: Equatable {
  public private(set) var isRecording = false
  public private(set) var willCancel = false

  public init() {}
  public mutating func begin() { isRecording = true; willCancel = false }
  public mutating func update(verticalTranslation: Double) { if isRecording { willCancel = verticalTranslation <= -60 } }
  public mutating func finish() -> ClawVoiceGestureOutcome {
    let outcome: ClawVoiceGestureOutcome = willCancel ? .cancel : .submit
    isRecording = false
    willCancel = false
    return outcome
  }
}
