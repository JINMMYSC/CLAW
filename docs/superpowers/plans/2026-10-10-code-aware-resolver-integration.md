# Code-Aware Resolver Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add PR #10's exact-build, fail-closed offline diagnostic resolver to the PR #19 integration lineage.

**Architecture:** The existing CI manifest remains developer-only. A standalone Python resolver consumes that manifest plus an explicitly exported redacted diagnostics JSON file, validates the complete source SHA, and returns only bounded, sanitized location evidence. It never uploads source or diagnostics and never claims a dynamic stack or root cause.

**Tech Stack:** Python 3 standard library, unittest, GitHub Actions.

## Global Constraints

- Inputs remain local developer artifacts and are never packaged into the IPA.
- Require a full 40-character lowercase hexadecimal commit SHA.
- Reject schema mismatch, missing inventory, invalid event collections, ambiguous filenames, and invalid line numbers.
- Analyze at most 2,000 warning/error events.
- Limit diagnostic input to 5 MB and manifest input to 50 MB.
- Preserve the user-visible warning that source location is instrumentation evidence, not a verified root cause.

---

### Task 1: Prove the resolver is absent on the integration baseline

**Files:**
- Create: `tools/tests/test_resolve_claw_diagnostic.py`
- Create later: `tools/resolve_claw_diagnostic.py`

**Interfaces:**
- Consumes: manifest schema v1 and capture schema v1.
- Produces: `resolve(manifest: dict, capture: dict) -> dict`.

- [ ] **Step 1: Add the existing PR #10 resolver tests unchanged**

Copy blob `tools/tests/test_resolve_claw_diagnostic.py` from commit `8221c7f95b9661156005f48ccc9036f8f1aef5d1`. The tests cover exact SHA matching, missing/wrong SHA, colliding Swift basenames, invalid lines, malicious action text, and unsupported schemas.

- [ ] **Step 2: Run the focused test and observe RED**

Run:

```bash
python3 -m unittest tools.tests.test_resolve_claw_diagnostic -v
```

Expected: import fails because `tools/resolve_claw_diagnostic.py` is absent.

- [ ] **Step 3: Commit the red test**

```bash
git add tools/tests/test_resolve_claw_diagnostic.py
git commit -m "test(code-aware): require fail-closed diagnostic resolver"
```

### Task 2: Add the minimal audited resolver

**Files:**
- Create: `tools/resolve_claw_diagnostic.py`
- Test: `tools/tests/test_resolve_claw_diagnostic.py`

**Interfaces:**
- `safe_field(value) -> str`: allow only the bounded diagnostic identifier grammar.
- `resolve(manifest: dict, capture: dict) -> dict`: return sanitized location evidence.
- CLI: `--manifest PATH --capture PATH --out PATH`.

- [ ] **Step 1: Add the existing PR #10 resolver unchanged**

Copy blob `tools/resolve_claw_diagnostic.py` from commit `8221c7f95b9661156005f48ccc9036f8f1aef5d1`.

- [ ] **Step 2: Run the focused test and observe GREEN**

```bash
python3 -m unittest tools.tests.test_resolve_claw_diagnostic -v
```

Expected: 5 tests pass.

- [ ] **Step 3: Run the complete Python tool suite**

```bash
python3 -m unittest discover -s tools/tests -p 'test_*.py' -v
```

Expected: all Code-Aware tests pass with no errors.

- [ ] **Step 4: Verify privacy and packaging boundaries**

```bash
git grep -n "resolve_claw_diagnostic" -- .github Packages Hamster HamsterKeyboard
git grep -n "tools/resolve_claw_diagnostic.py" -- .github/workflows/build-ipa.yml
```

Expected: no runtime model invocation, automatic upload, or IPA packaging reference.

- [ ] **Step 5: Commit**

```bash
git add tools/resolve_claw_diagnostic.py
git commit -m "feat(code-aware): integrate fail-closed exact-build resolver"
```

### Task 3: Integration verification

- [ ] Run Build Test on the exact child-branch SHA.
- [ ] Confirm the Code-Aware manifest artifact still identifies the exact SHA.
- [ ] Merge the two reviewed commits into `work/claw-unified-p0-20261010`.
- [ ] Re-run Build Test, Startup Smoke, and signed IPA on the resulting integration SHA.
