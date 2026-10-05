from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class ClubFeedAccessibilityLeaf(unittest.TestCase):
    def test_post_anchor_does_not_override_time_source_or_gallery_controls(self):
        s=(ROOT/'App/ClubGovernanceFeedPostView.swift').read_text()
        self.assertEqual(s.count('.accessibilityIdentifier("club.feed.post.\\(post.id)")'),1)
        self.assertNotIn('.fixedSize(horizontal: false, vertical: true)\n        .accessibilityIdentifier',s)
        for token in ['.accessibilityIdentifier("club.feed.time.\\(post.id)")', '.accessibilityIdentifier("club.feed.source.\\(post.id)")', '.id(mediaScope)', 'Button(action: openClub)']:
            self.assertIn(token,s)
    def test_chrome_uses_exact_unique_native_targets_and_full_frame(self):
        s=(ROOT/'Tests/AppUITests/ClubFeedReadFlowTests.swift').read_text()
        part=s.split('private func tapChrome',1)[1].split('private func absent',1)[0]
        for token in ['app.navigationBars.buttons.matching(identifier: id)', 'query.count == 1', 'button.isEnabled', 'button.isHittable',
                      'app.frame.contains(frame)', '$0.frame.contains(frame)', 'frame.minY >= counter.frame.maxY', 'frame.maxY <= firstBar.frame.minY']:
            self.assertIn(token,part)
        self.assertNotIn('revealFixtureElement',part)
        self.assertNotIn('swipe',part)
    def test_source_identity_privacy_default_off_and_account_clear_assertions_remain(self):
        s=(ROOT/'Tests/AppUITests/ClubFeedReadFlowTests.swift').read_text()
        for token in ['Actual source club 81','Actual source club 82','PRIVATE-CONTACT-MUST-NOT-APPEAR','"3 / 3"',
                      'XCTAssertEqual(app.staticTexts["club.feed.fixture.imageReads"].label, "0")',
                      'absent("club.detail.name", app: app)', 'XCTAssertFalse(app.staticTexts["Fixture feed author"].exists)',
                      'XCTAssertFalse(app.buttons["club.feed.source.191"].exists)']:
            self.assertIn(token,s)
