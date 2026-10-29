from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "Packages/HamsterKit/Sources/Services/ClawWeChatLocalPump.swift"


class WeChatPumpNonemptyScopeGateTests(unittest.TestCase):
    def test_poll_rejects_blank_sender_and_conversation_before_fetch(self):
        source = SOURCE.read_text(encoding="utf-8")
        poll = source.split("public func pollOnce(", 1)[1]
        before_fetch = poll.split("let batch = try await transport.fetch", 1)[0]
        self.assertIn("!allowedSenderID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty", before_fetch)
        self.assertIn("!allowedConversationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty", before_fetch)


if __name__ == "__main__":
    unittest.main()
