"""Source-shape checks only. Device/Swift/visual execution has separate evidence."""
import json
import pathlib
import re
import unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]

class PlayKitAuthoringLegacyChecks(unittest.TestCase):
    def read(self,p):return (ROOT/p).read_text()
    def test_five_creator_kinds_have_editor_dispatch(self):
        enum=self.read('Core/TemplateAdvancedDraft.swift')
        ui=self.read('App/TemplateMiniGameConfigurationView.swift')
        for kind in ['sort','match','classify','compass','shout']:
            self.assertRegex(enum,r'\b'+kind+r'\b')
        self.assertIn('TemplateMiniGameConfigurationView',self.read('App/TemplateAuthoringDetailForms.swift'))
        for key in ['answerOrder','pairs','answer','bearing','holdSeconds','seconds']:
            self.assertIn('"'+key+'"',self.read('Core/TemplateAdvancedMiniGames.swift'))
        self.assertIn('game.isReasoning',ui)
    def test_compass_has_no_guessed_north(self):
        text=self.read('Core/TemplateAdvancedMiniGames.swift')
        self.assertIn('"bearing": .string("")',text)
        self.assertIn('number("bearing", 0...359, nonblank: true)',text)
    def test_author_shape_and_answer_derivation_are_explicit(self):
        text=self.read('Core/TemplateAdvancedMiniGames.swift')
        for token in ['2...8','2...6','2...4','2...10','label.utf16.count > 40','string("prompt").utf16.count > 200','zip(left, right)','Set(answer.keys) != items','answerOrder']:
            self.assertIn(token,text)
        self.assertIn('row["img"]',text)
    def test_preview_removes_answers_and_has_no_transport(self):
        text=self.read('Core/TemplateAdvancedMiniGames.swift').split('public func miniPreviewSegment',1)[1]
        self.assertIn('["answerOrder", "pairs", "answer", "xp", "enabled"]',text)
        ui=self.read('App/TemplateMiniGameConfigurationView.swift').split('struct TemplateMiniGamePreviewView',1)[1]
        for token in ['PlayKitReasoningForm','previewPayload = payload','enabled: false, active: false']:
            self.assertIn(token,ui)
        for forbidden in ['model.submit','transport','PlayAdvancedState(']:self.assertNotIn(forbidden,ui)
    def test_root_presentation_is_preserved_and_validated(self):
        text=self.read('Core/TemplateAdvancedDraft.swift')
        self.assertIn('if key == "present" { value[key] = entry; continue }',text)
        self.assertIn('selected?.allowsInline == false',text)
        self.assertIn('setPresentation',self.read('App/TemplateAuthoringDetailForms.swift'))
    def test_all_six_active_legacy_sections_have_actual_bodies(self):
        ui=self.read('App/PlayKitLegacyViews.swift')
        for kind in ['blindTaste','diyName','silentOrder','slowTask','musicCorner','timeWindow']:
            self.assertIn('.'+kind,ui)
        for action in ['SUBMIT_BLIND_TASTE','SUBMIT_DIY_NAME','START_SLOW_TASK','CLAIM_SLOW_TASK']:
            self.assertIn(action,ui)
    def test_slow_task_uses_server_days_and_silent_clock_cannot_submit(self):
        ui=self.read('App/PlayKitLegacyViews.swift')
        self.assertIn('segment["daysLeft"].integer == 0',ui)
        silent=ui.split('struct PlayKitSilentOrderBody',1)[1]
        self.assertIn('ProcessInfo.processInfo.systemUptime',silent)
        self.assertNotIn('requestReview',silent)
        self.assertNotIn('SUBMIT',silent)
    def test_wechat_subscribe_and_steps_stay_provider_specific(self):
        catalog=self.read('Core/PlayAdvancedRuntime.swift')
        self.assertIn('"timeWindow": []',catalog)
        self.assertNotIn('SUBSCRIBE_TIME_WINDOW',catalog)
        self.assertIn('case .bingo, .walk, .steps: throw PlayExperienceError.unsupported',self.read('Core/PlayKitScreenContracts.swift'))
    def test_scan_preserves_returned_image_without_fake_ar(self):
        ui=self.read('App/PlayKitPersonalForms.swift')
        self.assertIn('artwork(raw["overlayUrl"].text)',ui)
        self.assertIn('playkitLegacy.scan.staticFallback',ui)
        self.assertNotIn('ARWorldTrackingConfiguration',ui)
    def test_localizations_cover_literal_new_ui(self):
        strings=json.loads(self.read('docs/playkit-authoring-legacy-localizations.json'))
        fragment=json.loads(self.read('Resources/PlayKitAuthoringLegacyLocalizations.fragment.json'))['strings']
        self.assertEqual(set(strings),set(fragment))
        files=['App/TemplateMiniGameConfigurationView.swift','App/PlayKitLegacyViews.swift','App/TemplateAuthoringDetailForms.swift','App/PlayKitPersonalForms.swift']
        for path in files:
            for key in re.findall(r'"((?:playkitAuthor|playkitLegacy)\.[A-Za-z0-9_.]+)"',self.read(path)):
                if key.endswith('.'):continue
                self.assertIn(key,strings)
                self.assertEqual(set(strings[key]),{'en','zh-Hans'})
    def test_provider_and_backend_grants_remain_off(self):
        self.assertIn('enabled: Set<PlayExperienceCapability> = []',self.read('Core/PlayExperienceService.swift'))
        self.assertIn('transport: (any TemplateAuthoringTransport)? = nil',self.read('Core/TemplateAuthoringService.swift'))
        self.assertIn('approvedArtworkHosts: Set<String> = []',self.read('App/PlayKitScreen.swift'))
        self.assertIn('PlayKitDormantSensorProvider()',self.read('App/PlayKitSensorChallengeView.swift'))

if __name__=='__main__':unittest.main()
