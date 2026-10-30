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



class TargetDeviceSigningGateTests(unittest.TestCase):
    def setUp(self):
        self.profiles = [
            ("Host", {"Entitlements": {"com.apple.developer.team-identifier": "TEAM"},
                      "ProvisionedDevices": ["IPHONE-A", "IPHONE-B"]}),
            ("Keyboard", {"Entitlements": {"com.apple.developer.team-identifier": "TEAM"},
                          "ProvisionedDevices": ["IPHONE-B"]}),
            ("Widget", {"Entitlements": {"com.apple.developer.team-identifier": "TEAM"},
                        "ProvisionedDevices": ["IPHONE-B"]}),
        ]

    def test_rejects_target_not_in_every_profile_without_disclosing_udid(self):
        with self.assertRaises(ValueError) as caught:
            verify_signed_ipa.validate_common_installable_devices(
                self.profiles, target_device_udid="IPHONE-A"
            )
        self.assertIn("target device", str(caught.exception))
        self.assertNotIn("IPHONE-A", str(caught.exception))

    def test_accepts_target_in_all_profiles_case_insensitively(self):
        verify_signed_ipa.validate_common_installable_devices(
            self.profiles, target_device_udid="iphone-b"
        )

    def test_enterprise_profile_allows_target_when_other_profiles_match(self):
        profiles = list(self.profiles)
        profiles[0] = ("Host", {"Entitlements": {"com.apple.developer.team-identifier": "TEAM"},
                                "ProvisionsAllDevices": True})
        verify_signed_ipa.validate_common_installable_devices(
            profiles, target_device_udid="IPHONE-B"
        )

    def test_rejects_empty_target_when_target_check_is_requested(self):
        with self.assertRaisesRegex(ValueError, "target device"):
            verify_signed_ipa.validate_common_installable_devices(
                self.profiles, target_device_udid=" "
            )



class SigningAssetPreflightTests(unittest.TestCase):
    """P12/profile mismatch must fail before downloading RIME or building Xcode."""

    def test_missing_widget_profile_is_rejected_before_certificate_import(self):
        with self.assertRaisesRegex(ValueError, "Widget"):
            sign_ipa.validate_signing_asset_set(
                "A" * 40, "host.mobileprovision",
                {"app.lgm.7517.123": "keyboard.mobileprovision"},
                "app.lgm.7517",
            )

    def test_all_three_profiles_are_checked_against_imported_p12(self):
        mappings = {
            "app.lgm.7517.123": "keyboard.mobileprovision",
            "app.lgm.7517.widget": "widget.mobileprovision",
        }
        with (
            mock.patch.object(sign_ipa, "require_identity_in_profiles") as cert_check,
            mock.patch.object(sign_ipa, "extract_profile") as decode,
            mock.patch.object(sign_ipa, "extract_entitlements") as entitlements,
            mock.patch.object(sign_ipa, "validate_profile") as entitlement_check,
            mock.patch.object(sign_ipa, "validate_common_installable_devices") as device_check,
        ):
            decode.return_value = {"ProvisionsAllDevices": True}
            entitlements.return_value = {}
            sign_ipa.validate_signing_asset_set(
                "A" * 40, "host.mobileprovision", mappings, "app.lgm.7517",
                target_device_udid="IPHONE-TEST",
            )
            cert_check.assert_called_once_with(
                "A" * 40,
                ["host.mobileprovision", "keyboard.mobileprovision",
                 "widget.mobileprovision"],
            )
            self.assertEqual(entitlement_check.call_count, 3)
            self.assertEqual(device_check.call_args.kwargs["target_device_udid"],
                             "IPHONE-TEST")

    def test_mismatched_p12_certificate_aborts_preflight(self):
        mappings = {
            "app.lgm.7517.123": "keyboard.mobileprovision",
            "app.lgm.7517.widget": "widget.mobileprovision",
        }
        with mock.patch.object(
            sign_ipa, "require_identity_in_profiles",
            side_effect=ValueError("profile does not include imported certificate"),
        ):
            with self.assertRaisesRegex(ValueError, "certificate"):
                sign_ipa.validate_signing_asset_set(
                    "A" * 40, "host.mobileprovision", mappings, "app.lgm.7517",
                )


if __name__ == "__main__":
    unittest.main()
