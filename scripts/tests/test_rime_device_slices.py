"""Native device-slice gate: metadata alone must never bless simulator binaries."""

import pathlib
import plistlib
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))


class RimeDeviceSliceTests(unittest.TestCase):
    def make_frameworks(self, root, *, variant=None, binary=True):
        from verify_rime_device_slices import REQUIRED_FRAMEWORKS

        for name in REQUIRED_FRAMEWORKS:
            framework = root / (name + ".xcframework")
            folder = framework / "ios-arm64"
            folder.mkdir(parents=True)
            entry = {
                "LibraryIdentifier": "ios-arm64",
                "LibraryPath": name + ".a",
                "SupportedArchitectures": ["arm64"],
                "SupportedPlatform": "ios",
            }
            if variant is not None:
                entry["SupportedPlatformVariant"] = variant
            (framework / "Info.plist").write_bytes(
                plistlib.dumps({"AvailableLibraries": [entry]})
            )
            if binary:
                (folder / (name + ".a")).write_bytes(b"fake-archive")

    @staticmethod
    def fake_tools(platform, minos="15.0"):
        calls = []

        def run(args):
            calls.append(args)
            if "lipo" in args:
                return subprocess.CompletedProcess(args, 0, "", "")
            if "ar" in args:
                return subprocess.CompletedProcess(args, 0, "test.o\n", "")
            return subprocess.CompletedProcess(
                args, 0,
                "Archive : lib.a\nlib.a(test.o):\n"
                "Load command 1\n cmd LC_BUILD_VERSION\n cmdsize 32\n"
                f" platform {platform}\n minos {minos}\n", "",
            )

        return run, calls

    def test_accepts_all_five_device_archives_only_after_native_checks(self):
        from verify_rime_device_slices import REQUIRED_FRAMEWORKS, verify_frameworks

        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.make_frameworks(root)
            runner, calls = self.fake_tools(2)
            verify_frameworks(root, run_command=runner)
            self.assertEqual(len(calls), len(REQUIRED_FRAMEWORKS) * 3)

    def test_rejects_simulator_only_xcframework_metadata(self):
        from verify_rime_device_slices import verify_frameworks

        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.make_frameworks(root, variant="simulator")
            runner, _ = self.fake_tools(2)
            with self.assertRaisesRegex(ValueError, "device.*slice"):
                verify_frameworks(root, run_command=runner)

    def test_rejects_simulator_macho_even_if_plist_claims_device(self):
        from verify_rime_device_slices import verify_frameworks

        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.make_frameworks(root)
            runner, _ = self.fake_tools(7)
            with self.assertRaisesRegex(ValueError, "Mach-O.*platform"):
                verify_frameworks(root, run_command=runner)

    def test_rejects_device_archive_requiring_ios_16(self):
        from verify_rime_device_slices import verify_frameworks

        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.make_frameworks(root)
            runner, _ = self.fake_tools(2, minos="16.0")
            with self.assertRaisesRegex(ValueError, "iOS 15.*deployment"):
                verify_frameworks(root, run_command=runner)

    def test_rejects_archive_when_one_object_lacks_platform_metadata(self):
        from verify_rime_device_slices import verify_frameworks

        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.make_frameworks(root)

            def run(args):
                if "lipo" in args:
                    return subprocess.CompletedProcess(args, 0, "", "")
                if "ar" in args:
                    return subprocess.CompletedProcess(args, 0, "first.o\nsecond.o\n", "")
                output = (
                    "Archive : lib.a\n"
                    "lib.a(first.o):\n"
                    "Load command 0\n cmd LC_BUILD_VERSION\n"
                    " platform 2\n minos 15.0\n"
                    "lib.a(second.o):\n"
                    "Load command 0\n cmd LC_SEGMENT_64\n"
                )
                return subprocess.CompletedProcess(args, 0, output, "")

            with self.assertRaisesRegex(ValueError, "missing.*LC_BUILD_VERSION"):
                verify_frameworks(root, run_command=run)

    def test_accepts_archive_with_two_verified_device_objects(self):
        from verify_rime_device_slices import REQUIRED_FRAMEWORKS, verify_frameworks

        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.make_frameworks(root)

            def run(args):
                if "lipo" in args:
                    return subprocess.CompletedProcess(args, 0, "", "")
                if "ar" in args:
                    return subprocess.CompletedProcess(args, 0, "first.o\nsecond.o\n", "")
                output = (
                    "Archive : lib.a\n"
                    "lib.a(first.o):\nLoad command 0\n"
                    " cmd LC_BUILD_VERSION\n platform 2\n minos 15.0\n"
                    "lib.a(second.o):\nLoad command 0\n"
                    " cmd LC_BUILD_VERSION\n platform 2\n minos 14.0\n"
                )
                return subprocess.CompletedProcess(args, 0, output, "")

            verify_frameworks(root, run_command=run)
            self.assertEqual(len(REQUIRED_FRAMEWORKS), 9)

    def test_rejects_archive_when_otool_does_not_identify_members(self):
        from verify_rime_device_slices import verify_frameworks

        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.make_frameworks(root)

            def run(args):
                if "lipo" in args:
                    return subprocess.CompletedProcess(args, 0, "", "")
                if "ar" in args:
                    return subprocess.CompletedProcess(args, 0, "test.o\n", "")
                return subprocess.CompletedProcess(
                    args, 0,
                    "Load command 0\n cmd LC_BUILD_VERSION\n"
                    " platform 2\n minos 15.0\n", "",
                )

            with self.assertRaisesRegex(ValueError, "archive member metadata missing"):
                verify_frameworks(root, run_command=run)

    def test_rejects_archive_member_omitted_from_otool_output(self):
        """A clean otool report cannot bless an uninspected archive member."""
        from verify_rime_device_slices import verify_frameworks

        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.make_frameworks(root)

            def run(args):
                if "lipo" in args:
                    return subprocess.CompletedProcess(args, 0, "", "")
                if "ar" in args:
                    return subprocess.CompletedProcess(args, 0, "first.o\nsecond.o\n", "")
                return subprocess.CompletedProcess(
                    args, 0,
                    "Archive : lib.a\nlib.a(first.o):\n"
                    "Load command 0\n cmd LC_BUILD_VERSION\n"
                    " platform 2\n minos 15.0\n", "",
                )

            with self.assertRaisesRegex(ValueError, "archive inventory mismatch"):
                verify_frameworks(root, run_command=run)

    def test_rejects_missing_device_archive(self):
        from verify_rime_device_slices import verify_frameworks

        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.make_frameworks(root, binary=False)
            runner, _ = self.fake_tools(2)
            with self.assertRaisesRegex(ValueError, "missing.*binary"):
                verify_frameworks(root, run_command=runner)

    def test_ci_runs_device_slice_gate_before_archive(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
        invocation = "python3 scripts/verify_rime_device_slices.py --frameworks Frameworks"
        self.assertIn(invocation, workflow)
        self.assertLess(workflow.index(invocation), workflow.index("name: Compile"))


if __name__ == "__main__":
    unittest.main()
