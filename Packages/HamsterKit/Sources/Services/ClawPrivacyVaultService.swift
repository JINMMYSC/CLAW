import Foundation
import LocalAuthentication

/// Protects selected long-term memories from both UI disclosure and AI retrieval.
///
/// Unlock state is intentionally process-local and short lived. The keyboard extension
/// never receives a persistent "unlocked" bit from the host app, so vault-protected
/// memories stay excluded from keyboard context unless that process explicitly unlocks.
public final class ClawPrivacyVaultService {
  public static let shared = ClawPrivacyVaultService()

  private let defaults = UserDefaults(suiteName: HamsterConstants.appGroupName)
  private let protectedIDsKey = "claw_privacy_vault_memory_ids_v1"
  private let lock = NSLock()
  private var unlockedUntil: Date?

  private init() {}

  public var protectedMemoryIDs: Set<UUID> {
    Set((defaults?.stringArray(forKey: protectedIDsKey) ?? []).compactMap(UUID.init(uuidString:)))
  }

  public var isUnlocked: Bool {
    lock.lock(); defer { lock.unlock() }
    guard let until = unlockedUntil else { return false }
    if until <= Date() {
      unlockedUntil = nil
      return false
    }
    return true
  }

  public func isProtected(_ item: ClawMemoryItem) -> Bool {
    protectedMemoryIDs.contains(item.id)
  }

  public func isVisibleToAI(_ item: ClawMemoryItem) -> Bool {
    !isProtected(item) || isUnlocked
  }

  public func setProtected(_ itemID: UUID, protected: Bool) {
    var ids = protectedMemoryIDs
    if protected { ids.insert(itemID) } else { ids.remove(itemID) }
    defaults?.set(ids.map(\.uuidString).sorted(), forKey: protectedIDsKey)
  }

  public func lockNow() {
    lock.lock(); unlockedUntil = nil; lock.unlock()
  }

  /// Uses biometrics when available and falls back to the device passcode.
  /// Successful unlock lasts only for the requested short session.
  public func unlock(
    reason: String = "解锁 CLAW 隐私保险箱",
    duration: TimeInterval = 5 * 60,
    completion: @escaping (Bool, Error?) -> Void
  ) {
    let context = LAContext()
    context.localizedCancelTitle = "取消"
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      completion(false, error)
      return
    }
    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, error in
      guard success else {
        completion(false, error)
        return
      }
      self?.lock.lock()
      self?.unlockedUntil = Date().addingTimeInterval(max(30, duration))
      self?.lock.unlock()
      completion(true, nil)
    }
  }
}

