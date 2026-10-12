#!/usr/bin/env python3
"""Focused source checks only; not native build or behavioral execution."""
from pathlib import Path
import json,re,sys,unittest
ROOT=Path(sys.argv.pop(1)).resolve() if len(sys.argv)>1 and not sys.argv[1].startswith('-') else Path(__file__).resolve().parents[2]
CORE=(ROOT/'Core/TemplateAuthoringExitDecision.swift').read_text();APP=(ROOT/'App/TemplateAuthoringExitGuard.swift').read_text();HOST=(ROOT/'App/TemplateAuthoringView.swift').read_text();COORD=(ROOT/'Core/TemplateAuthoringCoordinator.swift').read_text();CHECKPOINT=COORD.split('public func localCheckpointForExit()',1)[1].split('public func saveLocal()',1)[0]
CT=(ROOT/'Tests/CoreTests/TemplateAuthoringExitDecisionTests.swift').read_text();AT=(ROOT/'Tests/AppUnitTests/TemplateAuthoringExitGuardTests.swift').read_text();LOC=json.loads((ROOT/'Resources/CreatorExitGuard.xcstrings').read_text())['strings'];REG=json.loads((ROOT/'docs/registration/template-author-exit-guard.json').read_text());DOC=(ROOT/'docs/template-author-exit-guard.md').read_text()
class ExitGuardSourceContracts(unittest.TestCase):
    def test_normal_root_host_has_one_additive_entry(self):
        self.assertEqual(HOST.count('.modifier(TemplateAuthoringExitGuard('),1)
        self.assertIn('overlaysOpen: { preview || discard || media.review != nil }',HOST)
        self.assertIn('.confirmationDialog("templateAuthor.discardQuestion"',HOST)
        self.assertIn('Button("templateAuthor.saveLocal") { model.save() }',HOST)
    def test_exact_checkpoint_comparison_not_unicode_equatable(self):
        for value in ['.sortedKeys','.withoutEscapingSlashes','encoder.encode(draft)','current == persisted','Self.snapshot(TemplateAuthoringDraft())']:
            self.assertIn(value,CORE)
    def test_all_unknown_checkpoint_states_are_unverified(self):
        self.assertIn('case .unavailable, .incompatible, .ownerMismatch: status = .unverified',CORE)
        self.assertEqual(CORE.count('status = .unverified; return'),2)
    def test_checkpoint_method_is_read_only_and_does_not_synchronize(self):
        self.assertEqual(CHECKPOINT.count('store.load('),1)
        self.assertNotRegex(CHECKPOINT,r'synchronizeSession|store\.(save|discard|remove)|generation\s*\+=|state\s*=|draft\s*=|messageKey\s*=')
    def test_checkpoint_rechecks_owner_identity_generation_after_read(self):
        for text in ['currentSession() == session','captured == session','identity == originalIdentity','generation == stamp','!locked','restore == .missing']:
            self.assertIn(text,CHECKPOINT)
        self.assertGreater(CHECKPOINT.index('generation == stamp'),CHECKPOINT.index('store.load('))
    def test_exit_controller_never_saves_deletes_or_mutates_a_draft(self):
        self.assertNotRegex(APP,r'model\.(save|discard|restore|changed|prepare|confirm)\(|model\.draft\s*=|URLSession|requestAuthorization|grant')
        self.assertIn('private func finish(_ dismiss: () -> Void) { retire(); dismiss() }',APP)
    def test_back_and_all_review_actions_are_fenced(self):
        self.assertIn('self.current(original), self.review == nil',APP)
        self.assertGreaterEqual(APP.count('self.current(original)'),4)
        self.assertIn('review?.id == original.id',APP)
        self.assertIn('capture() == original',APP)
        self.assertIn('generation = UUID()',APP)
    def test_live_overlays_and_busy_review_block_root_back(self):
        for token in ['!overlaysOpen()','!model.busy','model.review == nil','model.coordinator.review == nil','model.coordinator.state != .submitting','.onChange(of: overlaysOpen())']:
            self.assertIn(token,APP)
    def test_exact_owner_identity_full_draft_and_lifecycle_capture(self):
        for token in ['model.coordinator.session','model.coordinator.identity','model.metadataGeneration','model.mediaReviewGeneration','TemplateAuthoringExitDecision.snapshot(model.draft)','model.coordinator.state','model.coordinator.restore','model.objectWillChange.sink']:
            self.assertIn(token,APP)
    def test_background_reentry_and_old_binding_retire(self):
        for token in ['.onDisappear { controller.retire() }','phase == .active { controller.activate() } else { controller.retire() }','let original = review','self.cancelAction(original)()']:
            self.assertIn(token,APP)
    def test_real_normal_navigation_and_confirmation_are_present(self):
        for token in ['.navigationBarBackButtonHidden(true)','.interactiveDismissDisabled(true)','.topBarLeading','.confirmationDialog','controller.backAction','controller.leaveAction','controller.cancelAction','controller.retryAction']:
            self.assertIn(token,APP)
    def test_compiled_catalog_has_exact_bilingual_keys(self):
        keys=set(re.findall(r'"(templateAuthorExit\.[A-Za-z]+)"',APP));self.assertEqual(keys,set(LOC));self.assertEqual(len(LOC),7)
        self.assertTrue(all(set(x['localizations'])=={'en','zh-Hans'} for x in LOC.values()))
        self.assertTrue(all(v['stringUnit']['value'] for x in LOC.values() for v in x['localizations'].values()))
        self.assertEqual(APP.count('tableName: "CreatorExitGuard"'),6)
        self.assertEqual(REG['localization_table'],'CreatorExitGuard')
    def test_native_tests_and_actual_registration_declared(self):
        self.assertEqual(len(re.findall(r'func test\w+\(',CT)),12);self.assertEqual(len(re.findall(r'func test\w+\(',AT)),18)
        self.assertEqual(len(REG['app_sources']),2);self.assertEqual(len(REG['app_unit_tests']),1);self.assertEqual(len(REG['package_tests']),1)
        self.assertEqual(REG['registration'],'ACTUAL_PBX_SOURCE_APP_TEST_RESOURCE_MEMBERSHIP');self.assertEqual(REG['native_status'],'NOT_RUN')
    def test_source_scope_and_verification_limits_are_explicit(self):
        for token in ['95e499471eaa39c28f77d16125f0cc17b8c37123','f329ff5180551ef3956b2718cb9ef071e2635409','local save, not Mini','NOT_RUN','does not intercept unrelated tab changes','No private Mini module']:
            self.assertIn(token,DOC)
if __name__=='__main__':unittest.main(verbosity=2)
