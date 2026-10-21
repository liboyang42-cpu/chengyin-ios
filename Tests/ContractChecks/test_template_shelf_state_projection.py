"""Source-only guards. Node runs the preserved Mini oracle separately; no Swift is interpreted."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import unittest
from test_template_shelf_read_bridge import assert_refresh_snapshot_contract

ROOT = Path(__file__).resolve().parents[2]
PARAMS = {'BASE_CORE_SHA': '3d8865b315f1712f0056d1b376f0f7f2b1aa01e8417dab95f438c200cefe2e91',
 'BASE_VIEW_SHA': '91d2c740529dd2970568cacfcd68409618c6e2d1d6cda007daccfdb3dc8164d7',
 'BASE_CATALOG_SHA': '6e9a854e14c29ad90a8b4ed88735e5641d15efc53ca810fb49dc366d3509910a',
 'PROJECTION_SHA': 'de84c821e29d567ad04fe6e79071a180f032fd906af0aadf292582931d898b9a',
 'DISPLAY_SHA': '03b1d163168f8b417f4d5a26b550ce0a3a13c9f3db7432e29e12750394bc423e',
 'CATALOG_NEXT_KEY': 'templateStory.derivedSummary',
 'LABELS': {'templateShelfState.market.feedback': {'en': 'Marketplace feedback', 'zh-Hans': '广场反馈'},
            'templateShelfState.market.listed': {'en': 'Listed in marketplace', 'zh-Hans': '广场已上架'},
            'templateShelfState.market.notSubmitted': {'en': 'Not submitted to marketplace',
                                                       'zh-Hans': '未提交广场'},
            'templateShelfState.market.rejected': {'en': 'Marketplace resubmission required',
                                                   'zh-Hans': '广场需重新提交'},
            'templateShelfState.market.reviewing': {'en': 'Marketplace review pending',
                                                    'zh-Hans': '广场审核中'},
            'templateShelfState.market.title': {'en': 'Template marketplace', 'zh-Hans': '模板广场'},
            'templateShelfState.market.unknown': {'en': 'Marketplace status unknown',
                                                  'zh-Hans': '广场状态待确认'},
            'templateShelfState.market.unlisted': {'en': 'Unlisted from marketplace',
                                                   'zh-Hans': '广场已下架'},
            'templateShelfState.personal.approved': {'en': 'Personal review approved',
                                                     'zh-Hans': '个人审核通过'},
            'templateShelfState.personal.draft': {'en': 'Draft', 'zh-Hans': '草稿'},
            'templateShelfState.personal.rejected': {'en': 'Personal review rejected',
                                                     'zh-Hans': '个人审核未通过'},
            'templateShelfState.personal.reviewing': {'en': 'Under personal review',
                                                      'zh-Hans': '个人审核中'},
            'templateShelfState.personal.title': {'en': 'Personal review', 'zh-Hans': '个人审核'},
            'templateShelfState.personal.unknown': {'en': 'Personal review status unknown',
                                                    'zh-Hans': '状态待确认'}}}
CORE = 'Core/TemplateAuthoringShelf.swift'
VIEW = 'App/TemplateAuthoringMineView.swift'
CATALOG = 'Resources/Localizable.xcstrings'
SWIFT_TESTS = 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'

def digest(text): return hashlib.sha256(text.encode()).hexdigest()
def read(path):
    if path == CATALOG:
        from Tests.ContractChecks.test_category_roam_registration import creator_catalog_input
        return creator_catalog_input((ROOT / path).read_bytes(), ROOT).decode()
    return (ROOT / path).read_text()
def section(text, first, last):
    start = text.index(first)
    return text[start:text.index(last, start)]

def assert_projection_contract(core, view, catalog):
    assert_refresh_snapshot_contract(core, view)
    projection = section(core, '/// Display-only projection', '/// Presentation-only member shelf.')
    assert digest(projection) == PARAMS['PROJECTION_SHA'], 'new projection bytes changed'
    assert 'case draftStatus, status, checkStatus, marketTemplateId, marketStatus, marketPublishStatus, marketReason' in projection
    assert 'status == 1, check == 1' in projection
    assert 'status == 2 || check == 2' in projection
    assert projection.index('personal = .rejected') < projection.index('personal = .reviewing')
    assert 'case .absent: market = .notSubmitted' in projection
    assert 'case .unknown: market = .unknown' in projection
    assert 'marketStatus == 1, marketPublishStatus == 1' in projection
    assert 'marketStatus == 1, marketPublishStatus == 0' in projection
    assert 'values.decode(Int64.self' in projection and 'Int64(text)' in projection
    assert 'text.utf8.dropFirst().allSatisfy' in projection
    assert 'case "0": return 0; case "1": return 1; case "2": return 2; default: return nil' in projection
    for forbidden in ['.integer', 'canSubmit', 'canToggle', 'publish_status', 'TemplateAuthoringRequest', 'submit(', 'URLSession']:
        assert forbidden not in projection, forbidden
    assert 'decode(TemplateOwnShelfStateEnvelope.self, from: data).data.rows' in core
    assert 'Dictionary(uniqueKeysWithValues: zip(rows.map(\\.id), states))' in core
    assert 'guard states.count == rows.count' in core
    assert 'let stateSnapshot = snapshot.isEmpty ? [:] : rowStates' in core
    assert 'let factSnapshot = snapshot.isEmpty ? [:] : cardFacts' in core
    assert core.index('let snapshot = refreshSnapshot(') < core.index('let stateSnapshot =') < core.index('let factSnapshot =') < core.index('leave(); self.keyword = keyword; owner = currentSession()')
    assert 'rowStates = stateSnapshot' in core
    assert 'cardFacts = factSnapshot' in core
    assert 'isShowingRefreshSnapshot = false; rowStates = [:]; cardFacts = [:] }' in core
    commit = section(core, '            if requested == 1 {', '            page = requested')
    assert 'if requested == 1 { rowStates = result.rowStates }' in commit
    assert 'if requested == 1 { cardFacts = result.cardFacts }' in commit
    assert 'rowStates.merge(result.rowStates) { _, fresh in fresh }' in commit
    assert 'cardFacts.merge(result.cardFacts) { _, fresh in fresh }' in commit
    assert commit.index('!existing.contains($0.id)') < commit.index('rowStates.merge(')
    assert 'await ' not in commit, 'rows and sidecars must commit without suspension'
    display = section(view, '                    let state = rowStates[row.id]', '                    Text("templateAuthor.existingEditUnavailable")')
    assert digest(display) == PARAMS['DISPLAY_SHA'], 'display-only block changed'
    assert '@State private var rowStates: [Int: TemplateOwnShelfStateProjection] = [:]' in view
    assert 'rowStates = coordinator.shelfReader.rowStates' in view
    assert 'cardFacts = coordinator.shelfReader.cardFacts' in view
    assert 'rowStates = rows.isEmpty ? [:] : coordinator.shelfReader.rowStates' in view
    assert 'cardFacts = rows.isEmpty ? [:] : coordinator.shelfReader.cardFacts' in view
    assert 'TemplateOwnShelfCardSection(facts: cardFacts[row.id], state: state, rowID: row.id)' in display
    assert 'templateAuthor.shelf.inLibrary' in display and 'templateAuthor.shelf.outLibrary' in display
    assert 'row.publishStatus == 1' in display
    assert 'rows = []; cardFacts = [:]; review = nil; rowStates = [:]; await refresh()' in view
    assert 'busy = false; rowStates = [:]; cardFacts = [:] }' in view
    assert 'rows = []; hasMore = false; readSnapshot = false; busy = false; rowStates = [:]' in view
    assert 'Text(verbatim: reason)' in display
    assert 'row.status == 1 ? "templateAuthor.published"' not in view
    assert '/market-submit' not in core + view
    parsed = json.loads(catalog)['strings']
    labels = {k: {lang: v['stringUnit']['value'] for lang, v in value['localizations'].items()}
              for k, value in parsed.items() if k.startswith('templateShelfState.')}
    assert labels == PARAMS['LABELS'], 'state labels must be exact and bilingual'
    # Exact inverse of only this additive change preserves all previous logic,
    # including both legacy writes and the already-reviewed refresh snapshot.
    restored = core.replace(projection, '', 1)
    for addition in [
        '    public let rowStates: [Int: TemplateOwnShelfStateProjection]\n',
        '    public private(set) var rowStates: [Int: TemplateOwnShelfStateProjection] = [:]\n',
        '    public let cardFacts: [Int: TemplateOwnShelfCardFacts]\n',
        '    public private(set) var cardFacts: [Int: TemplateOwnShelfCardFacts] = [:]\n',
        '        let stateSnapshot = snapshot.isEmpty ? [:] : rowStates\n',
        '        let factSnapshot = snapshot.isEmpty ? [:] : cardFacts\n',
        '        rowStates = stateSnapshot\n',
        '        cardFacts = factSnapshot\n',
        '            // No suspension between committing rows and their display-only sidecars.\n            if requested == 1 { rowStates = result.rowStates }\n            else { rowStates.merge(result.rowStates) { _, fresh in fresh } }\n            if requested == 1 { cardFacts = result.cardFacts }\n            else { cardFacts.merge(result.cardFacts) { _, fresh in fresh } }\n',
    ]:
        assert restored.count(addition) == 1, addition
        restored = restored.replace(addition, '', 1)
    restored = restored.replace('isShowingRefreshSnapshot = false; rowStates = [:]; cardFacts = [:] }', 'isShowingRefreshSnapshot = false }', 1)
    added_decode = section(restored, '        // Decode optional display columns from original bytes,', '\n    }\n}')
    restored = restored.replace(added_decode, '        return .init(rows: rows, total: total.flatMap { $0 >= 0 ? $0 : nil })', 1)
    assert digest(restored) == PARAMS['BASE_CORE_SHA'], 'existing Core bytes changed'
    restored = view.replace(display,
        '                    Text(LocalizedStringKey(row.status == 1 ? "templateAuthor.published" : row.status == 2 ? "templateAuthor.underReview" : "templateAuthor.unpublished"))\n'
        '                    Text(LocalizedStringKey(row.publishStatus == 1 ? "templateAuthor.shelf.inLibrary" : "templateAuthor.shelf.outLibrary"))\n', 1)
    for addition in ['    @State private var rowStates: [Int: TemplateOwnShelfStateProjection] = [:]\n',
                     '    @State private var cardFacts: [Int: TemplateOwnShelfCardFacts] = [:]\n',
                     '        rowStates = coordinator.shelfReader.rowStates\n',
                     '        cardFacts = coordinator.shelfReader.cardFacts\n',
                     '        rowStates = rows.isEmpty ? [:] : coordinator.shelfReader.rowStates\n',
                     '        cardFacts = rows.isEmpty ? [:] : coordinator.shelfReader.cardFacts\n',
                     '            .onChange(of: selectedMember) { previous, next in\n                guard previous != nil, next == nil else { return }\n                Task { await refresh() }\n            }\n',
                     '                            if value.action == .remove { TemplateOwnShelfDeleteReviewCopy(title: value.title) }\n']:
        assert restored.count(addition) == 1
        restored = restored.replace(addition, '', 1)
    restored = restored.replace('cardFacts = [:]; ', '', 1)
    restored = restored.replace('review = nil; rowStates = [:]; await refresh()', 'review = nil; await refresh()', 1)
    restored = restored.replace('busy = false; rowStates = [:]', 'busy = false')
    restored = restored.replace('; cardFacts = [:]', '')
    assert digest(restored) == PARAMS['BASE_VIEW_SHA'], 'existing View bytes changed'
    first = '    "' + min(PARAMS['LABELS']) + '": {'
    last = '    "' + PARAMS['CATALOG_NEXT_KEY'] + '": {'
    inserted = section(catalog, first, last)
    assert digest(catalog.replace(inserted, '', 1)) == PARAMS['BASE_CATALOG_SHA'], 'existing catalog bytes changed'


class TemplateShelfStateProjectionContracts(unittest.TestCase):
    def test_source_projection_atomic_lifetime_and_exact_inverse(self):
        assert_projection_contract(read(CORE), read(VIEW), read(CATALOG))

    def test_new_state_data_cannot_enter_shared_dto_writer_or_journal(self):
        for path in ['Core/DiscoveryContracts.swift', 'Core/TemplateAuthoringCoordinator.swift',
                     'Core/TemplateAuthoringService.swift', 'Core/TemplateAuthoringStorage.swift',
                     'Core/TemplateAuthoringContract.swift', 'Core/TemplateAuthoringWireRequestBuilder.swift']:
            text = read(path)
            self.assertNotIn('TemplateOwnShelfStateProjection', text)
            self.assertNotIn('rowStates', text)
            self.assertNotIn('/market-submit', text)
        core = read(CORE)
        pending = core.split('/// Display-only projection')[0]
        self.assertNotIn('marketStatus', pending)
        self.assertIn('guard acknowledged else { return false }', pending)
        self.assertIn('rows.count < 100 && matches.isEmpty', pending)
        self.assertIn('"pageNum": "1", "pageSize": "100"', read('Core/TemplateAuthoringContract.swift'))

    def test_same_id_partial_decoding_and_lifetime_runtime_cases_are_authored_not_executed(self):
        tests = read(SWIFT_TESTS)
        names = re.findall(r'func (test\w+)\(', tests)
        self.assertEqual(len(names), 20)
        for name in ['testActualMiniCounterexamplesSeparatePersonalAndMarketplaceStates',
                     'testMalformedOptionalColumnsNeverInvalidateAnOtherwiseLegalRow',
                     'testPartialMetadataDecodingDoesNotDropOtherFieldsOrOtherRows',
                     'testExistingBaseDTOValidationIsNotRelaxedByTolerantDisplayColumns',
                     'testMarketIdentityLongBoundsAreReadFromOriginalBytesWithoutCoercion',
                     'testSameIDsAndEqualBaseRowsStillReplaceChangedDisplayStates',
                     'testTransientRefreshRetainsStatesWithRowsAndRetryReplacesBoth',
                     'testOverlappingContinuationCannotPartiallyReplaceOrAppendStates',
                     'testAuthContractAndCancellationErrorsClearEveryCachedState',
                     'testOldSuccessAndErrorCannotOverwriteNewSameIDState',
                     'testScopeTransitionsABARevocationLeaveAndCancelRetireStates',
                     'testDisplayMetadataNeverChangesSharedDTOOrAcknowledgesPendingMutation']:
            self.assertIn(name, names)
        self.assertIn('XCTAssertEqual(reader.rows, rows); XCTAssertNotEqual(reader.rowStates, states)', tests)
        self.assertIn('Set(reader.rows.map(\\.id)), Set(reader.rowStates.keys)', tests)
        self.assertIn('func testRefreshAtHundredPageBoundaryRestartsAtOneWithoutPage101(', read('Tests/CoreTests/TemplateAuthoringHTTPTests.swift'))
        self.assertIn('func testCachedRefreshNeverSurvivesOwnerLeaseABAExpiryOrCancellation(', read('Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'))

    def test_source_negative_controls(self):
        core, view, catalog = read(CORE), read(VIEW), read(CATALOG)
        changes = [
            ('core', 'status == 1, check == 1', 'status == 1'),
            ('core', 'status == 2 || check == 2', 'status == 0 || check == 0'),
            ('core', 'if draft == 0 { personal = .draft }', 'if draft == 1 { personal = .draft }'),
            ('core', 'Self.code(values, .marketPublishStatus)', 'Self.code(values, .status)'),
            ('core', 'case .unknown: market = .unknown', 'case .unknown: market = .listed'),
            ('core', 'case .absent: market = .notSubmitted', 'case .absent: market = .listed'),
            ('core', 'marketStatus == 1, marketPublishStatus == 1', 'marketStatus == 1'),
            ('core', 'values.decode(Int64.self', 'values.decode(Double.self'),
            ('core', 'case "0": return 0;', 'case "", "0": return 0;'),
            ('core', '(1...19).contains(text.utf8.count)', 'true'),
            ('core', '(49...57).contains(first)', '(48...57).contains(first)'),
            ('core', 'let value = Int64(text)', 'let value = Int64(text.trimmingCharacters(in: .whitespacesAndNewlines))'),
            ('core', 'from: data).data.rows', 'from: JSONEncoder().encode(raw)).data.rows'),
            ('core', 'guard states.count == rows.count', 'guard true'),
            ('core', 'zip(rows.map(\\.id), states)', 'zip(rows.reversed().map(\\.id), states)'),
            ('core', 'let stateSnapshot = snapshot.isEmpty ? [:] : rowStates', 'let stateSnapshot = rowStates'),
            ('core', 'rowStates = stateSnapshot', 'rowStates = [:]'),
            ('core', 'isShowingRefreshSnapshot = false; rowStates = [:]; cardFacts = [:] }', 'isShowingRefreshSnapshot = false }'),
            ('core', 'let factSnapshot = snapshot.isEmpty ? [:] : cardFacts', 'let factSnapshot = cardFacts'),
            ('core', 'cardFacts = factSnapshot', 'cardFacts = [:]'),
            ('core', 'if requested == 1 { cardFacts = result.cardFacts }', 'if requested == 1 { cardFacts.merge(result.cardFacts) { old, _ in old } }'),
            ('core', 'cardFacts.merge(result.cardFacts) { _, fresh in fresh }', 'cardFacts = result.cardFacts'),
            ('core', 'if requested == 1 { rowStates = result.rowStates }', 'if requested == 1 { rowStates.merge(result.rowStates) { old, _ in old } }'),
            ('core', 'rowStates.merge(result.rowStates) { _, fresh in fresh }', 'rowStates = result.rowStates'),
            ('core', '            page = requested', '            await Task.yield()\n            page = requested'),
            ('core', 'public let marketReason: String?', 'public let marketReason: String?\n    func submit() {}'),
            ('view', '@State private var rowStates:', 'private var rowStates:'),
            ('view', 'rowStates = coordinator.shelfReader.rowStates', 'rowStates = [:]'),
            ('view', 'rowStates = rows.isEmpty ? [:] : coordinator.shelfReader.rowStates', 'rowStates = coordinator.shelfReader.rowStates'),
            ('view', 'cardFacts = rows.isEmpty ? [:] : coordinator.shelfReader.cardFacts', 'cardFacts = coordinator.shelfReader.cardFacts'),
            ('view', 'guard previous != nil, next == nil else { return }', 'guard true else { return }'),
            ('view', 'if value.action == .remove { TemplateOwnShelfDeleteReviewCopy(title: value.title) }', ''),
            ('view', 'review = nil; rowStates = [:]; await refresh()', 'review = nil; await refresh()'),
            ('view', 'busy = false; rowStates = [:]', 'busy = false'),
            ('view', 'Text(verbatim: reason)', 'Text(reason)'),
            ('view', 'state.market.rawValue', 'state.personal.rawValue'),
            ('view', 'let state = rowStates[row.id] ?? .unknown', 'let state = rowStates[7] ?? .unknown'),
            ('view', '.disabled(readSnapshot)', ''),
            ('catalog', 'Marketplace status unknown', 'Marketplace approved'),
        ]
        for target, before, after in changes:
            source = {'core': core, 'view': view, 'catalog': catalog}[target]
            self.assertIn(before, source)
            changed = source.replace(before, after)
            with self.subTest(target=target, mutation=before), self.assertRaises((AssertionError, ValueError, KeyError)):
                assert_projection_contract(changed if target == 'core' else core,
                                           changed if target == 'view' else view,
                                           changed if target == 'catalog' else catalog)

    def verify_real_mini_oracle(self, source_root):
        """Explicit caller only: absence is a failure, never a newly allowed skip."""
        source = Path(source_root)
        files = {
            'utils/template-market.js': '3d37244ac008c2adbc345c71b785d923d3f9f2801e3a25d5961b6cefc90d8dae',
            'subpackageMember/mytemplate/mytemplate.js': 'b176ad7b5b4edb94083d7dd9a6a7d3b2aff75cf5767f7c6accfd2ee81370b274',
            'subpackageMember/mytemplate/mytemplate.wxml': 'cb398ac46e418f277ee01bb0a7836876d9e5a6717cd2c1426b5f78644b8db45a',
        }
        for path, expected in files.items():
            self.assertEqual(hashlib.sha256((source / path).read_bytes()).hexdigest(), expected)
        script = r"""
const assert = require('node:assert/strict');
const {marketView} = require('./utils/template-market.js');
const counterexamples = [
 {row:{id:41,draftStatus:1,status:2,checkStatus:2,publishStatus:1,marketTemplateId:null},personal:'个人审核未通过',market:'未提交广场'},
 {row:{id:42,draftStatus:1,status:1,checkStatus:1,publishStatus:0,marketTemplateId:900,marketStatus:1,marketPublishStatus:1},personal:'个人审核通过',market:'广场已上架'}
];
for (const c of counterexamples) { const v=marketView(c.row); assert.equal(v._statusText,c.personal); assert.equal(v._marketText,c.market); }
let matrix=0;
for (const draft of [0,1,2,3,'0','1','2',null]) for (const status of [0,1,2,3,'0','1','2',null]) for (const check of [0,1,2,3,'0','1','2',null]) {
 const same=(x,n)=>x===n||x===String(n); const t={draftStatus:draft,status,checkStatus:check};
 const expected=same(draft,0)?'草稿':same(draft,1)&&same(status,1)&&same(check,1)?'个人审核通过':same(draft,1)&&(same(status,2)||same(check,2))?'个人审核未通过':same(draft,1)&&(same(status,0)||same(check,0))?'个人审核中':'状态待确认';
 assert.equal(marketView(t)._statusText,expected); matrix++;
}
const numericAndText = [0,1,2,3,'0','1','2',null];
for (const id of [undefined,null,0,'0',99,'99','01',-1,true,'',{},[]]) for (const status of numericAndText) for (const publish of numericAndText) {
 const t={marketTemplateId:id,marketStatus:status,marketPublishStatus:publish,publishStatus:0};
 const a=marketView(t), b=marketView({...t,publishStatus:1}); assert.equal(a._marketText,b._marketText); matrix++;
}
const stricter=[{field:'marketTemplateId',value:'9223372036854775808',mini:marketView({marketTemplateId:'9223372036854775808',marketStatus:1,marketPublishStatus:1})._marketText,nativePolicy:'unknown: outside backend Long domain'},
 {field:'marketReason',value:'   ',miniPolicy:'WXML truthy text renders',nativePolicy:'whitespace-only feedback omitted'}];
console.log(JSON.stringify({counterexamples,matrixCases:matrix,intentionalDifferences:stricter}));
"""
        result = subprocess.run(['node', '-e', script], cwd=source, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        value = json.loads(result.stdout)
        self.assertEqual(value['matrixCases'], 1280)
        return value
