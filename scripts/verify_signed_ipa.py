#!/usr/bin/env python3
"""Verify signatures, profiles, and required entitlements in a signed IPA."""

import argparse
import fnmatch
import os
import plistlib
import re
import subprocess
import tempfile
import zipfile


DEFAULT_APP_GROUP = "group.7518554"
DEFAULT_ICLOUD_CONTAINER = "iCloud.dev.fuxiao.app.hamsterapp"


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

    team_identifier = profile_entitlements.get("com.apple.developer.team-identifier")
    if not team_identifier and "." in profile_app_id:
        team_identifier = profile_app_id.split(".", 1)[0]
    expected_app_id = "%s.%s" % (team_identifier, bundle_identifier)
    if signed_entitlements.get("application-identifier") != expected_app_id:
        raise ValueError("signed application-identifier does not match bundle identifier %s" % bundle_identifier)
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


def bundle_paths(app_path):
    paths = []
    plug_ins = os.path.join(app_path, "PlugIns")
    if os.path.isdir(plug_ins):
        for root, dirs, _files in os.walk(plug_ins):
            for directory in dirs:
                if directory.endswith(".appex"):
                    paths.append(os.path.join(root, directory))
    return sorted(paths) + [app_path]


def verify_bundle_tree(app_path):
    main_identifier = bundle_identifier(app_path)
    for path in bundle_paths(app_path):
        subprocess.run(["codesign", "--verify", "--strict", path], check=True)
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
                [DEFAULT_ICLOUD_CONTAINER] if identifier == main_identifier else []
            ),
        )
        print("verified bundle:", identifier)


def verify_ipa(ipa_path):
    with tempfile.TemporaryDirectory() as tmp:
        with zipfile.ZipFile(ipa_path) as archive:
            archive.extractall(tmp)
        payload = os.path.join(tmp, "Payload")
        apps = [name for name in os.listdir(payload) if name.endswith(".app")]
        if len(apps) != 1:
            raise ValueError("expected exactly one app in IPA Payload")
        verify_bundle_tree(os.path.join(payload, apps[0]))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", help="path to signed IPA")
    args = parser.parse_args()
    verify_ipa(args.ipa)
    print("signed IPA verification OK")


if __name__ == "__main__":
    main()
