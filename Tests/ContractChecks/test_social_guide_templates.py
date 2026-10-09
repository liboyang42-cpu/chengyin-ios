"""Narrow source contracts; these do not replace Apple compile/hosted execution."""
from pathlib import Path
import hashlib,json,re,unittest
ROOT=Path(__file__).resolve().parents[2]
NEW=ROOT/'App/SocialGuideTemplateSection.swift'
PROTECTED = {'App/TicketWalletDetailView.swift': 'f5eb0bee1d74415d0cbbc21443107cd2049ae6dce3fa49c5be8772b8a25a15e2', 'Tests/AppUnitTests/TicketWalletPlayEntryTests.swift': 'a6f7432a2960ba9458cc7eb776b62f28ecf0cad6f66005981d0d5937c7ad6712', 'Tests/ContractChecks/test_ticket_wallet_play_entry.py': 'be04e6f6a464eec179a452ae85e8dc666146585ed7ff62a42d47825587daf64e', 'App/DiscoveryReading.swift': 'baf78d181e36f5d7800fd0646e457a19b0a39ed8e5d2114626ef4f6d383191be', 'App/DiscoveryPresentationScope.swift': 'f52f4e4f250f1d685d359579f5d3306466b8d9c89be0205f814e9c626f0a3c8a', 'App/DiscoveryTemplateBrowserView.swift': '9f91ec1a5e344ffc6932b883ed780fb06c4260183f7730f1b037f6938c860f6e', 'App/DiscoveryTemplateDetailView.swift': 'bb36d44d6413e79dc8e4380efd1eaf6de7d7ec06f206c542a5c1f2f0b8b88883', 'App/DiscoveryPlayTemplatePresentationView.swift': '6bfa05048457b33658d6490d1a31d9905b8e740320e843d3bfe499bf511edbde', 'App/AppSession.swift': 'd6a39320f8978fc5179ce615bf9335a510dd2f3280901e093f2d0187bbb65187', 'Core/DiscoveryContracts.swift': '565d8472c4d5b5285f151270408de8d7b83505caed2a9045a838096e60e8cecf', 'Core/DiscoveryService.swift': 'd3064d85ac276d7ee21bcfae3a5fde0965635063ec5323ac8c9d6d3b0512292a', 'Core/SocialAccountContracts.swift': '04376c38dc043aaa4ab436f2e08c60a12e67c0354b300068b7e2aa3d22039a4c', 'Core/SocialAccountService.swift': '42245e981f40181f791d21dbb0b2c81d90672f0c01600369333eda57b787fb82', 'App/SocialAccountComponents.swift': 'db709b09b552839ee0d31c1a8eaa97c8781fddcc1d7b59a2353ac198a28fef0c', 'App/SocialAccountFixtureSupport.swift': 'cba92bc13a1ebf32f6c1820307bb5779c144b6ed4a30d500c568c8fdd39afcb1', 'App/SocialArticleContentView.swift': '7c90b92770976eea41147170f91fb0e71149ca21da4a8bbdd56367f7e57e5b14', 'App/ProfileEditView.swift': '5bec19374886dc1f2f780a170675ead92425b99a643fcf6b6bf09f5c9e59ac73', 'App/SettingsView.swift': '71d5c2d1951ec43c206ed9c3ba32799adb0c4e227a38aa126f965c40cd3d5df9', 'App/SettingsAboutView.swift': '585345c14d5979ac9ae26896c63f7171d49648719bbd750bae0e70504180724c', 'App/SettingsSupportSections.swift': '3bce8a7d7c6cd5a2d26fe84f08db7f041331c111f211ee2e22e26db3f945f044', 'App/SettingsLegalDocumentView.swift': 'b4265846b83888ae09d1b6420b0b6b96ae3cbcfd82a6bb4f9cb97ec5a623a0e4', 'App/AccountCollectionFavoritesView.swift': '4a5053d9b3675b68d465b04d3eb607e27dd1d73d8e93aa205091e01c8d3ba0ec'}
INVERSES = {'App/AccountView.swift': {'base_sha256': '617807e0af1ca7071a9eb367d55200bf3c5bffc1be528c46bd7405779f6617c6', 'hunks': [(2957, b'                    NavigationLink { SocialPlayGuideView(reader: session.socialAccountReader, onOpenDestination: onOpenGuideDestination, templateReader: session).id(session.socialAccountReader.identity) } label: {\n', b'                    NavigationLink { SocialPlayGuideView(reader: session.socialAccountReader, onOpenDestination: onOpenGuideDestination).id(session.socialAccountReader.identity) } label: {\n')]}, 'App/SocialGuideViews.swift': {'base_sha256': 'cd44920e357a25b1628d22e0bad0bd2eb381c80374f6bdbeab7218df6bf6e5fe', 'hunks': [(172, b'    var templateReader: (any DiscoveryReading)? = nil\n', b''), (848, b'            SocialGuideTemplateSection(reader: templateReader)\n', b'')]}}

class GuideTemplateContracts(unittest.TestCase):
    def setUp(self): self.s=NEW.read_text()
    def test_exact_shared_file_inverse(self):
        for path, proof in INVERSES.items():
            raw=(ROOT/path).read_bytes()
            for offset, after, before in reversed(proof['hunks']):
                self.assertEqual(raw[offset:offset+len(after)],after)
                raw=raw[:offset]+before+raw[offset+len(after):]
            self.assertEqual(hashlib.sha256(raw).hexdigest(),proof['base_sha256'])
    def test_existing_ticket_play_and_read_contracts_are_unchanged(self):
        for path, digest in PROTECTED.items(): self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(),digest,path)
    def test_only_existing_discovery_home_read_is_added(self):
        self.assertEqual(self.s.count('try await reader.discoveryTemplateHome()'),1)
        for forbidden in ['URLSession', 'api/', 'authoringFactory:', 'TemplateAuthoringCoordinator', 'AppSession', 'accessToken', 'UserDefaults', 'FileManager', 'NotificationCenter']:
            self.assertNotIn(forbidden,self.s)
    def test_nonempty_pool_is_selected_before_filter_and_six_limit(self):
        self.assertIn('!home.hot.isEmpty ? home.hot : !home.recommended.isEmpty ? home.recommended : home.mustPlay',self.s)
        self.assertIn('source.filter { $0.id > 0 && !text($0.title).isEmpty }.prefix(6)',self.s)
        self.assertIn('$0 > 0 ? $0 : nil',self.s)
    def test_async_completions_bind_generation_reader_object_scope_and_configuration(self):
        for token in ['ObjectIdentifier(reader)','scope = reader.discoveryPresentationIdentity','configured = reader.isConfigured','request == generation, key == ReaderKey(reader), !Task.isCancelled']:
            self.assertIn(token,self.s)
        self.assertEqual(self.s.count('request == generation, key == ReaderKey(reader), !Task.isCancelled'),2)
    def test_exact_row_snapshot_and_current_scope_guard_destinations(self):
        for token in ['snapshot.id == snapshotID','snapshot.rows.indices.contains(index)','target: .detail(snapshot.rows[index].id)','permit.generation == generation, permit.key == ReaderKey(reader), selection == nil','selection?.key == ReaderKey(reader)']:
            self.assertIn(token,self.s)
    def test_catalog_action_is_generation_bound_at_render(self):
        self.assertIn('let catalogPermit = model.catalogPermit(reader: reader)',self.s)
        self.assertIn('model.openCatalog(reader: reader, permit: catalogPermit)',self.s)
        self.assertIn('permit.generation == generation, permit.key == ReaderKey(reader), selection == nil',self.s)
        tests=(ROOT/'Tests/AppUnitTests/SocialGuideTemplateTests.swift').read_text()
        self.assertIn('testOldRenderedCatalogActionCannotReviveAfterSameReaderRetirementAndReturn',tests)
        self.assertIn('testCoveringSheetSuspensionRetiresOldCatalogPermitWithoutClosingSelection',tests)
    def test_queued_retry_and_old_dismissal_are_bound(self):
        self.assertIn('permit.generation == generation, permit.key == ReaderKey(reader), !Task.isCancelled',self.s)
        self.assertIn('let retryPermit = model.reloadPermit(reader: reader)',self.s)
        self.assertIn('if selection?.id == id { selection = nil }',self.s)
        self.assertIn('model.closeDestination(id: destination.id)',self.s)
        self.assertIn('let id = presented?.id { model.closeDestination(id: id)',self.s)
    def test_scene_scope_departure_and_sheet_cover_are_separate(self):
        self.assertIn('.task(id: loadKey)',self.s)
        self.assertIn('.onReceive(reader.discoveryPresentationChanges)',self.s)
        self.assertIn('if phase != .active { model.invalidate() }',self.s)
        self.assertIn('if model.selection == nil { model.invalidate() } else { model.suspend() }',self.s)
        self.assertIn('if scenePhase == .active, model.destination(reader: reader)?.id == destination.id',self.s)
    def test_details_and_full_catalog_use_read_only_existing_destinations(self):
        self.assertIn('DiscoveryTemplateDetailView(id: id, reader: reader)',self.s)
        self.assertIn('DiscoveryTemplateBrowserView(reader: reader)',self.s)
        self.assertNotIn('NavigationLink',self.s)
    def test_template_error_is_local_and_catalog_is_not_hidden_by_error(self):
        self.assertIn('else if model.phase == .failed',self.s)
        self.assertIn('Button("action.retry")',self.s)
        self.assertIn('Button("social.guideTemplates.browse")',self.s)
        self.assertIn('.disabled(!reader.isConfigured || scenePhase != .active)',self.s)
        self.assertIn('SocialReadScreen(reader: reader, requestKey: "information-list"', (ROOT/'App/SocialGuideViews.swift').read_text())
    def test_locale_fragment_is_complete_and_separate(self):
        data=json.loads((ROOT/'Resources/SocialGuideTemplateLocalizations.fragment.json').read_text())
        self.assertEqual(len(data),7)
        for value in data.values():
            for locale in ['en','zh-Hans']: self.assertTrue(value['localizations'][locale]['stringUnit']['value'])
        used=set(re.findall(r'(?:Text|Section|LabeledContent|Button)\("(social\.guideTemplates\.[^"\\]+)"',self.s))
        self.assertEqual(used,set(data))
    def test_focused_hosted_regressions_are_authored(self):
        s=(ROOT/'Tests/AppUnitTests/SocialGuideTemplateTests.swift').read_text()
        self.assertEqual(len(re.findall(r'func test',s)),33)
        for name in ['testLateSuccessFromOldScopeCannotPublish','testLateFailureCannotReplaceNewerSuccessfulLoad','testOldRenderedCatalogActionCannotNavigateInReplacementScope','testOldDismissalCannotCloseNewerDestination','testQueuedRetryCannotReadAfterRetirement','testPresentedSheetSuspensionKeepsExactScopeSelectionAndRows']:
            self.assertIn(name,s)
    def test_account_changes_only_the_existing_guide_dependency(self):
        proof=INVERSES['App/AccountView.swift'];self.assertEqual(len(proof['hunks']),1)
        after,before=proof['hunks'][0][1:]
        self.assertEqual(after.replace(b', templateReader: session',b''),before)
    def test_guide_changes_only_add_optional_read_injection_and_section(self):
        proof=INVERSES['App/SocialGuideViews.swift'];self.assertEqual(len(proof['hunks']),2)
        self.assertEqual([h[2] for h in proof['hunks']],[b'',b''])
        self.assertIn('var templateReader: (any DiscoveryReading)? = nil',str(proof))
if __name__=='__main__':unittest.main(verbosity=2)
