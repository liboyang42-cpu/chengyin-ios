"""Supplementary source-contract checks; not Swift execution or Apple acceptance."""
import json
import pathlib
import re
import unittest
from flutter_source import read_flutter_source
ROOT=pathlib.Path(__file__).resolve().parents[2]
class PlayDirectorPrefabSourceChecks(unittest.TestCase):
    def read(self,name):return (ROOT/name).read_text()
    def test_prefab_reuses_engine_and_has_no_preview_restore(self):
        text=self.read('Core/PlayPrefabRuntime.swift')
        self.assertIn('PrefabPreviewState',text)
        self.assertIn('prefab-runtime.v1.',text)
        self.assertNotIn('PrefabPreviewStore(',text)
        self.assertIn('clean.photos = [:]',text);self.assertIn('clean.synced = false',text)
        self.assertIn('record.story.synced = false',text)
    def test_prefab_arrival_photo_readback_chain_matches_source(self):
        text=self.read('Core/PlayPrefabRuntime.swift')
        self.assertIn('evidence: .location',text);self.assertIn('evidence: .photo',text)
        self.assertIn('first.done == true || document.extras[first.id]?.uploadedImage?.isEmpty == false',text)
        self.assertIn('pendingPhotoNodeID',text);self.assertIn('pendingUploadKey',text)
    def test_prefab_arrival_external_flutter_parity(self):
        source=read_flutter_source(self, 'feature/prefab/prefab_life_page.dart')
        for name in ['submitArrive','submitPhoto','fetchNodes']:self.assertIn(name,source)
    def test_upload_contract_uses_file_and_top_level_url(self):
        text=self.read('Core/PlayPrefabRuntime.swift')
        self.assertIn('api/common/uploadOSS',text)
        self.assertIn('name=\\"file\\"',text);self.assertIn('raw["url"].text',text)
        self.assertIn('10 * 1024 * 1024',text)
    def test_upload_external_flutter_parity(self):
        source=read_flutter_source(self, 'data/api/play_api.dart')
        self.assertIn('/api/common/uploadOSS',source)
    def test_scene_source_constants_and_timing(self):
        text=self.read('Core/PlayPrefabScenes.swift')
        self.assertIn('bootTarget = "hello world"',text)
        for item in ['story.walkProgress == 50','story.walkProgress == 74','now - (bootAnchor ?? now) < 10','now - (bootAnchor ?? now) < 6','1.5 : 3.0','>= 8','quizAnswers = [1, 0, 1]']:
            self.assertIn(item,text)
        self.assertIn('1.8 + 2.2',text)
    def test_scene_timing_external_flutter_parity(self):
        source=read_flutter_source(self, 'feature/prefab/prefab_life_page.dart')
        self.assertIn('Duration(milliseconds: 1800)',source)
    def test_source_scene_logic_is_not_remote_reward(self):
        text=self.read('Core/PlayPrefabScenes.swift')
        self.assertNotIn('HTTPTransport',text);self.assertNotIn('URLSession',text)
        self.assertNotIn('synced = true',text)
    def test_director_editor_uses_actual_source_reason_codes(self):
        text=self.read('App/PlayDirectorView.swift')
        for code in ['ONSITE','ONSITE_REJECT']:self.assertIn('"'+code+'"',text)
        self.assertIn('projection.allows(command)',text);self.assertIn('confirmationDialog',text)
    def test_director_reason_codes_external_flutter_parity(self):
        source=read_flutter_source(self, 'feature/club/club_director_controller.dart')
        for code in ['ONSITE','ONSITE_REJECT']:self.assertIn("'"+code+"'",source)
    def test_recap_export_is_whitelisted(self):
        text=self.read('Core/PlayDirectorRecap.swift')
        for key in ['GAME_RECAP_EXPORT_V1','GAME_RECAP_V1','eligibleTeams','completedTeams','ratePercent','merchantFallbackCompletions']:
            self.assertIn(key,text)
        for forbidden in ['"phone":','"memberId":','"evidence":']:self.assertNotIn(forbidden,text)
        self.assertIn('normalizeExport',text);self.assertIn('validDateTime',text)
    def test_recap_export_external_flutter_parity(self):
        source=read_flutter_source(self, 'data/models/game_session.dart')
        for key in ['GAME_RECAP_EXPORT_V1','GAME_RECAP_V1','eligibleTeams','completedTeams','ratePercent','merchantFallbackCompletions']:
            self.assertIn(key,source)
    def test_new_ui_is_localized_and_has_accessible_controls(self):
        strings=json.loads((ROOT/'docs/play-experience-localizations.json').read_text())
        for name in ['PlayDirectorView.swift','PlayPrefabRuntimeView.swift']:
            text=self.read('App/'+name)
            for key in re.findall(r'(?:Text|Button|Section|TextField|LabeledContent|navigationTitle)\("(playx\.[A-Za-z0-9_.-]+)"',text):
                self.assertIn(key,strings);self.assertTrue(strings[key]['en']);self.assertTrue(strings[key]['zh-Hans'])
            self.assertIn('accessibilityIdentifier',text)
    def test_no_live_device_frameworks_in_core(self):
        text=self.read('Core/PlayPrefabRuntime.swift')+self.read('Core/PlayPrefabScenes.swift')
        for token in ['import CoreLocation','import AVFoundation','import Photos','URLSession.shared','requestAuthorization']:
            self.assertNotIn(token,text)
    def test_fixed_dice_only_live_in_synthetic_fixture(self):
        text=self.read('App/PlayDirectorPrefabFixtureSupport.swift')
        self.assertTrue(text.startswith('#if DEBUG'))
        self.assertIn('PlaySyntheticDeviceProvider',text);self.assertIn('https://example.com/fixture/',text)
if __name__=='__main__':unittest.main()
