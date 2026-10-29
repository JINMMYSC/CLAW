from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT / "Packages/HamsterKit/Tests/Services/ClawWeChatLocalPumpTests.swift"


class WeChatPumpTestInitializerTests(unittest.TestCase):
    def test_every_pump_test_initializer_supplies_explicit_conversation_scope(self):
        source = TESTS.read_text(encoding="utf-8")
        cursor = 0
        invocations = 0
        while True:
            start = source.find("ClawWeChatLocalPump(", cursor)
            if start < 0:
                break
            opening = source.find("(", start)
            depth = 0
            end = opening
            for end in range(opening, len(source)):
                if source[end] == "(":
                    depth += 1
                elif source[end] == ")":
                    depth -= 1
                    if depth == 0:
                        break
            self.assertEqual(depth, 0, "Unbalanced ClawWeChatLocalPump initializer")
            invocation = source[opening:end + 1]
            invocations += 1
            self.assertIn(
                "allowedConversationID:", invocation,
                "Every pump test must opt into an exact conversation explicitly.",
            )
            cursor = end + 1
        self.assertGreater(invocations, 0, "Expected at least one pump initializer in tests")


if __name__ == "__main__":
    unittest.main()
