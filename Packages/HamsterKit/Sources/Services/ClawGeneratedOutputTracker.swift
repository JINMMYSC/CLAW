import Foundation

public struct ClawPendingGeneratedOutput: Codable, Equatable {
  public var skillID: String
  public var contactID: UUID?
  public var sourceText: String?
  public var generatedText: String
  public var style: String?
  public var experimentVariantID: String?
  public var insertedAt: Date
}

/// Bridges "AI candidate inserted" with the keyboard session's eventual final text.
/// This lets Evolution learn edits instead of only learning which candidate was tapped.
public final class ClawGeneratedOutputTracker {
  public static let shared = ClawGeneratedOutputTracker()

  private let defaults = UserDefaults(suiteName: HamsterConstants.appGroupName)
  private let key = "claw_pending_generated_output_v1"

  public func markInserted(
    skillID: String,
    contactID: UUID?,
    sourceText: String?,
    generatedText: String,
    style: String? = nil,
    experimentVariantID: String? = nil
  ) {
    let pending = ClawPendingGeneratedOutput(
      skillID: skillID,
      contactID: contactID,
      sourceText: sourceText,
      generatedText: generatedText,
      style: style,
      experimentVariantID: experimentVariantID,
      insertedAt: Date()
    )
    defaults?.set(try? JSONEncoder().encode(pending), forKey: key)
  }

  public func clear() {
    defaults?.removeObject(forKey: key)
  }

  @discardableResult
  public func reconcile(finalSessionText: String, now: Date = Date()) -> Bool {
    guard let data = defaults?.data(forKey: key),
          let pending = try? JSONDecoder().decode(ClawPendingGeneratedOutput.self, from: data)
    else { return false }
    defer { clear() }
    guard now.timeIntervalSince(pending.insertedAt) < 30 * 60 else { return false }
    let final = finalSessionText.trimmingCharacters(in: .whitespacesAndNewlines)
    let generated = pending.generatedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !final.isEmpty, !generated.isEmpty else { return false }
    if final == generated || final.contains(generated) { return false }
    guard isLikelyEdit(of: generated, final: final) else { return false }

    try? ClawMemoryStore.shared.recordFeedback(ClawEvolutionFeedback(
      skillID: pending.skillID,
      contactID: pending.contactID,
      action: .edited,
      originalText: generated,
      finalText: final
    ))
    ClawSkillRuntime.shared.recordExperimentFeedback(
      skillID: pending.skillID,
      variantID: pending.experimentVariantID,
      action: .edited
    )
    _ = ClawEvolutionEngine.shared.evolveIfNeeded(skillID: pending.skillID)
    return true
  }

  private func isLikelyEdit(of generated: String, final: String) -> Bool {
    let g = Array(generated)
    let f = Array(final)
    let ratio = Double(f.count) / Double(max(g.count, 1))
    guard ratio > 0.35, ratio < 2.3 else { return false }
    let commonPrefix = zip(g, f).prefix(while: { pair in pair.0 == pair.1 }).count
    let commonSuffix = zip(g.reversed(), f.reversed()).prefix(while: { pair in pair.0 == pair.1 }).count
    let shared = commonPrefix + commonSuffix
    if shared >= min(6, g.count / 3) { return true }
    let gTokens = Set(generated.filter { !$0.isWhitespace }.map(String.init))
    let fTokens = Set(final.filter { !$0.isWhitespace }.map(String.init))
    let union = gTokens.union(fTokens)
    guard !union.isEmpty else { return false }
    let overlap = Double(gTokens.intersection(fTokens).count) / Double(union.count)
    return overlap >= 0.45
  }
}

