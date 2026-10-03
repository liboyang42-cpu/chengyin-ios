"""Regression tests for the conservative private-home logging-call source guard."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("private_home_guard_for_tests", ROOT / "tools/check_private_home.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PrivateHomeLoggingGuardTests(unittest.TestCase):
    def test_actual_print_calls_are_rejected_with_qualification_and_whitespace(self):
        for source in ['print(payload)', 'Swift.print(payload)', 'print (payload)',
                       'Swift.print\t(payload)', 'print\n(payload)', 'print\r\n (payload)']:
            with self.subTest(source=source):
                self.assertTrue(module.has_logging_call(source))

    def test_fingerprint_and_other_longer_identifiers_are_not_logging_calls(self):
        for source in ['fingerprint(payload)', 'try fingerprint (payload)',
                       'private func fingerprint(_ value: Data) -> Data', 'blueprint(value)']:
            with self.subTest(source=source):
                self.assertFalse(module.has_logging_call(source))

    def test_other_logging_calls_remain_rejected(self):
        for source in ['os_log(payload)', 'os_log (payload)', 'Logger ()',
                       'debugPrint(payload)', 'Swift.dump (payload)']:
            with self.subTest(source=source):
                self.assertTrue(module.has_logging_call(source))


if __name__ == '__main__':
    unittest.main()
