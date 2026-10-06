import Foundation

extension Notification.Name {
  public static let clawMemoryPolicyDidChange = Notification.Name("clawMemoryPolicyDidChange")
}

public enum ClawMemoryProvenanceClass: String, Codable, CaseIterable {
  case explicit
  case observed
  case inferred
  case imported

  public var displayName: String {
    switch self {
    case .explicit: return "明确记录"
    case .observed: return "行为观察"
    case .inferred: return "AI 推断"
    case .imported: return "外部导入"
    }
  }
}

/// Controls which long-term sources may participate in AI retrieval.
/// Collection privacy and retrieval privacy remain separate controls.
public final class ClawMemoryPolicyService {
  public static let shared = ClawMemoryPolicyService()

  private let defaults = UserDefaults(suiteName: HamsterConstants.appGroupName)
  private let pausedSourcesKey = "claw_memory_paused_sources_v1"
  private let temporaryModeKey = "claw_memory_temporary_mode_v1"

  public var temporaryMode: Bool {
    get { defaults?.bool(forKey: temporaryModeKey) ?? false }
    set {
      defaults?.set(newValue, forKey: temporaryModeKey)
      notify()
    }
  }

  public var pausedSources: Set<String> {
    Set(defaults?.stringArray(forKey: pausedSourcesKey) ?? [])
  }

  public func isSourceEnabled(_ sourceType: String) -> Bool {
    !pausedSources.contains(sourceType)
  }

  public func setSource(_ sourceType: String, enabled: Bool) {
    var sources = pausedSources
    if enabled { sources.remove(sourceType) }
    else { sources.insert(sourceType) }
    defaults?.set(Array(sources).sorted(), forKey: pausedSourcesKey)
    notify()
  }

  public func provenance(for item: ClawMemoryItem) -> ClawMemoryProvenanceClass {
    let source = item.sourceType.lowercased()
    if source.contains("import") { return .imported }
    if source.contains("evolution") || source.contains("learner") || source.contains("insight") { return .inferred }
    if source.contains("screenshot") || source.contains("keyboard") || source.contains("clawtalk") || source.contains("conversation") {
      return .observed
    }
    return .explicit
  }

  private func notify() {
    NotificationCenter.default.post(name: .clawMemoryPolicyDidChange, object: nil)
  }
}

