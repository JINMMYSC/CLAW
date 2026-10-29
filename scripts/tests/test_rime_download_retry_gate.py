"""Fail release gates if transient upstream downloads have no bounded retry."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class RimeDownloadRetryGateTests(unittest.TestCase):
    def test_build_and_signed_release_use_bounded_retries(self):
        for name in ("ci.yml", "build-ipa.yml"):
            with self.subTest(workflow=name):
                workflow = (ROOT / ".github" / "workflows" / name).read_text(encoding="utf-8")
                self.assertIn("curl --retry 3 --retry-delay 2 --retry-all-errors", workflow)
                self.assertIn("--connect-timeout 15 --max-time 120 -fL", workflow)
                self.assertIn('"$BASE/$f.xcframework.zip"', workflow)


if __name__ == "__main__":
    unittest.main()
