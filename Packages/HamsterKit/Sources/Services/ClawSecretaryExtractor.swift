import Foundation

/// Conservative local extractor for explicit commitments / waiting-for / deadlines.
/// It intentionally skips vague chat instead of inventing tasks.
public final class ClawSecretaryExtractor {
  public static let shared = ClawSecretaryExtractor()

  public init() {}

  public func extractTasks(from message: ClawConversationMessage, now: Date = Date()) -> [ClawSecretaryTask] {
    let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.count >= 2 else { return [] }

    let actionWords = ["发", "发送", "给", "联系", "回复", "处理", "提交", "交", "付款", "付", "确认", "打电话", "告诉", "安排", "完成"]
    let explicitTime = containsExplicitTime(text)
    let hasAction = actionWords.contains { text.contains($0) }
    var result: [ClawSecretaryTask] = []

    if text.contains("等") && (text.contains("回复") || text.contains("消息") || text.contains("结果") || text.contains("通知")) {
      result.append(ClawSecretaryTask(
        kind: .waitingFor,
        title: concise(text),
        contactID: message.contactID,
        dueAt: dueDate(in: text, now: now),
        sourceType: message.sourceType,
        sourceRef: message.sourceRef ?? message.id.uuidString
      ))
    }

    if explicitTime && hasAction {
      let kind: ClawTaskKind = message.speaker == .me ? .commitment : .nextAction
      result.append(ClawSecretaryTask(
        kind: kind,
        title: concise(text),
        contactID: message.contactID,
        dueAt: dueDate(in: text, now: now),
        sourceType: message.sourceType,
        sourceRef: message.sourceRef ?? message.id.uuidString
      ))
    }

    return deduplicate(result)
  }

  public func persistExtractedTasks(from message: ClawConversationMessage, store: ClawMemoryStore = .shared) {
    let existing = (try? store.tasks(status: .open, limit: 500)) ?? []
    for task in extractTasks(from: message) {
      let duplicate = existing.contains {
        $0.title == task.title && $0.contactID == task.contactID && $0.kind == task.kind
      }
      if !duplicate { try? DefaultMemorySDK(store: store).createTask(task) }
    }
  }

  private func containsExplicitTime(_ text: String) -> Bool {
    let markers = ["今天", "明天", "后天", "今晚", "上午", "下午", "晚上", "周一", "周二", "周三", "周四", "周五", "周六", "周日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期天", "月底", "月初"]
    if markers.contains(where: text.contains) { return true }
    return text.range(of: #"\d{1,2}[月/-]\d{1,2}|\d{1,2}:\d{2}"#, options: .regularExpression) != nil
  }

  private func dueDate(in text: String, now: Date) -> Date? {
    let calendar = Calendar.current
    if text.contains("今天") || text.contains("今晚") {
      return calendar.date(bySettingHour: text.contains("晚上") || text.contains("今晚") ? 20 : 18, minute: 0, second: 0, of: now)
    }
    if text.contains("明天") {
      let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
      return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: tomorrow)
    }
    if text.contains("后天") {
      let day = calendar.date(byAdding: .day, value: 2, to: now) ?? now
      return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day)
    }
    if text.contains("月底") {
      guard let interval = calendar.dateInterval(of: .month, for: now) else { return nil }
      return calendar.date(byAdding: .second, value: -1, to: interval.end)
    }
    let weekdays: [(String, Int)] = [
      ("周一", 2), ("星期一", 2), ("周二", 3), ("星期二", 3), ("周三", 4), ("星期三", 4),
      ("周四", 5), ("星期四", 5), ("周五", 6), ("星期五", 6), ("周六", 7), ("星期六", 7),
      ("周日", 1), ("星期天", 1),
    ]
    if let match = weekdays.first(where: { text.contains($0.0) }) {
      let current = calendar.component(.weekday, from: now)
      var delta = (match.1 - current + 7) % 7
      if delta == 0 { delta = 7 }
      let day = calendar.date(byAdding: .day, value: delta, to: now) ?? now
      return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day)
    }
    return nil
  }

  private func concise(_ text: String) -> String {
    let flattened = text.replacingOccurrences(of: "\n", with: " ")
    return flattened.count > 80 ? String(flattened.prefix(80)) + "…" : flattened
  }

  private func deduplicate(_ tasks: [ClawSecretaryTask]) -> [ClawSecretaryTask] {
    var seen = Set<String>()
    return tasks.filter { task in
      let key = "\(task.kind.rawValue)|\(task.title)"
      return seen.insert(key).inserted
    }
  }
}
