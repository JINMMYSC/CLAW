"""Regression: a candidate push must not cancel an in-progress signed release.

The GitHub Actions concurrency group is the public release boundary. A
workflow_dispatch uses the frozen SHA; unrelated push CI must not cancel it.
"""

from pathlib import Path
import unittest


WORKFLOW = Path(__file__).resolve().parents[2] / ".github" / "workflows" / "build-ipa.yml"


class SignedReleaseConcurrencyTests(unittest.TestCase):
    def test_push_and_signed_release_have_separate_concurrency_groups(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        block = text.split("\nconcurrency:\n", 1)[1].split("\njobs:\n", 1)[0]
        self.assertIn(
            "${{ github.event_name }}",
            block,
            "push CI must not share a cancellation group with workflow_dispatch signing",
        )

    def test_manual_signed_release_is_never_cancelled_by_a_new_run(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        block = text.split("\nconcurrency:\n", 1)[1].split("\njobs:\n", 1)[0]
        self.assertIn(
            "cancel-in-progress: ${{ github.event_name != 'workflow_dispatch' }}",
            block,
            "signed release must be allowed to complete its frozen-SHA signing run",
        )


if __name__ == "__main__":
    unittest.main()
