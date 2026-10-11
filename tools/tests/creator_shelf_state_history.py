"""Exact eight-input admission for display-only shelf state history.

Current product gates read raw sources. This adapter only restores the separately
reviewed historical refresh inputs, after full-bundle raw identity verification.
"""
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REFRESH_INPUTS = ('App/TemplateAuthoringMineView.swift',
 'Core/TemplateAuthoringShelf.swift',
 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift',
 'Tests/ContractChecks/test_template_shelf_read_bridge.py',
 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift')
STATE_EXTRA_INPUTS = ('Resources/Localizable.xcstrings',
 'Tests/ContractChecks/test_template_shelf_state_projection.py',
 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift')
SOURCE_SHA256 = {'App/TemplateAuthoringMineView.swift': ('91d2c740529dd2970568cacfcd68409618c6e2d1d6cda007daccfdb3dc8164d7',
                                         '070653140719b1dd37b8cf5b811c0a6cfef9c66eff13fa06d9a78b6634a4c38f'),
 'Core/TemplateAuthoringShelf.swift': ('3d8865b315f1712f0056d1b376f0f7f2b1aa01e8417dab95f438c200cefe2e91',
                                       'a9261782a98016cf474bbd9a2b2035fd6fbba6bf5ac9bb5682f85c95f4bbb13a'),
 'Resources/Localizable.xcstrings': ('6e9a854e14c29ad90a8b4ed88735e5641d15efc53ca810fb49dc366d3509910a',
                                     '8f552d5a3f34a86c19a370c411a08669dfb4440a15f3b3037cd635595b4ff995'),
 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift': ('7311d093a69f2291048f9f08110ef1425cd884ede1781abb28c037c1b50a2673',
                                                                '7311d093a69f2291048f9f08110ef1425cd884ede1781abb28c037c1b50a2673'),
 'Tests/ContractChecks/test_template_shelf_read_bridge.py': ('c6739456a84e353060b42225dae9b8c2a472d8f080bb831ccd7bb74c39afaec8',
                                                             'c6739456a84e353060b42225dae9b8c2a472d8f080bb831ccd7bb74c39afaec8'),
 'Tests/ContractChecks/test_template_shelf_state_projection.py': (None,
                                                                  '92a11a1874c3c442ff7bf76d62ae4e8331e0d7d589f6d55d919e9a4130180dc4'),
 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift': ('760c57eef41df4f73d89ea5143fd629c68d82ffe1c290a203006371c684e8ee6',
                                                      '760c57eef41df4f73d89ea5143fd629c68d82ffe1c290a203006371c684e8ee6'),
 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift': (None,
                                                                'b2b199d73b7045d4c3de9ce7bc0ea41b10bfc233c6b9c180438fd415d5c99b87')}
INVERSE_DELTAS = {'App/TemplateAuthoringMineView.swift': ((871,
                                          b'    @State private var viewRequest = UUID()\n    @Sta'
                                          b'te private var rows: [DiscoveryPlayTemplate] = []\n  '
                                          b'  @State private var rowStates: [Int: TemplateOwnShe'
                                          b'lfStateProjection] = [:]\n    @State private var mess'
                                          b'ageKey: String?\n    @State private var review: Templ'
                                          b'ateOwnShelfReview?\n',
                                          b'    @State private var viewRequest = UUID()\n    @Sta'
                                          b'te private var rows: [DiscoveryPlayTemplate] = []\n  '
                                          b'  @State private var messageKey: String?\n    @State '
                                          b'private var review: TemplateOwnShelfReview?\n'),
                                         (3059,
                                          b'                    LabeledContent("templateAuthor.s'
                                          b'helf.identity", value: String(row.id))\n             '
                                          b'       if let text = row.description { Text(verbatim'
                                          b': text) }\n                    let state = rowStates['
                                          b'row.id] ?? .unknown\n                    LabeledConte'
                                          b'nt("templateShelfState.personal.title") { Text(Local'
                                          b'izedStringKey(state.personal.rawValue)) }\n          '
                                          b'              .accessibilityIdentifier("templateShel'
                                          b'fState.personal.\\(row.id)")\n                    Labe'
                                          b'ledContent("templateShelfState.market.title") { Text'
                                          b'(LocalizedStringKey(state.market.rawValue)) }\n      '
                                          b'                  .accessibilityIdentifier("template'
                                          b'ShelfState.market.\\(row.id)")\n                    if'
                                          b' let reason = state.marketReason {\n                 '
                                          b'       LabeledContent("templateShelfState.market.fee'
                                          b'dback") { Text(verbatim: reason).textSelection(.enab'
                                          b'led) }\n                            .accessibilityIde'
                                          b'ntifier("templateShelfState.feedback.\\(row.id)")\n   '
                                          b'                 }\n                    Text("templat'
                                          b'eAuthor.existingEditUnavailable").font(.caption).for'
                                          b'egroundStyle(.secondary)\n                    Button('
                                          b'LocalizedStringKey(row.publishStatus == 1 ? "templat'
                                          b'eAuthor.shelf.removeLibrary" : "templateAuthor.shelf'
                                          b'.addLibrary")) {\n',
                                          b'                    LabeledContent("templateAuthor.s'
                                          b'helf.identity", value: String(row.id))\n             '
                                          b'       if let text = row.description { Text(verbatim'
                                          b': text) }\n                    Text(LocalizedStringKe'
                                          b'y(row.status == 1 ? "templateAuthor.published" : row'
                                          b'.status == 2 ? "templateAuthor.underReview" : "templ'
                                          b'ateAuthor.unpublished"))\n                    Text(Lo'
                                          b'calizedStringKey(row.publishStatus == 1 ? "templateA'
                                          b'uthor.shelf.inLibrary" : "templateAuthor.shelf.outLi'
                                          b'brary"))\n                    Text("templateAuthor.ex'
                                          b'istingEditUnavailable").font(.caption).foregroundSty'
                                          b'le(.secondary)\n                    Button(LocalizedS'
                                          b'tringKey(row.publishStatus == 1 ? "templateAuthor.sh'
                                          b'elf.removeLibrary" : "templateAuthor.shelf.addLibrar'
                                          b'y")) {\n'),
                                         (6074,
                                          b'            .onChange(of: sessionRevision) { _, _ in'
                                          b' selectedConfiguration = nil }\n            .onChange'
                                          b'(of: sessionRevision) { _, _ in selectedMember = nil'
                                          b' }\n            .task(id: sessionRevision) { rows = ['
                                          b']; review = nil; rowStates = [:]; await refresh() }\n'
                                          b'            .onDisappear { viewRequest = UUID(); coo'
                                          b'rdinator.shelfReader.leave(); coordinator.leaveShelf'
                                          b'Screen(); rows = []; review = nil; busy = false; row'
                                          b'States = [:] }\n            .sheet(item: $review, onD'
                                          b'ismiss: { coordinator.cancelShelfReview() }) { value'
                                          b' in\n                NavigationStack {\n',
                                          b'            .onChange(of: sessionRevision) { _, _ in'
                                          b' selectedConfiguration = nil }\n            .onChange'
                                          b'(of: sessionRevision) { _, _ in selectedMember = nil'
                                          b' }\n            .task(id: sessionRevision) { rows = ['
                                          b']; review = nil; await refresh() }\n            .onDi'
                                          b'sappear { viewRequest = UUID(); coordinator.shelfRea'
                                          b'der.leave(); coordinator.leaveShelfScreen(); rows = '
                                          b'[]; review = nil; busy = false }\n            .sheet('
                                          b'item: $review, onDismiss: { coordinator.cancelShelfR'
                                          b'eview() }) { value in\n                NavigationStac'
                                          b'k {\n'),
                                         (9714,
                                          b'        coordinator.synchronizeSession(); coordinato'
                                          b'r.shelfReader.synchronizeSession()\n        rows = co'
                                          b'ordinator.shelfReader.rows; hasMore = coordinator.sh'
                                          b'elfReader.hasMore\n        rowStates = coordinator.sh'
                                          b'elfReader.rowStates\n        readSnapshot = coordinat'
                                          b'or.shelfReader.isShowingRefreshSnapshot\n        read'
                                          b'MessageKey = coordinator.shelfReader.messageKey; mes'
                                          b'sageKey = coordinator.shelfMessageKey; locked = coor'
                                          b'dinator.shelfLocked\n',
                                          b'        coordinator.synchronizeSession(); coordinato'
                                          b'r.shelfReader.synchronizeSession()\n        rows = co'
                                          b'ordinator.shelfReader.rows; hasMore = coordinator.sh'
                                          b'elfReader.hasMore\n        readSnapshot = coordinator'
                                          b'.shelfReader.isShowingRefreshSnapshot\n        readMe'
                                          b'ssageKey = coordinator.shelfReader.messageKey; messa'
                                          b'geKey = coordinator.shelfMessageKey; locked = coordi'
                                          b'nator.shelfLocked\n'),
                                         (10786,
                                          b'        defer {\n            if stamp == viewRequest,'
                                          b' Task.isCancelled {\n                rows = []; hasMo'
                                          b're = false; readSnapshot = false; busy = false; rowS'
                                          b'tates = [:]\n            }\n        }\n',
                                          b'        defer {\n            if stamp == viewRequest,'
                                          b' Task.isCancelled {\n                rows = []; hasMo'
                                          b're = false; readSnapshot = false; busy = false\n     '
                                          b'       }\n        }\n'),
                                         (11069,
                                          b'        coordinator.synchronizeSession(); coordinato'
                                          b'r.cancelShelfReview()\n        rows = coordinator.she'
                                          b'lfReader.refreshSnapshot(keyword: keyword)\n        r'
                                          b'owStates = rows.isEmpty ? [:] : coordinator.shelfRea'
                                          b'der.rowStates\n        readSnapshot = !rows.isEmpty\n '
                                          b'       await coordinator.shelfReader.refresh(keyword'
                                          b': keyword)\n',
                                          b'        coordinator.synchronizeSession(); coordinato'
                                          b'r.cancelShelfReview()\n        rows = coordinator.she'
                                          b'lfReader.refreshSnapshot(keyword: keyword)\n        r'
                                          b'eadSnapshot = !rows.isEmpty\n        await coordinato'
                                          b'r.shelfReader.refresh(keyword: keyword)\n')),
 'Core/TemplateAuthoringShelf.swift': ((2570,
                                        b'}\n\n/// Display-only projection of the owned-list rev'
                                        b'iew and marketplace columns.\n/// No action eligibility, '
                                        b'write intent, library identity, or authority is derived '
                                        b'here.\npublic struct TemplateOwnShelfStateProjection: Dec'
                                        b'odable, Equatable {\n    public enum Personal: String'
                                        b' {\n        case draft = "templateShelfState.personal.dra'
                                        b'ft"\n        case approved = "templateShelfState.personal'
                                        b'.approved"\n        case rejected = "templateShelfState.p'
                                        b'ersonal.rejected"\n        case reviewing = "templateShel'
                                        b'fState.personal.reviewing"\n        case unknown = "templ'
                                        b'ateShelfState.personal.unknown"\n    }\n    public enu'
                                        b'm Market: String {\n        case notSubmitted = "template'
                                        b'ShelfState.market.notSubmitted"\n        case reviewing ='
                                        b' "templateShelfState.market.reviewing"\n        case list'
                                        b'ed = "templateShelfState.market.listed"\n        case unl'
                                        b'isted = "templateShelfState.market.unlisted"\n        cas'
                                        b'e rejected = "templateShelfState.market.rejected"\n      '
                                        b'  case unknown = "templateShelfState.market.unknown"\n   '
                                        b' }\n    public let personal: Personal\n    public let '
                                        b'market: Market\n    public let marketReason: String?\n'
                                        b'    /// A missing sidecar is unknown, never evidence of '
                                        b'an absent marketplace record.\n    public static let unkn'
                                        b'own = Self(personal: .unknown, market: .unknown, marketR'
                                        b'eason: nil)\n    private init(personal: Personal, market:'
                                        b' Market, marketReason: String?) {\n        self.personal '
                                        b'= personal; self.market = market; self.marketReason = ma'
                                        b'rketReason\n    }\n    private enum Keys: String, Codi'
                                        b'ngKey {\n        case draftStatus, status, checkStatus, m'
                                        b'arketTemplateId, marketStatus, marketPublishStatus, mark'
                                        b'etReason\n    }\n    public init(from decoder: Decoder'
                                        b') throws {\n        let values = try decoder.container(ke'
                                        b'yedBy: Keys.self)\n        let draft = Self.code(values, '
                                        b'.draftStatus), status = Self.code(values, .status)\n     '
                                        b'   let check = Self.code(values, .checkStatus)\n        i'
                                        b'f draft == 0 { personal = .draft }\n        else if draft'
                                        b' == 1, status == 1, check == 1 { personal = .approved }\n'
                                        b'        else if draft == 1, status == 2 || check == 2 { '
                                        b'personal = .rejected }\n        else if draft == 1, statu'
                                        b's == 0 || check == 0 { personal = .reviewing }\n        e'
                                        b'lse { personal = .unknown }\n        let marketStatus = S'
                                        b'elf.code(values, .marketStatus)\n        let marketPublis'
                                        b'hStatus = Self.code(values, .marketPublishStatus)\n      '
                                        b'  switch Self.marketIdentity(values) {\n        case .abs'
                                        b'ent: market = .notSubmitted\n        case .unknown: marke'
                                        b't = .unknown\n        case .present:\n            if m'
                                        b'arketStatus == 0 { market = .reviewing }\n            els'
                                        b'e if marketStatus == 1, marketPublishStatus == 1 { marke'
                                        b't = .listed }\n            else if marketStatus == 1, mar'
                                        b'ketPublishStatus == 0 { market = .unlisted }\n           '
                                        b' else if marketStatus == 2 { market = .rejected }\n      '
                                        b'      else { market = .unknown }\n        }\n        i'
                                        b'f let reason = try? values.decode(String.self, forKey: .'
                                        b'marketReason),\n           !reason.trimmingCharacters(in:'
                                        b' .whitespacesAndNewlines).isEmpty { marketReason = reaso'
                                        b'n }\n        else { marketReason = nil }\n    }\n    //'
                                        b'/ Exact 0/1/2 or their canonical text only. In particula'
                                        b'r, empty text is not zero.\n    private static func code('
                                        b'_ values: KeyedDecodingContainer<Keys>, _ key: Keys) -> '
                                        b'Int64? {\n        if let value = try? values.decode(Int64'
                                        b'.self, forKey: key), (0...2).contains(value) { return va'
                                        b'lue }\n        guard let text = try? values.decode(String'
                                        b'.self, forKey: key) else { return nil }\n        switch t'
                                        b'ext { case "0": return 0; case "1": return 1; case "2": '
                                        b'return 2; default: return nil }\n    }\n    private en'
                                        b'um MarketIdentity { case absent, present, unknown }\n    '
                                        b'private static func marketIdentity(_ values: KeyedDecodi'
                                        b'ngContainer<Keys>) -> MarketIdentity {\n        guard val'
                                        b'ues.contains(.marketTemplateId) else { return .absent }\n'
                                        b'        if (try? values.decodeNil(forKey: .marketTemplat'
                                        b'eId)) == true { return .absent }\n        if let value = '
                                        b'try? values.decode(Int64.self, forKey: .marketTemplateId'
                                        b') {\n            return value == 0 ? .absent : value > 0 '
                                        b'? .present : .unknown\n        }\n        guard let te'
                                        b'xt = try? values.decode(String.self, forKey: .marketTemp'
                                        b'lateId) else { return .unknown }\n        if text == "0" '
                                        b'{ return .absent }\n        // Source accepts arbitrary-l'
                                        b'ength digit strings. We bound them to the\n        // bac'
                                        b'kend Long domain; an out-of-domain value remains an unkn'
                                        b'own display.\n        guard (1...19).contains(text.utf8.c'
                                        b'ount), let first = text.utf8.first, (49...57).contains(f'
                                        b'irst),\n              text.utf8.dropFirst().allSatisfy({ '
                                        b'(48...57).contains($0) }),\n              let value = Int'
                                        b'64(text), value > 0 else { return .unknown }\n        ret'
                                        b'urn .present\n    }\n}\nprivate struct TemplateOwnShelf'
                                        b'StateEnvelope: Decodable {\n    struct Payload: Decodable'
                                        b' { let rows: [TemplateOwnShelfStateProjection] }\n    let'
                                        b' data: Payload\n}\n\n/// Presentation-only member shelf'
                                        b'. Never used as mutation authority or absence proof.\npub'
                                        b'lic struct TemplateOwnShelfPage {\n',
                                        b'}\n\n/// Presentation-only member shelf. Never used as'
                                        b' mutation authority or absence proof.\npublic struct Temp'
                                        b'lateOwnShelfPage {\n'),
                                       (7553,
                                        b'    public let rows: [DiscoveryPlayTemplate]\n    public '
                                        b'let total: Int?\n    public let rowStates: [Int: Template'
                                        b'OwnShelfStateProjection]\n    public static func request('
                                        b'page: Int, keyword: String) throws -> TemplateAuthoringR'
                                        b'equest {\n        guard (1...maximumPages).contains(page)'
                                        b' else { throw TemplateAuthoringError.invalidContract }\n',
                                        b'    public let rows: [DiscoveryPlayTemplate]\n    public '
                                        b'let total: Int?\n    public static func request(page: Int'
                                        b', keyword: String) throws -> TemplateAuthoringRequest {\n'
                                        b'        guard (1...maximumPages).contains(page) else { t'
                                        b'hrow TemplateAuthoringError.invalidContract }\n'),
                                       (8759,
                                        b'              Set(rows.map(\\.id)).count == rows.count el'
                                        b'se { throw TemplateAuthoringError.invalidContract }\n    '
                                        b'    let total = payload["total"]?.integer\n        // Dec'
                                        b'ode optional display columns from original bytes, avoidi'
                                        b'ng Double\n        // roundtripping of backend Long value'
                                        b's. Malformed optional columns are unknown.\n        let s'
                                        b'tates = try JSONDecoder().decode(TemplateOwnShelfStateEn'
                                        b'velope.self, from: data).data.rows\n        guard states.'
                                        b'count == rows.count else { throw TemplateAuthoringError.'
                                        b'invalidContract }\n        let rowStates = Dictionary(uni'
                                        b'queKeysWithValues: zip(rows.map(\\.id), states))\n    '
                                        b'    return .init(rows: rows, total: total.flatMap { $0 >'
                                        b'= 0 ? $0 : nil }, rowStates: rowStates)\n    }\n}\n',
                                        b'              Set(rows.map(\\.id)).count == rows.count el'
                                        b'se { throw TemplateAuthoringError.invalidContract }\n    '
                                        b'    let total = payload["total"]?.integer\n        return'
                                        b' .init(rows: rows, total: total.flatMap { $0 >= 0 ? $0 :'
                                        b' nil })\n    }\n}\n'),
                                       (9694,
                                        b'    private var generation = 0\n    public private(set) v'
                                        b'ar rows: [DiscoveryPlayTemplate] = []\n    public private'
                                        b'(set) var rowStates: [Int: TemplateOwnShelfStateProjecti'
                                        b'on] = [:]\n    public private(set) var keyword = ""\n '
                                        b'   public private(set) var page = 0\n',
                                        b'    private var generation = 0\n    public private(set) v'
                                        b'ar rows: [DiscoveryPlayTemplate] = []\n    public private'
                                        b'(set) var keyword = ""\n    public private(set) var page '
                                        b'= 0\n'),
                                       (10446,
                                        b'        leave(); owner = currentSession()\n    }\n    '
                                        b'public func leave() { generation += 1; busy = false; row'
                                        b's = []; page = 0; hasMore = false; messageKey = nil; isS'
                                        b'howingRefreshSnapshot = false; rowStates = [:] }\n    ///'
                                        b' A same-scope display snapshot only. It cannot authorize'
                                        b' a shelf mutation.\n    public func refreshSnapshot(keywo'
                                        b'rd: String) -> [DiscoveryPlayTemplate] {\n',
                                        b'        leave(); owner = currentSession()\n    }\n    '
                                        b'public func leave() { generation += 1; busy = false; row'
                                        b's = []; page = 0; hasMore = false; messageKey = nil; isS'
                                        b'howingRefreshSnapshot = false }\n    /// A same-scope dis'
                                        b'play snapshot only. It cannot authorize a shelf mutation'
                                        b'.\n    public func refreshSnapshot(keyword: String) -> [D'
                                        b'iscoveryPlayTemplate] {\n'),
                                       (11008,
                                        b'    public func refresh(keyword: String = "") async {\n  '
                                        b'      let snapshot = refreshSnapshot(keyword: keyword)\n '
                                        b'       let stateSnapshot = snapshot.isEmpty ? [:] : rowS'
                                        b'tates\n        leave(); self.keyword = keyword; owner = c'
                                        b'urrentSession()\n        rows = snapshot; isShowingRefres'
                                        b'hSnapshot = !snapshot.isEmpty\n        rowStates = stateS'
                                        b'napshot\n        await fetch(page: 1)\n    }\n',
                                        b'    public func refresh(keyword: String = "") async {\n  '
                                        b'      let snapshot = refreshSnapshot(keyword: keyword)\n '
                                        b'       leave(); self.keyword = keyword; owner = currentS'
                                        b'ession()\n        rows = snapshot; isShowingRefreshSnapsh'
                                        b'ot = !snapshot.isEmpty\n        await fetch(page: 1)\n'
                                        b'    }\n'),
                                       (12869,
                                        b'                rows += result.rows\n            }\n  '
                                        b'          // No suspension between committing rows and t'
                                        b'heir display-only sidecars.\n            if requested == '
                                        b'1 { rowStates = result.rowStates }\n            else { ro'
                                        b'wStates.merge(result.rowStates) { _, fresh in fresh } }\n'
                                        b'            page = requested\n            let continuatio'
                                        b'n = !result.rows.isEmpty && (result.total.map { rows.cou'
                                        b'nt < $0 } ?? (result.rows.count == TemplateOwnShelfPage.'
                                        b'pageSize))\n',
                                        b'                rows += result.rows\n            }\n  '
                                        b'          page = requested\n            let continuation '
                                        b'= !result.rows.isEmpty && (result.total.map { rows.count'
                                        b' < $0 } ?? (result.rows.count == TemplateOwnShelfPage.pa'
                                        b'geSize))\n')),
 'Resources/Localizable.xcstrings': ((3491752,
                                      b'    "templateShelfState.market.feedback": {\n      "extra'
                                      b'ctionState": "manual",\n      "localizations": {\n        '
                                      b'"en": {\n          "stringUnit": {\n            "state": "'
                                      b'translated",\n            "value": "Marketplace feedback"'
                                      b'\n          }\n        },\n        "zh-Hans": {\n       '
                                      b'   "stringUnit": {\n            "state": "translated",\n  '
                                      b'          "value": "\xe5\xb9\xbf\xe5\x9c\xba\xe5\x8f'
                                      b'\x8d\xe9\xa6\x88"\n          }\n        }\n      }\n    '
                                      b'},\n    "templateShelfState.market.listed": {\n      "extr'
                                      b'actionState": "manual",\n      "localizations": {\n       '
                                      b' "en": {\n          "stringUnit": {\n            "state": '
                                      b'"translated",\n            "value": "Listed in marketplac'
                                      b'e"\n          }\n        },\n        "zh-Hans": {\n     '
                                      b'     "stringUnit": {\n            "state": "translated",\n'
                                      b'            "value": "\xe5\xb9\xbf\xe5\x9c\xba'
                                      b'\xe5\xb7\xb2\xe4\xb8\x8a\xe6\x9e\xb6"\n          }\n     '
                                      b'   }\n      }\n    },\n    "templateShelfState.market.notSu'
                                      b'bmitted": {\n      "extractionState": "manual",\n      "lo'
                                      b'calizations": {\n        "en": {\n          "stringUnit": '
                                      b'{\n            "state": "translated",\n            "value"'
                                      b': "Not submitted to marketplace"\n          }\n        },\n'
                                      b'        "zh-Hans": {\n          "stringUnit": {\n         '
                                      b'   "state": "translated",\n            "value": "'
                                      b'\xe6\x9c\xaa\xe6\x8f\x90\xe4\xba\xa4\xe5\xb9\xbf'
                                      b'\xe5\x9c\xba"\n          }\n        }\n      }\n    },\n  '
                                      b'  "templateShelfState.market.rejected": {\n      "extract'
                                      b'ionState": "manual",\n      "localizations": {\n        "e'
                                      b'n": {\n          "stringUnit": {\n            "state": "tr'
                                      b'anslated",\n            "value": "Marketplace resubmissio'
                                      b'n required"\n          }\n        },\n        "zh-Hans"'
                                      b': {\n          "stringUnit": {\n            "state": "tran'
                                      b'slated",\n            "value": "\xe5\xb9\xbf\xe5\x9c'
                                      b'\xba\xe9\x9c\x80\xe9\x87\x8d\xe6\x96\xb0\xe6\x8f'
                                      b'\x90\xe4\xba\xa4"\n          }\n        }\n      }\n    '
                                      b'},\n    "templateShelfState.market.reviewing": {\n      "e'
                                      b'xtractionState": "manual",\n      "localizations": {\n    '
                                      b'    "en": {\n          "stringUnit": {\n            "state'
                                      b'": "translated",\n            "value": "Marketplace revie'
                                      b'w pending"\n          }\n        },\n        "zh-Hans":'
                                      b' {\n          "stringUnit": {\n            "state": "trans'
                                      b'lated",\n            "value": "\xe5\xb9\xbf\xe5\x9c\xba'
                                      b'\xe5\xae\xa1\xe6\xa0\xb8\xe4\xb8\xad"\n          }\n     '
                                      b'   }\n      }\n    },\n    "templateShelfState.market.title'
                                      b'": {\n      "extractionState": "manual",\n      "localizat'
                                      b'ions": {\n        "en": {\n          "stringUnit": {\n     '
                                      b'       "state": "translated",\n            "value": "Temp'
                                      b'late marketplace"\n          }\n        },\n        "zh-Han'
                                      b's": {\n          "stringUnit": {\n            "state": "tr'
                                      b'anslated",\n            "value": "\xe6\xa8\xa1'
                                      b'\xe6\x9d\xbf\xe5\xb9\xbf\xe5\x9c\xba"\n          }\n     '
                                      b'   }\n      }\n    },\n    "templateShelfState.market.unkno'
                                      b'wn": {\n      "extractionState": "manual",\n      "localiz'
                                      b'ations": {\n        "en": {\n          "stringUnit": {\n   '
                                      b'         "state": "translated",\n            "value": "Ma'
                                      b'rketplace status unknown"\n          }\n        },\n       '
                                      b' "zh-Hans": {\n          "stringUnit": {\n            "sta'
                                      b'te": "translated",\n            "value": "\xe5\xb9\xbf'
                                      b'\xe5\x9c\xba\xe7\x8a\xb6\xe6\x80\x81\xe5\xbe\x85'
                                      b'\xe7\xa1\xae\xe8\xae\xa4"\n          }\n        }\n      '
                                      b'}\n    },\n    "templateShelfState.market.unlisted": {\n   '
                                      b'   "extractionState": "manual",\n      "localizations": {'
                                      b'\n        "en": {\n          "stringUnit": {\n            "'
                                      b'state": "translated",\n            "value": "Unlisted fro'
                                      b'm marketplace"\n          }\n        },\n        "zh-Hans":'
                                      b' {\n          "stringUnit": {\n            "state": "trans'
                                      b'lated",\n            "value": "\xe5\xb9\xbf\xe5\x9c\xba'
                                      b'\xe5\xb7\xb2\xe4\xb8\x8b\xe6\x9e\xb6"\n          }\n     '
                                      b'   }\n      }\n    },\n    "templateShelfState.personal.app'
                                      b'roved": {\n      "extractionState": "manual",\n      "loca'
                                      b'lizations": {\n        "en": {\n          "stringUnit": {\n'
                                      b'            "state": "translated",\n            "value": '
                                      b'"Personal review approved"\n          }\n        },\n      '
                                      b'  "zh-Hans": {\n          "stringUnit": {\n            "st'
                                      b'ate": "translated",\n            "value": "\xe4\xb8'
                                      b'\xaa\xe4\xba\xba\xe5\xae\xa1\xe6\xa0\xb8\xe9\x80'
                                      b'\x9a\xe8\xbf\x87"\n          }\n        }\n      }\n    '
                                      b'},\n    "templateShelfState.personal.draft": {\n      "ext'
                                      b'ractionState": "manual",\n      "localizations": {\n      '
                                      b'  "en": {\n          "stringUnit": {\n            "state":'
                                      b' "translated",\n            "value": "Draft"\n          }\n'
                                      b'        },\n        "zh-Hans": {\n          "stringUnit": '
                                      b'{\n            "state": "translated",\n            "value"'
                                      b': "\xe8\x8d\x89\xe7\xa8\xbf"\n          }\n        }\n   '
                                      b'   }\n    },\n    "templateShelfState.personal.rejected": '
                                      b'{\n      "extractionState": "manual",\n      "localization'
                                      b's": {\n        "en": {\n          "stringUnit": {\n        '
                                      b'    "state": "translated",\n            "value": "Persona'
                                      b'l review rejected"\n          }\n        },\n        "zh-Ha'
                                      b'ns": {\n          "stringUnit": {\n            "state": "t'
                                      b'ranslated",\n            "value": "\xe4\xb8\xaa\xe4\xba\xba'
                                      b'\xe5\xae\xa1\xe6\xa0\xb8\xe6\x9c\xaa\xe9\x80\x9a'
                                      b'\xe8\xbf\x87"\n          }\n        }\n      }\n    },\n  '
                                      b'  "templateShelfState.personal.reviewing": {\n      "extr'
                                      b'actionState": "manual",\n      "localizations": {\n       '
                                      b' "en": {\n          "stringUnit": {\n            "state": '
                                      b'"translated",\n            "value": "Under personal revie'
                                      b'w"\n          }\n        },\n        "zh-Hans": {\n     '
                                      b'     "stringUnit": {\n            "state": "translated",\n'
                                      b'            "value": "\xe4\xb8\xaa\xe4\xba\xba'
                                      b'\xe5\xae\xa1\xe6\xa0\xb8\xe4\xb8\xad"\n          }\n     '
                                      b'   }\n      }\n    },\n    "templateShelfState.personal.tit'
                                      b'le": {\n      "extractionState": "manual",\n      "localiz'
                                      b'ations": {\n        "en": {\n          "stringUnit": {\n   '
                                      b'         "state": "translated",\n            "value": "Pe'
                                      b'rsonal review"\n          }\n        },\n        "zh-Hans":'
                                      b' {\n          "stringUnit": {\n            "state": "trans'
                                      b'lated",\n            "value": "\xe4\xb8\xaa\xe4\xba\xba'
                                      b'\xe5\xae\xa1\xe6\xa0\xb8"\n          }\n        }\n      '
                                      b'}\n    },\n    "templateShelfState.personal.unknown": {\n  '
                                      b'    "extractionState": "manual",\n      "localizations": '
                                      b'{\n        "en": {\n          "stringUnit": {\n            '
                                      b'"state": "translated",\n            "value": "Personal re'
                                      b'view status unknown"\n          }\n        },\n        "zh-'
                                      b'Hans": {\n          "stringUnit": {\n            "state": '
                                      b'"translated",\n            "value": "\xe7\x8a\xb6\xe6'
                                      b'\x80\x81\xe5\xbe\x85\xe7\xa1\xae\xe8\xae\xa4"\n          }'
                                      b'\n        }\n      }\n    },\n    "templateStory.derived'
                                      b'Summary": {',
                                      b'    "templateStory.derivedSummary": {'),)}

def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def restore_state_bytes(name, raw):
    if name not in INVERSE_DELTAS or digest(raw) != SOURCE_SHA256[name][1]:
        raise ValueError('Unreviewed shelf state postimage')
    restored = raw
    for offset, after, before in reversed(INVERSE_DELTAS[name]):
        if restored.count(after) != 1 or restored[offset:offset + len(after)] != after:
            raise ValueError('Missing, repeated or moved shelf state delta')
        restored = restored[:offset] + before + restored[offset + len(after):]
    if digest(restored) != SOURCE_SHA256[name][0]:
        raise ValueError('Shelf state inverse did not restore full original bytes')
    return restored


def historical_pre_shelf_state_sources(*, root=ROOT):
    root = Path(root)
    sources = {}
    for name in REFRESH_INPUTS:
        try:
            sources[name] = (root / name).read_bytes()
        except OSError as error:
            raise ValueError('Missing or unreadable shelf refresh history input: ' + name) from error
    # The original five-file fixture domain remains guarded by the original
    # refresh adapter. Any state-era input opts into complete group validation.
    present = {name: (root / name).exists() or (root / name).is_symlink()
               for name in STATE_EXTRA_INPUTS}
    if not any(present.values()):
        return sources
    if not present[STATE_EXTRA_INPUTS[0]]:
        raise ValueError('Missing or unreadable shelf state catalog')
    for name, exists in present.items():
        if exists:
            try:
                sources[name] = (root / name).read_bytes()
            except OSError as error:
                raise ValueError('Unreadable shelf state input: ' + name) from error
    current = all(name in sources and digest(sources[name]) == pair[1]
                  for name, pair in SOURCE_SHA256.items())
    if current:
        for name in INVERSE_DELTAS:
            sources[name] = restore_state_bytes(name, sources[name])
        return {name: sources[name] for name in REFRESH_INPUTS}
    # Legacy catalog with no new test files is legal only alongside a complete
    # legacy refresh group; the original adapter validates that group next.
    if (not any(present[name] for name in STATE_EXTRA_INPUTS[1:])
            and digest(sources[STATE_EXTRA_INPUTS[0]]) == SOURCE_SHA256[STATE_EXTRA_INPUTS[0]][0]):
        return {name: sources[name] for name in REFRESH_INPUTS}
    raise ValueError('Mixed, incomplete or unreviewed shelf state source bundle')
