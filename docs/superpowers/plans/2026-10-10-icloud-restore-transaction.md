# iCloud Restore Transaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Follow RED-GREEN-REFACTOR and commit each task independently.

**Goal:** Block iCloud operations unless signing capability is explicitly confirmed, and preserve both live RIME directories when an ordinary restore I/O operation fails.

**Architecture:** A pure access gate resolves the configured container once. A filesystem transaction stages SharedSupport and UserData on the destination volume, commits them in order, and restores prior directories in reverse order on failure. Apple Developer configuration, process-crash recovery, ZIP restore, and keyboard concurrency remain separate acceptance batches.

**Tech Stack:** Swift, Foundation, XCTest, iOS 15.

## Global Constraints

- Base from the PR #19 integration lineage, which already contains PR #17 single-file staging.
- Never expose private paths or file contents in diagnostics.
- Preserve destination-only files through incremental merge.
- Do not claim global atomicity across other processes.
- Real iCloud read/write requires Apple entitlements and a real device.

---

### Task 1: Confirmed capability gate

**Files:**
- Create: `Packages/HamsterKit/Sources/Services/ClawICloudAccessGate.swift`
- Create: `Packages/HamsterKit/Tests/Services/ClawICloudAccessGateTests.swift`

**Interfaces:**

```swift
public enum ClawICloudAccessError: Error, LocalizedError, Equatable {
  case missingSigningCapability
  case unknownSigningCapability
  case containerUnavailable
}

public struct ClawICloudAccessGate {
  public init(
    readCapability: @escaping () -> Bool?,
    resolveContainer: @escaping (String) -> URL?
  )
  public func documentsURL() throws -> URL
}
```

- [ ] Add tests:
  - `testFalseCapabilityBlocksBeforeContainerResolution`
  - `testUnknownCapabilityBlocksBeforeContainerResolution`
  - `testEntitledBuildResolvesConfiguredContainerIdentifier`
  - `testUnavailableContainerThrowsBeforeFileMutation`
  - `testDocumentsURLUsesOneContainerResolution`
  - `testMissingOrNonBooleanBundleStampIsUnknown`
- [ ] Add a compiling skeleton and run the focused test. RED must be an assertion failure, not a compiler error.
- [ ] Implement: false → missing capability; nil/non-Bool → unknown; true resolves `HamsterConstants.iCloudID` exactly once and returns its Documents URL.
- [ ] Run the entire test class and commit:

```text
fix(icloud): require confirmed capability before file operations
```

### Task 2: Paired directory restore transaction

**Files:**
- Create: `Packages/HamsterKit/Sources/Services/ClawDirectoryRestoreTransaction.swift`
- Create: `Packages/HamsterKit/Tests/Services/ClawDirectoryRestoreTransactionTests.swift`
- Create: `Packages/HamsterKit/Tests/Support/ClawRestoreFileSystemFixture.swift`

**Interfaces:**

```swift
public enum ClawDirectoryRestoreOutcome {
  case committed
  case committedWithDeferredCleanup
}

public enum ClawDirectoryRestoreError: Error, LocalizedError {
  case invalidLayout
  case invalidSource
  case rollbackFailed
}

public struct ClawDirectoryRestoreTransaction {
  public init()
  public func restore(
    sourceRoot: URL,
    destinationRoot: URL,
    directoryNames: [String]
  ) throws -> ClawDirectoryRestoreOutcome
}
```

Use an internal `ClawRestoreFileSystem` protocol for deterministic failure injection. Validate source directories, duplicate/unsafe names, overlap, and symbolic links before mutation. Create a same-volume `.claw-restore-UUID` staging/rollback workspace. Stage both directories before moving either live directory. On commit failure, reverse successful moves. Preserve the unique old copy if rollback itself fails.

- [ ] Add tests:
  - `testMissingSecondSourceLeavesBothDestinationsUnchanged`
  - `testSecondStagingCopyFailureLeavesLiveDirectoriesUnchanged`
  - `testRestorePreservesDestinationOnlyFiles`
  - `testRestoreUpdatesBothDirectories`
  - `testSecondCommitFailureRollsBackFirstDirectory`
  - `testFailedCommitRestoresOriginallyAbsentDestination`
  - `testRollbackFailurePreservesOriginalBackup`
  - `testCleanupFailureReportsCommittedOutcome`
  - `testSuccessfulRestoreRemovesTransactionWorkspace`
  - `testInvalidOrOverlappingLayoutDoesNotMutateFiles`
  - `testSymbolicLinkSourceDoesNotEscapeRestoreRoot`
- [ ] Run `testSecondCommitFailureRollsBackFirstDirectory` and observe a disk-snapshot assertion fail.
- [ ] Implement staging, commit journal, reverse rollback, and cleanup outcome.
- [ ] Run the full transaction test class and existing `FileManagerTest`.
- [ ] Commit:

```text
feat(icloud): stage and roll back paired directory restores
```

### Task 3: Route iCloud copy and restore through the services

**Files:**
- Create: `Packages/HamsterKit/Sources/Services/ClawICloudFileOperations.swift`
- Create: `Packages/HamsterKit/Tests/Services/ClawICloudFileOperationsTests.swift`
- Modify: `Packages/HamsteriOS/Sources/ViewModel/iCloud/AppleCloudViewModel.swift`

**Interfaces:**

```swift
public struct ClawICloudFileOperations {
  public init()
  public init(
    gate: ClawICloudAccessGate,
    transaction: ClawDirectoryRestoreTransaction,
    sandboxRoot: URL
  )
  public func copyToICloud(filterRegex: [String]) throws
  public func restoreFromICloud() throws -> ClawDirectoryRestoreOutcome
}
```

- [ ] Add tests proving false/unknown/unavailable capability makes no mutation, one container resolution serves both directories, second-directory failure preserves the original sandbox, and committed outcome contains both updated directories.
- [ ] Observe the focused integration test RED.
- [ ] Move duplicate ViewModel guards into the common operation entry.
- [ ] Report success only after committed outcome. Distinguish deferred cleanup and rollback failure without logging paths.
- [ ] Run HamsterKit, HamsteriOS (skipping the existing CloudKitHelperTest), signing Python tests, and `git diff --check`.
- [ ] Commit:

```text
fix(icloud): restore through capability gate and directory transaction
```

### Verification commands

On macOS select an available iPhone simulator, then run focused tests with `xcodebuild test -scheme HamsterKit -only-testing:<exact test>`. After each GREEN run the whole modified class. At the final SHA run HamsterKit, HamsteriOS, Build Test, signed IPA, and Startup Smoke.

Real-device acceptance remains required for login changes, iCloud Drive off, first upload, offline recovery, storage exhaustion, two-device round trip, interrupted restore, and concurrent keyboard access.
