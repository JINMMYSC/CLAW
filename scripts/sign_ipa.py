#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Sign an unsigned ClawTalk ipa with a third-party P12 + two provisioning
profiles (main app + keyboard extension). Runs on macOS (codesign + security).

Usage:
  python3 sign_ipa.py \
    --ipa unsigned.zip --p12 sign.p12 --password 1 \
    --main-profile main.mobileprovision --ext-profile ext.mobileprovision \
    --out signed.ipa
"""
import argparse
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

from verify_signed_ipa import (
    DEFAULT_APP_GROUP,
    DEFAULT_ICLOUD_CONTAINER,
    validate_bundle_entitlements,
    verify_bundle_tree,
)


def extract_entitlements(profile_path):
    """Parse the Entitlements dict embedded in a .mobileprovision file."""
    raw = open(profile_path, "rb").read()
    m = re.search(rb"<\?xml.*?</plist>", raw, re.S)
    if not m:
        raise RuntimeError("no plist found in %s" % profile_path)
    pl = plistlib.loads(m.group(0))
    return pl.get("Entitlements", {}) or {}



def has_cloud_documents_entitlement(entitlements):
    """Exactly the iCloud Documents capability needed for CLAW's file copy."""
    return (
        DEFAULT_ICLOUD_CONTAINER in
        (entitlements.get("com.apple.developer.icloud-container-identifiers", []) or [])
        and "CloudDocuments" in
        (entitlements.get("com.apple.developer.icloud-services", []) or [])
    )


def stamp_cloud_capability(app_path, entitlements):
    """Signed app metadata must reflect the actual *provisioning profile*."""
    path = os.path.join(app_path, "Info.plist")
    with open(path, "rb") as source:
        info = plistlib.load(source)
    enabled = has_cloud_documents_entitlement(entitlements)
    info["ClawICloudContainerEntitled"] = enabled
    with open(path, "wb") as target:
        plistlib.dump(info, target)
    return enabled


def add_shared_keychain_group(entitlements, app_group="group.7518554"):
    """Add one concrete shared Keychain group when the profile wildcard permits it."""
    app_id = entitlements.get("application-identifier", "")
    prefix = app_id.split(".", 1)[0] if "." in app_id else ""
    if not prefix:
        return None
    shared = "%s.%s" % (prefix, app_group)
    groups = list(entitlements.get("keychain-access-groups", []) or [])
    permitted = (shared in groups) or ("%s.*" % prefix in groups)
    if permitted and shared not in groups:
        groups.append(shared)
        entitlements["keychain-access-groups"] = groups
    return shared if permitted else None


def select_profile_for_bundle(
        bundle_identifier, profile_by_bundle, ext_profile=None, widget_profile=None,
        extension_point=None):
    """Select an extension profile from an exact mapping or legacy fallback."""
    if bundle_identifier in profile_by_bundle:
        return profile_by_bundle[bundle_identifier]
    return ext_profile if not profile_by_bundle else None


def resolve_extension_profiles(bundle_identifiers, profile_by_bundle, ext_profile=None):
    """Resolve all profiles and reject partial or ambiguous routing."""
    identifiers = sorted(set(bundle_identifiers))
    mappings = dict(profile_by_bundle)
    if not mappings and ext_profile and len(identifiers) == 1:
        return {identifiers[0]: ext_profile}
    if not mappings and ext_profile and len(identifiers) > 1:
        raise ValueError(
            "multiple extensions require an explicit --bundle-profile for each bundle identifier"
        )
    missing = [identifier for identifier in identifiers if identifier not in mappings]
    if missing:
        raise ValueError("missing profile mapping for: %s" % ", ".join(missing))
    unused = sorted(set(mappings) - set(identifiers))
    if unused:
        raise ValueError("profile mapping has no matching extension: %s" % ", ".join(unused))
    return {identifier: mappings[identifier] for identifier in identifiers}


def parse_bundle_profile_mappings(values):
    mappings = {}
    for value in values:
        if "=" not in value:
            raise ValueError("--bundle-profile must use BUNDLE_ID=PATH")
        identifier, path = value.split("=", 1)
        if not identifier or not path:
            raise ValueError("--bundle-profile must use BUNDLE_ID=PATH")
        mappings[identifier] = path
    return mappings


def read_bundle_info(bundle_path):
    with open(os.path.join(bundle_path, "Info.plist"), "rb") as stream:
        return plistlib.load(stream)


def validate_profile(bundle_identifier, entitlements, required_icloud_containers=()):
    """Validate profile coverage before using it to sign a bundle."""
    app_id = entitlements.get("application-identifier", "")
    app_id_prefix = app_id.split(".", 1)[0] if "." in app_id else ""
    team = entitlements.get("com.apple.developer.team-identifier")
    signed_shape = dict(entitlements)
    signed_shape["application-identifier"] = "%s.%s" % (app_id_prefix, bundle_identifier)
    signed_shape["com.apple.developer.team-identifier"] = team
    validate_bundle_entitlements(
        bundle_identifier,
        entitlements,
        signed_shape,
        required_app_groups=[DEFAULT_APP_GROUP],
        required_icloud_containers=required_icloud_containers,
    )


class SigningCommandError(RuntimeError):
    pass


def run_sensitive_command(command, operation):
    """Run a command without exposing its argv or captured output on failure."""
    result = subprocess.run(command, capture_output=True, check=False)
    if result.returncode:
        raise SigningCommandError("%s failed" % operation)
    return result


def resolve_password(args):
    if args.password and args.password_env:
        raise ValueError("use only one of --password or --password-env")
    if args.password_env:
        password = os.environ.get(args.password_env)
        if not password:
            raise ValueError("password environment variable is empty")
        return password
    if args.password:
        return args.password
    raise ValueError("one of --password or --password-env is required")


def locate_ipa(input_path, tmp):
    if input_path.lower().endswith(".zip"):
        with zipfile.ZipFile(input_path) as artifact:
            ipa_names = [name for name in artifact.namelist() if name.endswith(".ipa")]
            if len(ipa_names) != 1:
                raise ValueError("expected exactly one IPA in artifact zip")
            ipa_path = os.path.join(tmp, "input.ipa")
            with open(ipa_path, "wb") as stream:
                stream.write(artifact.read(ipa_names[0]))
            return ipa_path
    return input_path


def extract_app(input_path, tmp):
    ipa_path = locate_ipa(input_path, tmp)
    work = os.path.join(tmp, "work")
    with zipfile.ZipFile(ipa_path) as archive:
        archive.extractall(work)
    payload = os.path.join(work, "Payload")
    apps = [name for name in os.listdir(payload) if name.endswith(".app")]
    if len(apps) != 1:
        raise ValueError("expected exactly one app in IPA Payload")
    return work, os.path.join(payload, apps[0])


def extension_bundle_paths(app_path):
    paths = []
    for root, dirs, _files in os.walk(app_path):
        for directory in dirs:
            if directory.endswith(".appex"):
                paths.append(os.path.join(root, directory))
    return sorted(paths)


def list_extension_bundle_identifiers(input_path):
    with tempfile.TemporaryDirectory() as tmp:
        _work, app_path = extract_app(input_path, tmp)
        return [read_bundle_info(path)["CFBundleIdentifier"]
                for path in extension_bundle_paths(app_path)]


def find_distribution_identity():
    out = subprocess.check_output(
        ["security", "find-identity", "-v", "-p", "codesigning"], text=True)
    for line in out.splitlines():
        if ("iPhone Distribution" in line) or ("Apple Distribution" in line):
            parts = line.split('"')
            if len(parts) >= 2:
                return parts[1]
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ipa", required=True, help="path to unsigned ipa or artifact zip")
    ap.add_argument("--p12")
    ap.add_argument("--password")
    ap.add_argument("--password-env", help="environment variable containing the P12 password")
    ap.add_argument("--main-profile")
    ap.add_argument("--ext-profile", help="legacy/default extension profile")
    ap.add_argument("--widget-profile", help="profile for a WidgetKit extension")
    ap.add_argument("--widget-bundle-id", help="exact bundle identifier for --widget-profile")
    ap.add_argument(
        "--allow-missing-icloud",
        action="store_true",
        help="sign without the CLAW iCloud container when the supplied profile omits it",
    )
    ap.add_argument(
        "--bundle-profile", action="append", default=[], metavar="BUNDLE_ID=PATH",
        help="profile for one exact extension bundle identifier (repeatable)")
    ap.add_argument("--list-extension-bundle-identifiers", action="store_true")
    ap.add_argument("--out")
    args = ap.parse_args()
    if args.list_extension_bundle_identifiers:
        for identifier in list_extension_bundle_identifiers(args.ipa):
            print(identifier)
        return 0
    missing_args = [name for name in ("p12", "main_profile", "out")
                    if not getattr(args, name)]
    if missing_args:
        ap.error("signing requires: %s" % ", ".join("--" + name.replace("_", "-")
                                                        for name in missing_args))
    try:
        profile_by_bundle = parse_bundle_profile_mappings(args.bundle_profile)
        if args.widget_profile:
            if not args.widget_bundle_id:
                raise ValueError("--widget-profile requires --widget-bundle-id")
            if args.widget_bundle_id in profile_by_bundle:
                raise ValueError("duplicate profile mapping for %s" % args.widget_bundle_id)
            profile_by_bundle[args.widget_bundle_id] = args.widget_profile
        password = resolve_password(args)
    except ValueError as error:
        ap.error(str(error))

    # --- import p12 into an isolated keychain ---
    subprocess.run(["security", "create-keychain", "-p", "ci", "ci.keychain"],
                   capture_output=True, check=False)
    subprocess.run(["security", "default-keychain", "-s", "ci.keychain"], check=True,
                   capture_output=True)
    subprocess.run(["security", "unlock-keychain", "-p", "ci", "ci.keychain"], check=True,
                   capture_output=True)
    run_sensitive_command(
        ["security", "import", args.p12, "-k", "ci.keychain",
         "-P", password, "-T", "/usr/bin/codesign"],
        "certificate import",
    )
    subprocess.run(["security", "set-key-partition-list", "-S",
                    "apple-tool:,apple:,codesign:", "-s", "-k", "ci", "ci.keychain"],
                   check=True, capture_output=True)

    identity = find_distribution_identity()
    if not identity:
        print("ERROR: no iPhone Distribution identity found in keychain")
        sys.exit(1)
    print("identity:", identity)

    with tempfile.TemporaryDirectory() as tmp:
        work, app_path = extract_app(args.ipa, tmp)
        app_name = os.path.basename(app_path)
        extension_paths = extension_bundle_paths(app_path)
        extension_records = [
            (path, read_bundle_info(path)["CFBundleIdentifier"])
            for path in extension_paths
        ]
        profiles = resolve_extension_profiles(
            [identifier for _path, identifier in extension_records],
            profile_by_bundle,
            args.ext_profile,
        )
        print("app:", app_name, "| extension bundle identifiers:",
              [identifier for _path, identifier in extension_records])

        # --- entitlements ---
        main_ent = extract_entitlements(args.main_profile)
        main_identifier = read_bundle_info(app_path)["CFBundleIdentifier"]
        required_icloud_containers = (
            [] if args.allow_missing_icloud else [DEFAULT_ICLOUD_CONTAINER]
        )
        if args.allow_missing_icloud and DEFAULT_ICLOUD_CONTAINER not in (
            main_ent.get("com.apple.developer.icloud-container-identifiers", []) or []
        ):
            print(
                "WARNING: signing without iCloud container %s; iCloud features are unavailable"
                % DEFAULT_ICLOUD_CONTAINER
            )
        validate_profile(
            main_identifier,
            main_ent,
            required_icloud_containers=required_icloud_containers,
        )
        if not stamp_cloud_capability(app_path, main_ent):
            print("CLAW iCloud backup is disabled in this signed build: missing CloudDocuments capability")
        main_shared = add_shared_keychain_group(main_ent)
        main_ent_path = os.path.join(tmp, "main_ent.plist")
        with open(main_ent_path, "wb") as f:
            plistlib.dump(main_ent, f)

        # --- embed profiles + sign extensions first, then the app ---
        shutil.copy(args.main_profile, os.path.join(app_path, "embedded.mobileprovision"))
        for ext_path, ext_identifier in extension_records:
            ext_info = read_bundle_info(ext_path)
            profile_path = profiles[ext_identifier]
            ext_ent = extract_entitlements(profile_path)
            validate_profile(ext_identifier, ext_ent)
            ext_shared = add_shared_keychain_group(ext_ent)
            if not main_shared or ext_shared != main_shared:
                print("WARNING: shared keychain group is not permitted for", ext_identifier)
            ext_ent_path = os.path.join(tmp, "%s-entitlements.plist" % ext_identifier)
            with open(ext_ent_path, "wb") as f:
                plistlib.dump(ext_ent, f)
            shutil.copy(profile_path, os.path.join(ext_path, "embedded.mobileprovision"))
            subprocess.run(["codesign", "--force", "--sign", identity,
                            "--entitlements", ext_ent_path,
                            "--timestamp=none", ext_path], check=True)
            print("signed extension:", ext_identifier)
        subprocess.run(["codesign", "--force", "--sign", identity,
                        "--entitlements", main_ent_path,
                        "--timestamp=none", app_path], check=True)
        print("signed app:", app_name)

        # --- verify ---
        verify_bundle_tree(app_path, require_icloud=not args.allow_missing_icloud)
        print("bundle signatures and entitlements verify OK")

        # --- repack ipa ---
        out_ipa = os.path.join(tmp, "signed.ipa")
        with zipfile.ZipFile(out_ipa, "w", zipfile.ZIP_DEFLATED) as z:
            for root, dirs, files in os.walk(work):
                for f in files:
                    fp = os.path.join(root, f)
                    z.write(fp, os.path.relpath(fp, work))
        shutil.copy(out_ipa, args.out)
        print("signed ipa ->", args.out)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SigningCommandError as error:
        print("ERROR:", error, file=sys.stderr)
        sys.exit(1)

