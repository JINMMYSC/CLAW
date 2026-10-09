import Foundation
@testable import HamsterKeyboardKit

final class ClawVoiceManualScheduler {
  final class Job: ClawVoiceScheduledWork {
    let deadline: TimeInterval
    let action: () -> Void
    private(set) var cancelled = false
    var executed = false

    init(deadline: TimeInterval, action: @escaping () -> Void) {
      self.deadline = deadline
      self.action = action
    }

    func cancel() { cancelled = true }
  }

  private var now: TimeInterval = 0
  private(set) var jobs: [Job] = []

  func schedule(after interval: TimeInterval, action: @escaping () -> Void) -> ClawVoiceScheduledWork {
    let job = Job(deadline: now + interval, action: action)
    jobs.append(job)
    return job
  }

  func advance(by interval: TimeInterval) {
    now += interval
    let due = jobs.filter { !$0.executed && !$0.cancelled && $0.deadline <= now }
    for job in due {
      job.executed = true
      job.action()
    }
  }

  /// Cancellation cannot retract work which has already begun executing.
  func executeEvenIfCancelled(_ job: Job) {
    job.executed = true
    job.action()
  }
}

