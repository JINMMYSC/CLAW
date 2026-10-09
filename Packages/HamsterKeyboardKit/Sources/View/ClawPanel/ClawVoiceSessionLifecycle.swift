import Foundation

protocol ClawVoiceScheduledWork {
  func cancel()
}

/// Owns a recording's callbacks and terminal arbitration independently of the
/// Speech/audio graph. Production callers serialize events on the main queue.
final class ClawVoiceSessionLifecycle {
  enum Callbacks {
    case oneShot((Result<String, Error>) -> Void)
    case streaming(
      onPartial: (String) -> Void,
      onSegment: (String) -> Void,
      onError: (Error) -> Void
    )
  }

  typealias Schedule =
    (TimeInterval, @escaping () -> Void) -> ClawVoiceScheduledWork

  private enum Phase { case idle, preparing, recording, finalizing }

  private let stopTimeout: TimeInterval
  private let schedule: Schedule
  private let onTeardown: (UInt, Bool) -> Void
  private var phase = Phase.idle
  private var callbacks: Callbacks?
  private var partialText = ""
  private var watchdog: ClawVoiceScheduledWork?
  private(set) var generation: UInt = 0

  init(
    stopTimeout: TimeInterval = 6,
    schedule: @escaping Schedule,
    onTeardown: @escaping (_ generation: UInt, _ cancelTask: Bool) -> Void
  ) {
    self.stopTimeout = stopTimeout
    self.schedule = schedule
    self.onTeardown = onTeardown
  }

  var isRecording: Bool { phase == .recording }

  @discardableResult
  func begin(_ callbacks: Callbacks) -> UInt {
    cancel()
    self.callbacks = callbacks
    partialText = ""
    phase = .preparing
    return generation
  }

  @discardableResult
  func markRecording(generation: UInt) -> Bool {
    guard self.generation == generation, phase == .preparing else { return false }
    phase = .recording
    return true
  }

  func receive(generation: UInt, text: String?, isFinal: Bool, error: Error?) {
    guard self.generation == generation, let callbacks else { return }
    if let text {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { partialText = trimmed }
      if isFinal {
        finish(generation: generation, result: .success(text), cancelTask: false)
        return
      }
    }
    if let error {
      if case .oneShot = callbacks, phase == .finalizing, !partialText.isEmpty {
        finish(generation: generation, result: .success(partialText), cancelTask: false)
      } else {
        finish(generation: generation, result: .failure(error), cancelTask: false)
      }
      return
    }
    if let text, case .streaming(let onPartial, _, _) = callbacks {
      onPartial(text)
    }
  }

  @discardableResult
  func stop(generation: UInt) -> Bool {
    guard self.generation == generation, phase == .recording else { return false }
    phase = .finalizing
    watchdog = schedule(stopTimeout) { [weak self] in
      guard let self, self.generation == generation, self.phase == .finalizing else { return }
      let result: Result<String, Error> = self.partialText.isEmpty
        ? .failure(ClawVoiceError.noTranscriptAfterStop)
        : .success(self.partialText)
      // Baseline extraction intentionally retains the existing defect: the
      // stop watchdog does not deliver a streaming terminal callback.
      if case .streaming? = self.callbacks {
        self.cancel()
      } else {
        self.finish(generation: generation, result: result, cancelTask: true)
      }
    }
    return true
  }

  func cancel() {
    let oldGeneration = generation
    let hadSession = callbacks != nil
    generation &+= 1
    clear()
    if hadSession { onTeardown(oldGeneration, true) }
  }

  private func finish(generation: UInt, result: Result<String, Error>, cancelTask: Bool) {
    guard self.generation == generation, let callbacks else { return }
    self.generation &+= 1
    clear()
    onTeardown(generation, cancelTask)
    switch callbacks {
    case .oneShot(let completion): completion(result)
    case .streaming(_, let onSegment, let onError):
      switch result {
      case .success(let text): onSegment(text)
      case .failure(let error): onError(error)
      }
    }
  }

  private func clear() {
    watchdog?.cancel()
    watchdog = nil
    callbacks = nil
    partialText = ""
    phase = .idle
  }
}

