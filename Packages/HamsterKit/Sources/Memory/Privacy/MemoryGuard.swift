import Foundation

public enum MemoryGuardReason: String, Codable, Equatable {
  case allowed
  case temporaryMode
  case neverSend
  case localOnly
  case wrongPerson
  case wrongProject
  case expired
}

public struct MemoryGuardDecision: Equatable {
  public var allowed: [MemoryV2Record]
  public var rejected: [UUID: MemoryGuardReason]

  public init(allowed: [MemoryV2Record], rejected: [UUID: MemoryGuardReason]) {
    self.allowed = allowed
    self.rejected = rejected
  }
}

public struct MemoryGuard {
  public init() {}

  public func evaluate(
    _ records: [MemoryV2Record],
    personID: UUID? = nil,
    projectID: UUID? = nil,
    temporaryMode: Bool,
    now: Date = Date()
  ) -> MemoryGuardDecision {
    var allowed: [MemoryV2Record] = []
    var rejected: [UUID: MemoryGuardReason] = [:]
    for record in records {
      let reason: MemoryGuardReason?
      if temporaryMode || record.cloudPermission == .temporary { reason = .temporaryMode }
      else if record.cloudPermission == .neverSend { reason = .neverSend }
      else if record.cloudPermission == .localOnly { reason = .localOnly }
      else if let expiresAt = record.expiresAt, expiresAt <= now { reason = .expired }
      else if let scopedPerson = record.personID, scopedPerson != personID { reason = .wrongPerson }
      else if let scopedProject = record.projectID, scopedProject != projectID { reason = .wrongProject }
      else { reason = nil }

      if let reason { rejected[record.id] = reason }
      else { allowed.append(redactPII(in: record)) }
    }
    return MemoryGuardDecision(allowed: allowed, rejected: rejected)
  }

  private func redactPII(in record: MemoryV2Record) -> MemoryV2Record {
    var result = record
    let patterns = [
      ("[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", "[邮箱已隐藏]"),
      ("(?<!\\d)(?:\\+?86[- ]?)?1[3-9]\\d{9}(?!\\d)", "[手机号已隐藏]"),
    ]
    for (pattern, replacement) in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
      let range = NSRange(result.content.startIndex..., in: result.content)
      result.content = regex.stringByReplacingMatches(in: result.content, range: range, withTemplate: replacement)
    }
    return result
  }
}
