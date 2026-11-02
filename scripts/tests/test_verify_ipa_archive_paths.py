"""Regression: signed IPA verification rejects hostile archive members before extraction."""

import os
import plistlib
import stat
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from verify_signed_ipa import verify_ipa


class SignedIPAArchivePathTests(unittest.TestCase):
    @staticmethod
    def _write_file(archive, name, data, mode=0o644, kind=stat.S_IFREG):
        member = zipfile.ZipInfo(name)
        member.create_system = 3
        member.external_attr = (kind | mode) << 16
        archive.writestr(member, data)

    def _make_ipa(self, filename, hostile_name, hostile_kind=stat.S_IFREG):
        bundles = (
            ("Payload/Guru.app", "app.lgm.7517", "Guru"),
            ("Payload/Guru.app/PlugIns/Keyboard.appex", "app.lgm.7517.123", "Keyboard"),
            ("Payload/Guru.app/PlugIns/Widget.appex", "app.lgm.7517.widget", "Widget"),
        )
        with zipfile.ZipFile(filename, "w") as archive:
            for root, bundle_id, executable in bundles:
                info = {
                    "CFBundleIdentifier": bundle_id,
                    "CFBundleExecutable": executable,
                    "MinimumOSVersion": "15.0",
                }
                self._write_file(archive, root + "/Info.plist", plistlib.dumps(info))
                self._write_file(archive, root + "/" + executable, b"binary", mode=0o755)
            self._write_file(
                archive, hostile_name, b"untrusted", mode=0o777, kind=hostile_kind
            )

    def _assert_rejected_before_codesign(self, hostile_name, hostile_kind=stat.S_IFREG):
        with tempfile.TemporaryDirectory() as directory:
            ipa = os.path.join(directory, "malicious.ipa")
            self._make_ipa(ipa, hostile_name, hostile_kind)
            with patch("verify_signed_ipa.subprocess.run", side_effect=AssertionError(
                "codesign must not run for an unsafe IPA"
            )):
                with self.assertRaisesRegex(ValueError, "unsafe IPA archive"):
                    verify_ipa(ipa)

    def test_rejects_parent_traversal_member(self):
        self._assert_rejected_before_codesign(
            "Payload/Guru.app/Resources/../../../../escaped.txt"
        )

    def test_rejects_symlink_member(self):
        self._assert_rejected_before_codesign(
            "Payload/Guru.app/Resources/link", stat.S_IFLNK
        )


if __name__ == "__main__":
    unittest.main()
