"""Signed IPA release must be explicitly dispatched for one frozen commit."""

from pathlib import Path
import re
import sys
import unittest


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))


class SignedIPAFrozenSHAGateTests(unittest.TestCase):
    def test_sign_job_requires_explicit_dispatch_and_frozen_sha(self):
        workflow = (ROOT / ".github/workflows/build-ipa.yml").read_text(encoding="utf-8")
        self.assertRegex(workflow, r"(?m)^  workflow_dispatch:\s*\n    inputs:\s*\n      frozen_sha:")
        self.assertRegex(workflow, r"(?m)^        required: true\s*$")
        sign = workflow.split("\n  sign:\n", 1)[1]
        condition = sign.split("    runs-on:", 1)[0]
        self.assertIn("github.event_name == 'workflow_dispatch'", condition)
        self.assertNotIn("refs/heads/main", condition)
        self.assertNotIn("startsWith", condition)
        self.assertNotIn("github.head_ref", condition)
        self.assertIn("python3 scripts/verify_release_sha.py", sign)
        self.assertLess(sign.index("Verify frozen release source SHA"),
                        sign.index("Check signing secrets"))

    def test_sha_gate_accepts_only_same_valid_commit(self):
        from verify_release_sha import verify_frozen_release_sha

        sha = "a" * 40
        verify_frozen_release_sha(sha, sha, sha)
        for frozen, event, checkout in (
            ("", sha, sha),
            ("abc", sha, sha),
            ("g" * 40, sha, sha),
            (sha, "b" * 40, sha),
            (sha, sha, "c" * 40),
        ):
            with self.subTest(frozen=frozen, event=event, checkout=checkout):
                with self.assertRaises(ValueError):
                    verify_frozen_release_sha(frozen, event, checkout)


if __name__ == "__main__":
    unittest.main()
