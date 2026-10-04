"""Executed source/structure assertions. Not Swift compilation or runtime acceptance."""
import ast
import json
import os
import re
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(os.environ.get('FLUTTER_AUDIT_ROOT', str(ROOT.parent / 'app-audit')))

class TemplateAuthoringContracts(unittest.TestCase):
    def read(self, path):
        local = ROOT/path
        return (local if local.exists() else ROOT.parent/'chengyin-ios'/path).read_text()
    def source(self, path):
        if not SOURCE.exists(): self.skipTest('Flutter source unavailable; no source verification')
        return (SOURCE/path).read_text()
    def test_exact_template_endpoint_set(self):
        native=self.read('Core/TemplateAuthoringContract.swift')
        paths=set(re.findall(r'"(/api/[^\"]+)"',native))
        self.assertEqual(paths, {'/api/template/my-list','/api/template/draft','/api/template/publish','/api/template/delete','/api/template/updateLibraryStatus','/api/common/dict'})
        source=self.source('lib/data/api/template_api.dart')+self.source('lib/data/api/registration_api.dart')
        for path in paths:self.assertIn("'"+path+"'",source)
    def test_payload_field_names_match_all_source_fields(self):
        source=self.source('lib/data/models/template_draft.dart').split('Map<String, dynamic> toJson()')[1].split('class TemplatePublishException')[0]
        expected=set(re.findall(r"'([^']+)'\s*:",source))
        native=self.read('Core/TemplateAuthoringContract.swift').split('public static func payload(')[1].split('public static func decodeList')[0]
        actual=set(re.findall(r'(?:string|number)\("([^"]+)"',native))|set(re.findall(r'(?:p\[|\[)"([^"]+)"',native))|{'description','isSync'}
        # The mini-program medal contract extends the legacy Flutter payload.
        self.assertEqual(expected | {'medalStyle'},actual)
    def test_no_module_flags_on_wire(self):
        native=self.read('Core/TemplateAuthoringContract.swift')
        for key in ['finishEnabled','rewardEnabled','storyEnabled','voiceEnabled']:
            self.assertNotIn('"'+key+'"',native)
    def test_source_defaults_are_exact(self):
        source=self.source('lib/data/models/advanced_play_config.dart')
        raw=source.split('Map<String, Object?> defaultAdvancedConfig() => ')[1].split('\n};')[0]+'\n}'
        raw=re.sub(r'//[^\n]*','',raw);raw=re.sub(r'<[^>]+>','',raw)
        raw=raw.replace('kAdvancedConfigSchemaVersion','1').replace('kHotspotRadius','0.08')
        raw=re.sub(r'\btrue\b','True',raw);raw=re.sub(r'\bfalse\b','False',raw);raw=raw.replace('null','None')
        self.assertEqual(ast.literal_eval(raw),json.loads(self.read('docs/advanced-source-defaults.json')))
    def test_source_enabled_game_catalog(self):
        source=self.source('lib/feature/template/advanced_game_configurator.dart').split('kImplementedGameKeys')[1].split('};')[0]
        keys=set(re.findall(r"'([^']+)'",source))
        self.assertEqual(keys,{'coin','dice','react','shake','quiet','countdown','stopwatch'})
        native=self.read('Core/TemplateAdvancedDraft.swift')
        self.assertIn('case coin, dice, react, shake, quiet, countdown, stopwatch',native)
    def test_source_verification_codes_not_conflated(self):
        labels=self.source('lib/data/models/validation_method_labels.dart')
        self.assertIn("5: 'GPS 到达'",labels)
        self.assertIn('gps = 5',self.read('Core/TemplateAuthoringDomain.swift'))
    def test_adopt_does_not_reconstruct_hidden_answers(self):
        source=self.source('lib/feature/template/template_detail_page.dart')
        self.assertIn('originalTemplateId: t.id',source)
        native=self.read('Core/TemplateAuthoringDomain.swift').split('public static func adopt(')[1]
        self.assertIn('d.originalTemplateID = source',native)
        for field in ['questionAnswer','correctAnswer','validationMethod','questionName']:self.assertNotIn('d.'+field+' =',native)
    def test_template_ids_are_typed_and_not_topic_identity(self):
        native=self.read('Core/TemplateAuthoringDomain.swift')
        self.assertIn('struct AuthoringPlayTemplateID',native)
        self.assertIn('var originalTemplateID: AuthoringPlayTemplateID?',native)
        self.assertNotIn('DiscoveryTopicTemplate',native)
    def test_source_prefab_scene_order(self):
        source=self.source('lib/feature/prefab/prefab_story_engine.dart').split('kPrefabScenes = <String>[')[1].split('];')[0]
        expected=re.findall(r"'([^']+)'",source)
        native=self.read('Core/PrefabPreviewEngine.swift').split('case prologue,')[1].split('\n')[0]
        self.assertEqual(expected,['prologue']+[v.strip() for v in native.split(',')])
    def test_secure_storage_no_plaintext_fallback(self):
        native=self.read('App/TemplateAuthoringSecureStorage.swift')
        for value in ['kSecAttrAccessibleWhenUnlockedThisDeviceOnly','kSecAttrSynchronizable as String: false','scope.service + ".template-author"','guard let scope']:self.assertIn(value,native)
        self.assertNotIn('UserDefaults',native)
    def test_account_region_epoch_and_authorization_guards(self):
        storage=self.read('Core/TemplateAuthoringStorage.swift')
        for token in ['authorizationRevision','epoch','namespace','accountID','value.identity == identity','value.ownerKey == session.ownerKey']:self.assertIn(token,storage)
        coordinator=self.read('Core/TemplateAuthoringCoordinator.swift')
        self.assertIn('value.session == currentSession()',coordinator)
        self.assertIn('value.generation == generation',coordinator)
        self.assertIn('value.draft == draft',coordinator)
        self.assertIn('guard active(session, stamp)',coordinator)
    def test_durable_intent_precedes_fake_transport(self):
        native=self.read('Core/TemplateAuthoringCoordinator.swift').split('public func confirm(')[1]
        self.assertLess(native.index('try store.save(draft'),native.index('try store.savePending'))
        self.assertLess(native.index('try store.savePending'),native.index('await adapter.submit'))
        self.assertIn('if let existing = try store.pending',native)
    def test_uncertain_outcomes_never_retry_or_reconcile_from_title(self):
        native=self.read('Core/TemplateAuthoringCoordinator.swift')
        self.assertEqual(native.count('await adapter.submit'),2)
        self.assertEqual(native.split('public func confirm(')[1].split('public func loadMine')[0].count('await adapter.submit'),1)
        self.assertEqual(native.split('public func confirmShelf(')[1].count('await adapter.submit'),1)
        self.assertIn('case .uncertain: state = .uncertain',native)
        self.assertNotIn('terminalReceipt(',native)
        self.assertIn('guard try pending(session: session, identity: identity) == nil',self.read('Core/TemplateAuthoringStorage.swift'))
    def test_production_hard_off_and_no_live_transport(self):
        service=self.read('Core/TemplateAuthoringService.swift')
        self.assertIn('#if DEBUG',service);self.assertIn('return false',service);self.assertIn('transport: (any TemplateAuthoringTransport)? = nil',service)
        for folder in ['App','Core']:
            for path in (ROOT/folder).glob('*Template*.swift'):
                self.assertNotIn('URLSession',path.read_text())
                if path.name != 'TemplateAuthoringWireRequestBuilder.swift': self.assertNotIn('URLRequest(',path.read_text())
    def test_dormant_wire_builder_is_exact_and_has_no_send(self):
        source=self.source('lib/data/api/template_api.dart')
        native=self.read('Core/TemplateAuthoringWireRequestBuilder.swift')
        self.assertIn('FormData.fromMap',source)
        self.assertIn('multipart/form-data; boundary=',native)
        self.assertIn('application/json',native)
        self.assertIn('forHTTPHeaderField: "Authorization"',native)
        self.assertNotIn('.send(',native)
        self.assertNotIn('URLSession',native)
    def test_debug_only_fixtures(self):
        for file in ['Core/TemplateAuthoringSyntheticFixtures.swift','App/TemplateAuthoringFixtureSupport.swift']:
            text=self.read(file).strip();self.assertTrue(text.startswith('#if DEBUG'));self.assertTrue(text.endswith('#endif'))
    def test_bilingual_catalog_and_literal_ui_keys(self):
        catalog=json.loads(self.read('docs/template-authoring-localizations.json'))
        catalog.update(json.loads(self.read('docs/template-authoring-repair-localizations.json')))
        catalog.update(json.loads(self.read('tools/template_preference_medal_localizations.json')))
        catalog.update(json.loads(self.read('tools/template_preference_draft_localizations.json')))
        for key,entry in catalog.items():self.assertEqual(set(entry),{'en','zh-Hans'},key);self.assertTrue(all(entry.values()),key)
        identifiers={'templateAuthor.preference.status','templateAuthor.shelf.readStatus','templateAuthor.status','templateAuthor.field.','templateAuthor.cancelReview','templateAuthor.game.','templateAuthor.openEditor','templateAuthor.openMine','templateAuthor.openPrefab','templateAuthor.shelf.status','templateAuthor.shelf.cancel','templateAuthor.shelf.confirm'}
        for path in list((ROOT/'App').glob('TemplateAuthor*.swift'))+list((ROOT/'App').glob('TemplatePreference*.swift'))+list((ROOT/'App').glob('PrefabPreview*.swift'))+list((ROOT/'Core').glob('TemplateAuthor*.swift')):
            for key in re.findall(r'"(templateAuthor\.[A-Za-z][A-Za-z.]+)"',path.read_text()):
                if key not in identifiers and not key.endswith('.'):self.assertIn(key,catalog,key)
    def test_authored_tests_are_not_claimed_as_executed(self):
        self.assertGreaterEqual(self.read('Tests/CoreTests/TemplateAuthoringTests.swift').count('func test'),55)
        ui=self.read('Tests/AppUITests/TemplateAuthoringFlowTests.swift')
        self.assertEqual(ui.count('func test'),10);self.assertIn('No UI test was run',ui)
    def test_production_factory_stays_disabled_and_scoped(self):
        session=self.read('App/AppSession.swift')
        section=session.split('func templateAuthoringEditor(')[1].split('private let creatorContentService')[0]
        self.assertIn('TemplateAuthoringAdapter()',section)
        self.assertNotIn('transport:',section)
        self.assertIn('namespace: storageScope.service',session)
        self.assertIn('authorizationRevision: account.effectiveRole',session)
        app=self.read('App/QuestifyApp.swift')
        self.assertEqual(app.count('contains("--ui-template-authoring")'),2)
    def test_guide_roam_routes_to_actual_roam_tab_tag(self):
        app=self.read('App/QuestifyApp.swift')
        actual=re.search(r'Label\("roam.title",systemImage:[^\n]+\) \}\.tag\((\d+)\)',app)
        selected=re.search(r'destination == \.roam \? (\d+) : (\d+)',app)
        self.assertIsNotNone(actual);self.assertIsNotNone(selected)
        self.assertEqual(actual.group(1),selected.group(1))
        home=re.search(r'SessionHomeFeedView[^\n]+\.tag\((\d+)\)',app)
        self.assertIsNotNone(home);self.assertEqual(home.group(1),selected.group(2))
    def test_no_false_gameplay_in_prefab_preview(self):
        native=self.read('App/PrefabPreviewView.swift')
        for key in ['No location, camera, microphone','production gameplay','captured == currentSession()']:self.assertIn(key,native)
        self.assertNotIn('transport.send',native)

if __name__=='__main__':unittest.main()
