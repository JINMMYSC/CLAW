import Foundation

/// A draft belongs to a specific person and a specific keyboard AI surface.
/// Nil personID means global mode; it is never interchangeable with a person.
public struct ClawPanelDraftContext: Hashable {
  public let personID: UUID?
  public let tab: Int

  public init(personID: UUID?, tab: Int) {
    self.personID = personID
    self.tab = tab
  }
}

/// In-process storage only: never upload or persist unsent keyboard input.
public struct ClawPanelDraftStore {
  private var drafts: [ClawPanelDraftContext: String] = [:]

  public init() {}

  public mutating func save(_ text: String, for context: ClawPanelDraftContext) {
    guard (0...2).contains(context.tab) else { return }
    if text.isEmpty {
      drafts.removeValue(forKey: context)
    } else {
      drafts[context] = text
    }
  }

  public func text(for context: ClawPanelDraftContext) -> String {
    guard (0...2).contains(context.tab) else { return "" }
    return drafts[context] ?? ""
  }
}
