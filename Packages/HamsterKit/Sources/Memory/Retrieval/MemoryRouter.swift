import Foundation

/// Scope-safe hybrid retrieval entry point. All callers get the same guard,
/// ranking and de-duplication rules instead of querying the store directly.
public final class MemoryRouter {
  private let store: ClawMemoryStore

  public init(store: ClawMemoryStore = .shared) {
    self.store = store
  }

  public func recall(
    _ request: MemoryRecallRequest,
    cloudEligibleOnly: Bool = false,
    now: Date = Date()
  ) throws -> [MemoryV2Record] {
    let candidates = try store.searchContextMemoryV2(
      request, limit: max(80, request.limit * 8),
      cloudEligibleOnly: cloudEligibleOnly, now: now
    )
    // Defense in depth: the SQL predicate owns the candidate budget, while
    // this guard continues enforcing the same request scope after decoding.
      .filter { $0.state == .active || $0.state == .confirmed }
      .filter { isVisible($0, for: request, now: now) }

    var seen = Set<String>()
    let ranked = candidates.sorted {
      score($0, query: request.query, now: now) > score($1, query: request.query, now: now)
    }
    let deduplicated = ranked.filter { record in
      let key = record.normalizedKey?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ?? record.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      return seen.insert(key).inserted
    }
    return diversify(deduplicated, query: request.query, limit: max(1, request.limit), now: now)
  }

  private func isVisible(_ record: MemoryV2Record, for request: MemoryRecallRequest, now: Date) -> Bool {
    if let expiresAt = record.expiresAt, expiresAt <= now { return false }
    if record.scope == .global && (record.personID != nil || record.projectID != nil) { return false }
    if let recordPerson = record.personID, recordPerson != request.personID { return false }
    if let recordProject = record.projectID, recordProject != request.projectID { return false }
    if let projectID = request.projectID,
       record.scope == .project,
       record.projectID != projectID { return false }

    switch request.scope {
    case .global:
      return record.scope == .global
    case .person, .relationship:
      if record.scope == .global { return true }
      guard let personID = request.personID else { return false }
      return (record.scope == .person || record.scope == .relationship) && record.personID == personID
    case .project:
      if record.scope == .global { return true }
      return record.scope == .project && record.projectID == request.projectID
    case .session:
      return record.scope == .global || record.scope == .session
    default:
      return record.scope == .global || record.scope == request.scope
    }
  }

  private func score(_ record: MemoryV2Record, query: String, now: Date) -> Double {
    let terms = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
    let text = (record.content + " " + (record.normalizedKey ?? "")).lowercased()
    let lexical = terms.isEmpty ? 0 : Double(terms.filter { text.contains($0) }.count) / Double(terms.count)
    let recency = Self.recencyFactor(updatedAt: record.updatedAt, now: now)
    return lexical * 4 + record.importance + record.confidence
      + Double(record.provenance.trustLevel) / 100 + recency * 0.25
  }

  /// Fixed-clock recency is deterministic and capped: device clock skew or
  /// future-dated imports must not receive unlimited ranking bonuses.
  static func recencyFactor(updatedAt: Date, now: Date) -> Double {
    min(1, max(0, 1 - now.timeIntervalSince(updatedAt) / (180 * 86_400)))
  }

  /// Bounded maximal-marginal-relevance selection. Character shingles make
  /// this language agnostic and prevent near-duplicate facts from consuming
  /// the entire context budget.
  private func diversify(_ records: [MemoryV2Record], query: String, limit: Int, now: Date) -> [MemoryV2Record] {
    var remaining = Array(records.prefix(max(limit * 4, limit)))
    var selected: [MemoryV2Record] = []
    while !remaining.isEmpty && selected.count < limit {
      let bestIndex = remaining.indices.max { left, right in
        mmr(remaining[left], selected: selected, query: query, now: now) <
          mmr(remaining[right], selected: selected, query: query, now: now)
      }!
      selected.append(remaining.remove(at: bestIndex))
    }
    return selected
  }

  private func mmr(_ record: MemoryV2Record, selected: [MemoryV2Record], query: String, now: Date) -> Double {
    let relevance = score(record, query: query, now: now)
    let redundancy = selected.map { similarity(record.content, $0.content) }.max() ?? 0
    return relevance * 0.78 - redundancy * 0.22
  }

  private func similarity(_ lhs: String, _ rhs: String) -> Double {
    func shingles(_ text: String) -> Set<String> {
      let characters = Array(text.lowercased().filter { !$0.isWhitespace })
      if characters.count < 2 { return Set([String(characters)]) }
      return Set((0..<(characters.count - 1)).map { String(characters[$0...($0 + 1)]) })
    }
    let a = shingles(lhs), b = shingles(rhs)
    let union = a.union(b).count
    return union == 0 ? 0 : Double(a.intersection(b).count) / Double(union)
  }
}
