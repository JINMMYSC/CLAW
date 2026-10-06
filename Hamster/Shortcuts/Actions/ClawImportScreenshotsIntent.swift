import AppIntents
import HamsterKit
import UIKit

/// System-compatible ingestion entry point:
/// Shortcuts can run "Take Screenshot" -> "CLAW 导入聊天截图".
@available(iOS 16.0, *)
struct ClawImportScreenshotsIntent: AppIntent {
  static var title: LocalizedStringResource = "CLAW 导入聊天截图"
  static var description = IntentDescription("把一张或多张聊天截图写入 CLAW 人物时间线，并自动提取待办。")
  static var openAppWhenRun = false
  static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

  @Parameter(title: "聊天截图")
  var screenshots: [IntentFile]

  static var parameterSummary: some ParameterSummary {
    Summary("导入 \(.$screenshots) 到 CLAW")
  }

  func perform() async throws -> some ReturnsValue & ProvidesDialog {
    var insertedTotal = 0
    var names = Set<String>()
    for file in screenshots.prefix(6) {
      let data = file.data
      guard let image = UIImage(data: data) else { continue }
      let lines = try await recognize(image)
      let evidence = image.jpegData(compressionQuality: 0.88)
        .flatMap { ClawScreenshotEvidenceStore.shared.saveJPEG($0) }
        ?? "shortcut-screenshot:\(UUID().uuidString)"

      let selected = HeartTargetService.shared.selectedProfile
      let first = ClawScreenshotChatParser.shared.parse(
        lines: lines,
        contactID: selected?.id,
        contactName: selected?.displayName,
        sourceRef: evidence
      )
      let resolution = ClawContactIdentityResolver.shared.resolve(displayTitle: first.detectedTitle, allowCreate: true)
      let profile = resolution.profile ?? selected
      if let profile {
        HeartTargetService.shared.select(id: profile.id)
        names.insert(profile.displayName)
      }
      let parsed = ClawScreenshotChatParser.shared.parse(
        lines: lines,
        contactID: profile?.id,
        contactName: profile?.displayName,
        sourceRef: evidence
      )
      for message in parsed.messages {
        if (try? ClawMemoryStore.shared.appendConversation(message)) == true {
          insertedTotal += 1
          ClawSecretaryExtractor.shared.persistExtractedTasks(from: message)
        }
      }
      if let id = profile?.id {
        ClawContactProfileLearner.shared.refreshIfNeeded(profileID: id)
      }
    }
    let who = names.isEmpty ? "" : "（\(names.sorted().joined(separator: "、"))）"
    return .result(value: insertedTotal, dialog: "CLAW 已归档 \(insertedTotal) 条聊天记录\(who)")
  }

  private func recognize(_ image: UIImage) async throws -> [VisionOCRService.OCRLine] {
    try await withCheckedThrowingContinuation { continuation in
      VisionOCRService.shared.recognizeLines(in: image) { result in
        continuation.resume(with: result)
      }
    }
  }
}

