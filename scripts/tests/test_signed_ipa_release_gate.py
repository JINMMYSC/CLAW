"""A signed IPA must be downstream of native and RIME release checks."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class SignedIPAReleaseGateTests(unittest.TestCase):
    def test_signed_release_requires_pinned_rime_and_native_tests(self):
        workflow = (ROOT / ".github/workflows/build-ipa.yml").read_text(encoding="utf-8")
        ci = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")

        self.assertIn("needs: build", workflow)
        self.assertIn("python3 -m unittest discover -s scripts/tests -p 'test_*.py'", workflow)
        self.assertIn("python3 scripts/verify_rime_device_slices.py --frameworks Frameworks", workflow)
        self.assertIn("xcodebuild test", workflow)
        self.assertIn("-scheme HamsterKit", workflow)
        self.assertIn("-scheme HamsteriOS", workflow)

        for name in ("librime", "libleveldb", "libmarisa", "libopencc", "libyaml-cpp"):
            ci_pin = next(line.strip() for line in ci.splitlines()
                          if line.strip().startswith(f'{name}) sha="'))
            self.assertIn(ci_pin, workflow, f"{name} release SHA must match the CI pin")

        ordered = [
            "shasum -a 256 -c",
            "unzip -oq",
            "python3 scripts/verify_rime_device_slices.py --frameworks Frameworks",
            "python3 -m unittest discover -s scripts/tests -p 'test_*.py'",
            "-scheme HamsterKit",
            "-scheme HamsteriOS",
            "name: Build device .app (unsigned, Release)",
            "name: Package .ipa (unsigned)",
        ]
        for before, after in zip(ordered, ordered[1:]):
            self.assertLess(workflow.index(before), workflow.index(after),
                            f"Release gate order: {before} must precede {after}")


if __name__ == "__main__":
    unittest.main()
