"""Ensure a wildcard provisioning profile produces concrete signed bundle IDs."""

import sys
from pathlib import Path
from unittest import TestCase

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from sign_ipa import validate_profile
from verify_signed_ipa import DEFAULT_APP_GROUP, DEFAULT_ICLOUD_CONTAINER


class ConcreteApplicationIdentifierTests(TestCase):
    def _profile(self):
        return {
            "application-identifier": "TEAM123.app.lgm.7517.*",
            "com.apple.developer.team-identifier": "TEAM123",
            "com.apple.security.application-groups": [DEFAULT_APP_GROUP],
            "com.apple.developer.icloud-container-identifiers": [DEFAULT_ICLOUD_CONTAINER],
            "com.apple.developer.icloud-services": ["CloudDocuments"],
        }

    def test_host_signing_entitlements_use_concrete_id(self):
        profile = self._profile()
        result = validate_profile(
            "app.lgm.7517",
            profile,
            required_icloud_containers=[DEFAULT_ICLOUD_CONTAINER],
        )
        self.assertEqual(result["application-identifier"], "TEAM123.app.lgm.7517")
        self.assertEqual(profile["application-identifier"], "TEAM123.app.lgm.7517.*")

    def test_keyboard_and_widget_have_distinct_concrete_ids(self):
        profile = self._profile()
        for bundle in ("app.lgm.7517.123", "app.lgm.7517.widget"):
            with self.subTest(bundle=bundle):
                result = validate_profile(bundle, profile)
                self.assertEqual(result["application-identifier"], "TEAM123." + bundle)
