from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class ActivityTopicAccessibleSummaries(unittest.TestCase):
    def test_reviews_assert_exact_full_ax_labels_not_bare_numbers(self):
        activity=(ROOT/'Tests/AppUITests/ActivityFlowTests.swift').read_text()
        topic=(ROOT/'Tests/AppUITests/TopicFlowTests.swift').read_text()
        for label in ['Total reviews, 12','Average rating, 4.2 / 5']:
            self.assertIn('label, "'+label+'"',activity)
            self.assertIn('label, "'+label+'"',topic)
        self.assertIn('label, "Total reviews, 0"',activity)
        self.assertIn('label, "Total reviews, 3"',topic)
        self.assertIn('label, "评价总数、0"',topic)
    def test_people_total_uses_unique_full_row_and_preserves_owner_change_checks(self):
        source=(ROOT/'App/ActivityPeopleSection.swift').read_text()
        self.assertIn('.accessibilityIdentifier("activity.people.total")',source)
        ui=(ROOT/'Tests/AppUITests/ActivityFlowTests.swift').read_text()
        for text in ['app.staticTexts.matching(identifier: "activity.people.total")','XCTAssertEqual(total.count, 1','"Total registered, 12"',
                     'XCTAssertFalse(app.buttons["activity.people.participant.1"].exists)',
                     'XCTAssertFalse(app.buttons["activity.people.participant.2"].exists)',
                     'tap(app.buttons["activity.people.switchAccount"])',
                     'XCTAssertFalse(app.staticTexts["Fixture host profile"].exists)',
                     'XCTAssertFalse(element("activity.detail.content").exists)']:
            self.assertIn(text,ui)
    def test_read_only_unknown_empty_and_route_replacement_assertions_remain(self):
        activity=(ROOT/'Tests/AppUITests/ActivityFlowTests.swift').read_text()
        topic=(ROOT/'Tests/AppUITests/TopicFlowTests.swift').read_text()
        for text in ['XCTAssertFalse(app.buttons["activity.openRegistration"].exists)',
                     'XCTAssertFalse(app.buttons["payment.pay"].exists)',
                     'XCTAssertFalse(element("activity.reviews.average").exists)',
                     'XCTAssertFalse(element("activity.reviews.text.0").exists)']:
            self.assertIn(text,activity)
        self.assertIn('XCTAssertFalse(app.staticTexts["A useful route review."].exists)',topic)
        self.assertIn('XCTAssertFalse(app.staticTexts["topic.reviews.average"].exists)',topic)
