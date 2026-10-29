#!/usr/bin/env python3
"""Fail closed before iPhoneOS archive when RIME archives are simulator-only.

Checks xcframework device metadata, the actual arm64 binary architecture and
each LC_BUILD_VERSION platform reported by Apple's otool. Run on macOS with
Xcode command-line tools; this does not replace linking or real-device tests.
"""

import argparse
from collections import Counter
import pathlib
import plistlib
import re
import subprocess
import sys


REQUIRED_FRAMEWORKS = (
    "librime", "boost_atomic", "boost_filesystem", "boost_regex",
    "boost_system", "libleveldb", "libmarisa", "libopencc", "libyaml-cpp",
)


def _run(args):
    return subprocess.run(args, capture_output=True, text=True, check=False)


def _device_binary(framework, name):
    info_path = framework / "Info.plist"
    if not info_path.is_file():
        raise ValueError(f"{name}: missing xcframework Info.plist")
    try:
        entries = plistlib.loads(info_path.read_bytes())["AvailableLibraries"]
    except (ValueError, KeyError, TypeError, OSError) as exc:
        raise ValueError(f"{name}: invalid xcframework metadata") from exc

    candidates = [
        entry for entry in entries
        if entry.get("SupportedPlatform") == "ios"
        and not entry.get("SupportedPlatformVariant")
        and "arm64" in entry.get("SupportedArchitectures", [])
    ]
    if len(candidates) != 1:
        raise ValueError(f"{name}: expected one iOS arm64 device slice, found {len(candidates)}")

    entry = candidates[0]
    identifier = entry.get("LibraryIdentifier", "")
    library = entry.get("LibraryPath", "")
    if not identifier or not library:
        raise ValueError(f"{name}: incomplete device slice metadata")
    binary = framework / identifier / library
    if library.endswith(".framework"):
        binary = binary / pathlib.Path(library).stem
    if not binary.resolve().is_relative_to(framework.resolve()) or not binary.is_file():
        raise ValueError(f"{name}: missing or invalid device binary")
    return binary


def _build_versions(otool_output, *, archive=False, expected_members=None):
    versions = []
    lines = otool_output.splitlines()
    members = [
        (i, match.group(1))
        for i, line in enumerate(lines)
        if (match := re.fullmatch(
            r".*\.a\(([^)]+)\)(?: \(architecture [^)]+\))?:", line.strip()
        ))
    ]
    member_starts = [start for start, _ in members]
    version_lines = []
    for i, line in enumerate(lines):
        if line.strip() != "cmd LC_BUILD_VERSION":
            continue
        platform = None
        minimum = None
        for next_line in lines[i + 1:i + 12]:
            value = next_line.strip()
            if value.startswith("platform "):
                platform = value.split(None, 1)[1].upper()
            if value.startswith("minos "):
                minimum = value.split(None, 1)[1]
            if value.startswith("cmd ") or value.startswith("Load command "):
                break
        if platform is None or minimum is None:
            raise ValueError("incomplete Mach-O LC_BUILD_VERSION")
        try:
            parts = tuple(int(part) for part in minimum.split("."))
        except ValueError as exc:
            raise ValueError("invalid Mach-O minimum iOS version") from exc
        if not 1 <= len(parts) <= 3:
            raise ValueError("invalid Mach-O minimum iOS version")
        versions.append((platform, parts))
        version_lines.append(i)
    if archive:
        if not member_starts:
            raise ValueError("archive member metadata missing from otool output")
        if expected_members is not None and Counter(name for _, name in members) != Counter(expected_members):
            raise ValueError("archive inventory mismatch between ar and otool")
        for index, start in enumerate(member_starts):
            end = member_starts[index + 1] if index + 1 < len(member_starts) else len(lines)
            if not any(start < version_line < end for version_line in version_lines):
                raise ValueError("archive member missing Mach-O LC_BUILD_VERSION")
    return versions


def verify_frameworks(frameworks, run_command=None):
    root = pathlib.Path(frameworks)
    runner = run_command or _run
    for name in REQUIRED_FRAMEWORKS:
        binary = _device_binary(root / f"{name}.xcframework", name)
        arch = runner(["xcrun", "lipo", "-verify_arch", "arm64", str(binary)])
        if arch.returncode != 0:
            raise ValueError(f"{name}: native arm64 architecture verification failed")
        result = runner(["xcrun", "otool", "-arch", "arm64", "-l", str(binary)])
        if result.returncode != 0:
            raise ValueError(f"{name}: native Mach-O inspection failed")
        archive = binary.suffix == ".a"
        expected_members = None
        if archive:
            inventory = runner(["xcrun", "ar", "-t", str(binary)])
            if inventory.returncode != 0:
                raise ValueError(f"{name}: native archive inventory inspection failed")
            expected_members = [
                member.strip() for member in inventory.stdout.splitlines()
                if member.strip() and not member.strip().startswith("__.SYMDEF")
            ]
            if not expected_members:
                raise ValueError(f"{name}: archive has no inspectable object members")
        versions = _build_versions(
            result.stdout, archive=archive, expected_members=expected_members
        )
        if not versions or any(platform not in ("2", "IOS") for platform, _ in versions):
            raise ValueError(f"{name}: Mach-O build platform is not exclusively iOS device")
        if any(minimum + (0,) * (3 - len(minimum)) > (15, 0, 0) for _, minimum in versions):
            raise ValueError(f"{name}: iOS 15 deployment compatibility failed")
        print(f"{name}: arm64 iOS device platform and iOS 15 deployment verified")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frameworks", type=pathlib.Path, required=True)
    args = parser.parse_args(argv)
    try:
        verify_frameworks(args.frameworks)
    except (ValueError, OSError) as exc:
        print(f"RIME device-slice gate FAILED: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
