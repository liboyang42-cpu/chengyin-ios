"""Source-only preflight for run91 regressions; does not execute Swift/XCTest."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def phone_fixture(source):
    match = re.search(r'var phoneResponse = #"(.*?)"#', source)
    if not match:
        return False
    value = json.loads(match[1])
    return value.get('data', {}).get('id') == 7 and value.get('token') == 'synthetic-7'


def delimiter_trim(source):
    return 'chunk.dropFirst(header.count).dropLast("\\r\\n".count)' in source and 'chunk.dropFirst(header.count).dropLast(2)' not in source


class CompositionRegressionPreflightTests(unittest.TestCase):
    def test_positive_phone_fixture_and_reject_token_only_negative_control(self):
        source = (ROOT / 'Tests/AppUnitTests/PlayReadCompositionTests.swift').read_text()
        self.assertTrue(phone_fixture(source))
        self.assertFalse(phone_fixture(source.replace(',"data":{"id":7}', '')))
        self.assertIn('guard session.account?.id == 7 else { throw APIError.malformedResponse }', source)
        self.assertIn('testInvalidPhoneIdentityCannotAuthorizePlayReads', source)
        self.assertNotRegex(source, r'(?<!try )await login\(')

    def test_delimiter_trim_and_reject_old_two_character_negative_control(self):
        source = (ROOT / 'Core/ManualMapReadApproval.swift').read_text()
        self.assertTrue(delimiter_trim(source))
        self.assertFalse(delimiter_trim(source.replace('dropLast("\\r\\n".count)', 'dropLast(2)')))
        for guard in ['canonical.httpBody == body', 'chunks.count == 5', 'fields[pieces[0]] == nil', 'Set(fields.keys) == ["longitude", "latitude", "radius", "limit"]']:
            self.assertIn(guard, source)

    def test_runtime_regressions_remain_authored(self):
        source = (ROOT / 'Tests/CoreTests/RoamServiceTests.swift').read_text()
        self.assertIn('testBuilderMultipartPreservesEveryValueCharacterForBothReaderRadii', source)
        self.assertIn('testMalformedMultipartAndUnreviewedFieldsRemainRejected', source)
        self.assertIn('XCTAssertEqual("\\r\\n".count, 1)', source)


if __name__ == '__main__':
    unittest.main()
