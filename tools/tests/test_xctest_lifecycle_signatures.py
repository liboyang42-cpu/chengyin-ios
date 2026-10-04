"""Source preflight for XCTest's throwing Objective-C lifecycle hooks.

This catches a known Apple compile failure; it does not replace Swift compilation.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
HOOK = re.compile(
    r"\boverride\s+func\s+(setUpWithError|tearDownWithError)\s*\(\s*\)"
    r"(?P<suffix>[^{}]*)\{"
)


def invalid_hooks(source):
    return [
        match.group(1) for match in HOOK.finditer(source)
        if not re.search(r"\bthrows\b", match.group("suffix"))
    ]


class XCTestLifecycleSignaturesTests(unittest.TestCase):
    def test_all_test_sources_preserve_throwing_with_error_overrides(self):
        sources = sorted((ROOT / "Tests").rglob("*.swift"))
        self.assertTrue(sources)
        observed = 0
        for path in sources:
            source = path.read_text()
            observed += len(list(HOOK.finditer(source)))
            with self.subTest(path=str(path.relative_to(ROOT))):
                self.assertEqual(invalid_hooks(source), [])
        self.assertGreater(observed, 0)

    def test_rejects_both_nonthrowing_objc_lifecycle_overrides(self):
        for name in ["setUpWithError", "tearDownWithError"]:
            with self.subTest(name=name):
                self.assertEqual(invalid_hooks(f"override func {name}() {{ }}"), [name])

    def test_preserves_valid_throwing_and_nonthrowing_hook_families(self):
        source = """
            override func setUpWithError() throws { }
            override func tearDownWithError()
                throws
            { }
            override func setUp() { }
            override func tearDown() { }
        """
        self.assertEqual(invalid_hooks(source), [])


if __name__ == "__main__":
    unittest.main()
