"""Source/catalog regression contracts only; these do not run SwiftUI or XCTest."""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / 'App/NativeChannelAppealEntry.swift').read_text()
STRINGS = json.loads((ROOT / 'Resources/NativeChannelAppealDetails.xcstrings').read_text())['strings']


def text_calls():
    for match in re.finditer(r'\bText\(', SOURCE):
        depth = 1
        pos = match.end()
        start = pos
        quoted = escaped = False
        while depth:
            char = SOURCE[pos]
            if escaped:
                escaped = False
            elif char == '\\' and quoted:
                escaped = True
            elif char == '"':
                quoted = not quoted
            elif not quoted:
                if char == '(':
                    depth += 1
                elif char == ')':
                    depth -= 1
            pos += 1
        yield SOURCE[start:pos - 1]


class NativeChannelAppealLocalizationContracts(unittest.TestCase):
    def testAllOwnedVisibleTextUsesTheFeatureTable(self):
        self.assertIsNone(re.search(r'[\u3400-\u9fff]', SOURCE))
        for call in text_calls():
            if not call.startswith('verbatim:'):
                self.assertIn('tableName: "NativeChannelAppealDetails"', call)
        for control in ['Button', 'Label', 'TextField', 'navigationTitle', 'confirmationDialog']:
            self.assertNotIn(control + '("', SOURCE)

    def testAllDirectDynamicAndFactKeysResolveInBothLanguages(self):
        keys = set()
        for call in text_calls():
            if not call.startswith('verbatim:'):
                keys.update(re.findall(r'"([^"]+)"', call.split('tableName:')[0]))
        keys.update(re.findall(r'(?:originalFact|fact)\("([^"]+)"', SOURCE))
        keys.update(re.findall(r'(?:case [^\n]+|default): "((?:status|operation)\.[^"]+)"', SOURCE))
        self.assertGreater(len(keys), 70)
        self.assertEqual(keys, set(STRINGS))
        for key in keys:
            for language in ['en', 'zh-Hans']:
                unit = STRINGS[key]['localizations'][language]['stringUnit']
                self.assertEqual(unit['state'], 'translated', key)
                self.assertTrue(unit['value'].strip(), key)
                self.assertNotEqual(unit['value'], key)

    def testOriginalValuesAreNotTranslatedOrFormatted(self):
        for value in ['id', 'flow.reviewedText', 'flow.appealStatus', 'flow.notice.actionID',
                      'flow.deadline', 'flow.actionReason', 'flow.decisionReason', 'value', 'event', 'reason']:
            self.assertIn('Text(verbatim: ' + value + ')', SOURCE)
        self.assertIn('.accessibilityValue(id)', SOURCE)
        self.assertNotIn('String(format:', SOURCE)
        self.assertNotIn('String(localized:', SOURCE)
        self.assertNotIn('Locale.current', SOURCE)

    def testActionHandlersStillUseTheOriginalPermissionAndRecoveryGuards(self):
        for call in ['await flow.confirm()', 'flow.cancelReview()', 'await flow.retryOriginal()',
                     'flow.prepare(.submit, text: explanation)', 'flow.prepare(.evidence, text: explanation)',
                     'flow.prepare(.withdraw, text: explanation)']:
            self.assertEqual(SOURCE.count(call), 1, call)
        for guard in ['if flow.isCurrent', 'if flow.hasPending', 'if flow.journalUnavailable',
                      'if flow.canSubmit', 'if flow.canSupplement', 'if flow.canWithdraw',
                      '.disabled(!flow.canRecover)', '.disabled(!flow.canRetry)', '.disabled(reading)']:
            self.assertIn(guard, SOURCE)
        self.assertEqual(SOURCE.count('.disabled(!validExplanation)'), 3)
        self.assertIn('isPresented: $retryConfirmation, titleVisibility: .visible', SOURCE)

    def testLengthAndLifecycleGuardsRemainExact(self):
        self.assertIn('explanation.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count', SOURCE)
        self.assertIn('explanationCount > 0 && explanationCount <= 500', SOURCE)
        self.assertIn('Text(verbatim: "\\(explanationCount)/500")', SOURCE)
        self.assertIn('Text(explanationCount > 500 ? "input.tooLong" : "input.required", tableName:', SOURCE)
        self.assertIn('.task { await flow.activate() }', SOURCE)
        self.assertIn('.onDisappear { retryConfirmation = false; flow.deactivate() }', SOURCE)
        self.assertIn('else { retryConfirmation = false; flow.deactivate() }', SOURCE)
        self.assertIn('.privacySensitive()', SOURCE)
        self.assertNotIn('.prefix(500)', SOURCE)

    def testStatusKeysHaveAnExplicitUnknownFallback(self):
        for status in ['PENDING', 'REVIEWING', 'UPHELD', 'REVERSED', 'WITHDRAWN']:
            self.assertIn('case "' + status + '": "status.' + status + '"', SOURCE)
        self.assertIn('default: "status.unknown"', SOURCE)
        self.assertNotIn('"status." + flow.appealStatus', SOURCE)
        self.assertIn('Text(LocalizedStringKey(NativeChannelAppealPresentation.statusTitleKey(flow.appealStatus)), tableName:', SOURCE)
        self.assertIn('Text(LocalizedStringKey(NativeChannelAppealPresentation.operationTitleKey(flow.reviewedOperation)), tableName:', SOURCE)

    def testReceiptCopyNeverPromisesReversalOrAutomaticResubmission(self):
        expected = {
            'retry.confirmation': 'Read the original result first. Retry the same content only if the server confirms that the original request was not found.',
            'recovery.journalUnavailable': 'The original request record is temporarily unavailable. Refresh to read it again; this will not create another appeal or resend automatically.',
            'result.acceptedNotReversed': 'A submission receipt only confirms that the appeal was accepted for processing. It does not mean the original action was reversed.',
            'result.currentSeparate': 'The original request outcome is confirmed. Current appeal status is read separately; a past receipt does not enable a new statement or withdrawal.',
            'session.unavailable': 'The current session or access is no longer valid. The original pending request is still saved.',
        }
        for key, english in expected.items():
            self.assertEqual(STRINGS[key]['localizations']['en']['stringUnit']['value'], english)
        self.assertEqual(STRINGS['input.explanation']['localizations']['zh-Hans']['stringUnit']['value'],
                         '最多 500 个字符；补充说明不会另行上传媒体。')

    def testAccessibilityIdentifiersAndOriginalDetailsRemainAvailable(self):
        for identifier in ['channel.appeal.journalUnavailable', 'channel.appeal.explanation', 'channel.appeal.currentStatus']:
            self.assertIn('.accessibilityIdentifier("' + identifier + '")', SOURCE)
        self.assertIn('.accessibilityLabel(Text("recovery.requestID", tableName: "NativeChannelAppealDetails"))', SOURCE)
        self.assertIn('ForEach(details.evidence)', SOURCE)
        self.assertIn('ForEach(details.timeline)', SOURCE)
        self.assertIn('details.evidenceUnavailable', SOURCE)
        self.assertIn('flow.locatorUnavailable', SOURCE)


if __name__ == '__main__':
    unittest.main()
