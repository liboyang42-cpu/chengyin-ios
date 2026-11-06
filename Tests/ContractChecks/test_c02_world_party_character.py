"""Linux contract checks for C02 world/party/character projections. XCTest is NOT_RUN here."""
from pathlib import Path
import hashlib
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = {
    'world': ROOT / 'Core/WorldEnvironmentProjection.swift',
    'party': ROOT / 'Core/PartyRosterProjection.swift',
    'card': ROOT / 'Core/CharacterCardReadback.swift',
    'clock': ROOT / 'Core/EnvironmentExpiryClock.swift',
}
TESTS = {
    'world': ROOT / 'Tests/CoreTests/WorldEnvironmentProjectionTests.swift',
    'party': ROOT / 'Tests/CoreTests/PartyRosterProjectionTests.swift',
    'card': ROOT / 'Tests/CoreTests/CharacterCardReadbackTests.swift',
}
FRAGMENT = ROOT / 'Resources/WorldEnvironment.fragment.json'
HUNK = ROOT / 'docs/issue5-hunks/C02-ios-pbx.rnhunk.md'
FORBIDDEN = [
    ROOT / 'App/AppSession.swift',
    ROOT / 'Questify.xcodeproj/project.pbxproj',
    ROOT / 'Resources/Localizable.xcstrings',
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class C02WorldPartyCharacterContracts(unittest.TestCase):
    def test_xctest_is_explicitly_not_run_on_linux(self):
        self.assertIn('NOT_RUN', Path(__file__).read_text())
        self.assertTrue(TESTS['card'].exists())

    def test_exclusive_files_exist_and_reuse_existing_http_clients(self):
        card = CORE['card'].read_text()
        for marker in ['PlayExperienceService', 'api/play/character', 'api/play/rpg/status',
                       'playerProjection', 'playerCommand', 'playerReceipt', 'originalRequestID']:
            self.assertIn(marker, card)
        self.assertNotIn('URLSession.shared', card)
        self.assertNotIn('URLSession(', card)
        self.assertNotIn('UUID().uuidString', card)
        self.assertIn('PlayPlayerTeamState', CORE['party'].read_text())
        self.assertIn('PlayAdvancedTeamProjection', CORE['party'].read_text())
        self.assertIn('recoverFromRouteAction', card)
        self.assertIn('recoverFromGameReceipt', card)
        self.assertIn('gameSession.receipt', card)
        self.assertIn('rpgv2.RpgRequestReceipts', card)
        self.assertNotIn('rpg2:', card)

    def test_missing_api_is_waiting_source_or_unknown_not_fake_success(self):
        for path in CORE.values():
            text = path.read_text()
            self.assertIn('WAITING_SOURCE', text)
            self.assertIn('UNKNOWN', text)
        self.assertIn('waitingSource', CORE['world'].read_text())
        self.assertIn('never filled with client weather', CORE['world'].read_text())
        party = CORE['party'].read_text()
        self.assertIn('not an empty success roster', party)
        self.assertIn('WorldEquipmentProjection', party)

    def test_expiry_clock_discards_client_now(self):
        clock = CORE['clock'].read_text()
        self.assertIn('_ = clientNow', clock)
        self.assertNotIn('Date()', clock)
        self.assertNotIn('Date.init', clock)
        self.assertIn('serverNow', clock)
        self.assertIn('expiresAt', clock)
        tests = TESTS['world'].read_text()
        self.assertIn('testClientClockCannotMintSuccessFromExpiresAt', tests)
        self.assertIn('WAITING_SOURCE', tests)
        self.assertIn('func present', clock)
        self.assertNotIn('raw["serverNow"] ??', clock)

    def test_character_and_play_401_return_before_cancel_for_same_owner(self):
        root = (ROOT / 'App/AppCompositionRoot.swift').read_text()
        runtime = (ROOT / 'Core/RuntimeDependencyConfiguration.swift').read_text()
        for source in (root, runtime):
            auth = source.index('PlayExperienceService.isAuthenticationFailure')
            cancel = source.index('try Task.checkCancellation()', auth)
            window = source[max(0, auth - 500):cancel]
            self.assertIn('CharacterCardReadRoute', source)
            self.assertIn('characterRead' if source is root else 'CharacterCardReadRoute', window)
            self.assertIn('current() == captured', window)
            self.assertLess(auth, cancel)

    def test_account_switch_isolation_markers_present(self):
        tests = TESTS['card'].read_text()
        self.assertIn('testOtherRequestDoesNotRewriteOriginalRequestID', tests)
        self.assertIn('testInProcessRecoverKeepsOriginalAndBlankDoesNotBindEmptyString', tests)
        self.assertIn('testUnknownBreakdownDoesNotOccupyOriginalThenUniqueBindApplies', tests)
        self.assertIn('other-request-id', tests)
        self.assertIn('requestID: ""', tests)
        card = CORE['card'].read_text()
        self.assertIn('if let originalRequestID { guard originalRequestID == command.requestID else { return } }', card)

    def test_first_journey_retries_the_same_original_request_id(self):
        tests = TESTS['card'].read_text()
        for name in ['testFirstJourneyProjectsCardBreakdownEnvironmentPartyEquipmentThenRetriesSameRequestId',
                     'testRetryWithoutOriginalRequestIdDoesNotMintOne',
                     'testHiddenSkillIsRedactedAndSuccessIsNotRecomputed']:
            self.assertIn(name, tests)
        self.assertIn('synthetic-request', tests)
        self.assertIn('body["requestId"].text, original.requestID', tests)
        card = CORE['card'].read_text()
        self.assertIn('command.requestID == originalRequestID', card)
        self.assertIn('CharacterCheckBreakdown', card)
        self.assertIn('never recomputed', card)

    def test_fragment_is_dedicated_and_not_shared_catalog(self):
        catalog = json.loads(FRAGMENT.read_text())['strings']
        self.assertEqual(set(catalog), {
            'world.environment.waitingSource', 'world.environment.unknown',
            'world.expiry.waitingSource', 'world.party.waitingSource', 'world.equipment.waitingSource',
        })
        for item in catalog.values():
            self.assertEqual(set(item['localizations']), {'en', 'zh-Hans'})
        shared = (ROOT / 'Resources/Localizable.xcstrings').read_text()
        for key in catalog:
            self.assertNotIn(key, shared)

    def test_pbx_hunk_exists_and_forbidden_shared_files_are_untouched(self):
        hunk = HUNK.read_text()
        for name in ['WorldEnvironmentProjection.swift', 'PartyRosterProjection.swift',
                     'CharacterCardReadback.swift', 'EnvironmentExpiryClock.swift']:
            self.assertIn(name, hunk)
        self.assertIn('PBXBuildFile', hunk)
        self.assertIn('dot', hunk.lower())
        self.assertTrue(FORBIDDEN[0].exists())
        session = FORBIDDEN[0].read_text()
        self.assertIn('func characterCardReadback(topicID:', session)
        self.assertIn('CharacterCardReadback(topicID:', session)
        self.assertIn('intersection([.reads])', session)
        start = session.index('func characterCardReadback(topicID:')
        end = session.index('// Journey extras', start)
        factory = session[start:end]
        self.assertNotIn('playerCommands', factory)
        self.assertNotIn('URLSession', factory)
        self.assertNotIn('playNodesAndRouteState', factory)
        self.assertIn('compositionViewerRevision == approval.viewerRevision', factory)
        self.assertIn('CharacterCardReadRoute.paths', factory)
        self.assertIn('characterCardScopeMatches', factory)
        route = (ROOT / 'Core/PlayReadRoute.swift').read_text()
        self.assertNotIn('api/play/character', route)
        self.assertNotIn('api/play/rpg/status', route)
        card_route = (ROOT / 'Core/CharacterCardReadRoute.swift').read_text()
        self.assertIn('api/play/character', card_route)
        self.assertIn('api/play/rpg/status', card_route)
        self.assertIn('characterCardReadback(topicID:', (ROOT / 'App/ActivityDetailView.swift').read_text())
        self.assertIn('CharacterCardReadRoute', (ROOT / 'App/AppCompositionRoot.swift').read_text())
        view = (ROOT / 'App/CharacterCardReadbackView.swift').read_text()
        self.assertIn('model.dismiss()', view)
        self.assertIn('model.isCurrent', view)
        self.assertIn('cardIfCurrent()', view)
        strings = (ROOT / 'Resources/Localizable.xcstrings').read_text()
        self.assertIn('"play.character.card"', strings)
        self.assertIn('"Character card"', strings)
        self.assertIn('"角色卡"', strings)
        self.assertIn('testRevokeClearsCardWithoutReloadOrLeavingAndBody401RetiresOwner', TESTS['card'].read_text())
        self.assertIn('PlayExperienceError.unauthorized', CORE['card'].read_text())
        pbx = FORBIDDEN[1].read_text()
        for name in ['WorldEnvironmentProjection.swift', 'PartyRosterProjection.swift',
                     'CharacterCardReadback.swift', 'EnvironmentExpiryClock.swift',
                     'CharacterCardReadRoute.swift', 'CharacterCardReadbackView.swift']:
            self.assertEqual(hunk.count(name) >= 1, True, name)
            self.assertLessEqual(pbx.count(name), 1, name)
            if name not in pbx:
                self.assertIn(name, hunk)

    def test_sha256_manifest_covers_exclusive_sources(self):
        lines = HUNK.read_text().splitlines()
        listed = {line.split()[1]: line.split()[0] for line in lines if re.fullmatch(r'[0-9a-f]{64} \S+', line)}
        for rel in ['Core/WorldEnvironmentProjection.swift', 'Core/PartyRosterProjection.swift',
                    'Core/CharacterCardReadback.swift', 'Core/EnvironmentExpiryClock.swift',
                    'Tests/CoreTests/WorldEnvironmentProjectionTests.swift',
                    'Tests/CoreTests/PartyRosterProjectionTests.swift',
                    'Tests/CoreTests/CharacterCardReadbackTests.swift',
                    'Resources/WorldEnvironment.fragment.json',
                    'Core/CharacterCardReadRoute.swift',
                    'App/CharacterCardReadbackView.swift']:
            self.assertEqual(listed[rel], sha256(ROOT / rel), rel)


if __name__ == '__main__':
    unittest.main()
