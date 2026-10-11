"""Readback source guards and negative controls, not Swift runtime or Apple acceptance.

Contract: chengyin@f859cd6e2618f618a53f5cd33949259828e86313.
MerchantAftercareServiceImpl.detailVO computes one current processing/opinion/
refunded tuple before projecting it into every MerchantAftercareResponseVO.from.
The row decision/createTime are historical; these three outcome mirrors are not.
Service blob: e81d7e573cb5d92a805e4ca608d9a6d423a53147.
ResponseVO blob: 21939cb11620919c120f8a1fbb14a5c0a1221b4d.
Detail read is POST in both the mini-program index.js (blob
924cbbffa876fc060f6ef99a419e6b75d3012281) and ApiMerchantAftercareController
(blob be97f358f8a2edd0d71f3d9ee564ecfedb9adaa6) at this same revision.
"""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "Core/MerchantAftercareProgress.swift"
TESTS = ROOT / "Tests/CoreTests/MerchantAftercareProgressTests.swift"


def without_comments(source):
    return re.sub(r"//[^\n]*|/\*.*?\*/", "", source, flags=re.S)


def assert_readback_guard(test, source):
    code = without_comments(source)
    rows = code.split('responses = try fields.mbObjects("responses").map { row in', 1)[1]
    before_response = rows.split('return Response(', 1)[0]
    call = 'try Self.validateResponseReadback(row, processing: processing, opinion: opinion)'
    test.assertEqual(before_response.count(call), 1)
    helper = code.split('private static func validateResponseReadback(', 1)[1].split('private static func text(', 1)[0]
    checks = [
        ('processing', 'string', 'processing.rawValue'),
        ('merchantOpinion', 'string', 'opinion.rawValue'),
        ('refunded', 'bool', '(processing == .refunded)'),
    ]
    for key, accessor, expected in checks:
        pattern = (r'if\s+let\s+value\s*=\s*row\["' + key + r'"\]\s*\{\s*'
                   r'guard\s+value\.' + accessor + r'\s*==\s*' + re.escape(expected)
                   + r'\s+else\s*\{\s*throw\s+MerchantBusinessFailure\.malformed\s*\}\s*\}')
        test.assertRegex(helper, pattern)
    # Validation may reject a conflicting mirror, but cannot derive a new outcome.
    test.assertIn('funds: Funds { processing == .refunded ? .confirmed : .unconfirmed }', code)
    test.assertNotRegex(helper, r'\b(?:self\.|funds\s*=|processing\s*=|opinion\s*=)(?!=)')


READ_TRANSPORT_ASSERTIONS = (
    'XCTFail("Conflicting response outcome must not become an authorized refund document")',
    'XCTAssertEqual(error as? MerchantBusinessFailure, .malformed)',
    'XCTAssertEqual(requests.count, 1)',
    'XCTAssertEqual(requests.first?.httpMethod, "POST")',
    'XCTAssertEqual(requests.first?.url?.path, "/api/merchant/aftercare/detail")',
    'XCTAssertFalse(service.canExecuteSyntheticMutation)',
)


def assert_read_transport_contract(test, source):
    # Scope to the contradictory-outcome test, not assertions in another method.
    method = source.split('func testReadTransportRejectsContradictoryOutcomeWithoutMutation()', 1)[1]
    method = without_comments(method.split('\n    func ', 1)[0])
    for assertion in READ_TRANSPORT_ASSERTIONS:
        test.assertIn(assertion, method)
    test.assertIn('fields["processing"] = .string("REFUNDED")', method)
    test.assertIn('row["refunded"] = .bool(false)', method)
    test.assertIn('try await service.document(.refund(.init(62001)), access: access, token: "synthetic-token")', method)


class MerchantAftercareProgressReadbackContracts(unittest.TestCase):
    def test_response_outcome_mirrors_are_validated_before_projection(self):
        assert_readback_guard(self, CORE.read_text())

    def test_guard_rejects_removal_comment_decoy_type_coercion_and_success_inversion(self):
        source = CORE.read_text()
        mutations = [
            ('missing_call', 'try Self.validateResponseReadback(row, processing: processing, opinion: opinion)', ''),
            ('comment_only_call', 'try Self.validateResponseReadback(row, processing: processing, opinion: opinion)',
             '// try Self.validateResponseReadback(row, processing: processing, opinion: opinion)'),
            ('missing_processing', 'row["processing"]', 'row["ignoredProcessing"]'),
            ('missing_opinion', 'row["merchantOpinion"]', 'row["ignoredOpinion"]'),
            ('missing_funds', 'row["refunded"]', 'row["ignoredRefunded"]'),
            ('processing_inequality', 'value.string == processing.rawValue', 'value.string != processing.rawValue'),
            ('historical_decision', 'value.string == opinion.rawValue', 'value.string == row["decision"]?.string'),
            ('coerced_refunded', 'value.bool == (processing == .refunded)', 'value.integer == 1'),
            ('success_inversion', 'value.bool == (processing == .refunded)', 'value.bool == (processing != .refunded)'),
            ('swallowed_mismatch', 'guard value.bool == (processing == .refunded) else { throw MerchantBusinessFailure.malformed }',
             'guard value.bool == (processing == .refunded) else { return }'),
            ('null_ignored', 'if let value = row["refunded"] {', 'if let value = row["refunded"], value != .null {'),
        ]
        for name, original, replacement in mutations:
            with self.subTest(mutation=name):
                self.assertIn(original, source)
                changed = source.replace(original, replacement, 1)
                self.assertNotEqual(source, changed)
                with self.assertRaises((AssertionError, IndexError)):
                    assert_readback_guard(self, changed)

    def test_authored_swift_covers_current_historical_conflicting_and_missing_readback(self):
        source = TESTS.read_text()
        for name in [
            'testResponseReadbackMatchesCurrentSnapshotAcrossEveryStateAndOpinion',
            'testContradictoryResponseReadbackRejectsBothDirectionsAtDocumentBoundary',
            'testProvidedResponseReadbackRejectsNullUnknownAndWrongTypes',
            'testOmittedResponseReadbackNeverCreatesFundsOrHistoricalState',
            'testResponseReadbackCannotReplaceMissingCurrentOutcome',
            'testReadTransportRejectsContradictoryOutcomeWithoutMutation',
        ]:
            self.assertIn('func ' + name, source)
        self.assertIn('MerchantAftercareProgress.Processing.allCases', source)
        self.assertIn('MerchantAftercareProgress.Opinion.allCases', source)
        self.assertIn('XCTAssertEqual(value.responses.first?.decision, .reject)', source)
        self.assertIn('XCTAssertEqual(value.responses.first?.decision, .agree)', source)
        self.assertIn('XCTAssertNil(value.responses.first?.occurredAt)', source)
        assert_read_transport_contract(self, source)

    def test_read_transport_contract_rejects_wrong_method_and_missing_or_commented_assertions(self):
        source = TESTS.read_text()
        start = source.index("func testReadTransportRejectsContradictoryOutcomeWithoutMutation()")
        end = source.index("\n    func ", start)
        method = source[start:end]
        mutations = [('wrong_http_method',
                      'XCTAssertEqual(requests.first?.httpMethod, "POST")',
                      'XCTAssertEqual(requests.first?.httpMethod, "GET")')]
        for assertion in READ_TRANSPORT_ASSERTIONS:
            mutations.append(('missing:' + assertion, assertion, ''))
            mutations.append(('commented:' + assertion, assertion, '// ' + assertion))
        for name, original, replacement in mutations:
            with self.subTest(mutation=name):
                self.assertEqual(method.count(original), 1)
                changed = source[:start] + method.replace(original, replacement, 1) + source[end:]
                with self.assertRaises((AssertionError, IndexError)):
                    assert_read_transport_contract(self, changed)

    def test_document_validation_remains_before_render_and_has_no_money_side_effect(self):
        document = (ROOT / 'Core/MerchantBusinessDocuments.swift').read_text()
        self.assertIn('_ = try MerchantAftercareProgress(refundID: id.rawValue, fields: object)', document)
        core = without_comments(CORE.read_text())
        for forbidden in ['Date()', 'timeIntervalSinceNow', 'URLSession', 'execute(', 'reserve(', 'UserDefaults', 'FileManager']:
            self.assertNotIn(forbidden, core)


if __name__ == '__main__':
    unittest.main()
