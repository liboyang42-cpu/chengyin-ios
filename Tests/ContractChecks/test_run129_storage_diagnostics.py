"""Bounded synthetic diagnostics; runtime OSStatus is still NOT_RUN here."""
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'App/TemplateAuthoringSecureStorage.swift'
ORIGINAL = ROOT / 'tools/tests/fixtures/run129_published_sources/TemplateAuthoringSecureStorage.swift.txt'


def verify(source):
    assert 'private enum DiagnosticOperation: String { case read, update, add, remove, missingScope }' in source
    start = source.index('    private func recordDiagnostic(')
    end = source.index('\n    }', start) + len('\n    }')
    diagnostic = source[start:end]
    assert '("--ui-template-authoring")' in diagnostic and '("--template-author-creator")' in diagnostic
    assert 'Self.diagnosticCount < 32 else { return }' in diagnostic
    assert 'Self.diagnosticCount += 1' in diagnostic
    assert 'status: OSStatus?' in diagnostic and 'operation: String' not in diagnostic
    assert 'let code = status.map { String($0) } ?? "not_called"' in diagnostic
    prints = re.findall(r'^\s*print\((.*)\)$', source, re.M)
    assert prints == ['"WORKSHOP_CREATOR_STORAGE operation=\\(operation.rawValue) osstatus=\\(code)"']
    lines = source.splitlines(True); release = []; enclosed = False; blocks = 0
    for line in lines:
        if line.strip() == '#if DEBUG && targetEnvironment(simulator)':
            assert not enclosed; enclosed = True; blocks += 1
        elif line.strip() == '#endif':
            assert enclosed; enclosed = False
        else:
            assert not line.lstrip().startswith(('#if', '#else', '#elseif'))
            if not enclosed: release.append(line)
    assert not enclosed and blocks == 6
    production = ''.join(release)
    assert 'print(' not in production and 'recordDiagnostic' not in production
    production = production.replace('            let added = SecItemAdd(insertion as CFDictionary, nil)\n            guard added == errSecSuccess',
                                    '            guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess')
    assert production == ORIGINAL.read_text(), 'Production storage logic or errors changed'
    operations = re.findall(r'recordDiagnostic\(\.(\w+), status: ([^)]+)\)', source)
    assert operations == [('missingScope','nil'),('read','status'),('update','status'),('add','added'),('remove','status')]


class Run129StorageDiagnostics(unittest.TestCase):
    def test_exact_diagnostic_keeps_release_storage_and_errors_identical(self):
        verify(SOURCE.read_text())

    def test_missing_flag_unbounded_or_nonsimulator_logging_fails_closed(self):
        source = SOURCE.read_text()
        changes = [('arguments.contains("--template-author-creator")', 'true'),
                   ('arguments.contains("--ui-template-authoring")', 'true'),
                   ('Self.diagnosticCount < 32', 'true'),
                   ('#if DEBUG && targetEnvironment(simulator)', '#if DEBUG'),
                   ('#if DEBUG && targetEnvironment(simulator)', '#if true')]
        for before,after in changes:
            with self.subTest(before=before,after=after):
                with self.assertRaises(AssertionError): verify(source.replace(before,after,1))

    def test_content_or_arbitrary_operation_or_fabricated_code_is_rejected(self):
        source = SOURCE.read_text()
        changes = [('operation: DiagnosticOperation', 'operation: String'),
                   ('operation=\\(operation.rawValue)', 'operation=\\(key)'),
                   ('osstatus=\\(code)', 'osstatus=\\(data)'),
                   ('"not_called"', '"-34018"'),
                   ('status: status)', 'status: -34018)')]
        for before,after in changes:
            with self.subTest(before=before):
                self.assertIn(before,source)
                with self.assertRaises(AssertionError): verify(source.replace(before,after,1))

    def test_changed_secure_storage_projection_cannot_hide_behind_diagnostics(self):
        source = SOURCE.read_text()
        for before,after in [('throw TemplateAuthoringError.storageUnavailable', 'return nil'),
                             ('kSecAttrSynchronizable as String: false', 'kSecAttrSynchronizable as String: true')]:
            with self.assertRaises(AssertionError): verify(source.replace(before,after,1))


if __name__ == '__main__': unittest.main()
