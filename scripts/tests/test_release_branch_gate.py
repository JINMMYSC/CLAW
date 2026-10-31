"""Release signing must be limited to the single audited candidate branch."""
import os
import unittest
from unittest import mock

from scripts.verify_release_sha import main

SHA = "a" * 40
CANDIDATE = "refs/heads/feature/claw-ipa-build-candidate-20261030"


class ReleaseBranchGateTests(unittest.TestCase):
    def run_gate(self, github_ref):
        with mock.patch.dict(os.environ, {"GITHUB_REF": github_ref}):
            with mock.patch(
                "scripts.verify_release_sha.subprocess.run",
                return_value=mock.Mock(returncode=0, stdout=SHA + "\n"),
            ):
                return main(["--frozen-sha", SHA, "--github-sha", SHA])

    def test_main_branch_cannot_be_signed_even_with_matching_sha(self):
        self.assertEqual(self.run_gate("refs/heads/main"), 1)

    def test_other_feature_branch_cannot_be_signed(self):
        self.assertEqual(self.run_gate("refs/heads/feature/unreviewed"), 1)

    def test_tag_cannot_be_signed(self):
        self.assertEqual(self.run_gate("refs/tags/v1"), 1)

    def test_approved_candidate_branch_can_be_signed(self):
        self.assertEqual(self.run_gate(CANDIDATE), 0)


if __name__ == "__main__":
    unittest.main()
