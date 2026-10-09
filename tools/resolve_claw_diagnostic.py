#!/usr/bin/env python3
"""Offline CLAW Code-Aware v1 resolver (developer-side only).

Input: signed-build source manifest + explicitly exported, redacted CLAW
diagnostics JSON. Never upload or send it to a model automatically.
Static source lines are NOT a runtime stack trace or a verified root cause.
"""
import argparse
import json
from pathlib import Path
import re

SHA = re.compile(r"^[a-f0-9]{40}$")
EVENT_ID = re.compile(r"^[a-zA-Z0-9._:/()-]{1,120}$")
SWIFT_FILE = re.compile(r"^(?:[A-Za-z0-9_]+/)*[A-Za-z0-9_+.-]+\.swift$")


def safe_field(value):
    return value if isinstance(value, str) and EVENT_ID.fullmatch(value) else "redacted"


def resolve(manifest: dict, capture: dict) -> dict:
    commit = manifest.get("gitCommit")
    if not isinstance(commit, str) or not SHA.fullmatch(commit):
        raise ValueError("index requires a full, valid 40-character commit SHA")
    if manifest.get("schemaVersion") != 1 or capture.get("schemaVersion") != 1:
        raise ValueError("unsupported manifest/capture schema version")
    files = manifest.get("files")
    if not isinstance(files, list):
        raise ValueError("missing source inventory")
    by_name = {}
    for record in files:
        if not isinstance(record, dict):
            continue
        path = record.get("path")
        if isinstance(path, str) and path.endswith(".swift"):
            by_name.setdefault(path.rsplit("/", 1)[-1], []).append(record)
    events = capture.get("events")
    if not isinstance(events, list):
        raise ValueError("capture has no events")
    out = []
    for e in events[:2000]:
        if not isinstance(e, dict) or e.get("severity") not in ("warning", "error"):
            continue
        item = {
            "module": safe_field(e.get("module")),
            "action": safe_field(e.get("action")),
            "traceID": e.get("traceID") if isinstance(e.get("traceID"), str) and
                re.fullmatch(r"[0-9A-Fa-f-]{36}", e["traceID"]) else None,
        }
        actual = e.get("sourceCommit")
        if not isinstance(actual, str) or not SHA.fullmatch(actual):
            item["status"] = "version_unknown"
        elif actual != commit:
            item["status"] = "version_mismatch"
        else:
            file_id = e.get("file")
            line = e.get("line")
            if not isinstance(file_id, str) or not SWIFT_FILE.fullmatch(file_id):
                item["status"] = "source_unknown"
            else:
                components = file_id.split("/")
                candidates = by_name.get(components[-1], [])
                if len(components) > 1:
                    module = components[0]
                    candidates = [c for c in candidates if module in c["path"].split("/")]
                if len(candidates) == 0:
                    item["status"] = "source_unindexed"
                elif len(candidates) > 1:
                    item["status"] = "source_ambiguous"
                elif not isinstance(line, int) or isinstance(line, bool) or not (
                    1 <= line <= candidates[0].get("lineCount", 0)
                ):
                    item["status"] = "line_unverified"
                else:
                    matched = candidates[0]
                    item.update(status="located", sourcePath=matched["path"],
                                sourceLine=line,
                                locationEvidence="logged Swift #fileID and #line only")
                    anchors = [s for s in matched.get("symbols", [])
                               if isinstance(s.get("line"), int) and s["line"] <= line]
                    if anchors:
                        nearest = max(anchors, key=lambda s: s["line"])
                        item["nearestDeclaration"] = {
                            "name": safe_field(nearest.get("name")),
                            "kind": safe_field(nearest.get("kind")),
                            "line": nearest["line"],
                            "confidence": "heuristic; not a dynamic call graph",
                        }
        out.append(item)
    return {
        "schemaVersion": 1, "gitCommit": commit, "analyzedEventCount": len(out),
        "warning": "Locations come from source instrumentation, not a stack trace. No root cause verified.",
        "results": out,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--capture", required=True, type=Path, help="redacted diagnostics.json, not ZIP")
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    if args.capture.stat().st_size > 5_000_000:
        raise ValueError("diagnostic capture too large")
    if args.manifest.stat().st_size > 50_000_000:
        raise ValueError("source manifest too large")
    index = json.loads(args.manifest.read_text(encoding="utf-8"))
    events = json.loads(args.capture.read_text(encoding="utf-8"))
    args.out.write_text(json.dumps(resolve(index, events), indent=2, ensure_ascii=False),
                        encoding="utf-8")


if __name__ == "__main__":
    main()
