import json
import re
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
class OptionalModuleSourceChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core=(ROOT/'Core/TemplateOptionalModules.swift').read_text()
        cls.app=(ROOT/'App/TemplateOptionalModuleManager.swift').read_text()
        cls.host=(ROOT/'App/TemplateAuthoringView.swift').read_text()
    def test_real_three_module_workflow_is_mounted(self):
        for token in ['case reward, story, voice','case add(Module), remove(Module)']: self.assertIn(token,self.core)
        for token in ['TemplateOptionalModuleManager(model: model)','templateModules.open']: self.assertIn(token,self.host)
        for token in ['removalAction','addAction','confirm(_ original','cancel(_ original','saveAction','ForEach(original.fields)']: self.assertIn(token,self.app)
    def test_source_owned_clear_fields_and_native_adaptations(self):
        for token in ['next.couponId = 0','next.feedbackText = ""','next.medalImg = ""','next.medalName = ""','next.medalStyle = "glow"','next.storyText = ""','next.storyJson = ""','next.storyTimelineEdited = true','next.audioUrl = ""','next.audioDuration = nil']: self.assertIn(token,self.core)
        for token in ['next.storyImg =','next.advanced','next.preferenceJson','next.sensorDraft','next.finishEnabled','next.validationMethod']: self.assertNotIn(token,self.core)
    def test_core_exact_source_fence(self):
        for token in ['fingerprint: Data?','.sortedKeys','.withoutEscapingSlashes','guard isCurrent(draft)','guard !enabled(module)','guard canRemove(module)']: self.assertIn(token,self.core)
    def test_controller_lifetime_and_review_identity(self):
        for token in ['session == model.coordinator.session','identity == model.coordinator.identity','mediaGeneration == model.mediaReviewGeneration','scope.isCurrent(model.draft)','model.$draft.dropFirst()','currentReview?.id == original.id','original.generation == generation','self.model.metadataGeneration == metadata','self.review == nil']: self.assertIn(token,self.app)
    def test_host_retires_media_and_story_before_draft_commit(self):
        helper=self.host.split('func commitOptionalModuleChange',1)[1].split('func setGameEnabled',1)[0]
        self.assertLess(helper.index('retireMediaReviews()'),helper.index('draft = next'))
        self.assertLess(helper.index('storyEditorGeneration += 1'),helper.index('draft = next'))
        self.assertIn('scope.applying(change, to: draft)',helper)
        self.assertIn('changed(); reloadMediaReviews()',helper)
    def test_no_runtime_grants_or_backend_calls(self):
        for token in ['URLSession','AsyncImage','AVPlayer','chooseImage','chooseDocument','capabilityGrant','ProductionTransport','submit(','sendEvent(','requestAuthorization','requestWhenInUseAuthorization']: self.assertNotIn(token,self.core+self.app)
    def test_bilingual_fragment_and_registration(self):
        fragment=json.loads((ROOT/'docs/localization/template-optional-modules.json').read_text())['strings']
        used=set(re.findall(r'"(templateModules\.[a-zA-Z]+)"',self.app+self.core))
        used-={'templateModules.saveLocal'}
        self.assertTrue(used.issubset(fragment),used-set(fragment))
        for key,entry in fragment.items():
            for lang in ['en','zh-Hans']: self.assertTrue(entry['localizations'][lang]['stringUnit']['value'])
        registration=json.loads((ROOT/'docs/registration/template-optional-modules.json').read_text())
        self.assertEqual(registration['dependencies'],[]);self.assertEqual(len(registration['app_sources']),2)
    def test_authored_native_coverage_is_explicit(self):
        core=(ROOT/'Tests/CoreTests/TemplateOptionalModulesTests.swift').read_text(); app=(ROOT/'Tests/AppUnitTests/TemplateOptionalModuleManagerTests.swift').read_text()
        self.assertEqual(len(re.findall(r'func test',core)),12);self.assertEqual(len(re.findall(r'func test',app)),14)
        for token in ['testInspectCancelConfirmReAddWholeFlow','testExternalDraftChangeAndABAInvalidateReview','testCommitRotatesMediaAndStoryLeasesBeforeRemoval','testNativeSaveRestoreKeepsRemovedAndReAddedState','testPendingWriteLockRejectsModuleManager']: self.assertIn(token,app)
