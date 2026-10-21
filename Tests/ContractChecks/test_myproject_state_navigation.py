"""C5 supplementary source checks; Swift decision and UI behaviour require Apple execution."""
from pathlib import Path
import re, unittest
ROOT = Path(__file__).resolve().parents[2]

class MyProjectStateNavigationContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()

    def test_decision_reuses_core_route_and_owner_target_without_restating_state_policy(self):
        source = self.read('App/MyProjectStateNavigation.swift')
        for token in ['MyProjectListPresentation.resolveRoute(', 'ProjectEditRemoteTarget(project: project, readerScope: readerScope)',
                      'case ownerTopicEditor(ProjectEditRemoteTarget)', 'case activityEditor(MyProjectActivityEditorRequest)',
                      'merchantScopeAccess.isBrowseOnly', 'project.destination.map',
                      'return .activityEditor(.init(activityID: id, readerScope: readerScope))']:
            self.assertIn(token, source)
        # State lists stay in Core resolveRoute; the App decision must not duplicate them.
        for state in ['"draft"', '"rejected"', '"pending"', '"running"']:
            self.assertNotIn(state, source)
        self.assertNotIn('ActivityEditingGrants(', source)
        self.assertNotIn('ActivityDetailView', source)

    def test_activity_editor_uses_the_existing_factory_and_does_not_invent_one(self):
        source = self.read('App/MyProjectStateNavigation.swift')
        adapter = self.read('App/MyProjectActivityEditorAdapter.swift')
        host = self.read('App/ProjectOwnedContentViews.swift')
        self.assertIn('case .activityEditor(let id):', source)
        self.assertIn('isServerSaveReceipt', source)
        self.assertIn('status == "acknowledged"', source)
        for absent in ['ActivityPublishingView', 'URLSession', 'ActivityEditingGrants(', 'ActivityDetailView']:
            self.assertNotIn(absent, adapter)
        for token in ['ActivityEditingView(owner: controller, makeActivityCover: makeCover)',
                      'makeEditor?(request.activityID)', 'myProject.state.activityEditorUnavailable',
                      'AppSession.activityEditingController(id:)']:
            self.assertIn(token, adapter)
        self.assertIn('makeActivityEditor: { session.activityEditingController(id: $0) }', host)
        self.assertIn('MyProjectActivityEditorPolicy.refreshRequest(token: token, status: "acknowledged"', host)
        self.assertNotIn('activityEditorUnavailableDetail', host)
        self.assertNotIn('activityEditorUnavailableDetail', source)

    def test_browser_routes_editor_directly_and_details_otherwise(self):
        host = self.read('App/ProjectOwnedContentViews.swift')
        for token in ['let decision: MyProjectStateNavigationDecision',
                      'navigation.open(project, scope: scope, reader: reader,',
                      'MyProjectMerchantScopeExclusiveAdapter.access(responseScope: serverScope)',
                      'case .ownerTopicEditor(let target):',
                      'case .activityEditor(let request):',
                      'case .detail(let destination):',
                      'ProjectRemoteEditorDestination(target: target, reader: reader, revision: revision,',
                      'if !value.merchantScopeAccess.isBrowseOnly,',
                      'ProjectEditRemoteTarget(project: value.project, readerScope: value.scope)',
                      'navigation.presentation(presented)', 'navigation.retire(scope: original)',
                      'listRefresh: listRefresh']:
            self.assertIn(token, host)
        # The direct-editor branch must not wrap the editor inside the detail host.
        editor_branch = host.split('case .ownerTopicEditor(let target):')[1].split('case .detail(')[0]
        self.assertNotIn('detail(destination)', editor_branch)
        self.assertNotIn('ActivityDetailView', editor_branch)

    def test_save_receipt_refreshes_only_the_same_scope_and_cancel_does_not(self):
        projects = self.read('App/CreatorContentViews.swift')
        self.assertIn('guard let request, request.readerScope == reader.scope, reader.isAuthenticated else { return }', projects)
        self.assertIn('Task { await refresh() }', projects)
        navigation = self.read('App/MyProjectStateNavigation.swift')
        self.assertIn('guard isServerSaveReceipt(status)', navigation)
        for status in ['localSaved', 'editing', 'notSent']:
            self.assertNotIn(f'status == "{status}"', navigation)

    def test_browse_only_hides_list_and_detail_writes_without_inferring_a_role(self):
        host = self.read('App/ProjectOwnedContentViews.swift')
        tabs = self.read('App/MyProjectTabViews.swift')
        self.assertIn('MyProjectMerchantScopeExclusiveAdapter.access(responseScope:', host)
        self.assertNotIn('.environment(\\.myProjectMerchantScopeAccess, MyProjectMerchantScopeAccess())', host)
        self.assertNotIn('merchantAccessRecord', host)
        self.assertNotIn('MERCHANT_OWNER', host)
        self.assertIn('!merchantScopeAccess.isBrowseOnly', tabs)
        self.assertIn('MyProjectListPresentation.card(project, merchantScopeAccess: merchantScopeAccess)', tabs)
        self.assertIn('publishingSession?.role == "club"', tabs)

    def test_close_never_rewrites_the_captured_row(self):
        host = self.read('App/ProjectOwnedContentViews.swift')
        close = host.split('func close(_ original: Selection)')[1].split('func retire')[0]
        self.assertIn('selection = nil', close)
        self.assertNotIn('project', close)
        self.assertIn('never rewrites', host)

    def test_new_swift_files_are_registered_in_the_xcode_project(self):
        pbx = self.read('Questify.xcodeproj/project.pbxproj')
        for path in ['App/MyProjectStateNavigation.swift', 'App/MyProjectActivityEditorAdapter.swift',
                     'Tests/AppUnitTests/MyProjectStateNavigationTests.swift',
                     'Resources/MyProjectActivityEditor.xcstrings']:
            self.assertIn(f'"path" = "{path}";', pbx)
        for build_id in ['C50000000000000000000002', 'C50000000000000000000004',
                         'C50000000000000000000006', 'C50000000000000000000008']:
            self.assertGreaterEqual(pbx.count(f'"{build_id}"'), 2)

    def test_copy_has_chinese_and_english_parameters(self):
        catalog = self.read('Resources/MyProjectActivityEditor.xcstrings')
        for key in ['"unavailable %lld"', '"revoked %lld"']:
            self.assertIn(key, catalog)
        self.assertIn('"zh-Hans"', catalog)
        self.assertIn('"en"', catalog)
        self.assertGreaterEqual(catalog.count('%lld'), 4)

    def test_swift_behaviour_cases_are_present(self):
        tests = self.read('Tests/AppUnitTests/MyProjectStateNavigationTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+', tests)), 9)
        for token in ['.ownerTopicEditor(let target)', '.detail(.topic(7))', '.activityEditor(let request)',
                      '.detail(.activity(9))', '.detail(.playTemplate(11))', '.unavailable', 'isBrowseOnly',
                      'currentScope: UUID()', 'localSaved', '.viewApplies']:
            self.assertIn(token, tests)

if __name__ == '__main__': unittest.main()
