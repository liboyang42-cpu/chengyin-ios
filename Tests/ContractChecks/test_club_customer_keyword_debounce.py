"""P044 keyword source checks, not Swift execution or Apple target admission."""
from pathlib import Path
import hashlib
import unittest
from tools import club_customer_directory_admission as _club_history
_CLUB_LIVE_ROOT = Path(__file__).resolve().parents[2]
ROOT = _club_history.club_keyword_context(_CLUB_LIVE_ROOT)
PATH = 'App/ClubGovernanceViews.swift'
BASE_SHA = 'bff35ca70073f32a548aa10a3741f8e64e82dcb9542117a97c06a22f1d724e4a'
CURRENT_SHA = 'f29b604938d53c1d397f1da93961eae1672a80b45b05bc3016501667dc6533ff'
REPLACEMENTS = [('    @State private var keyword = ""\n    @State private var customerKeywordDebounce = ClubCustomerKeywordDebounce()\n', '    @State private var keyword = ""\n'), ('                    .onChange(of: filter) { _, _ in loadCustomersNow() }\n                    TextField("club.gov.keyword", text: $keyword).submitLabel(.search)\n                        .onChange(of: keyword) { _, _ in scheduleCustomerKeywordRead() }\n                        .onSubmit { loadCustomersNow() }\n                    Button("club.gov.search") { loadCustomersNow() }.disabled(loading)', '                    .onChange(of: filter) { _, _ in Task { await load() } }\n                    TextField("club.gov.keyword", text: $keyword).submitLabel(.search).onSubmit { Task { await load() } }\n                    Button("club.gov.search") { Task { await load() } }.disabled(loading)'), ('        .onDisappear {\n            if operation == .customers {\n                customerKeywordDebounce.cancel()\n                generation &+= 1\n            }\n        }\n        .onDisappear { generation &+= 1 }', '        .onDisappear { generation &+= 1 }'), ('    @MainActor private func load() async {\n        if operation == .customers { customerKeywordDebounce.cancel() }\n', '    private func load() async {\n'), ('    @MainActor private func invalidateRead() {\n        if operation == .customers { customerKeywordDebounce.cancel() }\n', '    private func invalidateRead() {\n')]

def digest(raw): return hashlib.sha256(raw).hexdigest()
def restore(raw):
    if digest(raw) != CURRENT_SHA: raise ValueError('Unreviewed keyword production input')
    source = raw.decode('utf-8')
    start = source.index('/// P044 keyword-only scheduling.')
    end = source.index('/// Mount independently of legacy', start)
    source = source[:start] + source[end:]
    start = source.index('    @MainActor private func loadCustomersNow()')
    end = source.index('    @MainActor private func load() async', start)
    source = source[:start] + source[end:]
    for after, before in REPLACEMENTS:
        if source.count(after) != 1: raise ValueError('Inverse span absent or repeated')
        source = source.replace(after, before, 1)
    result = source.encode('utf-8')
    if digest(result) != BASE_SHA: raise ValueError('Complete baseline not restored')
    return result

@_club_history.club_authenticated_keyword_test_case
class ClubCustomerKeywordDebounceContracts(unittest.TestCase):
    def source(self): return (ROOT / PATH).read_text()
    def test_exact_source_restores_the_complete_published_base(self):
        self.assertEqual(digest(restore((ROOT / PATH).read_bytes())), BASE_SHA)
    def test_keyword_input_is_wired_and_confirm_and_filter_cancel_first(self):
        source = self.source()
        self.assertIn('.onChange(of: keyword) { _, _ in scheduleCustomerKeywordRead() }', source)
        self.assertIn('.onSubmit { loadCustomersNow() }', source)
        self.assertIn('.onChange(of: filter) { _, _ in loadCustomersNow() }', source)
        body = source.split('private func loadCustomersNow()',1)[1].split('private func scheduleCustomerKeywordRead()',1)[0]
        self.assertLess(body.index('customerKeywordDebounce.cancel()'),body.index('Task { await load() }'))
    def test_production_delay_and_generation_cancellation(self):
        body=self.source().split('/// Mount independently',1)[0]
        for text in ['delayNanoseconds: UInt64 = 300_000_000','try await Task.sleep(nanoseconds: ClubCustomerKeywordDebounce.delayNanoseconds)','pending?.cancel()','revision &+= 1','guard !Task.isCancelled, self.revision == expected else { return }']:
            self.assertIn(text,body)
        self.assertLess(body.index('self.pending = nil'),body.index('await action()'))
    def test_old_response_is_retired_before_the_debounce_wait(self):
        body=self.source().split('private func scheduleCustomerKeywordRead()',1)[1].split('private func load() async',1)[0]
        for text in ['guard operation == .customers else { return }','generation &+= 1','snapshot = nil; snapshotContext = nil','context == readContext','expected == identity','access.identity == expected','filter == expectedFilter','keyword == expectedKeyword','!Task.isCancelled']:
            self.assertIn(text,body)
        self.assertLess(body.index('generation &+= 1'),body.index('customerKeywordDebounce.schedule'))
    def test_refresh_disappear_and_context_invalidation_cancel_pending_work(self):
        source=self.source()
        self.assertIn('.onDisappear { generation &+= 1 }', source)
        self.assertIn('keywordRevision == generation', source)
        self.assertIn('let keywordRevision = generation', source)
        self.assertIn('customerKeywordDebounce.cancel()\n                generation &+= 1', source)
        for start in ['private func load() async {','private func invalidateRead() {']:
            body=source.split(start,1)[1]
            self.assertIn('if operation == .customers { customerKeywordDebounce.cancel() }', ''.join(body.splitlines()[:2]))
        self.assertIn('.refreshable { await load() }',source)
        self.assertIn('.onChange(of: readContext) { _, _ in invalidateRead() }',source)
        self.assertIn('.onChange(of: identity) { _, _ in invalidateRead() }',source)
    def test_payload_and_final_transport_fences_are_unchanged(self):
        source=self.source()
        self.assertIn('if operation == .customers { options = ["filter": .string(filter), "keyword": .string(keyword)] }',source)
        self.assertNotIn('keyword.trimmingCharacters',source)
        self.assertIn('guard revision == generation, context == readContext, expected == identity, access.identity == expected, !Task.isCancelled else { return }',source)
        self.assertIn('guard context.accepts(result) else { throw ClubGovernanceFailure.targetChanged }',source)
    def test_all_four_production_edges_reject_source_mutations(self):
        original=(ROOT/PATH).read_bytes()
        for before,after in [(b'300_000_000',b'000_000_000'),(b'pending?.cancel()',b'pending = nil'),(b'self.revision == expected',b'true'),(b'keyword == expectedKeyword',b'true'),(b'.onDisappear { generation &+= 1 }',b'.onDisappear { }'),(b'keywordRevision == generation',b'true'),(b'customerKeywordDebounce.cancel()\n                generation &+= 1',b'customerKeywordDebounce.cancel()')]:
            with self.subTest(edge=before),self.assertRaises(ValueError):restore(original.replace(before,after,1))
    def test_swift_timer_tests_are_authored_without_runtime_claims(self):
        source=(ROOT/'Tests/AppUnitTests/ClubCustomerKeywordDebounceTests.swift').read_text()
        self.assertEqual(source.count('    func test'),6)
        self.assertIn('NOT_RUN',source)
        self.assertIn('XCTAssertFalse(Task.isCancelled)',source)
        self.assertIn('SleeperIgnoresCancellation',source)

if __name__ == '__main__': unittest.main()
