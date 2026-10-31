import Foundation

/// Presentation-only authorization policy for explicit contact profile learning.
/// This does not grant consent: only a deliberate user action may call the store.
public enum ClawContactProfileLearningPresentationPolicy {
  public static func canSetConsent(
    to granted: Bool,
    isGroup: Bool,
    isConfirmed: Bool
  ) -> Bool {
    // Revocation must remain available even after a contact becomes a group,
    // is unconfirmed, or disappears from the UI.
    if !granted { return true }
    return !isGroup && isConfirmed
  }
}
