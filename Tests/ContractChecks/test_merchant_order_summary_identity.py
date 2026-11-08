"""Source guards only; these checks do not execute SwiftUI or a merchant request."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MerchantOrderSummaryIdentityContracts(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / 'App/MerchantOrdersView.swift').read_text()

    def test_row_and_sheet_require_current_valid_snapshot(self):
        guard = self.source.split('private var canPresentSummary: Bool {', 1)[1].split('\n    }', 1)[0]
        for fact in ['reader.isConfigured', 'reader.isSignedIn', 'model.loadedRevision == reader.sessionRevision',
                     '!model.isLoading', 'model.errorKey == nil', 'model.value != nil']:
            self.assertIn(fact, guard)
        self.assertIn('guard canPresentSummary, model.value?.contains(order) == true else { return }', self.source)
        self.assertIn('.disabled(!canPresentSummary)', self.source)
        sheet = self.source.split('.sheet(item: $selection)', 1)[1].split('.task(id:', 1)[0]
        self.assertIn('if canPresentSummary, selected.revision == reader.sessionRevision,', sheet)
        self.assertIn('model.value?.contains(selected.order) == true', sheet)

    def test_refresh_retires_copy_before_access_read(self):
        reload = self.source.split('private func reload(discardOldValue:', 1)[1]
        self.assertLess(reload.index('selection = nil'), reload.index('await model.load'))
        self.assertLess(reload.index('reader.merchantAccess()'), reload.index('reader.merchantOrders('))
        self.assertIn('guard access.allows(.orders)', reload)
        self.assertIn('.onChange(of: reader.sessionRevision) { _, _ in selection = nil; showFilters = false }', self.source)

    def test_summary_does_not_invent_a_detail_or_refund_writer(self):
        self.assertIn('MerchantOrderSummary(order: selected.order)', self.source)
        for unsupported in ['refundId', 'api/', 'OrderLifecycleCoordinator', 'MerchantBusinessMutation']:
            self.assertNotIn(unsupported, self.source)

if __name__ == '__main__':
    unittest.main()
