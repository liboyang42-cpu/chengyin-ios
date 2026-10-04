"""Source integration gates only. Swift runtime coverage is authored separately."""
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
class NonCashRewardReaderChecks(unittest.TestCase):
    def test_normal_root_passes_dormant_session_reader(self):
        session = (ROOT / 'App/AppSession.swift').read_text()
        self.assertIn('private let nonCashRewardService: NonCashRewardService? = nil', session)
        self.assertIn('epoch: gate.currentStamp', session)
        self.assertIn('self.currentNonCashRewardSession == captured', session)
        self.assertIn('rewards:session.nonCashRewardReader', (ROOT / 'App/AccountView.swift').read_text())
    def test_only_source_read_routes_and_no_owner_query(self):
        source = (ROOT / 'Core/NonCashRewardService.swift').read_text()
        self.assertIn('request.httpMethod = "GET"', source)
        self.assertIn('api/rewards/noncash', source)
        for name in ['limit', 'cursor', 'contextType', 'contextId', 'releaseId', 'instanceId']:
            self.assertIn('name: "' + name + '"', source)
        for name in ['memberId', 'ownerId', 'accountId', 'token']:
            self.assertNotIn('name: "' + name + '"', source)
        for forbidden in ['URLSession', 'POST', 'qr-token', 'redeem(', 'grant(']: self.assertNotIn(forbidden, source)
    def test_live_ui_does_not_enable_presentation_and_fresh_detail_is_read(self):
        source = (ROOT / 'App/NonCashRewardViews.swift').read_text()
        self.assertIn('reader.isOfflineExample, reward.canPresent', source)
        self.assertIn('try await reader.reward(reference)', source)
        self.assertIn('rewards.redemptionUnavailable', source)
        self.assertIn('model.state.nextCursor != nil', source)
        self.assertIn('AccountCollectionReadLifecycle', source)
    def test_domain_and_late_reply_fences_are_explicit(self):
        source = (ROOT / 'Core/NonCashRewardService.swift').read_text()
        for guard in ['value.asOf >= old.asOf', 'old.state == .awarded || value.state == old.state', 'quantity == 1', 'validUntil > validFrom']:
            self.assertIn(guard, source)
        reader = (ROOT / 'Core/NonCashRewardReading.swift').read_text()
        self.assertIn('currentSession() == session, scope == captured', reader)
        model = (ROOT / 'Core/NonCashRewardCollectionModel.swift').read_text()
        self.assertIn('existing.isDisjoint(with: incoming)', model)
        self.assertIn('consumedCursors', model)
    def test_swift_fixtures_match_captured_backend_mvc_projection(self):
        import json, re, hashlib
        raw = (ROOT / 'Tests/ContractChecks/fixtures/noncash-mvc-wire-examples.json').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(), '6a65210fb9a53b35d1df3c5395745f643968351a7fb04a8edd6f248cc18e8caa')
        fixture = json.loads(raw)
        swift = (ROOT / 'Tests/CoreTests/NonCashRewardReaderTests.swift').read_text()
        for name, key in [('mvcRewardList', 'W17_READ_LIST_JSON'), ('mvcRewardDetail', 'W17_READ_DETAIL_JSON'), ('mvcRewardNotFound', 'W17_READ_NOT_FOUND_JSON')]:
            match = re.search(r'private let ' + name + r' = #"(.*?)"#', swift)
            self.assertIsNotNone(match)
            self.assertEqual(json.loads(match.group(1)), fixture[key])
