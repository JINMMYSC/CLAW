"""A full-feature signed IPA must not silently remove the widget extension."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class SignedIPAWidgetPreservationTests(unittest.TestCase):
    def test_missing_widget_profile_fails_closed_instead_of_stripping_widget(self):
        workflow = (ROOT / ".github/workflows/build-ipa.yml").read_text(encoding="utf-8")
        secrets_gate = workflow.split("- name: Check signing secrets", 1)[1].split(
            "- name: Download unsigned ipa", 1
        )[0]

        self.assertIn("WIDGET_PROFILE_B64: ${{ secrets.PROFILE_WIDGET_B64 }}", secrets_gate)
        self.assertIn("missing+=(PROFILE_WIDGET_B64)", secrets_gate)
        self.assertNotIn("Omit widget only when its signing profile is unavailable", workflow)
        self.assertNotIn("omitted ClawWidgets from signed IPA", workflow)

    def test_widget_must_exist_in_release_ipa(self):
        workflow = (ROOT / ".github/workflows/build-ipa.yml").read_text(encoding="utf-8")
        extension_gate = workflow.split("- name: Inspect extension bundle identifiers", 1)[1].split(
            "- name: Install signing assets", 1
        )[0]
        self.assertIn('if [ "$has_widget" != "true" ]; then', extension_gate)
        self.assertIn("Widget extension app.lgm.7517.widget is missing", extension_gate)


if __name__ == "__main__":
    unittest.main()
