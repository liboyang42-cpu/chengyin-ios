"""Regression contracts for evidence-backed run129 AX and shipped-localization repairs.
Source checks do not substitute for new Apple execution.
"""
import hashlib
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
ORIGINALS = ROOT / 'tools/tests/fixtures/run129_published_sources'
UI_CLASSES = ['ProjectOwnedEditorFlowTests', 'ProjectSubmissionAcknowledgmentFlowTests',
              'ApprovedReleasePreparationFlowTests', 'ApprovedReleasePublicationFlowTests',
              'ProjectPendingNewChapterFlowTests', 'ProjectEditPreparedNodesFlowTests',
              'ApprovedReleaseReceiptRecoveryFlowTests', 'ApprovedTopicFrozenCoverPublicationFlowTests']


def declarations(source):
    result = {}
    for match in re.finditer(r'    func (test\w+)\s*\(', source):
        end = source.index('\n    }', match.start()) + len('\n    }')
        result[match[1]] = source[match.start():end]
    return result


class Run129ProjectEditorRepairs(unittest.TestCase):
    def source(self, path):
        result = (ROOT / path).read_text()
        pairs = {'ProjectSubmissionAcknowledgmentFlowTests': 'ProjectSubmissionAcknowledgmentChineseFlowTests',
                 'ApprovedReleasePreparationFlowTests': 'ApprovedReleasePreparationChineseFlowTests'}
        for original, continuation in pairs.items():
            if path == 'Tests/AppUITests/' + original + '.swift':
                result += (ROOT / 'Tests/AppUITests' / (continuation + '.swift')).read_text()
        return result

    def test_original_201_bilingual_entries_are_shipped_and_referenced(self):
        catalog = json.loads(self.source('Resources/Localizable.xcstrings'))['strings']
        count = 0
        sources = '\n'.join(p.read_text() for folder in ['App', 'Core'] for p in (ROOT / folder).glob('*.swift'))
        for name, expected in [('ProjectOwnedContentLocalizations', 13),
                               ('ProjectEditPreparedLocalizations', 23),
                               ('ProjectSubmissionLocalizations', 15),
                               ('ApprovedReleasePublicationLocalizations', 15),
                               ('ApprovedTopicFrozenCoverLocalizations', 2),
                               ('ApprovedTopicReviewLocalizations', 50),
                               ('ProjectPendingChapterLocalizations', 2),
                               ('ApprovedTopicSelectedCoverLocalizations', 8),
                               ('ApprovedTopicReviewObservationLocalizations', 14),
                               ('ProjectEditPendingLocalizations', 18),
                               ('ApprovedReleaseLocalizations', 31),
                               ('ProjectEditStarterLocalizations', 8),
                               ('ApprovedReleaseCategoryLocalizations', 2)]:
            fragment = json.loads(self.source('Resources/' + name + '.fragment.json'))['strings']
            self.assertEqual(len(fragment), expected)
            for key, row in fragment.items():
                self.assertEqual(catalog[key], row, key)
                if key == 'projectPrepared.nodePosition %lld':
                    self.assertTrue('Text("projectPrepared.nodePosition \\(node.id + 1)")' in sources, key)
                elif key.startswith('projectPrepared.field.'):
                    fields = self.source('Core/ProjectEditPreparedNodes.swift').split('public enum Field:', 1)[1].split('public var id:', 1)[0]
                    declared = re.search(r'case ([^\n]+)', fields)[1].replace(' ', '').split(',')
                    self.assertIn(key.removeprefix('projectPrepared.field.'), declared)
                    view = self.source('App/ProjectEditPreparedReview.swift')
                    self.assertIn('ForEach(ProjectEditPreparedNodes.Field.allCases)', view)
                    self.assertIn('Text(LocalizedStringKey("projectPrepared.field." + field.rawValue))', view)
                else:
                    self.assertTrue('"' + key + '"' in sources, key)
                self.assertEqual(set(row['localizations']), {'en', 'zh-Hans'})
                for locale in ['en', 'zh-Hans']:
                    self.assertTrue(row['localizations'][locale]['stringUnit']['value'].strip())
            count += len(fragment)
        self.assertEqual(count, 201)

    def test_version_reads_the_existing_verbatim_value_with_contained_ax_identity(self):
        source = self.source('App/ProjectEditView.swift')
        self.assertIn('LabeledContent("projectRemote.version") {\n'
                      '                            Text(verbatim: model.draft.baseRevision).accessibilityIdentifier("projectRemote.version.value")\n'
                      '                        }.accessibilityElement(children: .contain)', source)
        ui = self.source('Tests/AppUITests/ProjectOwnedEditorFlowTests.swift')
        self.assertIn('let version = app.staticTexts["projectRemote.version.value"]', ui)
        self.assertIn('XCTAssertTrue(version.exists, app.debugDescription)', ui)
        self.assertIn('XCTAssertEqual(Array(version.label.utf8), Array("fixture-r2".utf8))', ui)
        self.assertIn('XCTAssertEqual(value.label, mode)', ui)

    def test_all_fourteen_original_full_journeys_remain_byte_exact(self):
        count = 0
        for name in UI_CLASSES:
            before = declarations((ORIGINALS / (name + '.swift.txt')).read_text())
            after = declarations(self.source('Tests/AppUITests/' + name + '.swift'))
            self.assertEqual(before, after)
            count += len(after)
        self.assertEqual(count, 14)

    def test_later_selected_and_frozen_cover_methods_only_reorder_existing_helpers(self):
        from tools.run129_repair_planning import historical_source
        for name in ['ApprovedTopicSelectedCoverFlowTests', 'ApprovedTopicFrozenCoverReviewFlowTests']:
            path=ROOT/'Tests/AppUITests'/(name+'.swift')
            old=historical_source(path).read_text();new=path.read_text()
            self.assertEqual(declarations(old),declarations(new))
            self.assertEqual(old.count('maximumSwipes: 70'),new.count('maximumSwipes: 70'))
            self.assertEqual(old.count('timeout: 5'),new.count('timeout: 5'))
            launch=lambda text:text.split('    private func launch',1)[1].split('    private func tap',1)[0]
            self.assertEqual(launch(old),launch(new))
            for token in ['target.isEnabled && target.isHittable','app.windows.firstMatch.frame.contains(target.frame)','Array(target.label.utf8), Array(expected.utf8)']:
                self.assertIn(token,new)

    def test_ack_launch_reveals_name_before_original_five_second_assertion(self):
        ui = self.source('Tests/AppUITests/ProjectSubmissionAcknowledgmentFlowTests.swift')
        launch = ui.split('private func launch(', 1)[1].split('private func tap(', 1)[0]
        self.assertLess(launch.index('revealFixtureElement(name,'), launch.index('name.waitForExistence(timeout: 5)'))
        self.assertIn('UICTContentSizeCategoryAccessibilityXXXL', launch)
        self.assertIn('assertFixtureEnvironment(in: app, dynamicTypeSize: "accessibility5")', ui)

    def test_ack_reveal_precedes_existence_and_all_tap_postconditions_remain(self):
        ui = self.source('Tests/AppUITests/ProjectSubmissionAcknowledgmentFlowTests.swift')
        tap = ui.split('private func tap(', 1)[1].split('private func value(', 1)[0]
        value = ui.split('private func value(', 1)[1].split('// UNMEASURED', 1)[0]
        for helper in [tap, value]:
            self.assertLess(helper.index('revealFixtureElement(target,'), helper.index('target.waitForExistence(timeout: 5)'))
            self.assertIn('maximumSwipes: 65', helper)
        for text in ['app.buttons.matching(identifier: id).count, 1',
                     'target.isEnabled && target.isHittable',
                     'app.windows.firstMatch.frame.contains(target.frame)', 'target.tap()']:
            self.assertIn(text, tap)
        self.assertIn('Array(target.label.utf8), Array(expected.utf8)', value)

    def test_fixture_flags_and_shared_scroll_helper_are_not_changed(self):
        for name in UI_CLASSES:
            before = (ORIGINALS / (name + '.swift.txt')).read_text()
            after = self.source('Tests/AppUITests/' + name + '.swift')
            def launch_flags(value):
                result = []
                for match in re.finditer(r'    private func launch\(', value):
                    end = value.index('\n    }', match.start())
                    result.append(re.findall(r'"--[^"]+"', value[match.start():end]))
                return result
            expected = launch_flags(before)
            self.assertEqual(len(expected), 1)
            for flags in launch_flags(after): self.assertEqual(flags, expected[0])
        helper = (ROOT / 'Tests/AppUITests/FailureScreenshot.swift').read_bytes()
        self.assertEqual(hashlib.sha256(helper).hexdigest(),
                         '705ba7fa14128cfd9e81f181fd2b5f5edd0cb464b2ececd26119510d98ed6e49')


if __name__ == '__main__':
    unittest.main()
