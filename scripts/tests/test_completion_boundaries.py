import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]


class CompletionBoundaryTests(unittest.TestCase):
    def test_feature_code_writes_memory_only_through_sdk(self):
        allowed = {
            ROOT / "Packages/HamsterKit/Sources/Memory/MemorySDK.swift",
            ROOT / "Packages/HamsterKit/Sources/Memory/Storage/MemoryMigrationV2.swift",
            ROOT / "Packages/HamsterKit/Sources/Services/ClawMemoryCore.swift",
        }
        offenders = []
        roots = [
            ROOT / "Packages/HamsterKit/Sources",
            ROOT / "Packages/HamsteriOS/Sources",
            ROOT / "Packages/HamsterKeyboardKit/Sources",
        ]
        pattern = re.compile(r"(?:ClawMemoryStore\.shared|\bstore)\.(?:upsertMemory|upsertTask)\(")
        for source_root in roots:
            for path in source_root.rglob("*.swift"):
                if path in allowed:
                    continue
                for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                    if pattern.search(line):
                        offenders.append(f"{path.relative_to(ROOT)}:{number}")
        self.assertEqual(offenders, [], "direct Memory store writes remain:\n" + "\n".join(offenders))

    def test_duplicate_people_settings_surface_is_removed(self):
        controller = ROOT / "Packages/HamsteriOS/Sources/UILayer/Settings/HeartTargetSettingsViewController.swift"
        self.assertFalse(controller.exists(), "legacy HeartTarget settings screen still exists")

    def test_startup_smoke_waits_for_migration_marker(self):
        workflow = (ROOT / ".github/workflows/startup-smoke.yml").read_text(encoding="utf-8")
        migration_step = workflow.split("- name: Launch legacy migration regression", 1)[1]
        migration_step = migration_step.split("- name: Capture diagnostics", 1)[0]

        self.assertRegex(
            migration_step,
            re.compile(
                r"for _ in \$\(seq 1 \d+\); do.*"
                r"grep -q \"clawtalk-v1-migration: start\".*"
                r"kill -0 \"\$monitor\".*done",
                re.DOTALL,
            ),
            "startup smoke must poll for the migration marker while the app stays alive",
        )


if __name__ == "__main__":
    unittest.main()

