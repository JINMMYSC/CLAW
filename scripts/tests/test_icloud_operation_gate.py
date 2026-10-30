"""Regression guard for real iCloud copy and restore entry points.

This source-level test is not a substitute for native XCTest or a signed-device
iCloud operation. It catches fail-open Info.plist capability checks before CI
spends time on Xcode builds.
"""

import re
import unittest
from pathlib import Path

SOURCE = (Path(__file__).resolve().parents[2] /
          "Packages/HamsteriOS/Sources/ViewModel/iCloud/AppleCloudViewModel.swift")


class ICloudOperationGateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8")

    def test_copy_requires_explicit_boolean_true(self):
        self._assert_strict_guard("copyFileToiCloud", "restoreFromiCloud")

    def test_restore_requires_explicit_boolean_true(self):
        self._assert_strict_guard("restoreFromiCloud", None)

    def test_boolean_helper_rejects_numeric_ones(self):
        self.assertIn("import CoreFoundation", self.source)
        self.assertIn("CFGetTypeID(number) == CFBooleanGetTypeID()", self.source)

    def _assert_strict_guard(self, method, next_method):
        start = self.source.index(f"func {method}() async")
        end = self.source.index(f"func {next_method}() async", start) if next_method else len(self.source)
        body = self.source[start:end]
        self.assertRegex(body, re.compile(
            r'guard\s+hasExplicitTrueBoolean\(Bundle\.main\.object\(forInfoDictionaryKey:\s*'
            r'"ClawICloudContainerEntitled"\)\)\s+else'))
        self.assertNotIn("as? Bool != false", body)
        self.assertLess(body.index("ClawICloudContainerEntitled"),
                        body.index("URL.iCloudDocumentURL"))


if __name__ == "__main__":
    unittest.main()
