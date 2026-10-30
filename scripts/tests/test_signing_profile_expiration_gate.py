"""Reject expired provisioning profiles before creating an installable IPA."""

from datetime import datetime, timezone
import pathlib
import plistlib
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock


sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import sign_ipa
import verify_signed_ipa


def profile(expiration=None, devices=None, all_devices=False):
    data = {"Entitlements": {"application-identifier": "TEAM.app.lgm.7517"}}
    if devices is not None:
        data["ProvisionedDevices"] = devices
    if all_devices:
        data["ProvisionsAllDevices"] = True
    if expiration is not None:
        data["ExpirationDate"] = expiration
    return plistlib.dumps(data)


class SigningProfileExpirationGateTests(unittest.TestCase):
    def test_signer_rejects_expired_profile(self):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / "expired.mobileprovision"
            path.write_bytes(profile(datetime(2020, 1, 1)))
            with mock.patch.object(
                verify_signed_ipa.subprocess, "run",
                return_value=SimpleNamespace(stdout=path.read_bytes()),
            ) as decoder:
                with self.assertRaisesRegex(ValueError, "expired"):
                    sign_ipa.extract_entitlements(str(path))
                decoder.assert_called_once_with(
                    ["security", "cms", "-D", "-i", str(path)],
                    check=True, capture_output=True,
                )

    def test_verifier_rejects_expired_profile(self):
        result = SimpleNamespace(stdout=profile(datetime(2020, 1, 1)))
        with mock.patch.object(verify_signed_ipa.subprocess, "run", return_value=result):
            with self.assertRaisesRegex(ValueError, "expired"):
                verify_signed_ipa.extract_profile_entitlements("expired.mobileprovision")

    def test_missing_expiration_fails_closed(self):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / "missing.mobileprovision"
            path.write_bytes(profile())
            with mock.patch.object(
                verify_signed_ipa.subprocess, "run",
                return_value=SimpleNamespace(stdout=path.read_bytes()),
            ) as decoder:
                with self.assertRaisesRegex(ValueError, "ExpirationDate"):
                    sign_ipa.extract_entitlements(str(path))
                decoder.assert_called_once_with(
                    ["security", "cms", "-D", "-i", str(path)],
                    check=True, capture_output=True,
                )

    def test_valid_profile_is_accepted(self):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / "valid.mobileprovision"
            path.write_bytes(profile(datetime(2099, 1, 1), devices=["TEST-DEVICE"]))
            with mock.patch.object(
                verify_signed_ipa.subprocess, "run",
                return_value=SimpleNamespace(stdout=path.read_bytes()),
            ) as decoder:
                self.assertEqual(
                    sign_ipa.extract_entitlements(str(path))["application-identifier"],
                    "TEAM.app.lgm.7517",
                )
                decoder.assert_called_once_with(
                    ["security", "cms", "-D", "-i", str(path)],
                    check=True, capture_output=True,
                )

    def test_app_store_profile_is_rejected_for_direct_iphone_install(self):
        result = SimpleNamespace(stdout=profile(datetime(2099, 1, 1)))
        with mock.patch.object(verify_signed_ipa.subprocess, "run", return_value=result):
            with self.assertRaisesRegex(ValueError, "not device-installable"):
                sign_ipa.extract_entitlements("app-store.mobileprovision")

    def test_empty_ad_hoc_device_list_is_rejected(self):
        result = SimpleNamespace(stdout=profile(datetime(2099, 1, 1), devices=[]))
        with mock.patch.object(verify_signed_ipa.subprocess, "run", return_value=result):
            with self.assertRaisesRegex(ValueError, "not device-installable"):
                sign_ipa.extract_entitlements("empty-ad-hoc.mobileprovision")

    def test_enterprise_profile_can_provision_all_devices(self):
        result = SimpleNamespace(stdout=profile(datetime(2099, 1, 1), all_devices=True))
        with mock.patch.object(verify_signed_ipa.subprocess, "run", return_value=result):
            self.assertEqual(
                sign_ipa.extract_entitlements("enterprise.mobileprovision")[
                    "application-identifier"
                ],
                "TEAM.app.lgm.7517",
            )


    def test_common_device_across_all_three_adhoc_profiles(self):
        profiles = [
            ("Host", {"Entitlements": {"com.apple.developer.team-identifier": "TEAM"},
                      "ProvisionedDevices": ["IPHONE-A", "IPHONE-B"]}),
            ("Keyboard", {"Entitlements": {"com.apple.developer.team-identifier": "TEAM"},
                          "ProvisionedDevices": ["IPHONE-B", "IPHONE-C"]}),
            ("Widget", {"Entitlements": {"com.apple.developer.team-identifier": "TEAM"},
                        "ProvisionedDevices": ["IPHONE-B"]}),
        ]
        verify_signed_ipa.validate_common_installable_devices(profiles)

    def test_disjoint_adhoc_profiles_cannot_install_on_one_iphone(self):
        profiles = [
            ("Host", {"Entitlements": {"com.apple.developer.team-identifier": "TEAM"},
                      "ProvisionedDevices": ["IPHONE-A"]}),
            ("Keyboard", {"Entitlements": {"com.apple.developer.team-identifier": "TEAM"},
                          "ProvisionedDevices": ["IPHONE-B"]}),
            ("Widget", {"Entitlements": {"com.apple.developer.team-identifier": "TEAM"},
                        "ProvisionedDevices": ["IPHONE-A", "IPHONE-B"]}),
        ]
        with self.assertRaisesRegex(ValueError, "no common provisioned device"):
            verify_signed_ipa.validate_common_installable_devices(profiles)

    def test_enterprise_profile_does_not_restrict_common_adhoc_devices(self):
        profiles = [
            ("Host", {"Entitlements": {"com.apple.developer.team-identifier": "TEAM"},
                      "ProvisionsAllDevices": True}),
            ("Keyboard", {"Entitlements": {"com.apple.developer.team-identifier": "TEAM"},
                          "ProvisionedDevices": ["IPHONE-A"]}),
            ("Widget", {"Entitlements": {"com.apple.developer.team-identifier": "TEAM"},
                        "ProvisionedDevices": ["IPHONE-A", "IPHONE-B"]}),
        ]
        verify_signed_ipa.validate_common_installable_devices(profiles)

    def test_mismatched_signing_teams_fail_before_xcode_build(self):
        profiles = [
            ("Host", {"Entitlements": {"com.apple.developer.team-identifier": "TEAM-A"},
                      "ProvisionedDevices": ["IPHONE-A"]}),
            ("Keyboard", {"Entitlements": {"com.apple.developer.team-identifier": "TEAM-B"},
                          "ProvisionedDevices": ["IPHONE-A"]}),
            ("Widget", {"Entitlements": {"com.apple.developer.team-identifier": "TEAM-A"},
                        "ProvisionedDevices": ["IPHONE-A"]}),
        ]
        with self.assertRaisesRegex(ValueError, "team mismatch"):
            verify_signed_ipa.validate_common_installable_devices(profiles)


if __name__ == "__main__":
    unittest.main()
