import Foundation
import XCTest
@testable import HamsterKit

final class ClawRuntimeCapabilityInspectorTests: XCTestCase {
  func testPermissionDeniedIsFailureAndGrantIsNotProofOfAudioSuccess() {
    XCTAssertEqual(ClawRuntimeCapabilityInspector.voice(speech: "denied", microphone: "granted").status, .fault)
    XCTAssertEqual(ClawRuntimeCapabilityInspector.voice(speech: "authorized", microphone: "denied").status, .fault)
    XCTAssertEqual(ClawRuntimeCapabilityInspector.voice(speech: "authorized", microphone: "granted").status, .unknown)
    XCTAssertEqual(ClawRuntimeCapabilityInspector.voice(speech: "unknown", microphone: "granted").status, .unknown)
  }

  func testSignedICloudCapabilityAndIdentityAreEvaluatedSeparately() {
    XCTAssertEqual(ClawRuntimeCapabilityInspector.sync(entitled: false, signedIn: true).status, .fault)
    XCTAssertEqual(ClawRuntimeCapabilityInspector.sync(entitled: true, signedIn: false).status, .fault)
    XCTAssertEqual(ClawRuntimeCapabilityInspector.sync(entitled: true, signedIn: true).status, .unknown)
    XCTAssertEqual(ClawRuntimeCapabilityInspector.sync(entitled: nil, signedIn: nil).status, .unknown)
  }
}
