#!/usr/bin/env python3
"""Verify signatures, profiles, and required entitlements in a signed IPA."""

import argparse
from dataclasses import dataclass
import fnmatch
import os
import plistlib
import re
import subprocess
import tempfile
import zipfile


DEFAULT_APP_GROUP = "group.7518554"
DEFAULT_ICLOUD_CONTAINER = "iCloud.dev.fuxiao.app.hamsterapp"


@dataclass(frozen=True)
class CodeBundle:
    path: str
    requires_profile: bool


def _application_identifier_matches(application_identifier, bundle_identifier):
    if "." not in application_identifier:
        return False
    profile_bundle_identifier = application_identifier.split(".", 1)[1]
    return fnmatch.fnmatchcase(bundle_identifier, profile_bundle_identifier)


def _entitlement_allows(profile_values, value):
    return any(fnmatch.fnmatchcase(value, permitted) for permitted in profile_values)


def validate_bundle_entitlements(
    bundle_identifier,
    profile_entitlements,
    signed_entitlements,
    required_app_groups=(),
    required_icloud_containers=(),
):
    """Raise ValueError when a signed bundle is not covered by its profile."""
    profile_app_id = profile_entitlements.get("application-identifier", "")
    if not _application_identifier_matches(profile_app_id, bundle_identifier):
        raise ValueError(
            "profile application-identifier does not match bundle identifier %s"
            % bundle_identifier
        )

    app_identifier_prefix = profile_app_id.split(".", 1)[0]
    expected_app_id = "%s.%s" % (app_identifier_prefix, bundle_identifier)
    if signed_entitlements.get("application-identifier") != expected_app_id:
        raise ValueError("signed application-identifier does not match bundle identifier %s" % bundle_identifier)
    team_identifier = profile_entitlements.get("com.apple.developer.team-identifier")
    if not team_identifier:
        raise ValueError("provisioning profile is missing team identifier")
    if signed_entitlements.get("com.apple.developer.team-identifier") != team_identifier:
        raise ValueError("signed team identifier does not match provisioning profile")

    profile_groups = profile_entitlements.get("com.apple.security.application-groups", []) or []
    signed_groups = signed_entitlements.get("com.apple.security.application-groups", []) or []
    for group in signed_groups:
        if not _entitlement_allows(profile_groups, group):
            raise ValueError("signed App Group is not permitted by provisioning profile: %s" % group)
    for group in required_app_groups:
        if group not in signed_groups or not _entitlement_allows(profile_groups, group):
            raise ValueError("missing required App Group: %s" % group)

    icloud_key = "com.apple.developer.icloud-container-identifiers"
    profile_containers = profile_entitlements.get(icloud_key, []) or []
    signed_containers = signed_entitlements.get(icloud_key, []) or []
    for container in signed_containers:
        if not _entitlement_allows(profile_containers, container):
            raise ValueError("signed iCloud container is not permitted by provisioning profile: %s" % container)
    for container in required_icloud_containers:
        if container not in signed_containers or not _entitlement_allows(profile_containers, container):
            raise ValueError("missing required iCloud container: %s" % container)


def _load_embedded_plist(data, description):
    match = re.search(rb"<\?xml.*?</plist>", data, re.S)
    if not match:
        raise ValueError("no plist found in %s" % description)
    return plistlib.loads(match.group(0))


def extract_profile_entitlements(profile_path):
    result = subprocess.run(
        ["security", "cms", "-D", "-i", profile_path],
        check=True,
        capture_output=True,
    )
    return plistlib.loads(result.stdout).get("Entitlements", {}) or {}


def extract_signed_entitlements(bundle_path):
    result = subprocess.run(
        ["codesign", "-d", "--entitlements", ":-", bundle_path],
        check=True,
        capture_output=True,
    )
    return _load_embedded_plist(result.stdout + result.stderr, bundle_path)


def bundle_identifier(bundle_path):
    with open(os.path.join(bundle_path, "Info.plist"), "rb") as stream:
        return plistlib.load(stream)["CFBundleIdentifier"]


def discover_code_bundles(app_path):
    """Return all nested code bundles, deepest first, followed by the main app."""
    suffix_profiles = {
        ".framework": False,
        ".appex": True,
        ".xpc": True,
        ".app": True,
    }
    bundles = []
    for root, dirs, _files in os.walk(app_path):
        for directory in dirs:
            path = os.path.join(root, directory)
            if os.path.normpath(path) == os.path.normpath(app_path):
                continue
            for suffix, requires_profile in suffix_profiles.items():
                if directory.endswith(suffix):
                    bundles.append(CodeBundle(path, requires_profile))
                    break
    bundles.sort(key=lambda item: (-item.path.count(os.sep), item.path))
    bundles.append(CodeBundle(app_path, True))
    return bundles


def verification_commands(app_path, bundles):
    commands = [
        ["codesign", "--verify", "--strict", bundle.path]
        for bundle in bundles
    ]
    commands.append(["codesign", "--verify", "--deep", "--strict", app_path])
    return commands


def verify_bundle_tree(app_path, require_icloud=True):
    main_identifier = bundle_identifier(app_path)
    bundles = discover_code_bundles(app_path)
    for bundle in bundles:
        path = bundle.path
        subprocess.run(["codesign", "--verify", "--strict", path], check=True)
        if not bundle.requires_profile:
            print("verified code bundle:", os.path.relpath(path, app_path))
            continue
        identifier = bundle_identifier(path)
        profile_path = os.path.join(path, "embedded.mobileprovision")
        if not os.path.isfile(profile_path):
            raise ValueError("missing embedded provisioning profile for %s" % identifier)
        profile_entitlements = extract_profile_entitlements(profile_path)
        signed_entitlements = extract_signed_entitlements(path)
        validate_bundle_entitlements(
            identifier,
            profile_entitlements,
            signed_entitlements,
            required_app_groups=[DEFAULT_APP_GROUP],
            required_icloud_containers=(
                [DEFAULT_ICLOUD_CONTAINER]
                if require_icloud and identifier == main_identifier
                else []
            ),
        )
        print("verified bundle:", identifier)
    subprocess.run(
        ["codesign", "--verify", "--deep", "--strict", app_path],
        check=True,
    )
    print("verified deep signature tree:", main_identifier)


def verify_ipa(ipa_path, require_icloud=True):
    with tempfile.TemporaryDirectory() as tmp:
        with zipfile.ZipFile(ipa_path) as archive:
            archive.extractall(tmp)
        payload = os.path.join(tmp, "Payload")
        apps = [name for name in os.listdir(payload) if name.endswith(".app")]
        if len(apps) != 1:
            raise ValueError("expected exactly one app in IPA Payload")
        verify_bundle_tree(
            os.path.join(payload, apps[0]),
            require_icloud=require_icloud,
        )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", help="path to signed IPA")
    parser.add_argument(
        "--allow-missing-icloud",
        action="store_true",
        help="verify a build signed by a profile that omits the CLAW iCloud container",
    )
    args = parser.parse_args()
    verify_ipa(args.ipa, require_icloud=not args.allow_missing_icloud)
    print("signed IPA verification OK")


if __name__ == "__main__":
    main()

