"""Native object-level checks for pinned RIME release ZIPs without Xcode."""

import importlib.util
from pathlib import Path
import struct
import unittest


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "audit_rime_release_archives.py"
SPEC = importlib.util.spec_from_file_location("rime_offline_audit", MODULE_PATH)
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


def macho(platform=2, minimum=(15, 0, 0)):
    version = (minimum[0] << 16) | (minimum[1] << 8) | minimum[2]
    header = struct.pack("<IiiIIIII", 0xFEEDFACF, 0x0100000C, 0, 1, 1, 24, 0, 0)
    return header + struct.pack("<IIIIII", 0x32, 24, platform, version, 0, 0)


def archive(name, payload):
    name_bytes = name.encode("utf-8")
    size = len(name_bytes) + len(payload)
    header = (f"#1/{len(name_bytes)}".ljust(16) + "0".ljust(12)
              + "0".ljust(6) + "0".ljust(6) + "100644".ljust(8)
              + str(size).ljust(10) + "`\n").encode("ascii")
    return b"!<arch>\n" + header + name_bytes + payload + (b"\n" if size % 2 else b"")


class RimeOfflineReleaseAuditTests(unittest.TestCase):
    def test_real_device_ios15_arm64_object_is_accepted(self):
        versions = AUDIT.inspect_archive(archive("example.o", macho()))
        self.assertEqual(versions, [(2, (15, 0, 0))])

    def test_simulator_platform_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "device"):
            AUDIT.inspect_archive(archive("example.o", macho(platform=7)))

    def test_explicit_simulator_slice_accepts_only_simulator_macho(self):
        self.assertEqual(
            AUDIT.inspect_archive(archive("example.o", macho(platform=7)), expected_platform=7),
            [(7, (15, 0, 0))],
        )
        with self.assertRaisesRegex(ValueError, "simulator"):
            AUDIT.inspect_archive(archive("example.o", macho(platform=2)), expected_platform=7)

    def test_ios16_minimum_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "iOS 15"):
            AUDIT.inspect_archive(archive("example.o", macho(minimum=(16, 0, 0))))

    def test_all_nine_release_assets_are_pinned(self):
        self.assertEqual(len(AUDIT.RELEASE_SHA256), 9)
        self.assertIn("librime", AUDIT.RELEASE_SHA256)
        self.assertIn("boost_regex", AUDIT.RELEASE_SHA256)

    def test_offline_sha_pins_match_both_ci_workflows(self):
        for workflow in ("ci.yml", "build-ipa.yml"):
            content = (ROOT / ".github" / "workflows" / workflow).read_text(encoding="utf-8")
            for name, digest in AUDIT.RELEASE_SHA256.items():
                with self.subTest(workflow=workflow, framework=name):
                    self.assertIn(f'{name}) sha="{digest}" ;;', content)


if __name__ == "__main__":
    unittest.main()
