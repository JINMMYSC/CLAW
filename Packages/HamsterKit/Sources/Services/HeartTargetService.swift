import Foundation
import UIKit

extension Notification.Name {
  /// 聊天对象档案集合变化（增删改/切换选中）
  public static let heartTargetProfilesDidChange = Notification.Name("heartTargetProfilesDidChange")
}

/// 聊天对象个人档案（设置页加入，键盘面板内切换）
public struct HeartTargetProfile: Codable, Identifiable, Equatable {
  public let id: UUID
  public var name: String
  public var bio: String
  public var avatarData: Data?
  /// 用户明确设置的关系，例如朋友/客户/家人。
  public var relationship: String
  /// AI 从可追溯互动里提炼的画像；与手工 bio 分开，便于纠错和重建。
  public var learnedSummary: String
  /// 备注名/昵称，用于截图顶部标题匹配。
  public var aliases: [String]
  public var updatedAt: Date

  public init(
    id: UUID = UUID(),
    name: String = "",
    bio: String = "",
    avatarData: Data? = nil,
    relationship: String = "",
    learnedSummary: String = "",
    aliases: [String] = [],
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.bio = bio
    self.avatarData = avatarData
    self.relationship = relationship
    self.learnedSummary = learnedSummary
    self.aliases = aliases
    self.updatedAt = updatedAt
  }

  enum CodingKeys: String, CodingKey {
    case id, name, bio, avatarData, relationship, learnedSummary, aliases, updatedAt
  }

  /// Backward-compatible decoding for profiles saved by older builds.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    bio = try c.decodeIfPresent(String.self, forKey: .bio) ?? ""
    avatarData = try c.decodeIfPresent(Data.self, forKey: .avatarData)
    relationship = try c.decodeIfPresent(String.self, forKey: .relationship) ?? ""
    learnedSummary = try c.decodeIfPresent(String.self, forKey: .learnedSummary) ?? ""
    aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
    updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
  }

  /// 头像 UIImage（用于设置页与键盘面板展示）
  public var avatarImage: UIImage? {
    guard let avatarData else { return nil }
    return UIImage(data: avatarData)
  }

  public var displayName: String {
    name.isEmpty ? "未命名档案" : name
  }

  public var memoryContext: String {
    var parts: [String] = []
    if !relationship.isEmpty { parts.append("关系：\(relationship)") }
    if !bio.isEmpty { parts.append("用户备注：\(bio)") }
    if !learnedSummary.isEmpty { parts.append("互动画像：\(learnedSummary)") }
    return parts.joined(separator: "\n")
  }

  public func matches(displayTitle: String) -> Bool {
    let normalized = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized == name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() { return true }
    return aliases.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized }
  }
}

/// 聊天对象档案存储服务（UserDefaults，App Group 与键盘扩展共享）
public class HeartTargetService {
  public static let shared = HeartTargetService()

  private let defaults = UserDefaults(suiteName: HamsterConstants.appGroupName)
  private let profilesKey = "heart_target_profiles"
  private let selectedKey = "heart_target_selected"

  public private(set) var profiles: [HeartTargetProfile] = []
  public private(set) var selectedIndex: Int = -1

  public var selectedProfile: HeartTargetProfile? {
    guard selectedIndex >= 0, selectedIndex < profiles.count else { return nil }
    return profiles[selectedIndex]
  }

  public var hasProfiles: Bool { !profiles.isEmpty }

  init() {
    reload()
  }

  func reload() {
    if let data = defaults?.data(forKey: profilesKey),
       let decoded = try? JSONDecoder().decode([HeartTargetProfile].self, from: data) {
      profiles = decoded
    }
    selectedIndex = defaults?.integer(forKey: selectedKey) ?? -1
    if selectedIndex >= profiles.count { selectedIndex = -1 }
  }

  private func persist() {
    defaults?.set(try? JSONEncoder().encode(profiles), forKey: profilesKey)
    defaults?.set(selectedIndex, forKey: selectedKey)
    NotificationCenter.default.post(name: .heartTargetProfilesDidChange, object: nil)
  }

  @discardableResult
  public func upsert(_ profile: HeartTargetProfile) -> HeartTargetProfile {
    var profile = profile
    profile.updatedAt = Date()
    if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
      profiles[idx] = profile
    } else {
      profiles.append(profile)
      if selectedIndex < 0 { selectedIndex = 0 }
    }
    persist()
    return profile
  }

  public func delete(id: UUID) {
    profiles.removeAll { $0.id == id }
    if selectedIndex >= profiles.count { selectedIndex = profiles.isEmpty ? -1 : profiles.count - 1 }
    persist()
  }

  public func select(at index: Int) {
    guard index >= 0, index < profiles.count else { return }
    selectedIndex = index
    persist()
  }

  public func select(id: UUID) {
    if let idx = profiles.firstIndex(where: { $0.id == id }) {
      select(at: idx)
    }
  }

  /// 全局模式：只使用用户全局记忆，不混合任何联系人档案。
  public func clearSelection() {
    selectedIndex = -1
    persist()
  }
}
Process exited with code 0.