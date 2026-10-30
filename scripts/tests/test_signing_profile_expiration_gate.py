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


if __name__ == "__main__":
    unittest.main()
