"""Guard the RIME release assets used by the macOS CI device-slice gate."""

import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
RELEASE_CHECKSUMS = {
    "librime": "869ad448db92be5855e239f6f61a87d87e84974a4668509a3cbe4d766f294a54",
    "libleveldb": "147cd30ee8763ccea573ca9778a5b2ed420c3adf5c91fe1b171fd1799422d103",
    "libmarisa": "cf66bb44fe11d5bc9ce39d61212e5f269bc4cc5045250bc79d62e34205bfc3bb",
    "libopencc": "715f2a323cc3f2b5aaeb3158533fc52ede265dbb54b07ea82f586c68604fe914",
    "libyaml-cpp": "4c277cc6fa3f7330200f16d4454cd77c43c495714465bcb0d506d07d5fcdcc4c",
}


class RimeReleaseChecksumTests(unittest.TestCase):
    def test_ci_pins_all_five_release_assets_before_extraction(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
        self.assertIn("zhanggenlove/LibrimeKit/releases/download/v0.1.0", workflow)
        for name, digest in RELEASE_CHECKSUMS.items():
            with self.subTest(name=name):
                self.assertIn(f'{name}) sha="{digest}" ;;', workflow)
        self.assertIn('*) echo "Unpinned RIME asset: $f" >&2; exit 1 ;;', workflow)
        self.assertIn("shasum -a 256 -c", workflow)
        self.assertLess(workflow.index("shasum -a 256 -c"), workflow.index("unzip -oq"))


if __name__ == "__main__":
    unittest.main()
