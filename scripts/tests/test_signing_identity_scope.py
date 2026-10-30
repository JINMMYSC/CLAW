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
        self.assertEqual(identity, "ABCDEF123456")
        mocked.assert_called_once_with(
            ["security", "find-identity", "-v", "-p", "codesigning", "ci.keychain"],
            text=True,
        )

    def test_rejects_non_distribution_identity(self):
        output = '  1) ABCDEF123456 "Apple Development: Example (TEAM123)"\n'
        with patch.object(sign_ipa.subprocess, "check_output", return_value=output):
            self.assertIsNone(sign_ipa.find_distribution_identity())

    def test_distribution_identity_must_match_every_embedded_profile(self):
        from hashlib import sha1
        certificate = b"the imported distribution certificate"
        identity = sha1(certificate).hexdigest().upper()
        profiles = [
            {"DeveloperCertificates": [certificate]},
            {"DeveloperCertificates": [certificate]},
            {"DeveloperCertificates": [b"different certificate"]},
        ]
        with patch.object(sign_ipa, "extract_profile", side_effect=profiles):
            with self.assertRaisesRegex(ValueError, "does not include the imported distribution certificate"):
                sign_ipa.require_identity_in_profiles(identity, ["main", "keyboard", "widget"])

    def test_distribution_identity_is_accepted_by_all_profiles(self):
        from hashlib import sha1
        certificate = b"the imported distribution certificate"
        identity = sha1(certificate).hexdigest().upper()
        with patch.object(sign_ipa, "extract_profile", return_value={"DeveloperCertificates": [certificate]}) as decoded:
            sign_ipa.require_identity_in_profiles(identity, ["main", "keyboard", "widget"])
        self.assertEqual(decoded.call_count, 3)

    def test_profile_without_developer_certificates_fails_closed(self):
        with patch.object(sign_ipa, "extract_profile", return_value={}):
            with self.assertRaisesRegex(ValueError, "does not include the imported distribution certificate"):
                sign_ipa.require_identity_in_profiles("A" * 40, ["widget"])
