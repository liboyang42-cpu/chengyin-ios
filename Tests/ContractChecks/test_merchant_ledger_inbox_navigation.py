import pathlib,unittest,json
ROOT=pathlib.Path(__file__).resolve().parents[2]
class LedgerInboxContracts(unittest.TestCase):
    def setUp(self): self.s=(ROOT/'App/MerchantLedgerInboxNavigation.swift').read_text()
    def test_exact_ledger_sources(self):
        self.assertIn('case .overview, .entries, .batches: return true',self.s)
        self.assertIn('snapshot.access.allows("merchant:finance:read")',self.s)
    def test_fresh_source_and_scope(self):
        for t in ['reader.snapshot(baseline.document.query)','fresh.access == baseline.access','reader.authorizationGeneration == authorization','fresh.document.query == baseline.document.query']:self.assertIn(t,self.s)
    def test_destination_identity_before_and_after(self):
        for t in ['identity.accountID == source.scope.accountID','identity.epoch == source.scope.epoch','currentMessaging() === messaging','messaging.identity == identity','generation == token']:self.assertIn(t,self.s)
    def test_production_existing_messaging_composition(self):
        for t in ['source.reader === session.merchantBusinessReader','MessagingHomeView(reader: session.messagingReader','session.socialMessageMediaReader','session.messageSender(for: $0)','session.imExpandedNavigation']:self.assertIn(t,self.s)
        for t in ['sendRequest','subscribe','URLRequest','execute(','messagingConversations()']:self.assertNotIn(t,self.s)
    def test_normal_host_and_factory(self):
        h=(ROOT/'App/MerchantBusinessViews.swift').read_text();a=(ROOT/'App/QuestifyApp.swift').read_text()
        self.assertIn('MerchantLedgerInboxEntry(reader: reader, snapshot: snapshot)',h)
        self.assertIn('!state.isBusy, state.failureKey == nil, snapshot.document.query == query',h)
        self.assertIn('SessionMerchantLedgerInboxView(session: session, source: $0)',a)
    def test_background_retry_and_bilingual(self):
        self.assertIn('.onDisappear { isVisible = false; gate.deactivate() }',self.s)
        self.assertIn('Button("action.retry")',self.s)
        f=json.loads((ROOT/'Resources/MerchantLedgerInboxLocalizations.fragment.json').read_text())
        for v in f.values():self.assertEqual(set(v['localizations']),{'en','zh-Hans'})
    def test_hidden_host_and_queued_retry_are_generation_fenced(self):
        self.assertIn('@State private var isVisible = false',self.s)
        self.assertIn('guard isVisible, scenePhase == .active, ownsSource else { gate.deactivate(); return }',self.s)
        self.assertIn('.onChange(of: scenePhase) { _, _ in scheduleOpen() }',self.s)
        self.assertIn('guard let permit = gate.openingPermit() else { return }\n        Task { await gate.open(source, currentMessaging: { session.messagingReader }, permit: permit) }',self.s)
        self.assertIn('guard active, permit == nil || permit == generation else { return }\n        cancel();',self.s)
        self.assertNotIn('Task { await open() }',self.s)
if __name__=='__main__':unittest.main()
