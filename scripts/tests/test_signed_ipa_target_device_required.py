import pathlib
import unittest

WORKFLOW = pathlib.Path(__file__).resolve().parents[2] / ".github" / "workflows" / "build-ipa.yml"


class SignedIPATargetDeviceRequiredTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = WORKFLOW.read_text(encoding="utf-8")

    def step(self, name):
        marker = "      - name: " + name
        start = self.workflow.index(marker)
        end = self.workflow.find("      - name: ", start + len(marker))
        return self.workflow[start:end if end >= 0 else None]

    def test_manual_build_fails_before_xcode_without_target_device(self):
        step = self.step("Check signing prerequisites before build")
        self.assertIn("CLAW_TARGET_DEVICE_UDID: ${{ secrets.CLAW_TARGET_DEVICE_UDID }}", step)
        self.assertIn("missing+=(CLAW_TARGET_DEVICE_UDID)", step)

    def test_profile_preflight_requires_exact_target_device(self):
        step = self.step("Validate installable Host/Keyboard/Widget profiles before expensive native build")
        self.assertIn('target_device_udid=os.environ["CLAW_TARGET_DEVICE_UDID"]', step)
        self.assertNotIn("optional device secret absent", step)

    def test_sign_job_rechecks_target_device(self):
        step = self.step("Check signing secrets")
        self.assertIn("CLAW_TARGET_DEVICE_UDID: ${{ secrets.CLAW_TARGET_DEVICE_UDID }}", step)
        self.assertIn("missing+=(CLAW_TARGET_DEVICE_UDID)", step)


if __name__ == "__main__":
    unittest.main()
