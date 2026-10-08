import Foundation

/// Keeps profile changes and their dependent Memory records consistent.
public final class ClawPeopleWorkflowService {
  public static let shared = ClawPeopleWorkflowService()

  private let profiles: HeartTargetService
  private let store: ClawMemoryStore

  public init(
    profiles: HeartTargetService = .shared,
    store: ClawMemoryStore = .shared
  ) {
    self.profiles = profiles
    self.store = store
  }

  @discardableResult
  public func merge(sourceID: UUID, into destinationID: UUID) -> Bool {
    guard sourceID != destinationID,
          let source = profiles.profile(id: sourceID),
          let destination = profiles.profile(id: destinationID)
    else { return false }

    let destinationWasSelected = profiles.selectedProfile?.id == destinationID
    let sourceWasSelected = profiles.selectedProfile?.id == sourceID
    let merged = Self.mergedProfile(source: source, destination: destination)
    _ = profiles.upsert(merged)
    do {
      try store.reassignContactReferences(from: sourceID, to: destinationID)
      profiles.delete(id: sourceID)
      if sourceWasSelected || destinationWasSelected { profiles.select(id: destinationID) }
      return true
    } catch {
      _ = profiles.upsert(destination)
      return false
    }
  }

  /// Safely delete *only* empty profiles. Legacy behavior promoted all
  /// dependent records to global scope and could leak person-specific context.
  /// Callers must explicitly handle a false result and leave data untouched.
  @discardableResult
  public func deleteProfilePreservingRecords(_ id: UUID) -> Bool {
    guard profiles.profile(id: id) != nil else { return false }
    do {
      guard try !store.hasContactReferences(id: id) else { return false }
      profiles.delete(id: id)
      return true
    } catch {
      return false
    }
  }

  public func splitCopy(of profile: HeartTargetProfile) -> HeartTargetProfile {
    HeartTargetProfile(
      name: profile.name + "（拆分）",
      bio: profile.bio,
      avatarData: profile.avatarData,
      relationship: profile.relationship,
      aliases: profile.aliases,
      isGroup: profile.isGroup
    )
  }

  public static func mergedProfile(
    source: HeartTargetProfile,
    destination: HeartTargetProfile
  ) -> HeartTargetProfile {
    var merged = destination
    merged.relationship = merged.relationship.isEmpty ? source.relationship : merged.relationship
    merged.bio = joinedDistinct(merged.bio, source.bio)
    merged.learnedSummary = joinedDistinct(merged.learnedSummary, source.learnedSummary)
    merged.avatarData = merged.avatarData ?? source.avatarData
    merged.avatarFingerprint = merged.avatarFingerprint ?? source.avatarFingerprint
    merged.lastSeenAt = [merged.lastSeenAt, source.lastSeenAt].compactMap { $0 }.max()
    merged.autoCreated = merged.autoCreated && source.autoCreated

    var aliases = merged.aliases
    aliases.append(contentsOf: source.aliases)
    if source.name.caseInsensitiveCompare(merged.name) != .orderedSame {
      aliases.append(source.name)
    }
    var seen: Set<String> = []
    merged.aliases = aliases.filter {
      let key = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      return !key.isEmpty && seen.insert(key).inserted
    }
    return merged
  }

  private static func joinedDistinct(_ first: String, _ second: String) -> String {
    let values = [first, second]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return Array(NSOrderedSet(array: values))
      .compactMap { $0 as? String }
      .joined(separator: "\n")
  }
}
