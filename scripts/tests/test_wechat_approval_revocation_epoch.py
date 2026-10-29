"""Auxiliary guard for approval revocation; Swift XCTest still required."""

from pathlib import Path
import unittest


SOURCE = Path(__file__).resolve().parents[2] / (
    "Packages/HamsterKit/Sources/Services/ClawWeChatLocalPump.swift"
)


class WeChatApprovalRevocationEpochTests(unittest.TestCase):
    def test_reactivation_does_not_revalidate_stale_send_approval(self):
        source = SOURCE.read_text(encoding="utf-8")
        self.assertIn("private var connectionRevision", source)
        self.assertIn("connectionRevision &+= 1", source)
        approval = source.index("await sendApproval.confirmSend(reply: reply, to: message)")
        send = source.index("try await transport.sendText(reply, conversationID: message.conversationID)")
        self.assertIn("connectionRevision == authorizationRevision", source[approval:send])


if __name__ == "__main__":
    unittest.main()
