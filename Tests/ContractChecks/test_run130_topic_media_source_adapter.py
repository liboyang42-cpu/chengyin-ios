"""Exact, reversible adapter for the reviewed topic-host source evolution only.

This is not a new run130 runtime result. The historical source, UI and helper
assertions remain owned by test_run130_version_label.py.
"""
from pathlib import Path
import hashlib
import importlib.util
import unittest

ROOT = Path(__file__).resolve().parents[2]
CURRENT_SHA = '4dcea018c092a8a4a44e07460e2f1e1afeacd7682e7ee14b21acb24ab508b391'
HISTORICAL_SHA = '3feee5e2ef697bf11dc109ddfe5e997a8acfa2eef14ca780d6b6280c669eac7b'
BEFORE_HUNK = (
    '                basicFields\n'
    '                ProjectEditPendingSection(model: model, controller: pending)\n'
)
AFTER_HUNK = (
    '                basicFields\n'
    '                ProjectTopicMediaHost(editor: model)\n'
    '                ProjectEditPendingSection(model: model, controller: pending)\n'
)
FEATURE_PATHS = (
    'App/ProjectTopicMediaPresentation.swift',
    'App/ProjectTopicMediaInspector.swift',
    'Core/ProjectTopicImageUpload.swift',
    'App/ProjectTopicMediaHost.swift',
    'App/AppCompositionRoot.swift',
)


def restore_topic_host_source(source):
    """Require the entire exact current postimage before reversing its one hunk."""
    assert hashlib.sha256(source.encode('utf-8')).hexdigest() == CURRENT_SHA
    assert source.count(AFTER_HUNK) == 1
    historical = source.replace(AFTER_HUNK, BEFORE_HUNK, 1)
    assert hashlib.sha256(historical.encode('utf-8')).hexdigest() == HISTORICAL_SHA
    return historical


def verify_current_feature_sources(sources):
    """Run the existing feature contract on current sources, never reversed ones.

    Only its helper function is invoked; no TestCase is imported into this module,
    avoiding duplicate unittest discovery/counting.
    """
    path = ROOT / 'Tests/ContractChecks/test_project_topic_media_app.py'
    spec = importlib.util.spec_from_file_location('_run130_current_topic_contract', path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert module.contracts(*sources)


class Run130TopicMediaSourceAdapterTests(unittest.TestCase):
    def current_source(self):
        return (ROOT / 'App/ProjectEditView.swift').read_bytes().decode('utf-8')

    def feature_sources(self):
        return tuple((ROOT / path).read_bytes().decode('utf-8') for path in FEATURE_PATHS)

    def test_exact_current_feature_contract_precedes_reversal(self):
        verify_current_feature_sources(self.feature_sources())
        historical = restore_topic_host_source(self.current_source())
        self.assertEqual(hashlib.sha256(historical.encode()).hexdigest(), HISTORICAL_SHA)
        self.assertNotIn('ProjectTopicMediaHost(editor: model)', historical)

    def test_new_host_hunk_change_removal_duplication_or_relocation_is_rejected(self):
        source = self.current_source()
        line = '                ProjectTopicMediaHost(editor: model)\n'
        candidates = [
            source.replace(line, '', 1),
            source.replace(line, line + line, 1),
            source.replace(line, line.replace('model)', 'otherModel)'), 1),
            source.replace(line, '', 1) + line,
            source.replace(AFTER_HUNK, AFTER_HUNK.replace('basicFields', 'basicFields.disabled(true)'), 1),
        ]
        for candidate in candidates:
            with self.subTest(candidate_sha=hashlib.sha256(candidate.encode()).hexdigest()):
                with self.assertRaises(AssertionError):
                    restore_topic_host_source(candidate)

    def test_original_accessibility_and_unrelated_bytes_remain_exact(self):
        source = self.current_source()
        line = '                                .accessibilityLabel(Text(verbatim: model.draft.baseRevision))\n'
        self.assertEqual(source.count(line), 1)
        for candidate in [source.replace(line, '', 1), source.replace(line, line.replace('model.draft.baseRevision', '"fixture-r2"'), 1),
                          source.replace('import SwiftUI', 'import Foundation', 1), source + '\n', source.replace('\n', '\r\n')]:
            with self.subTest(candidate_sha=hashlib.sha256(candidate.encode()).hexdigest()):
                with self.assertRaises(AssertionError):
                    restore_topic_host_source(candidate)

    def test_current_feature_mutation_cannot_hide_behind_historical_reversal(self):
        current = self.feature_sources()
        for index, token in [(0, 'editor.topicMediaContext == original.context'),
                             (1, 'O_NOFOLLOW'), (2, 'currentApproval() == approval'),
                             (3, 'RetainedImagePresenterHost'), (4, 'issued.fields.contains(field)')]:
            changed = list(current); self.assertIn(token, changed[index]); changed[index] = changed[index].replace(token, 'REMOVED')
            with self.subTest(token=token), self.assertRaises(AssertionError):
                verify_current_feature_sources(tuple(changed))


if __name__ == '__main__':
    unittest.main()
