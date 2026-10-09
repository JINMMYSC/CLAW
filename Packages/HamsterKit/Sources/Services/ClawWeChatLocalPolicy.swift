import Foundation

/// Explicit states for an on-device WeChat channel. Authorization is not
/// evidence that the iOS process is actively polling for new messages.
public enum ClawWeChatLocalConnectionState: String, Codable {
  case disconnected, awaitingAuthorization, authorizedPaused, active, recovering, expired, failed
}

public enum ClawWeChatLocalMessageKind: String, Codable {
  case text, image, voice
}

/// A minimal, transient envelope. Image/voice bytes are downloaded and verified
/// by a separate authorized media transport; references are never treated as
/// trusted local file paths. This type does not write to personal memory.
public struct ClawWeChatLocalMessage: Equatable {
  public let messageID: String
  public let conversationID: String
  public let senderID: String
  public let kind: ClawWeChatLocalMessageKind
  public let text: String?
  public let mediaReference: String?

  public init(
    messageID: String,
    conversationID: String,
    senderID: String,
    kind: ClawWeChatLocalMessageKind,
    text: String? = nil,
    mediaReference: String? = nil
  ) {
    self.messageID = messageID
    self.conversationID = conversationID
    self.senderID = senderID
    self.kind = kind
    self.text = text
    self.mediaReference = mediaReference
  }

  public var isStructurallyValid: Bool {
    guard !messageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !conversationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !senderID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    switch kind {
    case .text:
      return !(text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .image, .voice:
      return !(mediaReference ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }
}

public enum ClawWeChatLocalRuntimePolicy {
  /// The host app is executable only while foregrounded. Keyboard network
  /// processing requires both a visible extension and user-granted full access.
  /// Neither screen-on state nor prior login makes the bridge always-on.
  public static func canPoll(
    connection: ClawWeChatLocalConnectionState,
    hostForeground: Bool,
    keyboardVisible: Bool,
    keyboardFullAccess: Bool
  ) -> Bool {
    guard connection == .active else { return false }
    return hostForeground || (keyboardVisible && keyboardFullAccess)
  }
}

public enum ClawWeChatLocalAdmission: Equatable {
  case accepted, duplicate, invalid, paused
}

/// Bounded in-process duplicate suppression across reconnects and text/media
/// message kinds. No message bodies, contact labels or audio are retained here.
public struct ClawWeChatLocalInboxGuard {
  private struct MessageKey: Hashable {
    let conversationID: String
    let messageID: String
  }

  private var seen: Set<MessageKey> = []
  private var order: [MessageKey] = []
  private let capacity: Int

  public init(capacity: Int = 512) {
    self.capacity = max(1, capacity)
  }

  public mutating func admit(
    _ message: ClawWeChatLocalMessage,
    bridgeActive: Bool
  ) -> ClawWeChatLocalAdmission {
    guard bridgeActive else { return .paused }
    guard message.isStructurallyValid else { return .invalid }
    let key = MessageKey(conversationID: message.conversationID, messageID: message.messageID)
    guard seen.insert(key).inserted else { return .duplicate }
    order.append(key)
    if order.count > capacity {
      let expired = order.removeFirst()
      seen.remove(expired)
    }
    return .accepted
  }

  /// A failed download/AI request/send must be eligible for retry with the
  /// same message ID. Successful replies remain suppressed until evicted.
  public mutating func release(_ message: ClawWeChatLocalMessage) {
    let key = MessageKey(conversationID: message.conversationID, messageID: message.messageID)
    guard seen.remove(key) != nil else { return }
    order.removeAll { $0 == key }
  }
}

/// Stable, length-prefixed identity for retrying the same outgoing reply.
/// Not a credential; the transport must not write it into logs.
public enum ClawWeChatLocalDeliveryKey {
  public static func make(for message: ClawWeChatLocalMessage) -> String {
    let components = [message.senderID, message.conversationID, message.messageID]
    return "claw-reply-v1:" + components.map { "\($0.utf8.count):\($0)" }.joined()
  }
}
