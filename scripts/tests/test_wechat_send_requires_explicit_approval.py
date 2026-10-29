"""Static safety gate; Swift XCTest must still run on macOS before release."""

from pathlib import Path
import unittest


SOURCE = Path(__file__).resolve().parents[2] / (
    "Packages/HamsterKit/Sources/Services/ClawWeChatLocalPump.swift"
)


class WeChatSendRequiresExplicitApprovalTests(unittest.TestCase):
    def test_send_is_fail_closed_without_an_explicit_reply_approval_provider(self):
        source = SOURCE.read_text(encoding="utf-8")
        self.assertIn("public protocol ClawWeChatLocalSendApproval", source)
        self.assertIn("sendApproval: ClawWeChatLocalSendApproval? = nil", source)
        self.assertIn("guard let sendApproval", source)
        self.assertIn("await sendApproval.confirmSend(reply: reply, to: message)", source)


    def test_connection_is_rechecked_after_async_reply_approval(self):
        source = SOURCE.read_text(encoding="utf-8")
        approval_call = source.index("await sendApproval.confirmSend(reply: reply, to: message)")
        send_call = source.index("try await transport.sendText(reply, conversationID: message.conversationID)")
        self.assertIn("guard connection == .active", source[approval_call:send_call])
        self.assertIn("try Task.checkCancellation()", source[approval_call:send_call])


if __name__ == "__main__":
    unittest.main()
