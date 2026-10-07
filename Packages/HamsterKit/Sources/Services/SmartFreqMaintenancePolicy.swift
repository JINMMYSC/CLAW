import Foundation

public struct SmartFreqPhraseObservation: Codable, Equatable, Sendable {
  public var phrase: SmartFreqAcceptedPhrase
  public var lastObservedAt: Date
  public var observationCount: Int
  public var isPinned: Bool

  public init(
    phrase: SmartFreqAcceptedPhrase,
    lastObservedAt: Date,
    observationCount: Int,
    isPinned: Bool = false
  ) {
    self.phrase = phrase
    self.lastObservedAt = lastObservedAt
    self.observationCount = observationCount
    self.isPinned = isPinned
  }
}

/// Pure policy shared by foreground runs and BGProcessingTask handlers.
public struct SmartFreqMaintenancePolicy: Sendable {
  public var staleAfter: TimeInterval
  public var minimumObservations: Int

  public init(staleAfter: TimeInterval = 90 * 24 * 60 * 60, minimumObservations: Int = 2) {
    self.staleAfter = staleAfter
    self.minimumObservations = minimumObservations
  }

  public func shouldSchedule(isEnabled: Bool, isLowPowerMode: Bool, hasExternalPower: Bool) -> Bool {
    isEnabled && !isLowPowerMode && hasExternalPower
  }

  public func retained(
    _ observations: [SmartFreqPhraseObservation],
    now: Date,
    budget: Int
  ) -> [SmartFreqPhraseObservation] {
    let cutoff = now.addingTimeInterval(-staleAfter)
    return observations
      .filter { $0.isPinned || ($0.observationCount >= minimumObservations && $0.lastObservedAt >= cutoff) }
      .sorted {
        if $0.isPinned != $1.isPinned { return $0.isPinned }
        if $0.lastObservedAt != $1.lastObservedAt { return $0.lastObservedAt > $1.lastObservedAt }
        return $0.phrase.word < $1.phrase.word
      }
      .prefix(max(0, budget))
      .map { $0 }
  }
}
