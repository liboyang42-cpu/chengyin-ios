"""Parser-helper tests, including preserved grammar gaps; NOT Swift compiler tests.

Run with the pinned parser venv. Missing dependencies intentionally fail, not skip.
"""
import contextlib
import importlib.util
import io
import pathlib
import subprocess
import tempfile
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("swift_syntax", ROOT / "tools/check_swift_syntax.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

GOOD_TOOLBAR = b'''import SwiftUI
struct Example: View {
    var body: some View {
        Text("Hello").toolbar {
            ToolbarItem { Text("One") }
            ToolbarItem { Text("Two") }
        }
    }
}
'''


class SwiftSyntaxTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.parser = module.make_parser()

    def test_separated_toolbar_items_parse(self):
        self.assertEqual(module.parse_source(self.parser, GOOD_TOOLBAR), [])

    def test_prior_bad_toolbar_adjacency_is_detected(self):
        bad = GOOD_TOOLBAR.replace(b'}\n            ToolbarItem', b'} ToolbarItem')
        diagnostics = module.parse_source(self.parser, bad)
        self.assertTrue(diagnostics)
        self.assertTrue(any(item.kind == "ERROR" and item.line == 5 for item in diagnostics))

    def test_actual_fixed_home_source_parses(self):
        self.assertEqual(module.parse_source(
            self.parser, (ROOT / "App/SessionHomeFeedView.swift").read_bytes()), [])

    def test_missing_brace_is_detected(self):
        self.assertTrue(module.parse_source(self.parser, b'func broken() {\nprint("hello")\n'))

    def test_valid_comment_and_string_are_not_checked_by_regex(self):
        self.assertEqual(module.parse_source(
            self.parser, b'// } ToolbarItem\nlet text = "} ToolbarItem"\n'), [])

    def test_invalid_utf8_fails_closed(self):
        with self.assertRaisesRegex(module.PreflightError, "UTF-8"):
            module.parse_source(self.parser, b'let text = "\xff"')

    def test_missing_anonymous_token_is_reported(self):
        # Known 0.7.3 grammar gap: valid Swift empty-tuple argument gets MISSING !.
        diagnostics = module.parse_source(self.parser, b'func f() { resume?.resume(returning: ()) }')
        self.assertTrue(any(item.kind == "MISSING" and item.node_type == "!" for item in diagnostics))

    def test_known_grammar_gaps_are_not_suppressed(self):
        samples = [
            b'enum E {\ncase a\n#if DEBUG\ncase b\n#endif\n}',
            b'func f() {\nLabel { Text("Title") }\nicon: { Image(systemName: "star") }\n}',
        ]
        for source in samples:
            with self.subTest(source=source):
                self.assertTrue(module.parse_source(self.parser, source))

    def test_diagnostics_include_zero_width_errors(self):
        diagnostics = module.parse_source(self.parser, b'enum E {\ncase a\n#if DEBUG\ncase b\n#endif\n}')
        self.assertTrue(any(item.kind == "ERROR" and item.line == 3 for item in diagnostics))

    def test_dependency_drift_fails_closed(self):
        with mock.patch.object(module.importlib.metadata, "version", return_value="999.0"):
            with self.assertRaisesRegex(module.PreflightError, "required"):
                module.make_parser()

    def test_missing_dependency_fails_closed(self):
        with mock.patch.object(module.importlib.metadata, "version",
                               side_effect=module.importlib.metadata.PackageNotFoundError("tree-sitter")):
            with self.assertRaisesRegex(module.PreflightError, "missing parser dependency"):
                module.make_parser()

    def test_discovery_includes_tracked_and_new_files_but_not_ignored_dependencies(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            (root / ".gitignore").write_text("vendor/\n")
            (root / "Tracked.swift").write_bytes(GOOD_TOOLBAR)
            subprocess.run(["git", "-C", str(root), "add", "Tracked.swift"], check=True)
            (root / "New.swift").write_bytes(GOOD_TOOLBAR)
            (root / "vendor").mkdir()
            (root / "vendor/Dependency.swift").write_text("bad source")
            self.assertEqual([path.name for path in module.swift_paths(root, [])],
                             ["New.swift", "Tracked.swift"])

    def test_empty_discovery_is_not_success(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            with self.assertRaisesRegex(module.PreflightError, "no Swift files"):
                module.swift_paths(root, [])

    def test_cli_exit_codes_and_no_false_success(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            (root / "Good.swift").write_bytes(GOOD_TOOLBAR)
            (root / "Bad.swift").write_text("func broken() {")
            for name, expected in [("Good.swift", 0), ("Bad.swift", 1), ("Missing.swift", 2)]:
                with self.subTest(name=name), contextlib.redirect_stdout(io.StringIO()) as out, \
                     contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(module.main(["--root", str(root), name]), expected)
                    self.assertEqual("PASS" in out.getvalue(), expected == 0)


if __name__ == "__main__":
    unittest.main()
