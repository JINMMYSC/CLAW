import Foundation

public enum ClawResetMode: Equatable {
  case inputLearningOnly
  case full
}

public enum ClawResetStep: String, Equatable {
  case stopRime
  case clearApplicationData
  case clearInputLearning
  case resetConfiguration
  case redeployRime

  public var displayName: String {
    switch self {
    case .stopRime: return "停止输入法引擎"
    case .clearApplicationData: return "清除 CLAW 数据"
    case .clearInputLearning: return "清除输入法学习"
    case .resetConfiguration: return "恢复默认设置"
    case .redeployRime: return "重新部署输入法"
    }
  }
}

public struct ClawResetStepResult: Equatable {
  public let step: ClawResetStep
  public let succeeded: Bool
  public let errorDescription: String?

  public init(step: ClawResetStep, succeeded: Bool, errorDescription: String? = nil) {
    self.step = step
    self.succeeded = succeeded
    self.errorDescription = errorDescription
  }
}

public struct ClawResetReport: Equatable {
  public let mode: ClawResetMode
  public let results: [ClawResetStepResult]

  public var succeeded: Bool { results.allSatisfy(\.succeeded) }

  public var userMessage: String {
    guard !succeeded else {
      return mode == .full ? "App 已重置。API Key 和输入方案文件已保留。" : "输入法学习已重置。"
    }
    let failures = results
      .filter { !$0.succeeded }
      .map { "\($0.step.displayName)：\($0.errorDescription ?? "未知错误")" }
      .joined(separator: "\n")
    let completed = results.filter(\.succeeded).map { $0.step.displayName }.joined(separator: "、")
    return "重置只完成了一部分。\n已完成：\(completed.isEmpty ? "无" : completed)\n失败：\n\(failures)"
  }

  public init(mode: ClawResetMode, results: [ClawResetStepResult]) {
    self.mode = mode
    self.results = results
  }
}

/// Runs reset operations in a fixed, observable order. Each operation is isolated so a
/// failure is reported without hiding which later cleanup steps did or did not run.
public final class ClawResetService {
  public struct Actions {
    public var stopRime: () throws -> Void
    public var clearApplicationData: () throws -> Void
    public var clearInputLearning: () throws -> Void
    public var resetConfiguration: () throws -> Void
    public var redeployRime: () throws -> Void

    public init(
      stopRime: @escaping () throws -> Void,
      clearApplicationData: @escaping () throws -> Void,
      clearInputLearning: @escaping () throws -> Void,
      resetConfiguration: @escaping () throws -> Void,
      redeployRime: @escaping () throws -> Void
    ) {
      self.stopRime = stopRime
      self.clearApplicationData = clearApplicationData
      self.clearInputLearning = clearInputLearning
      self.resetConfiguration = resetConfiguration
      self.redeployRime = redeployRime
    }
  }

  private let actions: Actions

  public init(actions: Actions) {
    self.actions = actions
  }

  /// Removes RIME's learned databases without deleting schema, dictionary, or YAML files.
  public static func removeInputLearningFiles(
    in roots: [URL],
    fileManager: FileManager = .default
  ) throws {
    for root in roots where fileManager.fileExists(atPath: root.path) {
      guard let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      ) else { continue }
      var learnedURLs: [URL] = []
      for case let url as URL in enumerator {
        let name = url.lastPathComponent.lowercased()
        if name.contains(".userdb") {
          learnedURLs.append(url)
          enumerator.skipDescendants()
        }
      }
      for url in learnedURLs.sorted(by: { $0.path.count > $1.path.count }) {
        try fileManager.removeItem(at: url)
      }
    }
  }

  public func perform(_ mode: ClawResetMode) -> ClawResetReport {
    let operations: [(ClawResetStep, () throws -> Void)]
    switch mode {
    case .inputLearningOnly:
      operations = [
        (.stopRime, actions.stopRime),
        (.clearInputLearning, actions.clearInputLearning),
        (.redeployRime, actions.redeployRime),
      ]
    case .full:
      operations = [
        (.stopRime, actions.stopRime),
        (.clearApplicationData, actions.clearApplicationData),
        (.clearInputLearning, actions.clearInputLearning),
        (.resetConfiguration, actions.resetConfiguration),
        (.redeployRime, actions.redeployRime),
      ]
    }

    let results = operations.map { step, operation in
      do {
        try operation()
        return ClawResetStepResult(step: step, succeeded: true)
      } catch {
        return ClawResetStepResult(
          step: step,
          succeeded: false,
          errorDescription: error.localizedDescription
        )
      }
    }
    return ClawResetReport(mode: mode, results: results)
  }
}
