"""Regression coverage for the public-checkout external-source boundary."""
import importlib.util
import os
import pathlib
import tempfile
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('flutter_source', ROOT / 'Tests/ContractChecks/flutter_source.py')
source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source)


class ExternalFlutterSourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name) / 'app-audit'
        self.patch = mock.patch.object(source, 'DEFAULT_SOURCE_ROOT', self.root)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.environment = mock.patch.dict(os.environ, {}, clear=True)
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def test_absent_optional_checkout_reports_not_run(self):
        with self.assertRaisesRegex(unittest.SkipTest, 'External Flutter parity NOT_RUN'):
            source.read_flutter_source(self, 'data/api/example.dart')

    def test_present_checkout_with_missing_file_fails(self):
        self.root.mkdir()
        with self.assertRaises(FileNotFoundError):
            source.read_flutter_source(self, 'data/api/example.dart')

    def test_present_source_is_read_without_skipping(self):
        path = self.root / 'lib/data/api/example.dart'
        path.parent.mkdir(parents=True)
        path.write_text("const route = '/api/example';")
        self.assertEqual(source.read_flutter_source(self, 'data/api/example.dart'), path.read_text())

    def test_explicit_source_root_is_honored(self):
        alternate = pathlib.Path(self.temp.name) / 'provided'
        (alternate / 'lib').mkdir(parents=True)
        (alternate / 'lib/example.dart').write_text('provided source')
        os.environ[source.SOURCE_ROOT_ENV] = str(alternate)
        self.assertEqual(source.read_flutter_source(self, 'example.dart'), 'provided source')

    def test_missing_explicit_source_root_fails(self):
        os.environ[source.SOURCE_ROOT_ENV] = str(self.root)
        with self.assertRaises(FileNotFoundError):
            source.read_flutter_source(self, 'example.dart')

    def test_malformed_present_source_is_not_skipped(self):
        path = self.root / 'lib/example.dart'
        path.parent.mkdir(parents=True)
        path.write_bytes(b'\xff')
        with self.assertRaises(UnicodeDecodeError):
            source.read_flutter_source(self, 'example.dart')
