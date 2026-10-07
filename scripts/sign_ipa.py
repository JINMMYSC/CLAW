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
    """Select an extension profile, preferring an explicit bundle-ID mapping."""
    if bundle_identifier in profile_by_bundle:
        return profile_by_bundle[bundle_identifier]
    is_widget = extension_point == "com.apple.widgetkit-extension"
    if widget_profile and (is_widget or "widget" in bundle_identifier.lower()):
        return widget_profile
    return ext_profile


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
    team = entitlements.get("com.apple.developer.team-identifier")
    app_id = entitlements.get("application-identifier", "")
    if not team and "." in app_id:
        team = app_id.split(".", 1)[0]
    signed_shape = dict(entitlements)
    signed_shape["application-identifier"] = "%s.%s" % (team, bundle_identifier)
    signed_shape["com.apple.developer.team-identifier"] = team
    validate_bundle_entitlements(
        bundle_identifier,
        entitlements,
        signed_shape,
        required_app_groups=[DEFAULT_APP_GROUP],
        required_icloud_containers=required_icloud_containers,
    )


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
    ap.add_argument("--p12", required=True)
    ap.add_argument("--password", required=True)
    ap.add_argument("--main-profile", required=True)
    ap.add_argument("--ext-profile", help="legacy/default extension profile")
    ap.add_argument("--widget-profile", help="profile for a WidgetKit extension")
    ap.add_argument(
        "--bundle-profile", action="append", default=[], metavar="BUNDLE_ID=PATH",
        help="profile for one exact extension bundle identifier (repeatable)")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    try:
        profile_by_bundle = parse_bundle_profile_mappings(args.bundle_profile)
    except ValueError as error:
        ap.error(str(error))

    # --- import p12 into an isolated keychain ---
    subprocess.run(["security", "create-keychain", "-p", "ci", "ci.keychain"],
                   capture_output=True, check=False)
    subprocess.run(["security", "default-keychain", "-s", "ci.keychain"], check=True,
                   capture_output=True)
    subprocess.run(["security", "unlock-keychain", "-p", "ci", "ci.keychain"], check=True,
                   capture_output=True)
    subprocess.run(["security", "import", args.p12, "-k", "ci.keychain",
                    "-P", args.password, "-T", "/usr/bin/codesign"], check=True,
                   capture_output=True)
    subprocess.run(["security", "set-key-partition-list", "-S",
                    "apple-tool:,apple:,codesign:", "-s", "-k", "ci", "ci.keychain"],
                   check=True, capture_output=True)

    identity = find_distribution_identity()
    if not identity:
        print("ERROR: no iPhone Distribution identity found in keychain")
        sys.exit(1)
    print("identity:", identity)

    with tempfile.TemporaryDirectory() as tmp:
        # --- locate ipa inside the artifact zip (or use it directly) ---
        if args.ipa.lower().endswith(".zip"):
            art = zipfile.ZipFile(args.ipa)
            ipa_name = next(n for n in art.namelist() if n.endswith(".ipa"))
            ipa_path = os.path.join(tmp, "input.ipa")
            with open(ipa_path, "wb") as f:
                f.write(art.read(ipa_name))
        else:
            ipa_path = args.ipa

        # --- extract ipa ---
        work = os.path.join(tmp, "work")
        with zipfile.ZipFile(ipa_path) as z:
            z.extractall(work)

        payload = os.path.join(work, "Payload")
        app_name = next(d for d in os.listdir(payload) if d.endswith(".app"))
        app_path = os.path.join(payload, app_name)
        plug_ins = os.path.join(app_path, "PlugIns")
        exts = [d for d in os.listdir(plug_ins) if d.endswith(".appex")]
        print("app:", app_name, "| extensions:", exts)

        # --- entitlements ---
        main_ent = extract_entitlements(args.main_profile)
        main_identifier = read_bundle_info(app_path)["CFBundleIdentifier"]
        validate_profile(
            main_identifier,
            main_ent,
            required_icloud_containers=[DEFAULT_ICLOUD_CONTAINER],
        )
        main_shared = add_shared_keychain_group(main_ent)
        main_ent_path = os.path.join(tmp, "main_ent.plist")
        with open(main_ent_path, "wb") as f:
            plistlib.dump(main_ent, f)

        # --- embed profiles + sign extensions first, then the app ---
        shutil.copy(args.main_profile, os.path.join(app_path, "embedded.mobileprovision"))
        for ext in exts:
            ext_path = os.path.join(plug_ins, ext)
            ext_info = read_bundle_info(ext_path)
            ext_identifier = ext_info["CFBundleIdentifier"]
            extension_point = (ext_info.get("NSExtension") or {}).get(
                "NSExtensionPointIdentifier")
            profile_path = select_profile_for_bundle(
                ext_identifier,
                profile_by_bundle,
                args.ext_profile,
                args.widget_profile,
                extension_point,
            )
            if not profile_path:
                raise ValueError("no provisioning profile configured for %s" % ext_identifier)
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
        verify_bundle_tree(app_path)
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


if __name__ == "__main__":
    main()
