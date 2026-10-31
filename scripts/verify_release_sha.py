#!/usr/bin/env python3
"""Fail closed unless a manually dispatched signed release uses one frozen SHA."""

import argparse
import os
import re
import subprocess
import sys


# Only the reviewed release-candidate branch is permitted to request signing.
# This is an accidental-release guard, not a substitute for protected GitHub
# environments, trusted workflows, and required signing approvals.
SIGNED_RELEASE_REF = "refs/heads/feature/claw-ipa-build-candidate-20261030"


def verify_release_ref(github_ref: str) -> None:
    if github_ref != SIGNED_RELEASE_REF:
        raise ValueError("signed release must use the audited release-candidate branch")


def verify_frozen_release_sha(frozen_sha: str, github_sha: str, checkout_sha: str) -> None:
    for name, value in (
        ("frozen", frozen_sha),
        ("GitHub event", github_sha),
        ("checkout", checkout_sha),
    ):
        if not re.fullmatch(r"[0-9a-f]{40}", value or ""):
            raise ValueError(f"{name} SHA must be a full lowercase 40-character commit ID")
    if frozen_sha != github_sha or frozen_sha != checkout_sha:
        raise ValueError("frozen SHA, GitHub event SHA, and checked-out SHA differ")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frozen-sha", required=True)
    parser.add_argument("--github-sha", required=True)
    args = parser.parse_args(argv)
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"], capture_output=True, text=True, check=False
    )
    if result.returncode:
        print("Signed release SHA gate FAILED: cannot read checked-out commit", file=sys.stderr)
        return 1
    try:
        verify_release_ref(os.environ.get("GITHUB_REF", ""))
        verify_frozen_release_sha(
            args.frozen_sha, args.github_sha, result.stdout.strip()
        )
    except ValueError as exc:
        print(f"Signed release SHA gate FAILED: {exc}", file=sys.stderr)
        return 1
    print(f"Signed release source SHA verified: {args.frozen_sha}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
