"""A release IPA must have one unambiguous ZIP member for each path."""
import io
import pathlib
import plistlib
import sys
import tempfile
import unittest
import warnings
import zipfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import sign_ipa
from verify_signed_ipa import verify_release_bundle_manifest, verify_ipa_source_sha


class DuplicateArchiveMemberTests(unittest.TestCase):
    def archive_bytes(self):
        buffer = io.BytesIO()
        entries = (
            ("Payload/Hamster.app/Info.plist", "app.lgm.7517"),
            ("Payload/Hamster.app/PlugIns/Keyboard.appex/Info.plist", "app.lgm.7517.123"),
            ("Payload/Hamster.app/PlugIns/Widget.appex/Info.plist", "app.lgm.7517.widget"),
        )
        with zipfile.ZipFile(buffer, "w") as archive:
            for path, bundle_id in entries:
                archive.writestr(path, plistlib.dumps({
                    "CFBundleIdentifier": bundle_id,
                    "MinimumOSVersion": "15.0",
                    "ClawSourceCommit": "a" * 40,
                }))
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                archive.writestr("Payload/Hamster.app/Extra.bin", b"first")
                archive.writestr("Payload/Hamster.app/Extra.bin", b"second")
        return buffer.getvalue()

    def test_release_manifest_rejects_duplicate_nonplist_member(self):
        with zipfile.ZipFile(io.BytesIO(self.archive_bytes())) as archive:
            with self.assertRaisesRegex(ValueError, "duplicate"):
                verify_release_bundle_manifest(archive)

    def test_unsigned_source_sha_gate_rejects_duplicate_nonplist_member(self):
        with zipfile.ZipFile(io.BytesIO(self.archive_bytes())) as archive:
            with self.assertRaisesRegex(ValueError, "duplicate"):
                verify_ipa_source_sha(archive, "a" * 40)

    def test_signer_rejects_duplicate_member_before_extraction(self):
        with tempfile.TemporaryDirectory() as tmp:
            ipa = pathlib.Path(tmp) / "duplicate.ipa"
            ipa.write_bytes(self.archive_bytes())
            with self.assertRaisesRegex(ValueError, "duplicate"):
                sign_ipa.extract_app(str(ipa), tmp)


if __name__ == "__main__":
    unittest.main()
