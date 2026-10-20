"""Package 05: Account -> 我的订单 -> detail -> read-only lifecycle preview. Source-level checks only."""
from pathlib import Path
import unittest
R = Path(__file__).resolve().parents[2]
class Pkg05LifecyclePreview(unittest.TestCase):
    def read(self, p): return (R / p).read_text()
    def host(self): return self.read('App/OwnedOrderComposition.swift')
    def test_account_orders_inject_fenced_read_only_coordinator_with_top_level_buyer_member_id_check(self):
        s = self.host()
        self.assertIn('struct OwnedOrdersLifecycleHost', s)
        self.assertIn('OrderLifecycleCoordinator(\n            reader: OwnedOrderLifecycleReader(origin: session.ownedOrderReader, base: session.orderLifecycleReader))', s)
        self.assertIn('lifecycleCoordinator: coordinator', s)
        self.assertIn('final class OwnedOrderLifecycleReader: OrderLifecycleReading', s)
        self.assertIn('var isOfflineExample: Bool { false }', s)
        self.assertIn('origin.identity == originIdentity', s)
        self.assertIn('guard let expectedAccountID = originIdentity?.accountID, current, id > 0 else { throw APIError.notConfigured }', s)
        self.assertIn('guard value.id == id, value.memberID == expectedAccountID else { throw APIError.malformedResponse }', s)

        contracts = self.read('Core/OrderLifecycleContracts.swift')
        self.assertIn('public let memberID: Int?', contracts)
        self.assertIn('memberID = try c.decodeIfPresent(Int.self, forKey: .memberId)', contracts)

        service = self.read('Core/OrderLifecycleService.swift')
        self.assertIn('public func detail(id: Int, token: String, expectedAccountID: Int? = nil) async throws -> OrderLifecycleDetail', service)
        self.assertIn('if let expectedAccountID, value.memberID != expectedAccountID { throw APIError.malformedResponse }', service)

        core_tests = self.read('Tests/CoreTests/OrderLifecycleServiceTests.swift')
        self.assertIn('func testExpectedAccountIDRejectsMissingOrMismatchedTopLevelBuyerMemberIdEvenWhenNestedOwnerMatches(', core_tests)
        app_tests = self.read('Tests/AppUnitTests/OwnedOrderCompositionTests.swift')
        self.assertIn('func testOwnedOrderLifecycleReaderEnforcesTopLevelBuyerMemberIdGrantAccountAndKeepsWritesClosed(', app_tests)

    def test_no_dispatch_path_is_opened(self):
        s = self.host()
        for forbidden in ['production:', 'fixtureSimulator', 'OrderLifecycleProductionFactory', 'OrderLifecycleProductionDispatcher',
                          'orderLifecycleCoordinator', 'makeOrderLifecycleDispatcher', 'URLSession', 'transport.send', 'api/']:
            self.assertNotIn(forbidden, s)
    def test_no_shared_integration_file_or_gate_changed(self):
        sess = self.read('App/AppSession.swift')
        self.assertIn('production: { [weak self] in self?.makeOrderLifecycleDispatcher() })', sess)
        self.assertIn('guard let configuration = runtimeDependencies.orderLifecycleConfiguration,', sess)
        self.assertIn('Default nil configuration cannot construct a writer.', sess)
        self.assertIn('let orderLifecycleConfiguration: OrderLifecycleProductionConfiguration?', self.read('App/NativeRuntimeDependencies.swift'))
if __name__ == '__main__': unittest.main()
