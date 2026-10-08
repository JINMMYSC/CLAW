//
//  File.swift
//
//
//  Created by morse on 2023/7/4.
//

import Foundation
import os
import Yams

public extension URL {
  /// 获取制定URL下文件或目录URL
  func getFilesAndDirectories() -> [URL] {
    do {
      return try FileManager.default.contentsOfDirectory(
        at: self,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
      )
    } catch {
      Logger.statistics.error("Error getting files and directories - \(error.localizedDescription)")
      return []
    }
  }

  /// 获取指定URL路径下 .schema.yaml 文件URL
//  func getSchemesFile() -> [URL] {
//    getFilesAndDirectories()
//      .filter { $0.lastPathComponent.hasSuffix(".schema.yaml") }
//  }

  /// 获取指定URL的文件内容
  func getStringFromFile() -> String? {
    guard let data = FileManager.default.contents(atPath: path) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  /// 获取 RIME 同步路径位置
  func getSyncPath() -> String? {
    guard let yamlContent = getStringFromFile() else { return nil }
    do {
      if let yamlFileContent = try Yams.load(yaml: yamlContent) as? [String: Any] {
        return yamlFileContent["sync_dir"] as? String
      }
    } catch {
      Logger.statistics.error("yaml load error \(error.localizedDescription), url:\(self.path)")
    }
    return nil
  }
}

// MARK: iCloud 相关地址

/// iCloud 不可用：未登录 iCloud、关闭了 iCloud Drive，或该 App 的 iCloud 开关未打开。
public enum ICloudPathError: LocalizedError {
  case unavailable

  public var errorDescription: String? {
    "iCloud 容器不可用。请检查 Apple ID、iCloud Drive 和 CLAW 的 iCloud 权限；如使用自行签名 IPA，还需检查签名描述文件是否包含正确的 iCloud 容器权限。"
  }
}

public extension URL {
  // 应用iCloud文件夹
  // 注意：appendingPathComponent("Documents")是非常重要的一点，如果没有它，你的文件夹将不会显示在iCloud Drive里面。
  /// 每次求值、不做缓存：用户中途登录 iCloud 后无需重启 App 即可生效。
  static var iCloudDocumentURL: URL? {
    guard let icloudURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
    return icloudURL.appendingPathComponent("Documents")
  }

  // iCloud中RIME使用文件路径
  // iCloud 不可用时抛错，避免强制解包导致闪退。
  static func iCloudRimeURL() throws -> URL {
    guard let base = iCloudDocumentURL else { throw ICloudPathError.unavailable }
    return base.appendingPathComponent("RIME")
  }

  // iCloud中 RIME sharedSupport 路径
  static func iCloudSharedSupportURL() throws -> URL {
    try iCloudRimeURL().appendingPathComponent(HamsterConstants.rimeSharedSupportPathName)
  }

  // iCloud中 RIME 方案 userData 路径
  static func iCloudUserDataURL() throws -> URL {
    try iCloudRimeURL().appendingPathComponent(HamsterConstants.rimeUserPathName)
  }

  // iCloud 中 RIME 方案同步路径
  static func iCloudRimeSyncURL() throws -> URL {
    try iCloudRimeURL().appendingPathComponent("sync")
  }

  // iCloud 中 软件备份路径
  static func iCloudBackupsURL() throws -> URL {
    guard let base = iCloudDocumentURL else { throw ICloudPathError.unavailable }
    return base.appendingPathComponent("backups")
  }
}
