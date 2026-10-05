"""Native static transport contracts; not Swift execution or live-service evidence."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ClubReadTransportChecks(unittest.TestCase):
    def setUp(self):
        self.service = (ROOT / "Core/ClubService.swift").read_text()
        self.reader = (ROOT / "Core/ClubReading.swift").read_text()
        self.tests = (ROOT / "Tests/CoreTests/ClubServiceTests.swift").read_text()

    def test_only_existing_read_routes_remain(self):
        self.assertEqual(set(re.findall(r'post\("(api/club/[^\"]+)"', self.service)),
                         {"api/club/home", "api/club/my", "api/club/list", "api/club/detail", "api/club/members"})
        self.assertNotIn("URLSession(", self.service)

    def test_all_read_bodies_use_json_and_shared_auth_builder(self):
        self.assertIn('fields: [:], token: token, includesBody: false)', self.service)
        self.assertIn('request.setValue("application/json", forHTTPHeaderField: "Content-Type")', self.service)
        self.assertIn('JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])', self.service)
        self.assertNotIn('form:', self.service)
        self.assertNotIn('multipart/form-data', self.service)
        self.assertEqual(self.service.count('transport.send(request)'), 1)

    def test_identifiers_are_numeric_and_endpoint_scoped(self):
        self.assertIn('post("api/club/detail", json: ["id": id], token: token)', self.service)
        self.assertIn('post("api/club/members", json: ["clubId": club.id], token: token)', self.service)
        self.assertIn('post("api/club/list", json: ["name": name], token: token)', self.service)
        self.assertIn('post("api/club/list", json: [:], token: token)', self.service)
        self.assertNotIn('String(id)', self.service)
        self.assertNotIn('String(club.id)', self.service)

    def test_response_shapes_and_membership_gate_are_preserved(self):
        for value in ['guard club.canSeeMembers else { throw ClubReadFailure.membershipRequired }',
                      'guard AuthRequestBuilder.isValidToken(token)',
                      'guard club.id == id else { throw APIError.malformedResponse }',
                      'decode(ClubValueEnvelope<ClubRecord>.self, data).data',
                      'decode(ClubValueEnvelope<[ClubMember]>.self, data).data']:
            self.assertIn(value, self.service)
        self.assertNotIn('viewerIsAdmin', self.service)

    def test_auth_decisions_still_precede_payload_decoding(self):
        send = self.service.index('transport.send(request)')
        http401 = self.service.index('if status == 401')
        status = self.service.index('let envelope = try decode(ClubStatusEnvelope.self, data)')
        envelope401 = self.service.index('if envelope.code == 401')
        self.assertLess(send, http401)
        self.assertLess(http401, status)
        self.assertLess(status, envelope401)
        self.assertIn('if status == 403', self.service)
        self.assertIn('if envelope.code == 403', self.service)

    def test_private_rows_keep_fresh_detail_and_same_session_fences(self):
        for value in ['let club = try await service.detail(id: id, token: token)',
                      'guard self.currentSession() == session else { throw CancellationError() }',
                      'let members = try await service.members(in: club, token: token)',
                      'guard currentSession() == snapshot else { throw CancellationError() }',
                      'guard !Task.isCancelled, currentSession() == snapshot else { throw CancellationError() }',
                      'onUnauthorized(snapshot)']:
            self.assertIn(value, self.reader)
        self.assertIn('try Task.checkCancellation()', self.reader)

    def test_authored_swift_tests_cover_exact_json_and_fail_closed_responses(self):
        for value in ['testDetailUsesNumericIdJSONAndMembersUsesNumericClubIdJSON',
                      'testDirectoryUsesEmptyJSONAndBareArray', 'testBlankSearchReturnsSourceUnfilteredJSON',
                      'testJSONIdentifiersRetainIntegerPrecisionBeyondDoubleRange',
                      'testOwnerCanRequestMembersWithoutClaimingJoinedOrSendingViewerFacts',
                      'testMalformedMemberArrayCannotBecomeEmptyOrRetryAnotherEncoding',
                      'testDetailAndMembersPreserveServerDenialWithoutRetryOrFallback',
                      'testMemberCancellationIsNotConvertedToEmptyOrRetried']:
            self.assertIn(value, self.tests)


if __name__ == "__main__":
    unittest.main()
