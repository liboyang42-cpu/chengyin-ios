from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class CoopRelationFixtureNavigationScope(unittest.TestCase):
    def test_destination_dependency_wraps_entire_navigation_stack(self):
        source=(ROOT/'App/CoopRelationDiscoveryFixture.swift').read_text()
        stack=source[source.index('            NavigationStack {'):]
        end=stack.index('            }')
        self.assertIn('CooperationFlowWorkbench(reader: reader)',stack[:end])
        self.assertNotIn('.environment(',stack[:end])
        self.assertIn('.environment(\\.cooperationRelationDiscovery, { flow in',stack[end:])
        self.assertIn('CoopRelationDiscoveryView(reader: flow, profiles: profiles',stack[end:])
        self.assertIn('topicID: 3, topicName: "Synthetic topic context", chapterID: 5',stack[end:])
    def test_synthetic_readers_and_namespace_restrictions_unchanged(self):
        source=(ROOT/'App/CoopRelationDiscoveryFixture.swift').read_text()
        self.assertTrue(source.startswith('#if DEBUG'))
        for text in ['target == .ownerMemberID(PublicMerchantOwnerID(41)!)','guard id == 9','current() && selectionCurrent()', 'reader.session = nil; reader.scope = UUID()']:
            self.assertIn(text,source)
        self.assertNotIn('URLSession',source)
        self.assertNotIn('Approval(',source)
    def test_navigation_negative_assertions_are_retained(self):
        ui=(ROOT/'Tests/AppUITests/CoopRelationDiscoveryFlowTests.swift').read_text()
        for text in ['Public owner 41','Public club 9','"1:0"','"0:0"',
                     'XCTAssertFalse(app.buttons["club.openManagement"].exists)',
                     'XCTAssertFalse(app.buttons["cooprelation.open.merchants.1"].exists)',
                     'XCTAssertFalse(app.buttons["coopflow.invite.reply"].exists)',
                     'XCTAssertFalse(app.staticTexts["Public owner 41"].exists)',
                     'XCTAssertFalse(app.buttons["context.coop.new"].exists)',
                     'context.label, "主题信息、Synthetic topic context"']:
            self.assertIn(text,ui)
