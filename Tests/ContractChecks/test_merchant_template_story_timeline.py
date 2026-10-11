"""Supplementary source checks, not Swift compilation or UI acceptance."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()


class MerchantTemplateStoryTimelineChecks(unittest.TestCase):
    def group(self):
        return read('Core/MerchantOperationsContracts.swift').split('public struct MerchantTemplateStoryTimeline:')[1].split('public struct MerchantNodeTemplate:')[0]

    def test_only_existing_optional_story_fields_are_decoded_and_serialized(self):
        core = read('Core/MerchantOperationsContracts.swift')
        for key in ['storyText', 'storyJson']: self.assertIn('try c.decodeIfPresent(String.self, forKey: .' + key + ')', core)
        self.assertIn('for (key, value) in storyTimeline.fields { fields[key] = value }', core)
        self.assertNotIn('fields["storyEnabled"]', core); self.assertNotIn('fields["story_json"]', core)

    def test_unknown_shapes_stay_opaque_instead_of_lossy_fallback(self):
        group = self.group()
        for token in ['Set(item.keys).isSubset(of: ["text", "tag", "imgs", "img"])',
                      'beats = []; isEditable = false; enabled = true',
                      'guard isEdited else { return ["storyText": sourceText, "storyJson": sourceJSON].compactMapValues { $0 } }']:
            self.assertIn(token, group)
        self.assertGreaterEqual(group.count('guard isEditable'), 5)

    def test_media_values_preserved_and_removal_is_disclosed(self):
        group = self.group()
        for token in ['result["imgs"] = sourceImages', 'result["img"] = legacyImage', 'public var removedImageCount:',
                      'public var removedBeats:', 'sourceBeats.filter { $0.hasContent && !retained.contains($0.id) }']:
            self.assertIn(token, group)
        app = read('App/MerchantOperationsEditor.swift')
        self.assertIn('ForEach(timeline.removedBeats)', app); self.assertIn('timeline.removedImageCount > 0', app)
        self.assertNotIn('removeImage', group); self.assertNotIn('upload', group.lower())

    def test_projection_is_bounded_without_truncating_full_json(self):
        group = self.group()
        for token in ['String(character).utf16.count', 'guard count + length <= 500 else { break }',
                      'previewBeats.map(\\.object)', 'result.append(character)', 'projectionIsShortened']:
            self.assertIn(token, group)
        self.assertNotIn('String(text.prefix', group)
        self.assertIn('merchant.storyTimeline.tagNeedsContent', group)

    def test_stable_editor_rows_support_order_and_last_row_safety(self):
        group = self.group()
        for token in ['beats.append(Beat(id: nextID))', 'beats.count > 1', 'beats.swapAt(index, index + offset)',
                      '[-1, 1].contains(offset)', 'public var previewBeats:']:
            self.assertIn(token, group)
        self.assertNotIn('result["id"]', group)
        app = read('App/MerchantOperationsEditor.swift')
        self.assertIn('ForEach(Array(timeline.beats.enumerated()), id: \\.element.id)', app)
        self.assertIn('$0.move(beat.id, offset: -1)', app); self.assertIn('$0.move(beat.id, offset: 1)', app)

    def test_existing_editor_and_frozen_review_mount_the_timeline(self):
        app = read('App/MerchantOperationsEditor.swift')
        for token in ['MerchantTemplateStoryTimelineFields(model: model)', 'action(&value.storyTimeline); model.edit(.template(value))',
                      'MerchantTemplateStoryTimelineReview(timeline: template.storyTimeline)',
                      'Text(verbatim: beat.text)', '.disabled(!timeline.isEditable)']:
            self.assertIn(token, app)
        preview = app.split('private struct MerchantTemplateStoryTimelineContent:')[1].split('private struct MerchantTemplateStoryTimelineReview:')[0]
        for token in ['save(', 'model.edit', 'URLSession', 'publish(']: self.assertNotIn(token, preview)

    def test_authority_and_ai_allowlists_stay_with_existing_services(self):
        fields = read('Core/MerchantTemplateAssistContracts.swift').split('public enum MerchantTemplateAssistField:')[1].split('public struct MerchantTemplateAssistEdits:')[0]
        self.assertNotIn('storyTimeline', fields); self.assertNotIn('storyJson', fields)
        self.assertIn('guard !localOnlyReview else { throw MerchantOperationsFailure.liveWritesDisabled }', read('Core/MerchantOperationsDraft.swift'))
        reader = read('Core/MerchantOperationsReading.swift')
        self.assertIn('baseline = .template(returned); draft = .template(returned)', reader)
        fixture = read('Core/MerchantOperationsSyntheticFixtures.swift')
        self.assertIn('returned.storyTimeline = .init(storyText:', fixture)
        self.assertIn('storyFields["storyJson"] ?? baseline.storyTimeline.fields["storyJson"]', fixture)

    def test_bilingual_fragment_covers_static_and_numbered_accessibility_keys(self):
        fragment = json.loads(read('Resources/MerchantTemplateStoryTimelineLocalizations.fragment.json'))
        source = read('Core/MerchantOperationsContracts.swift') + read('App/MerchantOperationsEditor.swift')
        source = re.sub(r'\.accessibilityIdentifier\("[^"\n]*"\)', '', source)
        source = re.sub(r'prefix: "merchant\.storyTimeline\.(preview|review)"', '', source)
        keys = set(re.findall(r'"(merchant\.storyTimeline\.[A-Za-z]+)"', source))
        keys.update('merchant.storyTimeline.' + key + ' %lld' for key in ['beat', 'images', 'removedImages', 'moveEarlier', 'moveLater', 'removeMoment'])
        self.assertEqual(set(fragment), keys); self.assertEqual(len(fragment), 25)
        for value in fragment.values():
            for locale in ['en', 'zh-Hans']: self.assertTrue(value['localizations'][locale]['stringUnit']['value'])
        self.assertIn('no uploaded image file is deleted', fragment['merchant.storyTimeline.removedImages %lld']['localizations']['en']['stringUnit']['value'])

    def test_authored_core_tests_cover_opaque_media_limits_clear_no_replay_and_real_adapter(self):
        core = read('Tests/CoreTests/MerchantTemplateStoryTimelineTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', core)), 21)
        for token in ['future', 'source.storyTimeline.fields["storyJson"], canonicalJSON', 'TimelineTransport: HTTPTransport',
                      'String(repeating: "🧩", count: 250)', 'value.removedImageCount, 2', 'coordinator.cancelConfirmation()',
                      'coordinator.discardChanges()', 'reader.switchAccount()', 'exerciseSave(clear: true)',
                      'XCTAssertTrue(transport.requests.isEmpty)', '"/prod-api/api/template/myinfo"']:
            self.assertIn(token, core)

    def test_authored_ui_tests_cover_add_reorder_preview_clear_and_removed_saved_content(self):
        ui = read('Tests/AppUITests/MerchantTemplateStoryTimelineFlowTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', ui)), 3)
        for token in ['merchant.storyTimeline.up.2', 'merchant.storyTimeline.review.clear', 'merchant.storyTimeline.review.removed.1',
                      'Keep editing', 'Discard and reload', 'XCTAssertEqual(first.value as? String, "Second moment")']:
            self.assertIn(token, ui)


if __name__ == '__main__': unittest.main()
