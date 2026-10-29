"""Verify that IPA signing only selects identities from its imported keychain."""

import sys
from pathlib import Path
from unittest import TestCase
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import sign_ipa


class SigningIdentityScopeTests(TestCase):
    def test_uses_isolated_imported_keychain(self):
        output = '  1) ABCDEF123456 "Apple Distribution: Example (TEAM123)"\n     1 valid identities found\n'
        with patch.object(sign_ipa.subprocess, "check_output", return_value=output) as mocked:
            identity = sign_ipa.find_distribution_identity()
        self.assertEqual(identity, "Apple Distribution: Example (TEAM123)")
        mocked.assert_called_once_with(
            ["security", "find-identity", "-v", "-p", "codesigning", "ci.keychain"],
            text=True,
        )

    def test_rejects_non_distribution_identity(self):
        output = '  1) ABCDEF123456 "Apple Development: Example (TEAM123)"\n'
        with patch.object(sign_ipa.subprocess, "check_output", return_value=output):
            self.assertIsNone(sign_ipa.find_distribution_identity())
