"""Keep all nine upstream LibrimeKit binary dependencies in both release gates.

The pinned v0.1.0 Swift package links four Boost binary targets in addition
to the five RIME-related archives. A partial download cannot prove the iOS
device dependency graph is complete.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
BOOST_SHA256 = {
    "boost_atomic": "4db32b1015c0b2df5b55042e5ec2cced674f8e54e083f7d4aeb1e7db3a6c6925",
    "boost_filesystem": "d22bfd6aa9dd37333710aa5cea19fb065ab270bf2e55551841193bfac5b52af1",
    "boost_regex": "8b13fb6da177e777b76cc9e02d1aed342f922cb3c24f3029e3879f3c2f82fe33",
    "boost_system": "cb3a7cb48499686024923eef902c4327bb021eb8ef25da602a713b9108f56365",
}


class RimeBoostReleaseGateTests(unittest.TestCase):
    def test_both_workflows_download_and_verify_all_four_boost_archives(self):
        for workflow_name in ("ci.yml", "build-ipa.yml"):
            with self.subTest(workflow=workflow_name):
                workflow = (ROOT / ".github/workflows" / workflow_name).read_text(encoding="utf-8")
                for name, digest in BOOST_SHA256.items():
                    self.assertIn(f'{name}) sha="{digest}" ;;', workflow)
                    self.assertIn(name, workflow.split("for f in ", 1)[1].split("; do", 1)[0])
                self.assertLess(workflow.index("shasum -a 256 -c"), workflow.index("unzip -oq"))

    def test_native_device_gate_checks_all_four_boost_archives(self):
        from importlib.util import module_from_spec, spec_from_file_location

        path = ROOT / "scripts/verify_rime_device_slices.py"
        spec = spec_from_file_location("rime_slice_gate", path)
        module = module_from_spec(spec)
        spec.loader.exec_module(module)
        for name in BOOST_SHA256:
            with self.subTest(name=name):
                self.assertIn(name, module.REQUIRED_FRAMEWORKS)

    def test_host_and_keyboard_link_all_four_boost_archives(self):
        project = (ROOT / "Hamster.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
        phases = project.split("/* Begin PBXFrameworksBuildPhase section */", 1)[1]
        phases = phases.split("/* End PBXFrameworksBuildPhase section */", 1)[0]
        for name in BOOST_SHA256:
            with self.subTest(name=name):
                self.assertIn(f"{name}.xcframework */ = {{isa = PBXFileReference;", project)
                # The host and the keyboard extension are separate link targets.
                self.assertEqual(phases.count(f"{name}.xcframework in Frameworks */,"), 2)


if __name__ == "__main__":
    unittest.main()
