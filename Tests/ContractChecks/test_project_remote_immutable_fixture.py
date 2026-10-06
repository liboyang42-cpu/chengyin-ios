"""Immutable fixture/source regression only; this does not compile or execute Swift."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def replacement_body(source):
    name = '    func testExactRecordCASRejectsReplacementBeforeAndAfterBaselineWrite()'
    return source.split(name, 1)[1].split('\n    func ', 1)[0]


def reconstruction_is_complete(source, stored_fields):
    body = replacement_body(source)
    if 'replacement.payload["description"] =' in body:
        return False
    required = [
        'let completed = capture.completed',
        'var payload = completed.payload; payload["description"] = .string("é")',
        'let replacement = ProjectEditPending(',
    ]
    if not all(item in body for item in required):
        return False
    arguments = body.split('let replacement = ProjectEditPending(', 1)[1].split(')', 1)[0]
    labels = re.findall(r'\b(\w+):\s*', arguments)
    if labels != stored_fields:
        return False
    return all(re.search(r'\b' + name + r':\s*' + ('payload' if name == 'payload' else r'completed\.' + name) + r'\b', arguments)
               for name in stored_fields)


class ProjectRemoteImmutableFixtureChecks(unittest.TestCase):
    def setUp(self):
        self.tests = (ROOT / 'Tests/CoreTests/ProjectEditRemoteTests.swift').read_text()
        self.store = (ROOT / 'Core/ProjectEditLocalStore.swift').read_text()
        record = self.store.split('public struct ProjectEditPending: Codable, Equatable {', 1)[1]
        record = record.split('    public var hasConsistentAcknowledgment:', 1)[0]
        self.fields = re.findall(r'(?m)^    public (?:let|var) (\w+):', record)

    def test_production_payload_stays_immutable_and_replacement_preserves_every_other_field(self):
        self.assertIn('public let payload: [String: ProjectEditJSON]', self.store)
        self.assertNotIn('public var payload:', self.store)
        self.assertEqual(self.fields, ['operationID', 'ownerKey', 'identity', 'payload',
                                      'dispatchStarted', 'baseline', 'completedTopicID',
                                      'serverAcknowledged', 'bundleAcknowledgment'])
        self.assertTrue(reconstruction_is_complete(self.tests, self.fields))

    def test_both_unicode_exact_record_cas_boundaries_and_original_assertions_remain(self):
        body = replacement_body(self.tests)
        self.assertIn('"description": .string("e\\u{301}")', self.tests)
        self.assertIn('payload["description"] = .string("é")', body)
        for original in [
            'for midWrite in [false, true]',
            'XCTAssertEqual(replacement.payload, capture.completed.payload)',
            'XCTAssertFalse(ProjectEditLocalStore.exactPending(replacement, capture.completed))',
            'if midWrite { storage.onWrite = { try? store.savePending(replacement, session: session) } }',
            'else { try store.savePending(replacement, session: session) }',
            'XCTAssertFalse(result3)',
            'XCTAssertFalse(storage.events.contains("remove"))',
            'XCTAssertTrue(ProjectEditLocalStore.exactPending(try XCTUnwrap(store.pending(session: session, identity: replacement.identity)), replacement))',
        ]:
            self.assertIn(original, body)
        self.assertEqual(len(re.findall(r'\bfunc test\w+\(', self.tests)), 11)

    def test_old_illegal_mutation_and_dropped_acknowledgment_field_fail_the_same_check(self):
        body = replacement_body(self.tests)
        current = body.split('            let completed = capture.completed', 1)[1].split('            XCTAssertEqual(', 1)[0]
        replacement = '            let completed = capture.completed' + current
        old = self.tests.replace(replacement, '            var replacement = capture.completed; replacement.payload["description"] = .string("é")\n', 1)
        self.assertFalse(reconstruction_is_complete(old, self.fields))
        missing = self.tests.replace(',\n                bundleAcknowledgment: completed.bundleAcknowledgment', '', 1)
        self.assertFalse(reconstruction_is_complete(missing, self.fields))
        altered = self.tests.replace('completedTopicID: completed.completedTopicID', 'completedTopicID: nil', 1)
        self.assertFalse(reconstruction_is_complete(altered, self.fields))


if __name__ == '__main__':
    unittest.main()
