"""Regression tests for isolated, automatically removed signing keychains.

The production signer must never replace the user's default/search keychains.
These tests mock macOS security commands; they do not claim a real P12 was used.
"""
import pathlib
import sys
import unittest
from unittest import mock
from types import SimpleNamespace

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import sign_ipa


class SigningKeychainIsolationTests(unittest.TestCase):
    def test_signing_keychain_preserves_user_keychain_settings_and_cleans_up(self):
        with (
            mock.patch.object(sign_ipa.subprocess, "run",
                              return_value=SimpleNamespace(returncode=0)) as run,
            mock.patch.object(sign_ipa, "run_sensitive_command") as import_p12,
            mock.patch.object(sign_ipa, "find_distribution_identity",
                              return_value="A" * 40),
        ):
            with sign_ipa.signing_keychain("sign.p12", "secret") as (path, identity):
                self.assertTrue(path.endswith("claw-signing.keychain-db"))
                self.assertEqual(identity, "A" * 40)
            commands = [call.args[0] for call in run.call_args_list]
            self.assertTrue(any(c[:2] == ["security", "delete-keychain"]
                                and c[2] == path for c in commands))
            self.assertFalse(any(c[:2] in (
                ["security", "list-keychains"],
                ["security", "default-keychain"],
            ) for c in commands))
            import_p12.assert_called_once()

    def test_signing_keychain_is_deleted_even_when_no_identity_is_found(self):
        with (
            mock.patch.object(sign_ipa.subprocess, "run",
                              return_value=SimpleNamespace(returncode=0)) as run,
            mock.patch.object(sign_ipa, "run_sensitive_command"),
            mock.patch.object(sign_ipa, "find_distribution_identity",
                              return_value=None),
        ):
            with self.assertRaisesRegex(ValueError, "Distribution identity"):
                with sign_ipa.signing_keychain("sign.p12", "secret"):
                    pass
            commands = [call.args[0] for call in run.call_args_list]
            self.assertTrue(any(c[:2] == ["security", "delete-keychain"]
                                for c in commands))


if __name__ == "__main__":
    unittest.main()
