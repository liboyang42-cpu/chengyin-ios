"""Supplementary source contracts. Authored Apple tests are not execution evidence."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
def read(p): return (ROOT/p).read_text()
class TemplateShelfReadBridge(unittest.TestCase):
    def test_default_nil_outer_fence_and_clone_selectors(self):
        s = read('App/AppCompositionRoot.swift')
        self.assertEqual(s.count('templateShelfReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> TemplateShelfReadApproval? = { _ in nil }'), 2)
        self.assertIn('templateShelfReadApproval: templateShelfReadApproval', s)
        for token in ['TemplateShelfReadRoute(request: request, baseURL: api.baseURL)', 'currentApproval.revision == approval.revision', 'readApprovalStillValid?() != false']:
            self.assertIn(token, s)
        self.assertNotIn('TemplateShelfReadApproval', read('App/RegionalLaunchConfiguration.swift'))
    def test_read_capability_does_not_enable_authoring(self):
        s = read('Core/TemplateAuthoringService.swift')
        self.assertIn('public var canRead: Bool { shelfReadTransport?.available == true || canSubmit }', s)
        self.assertIn('public var canSubmit: Bool { canSimulate || transport?.authority == .injectedHTTP }', s)
        self.assertIn('guard canSubmit, let transport else', s.split('func listMine()')[1].split('func listMinePage')[0])
        self.assertIn('!descriptor.mutates', read('Core/TemplateShelfReadApproval.swift'))
        factory = read('App/AppSession.swift').split('func templateShelfCoordinator')[1].split('var templateAuthoringViewIdentity')[0]
        self.assertIn('TemplateAuthoringAdapter(shelfReadTransport: makeTemplateShelfReadTransport())', factory)
        self.assertNotIn('TemplateAuthoringHTTPTransport', factory)
        self.assertIn('if coordinator.canSubmit { await coordinator.loadMine() }', read('App/TemplateAuthoringMineView.swift'))
        self.assertIn('TemplateAuthoringView(coordinator: session.templateAuthoringEditor()', read('App/TemplateAuthoringLaunchView.swift'))
    def test_exact_multipart_read_bounds(self):
        s = read('Core/TemplateShelfReadApproval.swift')
        for token in ['body.count <= 4096', 'keyword.utf8.count <= 512', 'fields["pageSize"] == "10"', 'Set(fields.keys) == ["id"]', 'fields[key] == nil', 'split.lowerBound > keyStart', 'canonical.httpBody == body', 'value.memberID == context.session.accountID', 'request.httpBodyStream == nil']:
            self.assertIn(token, s)
        self.assertNotIn('api/template/info"', s)
        self.assertNotIn('api/common/dict', s)
    def test_complete_lifetime_fences_and_authored_negative_cases(self):
        s = read('App/AppSession.swift')
        for token in ['self.compositionViewerRevision == revision', 'self.currentTemplateShelfReadApproval?.revision == approval.revision', 'self.templateShelfViewIdentity == identity']:
            self.assertIn(token, s)
        tests = read('Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift')
        for token in ['"roleABA"', '"sessionABA"', '"reissue"', '"expire"', '"cancel"', '[200, 401, -1]', 'testOuterClonesOnlyAdmitExactReadsAndDenyAllAdjacentMutations']:
            self.assertIn(token, tests)
        self.assertIn('testReadOnlyRefreshRevocationAndReopenPreserveBothPendingJournals', read('Tests/CoreTests/TemplateShelfReadTests.swift'))
    def test_normal_root_recorder_not_live_api(self):
        s = read('App/IntegratedNativeAcceptanceFixture.swift')
        self.assertIn('templateShelfReadApproval: { self.grants($0)?.shelf }', s)
        self.assertIn('case "api/template/my-list":', s)
        self.assertIn('case "api/template/myinfo":', s)
        self.assertIn('testNormalRootOwnedShelfPaginationAndDetailWithoutMutation', read('Tests/AppUITests/IntegratedActivityPlayJourneyFlowTests.swift'))
        self.assertNotIn('func testNormalRootOwnedShelfPaginationAndDetailWithoutMutation(', read('Tests/AppUITests/IntegratedNativeAcceptanceFlowTests.swift'))

    def test_multipart_suffix_uses_swift_character_count_not_byte_count(self):
        s = read('Core/TemplateShelfReadApproval.swift')
        self.assertIn('dropLast("\\r\\n".count)', s)
        self.assertNotIn('dropLast(2)', s)
        tests = read('Tests/CoreTests/TemplateShelfReadTests.swift')
        self.assertIn('XCTAssertEqual("\\r\\n".count, 1)', tests)
        self.assertIn('XCTUnwrap(wire.requests.first', tests)
        self.assertNotIn('wire.requests[0]', tests)
        for case in ['String(repeating: "x", count: 512)', 'String(repeating: "Z", count: 70)', '[1, 9, 10, 41, Int.max]']:
            self.assertIn(case, tests)

    def test_keyword_joiner_exception_does_not_allow_other_format_controls(self):
        source = read('Core/TemplateShelfReadApproval.swift')
        self.assertIn('keyword.utf8.count <= 512, Self.allowsKeywordScalars(keyword)', source)
        self.assertIn('scalar.value == 0x200C || scalar.value == 0x200D', source)
        self.assertIn('!CharacterSet.controlCharacters.contains(scalar) && !CharacterSet.newlines.contains(scalar)', source)
        tests = read('Tests/CoreTests/TemplateShelfReadTests.swift')
        self.assertIn('👩🏽‍💻', tests)
        self.assertIn('testKeywordJoinersDoNotAdmitControlsBidiFormatsOrUnicodeLineBreaks', tests)
        self.assertIn('Array(0...31) + Array(127...159)', tests)
        self.assertIn('0x202E', tests); self.assertIn('0xFEFF', tests); self.assertIn('0xE007F', tests)

# P119 refresh-cache checks are source contracts, not a Swift interpreter or build.
import hashlib
import json
import re
import subprocess

SHELF = 'Core/TemplateAuthoringShelf.swift'
MINE = 'App/TemplateAuthoringMineView.swift'


def _body(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth, cursor = 1, opening + 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[opening + 1:cursor - 1]


def assert_refresh_snapshot_contract(core, view):
    def require(needle, source):
        assert needle in source, needle
    snapshot = _body(core, 'func refreshSnapshot(')
    refresh = _body(core, 'func refresh(keyword:')
    fetch = _body(core, 'private func fetch(')
    transient = _body(core, 'private static func isTransientRefreshFailure(')
    invalidate = _body(core, 'private static func invalidatesReadScope(')
    leave = _body(core, 'public func leave()')
    synchronize = _body(core, 'public func synchronizeSession()')
    require('owner != currentSession() || !adapter.canRead', synchronize)
    for token in ['synchronizeSession()', 'owner != nil, owner == currentSession(), adapter.canRead, self.keyword == keyword, !Task.isCancelled', 'return rows']:
        require(token, snapshot)
    require('let snapshot = refreshSnapshot(keyword: keyword)', refresh)
    require('leave(); self.keyword = keyword; owner = currentSession()', refresh)
    require('rows = snapshot; isShowingRefreshSnapshot = !snapshot.isEmpty', refresh)
    assert refresh.index('let snapshot =') < refresh.index('leave()') < refresh.index('rows = snapshot') < refresh.index('await fetch(page: 1)')
    for token in ['generation += 1', 'busy = false', 'rows = []', 'page = 0', 'hasMore = false', 'isShowingRefreshSnapshot = false']:
        require(token, leave)
    assert fetch.count('guard generation == stamp else { return }') == 2
    assert fetch.count('self.owner == owner, currentSession() == owner, adapter.canRead, !Task.isCancelled') == 2
    require('guard !Task.isCancelled, adapter.canRead else { leave(); return }', fetch)
    require('guard let owner, owner == currentSession() else { leave(); messageKey = \"templateAuthor.signIn\"; return }', fetch)
    require('guard owner == currentSession(), adapter.canRead else { leave(); owner = currentSession(); return }', _body(core, 'public func loadMore()'))
    require('if requested == 1 {\n                rows = result.rows; isShowingRefreshSnapshot = false\n            } else {', fetch)
    require('!existing.contains($0.id)', fetch)
    require('messageKey = "templateAuthor.shelf.moreFailed"; return', fetch)
    require('rows += result.rows', fetch)
    require('page < TemplateOwnShelfPage.maximumPages', fetch)
    require('if error is CancellationError || (error as? URLError)?.code == .cancelled { leave(); return }', fetch)
    require('(requested == 1 && !Self.isTransientRefreshFailure(error)) || Self.invalidatesReadScope(error) { leave() }', fetch)
    require('APIError.httpStatus(let status) = error { return (500...599).contains(status) }', transient)
    require('guard let error = error as? URLError else { return false }', transient)
    # A finite whitelist: cancellation, TLS, malformed requests and unknown errors are excluded.
    assert re.findall(r'\.([A-Za-z]+)', transient) == ['httpStatus', 'contains', 'timedOut', 'cannotFindHost', 'cannotConnectToHost', 'networkConnectionLost', 'dnsLookupFailed', 'notConnectedToInternet', 'contains', 'code']
    require('error is TemplateAuthoringRejection || error is DecodingError', invalidate)
    require('error == .invalidContract || error == .unavailable', invalidate)
    require('case .httpStatus(let status): return !(500...599).contains(status)', invalidate)
    require('default: return true', invalidate)
    ui_refresh = _body(view, 'private func refresh()')
    require('rows = coordinator.shelfReader.refreshSnapshot(keyword: keyword)', ui_refresh)
    require('coordinator.synchronizeSession(); coordinator.cancelShelfReview()', ui_refresh)
    require('if coordinator.canSubmit { await coordinator.loadMine() }', ui_refresh)
    require('if stamp == viewRequest, Task.isCancelled {\n                rows = []; hasMore = false; readSnapshot = false; busy = false', ui_refresh)
    prepare = ui_refresh.split('busy = true; review = nil;', 1)[1].split('await coordinator.shelfReader.refresh(keyword: keyword)', 1)[0]
    assert 'rows = []' not in prepare
    require('readSnapshot = !rows.isEmpty', prepare)
    assert view.count('.disabled(!coordinator.canSubmit || locked || busy || !coordinator.rows.contains(row))') == 2
    assert view.count('.disabled(readSnapshot)') == 2
    require('readSnapshot = coordinator.shelfReader.isShowingRefreshSnapshot', view)
    require('guard !coordinator.shelfReader.isShowingRefreshSnapshot else { return }', _body(view, 'private func prepare('))


class TemplateShelfRefreshSnapshotContracts(unittest.TestCase):
    def test_native_snapshot_source_contract(self):
        assert_refresh_snapshot_contract(read(SHELF), read(MINE))

    def test_targeted_source_negative_controls(self):
        core, view = read(SHELF), read(MINE)
        core_mutations = [
            ('owner != currentSession() || !adapter.canRead', 'false'),
            ('owner != nil, owner == currentSession(), adapter.canRead, self.keyword == keyword, !Task.isCancelled', 'true'),
            ('let snapshot = refreshSnapshot(keyword: keyword)', 'let snapshot: [DiscoveryPlayTemplate] = []'),
            ('rows = snapshot; isShowingRefreshSnapshot = !snapshot.isEmpty', 'rows = snapshot'),
            ('generation += 1', 'generation += 0'),
            ('guard generation == stamp else { return }', 'guard true else { return }'),
            ('currentSession() == owner, adapter.canRead, !Task.isCancelled', 'currentSession() == owner'),
            ('guard !Task.isCancelled, adapter.canRead else', 'guard true else'),
            ('guard let owner, owner == currentSession() else { leave();', 'guard let owner, owner == currentSession() else {'),
            ('guard owner == currentSession(), adapter.canRead else', 'guard owner == currentSession() else'),
            ('rows = result.rows; isShowingRefreshSnapshot = false', 'rows += result.rows; isShowingRefreshSnapshot = false'),
            ('!existing.contains($0.id)', 'true'),
            ('page < TemplateOwnShelfPage.maximumPages', 'true'),
            ('if error is CancellationError || (error as? URLError)?.code == .cancelled', 'if false'),
            ('(requested == 1 && !Self.isTransientRefreshFailure(error)) || Self.invalidatesReadScope(error)', 'false'),
            ('(500...599).contains(status)', '(400...599).contains(status)'),
            ('guard let error = error as? URLError else { return false }', 'guard let error = error as? URLError else { return true }'),
            ('.notConnectedToInternet].contains(error.code)', '.notConnectedToInternet, .cancelled].contains(error.code)'),
            ('error is TemplateAuthoringRejection || error is DecodingError', 'false'),
            ('error == .invalidContract || error == .unavailable', 'false'),
        ]
        view_mutations = [
            ('rows = coordinator.shelfReader.refreshSnapshot(keyword: keyword)', 'rows = []'),
            ('coordinator.synchronizeSession(); coordinator.cancelShelfReview()', 'coordinator.synchronizeSession()'),
            ('if coordinator.canSubmit { await coordinator.loadMine() }', ''),
            ('if stamp == viewRequest, Task.isCancelled', 'if false'),
            ('.disabled(readSnapshot)', ''),
            ('!coordinator.rows.contains(row)', 'false'),
            ('readSnapshot = coordinator.shelfReader.isShowingRefreshSnapshot', 'readSnapshot = false'),
            ('guard !coordinator.shelfReader.isShowingRefreshSnapshot else { return }', ''),
        ]
        for target, changes in [('core', core_mutations), ('view', view_mutations)]:
            for before, after in changes:
                source = core if target == 'core' else view
                self.assertIn(before, source)
                mutated = source.replace(before, after)
                with self.subTest(target=target, mutation=before), self.assertRaises((AssertionError, ValueError)):
                    assert_refresh_snapshot_contract(mutated if target == 'core' else core, mutated if target == 'view' else view)

    def test_authored_apple_cases_preserve_existing_write_and_pagination_tests(self):
        core = read('Tests/CoreTests/TemplateAuthoringHTTPTests.swift')
        for name in ['testOnlyExplicitTransientFailuresRetainSnapshotAndRequireFirstPageRetry',
                     'testRefreshReplacesOverlappingIDsAndValidEmptyClearsSnapshot',
                     'testAuthContractUnknownAndCancellationFailuresClearRefreshSnapshot',
                     'testContinuationAuthAndContractErrorsClearRowsButOverlapRemainsRetryable',
                     'testAlreadyCancelledRefreshClearsSnapshotWithoutDispatch',
                     'testNewKeywordNeverDisplaysPreviousQuerySnapshot',
                     'testSameKeywordNewGenerationRejectsOldSuccessAndError',
                     'testCachedRefreshLifetimeTransitionsAndABAFenceAllLateResults',
                     'testRefreshAtHundredPageBoundaryRestartsAtOneWithoutPage101',
                     'testRefreshSnapshotCannotReplaceHundredRowWritePreflightOrOldReview',
                     'testOverlappingPagePreservesPreviousRowsAndRetriesSamePage',
                     'testLimitCannotIssuePage101', 'testChangedBaselinePreventsWrite',
                     'testUnknownPersistsAfterNewCoordinatorAndMatchingReadback']:
            self.assertIn('func ' + name + '(', core)
        app = read('Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift')
        for name in ['testLoadedReadOnlyRefreshSnapshotSurvives503ThenReplacesAndClears',
                     'testCachedRefreshNeverSurvivesOwnerLeaseABAExpiryOrCancellation',
                     'testCachedSnapshotPreparationClearsRevokedScopeBeforeAnotherRequest']:
            self.assertIn('func ' + name + '(', app)
        self.assertIn('testReadOnlyRefreshRevocationAndReopenPreserveBothPendingJournals', read('Tests/CoreTests/TemplateShelfReadTests.swift'))

    def verify_real_mini_refresh_oracle(self, source_root):
        # Explicit callable, outside default native-only discovery. An absent Mini
        # checkout is never reported as a passing or newly permitted skipped test.
        mini = Path(source_root)
        self.assertEqual(hashlib.sha256((mini/'subpackageMember/mytemplate/mytemplate.js').read_bytes()).hexdigest(), 'b176ad7b5b4edb94083d7dd9a6a7d3b2aff75cf5767f7c6accfd2ee81370b274')
        self.assertEqual(hashlib.sha256((mini/'tests/unit/mytemplate-list-recovery-contract.test.js').read_bytes()).hexdigest(), '1a944849e73703169deb755781a4688ee3c6b8266106c715a1313480f776c59f')
        result = subprocess.run(['node', '--test', 'tests/unit/mytemplate-list-recovery-contract.test.js'], cwd=mini, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        oracle = r'''
const assert = require('node:assert/strict'); let definition; const requests = [], trace = [];
global.getApp = () => ({getRequestErrorMessage:(r,f)=>(r&&(r.msg||r.errMsg))||f,getUserRole:()=> 'user',getUserType:()=> 'user',sendRequest:o=>requests.push(o)});
global.Page = p => {definition=p}; global.wx = {getAccountInfoSync:()=>({miniProgram:{envVersion:'release'}}),navigateTo(){},showModal(){},showToast(){},stopPullDownRefresh(){}};
require('./subpackageMember/mytemplate/mytemplate.js');
const page = Object.assign({},definition,{data:JSON.parse(JSON.stringify(definition.data)),setData(p,cb){Object.assign(this.data,p);if(cb)cb.call(this)}});
function record(stage, ids){assert.deepEqual(page.data.list.map(x=>x.id),ids);trace.push({stage,ids,loading:page.data.loading});}
page.getList();requests[0].success({code:200,data:{rows:[{id:7,title:'Existing'}],total:1}});requests[0].complete();record('loaded',[7]);
page.refreshList();record('pending',[7]);requests[1].fail({errMsg:'network timeout'});requests[1].complete();record('failed',[7]);
page.refreshList();requests[2].success({code:200,data:{rows:[{id:8,title:'Fresh'}],total:1}});requests[2].complete();record('replaced',[8]);
assert.equal(requests.length,3);assert.ok(requests.every(x=>x.url==='/api/template/my-list'&&x.data.pageNum===1&&x.data.pageSize===10));console.log(JSON.stringify(trace));
'''
        result = subprocess.run(['node', '-e', oracle], cwd=mini, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout), [
            {'stage': 'loaded', 'ids': [7], 'loading': False},
            {'stage': 'pending', 'ids': [7], 'loading': True},
            {'stage': 'failed', 'ids': [7], 'loading': False},
            {'stage': 'replaced', 'ids': [8], 'loading': False}])

        return json.loads(result.stdout)
