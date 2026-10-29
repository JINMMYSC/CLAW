"""Schema generation must not hang indefinitely on a bad upstream asset."""

from pathlib import Path
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "InputSchemaBuild.sh"


class InputSchemaDownloadFailFastTests(unittest.TestCase):
    def test_all_schema_downloads_are_bounded_and_fail_on_http_error(self):
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("curl --fail --location --retry 3", source)
        self.assertIn("--connect-timeout 15 --max-time 120", source)
        self.assertEqual(source.count("download_schema_asset"), 4)
        self.assertNotIn("curl -LO", source)
        self.assertNotIn("curl -Lo", source)

    def test_schema_repository_clones_have_low_speed_abort(self):
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertEqual(
            source.count("git -c http.lowSpeedLimit=1024 -c http.lowSpeedTime=30 clone"),
            2,
        )


if __name__ == "__main__":
    unittest.main()
