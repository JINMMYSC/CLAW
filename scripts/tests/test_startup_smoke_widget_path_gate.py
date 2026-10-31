"""Every candidate push, including Widget and Voice changes, must run Startup Smoke."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class StartupSmokeWidgetPathGateTests(unittest.TestCase):
    def test_candidate_push_has_unfiltered_startup_smoke(self):
        workflow = (ROOT / ".github/workflows/startup-smoke.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn("  push:\n", workflow)
        push = workflow.split("  push:\n", 1)[1].split("\nconcurrency:", 1)[0]
        self.assertIn("'feature/claw-ipa-build-candidate-*'", push)
        # An absent paths filter includes Widget, Voice, RIME and project files.
        # A Widget-only or Voice-only push must not silently skip startup checks.
        self.assertNotIn("\n    paths:", push)
        self.assertNotIn("\n    paths-ignore:", push)


if __name__ == "__main__":
    unittest.main()
