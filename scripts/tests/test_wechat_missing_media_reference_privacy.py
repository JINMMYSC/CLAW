"""Auxiliary source gate for malformed WeChat adapter media references.

Runtime behavior must be verified by Swift XCTest on macOS CI.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "Packages/HamsterKit/Sources/Services/ClawWeChatLocalPump.swift"
NATIVE = ROOT / "Packages/HamsterKit/Tests/Services/ClawWeChatLocalMissingMediaReferencePrivacyTests.swift"


class MissingMediaReferencePrivacyTests(unittest.TestCase):
    def test_media_reference_is_validated_before_download_without_force_unwrap(self):
        source = SOURCE.read_text(encoding="utf-8")
        admitted_scope = source.split("guard message.conversationID == allowedConversationID else { continue }", 1)[1].split(
            "let admission = inbox.admit", 1
        )[0]
        self.assertIn("ClawWeChatLocalPumpError.invalidMediaReference", admitted_scope)
        self.assertIn("message.mediaReference", admitted_scope)
        media_branch = source.split("case .image, .voice:", 1)[1].split(
            "let response = try await processor.makeReply", 1
        )[0]
        self.assertIn("ClawWeChatLocalPumpError.invalidMediaReference", media_branch)
        self.assertIn("message.mediaReference", media_branch)
        self.assertIn("trimmingCharacters(in: .whitespacesAndNewlines)", media_branch)
        self.assertNotIn("message.mediaReference!", media_branch)
        self.assertLess(media_branch.index("invalidMediaReference"), media_branch.index("downloadMedia"))

    def test_native_test_covers_nil_and_blank_without_side_effects(self):
        native = NATIVE.read_text(encoding="utf-8")
        self.assertIn("Optional<String>.none", native)
        self.assertIn('Optional(" \\t ")', native)
        self.assertIn("XCTAssertNil(cursor)", native)
        self.assertIn("XCTAssertEqual(processed, 0)", native)


if __name__ == "__main__":
    unittest.main()
