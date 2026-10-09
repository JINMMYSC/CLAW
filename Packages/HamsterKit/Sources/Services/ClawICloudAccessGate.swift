import Foundation

public enum ClawICloudAccessError: Error, LocalizedError, Equatable {
  case missingSigningCapability
  case unknownSigningCapability
  case containerUnavailable

  public var errorDescription: String? {
    switch self {
    case .missingSigningCapability:
      return "当前安装包没有 CLAW 所需的 iCloud 文稿容器签名权限，无法执行云端拷贝或恢复。"
    case .unknownSigningCapability:
      return "当前安装包未提供可核验的 iCloud 权限标识，无法确认云端拷贝或恢复权限。"
    case .containerUnavailable:
      return "iCloud 容器当前不可用，请检查 Apple ID、iCloud Drive 和应用的 iCloud 设置。"
    }
  }
}

/// Resolves one confirmed container for a single iCloud file operation.
public struct ClawICloudAccessGate {
  private let readCapability: () -> Bool?
  private let resolveContainer: (String) -> URL?

  public init(
    readCapability: @escaping () -> Bool?,
    resolveContainer: @escaping (String) -> URL?
  ) {
    self.readCapability = readCapability
    self.resolveContainer = resolveContainer
  }

  public func documentsURL() throws -> URL {
    guard let capability = readCapability() else {
      throw ClawICloudAccessError.unknownSigningCapability
    }
    guard capability else {
      throw ClawICloudAccessError.missingSigningCapability
    }
    guard let container = resolveContainer(HamsterConstants.iCloudID) else {
      throw ClawICloudAccessError.containerUnavailable
    }
    return container.appendingPathComponent("Documents", isDirectory: true)
  }
}
