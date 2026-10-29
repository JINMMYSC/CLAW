"""Keep the basic CLAW widget available on the app's iOS 15 baseline."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]


class WidgetIOS15CompatibilityTests(unittest.TestCase):
    def test_widget_debug_and_release_deploy_to_ios15(self):
        project = (ROOT / "Hamster.xcodeproj" / "project.pbxproj").read_text(
            encoding="utf-8"
        )
        widget_configs = re.findall(
            r"A1000000000000000000000[DE] /\* (?:Debug|Release) \*/ = "
            r"\{isa = XCBuildConfiguration; buildSettings = \{([^}]+)\}",
            project,
        )
        self.assertEqual(len(widget_configs), 2, "both widget configs must exist")
        for config in widget_configs:
            self.assertRegex(config, r"IPHONEOS_DEPLOYMENT_TARGET = 15\.0;")

    def test_live_activity_is_guarded_above_ios15(self):
        source = (ROOT / "ClawWidgets" / "ClawWidgets.swift").read_text(
            encoding="utf-8"
        )
        self.assertIn("@available(iOSApplicationExtension 16.1, *)", source)
        self.assertIn("if #available(iOSApplicationExtension 16.1, *)", source)
        self.assertIn("ClawTodayWidget()", source)


if __name__ == "__main__":
    unittest.main()
