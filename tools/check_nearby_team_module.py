#!/usr/bin/env python3
"""Supplementary source/fixture checks only. Swift/XCTest/SwiftUI runtime NOT_RUN."""
import json
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[1]
CORE = '\n'.join(p.read_text() for p in (ROOT/'Core').glob('NearbyTeam*.swift'))
UI = '\n'.join(p.read_text() for p in (ROOT/'App').glob('NearbyTeam*.swift'))
LOCAL = json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings']
class NearbySourceChecks(unittest.TestCase):
    def test_bilingual(self):
        for key, value in LOCAL.items():
            for language in ['en','zh-Hans']:
                self.assertTrue(value['localizations'][language]['stringUnit']['value'],(key,language))
    def test_literal_localizations_resolve(self):
        for key in set(re.findall(r'"(nearby\.[A-Za-z]+(?:\.[A-Za-z]+)*)"', UI)):
            if key in ['nearby.section','nearby.serverMessage','nearby.message','nearby.fixture.destination','nearby.confirm'] or key.startswith('nearby.fixture.'):
                continue
            self.assertIn(key,LOCAL)
    def test_no_location_access_or_network_executor(self):
        for forbidden in ['CLLocationManager','requestWhenInUseAuthorization','requestAlwaysAuthorization','URLSession.shared','startUpdatingLocation']:
            self.assertNotIn(forbidden, CORE + UI)
    def test_no_join_mode_or_retired_routes(self):
        for forbidden in ['/api/team/join-mode','setJoinMode','/api/hangout','/api/team/create','/api/team/join','/api/team/kick','/api/team/disband','/api/team/quit']:
            self.assertNotIn(forbidden,CORE)
    def test_writes_require_scoped_adapter_and_review(self):
        service = (ROOT/'Core/NearbyTeamService.swift').read_text()
        adapter = (ROOT/'Core/NearbyTeamHTTPWriteAdapter.swift').read_text()
        self.assertIn('liveReadGrant: Bool = false',service)
        self.assertIn('writeAdapter: (any NearbyTeamWriting)? = nil',service)
        self.assertIn('review.action == action, review.session == session',service)
        self.assertIn('approval: OperationEndpointApproval? = nil',adapter)
        self.assertIn('evidence.validates(review, now: now())',adapter)
        self.assertIn('record.phase = .dispatched; try journal.write(record)',adapter)
        self.assertIn('case .acknowledged',adapter)
        self.assertNotIn('URLSessionTransport()',adapter)
    def test_wire_shapes(self):
        self.assertIn('method: "GET", path: "/api/team/nearby"',CORE)
        self.assertIn('"lat": String(context.latitude)',CORE)
        self.assertIn('"radius": String(context.radius)',CORE)
        self.assertIn('path: "/api/team/my-applications", query: [:], body: nil',CORE)
        self.assertIn('["teamId": team.rawValue, "memberId": applicant.rawValue, "approved": approved]',CORE)
    def test_all_source_error_codes(self):
        for code in ['TICKET_REQUIRED','APPLY_REJECTED','APPLY_PENDING','ALREADY_JOINED','TEAM_FULL','ACTIVITY_STARTED','TEAM_UNDER_REVIEW','TEAM_NOT_PUBLIC','APPLY_BLOCKED','APPLY_NOT_PENDING']:
            self.assertIn('"'+code+'"',CORE)
    def test_error_message_not_state_authority(self):
        effect=CORE.split('public static func resolve(operation:')[1].split('}; return effect')[0]
        self.assertNotIn('message',effect)
        self.assertIn('switch (operation, errorCode)',effect)
    def test_no_fabricated_expiry(self):
        self.assertNotIn('addingTimeInterval(86400)',CORE)
        self.assertIn('replaceExpiry: true',CORE)
        self.assertIn('applyExpireTime = expiry',CORE)
    def test_review_and_locks(self):
        for term in ['snapshot.session == session','snapshot.revision == revision','review == snapshot','uncertain','questify.nearby.unresolved.v1.','guard valid(capturedSession, capturedGeneration)','settledActions']:
            self.assertIn(term,CORE)
    def test_identity_bridge(self):
        for term in ['NearbyApplicantID','NearbyTeamID','case joined(OwnedTeam)','ownerType/ownerID','radius: 1000','number % 10 == 4']:
            self.assertIn(term,CORE)
    def test_synthetic_fixtures_parse(self):
        fixtures=(ROOT/'Core/NearbyTeamSyntheticFixtures.swift').read_text()
        blocks=re.findall(r'public static let (\w+) = """\n(.*?)\n    """',fixtures,re.S)
        self.assertEqual(len(blocks),3)
        for _, block in blocks: self.assertEqual(json.loads(block)['code'],200)
    def test_swift_suite_has_interruption_and_role_tests(self):
        tests=(ROOT/'Tests/CoreTests/NearbyTeamTests.swift').read_text()
        self.assertGreaterEqual(len(re.findall('    func test',tests)),18)
        for term in ['testLateReadAfterLogoutIsDiscarded','testLateMutationUnknownSurvivesLogout','testMerchantRoleDoesNotRead','testExpiredApplicantCannotBeReviewed']:
            self.assertIn(term,tests)
if __name__ == '__main__':
    unittest.main(verbosity=2)
