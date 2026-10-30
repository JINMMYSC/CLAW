"""Regression: re-signing an IPA must not strip executable bits from iOS binaries."""
import io
import os
import pathlib
import plistlib
import stat
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import sign_ipa


class SigningExecutableModeTests(unittest.TestCase):
    def test_host_keyboard_widget_executables_survive_extract_and_repack(self):
        executables = (
            ("Payload/Hamster.app/Hamster", "app.lgm.7517"),
            ("Payload/Hamster.app/PlugIns/HamsterKeyboard.appex/HamsterKeyboard",
             "app.lgm.7517.123"),
            ("Payload/Hamster.app/PlugIns/ClawWidgets.appex/ClawWidgets",
             "app.lgm.7517.widget"),
        )
        with tempfile.TemporaryDirectory() as tmp:
            ipa = pathlib.Path(tmp, "unsigned.ipa")
            with zipfile.ZipFile(ipa, "w") as archive:
                for executable, bundle_id in executables:
                    binary = zipfile.ZipInfo(executable)
                    binary.create_system = 3
                    binary.external_attr = (stat.S_IFREG | 0o755) << 16
                    archive.writestr(binary, b"MachO")
                    info = zipfile.ZipInfo(
                        executable.rsplit("/", 1)[0] + "/Info.plist")
                    archive.writestr(info, plistlib.dumps({
                        "CFBundleIdentifier": bundle_id,
                    }))
            work, app = sign_ipa.extract_app(str(ipa), tmp)
            self.assertTrue(app.endswith("Hamster.app"))
            for executable, _bundle_id in executables:
                path = pathlib.Path(work, executable)
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o755,
                                 executable)
            repacked = pathlib.Path(tmp, "repacked.ipa")
            with zipfile.ZipFile(repacked, "w", zipfile.ZIP_DEFLATED) as archive:
                for root, _dirs, files in os.walk(work):
                    for filename in files:
                        path = pathlib.Path(root, filename)
                        archive.write(path, path.relative_to(work))
            with zipfile.ZipFile(repacked) as archive:
                for executable, _bundle_id in executables:
                    mode = stat.S_IMODE(
                        archive.getinfo(executable).external_attr >> 16)
                    self.assertEqual(mode, 0o755, executable)

    def test_rejects_archive_path_traversal_before_extraction(self):
        with tempfile.TemporaryDirectory() as tmp:
            ipa = pathlib.Path(tmp, "unsafe.ipa")
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr("Payload/../outside.txt", b"bad")
            with self.assertRaisesRegex(ValueError, "unsafe IPA archive path"):
                sign_ipa.extract_app(str(ipa), tmp)


if __name__ == "__main__":
    unittest.main()
