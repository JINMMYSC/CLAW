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
  /// Implementations must bound downloads WHILE streaming; never allocate
  /// untrusted image/voice payloads in full before checking maximumBytes.
  func downloadMedia(reference: String, maximumBytes: Int) async throws -> Data
  func sendText(_ text: String, conversationID: String) async throws
}

/// A separate image/OCR or voice/transcription processor is injected by the
/// containing application. It has no direct access to the keyboard UI.
public protocol ClawWeChatLocalMessageProcessor {
  func makeReply(to message: ClawWeChatLocalMessage, media: Data?) async throws -> String?
}

/// A host-UI boundary that must confirm the exact draft and destination with
/// the user for EACH reply. Connection authorization is never send consent.
/// Until such a confirmation UI exists, omit this dependency to fail closed.
public protocol ClawWeChatLocalSendApproval {
  func confirmSend(reply: String, to message: ClawWeChatLocalMessage) async -> Bool
}

public enum ClawWeChatLocalPumpError: Error, Equatable {
  case notRunning
  case alreadyRunning
  case mediaTooLarge
  case invalidMediaReference
}

/// One execution owner per connection: the host and keyboard must never run
/// this pump simultaneously. Process-level lease and Keychain auth will be
/// added only after the provider grants independent client access.
public actor ClawWeChatLocalPump {
  private let transport: ClawWeChatLocalTransport
  private let processor: ClawWeChatLocalMessageProcessor
  private let allowedSenderID: String
  private let allowedConversationID: String
  private let sendApproval: ClawWeChatLocalSendApproval?
  private let maximumMediaBytes: Int
  private var inbox: ClawWeChatLocalInboxGuard
  private var cursor: String?
  private var connection: ClawWeChatLocalConnectionState = .authorizedPaused
  // A pause/revoke followed by reactivation must not resurrect in-flight work.
  private var connectionRevision: UInt64 = 0
  private var isPolling = false

  public init(
    transport: ClawWeChatLocalTransport,
    processor: ClawWeChatLocalMessageProcessor,
    allowedSenderID: String,
    allowedConversationID: String,
    sendApproval: ClawWeChatLocalSendApproval? = nil,
    maximumMediaBytes: Int = 12 * 1024 * 1024,
    inboxCapacity: Int = 512
  ) {
    self.transport = transport
    self.processor = processor
    self.allowedSenderID = allowedSenderID
    self.allowedConversationID = allowedConversationID
    self.sendApproval = sendApproval
    maximumMediaBytes = max(1, maximumMediaBytes)
    inbox = ClawWeChatLocalInboxGuard(capacity: inboxCapacity)
  }

  public func setConnection(_ state: ClawWeChatLocalConnectionState) {
    connection = state
    connectionRevision &+= 1
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
    // Missing owner or conversation identifiers are not valid authorization.
    // Fail before fetching any private data, even if a provider emits blank IDs.
    guard !allowedSenderID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ClawWeChatLocalPumpError.notRunning
    }
    guard !allowedConversationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ClawWeChatLocalPumpError.notRunning
    }
    guard ClawWeChatLocalRuntimePolicy.canPoll(
      connection: connection,
      hostForeground: hostForeground,
      keyboardVisible: keyboardVisible,
      keyboardFullAccess: keyboardFullAccess
    ) else { throw ClawWeChatLocalPumpError.notRunning }
    try Task.checkCancellation()
    let authorizationRevision = connectionRevision
    isPolling = true
    defer { isPolling = false }

    let batch = try await transport.fetch(after: cursor)
    // If the user leaves the app, authorization expires, or the keyboard
    // loses execution permission during fetch, do NOT consume the cursor.
    guard connection == .active && connectionRevision == authorizationRevision else {
      throw ClawWeChatLocalPumpError.notRunning
    }
    try Task.checkCancellation()
    var handled = 0
    for message in batch.messages {
      guard connection == .active && connectionRevision == authorizationRevision else {
        throw ClawWeChatLocalPumpError.notRunning
      }
      try Task.checkCancellation()
      // This bridge is a *personal* assistant. Never process other people's
      // messages under the owner's personal-memory authorization.
      guard message.senderID == allowedSenderID else { continue }
      // Owner identity alone is insufficient: the same account may appear in
      // groups or unrelated chats. Enforce the explicit conversation scope
      // before deduplication, media download, AI processing, or any reply.
      guard message.conversationID == allowedConversationID else { continue }
      // InboxGuard skips structurally invalid rows. A malformed media row in
      // the authorized conversation must instead stop this batch, or advancing
      // the cursor would permanently acknowledge an unprocessed attachment.
      if message.kind == .image || message.kind == .voice {
        guard let reference = message.mediaReference,
              !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          throw ClawWeChatLocalPumpError.invalidMediaReference
        }
      }
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
          // A malformed adapter row must fail closed, not crash the pump or
          // acknowledge a cursor that still contains unprocessed media.
          guard let reference = message.mediaReference,
                !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClawWeChatLocalPumpError.invalidMediaReference
          }
          let data = try await transport.downloadMedia(
            reference: reference, maximumBytes: maximumMediaBytes
          )
          guard data.count <= maximumMediaBytes else {
            throw ClawWeChatLocalPumpError.mediaTooLarge
          }
          // Authorization may be revoked while the transport is suspended.
          // Do not pass downloaded private media to OCR/AI after the channel pauses.
          guard connection == .active && connectionRevision == authorizationRevision else {
            throw ClawWeChatLocalPumpError.notRunning
          }
          media = data
        }
        let response = try await processor.makeReply(to: message, media: media)
        try Task.checkCancellation()
        guard connection == .active && connectionRevision == authorizationRevision else {
          throw ClawWeChatLocalPumpError.notRunning
        }
        if let reply = response?.trimmingCharacters(in: .whitespacesAndNewlines), !reply.isEmpty {
          guard connection == .active && connectionRevision == authorizationRevision else {
            throw ClawWeChatLocalPumpError.notRunning
          }
          // Drafting a response is not permission to send it. A missing or
          // rejecting UI confirmation skips delivery without retrying the
          // same unapproved message on every poll.
          guard let sendApproval else {
            handled += 1
            continue
          }
          guard await sendApproval.confirmSend(reply: reply, to: message) else {
            handled += 1
            continue
          }
          // User may pause/revoke the connection while approval is pending.
          guard connection == .active && connectionRevision == authorizationRevision else {
            throw ClawWeChatLocalPumpError.notRunning
          }
          try Task.checkCancellation()
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
    // A paused/cancelled connection must not acknowledge unseen messages.
    guard connection == .active && connectionRevision == authorizationRevision else {
      throw ClawWeChatLocalPumpError.notRunning
    }
    try Task.checkCancellation()
    cursor = batch.nextCursor
    return handled
  }
}
