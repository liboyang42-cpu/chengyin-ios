"""Static P003 wiring checks only. These do not execute Swift, HTTP, or Apple UI tests."""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class MerchantClubDiscoveryContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_locality_uses_existing_owner_operator_info_read_only(self):
        source = self.read('Core/MerchantOnboardingService.swift')
        method = source.split('public func clubLocality(', 1)[1].split('public func application(', 1)[0]
        self.assertIn('read(request("api/merchant/info", token: token, multipart: true))', method)
        self.assertEqual(re.findall(r'"api/[^" ]+"', method), ['"api/merchant/info"'])
        for prohibited in ['write(', 'submit(', 'upload', 'member_id', 'merchantId', 'latitude', 'longitude', 'URLSession']:
            self.assertNotIn(prohibited, method)

    def test_narrow_projection_requires_positive_identity_and_only_city_address(self):
        source = self.read('Core/MerchantClubDiscovery.swift')
        self.assertIn('case id, city, address', source)
        self.assertIn('let id = c.merchantInteger(.id), id > 0', source)
        self.assertIn('value = city.flatMap', source)
        self.assertIn('?? address.flatMap', source)
        self.assertNotIn('CLLocation', source)
        self.assertNotIn('geocodeAddressString', source)

    def test_exact_literal_filter_does_not_normalize_club_city(self):
        source = self.read('Core/MerchantClubDiscovery.swift')
        method = source.split('public func matches(', 1)[1].split('\n}', 1)[0]
        self.assertIn('let city = club.city.flatMap { $0.isEmpty ? nil : $0 }', method)
        self.assertIn('let location = city ?? club.address ?? ""', method)
        self.assertIn('location.range(of: value, options: .literal)', method)
        self.assertIn('value.range(of: $0, options: .literal)', method)
        for prohibited in ['lowercased', 'localized', 'trimmingCharacters']:
            self.assertNotIn(prohibited, method)
        self.assertIn('Self.sourceWhitespace', source)
        self.assertIn(r'\u{FEFF}', source)
        self.assertNotIn(r'\u{0085}', source)

    def test_scope_covers_identity_role_viewer_and_merchant_revisions(self):
        source = self.read('Core/MerchantClubDiscovery.swift')
        for field in ['identity: ClubReadIdentity', 'role: String?', 'viewerRevision: UInt64',
                      'merchantID: Int?', 'merchantRevision: UInt64']:
            self.assertIn(field, source)
        self.assertIn('identity.isSignedIn && role == "merchant"', source)
        self.assertIn('current.merchantID == result.merchantID', source)

    def test_state_fences_scope_generation_and_unknown_result(self):
        source = self.read('Core/MerchantClubDiscovery.swift')
        self.assertIn('request.generation == generation && request.scope == scope && scope == current', source)
        self.assertIn('guard result.value != nil', source)
        self.assertIn('locality = nil; phase = .unavailable', source)
        self.assertIn('guard current.isMerchantViewer, scope == current, phase == .ready, let locality else { return rows }', source)
        self.assertIn('public mutating func leaveScreen()', source)

    def test_default_readers_preserve_player_behavior_without_info_request(self):
        source = self.read('Core/ClubReading.swift')
        extension = source.split('public extension ClubReading {', 1)[1].split('\n}', 1)[0]
        self.assertIn('.init(identity: clubIdentity)', extension)
        self.assertIn('throw APIError.notConfigured', extension)
        self.assertNotIn('clubLocality(token:', extension)

    def test_app_session_reads_with_credential_and_scope_fences_without_expiring_optional_read(self):
        source = self.read('App/AppSession.swift')
        locality = source.split('func clubMerchantLocality()', 1)[1].split('func clubHome()', 1)[0]
        self.assertIn('captured.isMerchantViewer', locality)
        self.assertEqual(locality.count('clubDiscoveryScope == captured, token == credential'), 2)
        self.assertIn('merchantOnboardingService.clubLocality(token: credential)', locality)
        self.assertNotIn('expireIfMatching(', locality)
        self.assertIn('captured.merchantID == result.merchantID', locality)

    def test_access_refresh_cannot_expire_a_new_scope_or_canceled_request(self):
        source = self.read('App/AppSession.swift')
        method = source.split('private func readMerchant<Value>', 1)[1].split('func merchantAccess()', 1)[0]
        catch = method.split('} catch {', 1)[1]
        self.assertLess(catch.index('expectedDiscoveryScope == nil || !Task.isCancelled'), catch.index('expireIfMatching'))
        self.assertLess(catch.index('expectedDiscoveryScope == clubDiscoveryScope'), catch.index('expireIfMatching'))
        access = source.split('func merchantAccess()', 1)[1].split('func merchantDashboard', 1)[0]
        self.assertEqual(access.count('merchantClubAccessRevision &+= 1'), 2)
        self.assertIn('readMerchant(expectedDiscoveryScope: localityScope)', access)
        self.assertLess(access.index('guard clubDiscoveryScope == localityScope'), access.index('merchantAccessRecord=(gate.currentStamp,access)'))

    def test_current_scope_is_consulted_during_render_and_each_completion(self):
        source = self.read('App/ClubHomeView.swift')
        self.assertIn('reader.clubDiscoveryScope', source)
        self.assertIn('.task(id: discoveryScope)', source)
        self.assertIn('.onDisappear { locality.leaveScreen() }', source)
        self.assertIn('locality.receive(result, for: request, current: discoveryScope)', source)
        self.assertIn('locality.fail(request, current: discoveryScope)', source)
        self.assertEqual(source.count('guard !Task.isCancelled else { return }'), 2)

    def test_merchant_owned_joined_create_are_presentation_hidden_only(self):
        source = self.read('App/ClubHomeView.swift')
        self.assertIn('if !discoveryScope.isMerchantViewer, let operations = management?.operations', source)
        self.assertIn('''if !discoveryScope.isMerchantViewer {
                    clubSection("club.owned"''', source)
        self.assertIn('clubSection("club.joined", rows: home.joined', source)
        self.assertIn('rows: locality.nearby(home.nearby, in: discoveryScope)', source)
        self.assertIn('ClubDetailView(id: club.id, reader: reader', source)
        self.assertIn('if let topicDestination, event.id > 0', source)

    def test_locality_failure_is_inline_with_retry_not_an_empty_list(self):
        source = self.read('App/ClubHomeView.swift')
        for marker in ['club.locality.loadingHint', 'club.locality.unavailableHint', 'club.home.locality.retry',
                       'club.locality.ready', 'club.locality.empty']:
            self.assertIn(marker, source)
        self.assertIn('Button("action.retry") { Task { await loadLocality() } }', source)

    def test_bilingual_fragment_is_merged_without_empty_strings(self):
        fragment = json.loads(self.read('Resources/MerchantClubDiscoveryLocalizations.fragment.json'))
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        self.assertEqual(len(fragment), 6)
        for key, value in fragment.items():
            self.assertEqual(catalog[key], value)
            for language in ['en', 'zh-Hans']:
                self.assertTrue(value['localizations'][language]['stringUnit']['value'].strip())

    def test_authored_tests_cover_edge_semantics_and_lifecycle(self):
        source = self.read('Tests/CoreTests/MerchantClubDiscoveryTests.swift')
        for name in ['testSourceTrimIncludesBOMButDoesNotStripNEL', 'testFilterIsLiteralWithoutUnicodeNormalization',
                     'testLoadingFailureAndUnknownRetainUnfilteredNearbyThenRetryFilters',
                     'testEveryCurrentScopeDimensionRejectsOldSuccessAndFailureImmediately',
                     'testRoleAndMerchantABARemainFencedByRevisions',
                     'testReversedRetryCompletionCannotReplaceLatestOrMakeItFail',
                     'testMerchantMismatchFallsBackWithoutAdoptingAnotherMerchant',
                     'testDisappearRejectsPendingButKeepsReadyRowsForReturnNavigation',
                     'testReusesOnlyExistingEmptyMultipartTokenScopedInfoRead']:
            self.assertIn('func ' + name, source)
        for literal in re.findall(r'#"(.*?)"#', source, re.S):
            json.loads(literal)

    def test_ui_fixture_has_deterministic_continuations_not_sleep_races(self):
        fixture = self.read('App/ClubFixtureSupport.swift')
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertIn('withCheckedThrowingContinuation', fixture)
        self.assertIn('continuation.resume(throwing: APIError.unauthorized)', fixture)
        self.assertIn('pendingLocalityCount', fixture)
        self.assertNotIn('URLSession', fixture)
        tests = self.read('Tests/AppUITests/MerchantClubDiscoveryFlowTests.swift')
        for marker in ['testLateLocalityAfterPlayerSwitchCannotHidePlayerRows',
                       'testMerchantSwitchFencesOldUnauthorizedBeforeNewLocality',
                       'testMerchantLocalityHidesOwnedJoinedAndKeepsDetailReturn']:
            self.assertIn(marker, tests)
        self.assertNotIn('sleep(', tests)
        self.assertNotIn('XCTSkip', tests)
