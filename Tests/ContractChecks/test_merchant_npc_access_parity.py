"""Offline structure and optional pinned-source checks; not Swift execution."""
from pathlib import Path
import hashlib
import os
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
ACCESS = (ROOT / 'Core/MerchantOperationsContracts.swift').read_text().split('public enum MerchantOperationsDestination', 1)[0]
SERVICE = (ROOT / 'Core/MerchantOperationsService.swift').read_text()
READING = (ROOT / 'Core/MerchantOperationsReading.swift').read_text()
APP = (ROOT / 'App/AppSession.swift').read_text()
TESTS = (ROOT / 'Tests/CoreTests/MerchantNPCAccessParityTests.swift').read_text()


class MerchantNPCAccessParityContracts(unittest.TestCase):
    def test_character_requires_exact_active_profile_permission(self):
        self.assertIn('profileWrite = identity.active && permissions.contains("merchant:profile:write")', ACCESS)
        self.assertIn('guard identity.active else { return false }', ACCESS)
        self.assertIn('case .character: return profileWrite', ACCESS)
        self.assertNotIn('roleCode', ACCESS)

    def test_legacy_assets_and_city_policy_not_reclassified(self):
        self.assertIn('case .assets, .cityNodes: return true', ACCESS)
        factory = (ROOT / 'Core/MerchantPublicProduction.swift').read_text()
        self.assertIn('public static let supportsLegacyResources = false', factory)
        self.assertIn('guard MerchantPublicProductionFactory.supportsLegacyResources else', APP)

    def test_shared_read_checks_permission_before_character_endpoint(self):
        method = SERVICE.split('public func document(', 1)[1].split('/// Exact source writes', 1)[0]
        self.assertLess(method.index('guard canRead else'), method.index('api/merchant/npc/profile'))
        self.assertIn('access.allows(destination)', method)
        character = method.split('case .character:', 1)[1].split('case .assets:', 1)[0]
        self.assertIn('body: .json', character)
        self.assertNotIn('profileWrite =', method)

    def test_visible_entry_reuses_same_permission_projection(self):
        views = (ROOT / 'App/MerchantOperationsViews.swift').read_text()
        self.assertIn('destinations.filter { access.allows($0) }', views)
        self.assertIn('MerchantOperationsDocumentView(reader: merchantOperationsReader', APP)

    def test_session_reader_refreshes_access_and_fences_late_reads(self):
        method = READING.split('public func document(_ destination:', 1)[1].split('public func saveExample', 1)[0]
        self.assertLess(method.index('service.access(token: token)'), method.index('service.document(destination'))
        self.assertIn('expected == currentSession()', method)
        self.assertIn('currentSession() == session, captured == scope', READING)
        self.assertIn('public let viewerRevision: UInt64', READING)

    def test_write_preflight_rechecks_permission_before_journal_and_send(self):
        method = SERVICE.split('public func save(_ draft:', 1)[1]
        self.assertLess(method.index('access.allows(draft.destination)'), method.index('try journal.write(record)'))
        self.assertLess(method.index('access.allows(draft.destination)'), method.index('transport.send(request)'))
        self.assertIn('guard let approval, let baseline, let journal, let checkSession', method)
        ordinary = APP.split('lazy var merchantOperationsReader =', 1)[1].split('private let merchantOnboardingService', 1)[0]
        self.assertNotIn('approval:', ordinary)
        self.assertNotIn('journal:', ordinary)

    def test_runtime_regressions_cover_denial_success_and_lifecycle(self):
        for name in ['RoleNameCannotSubstitute', 'ExplicitProfileWriteAllowsActiveDelegates',
                     'UnknownActiveRoleCannotDecodeEvenWithExplicitProfileWrite',
                     'LegacyAssetsAndCityPolicyIsUnchanged', 'DeniedCharacterReadUsesZeroTransportRequests',
                     'AuthorizedCharacterReadRetainsExactEndpointAndBody', 'SessionReaderRechecksAccess',
                     'RevokedAccessReloadClearsPreviouslyLoadedCharacter', 'AccountChangeDuringAccessRead',
                     'AccessRevisionChangeDuringProfileRead', 'ServerRevocationDuringProfileRead',
                     'SignOutDuringProfileRead', 'WritePreflightUsesLatestPermission',
                     'ProfileWritePermissionDoesNotEnableOrdinaryReaderWrites']:
            self.assertIn(name, TESTS)
        self.assertEqual(len(re.findall(r'func test\w+\(', TESTS)), 14)
        self.assertEqual(TESTS.count('for role in MerchantAccess.Role.allCases'), 2)
        unknown = TESTS.split('func testUnknownActiveRoleCannotDecodeEvenWithExplicitProfileWrite()', 1)[1].split('func testLegacyAssets', 1)[0]
        self.assertIn('XCTAssertThrowsError(try access(permissions, role: role))', unknown)
        self.assertIn('DecodingError.dataCorrupted', unknown)
        self.assertNotIn('XCTAssertTrue', unknown)


class MerchantNPCAccessCe61Parity(unittest.TestCase):
    def test_pinned_source_requires_profile_write_for_character(self):
        value = os.environ.get('CHENGYIN_NPC_ACCESS_EVIDENCE_ROOT')
        if value is None:
            self.skipTest('NOT_RUN: optional pinned ce61 NPC source evidence not supplied')
        root = Path(value)
        blobs = {'ApiMerchantController.java': 'ac739a411d2de90de83bebecf482508e1d363a2a',
                 'index.wxml': 'c390dc72f237add08f5ab66333b36a63d290745b'}
        texts = {}
        for name, expected in blobs.items():
            data = (root / name).read_bytes()
            digest = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
            self.assertEqual(digest, expected)
            texts[name] = data.decode()
        controller = texts['ApiMerchantController.java']
        for start, end in [('@PostMapping("/npc/profile")', '@PostMapping("/npc/save")'),
                           ('@PostMapping("/npc/save")', '@PostMapping("/npc/voice/enroll")')]:
            method = controller.split(start, 1)[1].split(end, 1)[0]
            self.assertIn('MerchantPermission.PROFILE_WRITE', method)
            self.assertIn('access.getMerchantId()', method)
        self.assertIn('kind="merchant" need="canWriteProfile"', texts['index.wxml'])
        # This file supplies no evidence for the dormant legacy avatar route.
        self.assertNotIn('@PostMapping("/npc/avatar/status")', controller)


if __name__ == '__main__':
    unittest.main()
