#!/usr/bin/env python3
"""Build-scoped Swift source-symbol inventory (developer CI artifact only).

Symbols are *syntactic anchors*, not a typechecked call graph or proof a
function executed. Do not package this inventory or private source into IPA.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from datetime import datetime, timezone

DECLARATION = re.compile(
    r"^\s*(?:(?:public|open|internal|private|fileprivate|final|static|class|override|mutating|required|convenience|indirect)\s+)*"
    r"(class|struct|enum|actor|protocol|extension|func|init)\b\s*([^({:]*)"
)
EXCLUDE = {".git", ".build", ".swiftpm", "DerivedData", "Pods", "Carthage"}


def build_manifest(root: Path, sha: str, previous: dict | None = None) -> dict:
    root = root.resolve()
    old = {f["path"]: f for f in (previous or {}).get("files", [])}
    files = []
    reused = 0
    for path in sorted(root.rglob("*.swift")):
        if any(part in EXCLUDE for part in path.relative_to(root).parts):
            continue
        relative = path.relative_to(root).as_posix()
        raw = path.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        if relative in old and old[relative].get("sha256") == digest:
            symbols = old[relative]["symbols"]
            reused += 1
        else:
            symbols = []
            for line_number, line in enumerate(raw.decode("utf-8", errors="replace").splitlines(), 1):
                match = DECLARATION.match(line)
                if match:
                    symbols.append({"kind": match.group(1), "name": match.group(2).strip()[:100],
                                    "line": line_number, "evidence": "regex-declaration"})
        files.append({"path": relative, "sha256": digest,
                      "lineCount": len(raw.splitlines()), "symbols": symbols})
    return {
        "schemaVersion": 1,
        "gitCommit": sha,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "sourceFileCount": len(files),
        "reusedUnchangedFiles": reused,
        "indexPrecision": "syntactic-only: dynamic-dispatch-and-runtime-calls-not-resolved",
        "files": files,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--previous", type=Path)
    args = parser.parse_args()
    root = args.repo.resolve()
    commit = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    previous = None
    if args.previous and args.previous.is_file():
        previous = json.loads(args.previous.read_text(encoding="utf-8"))
    document = build_manifest(root, commit, previous=previous)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(document, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Code-Aware manifest for {commit}: {document['sourceFileCount']} files; "
          f"{document['reusedUnchangedFiles']} unchanged reused")


if __name__ == "__main__":
    main()
