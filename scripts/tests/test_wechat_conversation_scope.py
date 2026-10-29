from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "Packages/HamsterKit/Sources/Services/ClawWeChatLocalPump.swift"


class WeChatConversationScopeTests(unittest.TestCase):
    def test_pump_requires_an_explicit_allowed_conversation(self):
        source = SOURCE.read_text(encoding="utf-8")
        self.assertIn("private let allowedConversationID: String", source)
        self.assertIn("allowedConversationID: String", source)

    def test_foreign_conversation_is_rejected_before_media_or_ai_processing(self):
        source = SOURCE.read_text(encoding="utf-8")
        sender_check = source.index("guard message.senderID == allowedSenderID else { continue }")
        conversation_check = source.index(
            "guard message.conversationID == allowedConversationID else { continue }"
        )
        admission = source.index("let admission = inbox.admit(message", conversation_check)
        media_download = source.index("transport.downloadMedia(", conversation_check)
        processor = source.index("processor.makeReply(to: message, media: media)", conversation_check)

        self.assertLess(sender_check, conversation_check)
        self.assertLess(conversation_check, admission)
        self.assertLess(conversation_check, media_download)
        self.assertLess(conversation_check, processor)


if __name__ == "__main__":
    unittest.main()
