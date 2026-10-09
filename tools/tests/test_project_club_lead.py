"""Native static contracts only. These checks do not compile or execute Swift."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

def read(path):
    return (ROOT / path).read_text()

class ProjectClubLeadContracts(unittest.TestCase):
    def test_existing_editor_mount_and_frozen_review_only(self):
        ui = read('App/ProjectEditView.swift')
        self.assertEqual(ui.count('ProjectClubLeadFields(model: model)'), 1)
        review = read('App/ProjectEditDetailForms.swift')
        self.assertIn('if confirmation.payload["openClubPool"] != nil', review)
        self.assertEqual(review.count('ProjectClubLeadSummary(draft: confirmation.draft)'), 1)

    def test_wire_uses_exact_source_eligibility_and_full_scope(self):
        policy = read('Core/ProjectClubLead.swift')
        self.assertIn('draft.product == .city && draft.clubID == nil', policy)
        self.assertLess(policy.index('guard supportsEditing(draft)'), policy.index('return .number(isEligible(draft)'))
        self.assertIn('raw == .number(0) || raw == .number(1)', policy)
        contract = read('Core/ProjectEditContract.swift')
        self.assertIn('payload["openClubPool"] = try ProjectClubLead.wireValue(draft)', contract)
        self.assertLess(contract.index('if scope == .whitelist'), contract.index('ProjectClubLead.wireValue(draft)'))
        self.assertIn('d.preserved["openClubPool"] = topic["openClubPool"]', contract)
        self.assertNotIn('"openClubPool"', contract.split('public static let whitelist = ', 1)[1].split('\n', 1)[0])

    def test_new_default_and_historical_shapes_are_distinct(self):
        draft = read('Core/ProjectEditDraft.swift')
        self.assertIn('"openClubPool": .number(1)', draft)
        self.assertLess(draft.index('guard scope == .full'), draft.index('!ProjectClubLead.supportsEditing(draft)'))
        policy = read('Core/ProjectClubLead.swift')
        self.assertIn('guard enabled != isSelected(draft) else { return draft }', policy)
        self.assertNotIn('result.preserved =', policy)

    def test_binding_captures_identity_revision_and_exact_draft(self):
        ui = read('App/ProjectClubLeadFields.swift')
        for needle in ['value.controllerID == controllerID', 'value.generation == generation',
                       'model.isCurrentStarterLease(value.lease)', 'model.draftMutationRevision == value.revision',
                       'ProjectEditPendingMaterials.exactData(model.draft) == value.draftBytes',
                       '.id(ObjectIdentifier(model))', 'self.model === model', '.onDisappear { controller.retire() }',
                       'set: { self.apply($0, captured: captured) }']:
            self.assertIn(needle, ui)

    def test_mutation_only_changes_working_draft_no_transport_or_save_claim(self):
        ui = read('App/ProjectClubLeadFields.swift')
        self.assertIn('guard let captured, isCurrent(captured)', ui)
        self.assertIn('ProjectEditPendingMaterials.exactData(next) != captured.draftBytes', ui)
        self.assertIn('model.draft = next', ui)
        for forbidden in ['URLRequest', 'saveLocal(', 'persistLocalChange(', '.submit(', '.confirm(', 'UserDefaults', 'suspendLocalWritesAfterChapterRemoval(']:
            self.assertNotIn(forbidden, ui)

    def test_localizations_cover_all_user_visible_keys(self):
        catalog = json.loads(read('Resources/ProjectClubLeadLocalizations.fragment.json'))['strings']
        for path in ['App/ProjectClubLeadFields.swift', 'Core/ProjectEditDraft.swift', 'App/ProjectEditDetailForms.swift']:
            for key in re.findall(r'"(projectClubLead\.[A-Za-z]+)"', read(path)):
                self.assertIn(key, catalog)
        for entry in catalog.values():
            self.assertEqual(set(entry['localizations']), {'en', 'zh-Hans'})
            self.assertTrue(all(value['stringUnit']['value'] for value in entry['localizations'].values()))

    def test_regressions_are_authored_for_unknown_whitelist_and_lifecycle(self):
        core = read('Tests/CoreTests/ProjectClubLeadTests.swift')
        app = read('Tests/AppUnitTests/ProjectClubLeadEditorTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+', core)), 7)
        self.assertEqual(len(re.findall(r'func test\w+', app)), 10)
        for needle in ['testMissingAndNullReadbackAndOldLocalEnvelopeNeverOptIn',
                       'testUnknownValuesRemainReadOnlyAndBlockFullBeforeEligibilityNormalization',
                       'testWhitelistExcludesSettingEvenForUnsupportedSourceAndDetectsLocalMutation']:
            self.assertIn(needle, core)
        for needle in ['testCapturedBindingCannotMutateAfterDraftABAAndEligibilityChanges',
                       'testUnconfirmedChapterRemovalBlocksPreviouslyCapturedToggle',
                       'testUnknownSubmissionLocksToggleAndRetainsPendingIdentity']:
            self.assertIn(needle, app)

if __name__ == '__main__':
    unittest.main()
