"""A final CLAW IPA must not silently drop its iCloud capability."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class SignedIPAICloudRequiredGateTests(unittest.TestCase):
    def test_release_signing_and_verification_require_icloud(self):
        workflow = (ROOT / ".github/workflows/build-ipa.yml").read_text(encoding="utf-8")
        sign_step = workflow.split("- name: Sign ipa (app + keyboard extension)", 1)[1]
        sign_step = sign_step.split("- name: Verify signed ipa bundles and entitlements", 1)[0]
        verify_step = workflow.split("- name: Verify signed ipa bundles and entitlements", 1)[1]
        verify_step = verify_step.split("- name: Verify embedded source SHA", 1)[0]

        self.assertIn("python3 scripts/sign_ipa.py", sign_step)
        self.assertIn("python3 scripts/verify_signed_ipa.py", verify_step)
        self.assertNotIn("--allow-missing-icloud", sign_step)
        self.assertNotIn("--allow-missing-icloud", verify_step)


if __name__ == "__main__":
    unittest.main()
