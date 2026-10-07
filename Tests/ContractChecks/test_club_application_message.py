"""Supplementary source contracts; Swift compilation and runtime tests are separate."""
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]

class ClubApplicationMessageContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()
    def test_frozen_message_reaches_dispatch(self):
        c = self.read('Core/ClubActionCoordinator.swift')
        self.assertIn('public let joinMessage: String', c)
        self.assertIn('joinMessage: confirmation.joinMessage', c)
        self.assertIn('joinMessage: joinMessage', self.read('Core/ClubActionWriting.swift'))
    def test_bounds_apply_at_all_boundaries(self):
        self.assertIn('message.utf16.count <= maximumUTF16Count', self.read('Core/ClubActionContracts.swift'))
        for path in ['Core/ClubActionCoordinator.swift', 'Core/ClubActionWriting.swift', 'Core/ClubActionService.swift']:
            self.assertIn('ClubApplicationMessage.isValid(joinMessage, for: action)', self.read(path))
    def test_current_join_and_quit_json_preserve_numeric_id_and_only_application_message(self):
        s = self.read('Core/ClubActionService.swift')
        construction = s.split('            request = ', 1)[1].split(
            '        } catch { throw ClubActionWriteError.notSent(.invalidRequest) }', 1)[0]
        actual = ['request = ' + line if index == 0 else line
                  for index, line in enumerate(construction.splitlines())]
        actual = [line.strip() for line in actual if line.strip() and not line.strip().startswith('//')]
        self.assertEqual(actual, [
            'request = URLRequest(url: configuration.baseURL.appendingPathComponent(action == .leave ? "api/club/quit" : "api/club/join"))',
            'request.httpMethod = "POST"',
            'request.timeoutInterval = 20',
            'request.cachePolicy = .reloadIgnoringLocalCacheData',
            'request.setValue("application/json", forHTTPHeaderField: "Accept")',
            'request.setValue(token, forHTTPHeaderField: "Authorization")',
            'request.setValue("application/json", forHTTPHeaderField: "Content-Type")',
            'var fields: [String: Any] = ["id": clubID]',
            'if action == .apply { fields["joinMessage"] = joinMessage }',
            'request.httpBody = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])',
        ])
        for prohibited in ['makeFormRequest', 'multipart/form-data', 'String(clubID)', 'Double(clubID)',
                           '"clubId"', '"payment"', '"transaction"', '"membershipAccessEnd"']:
            self.assertNotIn(prohibited, construction)
    def test_membership_write_has_one_send_and_no_automatic_retry(self):
        s = self.read('Core/ClubActionService.swift')
        self.assertEqual(s.count('transport.send('), 1)
        self.assertIn('guard !Task.isCancelled else { throw ClubActionWriteError.cancelledBeforeDispatch }', s)
        self.assertIn('do { (data, status) = try await transport.send(request) }', s)
        self.assertIn('catch is CancellationError { throw ClubActionWriteError.outcomeUnknown(.cancelled) }', s)
        self.assertIn('catch { throw ClubActionWriteError.outcomeUnknown(.transport) }', s)
        for retry in ['while ', 'for ', 'Task.sleep', 'URLSession', 'makeFormRequest']:
            self.assertNotIn(retry, s)
    def test_leave_runtime_contract_cases_remain_authored(self):
        s = self.read('Tests/CoreTests/ClubActionServiceTests.swift')
        for required in [
            'func testJoinApplyAndLeaveUseCurrentJSONContract()',
            'func testLeaveJSONContainsOnlyNumericIDWithoutPrecisionLoss()',
            'for id in [1, 9_007_199_254_740_993, Int.max]',
            'XCTAssertEqual(data, Data(expectedBody.utf8))',
            'XCTAssertEqual(Set(json.keys), Set(["id"]))',
            'XCTAssertEqual(json["id"] as? Int, id)',
            'func testLeaveFailuresNeverRetryOrFallBackToMultipart()',
            'XCTAssertEqual(t.requests.count, 1)',
            'func testInvalidLeaveIDNeverDispatches()',
        ]:
            self.assertIn(required, s)
    def test_optional_verbatim_received_message(self):
        self.assertIn('decodeIfPresent(String.self, forKey: .joinMessage)', self.read('Core/ClubManagementContracts.swift'))
        self.assertIn('Text(verbatim: message).accessibilityIdentifier("club.management.joinMessage")', self.read('App/ClubManagementView.swift'))
    def test_review_and_identity_reset(self):
        s = self.read('App/ClubActionPanel.swift')
        self.assertIn('value.joinMessage', s)
        self.assertIn('joinMessage: reviewedMessage', s)
        self.assertIn('joinMessage = ""; revision', s)
        self.assertIn('.onChange(of: identity)', s)
    def test_all_protocol_conformers_accept_message(self):
        for path in ['Core/ClubActionWriting.swift', 'App/ClubActionFixtureSupport.swift', 'Tests/CoreTests/ClubActionCoordinatorTests.swift']:
            self.assertIn('expectedIdentity: ClubReadIdentity, joinMessage: String', self.read(path))
