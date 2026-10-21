"""C5 supplementary source checks; Swift decision and UI behaviour require Apple execution."""
from pathlib import Path
import re, unittest
ROOT = Path(__file__).resolve().parents[2]

class MyProjectStateNavigationContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()

    def test_decision_reuses_core_route_and_owner_target_without_restating_state_policy(self):
        source = self.read('App/MyProjectStateNavigation.swift')
        for token in ['MyProjectListPresentation.resolveRoute(', 'ProjectEditRemoteTarget(project: project, readerScope: readerScope)',
                      'case ownerTopicEditor(ProjectEditRemoteTarget)', 'case activityEditorUnavailableDetail(CreatorContentDestination)',
                      'merchantScopeAccess.isBrowseOnly', 'project.destination.map']:
            self.assertIn(token, source)
        # State lists stay in Core resolveRoute; the App decision must not duplicate them.
        for state in ['"draft"', '"rejected"', '"pending"', '"running"']:
            self.assertNotIn(state, source)

    def test_activity_editor_is_a_detail_fallback_not_an_invented_interface(self):
        source = self.read('App/MyProjectStateNavigation.swift')
        self.assertIn('case .activityEditor(let id):', source)
        self.assertIn('return .activityEditorUnavailableDetail(.activity(id))', source)
        self.assertNotIn('ActivityPublishingView', source)
        self.assertNotIn('URLSession', source)

    def test_browser_routes_editor_directly_and_details_otherwise(self):
        host = self.read('App/ProjectOwnedContentViews.swift')
        for token in ['let decision: MyProjectStateNavigationDecision',
                      'navigation.open(project, scope: scope, reader: reader, merchantScopeAccess: merchantScopeAccess)',
                      'case .ownerTopicEditor(let target):',
                      'case .detail(let destination), .activityEditorUnavailableDetail(let destination):',
                      'ProjectRemoteEditorDestination(target: target, reader: reader, revision: revision,',
                      'if !merchantScopeAccess.isBrowseOnly,',
                      'ProjectEditRemoteTarget(project: value.project, readerScope: value.scope)',
                      'navigation.presentation(presented)', 'navigation.retire(scope: original)']:
            self.assertIn(token, host)
        # The direct-editor branch must not wrap the editor inside the detail host.
        editor_branch = host.split('case .ownerTopicEditor(let target):')[1].split('case .detail(')[0]
        self.assertNotIn('detail(destination)', editor_branch)

    def test_close_never_rewrites_the_captured_row(self):
        host = self.read('App/ProjectOwnedContentViews.swift')
        close = host.split('func close(_ original: Selection)')[1].split('func retire')[0]
        self.assertIn('selection = nil', close)
        self.assertNotIn('project', close)
        self.assertIn('never rewrites', host)

    def test_new_swift_files_are_registered_in_the_xcode_project(self):
        pbx = self.read('Questify.xcodeproj/project.pbxproj')
        for path in ['App/MyProjectStateNavigation.swift', 'Tests/AppUnitTests/MyProjectStateNavigationTests.swift']:
            self.assertIn(f'"path" = "{path}";', pbx)
        for build_id in ['C50000000000000000000002', 'C50000000000000000000004']:
            self.assertGreaterEqual(pbx.count(f'"{build_id}"'), 2)

    def test_swift_behaviour_cases_are_present(self):
        tests = self.read('Tests/AppUnitTests/MyProjectStateNavigationTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+', tests)), 5)
        for token in ['.ownerTopicEditor(let target)', '.detail(.topic(7))', '.activityEditorUnavailableDetail(.activity(9))',
                      '.detail(.playTemplate(11))', '.unavailable', 'isBrowseOnly']:
            self.assertIn(token, tests)

if __name__ == '__main__': unittest.main()
