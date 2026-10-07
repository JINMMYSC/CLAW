import Foundation
import HamsterKit

enum ClawMemoryFilter {
  static func apply(
    _ items: [ClawMemoryItem],
    query: String = "",
    personID: UUID? = nil,
    sourceType: String? = nil,
    kind: ClawMemoryKind? = nil,
    scope: String? = nil,
    protectedIDs: Set<UUID> = [],
    includeProtectedContent: Bool = false
  ) -> [ClawMemoryItem] {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

    return items.filter { item in
      if let personID, item.subjectID != personID { return false }
      if let sourceType, item.sourceType != sourceType { return false }
      if let kind, item.kind != kind { return false }
      if let scope, item.scope != scope { return false }

      guard !normalizedQuery.isEmpty else { return true }
      if protectedIDs.contains(item.id), !includeProtectedContent { return false }
      return item.content.localizedCaseInsensitiveContains(normalizedQuery)
        || (item.sourceRef?.localizedCaseInsensitiveContains(normalizedQuery) ?? false)
        || item.sourceType.localizedCaseInsensitiveContains(normalizedQuery)
        || item.kind.rawValue.localizedCaseInsensitiveContains(normalizedQuery)
    }
  }
}
