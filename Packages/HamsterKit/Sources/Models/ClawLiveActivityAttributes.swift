#if canImport(ActivityKit)
import ActivityKit
import Foundation

@available(iOS 16.1, *)
public struct ClawLiveActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    public var phase: String
    public var elapsedSeconds: Int
    public var detail: String
    public init(phase: String, elapsedSeconds: Int = 0, detail: String = "") {
      self.phase = phase; self.elapsedSeconds = elapsedSeconds; self.detail = detail
    }
  }
  public var kind: String
  public init(kind: String) { self.kind = kind }
}
#endif
