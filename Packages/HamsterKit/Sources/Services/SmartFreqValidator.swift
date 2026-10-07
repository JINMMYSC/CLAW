import Foundation
import Yams

public struct SmartFreqDraft: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case frequency
    case newPhrase
  }

  public let kind: Kind
  public let action: String?
  public let code: String
  public let word: String
  public let observedCount: Int

  public init(kind: Kind, action: String? = nil, code: String, word: String, observedCount: Int) {
    self.kind = kind
    self.action = action
    self.code = code
    self.word = word
    self.observedCount = observedCount
  }
}

public struct SmartFreqAcceptedPhrase: Codable, Equatable, Sendable {
  public let code: String
  public let word: String
  public let weight: Int

  public init(code: String, word: String, weight: Int) {
    self.code = code
    self.word = word
    self.weight = weight
  }

  /// RIME `tabledb` format is phrase, code, weight (in that order).
  public var rimeLine: String { "\(word)\t\(code)\t\(weight)" }
}

public enum SmartFreqValidationReason: String, Codable, Hashable, Sendable {
  case illegalTerm
  case notObserved
  case insufficientEvidence
  case pinyinMismatch
  case duplicate
  case conflict
  case budgetExceeded
}

public struct SmartFreqReviewedDraft: Codable, Equatable, Sendable {
  public let draft: SmartFreqDraft
  public let reason: SmartFreqValidationReason

  public init(draft: SmartFreqDraft, reason: SmartFreqValidationReason) {
    self.draft = draft
    self.reason = reason
  }
}

public struct SmartFreqValidationReport: Codable, Equatable, Sendable {
  public var accepted: [SmartFreqAcceptedPhrase]
  public var pending: [SmartFreqReviewedDraft]
  public var rejected: [SmartFreqReviewedDraft]

  public init(
    accepted: [SmartFreqAcceptedPhrase] = [],
    pending: [SmartFreqReviewedDraft] = [],
    rejected: [SmartFreqReviewedDraft] = []
  ) {
    self.accepted = accepted
    self.pending = pending
    self.rejected = rejected
  }
}

/// Deterministic gate between untrusted model output and RIME's custom phrase table.
public struct SmartFreqValidator: Sendable {
  private static let knownPolyphones: [String: String] = [
    "重庆": "chongqing",
    "重启": "chongqi",
    "长安": "changan",
    "音乐": "yinyue",
    "银行": "yinhang",
    "行程": "xingcheng",
  ]

  public init() {}

  public func validate(
    _ drafts: [SmartFreqDraft],
    existing: [SmartFreqAcceptedPhrase],
    acceptanceBudget: Int = 50
  ) -> SmartFreqValidationReport {
    var report = SmartFreqValidationReport()
    var knownPairs = Set(existing.map { pairKey(code: $0.code, word: $0.word) })
    var codeToWords = Dictionary(grouping: existing, by: { normalizedCode($0.code) })
      .mapValues { Set($0.map { $0.word }) }
    var wordToCodes = Dictionary(grouping: existing, by: \.word)
      .mapValues { Set($0.map { normalizedCode($0.code) }) }

    let ordered = drafts.enumerated().sorted {
      if $0.element.observedCount != $1.element.observedCount {
        return $0.element.observedCount > $1.element.observedCount
      }
      return $0.offset < $1.offset
    }.map(\.element)

    for draft in ordered {
      let code = normalizedCode(draft.code)
      let word = draft.word.trimmingCharacters(in: .whitespacesAndNewlines)
      let normalized = SmartFreqDraft(
        kind: draft.kind,
        action: draft.action?.lowercased(),
        code: code,
        word: word,
        observedCount: draft.observedCount
      )

      guard isLegal(word: word, code: code) else {
        report.rejected.append(.init(draft: normalized, reason: .illegalTerm))
        continue
      }
      guard draft.observedCount > 0 else {
        report.rejected.append(.init(draft: normalized, reason: .notObserved))
        continue
      }
      let key = pairKey(code: code, word: word)
      guard !knownPairs.contains(key) else {
        report.rejected.append(.init(draft: normalized, reason: .duplicate))
        continue
      }
      if codeToWords[code]?.contains(where: { $0 != word }) == true
        || wordToCodes[word]?.contains(where: { $0 != code }) == true {
        report.pending.append(.init(draft: normalized, reason: .conflict))
        continue
      }
      guard draft.observedCount >= 2 else {
        report.pending.append(.init(draft: normalized, reason: .insufficientEvidence))
        continue
      }
      guard deterministicPinyin(for: word) == code else {
        report.pending.append(.init(draft: normalized, reason: .pinyinMismatch))
        continue
      }
      guard report.accepted.count < max(0, acceptanceBudget) else {
        report.pending.append(.init(draft: normalized, reason: .budgetExceeded))
        continue
      }

      let weight = normalized.action == "demote" ? 1 : 100
      report.accepted.append(.init(code: code, word: word, weight: weight))
      knownPairs.insert(key)
      codeToWords[code, default: []].insert(word)
      wordToCodes[word, default: []].insert(code)
    }
    return report
  }

  public func deterministicPinyin(for word: String) -> String {
    if let known = Self.knownPolyphones[word] { return known }
    let latin = word.applyingTransform(.mandarinToLatin, reverse: false) ?? word
    let stripped = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
    return stripped.lowercased().unicodeScalars
      .filter { CharacterSet.lowercaseLetters.contains($0) }
      .map(String.init)
      .joined()
  }

  /// Merges the managed translator into an existing `<schema>.custom.yaml`.
  public static func schemaPatchYAML(existing: String?) throws -> String {
    var root = ((try existing.flatMap { try Yams.load(yaml: $0) }) as? [String: Any]) ?? [:]
    var patch = root["patch"] as? [String: Any] ?? [:]
    var translators = patch["engine/translators/+"] as? [String] ?? []
    let translator = "table_translator@claw_smart_freq"
    if !translators.contains(translator) { translators.append(translator) }
    patch["engine/translators/+"] = translators
    patch["claw_smart_freq"] = [
      "dictionary": "",
      "user_dict": "claw_smart_freq",
      "db_class": "stabledb",
      "enable_completion": false,
      "enable_sentence": false,
      "initial_quality": 1,
    ] as [String: Any]
    root["patch"] = patch
    return try Yams.dump(object: root, sortKeys: true)
  }

  private func normalizedCode(_ code: String) -> String {
    code.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func pairKey(code: String, word: String) -> String { "\(normalizedCode(code))\u{1f}\(word)" }

  private func isLegal(word: String, code: String) -> Bool {
    guard (1 ... 16).contains(word.count), !word.contains("\t"), !word.contains("\n"), !word.contains("\r") else {
      return false
    }
    guard !code.isEmpty, code.allSatisfy({ $0.isASCII && ($0.isLowercase || $0 == "'") }) else {
      return false
    }
    return word.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
  }
}
