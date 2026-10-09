import Foundation

/// New replies should follow the bottom only while the user is already at the
/// bottom; search and reading older messages must preserve scroll position.
public enum ClawChatScrollPolicy {
  public static func shouldFollow(isAtBottom: Bool, isSearching: Bool) -> Bool {
    isAtBottom && !isSearching
  }
}
