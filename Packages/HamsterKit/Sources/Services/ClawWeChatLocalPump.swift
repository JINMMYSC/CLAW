import Foundation

/// A single fetched batch with an opaque provider cursor.
public struct ClawWeChatLocalBatch {
  public let messages: [ClawWeChatLocalMessage]
  public let nextCursor: String?

  public init(messages: [ClawWeChatLocalMessage], nextCursor: String?) {
    self.messages = messages
    self.nextCursor = nextCursor
  }
}

/// Protocol seam for an authorized provider adapter. It intentionally does not
/// implement private iLink APIs or assume third-party access is permitted.
/// Media references are opaque, and transport must authenticate/decrypt them.
public protocol ClawWeChatLocalTransport {
  func fetch(after cursor: String?) async throws -> ClawWeChatLocalBatch
  func downloadMedia(reference: String) async throws -> Data
  func sendText(_ text: String, conversationID: String) async throws
}

/// A separate image/OCR or voice/transcription processor is injected by the
/// containing application. It has no direct access to the keyboard UI.
public protocol ClawWeChatLocalMessageProcessor {
  func makeReply(to message: ClawWeChatLocalMessage, media: Data?) async throws -> String?
}

public enum ClawWeChatLocalPumpError: Error, Equatable {
  case notRunning
  case alreadyRunning
  case mediaTooLarge
}

/// One execution owner per connection: the host and keyboard must never run
/// this pump simultaneously. Process-level lease and Keychain auth will be
/// added only after the provider grants independent client access.
public actor ClawWeChatLocalPump {
  private let transport: ClawWeChatLocalTransport
  private let processor: ClawWeChatLocalMessageProcessor
  private let allowedSenderID: String
  private let maximumMediaBytes: Int
  private var inbox: ClawWeChatLocalInboxGuard
  private var cursor: String?
  private var connection: ClawWeChatLocalConnectionState = .authorizedPaused
  private var isPolling = false

  public init(
    transport: ClawWeChatLocalTransport,
    processor: ClawWeChatLocalMessageProcessor,
    allowedSenderID: String,
    maximumMediaBytes: Int = 12 * 1024 * 1024,
    inboxCapacity: Int = 512
  ) {
    self.transport = transport
    self.processor = processor
    self.allowedSenderID = allowedSenderID
    maximumMediaBytes = max(1, maximumMediaBytes)
    inbox = ClawWeChatLocalInboxGuard(capacity: inboxCapacity)
  }

  public func setConnection(_ state: ClawWeChatLocalConnectionState) {
    connection = state
  }

  public func lastCursor() -> String? { cursor }

  /// Exactly one bounded poll. No indefinite background loop: the caller must
  /// opt in for each poll while iOS permits execution.
  @discardableResult
  public func pollOnce(
    hostForeground: Bool,
    keyboardVisible: Bool,
    keyboardFullAccess: Bool
  ) async throws -> Int {
    guard !isPolling else { throw ClawWeChatLocalPumpError.alreadyRunning }
    guard ClawWeChatLocalRuntimePolicy.canPoll(
      connection: connection,
      hostForeground: hostForeground,
      keyboardVisible: keyboardVisible,
      keyboardFullAccess: keyboardFullAccess
    ) else { throw ClawWeChatLocalPumpError.notRunning }
    isPolling = true
    defer { isPolling = false }

    let batch = try await transport.fetch(after: cursor)
    var handled = 0
    for message in batch.messages {
      // This bridge is a *personal* assistant. Never process other people's
      // messages under the owner's personal-memory authorization.
      guard message.senderID == allowedSenderID else { continue }
      let admission = inbox.admit(message, bridgeActive: connection == .active)
      guard admission == .accepted else { continue }
      do {
        let media: Data?
        switch message.kind {
        case .text:
          media = nil
        case .image, .voice:
          // Bytes must come from the authenticated adapter, never an
          // arbitrary file URL chosen by the sender.
          let data = try await transport.downloadMedia(reference: message.mediaReference!)
          guard data.count <= maximumMediaBytes else {
            throw ClawWeChatLocalPumpError.mediaTooLarge
          }
          media = data
        }
        let response = try await processor.makeReply(to: message, media: media)
        if let reply = response?.trimmingCharacters(in: .whitespacesAndNewlines), !reply.isEmpty {
          guard connection == .active else { throw ClawWeChatLocalPumpError.notRunning }
          try await transport.sendText(reply, conversationID: message.conversationID)
        }
        handled += 1
      } catch {
        inbox.release(message)
        // Do not advance the cursor: failures must never silently drop media
        // or user messages. Previously sent messages stay deduplicated.
        throw error
      }
    }
    cursor = batch.nextCursor
    return handled
  }
}
