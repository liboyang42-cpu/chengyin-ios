"""Own-shelf host flow. Source contracts only: not Swift, XCTest, UI, or a device."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

def read(path):
    return (ROOT / path).read_text()


class TemplateOwnShelfHostFlow(unittest.TestCase):
    def setUp(self):
        self.shelf = read('Core/TemplateAuthoringShelf.swift')
        self.plan = read('Core/TemplateOwnShelfMarketPlan.swift')
        self.view = read('App/TemplateAuthoringMineView.swift')
        self.card = read('App/TemplateOwnShelfCardSection.swift')
        start = self.shelf.index('public static func decode(')
        self.decode = self.shelf[start:self.shelf.index('@MainActor public final class TemplateOwnShelfReader')]

    def test_same_my_list_response_keeps_card_fact_fields(self):
        self.assertIn('path: "/api/template/my-list"', self.shelf)
        self.assertEqual(self.shelf.count('"/api/template/'), 1)
        for key in ['rating', 'useNum', 'duration', 'createTime', 'reason']:
            self.assertIn('case rating, useNum, duration, createTime, reason', self.plan)
            self.assertIn(key, self.plan.split('enum Keys')[1].split('public init(from decoder:')[0])
        self.assertIn('TemplateOwnShelfStateEnvelope.self, from: data', self.shelf)
        self.assertIn('TemplateOwnShelfCardFactsEnvelope.self, from: data', self.shelf)
        self.assertLess(self.shelf.index('TemplateOwnShelfStateEnvelope.self, from: data'),
                        self.shelf.index('TemplateOwnShelfCardFactsEnvelope.self, from: data'))
        for forbidden in ['/api/template/market-submit', '/market-submit', 'updateLibraryStatus', 'MERCHANT']:
            self.assertNotIn(forbidden, self.decode)
        self.assertNotIn('MERCHANT', self.shelf)

    def test_personal_library_stays_separate_from_the_undispatchable_plan(self):
        self.assertIn('public var isDispatchable: Bool { false }', self.plan)
        self.assertIn('row.publishStatus == 1 ? "templateAuthor.shelf.removeLibrary" : "templateAuthor.shelf.addLibrary"', self.view)
        self.assertIn('templateAuthor.shelf.inLibrary', self.view)
        self.assertIn('templateAuthor.shelf.outLibrary', self.view)
        self.assertIn('plan.isDispatchable == false', self.card)
        self.assertIn('不是发布', self.card)
        self.assertIn('This is not a publish.', self.card)
        self.assertNotIn('Button', self.card)
        self.assertNotIn('confirmShelf', self.card)
        self.assertNotIn('TemplateAuthoringRequest', self.plan + self.card)

    def test_delete_review_cancel_and_return_refresh_stay_on_the_existing_controls(self):
        self.assertIn('Text(LocalizedStringKey(value.action == .remove ? "templateAuthor.shelf.deleteReview"', self.view)
        self.assertIn('if value.action == .remove { TemplateOwnShelfDeleteReviewCopy(title: value.title) }', self.view)
        self.assertIn('accessibilityIdentifier("templateAuthor.shelf.confirm")', self.view)
        self.assertIn('accessibilityIdentifier("templateAuthor.shelf.cancel")', self.view)
        self.assertIn('guard previous != nil, next == nil else { return }', self.view)
        self.assertIn('Task { await refresh() }', self.view.split('onChange(of: selectedMember)')[1].split('.task(id: sessionRevision)')[0])
        for key in ['templateAuthor.shelf.empty', 'templateAuthor.listUnavailable',
                    'templateAuthor.shelf.moreFailed', 'templateAuthor.shelf.loadMore', 'templateAuthor.signIn']:
            self.assertIn(key, self.shelf + self.view)

    def test_card_facts_share_the_state_lifetime(self):
        leave = self.shelf.split('public func leave()')[1].split('public func refreshSnapshot')[0]
        self.assertIn('rowStates = [:]; cardFacts = [:]', leave)
        refresh = self.shelf.split('public func refresh(keyword: String = "")')[1].split('public func loadMore()')[0]
        self.assertLess(refresh.index('let stateSnapshot = snapshot.isEmpty ? [:] : rowStates'),
                        refresh.index('let factSnapshot = snapshot.isEmpty ? [:] : cardFacts'))
        self.assertLess(refresh.index('let factSnapshot = snapshot.isEmpty ? [:] : cardFacts'),
                        refresh.index('leave()'))
        commit = self.shelf.split('// No suspension between committing rows and their display-only sidecars.')[1].split('page = requested')[0]
        self.assertNotIn('await', commit)
        self.assertLess(commit.index('rowStates = result.rowStates'), commit.index('cardFacts = result.cardFacts'))
        self.assertIn('cardFacts = rows.isEmpty ? [:] : coordinator.shelfReader.cardFacts', self.view)
        self.assertIn('rows = []; cardFacts = [:]; review = nil; rowStates = [:]; await refresh()', self.view)

    def test_authored_cases_name_the_flow_without_claiming_execution(self):
        core = read('Tests/CoreTests/TemplateOwnShelfHostFlowTests.swift')
        for name in ['testSameMyListResponseKeepsRatingUseCountDurationCreatedAndReason',
                     'testMalformedCardColumnsRemainOnTheLegalRow',
                     'testLeaveNewKeywordAndAuthClearCardFactsWithStates',
                     'testPersonalPublishStatusDoesNotDispatchTheMarketplacePlan']:
            self.assertIn('func ' + name + '(', core)
        ui = read('Tests/AppUITests/TemplateOwnShelfFlowTests.swift')
        self.assertIn('func testDeleteReviewShowsSourceDangerCopyAndCancelDoesNotSubmit(', ui)
        self.assertIn('func testOwnedCardShowsZeroDurationAndNoMarketplacePublishButton(', ui)
        self.assertIn('Delete this exact template from your own shelf? This may not be reversible.', ui)


if __name__ == '__main__':
    unittest.main()
