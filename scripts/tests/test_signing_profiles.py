import importlib.util
import pathlib
import sys
import tempfile
import traceback
import unittest
from unittest import mock


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

    def test_requires_a_profile_mapping_for_every_extension_in_production(self):
        resolve = getattr(sign_ipa, "resolve_extension_profiles", None)
        self.assertTrue(callable(resolve), "production profile routing must be explicit")

        with self.assertRaisesRegex(ValueError, "app.lgm.7517.widget"):
            resolve(
                ["app.lgm.7517.123", "app.lgm.7517.widget"],
                {"app.lgm.7517.123": "keyboard.mobileprovision"},
            )

    def test_legacy_ext_profile_is_only_used_for_one_extension(self):
        resolve = getattr(sign_ipa, "resolve_extension_profiles", None)
        self.assertTrue(callable(resolve), "legacy profile routing must be bounded")

        self.assertEqual(
            resolve(["app.lgm.7517.123"], {}, "legacy.mobileprovision"),
            {"app.lgm.7517.123": "legacy.mobileprovision"},
        )
        with self.assertRaisesRegex(ValueError, "explicit --bundle-profile"):
            resolve(
                ["app.lgm.7517.123", "app.lgm.7517.widget"],
                {},
                "legacy.mobileprovision",
            )

    def test_accepts_legacy_application_identifier_prefix_distinct_from_team(self):
        verifier = load_verifier()
        validate = getattr(verifier, "validate_bundle_entitlements", None)
        self.assertTrue(callable(validate), "bundle entitlement validator must exist")

        validate(
            bundle_identifier="app.lgm.7517",
            profile_entitlements={
                "application-identifier": "LEGACYSEED.app.lgm.7517",
                "com.apple.developer.team-identifier": "TEAM123",
            },
            signed_entitlements={
                "application-identifier": "LEGACYSEED.app.lgm.7517",
                "com.apple.developer.team-identifier": "TEAM123",
            },
        )

    def test_discovers_nested_code_bundles(self):
        verifier = load_verifier()
        discover = getattr(verifier, "discover_code_bundles", None)
        self.assertTrue(callable(discover), "nested code bundle discovery must exist")

        with tempfile.TemporaryDirectory() as tmp:
            app = pathlib.Path(tmp, "Main.app")
            paths = [
                app / "Frameworks" / "Root.framework",
                app / "PlugIns" / "Keyboard.appex",
                app / "PlugIns" / "Keyboard.appex" / "Frameworks" / "Nested.framework",
                app / "XPCServices" / "Agent.xpc",
                app / "Watch" / "Companion.app",
            ]
            for path in paths:
                path.mkdir(parents=True, exist_ok=True)

            discovered = {
                pathlib.Path(item.path).relative_to(app).as_posix(): item.requires_profile
                for item in discover(str(app))
                if pathlib.Path(item.path) != app
            }

        self.assertEqual(
            discovered,
            {
                "Frameworks/Root.framework": False,
                "PlugIns/Keyboard.appex": True,
                "PlugIns/Keyboard.appex/Frameworks/Nested.framework": False,
                "Watch/Companion.app": True,
                "XPCServices/Agent.xpc": True,
            },
        )

    def test_main_bundle_keeps_deep_strict_verification(self):
        verifier = load_verifier()
        commands = getattr(verifier, "verification_commands", None)
        self.assertTrue(callable(commands), "verification command builder must exist")

        self.assertIn(
            ["codesign", "--verify", "--deep", "--strict", "/tmp/Main.app"],
            commands("/tmp/Main.app", []),
        )

    def test_sensitive_command_failure_does_not_leak_password(self):
        run_sensitive = getattr(sign_ipa, "run_sensitive_command", None)
        self.assertTrue(callable(run_sensitive), "sensitive subprocess wrapper must exist")
        password = "do-not-print-this-password"

        failed = mock.Mock(returncode=1, stdout=b"", stderr=password.encode())
        with mock.patch.object(sign_ipa.subprocess, "run", return_value=failed):
            try:
                run_sensitive(
                    ["security", "import", "sign.p12", "-P", password],
                    "certificate import",
                )
            except Exception as error:
                rendered = "".join(traceback.format_exception(error))
            else:
                self.fail("failed sensitive command must raise")

        self.assertNotIn(password, rendered)
        self.assertIn("certificate import failed", rendered)

    def test_workflow_uses_exact_bundle_profile_mappings(self):
        workflow = (SCRIPTS_DIR.parent / ".github" / "workflows" / "build-ipa.yml").read_text()
        self.assertIn(
            "--bundle-profile app.lgm.7517.123=profiles/ext.mobileprovision",
            workflow,
        )
        self.assertIn(
            '--bundle-profile "$WIDGET_BUNDLE_ID=profiles/widget.mobileprovision"',
            workflow,
        )
        self.assertIn("--list-extension-bundle-identifiers", workflow)
        self.assertEqual(workflow.count("--allow-missing-icloud"), 2)


if __name__ == "__main__":
    unittest.main()

