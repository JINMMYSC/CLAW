import importlib.util
import pathlib
import sys
import unittest


SCRIPTS_DIR = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS_DIR))

import sign_ipa


def load_verifier():
    path = SCRIPTS_DIR / "verify_signed_ipa.py"
    if not path.exists():
        return None
    spec = importlib.util.spec_from_file_location("verify_signed_ipa", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SigningProfileTests(unittest.TestCase):
    def test_rejects_profile_bundle_identifier_mismatch(self):
        verifier = load_verifier()
        self.assertIsNotNone(verifier, "signed IPA verifier must exist")
        validate = getattr(verifier, "validate_bundle_entitlements", None)
        self.assertTrue(callable(validate), "bundle entitlement validator must exist")

        with self.assertRaisesRegex(ValueError, "does not match bundle identifier"):
            validate(
                bundle_identifier="app.lgm.7517.123",
                profile_entitlements={
                    "application-identifier": "TEAM123.app.lgm.other",
                    "com.apple.developer.team-identifier": "TEAM123",
                },
                signed_entitlements={
                    "application-identifier": "TEAM123.app.lgm.7517.123",
                    "com.apple.developer.team-identifier": "TEAM123",
                },
            )

    def test_rejects_missing_required_icloud_container(self):
        verifier = load_verifier()
        self.assertIsNotNone(verifier, "signed IPA verifier must exist")
        validate = getattr(verifier, "validate_bundle_entitlements", None)
        self.assertTrue(callable(validate), "bundle entitlement validator must exist")

        with self.assertRaisesRegex(ValueError, "missing required iCloud container"):
            validate(
                bundle_identifier="app.lgm.7517",
                profile_entitlements={
                    "application-identifier": "TEAM123.app.lgm.7517",
                    "com.apple.developer.team-identifier": "TEAM123",
                    "com.apple.developer.icloud-container-identifiers": [],
                },
                signed_entitlements={
                    "application-identifier": "TEAM123.app.lgm.7517",
                    "com.apple.developer.team-identifier": "TEAM123",
                    "com.apple.developer.icloud-container-identifiers": [],
                },
                required_icloud_containers=["iCloud.dev.fuxiao.app.hamsterapp"],
            )

    def test_selects_different_extension_profiles_by_bundle_identifier(self):
        select = getattr(sign_ipa, "select_profile_for_bundle", None)
        self.assertTrue(callable(select), "per-bundle profile selector must exist")

        mappings = {
            "app.lgm.7517.123": "keyboard.mobileprovision",
            "app.lgm.7517.widget": "widget.mobileprovision",
        }
        self.assertEqual(
            select("app.lgm.7517.123", mappings, "legacy.mobileprovision", None),
            "keyboard.mobileprovision",
        )
        self.assertEqual(
            select("app.lgm.7517.widget", mappings, "legacy.mobileprovision", None),
            "widget.mobileprovision",
        )


if __name__ == "__main__":
    unittest.main()
