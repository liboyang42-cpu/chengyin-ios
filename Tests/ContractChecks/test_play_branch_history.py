"""Static branch-history boundaries only. No Swift compiler or Apple-runtime claim."""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()

class PlayBranchHistoryContracts(unittest.TestCase):
    def test_only_optional_route_field_changes_existing_wire_contract(self):
        current = read('Core/PlayContracts.swift')
        start, end = 'public struct PlayRouteState:', 'public struct PlayNodesResult:'
        segment = current.split(start)[1].split(end)[0]
        self.assertIn('public let decisionLog: PlayBranchHistoryLog?', segment)
        self.assertIn('decisionLog = try? c.decode(PlayBranchHistoryLog.self, forKey: .decisionLog)', segment)
    def test_decode_is_bounded_and_does_not_decode_unknown_recursive_fields(self):
        text = read('Core/PlayBranchHistoryLog.swift')
        for required in ['maximumEntries = 200', 'count <= Self.maximumEntries', 'container.superDecoder()', 'container.currentIndex', 'value.utf8.count <= 128', 'text.utf8.count <= 64', '(48...57).contains($0)']:
            self.assertIn(required, text)
        for forbidden in ['PlayWireValue', 'PlayJSONValue', 'outcomeCode', 'reason', 'JSONSerialization']:
            self.assertNotIn(forbidden, text)
    def test_server_order_not_current_node_or_edge_deduplication(self):
        text = read('Core/PlayBranchHistoryPresentation.swift')
        self.assertIn('log.entries.enumerated().map',text)
        self.assertIn('Row(id: log.sourceIndices[index]',text)
        for forbidden in ['currentNodeID', 'recommendedNodeID', 'Set(log.', 'sorted(by:', 'edgeID']:
            self.assertNotIn(forbidden,text)
    def test_only_visible_names_and_no_node_id_navigation(self):
        text=read('Core/PlayBranchHistoryPresentation.swift')
        self.assertIn('snapshot.visibleNodes.compactMap',text)
        self.assertIn('name.utf8.count <= 512',text)
        self.assertNotIn('snapshot.result.nodes',text)
        view=read('App/PlayBranchHistoryView.swift')
        for forbidden in ['NavigationLink', 'nodeID', 'edgeID', 'Link(', 'openURL', 'WebView']:
            self.assertNotIn(forbidden,view)
        self.assertIn('branchHistory.nodeUnknown',view)
    def test_selection_drops_old_read_and_never_caches_rows(self):
        text=read('Core/PlayBranchHistoryPresentation.swift').split('public struct PlayBranchHistoryPresentation:')[0]
        for required in ['public let scope: PlaySessionScope', 'public let sessionID: Int', 'public let version: Int', 'Self(snapshot: snapshot) == self', 'snapshot.result.mode == 1']:
            self.assertIn(required,text)
        self.assertNotIn('let rows:',text)
        summary=read('App/PlayTaskSummaryView.swift')
        for required in ['.sheet(item: $branchHistorySelection)', 'selection.presentation(snapshot: snapshot)', '.onDisappear { branchHistorySelection = nil }', 'if current != branchHistorySelection', 'if value != "ready" && value != "unknown"']:
            self.assertIn(required,summary)
    def test_ui_is_read_only_and_plain_text(self):
        for path in ['App/PlayBranchHistoryView.swift','Core/PlayBranchHistoryPresentation.swift','Core/PlayBranchHistoryLog.swift']:
            text=read(path)
            for forbidden in ['URLSession','HTTPRequest','makeInteractionLifetime','submit(', 'review(', 'requestAuthorization', 'MapKit', 'AVFoundation', 'WKWebView', 'UserDefaults']:
                self.assertNotIn(forbidden,text)
        view=read('App/PlayBranchHistoryView.swift')
        self.assertEqual(view.count('Button('),1)
        self.assertIn('Text(verbatim: name ??',view)
        self.assertIn('.privacySensitive()',view)
    def test_dedicated_localization_table_is_complete_and_bilingual(self):
        catalog=json.loads(read('Resources/PlayBranchHistory.xcstrings'))
        sources=read('App/PlayBranchHistoryView.swift')+read('App/PlayTaskSummaryView.swift')
        used=set(re.findall(r'"(branchHistory\.[A-Za-z]+)"',sources))
        for key in used:
            self.assertIn(key,catalog['strings'])
        for key,value in catalog['strings'].items():
            self.assertEqual(set(value['localizations']),{'en','zh-Hans'})
            for lang in ['en','zh-Hans']:
                self.assertTrue(value['localizations'][lang]['stringUnit']['value'])
        self.assertIn('table: "PlayBranchHistory"',sources)
    def test_maximum_type_content_has_no_fixed_height_or_truncation(self):
        view=read('App/PlayBranchHistoryView.swift')
        self.assertIn('.fixedSize(horizontal: false, vertical: true)',view)
        for forbidden in ['lineLimit(', 'frame(height:', 'minimumScaleFactor', 'truncationMode', 'animation(']:
            self.assertNotIn(forbidden,view)
    def test_fixture_drives_normal_host_and_has_only_read_grant(self):
        text=read('App/PlayBranchHistoryFixtureSupport.swift')
        self.assertTrue(text.startswith('#if DEBUG'))
        for token in ['PlayExperienceView(model: model)', 'PlayRecoveryRecordingTransport()', 'enabled: [.reads]', 'await model.load()', 'model.invalidate()']:
            self.assertIn(token,text)
        self.assertNotIn('URLSession',text)
    def test_generated_project_contains_every_new_apple_source(self):
        project=read('Questify.xcodeproj/project.pbxproj')
        paths=[*ROOT.glob('App/PlayBranchHistory*.swift'),*ROOT.glob('Core/PlayBranchHistory*.swift'),ROOT/'Resources/PlayBranchHistory.xcstrings',ROOT/'Tests/AppUnitTests/PlayBranchHistoryAppTests.swift',ROOT/'Tests/AppUITests/PlayBranchHistoryFlowTests.swift']
        for path in paths: self.assertIn(str(path.relative_to(ROOT)),project)
    def test_full_journey_methods_and_unmeasured_budget_are_declared(self):
        test='\n'.join(read('Tests/AppUITests/'+name+'.swift') for name in ['PlayBranchHistoryFlowTests','PlayBranchHistoryLifetimeFlowTests'])
        methods=re.findall(r'func (test\w+)\(',test)
        self.assertEqual(len(methods),5)
        budget=json.loads(read('docs/branch-history/ui-budget-assumptions.json'))
        self.assertEqual(set(budget['estimated_method_seconds']),{'PlayBranchHistoryFlowTests.'+method for method in methods})
        self.assertEqual(budget['apple_execution'],'NOT_RUN')
    def test_history_adds_no_service_or_mutation_capability(self):
        text=read('Core/PlayBranchHistoryLog.swift')+read('Core/PlayBranchHistoryPresentation.swift')+read('App/PlayBranchHistoryView.swift')
        for forbidden in ['PlayExperienceService', 'PlayExperienceCapability', 'PlayRouteAdvance', 'PlayCompletionEvidence', 'PlayPreparedDispatch', 'URLRequest', 'import MapKit']:
            self.assertNotIn(forbidden,text)

if __name__=='__main__': unittest.main()
