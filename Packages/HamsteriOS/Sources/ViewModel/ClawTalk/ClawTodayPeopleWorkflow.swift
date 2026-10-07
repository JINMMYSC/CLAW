import Foundation
import HamsterKit

enum ClawTodayTaskGroup: String, CaseIterable, Identifiable {
  case overdue
  case today
  case upcoming
  case unscheduled

  var id: String { rawValue }

  var title: String {
    switch self {
    case .overdue: return "已逾期"
    case .today: return "今天"
    case .upcoming: return "稍后"
    case .unscheduled: return "未安排时间"
    }
  }
}

enum ClawTodayTaskGrouping {
  static func group(
    _ tasks: [ClawSecretaryTask],
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> [ClawTodayTaskGroup: [ClawSecretaryTask]] {
    var result: [ClawTodayTaskGroup: [ClawSecretaryTask]] = Dictionary(
      uniqueKeysWithValues: ClawTodayTaskGroup.allCases.map { ($0, []) }
    )
    let startOfToday = calendar.startOfDay(for: now)
    let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now

    for task in tasks where task.status == .open {
      let group: ClawTodayTaskGroup
      if let dueAt = task.dueAt {
        if dueAt < startOfToday { group = .overdue }
        else if dueAt < startOfTomorrow { group = .today }
        else { group = .upcoming }
      } else {
        group = .unscheduled
      }
      result[group, default: []].append(task)
    }

    for group in ClawTodayTaskGroup.allCases {
      result[group]?.sort { lhs, rhs in
        switch (lhs.dueAt, rhs.dueAt) {
        case let (left?, right?) where left != right: return left < right
        case (_?, nil): return true
        case (nil, _?): return false
        default: return lhs.createdAt > rhs.createdAt
        }
      }
    }
    return result
  }
}

enum ClawReminderStrategy: String, CaseIterable, Identifiable {
  case proactive
  case dueOnly
  case silent

  var id: String { rawValue }

  var title: String {
    switch self {
    case .proactive: return "智能提醒"
    case .dueOnly: return "仅截止提醒"
    case .silent: return "只在 App 内显示"
    }
  }
}

enum ClawPeopleFilter: String, CaseIterable, Identifiable {
  case all
  case people
  case groups
  case unconfirmed

  var id: String { rawValue }

  var title: String {
    switch self {
    case .all: return "全部"
    case .people: return "联系人"
    case .groups: return "群聊"
    case .unconfirmed: return "待确认"
    }
  }
}

enum ClawPeoplePresentation {
  static func filtered(
    _ profiles: [HeartTargetProfile],
    query: String,
    filter: ClawPeopleFilter
  ) -> [HeartTargetProfile] {
    let normalizedQuery = normalize(query)
    return profiles
      .filter { profile in
        switch filter {
        case .all: return true
        case .people: return !profile.isGroup
        case .groups: return profile.isGroup
        case .unconfirmed: return profile.autoCreated
        }
      }
      .filter { profile in
        guard !normalizedQuery.isEmpty else { return true }
        let values = [profile.displayName, profile.relationship] + profile.aliases
        return values.contains { value in
          let normalized = normalize(value)
          let (pinyin, initials) = pinyinForms(value)
          return normalized.contains(normalizedQuery)
            || pinyin.contains(normalizedQuery)
            || initials.contains(normalizedQuery)
        }
      }
      .sorted { lhs, rhs in
        let left = lhs.lastSeenAt ?? .distantPast
        let right = rhs.lastSeenAt ?? .distantPast
        if left != right { return left > right }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
      }
  }

  private static func normalize(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: " ", with: "")
  }

  private static func pinyinForms(_ text: String) -> (full: String, initials: String) {
    guard let latin = text.applyingTransform(.toLatin, reverse: false)?
      .applyingTransform(.stripDiacritics, reverse: false)
      .lowercased()
    else { return ("", "") }
    let parts = latin.split(whereSeparator: { $0.isWhitespace || $0 == "-" })
    return (
      parts.joined(),
      parts.compactMap { $0.first }.map { String($0) }.joined()
    )
  }
}
