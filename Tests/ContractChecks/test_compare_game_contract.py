"""Native/source contract evidence, never Apple compile or live gameplay evidence."""
import json
import os
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

class CompareGameContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()
    def test_registered_backend_family_and_action_reaches_both_hosts(self):
        self.assertIn('classify, compare, compass', self.read('Core/PlayKitScreenContracts.swift'))
        self.assertIn('"compare": ["SUBMIT_COMPARE"]', self.read('Core/PlayAdvancedRuntime.swift'))
        self.assertIn('case .compare:', self.read('App/PlayKitScreen.swift'))
        self.assertIn('PlayKitScreenKind.present(in: state)', self.read('App/PlayAdvancedView.swift'))
        self.assertIn('PlayKitScreenKind.present(in: state)', self.read('Core/ChapterInlineKitSelection.swift'))
    def test_exact_payload_no_client_answer_or_reward(self):
        text = self.read('Core/PlayCompareContracts.swift')
        self.assertIn('Set(payload.keys) == ["marked"]', text)
        self.assertIn('Set(marked).count == marked.count', text)
        self.assertIn('Set(marked).isSubset(of: knownIDs)', text)
        for forbidden in ['segment["answer"]', 'score =', 'readyForBase =', '.sorted(', '.shuffled(']: self.assertNotIn(forbidden, text)
    def test_bounded_question_rejects_bad_identity_without_silent_dedup(self):
        text = self.read('Core/PlayCompareContracts.swift')
        for token in ['(2...20).contains(rows.count)', '^[A-Za-z0-9_-]{1,32}$', 'known.insert(id).inserted', 'limit: 16', 'limit: 200', 'limit: 20', 'items: items']:
            self.assertIn(token, text)
    def test_server_receipt_is_whole_result_and_cap_only_when_present(self):
        text = self.read('Core/PlayCompareContracts.swift')
        for token in ['lastMarked', 'lastCorrect', 'remaining == max(0, cap - attempts)', 'remainingAttempts = nil', '!finished']:
            self.assertIn(token, text)
        self.assertIn('case .qa, .pricePair, .sort, .compare: return segment["finished"].bool == true', self.read('Core/PlayKitScreenContracts.swift'))
    def test_draft_and_review_are_immutable_version_and_owner_bound(self):
        text = self.read('Core/PlayCompareContracts.swift')
        self.assertIn('self.revision == revision', text)
        self.assertIn('throw PlayExperienceError.staleSession', text)
        runtime = self.read('Core/PlayAdvancedRuntime.swift')
        for token in ['state.version == review.version', 'state.sessionID == review.sessionID', 'currentSession() == review.owner', 'payload: review.payload', 'phase = "retryable"']:
            self.assertIn(token, runtime)
        self.assertIn('public let compareQuestion: PlayCompareQuestion?', self.read('Core/PlayKitScreenContracts.swift'))
    def test_creator_exact_optional_limit_answer_and_effects_rules(self):
        schema = self.read('Core/TemplateCreatorSchema.swift')
        self.assertIn('.number(min: 1, max: 10, integer: true), .null', schema)
        self.assertIn('.strings(min: 1, max: 40, length: 32)', schema)
        self.assertIn('.strings(min: 0, max: 0, length: 32), .null', schema)
        code = self.read('Core/TemplateCreatorConfiguration.swift')
        self.assertIn('"compare": ["answer"]', code)
        self.assertIn('Set(answer).isSubset(of: Set(ids))', code)
        self.assertIn('left/right.items', code)
        self.assertIn('identityRows = family == .compare', code)
    def test_public_configuration_is_an_allowlist_without_secrets(self):
        text = self.read('Core/TemplateCompareConfiguration.swift')
        for key in ['enabled', 'prompt', 'maxAttempts', 'left', 'right', 'label', 'items', 'id', 'time', 'text']:
            self.assertIn('"' + key + '"', text)
        for key in ['answer', 'xp', 'effects']:
            self.assertNotIn('"' + key + '"', text)
        self.assertIn('comparePublicConfiguration()', self.read('App/TemplateCreatorRehearsalView.swift'))
    def test_creator_counts_are_38_without_changing_twelve_advanced_families(self):
        creator = self.read('Core/TemplateCreatorSchema.swift').split('public var id:', 1)[0]
        self.assertIn('typeIn, compare', creator)
        tests = self.read('Tests/CoreTests/TemplateCreatorConfigurationTests.swift')
        self.assertIn('allCases.count, 25', tests); self.assertIn('supported.count, 38', tests)
        self.assertIn('enabledGames.count, 12', self.read('Tests/CoreTests/TemplateCompositionTests.swift'))
    def test_native_ui_has_readable_timelines_selection_receipt_and_recovery(self):
        text = self.read('App/PlayCompareView.swift')
        for token in ['ForEach(side.items)', 'item.time', 'item.text', 'selection.marked.contains', 'question.remainingAttempts', 'question.lastCorrect', 'PlayCompareReview', 'ViewThatFits', 'typeSize.isAccessibilitySize']:
            self.assertIn(token, text)
        self.assertNotIn('URLSession', text); self.assertNotIn('api/play/', text)
    def test_live_grants_stay_off_and_synthetic_fixture_is_debug_only(self):
        self.assertIn('enabled: Set<PlayExperienceCapability> = []', self.read('Core/PlayExperienceService.swift'))
        fixture = self.read('App/PlayCompareFixtureSupport.swift')
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertNotIn('URLSession', fixture)
        self.assertIn('if let prior = replay[body]', fixture)
    def test_bilingual_compare_strings_and_correct_non_numeric_answer_label(self):
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        for key in [k for k in catalog if k.startswith(('playkit.compare.', 'creator.compare.'))] + ['playkit.kind.compare', 'creator.family.compare']:
            for lang in ['en', 'zh-Hans']: self.assertTrue(catalog[key]['localizations'][lang]['stringUnit']['value'].strip())
        self.assertIn('labelKey: "creator.compare.answer"', self.read('Core/TemplateCreatorSchema.swift'))
    def test_authored_tests_cover_negative_and_interrupted_flows(self):
        tests = self.read('Tests/CoreTests/PlayCompareTests.swift') + self.read('Tests/CoreTests/TemplateCompareTests.swift')
        for token in ['testUnknownRetainsExactComparePayloadAndKeyAfterReadback', 'testVersionOrSessionChangeNeverSilentlyRebasesDraft', 'testImportedPublicProjectionNeverGetsAnAnswerDefault', 'testEffectsNeverSilentlyBecomeActive', 'testCompareCoexistsWithExistingGamesAndPresentationModes']:
            self.assertIn(token, tests)
        ui = self.read('Tests/AppUITests/PlayCompareFlowTests.swift')
        self.assertEqual(len(re.findall(r'func test', ui)), 6)
    def test_optional_private_source_matches_exact_current_contract(self):
        root = os.environ.get('CHENGYIN_COMPARE_BACKEND_SOURCE_ROOT')
        if not root: self.skipTest('NOT_RUN: optional current backend source checkout not supplied')
        source = Path(root) / 'chengyinhub-system/src/main/java/com/chengyinhub/business'
        runtime = (source/'service/impl/AdvancedGameRuntimeServiceImpl.java').read_text()
        validation = (source/'service/support/AdvancedGameConfigValidator.java').read_text()
        projection = (source/'util/AdvancedGamePublicProjection.java').read_text()
        self.assertIn('"SUBMIT_COMPARE"', runtime)
        self.assertIn('payload.get("marked")', runtime)
        self.assertIn('boolean correct = marked.equals(answer);', runtime)
        self.assertIn('state.path("compare").path("finished").asBoolean(false)', runtime)
        self.assertIn('MAX_COMPARE_SIDE = 20', validation)
        self.assertIn('MIN_COMPARE_ATTEMPTS = 1', validation)
        block = projection.split('private static void copyCompare(',1)[1].split('private static void copyCompareSide',1)[0]
        self.assertNotIn('get("answer")', block)
        self.assertNotIn('path("answer")', block)

if __name__ == '__main__': unittest.main()
