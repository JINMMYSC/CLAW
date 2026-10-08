import Foundation

public struct ClawContactResolution: Equatable {
  public var profile: HeartTargetProfile?
  public var confidence: Double
  public var created: Bool
  public var reason: String

  public init(profile: HeartTargetProfile?, confidence: Double, created: Bool, reason: String) {
    self.profile = profile
    self.confidence = confidence
    self.created = created
    self.reason = reason
  }
}

/// Resolves screenshot/chat titles to a stable CLAW person profile.
/// It deliberately refuses weak/generic titles instead of creating junk contacts.
public final class ClawContactIdentityResolver {
  public static let shared = ClawContactIdentityResolver()

  private let genericTitles: Set<String> = [
    "微信", "聊天", "消息", "通讯录", "返回", "更多", "详情", "群聊", "new chat", "messages",
  ]

  public init() {}

  public func resolve(
    displayTitle: String?,
    avatarFingerprint: String? = nil,
    allowCreate: Bool = true
  ) -> ClawContactResolution {
    let service = HeartTargetService.shared
    guard let rawTitle = displayTitle else {
      return ClawContactResolution(profile: service.selectedProfile, confidence: service.selectedProfile == nil ? 0 : 0.65, created: false, reason: "no-title")
    }
    let title = normalized(rawTitle)
    guard isValidTitle(title) else {
      return ClawContactResolution(profile: service.selectedProfile, confidence: service.selectedProfile == nil ? 0 : 0.55, created: false, reason: "generic-title")
    }

    if let fingerprint = avatarFingerprint,
       let profile = service.profiles.first(where: { $0.avatarFingerprint == fingerprint }) {
      touch(profile)
      return ClawContactResolution(profile: profile, confidence: 0.995, created: false, reason: "avatar")
    }
    if let profile = service.profiles.first(where: { $0.matches(displayTitle: title) }) {
      touch(profile)
      return ClawContactResolution(profile: profile, confidence: 0.98, created: false, reason: "name-or-alias")
    }

    let fuzzy = service.profiles.filter { profile in
      let name = normalized(profile.name)
      guard min(name.count, title.count) >= 2 else { return false }
      return name.contains(title) || title.contains(name)
    }
    if fuzzy.count == 1, let profile = fuzzy.first {
      touch(profile)
      return ClawContactResolution(profile: profile, confidence: 0.82, created: false, reason: "unique-fuzzy-title")
    }

    guard allowCreate else {
      return ClawContactResolution(profile: nil, confidence: 0, created: false, reason: "not-found")
    }
    let group = looksLikeGroup(title)
    let profile = HeartTargetProfile(
      name: title,
      relationship: group ? "群聊" : "",
      aliases: [],
      autoCreated: true,
      isGroup: group,
      avatarFingerprint: avatarFingerprint,
      lastSeenAt: Date()
    )
    let saved = service.upsert(profile)
    service.select(id: saved.id)
    return ClawContactResolution(profile: saved, confidence: 0.78, created: true, reason: "auto-created")
  }

  private func touch(_ profile: HeartTargetProfile) {
    var updated = profile
    updated.lastSeenAt = Date()
    _ = HeartTargetService.shared.upsert(updated)
  }

  private func normalized(_ value: String) -> String {
    value
      .replacingOccurrences(of: #"\s*\(\d+\)\s*$"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"\s*[（]\d+[）]\s*$"#, with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func isValidTitle(_ title: String) -> Bool {
    guard (1...40).contains(title.count) else { return false }
    guard !genericTitles.contains(title.lowercased()) else { return false }
    guard title.range(of: #"^[\p{L}\p{N}\p{Han}_·\- .（）()]+$"#, options: .regularExpression) != nil else { return false }
    return true
  }

  private func looksLikeGroup(_ title: String) -> Bool {
    title.contains("群") || title.range(of: #"[（(]\d+[）)]$"#, options: .regularExpression) != nil
  }
}

