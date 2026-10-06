"""Source/structure checks only; Swift, fake-transport XCTest and device runtime are NOT_RUN."""
import json, pathlib, re, unittest
from flutter_source import read_flutter_source
ROOT = pathlib.Path(__file__).resolve().parents[2]
class OperationHTTPAdapters(unittest.TestCase):
    def text(self, path): return (ROOT/path).read_text()
    def test_project_exact_routes_and_source_reply_shapes(self):
        adapter=self.text('Core/ProjectEditHTTPService.swift')
        for guard in ['operation.payload["scope"] == .string(owner.rawValue)', 'fresh.snapshot == baseline', 'fresh.capability.allowsCreate', 'positiveID(envelope?["data"])']: self.assertIn(guard,adapter)
    def test_project_routes_external_flutter_parity(self):
        adapter=self.text('Core/ProjectEditHTTPService.swift')
        source=read_flutter_source(self, 'data/api/publish_api.dart')+read_flutter_source(self, 'data/api/my_project_api.dart')
        for route in set(re.findall(r'"(api/[a-z/-]+)"',adapter)): self.assertIn("'/"+route+"'",source)
    def test_all_default_app_composition_remains_off(self):
        app=self.text('App/AppSession.swift')
        self.assertIn('else { service = ProjectEditDisabledService() }',app)
        self.assertIn('private let teamService = TeamReadOnlyService()',app)
        self.assertIn('readApproval: OperationEndpointApproval? = nil',app)
        self.assertNotIn('TeamHTTPService(',app); self.assertNotIn('approval: OperationEndpointApproval(',app)
    def test_owned_registration_bridge_is_not_activity_id_guess(self):
        app=self.text('App/AppSession.swift')
        for guard in ['creationSource.registrationID', 'detail.teamCreationSource', 'self.currentTeamSession == session', 'path: "api/registration/info"']: self.assertIn(guard,app)
        self.assertNotIn('registrationID: ownerID',app)
    def test_no_guessed_receipt_or_join_mode_paths(self):
        adapters=''.join(self.text('Core/'+p) for p in ['ProjectEditHTTPService.swift','TeamHTTPService.swift','ClubOperationsService.swift','MerchantOperationsService.swift'])
        for path in ['api/team/join-mode','api/operation/receipt','api/topic/receipt','api/team/receipt','api/club/receipt','api/merchant/receipt']: self.assertNotIn(path,adapters)
        self.assertNotIn('Idempotency-Key',adapters)
    def test_minimal_shared_journal_and_exact_scope(self):
        safety=self.text('Core/OperationAdapterSafety.swift')
        record=safety.split('public struct OperationPendingRecord')[1].split('@MainActor')[0]
        for secret in ['token:', 'payload:', 'inviteCode:', 'name:', 'draft:']: self.assertNotIn(secret,record)
        for guard in ['baseURL == configuration.baseURL','self.namespace == namespace','self.accountID == accountID','paths.contains(path)','record.ownerKey == ownerKey','record.targetKey == targetKey']: self.assertIn(guard,safety)
    def test_story_is_sequential_and_partial_stays_locked(self):
        service=self.text('Core/MerchantOperationsService.swift')
        self.assertIn('for (index, request) in requests.enumerated()',service)
        self.assertIn('record.acknowledgedSteps += 1',service)
        self.assertIn('partial(acknowledgedSteps: record.acknowledgedSteps)',service)
        self.assertNotIn('async let',service.split('public func save(')[1])
        self.assertIn('reader.hasPending(destination)',self.text('Core/MerchantOperationsReading.swift'))
    def test_fake_only_regressions_and_no_network_client(self):
        tests=self.text('Tests/CoreTests/OperationHTTPAdapterTests.swift')
        self.assertGreaterEqual(len(re.findall(r'func test\w+',tests)),24)
        self.assertIn('OperationFakeTransport: HTTPTransport',tests)
        for forbidden in ['URLSession(', 'URLSession.shared','Task.sleep']: self.assertNotIn(forbidden,tests)
    def test_project_v2_adapter_xctests_assert_complete_acknowledgments(self):
        tests = self.text('Tests/CoreTests/OperationHTTPAdapterTests.swift')
        cases = [
            ('testProjectCreateExactJSONAndDurableDispatchMarker', '711', 'XCTAssertEqual(acknowledgment.auditTaskID, 91)', 'PENDING', '[41]'),
            ('testProjectMerchantDetailMultipartAndUpdateAcknowledgment', '71', 'XCTAssertNil(acknowledgment.auditTaskID)', 'NOT_REQUIRED', '[]'),
        ]
        for name, topic, audit, state, ids in cases:
            method = tests.split('func ' + name + '()', 1)[1].split('\n    func ', 1)[0]
            self.assertIn('guard case .bundleAcknowledged(let operationID, let acknowledgment) = result else { return XCTFail(', method)
            for assertion in ['XCTAssertEqual(operationID, op.operationID)',
                              'XCTAssertEqual(acknowledgment.topicID, ' + topic + ')', audit,
                              'XCTAssertEqual(acknowledgment.reviewState, "' + state + '")',
                              'XCTAssertTrue(acknowledgment.published)',
                              'XCTAssertEqual(acknowledgment.bundledTemplateIDs, ' + ids + ')']:
                self.assertIn(assertion, method)
            self.assertNotIn('XCTAssertEqual(result, .acknowledged(', method)
    def test_project_legacy_scalar_acknowledgment_has_separate_xctest(self):
        tests = self.text('Tests/CoreTests/OperationHTTPAdapterTests.swift')
        method = tests.split('func testProjectLegacyCreateAndUpdateKeepScalarAcknowledgment()', 1)[1].split('\n    func ', 1)[0]
        for token in ['ProjectEditSyntheticFixtures.draft(product: .freeExplore)',
                      '"api/topic/create"', '"api/topic/update"',
                      'XCTAssertEqual(created, .acknowledged(operationID: create.operationID, topicID: 711))',
                      'XCTAssertEqual(updated, .acknowledged(operationID: update.operationID, topicID: 71))']:
            self.assertIn(token, method)
        self.assertEqual(method.count('ProjectEditHTTPService.decodeAcknowledgment('), 2)
if __name__=='__main__': unittest.main()
