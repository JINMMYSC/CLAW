import Foundation

public struct ClawScreenshotParseResult: Equatable {
  public var detectedTitle: String?
  public var messages: [ClawConversationMessage]
  public var rawText: String

  public init(detectedTitle: String?, messages: [ClawConversationMessage], rawText: String) {
    self.detectedTitle = detectedTitle
    self.messages = messages
    self.rawText = rawText
  }
}

/// Geometry-first screenshot parser. It intentionally prefers `unknown` over inventing a speaker.
public final class ClawScreenshotChatParser {
  public static let shared = ClawScreenshotChatParser()

  public init() {}

  public func parse(
    lines: [VisionOCRService.OCRLine],
    contactID: UUID?,
    contactName: String?,
    capturedAt: Date = Date(),
    sourceRef: String? = nil
  ) -> ClawScreenshotParseResult {
    // Vision observations do not promise visual reading order. Normalize
    // top-to-bottom before grouping so the timeline is independent of the
    // OCR callback order (Vision coordinates have their origin at bottom-left).
    let useful = lines
      .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .sorted {
        if $0.boundingBox.midY != $1.boundingBox.midY {
          return $0.boundingBox.midY > $1.boundingBox.midY
        }
        return $0.boundingBox.minX < $1.boundingBox.minX
      }
    let raw = useful.map(\.text).joined(separator: "\n")
    let title = detectTitle(in: useful, expectedContactName: contactName)
    let body = useful.filter { !isChromeLine($0, title: title) }

    // Merge OCR lines that visually belong to the same bubble row and share a side.
    var groups: [[VisionOCRService.OCRLine]] = []
    for line in body {
      let side = speaker(for: line)
      if var last = groups.last,
         let lastLine = last.last,
         speaker(for: lastLine) == side,
         abs(lastLine.boundingBox.midY - line.boundingBox.midY) < 0.055 {
        last.append(line)
        groups[groups.count - 1] = last
      } else {
        groups.append([line])
      }
    }

    let calendar = Calendar.current
    var messages: [ClawConversationMessage] = []
    for (index, group) in groups.enumerated() {
      let ordered = group.sorted {
        if $0.boundingBox.midY != $1.boundingBox.midY {
          return $0.boundingBox.midY > $1.boundingBox.midY
        }
        return $0.boundingBox.minX < $1.boundingBox.minX
      }
      let content = ordered.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
      guard content.count > 0, !looksLikeTimestamp(content) else { continue }
      let representative = ordered[0]
      let role = speaker(for: representative)
      let secondsOffset = TimeInterval(max(0, groups.count - index))
      let occurredAt = calendar.date(byAdding: .second, value: -Int(secondsOffset), to: capturedAt) ?? capturedAt
      messages.append(ClawConversationMessage(
        contactID: contactID,
        speaker: role,
        senderName: role == .other ? (contactName ?? title) : nil,
        content: content,
        occurredAt: occurredAt,
        sourceType: "screenshot",
        sourceRef: sourceRef,
        confidence: Double(ordered.map(\.confidence).min() ?? 0.6)
      ))
    }
    return ClawScreenshotParseResult(detectedTitle: title, messages: messages, rawText: raw)
  }

  private func detectTitle(in lines: [VisionOCRService.OCRLine], expectedContactName: String?) -> String? {
    if let expectedContactName, !expectedContactName.isEmpty,
       lines.contains(where: { $0.text.contains(expectedContactName) && $0.boundingBox.midY > 0.82 }) {
      return expectedContactName
    }
    return lines
      .filter { $0.boundingBox.midY > 0.84 && $0.boundingBox.midX > 0.22 && $0.boundingBox.midX < 0.78 }
      .filter { !$0.text.contains("返回") && !$0.text.contains("...") }
      .max(by: { $0.confidence < $1.confidence })?
      .text
  }

  private func speaker(for line: VisionOCRService.OCRLine) -> ClawConversationSpeaker {
    if line.boundingBox.midX >= 0.58 { return .me }
    if line.boundingBox.midX <= 0.42 { return .other }
    return .unknown
  }

  private func isChromeLine(_ line: VisionOCRService.OCRLine, title: String?) -> Bool {
    if line.boundingBox.midY > 0.86 { return true }
    if line.boundingBox.midY < 0.08 { return true }
    let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if text == title { return true }
    let chrome = ["语音输入", "按住说话", "发送", "更多", "相册", "拍摄"]
    return chrome.contains(text)
  }

  private func looksLikeTimestamp(_ text: String) -> Bool {
    // Match standalone date/time chrome only. A message such as “周五提交方案”
    // starts with a weekday token but is still actual conversation content.
    let pattern = #"^(今天|昨天|星期.|周.|\d{1,2}:\d{2}|\d{1,2}月\d{1,2}日|\d{4}年.*)$"#
    return text.range(of: pattern, options: .regularExpression) != nil
  }
}
