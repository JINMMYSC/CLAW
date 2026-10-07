#if canImport(ActivityKit)
import ActivityKit
import Foundation
import HamsterKit

@available(iOS 16.1, *)
public final class ClawLiveActivityManager {
  public static let shared = ClawLiveActivityManager()
  private var activity: Activity<ClawLiveActivityAttributes>?

  public func start(kind: String, detail: String) async {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    let state = ClawLiveActivityAttributes.ContentState(phase: "active", detail: detail)
    activity = try? Activity.request(attributes: .init(kind: kind), contentState: state, pushType: nil)
  }
  public func update(phase: String, elapsedSeconds: Int, detail: String) async {
    await activity?.update(using: .init(phase: phase, elapsedSeconds: elapsedSeconds, detail: detail))
  }
  public func end(detail: String) async {
    await activity?.end(using: .init(phase: "complete", detail: detail), dismissalPolicy: .default)
    activity = nil
  }
}
#endif
