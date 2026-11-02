"""Unsigned IPA SHA preflight must reject unsafe ZIP members and broken executable modes.

These checks run before signing assets are installed by the release workflow.
"""

import plistlib
import stat
import sys
import unittest
import zipfile
from io import BytesIO
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from verify_signed_ipa import verify_ipa_source_sha


FROZEN_SHA = "a" * 40
BUNDLES = (
    ("Payload/Guru.app", "app.lgm.7517", "Guru"),
    ("Payload/Guru.app/PlugIns/Keyboard.appex", "app.lgm.7517.123", "Keyboard"),
    ("Payload/Guru.app/PlugIns/Widget.appex", "app.lgm.7517.widget", "Widget"),
)


class UnsignedIPAPreflightTests(unittest.TestCase):
    @staticmethod
    def add_file(archive, path, data, *, mode=0o644, kind=stat.S_IFREG):
        entry = zipfile.ZipInfo(path)
        entry.create_system = 3
        entry.external_attr = (kind | mode) << 16
        archive.writestr(entry, data)

    def make_archive(self, *, extra_path=None, extra_kind=stat.S_IFREG, host_mode=0o755):
        buffer = BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            for root, identifier, executable in BUNDLES:
                info = {
                    "CFBundleIdentifier": identifier,
                    "CFBundleExecutable": executable,
                    "MinimumOSVersion": "15.0",
                    "ClawSourceCommit": FROZEN_SHA,
                }
                self.add_file(archive, root + "/Info.plist", plistlib.dumps(info))
                mode = host_mode if identifier == "app.lgm.7517" else 0o755
                self.add_file(archive, root + "/" + executable, b"mach-o", mode=mode)
            if extra_path:
                self.add_file(archive, extra_path, b"unsafe", kind=extra_kind)
        buffer.seek(0)
        return buffer

    def verify(self, **kwargs):
        with zipfile.ZipFile(self.make_archive(**kwargs)) as archive:
            verify_ipa_source_sha(archive, FROZEN_SHA)

    def test_valid_unsigned_archive_passes(self):
        self.verify()

    def test_rejects_parent_traversal_before_signing(self):
        with self.assertRaisesRegex(ValueError, "unsafe IPA archive"):
            self.verify(extra_path="Payload/Guru.app/../../outside")

    def test_rejects_symlink_before_signing(self):
        with self.assertRaisesRegex(ValueError, "unsafe IPA archive"):
            self.verify(
                extra_path="Payload/Guru.app/Resources/linked",
                extra_kind=stat.S_IFLNK,
            )

    def test_rejects_missing_host_executable_mode_before_signing(self):
        with self.assertRaisesRegex(ValueError, "execute permission"):
            self.verify(host_mode=0o644)


if __name__ == "__main__":
    unittest.main()
