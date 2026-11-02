// Compile this alongside MemoryV2Models.swift and MemorySyncProtocol.swift
// using: swiftc -swift-version 6 -typecheck ...
// This is a compiler-level regression gate, not a runtime test.
import Foundation

private func requireSendable<T: Sendable>(_: T.Type) {}

func verifyClawMemoryCrossActorValueTypes() {
  requireSendable(MemoryScope.self)
  requireSendable(MemoryState.self)
  requireSendable(MemoryType.self)
  requireSendable(MemoryOriginType.self)
  requireSendable(MemoryCloudPermission.self)
  requireSendable(MemoryProvenance.self)
  requireSendable(MemoryEvidence.self)
  requireSendable(MemoryLineage.self)
  requireSendable(MemoryV2Record.self)
  requireSendable(MemoryVersionVector.self)
  requireSendable(MemorySyncOperationKind.self)
  requireSendable(MemorySyncOperation.self)
}
