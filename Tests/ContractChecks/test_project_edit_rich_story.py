"""Offline structural/source evidence. Swift/UIKit behavior remains NOT_RUN until Apple CI."""
import json
import os
import re
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class RichStoryContracts(unittest.TestCase):
    def text(self, path): return (ROOT / path).read_text()
    def test_all_rich_types_and_seven_segments_are_implemented(self):
        draft = self.text('Core/ProjectEditDraft.swift'); rich = self.text('Core/ProjectEditRichStoryContract.swift')
        for kind in ['dream', 'mood', 'thought', 'voice', 'odd', 'reveal']:
            self.assertIn(kind, draft); self.assertIn('case .' + kind, rich)
        for beat in ['brief', 'route', 'enter', 'outcome', 'deliver', 'unlock', 'revisit']:
            self.assertIn('case .' + beat, rich)
        for guard in ['questions[node, default: []] == answers[node, default: []]', 'delivered.isSubset(of: rewarded)', 'positions[node] == nil', 'npc > 0', 'counts[scoped, default: 0] <= limit']:
            self.assertIn(guard, rich)
    def test_readback_and_wire_use_same_node_identity(self):
        contract = self.text('Core/ProjectEditContract.swift'); story = self.text('Core/ProjectEditStoryContract.swift')
        self.assertIn('if kind == .node || narrative', contract)
        self.assertIn('byServerID[serverID]', contract)
        self.assertIn('if block.isNarrative', story)
        self.assertIn('ordered.firstIndex(where: { $0.id == block.nodeID })', story)
        self.assertIn('validateNarrative(blocks, nodeCount: nodes.count)', story)
        self.assertIn('ProjectEditRichStoryContract.validateShape(shape, kind: kind)', contract)
    def test_legacy_endings_are_deterministic_and_preserve_other_story_sections(self):
        rich = self.text('Core/ProjectEditRichStoryContract.swift')
        for token in ['chapter.id = "legacy-ending-\\(index)"', 'row["summary"]', 'row["title"]', 'Set(ending.keys) == ["endings"]', 'root.removeValue(forKey: "ending")']:
            self.assertIn(token, rich)
        self.assertIn('attachEndings(endings, draft: &draft)', self.text('Core/ProjectEditStoryContract.swift'))
    def test_existing_ui_hosts_new_forms_and_review(self):
        forms = self.text('App/ProjectEditDetailForms.swift'); rich = self.text('App/ProjectEditRichStoryForms.swift')
        for token in ['ProjectEditRichBlockEditor(model: model', 'ProjectEditChapterStorySettings', 'ProjectEditRichBlockSummary', 'removedIDs.contains']:
            self.assertIn(token, forms)
        for token in ['@ObservedObject var model: ProjectEditModel', '.disabled(!model.fullEdit)', 'ProjectEditStoryConditionEditor', 'block.selectNarrativeField($0)']:
            self.assertIn(token, rich)
        for forbidden in ['URLSession', 'transport.send', 'OperationEndpointApproval(', 'WebView', 'TextEditor(']:
            self.assertNotIn(forbidden, rich)
    def test_all_added_keys_bilingual_and_present_in_catalog(self):
        additions=json.loads(self.text('docs/project-edit-rich-localizations.json'))
        catalog=json.loads(self.text('Resources/Localizable.xcstrings'))['strings']
        self.assertEqual(len(additions), 101)
        for key, langs in additions.items():
            self.assertEqual(set(langs), {'en','zh-Hans'})
            for lang, value in langs.items(): self.assertEqual(catalog[key]['localizations'][lang]['stringUnit']['value'], value)
        for path in ['App/ProjectEditDetailForms.swift', 'App/ProjectEditRichStoryForms.swift']:
            for key in re.findall(r'"(projectEdit\.rich\.[A-Za-z][A-Za-z.]+)"', self.text(path)):
                if not key.endswith('.'): self.assertIn(key, additions)
    def test_authored_regressions_and_fixtures_have_no_live_transport(self):
        tests = self.text('Tests/CoreTests/ProjectEditRichStoryTests.swift')
        self.assertGreaterEqual(tests.count('func test'), 19)
        ui = self.text('Tests/AppUITests/ProjectEditRichStoryFlowTests.swift')
        self.assertEqual(ui.count('func test'), 3); self.assertIn('NOT_RUN', ui)
        fixture=self.text('Core/ProjectEditRichStoryFixtures.swift').strip()
        self.assertTrue(fixture.startswith('#if DEBUG')); self.assertTrue(fixture.endswith('#endif'))
        self.assertNotIn('URLSession', tests + fixture)
        self.assertIn('else { service = ProjectEditDisabledService() }', self.text('App/AppSession.swift'))
    def test_current_external_sources_if_supplied(self):
        value=os.environ.get('CHENGYIN_CURRENT_SOURCE_ROOT')
        if value is None: self.skipTest('Current private source unavailable: source comparison NOT_RUN')
        source=Path(value); self.assertTrue(source.is_dir())
        base=source/'chengyinhub-system/src/main/java/com/chengyinhub/business'
        compiler=(base/'service/impl/ChapterFlowCompiler.java').read_text()
        narrative=(base/'service/support/ChapterNarrativeBlocks.java').read_text()
        mini=(source/'chengyinhub-xcx/pages/publish/utils/publish/story-ending.js').read_text()
        for block in ['dream', 'mood', 'thought', 'voice', 'odd', 'reveal']: self.assertIn('"'+block+'"', compiler)
        for field in ['MAX_TEXT = 200', 'MAX_CARRY = 8', 'MAX_FACTS = 8', 'MAX_CHANGES = 6', 'MAX_QUESTIONS = 6']: self.assertIn(field, narrative)
        for token in ['attachEndingsToChapters', 'legacy.push', 'withoutEndingList']: self.assertIn(token, mini)

if __name__ == '__main__': unittest.main()
