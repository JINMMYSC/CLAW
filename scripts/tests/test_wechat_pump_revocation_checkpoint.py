from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "Packages/HamsterKit/Sources/Services/ClawWeChatLocalPump.swift"


class WeChatPumpRevocationCheckpointTests(unittest.TestCase):
    def test_connection_is_rechecked_after_media_download_before_processing(self):
        source = SOURCE.read_text(encoding="utf-8")
        download = source.index("let data = try await transport.downloadMedia(")
        processor = source.index("let response = try await processor.makeReply", download)
        checkpoint = source[download:processor]
        self.assertIn("guard connection == .active", checkpoint)


if __name__ == "__main__":
    unittest.main()
