"""Release-blocking workflow checks; native CI still must execute on macOS."""

import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github" / "workflows"
SPEC = importlib.util.spec_from_file_location(
    "rime_archive_audit", ROOT / "scripts" / "audit_rime_release_archives.py"
)
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


class IPAReleasePipelineGates(unittest.TestCase):
    def test_startup_smoke_downloads_all_nine_pinned_rime_libraries(self):
        workflow = (WORKFLOWS / "startup-smoke.yml").read_text(encoding="utf-8")
        for name, sha in AUDIT.RELEASE_SHA256.items():
            with self.subTest(name=name):
                self.assertIn(f'{name}) sha="{sha}" ;;', workflow)
        self.assertIn("shasum -a 256 -c -", workflow)
        self.assertIn("--retry-all-errors", workflow)
        self.assertLess(workflow.index("shasum -a 256 -c -"), workflow.index("name: Build simulator app"))

    def test_signed_dispatch_rejects_wrong_sha_before_download_or_build(self):
        workflow = (WORKFLOWS / "build-ipa.yml").read_text(encoding="utf-8")
        early = workflow.index("name: Verify frozen release source SHA before build")
        download = workflow.index("name: Download Rime frameworks")
        self.assertLess(early, download)
        self.assertIn("python3 scripts/verify_release_sha.py", workflow[early:download])

    def test_macos_signing_uses_bsd_base64_decoder(self):
        workflow = (WORKFLOWS / "build-ipa.yml").read_text(encoding="utf-8")
        signing = workflow[workflow.index("name: Install signing assets"):]
        self.assertNotIn("base64 --decode", signing)
        self.assertGreaterEqual(signing.count("base64 -D"), 3)

    def test_signed_dispatch_checks_signing_secrets_before_expensive_build(self):
        workflow = (WORKFLOWS / "build-ipa.yml").read_text(encoding="utf-8")
        early = workflow.index("name: Check signing prerequisites before build")
        download = workflow.index("name: Download Rime frameworks")
        self.assertLess(early, download)
        section = workflow[early:download]
        self.assertIn("github.event_name == 'workflow_dispatch'", section)
        for name in (
            "P12_BASE64", "P12_PASSWORD", "PROFILE_MAIN_B64",
            "PROFILE_EXT_B64", "PROFILE_WIDGET_B64",
        ):
            with self.subTest(name=name):
                self.assertIn(f"secrets.{name}", section)


if __name__ == "__main__":
    unittest.main()
