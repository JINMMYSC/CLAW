"""Widget-only changes must run the same macOS Startup Smoke gate as Host changes."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class StartupSmokeWidgetPathGateTests(unittest.TestCase):
    def test_widget_sources_trigger_startup_smoke(self):
        workflow = (ROOT / ".github/workflows/startup-smoke.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn('"ClawWidgets/**"', workflow)


if __name__ == "__main__":
    unittest.main()
