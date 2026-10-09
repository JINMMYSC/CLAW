import importlib.util
from pathlib import Path
import tempfile
import unittest

MODULE_PATH = Path(__file__).resolve().parents[1] / "generate_claw_source_manifest.py"
spec = importlib.util.spec_from_file_location("claw_source_index", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CodeAwareManifestTests(unittest.TestCase):
    def test_source_file_sha_symbol_line_and_incremental_equivalence(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "Demo.swift").write_text(
                "import Foundation\nstruct Demo {\n  func begin() {}\n}\n", encoding="utf-8"
            )
            first = module.build_manifest(root, "a" * 40)
            self.assertEqual(first["sourceFileCount"], 1)
            self.assertEqual(first["files"][0]["symbols"][0]["line"], 2)
            self.assertEqual(first["files"][0]["symbols"][1]["line"], 3)
            second = module.build_manifest(root, "b" * 40, previous=first)
            self.assertEqual(second["reusedUnchangedFiles"], 1)
            self.assertEqual(first["files"], second["files"])
            self.assertEqual(second["gitCommit"], "b" * 40)
            (root / "Demo.swift").write_text("class Changed {}\n", encoding="utf-8")
            third = module.build_manifest(root, "c" * 40, previous=second)
            self.assertEqual(third["reusedUnchangedFiles"], 0)
            self.assertEqual(third["files"][0]["symbols"][0]["name"], "Changed")


if __name__ == "__main__":
    unittest.main()
