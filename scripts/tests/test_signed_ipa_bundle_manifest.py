"""Signed releases must retain all three iOS 15-compatible bundle identifiers."""
import io
import pathlib
import plistlib
import sys
import unittest
import zipfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from verify_signed_ipa import verify_release_bundle_manifest, verify_ipa_source_sha


class SignedIPABundleManifestTests(unittest.TestCase):
    def archive(self, omit_widget=False, keyboard_id="app.lgm.7517.123",
                widget_minimum="15.0", source_sha="a" * 40,
                widget_source_sha=None):
        buffer = io.BytesIO()
        bundles = [
            ("Payload/Hamster.app/Info.plist", "app.lgm.7517", "15.0"),
            ("Payload/Hamster.app/PlugIns/HamsterKeyboard.appex/Info.plist",
             keyboard_id, "15.0"),
        ]
        if not omit_widget:
            bundles.append((
                "Payload/Hamster.app/PlugIns/ClawWidgets.appex/Info.plist",
                "app.lgm.7517.widget", widget_minimum,
            ))
        with zipfile.ZipFile(buffer, "w") as archive:
            for name, bundle_id, minimum in bundles:
                metadata = {
                    "CFBundleIdentifier": bundle_id,
                    "MinimumOSVersion": minimum,
                    "ClawSourceCommit": (
                        widget_source_sha
                        if widget_source_sha is not None and bundle_id == "app.lgm.7517.widget"
                        else source_sha
                    ),
                }
                archive.writestr(name, plistlib.dumps(metadata))
        buffer.seek(0)
        return zipfile.ZipFile(buffer)

    def test_exact_host_keyboard_widget_on_ios15_passes(self):
        with self.archive() as archive:
            verify_release_bundle_manifest(archive)

    def test_missing_widget_is_rejected(self):
        with self.archive(omit_widget=True) as archive:
            with self.assertRaisesRegex(ValueError, "Widget"):
                verify_release_bundle_manifest(archive)

    def test_wrong_keyboard_bundle_identifier_is_rejected(self):
        with self.archive(keyboard_id="app.lgm.7517.wrong") as archive:
            with self.assertRaisesRegex(ValueError, "Bundle IDs"):
                verify_release_bundle_manifest(archive)

    def test_widget_ios16_minimum_is_rejected(self):
        with self.archive(widget_minimum="16.0") as archive:
            with self.assertRaisesRegex(ValueError, "iOS 15"):
                verify_release_bundle_manifest(archive)

    def test_unsigned_source_sha_matches_all_three_bundles(self):
        with self.archive() as archive:
            verify_ipa_source_sha(archive, "a" * 40)

    def test_unsigned_source_sha_rejects_wrong_widget_commit(self):
        with self.archive(widget_source_sha="b" * 40) as archive:
            with self.assertRaisesRegex(ValueError, "source SHA mismatch"):
                verify_ipa_source_sha(archive, "a" * 40)

    def test_unsigned_source_sha_rejects_missing_widget_stamp(self):
        with self.archive(widget_source_sha="") as archive:
            with self.assertRaisesRegex(ValueError, "source SHA mismatch"):
                verify_ipa_source_sha(archive, "a" * 40)

    def test_unsigned_source_sha_rejects_invalid_expected_sha(self):
        with self.archive() as archive:
            with self.assertRaisesRegex(ValueError, "lowercase 40-character"):
                verify_ipa_source_sha(archive, "A" * 40)

    def test_unsigned_source_sha_requires_widget_bundle(self):
        with self.archive(omit_widget=True) as archive:
            with self.assertRaisesRegex(ValueError, "Widget"):
                verify_ipa_source_sha(archive, "a" * 40)


if __name__ == "__main__":
    unittest.main()
