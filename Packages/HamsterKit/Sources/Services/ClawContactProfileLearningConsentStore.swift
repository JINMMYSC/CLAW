import Foundation
import CoreFoundation

/// Explicit, per-contact opt-in for AI-generated contact profile learning.
/// Consent defaults to denied and is stored in the shared App Group defaults.
public final class ClawContactProfileLearningConsentStore {
  public static let shared = ClawContactProfileLearningConsentStore(
    defaults: UserDefaults(suiteName: HamsterConstants.appGroupName)
  )

  private static let accessLock = NSRecursiveLock()
  private let defaults: UserDefaults?
  private let keyPrefix = "claw_contact_profile_learning_consent_"
  private let tokenKeyPrefix = "claw_contact_profile_learning_authorization_token_"

  public init(defaults: UserDefaults?) {
    self.defaults = defaults
  }

  public func isGranted(for contactID: UUID) -> Bool {
    Self.accessLock.lock()
    defer { Self.accessLock.unlock() }
    guard let defaults else { return false }
    return isExplicitlyGranted(in: defaults, for: contactID)
  }

  /// Returns the token for the current consent session. A revoke followed by
  /// a new grant must create a different token so older async results stay stale.
  public func authorizationToken(for contactID: UUID) -> String? {
    Self.accessLock.lock()
    defer { Self.accessLock.unlock() }
    guard let defaults else { return nil }
    guard isExplicitlyGranted(in: defaults, for: contactID) else {
      return nil
    }

    let tokenKey = authorizationTokenKey(for: contactID)
    if let token = defaults.string(forKey: tokenKey), !token.isEmpty {
      return token
    }
    let token = UUID().uuidString
    defaults.set(token, forKey: tokenKey)
    return token
  }

  public func setGranted(_ granted: Bool, for contactID: UUID) {
    Self.accessLock.lock()
    defer { Self.accessLock.unlock() }
    guard let defaults else { return }
    let consentKey = key(for: contactID)
    if granted {
      // Fail closed while rotating the token for a new consent session.
      defaults.removeObject(forKey: consentKey)
      defaults.set(UUID().uuidString, forKey: authorizationTokenKey(for: contactID))
      defaults.set(true, forKey: consentKey)
    } else {
      defaults.removeObject(forKey: consentKey)
      defaults.removeObject(forKey: authorizationTokenKey(for: contactID))
    }
  }

  /// Serialize the final consent check with persistence so revocation cannot
  /// race between the check and writes in this process.
  @discardableResult
  func performIfGranted(for contactID: UUID, _ operation: () -> Void) -> Bool {
    Self.accessLock.lock()
    defer { Self.accessLock.unlock() }
    guard let defaults else { return false }
    guard isExplicitlyGranted(in: defaults, for: contactID) else {
      return false
    }
    operation()
    return true
  }

  /// Runs only if the consent session still matches the one that authorized
  /// the async work. This prevents revoke-then-regrant from reviving stale output.
  @discardableResult
  func performIfGranted(
    for contactID: UUID,
    authorizationToken: String,
    _ operation: () -> Void
  ) -> Bool {
    Self.accessLock.lock()
    defer { Self.accessLock.unlock() }
    guard let defaults else { return false }
    guard isExplicitlyGranted(in: defaults, for: contactID),
          defaults.string(forKey: authorizationTokenKey(for: contactID)) == authorizationToken else {
      return false
    }
    operation()
    return true
  }

  /// Reads consent-protected data while the same lock guards the current
  /// authorization session. The returned snapshot is nil if consent was
  /// revoked or replaced before the read began.
  @discardableResult
  func withAuthorization<T>(
    for contactID: UUID,
    authorizationToken: String,
    _ operation: () -> T
  ) -> T? {
    Self.accessLock.lock()
    defer { Self.accessLock.unlock() }
    guard let defaults else { return nil }
    guard isExplicitlyGranted(in: defaults, for: contactID),
          defaults.string(forKey: authorizationTokenKey(for: contactID)) == authorizationToken else {
      return nil
    }
    return operation()
  }

  private func key(for contactID: UUID) -> String {
    keyPrefix + contactID.uuidString.lowercased()
  }

  /// A numeric/string value bridged by Foundation is not explicit user consent.
  /// Every read and authorization gate must use the same fail-closed rule.
  private func isExplicitlyGranted(in defaults: UserDefaults, for contactID: UUID) -> Bool {
    guard let stored = defaults.object(forKey: key(for: contactID)) as? NSNumber,
          CFGetTypeID(stored) == CFBooleanGetTypeID() else {
      return false
    }
    return stored.boolValue
  }

  private func authorizationTokenKey(for contactID: UUID) -> String {
    tokenKeyPrefix + contactID.uuidString.lowercased()
  }
}
