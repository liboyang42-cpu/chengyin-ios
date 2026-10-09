"""Offline source contracts only; these do not compile or execute Swift/iOS."""
from pathlib import Path
import hashlib
import json
import os
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
READING = (ROOT / 'Core/MerchantOperationsReading.swift').read_text()
BRANCH = READING.split('if destination == .character {', 1)[1].split('} else if destination == .profile', 1)[0]
TESTS = (ROOT / 'Tests/CoreTests/MerchantNPCCharacterReadbackTests.swift').read_text()
CATALOG = json.loads((ROOT / 'Resources/MerchantNPCCharacterReadbackLocalizations.fragment.json').read_text())['strings']


class MerchantNPCCharacterReadbackContracts(unittest.TestCase):
    def test_only_acknowledged_character_save_enters_readback(self):
        confirmation = READING.split('public func confirm(', 1)[1]
        self.assertLess(confirmation.index('try await reader.saveReviewed'), confirmation.index('if destination == .character'))
        self.assertLess(confirmation.index('isLocked = false'), confirmation.index('if destination == .character'))
        self.assertIn('try await reader.document(.character)', BRANCH)
        self.assertNotIn('saveReviewed', BRANCH)

    def test_old_fields_are_cleared_before_the_await(self):
        self.assertLess(BRANCH.index('document = nil; baseline = nil; draft = nil; exampleSaved = false'),
                        BRANCH.index('try await reader.document(.character)'))
        self.assertNotIn('baseline = value.draft', BRANCH)
        self.assertNotIn('draft = value.draft', BRANCH)

    def test_success_is_only_authoritative_character_data(self):
        self.assertIn('guard case .draft(.character(let character)) = current', BRANCH)
        self.assertIn('document = current; baseline = .character(character); draft = .character(character)', BRANCH)
        for token in ['auditStatus =', 'auditReason =', 'enabled =', 'MerchantStoreCharacter()', '.approved', '.pending']:
            self.assertNotIn(token, BRANCH)

    def test_success_and_failure_are_both_session_fenced(self):
        fence = 'guard !Task.isCancelled, operation == generation, reader.scope == value.scope, reader.isAuthenticated else { return }'
        self.assertEqual(BRANCH.count(fence), 2)
        self.assertIn('if current != snapshot { snapshot = current; stamp = UUID() }', READING)
        self.assertIn('captured == scope', READING)

    def test_read_failure_cannot_become_an_unknown_write(self):
        failure = BRANCH.split('} catch {', 1)[1]
        self.assertIn('merchantNPCCharacter.readbackFailed', failure)
        for token in ['isLocked = true', 'unknownOutcome', 'saveReviewed', 'baseline = value', 'throw error']:
            self.assertNotIn(token, failure)
        self.assertIn('isLocked = isLocked || reader.hasPending(destination)', READING)

    def test_existing_reader_rechecks_owner_access_without_public_or_ai_routes(self):
        reader = READING.split('public func document(_ destination:', 1)[1].split('public func saveExample', 1)[0]
        self.assertIn('try await service.access(token: token)', reader)
        self.assertIn('expected == currentSession()', reader)
        service = (ROOT / 'Core/MerchantOperationsService.swift').read_text()
        character = service.split('case .character:', 1)[1].split('case .assets:', 1)[0]
        self.assertIn('api/merchant/npc/profile', character)
        self.assertIn('body: .json', character)
        for token in ['URLSession', 'MerchantNPCGrants', 'chat', 'provider', 'publish', 'UserDefaults']:
            self.assertNotIn(token, BRANCH)

    def test_bilingual_messages_distinguish_acknowledgment_and_failed_readback(self):
        self.assertEqual(set(CATALOG), {'merchantNPCCharacter.readback', 'merchantNPCCharacter.readbackFailed'})
        for key, item in CATALOG.items():
            self.assertIn(key, BRANCH)
            self.assertEqual(set(item['localizations']), {'en', 'zh-Hans'})
            for locale in ('en', 'zh-Hans'):
                self.assertTrue(item['localizations'][locale]['stringUnit']['value'].strip())
        failed = CATALOG['merchantNPCCharacter.readbackFailed']['localizations']['en']['stringUnit']['value']
        self.assertIn('acknowledged', failed)
        self.assertIn('Refresh', failed)

    def test_authored_runtime_regressions_cover_source_gap_and_boundaries(self):
        expected = ['AuthoritativePendingProfile', 'DoesNotInventPendingOrApproval', 'OnlyReloadsOnRetry',
                    'UnexpectedReadbackDocument', 'AbsentOwnerProfile', 'ReadbackIsInFlight',
                    'AccountScopeChange', 'SignOutDuringReadback', 'LeaveDuringReadback',
                    'UnknownWriteNever', 'RejectedWrite', 'RealReaderRefreshesOwnerAccess',
                    'RevokedPostSaveAccess', 'OwnerRevisionChange', 'AmbiguousSaveKeepsDurableJournal']
        for name in expected:
            self.assertIn(name, TESTS)
        self.assertEqual(len(re.findall(r'func test\w+\(', TESTS)), 15)


class MerchantNPCCharacterCe61Parity(unittest.TestCase):
    def test_verified_mini_and_backend_review_contracts(self):
        external = os.environ.get('CHENGYIN_CE61_SOURCE_ROOT')
        if external is None:
            self.skipTest('NOT_RUN: optional ce61 source checkout not supplied')
        source = Path(external)
        blobs = {
            'chengyinhub-xcx/pages/merchant/decor/ai-npc/index.js': 'd0088bf4d71158bc2b5cc19e7b4e1db32c4fc0b3',
            'chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiMerchantController.java': 'ac739a411d2de90de83bebecf482508e1d363a2a',
            'chengyinhub-system/src/main/resources/mapper/business/NpcProfileMapper.xml': '5083449a94de07f67eb80ebe0d5a0b18c937e6cf',
        }
        contents = []
        for path, expected in blobs.items():
            data = (source / path).read_bytes()
            self.assertEqual(hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest(), expected)
            contents.append(data.decode())
        mini, controller, mapper = contents
        persist = mini.split('persistProfile(payload, onSuccess)', 1)[1].split('openVoice()', 1)[0]
        self.assertIn('auditStatus: 0, auditReason:', persist)
        profile = controller.split('@PostMapping("/npc/profile")', 1)[1].split('@PostMapping("/npc/save")', 1)[0]
        self.assertIn('MerchantPermission.PROFILE_WRITE', profile)
        self.assertIn('selectMerchantNpcList(access.getMerchantId(), null)', profile)
        update = mapper.split('<update id="updateMerchantSelfNpc"', 1)[1].split('</update>', 1)[0]
        self.assertIn('audit_status = 0', update)
        self.assertIn('scope_id = #{scopeId}', update)
        self.assertIn('scope_type = 2', update)


if __name__ == '__main__':
    unittest.main()
