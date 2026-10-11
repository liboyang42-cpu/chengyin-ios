#!/usr/bin/env python3
"""P107 read-error source checks. These do not compile or execute Swift/XCTest."""
import argparse
import hashlib
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
CORE = 'Core/ProfileEditCoordinator.swift'
TESTS = 'Tests/CoreTests/ProfileEditTests.swift'
HELPER = '''    /// Only the explicit server-facing explanation is presentable. Transport/debug
    /// descriptions can contain URLs or credentials and must never become UI text.
    /// A whitespace-only explanation falls back to the existing localized status.
    private static func readFailureMessage(_ error: Error) -> String? {
        guard let message = (error as? ProfileReadFailure)?.message,
              !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return message
    }
'''
ASSIGN = '            remoteMessage = Self.readFailureMessage(error)\n'

def errors(source):
    result = []
    if source.count(HELPER) != 1:
        result.append('explicit server message helper differs')
    contexts = [
        'guard active(expected, request) else { return false }\n' + ASSIGN + '            messageKey = isLocked',
        'guard active(expected, request) else { return }\n' + ASSIGN + '            messageKey = "profile.edit.loadFailed"',
        'guard active(expected, request) else { return }\n' + ASSIGN + '            messageKey = "profile.edit.unknown"',
    ]
    for context, count in zip(contexts, [1, 2, 1]):
        if source.count(context) != count:
            result.append('missing gated read-failure site')
    if source.count(ASSIGN) != 4:
        result.append('read-failure assignment count')
    return result

def inverse(source):
    if errors(source):
        raise ValueError('candidate failed exact current source checks')
    return source.replace(ASSIGN, '').replace(HELPER, '')


OLD_COORDINATOR_SHA256 = '2abfe23ec770e6c0b6781c42b3a5b502a4855a8394ba46a4db5857eed563bb7b'
CURRENT_COORDINATOR_SHA256 = 'bbd462eed41321ab249fda4e2f80e48aad51942cc6ce195bbd45b7e52b1e1b67'
OLD_CORE_TESTS_SHA256 = '4d4468b05bf394c5bbc37b2d8db934d4d24275092d7f4b72a18b36c09e0d2a50'


def validated_original_coordinator(data):
    """Strict current-stage gate followed by a bounded raw-byte inverse.

    Old source is NOT a completed upgrade. No newline/Unicode normalization is
    performed, and the final old digest protects every untouched source byte.
    """
    if hashlib.sha256(data).hexdigest() != CURRENT_COORDINATOR_SHA256:
        raise ValueError('not the complete admitted current Coordinator bytes')
    source = data.decode('utf-8')
    if errors(source):
        raise ValueError('current read-error behavior/fences differ')
    assignment, helper = ASSIGN.encode('utf-8'), HELPER.encode('utf-8')
    if data.count(assignment) != 4 or data.count(helper) != 1:
        raise ValueError('nonunique read-error inverse regions')
    original = data.replace(assignment, b'').replace(helper, b'')
    if hashlib.sha256(original).hexdigest() != OLD_COORDINATOR_SHA256:
        raise ValueError('original Coordinator bytes differ')
    return original


def historical_coordinator_input(data):
    """Only for old preservation assertions, NOT a current-stage positive gate.

    The genuine old file remains a valid input to historical tests. Every other
    input must pass the strict new-stage gate before recovering old bytes.
    """
    if hashlib.sha256(data).hexdigest() == OLD_COORDINATOR_SHA256:
        return data
    return validated_original_coordinator(data)


def coordinator_byte_mutations(data):
    """Changes inside and outside the insertion; all operate on raw bytes."""
    yield 'CRLF conversion', data.replace(b'\n', b'\r\n')
    yield 'BOM', b'\xef\xbb\xbf' + data
    yield 'invalid UTF8', data + b'\xff'
    yield 'trailing whitespace', data + b' '
    yield 'leading comment', b'// drift\n' + data
    yield 'old text changed', data.replace(b'private var generation = 0', b'private var generation = 1', 1)
    yield 'session fence changed', data.replace(b'currentSession() == expected && !Task.isCancelled', b'true', 1)
    yield 'lock changed', data.replace(b'if unresolved.acknowledged && matches', b'if matches', 1)
    yield 'lost cancellation', data.replace(b'!Task.isCancelled', b'true', 1)
    yield 'unsafe error string', data.replace(b'(error as? ProfileReadFailure)?.message', b'error.localizedDescription', 1)
    yield 'empty filter removed', data.replace(b'!message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty', b'true', 1)
    yield 'rewritten explanation', data.replace(b'return message\n    }\n    private func reconcile', b'return message.uppercased()\n    }\n    private func reconcile', 1)
    for index, match in enumerate(re.finditer(re.escape(ASSIGN.encode()), data)):
        yield 'missing assignment ' + str(index), data[:match.start()] + data[match.end():]
    yield 'duplicate helper', data + HELPER.encode()
    yield 'extra assignment', data + ASSIGN.encode()

class ProfileReadFailureContracts(unittest.TestCase):
    def test_strict_current_stage_recovers_exact_original_bytes(self):
        data = (ROOT / CORE).read_bytes()
        original = validated_original_coordinator(data)
        self.assertEqual(hashlib.sha256(original).hexdigest(), OLD_COORDINATOR_SHA256)
        self.assertEqual(historical_coordinator_input(data), original)

    def test_current_gate_rejects_baseline_but_historical_gate_accepts_it(self):
        original = validated_original_coordinator((ROOT / CORE).read_bytes())
        with self.assertRaises(ValueError):
            validated_original_coordinator(original)
        self.assertEqual(historical_coordinator_input(original), original)

    def test_all_raw_byte_drift_controls_fail_both_gates(self):
        data = (ROOT / CORE).read_bytes()
        variants = list(coordinator_byte_mutations(data))
        self.assertEqual(len(variants), 18)
        self.assertEqual(len({name for name, _ in variants}), 18)
        self.assertEqual(len({mutant for _, mutant in variants}), 18)
        for name, mutant in variants:
            with self.subTest(mutation=name):
                self.assertNotEqual(mutant, data)
                with self.assertRaises(ValueError):
                    validated_original_coordinator(mutant)
                with self.assertRaises(ValueError):
                    historical_coordinator_input(mutant)

    def test_complete_original_xctest_bytes_remain_before_append(self):
        data = (ROOT / TESTS).read_bytes()
        marker = b'\n/// Source-backed read-error presentation only. All services are in-memory; no live writes.\n'
        self.assertEqual(data.count(marker), 1)
        original = data.split(marker, 1)[0]
        self.assertEqual(hashlib.sha256(original).hexdigest(), OLD_CORE_TESTS_SHA256)

    def test_four_read_failures_are_gated_before_presentation(self):
        self.assertEqual(errors((ROOT / CORE).read_text()), [])

    def test_all_eight_existing_current_session_checks_stay_present(self):
        source = (ROOT / CORE).read_text()
        self.assertIn('currentSession() == expected && !Task.isCancelled', source)
        self.assertIn('guard currentSession() == expected, !Task.isCancelled else { throw CancellationError() }', source)
        self.assertGreaterEqual(source.count('guard active(expected, request)'), 8)

    def test_literal_app_presentation_and_reload_draft_retention_remain(self):
        view = (ROOT / 'App/ProfileEditView.swift').read_text()
        self.assertIn('if let remote = model.coordinator.remoteMessage { Text(verbatim: remote) }', view)
        self.assertIn('if loaded, let snapshot = coordinator.snapshot { draft = snapshot.draft }', view)

    def test_pending_lock_and_no_automatic_post_retry_remain(self):
        source = (ROOT / CORE).read_text()
        self.assertIn('if unresolved.acknowledged && matches', source)
        self.assertIn('messageKey = "profile.edit.readbackUnconfirmed"', source)
        load = source.split('@discardableResult public func load()', 1)[1].split('public func prepare(', 1)[0]
        self.assertNotIn('service.save', load)
        self.assertNotIn('pending[', load)

    def test_new_requests_and_session_changes_clear_messages(self):
        source = (ROOT / CORE).read_text()
        self.assertEqual(source.count('messageKey = nil; remoteMessage = nil'), 4)

    def test_each_removed_presentation_site_is_rejected(self):
        source = (ROOT / CORE).read_text()
        positions = [m.start() for m in re.finditer(re.escape(ASSIGN), source)]
        self.assertEqual(len(positions), 4)
        for start in positions:
            self.assertTrue(errors(source[:start] + source[start + len(ASSIGN):]))

    def test_each_missing_active_fence_is_rejected(self):
        source = (ROOT / CORE).read_text()
        matches = list(re.finditer(r'            guard active\(expected, request\) else \{ return(?: false)? \}\n(?=' + re.escape(ASSIGN) + ')', source))
        self.assertEqual(len(matches), 4)
        for match in matches:
            self.assertTrue(errors(source[:match.start()] + source[match.end():]))

    def test_debug_blank_and_rewritten_message_mutations_are_rejected(self):
        source = (ROOT / CORE).read_text()
        for old, new in [
            ('(error as? ProfileReadFailure)?.message', 'error.localizedDescription'),
            ('(error as? ProfileReadFailure)?.message', 'String(reflecting: error)'),
            ('!message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty', 'true'),
            ('return message\n    }\n    private func reconcile', 'return message.uppercased()\n    }\n    private func reconcile'),
        ]:
            self.assertIn(old, source)
            self.assertTrue(errors(source.replace(old, new, 1)))

    def test_twelve_new_xctests_are_authored_not_claimed_executed(self):
        tests = (ROOT / TESTS).read_text().split('final class ProfileReadFailureRecoveryTests', 1)[1].split('@MainActor private final class', 1)[0]
        self.assertEqual(len(re.findall(r'    func test\w+\(', tests)), 12)
        self.assertNotIn('XCTSkip', tests)
        self.assertIn('withUnsafeCurrentTask', tests)
        self.assertIn('synthetic-replacement', tests)
        self.assertIn('INTERNAL_SENTINEL_DO_NOT_DISPLAY', tests)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=ROOT)
    args, remaining = parser.parse_known_args()
    ROOT = args.root.resolve()
    unittest.main(argv=[__file__, *remaining])
