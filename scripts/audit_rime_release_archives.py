#!/usr/bin/env python3
"""Audit pinned LibrimeKit v0.1.0 ZIPs without a macOS toolchain.

Checks the published SHA-256, XCFramework device metadata, and *every* arm64
Mach-O object in the iPhoneOS static archive for platform=iOS and minOS<=15.
The macOS xcrun/otool gate, Xcode link, and real-device tests remain required.
ZIP files are read in place; no third-party binary is extracted or patched.
"""

import argparse
import hashlib
import pathlib
import plistlib
import struct
import sys
import zipfile


RELEASE_SHA256 = {
    "librime": "869ad448db92be5855e239f6f61a87d87e84974a4668509a3cbe4d766f294a54",
    "boost_atomic": "4db32b1015c0b2df5b55042e5ec2cced674f8e54e083f7d4aeb1e7db3a6c6925",
    "boost_filesystem": "d22bfd6aa9dd37333710aa5cea19fb065ab270bf2e55551841193bfac5b52af1",
    "boost_regex": "8b13fb6da177e777b76cc9e02d1aed342f922cb3c24f3029e3879f3c2f82fe33",
    "boost_system": "cb3a7cb48499686024923eef902c4327bb021eb8ef25da602a713b9108f56365",
    "libleveldb": "147cd30ee8763ccea573ca9778a5b2ed420c3adf5c91fe1b171fd1799422d103",
    "libmarisa": "cf66bb44fe11d5bc9ce39d61212e5f269bc4cc5045250bc79d62e34205bfc3bb",
    "libopencc": "715f2a323cc3f2b5aaeb3158533fc52ede265dbb54b07ea82f586c68604fe914",
    "libyaml-cpp": "4c277cc6fa3f7330200f16d4454cd77c43c495714465bcb0d506d07d5fcdcc4c",
}


def _macho_build_version(data, expected_platform=2):
    if len(data) < 32 or data[:4] != b"\xcf\xfa\xed\xfe":
        raise ValueError("archive contains a non-arm64 Mach-O object")
    _, cpu, _, _, ncmds, sizecmds, _, _ = struct.unpack_from("<IiiIIIII", data)
    if cpu != 0x0100000C or not 0 < ncmds < 10000 or 32 + sizecmds > len(data):
        raise ValueError("invalid arm64 Mach-O header")
    offset = 32
    versions = []
    for _ in range(ncmds):
        if offset + 8 > 32 + sizecmds:
            raise ValueError("truncated Mach-O load command")
        cmd, size = struct.unpack_from("<II", data, offset)
        if size < 8 or offset + size > 32 + sizecmds:
            raise ValueError("invalid Mach-O load command length")
        if cmd == 0x32:
            if size < 24:
                raise ValueError("truncated LC_BUILD_VERSION")
            platform, encoded = struct.unpack_from("<II", data, offset + 8)
            minimum = (encoded >> 16, (encoded >> 8) & 255, encoded & 255)
            versions.append((platform, minimum))
        offset += size
    if len(versions) != 1:
        raise ValueError("missing or duplicate Mach-O LC_BUILD_VERSION")
    platform, minimum = versions[0]
    if platform != expected_platform:
        kind = "device" if expected_platform == 2 else "simulator"
        raise ValueError(f"Mach-O platform is not iOS {kind}")
    if minimum > (15, 0, 0):
        raise ValueError("Mach-O minimum OS exceeds iOS 15")
    return versions[0]


def inspect_archive(data, expected_platform=2):
    """Return (platform, minOS) for every non-index member of a BSD ar archive."""
    if not data.startswith(b"!<arch>\n"):
        raise ValueError("invalid static archive magic")
    offset = 8
    versions = []
    while offset < len(data):
        if offset + 60 > len(data):
            raise ValueError("truncated static archive member")
        header = data[offset:offset + 60]
        if header[58:60] != b"`\n":
            raise ValueError("invalid static archive member header")
        try:
            size = int(header[48:58].decode("ascii").strip())
            name = header[:16].decode("ascii").strip().rstrip("/")
        except (ValueError, UnicodeError) as exc:
            raise ValueError("invalid static archive member metadata") from exc
        start = offset + 60
        end = start + size
        if end > len(data):
            raise ValueError("truncated static archive payload")
        member = data[start:end]
        offset = end + (size & 1)
        if name.startswith("#1/"):
            try:
                length = int(name[3:])
            except ValueError as exc:
                raise ValueError("invalid BSD archive member name") from exc
            if length > len(member):
                raise ValueError("truncated BSD archive member name")
            name = member[:length].rstrip(b"\0").decode("utf-8")
            member = member[length:]
        if name.startswith("__.SYMDEF") or name in ("", "/", "//"):
            continue
        versions.append(_macho_build_version(member, expected_platform=expected_platform))
    if not versions:
        raise ValueError("no Mach-O object members in device archive")
    return versions


def audit_zip(path, name):
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != RELEASE_SHA256[name]:
        raise ValueError(f"{name}: release SHA-256 mismatch")
    with zipfile.ZipFile(path) as bundle:
        if len(bundle.infolist()) > 100 or sum(e.file_size for e in bundle.infolist()) > 150_000_000:
            raise ValueError(f"{name}: oversized XCFramework ZIP")
        prefix = f"{name}.xcframework/"
        metadata = plistlib.loads(bundle.read(prefix + "Info.plist"))
        results = []
        for variant, platform in ((None, 2), ("simulator", 7)):
            entries = [e for e in metadata["AvailableLibraries"]
                       if e.get("SupportedPlatform") == "ios"
                       and e.get("SupportedPlatformVariant") == variant
                       and "arm64" in e.get("SupportedArchitectures", [])]
            if len(entries) != 1:
                raise ValueError(f"{name}: expected exactly one iOS arm64 {variant or 'device'} slice")
            entry = entries[0]
            identifier = entry["LibraryIdentifier"]
            library = entry["LibraryPath"]
            if "/" in identifier or "\\" in identifier or pathlib.PurePosixPath(library).name != library or not library.endswith(".a"):
                raise ValueError(f"{name}: unsafe or unsupported XCFramework library path")
            archive = bundle.read(prefix + identifier + "/" + library)
            results.append(inspect_archive(archive, expected_platform=platform))
        return tuple(results)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zips-dir", required=True, type=pathlib.Path)
    args = parser.parse_args(argv)
    for name in RELEASE_SHA256:
        path = args.zips_dir / f"{name}.zip"
        if not path.is_file():
            path = args.zips_dir / f"{name}.xcframework.zip"
        try:
            device, simulator = audit_zip(path, name)
        except (OSError, ValueError, KeyError, zipfile.BadZipFile) as exc:
            print(f"{name}: FAIL: {exc}", file=sys.stderr)
            return 1
        print(f"{name}: PASS SHA-256, iOS arm64 device {len(device)} objects "
              f"(max minOS={max(minimum for _, minimum in device)}), "
              f"simulator {len(simulator)} objects "
              f"(max minOS={max(minimum for _, minimum in simulator)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
