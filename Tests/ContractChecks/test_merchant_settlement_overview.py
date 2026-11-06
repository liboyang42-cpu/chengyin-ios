"""C1 settlement-overview source contracts; no Swift compilation is claimed."""
import json
import re
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
VIEW = 'App/MerchantBusinessViews.swift'
class MerchantSettlementOverviewContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_current_business_entry_keeps_scoped_ledger_navigation(self):
        # Integration changes other business pages; enforce the live route boundary instead of an old whole-file hash.
        source = self.read(VIEW)
        self.assertIn('if route.isCurrent(reader: reader, journal: journal)', source)
        self.assertIn('if query == .overview { MerchantLedgerSettlementOverview(reader: route.reader) }', source)
        self.assertIn('MerchantBusinessPage(reader: route.reader, journal: route.journal, query: query)', source)
        self.assertIn('access.require(query.permissions)', source)

    def test_existing_queries_and_finance_permission_are_reused(self):
        core = self.read('Core/MerchantSettlementOverview.swift')
        query = self.read('Core/MerchantBusinessQuery.swift')
        for token in ['case .overview: return .overview', '.entries(source: "all", page: page)', '.batches(page: page)',
                      '"merchant:finance:read"', 'snapshot.access.allows(id.permission)']:
            self.assertIn(token, core)
        for token in ['api/merchant/finance/overview', 'api/merchant/finance/settlement-entries',
                      'api/merchant/finance/public-transfer-batches', 'api/merchant/finance/public-transfer-batch-detail']:
            self.assertIn(token, query)

    def test_sections_are_independent_and_never_locally_totalled(self):
        core = self.read('Core/MerchantSettlementOverview.swift')
        app = self.read('App/MerchantSettlementOverviewView.swift')
        for token in ['public mutating func begin', 'public mutating func succeed', 'public mutating func fail',
                      'guard !section(id).isLoading', 'merchantID == nil || merchantID == snapshot.access.merchantID']:
            self.assertIn(token, core)
        for token in ['MerchantSettlementOverviewSection.allCases' ]:
            self.assertNotIn(token, app)  # sections render explicitly, not as one shared load
        for forbidden in ['reduce(0', 'rows.map', 'Date()', 'Currency', 'execute(', 'URLSession', 'UserDefaults']:
            self.assertNotIn(forbidden, core + app)
        self.assertIn('async let overview', app)
        self.assertIn('model.retry(section)', app)
        self.assertIn('model.move(section, by:', app)

    def test_context_change_and_disappear_invalidate_generations(self):
        core = self.read('Core/MerchantSettlementOverview.swift')
        app = self.read('App/MerchantSettlementOverviewView.swift')
        self.assertIn('overview.clear(); entries.clear(); batches.clear()', core)
        self.assertIn('section(id).generation == generation', core)
        self.assertEqual(app.count('guard isLive, !Task.isCancelled, context == expected else { return }'), 2)
        detail = self.read('App/MerchantLedgerParityViews.swift')
        self.assertEqual(detail.count('reader.scope == scope, reader.authorizationGeneration == authorization'), 2)
        for token in ['func disappear()', 'state.invalidateAll()', '.onChange(of: reader.scope)',
                      '.onChange(of: reader.authorizationGeneration)', 'model.refreshBatchesAfterReturn()']:
            self.assertIn(token, app)

    def test_batch_detail_mounts_statement_card_and_progress(self):
        views = self.read('App/MerchantLedgerParityViews.swift')
        self.assertIn('struct MerchantSettlementStatementCard: View', views)
        self.assertIn('MerchantSettlementStatementCard(statement: statement)', views)
        self.assertIn('reader.snapshot(.batch(id))', views)
        self.assertIn('settlementReader: reader', views)
        self.assertIn('MerchantSettlementStatement(document: document)', views)
        overview = self.read('App/MerchantSettlementOverviewView.swift')
        self.assertIn('MerchantSettlementBatchDetailView(reader: reader, batchID: id)', overview)

    def test_statement_never_claims_complete_details_or_sums_lines(self):
        core = self.read('Core/MerchantSettlementOverview.swift')
        self.assertIn('public var hasCompleteDetailContract: Bool { false }', core)
        self.assertIn('returnedEarningsCount', core)
        self.assertIn('returnedAdjustmentsCount', core)
        self.assertIn('serverTotalDisplay', core)
        self.assertNotIn('signedAmount', core)
        views = self.read('App/MerchantLedgerParityViews.swift')
        self.assertIn('merchant.settlementOverview.detailIncomplete', views)

    def test_no_write_payment_or_permission_mutation_surface(self):
        combined = self.read('Core/MerchantSettlementOverview.swift') + self.read('App/MerchantSettlementOverviewView.swift') + self.read('App/MerchantLedgerParityViews.swift')
        for forbidden in ['.execute(', 'reserve(', 'confirm(', 'MerchantBusinessMutation', 'refundOpinion',
                          'withdraw', 'URLSession', 'print(']:
            self.assertNotIn(forbidden, combined)

    def test_localization_keys_are_bilingual_in_dedicated_catalog(self):
        catalog = json.loads(self.read('Resources/MerchantSettlementOverview.xcstrings'))
        app = self.read('App/MerchantSettlementOverviewView.swift') + self.read('App/MerchantLedgerParityViews.swift')
        app = re.sub(r'\.accessibilityIdentifier\("[^"]*"\)', '', app)
        keys = set(re.findall(r'"(merchant\.settlementOverview\.[A-Za-z.]+)', app))
        self.assertTrue(keys)
        for key in keys:
            if key.endswith('.'):
                continue
            self.assertIn(key, catalog['strings'])
            self.assertEqual(set(catalog['strings'][key]['localizations']), {'en', 'zh-Hans'})

    def test_authored_swift_tests_cover_required_races(self):
        core = self.read('Tests/CoreTests/MerchantSettlementOverviewTests.swift')
        app = self.read('Tests/AppUnitTests/MerchantSettlementOverviewTests.swift')
        for method in ['testSectionsSucceedAndFailIndependentlyWithoutBecomingZero',
                       'testDuplicateBeginWhileLoadingIsRejectedAndInvalidateRejectsOldCompletion',
                       'testContextChangeClearsAllFinanceSectionsAndMerchant',
                       'testWrongQueryOrOtherMerchantCompletionIsRejected',
                       'testStatementUsesOnlyReturnedCountsAndServerTotal']:
            self.assertIn('func ' + method, core)
        for method in ['testOneFailedSectionKeepsOtherSectionsLoaded', 'testRetryReadsOnlyTheFailedSection',
                       'testEntriesPaginationDoesNotMoveBatches', 'testScopeChangeDuringReadCannotFillAndDisappearClears',
                       'testReturnFromBatchDetailRefreshesOnlyBatches',
                       'testScopeOrAuthorizationChangeDropsLateSuccessAndFailureBeforeObserver']:
            self.assertIn('func ' + method, app)


if __name__ == '__main__':
    unittest.main()
