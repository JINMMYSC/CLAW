import Foundation

/// The screenshot OCR flow may only populate a transient editable draft.
public enum ClawScreenshotDraftPolicy {
  public static func combine(existing: String, recognized: String) -> String {
    let incoming = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !incoming.isEmpty else { return existing }
    guard !existing.isEmpty else { return incoming }
    let separator = existing.hasSuffix("\n") ? "" : "\n"
    return existing + separator + incoming
  }
}
