import Foundation

public struct ClawQueryPersonResolver {
  public init() {}

  public func resolve(query: String?, profiles: [HeartTargetProfile]) -> UUID? {
    guard let query else { return nil }
    let normalizedQuery = normalize(query)
    guard !normalizedQuery.isEmpty else { return nil }

    let matches = profiles.filter { profile in
      ([profile.displayName] + profile.aliases).contains { candidate in
        let normalizedCandidate = normalize(candidate)
        return !normalizedCandidate.isEmpty && normalizedQuery.contains(normalizedCandidate)
      }
    }
    return matches.count == 1 ? matches[0].id : nil
  }

  private func normalize(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .filter { !$0.isWhitespace && !$0.isPunctuation }
  }
}
