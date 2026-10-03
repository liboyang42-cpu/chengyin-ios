"""Diagnostic test contract; lost-navigation cause and Apple behavior remain unproven."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class ClubNavigationAcknowledgementChecks(unittest.TestCase):
    def test_root_then_single_tap_then_destination_acknowledgement(self):
        s = (ROOT/'Tests/AppUITests/ClubGovernanceFlowTests.swift').read_text()
        helper = s.split('private func open(', 1)[1].split('private func fact(', 1)[0]
        self.assertLess(helper.index('root.waitForExistence(timeout: 5)'), helper.index('revealFixtureElement'))
        self.assertLess(helper.index('button.tap()'), helper.index('destination.waitForExistence(timeout: 5)'))
        self.assertEqual(helper.count('button.tap()'), 1)
        self.assertNotIn('for ', helper)
        self.assertEqual(helper.count('XCTFail(app.debugDescription); return false'), 3)
        self.assertEqual(s.count('guard open('), 6)
        self.assertIn('continueAfterFailure = false', s)
        self.assertIn('attachFailureScreenshot(self, app: runningApp)', s)

    def test_fixture_markers_do_not_replace_navigation_or_store_ownership(self):
        s = (ROOT/'App/ClubGovernanceFixtureHost.swift').read_text()
        self.assertTrue(s.startswith('#if DEBUG'))
        self.assertIn('@StateObject private var store = ClubGovernanceFixtureStore()', s)
        self.assertIn('NavigationLink {\n                        ClubGovernanceReadView(operation: operation', s)
        self.assertIn('.accessibilityIdentifier("club.gov.fixture.destination." + operation.rawValue)', s)
        self.assertIn('.accessibilityIdentifier("club.gov.fixture.root")', s)

    def test_story_protected_answer_assertions_remain(self):
        s = (ROOT/'Tests/AppUITests/ClubGovernanceFlowTests.swift').read_text()
        case = s.split('func testClubStoryUsesOwnRouteAndProtectedAnswer()', 1)[1].split('\n    func ', 1)[0]
        for token in ['guard open("topicOverview", app: app) else { return }', 'app.buttons["club.gov.openStory"]',
                      'story.tap()', 'containing: "Fixture chapter"', 'containing: "Fixture puzzle"',
                      'chapter.waitForExistence(timeout: 5)', 'puzzle.waitForExistence(timeout: 5)']:
            self.assertIn(token, case)
        self.assertNotIn('XCTSkip', case)
