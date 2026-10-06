import Foundation
import UserNotifications

public enum ClawSecretaryUrgency: Int, Codable, Comparable {
  case low = 0
  case normal = 1
  case high = 2
  case critical = 3

  public static func < (lhs: ClawSecretaryUrgency, rhs: ClawSecretaryUrgency) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public struct ClawSecretarySuggestion: Identifiable, Equatable {
  public var id: String
  public var taskID: UUID
  public var urgency: ClawSecretaryUrgency
  public var title: String
  public var detail: String
  public var dueAt: Date?
  public var contactID: UUID?
}

/// Converts structured commitments/waiting items into a calm proactive secretary feed.
public final class ClawProactiveSecretaryService {
  public static let shared = ClawProactiveSecretaryService()
  private let store: ClawMemoryStore

  public init(store: ClawMemoryStore = .shared) {
    self.store = store
  }

  public func suggestions(now: Date = Date()) -> [ClawSecretarySuggestion] {
    let tasks = (try? store.tasks(status: .open, limit: 500)) ?? []
    return tasks.compactMap { task in
      let age = now.timeIntervalSince(task.createdAt)
      if let due = task.dueAt {
        let delta = due.timeIntervalSince(now)
        if delta < 0 {
          return suggestion(task, urgency: delta < -24 * 3600 ? .critical : .high, detail: "已经到期，建议现在处理或重新安排。")
        }
        if delta <= 24 * 3600 {
          return suggestion(task, urgency: delta <= 3 * 3600 ? .high : .normal, detail: "即将到期，今天需要关注。")
        }
      }
      if task.kind == .waitingFor, age >= 48 * 3600 {
        return suggestion(task, urgency: .normal, detail: "已经等待超过两天，可以考虑跟进。")
      }
      if task.kind == .commitment, task.dueAt == nil, age >= 24 * 3600 {
        return suggestion(task, urgency: .low, detail: "这是你做过的承诺，尚未看到完成记录。")
      }
      return nil
    }
    .sorted {
      if $0.urgency != $1.urgency { return $0.urgency > $1.urgency }
      return ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture)
    }
  }

  @discardableResult
  public func complete(taskID: UUID) -> Bool {
    (try? store.setTaskStatus(id: taskID, status: .done)) ?? false
  }

  @discardableResult
  public func snooze(taskID: UUID, hours: Int = 24, now: Date = Date()) -> Bool {
    let date = now.addingTimeInterval(TimeInterval(max(1, hours)) * 3600)
    return (try? store.snoozeTask(id: taskID, until: date)) ?? false
  }

  /// Schedules only high-value reminders. Low-priority suggestions stay inside the Today feed.
  public func refreshLocalNotifications(now: Date = Date()) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
      center.getPendingNotificationRequests { existing in
        let ids = existing.map(\.identifier).filter { $0.hasPrefix("claw-secretary-") }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        for suggestion in self.suggestions(now: now).filter({ $0.urgency >= .high }).prefix(5) {
          let content = UNMutableNotificationContent()
          content.title = suggestion.urgency == .critical ? "CLAW：有事项已经逾期" : "CLAW：有事项需要关注"
          content.body = suggestion.title
          content.sound = .default
          let fire: Date
          if let due = suggestion.dueAt, due > now {
            fire = max(now.addingTimeInterval(60), due.addingTimeInterval(-30 * 60))
          } else {
            fire = now.addingTimeInterval(90)
          }
          let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(60, fire.timeIntervalSince(now)), repeats: false)
          center.add(UNNotificationRequest(identifier: "claw-secretary-\(suggestion.taskID.uuidString)", content: content, trigger: trigger))
        }
      }
    }
  }

  private func suggestion(_ task: ClawSecretaryTask, urgency: ClawSecretaryUrgency, detail: String) -> ClawSecretarySuggestion {
    ClawSecretarySuggestion(
      id: "task-\(task.id.uuidString)",
      taskID: task.id,
      urgency: urgency,
      title: task.title,
      detail: detail,
      dueAt: task.dueAt,
      contactID: task.contactID
    )
  }
}

