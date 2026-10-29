"""The required CLAW iCloud backup capability must survive signing."""

import pathlib
import sys
import unittest


sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import sign_ipa
import verify_signed_ipa


CONTAINER = "iCloud.dev.fuxiao.app.hamsterapp"


def entitlements(services):
    return {
        "application-identifier": "TEAM123.app.lgm.7517",
        "com.apple.developer.team-identifier": "TEAM123",
        "com.apple.security.application-groups": ["group.7518554"],
        "com.apple.developer.icloud-container-identifiers": [CONTAINER],
        "com.apple.developer.icloud-services": list(services),
    }


class SignedIPACloudDocumentsGateTests(unittest.TestCase):
    def test_signing_rejects_profile_with_container_but_no_cloud_documents(self):
        with self.assertRaisesRegex(ValueError, "CloudDocuments"):
            sign_ipa.validate_profile(
                "app.lgm.7517",
                entitlements(["CloudKit"]),
                required_icloud_containers=[CONTAINER],
            )

    def test_verifier_rejects_signed_bundle_missing_cloud_documents(self):
        with self.assertRaisesRegex(ValueError, "CloudDocuments"):
            verify_signed_ipa.validate_bundle_entitlements(
                "app.lgm.7517",
                entitlements(["CloudDocuments", "CloudKit"]),
                entitlements(["CloudKit"]),
                required_icloud_containers=[CONTAINER],
            )

    def test_valid_cloud_documents_profile_and_signature_pass(self):
        valid = entitlements(["CloudDocuments", "CloudKit"])
        verify_signed_ipa.validate_bundle_entitlements(
            "app.lgm.7517", valid, valid,
            required_icloud_containers=[CONTAINER],
        )


if __name__ == "__main__":
    unittest.main()
