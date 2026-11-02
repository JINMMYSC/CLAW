#!/usr/bin/env python3
"""Verify signatures, profiles, and required entitlements in a signed IPA."""

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import fnmatch
import os
import plistlib
import re
import stat
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

    # A CloudDocuments release must also be authorized for its ubiquity container.
    ubiquity_key = "com.apple.developer.ubiquity-container-identifiers"
    profile_ubiquity = profile_entitlements.get(ubiquity_key, []) or []
    signed_ubiquity = signed_entitlements.get(ubiquity_key, []) or []
    for container in signed_ubiquity:
        if not _entitlement_allows(profile_ubiquity, container):
            raise ValueError("signed ubiquity container is not permitted by provisioning profile")
    for container in required_icloud_containers:
        if container not in signed_ubiquity or not _entitlement_allows(profile_ubiquity, container):
            raise ValueError("missing required ubiquity container in profile or signature")

    # A container identifier alone does not grant iCloud Documents or CloudKit.
    # The CLAW Host release requires both services, and neither may silently
    # disappear from the profile or from the final code signature.
    if required_icloud_containers:
        service_key = "com.apple.developer.icloud-services"
        for source, entitlements in (("profile", profile_entitlements),
                                     ("signature", signed_entitlements)):
            granted_services = entitlements.get(service_key, []) or []
            for required_service in ("CloudDocuments", "CloudKit"):
                if required_service not in granted_services:
                    raise ValueError("required %s entitlement missing from %s"
                                     % (required_service, source))



def has_cloud_documents_entitlement(entitlements):
    return (
        DEFAULT_ICLOUD_CONTAINER in
        (entitlements.get("com.apple.developer.icloud-container-identifiers", []) or [])
        and DEFAULT_ICLOUD_CONTAINER in
        (entitlements.get("com.apple.developer.ubiquity-container-identifiers", []) or [])
        and "CloudDocuments" in
        (entitlements.get("com.apple.developer.icloud-services", []) or [])
    )


def _load_embedded_plist(data, description):
    match = re.search(rb"<\?xml.*?</plist>", data, re.S)
    if not match:
        raise ValueError("no plist found in %s" % description)
    return plistlib.loads(match.group(0))


def validate_profile_expiration(profile, now=None):
    """Reject missing or expired provisioning dates before trusting a profile."""
    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, datetime):
        raise ValueError("provisioning profile is missing ExpirationDate")
    if expiration.tzinfo is None:
        expiration = expiration.replace(tzinfo=timezone.utc)
    current = now if now is not None else datetime.now(timezone.utc)
    if current.tzinfo is None:
        current = current.replace(tzinfo=timezone.utc)
    if expiration <= current:
        raise ValueError("provisioning profile expired")


def validate_device_installable_profile(profile):
    """A directly installed IPA needs Ad Hoc device authorization or enterprise scope.

    App Store / TestFlight distribution profiles can sign an app, but do not
    authorize installing that IPA directly onto an iPhone.
    """
    if profile.get("ProvisionsAllDevices") is True:
        return
    devices = profile.get("ProvisionedDevices")
    if (isinstance(devices, list) and devices
            and all(isinstance(device, str) and device.strip() for device in devices)):
        return
    raise ValueError(
        "provisioning profile is not device-installable; "
        "use an Ad Hoc profile including the target iPhone or an enterprise profile"
    )


def validate_common_installable_devices(named_profiles, target_device_udid=None):
    """Require a common device and developer team across Host and extensions.

    Individually valid Ad Hoc profiles can still be mutually incompatible:
    if their ProvisionedDevices sets have no intersection, no iPhone can
    install the complete app. Enterprise profiles allow all devices.
    Never print or persist device identifiers from the profiles.
    """
    common_devices = None
    expected_team = None
    if not named_profiles:
        raise ValueError("no provisioning profiles supplied")
    for name, profile in named_profiles:
        validate_device_installable_profile(profile)
        entitlements = profile.get("Entitlements", {}) or {}
        team = entitlements.get("com.apple.developer.team-identifier")
        if not isinstance(team, str) or not team:
            raise ValueError("missing developer team in " + name + " profile")
        if expected_team is None:
            expected_team = team
        elif team != expected_team:
            raise ValueError("provisioning profile team mismatch across targets")
        if profile.get("ProvisionsAllDevices") is True:
            continue
        devices = set(profile["ProvisionedDevices"])
        common_devices = devices if common_devices is None else common_devices & devices
        if not common_devices:
            raise ValueError("no common provisioned device across Host/Keyboard/Widget profiles")

    # A common Ad Hoc device may not be the actual destination iPhone.
    # Device-specific checks must never disclose the UDID in diagnostics.
    if target_device_udid is not None:
        if not isinstance(target_device_udid, str) or not target_device_udid.strip():
            raise ValueError("target device identifier is invalid")
        requested = target_device_udid.strip().casefold()
        if common_devices is not None and requested not in {
            device.casefold() for device in common_devices
        }:
            raise ValueError("target device is not provisioned across all app targets")


def extract_profile(profile_path):
    """Decode and validate the complete Apple CMS provisioning profile."""
    result = subprocess.run(
        ["security", "cms", "-D", "-i", profile_path],
        check=True,
        capture_output=True,
    )
    profile = plistlib.loads(result.stdout)
    validate_profile_expiration(profile)
    validate_device_installable_profile(profile)
    return profile


def extract_profile_entitlements(profile_path):
    return extract_profile(profile_path).get("Entitlements", {}) or {}


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
        if identifier == main_identifier:
            with open(os.path.join(path, "Info.plist"), "rb") as source:
                stamp = plistlib.load(source).get("ClawICloudContainerEntitled")
            actual = has_cloud_documents_entitlement(signed_entitlements)
            if type(stamp) is not bool or stamp != actual:
                raise ValueError("signed iCloud capability stamp is missing or disagrees with entitlement")
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


EXPECTED_RELEASE_BUNDLE_IDS = frozenset({
    "app.lgm.7517",
    "app.lgm.7517.123",
    "app.lgm.7517.widget",
})


def reject_duplicate_archive_members(archive):
    """Reject ambiguous ZIP paths before trusting metadata or extracting an IPA."""
    seen = set()
    for member in archive.infolist():
        if member.filename in seen:
            raise ValueError("duplicate IPA archive member")
        seen.add(member.filename)


def reject_unsafe_archive_members(archive):
    """Reject ambiguous or link-backed IPA paths before extraction/codesign."""
    reject_duplicate_archive_members(archive)
    for member in archive.infolist():
        name = member.filename
        parts = name.rstrip("/").split("/")
        if (not name or name.startswith("/") or "\\" in name
                or re.match(r"^[A-Za-z]:", name)
                or any(part in ("", ".", "..") for part in parts)
                or stat.S_ISLNK(member.external_attr >> 16)):
            raise ValueError("unsafe IPA archive member")


def verify_release_bundle_manifest(archive):
    """Fail closed if a signed release drops a target or raises the iOS 15 floor."""
    reject_duplicate_archive_members(archive)
    names = archive.namelist()
    hosts = [name for name in names
             if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)]
    if len(hosts) != 1:
        raise ValueError("signed IPA must contain exactly one Host app")
    prefix = hosts[0].rsplit("/", 1)[0] + "/PlugIns/"
    extensions = [name for name in names
                  if re.fullmatch(re.escape(prefix) + r"[^/]+\.appex/Info\.plist", name)]
    if len(extensions) != 2:
        raise ValueError("signed IPA must preserve Keyboard and Widget extensions")

    bundle_ids = []
    for path in hosts + extensions:
        info = plistlib.loads(archive.read(path))
        identifier = info.get("CFBundleIdentifier")
        bundle_ids.append(identifier)
        minimum = info.get("MinimumOSVersion")
        if (not isinstance(minimum, str)
                or not re.fullmatch(r"\d+(?:\.\d+){0,2}", minimum)):
            raise ValueError("invalid MinimumOSVersion for " + str(identifier))
        major, minor = (int(part) for part in (minimum.split(".") + ["0"])[:2])
        if (major, minor) > (15, 0):
            raise ValueError("iOS 15 compatibility lost for " + str(identifier))

    if frozenset(bundle_ids) != EXPECTED_RELEASE_BUNDLE_IDS or len(set(bundle_ids)) != 3:
        raise ValueError("signed IPA Bundle IDs do not match Host/Keyboard/Widget release")


def verify_ipa_source_sha(archive, expected_sha):
    """Verify every unsigned release bundle embeds the exact frozen commit."""
    if not re.fullmatch(r"[0-9a-f]{40}", expected_sha or ""):
        raise ValueError("expected source SHA must be a lowercase 40-character commit ID")
    verify_release_bundle_manifest(archive)
    paths = [name for name in archive.namelist()
             if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)
             or re.fullmatch(r"Payload/[^/]+\.app/PlugIns/[^/]+\.appex/Info\.plist", name)]
    for path in paths:
        actual = plistlib.loads(archive.read(path)).get("ClawSourceCommit")
        if actual != expected_sha:
            raise ValueError("unsigned IPA source SHA mismatch in " + path)


def verify_ipa_executable_modes(archive):
    """Require executable Host/extension Mach-O modes in the final IPA ZIP."""
    bundle_plists = []
    for name in archive.namelist():
        parts = name.split("/")
        is_host = (len(parts) == 3 and parts[0] == "Payload"
                   and parts[1].endswith(".app") and parts[2] == "Info.plist")
        is_extension = (len(parts) == 5 and parts[0] == "Payload"
                        and parts[1].endswith(".app") and parts[2] == "PlugIns"
                        and parts[3].endswith(".appex") and parts[4] == "Info.plist")
        if is_host or is_extension:
            bundle_plists.append(name)
    if not bundle_plists:
        raise ValueError("no Host or extension Info.plist in IPA")
    for plist_path in bundle_plists:
        info = plistlib.loads(archive.read(plist_path))
        executable = info.get("CFBundleExecutable")
        if not isinstance(executable, str) or not executable:
            raise ValueError("missing CFBundleExecutable in " + plist_path)
        executable_path = plist_path.rsplit("/", 1)[0] + "/" + executable
        try:
            member = archive.getinfo(executable_path)
        except KeyError:
            raise ValueError("missing IPA executable: " + executable_path) from None
        if not (stat.S_IMODE(member.external_attr >> 16) & stat.S_IXUSR):
            raise ValueError("IPA executable lost owner execute permission: "
                             + executable_path)


def verify_ipa(ipa_path, require_icloud=True):
    with tempfile.TemporaryDirectory() as tmp:
        with zipfile.ZipFile(ipa_path) as archive:
            reject_unsafe_archive_members(archive)
            verify_ipa_executable_modes(archive)
            verify_release_bundle_manifest(archive)
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
    parser.add_argument("--check-unsigned-source-sha", metavar="SHA",
                        help="verify Host/Keyboard/Widget source SHA before importing signing assets")
    args = parser.parse_args()
    if args.check_unsigned_source_sha is not None:
        with zipfile.ZipFile(args.ipa) as archive:
            verify_ipa_source_sha(archive, args.check_unsigned_source_sha)
        print("unsigned IPA source SHA verified:", args.check_unsigned_source_sha)
        return
    verify_ipa(args.ipa, require_icloud=not args.allow_missing_icloud)
    print("signed IPA verification OK")


if __name__ == "__main__":
    main()

