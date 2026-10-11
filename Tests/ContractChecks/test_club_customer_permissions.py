"""Customer CRM preflight source checks. Neither Swift nor server Java is executed."""
import hashlib
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def assert_directory_boundary(case, core, contracts):
    body = core.split('func allowsCustomerDirectory(scope:', 1)[1]
    for token in ['guard active, clubID == scope.clubID, (scope.clubID ?? 0) > 0', 'try scope.validate()',
                  'roleCodes.contains("CLUB_OWNER")', 'roleCodes.contains("CLUB_LEGACY_ADMIN")',
                  'permissions.contains("club:member:manage")']:
        case.assertIn(token, body)
    for token in ['eventAccesses', 'club:member:list:read', 'club:event:checkin', 'CLUB_OPERATOR',
                  'CLUB_CO_OWNER', 'isOwner', 'viewerIsAdmin', 'allows(']:
        case.assertNotIn(token, body)
    selector = 'if permission == "CUSTOMER_DIRECTORY" { return allowsCustomerDirectory(scope: scope) }'
    case.assertIn(selector, contracts)
    case.assertLess(contracts.index(selector), contracts.index('if permissions.contains(permission)'))
    case.assertIn('case .customers, .customer, .customerCount: return "CUSTOMER_DIRECTORY"', contracts)


class ClubCustomerPermissionContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()





    def test_directory_selector_is_club_scoped_and_precedes_generic_fallback(self):
        assert_directory_boundary(self, self.read('Core/ClubCustomerHistoryTopicRoute.swift'), self.read('Core/ClubGovernanceContracts.swift'))

    def test_mutation_restoring_list_permission_is_detected(self):
        core = self.read('Core/ClubCustomerHistoryTopicRoute.swift')
        contracts = self.read('Core/ClubGovernanceContracts.swift').replace('case .customers, .customer, .customerCount: return "CUSTOMER_DIRECTORY"',
            'case .customers, .customer, .customerCount: return "club:member:list:read"')
        with self.assertRaises(AssertionError): assert_directory_boundary(self, core, contracts)

    def test_mutation_promoting_event_permission_is_detected(self):
        core = self.read('Core/ClubCustomerHistoryTopicRoute.swift')
        core = core.replace('permissions.contains("club:member:manage")', 'permissions.contains("club:member:manage") || !eventAccesses.isEmpty')
        with self.assertRaises(AssertionError): assert_directory_boundary(self, core, self.read('Core/ClubGovernanceContracts.swift'))

    def test_service_workspace_and_history_share_the_same_selector(self):
        service = self.read('Core/ClubGovernanceService.swift')
        self.assertIn('var permitted = access.allows(operation.permission, scope: scope)', service)
        self.assertLess(service.index('guard permitted else'), service.index('var value = try await post(operation'))
        view = self.read('App/ClubGovernanceViews.swift')
        self.assertIn('snapshot.permissions?.allows(read.permission, scope: scope) == true', view)
        self.assertIn('snapshot.permissions?.allows(ClubGovernanceRead.customer.permission, scope: context.scope) == true',
            self.read('Core/ClubCustomerHistoryTopicRoute.swift'))
        self.assertIn('self.viewerRevision() == viewerRevision, authorizationGeneration == authorization', service)

    def test_receipt_enrollment_and_mutation_boundaries_remain_separate(self):
        contracts = self.read('Core/ClubGovernanceContracts.swift')
        self.assertIn('case .checkin, .topicCustomers, .registrations: return "club:member:list:read"', contracts)
        self.assertIn('case .roster: return "club:event:checkin"', contracts)
        self.assertNotIn('CHECKIN_RECEIPT', contracts)
        self.assertNotIn('TOPIC_CUSTOMERS', contracts)
        from tools.club_customer_directory_admission import restore_product_source
        for path in ['Core/ClubGovernanceContracts.swift', 'Core/ClubCustomerHistoryTopicRoute.swift']:
            self.assertIsInstance(restore_product_source(path, (ROOT / path).read_bytes()), bytes)

    def test_native_allow_deny_transport_and_cancellation_matrix_is_authored(self):
        tests = self.read('Tests/CoreTests/ClubCustomerPermissionTests.swift')
        for name in ['testExactGovernorMatrixForAllCustomerDirectoryReads', 'testInvalidScopeAndLegacyFlagsCannotAuthorizeDirectory',
                     'testDeniedPreflightOnlyRequestsAccessForEachDirectoryEndpoint',
                     'testAllowedDirectoryReadsKeepExactPayloadAndServerRedaction',
                     'testServerDenialRemainsFinalForEveryAllowedDirectoryEndpoint',
                     'testBothReadStagesRetainCancellationChecks', 'testReceiptEnrollmentAndContactVisibilityRemainIndependent']:
            self.assertIn('func ' + name + '(', tests)
        self.assertIn('private let operations: [ClubGovernanceRead] = [.customers, .customer, .customerCount]', tests)
        self.assertIn('for retireAfter in [1, 2]', tests)
        self.assertIn('XCTAssertEqual(wire.requests.map { $0.url!.path }, ["/api/club/access/me"])', tests)

    def test_existing_production_fixture_changes_only_allow_evidence(self):
        from tools.club_customer_directory_admission import restore_product_source
        path = 'Tests/CoreTests/ClubGovernanceProductionTests.swift'
        restored = restore_product_source(path, (ROOT / path).read_bytes())
        self.assertEqual(hashlib.sha256(restored).hexdigest(), '7ec52b15675c3a14de89bd27b32b28b9079d28fc6da784337e2a1f16fc82aa5f')






if __name__ == '__main__':
    unittest.main()
