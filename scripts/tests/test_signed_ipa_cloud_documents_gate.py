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
        "com.apple.developer.ubiquity-container-identifiers": [CONTAINER],
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

    def test_signing_rejects_profile_with_documents_but_no_cloudkit(self):
        with self.assertRaisesRegex(ValueError, "CloudKit"):
            sign_ipa.validate_profile(
                "app.lgm.7517",
                entitlements(["CloudDocuments"]),
                required_icloud_containers=[CONTAINER],
            )

    def test_verifier_rejects_signature_with_documents_but_no_cloudkit(self):
        with self.assertRaisesRegex(ValueError, "CloudKit"):
            verify_signed_ipa.validate_bundle_entitlements(
                "app.lgm.7517",
                entitlements(["CloudDocuments", "CloudKit"]),
                entitlements(["CloudDocuments"]),
                required_icloud_containers=[CONTAINER],
            )

    def test_valid_cloud_documents_profile_and_signature_pass(self):
        valid = entitlements(["CloudDocuments", "CloudKit"])
        verify_signed_ipa.validate_bundle_entitlements(
            "app.lgm.7517", valid, valid,
            required_icloud_containers=[CONTAINER],
        )


    def test_missing_ubiquity_container_in_profile_is_rejected(self):
        valid = entitlements(["CloudDocuments", "CloudKit"])
        profile = dict(valid)
        profile.pop("com.apple.developer.ubiquity-container-identifiers")
        with self.assertRaisesRegex(ValueError, "ubiquity"):
            verify_signed_ipa.validate_bundle_entitlements(
                "app.lgm.7517", profile, valid,
                required_icloud_containers=[CONTAINER],
            )

    def test_missing_ubiquity_container_in_signature_is_rejected(self):
        valid = entitlements(["CloudDocuments", "CloudKit"])
        signed = dict(valid)
        signed["com.apple.developer.ubiquity-container-identifiers"] = []
        with self.assertRaisesRegex(ValueError, "ubiquity"):
            verify_signed_ipa.validate_bundle_entitlements(
                "app.lgm.7517", valid, signed,
                required_icloud_containers=[CONTAINER],
            )

    def test_capability_stamp_rejects_missing_ubiquity_container(self):
        valid = entitlements(["CloudDocuments", "CloudKit"])
        without_ubiquity = dict(valid)
        without_ubiquity.pop("com.apple.developer.ubiquity-container-identifiers")
        self.assertFalse(sign_ipa.has_cloud_documents_entitlement(without_ubiquity))
        self.assertFalse(verify_signed_ipa.has_cloud_documents_entitlement(without_ubiquity))

if __name__ == "__main__":
    unittest.main()
