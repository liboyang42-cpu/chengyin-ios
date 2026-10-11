"""P099 global category recovery: raw native source contracts only.

No Mini checkout or external-source environment is read by this permanent gate.
The authored Swift tests exercise the reused controller, not rendered SwiftUI.
Historical gates receive only fail-closed exact prior inputs; new predicates below
always inspect unprojected shipping sources. Swift/Apple/UI execution is separate.
"""
import hashlib
from pathlib import Path
import unittest
from Tests.ContractChecks.test_category_roam_registration import pre_roam_category_inputs, pre_roam_category_contract_bytes

ROOT = Path(__file__).resolve().parents[2]
VIEW_SHA256 = '5f679b73132b5bf9aed78a94964eab58b11c37335dba7d0acec940415462ac78'
OLD_VIEW_SHA256 = '0aafd543944d3ad919da43ca44e107accdd01a7a42c268522addcc5f2dabd8a5'
VIEW_INVERSE_SPANS = [(b'import SwiftUI\n\n@MainActor struct GlobalSearchView<Destination: View>: View {\n    @Environment(\\.scenePhase) private var scenePhase\n    let reader: any SearchMapReading\n    var historyNamespace: String? = nil\n    var publicMerchant = PublicMerchantHomeContext()\n    var onSignIn: (() -> Void)? = nil\n    let destination: (SearchMapDestination) -> Destination\n    @State private var filter = GlobalSearchQuery()\n    @State private var categoryRecovery = SearchMapCategoryRecovery()\n    @State private var categoryPresentationID = UUID()\n    @State private var filterPresentationID = UUID()\n    @State private var filterSheetVisible = false\n    @State private var retainedResults = GlobalSearchRetainedResults()\n    @State private var isVisible = false\n    @State private var issue: String?\n', b'import SwiftUI\n\n@MainActor struct GlobalSearchView<Destination: View>: View {\n    let reader: any SearchMapReading\n    var historyNamespace: String? = nil\n    var publicMerchant = PublicMerchantHomeContext()\n    var onSignIn: (() -> Void)? = nil\n    let destination: (SearchMapDestination) -> Destination\n    @State private var filter = GlobalSearchQuery()\n    @State private var categories: [DiscoveryCategory] = []\n    @State private var categoryFailed = false\n    @State private var retainedResults = GlobalSearchRetainedResults()\n    @State private var isVisible = false\n    @State private var issue: String?\n'), (b'    @State private var showsFilters = false\n    @State private var history: [String] = []\n    @State private var historyFailure = false\n    @State private var preparedOwner: ReadOwner?\n    private let historyStore = SearchMapLocalHistory()\n\n', b'    @State private var showsFilters = false\n    @State private var history: [String] = []\n    @State private var historyFailure = false\n    @State private var categoryGate = SearchMapQueryGate()\n    @State private var preparedOwner: ReadOwner?\n    private let historyStore = SearchMapLocalHistory()\n\n'), (b'                    TextField("searchMap.placeholder", text: Binding(get: { filter.keyword }, set: setKeyword)).textInputAutocapitalization(.never)\n                        .submitLabel(.search).onSubmit { Task { await search() } }\n                        .accessibilityIdentifier("searchMap.keyword")\n                    Button { openFilters() } label: { Label("searchMap.filters", systemImage: "line.3.horizontal.decrease") }\n                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("searchMap.filters")\n                }.padding(12).background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))\n                Button("searchMap.search") { Task { await search() } }\n', b'                    TextField("searchMap.placeholder", text: Binding(get: { filter.keyword }, set: setKeyword)).textInputAutocapitalization(.never)\n                        .submitLabel(.search).onSubmit { Task { await search() } }\n                        .accessibilityIdentifier("searchMap.keyword")\n                    Button { showsFilters = true } label: { Label("searchMap.filters", systemImage: "line.3.horizontal.decrease") }\n                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("searchMap.filters")\n                }.padding(12).background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))\n                Button("searchMap.search") { Task { await search() } }\n'), (b'        }\n        .appNavigationTitle("searchMap.title")\n        .sheet(isPresented: $showsFilters) {\n            let presentationID = filterPresentationID\n            let context = categoryRecovery.context(for: categoryOwner)\n            let applyContext = categoryRecovery.presentationContext(for: categoryOwner)\n            SearchMapFilterSheet(filter: filter, categories: categories, categoryFailed: categoryFailed,\n                                 categoryLoading: categoryLoading, categoryLoaded: categoryLoaded,\n                                 retryCategories: context.map { captured in {\n                                     guard showsFilters, filterSheetVisible, presentationID == filterPresentationID else { return }\n                                     _ = categoryRecovery.retry(in: captured)\n                                 } }) { next in\n                guard showsFilters, filterSheetVisible, presentationID == filterPresentationID,\n                      let applyContext, categoryRecovery.acceptsPresentation(applyContext) else { return }\n                applyFilter(next)\n            }\n            .onAppear {\n                guard showsFilters, presentationID == filterPresentationID, categoryRecovery.owns(categoryOwner) else { return }\n                filterSheetVisible = true; updateCategoryPresentation()\n            }\n            .onDisappear {\n                guard presentationID == filterPresentationID, categoryRecovery.owns(categoryOwner) else { return }\n                filterSheetVisible = false; updateCategoryPresentation()\n            }\n        }\n        .task(id: readOwner) { await prepare() }\n        .onChange(of: categoryOwner) { _, _ in updateCategoryPresentation() }\n        .onChange(of: scenePhase) { _, _ in updateCategoryPresentation() }\n        .onChange(of: showsFilters) { _, visible in\n            if !visible { filterSheetVisible = false }\n            updateCategoryPresentation()\n        }\n        .onAppear { isVisible = true; categoryPresentationID = UUID(); updateCategoryPresentation() }\n        .onDisappear {\n            isVisible = false; retainedResults.cancelPending(); loading = false\n            categoryRecovery.update(reader: reader, presentationID: nil, active: false)\n        }\n    }\n    private var categoryOwner: SearchMapCategoryRecovery.Owner { .init(reader: reader) }\n    private var categories: [DiscoveryCategory] { categoryRecovery.owns(categoryOwner) ? categoryRecovery.categories : [] }\n    private var categoryFailed: Bool { categoryRecovery.owns(categoryOwner) && categoryRecovery.phase == .failed }\n    private var categoryLoading: Bool { categoryRecovery.owns(categoryOwner) && categoryRecovery.phase == .loading }\n    private var categoryLoaded: Bool { categoryRecovery.owns(categoryOwner) && categoryRecovery.phase == .loaded }\n    private func openFilters() {\n        filterPresentationID = UUID(); filterSheetVisible = false; showsFilters = true\n        updateCategoryPresentation()\n    }\n    private func updateCategoryPresentation() {\n        // The page and sheet share the directory, never a draft or search request.\n        // Switching surfaces retires callbacks; a settled directory survives reopening.\n        let presentationID = showsFilters ? (filterSheetVisible ? filterPresentationID : nil) : categoryPresentationID\n        categoryRecovery.update(reader: reader, presentationID: presentationID,\n                                active: isVisible && scenePhase == .active)\n        if let context = categoryRecovery.context(for: categoryOwner) {\n            categoryRecovery.loadIfNeeded(in: context)\n        }\n    }\n    @ViewBuilder private var suggestions: some View {\n        let context = categoryRecovery.context(for: categoryOwner)\n        if !history.isEmpty {\n            HStack {\n                Text("searchMap.history").font(.headline)\n', b'        }\n        .appNavigationTitle("searchMap.title")\n        .sheet(isPresented: $showsFilters) {\n            SearchMapFilterSheet(filter: filter, categories: categories, categoryFailed: categoryFailed) { next in\n                applyFilter(next)\n            }\n        }\n        .task(id: readOwner) { await prepare() }\n        .onAppear { isVisible = true }\n        .onDisappear { isVisible = false; retainedResults.cancelPending(); categoryGate.invalidate(); loading = false }\n    }\n    @ViewBuilder private var suggestions: some View {\n        if !history.isEmpty {\n            HStack {\n                Text("searchMap.history").font(.headline)\n'), (b'            }\n        }\n        Text("searchMap.categories").font(.headline)\n        if categoryLoading {\n            ProgressView("searchMap.loading").accessibilityIdentifier("globalSearch.category.loading")\n        } else if categoryFailed {\n            SearchMapIssue(key: "searchMap.categoryFailed") {\n                guard !showsFilters, let context else { return }\n                _ = categoryRecovery.retry(in: context)\n            }\n        }\n        LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], spacing: 12) {\n            ForEach(categories) { category in\n                Button {\n                    guard !showsFilters, let context, categoryRecovery.accepts(context) else { return }\n                    var next = filter; next.categoryID = category.id; applyFilter(next)\n                } label: {\n                    Text(verbatim: category.name).frame(maxWidth: .infinity, minHeight: 44)\n', b'            }\n        }\n        Text("searchMap.categories").font(.headline)\n        if categoryFailed { SearchMapIssue(key: "searchMap.categoryFailed") { Task { await prepare(force: true) } } }\n        LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], spacing: 12) {\n            ForEach(categories) { category in\n                Button {\n                    var next = filter; next.categoryID = category.id; applyFilter(next)\n                } label: {\n                    Text(verbatim: category.name).frame(maxWidth: .infinity, minHeight: 44)\n'), (b'        invalidate(); filter.keyword = value\n    }\n    private func invalidate() { retainedResults.invalidate(); issue = nil; loading = false; selectedKind = nil }\n    private func prepare() async {\n        guard !Task.isCancelled else { return }\n        if preparedOwner != readOwner {\n            preparedOwner = readOwner; invalidate()\n            history = historyStore.read(namespace: historyNamespace); historyFailure = historyStore.failed\n        }\n        updateCategoryPresentation()\n    }\n    private func search() async {\n        let query = filter\n', b'        invalidate(); filter.keyword = value\n    }\n    private func invalidate() { retainedResults.invalidate(); issue = nil; loading = false; selectedKind = nil }\n    private func prepare(force: Bool = false) async {\n        if preparedOwner != readOwner {\n            preparedOwner = readOwner; invalidate(); categories = []; categoryFailed = false\n            history = historyStore.read(namespace: historyNamespace); historyFailure = historyStore.failed\n        }\n        guard reader.isConfigured, force || categories.isEmpty else { return }\n        let ticket = categoryGate.begin(scope: reader.scope)\n        do {\n            let value = try await reader.categories()\n            guard categoryGate.accepts(ticket, scope: reader.scope) else { return }; categories = value; categoryFailed = false\n        } catch {\n            guard categoryGate.accepts(ticket, scope: reader.scope) else { return }; categoryFailed = true\n        }\n    }\n    private func search() async {\n        let query = filter\n')]
def exact_inverse(raw, expected, previous, spans):
    if hashlib.sha256(raw).hexdigest() != expected:
        raise AssertionError('Unreviewed global category input')
    result = raw
    for current, old in spans:
        if result.count(current) != 1:
            raise AssertionError('Inverse span is not unique')
        result = result.replace(current, old, 1)
    if hashlib.sha256(result).hexdigest() != previous:
        raise AssertionError('Historical bytes differ')
    return result


def project_pre_global_category_view(raw):
    return exact_inverse(raw, VIEW_SHA256, OLD_VIEW_SHA256, VIEW_INVERSE_SPANS)


def section(text, start, end):
    if text.count(start) != 1 or text.count(end) != 1:
        return ''
    return text.split(start, 1)[1].split(end, 1)[0]


def contract(view):
    required = {
        'shared_recovery': '@State private var categoryRecovery = SearchMapCategoryRecovery()',
        'owner_mask': 'categoryRecovery.owns(categoryOwner) ? categoryRecovery.categories : []',
        'owner_source': 'private var categoryOwner: SearchMapCategoryRecovery.Owner { .init(reader: reader) }',
        'loading_wiring': 'categoryLoading: categoryLoading, categoryLoaded: categoryLoaded,',
        'captured_retry': 'retryCategories: context.map { captured in {',
        'exact_retry': '_ = categoryRecovery.retry(in: captured)',
        'sheet_lifetime': 'guard showsFilters, filterSheetVisible, presentationID == filterPresentationID else { return }',
        'apply_lifetime': 'let applyContext, categoryRecovery.acceptsPresentation(applyContext) else { return }',
        'local_apply': 'let applyContext = categoryRecovery.presentationContext(for: categoryOwner)',
        'owner_observation': '.onChange(of: categoryOwner) { _, _ in updateCategoryPresentation() }',
        'scene_observation': '.onChange(of: scenePhase) { _, _ in updateCategoryPresentation() }',
        'foreground': 'active: isVisible && scenePhase == .active)',
        'retire_departure': 'categoryRecovery.update(reader: reader, presentationID: nil, active: false)',
        'new_presentation': 'filterPresentationID = UUID(); filterSheetVisible = false; showsFilters = true',
        'surface_fence': 'let presentationID = showsFilters ? (filterSheetVisible ? filterPresentationID : nil) : categoryPresentationID',
        'close_fence': 'if !visible { filterSheetVisible = false }',
        'old_appear_fence': 'guard showsFilters, presentationID == filterPresentationID, categoryRecovery.owns(categoryOwner) else { return }',
        'old_disappear_fence': 'guard presentationID == filterPresentationID, categoryRecovery.owns(categoryOwner) else { return }',
        'home_retry': 'guard !showsFilters, let context else { return }',
        'home_selection': 'guard !showsFilters, let context, categoryRecovery.accepts(context) else { return }',
    }
    failures = [key for key, marker in required.items() if view.count(marker) != 1]
    for legacy in ['@State private var categories:', '@State private var categoryFailed', 'categoryGate', 'reader.categories()', 'prepare(force:']:
        if legacy in view: failures.append('legacy_category_path')
    update = section(view, '    private func updateCategoryPresentation()', '    @ViewBuilder private var suggestions:')
    if not update: failures.append('missing_update')
    for marker in ['search()', 'applyFilter(', 'filter =', 'filter.categoryID', 'historyStore', 'retainedResults.', 'selectManualArea', 'citySearch', 'nearby(', 'showsFilters =', 'filterPresentationID =', '.id(']:
        if marker in update: failures.append('category_side_effect')
    retry = section(view, 'retryCategories: context.map { captured in {', '                                 } }) { next in')
    home = section(view, 'SearchMapIssue(key: "searchMap.categoryFailed") {', '        LazyVGrid(')
    for block in [retry, home]:
        if not block: failures.append('missing_retry')
        for marker in ['search()', 'applyFilter(', 'Task', 'prepare(', 'filter =', 'historyStore', 'citySearch', 'nearby(', 'loadIfNeeded(']:
            if marker in block: failures.append('retry_side_effect')
    if 'categoryRecovery.loadIfNeeded(in: context)' not in update:
        failures.append('initial_read')
    if view.count('categoryRecovery.retry(in:') != 2:
        failures.append('retry_entry_count')
    return failures


class GlobalSearchCategoryRecoveryContracts(unittest.TestCase):
    def setUp(self):
        self.raw = (ROOT / 'App/GlobalSearchView.swift').read_bytes()
        self.view = self.raw.decode()

    def test_raw_shipping_source_satisfies_forward_contract(self):
        self.assertEqual(contract(self.view), [])
        self.assertEqual(hashlib.sha256(self.raw).hexdigest(), VIEW_SHA256)

    def test_actual_prior_global_source_fails_same_forward_contract(self):
        old = project_pre_global_category_view(self.raw)
        self.assertIn('captured_retry', contract(old.decode()))
        self.assertIn('owner_mask', contract(old.decode()))
        self.assertIn('legacy_category_path', contract(old.decode()))

    def test_each_owner_lifetime_and_rendered_callback_guard_has_negative_control(self):
        markers = [
            ('categoryRecovery.owns(categoryOwner) ? categoryRecovery.categories : []', 'categoryRecovery.categories', 'owner_mask'),
            ('retryCategories: context.map { captured in {', 'retryCategories: {', 'captured_retry'),
            ('_ = categoryRecovery.retry(in: captured)', '_ = categoryRecovery.retry(in: categoryRecovery.context(for: categoryOwner)!)', 'exact_retry'),
            ('guard showsFilters, filterSheetVisible, presentationID == filterPresentationID else { return }', '', 'sheet_lifetime'),
            ('let applyContext, categoryRecovery.acceptsPresentation(applyContext) else { return }', 'true else { return }', 'apply_lifetime'),
            ('let applyContext = categoryRecovery.presentationContext(for: categoryOwner)', 'let applyContext = categoryRecovery.context(for: categoryOwner)', 'local_apply'),
            ('.onChange(of: categoryOwner) { _, _ in updateCategoryPresentation() }', '', 'owner_observation'),
            ('.onChange(of: scenePhase) { _, _ in updateCategoryPresentation() }', '', 'scene_observation'),
            ('active: isVisible && scenePhase == .active)', 'active: true)', 'foreground'),
            ('categoryRecovery.update(reader: reader, presentationID: nil, active: false)', '', 'retire_departure'),
            ('filterPresentationID = UUID(); filterSheetVisible = false; showsFilters = true', 'showsFilters = true', 'new_presentation'),
            ('if !visible { filterSheetVisible = false }', '', 'close_fence'),
            ('guard !showsFilters, let context, categoryRecovery.accepts(context) else { return }', '', 'home_selection'),
            ('guard !showsFilters, let context else { return }', '', 'home_retry'),
            ('guard showsFilters, presentationID == filterPresentationID, categoryRecovery.owns(categoryOwner) else { return }', '', 'old_appear_fence'),
            ('guard presentationID == filterPresentationID, categoryRecovery.owns(categoryOwner) else { return }', '', 'old_disappear_fence'),
        ]
        for marker, change, reason in markers:
            with self.subTest(reason=reason):
                self.assertEqual(self.view.count(marker), 1)
                broken = self.view.replace(marker, change, 1)
                self.assertIn(reason, contract(broken))

    def test_search_map_apply_history_and_query_side_effect_mutants_are_rejected(self):
        for inserted in ['Task { await search() }', 'applyFilter(filter)', 'filter = GlobalSearchQuery()',
                         'historyStore.clear(namespace: historyNamespace)', 'reader.citySearch(query)', 'reader.nearby(area: area)']:
            for marker in ['_ = categoryRecovery.retry(in: captured)', 'categoryRecovery.loadIfNeeded(in: context)']:
                with self.subTest(inserted=inserted, marker=marker):
                    broken = self.view.replace(marker, marker + '; ' + inserted, 1)
                    self.assertTrue({'retry_side_effect', 'category_side_effect'} & set(contract(broken)))

    def test_full_raw_global_inverse_are_exact_and_fail_closed(self):
        for path, project, previous in [
            ('App/GlobalSearchView.swift', project_pre_global_category_view, OLD_VIEW_SHA256),
        ]:
            raw = (ROOT / path).read_bytes()
            old = project(raw)
            self.assertEqual(hashlib.sha256(old).hexdigest(), previous)
            for changed in [old, raw + b'\n', raw.replace(b'\n', b'\r\n'), raw[:-1], raw + raw]:
                with self.assertRaises(AssertionError): project(changed)
            # One XOR-1 mutation at every byte position, not all 255 possibilities.
            for offset in range(len(raw)):
                with self.assertRaises(AssertionError):
                    project(raw[:offset] + bytes([raw[offset] ^ 1]) + raw[offset + 1:])

    def test_each_inverse_span_is_unique_and_cannot_be_removed_or_duplicated(self):
        for path, project, spans in [('App/GlobalSearchView.swift', project_pre_global_category_view, VIEW_INVERSE_SPANS)]:
            raw = (ROOT / path).read_bytes()
            for current, old in spans:
                self.assertEqual(raw.count(current), 1)
                for altered in [raw.replace(current, b'', 1), raw + current, raw.replace(current, old, 1)]:
                    with self.assertRaises(AssertionError): project(altered)

    def test_reviewed_helper_sheet_services_and_remote_explorer_are_pinned(self):
        expected = {'Core/SearchMapReading.swift': '34c67b5893b5ebba2eec8fdfc468a9b1662f4b94f86936d63d755385954d9aad', 'App/SearchMapFilterSheet.swift': 'd805599b752fcd104e40b382fb30d5bc96b9f8f27622766bfaefeed402c07b54', 'App/SearchMapExplorerView.swift': '8ff7a9df03d1c1cf821ad279b1ba3897af79548127857784942472fafa5c4558', 'App/SessionGlobalSearchView.swift': 'b9524fe70d54d995cfb847fade325d635ecd5c3b6c76b82bfd1b645725e2f47e', 'Core/SearchMapService.swift': '449f21a53d8b75592aa82b06c404b3107752fb37176d366fc27c43b463835445', 'Core/SearchMapContracts.swift': '6489eec7ecf8598b569554f2475fc4a0b20cc652408364d8dbeefa46db3c97f7', 'Tests/CoreTests/SearchMapCategoryRecoveryTests.swift': '4f7ed5b79dd4929b5eb828c53e1a07826e1a8b6ff78a09c0f55148faa24a4dad'}
        for path, digest in expected.items():
            with self.subTest(path=path):
                self.assertEqual(hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), digest)

    def test_recovery_does_not_reset_selected_query_or_recreate_filter_drafts(self):
        self.assertNotIn('.id(', self.view)
        old = project_pre_global_category_view(self.raw).decode()
        for start, end in [('    private func applyFilter(', '    private func prepare('),
                           ('    private func search()', None)]:
            a = self.view.split(start, 1)[1]; b = old.split(start, 1)[1]
            if end: a = a.split(end, 1)[0]; b = b.split(end, 1)[0]
            self.assertEqual(a, b)
        sheet = (ROOT / 'App/SearchMapFilterSheet.swift').read_text()
        self.assertIn('@State private var draft: GlobalSearchQuery', sheet)
        self.assertIn('.tag(Optional(selectedID))', sheet)
        self.assertNotIn('.onChange(of: categories)', sheet)

    def test_phase_flags_require_current_owner_and_keep_empty_distinct(self):
        for name, phase in [('Failed', 'failed'), ('Loading', 'loading'), ('Loaded', 'loaded')]:
            self.assertIn('private var category' + name + ': Bool { categoryRecovery.owns(categoryOwner) && categoryRecovery.phase == .' + phase + ' }', self.view)
        sheet = (ROOT / 'App/SearchMapFilterSheet.swift').read_text()
        self.assertIn('} else if categoryLoaded && categories.isEmpty {', sheet)

    def test_existing_helper_rejects_reader_identity_configuration_auth_area_and_aba(self):
        core = (ROOT / 'Core/SearchMapReading.swift').read_text().split('public final class SearchMapCategoryRecovery', 1)[1]
        for marker in ['readerID = ObjectIdentifier(reader); scope = reader.scope',
                       'configured = reader.isConfigured; authenticated = reader.isAuthenticated',
                       'manualAreaRevision = reader.manualAreaRevision',
                       'return owner == current && Owner(reader: reader) == current',
                       'generation = UUID(); task?.cancel(); task = nil; pending = nil',
                       'self.pending == requestID, self.accepts(context)',
                       'pending == nil, accepts(context)', '} catch is CancellationError {']:
            self.assertIn(marker, core)

    def test_page_sheet_transition_swift_cases_are_authored_not_claimed_executed(self):
        swift = (ROOT / 'Tests/CoreTests/GlobalSearchCategoryRecoveryTests.swift').read_text()
        for name in ['testPageFailureRecoversInSheetWithoutChangingQueryOrDraft',
                     'testSurfaceSwitchRejectsOldRetryAndNonCooperativeCompletion',
                     'testCloseReopenKeepsSelectedMissingCategoryAndSettledEmptyDirectory',
                     'testForegroundResumeRetiresOldCallbackWithoutResettingDraft',
                     'testSameScopeReaderReplacementRejectsOldPageAndSheetActions',
                     'testUnconfiguredSheetMayApplyLocalDraftButCannotReadCategories']:
            self.assertIn('func ' + name + '(', swift)
        self.assertIn('CheckedContinuation<[DiscoveryCategory], Error>', swift)

    def test_ci_discovers_this_public_gate_without_private_source(self):
        runner = (ROOT / 'tools/run_static_checks.py').read_text()
        workflow = (ROOT / '.github/workflows/native-ios.yml').read_text()
        self.assertIn("'contracts': {'directory': 'Tests/ContractChecks', 'pattern': 'test_*.py'}", runner)
        self.assertIn('tools/run_static_checks.py', workflow)
        self.assertTrue(Path(__file__).name.startswith('test_'))



# This independent remote batch restores its actual three-file predecessor.
SOURCE_INVERSES = {'App/GlobalSearchView.swift': {'before': '0aafd543944d3ad919da43ca44e107accdd01a7a42c268522addcc5f2dabd8a5', 'after': '5f679b73132b5bf9aed78a94964eab58b11c37335dba7d0acec940415462ac78', 'spans': [(b'import SwiftUI\n\n@MainActor struct GlobalSearchView<Destination: View>: View {\n    @Environment(\\.scenePhase) private var scenePhase\n    let reader: any SearchMapReading\n    var historyNamespace: String? = nil\n    var publicMerchant = PublicMerchantHomeContext()\n    var onSignIn: (() -> Void)? = nil\n    let destination: (SearchMapDestination) -> Destination\n    @State private var filter = GlobalSearchQuery()\n    @State private var categoryRecovery = SearchMapCategoryRecovery()\n    @State private var categoryPresentationID = UUID()\n    @State private var filterPresentationID = UUID()\n    @State private var filterSheetVisible = false\n    @State private var retainedResults = GlobalSearchRetainedResults()\n    @State private var isVisible = false\n    @State private var issue: String?\n', b'import SwiftUI\n\n@MainActor struct GlobalSearchView<Destination: View>: View {\n    let reader: any SearchMapReading\n    var historyNamespace: String? = nil\n    var publicMerchant = PublicMerchantHomeContext()\n    var onSignIn: (() -> Void)? = nil\n    let destination: (SearchMapDestination) -> Destination\n    @State private var filter = GlobalSearchQuery()\n    @State private var categories: [DiscoveryCategory] = []\n    @State private var categoryFailed = false\n    @State private var retainedResults = GlobalSearchRetainedResults()\n    @State private var isVisible = false\n    @State private var issue: String?\n'), (b'    @State private var showsFilters = false\n    @State private var history: [String] = []\n    @State private var historyFailure = false\n    @State private var preparedOwner: ReadOwner?\n    private let historyStore = SearchMapLocalHistory()\n\n', b'    @State private var showsFilters = false\n    @State private var history: [String] = []\n    @State private var historyFailure = false\n    @State private var categoryGate = SearchMapQueryGate()\n    @State private var preparedOwner: ReadOwner?\n    private let historyStore = SearchMapLocalHistory()\n\n'), (b'                    TextField("searchMap.placeholder", text: Binding(get: { filter.keyword }, set: setKeyword)).textInputAutocapitalization(.never)\n                        .submitLabel(.search).onSubmit { Task { await search() } }\n                        .accessibilityIdentifier("searchMap.keyword")\n                    Button { openFilters() } label: { Label("searchMap.filters", systemImage: "line.3.horizontal.decrease") }\n                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("searchMap.filters")\n                }.padding(12).background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))\n                Button("searchMap.search") { Task { await search() } }\n', b'                    TextField("searchMap.placeholder", text: Binding(get: { filter.keyword }, set: setKeyword)).textInputAutocapitalization(.never)\n                        .submitLabel(.search).onSubmit { Task { await search() } }\n                        .accessibilityIdentifier("searchMap.keyword")\n                    Button { showsFilters = true } label: { Label("searchMap.filters", systemImage: "line.3.horizontal.decrease") }\n                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("searchMap.filters")\n                }.padding(12).background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))\n                Button("searchMap.search") { Task { await search() } }\n'), (b'        }\n        .appNavigationTitle("searchMap.title")\n        .sheet(isPresented: $showsFilters) {\n            let presentationID = filterPresentationID\n            let context = categoryRecovery.context(for: categoryOwner)\n            let applyContext = categoryRecovery.presentationContext(for: categoryOwner)\n            SearchMapFilterSheet(filter: filter, categories: categories, categoryFailed: categoryFailed,\n                                 categoryLoading: categoryLoading, categoryLoaded: categoryLoaded,\n                                 retryCategories: context.map { captured in {\n                                     guard showsFilters, filterSheetVisible, presentationID == filterPresentationID else { return }\n                                     _ = categoryRecovery.retry(in: captured)\n                                 } }) { next in\n                guard showsFilters, filterSheetVisible, presentationID == filterPresentationID,\n                      let applyContext, categoryRecovery.acceptsPresentation(applyContext) else { return }\n                applyFilter(next)\n            }\n            .onAppear {\n                guard showsFilters, presentationID == filterPresentationID, categoryRecovery.owns(categoryOwner) else { return }\n                filterSheetVisible = true; updateCategoryPresentation()\n            }\n            .onDisappear {\n                guard presentationID == filterPresentationID, categoryRecovery.owns(categoryOwner) else { return }\n                filterSheetVisible = false; updateCategoryPresentation()\n            }\n        }\n        .task(id: readOwner) { await prepare() }\n        .onChange(of: categoryOwner) { _, _ in updateCategoryPresentation() }\n        .onChange(of: scenePhase) { _, _ in updateCategoryPresentation() }\n        .onChange(of: showsFilters) { _, visible in\n            if !visible { filterSheetVisible = false }\n            updateCategoryPresentation()\n        }\n        .onAppear { isVisible = true; categoryPresentationID = UUID(); updateCategoryPresentation() }\n        .onDisappear {\n            isVisible = false; retainedResults.cancelPending(); loading = false\n            categoryRecovery.update(reader: reader, presentationID: nil, active: false)\n        }\n    }\n    private var categoryOwner: SearchMapCategoryRecovery.Owner { .init(reader: reader) }\n    private var categories: [DiscoveryCategory] { categoryRecovery.owns(categoryOwner) ? categoryRecovery.categories : [] }\n    private var categoryFailed: Bool { categoryRecovery.owns(categoryOwner) && categoryRecovery.phase == .failed }\n    private var categoryLoading: Bool { categoryRecovery.owns(categoryOwner) && categoryRecovery.phase == .loading }\n    private var categoryLoaded: Bool { categoryRecovery.owns(categoryOwner) && categoryRecovery.phase == .loaded }\n    private func openFilters() {\n        filterPresentationID = UUID(); filterSheetVisible = false; showsFilters = true\n        updateCategoryPresentation()\n    }\n    private func updateCategoryPresentation() {\n        // The page and sheet share the directory, never a draft or search request.\n        // Switching surfaces retires callbacks; a settled directory survives reopening.\n        let presentationID = showsFilters ? (filterSheetVisible ? filterPresentationID : nil) : categoryPresentationID\n        categoryRecovery.update(reader: reader, presentationID: presentationID,\n                                active: isVisible && scenePhase == .active)\n        if let context = categoryRecovery.context(for: categoryOwner) {\n            categoryRecovery.loadIfNeeded(in: context)\n        }\n    }\n    @ViewBuilder private var suggestions: some View {\n        let context = categoryRecovery.context(for: categoryOwner)\n        if !history.isEmpty {\n            HStack {\n                Text("searchMap.history").font(.headline)\n', b'        }\n        .appNavigationTitle("searchMap.title")\n        .sheet(isPresented: $showsFilters) {\n            SearchMapFilterSheet(filter: filter, categories: categories, categoryFailed: categoryFailed) { next in\n                applyFilter(next)\n            }\n        }\n        .task(id: readOwner) { await prepare() }\n        .onAppear { isVisible = true }\n        .onDisappear { isVisible = false; retainedResults.cancelPending(); categoryGate.invalidate(); loading = false }\n    }\n    @ViewBuilder private var suggestions: some View {\n        if !history.isEmpty {\n            HStack {\n                Text("searchMap.history").font(.headline)\n'), (b'            }\n        }\n        Text("searchMap.categories").font(.headline)\n        if categoryLoading {\n            ProgressView("searchMap.loading").accessibilityIdentifier("globalSearch.category.loading")\n        } else if categoryFailed {\n            SearchMapIssue(key: "searchMap.categoryFailed") {\n                guard !showsFilters, let context else { return }\n                _ = categoryRecovery.retry(in: context)\n            }\n        }\n        LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], spacing: 12) {\n            ForEach(categories) { category in\n                Button {\n                    guard !showsFilters, let context, categoryRecovery.accepts(context) else { return }\n                    var next = filter; next.categoryID = category.id; applyFilter(next)\n                } label: {\n                    Text(verbatim: category.name).frame(maxWidth: .infinity, minHeight: 44)\n', b'            }\n        }\n        Text("searchMap.categories").font(.headline)\n        if categoryFailed { SearchMapIssue(key: "searchMap.categoryFailed") { Task { await prepare(force: true) } } }\n        LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], spacing: 12) {\n            ForEach(categories) { category in\n                Button {\n                    var next = filter; next.categoryID = category.id; applyFilter(next)\n                } label: {\n                    Text(verbatim: category.name).frame(maxWidth: .infinity, minHeight: 44)\n'), (b'        invalidate(); filter.keyword = value\n    }\n    private func invalidate() { retainedResults.invalidate(); issue = nil; loading = false; selectedKind = nil }\n    private func prepare() async {\n        guard !Task.isCancelled else { return }\n        if preparedOwner != readOwner {\n            preparedOwner = readOwner; invalidate()\n            history = historyStore.read(namespace: historyNamespace); historyFailure = historyStore.failed\n        }\n        updateCategoryPresentation()\n    }\n    private func search() async {\n        let query = filter\n', b'        invalidate(); filter.keyword = value\n    }\n    private func invalidate() { retainedResults.invalidate(); issue = nil; loading = false; selectedKind = nil }\n    private func prepare(force: Bool = false) async {\n        if preparedOwner != readOwner {\n            preparedOwner = readOwner; invalidate(); categories = []; categoryFailed = false\n            history = historyStore.read(namespace: historyNamespace); historyFailure = historyStore.failed\n        }\n        guard reader.isConfigured, force || categories.isEmpty else { return }\n        let ticket = categoryGate.begin(scope: reader.scope)\n        do {\n            let value = try await reader.categories()\n            guard categoryGate.accepts(ticket, scope: reader.scope) else { return }; categories = value; categoryFailed = false\n        } catch {\n            guard categoryGate.accepts(ticket, scope: reader.scope) else { return }; categoryFailed = true\n        }\n    }\n    private func search() async {\n        let query = filter\n')]}, 'Core/SearchMapReading.swift': {'before': '1dee179f1505a44f1375ac860c7e7540f14d743a5302fc69707fbe3b32d5a02b', 'after': '34c67b5893b5ebba2eec8fdfc468a9b1662f4b94f86936d63d755385954d9aad', 'spans': [(b'    public func accepts(_ ticket: Ticket, scope: UUID) -> Bool { generation == ticket.generation && ticket.scope == scope && !Task.isCancelled }\n    public func invalidate() { generation &+= 1 }\n}\n\nimport Observation\n\n/// Read-only category directory for one visible filter presentation. The directory\n/// never owns a query/draft, applies filters, or grants any reader capability.\n@Observable @MainActor public final class SearchMapCategoryRecovery {\n    public enum Phase: Equatable { case idle, loading, loaded, failed }\n    public struct Owner: Hashable {\n        public let readerID: ObjectIdentifier\n        public let scope: UUID\n        public let configured: Bool\n        public let authenticated: Bool\n        public let manualAreaRevision: UInt64\n        @MainActor public init(reader: any SearchMapReading) {\n            readerID = ObjectIdentifier(reader); scope = reader.scope\n            configured = reader.isConfigured; authenticated = reader.isAuthenticated\n            manualAreaRevision = reader.manualAreaRevision\n        }\n    }\n    public struct Context: Equatable {\n        fileprivate let owner: Owner\n        fileprivate let presentationID: UUID\n        fileprivate let generation: UUID\n    }\n    public private(set) var categories: [DiscoveryCategory] = []\n    public private(set) var phase: Phase = .idle\n    private var settledPhase: Phase = .idle\n    private var owner: Owner?\n    private var presentationID: UUID?\n    private var active = false\n    private var generation = UUID()\n    private var pending: UUID?\n    @ObservationIgnored private weak var reader: (any SearchMapReading)?\n    @ObservationIgnored private var task: Task<Void, Never>?\n    public init() {}\n    deinit { task?.cancel() }\n\n    /// Every observed lifetime transition retires old callbacks, including A/B/A.\n    /// Reopening keeps a settled same-owner directory; interrupted reads may resume.\n    public func update(reader: any SearchMapReading, presentationID: UUID?, active: Bool) {\n        let next = Owner(reader: reader)\n        if owner != next || self.presentationID != presentationID || self.active != active {\n            generation = UUID(); task?.cancel(); task = nil; pending = nil\n            if owner != next { categories = []; settledPhase = .idle }\n            phase = settledPhase\n        }\n        self.reader = reader; owner = next\n        self.presentationID = presentationID; self.active = active\n    }\n    public func owns(_ current: Owner) -> Bool {\n        guard let reader else { return false }\n        return owner == current && Owner(reader: reader) == current\n    }\n    /// Local filter edits require a current presentation, not a network capability.\n    public func presentationContext(for current: Owner) -> Context? {\n        guard active, owns(current), let presentationID else { return nil }\n        return Context(owner: current, presentationID: presentationID, generation: generation)\n    }\n    public func acceptsPresentation(_ context: Context) -> Bool {\n        self.presentationContext(for: context.owner) == context\n    }\n    /// A local Apply context must never authorize a category read while unconfigured.\n    public func context(for current: Owner) -> Context? {\n        guard current.configured else { return nil }\n        return presentationContext(for: current)\n    }\n    public func accepts(_ context: Context) -> Bool {\n        self.context(for: context.owner) == context\n    }\n    @discardableResult public func loadIfNeeded(in context: Context) -> Task<Void, Never>? {\n        guard phase == .idle else { return nil }\n        return begin(in: context)\n    }\n    @discardableResult public func retry(in context: Context) -> Task<Void, Never>? {\n        guard phase == .failed else { return nil }\n        return begin(in: context)\n    }\n    private func begin(in context: Context) -> Task<Void, Never>? {\n        guard !Task.isCancelled, pending == nil, accepts(context), let reader else { return nil }\n        let requestID = UUID()\n        // Acquire the single-flight slot before queuing asynchronous work.\n        pending = requestID; phase = .loading\n        let request = Task { [weak self, weak reader] in\n            defer { self?.finishPending(requestID) }\n            guard !Task.isCancelled, let reader, self?.accepts(context) == true else { return }\n            do {\n                let values = try await reader.categories()\n                guard !Task.isCancelled, let self, self.pending == requestID, self.accepts(context) else { return }\n                self.categories = values // An authoritative empty array is a successful directory.\n                self.settledPhase = .loaded; self.phase = .loaded\n            } catch is CancellationError {\n                // Cancellation restores the previous state; it is not a new failure.\n            } catch {\n                guard !Task.isCancelled, let self, self.pending == requestID, self.accepts(context) else { return }\n                self.settledPhase = .failed; self.phase = .failed\n            }\n        }\n        task = request\n        return request\n    }\n    private func finishPending(_ requestID: UUID) {\n        guard pending == requestID else { return }\n        pending = nil; task = nil\n        if phase == .loading { phase = settledPhase }\n    }\n}\n', b'    public func accepts(_ ticket: Ticket, scope: UUID) -> Bool { generation == ticket.generation && ticket.scope == scope && !Task.isCancelled }\n    public func invalidate() { generation &+= 1 }\n}\n')]}, 'App/SearchMapFilterSheet.swift': {'before': 'a5e636bf36cc439e29071e4f0833ae885587a160ae2a3ae7d548fefb36845620', 'after': 'd805599b752fcd104e40b382fb30d5bc96b9f8f27622766bfaefeed402c07b54', 'spans': [(b'    let applyCityOptions: ((String, String, Int) -> Void)?\n    let categories: [DiscoveryCategory]\n    let categoryFailed: Bool\n    let categoryLoading: Bool\n    let categoryLoaded: Bool\n    let retryCategories: (() -> Void)?\n    let apply: (GlobalSearchQuery) -> Void\n    init(filter: GlobalSearchQuery, categories: [DiscoveryCategory], categoryFailed: Bool,\n         categoryLoading: Bool = false, categoryLoaded: Bool = false, retryCategories: (() -> Void)? = nil,\n         tag: String = "", cityRole: String = "", sortType: Int = 1,\n         applyCityOptions: ((String, String, Int) -> Void)? = nil, apply: @escaping (GlobalSearchQuery) -> Void) {\n        _draft = State(initialValue: filter)\n', b'    let applyCityOptions: ((String, String, Int) -> Void)?\n    let categories: [DiscoveryCategory]\n    let categoryFailed: Bool\n    let apply: (GlobalSearchQuery) -> Void\n    init(filter: GlobalSearchQuery, categories: [DiscoveryCategory], categoryFailed: Bool,\n         tag: String = "", cityRole: String = "", sortType: Int = 1,\n         applyCityOptions: ((String, String, Int) -> Void)? = nil, apply: @escaping (GlobalSearchQuery) -> Void) {\n        _draft = State(initialValue: filter)\n'), (b'        _maximum = State(initialValue: filter.maximumPrice.map { String($0) } ?? "")\n        _dateDraft = State(initialValue: SearchMapDateFilterDraft(filter: filter))\n        self.categories = categories; self.categoryFailed = categoryFailed; self.apply = apply\n        self.categoryLoading = categoryLoading; self.categoryLoaded = categoryLoaded; self.retryCategories = retryCategories\n    }\n    var body: some View {\n        NavigationStack {\n', b'        _maximum = State(initialValue: filter.maximumPrice.map { String($0) } ?? "")\n        _dateDraft = State(initialValue: SearchMapDateFilterDraft(filter: filter))\n        self.categories = categories; self.categoryFailed = categoryFailed; self.apply = apply\n    }\n    var body: some View {\n        NavigationStack {\n'), (b'                    Picker("searchMap.category", selection: $draft.categoryID) {\n                        Text("searchMap.all").tag(Int?.none)\n                        ForEach(categories) { Text(verbatim: $0.name).tag(Optional($0.id)) }\n                        // Keep an explicit tag for a selection missing from the new directory.\n                        // Only the user\'s selection/reset/Apply may change this manual draft.\n                        if let selectedID = draft.categoryID, !categories.contains(where: { $0.id == selectedID }) {\n                            (Text("searchMap.category") + Text(verbatim: " #\\(selectedID)"))\n                                .tag(Optional(selectedID))\n                        }\n                    }\n                    .accessibilityIdentifier("searchMap.filter.category")\n                    if categoryLoading {\n                        ProgressView("searchMap.loading").accessibilityIdentifier("searchMap.category.loading")\n                    } else if categoryFailed {\n                        Text("searchMap.categoryFailed").font(.caption)\n                            .accessibilityIdentifier("searchMap.category.failed")\n                        if let retryCategories {\n                            Button("searchMap.retry", action: retryCategories).frame(minHeight: 44)\n                                .accessibilityIdentifier("searchMap.category.retry")\n                        }\n                    } else if categoryLoaded && categories.isEmpty {\n                        Text("searchMap.empty").font(.caption)\n                            .accessibilityIdentifier("searchMap.category.empty")\n                    }\n                }\n                Section("searchMap.dates") {\n                    Button("mapDatePreset.today") { selectDatePreset(.today) }\n', b'                    Picker("searchMap.category", selection: $draft.categoryID) {\n                        Text("searchMap.all").tag(Int?.none)\n                        ForEach(categories) { Text(verbatim: $0.name).tag(Optional($0.id)) }\n                    }\n                    .accessibilityIdentifier("searchMap.filter.category")\n                    if categoryFailed { Text("searchMap.categoryFailed").font(.caption) }\n                }\n                Section("searchMap.dates") {\n                    Button("mapDatePreset.today") { selectDatePreset(.today) }\n')]}}


def project_category_source(relative, raw):
    row = SOURCE_INVERSES[relative]
    return exact_inverse(raw, row['after'], row['before'], row['spans'])


# The runner's full contract pin is authoritative; this adapter proves its exact
# inverse to the complete pre-category contract, not just selected JSON fields.
# It never projects source bytes passed to the actual gitleaks scanner.
CONTRACT_PATH = 'tools/run138_editor_readiness_contract.json'
BASE_CONTRACT_SHA256 = '11cc2e20ce328dcba2fcfbcb4425bf581908038c71d4f4c7eee15c1bbab1b2b6'
BASE_RUNNER_SHA256 = 'cafa9858b24a18f3827ce5678701b1e32cf533e66d51dc43788b15a74d60a79f'
SUPPORT_PATHS = (
    'Tests/ContractChecks/test_global_search_category_recovery.py',
    'Tests/CoreTests/GlobalSearchCategoryRecoveryTests.swift',
    'Tests/CoreTests/SearchMapCategoryRecoveryTests.swift',
    'docs/global-search-category-recovery.md',
    'tools/tests/test_gitleaks_configuration.py',
)


def historical_category_contract_bytes(raw, *, root=ROOT):
    raw, root = pre_roam_category_inputs(raw, root=root)
    import json
    import re
    root = Path(root)
    runner = (root / 'tools/run138_editor_readiness.py').read_bytes()
    pins = re.findall(rb"(?m)^CONTRACT_SHA256 = '([0-9a-f]{64})'$", runner)
    if len(pins) != 1:
        raise AssertionError('Missing or repeated current contract pin')
    normalized = runner.replace(pins[0], BASE_CONTRACT_SHA256.encode())
    if hashlib.sha256(normalized).hexdigest() != BASE_RUNNER_SHA256:
        raise AssertionError('Unreviewed current runner')
    if hashlib.sha256(raw).hexdigest().encode() != pins[0]:
        raise AssertionError('Unknown complete current contract')
    value = json.loads(raw)
    if (json.dumps(value, indent=2, ensure_ascii=False) + '\n').encode() != raw:
        raise AssertionError('Noncanonical or duplicated current contract bytes')
    for path in SUPPORT_PATHS:
        expected = value['feature_batch_support_sha256'].pop(path)
        if hashlib.sha256((root / path).read_bytes()).hexdigest() != expected:
            raise AssertionError('Changed category support: ' + path)
    for path, inverse in SOURCE_INVERSES.items():
        current = (root / path).read_bytes()
        project_category_source(path, current)
        row = value['feature_batch_sources'][path]
        added = [{'before': before.decode(), 'after': after.decode()}
                 for after, before in inverse['spans']]
        if row['after_sha256'] != inverse['after'] or row['hunks'][-len(added):] != added:
            raise AssertionError('Changed exact category source registration: ' + path)
        del row['hunks'][-len(added):]
        row['after_sha256'] = inverse['before']
    result = (json.dumps(value, indent=2, ensure_ascii=False) + '\n').encode()
    if hashlib.sha256(result).hexdigest() != BASE_CONTRACT_SHA256:
        raise AssertionError('Complete pre-category contract was not restored')
    return result

HELPER_MARKERS = {
    'object': 'readerID = ObjectIdentifier(reader)',
    'scope': 'scope = reader.scope',
    'configuration': 'configured = reader.isConfigured',
    'authentication': 'authenticated = reader.isAuthenticated',
    'manual_area': 'manualAreaRevision = reader.manualAreaRevision',
    'live_owner': 'return owner == current && Owner(reader: reader) == current',
    'transition': 'owner != next || self.presentationID != presentationID || self.active != active',
    'retire': 'generation = UUID(); task?.cancel(); task = nil; pending = nil',
    'owner_reset': 'if owner != next { categories = []; settledPhase = .idle }',
    'local_apply': 'guard active, owns(current), let presentationID else { return nil }',
    'context_identity': 'Context(owner: current, presentationID: presentationID, generation: generation)',
    'local_acceptance': 'self.presentationContext(for: context.owner) == context',
    'read_permission': 'guard current.configured else { return nil }',
    'read_context': 'return presentationContext(for: current)',
    'read_acceptance': 'self.context(for: context.owner) == context',
    'idle': 'guard phase == .idle else { return nil }',
    'failed': 'guard phase == .failed else { return nil }',
    'single_flight': 'guard !Task.isCancelled, pending == nil, accepts(context), let reader else { return nil }',
    'request_uuid': 'let requestID = UUID()',
    'claim': 'pending = requestID; phase = .loading',
    'deferred_finish': 'defer { self?.finishPending(requestID) }',
    'dispatch_guard': 'guard !Task.isCancelled, let reader, self?.accepts(context) == true else { return }',
    'empty_success': 'self.categories = values // An authoritative empty array is a successful directory.',
    'loaded': 'self.settledPhase = .loaded; self.phase = .loaded',
    'cancel': '} catch is CancellationError {',
    'failed_result': 'self.settledPhase = .failed; self.phase = .failed',
    'old_finish': 'guard pending == requestID else { return }',
    'restore_settled': 'if phase == .loading { phase = settledPhase }',
}
SHEET_MARKERS = {
    'draft': '@State private var draft: GlobalSearchQuery',
    'retain_draft': '_draft = State(initialValue: filter)',
    'default_loading': 'categoryLoading: Bool = false',
    'default_loaded': 'categoryLoaded: Bool = false',
    'default_retry': 'retryCategories: (() -> Void)? = nil',
    'wiring': 'self.categoryLoading = categoryLoading; self.categoryLoaded = categoryLoaded; self.retryCategories = retryCategories',
    'selected_missing': 'if let selectedID = draft.categoryID, !categories.contains(where: { $0.id == selectedID }) {',
    'unknown_tag': '.tag(Optional(selectedID))',
    'loading': 'if categoryLoading {',
    'failed': '} else if categoryFailed {',
    'retry': 'Button("searchMap.retry", action: retryCategories).frame(minHeight: 44)',
    'empty': '} else if categoryLoaded && categories.isEmpty {',
}


def helper_contract(source):
    helper = source.split('public final class SearchMapCategoryRecovery', 1)[-1]
    errors = [name for name, marker in HELPER_MARKERS.items() if helper.count(marker) != 1]
    callback = 'guard !Task.isCancelled, let self, self.pending == requestID, self.accepts(context) else { return }'
    if helper.count(callback) != 2:
        errors.append('both_callback_guards')
    if helper.find('pending = requestID; phase = .loading') > helper.find('let request = Task'):
        errors.append('claim_before_enqueue')
    local = section(helper, 'public func presentationContext(', 'public func acceptsPresentation(')
    if not local or 'configured' in local or 'context(for:' in local:
        errors.append('local_apply_independent')
    cancel = section(helper, '} catch is CancellationError {', '            } catch {')
    if not cancel or any(token in cancel for token in ['.failed', 'categories =', 'phase =']):
        errors.append('cancel_not_failure')
    for token in ['search(', 'cityNodes', 'citySearch', 'nearby(', 'applyFilter(', 'historyStore', 'selectManualArea', 'query =']:
        if token in helper:
            errors.append('directory_only')
    if helper.count('reader.categories()') != 1:
        errors.append('one_read_site')
    return errors


def sheet_contract(source):
    errors = [name for name, marker in SHEET_MARKERS.items() if source.count(marker) != 1]
    for token in ['.onChange(of: categories)', '.id(categories)', 'draft.categoryID = nil', 'reader.', 'SearchMapLayerRetry', 'PriceSlider']:
        if token in source:
            errors.append('retained_local_draft')
    return errors


class IndependentRemoteCategoryContracts(unittest.TestCase):
    def test_raw_helper_sheet_semantic_contracts_and_negative_controls(self):
        for path, check, markers in [
            ('Core/SearchMapReading.swift', helper_contract, HELPER_MARKERS),
            ('App/SearchMapFilterSheet.swift', sheet_contract, SHEET_MARKERS),
        ]:
            source = (ROOT / path).read_text()
            self.assertEqual(check(source), [])
            for name, marker in markers.items():
                with self.subTest(path=path, guard=name):
                    self.assertIn(name, check(source.replace(marker, '', 1)))
            old = project_category_source(path, source.encode()).decode()
            self.assertTrue(check(old))
        helper = (ROOT / 'Core/SearchMapReading.swift').read_text()
        mutations = [
            helper.replace('pending = requestID; phase = .loading', '').replace('let request = Task {', 'let request = Task {\n pending = requestID; phase = .loading'),
            helper.replace('guard active, owns(current), let presentationID', 'guard current.configured, active, owns(current), let presentationID'),
            helper.replace('} catch is CancellationError {', '} catch is CancellationError { self.phase = .failed'),
            helper.replace('let values = try await reader.categories()', 'let values = try await reader.categories(); search(query)'),
        ]
        guard = 'guard !Task.isCancelled, let self, self.pending == requestID, self.accepts(context) else { return }'
        first = helper.find(guard); second = helper.find(guard, first + 1)
        mutations.extend([helper[:offset] + helper[offset:].replace(guard, '', 1) for offset in [first, second]])
        for value in mutations:
            self.assertTrue(helper_contract(value))
        sheet = (ROOT / 'App/SearchMapFilterSheet.swift').read_text()
        for token in ['.onChange(of: categories)', '.id(categories)', 'draft.categoryID = nil']:
            self.assertIn('retained_local_draft', sheet_contract(sheet + token))

    def test_three_complete_source_inverses_reject_every_byte_drift(self):
        for path, row in SOURCE_INVERSES.items():
            raw = (ROOT / path).read_bytes()
            prior = project_category_source(path, raw)
            self.assertEqual(hashlib.sha256(prior).hexdigest(), row['before'])
            if path == 'Core/SearchMapReading.swift':
                self.assertTrue(raw.startswith(prior))
            for changed in [prior, raw + b'\n', raw[:-1], raw.replace(b'\n', b'\r\n'), raw + raw]:
                with self.assertRaises(AssertionError):
                    project_category_source(path, changed)
            for offset in range(len(raw)):
                with self.assertRaises(AssertionError):
                    project_category_source(path, raw[:offset] + bytes([raw[offset] ^ 1]) + raw[offset + 1:])
            for after, before in row['spans']:
                self.assertEqual(raw.count(after), 1)
                for value in [raw.replace(after, b'', 1), raw + after, raw.replace(after, before, 1)]:
                    with self.assertRaises(AssertionError):
                        project_category_source(path, value)

    def test_source_inverses_reject_missing_repeated_or_wrong_span_tables(self):
        from unittest.mock import patch
        for path, row in SOURCE_INVERSES.items():
            raw = (ROOT / path).read_bytes()
            after, before = row['spans'][0]
            for spans in [row['spans'][1:], row['spans'] + [row['spans'][0]], [(after, before + b'x')] + row['spans'][1:]]:
                with patch.dict(SOURCE_INVERSES, {path: {**row, 'spans': spans}}):
                    with self.assertRaises(AssertionError):
                        project_category_source(path, raw)

    def test_full_contract_inverse_preserves_historical_rows_and_original_scanner_assertions(self):
        import json
        raw = (ROOT / CONTRACT_PATH).read_bytes()
        prior = historical_category_contract_bytes(raw)
        self.assertEqual(hashlib.sha256(prior).hexdigest(), BASE_CONTRACT_SHA256)
        old = json.loads(prior); current = json.loads(pre_roam_category_contract_bytes(raw, root=ROOT))
        for path, row in SOURCE_INVERSES.items():
            self.assertEqual(current['feature_batch_sources'][path]['before_sha256'], old['feature_batch_sources'][path]['before_sha256'])
        self.assertEqual(set(current['feature_batch_sources']), set(old['feature_batch_sources']))
        from Tests.ContractChecks.test_category_roam_registration import category_scanner_bytes
        scanner = category_scanner_bytes((ROOT / 'tools/tests/test_gitleaks_configuration.py').read_bytes(), root=ROOT)
        restored = scanner.replace(b'from Tests.ContractChecks.test_global_search_category_recovery import historical_category_contract_bytes\n', b'', 1)
        restored = restored.replace(b'raw = historical_category_contract_bytes((ROOT / FILE_DIGEST_PATH).read_bytes(), root=ROOT).decode()', b'raw = (ROOT / FILE_DIGEST_PATH).read_text()', 1)
        self.assertEqual(hashlib.sha256(restored).hexdigest(), 'c305a75379a5cb47e34314e997a7f49ea6ab9e5877887fe13465ba49f2df9f8c')
        self.assertEqual(hashlib.sha256((ROOT / '.gitleaksignore').read_bytes()).hexdigest(), 'e6643cd2a90f794cf60c3f635243897b6fefb5adac156493eb2039e590ee09a0')
        self.assertIn(b'(4028, "feature_batch_support_sha256"', scanner)

    def test_contract_inverse_rejects_current_bytes_and_sources_without_caching(self):
        from unittest.mock import patch
        raw = (ROOT / CONTRACT_PATH).read_bytes()
        for changed in [raw + b'\n', raw[:-1], raw.replace(b'\n', b'\r\n'), b'x' + raw[1:]]:
            with self.assertRaises(AssertionError): historical_category_contract_bytes(changed)
        real_read = Path.read_bytes
        targets = list(SOURCE_INVERSES) + list(SUPPORT_PATHS) + ['tools/run138_editor_readiness.py']
        for path in targets:
            target = ROOT / path
            def corrupt(obj, target=target):
                value = real_read(obj)
                return value + b'\n' if obj == target else value
            historical_category_contract_bytes(raw)
            with patch.object(Path, 'read_bytes', corrupt):
                with self.assertRaises(AssertionError): historical_category_contract_bytes(raw)
            self.assertEqual(hashlib.sha256(historical_category_contract_bytes(raw)).hexdigest(), BASE_CONTRACT_SHA256)
        # Even coherent runner re-pinning cannot hide registration/floor changes:
        # the complete inverse must still restore the separately pinned baseline.
        import copy
        import json
        runner_path = ROOT / 'tools/run138_editor_readiness.py'
        runner = real_read(runner_path)
        current_pin = hashlib.sha256(raw).hexdigest().encode()
        value = json.loads(raw)
        variants = []
        for key in ['before_sha256', 'after_sha256']:
            changed = copy.deepcopy(value)
            changed['feature_batch_sources']['Core/SearchMapReading.swift'][key] = '0' * 64
            variants.append((json.dumps(changed, indent=2, ensure_ascii=False) + '\n').encode())
        changed = copy.deepcopy(value)
        changed['feature_batch_sources']['Core/SearchMapReading.swift']['hunks'].pop()
        variants.append((json.dumps(changed, indent=2, ensure_ascii=False) + '\n').encode())
        variants.append(raw + b'\n')
        for changed in variants:
            repinned = runner.replace(current_pin, hashlib.sha256(changed).hexdigest().encode())
            def coherent(obj):
                return repinned if obj == runner_path else real_read(obj)
            with patch.object(Path, 'read_bytes', coherent):
                with self.assertRaises(AssertionError):
                    historical_category_contract_bytes(changed)
        for path in targets:
            target = ROOT / path
            def absent(obj, target=target):
                if obj == target:
                    raise FileNotFoundError(str(target))
                return real_read(obj)
            with patch.object(Path, 'read_bytes', absent):
                with self.assertRaises(FileNotFoundError):
                    historical_category_contract_bytes(raw)

    def test_central_inverse_composes_to_unchanged_historical_floors(self):
        import json
        from tools import run138_current_source_projection as projection
        contract = json.loads((ROOT / CONTRACT_PATH).read_bytes())
        floors = {'App/GlobalSearchView.swift': 'c70fee37e02a6b4e2ee6540104932b175fee1d0faed013141fecb8cbce6c7cec',
                  'Core/SearchMapReading.swift': '2089e1dd5f41c81411472acfe8caf0f18e51693dd2c8ca390dde074409cde017',
                  'App/SearchMapFilterSheet.swift': '33348878001340ef3962016363280702c5be0b2377e0af6be881da7855512871'}
        for path, floor in floors.items():
            raw = (ROOT / path).read_bytes()
            restored = projection.original_feature_batch_bytes(path, raw, ROOT)
            self.assertEqual(hashlib.sha256(restored).hexdigest(), floor)
            self.assertEqual(contract['feature_batch_sources'][path]['before_sha256'], floor)
            with self.assertRaises(ValueError):
                projection.original_feature_batch_bytes(path, raw + b'\n', ROOT)

    def test_swift_controller_cases_are_24_authored_not_executed(self):
        import re
        counts = []
        for path in ['Tests/CoreTests/GlobalSearchCategoryRecoveryTests.swift', 'Tests/CoreTests/SearchMapCategoryRecoveryTests.swift']:
            source = (ROOT / path).read_text()
            counts.append(len(re.findall(r'\bfunc test\w+\(', source)))
        self.assertEqual(counts, [6, 18])


# CATEGORY_ROAM_FROZEN_SOURCE_BEGIN
FROZEN_REGISTRATION_SOURCE_ZLIB_BASE85 = (
    'c-ri}U5^_{wjlOizaqP4JS6W>smx@ONwRK@x>_oA7e+1VR!Kd(tJW4GGb5{VL}qfBNl7)D0v3Mp8eU`l'
    ';E#oOZNRW$*ubuLVH>`{g|YX?*fV?YlmCLxiHQ7UlEq?1vP#n;x>Z#qGfu>b^BpJ7+27xPyqM2v5I?w>'
    'hl`mqrx$({&q?fufkFaTp&yA8E0^$QIQJbgQ5+J}i*SAgUnTAXKTw=7fCrp7Qup`w_q=&HRc0i<ocOll'
    'PiNsgR$juNd*XKz#a(!0cGXobNrd0(D!+}wpbO)5m6%Rvo<D)#7J(nfG>Z9v$zSR;blxSy0u<+xfBp(S'
    'i`2(rCXX+v^Da{Hf%ADtrtr@qrss1yn~<yI>9ZHFPahwjpFIEJ`1I`f3?`<WzBu~+y!8Iw-sy`MuarZ!'
    'i1zt8&hGrYqt0m*PTtdYN1YMGU-ZU!yLWc{?CJT-qgUU-_gidE4~uhp$mW!wP)sg|a&>mq+I#%s`K!~T'
    '$FI_n;xL><59f<O?+wqX>%&%@Bli7(M$vhKe-+W#+B<#y{Q2?eX3uhPN3V{*eR28^&%cFV)=&Im653>P'
    '9#JxPE_2JEPWYbAuae=8p1t@soxmv|YB6_c^zc~-^yB}Y*b}OLbYRJTa1pikzB@U4h2WD1j%Krmr+}F6'
    '7|mV%;L{J08h!A+xV87q(b@5Nil4LZj*R{QpV4*4F{q(Av}X)m$0mm7c(!AkrqQ>({!kxjL#;P-EZsFd'
    ')3GR}df(A)o7lQ-*aI=Lz+E=3Lp(AX_J_7%5`F0PhKA+P{=gbqnr`a=%<=lY9vuwazV13^&l(PGy-zID'
    '9caWFc{%J>%-Yg*&4gKwjFE2Hj^*_2LEoi4eE{p|4+lEYsopbt-azm5+`(YbCuGnYYI?s%Mmo-VdGv4o'
    ';VU5KLj|7DVVc=Dme%H(qrRc{DY1I4?F}@~vK)QrS{ii+uBlOH*mE7%bWFn|uu#{fo;h#^IxNf@QB7~{'
    'y*NGj_T>4|v-1K8<v<KH-PJ~}<7q=j(>&d!gAp0IL&x(>G8oy!GDb$<>h*>QZ=e|(V1ya~VxR#6`>nmB'
    'Cr2+|9Y0wKK_`9Br3N+KVQ=JG2JtjPha*4|AvT4j42d`FQOoOjKm;SV-**9ut2@-zbhF<tk^lLV<7cmq'
    '5Pxslz0t6%*!x0U2x0YOuu8!F7>GX-StY)@S~RT|1F3|YQ~qK4RX><5;;38kNg@W$?JF4l$Kc0cbHVjv'
    '@WaXRZ*pkudjo4^TRpvJ*uX#|LS1V}M&@W>Qep!?0K@fQ-})}>p{o&xIwMmv^}abUh+_>~KL-0Xk$30w'
    '?{t;6IUEj5SV#-!0}PN;gsU*$o|6w<<u5>=g<*V%Yv_!B3>0{=5Aa=>;i{c&r(Zh6e>(h0fgBX@g*WC@'
    'jLZjRm=ce*WX*aT*oeCRs5f8?q=*+lfbX^0u0B)>N)C6GxMC(^&G?$l{csKsZ8rbhgAtv0Dv2UGkB@)1'
    'Ad|MBKsCA~Kq756a7VqQA6@?f$gK@CuF@^JA;XCaGeI<{laRQP7~?>3xB*rEa6NzK_L(6&2grjZBa7h2'
    '9~3aKN*0OggOvnm8fTAGE?La$P0OPsUch{8w3p6>Hg3IrgFxQCY1tGY(sPcP*4r+w^tKPJLw!W!8|MP('
    '$FHq}TtHD>!J2*}a!3%+c_K8^Mew&_PpiM#PRLl;S1~i0xQ*n;6H4AOyUg=17MWpJr1JdkXMjPv0i{zU'
    'H33j%W~)QncI$>^-(a03YrmP9eiY&Z{?V)Fmi(HV9B1zhI5k1t)01bQZ%@8GKC2P}dGx3*EWrhl&t_GW'
    'BP&LU>BpFTU%!P^NLE!63@xXpflb%%StHU1o6@3Slj$ZMjVxk;6-CK_*dy8>T44TJ9-3@}zD>-LXSm+T'
    '8#=9yP=`NBQCOVL7wLARbjyTKeJS%rvi$i=md@MEiAkL4(-(Pj7~C&#eMp}ePM?g3V-76c9QOJ>dtg}T'
    'EA_qMs1N><<qhb_ary(z@nAlEOY4IpN-`(?>9ZFvPMPC1G6v4jv~^R{!6~+f;8vr5N{2eNU{$UM=C@|+'
    'o}rJ-{)n2k*4MykCe)**)d%nK<lE;jPV>GTxY1_MaSbv8Uvy+T;FCJw`}X>V*&B{5d*D&e?h}_ddVgS!'
    'dek<w9$;srQL2rImh<JfP(eSg&Eg5)G6Fth^os!n5l?^}cnsU}kbm$!nVqu8$VK)sKAe8~)Stw3es)P|'
    'EWXjnfqeb)<%`o-3}mecN;iwZ%qjmZKmEtznN#ry=h}3_<ww)W-|(CpI?+Quy9a!B50cqENM|>7@vFBH'
    'MteM_R)L#jf*9&K#rWJQ3(u`s&N3#K0($~?Y$5pJ1NPwq@gYpTv-kA$#XmZJo{`+Ab;L22;6~m+U;v^A'
    'Y-7Ptqn_QTwoMF5ouTJ?z@q@k)&~Q_GwqS-4F}**xr3f-_4~bHf7CbK5h3mdL<&&cq1Nw@U@3jWb6j0B'
    'sj1n$q2bv*&F$OHXkddl@eFHV!2bi=LpG(ZsTqz2voq@uC4e`HHKYz1P)Bz?UAH{la}5weeQM$V9*6{I'
    ';OVY2?0W_^N5i3O7(Ea^+Q`tgA>Ep=5w>ShSfVv@U2|lN5X(bj==6J3Cz>@h2JmwTvc-d))kcoy_4^<j'
    'JwgnVm@Y@~rpy80hQk3d2JXls1KY+>9t;P-JbMT`=eU4at8e!DI_xIwAIM?N)Vu+)3}<K!U5DI~!2lu%'
    '@4n+AfmoVn<9K}nH0#+!M@eaENSEe-XwDE&K!-g;rv`{k7v!u1`=3zIikK@vFaQxiq_(YTJ=fC)poB&v'
    'XQb;O?HwTW0W~yxG@=IaEK~rXOkn9llYj&t>Xwm*aQtyb=ROS_`ZxruA;1Vu21zsY;m{$T;lPT9E&+WA'
    'ENJy%$6SM2h5;+_hDLAXjYdYFctdw&8SV%+3@8bxIc2yasPDn7%YY03Vbs&9=4tu>HfLz{QSE^$1WjTL'
    ';2&?~VieLPpx7*+9o!z!Or&QIVOtT%O;K$CGeT_#+T9?wVVOfmXFAsfLbE{44SEE$WFI~RSgxVl00GSa'
    'YU-M2kl|=pMf7WgB|x+(JgtM$9gTXX0dl2}F<aB?4J=p@(TA|2!Dyr#AW$5y?~M!tkV;(GQ4`QXwh*{T'
    '@jVylNb5UvM4f>FlB{onK+(*RNe3gNX9HsyLj!Q^7^X=b4Y&=d-?M>w`c7}X&_*fjnA*s-b(g^WJrCq8'
    'aA<F6^<d9>x~74tVCrBn=(c5!EUMceAO}<fk!=yPH|n>p_l{n^Jbm%Q@e^jqvG8uAW<gi^Ntgheok(>z'
    'ID}e@u-QCh!Cz*6d&Hlh|1_u55GawjQ$LD?FkCOlHWNZO3Xlz$|8|Tk*~;l|fAaWt@8tWJ&yK%8e*Ws{'
    ')ya#Tp;U5bmO}EGcUACk_VzIPJg2`~_;cC@vVg7k@vL_W`%W%sXS~NE%AOL0v66ny-{pZ4KcdPJbFAQl'
    '<M}+Cx08qW`0xT4h8g&Sa|#}IP@Xe>UYr|y8g>^Q!1rXbpvC9gEQaAOrn88D+=VYkNP8r5eE;w%nMClO'
    'AGkn1hek*FrP9LKw<?BAAPC<t!~F&PlAkW~It!nkfAHf=*w=GB51%Ao7n9@2%&l5EJXF@5lL1A%4&DXf'
    'hd=@6X%>T@ogU&Nv=$$ktr0zN@?kHD)P$ZF(YUJ+4<sD8$Sf{`QJXmhX%JDjU3Glc$!(yRE*o5R!bK3b'
    '*<fteI!iHNpS|Ir#{381azX>~&A0efK7&1_^lE*N>>peJNr8NF6__)y0wsk-CYcJ+j09q_`2}<M0`gk`'
    'EtdJq!psU&8o#aD3{FHi+qEa7upckx{)Hc4HU-F^35{uSM-=Ch1Q*n8b@Bwsh8INTAX8KKT!fyo;{<{G'
    '{r&wT5RI`CUs45xzye{3=$t-$fSjxFj1RF``f(N_B4J0aSb&f5GfU~HJmo2@pS`s{l8IPhlWaZn-_vw1'
    'iK+lD1}|V9@z8#>n9U|W6_ZG?ut=g}0$MK9p$Ln8edY%dizlfbuqc^K+H-rq{b<_x#}y~>?Kj$k5qaRf'
    '{WLJIJFTDZcLliOI*|ZyTu!{*l=_Nfmu_i!jqqrznu`~OcpQRwqrI(;!=~b;!)CFZw@_q~mdNi((1(*D'
    'h?*(xdJJ^NNn{3E_C1^Zjgv(|noI(xkWM!hGZiS9+Mw*S;Y%{76fQ1+ElB8$jGl*qLxM11NlAczcL5~h'
    'kSe_AsYqyUbpA2eJ5H$y|0<De601gmR|p+k?-fJYz&zB!y)S<;jb<+iM1f2(9UgdQt4qd0Lxf9#bV0xy'
    'zo!9+A>x5q3<8PGIlrto1$px}$1H^pD%d3%AWdP)Kb*c<@!*ODW#h0_RT>s0N___V&-sVb3X_Cx2%Cl0'
    '!4w1LDJnRalt8OAY&A+cg{{L4TM8QfQi*|<XuB#MEWeZChg5m23hS#EG;U|Rl*bo4{@_akQl?B3!h3I8'
    'Ov9vS4~V=<T3M|NksE{pLDe@YA+3<(SEi$C#E9_SFO@<x@0UtD-R15ooxg+{5bfbSPS=-VNa{*C6ckP6'
    '72bY!`HZ%zS>``4&$b0V7ny_?>5Qg}2m}&nBqnwXlXm!5E0lgWVb4S@brYex%EnA&U%{{iWqwN0PEx{P'
    'awSqb(KA_2`xFDRNqURPL_tR@E?8BmmzUTGi7?0PPSvG!hQEjjlmw<9F!K?qtcuH4i_L^K*Rx$tGqdF-'
    'gdct=Q^Tf=%t<kQ<Z=<bLml$wlQ=7EjfEkVo+!Z_7$?Ig>}UGHHN(S_MJ-VBriE52Kzv&zF{-3P`XC3F'
    '*TZ~oVR>NN#r_nWrmFRW`^C@-W94%(#|1(zOrmr?ntzfX5T(M5Aqvp<08J<M2iVT|efIk@XLFtrEG?XP'
    ';BsLtdy^2IlDQyVFj{EfGPTQ4khAUa<<iNTNfcLCh1v|WVvpZeVnj#-VWz-H+%Q{nBv)_%5_U=!i`!K+'
    '|M5k^*Ic<F2<}s9Q^w1)PbjkDD;eo<T#fnuT;H%kd>aD#VR9uz2*p#}gzTz_E!mij*)6Y;Zl!+Ki;9w<'
    '&q<8b{zydjij}NhMQQBZVmAAJL7@O0R*A^smr5kMF_@yQxYldsP8In5ez-u<S1`+~EWzZvMQ$iNUnnV<'
    'Tebe%EUmeuT8|m^EqTxnm~u;v{||&4S;-N6QN1Q$g&y53ZLgRnnPI%Eob&%s39fX|^WbmN+b}Ko490>H'
    '(MsH7U!Wi3a|cWZ)YiBa+REAIlS(UQ4VwEokh<c6<)L6qAYzumK_+oi@kEjsT%>?10fT^kq|O4+z6hov'
    'IPc)Cr-lHJAuD|5fR3d(uL&uvv3G99YK}Z_#4J<e*|nC`A1v6OH#rJr6ZyI{>@ttt-dD+ucAJyIx2uyE'
    '6KJ;@E}xZLo>wjs!`8SI&giZb09iPrN`|a}Q4|uz=tq@qO=2IVs9F}($>6Y|M=;8F6<3}FAp`9@l%nAg'
    'AonoF5re*?SLio`EzM{;%T@<_Fc&}JUrxgYDe;M~AU}3;<}%|?pulXJiG_Tf1ki<;D0`Ir?Kdr$7q`>k'
    'mrPa0WDX7vfKR@LbIzGLB5(-P!v*17U_le0iTCt84%__kPA8qW_(twDpu&F0vlJgeoukBPxBjBlNsLj|'
    'kJ#}-vcmj^C9^8VN^k*uLwI!aa?SoN+gBxZ&=oUVjol213GODo2l`iafPsR=OhiZUO~7AruT6bLF;$Mt'
    'ub#k495nb)^LhTq!&Y|IhQ~U5`d1Ic9Mhd*;u1$y12SFmt5y?AHeZIF!(>Dr_$quTE>@`1cdn1S&Td&8'
    'zM8WWkdH9(dH9a~*(pBuVGgjw&NB+$%h1D;ZIB4ZNP)0ljMBzp7VtO2-k9O*T0FO;>3(^r=zHsSYj4k)'
    'fTB{;gHAkk%el76kyzADFBIZg*<%tVE;6doh{msHZA|IQVU1<@ZJf8emk!2{-MG3s*N6Pfj78qhfyC`_'
    '5x_&-a?fQr&gS87fjnT!<$0{qk5x8DGUu+sbbhv$GzRMWP8!GP9HhGM<>?ES{g}o9#ftOq7Z-fM%;7Zn'
    '_xLCi)_W_HBvJAvz`Ke*=&b*0A+m}Om}?%ugxh3n<qyiI!e({zX9w3jJGYo3&{;Ed68;g`#e~wDhYWAD'
    'w`q7_4d5Gmro8iBmHAw7(aR*tT)Fea_W|jiSt#&(Vh^4t)^=)6MP&kAnM#~w32&593`TqM=3X)F{6-T!'
    '-Ip785C-h5woGoI##Ik9PvvIV$?Vk)@|x2XtxC;Lp=Am9xnbu<X8e{!!a;hkAa??TE8DA=@UA>yJjDiI'
    'lNMhYT@Ya7>i9d1{3%c9*JVP^NVRaH4#v<q@aK8v$DAjoI3xYZRhf`8T&4p5hBK7>J&kHRUyOM(dGH$*'
    '-SsZ{4HTM;F))Xgo{w92Id3kPh)}YH-VjianEucXKrms<)|o6^z+@cHeH&cAh^IhsLlwV+mIprcflS`D'
    '@fWZiBAPRJ%P+93{KyZYm;~S_a4`7XW7w$<vtLUetKK4T_;-$yX;cr552sJ4IA;~cna2^PR<v6j0j<s&'
    '?Uch&vTfZw;y8MXcxA5C8kDjbq2VSUXHQ|BII$<x>tw4(ScQc%9$C9?zJ_ec{BN<^gKAPMd<Qi1D4YAw'
    '6mjP8TRi!|^91xwU;!`yKepky88Pt3RGe~7`S;SWuUML5hwhb{jyxsvcPt^mZf$?PwzYTD6(f<g!lB{f'
    'R!W@2%SKs)Cp$vaor48^4t~SAaEMW82xD(a=*YbLbF&4*fx(&zrq%7@0+nD+g0|gio0>7~D*Nlgko&D}'
    'vgVuTo1#Qb=Hp)k81*crpmmkP-I9`U?xt?w8ai1vB6xT#afJ(huo$l+Ty{kiMS-`<o^6#|yR=#ci5sOG'
    'gq$!Ap0j4VooWm6d5D{m4;pv*lGdPo14pN;tTnd)YNc8$o6u#JLQS1GO>CCuQy!f^$HNA&P#KRo^NGh2'
    'LeHH^h{<RrX8M`(a_&!)P{381>clL}32YvZ6igQ}Cuij>$vZ+v4<yo6q(tOBb=4dNZA>ss0wAu0*Pg@M'
    'UR5ll=ztXUN9z8I9Vz(iSrTCiG6~J>l>;xyX*s|{S%}GQEp{gl{>WXqOX>&AF`==f%TgO+!cKeIq5a#$'
    '0Y6OKc>(57{Hz!urxnvVc?yh$aUHQ-JoL(~2|ip_iKx|hB_I_(2cMZGr(%F1#WpNO%yq>)*cdsgJ;kik'
    's9j7u?Tl};`4wlY1ukl6A_>0t%9|zFr(&}za8llgvB<-H3fux5{S<>1JQWvZVG;%0Td}=sHgL1e6LYVa'
    '=n8x-&2zK8OGOaO7AJ%H+6T?V<w{q{r&44*w|owkB`couy-&C{C#Ex}HZgKm3yC!GG5KygH+m=K+OkYd'
    'BkP68b1B}w`7TVz)OHCH#yFW#Mko2@a;^p3WFJ@Q5&pe&Nk|)|9j?s{#a(5JB~c?Hul_^C6p64&BCbq8'
    'KLqFeq&y9GFj9yrgK<UYxx#Q*I>0Wvw8cdy!mv7xhKJe2cQ#E{Np<oPT`!4?TOYR9o$~6V@>|Y){Upj?'
    'YyJp+gQ>6ZB3P13biUv@JQ<OSWQ}u{nQ@LbGq@BshK*ep2-d!mMWov%L~cS0n~`oshLO_JTFPH219KbV'
    'kU2AvOr*}jS-W!wl$y?m-DY|nBxhjaHql$9Di<h0-f{|1OHV&ZQh(mOz21(5r~XGgec)+~jAj=>mKJo5'
    'Qv!$W{2jd#l2%MJoVel`e8W)k4W%8$>B%{>-NiRJ-qr{AvMkSPKiVb{WlrO&;Y<G2Qnasv6_f8ABuP8T'
    'B{JCHJocV)<f-By7xs7}?w+w|6l~k4>+8K${z86U2b<U&C=YDH{RCWgw`k{7Y3f^95Nzy9dw-opAlX<i'
    '9nvM=<Cmo7sjZOSEO5`+B_j~kSs3};odeqm4q0|VODBdK1d!KWyQ;cvHC}S^l8po4`D;!1XXRZc=KaBY'
    'EACjOAyxcXjI+tGH8!t0dJgN#Go#BdtL5C*as-1pu@&J6R=s7ffk|bX$1cgClw|Qy7UL+QBb|TY<{2Y~'
    'HyKLbD*sr~-*(Dq)=T-T5|&V82F#=2XVvWZK0T`j>gUl-kORI84@YU7hDBsp7Dn#aD!1r!3^>iBTZY|O'
    '@Ren#R3?!nNI%c;ZS-NGOR=n*LB7%7iW#m6i7ii~%cs~`mc4wnC9Xf<5v4Q%qgn{W^Q)==P$9*Fk0Sy&'
    'oejw0lwQz}C7P(noN3)I(&3@7o@_YXjiO`uI$}a_=1=_U_^pLdM1s4VB1!;PM4n_jryCqo-;QRhQ%)R;'
    'hEsYJA)JT^j4(Q5Vb+MbyCv_V(h_5*0%`eAewjZ3BZklNR`3KLL0{dCA5zr2%Xj;VqL}N~Lq1_O!$raJ'
    '=1+>+b<0UL>kckBfKGR#toP;ebDI#}4>)o{bhlYY76Rt$DW`>i{fS0U1U?Fny3ZCim_z5TAMsp`a}1Ox'
    '+MzOSs(e~lO0@xHJiOs3yDCAa_*kBB-mIyBATmy-WOfc71I0QN@yenbY2}P(_|;SVX1;R6+wrR1X9wf$'
    'BKa{?Mk^A0PJ;G+E6u4vYrf?s8G`7gRV@f-3`2vl72sFc^8Nx>a=pLGh$|f`0u$rz#ju?YcdW8QL|*5v'
    'a<Z8FSFQoE>Yy1@*ng(*RQ;4>SUC)Z;a>^)1!Qrz)tM}8<<#Ieebl|9C*Pl(o#Bnqrzg+9JwAPTdh#60'
    'h_%dt)1xD8Frt0av30#?SR;q()S{->*UW+K=>5KpWn#>}+czxY7{tUP<J9noVbNTzxL3#DzkG(~^oyrY'
    '&yI2QL0=zgdyikAo*qAcb$-j*F?%-@kJ-Dqddyzk@-cfg>c{MDTR>*-78PXnZdpQRZ<87_dvc1%?5(dN'
    'v$t6pnY|n9$n0%UNM`SLm1OpAUrJ_gZ7rF-?Tg8*e>N#>0!j|#3KK$k>meB+pNPOL?r>gsLY(YYeVtEn'
    '{WEX(j{m`{(<3k<UcP>X7xd0pWTn=$$5r9CkwJ8w=tIkNdX8xto@d#fHE;(8p;(fwr&G<f-2QOn4X{VS'
    'NFUJ=G4-B?MY|lcwI)?=<JVH?&ohh>={dS-TBAM)J<TzV-e5R1Eoy1-!N_#AQLk?gd&8kIwCz!UM0LaL'
    'V@W{0KkCbwRT_58-KA}v{pRH9D-g|RuW(CR65v$6_Ltb}mDu4IAA&R7<1^gim+21Y+3m+*zo~h(@`*{Z'
    '$IcZ^VreVm<fOJakfmBoEHx%Qh|E`IYI@zwon!V`y6V&>Y7B7B{oqzr)2occ-2sFq{KIa8>zfepKgUfj'
    'iW#72T(Y|~Ks;D=>tmaHzD)yeoI7wuZ`kt2xy4OLv%AIscHaINND<>pdS-W0{GJN&24(o}MfiP?;AH{c'
    'Af$5Y7C$~~8e$r0YYfU(JyRN+P11}-80pEuF$;3;0M$*iOy#=TO`997<zQ!XTBKF%qR{ZB?Z{x;rM<R$'
    'bFFb}?XHZqUD#@OVyfjVwd=Rnw+xF^h9d?&*BlMKk)aPw+jBjm2Y;F)XE5ybOpCZq-x>_4)f-wv$I-n$'
    '9S*FKW)FteXyh8Sw}r*H6nt>)zNUGOHPHI5;kmj&M?>4RH532Psb>t$f!Wvl16QNw0A@QF4k-pDj3G=#'
    'qub1(GSncAA|;MgYT7rO7b8w0YS{h@X++m5^!<}HDC5YA{(usP&(-t1mOC=Lp@&!XFc<dt>FM#=cRWyd'
    'Hm>V4Wge2ODa#vZ*QD13<+UVR(syY$m#t(W+s_egQt>4iwF(YnTxlDQH?Pj~%@5@-LcX+VOxSE7Ybvz<'
    'CZ`*fs^2DL)OXFk+0%$V@(f}*re(N}YYawuU(-j{K({<RG}WwLpAgpK%W#M>vU+Z>=WHwZmh?Yy971}g'
    '?trG(dSoy(Ek_?wid{=A+a9^vz#jH=x2I{2PWsqVN4H#T!Q^`Opij4+NV7&j6QQ40c4a?JxS5j=oWLbp'
    '@&$4%R<@Q3COKU{`|c>$@=^LqL?9=*KrHH6O9jK~FcmK#D_>=`sU)vzKmP~6mY1dewA0F*nAjsTu({8q'
    'i^4(}yci~1Hug2G4Mn~+)BqFikOyU3FZUz#w+lOF_r^@47R?R?a`W<dH{y7=()ezK@oHIoU0WFEZKC8o'
    'midR7FOtvjTI;GJb{aAUcp9VYJ{Dyf)5Rr)8yf|jcTY0NV*8o{o8{AgLRjNQLg*E&SMY13!eT6-iX3p!'
    'l%+`wPUr=3uF{H$IixnVae377)rwU2<l0w5a7#;mgL8N*oAddClG{k!bLBL{wVYgFx!vN+=}1X>$n4gJ'
    'CFKqU<z30iyAhL(ox0y!Yg<IH8r-`~*T@91VjWD6$+hJxG)t4DzAMFYM|x$KYGs#NWrb2{#sE+8C(0|o'
    'qgQW}(pn8#0r+CK&E#w2l~>ntx%9~m<MYbfa&7sZc8OT?$OaFtK~Pc$4kzwm{#Ja2JWC4KynUm;&8kGL'
    '{i2rpqP{b<!&({yC7rhS3zv}r{Xu}OX<Mao&8=>({xn8e_CG5Q-d}OCJY(Z-+H_Rv%7h$vz~lfAe<W3M'
    '#&TC!c`vKQwyFuYVQ2EaapJhg(tUTry#NVo8?js8hov632Qu-#pMu%6vf10i8|1xIvDB2h!*w6#8?~o+'
    '=vMS<Pg}MBvh`!3Q+so3ZB(5#s?F|!GHYC1-H|HWnI>DO$mF^zlFhWADUYAM{w8gm$?xZWbNube^9C|2'
    '(nb)oImP+|X^<gKdvP_AWU*9JMJfok5@!J`nbP@rT1+Cl?9O_uz?T|WS_4_wY(1%OUk(RlJGBc!JbwN}'
    'asXMbTG$cy+zs>mw6Y^a?F!18H_OK(>lfE-q_(gEMi8RXP(xJFltjHFf!dHfy%TY|PMTi7y}sUie0qEY'
    'pPWBE`3J9FpB{@8SS;klYOW;LdXE<IWr!70zV`!KReNXYi|iKgQk4`K^L60I#XH07t5~y#)pUvc@`d4B'
    ')ivRV;d9@;psNb=EY0=1SFc`{0p6xi%+|$LYTTmkh(anak9ZQ1s2VPzm<smVy!Dl*s)shqn6956ol)`W'
    '(QkO2R#xu*u;vb>!=AmuF~2*0_EPi`z@cw}o^+su4e@?{<v^RDY%kvva{VGVF2S^y?;lw?snz|6_E>Si'
    '4bfg%5@}Bm@vGD0V|=`C4xPT`QD<ZkIvAO@+oOgCWTFpX$NN3qBBnl~M*3hy>&M<mGswWS;W6U%tlq%z'
    'sL|JLyJrt<ofw|(lA&SR#4>aTzU3KC&-P5}>6$jMJvSXY!FD#ZPBhCJ*<>&n=mTO?+Slw6p+n1YdamXT'
    'h|?p3zGae;r4!OKdaiDImTQ@Pr)LfN+0aRi=xper*Y6u{pY*(*NrnSQACaD=Ii?OUhl9b$^=#8LflvBg'
    '&+chG%W((2et*=rP0t&R`svWger7|HzSnnL(;E&f&9imQ)cVA>dY(;m;^=)#(}+XO0nwbH>tcl@L#M`w'
    '_FXd49Ducikkc2xsjhrp8$T#W%9j_0mPIUBZg1qmv|JCi&e18=hnh_cjao*}8d;tJyGeU4b;!`s2G(Ez'
    'n@>H>7_keK)fW+%4U=}Korcc4w5mA<3s&pnH9iEprJdwcWF`C3-qfPuZ}i4^yWRNc2w-Hhopi<O@|46i'
    'mOsBwGoud7i!TtXODtl4qT;*fhzCAXtaHw;NAp8mk-3&YT2AH3ysB++xq7KGFuDKa<m~Z_AC5ut3L##q'
    'ZTOevFZ^nCm6A16z5S-h+>>H>X|qt#O(b>>hBt=E;&XcuC3OO)GghTKX>gkSBD(zDbgwW?7C+qN${720'
    '3L&`$z@y0S;W_gVcuVJWro8Aw`pgXgSVD0!UOuj!4v@sKE8^Q#VeM6{u?_7vvjv&wwv`W_wS4gMlMt1X'
    'S2JN@C$qMZm7|na)Kyvu7Fw&14sJzRO%s-Mx?0WN%)@(fa(euj8J9xDWtx8#<+nh04m_+eIMAur9}Ou%'
    'g{c`-(}wz}H?;epX9=~21C8`(&m*oipnXU4h(-)Bzt@y<x>2w&1ZOV&w$g;58SLa4YuA<SdscDx#vlS('
    'plcR_|6~^^IH={@4(s;drs*@XUAoHfI+)Y<;AvA=NqS=OTD@Ymj2c_(B+hnp(Ii>iB<kc4#b+tsaOrDg'
    'ThnyjD49#4@<z;?)YWEAb}f_UXUeNfnzl3W7L!Sy8hHCYY!aOXFQ=iqm{0}mSA{I%OL&a;yix3{8)0Dq'
    'Z--1KFlf?aH2}8vgA4e`k8<@S9)!W<idX(tmFL)rm9_unUqjTZ8`x^)3;xoL94Q;|c``m<`Av4sZpdqw'
    ')U}ehn&I?tYJ>Ico-b_-tHV!SaZs{3!|(6!^CJ7n(CO|x_?41MH31GQ>}UHGFhnI^&m=Sqxdk(>vn|q2'
    'rs>Vk8>_k(FO)Um(a78jxjdg7$85s#*&K81UK}8|4&-#P?3-A9$AooDx{^j#tJyqv04L7N-0e9(S6OMf'
    '*}*nU|6Mwuf_>3heN@&}V{&!CC8t2YXauBS$1f#{eGu8aX<dXlioEmK1}vXhW$b(qtE0X+J^A+J`O&lU'
    ')8nHjC(n=1&Te)!%0)PFur-?eHhXXbzsuTz&xqB<XB%+(?x;y3F|DAb>$lfw4;PW;ns#_t)4-*&YLa7V'
    '9;H2t;xUeGQiIY#-_&%?9Q6!axBBp@?t;%rT}|)lrtVS49y+!|2ae^?O{yj>oiX&ifi<$No(>TDwuhCE'
    'tRWehqk&0@-5=Vz?)0o)ukYH#a`C*x8JU`?_sxMp9Ba4<%*rDO{N!tP*bCI<zsH~N$z1VRqZ&Y89&vxQ'
    'ptbIxt^y`F$EOiY?n%-&DCs|g7suYbZ3^hsQvw`?jp;lLe@O=e5^OPv#|1o|viG7#(t&}>UC^;|#u5eO'
    '503{7Xoxq3D-fvud&;P6yi9oV*AvkRs}u5TKX8ix@tp?XU4|bb-U2FW42eSi11E7ZXo!6Tn5X<?zp>RY'
    'm2;@1O{o|qe2aZd8xuop_+7!A%_*KDx@XvNZ>+q2ee$Fx-6f+>Xq;@)S<E{gW*zP@uSoQ}s<WtiGsX4W'
    'p$nuMg;T1aT2?;Q8xmh<&ODq<WQ~TeA7I~{cWpB9FM=u9LSsdp@IG%{C7KZjei>tbLRs*HwNzrUPur#h'
    'wq9Xf^Zh8<eN_znIw0?1Y|Jj(@2DP_v~ATPGqhOoPq1L;cnWnEUrlIRjVRd7E}36-ww}keRP=CjRrRA6'
    'o`?1;IIbAQm58U15B%97=Q~EPGN}<?h@GcCow#`vv1`Yd;04h6ewP)1-}+8V>*w6)#IE-r!nxZ~akvw7'
    'agG)-NUWJ3vusF~i=eW2Lr3ls@ufx!d+Nu}h)pNBvAEKX8U|<VZJ@4KBzjka$jAo*!|-w29pzfNmcNE='
    '$5V;pfQRhc{=|>3PVkV}_k23f@3`2VeaWc*W)a8WDSs*(N%4F^0Z9|wj&TjN^Zm@NgA-c>R2yAIF`b@Z'
    '%KG-iyN{AW?Wvg7`+JZUWP*({Kt@F%KiD4M>Iz9Q8nPn??JoSY-MD9~y|b8Lm{WLUTi=do72UhSpz`;_'
    'kACohNhh=^w8-%z8+Idi?A7hUsoRZDw;Px44!o?JoU9ig0y-Znc;AElT8|cX=V-O0%rgR2>crXV#|pMw'
    'kJ0?!-c(F=IbwlZ<R?$Y$_sXpJToAq3?F4avXt=(N7G~Fn=qV688^A6AZ5^NDSOX#9a-W42^+8afgiV5'
    'Z@u`a(@pkoOL)TFV}o>S&ziqV6p(t9NBQ@=g$=DYdp~-dj@7w0bb)3Ho@g=eZ8=aaKKfi~MJes)%6*nZ'
    'RQWy5!OGt3D!=0)Zf?WhB^^i&!AXt4?Kl9}VEpZ#gx^}%GI1k2_;#1EH;I_38+p5nz+3AZaEpM0+7~p&'
    '2um>vr(6Sz(d`F^XMZi?d5s42?kJuoF`Oqknzx%^-W|m98V==c5Xrk$HKlbmUURq*i%M?%sICaJsWIMu'
    '-ru^OZL5HieU?t;&0$$$EfPbxsy8Q7+MfEschtYQtZ@=xnw{0uyNn`CPr8yBkOl?!RfXXO+mw3tCm14Y'
    '1OL<r8D|t6gmDH&?#|FjL~%h$)NT6^`pbEE0nS2%hFzZh#K@?sIRTK5zwzDpa(m2xpWvaZaMjsFh^6ow'
    'K^r*qEF8LG^Vw&eI){#2{VeN|rdGrKJpefu@oD~3KK4NVFD@|Q57c`kYxHY%MqFmDNZ@w~b5hA{_ME);'
    'FPIhc3War^Ho5ff)I0v!t;%RbV>GHTcC0V%L|rtZEmrWY)J>M4dUmFHcCUC=qO4i9(}dPpx0EO#GjImB'
    'Zxqrhoz$wyh;2U@7ekmG$pnnAL{%nGRq;kQJwe8^#b|pkIU6@OoLsN$I<*46N*MANzYs)rc&G&aWP5Uw'
    'qUe`(os^LzSPU(BGuqf*kmh6pz{wSN!rKAzha^Mnewbe|2(q@H1=?B6zmtkKarE1kV%@4?z`H!QLvLJ)'
    'lOf3Su98H}`~Vqk>m0Ex5&lsci2Ld=9sLuGpVZWsl|u%Ld*VkxEI^9@028m(Jd~|V*tha0{-q&HsUUUN'
    'QS<Sy(Z2X*;bTy>nB$R&H_6G$D2<Z>dwz60oyAvdSV`W3G~RE?mCF+3Xo2zBVYXDR&-2Am!W8+$D;~_0'
    'F?^owmQuS8WEo5j2^>0kNqMXvcyA3`ZV6HvH%mC#+!-(5$jZ_b`3_^OnL&aLAm<{3Y5)G14)}T+&W{QB'
    'EduFX1*O4{KdRX00cAm^i{%Bj(xZ*iDOswU50rvywRO}!?~;`wJ_1tdv}50ygwDHNMD>Ak?v)8CNmuSJ'
    'A|;!<BrE6L@YZV9%8rZ^QtwFNsykt-=6R|C(@cuWx_bw)33tF-1Wp<bI#*cxsqK|;#jWrTmRgbSW3YLu'
    '=+yDhQo%xzAj+4{<iY-qeOQ`*5u60_F4-_{6e&So7{);uQ;7$^O<tV3Sb*7y#<r~Epu2X%8Zgjha#s~|'
    'EyZi!l<$YU&G>Iiu=3oAT$olc@I3q=fpsM`=o9&R7sYE&NcLf%;&~yBF2%`AkyqE{?@80K(le%RUgtds'
    'iST2{9C=Hol#Q}*O_|3p>xe9hiHMZTft6Ui1q?3Rz3?sucWb4t;UGNH4|Z;)#i^1xu)6B_bMO#mB)*hp'
    'f^M54yTr%0<P}-lC5KJqn?pOdhGZK<%?r_0rjQ(OqoFv31TO{;z~84)-JBv9cep<luB;|!v48l(_JtHQ'
    '^_>{0F!Hq&UqUP;Wtq%6A(M%?uDyLa96Q7h;@stka?%GysM0(Ncs%gEE6`mR6B1z#u}dRo?z7tlW2Jm8'
    'fdT){$7Coek+wwZ2&AHl0n(5bvdm7JpZNjCPh1Rr2R!2*HB9br42x_FGYzJsxhjvz+(iguTu)aK*EzP|'
    's1+AZq=q}U_Wo=Zy5jciU!iORib4c@lY76jQ9zLUKI)G@vfc6Bjx=YnnV8eHlpC`<l#cR+<4v-0*^A5M'
    'B)qpJP(G5!hAEmbFy?CWW?OJO70Y)dm75dFcOa7+7s(AsWN9X7)AG2s#rp7}a+0371Iq-?<va|+MKr;q'
    'mcW@Tn8-+u=y|F8dS{6g`_)n`gQ3KsLIQ;`4Zn)4*4LqFJt9mqIZ%rE1S_&l?=-q!2sswgsVbA7aw%Ec'
    '_fT$u>N-d+U@%2?kR)L8KP2Zv71o#}#Q-fjlvk!m;B*v%G$`q?p-|Hj)7J8-d9n^1ia?4m%H&rwam}X@'
    'tG9E|NX_8nB~Dsl(0nl&R=J)v-opr64f|OP`aBs4(6UtTrvR9n7Wcw|zF2_luCAoOh#9THY_C#dXIrr1'
    '@{%YpE+NBUhtj@DVSgvGUShEmCIxfJ1?l+`FRCRYaLp<8t73AHx`@4@3cdyg%_A(jG--1S9Y5&swEQgr'
    '7s#}x`%>7(rTiu~<NLCUC4F7ab(E6LxK1%2l$=uLlS*7)le)S}Rr6v{LRHJE43$^Ye9YYVWwBAvwOay~'
    'ucCLSp?9sIB}Q;|s-7#fb1iR7riGnqJ89N52FHFUd=4&=8?~mmec+IQ#|)GruJ5q2HR2)mop%)7Cgz>l'
    '^uiC?qD)xf?oWMaMPH90MZywN4T3iZ)_8&SLAlgpfm0Ch3|AQEn8i_>V=yhQR=zQ{b@0FJw92sg-B6aN'
    '$O6o0yfD;X3ClEDJZD+9$CC2MIDc)7`0XpZBxblEQDs>&N?1)wrnT(9jT9+yUA_@&nvC0k<J(QzT8$Iv'
    'RhqUYG|4VBs!tHdpS}?2@@f*vS-d5WB-EzZ=(qDZry<u2K1lVO<=8e2m^LNLCc8o>iQewYa%#yrT*b<X'
    'tQ^T<u}*@N!BeBG?1FRq42v@)@arEomrW=MMw1kKW5?!3g)sjLqi#r&?2_jMDKce)u2Pc2U0GL3%i5!&'
    '6vsW`gCh0F3kj4lg2iK^OCH_p3g#FqdHigR`aD{j3}-Z9h3(V`Yc&!jscV8&Fl~-QH{mQPlp|dy?u@fw'
    'AJ+&PDKIfJm>Z3-H;Ry@EDz(DS(5C2K36$gLR)F1e#V!1YK7oLXXG>N#{2r@E;<o@{XNjxkpsda>5x(G'
    '75tY^vV@#5yOsB=v6RbsS<j5ILV~Nzg*oNdD(bgaEX&=rr;m(K6Kk!quqVFry(qDVZQKiQd>2lsV9~nu'
    '8WCC;@C^E~(r&YRT0exo+mW&u+zU6q&+T+Kp5*hf0BG)S>HR>z^j($&MpkF9hFW_y-`i{R=3ZL{803iV'
    '?Ry*DiQwi)Jr3Uc^N?MFYvbiGhX(ZJCBehlLaCYb{aWCfQWH&UiJdBmW_83JsEB*i`0?tLa@8Qg@O@kw'
    'vbjmW1P=iilx@Pv6PP+S4wDa#@5fGoon2BIH{1g9OJ~f@lxMBvgNEBl?x>&Sjv7kdMMufqwUpd-Pf2EY'
    '$!$ser4#BM)6gBXC6!v-u<;J_O?JB4U8}1vz3ZzU`_j9<!QS<<>6D>F)c^6FFnAG6t~%Kb<(ln-OtY&L'
    '?>TQm90^kIK{>IkWW8>5RGT>Oc*Ue#u_QIbiaYUDTT``Rr_KqH(mKVl(JFUh5?sKZIN==h&?#~KMKo6Q'
    'L8l|Tf@&V|{I~s1CZFWhPL*38^h+nk`>UP4bYfhmnZg+jgkoa2`Rscz?tMNA>8|vVtn2hU)kaM!qn+!b'
    'vMQ?WE$y;lU0pa4Mk(8VBtoOu4E^VM1GytBpE-4FpJvg~Hs_wCOG~$K)>;2Pc(-(nIWGN;^n;gUrPiMR'
    '2{rPO-_N7zh91p#^tg+b9uj+c{JC}Lk-&L%yTz|6n3_rR%cQk{s1kVzyoIKfgrZ_QY=yRWZxzu}=J%|8'
    '4p?<OC=Hs!Pt5^L`J`4AAK?x1txd6HP%e$7&6?@4$LZ8-PA*+>9`%p&t8ZW#J2E+LVR3Y&`$Xw00rZTk'
    'g4*OH#_1LY&aa67-QbEqk*0ZWY<mQ^s8cfA-X~5k+W0{OEl3M5o<N=#Vq0J8SWYSEE=jR!F_z?#Z-1La'
    'UJClk*SSOq!^lSRou-v9@E9d{5v@%qr-}r&1h*OG$Y$-bR_RLHa&ZwOKmB$d(!ILjB-Kf5ps7^O^J<iy'
    'mx-{JY%J04vaJ<<2%>h;%D8W`u`+Rt-=f?S!eWN5<>QKEyY@Y!xtupHnd~-{cG9HL8baF*#nfv_`WcYS'
    '=hc`t*NwVF6|5Qcd5umb>-I|e<nsyipV`cdaRi)uQp{YE(Z<@9h#^0%;YvxY-zbkZ+l~2Pb?Wz)P<ayf'
    'fzmul$<|R7QRf?@$8x$pOPT(X=HoliPOic5pOU<kG2RU6imG2@QDyP7?yXmq9WAm<S6;+WMcK!#lN|iO'
    'k4qcWk-v_WmlZ!XYGpl=HhQkmB`oA^13R4r2wBz8X3_GCUo5lg4E1;or%RM<XaF&30P}OjOd@KVLCxn('
    'GZQv{nFX(k8B?Dm70q68Pwb%Du-i6lAxac4XCv2MMPufn#GPAft<~SihYyukmsFXN3#yO+V^6SW@Gtmv'
    'N(>*k{+v3zX*x@!REXlviMMqQ5#Dd+MaAayci7BCm9d1g4}R=m>ry3J%st|OIsyX`rXB%zP9~V;6&=9T'
    'BO1pjjkkoDA_Kv^2m1=aAZr0+RZ0c2r4!cz**{X+6`b`*W<XG3_G3pGuW&zVuX0mkxNOx*F^-!%g-h)1'
    '%vAx+kVOKvojxcLl@HyK(t~-|$Lx|Ez@?d@hCK0}Qwn;LpJB-=opkTIh&PcCR4l3ZS>;_w&0vz6z*H-L'
    'Nlx3?dy)KDUUudqR<68$Mq8-}&!<xL-1a+qRpUC@(n18B<+SQjp9?fmJKNuyl5-*P8TtLy58uvxx9x<J'
    '#T4bo8~pPmrqi}cTrxxDg0}+v>0&xobfe$tyxqP^a@smwH>9ORCmjqkLPFFhyCF3zIk{pY_m&`v@PLb0'
    'ZgU;5KU0FL5!KD)tLnQ4O=VRx$&g;Nk&7HAE<oGZV53dP_0fR!J=4oB<fFLkqWS@rGmWpxmscb;q`e2H'
    '3A>QHRbp2Jq9iHKEr)nH4==#fkIIc)MUZKK%_XIaTuqmhC9?-5R9j`I+7*gQZuVwQ*{xMtlG6shDyFOC'
    'Ey|`&^Uten)m%QC%rdI?fwOn3#3kwQ-KcQs8oW|R-9+iqQ}o(SlO>LKV3#yxmNa0MY+{t$U|ei}$hgub'
    'sqGIo*#NQemc>o9K-^^y#QV^&SY{W*`fU)mh5Myd@f}8T?z~m8%tm{K>!eLK+}lyJw+!)ZslDC`cv{g?'
    'Yx_ID`6hj({VuglWecy}?p(UaXrz7F-QzsNQ=OCb`_N@<N%QWgk!j5+(wBzScV(=tw$<eIhg;FuO1gJ<'
    'kGf!g=~CTbMCfzKT-r^O#p}1|Dz_fP_B<^25>O*-=KxYRagfiWOJei~D0dBQIHJ1i_B~T~hPtWirezSv'
    'qeF*ynx_wGUmuKmu4_2(PH&{SF4Zj4)J6{cqFbBDdoJa3KzpV$u<ZVD)U*54wuwQhGxS`~F$Y63vh~5h'
    '@JxGTdP4v`a0flt>i2uY{-|%dBSPGbfL<<wcM(8)Qw|HTUCEn`VrSyZdH5m1O8*t9$Xjd69L%ZcjgXGs'
    'j>*MX`M&)2D{_&{X=|Xl#Vn0~8h((n9zogXoEpc=%?p+>yEV{a#d)S+Wh?>fo1K-G@fhBF9=de(Lbiqr'
    '7$}Y|c_~MjBLzQSk_)<aL0y*WINp9GCqcZtyQ$#G&qK!A0vOo7YJ<8ZW92j?Qx53}{+38%>GYp7aM|A6'
    '%BC$DwY!xzcOh(=lQnlCYNSe<B6lJWMz@hOHCFK^yAve9yp^<yorz2N((-PE<t}99Zbjv4NqMXDn!<t2'
    'bqzi7@Zm${1<Mxo{Et|}MFa;U<&wOoN)Re;B99bs7{~zzCxZ}cu)GI{VS9~1S)eysu$&5SF%b<+Belk2'
    'cw;SvevD}lfhV)n8mva>ChMp*CBcGBkSb0o-bBXMSFeFk2PXL8nsP12KE&w6_bDV`vMREC)KNZN|GC-M'
    'fJOEd<>=)JYc#6@y=5l{+XKF?VUN@ZC*Bc@HNatwGT6OR_&3qub^Ye8jfs&ROObnNH#a0hZr|K_Wv0FF'
    'DRKCY1{hyu_wB#p?5SQ55tYu4LzBg9E%{O`ECRBKSrz$OM7-3S9AnRX{u0KlJFmLW3n{ma*)BmTR@&{g'
    '4HtZ666cHw1`s)qR1oCA5oh8wq|KJ7qLk>=^xp4)(52IP17v<*&NoXmzPY}YAhN6UZGD7-nROEUmeVzu'
    'P&8sj6ubL~CkiA`fGTFQIVg!VB}G<-i?f)|!B$J#_NtuM&_`tu$s|$of(`1XxHM^<Y$q#f0u<a;Oj5yx'
    'rf>XQQ!`5a9gi+-O^hg!#>&t2&OPJ9=5<Yjs-_0@)HAB`SWJ>%&PC$ZSb0@UgTWFLtSdFkpxj!keo`)I'
    'K<Dhp6ian*Xlm}wU;H9@lR?HW@n7JBt-&s50LV0VN_iRi#r*P6(QCoFu4z!z*yQbd4c@^XOWoof?r@zL'
    '$@WkB(^)u=l^1qI=kIHEn6EPnjPYOy<UtrruCiMxS-B68R!SJqv>KvlTfcQ6CYP_Fvid72sCtXwC0ejf'
    'kwUl*ddRA^blD9I%&YX0+bgi5i#a&n@Xg?=W^y4`5GVX%T@9P;Ye5Bw;IF?YesF{sNy*<2$V71_B#P=s'
    '@5|-l>T1m-vKB0+3aj@qR*rwSATi-}E*-1@;=5Rhe3G;a;5DAMw}I-`6)Q|UisuUl*pOG%`;J7HeCG9S'
    '2>}38cQ~zJEteNI8v5BCOsQaUDn#nIPHLg^+Z$2`M}HTwfwHHG@mGf{>w{V5)k5(^6ffmKv$WCx2~8=7'
    'OGG6m&^Zt){ZL8<wVY{Zv?TH;OZO`diUd)A?tXNXA5hLJmWe7`&GKh|CNUQwDn+cIAm{6^5VSMRx4aLz'
    'KxT4T{^;crTXIBZ8A@iO%77qe6UF@65sf<=)nnbB0pGlBX2vsaX7K7_hl+~kg`7(htl$(cl=rexAbIM3'
    'ByZR%vX(eJFUKb5LQ#I)yss(>X-dQiFN`e(8DHnTwUdh=L@k!U`asD$1~Ae7?K<AYlG)JU%yH7#>|o4l'
    'I{oDjp%2FSbM&Wv^+*Z_Goz^fS*=TPAPlX-G#`n&=k<Dt)|(LeoyW|H3K@0*rxV|!u|K6s3?63WGn!87'
    'afTDO#+^P<%M*JtJCg;=SvY$5&BG(L{u)k`N}kF)N@r27T4+S3^Z^rAnV(+c7CIOX^Z8;Hi*t+!?5Hbt'
    'E;Xg9yhu^0tY(!J-jx!-NJVT`bRON8j;xDzqCf@H66K2QQZCGg$wes!=?{Ov#0yU?Rbu_>P!h6I078$z'
    'z~VPqH%gcF$U#Y1@V}GGbz85C>l8kWoVhRU#;4+)V5|j@H%)5TWz3e5b+{}lei!C;FK+NNN)ti4#5X$-'
    'IOZsp1Y@aiaq*3V0?lu~YkYuvbLPh?!k;JS$HJ7&9bCvdpw7Z)r5mGC+F0{I3L8&Q#$mD~JP4_jyxW(z'
    '2Q|*ezSCVqjsGkJgCdFLQ`e6pR+Jo6JShJJ0eL#^@|=XN7aq{~LpXmYCtO~p#T6ZctB7-3kYd<J@(7#r'
    'bC)xcm}#e5RSLaU3&OMqp@gbFIc`bNEF4)ee_6H5mx`AcLMhqroqHn=tNM$cCpFT>O4?<#=IMRwQv*t?'
    '*koIDP!2iEpgiR7+_}s;QYK7l9brYaw9w*o5yeS=h9q+iWms~OStoj|e7N+%QiA<W!_yL_ma|?`$(J|+'
    'h?)z*7gefU5wV)Ygs{7B%)6FhWig&}|C#M;yw(8(gQ0z%TUEeTsR2QTvzoe<;d(g&C6E5o=0w~9YLfPO'
    'ku4b&S$DCcN&VPr^4}KlZnjb+1N?+GvruUynOpVN<+fm3h|;%iDM_rWq~R2iXurLST&y75UF|(eq7Xhl'
    '>*kc}0wyIT{K(<{7`CE{06P=<z?)#5R3(~#E5`FkG1F;*sM{K4n2~!q4})+KDd?d|$SlvIV<~D5(l}94'
    'U0f>eVO-IU;te~7K~3A`Co+8Z-%4wh;8Kru*F+GHR4if}T_(L()8%$#Mb}ocOh(u>8dk6+ER|h8<c07Q'
    '=`|@C`a+pa6w)e@(Qe8_-nb>4@VJL1xM1t@uQ~SVCNacjDr7G&lAEeaH7O$|n1aO9Lfig5t$ELv%;)4v'
    '@!6?UcI7ucZBivKsuV*P4JSpAc2+mC&PS6o<)qvuphi#`bEVk58JSE3Tbdsq&*QM-Tf{UEIC1ZN)D01A'
    'Ha$@MxJC_X5km~<2gT!6=2W?;`t*g(>vIIRsAX}4teVb}PK6{4Ar275u1WJUq>LxiwJ6#)=NXwMmsI3='
    'bD9008Pn2<zHn%pKL?gmdp`9@lZvgMD$hpmFqQK<s~LGTn`I><pJt6!*OiUz^?K%TXbm+@@0l9)dZU4%'
    '>4V;&XACt<Gn~FnHQVS}7S)J1u<3B9yTlsy`+eOQTKa}}sFo^6x<jqsAB}9QZ+MQYYbG@{yEimEyQjH*'
    '+Zhe)kvH@VYhb|t1KT5DqEpv|8EKZ?H#dd5vUp_qRn>QI+skDvP*UB!D(zb&I#@Z_>n059_!gB)K=N>B'
    '{MuxGL70vc)#<-f4N2?;>#%}1LSHcaM9D?v2B6`KciCz0Ps!{Ftc#ua#A+P6<cjr0tOJwRJ;{b`^Kqqb'
    'dH$8ObjjMV)PZE0Yub%fqHMRjG!4Og{?N!q@uB}*_bNeLGmEP)K8y3kc=sg4Yul;#^ujO({{wp%fo#8+'
    'hl{{Hi?1fM4Hht%+Af)2HL$t{r~w!J)Ta|SFJr+!n=^vk?<%#9V;I<<qsV@O_b0P~*APoK4N<+HJ=6rT'
    'l=&L3FsI;ZGBqZ_W`nl*sGOg>w;i^+q)amw#BL1;x%R`(%!k%(v_ySf-jFJ9?Lsr`Sc%_iXQb%w=G6B+'
    '+#eZ=d#9#%14hEVu@S0G1QF}FpGf09g6}2Xq>tFRWpy76s~y`_>&&X_+uBv-&<raeP!d98rQJS@=j@hG'
    '@{^V0e();=b0KP6rAyJrsv@kvI4c#1Fy(5NM<|TU&<41wD620JRUZz!_{S-?qJDq3fWkVkD$w7pL|s>s'
    'N5bmEa^g}Bm3@#5SOe`eoY2zSQ8<rZUDaq}$KV3_!g#u@+25XHYRz6`^$3FdnnvJ=AcoeEp0rruIV%DL'
    '$UDRH%Qh0EPbNR$VfI+uf9TZr?{+VSb|Hlt6GBS^KjTLx4UH^y$}Cs%aSrM2w(Ko!Rx<BUFz-k%XM(Mg'
    'o|1Y6-AbaUv%GZR^+dr>86_=or<zBK;;E%~4(rT**J|gsTBo-8%V15(M}NAQu7FlYi3*=X0C+j~9SVQU'
    'z#ZVb)&98#cD(ZF5fEHQmcCB>qXyQKo_M1>!cV;!s8kY)t&y~r<s`c7kAuReSqtJiaEpT__m0_ZsYA{N'
    '_17igI0MU#*r5wN8HH1-{NU3MvaG%5<h_5vve<xhoOf(k38DMOSZsG3whIQ^4S(Gcdo|2mm8(kZm~3gu'
    'I|ntR-$f7%HN`g$lKKe+!=@evOM}%$SN-^(bWyZc5=l|_`Im^ORh<0ocSR2!c44~SNiYjmCIi>Y`)ept'
    'y?g>nCX@Y+3bt|^?8!%J5C*iN%!Q}n{FpeG?M(JyxRlKY{2m)fU|MqnG!@%@^VM*}nM^=0s9>%(l5Enz'
    'kafnpMQ}W&{!Sx_W?z#2Rt~q@q`x~$!IPW@(!BhZF1}aF!KNkfT?ybO<?qThJ$$JAn$j7z{-Gad6W{S;'
    '4E(TS{G@*31K#qP`VrnLRlIpPWjB5BR*r;QSMb_jv#b}`W&pu0BH)Wi*_W`Ehm27l^12{cQ4rheUEs}G'
    'KN6Li70w2YY!+w+aVLoNhhg`C%Usv3vuR&tq|M4l5I>08A1>(}ytPjXqeRxeBb&f=Q(TU(_A1o{viFy@'
    '^9?ed-B*70<B#oZRh|7#r?ExhtH|Lwz|DZY{tOZ#Y7Dn?yX_{kEpevrU7pR$d3XULEJF7)j~#K5Xn&*p'
    'kYttFQ%&V5RanCJGjnNU<GL}a(lGm^d+v#KHL2gqp`hjzOk&<=3uUnPd6nIo261T_o#n(#(`;7F?20Hj'
    '(mosAwIp0bWU@xjxh!gnrc>Ih^}b6hRu|#VPe_Sn-E*tw%WZ~RM@4dXim^ZYcRtpSxI$|tT6dpV9~lE@'
    'Xxh4|>4xRlL(g;ueM0C^r&dqvyPgd{Y~3^Tk=Y+n)7JW$rrUVE*R=YZ+$UbTOKcF+9ay$)Yg*6sw1GM3'
    'k4DZ&*8!?y5NALQ%^r=YK|Bj5;tfYO?F~)h4YZ+d8JobYyhmK4H(b_ZN;KdpA$eT)+#;9TlvT_}AjcnP'
    '6hvp>P*FC&W)(Vi+*oKkF{e&AcQJJ>x2RM0=37?uTslOG<x|EAtD^Eq`skD7G)+Q>6uE~}sl+&Q=HX-_'
    'Ycza4Bfr1;fgN+T$;7`1rmT{wI!RhBL^I;BY%G1yx&4uR7DC;2w#~Cp^Bj~?#KeD3pU^1w15piGq?#QC'
    'Y$ZvySuHrbWYk9av{^P?IXZ07ae(E>4)cWeEO~qTYGm@|f>g0kPb%E%c>JcL@mjTLgZOno-h)q#^-_6M'
    'W)AzP(v+LkOTMSfqu8%eg6}Gd>GWhuF6da<=T({24`lKV#&l`q%>7v{k5~8>>t_F*AH;PctE;a(7Mz3Q'
    '2}KHMJD2{%ozogiN@Cy*OnK`mt@MLdV7|69)LP*`f0Bz7cCfLSPDxpqo$)u@LN7?(i=yg$j5VTa*bVY_'
    'dbi@CY3b0saM-bIs4p5MONQMGhE<0ksZD~NuwKk)Q0i*4HH}`9s9=tk>{D?gyd%k|D9fg$-b-7;$k0<9'
    'QTn8l7)^QmaRN;UiY5@xke?!q^|8tK+uI32$?7yyYBVEXa9qomoi?K(alhUM^-Jf}eK`-Oeo&{a#@)+4'
    '+-eoCi%XV&^7f#vm322p)@^JoX<nG5GPT$0jJT`<sRSGIS`E^?>{osa{IiM{WtrwGmKkmP?l|pr&-fs|'
    '!hk%6A==Vv#owCW_U}<23xSGHGRo;PW)UqjSr{oP`6@Fyi!Ur@pM!@HAF;~<!`N>$1<H!*U)SgW%qm>-'
    'dl|{H_|Lm7Dci)k#uEx={G=3`mE``((FPLa(oV(F3aM0zPgXX(-2UvaRae3lXB`Gdvl%7Wej{gpvbSUc'
    'dE!T88IGI0D-+aXmZ{nfy~cOqysMnoXoAvO?Evuh<|iJTF<+3oWA9Q9M>nvkE4^Xm%YN)=KQhspn`qky'
    'e|fC@Ji}T{<`*=s!C-s<nOj;2+e}gY)2PkCbd}w1C~tdF{!p?TR2;o6&)vDcPxQDuE4@{J)>3Ws-I?fx'
    '9$`^HX3=Gc_uVsgVtw=QOunpQYlE!Q;i^C>w{k3`K+FgAumugnk4T#wC-X`2D7Oz*iv1X;J5!cs5-e(^'
    '33sU`Lv8=$)(>Le<X3nND#UwNJd2Mvb|MqRHN3Z&%_ct35pKQ`Ide(_RXIs|DsKrFhQTyPg*kU*9%FYe'
    'ly5KvkbPmW^-ZkSvagt0%VXvEcMB5Zsa#k2jzpLEo3x}Jj4{8ke+vlAgm&$rBPX2EU(>6kcGIKUBhp#u'
    'T#l93CqX<g>ksEgkJE0^^{S}xY?;jIXC=sP%$Jg(ZrD0R*o`%ADg@#rXfsY8Fm#zd+Op&surbm)xj<s!'
    'M<4U|qD341NPr<;zk2#$sNhXiOst_>OXn$>zeD@drL#$Rg~zh6IWD%y4j1sdeFbc-)?QCS_kgoxA0Daf'
    'O*LC*Z77Tv3Lw}!wa3jfMUJ3y@7|%whUsB`bi_L}{yr^p_bJ1<DAN6lUlbQ|7m96d5HL-ct0@D-$gh~^'
    'G?t|qGRacA?{8tekgKvP1$Pe|0i>=qGkhcsNY)FKS(~U1q<95+81H@X!zNVbxa|mo2srpsYJvnB!Es|j'
    '#+;lV?cS!uf2Ipu7?ux6n~)crsWtk1>yGlRDuR>1#D4IeOnkhSBZ-4^4(BF8-P$l2KVq9f0at=W!+I`C'
    '8Sh#momF|Ita_}H`IHiAtE=q9Jgt^=$!$f@(qezJ4c`7vWGkc19T2C~y-&_wKIOzVMm`RtC4q4PEp^uU'
    'L!(bJynvUB=n_Xq!$0S-E0<v7M!e$5d!K$dKpqCuO7X$<-V!QH?4p=xng)Eq0|3J@;BCLZA<nz{o<K<l'
    'A2gyj>uo99$#UA{N|7Kf6pxaPsY`CZOT#n>4{=s;m^uPQ*mdMfg)mD**dsOXmmqX$k;}Z4{Jg|kIeT(9'
    'bhVs5S+k{csiQOR9bV$(!xGS~SF|dHxxCWi-{KH!OPHLzBsHbZ^%CcdD6ILmaIM&nI~RG$k>h#E=P24m'
    'H4Lr_8gE(%GQ!NnpZHCt1mr`iYzqqlPnMv|1GrJ%Z3*(eiOID&4ZEU339hCm)YMm-sVU_Tf7o_qUzG^@'
    'Q^C)@voo-K2&TBjh3S2gCt2CCa^fPhKh}hn4&+=TxNEDmp@3{<R%We)@rv8i;GKRryCiceCr`KGA`Q(}'
    'nD}f;Kx}l;+t4~P@23`J_wz9J9Zb6OCVsGe8-rGQnDc^<bo`M_XA>&%f~%;f#&Z!qm6mZ5MGM*%B*cDn'
    'Yb+(61L+{SOS@#ij@3k=E`BzSNg=YY9j~~XBKfxWX4MIXovk;ZfjQ&r8L{bPIbSRy@2Sg6a>%Mku<aoG'
    'b{M`>u}f@4wZ%qy#I8k{pw-`p0cFRvh$3}LNdP+xR=_{P_qX2Ta;a&Ak}NsKWPYQg+TldvMW0H3{3N+V'
    '1a=ks4ZA_Q)3u1LLNhSiD*l7IM{(U{;<&)vNOr*O_*Y{qK^b-$E@FE2j)EV}>ICqGB&l?r1_29<p>+~9'
    '4^}b?uj^g*Y0{{?n~Fj^D2605=+GJZHNBE^j-PlCd`#(?7foeKB;$iP2L~F=zp=uy>F!DT#XLc$z$?f^'
    'l_k>&e5i%Yx_SYiZXOBguN{f2aTfDA*j}eXL@iYpdnE433JTqJJ%@)0-jqj)(K=?QAJUg{oM+b3><iP_'
    '5-fKd8k&5eHR{T_Zyy~Ma`O78PywxZr+6nmv2>Ssy+?dl;G^yDW8Lgm%khslagPs+VovhKDVg5#T{+9G'
    'X3Eqw=qk(bly~na*Y=Y?)hagDtef1Nm%M8y`A&S~23+JD9n~|&iRdPu(%FPu2{&1S?b=l&xxIJeZ11R`'
    ')V1uwtAzq*5xU%*DX^oRl+a@Iy9EwP0#_xV$3Lix8LMuecky|tmCvR=C`VJh!dG(3;I6F<`4Zg*=jx6E'
    'yIG?U;Y)nFA1K?jG$@w~-}Cl+(n<&aZh>e0VSv}SU>_zR0Gll#Tv$e9HH3FpkXQ6WY@#HuQf%<WW{`I2'
    '`dsUziHp2Dsgt%8z1_O~c}sH1wdj)4xa~(TdHM%NPJW)w7N=f1Cf$18OZ~(PbpjDu)d2&L;Pvjy%Sj@Q'
    '`&?cwNhR7<dASuuAXLwvM=@^#8b=tR+ZJXT+f}ZYOV-`n(sL3Ef;Vfo?!s){as5^qMyt%y?DxiGU1PBp'
    'g6xumbPZRumt(f>%4*$#(R%mgl53l+yS7;GvVdl7qhyV_`fIw%OqE^#GFMtK2Uye+T%Ld|z_&DWx4wZ{'
    'IwetVY4vU$FO*;`-<7R=&x^cmU??9HPnoyf#kx(;@P#ytra`W-i;Oxn(n`YN{N9tvf;Q|A<lO-&6X&-A'
    'Gt_3O1hQ|`6-bZas^rf|BDZ8M@=DcxhKOEv2+P=&ho(EcN>gfZn>%X{r?U{7Zmex|+jljKdaiBthK`}>'
    '-oP8#gT7|ix}od6p61$vo;w&?J?fe^?Yq4m)v2xZO<nKXX1{j}H+QMwt!C)Mp+h{waa?og652Dpfo1iF'
    '#?UpWWf%@My`j+?d83ihC*IH<S%y2(%^|fc!?SM#yRz|Zt$xbFXUHxhl@e-ex4tb9NoK)R<e|v{A@@R0'
    'rT&T-c0}!&9KPD|989ROQWusuZ)T%)mDz-VrIQ34)mi9A>XgjdKmLfn2XUt(Z*~7j7=gD9{4586Y7^xS'
    'XtH^dOes=ShB%`anAsDtbk~}FWSgh@TM>PcXlnv)p607a{(2jlUv*kvyIbVS5W-^;yeAPD8rX`DevG?H'
    '<o}-5D2u*6;KC}ckr=oBCH!c2ngIhiRN8*v(vKkW*dC+5U0bm+8s$`}(qJ*AbMV9J9aP*Ho?>nD!pLX0'
    '!Vi_l-@e54v_IC@3=A>qN98Zrma89pH@@sD!1erttK@@A>R(*Oo#vM4dkWhtG=DW9MI;b)8osCPIFzwW'
    'j=WA5E@J?Q>pt@X4kP!SW|nzfUkNrL4|XRGb|Vc|_iN+2@-Zuld#Fsw$F^2mu@vM1uebX^(VJTY<I7|T'
    'B_jYeTHW=0Ql@^;&ZDZEVCv^ur=$E*(Sh<FJ(7>NMo`v-5-84nHm9Edv7PNpN3vSjLMtRvy(ZutDTO=H'
    '3A<JaaxyvB*@)NToHSb4mz218>!SnM3PM&~+<oF-_^~WoOM-@!s10|saybi^;K$Y;06R?Z)NRpZ0xMIZ'
    'lS*CTm8rY~1(v16!b(aI)@8Rz=&(bft`gArLpXnjeI`E4{g`6Bk?>O&wf54gYvEL7tT*8E-%t(kGl?#I'
    'eH^^^=OMc>g#K~l(15-KDxjU>{p|GpM!*)1<4&o&aOn3T7skmfYC`1~bF+cvEMxhy_MFjNKG4CbkbP5<'
    'T&e&osZ#pQt791<c(s}R@<<AxrR(TyY{?NQ32gu>#}$6lxN^hQ$NW>t5Em>6_~s;t-`*2Nm*2)x3xXw_'
    'h`R7~Il6d_e#M<4NlR-!Kq@jTfJVbQ^%2&QC_6C6ZBWG<Z4WQo3dr)fVzZm5hHP&M?3|;?2Q+hna6Sd-'
    'zo*RBaYDQd4Rpy#;-D_w&FOmzqX!oXQMf-ST5-*3<d6xC6hBs_uI%PYHMJufOD7B|&F~V`kJ!KC`nY5C'
    'SAr(jsT8SB$pYlN<N!ddV}=G1qDaL*ktCW40OWI@bK+Eu-ubir`cbVy$|uN#4`lADG;sHu3}{4GfpZBa'
    'Ah2n>xu^n9w-DRK+fzjCG}KuWsF0jVIcQlK95*g%p6!0y55`&OHl0vSz<fOiiMc27q;V-IqIz>OrR}L7'
    'e8&PzwdZb{o%Pv$OAI8R`WlPYvp4GvDP+kraM4jky1cL9ujy5LNvI{7(^YCmfR`{&F2Hx+2aU44C)kg2'
    'zav?!;m}{?+5MDfLSx6i^N!}MR7MC)z|~#Xl6({kY>pbZm`<dp@MznquUHc*$5c1<1QX7kkbobrM9op)'
    '^`E64;4(+PB9J~};o=8NpUt*kd{kQw#9>S(<E9Qa>$?4gP3852vdcvIO-=Bz-}wv{@&j%qU&zvSdg#yA'
    '=LmI1=ML}yo?<#a-fCzg*EtvteMW<e__D2aI-diw*0FN7>(bZ3c4q^_srEhzXY$dqaU?!M!$~^Wyt%go'
    'IQ?+HeiUG7aMtO3|Gtvm4vMH$O<$hwkT;SV21l%2UPYI`f&nZS=98pLUjeMRoYWxP+-<(ZV$AOH?F4N8'
    'JZ=^2J3phYp8C9SjF(Nmwp-T_-g7rb`Pr80yRuyb?!GPEV&i^7lkQeNHHvu%GE$?GH3*-h=~SpRL+DqS'
    'Ak>JeU==;^;vV@x{J1WDUI9g^(S*`jJ0L;G^+Z%#eU=W@UZU6MgJU@dci?#jr>Q)qq}WJfVS(#rBKDay'
    '!mHqUDRPjk<=#lrqP+Nu5t1K0CV@jI6Y6#oEm%KDmg*N4@#8IJyA1^o%3-Tae0-kqt7JXyd)ye7MCkA&'
    'S{XsBCG3=zcTbH?d_8=qJP(y{;yys7syGu$g2fD5^s?XQ3Q;DYCg$~z6Pe~z@1vz$a9EEgl%+a3m;S_s'
    'O&lw1TZtdY+s2)F*sM77e&-%$p0EN5MFUZuoglb<F=H(d^NnD;yh|`0=UX^8BA5$mtYl(KTWE5CzGR`+'
    '7SLbar~#HD^pZpbKf;tmZgTR1#ijMf;hdIkt$&ZH>1*z*>$>Om`c6+Xsn)Xwj%HaS!=yt?GxecuS*|_u'
    'EXN@|$LbBOq3&rT+H*}}>Yh0on&xJy*h^Q{2Ys(kJ)LTvrVn(dKeYPZfQ|-+HPWatfPcJ^OATFfiRIW<'
    '-?oTlI6cQDJ$pz78(vkfzNMag%G(3uT@2XKqxqa%wbN`LH@TjXyJynr)XDd0@iy7)I%yR=cOK53VnvT4'
    '$U5XvpTM?CwqMS(-zlbdkLcQXu4V1lN$Y1B{YQ$85lE2Em}@^#Tt8xY$B}ahI$=T&6mVaYv^3&IAX!;t'
    'CaSSVm}U>EKLYD*j^;oev#T{**c0DT%GdNWmv*ci|87CzdhMuE10jJ%V)((*ftMZTvGSU=ky2`e(p$Qr'
    'oogEVU;d=0<fA`bOrPRWDe{S7N`fIXtvEj}OVQ2WFJz?)I`uacUo2+;k1DhKoq13l88Em5&Y@t~Nw}08'
    'R{;0T+XET?WnoQTvb}gYlY#CkXDA;F+uxA|E{f?4gZONX4-@FWR5)nmKT79=_wpXW|KmFBA!XY9DnhiF'
    '#DZMePKd}R{I1CW@&SA`Du(<^fgUMz%YtZPrhM2337A8^8;`{MBAx)7QA4xBfU;)IajxQ7OyIU1X<R0S'
    'byA+>v;67W1}v4}0lVubZX=OJd>PL1&YkkgpVE1xOu(DO697z*KSNLB^+^pHb6MYc%!bG6lkDoBTHnG+'
    'GPrFz34@CWctRn8LO+5pEUtSzjGS;ryIG3=_8>(`I$pew1a9iePkfJJwY}!79e&M9o{hs`h<2e8ZK#sD'
    'z<1!}$yj+||CTy&7BP|xC}}h>E_Y%V?>~|Z53g8~3(7ip@*EG@5P+~f{{jOaypN;wosoZIG=-D9bDOvE'
    '^7mo42U2;Hw!3;k9eD~lA!pDZWqKBi1OGN5#abRhsegv71!QCkvr7hlq%sMqW*^EkU=kV@by!&g%E#%u'
    '2RwjKv*2(hneT;}aV=LyKTgttB}-`!4A&$ip6kQ>qUOcImE&K~0FV7yNE&b0-WN1uK7ztx=miuj4o1~k'
    '&KawZc*TUw_7JnYIaw1I$OX?Cd}UTMi7!H&2PiyYt|?&5_ek#M$?&GooWtllcB+h+$+-x4ILcML#blC%'
    'ICwb<JUw+L3l#k|HYEsy2g3Sw$YcUGui6y8DyuWr2DW^en(?pHf%&PDgrWfzJ<xOM77dJ_i5wZX`j<jh'
    'U|7iFWyZcDCwZ(q2^Z4Dd@eSXa%(O|CBjmg9Pe6;#^>KIkvx_NE6k&#JgmXH0!VSh`=V6XezN#<MbH}1'
    'u2#f6w+CFps;os!7btN-z_Jtb;*s`?;*mBwDBW7-TmHlvN0Vf=`yMwj*|e3fMBxPG4}aiq3)u$mi{GTV'
    '3Kg>FK$#U(bDg8GGH=zre7n@3fE9L&8Yn=`?+vTf1*j#BT2aiGLz0Oh*h?%62PpczKjYQ@>fEa0g;%58'
    'DJD!><o`sh6rDfEU>yEbH6&T~n=VIk<Ew1aB@29%9Gr+5W;HEqtadCX{w`(lISC;I#6dwkB+{Yw*>%a_'
    'kyL6bFYF2se(?*XqWDA_2yJ)nkF(2EOs?WgmgDn+=lDGMRpJRhl4%$vDN|zi4->fERVLH+fKy|uZjMpe'
    '+!A<6RCBt5yvMyguxymhy&{$*J?uOyuJw2+K`bMl?E#}TB8TLd45%!t#3-+J6)-tS{@V2;2Y3VHAgAn<'
    'tlA(<Zr&^PFRZuL?OZc#Un+`_!cBIhD@5m4b)u4~&@Fmf(gZ*Q4sMkm`IH&1X&CFE9MPzOCect#Hg?iU'
    'i(OcrvZN#cG4a*xeP0A;k%6--3H(@`#iTH>)+k5c2^SwWz{S#1d6Fc(TrN*Sp=qUcNx6&}?h>HCI#j9x'
    'HCp*%%pIjUB)=?ku2_I1d6(|NVaf2jpXPE&6Z0Bh>kOgop?+c8iiKn}arYD<0^UWE$Pw+QhAfSPN~_?W'
    'g|uoXXo(9LU<ikcxkICeqO=EE$LdEXV!0nt^%abv*Y6u{pY*(*NrnSQACaD=Ii{`?Z8#W=T+cR5QzLrc'
    '>)Ac6XF2Ym*YA(|w&{7JQGe3}{iRD7BTctSpI8R54a*!lx}}@Lp6hv*W%iswkMuN{8L>wo@(kTJoL<iw'
    '5o+q1XOQ7&xG~_h*Dz||foaJdN5&}i$GGm+9%BDJowI(!V`X1gwf(L7CRDW$s<*n9)L|qHQWMo|j1^VD'
    '#x?H@ibd{&{u9NOSb`t!=#&HtGTHA+8Gj<A6+(z)%^K$&$QulX<6`u6;KwqDWdjSW0-A#e?-RRnFe}Dq'
    'sh~JMrw(@a#pO3&_GN*Q#g&rQz5n~m2j3By)bwXT0Dt_K|NWo-%YXmJzy9C<-@pCu{`hbH#ozt)zx@w?'
    '^SAeo2L7BSGp`o=MKXV3%qq#uspE@G{wZz!-~T87`Jevlf5#>B7g4-RBN<Dkf04vr*s;KlXP4oJT&I;U'
    'M)FUN0{-r=|BpZZ(|`BJ|Lvds>A(6vzgWmS7t3kc<1eE53u6{Va~8Kq?gOX9@<l}dq~aLG2nIKv|L$-9'
    '<sbj%fBqt?cPXny5%({m`U`_r#53@uH^z?4Un0&wRYLgFzxf~k_^<vKE};MPum1I){`LRxCHj1K@;d8%'
    '@kL^PVbr3;&YRT<oqQ42Ke5P1W=&)K<DdQ)U!?O6r893H^hGj%;mQJ6K2CzsIV)OK#EIdDOByIw;i67;'
    '>6UXDh7nc2Nc*2!5amz*;@|&=|LJdds5@_z|9}7YKl|f9|F?ht-~RJI{Wt&D-~W^U^iTiU|H_rZ|MO4&'
    '<1ZRvg+{15M15+nNV&Xzdwsq4^62#V`K$A@7q3qrAD^GT_|2JesC;T2&1Mh3orE@CBp`F=5*u-@E7tB<'
    'nn!8RqMAVlwn+_22Ypl1HFMN6Y~AX^r@E_ogu0sE(@ou@jy-g2hYlReq0R>RpG!%?8X=zBH+v(~bbG`d'
    '=_8kzJ%^Yk)isMajtj7eMNGpn2E)E#5Z85_zGt|^c86q>?Bvz?!C&)whWTnOo<E7%4eUJP{%S$zS2eQi'
    'R{?Y2my2-jW6^;(PyEOUVS}$8^LMX!so17~UOgrLgx&Y4SMg>Qn55`!9*_JYXY@!qFh7d0yKLPWh^vO5'
    'gsi+@W4Pk?zZsQ{mkCe)dLlZZ4yc`9`+-{oi0?E2?=t)lJ!PB~HHO4XUTzUMiIYJ?>?6P+_bleLvDIAQ'
    'FNX@>mG8-nQNp*R)@7fYB*M2lggKkj8JSb}42wSUT6{I>E??$PY|<J0Q&<tZHY4hC)>%}&nd18G&;?SB'
    '!YNfyE!QwGQ$y*@nTL~!tkLlG1MHjgt_@z`MKEP|<J3t~=`@-V2YwkV`miGl9=?39%wk(N)@ku(+flOn'
    'su=inK;FaHczJ5SbBmt2ThHTKDtgiqrY}5i;s^BjBSHUBBA!A%@Mnjd?-;$xq(*!pcAoll;^tArYDHa!'
    '6WEFUu2Sosdh6%h=v3d)s}EQzSjFK^g4rTITErl+W`3LoV%jQemC}*BM0}~y!k+puZ&R=Gm3GuHIAd=E'
    'bzy7A8brqXl=5-$7PE3Ke+}D?x4NTTw&P-V_9dhKn?)S+KA%M+2|HB-k|wwv;~Hq^`<Yt@C$<QvHoA&p'
    'Iz5?^3%Wh=?xUnodn#7#|2-B8o2V{zKt@F%Ka^WHcq(29+>wKJ7yj99+_Tl*8CG<ouJFjVu6o@nx_5;^'
    '<?n|d{ZMSFE+2plKeAyra>riXE}XjE_;kB*>F&VGy2;5B9X7B_LA}b%J9e~MQs$YoGD%i1rHFl@c8>f8'
    'BgM8?nU5@GJnXT96GV!v+1H~muB>Ju^}_8H1-{7=2T0g>HP=m~YU`6;9NlF9wuC3#J>Ea4_N@7<L;<Ns'
    'd6a*@TiDQgv(NY2=-eB+Kr<!nY_S}u79V}Cw4#*ubLBouBC7lzkE<H3bd}%n5I48s?~)FrhTx<|;C38<'
    'YcT$HPr`4lYnix_9elgX*qcPm)Q!B|Mc}RV4Y)<XLG23~V}zv`g;TDvN9*>3!?V8@@w`R@dUq7hlNipE'
    '9L?KJFz*gxc@2m1Hi+b1-zJn-U5t&ta<~wSn$kJ;S&CIxgxS>Ck3m6f-OHd=K*>I89_r0uS^FK?k!O{)'
    '9d1wk;5+JHT-G=VFwM?t>Rm<=d^W$58IT4A_f>`A2HTW+_9qx3Yrn&mlUs+3GYSsEI0GYhXIQ~aSWpsm'
    '+dhQ;QrtmB!!FN$Vq{d+oB+tj-}r8PxjkmUPw>!Hxaw>o#8UW;pbh((;$E-VeD+zV&Y>e$Kg)Wgsnu|Q'
    'kJVu1@oD~3KK4NVFD@=<#1f}vjef1ph|A0s3H&Z$PS{%eIeG72Fe~O23hO*=a_QZvcl@(kmC=aCXjEbB'
    'SYO<Ux@bgOtl(Rzn=C=~>`e3QUh%9%S+i=V39YkkDN#UX;0(muAF!5AYSm=KwjYd(A<T|s0>)RODif%x'
    'c%z%1AmiC$w7r*{jhh=zu2*)QS^-}r4Ec*+2qHUV^}V+zCn<`4S=UJ!NrJ`Dk~gD`?FDI0CIFmVaVNYT'
    'Ab&_Q#O{ar6@wsa`&po!#r!*|XcI@jZ7J5R8U~M96XbU2jZ1Md1bN<7lBk&<Afs)aBbFt?KS~2}Umd2S'
    'e}eJflZnrofJ(|CgT+1ZBOn%_MF4<_*J>Wh*4+eJ`4j)rkfl_Ry6dR<_}6G(e6#Q|s9MbN$i$oEWM!1b'
    ';yeIs$K&ZNzGA~l@)o4=eoL-gmLNw9jGy#Hk;nCUzBo#lBA<B0gPAgh&$Hc9YS)1*gUP}6Qj?dI$NGWy'
    '*0AN4Af<7$gp<vk@$!wVEKQN`Fvgl0B+dkW6&XzX_s4X=*VAx*Ou%muNbf2r4SxJl#nx{q3o>0SFR+y!'
    'ZIn*QQr&!@6kMyVqxN~1tQ7GPkV>Z=`_3eE-t8i)50rDSOh`$(a(59a+1w>rIq!zIR<l-iWSo$CM+#Tn'
    '2~#!CQw^AAQdHL6JBUrV1FWH25)L|7SdoeCm2kzaaMos5x{tx;siITILrVn<MS>__I+F+cJN98|{zY&S'
    '$h&02xKX48d0`j_VN4|+{5E-U>S6(ACmP$bj)U&n4Qs$am&sjK%(WD+eN(<4@;2kYEy2ojCvst0!NBwI'
    'g9O%X)hBt8uXj<r_Jm{~1}dHx(&$p0%oKTbUH+al9V<O!>gILcgOCV6hRl(-WJ=j63)hr+{IZV7qL_$C'
    'xg1!D#aqDOvfT^sVsN)s>KYEhBmH3KR$81YnFFh<jz0$vVMgLhX(s5lDY8p^d`n)DwOw-9M7}w+b8ASp'
    'G1R;eU1bW%@irQYQ%LY)@BsXM8r97ya&d?IQ{l>Lau)lCKWtw}K~vv}kqRSUOYtSdQc{-5tP?Vsi0j(h'
    'r^B&B{2<O<jwmO6P=qSYqkzW)-@^*-7ZVa;4zWukXa4`Q_pV)T+sLBm_xTl!PwupIcel*<qrEd8$958*'
    'JnU&ZnRU)2OA7?RZf&bYMU-s!c>Lc_6#!BsMM-=>?aW@g*G$|kkp-ZtP%jj!X5zNNrBT0@AO`<#hRIM`'
    'B5k?WQAkA<1FWGfWVt<Q{$aMj_zA<%_d;geqlPK{jbV|#V-~@bB3I=pSuq^p64!HXsOud43AN|KiPmsu'
    'Z|^S_p(|<6{taata1<io>(b}rRslij`%HfQRZwTf#@d|4)5M%UX}K|bkJ3@Ua6Bd(cfGi+oP^JM4k{rf'
    '0!-C}0hs&Eo4&){t62U_Qu%a3`7_AmlZ)gNNMvm$=&9xLV2kzPL*qqp;tpG8L2p*+BHd(jJZf3c`9_G0'
    '{D}S{UCi$Wo+a|k5T{Kbb=Ijt7KYd~@+$IVxDGAq5n-CiBcqy6uqWH}vqtwTA;(HORb%o~DJ83S6030r'
    's_RjH0YfOVM|lFK{6lj-RAr5MQVj4S<+3tGKF-)6$b*^=8!9y|F>S4!ny2f)p*l!)j5_-bOkA7sOw`+X'
    'bds9E`Hwnj1)$|(GNM<)XaSZRM%V_}&kE>IIV3>KPQ9PXz|yq%Lpada8<5@2l@tUsqcymtRblM(9addl'
    'TJiN}wa}4aaF5ddl*0bA$a;;%PJ|RJB^MOuOR}hzj=;6#)Gw;ZL6glo2`AudV9-3nqD%9Uw9xU3u}sVF'
    'IdFwd2f8m6GVbIzi5dS<s94k2^;}0S*^Gx2^P`$mDtuCn>pP{cZc^2<7?e`gx++7J)wG0Jf?pRK6<ynN'
    'VErok{xtM`D`<@ooO@Nz4cd8-H>T6VF0`FCYZ`-Nzbl_ZO5~GTQ_?=5WFcb)Mitkev9dMdVLhX7Il4{4'
    'JB#`CY%x-0!YX%vhL2YD^#oEhETPaKcyr)@7dU(<#uE`Z1pzN`g>jDMIvYt07RA--H>P?A|Labx4x68)'
    'x;#Y@U`FFbp#Dx-rupLKmK8MClt(7_S8K%guk4bW;fh6#UCF3nH3gdvvj18sQo@)d#H2{ZJ%QtUZqUtY'
    'CDK>aS52CB;Aom%XjGpdjz9hngYK>-mz>pG^2kCXzFMWL@xOB#^1$GOR=-(~ZF2(Cre@h}uh41Yx6frc'
    'o#{DT#mb4I9LZPJItf~U7e-m#1()_27H7!EAAZ<eH=#5bO<L@Ydp0*3g!va3bwidEmptdlk;OJRH)?YD'
    'T-TM-y7p)&#qkH(2UYIT7ZRvr1dGRHH!`|+t~SS|QN~Yi)R)nE%5cUhtgw4E!p=?-B^hdhHEi0_4sElu'
    'v~Z4gop^6M3+Q-2&}bPGGlQkk2(&SjEERbe&xIu^?&nLD({r@FM(V%uWu8y6{VtfPXHQ|rJuKFEB`*gY'
    'YPD;dVZ<%Qyu`I=Xt|c<1~#Dy4=G8^#0t4*`H{nzP2m$KG8yA$;JRi+;TJ1tV;t}F+O-(xRuCnYXL`hS'
    '6UzxaLPOuA0S`PEhILusI>d8KJE49Qm_ZVACw6S+5z~%a4Z644uCS)J;n2dOUf*EW8(uzYXtC74WAb*)'
    'ybfLgeY7Umm&T9vkKd5%d``UwEiGmT{#E*3%X*Y8HO;H(?=-^N#cc0E8?KV+SOT4`?_SrI@f1G$DP?^B'
    'LVAx27^p(myp$&xH-&#+k!yZ%LFdMDNY=J-_F}Q#rEVd3%Ja~%wgmu=??wcS_)Fs|CAV^<C-ApM9xJB*'
    'lNfGGn@$0MS_I&JrOoFMHm8#{pF`AWl{D4eiF+{XB4-Ay;vd_jQ#H(QnpSad;!?k~{5-<)K4j(nipu?x'
    'veQX$<tX^m06p>W;X~u4xW=B$K47RzMSC*ihP>m(A~o{L!*>QFYw`$#O^bAm84%zC_tzLQsVm!vH0ES8'
    '&u`981}tW|iRUwFfKSC28F)TM-JBnA3bE}ubW0W+GDohs;+SQRN&P<qqxvrRSf=qwk9~+4IzJX8!6s{B'
    '%g5l>efsZaUjr7!BgT_gFNE(}tr^{a;7<eWkpbr*pJ|JoV27P_gZ-ft{xKdLc&c_%F>=pR<PT{#pGbzB'
    'eHx^wYw@~u`j#&+ad9!5pJVw8ab2hJ=9^qhZ^>6+VY9%tk=Pt)5EJi&J24(B=dS_g(0L7gUrD(>X1fNZ'
    '*l4#8HeB#$D{)>6!2lxX@dN}p?1<MYBUqiDpp+O7^xi)Mqig5$6R`Ooq&{4o$J^^$4I;Zq-wsEpxT*4A'
    'lCQyp;+Zg_L_Q>Df{=v)T(MlPKuHvd5V|r_)rp`w(HV^=a<8F}Dn=ypT*<3#F!X}YDXo)!vSQ$XYIjw$'
    '4sfBx2Va_#EvF7j1^{M6iF9dvX^sD2`|$L-=7g$d0QaavIM^-QGdNlM{q+s!>qF;oj^nst7=)&2Ij+eQ'
    'C-QC6@*Ur?Lo+aK>c!lQZ6^r0NfJNiVQ4WDgr4VFb{JSKwcO589Pu~|5+{yNsp~}Cj?BQ~ZeoUxLtqfk'
    '3j<>LCgC=L4+7@7VZxKx@k7^xDYhMV?`d592Q+Q%21)O{XfbfTQb85?PIucOc9)^EgGw{F*OCv*3&Q(5'
    '*@N*A<I33IJ4o~|z%BN2DVxhE$$x^;@JH4M7(KWp%V)5zS74{WzFDV?+&vf%<OJzRZo!TuT<s(;|7fcg'
    'FGf1tWvvNi_e-VQ6pQAagisRne^*-Nh&#>VhKtYYd@<5DPf-uvPj%7#t2+TVH1_(=)?_6Za$u)#Iqa7x'
    'vY)L$6>kBzs)eGi1dEqW!7TNCjmcica054Wy5x&3(2;~X?tZy{zmI+z3*vqa2)*{hy_pYZU9`k-U49}}'
    'es&+4;hvRvC(3Bi-=|aGe?a=^P~7)wdY`~Z_`}!;hnjBwL6Ig)HUA;;rXAwREvr9*VRg@T)giO06pg~8'
    'Qq|-Lt43yrB2iXk`!sZ8%QY=KpmCVE)b|MCp~VBo^jH$ZKe3hAR^)mScVp8tO)Dlm;cnoyiA3#0p-jt<'
    '%)|+kz-8R@qmXePx-?{VNJ3(}mJ<ga^G(NfUFt>DPZCCLn?*E=Jv$EDjM*50>K`Ti>yKo%ctQcCMz&sU'
    '=-Q|u`BF>!7`)6T!~B;9S=@<1o_|>K)r>DFR|yLPyX?GP<IzI7Mc)eK%1U(SC@tzreE6HF#HM{jaS7wn'
    '5C;K|wL{1IF}ljdA-p(ccbfZ<zNV{mKGy{ee|{kUyld4l!t%#MTAud4w{r3=bow1saKwD}jz8O$jlDER'
    'Bhkm^$wI7T{8+;++56n6C*7x~-KKk?1Bsq5*5blt30ptp9}nzKu2n8*6$`_pg4XV-x|<TLfQ}Ph?B<EO'
    'dHP(H!tPzLx6%+so=8vLllj|v9qhgXNbCR5>{T&sy{$xrvs|%<pUa|%BYHENvlSn(qzSkpcw_VgQ`X-U'
    'ZV%>F4Rwu680>yFA_a9?wz<6}bz$~eemGKkK{G9?suSyZ>ui<YpVId$9!@PCPA?qpSvCw84Vopx{R@VD'
    'F}}hk!OAr+!IvN9rmFn6H;>+stYVJV>{As>)Y&SoESr`X%mR|*P%obKzpcMTPZgr}N#_xoI{9$|rw|mU'
    'K)gVHfv`Mf@O~NUyhi%oBBKgMzu@?!Uv`#zUQA+8zkJ2nt5teCTfj>Gjb$H_dV+yQ&GJtl4Tf4-pU24R'
    'Vq<CZ!ZhWPf0`@_LyvK!qrBf_QMBZFgIziI@}e%&e6l9l+Yz=F&5Oy2eXzd6a6E<~M%wzCb>447*Qm3g'
    'vO>j29jVb`v#35Evc^xTw7bq`9#~1PG#*BL6qOZ*vD|qvC|0r?(0ET(rNV1!$s}Kv{P*)#tvtoK#xtx5'
    'HLrzcHMxI!w1Eb>bgyD*k5sC~Cq=>jnk6^xe{y&>RKitfoi3g%mz-e1>yrH`KGHeJvsp%V$6@)WI){3C'
    'Ll)P3lqM&q#Pr;l>gsD(bpTd;JzMb?iI}lm5W8pZQqPV)0a5pQ!^Z#6<DTfT6|JR-j%MI5Um9O-v9>0w'
    'YrY<^!6X2kB&~#PZc+X7Y$S&{H}039=fX*;f2r9GszM*>b9X-dk@)fctaROl!H3%D_h+J43Rh<fvdnH$'
    'EM2|bPNHZvp2^o$>>sDRbSK9`Pj%N)P!Frp3jC<s=9l?=^6TgQgO!RNmjz|&(rm1+h_6<6NkjS6esA`E'
    '5v%FE0iH2Lqd}Q4of+#JZjd?R8Y|u`m-89$5fb0X=!)~j#CWkb7W^Gw^`$X@!E}E^ICo?PV-f@98%!a?'
    'd)@sz6Ylzog|&QXV8^{R5p|ZoBiRl9rY)%lW6UpOyfMEO+Jixhz8l~3ySy{u<G~R5GNm_pZJgoY%DoR{'
    'ce-KOGFzvAwwSF)NAsn|n)*-VVYhAn*!&X>+Dx(sfUfh$NS8c=ZH&B5u8~>f(Z}i?mphq%Ah02Re)G*m'
    'xUJvbTRPv8l_<Q;_;Q}!;jt_bhZ&#{(hd9`-@&#X-d8l|d%#&vhsUxB&1AdI!J~-1P#HpeGQ6E)X;YLK'
    's`Tk+G}$mcY?eJK3c9GCk{`D?SJylK{O9UIK8IpE7z8X5<_5|D1^JEeoGx`~hOJ})7Wnz+7tb^}EC?@^'
    's;o)D{Q(>S<gNoVe5`GdZ6!WoZK68R;uVy~c&EAtX@on<Fo=M_cTy8H@Cd?PD>jzw{P_NDO8n351{b!t'
    'mX6`BGj%|p_bxqn*2Hi+n&Xzb)9Q9O+XQt7kD02DyZN{pEE-W=NDI7A8u_frD@EmYZft!@jl6Yk+>3eI'
    'Ea~zhZ=j_WeYXV04+lEm2=3&}sg?Hm*~`b0*p|(~bR~gF0j+h`<wK*7I=p~ao9qUmqv2oj*o_;oanT(B'
    'SO49Nzkj5<>KL<i-?HduvNtX!nic_H@BqMY#6RGRuL*rS+!Ltj;72FXo5M(|IxAGuCijX2ZJ~ISY(ia1'
    '`&}ERL3pUMimwVspgQ&t`O+ZFauN1;Qua%5bZwE#vXuPy5^MGB$@}4}-SkP^WjbV(tnetJuJxV#Rc+AT'
    'E83UBTwiJRZ*_>(b4<xzx_heS8&O&FBjs9&e?Gg&%a0tVHJ_tu7Y#7D8hHHFLQpW~R{W{obV@)8aw14r'
    '5qP=;U3q|`@~(F)!9SLmJebpPUtFlc)l8I{`l6khGXC|izAO8p#?T)te(q;G11pDMswA#V@1s7+Dvp(N'
    '7g_vqAhh&I&ozS2ZMB{#AlsOgS*!k0N-0lomnq&z*j54g3H~m+M^>Nyk*sfap1a~%x>*6S9{!M0;EsP{'
    '+;;MTX5z3cQ%`>S)01b<o<Ezu{`u9bmsfA5ub#a5?lq8LboK@|K=u$X?XAGjdV0g@+w9>QKAg&WI8#}f'
    'Wtx{-o8lQac14&h?=ao80I=fnw{p*}youVCdPh8=meBO>wvP9a7g<WPhjM}!a)KB61TTsS-m=C)5UE$`'
    'W(~4zIVXGPw2KftorV9vn}7s-HAjJ%4SstezP(W2*2dojxW%b}%&&omR$_l3<nf<gJ-K@R)0^p=m(!<D'
    '-aP;I<<<Y0K70Pdn<tnR^6_j5?0_{?&Js?r3(Pb|V`Qq>;p|*8+|&6c{uc4Ezz(kEiZj1qvT*5k0`(m)'
    'PJBO(LMQO3%lybnl7xk(XT^~jCzk6a+@tV_A6kq?%ww)^Qx-*(hY=Ua$HFB}7YJ{~Z(&?<TcYh`%e;eA'
    '&B;=$Qd6I~6}T)29m`C7&V1YS9F~NX2PPq$Qp=3(AYsh+;1TYSkj8->n+cDoM{O3Xg3YCwXM8O`60NK8'
    '6EE?DC=MLUv133|L^upcA~*6~PGT>NEsHvV<9IA40W%5ZG;&SX@&G}E2B9V_$htZ8<pZ^>fP0C<C{iX$'
    'd@J!t5XT|R!-{On4sDo9Vws+2F`My(c+}ys8HHZ#1?JB3m-87_<P@n1@L{O_N|(hSIdUpRd}bifR%_!m'
    '&iLmS2W0G_;Ch3It>ffBE5-+Y@|PABN*arh)LRZ6dmm32>MgvB<b<Q8MG6qIP<!5N2HtyB`QW?smKW9k'
    '+rUc~uV>eb7u#|tzoauZZaE>u39FP$DX>y@4-stX?_*FK3V+DzUNEVhu93%A*#K_a%=5CTcjvLPD@VZQ'
    'HA{~le(kRbQ)%2?TlZD<+g=zb`lb(<rRd{b&abImBiUXQX}i4-?Cw)-Zn?PUi+8hCDk`are*JZlQNG}>'
    'z|QC6>d|TO`4NEqg~f1Lp;=T6l@uot6nf>vvHhHzlK^+GsW}AxtFA82;pJ-vCmLV0mKG-$X&NM2Yk^j~'
    'vRl8D+W;cFN#AF(VMsPWw5rVy+DT5Pw@OlgP$OZ-$Nn?QdG%ZTptKLf=KA*75&u4@;M_0CiZhjEiqi3D'
    'wo4__fr3S?@iqLXGBx4ZewU|pA2BNT>MkvW)<tJsWY$Oz?c_K+zVYfmjdf|knWp?E#g3;%W!kT23vshl'
    '#N0nB0XKQe@7|{?W_&tuZi3$3r2+r>UOqe?PY~pb#d5QLvRT90mb0}8q=+jv6OrV7bW1e-OtMXUJ6r!i'
    'Vm`<Ez__0A1hlXC7-s#3WN+ag*^NrIRUaFl4o0<F)(dK`t*h|!p!0HMO%}|MtnL<dVSA2CL^{Z|?o{*5'
    '9vmb{r8LVN)W^h`h!X)URWzS4j=Ay~e=zQe88JOo3}i;r#mmL~ZoDm2{`VPM-&`85dv3HTTYk7I`R>v?'
    'A$xmg+Oo%!n9#Sf$aJZ`^d!Zyfa|-FIWfcWxiLFb4C?F(-$s2**JN=G7@+A2<iHhJubWI%7VI>?yf{y('
    'YP9%G)J{Ic&j-cw{fhzJQs7>Nz^P@xVG)4UXOsjG6K%8kD_eZ;u)X*GJ#BrBJO9)hf7rg)x9wZ#|5h>`'
    'YZ&}guK=-~%^E*wCut`cx<R8^ro1am|NpYA*2c#}i1|-bXTg!A{-qK|=am@M_V@Ezkm-;NuRe(=Ux2JS'
    'e2;pEgrbFooaYE%Z!Pv)(We~|E0unPJvuHJM_H_+mP)={>7wj0N{gf=gmM{+9k=sQ-POgqfRxW)ajA30'
    'k6Mrn9jZzB+*V#n#Uouc%<;({ec-Pc8~b`QL)BQjA#i<-QJ8d*wJn8QK8XJ!uR2z=Q*O&M--)Wm?Vrz;'
    'etAz9m%CN(jT_(@R1o7f)<hd+F;u2#5-HXD#Z46(o1#G-;87VH1VHsT*hGCbO0bZ4{_V>nsZ~1z$nH4%'
    'M=3Ap>EIFXMd;RK?s*T}qxi`|{UA5~W&MNm$_K4xB_A9#D-dqQNr^<0q|D@&EI}M%4>fV;ZMJC5ynBCC'
    '#$#zmoHxWI&yC%5$i3q>Mo3%d9=4nIw27Go-bQG9<tQ2t83)XyRto*>GvTy5kJTl@`7RFSEtRZ1(y08('
    'SW<HDz`aP^!2oJ&|Lm*1HIR(EBx|J1aWPRKJbk~&MpbD$V6!wHC&-H?n<bh#PaDodMkl~`$$smM@_$Pt'
    'E5r1ju-wXs8f?>-4f0Z5uo@zZa$pA+-(#He5%K8;sTzYgOn%p-wa`a{Jb&rq0rqIkWdpgWB^LI2X^)N_'
    'o9_3o&UBEcyYT4aBG$aUmLu)R7P;V^>m2nfDx&PSyp?t-2h>5yPc09P%Eyc9;A!tM`$XMMHYSxSCwW$P'
    'k0JLa0ev)DiR#B4ME!P11IGNV7lv{dMAe>XHOB*YE_NrmM4^U?ZIZ}5rarSQoR)i-X1-VY&hwtIsj7;#'
    'oux?KuLjNA2%Li{Ade232MvdGEe0H*4mzRYpzLmg8Bwr{8%uJ{Md2M0eS!air6Df;ve}AbdfDB%s?bFY'
    'hK)!?sVyOoK+OEU;n{l9ZnW3$XKO0%6la@NLMZHddD|ufKAX=mSf4$DQ8K<><31}UfX~01y%WzP2LOmR'
    'LpBD1Dnxy3j2al=aWm6g%7Usb!U~;3Onvp#a-fe{^6Heb+v;Z6)mxiRY*_hB8%>DyM0-cfTH6sjKvAN+'
    'NPglR<cbU}C_nffl()v<@!7pZ9Xkf5JI194g{50&yXZSnsZVZemo(0=P0+uV`}}ch!o9$(y3t!K#kV`8'
    'dVcpnaQ~pWcL*rLtXNc2;@Gg=(na&cZ&x!mqUn5di%j|t{PV?{-;O4PktJ?=Jmj6-Zf-9P%l5|O-^xuD'
    '?G7h>-=wSOgx-v{2p*TLjE+Zf`B8e;WER|&3%RGHpnoL(EJz^qME=KQ#vb)Q^pl~<{Aj=HL<L*IR*ylz'
    '-)^_~1Z(dVr|;y0I(-KZAVDYKu5t+Py5qKKBf4T4dUjLOW>QvkYr(Vkp;xQ)8gyqSd+Kecs!Znx2l5lH'
    'OKG|V%WPk4gF_k4Y7i1#k8awElFm`RFRGE$vLfmqiaT}=&|X>V<knLQKwa{$hxj|&e~7f7!28b`MznIQ'
    'u)lu&S<jQBlM3cua{0t!xrL!qO?s$h=6z*|+k=BMA1aPz^?LkHXs$XTaYdk9QoR(Udvq{+7z;#m_Wf+Z'
    '<m(-0S+jaXyh4pTHb`~{kF?Fts3dt~!Gt0N-(F=`VU$2Ts!^~M@{&dA`(2XDf0P*wua(oxCpi3QvArr)'
    'zdQvK*-4S#KVSv441#Ghy`?y6C~SLf2-0F<iY?9xPo;f%oQgNKp3%3w>`aNoB2iUxB&yaH-P6Qht?axb'
    'W%zf}Jj9k&wf3cLuZG+%bJW_vl<2FhCYRQ7t>;G5y6X6Ak%J{UR!n{f(-!se|9C6huI5O!u=X6@O{Nt|'
    'pB>~Ea@6k|c^OY?hc@Q^Fs;%(Sa}aRrK3vOuTff{zb3uDKu;ZompHXT7V2&!_tryw)KE)k_n=(5>6T80'
    '{e1=E+wa=Ln^u;$X<OYQzqS1JCWD=nWzX3RP}s84habeDXM2tvyS_(#n<j+&iSLIzF_|BeB=9UoZTK|~'
    '0@LzsFNu85i!F;&+o$I7N*_+Z-6Zw{)AKz5K>|Cms708`E$YQKp)N@h>Uh2%d6w%%0S(O{GMUT6#ED#X'
    'rV|&<^*$oo^cbg>&q8WNHg`gsxW3QhBup&Ect9furkmJyz=%te&?P+deQMc+vB+}U)cf$u^*(}Xy^mhx'
    'e!1kbv`t5XJGLJLA$7RpCoxtsArUkEz^5Jy9TxeP9eGX?yB;Mj2^`ysEDO-$$F@VGkhdT>w}|DqEOs2v'
    '<Gw>pKTK%sCW*)5*ds9wSU{+0x?xCt&kb2bOwV<kh=+*fGriboCOHi}(~m6bM#N7zFu4^Zltd9Qb{GT0'
    '!vy2lNnD#Vz>V+tmhbx1A;8M6?*?HTlDlP+djm-RYL#M-kDpS;#f_h*t8}@i=8(l5>bh>?`X-PQh#c51'
    '0WRid%uLg^P1o@~Gq9|L*-qdBSzO?TB#8nu^b*Q6)EsI`CvM4{6qwEnA{X%NQzQfMN<hrSC!rmaz;w9F'
    'ZOT{-&oBoVh%q;CNX){(j~td9XHG1><N=uj&xX}nrpsM3hW(zzj>){3Mt&T@uD1gpHoNb~APy7GnQPkA'
    '3}VmKh>6cvd&nv?rnSHJP&N5<w!VA0RHs*?k-U|CZsh;ISgcE>FWQvHIg(}40YoM9qs@C_L9mLQS{TI='
    'jzJMQHhGTx4w&;}i#u<e`gto)Xicv3N(^8$Ja_=GfHYU>oYy|i($)IS9r{BrM3ED#9sKUpmNxczj@G~O'
    '3~zhFJob-v0QD^ok)|>Q;VVPj)gK{2W@P>g@^OA^;plmXZss1&+dWx(=e0_fQOEZ>47YRVp;7>+1%M$t'
    '@w05iv;DVF%8|$O<~*w6+kJ@JJ8WgAwVB>Y#KgTyiQYn@tBhz7e4pNu4|wWx5Y|LJ^lAkvS6%y&xEOtD'
    ';z|7D$AIy1JLv|4JUcM^ZIvkaPTCjZ@!G|$cEt!ph3ZOlZ~Moi%D3CdSoH(-l%Vaw2(ox$aIg%|hvJmo'
    'b-skTy`H#DTsayeyC34;EA3B5`XdBx9Jn~n|EexkAMHL@nS%V_a4ayH)TFHlhgCiq7zOIcjt9B1V}YMn'
    '82Mf`Bw5^{XcvJ{QC99tAqq<esN?QgC`~CHWIlf|o`A9$fwX@-S)?r!qv}7+=i#*j)-O$Uw2I?N#Y5(>'
    'y(XX#depM%{6hO$6<aEF#zs@h*q%h1BC$gy)8GY4Q7y33$~ry#S~665GAORH2R-;HFM@F^C7B4!t|#l1'
    'kvoz0CfRrU)kuCf?q2`qG`r+Po8&X?k-ft{d}w^n`O+W@gMYwq!fcJ!C7#NP9BqX?<8}sH154|#(p!-?'
    'z5p?}ceEm>`#=Ksg9B5-!ZTu&O$Kz&w)1!>c;(>}p^t9Kok7L5G1;i<mMk`8F4Nax;0IlCq4JsY6DE;|'
    'Qs<d-<BQTcHKxjt*&-Xgzu_x>c_>*%5J@y$+k*cz?tNQ)v`=cl=K7C1+dMG-*RQ{hwgZnJjE7vqu5w=q'
    'Y#*RqnYQcmn#KAtsophr@zi;YyA0APiLshVH87#^kQ6<l^m=k@C%hzT=pJJ!$x$~&`)=;t0#X9<19@8!'
    'by;nsQjxAUWx0mz{Vo`lv%VLpu)~|moA~peoAQcua4bhipM_D?$R`w>U7qb{H0rk*+aIipZZX*E<LM?_'
    'gHN|o<yqgP%NZ5TPWBwY5uXQv!x@bT_afUQF1M1{wuuLylF()ewG%UnES9)|Z&BapVMGGY46PuvIURTa'
    'SIm3cq9kvWvad}E9&g&za%?l9)aUTO*!N=Fj{=rBapJm`XHws@&4}8T6Pr;GBsQ#qS&8Rb%+WDp&|aWm'
    'IiB4<P16;_GUu(2v|%!FKzQIqk?ZgzPNL9rXc8qB_i138%=V}oS;RIimq(!=L@cmfAV~}>3qyMR)DRv`'
    'xb1Kn1SY^VV?PKj>e{hGyx22s;)b3_LML)#;`+p8u@`y)=gjk+I1XaH$Y?$|<RQ1+z)j3BFx@0JeLr!S'
    '<An+LLWjj6F-@3LOhW=xC5g>l;(II#O%^47KxmtTL$7>r81+2S7Hh1R{clO?nE7$QNg|eH`gUSR9wQ{c'
    '`~@fECO2IxabQOQ%SM=8f~{&?2eupWEoQaJUT~=&0Qn*(_IMl<n{yf_uxnjEBvEYnFsK_xZW8*D<1^o3'
    'f#*4)7kMs=2w`WM(D3<Ahn+H!ox`WYvXMf$Q?_W`D6%mxjW^Y-Oxf<U=&NX4^My*<I8;Q*IFsNerN^-&'
    'q5M#Q7A}+c1-{r#!8@LMSz1LcKe0UMe|%+Fhk+f9OWXs#PKhp^*gDiO?ohWA)iLE|3~v9sW6dxQeD(0*'
    'Ls7;3BE>*Laq(t*)f~ec>4Fz^WmE@^@=fcBxHn(Ca%41lcOL5|7(^!hJrtn>c_fC;K$73WfuXNgWU<af'
    'j})2CjOEdYH2x0VdH<`z3{JV!878M1D3iHC=OoMaml8Q@lqq0*vAH$Gt?*0Z`R^ODCbE<c#e3p2hQ-q6'
    'c||^1<Kf(BTRB6Hp!(UU+9%%;Pzz#+7Dl6ju<bX4*W_Qum`Js?ox8y)?aOX2(&8>dtCRKG+hnu8!3iUe'
    '_5vV-UQYlGR~)$+y~CehEY`l;0?sZERqD$$_3&wL)#sEkzS<#;8e#lM$*Qj^S^aGb0~CngzF)pt@~Dd3'
    '@<UI`U$h)<7tvdYyWibMA)(4PQpEr(o3&lx6kcv)p&CYuP1)o1rY_(;z-)C*D-bO)rA8QmVK~;%5bYr7'
    'rIehitcEc`iP@o0k1CGxY8aF<F&}q$uZfCX-j^jrT2}EYzgV_{+VyX$Oj{NbYd7D&mW+%S*NYUzNDk~h'
    'CvR2zCMgI<jgoN45C|QM0bYvw5C4g2FXzTjXhi(waXXe1k{YD(G3I9+p9IZ~!#!3t*Nzl^I|337p69}t'
    'NW}_aUGrJO*Rxx0tiiO&W`cxy*`IXIwxxft5<i`9M3DT+!>=DcnY0+}DlZ6RyybkEm8u72<d$E^Zp?+L'
    'hPPnA)LLzpDE5(tnK&zgxomFvq=N}uE6~%#1?SDXWm{P8Xs_?eeGzpry0LqAyZc2&LvR7=U;mOx7PSgV'
    '@OABz{6V#M;Q{qqTXo;CcOTVwPX3+W`BK}pRVTf@>-)HS)wV1<bD`NfqNxg(Re)%^sid-1gt?zv4y8`w'
    'u$s0&cFJ8<KX_E3WKKvuI#kwY!}4%bgKkzU7*#2lk~iD>O5N6guid3<Uz=0CpwReLJ}Gp68#htunSmHV'
    '!6dqS<=!J_vvnq_rGX>@8I@0^Or3LMk%H9^<X*o|S8rSTeRTrtsS)2q5%u-s4pfo+axTfNK#tFw3awR%'
    '*5)o|iDdc2m6f6fI$Hj$VjOONA8X|Ari$CsymH2+QPkb;!tgsAw_4j@m6J~;-H=D+CmMM43Hay8r7~$E'
    'FYt1^$<}$rKk$aIiICvgJXV6+#dv=MhPeSKDV(Y<TuQZbrh+mlxqgFKa6dg1*Xw60J&Z)}gL(eSz$F5-'
    'qcbV*a90*otHam4tX=E21G%?VM1>9?L~2?6p+g0tf!N6_9-R~|D&Y3VLQLh_bPoLlXxNEvpKndd{5nFd'
    'q|y0)ivzLNE1X@n-c_a4_U(sNzS|QjZ3awv!!)}&zewho$6;i1Fc;*x42G3AxH@qI{brRe(oJTd715?l'
    '>ekvWCi$qacJrK|Zp(xhRq?`q2#*;h)46n>C5nG*U+RkSL=?D27>_4dN-4X^3xgLEZlB_~mqWJnKUZVz'
    'l)d^&^~I|4#~|JiD@;4(LliY+vi?P6_LY5WMvEk$v{SbGs6hVtkv#l;<->YZ3ERE5pfG`3Ws%z}sJ6ks'
    '5!o;XS*^gspNY`GM&!~YoB6N=)#ho{z00|}q#*HD{j_b3J5?+PX0J#h43g)oRobmr2cV}600SOaa3d3P'
    '1#F#nGn5z^-a2_?05idWxi|7&9NvIMHR(9%kN-{CuTJNrd>>|6{q&w|8LA+PLQQ*3-|mG@>b)wcr(1I6'
    'C)^#Zng*ixAYvt|R1P?`tj@DjU;krcOlZ*QO}BKlzacJW$=&1wO&MRV(*Jt6ltm*Z%lHHSdb}`57&_eb'
    '95ab2aRM4dF{8wF5*piPl(<O}JKVA;OX4^tPQtk9ScyX|8u>g4tmCOQ2~8Z!PdtmeaqPub6bFeNTRuwy'
    '!Y$uokxvuuaURmxPb}Y0xNF5xWLuoao@bxw#YS_6jb}5HCQ+35EHvZ5wTbP=aT0mlVXo<$3A2393#rQ;'
    'V)_;=B=KC+O?Z+xUPO~N88)_AsRje+?U_pT2G*H9#7rXfTP5-D)hcBhF%j|Yp7cMOkifR7X~%wKnK8F*'
    '*9jBPPDp46VZ>Mv1wJJ}nwTZju_A}M5j;sv-(ifn1JnQNOHj2=@MiIAQA-Lac!eOz{Lm`G#ByWDbrUa)'
    'X&l%b{_lsx37O+sKsFOZKk)+UdR}72Kq?kmLF}5I%Pl90%wDV5EHM=&-%#C)wQx7|N$9$f=f%Fw64-VQ'
    'b<8M?5)(diEt_I(8X5-hOH6_wf{kMafopMQano(F<)SDGV&4jh%|g#K1JlGrPCKzV?Diy#Ln{tAw_wY&'
    'm{@>09>k&R^MJ&W?~<+v04G<H_MwP+&i;v>FKok1T!h`-ZN#*g9l`p5Dljhs>}MsWNrDgv6*vJ9$a1aF'
    'Vga|969pz`He*(jSSAPz+dqy0pGPD_D!bH<2#ZV-#x7@J7&spHeAi-@#}n!~l!O+@J~v|2@qOlan51iV'
    '#(?BvV1%C+v-NgY=4r&LJNh#or=T18A(pm4E;1I|Hi$<%j6#=tZo&dL1eUQJI}U(wKwEASp96c?Ae79|'
    'rrZe_>}QMVVd;kT<TaO`ahk5)kZXCl?$A;=Xc7~qOu`U2%nn1J`>yLS$E0=;6F0Q15Pr222Uq5prW<>%'
    'mxP?ULFBL&x`h%#c*sa>nLH#B^CRGPnphyrm=!ygV*y{qAp_DA&&TZmG!JQjFMz<O{m_!9RzJPr^lkQV'
    '4IfS^P<u)hxu=B_F-7#R`IInmO)gzbmUp{&@+=Z04hwt_)<R;?DXxjh;UFJi;{&=Z%eGt=FgJ;?K$-<w'
    'h*OgQ`ruKbljO(Orm93vnPTRq6}do68_4Y?+_GT<2OjKo6J)a$dm(2g;ZYR&zT?5SKs}d&@^=FYmWBh0'
    'D7fbpE%{1OCu>|x=qFgV&W;l|46P`%eHtV&C`Q|34scrl#tP`g*kvHR{W!!DRTfAW*pigl?x`0e3(`;J'
    'C5veurU%Z;J1*@k>8EtTkBd+c(k6(-!~_XrCKls<1Y0bmN#YVe0>xxUHb`qHbWKiu5abr@LK}pq51N;F'
    '`WASrBoDA0h@R=1Tu+xm_%u-~2Fr~*9Q0@u!nQI=;yW%Dc5^&1T1^LZ05F|T2<Su41gT>M32eB~atYYI'
    '2{|rwTr7=e^C%!8_kd+%#|iKzg~=>pB|!-GhGm8(>;XVeNPOF+f$3w(GHxfF1}8uaI`I6xta~z*E>RP1'
    '0)i7y81=Xnaj^V-HwGRJg}jMekTQ-5=wtX?05*c-h78tW1EUjehAj%M@d%84JBmCoJG>}~C=U{!qinZh'
    'u)RDt01Sab@W2oW%pig1nHPX{>4JWb{7@fmmhw8qlz>Z0R?XM|ffTu+9dQszegr0@NgNL*XU2{hdNF+B'
    'delt90Hjywffxuue8pf+Ff-oOv<<fkVvuWKp_&YAZ7?msyI>&VJQwrz6URYs!if_f8P=tK7!c3#8M-|d'
    '4?%P3#|8!orz)P)N;las8%mi2o**SW@QKHw*rH&e`VmO;AhLPj`W|?3rt1^RcxYO7V7p-eTf>Q?QwzWC'
    '!q6+9s*{&Sa(jgG$oGQ?M7R(0jYB_9f&dm1fUoNT(?>CQz#eCyw<3?(G)inYGCd!x71oB_jDUW#9BRWB'
    'iwQWsJPIk$oJJN%2=GF{+@!>^@YaasniR;)f)E}DdlZ)17b|5yFt<2g6*}#pu?cd@b|@?qYjA>R?z;ir'
    'd<j8#f&Q|=9SH#`VF0!!O~Qzy*X!8?ud#ts@9U**zK(MJr+Sk5fz`CqYA!e#oTBXvYryiKSQ69q1CIyz'
    '|0KbU2+EFz9$uD;!Vt`A5LMt8fNBc|udQxHiwZsmU0fSILXQv^%xG|QDa^yQT$mL6jhB2ZCv@N$7PA;0'
    '4B{w=SOkVI<=nHQ7HsSB$V`~ydjb3x%`Z?1z{8>Af|X;U9mBDvE0~-PFn}9_cWHur#5;l>?00`CN=g^s'
    '4k5yGotQabe1%~6f(Hx6R%pUR0#NQI2aAI<A2f>X#9k73@E>q{gUF<=6UKgETc_dGo`DM&e0{L0V3MB6'
    'iHn7m!zf^Z8CisT;P`<YGA%E*LdKaFMLzXFZUN&0<&%W9hyhSgIu6LTI6|HPrDcN(2W9Lfgu)J{5ol){'
    '9Aq0WqsAcfz+~kfu#gqFb{vzTh}nD1Wbh770ze699>(0rj_|%-XonOnF=7V5AMh_wJON7#Y&=lko@cpX'
    'LWu1WmmR&Tx3e&o((EBR3>Ue>aG_kFi^2uEWjhp3V$b)%webQIFm8f{#lR5aK3+ymJRbxPAy_GyfEB<J'
    'aOB}pn6AZaPV9&}df2sL@?~$QVcsDjVE~S$3rZ0jaZqW@Cjl5|F*xufW(15N@KqC&g)V5hI09J;ECbe~'
    '1L$^{#(7J}=0Z9)7rA3|Q8+fcvv0*fVd$fg8zsb#WA0#J*P>YbIs_M-vIOrGyWpB)ZDCklV3{t~A_ff('
    'MlqwL*IIH@{X+OK7vRHONFV0m>~=Zlx5eGE29l7704)e?Vux7Zb@-sOz^1l5?)z>6YT2?$<bjd`X&rbW'
    'UMP?8ny(#%COF`2Q~<^n!2SWZEjBIJcO5_l511JQK?p`X2n!G(z7JB1xNZ=^&hp`VaDBn92X)jHCF?Yu'
    '17D&Y*KC?nW$HB<auJx-rem8i>@S)G6x1B31N3VGuw)$g&I8KYAxOIj_8{N^B&ZK2UjmvlBARxVTEd>N'
    '&q15o^uYCsBhDDe_%H@35{5#lfi8<EIIJGnTvmiduL%uZZsLXf#3MjoaG=1m*0_MR5Y{p%0u+GB!y|m2'
    'OvPF7G;a{vunG$>pMYl#iZ=n@B@SaJN~j6GZ^FTC1hdKu!C<n`qy+58pz^>e_eto0r|eqpiB@qvThBRp'
    'n@#gfK)J0N765Vp{eFv^G`4Irv4I%is3**a9p!>{woQul;9cU`V9t9W0AMwy&8Q9bQ0yGvR^V8=5v3Sb'
    '4+A_#W1R5Nj$wZ#E(lXl>aK|0T0WR5V0;sk_yk<60JJ@CIQmNG^YneX*o%kNW+4bSqf@cD8sk|ugN?#z'
    '0IEMs(6Rsz9321`{89&l7l{>dn7WsEFlCc~YmksA3OyfO*T@N4h?Btgz{@3sgKzD}rt4DXdNBp%=TUHZ'
    'J-`5ZT%f)^-?4~C12?9`jl76}OXPN5cZvQBk^6BR3o-WtaQ{FFgCXe>kPToH0T+Oc?F8WO!qn^_;NTqD'
    '4)am}fm>vP_3Hy+JikRv0nqSK2u>cbKAsjj;3m5kfW||a(1rg3rl}7$7~vqwY!4JF!FY){qyY2q?9*?5'
    'diCV$`A=`AZ(dHHK6&%}+m~1WXZrH$+4C#oE5Oe_v>?iqc$$HCFfE<~1;pT)w<Y=dUs<|yd42b8c^%0r'
    '-bCJkxK>H()7b))awfvT?cmiWr_O5CW^D%|Q!(~;oXn?Wh4}~b?h|Q*(g#Bz!pICSBTczzM=@mp3+B>&'
    'N_!#oo0bM@H38`}8A)}TZkEWnzi$W#cbOe41hradn|Vpw7QtOea2FEXMG4%61a~oz-<vq3J?bhOr<tz3'
    'faybJc^|Af7^JBC;lB$p)jr6Bm+!zLx+TlphUg1#0vi2h6F<as)&xXF_E3uWi&>gY?r!I8`FFFh91~AP'
    '_-wf@CesExqN#^K@84k#qQw=~+smuAv>krBnW2Q1(aB?Pi8?Vb@Cs}qCd*H8uxm2@YD?g!^BG=wXg3X9'
    'L=G<pC7Oi^P@UHkugC%nvYfVC%`%8<ggFg!Lg6w9&>m_Jft9yb6OM{#Gu0cK9Zkg!>kA2K`BZHCrzz{s'
    'i*z=<#yV^rguk3LVqmr!hE3Q6Oc~|V_o5<U*6#KFX8>w;i=wPHIAY{_k!D~4c39+5mTm*8A#vgrh{CT0'
    'Y*kI}o7o5SX}-$`C`ZKlW1%+vL=LiDMq5cI1Wa}V>s9wLaGq(BAe&_!gw4*fJMd}a`wDHZrLo%ulC&&e'
    'Z(`+?KYur4d?BTH)@kePXy3wo#f#<FTW7PqR@m`WI?v>g%d;m14_$;3YB2WRmOS<Mo?$P~`8Vn6Hf#NQ'
    'o~rqbV?}^FtPI)a)dL9~f*5FRpiITuPE)?XEVSdwwpHHfpW5yD7u7=^v4IxrZ-7Hu?{TT9DOh#*KA2)N'
    '(uGrVJ^z}^@Kf7Y@a%BgO|RQ<MSYZ7IlH4T*84W%5y6Ue8@vvq-`k2()h>cv-|jc`Pp_W#dvRa$!yW*-'
    'O(5Se@O$TXL~`u&#Ts_~Q#6I!zJHaH+pkw({qt2PL51(V0GCEesZOt!POuj5NY?$m=O31HFyp&T`1MV?'
    'R4mc@9pN8z#g6na>Vl@B^k@$#uled7_QPonp|+C%(k<F8-2njVN=xVg;Pv*-ce#9S3kX+$g4r#{6ljF-'
    'Y8%gLOUG|koJ*!DoU$HbVG*YU5pdm!hw|6oDEI#f=#Ok&X<peG#_P@XHE#QKaV4ThugHSW+uImm00K7n'
    'YL?q-UCk45BL8H=X6X}gF|Zp9;b`Ye`YyfYefF`^!{323(w!H#r0l_tyHZ{YkS;oY4~X8<p~{<RR`rKb'
    '=gszzc9^T%M0Q^P-(Zt3$b0~VH)M6qJMh;oYj==xpiuKS+rOoDLk|ut-t4BA%HpW=-pyb9k*wbGbyrFH'
    'lW@nt##!C{Ko*?^amls1n$a6U<!;{9)`NfYLgbgVm*SPJQY`;R@QdbIX9j&C+t-O+b{(0sJp0z$3)lWK'
    'NoEuVef|#2h^&`QQ~}Y)4uBof?KSE00oQ<4+`~{U%Y$6Jl`9kt0@O$8sYp#%Q?!hLuC8*YX?_cAvA%iA'
    'u@+#D7k?0y7KCc<C06=ksAA*xR^{;acW>UjYVTa+N>|oa=pfC+usg5!@-TLwbhaUOA;1K{7wr@w0g1%3'
    '+4Z6u3d(PG5@tEco-eLprnj9#3@Wqs<qFs}>!pMi%J^iWZl}ER*GUiH_}ztJJ*d+mz)|7#{QVy{9VKC9'
    'tKBYBP$E|xJ<~2gWNquO3A^qXzbhxe_mwc;FVgpO4nqqa+Kpk02u7D(CRY4@!I@w;iM3fLd=<mW=C<8@'
    '&r%k7=K#^x%lvK=cYeEcywRS-vgyO$$$ZY&ePUB7S}5OcW{meASD1CZ-u$Jj!?f*e(^+pF?u*mu{q9Pm'
    'wC2u^Z^@9)m)-N_eyc7HXhfsRK5wF(&>3f?_k|(ZY3)tNr(1Zh)DgV&*t;F6lx<rPgzgg(s>A4PW$*a!'
    '0!&x`y{_K+IL8e>TE}CAQpt;aBHyK(Rrbw{&sk?|?11TV+EvmvS83WkV5#Pi^|QxS(7LO#EHkz&P1KK_'
    '_H>hKI{n?v6RjL$f%o;dO}ZwpH@CNBb=U4>yx}-Z<-;Rh2%fuZfhPJh=9h?Gw~wqh!BjzhMX@)tTP~P3'
    '>k1Fe!yAHq2TA+vhRW-I+klFZhhypDYqIJJBENs8F2}UD(D$9@W9(okkQZ6D;oC0v10bPP0LO{0W}=B^'
    'Ytga?+-oew#8+MSSpzh+V@uclgq};mQs|7i{A@ID<~w`Gzn*VaPgbH3cvonJIQRiGFkk2WvAck&N;f>J'
    'os-$^-)HL^wj%G_g{t?$5)!6AgsN=mOUXu<6$#TD+K%s~4^l@xe-!91vWwdg+$l-=ifl6e^d@bo{|<pt'
    'Liz8r1xw#|23C^DL*5;N>AF<!44@_lUJ>lzj2+_oKq?FN{=%Rx-19^3zJPYcXJ<&lamNt-Geq;E-*gbj'
    '6}sOG^ePDJ44^7)f0^Ztn)?GnLjtX|Uc@?9iLE1$13DmwFHUr^$@n$KCtIcR9vVexhf~0=>WveQP|+eM'
    '7^f_8PY1qa8fzS+*;?(*p3QdaP;d>hNk2%9NNo~?n!%Svq(;#Dgy$)S$i?bl*au1@Haor@()*8&&=}a)'
    'F+k0e)daHc-Rc0_C_^*?u1XWlfS-Q=zId`(rx|(2HN&oX-I}2{dEy#}IOI?380N5#tz(2HF|2DV)n%|Q'
    'xcdaKcKAC+?SK(#_dkjvh(#F=(f6Ul4d(;Et7R5r6`!6G(MMvMx3<(d1{D{p(bk^6-v(TC5AeGP!svvW'
    'BcDp$cM{l=u;s$0x`xQ4)jLgva3k|+qPmivVvtPQ)>BQaqpm;V<)?VFUc&$&Hgy4Z%;_3$7r-jmjHvr#'
    'Q^Lq{-Rf$2b&PryyavCrw@_$;Exbv65cA6k5>@)(?vH6|AEV-(YJ<LGmTH5%8(-87x)N_347_AV>wr};'
    'pa%oo8(7o<xiQeF6L2N)s0;9}-8mR?lOd=DXxRcB3~-<6rw{Os&DR-pwQ?RBE*HWwy4YGq4dwItf)+NB'
    'CU|+VMP&_XhAQl!q7I@S;L13;SfZqTnA<@Yg&i~usxo;l(B$bm-{DoG%5W-o#XA+U*bAkr$DyM-Qw0**'
    'Yatl;Q;wHU`mah`rLW!0i@fe}`&^?YDBsAm7M9-`=$EljhxT+1qDzGx`oh{?*%L`j!<M;wS4|`_w9Sic'
    '$`iQ}hI@}Ykw<_H$;>Fj(U6)Uah^ka*JFL^8cS|>U2zbJUklf&C#2URY{prUu-p5Pyizy3H<bGRdAXF~'
    '@V@Yx8MW`>aG4)^o#@t=*Z<rbp}i8N%v2ijFi=<NX3fQI{UL|eP3+khNQE=|oix{3^8|;Ib%LI72%!W{'
    '0KcXfPH?DN-ZeUoRBJMHD9Flf(Eh-7t}f?E!ve78bI*FB^(n@vh?i5IPVR5qHWYHRId+N>$|jml__f`s'
    'sy65xp;<-hJP@s0V<&>GAw0S7jIk<lGy>nf<)8)lVOgZ}@Nch0qjQi(X{U35W=l%zA!(C=rR_Ac!S2!s'
    'w_=LvIU7CRK2H~Hb<u=PiQ>>xjzLii=!BdW;(vOB@?TYF)-Xf{w4E-NRMdxDtv1U}p{mZ^qXt3U;}vR$'
    'zg6NoPtkUZC7l4Yunx4r)oK&$_M|E)?Nh+~d5JCebU`kw=;1IAYi2E{F?&_A7U+$-SPSH4C9LOws!96}'
    'KTy)Ac6Wdd)482HJN1B?E4_<cv7QFHP^o%gZk6eUP^NvMmLuUW78#Zb$HawOfFv(1U8V1{o-yJ#Ff)Mn'
    'j3=|jtYZz;3b<0SDtUEw;BC9ch4u}k?yhoJgilRwn`5d!iq$aXj<KTsUf@2WYx4yg7~vFl{7jOeRPcVV'
    'LD|T5x>Wlv-t{Q>GP--^L{#OLLhHpAtvV!^EY^hwrUFLiTKEkzq8ViGJAKs}Pcq4>r=U1kHmY~bS6MBT'
    'BazV%+GMAUlQz|S(tL-bfqXhfs8lYLwGXw%a1N1IV~nUwXnlF&LWZUaLsO0@Dl#N84W51hdb#2WUtu*V'
    '?D(_dGUX2Wbf}cp$~jx`6}HiqvDYY8ba^mk7U>ML!LZETp?;-GN+oQ*CAS=VU#Vom&S?>qQkYl#_svWM'
    'Og8c0yW0)3>nG%!W_N-E(<){3TbfPy7;b7FB%Llfe2{rH3i^Evt=nLh#VxQ_G8mqGsM2j^JLg@8MW$SD'
    '!F-U~x+G}>6|~yVy0G7DO)ErS2t*Gts7u%=;-)#O`-#~@5C_@6%@DQuv5nw$AIqu$8P<qgEnaTc;23H;'
    'l#*?~^MjGzd+!i3bcF|Bln!ll!PJA%8qi)gP%gcmWEqwdU2}%9;cQ@SHKmlEtby6%jksYmtN`3LHX#Zi'
    'XBe`{G{xCUv(yl>E6s11X;q`h>8z{L`cF4Vj+0Y3?Rzk$*=^i0A4rLBG@e7};8%i|rtflQ8fu@^u%qn&'
    'bC-*BgRbr>O*To1dU}pLa=?;q7dhSf0^jbWorVLdr`YK>t5A8%6<_NK@HcGPeQVO~9f4YeRW4!T`~~Bp'
    '<=iPn!mNTgT@m>zIdopw)rOk}*qZif6{VV;ho>t}`uh&M?Ig%M&N|=9Xec9=rpu>fNvOCQuQwO{02VZO'
    'Cvsnlb_bew^nrPwVn<UT!IUZ*^h`F}tsPJ!>)`EnfCGnKw1v4|<m(@n8L)@HZ?NFG3<;k?!;~AY+)r3Z'
    'vW!?3{3FVs_T`upO}>#KOLWkeELZgT)53;giWd^6I?iLCUj2v_3a-fFx<{ewYTe)xsJ_9cyhTF!lw_a+'
    'k+YI()2lp+W<s(r#%p@R+2%BtR`!pkS*cVBFz77vu!LCMPH`vq&5PdIza{3=5oz9oZCyd^CO#i3A6B;)'
    'h|z%wakXTPZ&zIOJnV6Gcy}-Ul!B#_u2wQwb>gIj+RRVE#0yvt=(>DCc+|bUtv&d3yMnAi@$4$2;H)pU'
    'v)1HCh-B9v$#MxO@18tZQ6yKKVM!0+j9}-hAtxE-X$@oE`m9dlh*ajQ^@wDbK&RLes{%{YL=sO!mdB4g'
    '%ZTn$T6KErJfAG%df;x|BJ@HcRFhzTvmy&wzVtQ4x}w82$CCtRM#+jl<8+qk4WF0#24d^6AIKeG_ms+G'
    'XEERy^fxQ^>8CmYv}C+Bq3RUdoa89NTXX_P=<cE6uOV|xEMgktDyHvY8PmB~M{Cg44OC3^BA=>`9aQkh'
    '^LI0b$!%>rneN$++j@bs>~;p?ZayIE>eWrUP6wr2m0NCZ>#Sv)`8pe-jms13Cva*LlTm;Zg#UNwdm43L'
    'LCA1*e~>#*R(L(<Sk1A`GHy<FfVq`pTw!XO;70Civ>ezsI_--xY6jXDTk)7<K!<o##YBIYy#pVndyS`h'
    'cgbJKYKE;_dPb<4K)qOGeAPd-sZ8i+d4u`&=^Bvam^^6&>p3Q+=@)c+@UBnX)o`Rq4%Luzl2!r@+^x0H'
    '{FXI`IZrLhc+Ua*Qwr$UVFF^~>}iU~2awy=*%}HE2+WA;;4=IukTd))LY)O?w|ZlRJKJZV*v~7GBGoRC'
    'Y8t{og2hlhy?lrDO?zDFssnnpEoa&{0Tp-g700XjV5fkdWBTRW?z*)EZgys_QSR(aS=W6fbqNRefzT#8'
    ';FjBtW5U)Dz)dnCPkvtsWKWsIwvLVgfRO2p#E6uS{qpN~A+H5Wgm(=8U@H8;)cyTCuU9Uu%6PzwgD^pL'
    '*JFTtoR{byQV;bt=KRf7X@fjNx?kGt&hnlXH|GX}>e_d4D~@(RoxmI|(c&~7akc4r?@O``#6IzPQxl77'
    '_J}LE(N@N57gHK#E0;VetT@S(qCmLLEMY7srLhT)NDZD(uMr{BwZce$1F>;`>x>0dn4*`kR<_2IcVtag'
    'LId=?^H4Te-|!FXAyu#oAce)-z2tOmQ*Kw+HA=e+;eP{~7d`s(R)EM_QN2qPV84R`KYbep@5S>VQ(La@'
    'L@|UdPYtcU+pubFHoHW@iPS(952pZJ+ixeZvxz{Eb}Jb5O8*{owcH;`L~XbKn|7?$_&|kn!;@)C9#=1w'
    'QUyS6e;E)BP(}8@zFKW&YZN3;$!c|no@+l*RiE4`48!^u8n;oE>(>B$sMpu4%wj{h|Me!ulOXu*#Vxiv'
    '8dTP22PVeVhGi-2ndT`SgFQo@G7y^;V@+pbFkQjTDk=J!n#gcZ=JDqC#Vxs3>H3`w#T|uSho~=ist#GJ'
    '*cNa*Lo7>2F+Fh}D9$Q|Be4WaFAleWwX}3>v@b;F2*J^&OB_y~Aq<s|wdoHMmGVA7x_YsAH<K8^JDs!T'
    'Fk!h1wQr=Xp;gDe8J|*a?j7_Lk~39<VJj~+nz(Ze!wr_5hbc2eh^i97`E6s~w`S)yl<;h`B7^IP>`ZG&'
    '!cab=L1JxpMnm1l%G9(;$(?zgFqD|j{=}kqCYMwc2;e$O%jLiqu#PFq$uLmH?;u}ij4sFa2{0^>P;_FK'
    '<@&qb(JTpps~NqKcFFLdTQj^t8@U0Tw#~N-`@~yg1p`jy(cr9D&Oj#KUBn<;<x1R~5r)sV=xuf@TGMoe'
    'q7LtrCdBS&r@8PTI)X}T^IBo4$JX20m?}IpZ0GHO)8rWF%T?V6`W~Hwm0FB8_n>cNubxCB_OQCR_RG*j'
    'nli9KT(ApG8yD<=J~0<C98XE#rCN-R)QR#EhHwFf3}ODs>{?k4J+IX512>2dcA@F3NnZzjVm`p=DV9Ah'
    'tz{q^?5to28=&o23Ox--qb?vl-KJBDTWW*ht<vRC7=2?Eb#GAs>wCmo0W#o}w*u!4mTOoK2Gjk#xY1=j'
    'Nqn>hSf|@GJUS}6?|i*sK!kyZM!8j~0RKH*z0H<{o;0hdK9=sp$HIus#o_yWByEX`g`h=3fS-z#m{KGK'
    '=IacOuGKO0nx;!_iPufcqrsmNhQbwJgM{hZA%3P#lf_+QX>+PBu=D=cW167q@b^mVJwco2rb+9&S+cVN'
    'on2%brhX!Gr|zvv^LHhAP~RpO1;V6JEy7Zo{HrEJ4YjI7(}eEV$x2XOanaIY0I;3gu?R+A$?fv2v}*ej'
    'V2#_M8K0+$m@aV$eN9<&*h{$x4P!Lj`mFHB@LJjVB{AGza%&C9Ox?xFwYVag-?*Y=&96~1^iI`nx?}rP'
    'LCuq|H6mpwWO3h0;^0E!;3CJtMS+91x2)D_I+tk8kvm(@IeDAyI<LQd`qQf?SI>WXGkx=NdSy?aJ^$g&'
    '6XPr6A0N+_WPNjXY5e0%^*NlzWQ{>+DLc;2rF_GRd*9;p7Gy!i)!lsEzu{cZVx9oH0L~fp9WPFNKaN5t'
    '@TklD$V!rgg{Ei4kr^kJ>m}Ty@Q5E;j7H33u5VKoMU;mT7i&Kwf}Ihb&=>sd6MWouvSnr{yT<?)FE&rJ'
    '8)AF@&djaAWkKjzX5w?^+otERB&0kr3E`AlW^4xuW4;HEaEF964(!-WctkyFvpBHoGtao>iZf768!>{H'
    '_(2p0j^)@fASogo1|*Ri`7S517si%FoxpKC7L$OPu(N68ny%#mf(Q*lO<1_uEZ$~2%Li&%0rwJzQKU?i'
    '_*UYPAdW+rhZWhD9ojIJ#4<h4Vm9Lm@u<UNGYY-f3(TG6FXuC=$eFFlY7HNT>aTQJ{E;IESaCZSnWJR9'
    '#u@+o;@8F5zWs1^=)1rENM?&C6s!aTG~I@-jXF;Lv($w3(!fvtBL6Wy9s-R2ne(-=5(Szs4YIg13L$|K'
    '6U6<o_ur9~p{{}bL~gn8R4$FzLL)zht+|-Z+kjYB+W5kIyM2984)YJ|(YOt~bn$w2y?6oG7>&lp#b1nH'
    '(it1KoDkxKl`%TnUOL`>EWnojJ_hx#qCuOnT+QC$zc@=-^#~?aCg|TbAU%(-vH_fu!84u#AL7MIA&7Hn'
    '{~HR*-}-~S`-aTsoB@=C%ro8t(5hNBqPFf@O^IF@m}OW$KA!Udvz%qwX3N6A?s#uf`gYmg2X^<VHn&{d'
    '^ToT_DqWx>I{Nk3Nk;jCzq%nAA6Hhq{rm{P{=#Cotk5hfhDwT)2nxM&;@E!9%|C#<*EAdgzwGe8cm|{V'
    '{PT-veE`bkYX<lFhVyl6X>oFqra_{$7HFTU60K~p>;aM8r0+9XOE4QCTGi$U?Ib7DTO}z#sFA>M95ADt'
    'SHHy%O8Y=;F8r{U8d|RSlB_s;`F??-5~ZW~_3<%SIS>>qYK<5js!UA;8dWWV!?Qc2yR;Bm7oByHStC8P'
    'ljH38#;gAnci~14vV6FSh`ijSb5Oz$&J9#^m&VsK5t<oYbNJ(<5^$5Z{O*0aV#X)%mG<&ThOfYXzLyV='
    '$CI_VZnfO3pKR8!w&iSH#I;A01qZEgbW1e-OvK%d^$#TG^U*}EXFO3iFV-;YHza!t|B&|t{*>Q?LjGiY'
    '>NOgn6npW;v-xa&CmWw6GrlTgQsL)8=jF)sC75e%w}Ab|VZw7<BGN&wwKSq6O!nX)LGH3OmzOdwjR$j3'
    '9}{PSZ6E##Mh%%y7^h%@W&FXoCuYR-Ua#-wd^DNSbn$XAzZ>I$#VsG*&K7^4vGvWR;kxGr{Pi8j_AHkN'
    '=IgrSHptGG-U->CCQHHuXIu7o5)=CNdX;V#4EYCU&al;7Dw|h~%!wI}&yCsQ&}6UhZPdqfO%~UH0h+Er'
    '4qSotx&f!j^2eR#CmEr<O!*to<}g1W6wCK726Rh-dldqwmH~%FK)U3r$Z{qo+Gg`tw)oy*d++^w+WH!I'
    '{;4<quzjy@+qcmFtz`OyESII4eHbq<&t{Duw3D=x4Bep7EWeMz*`@JiS*?wahY<6h!X)};>tKx}^)Hn$'
    'I<Lg2w!fd(f=q{Gc=bs{`2u7W(7%i11_aLU<UB|CdTX)Yiaza#xCTxc&0wvo+#VeljH4{pQA;HcBJ{~}'
    '3HS#9Wsgx>BrPF4n`NX4h%mYz)m_~Q#UqrtI@%nKAGIJEI#iR{;vJ|GCVZ<$1}1;O`}r`(CwugPzhZ3c'
    '>&*;RW7W6WTwh}pCS3sUW$7(%86wA@Sz>&lJb=k86EzRoZ;bE2BcX5GKc6f8@}5?MKLBwJx?nW90iHnx'
    'F>Yf`v{4pAWr`+|Qb7dzUCVmdrzslL0UnjHK>$>bgH6;|Baq33aJrKlv%>&Fv^?EEN_jy~2ak9!LboP!'
    '&wJP&#ZM0E2f6Vt>mQs~K4>*7`QV^gfp9BMN+g;jWhS>|3E~h8U_7B@pk-P!@7|y54FPk!yd%yVVv^@O'
    'od4B+Of*JFIm*+IhD?R(WiVELrcKN&@HRr*D@W0I$T(mowNmJ3p9!bkd8{rG&UbN$HuQ2`xe+@mzcQAT'
    '+&geD5_d3w+S)&r=SmjIKr-%<tdTOu#YBPd^!*|mRi*8K&C+<BfQHv2W3xmv=V`-v$mj(4F4=FLQT}g<'
    'WM!D%6P8;UQG;#zvOz9;^NiA@ZW{o|={X2w&_;(A-(#He5%K8;sTzYg%sWNY)<Pc*^8BTb2iT)Emks2i'
    'mRQ*9r9C=!Y`WjSI@3X(?!u#wi&*paT8^|MTjYXAc`AbZx2`EJ@c{qaz)Y@p{8A36gOZ<G9vYR87uCVj'
    '-edNOcmUX9f>kAI3mf+ta&HpQN28Ufe%wLSZ-+Es%-?!pD0e}=PSbhYIsW<29VWR%p@xcWlE^%!KC>*G'
    'mV20HzE}Fr^PaFd7elq4WwKe&TF|_Wz&V%#^5~#>&~QlCV!#3Fpc5(%%I-FpdHB$HbHj}#x#k90pz#by'
    'fd7J}VXWZ`Hp6D90Q=k!$2JBr#1$C>GtPuO0x|RZhG*+ZyU||1pRMT)a%Q$!C4|DR2e}WUWWZ<hIR@*q'
    'M=(mp*K6Eo#RTyAcOZ-LdE@|W1KMK9#vo9IsE>_N0|Pv6W*VUu#zu><Lgx@uUp=)P=wp_=I;HHkx*2x$'
    ')}|91RzA~46M~J^KVsI}j@SW;66Hnm6XzgTWN1P8!S|rNH3pB*?j`EjF)-aRE<GqL-7?!n--$|na$CEk'
    'aei%r{<Ylak6RP&1!mQa-txOkV|PgP{O*C^{y}r^5Kx3!v8blRv0=NV|3LnE_sh4d85_}bzPUvv{RjT}'
    'V$E+y6T-+6H$5Km&Tcoimxg6~<MD6j2Ik-jgT}Huob-K@uAUQmGuk3}T(UAc9>wKH>0Ogqa91wmo|1z8'
    'k@&M9fzT8AACnn-)c?>=h9>i){jL)gYzbRE1_6J&-Qtr4x#h*_JNcka-@yY&&<VJ!9KyTqxNX{qu2_bi'
    '-PE+1loj1t@a%o))hfLP-6{Hol&7jp=LZM!6Rt~Xx&_N@Uu=Uz8O~}D5?zmO+KQ6SQN1s!k<_vx>K}?b'
    'b`H>9S?lE1Qwu;{@~?;ZJKKMVw4cEH&lyIva;)%i|Mu#6a&%I`+)FN>SS+_NbgD@YwamP)3~_sKaOOkB'
    'u`G`$H+m&BSDlc!A|S84>;&l^9n2oa8{3?HKU*;QddFGTtR4}sP~(mblHI{0ZSylKN#4d6Uu{G1?NxRa'
    'MhV2D8U;%sFHCKJ)bo;D{-exjc&(gfKEdHfi|tjZ`sFE@$WDs<{sAkXWe`l8=`F>Pba25B$*Y8Mc5VpL'
    '8vpuN31@|;(pn2uy(!ryq9jE`Vo}VmXNysWWpZ*~dm{d7W#_T9J)7Vh#FiEDq&sEXt0A|`9JMwuCHg9>'
    '$)&YiD=4alb=C3LA_q%yteE@|ru~HP(wp`uyT27~S93Vj*MY;k$+RNrvxEFXj{1EgFXKt=(8k;!rd7HJ'
    'EAK(4bW|z(HA)Ng*QD1M=&7Ud5~o(kLfwtz-g>By8fppc9+XQr-O|ahzpp@i`(1l@(|-D`OLdF<)^gtI'
    'uv!cCNTm-yh(piz96NS>kNP%E2=^1;4|!rTKPE}wS&Z87Ya9fo<=b8o`JNYB7N@pP&Eu6moPfJY><6aj'
    'djNt2c4ASBFq2!<i)}((k|fmed_VFm*NXxgnn7eTmxqZHx$I0QE}H9oM7HTMPA#8>)QW8Ggf?+~pT|j<'
    'Sd8(2Mh;9jvF(5nmnNZ0c<B4ovI%36<+iE!;g{=u1l4*Uy~r&)XJ9b78^Imh4}y?7-0_nbE18gpnSS6?'
    'kA)74e9MkJCy8B;5|;#yZAF#^Xz^p)p;5?N5S&}Ya$FWWj^}aTp{5@uG<K83V{z<}m<B8$)HK~Nq`v2d'
    'EFz}oI!?qx#PXS5Y&4Uc2A=6h7Ih=yCmfjE3KB}92pBtzf#G3-aqJ|n%^BdvcYMoted-WkW!HCuuno!G'
    'GReIGBtKA8cBgU=cc|;SiR+s{P9Sn%y9BtHn=vy@+csUt_sqbu5@tJr3uJMD8<Hdn%+O0H(@=8=`<y@j'
    '0Q8t~P=cbM?gHfPo+?Q{!I#HaD))wSp2qq?%nW$K;=l>1ZCZ(+L@_MP29CBY$1z##JIoIQhch?k9s^WZ'
    'JO(ziEDw0wsToGqJp=Gf+XC(+iA^a34kg@i6WBLiXot+^fo)TeYN72!Nfg;0Nq~t18)ZSr1CVfW9lqqk'
    'T5X?0HeuPEkwrZauc9XLYcO?XU5^$OdTKgHmfxUY++7-_hV)nBqxN7hJ`<<xuI(j=J(@2QD*@G4TiXb$'
    'rM<mWGo6UP&JA&2F*|UtrxJG(Z!XhWhWXc6x&(e-tPft!Y?$T$-JWmltwgpps#_6M6Fv2iv!JF*gnP|J'
    '%~8Pei^ckQts_lbaW70UkSCg0;?q8!*n3c^{DE#vnE!xR@s4B|Ce8!2+3cT(6CT?HT2ZWH4IKDqH0}=y'
    ')@zKw<KiEHDgv*V_bI6<sWst?%`NI_&JJg$w8>WxIUTB0JIwy+x36%_(T7Vp_~e7}{|od?-edIj+_=lX'
    'xPvcRiCuj8Mnq}H!=?%zoxls`PMAPGMEC^t>S&!_7K<1c+|g=!0tncjKY*cIhtq$$pV|q!zC5j$rS)<2'
    '***@-q&$3@ZbY4^Tk>IKo>!TgitjEAYuHGFIrDL9(pX&~y2aRJX+r1ud|C|qr8yoO|6y1_uE&oX7SMa{'
    '&D*|>8Z6IYx#G#}!)S|yaSvhfxnxCWQE{J=Vz8jtD<?W>zfbDCKikB`kw2_#k%~YOdp5hCiDGLCct<(Z'
    '7JAFow!=%ir&>Mq@Zm$_ii0h4ml^3|ekal{(UjvX->b%(n^|UHeRAUlB<3PD<|!2}FJ@(~u{QzcW4>R_'
    '*1Qc{P_iU4r(x1+in~<?(LQ@k-f<?3G&%hNR_wMWVAX>>UPbg2HnGmahetqH5=^c*+fe>vDmQ4gPTcmJ'
    '_G2~Gn?pjC?Q2Oo@nnZh(g6Bh>&lreW+@VivC@|K<#B6ZIh34B<@-Gxkr``IA@Fdr=4B(2C+b#a52zdA'
    'oBacvv)?pJvoh*LQA<_mtZDv-u9}<|o3FJ?)<qHN@iFOUwc^6k63gsMUU9C1XsKo3O6c9V<`>~sj>vp='
    'EhNLGF`099oxOF6WwX)-<?>|y9(BtiUEN|4CYjey)7vGihAWEU<*RobzFu4##E=%5O89R@%8ZgZ&y3l6'
    '(s_mrv5-;DM)KeD-3UcN1bM{wSp2uez?V7EY7o1dZnf<8enu()QS;f}h`~RPq&FTh(DDL9tLpxpWN&B7'
    'di|&ez_stmih;>}BuTJ^35!QxH=x~s$wtGB;XENk%)6F(cAjstOSyyVr~KN?w|!r%w&*P9Ebh$fQLf24'
    '#?p2S?rn{&qXqT0kPg<@YGjRmBpVb1D6y;RfW(<B`uRP-8}00kTxzic7Ys|I?JSdAgCYCC0Jh&j03O^t'
    '7}s|Pe)m7yqO}8C$*x+JFne&H3`DQolKDncHs7eQ!t(r}+<<DO&m`Z?$wEd*vSDQV^oQR1lJooR{a$ZX'
    '^6te!U!j(l>Z@~Oovz9Ja!6#YiUL_sQQk_ZqaYvk!C2R5zu>CmXge!Q&=6}!$O$;Y6#Kw|MMlA5!RndG'
    'N*<T~z!%r+n~^ylYn$~UHre8+*I)t_ZA5%-{`3>@>TMM9hqcGfo5hz8+S!pi0MG>jT``0hGLVI(kT3!;'
    '!8n>MT&ap~7S$`ekI`+Xc6+*9nBrZnEJa24b%$FnD)?^aYW6VLrII3Py)KGA(9I=L^ub?Mf<~G~DAl2n'
    '5tzx0^-<H(UJ-s$UIOi_LRYuX-fjk7K79~cTAV)Q11ZI=<0zqs%>M-g^S!q>rihpFy+yicHs^dfT98F5'
    '_jWt`q!yTYg?7pe%$*e|)1S7mh6MRles+KA^fwQLQ@mwrER<g6<wwKjv?p1&h%uZuUwA(sU;x(b^(}{f'
    'Uc)_~7kh_T5a&Zwo-LLu^6j1GiFJ^QUj39B>6~4lL^9}{lf`BUQ(K7Nu^PpkU~ik_H7JH_xr(Xue9lD-'
    'pWe*o46t%(2t0v%IUWG@pq-A#Ef2;g4E@SP=8E3vChZhMsk#*^iY)%w7E*e5q_V_$I|pqmA8IPF(}eRN'
    '-i~rQH@@h+Yg>%_u^JKTK%@4@lAnJ2)HP*O9g~$CS{}<KHcijr79~MqJ8sPUh`KZismpobdoi}NjCf#1'
    '+%cIG(b$Qc(DjHJSzcsY4)>1d65GUOeh|m8X*w)1eb@J*h(?x0ct~wReQuj^6mgp*0eoa7VH9&1g(SWi'
    'T7iA02MeFCO{7!KA$In+iQIFFhIe~ki#k62`x~k1O#K1y)e28Vp5s4{+jL&+a=ue+<JT1XySIP7^_h!p'
    'j=L3Xs2*Sc1R{x|nVw))!sYgY<4gI;^A7}_&Q66Sl*kf@1skC{pezNTkS_i?m$iv61t~lBe8~$GY){p@'
    'SFfmLgp)on+8>dH<9^WbM|IplwL9U(jHTL@2?T9>Zy09};xv6bp>wdrSyAp{pkIG*@`_6TOcz`zF_G<h'
    '3)T|gCE3jXFMj^9erJ9EPzWcVwkX|>Z8X3P8};lORB)4;!w#0Q702Jn{OtqXqbkHO*`Q4!M*hRulXX5J'
    '{2r)_<N(gXzXptX{6up+2(+3#O502a;LZ#E)U!2QOLa6<8x2%OhlejUf%~4{wQT`cB&3M9E{*R9*j1wV'
    'Y|D#+rIZY1r~ClM^2@^+47FSDw_tdJ!V&rXzN@iL=_+5AT3?YKqGsJ#mh`+lqvF?&)k>uaezh;<>oLrv'
    'L^gCY)Lf0nxk|h2bV;~0>hm%?9U4gL>fYnjs&Vca2K=d(wKO}LSskq`?MBwgZLGs4)>jpBYqhxA7+haf'
    'dAxI(nr`;jNzJc&vc67XeBGbz)zkF)ESA@2FuaZ$M@>n|d$Sae+Dxai#rl|HZFBLDwS_HbhfPGGU)7zd'
    'p8JyhzQHfaf=vhrw)d0GQdFeeT5|iX#xA|Xx}8a@DPslT?yXn%Ki#}JR9%W!sFdm5$vnAjEkLEhJ3Fx='
    't9Y^gc|qQh*&HoPS=6w;Ajz3O&H%lO>kj^`2wK9DZ^`N{tXlOAWjv#+*-}Pfn=x1!@VnV!{a`#k0aNVK'
    'Y;vm>*@qGzt2ruijH0?@d$!&-qHHybPm@Kxh1!lnL?omgSijm+1T7<hyY*dlD;J0AxXLaL_uhVO0xk|x'
    'iy#@>HgW1U?ZJ+_g+(vmHTlx*%iMNjq}HhJR^Le>xYZUfj6hKZDK|)ql1SZ(Zi(~f0wNwnD~`Cy+mBC@'
    '*$S^q7+;!`b%x$W;g@0UtYS#jsal>9?;jZWi_eouK5hB$uxeSIyC2_!wrip6POIxWsk-~rbO#h&#kcM3'
    'HJnu4-J7<%UuCCX*L7EQnl;@4MfW}Lui)yP(JI+i1?VEtsy;+}&>dChPAs5<D%GM%Pp3$`7hF58M!Rd#'
    'N7dlk;Y%CUOJU^<0>L6JUOZeg^kB)*PMW*r7<rA&d?nl1V!vwN1=>})(2Ds`M|D1ItIFv|i-(?cUAsoj'
    'ki`tx6Q4TQ3v6ol+cM#UdX#uU<T}LlDV9l#X%G-I@kwaMBrqNBa+@+1!!yh=-H<Uia7fI;z>gf398dUQ'
    'q3L;16bGK2P-dAfcg@%d?Id<g=EXGf<0uIeJMeAzzaJ-rC!90aw5b`yo_nSb6Q3{X!zw3zScj87w#{Kd'
    '0KZ(S?lPm1%&tE-@_%1oYV5^dj9=0j8z0TWkmBrM7q|`}DxKNdyeAd}tN6CmVc~CBC9_z<F(~4&Deqyu'
    '1LpkL;?5hVe%{KzT$Afdg?11F55Q=|@ak2H!OhCYS-M)kxx;$JFT_=3s~!CA)RtQ8JV)za@uuz)=dpjZ'
    '1E_E5woYY>u&)eRR{#kzBlBP6O&>{_qy0#9Gxu=b?#bFauT{DLc6_hHa63K8N26|t8nP2V%SPPpljeqt'
    '%E~)$?sHgtyAN@Dhpp_iHq$$an7CId(OXD#l@TotH>S7b19oLO2y3DqdbI+Tt7>XVT#UXn$FefkgLYBX'
    'DV|b2J23mgws;2LN&7-PUhD<6yjG(LYqL^)fBVOy%D3Cf_0<p5Q-Zb!J3NRd1_wKPXL0U0vu$F1_e1=9'
    'rTythe}uq|0~hVKzN$;rN4w8erXW8!T&q8s)TFI&pevsY3>x&!c4^|qjwh|J@aFldp$Xa@igwYcK*SQi'
    '6r!-y;HYO7YrW+fna>}LC!lObSkQH{NEf`<*;{kJs#-$Bm!@icgyTuYL*}r(@aEvSUy5O;7xssvwg^$u'
    'prAr$Y&5lW+|%f;XuMX7q<33cr-xrlhAK}6#Z~s82S4TKCbv?Oi3sI-vQC+-hoRVa`_)K(H#Rz-(41zM'
    'oM@ALraiKE*oO~|?>S!@WMS|R7*3e2(Yh3OW62hKhB_ZGl2v*u>OU<&4DKDR=(&90KHY-@Q+k<~G2CQ8'
    '_iQ_lhk{ogJ`wupmfRUsgx2BNSq6VEHe@c_OT)kqy5d3w%kvH}qEB3%XU>f;N`0i%jlFF2{)VqWc^?R$'
    '3nF3cumt{7|8%#}KB@5lE49|x=7I6Qe*JZ{9eCXDRH<}OQsTZ6*!xOY`qSqV>&K*e*WRM7PFx4{8Qo=&'
    'PEAJloW1sIIC@Bm9#MKdxwR8s5;b&>v5I51swvucbLYBqJ4pfgfxHAOZ>&~E8n>_Vb0&L6_TKwlFe+z#'
    'FH&KLH<dT>=RY^~{nNp*93g!cMpYx9P;hp6wx7|c-)3xoko6Q?u7^+OoA~J_TZ2!xQpehF(&dbb)ZaY~'
    'a){3Z><U98!oA2giOa1dwr%3UrzEslLhZziB8w$%;9J!9c^Hwv!|TMM&FR1fImNuc#W?4Jhz>amtbx9-'
    'LCzVrAF`?C*k(eh&*6Wu@5Qzs1uSvm#C0vtq`qgH5w$HRHlrX&Y*+=e63?}mqhrRPy+FZo?5*@PO;@0M'
    'Nc)ykFqt?YJn*8(b$AjdQRq1|i4u$ZG_Xx(d(@3AVw;xBqtFi`7T7M3B!-oRA#HO_JWjana2f<Az%*k&'
    '2rcT`u|vGrGi~CAo<~9_a%1B9#AUG;dI9Im^PM;jV!g;{J~-qdx81-^%rG$BBsP6NahT(U3HL&W#UU|G'
    'm{Uwc0#qf5&0XSqEDB8)C4N9?n}b8Id~g``>^LRXSiLgxBbJcY*}e(;PdOfSOqZKZ02B*?$aXoR#tP#g'
    'U~!ZLloE#qP6)J2u!;b4iEAZp6uR!Q_D#N*cpST4C8h<N*b4(M@p<IiL1c2+Iwnsd#%;@FBmn00fIkD9'
    'I+PIyDB-tj-&Bc|i8cn{Y&==5$la)@v&-_%2BlUD<FSgG$=)@G!m*_(>;Pt~bomWtd{kk#@BPuTO-RR5'
    '{P%$kt;qO%75|?YF(y-jiG!v5!Rwu6qBMI(Z#dh``6B~7d0BuNvsJQl<tk@b=pS!IW#HehgtBWj=5iB*'
    '%rNTxr?v&8E{*5EZ^-)CrPO*#Rt^?CRVpi|@7AHZG=3I0PVoTCHm9a3{y$(070&+#jb`K;+wBUhe?@f#'
    'K%8xs8?s!=Bem}J$VH*cQh%8e%x=YOWS)}*hn31yc9UGD>NDP}bQaDs$#IR1Xv7%jU^>Fqt<a)-vHWb!'
    'mzWYJX8kZ9=06NMhVlOu17lN^$MFBoB|+r{Wo$95NG(vIO2)zOW+!OxZ$SO4cmGpOyL(Bvd~EstMGo&P'
    'iH^tWb5)KDuz??U9z-r04}bWAjc9j<>c%AnpUH9m*y2~5)?J8pE2<|3*{pBC%Us`0j5jlIDl%g}dxzbq'
    'L?H7u8bCk4Fc|i%o@0UhqL1*TgUrvX#m9V}F0M16vy9w=1*K9tABx81=k@yhD*2NvSW!T$#h~+9!Z8n2'
    'gNl&l5PB#E0ZbK5=%Zn3LR(_##j{J}WsHqcx4w2?i1~e}%lgf3_4(tzfYB)>*IX1vkf+VPK>^<+vujK#'
    'J(@^&1bah!<KWN#WA9yi<H)iEvG4UOa&iVka)wF8`=OfZYKo$&G+lZO$*P{Qq)FT-nXP1Ic0Qz1s|5`F'
    '#cOzt^@p{+@U9IQHVhls^)76~0}PCv|6;p)XFmBa_?&wqG9xl0lkvEbRq7VIOC*yK=iYnndEax-$+QE?'
    'YQsC*_*7~SvN6Rv)jLya0jac3F3EJU(|oegN$z&$id^OKR$C6hQYc@ZD4sr9{jr9=NcTT8$=TWR)5MHk'
    'W?WCJZ|a9O3Jd0hz*$<6y{;HQ&pW*Xkg19Cta2NdbwJl*l(dk(ubTd}hYGAl+fgMCb7<%=EP|*iNUOG{'
    '?-aMJ>Qz@BCs`d>s9=+-wupMnq}pOfSF3IeRoN+N50y%`6zW5)hk|tyX8Npfq&*zok&EFlHTQJ~G^|L<'
    'h6{BxGa8S2iOvScX$YG7r13fmJK#2Houp{89t2$mvvMD;ZSBGu0a`Ie^>$cU)c~@)G6^fHO-|14cOH%x'
    ')dfbzBU%z^#xqKsA*-UHo4lrHbht)3m`au#@Cdw`<k9@+?Fku$Ipxw9`1#A)OnK*ZZO)a)yj>u_Vuk@;'
    '&dOJSeU`5PtFm}I`4X=9Sycr;kXq}hQ96H+^z-Wc`qxR)o8}|<Jo%|c`SMNj|GYEFiO|p2Wk=0kKg%|-'
    'v+dol)%s3q_rT7*UeF0!gRC`kKnb=Og{l8)Fwvb{XGu%gStdRQW27k;s=?`CivAUTKe5WJ0QOQnY}Y6y'
    'y{@X#DSw#;UXt0aTKa<jZMEnxXJ|Je-OqD`o6_ylw#&)%S{)%1uE~M=<3H{c^d4K<9+i3rRF)b_SY-O='
    't!gSi(>0ZQKS|BTFKfyEw5IepEti%IaD1m$s8*giqZg9-rowMIVAjZ7{e09ia?|qF{Z(7avyB4QD`e{$'
    'bJgj%um_^Tcg1#><yZMrKA17sW3-?zRLH4V7p48Db|Ij|kj4mdThp!-YsU#c{y~NxH%ZfYQ-CI>UXfgR'
    'zfzP-KW2-v{JcKTEyqYORWyQChl{sUb$bk(r`uIq1|3>ePRVg+Hz7YOUy8m};{9SP@m4>2NDs;~XAkM_'
    '9;eE?>Y3kaO)2!Be9<Yg<*lPe^WUV#WW1`pwM4=fYnp3cs(MYR>fV<nNb%#KvlR|o?5~kWVP@OjH<i?%'
    'mlw7_Y{v<eV6wa;mBfWh<`PjJ&`=Pma%QZ+kxuM$Lc$;nm>UU8Se`9i5yig6VxKz1qE6_!acq;o=C-&y'
    'm&o;45K=#iUFr);i6aDyB$vz!A`(+OfI&SPdol`QH{gNGL*I8JKlVKy6T%M+q2c4`IZ<q8>UNv=J6B2D'
    'O%?mrVbzR<nIqy|cM>(Ylg#7bup}QU&?+Zi{Q!U1XzNs>Hd|&DgAputph6c%`8odapMKG?8<r;91HRfs'
    'mq~2xvQ2j!;vNicC*$e7^Nh|g$7Hwfy9*9RpONeI32>U3+gaXwQTJ!CZf|<ns;?O2&wV>rH)8e59i!<~'
    '9`Fe<Z|9eIU;3W9o1*VrW45^-0!$hh`g%%GVB<-eKJCGhGDK$=?}&CE{4~J~PI>c`P7X$7*kMC5o2~At'
    'rq}K9kPWZj-<kDW<|Jdlv5{JGQ{gzNj&t16Df(rJEPr-fsbYS^1LMNe+!bF|d$Ii4ZPDA9mVgsR8m$FD'
    '->NzVG+c-`s)cNtj#UCqiId)SEml5lywu@rBDB&&PxWg__;(+g=8&6x=rsF>lEZBxdIfRwZ!MRGYI^$G'
    '@XU4V>sbMcJXw;R>L1uv!PLgF;2i}@R3ceT(Cg>1C^0Lvh5$Ho5T(zXK`D7yx$$1nE>?NJ>=9?P^T^F<'
    'i;=DdQ)a$D%@`SvuSa7PBPp=Ag1lZfK0yo~7D~b<L#Weru+HwQKCyp>bybc#Ptl0@$(Q9wuEfEsdYlV<'
    '5?j;4Kwq9PWeeU>AoC88Xz-jXV`8jUh*{1_Dq3d_rp;`iwh%mZu%2ev-%}msQ^H=)vPb==_a59kJt;BR'
    'g}@rQ_{wV`CNp*QSusdwMs7t<NB@_m+UGh+dAgXO*jMS*>M}AWF78a0+c1HXbIx7*@VJ;;^2eb^rTYMl'
    'Fn#a~&9dtqbxMF3$j<V(RDnuQOY@V&Kd*gK=UDab!_+*@>EF|!aKf&o>u?sX?|mm%Km~K4v$8W4nx(JI'
    'rE!)l5Cgh=d61Hr`>Eydd3tiCR#O(p+SaY_W$`(q86B$F0^J-uajJg4v=#_l8Srb-z4C>2lNZ(x0MY#|'
    'WTMP74Kad(=^J&qBk>*uAAnPb9biEcfs9J0lHHx-&S(r)KWz8>?RfgSq~Eu`0a=J=&5u{NAF9p{R}tAw'
    '`>xuNYT1L-b$Ocqy~aUnW%^E{H_tNz7aXuwBlr!*J<A<F>0eHgR>NfuR!h_9X>tWgSLH}k)NdEF^a4_n'
    '8viRrvuUgZ*(JFR0Vr8IRaK~z8K=wy%1OrcYea(E_v6mPz`8_bhLG4kh-do={IWv#WBF7FE_l&dky_TK'
    'bz5P(S7$&<hd0`4Dy|2kL)G{`nO?itQN<P7MoSWK`*9&ASH?Ys-U1pnqT9zSlQOM$nLlVulvts~u`B7~'
    ';6q94J?Z|gY_d}BtCrE7Q>JYO%#+4CPD9a?Lo5{1nGMHyoe0lmFs!`5)sfk|5xbd=N8`n;gI2^znULYq'
    '+FnjFbE=qxa;q&9Uc@Z`9KKK<GfJjo?L2D~zXC_Bq}|Ph6jNP8LVkH7!DXG@Jl9h`Tu%6?Vy*iE3R&&{'
    'aWd9Aji@7d?DvwVk4ChiRyeLyaAVmKV3xE5AaBVaoqMKg<YARUBRkQew@=$CD?VBx|M-qVj~jTbSABn_'
    ';<A2Sf(c}m(ef%EQT~l8x6&baYrHd1p@D@e)*=_fW);wir?u`~4wEXF8gKbe%eGcY8XmyxlPysONz#zC'
    '!UO?5SpXRDfHewz{{n2CHv^Oyc=JNvKZgNRZ{)2yya9{qq~fIC|BjO1`aa8S!PQCr)3PWt6i7&dC<$uH'
    'Yx;68R8sGGLET?%S9-!-!Kx|P^ctI(iz;OUPUWI!E8A+AmWnHk3GK15$6u&!Rr1}*_iW6?WIF!EJ^Tmc'
    '*U5x_k3Zg-S`$Q(D?Hz|BxS@6Sr}8!i04X19V?cel++cr&A6nL5?69zxwdqf&Ei1F(7rphMl$Kzf%I+R'
    'QR-7WrlEAG9dH>EVFxyk115zpM8s$y?I4iCvuPYVwh+|!oddJjD9*6)9d0oh$1>oNMMKXaPC%)QeJns@'
    '1(xJ?;QJBtgiEZzhJ{GqvpgxJbp4pgG8s0G6=ZX40KGM9^?*;If4QfEOoLycqXDa)sjJ2_L)Cf$5tGRG'
    'gzYgWCOo!CL_NWyD0F?{2cFGsUr6S=j6^n&j~8?11_5_{ETm<TyQ=j_8hL(X@hFZ0!abl176{mKEYxGe'
    'c(&w`^gN&n=>{PUV$Wj{wJi^3z#>U1RqIh)xA9~0gZlR282{~ptD!np-S2em6RTUT3QpCFAXT2Okl=Y-'
    '`cc)eD|1ckMA0fNzDizV7nJH$)0V0gfVk7g-reIWV1@}XtIh=#=YX>qRelHF(meC+XfUtwwt7EVu{zxv'
    'V%9*VRVQE+A0imN530@&*HwPH6`@rm!D^H3{_3XpHL0;ZKSEUh=3oAIzy0U`{x^U7zx}^||KI-R-~5Yz'
    '_}hQ`AO7y|TgLW}j^W8Q8H_$L{149XdLKTqdOJw|$N%I%|LuSE?=-{zzHvBS*!aZYKOF5{-i+U7iaLE#'
    '=`G^=AO7}#|II)7cfa{x|LJf4%m3r|Q=g}GGd^+r56JN=<2|i0x7?OboZpf$pEu*Rs{e<-|Chh{yZ`C;'
    'P6X&%k)I^M4{g+Aj9B%z`Q**FkMiICoB!cA|LT9%eE-{j^{;>XumAhsbI*Qx9r%+V_yGk$)(A*<<dY0&'
    '&HP{Keslu<$$#<t#`LN(*(Zko;Yjc-b@Vej|D=-y`QF}$QRm%w(P1~^@l2e25(Mpe1Hb(j|NcMxkAJ5_'
    '0a-KP|NFoG>2Lnozx~Jm=AZrczy3e}@o)aq-~MO+i<TGv&)@vVAEmG;`DAHgC^!MFQ03!F%;vLuSmYx4'
    'DcAJq`E<+|O3<jkZfSkQBncgdSq=?i+oHm8JU5cQBT3|hQOtQ5hXEr2lax#5+Of+#JaJ}L;Brp9hOLj*'
    'm+)NY5MWpJOUw&<I_4m40VEmjT16ynkGh^G{fIIeIs*O+BH~8e^=vD!EXD-!L+1Iuw5W7_9@!!FEIe^{'
    '<JhXTip2!0B&3Jzu$a@yBwYZ``|&Ng7H8A(WXq(57X>8pyx8|?;BZOY&}FU_N3pcvGtYLI6rs<e5PqN}'
    '3}cT{D-1nba9dbjiENNKjzb#Q5pj6rTUKaU*u=__j)+_#BO2K>6vC#Aa7t{zoCs;;1tKIg4m?s70Tpv4'
    '4v1xQCx-RGuE4wqke@9ri-ZwuROp7VLAGZ{HV=i(-8i%acR07Dw6W)q6O_O})4Yd@7|>J<gn;6C#g%Cb'
    'wV#Q1Z^u*qP+*-YCU%ju&1J|rbsQNI2d3`{-;+G_A|M&tb!Z412NM<+2?UUb<44Sj946e513%l`3`rNP'
    '=ZTnN1?l-itZ;fou61MKT}u(15eueFq6jF=iK0LRp67DcVopej7uj|MKRVLImARJXQQz}rB$yY*E-#Vx'
    '#0ViG;skb1L?q@x4Ajn~4Z@7u)U{n3=!!<%6P)+~vV&xRun=G1AROwUC2cErb|cv9*}XY@*iSF+^wC)C'
    'PsQ~Bh+h{nnY^o$EOZbDmb7^!Tu;V!2t4dYHers(IY?@U2<+|U+Qbe7NNmX%=gg%6NDnLY0!K=NYXeH|'
    'vxJoU%iP^QlGa@G30Lip3s-s|e4B*Q<ze8%J`pNmvn_1;2eJ=@8jyl*JGRF|4$Jfe2z22R!7Ku#0gn=s'
    '<b3zqUTZ$>^Mp~0R^$PpIzY<46t)AxDfB^(S)g}p>PLcGM8qI;0@sJX0%dwkL_p8X1&sqrHr(@yCSscG'
    '&a7}TQ6Md0GlxnLeRdo<0ShGsrSJIM1x^a%7_5YVdK?r}KqD7Kq%FWA2sz`9*Y;wrhhs{Hece1W!(>S{'
    'ow~dgc_aoc0|E-<gB?rH4>&>D0V*a0o5B%*6_2?*V6kHdU{E-quq+B<+4q59%`NaYk*Yv)AXfWxa^0UO'
    '!CJIilsJKK1=t8N$b!%!GH^X7B+T`h4bp(a7CLS~2<Up>0*MNX0fvigk1*m%a<@SBVvxy>h(i(yA4rzE'
    'ZipQ+Ee?`Kh7s6OwiQ{x1CAd?Byc<yS^@V$S2$9zum!|m-n@9*SLK}gIup4FHzC1^OU`^@$0CZ{z@tE;'
    'k&-vD2b<<vfIg1Tg<$`<Uc_M?u&+K5RwVDnjfkadJ8|rTN#(~fW+Ie<K)vNquq%Bp1Pp<)^TEghc`f02'
    '?uTGGgUGhyATo!WiEfkGCvV7{OpCDr0x9+)Cl(-*f*8zWi?}{a&Z4dr`4m3!d}hfg1nCv|AO<23UldFu'
    'ZqZFEqM(=`1-S;+x5dGaaD7V#oP&t-JuH(aT^EyhT`B`4SdRr!NPIWom~Cte>^f;48yJ@9C)X%S=_Ute'
    '1A5byo@A&`iO*wdGqApc7^Ha^I|5XxZ}Zsl0>Ze6EZYekFA9M*TpG76{8kIYWcYq^;jwVLeZoW>1Yry!'
    'Jb?MqD4;S7VKE_fEFXwIrfvwl!9j1uK6h9w9WS>004y<HX1h57{bsw&0T!b~0+Qm0!JacPP8<dvmdilM'
    '*fthxv^|T#HuEro$32_FQq5sS8(0|f=}(ihxOz$eJX}8lAqsq9``F$W+y!tTr2u{fxdx^;hwUaVOw|(L'
    'O*vq{L_8*r1%lA_Yb$}Q+nzcI&zEX?r*8nF*Krx_T?9%yreWZPSVJ=cc?>Gq0q-$_eU3tK4Va8#f%)^k'
    'L$KqrYX^Z@f=$=)mD16=Fw1(myB(`3wMQQKgo2@~18cBRH%r)?AoN9u|4E6m1<Yg?`PkPtjw0}aK>GTi'
    '0RdZ$*S7BTJVY(DGa})j1Md^!f!E_nAMFPZ3<}4E-?3b%?M5y<!zrimU`XRI<}vswObFkJOK_quVoP#2'
    '@I&|)ElSXGz?PBgf#GJMX(n9P_rZ#GfdD)z<Jba`kL|2|5Me=6lw^7|??Qy{xs-$56hvUlQ}E?|FS1}F'
    'A+VGs0x*+#07}wvsV_qx{s9jsj4cMv4GluaZiiND#+kfWTFkOwlD;K~M{UqyamYg}wu$h;PY2Oz**>)+'
    'F1R1Z0rNo=1L4BXOUX-wY#8WK7sNG<ktRS7gNFy`34BQya4?I(;BY+fIIwRz1u+g*xbT65?9g*4B~1~t'
    '*2<<S-%=r9YG6skVE#A^7?uMqdKhexF-PZ)lOT@4QKvDJppqO1lq~^M#q(@oHD1ov`kRdfk_=&o!8QOl'
    'Ja%F%WE?pWLtB|xA&@(K2LhI$BESj<0}K2GFOq~f9`X2{HH<eF#>Z@S4_&%m>eBTRC$+b9Qg8VN!Aj}}'
    '0XUz2XaNCPU;}e7RYibp;H3|nV58de1pzyaOGzDg6sBu)M-V4wt{Lttn0(eBEtq!%DmDb_@W5;l3=n4X'
    'fP`Q^QzwcD<pj)B>2e9G+5<a;#-JL21His_0o@)qIB)HG_O$ESOI^?2()HY&eL2@N3eXLSB?%}MF5Y;v'
    'fqW#m);wfff*}f`)3<}z1zRHsZOa4O8hfaN+rk;CwU*SG>M1X?2VQ1RdztqJc#?LzEV^5;B_t-W7X)OI'
    'OKk8915m->_1L}$0#AaKVLRYDgU$uzg9a6NVbmjm?}U*hMHyGZ$LJ4Os21_5WqX0=0xCqvtuPEDaI--6'
    'fjkTX5W>Xs!WcL!fWL#Q4xSfi*IFn+GqR`5$fVs}-3|4bXT=<RCIT`Iggvan1|<d_aU8g|1yspAI|K@)'
    'K&K(N)S#OK0W$}y+;ii~mhpT%9s*aPMO^Iqu*7ICaui~4+bq|yC`bn;Lk2bn=w|erLoh2{_?r)O=|rG<'
    'Vvr!Pi=fT|a4961F)=YD7m_7x2`ldO*(@Jidm0PQLE%OeWMC923j+*`m=REzU;x{(Cme7`B2QQnoKWc#'
    'piXemiEnZNbERr@&<%C~CJ&E@q3o-Z*8YuduUfPU8!#_D2b>SE*Mf*f)Qu&xm<=2gaWL<|CkN}*M*AMH'
    'Pr?51eegje*R?p9lP#^{dN3af@_N=!3p{NLV51bnxDu#pMs0A29N3J|3M3Ce9(Z6XITqlbf*|l6a2I_L'
    'U$7d>;miT!l)85dg%~V|m@zz(LSC|ME{KR63erJ(pbEgk^3=J99e~XUo)ED}K){6$!SoUZ-r0CK9KRip'
    'w&G#B81;2m%)Vl-!g#5}fl&kt!48Wgnt2>X18>apJ;%l1n6zU7Q}?A0Q?>~BX_CZo<OjCv$8K0c7>0rG'
    '`W_*|iA6vy&tu&4DFfB*GZ&OLU;sUOFg|>cFT`h|M;Y;AKPKREdzIIn+5eF$>2Ws}s0czTLogx0s`m)U'
    '1~5>83c%rUL+)bd2qz2$c&d)e1JvH&qgvpK1h6rFP@+`?*e7vhF&{`DFM+#W0B#k4#skgBgMR_jEC7R;'
    'fM*^!K9~ap<8kWZG}!6~A6|X-{Pg1d=~e&gS^vW6Kf8E%e$n{?FtZIIh^#~~4Zun3FP{U&$>EvT8Oi#K'
    '*?7mD<>Z)u1HDNkle_^zom3s{4@Q^@pbi?!!CRYLa``@C({dnY$?44-L56)Y#ex#U>Jur1QU^mIyvP8n'
    '%l5H?BM4CruwX9Lr?eGPy=fWPts)?GCZl(qjTaLn++QvTh;?1=Oo`}Zp=IW!ZE^(H)8Kj<TrUHzr@{3a'
    '(t8nwlt*2Taf<h~7BF+D%<{opfFX@qA3MXUsn$Ur+M!?z-I7UaJ=BGF0=oQWLGNLGG6|w$c25iU-e5dC'
    'd3QT3OTUYe?OJ%=CI*xFax!JGgIO_`3cWvvIm{*?pT7fMNZas~9lpO9poG?O@4MbojelU^DOf}NY79Qk'
    'g#e3YCZ4Z0_-r`98kXgzfs07trJ%rFAlfpjydF9wBQV9%y<KURMpUB=X_ylVmqviL>~<4a6NN3om5VYM'
    'iP@|+G$-yW4yy|Z_wr1!{n?mTr$sjCU&HVfgibPP#K2(M44c3NJTb@nZv~bnoRxch$2p3g-H5yyTqlxm'
    'K(0sQ8Q6Xm7I`O0mjP9fZuA^P;R6NxYYqC*;Cu9DzD@_oM)K-oVQu<S53*WDSxKh^%<Kl%n-ti@d5)z-'
    'GMiNpHXF;XK&OT8CuqCW#%>iz+OoV{(8L`-e>31>q^0<*66<Ve-=+DAodT{`Zf1F{u;HUrp2;p}XG`KL'
    'x(FH6;1NjK?OA{Cp_qe7_-H)6ot1t)t-bY7V2g)$PspUyt2<JK)MlWyfie}Fb@jyvb2sl+wxtSzeO8X='
    'ALq~76a$UskAOl-^SD;jO!X;Mw*v;G3Z<rc{!-|`Q`uMW2>00}DS<w#Hr%q|&02rLJ6}xk^k6YlYVbm}'
    'oUb<cI*fX6Cp&enjPkl~*Bkoj^Rs#{uC}Y@wCnD7$}sSA<#$v{`T1xLTz`h9aM}0qRPVtQtbZ}BB&hJc'
    '$KcXvDOKs!%*os64VhJc@BI785X|^$6TZ9|PZE+S{f_bvs$xfb80&)OYz!PY7?HB{R1D=(Oy3NcC=X$c'
    'lK|2!+AY-q0O~SJr~%+|Rm2~aOa%xRfP%rTz>5P2;rS|_RdydAO@+`zvvkU8h=may6GXsuB^pX!ze?Qy'
    'Q_vr?`Q?oe^V%>j7uVOw_T$loiXJ^DBQY#*V}Jn&*bvh}YO7T>PgG*W>4Fc&r>fF(H5kg#PM7rc_*T^6'
    '<3taC4bDh)T3l^q4RYL+@<xDE(eYbA)Rqo;+C;OeK8$tREDvdexT;NL<MlrWn|wru4Io^R>9wdpUz?;|'
    'LCS$bP2Vj4R>BQ6C~)~^HNBJ-N0oUueensIz83SUlJu!^$H2y!zWauZDhuL_YjrVTH)@xwc~>hB{`9d*'
    '^D8gKbF8vl{uA(vhO^29`gk;$56Dp660b;{+1Zz7FI@XGDF+M&J%59p>}%OXIS_U10N{{nuW6SLs0OU!'
    '8is0C9;D(e+j6QApgKw~iPTgzMY9N~>MB>7=2t)#^P4k)%^hpJ_>F3vp;U7%u~HX9IUBdODu=hfzPfr|'
    '-nmGXu5Ol5L7J&yH(syhVQfIDY(s29fC+#vS}8&T5=qPk*Q07E$i7)gn5A2GKDvgP-c}AVBni&Xra-Q<'
    'T1se?7@u4<V$~OAE9n6ozq&A759(A1aO7w`egDa#q9n|*+U;ZvO5{SIXIce_ZdU$)@au~4yX-xLx)SDR'
    'qw(9JfT5KRtwylR2u2kyQ!9Qu5?qm+#@e6~zLvv2Qf)A+`JS0%{>lNOm6!STf>wSzbG%W0i?5KC=07LH'
    'p_tc+O^wk)`D!uXqW-wbtgH3rcU2vxbZctpt=!u+R7d9h>PjQC=E{z5#*j~!UGwF7t6m<^pa7`#CfW&='
    'ah7>s8IqOOUUYoAg7-W*g4Z5<wIh|RZL5ONbwWbxFe+Qw8~(cjQ`LW8S8sKk;{qS8;xR&|P)s_Jug8n&'
    '?9o6Bd1Y*DfT?oYmC-gA<8k$XWip3ZJ$pO}T31z;S;E%6rs|Q?dL#Los!!o?gkEzsS9b;B37OxNdbdoK'
    'o!vR#>G}0?3&3&wi^X_OE*H1AWcse$p?<+hUXsL*TS_oxzzDQ+>@1kx+qx`&C{P45IiE;~?P_o<6u-@?'
    '!b8jUhRh$5IVqo*k$e3w7N8yVx!!p6fK01`NN+GE_mRpw7uymMFznG3$m7{;A)YQXi5fscfd)Pwn+_%j'
    'skBtw0`3x9Es1GW5m5jw5jL3%qe?}O!N{qMx%61~c~Y=^@J2isE~ckb)s(&}w525b29rlG#jrZ7<OMUH'
    'G7rh%_UD874WE*?<)Z9cVJQhyA3|QX)ZNKKm^lek8`_53Xbw_E6Xi~z-+|iT&2X1U(&uC`6K6N$lB#<b'
    's6;6Ld@$nUx0QiqByy8?n_zlfs#gZECI_CADY+GMF`d<clojmtg~7UTPtWJ;0@@Uxl_4p!2~QUuBAQ3_'
    'rlan;W8`3j4iVv%0pz9acZ1nLU+bt32n`9e(rRtiT}EL=AUkxxH`&U=Cvr-zF|=AL3whTlN;|XxJFhod'
    '93iJgS{NrQaoYo*F^vrlQf#f(CeLEKwJEp)*<>E1L8KN5Lc`#*BGMq}ZNjsSAyTp081{}@sKt(Ng_{X?'
    'j!<|eVPb$aPu38~b??>$*g_d%5O7|a7zTX)J<!GJVm`)F^@d@udEJJg7kT0ahuGy$n;2%dk8NUvA~9@='
    'mDXjjDY)ANuyObsMs0%;)~>EBD}yd;hX}O5DqPOq0X$!OlqR9|K4A>M4F^(SwzA1Fn7R{=ws!yRD&S&z'
    'fM2R0j7g{|@|o6st-#hBo2~Y1YKWP(di!G~+{mym$#6&sd)>w$Gi_V<4UtZAa})1v(ZzfY1Ay2x1=zLv'
    'bG#S<tKb8YTz%^kPA2nGx8n0-tk+R2@GENzg(BF>n=}V8y;q@8We)E4n5OYDa^9&i=o@CKG02<oMbn^j'
    '@y5o$Gj_BISUCf_F~F^XMH7$<1C1sD=K_zW0B_ozjUg8qf<}O5Ex^VAx0!zC0B_iQl|ko=6{6wNQ<hP0'
    'Wf>JzEUXJ!*+homrS&ZnYsfHEWd|)wPnrRq7$?06O4@s=9n@ReLCv5hCQlDdp1SjGUhpalCwI-gQVou+'
    'P^x+yCJIaCAfde$fq~x_cyFfus*DvW+swR3D`%HalPZGpNT;>%^twa6jD>Y*XG0KON!Xz-tkrEpm4DT2'
    'nVZ+_R1!nkl-{B|ksD>W*SOAk2e2lY8Cf_6QZqEpQ)q8$tS`BNliFPu0z~2i<yzH*bg9B-f-iH8Yaf#5'
    'D$m!3vd%xxCORBm7hW-;);%1~(nGBi-Sy?wKlesx&s7z+Bm=q`C{<Ej6&h%AXkA2}b%Eq4v))PbI%&3W'
    'D7n6&Ee@fSKnw8K6hjM#s#&fvaiqE?Lz{xkU1Y5fY~$8-n(wRt8$S13&k=89jGTCB^K^21r^cp`i_Nh%'
    'M#!3ICgHDfXHsy&<Oszo(&T~Yx;54kYy;uRZD)*miDMA><^>HSz<0|clZSs>EgF-96iPdj0~A|QMh{7g'
    '3@l@(nFV&2LAW_n%*@&7-905u!A>rk@IFZ>w9PRXY5|jw$4l|wzd`w*6qYtH#0>VfKbkOA+HyKwOe%${'
    'D)%321a*s7XdM1ZiJLq{+pP1{0%&C&7=vrnCfMw1mQmVm!2EWCeJD*q&Z_9<Fn4QaBd0N2Rk9K2g}T@X'
    '<YFak=76e5`!+vNGN*PofHu>)m78hRfSM}3UaDBzfv!}l8JH_&+EdE3F4Sx!{PAdpRn9SS;T9n2OG_8y'
    'x3iit;wzXLz<Vg<U^J*${xt_KQ)f$Goo#sAu5h7s1F4&<Y!=~5Cb!BlH6O()m~zEf(RMFz+ol`y1q%qF'
    '4Lg3Iw;@xjzp+7CNOq=F`zGGaDEKV8Yvn}b<yL~$-U_WIB$uu;h6kn!M&&a81u~)-WbHeB`SMgc$*QKH'
    '*je$acFZ@iTA091Mnh;ZYcoz-RIbYK9gc$SGciK0=%Oy$Xf%eiYkLjGh_V}PE>B#^&~bvHzCaW$GbCmP'
    'JpCo;$y7)&#abTNtY|89${o^aQz>nfa#rATWMeF2uTZR*@?f$gQW<7}VVSx^^-7gws_%S7ZdLo(B$=>s'
    'T12jj=Y{y?VxR&h3)=YZcERlG3HhSgwQyjX-x>3kW)VJ`o0>bf&XgS9NxTLH{WgL&Z7}QN7FgyP3{TNi'
    '>6Wsc(^knUQ?9mP-nrYRBx%7e7`2~GVZYd#P7vKwh;Cv~XRxu1o2IC)CuVm+Y-IlyLp0{c7J@f@ESm(#'
    'u)O7T^lUK)$I#HBl<rlY9*orHy<NyK6&`$?IkYha(+oz}fY!2sQt5R%n_(r?x!@QZo;9qkmMEpuIS@Nt'
    's2euT3c#&m6RLLe3_~_ELvgmuEDeP0GV^O@TCMF!d)8HE{p}5s;-n3yeGA46yNw&>1If^h!E@*o{8Z6W'
    '|4m9vP3@C4>=--1+@vDYpz~a1$R^3`o|z+$6tLd6Ub=5}fv-4eqgO)G4y`?ARVr^X6>~EI{sNZWwkFfw'
    '5vWC2<pd@!9&@3(<+Uji206r;ipb};!{misW4I}RZHQ0vC^hUnoJ|F(?>lUE!XR%1uY4<`pp4jfJUJs1'
    '!qnAxv$^OyuwcMD(R{5sH5lgT9rJF3qZw>LpCx-xGudpjcEH-UHfFaS6xj5lEzGr-uD@Akz!v(x!CLJ)'
    'B;1CE$@YrbPgqHlj9M0aQ)N)=QcO#eFC@s!KA20ETec`PLWXLJJ&jWn=douOPq0G41sPq}D0H2#8=L`E'
    'H~5rxcgUWSG*lpZR(fq_mB+FVl5Xj7$!-K+v~y`?`)G!hN`3<xon`Kp5YyW}a&q0g=nekO5TA)i^A>EI'
    '3St-0c~ki?z3m}J8z#i9C2M>&6{=lhjjO|(y!dnsmdbcK)xoNklNQ!y-UbnmU_GGg(gopB_v*HG<J0XN'
    'vKqy+^Mr!4?yY8R$d6FTu20Bh0w}MZJeX4?7lLC+59N$t)2=2b8QEzyBi{8{wd087=4<qbWOIYsV2SAx'
    'OMR&~&p?*P6ET|+)1|c5_tWJ0WER&Axpjrmo<^u4!G1L*BVE4ql3`uZX3TLaVP=d>#Y4dcGqd6IOv^*;'
    'n)VHO2iR>>d2B2O9E191#Wwx4z5zxu-ilDw2Ah)<MR<!&;RxM5H2e)@j;TfTDXyab7M9T;s&$kGooArs'
    'RD0=EO>oeXM$X?1I3~B1ZNj>R9ar@N2eaD&h`V8ftgGiY<N3Hz%2l>o=&H`zY%!eAnrP$f#Oev0wTbB{'
    'Knvmjjs0y$-RBU}T;1=a&ejUArxa^Awwc9ETL+jcIVKWJ^(8WLU87|O-<Y&7vZ!fjU#!GqiUAYiF)1ec'
    '&EO6AFx6{3tvAN}j!XyGx}|1>stDBM(M(M1r#59bTE&;pKbyDLfF#9as}ZboOiD8^=(gb9oVZ)Vks&#>'
    'hMZPf2^3Jb(L(bp(ro5Dl_=vq1nl=2px=ZEh&{jiV?;iHTy_06P=G*TMpXyb;YWp>=64a+NpNs$HdeU7'
    'J`KfwT8R{Qt%tj2APl5P4As-KH(1}a#+9yhK+jj@OzS3~A{So>yqXVo3g|g*UcPOv+eqMMW9A0s&c>8Y'
    '-B(I3;UFI<ZDIm$wqrUbY&8K~Boor)_o+g5pKENJ=okP9>ECFKX!%$#zkU<)T%kmH$M6kP;TxvzZ|A&P'
    'xwJ{f16~}22_|<v8o0-4iT)<_P%km(Z<v%eNHe7CrOj?E?`(N<t}&>peHT~aXaiIW=4fUw+VP0<{n~3^'
    'k}cTmmd~4tNYt=LoWqT=GG3dQGALVxrb%VRX`)mG!cArgV>u~<O>k6d@UVZ42<gugjMO&}3;Ek*EFeb|'
    'wS;wIYn;9zb23#Lpyr*2tigIEzMnU#g1rQ?w0NtRoK9`Z)#|E7X*VJKIiPt|qd#vBh^`e?yF>x@J6PhU'
    'Zo}ZMcy45B>-Du1Ls-#N)9Skgt2Sn{YZSDk2J(1l1MnKZwP0rxg&^ZrFzS{1J?PeQfAl6AyZv9pu}0$q'
    'xt(jCOq=nzYN?bw0CM|XgJ?ifWDo4C>0&TPL2^c>(|72())Q6hlWW5;Tpz<A8|A5f4#1mweYMIg7KHmR'
    '7Zgu|;HSs8*y^ZJS)UD<7*}hSrLbk1Z8`>9hHNtsJ6n#`AE?1h1vm3sQP<Q&f;%13#qHx;a-F2>S2h$k'
    '6#6<ubGcLNkd2CM1-CN9taMb<Q|E!|tfDy*GqB9!a0S>%OUFX{LS>E+9IZdW;q)0oQ~9_y{YIiv-v<~^'
    'ACKM)GzRca=U~!ISZ+eC8!0Pj)v;~HZOYB9gSH_#$H`#W$}1U7-8qKg8q3bzJJUpnCMAN?+s2}9&CXRQ'
    ';o)LR8rKimm{ya7p>#%##M<VJn!1m<sTq@!8}n>2l$g%GWl=oPOIj8P5GG2?rNBq9jy_Mfp`nc5K)%Ts'
    'U5f1%FszWU?8L6i^;f&2nGpgP19qeBlIB6TVt9=hxd5Co=G%nbGHXm>z`i~j94wd9kcc-I(a2W0P&a3k'
    ';qw)Go7IZe6kVZMhu5YFu{l~h7amkcP;G5qCs?Y%dMg_<2@f^nybW-M90PN?s@p*C(K(nVi!tUN)Q#+|'
    'C($S#PA;x}*EEqP3#<_pY(g_e1skASrUH)RCDM12EXG9YM0N>Hr~pHTFn>9?PArF-SL(KbYeWZ|(9G4O'
    'UkBYX9bohn%N}Re(vS=`R?vhD(00s(o*JZ4FCm?+(kay~wZ`zK<4IE(bz>Fl-l76l_lP$Kq`@g~4$c*p'
    'YnV3%Q~kWS&}D5UKDq|jq}$XyI;y(wJXmnpgocMksa2T({`q+NdNv`f)vTiRu}mjEE{)h!9KKCQGM1>g'
    '6tuVz;HTnF^ciji=Ib<$uB~I}l8q<E60eJh$ACYj4226Z2MJTRL;N5)O;&e}wauAyfgRSr9#aI>guj<r'
    'ZwqanizaREX3541Om>kin0ia*&bqg%&EKh}L32#53WRB+T7{(y`Bz1VYHC%frU})rlVzYh7pkR017I7s'
    'V-bwGlH1u?8P)a~zy{f&7@uuLOeZ*mxu&cs?1^54fia41edg$+d9Cd9k{I%rW~~O9shc>tR#zm`8&{0X'
    '#WhNX+NrulcWloRsA=-GL8LT=tnOQB9P~5}dMOTiOB|HFWi=m<hZ?OZatHIFAg^bJoY!T$$_v$3!5|f='
    'J1|oO4LgsptCexU*L&*qUh;Zblx?5ViWJq{#PtA#;}U<bK74lJ^v|9>y}CF(yXs$led_o@=ZnsPXIqiW'
    'Jll?BME%I7abQKBWT9s{0dYNF*nv$WJMjI$vqIuTu?&3aa8D8z2K3;wv(u~duby4}RsZtr^y$;{i~fVZ'
    'x;noE*oOz*Zugm#!@)>&ay#0&UXUrDecqYhh|W}yVMi{8!(MW!s54_^G!oO!bTOKB2BXf|;}d}Na&+)n'
    '=Ri)!x19-@-wX$|qcedz&*4}7*W`n#$o-0zSnh)xGQ;<CpDjRiBO)`yXoATj`=pE%NGGNjGywB(^-S81'
    's!!hmC_P&C--~C@t^j$sro(<;rIz-OPQZd158sHxqmv1lf-N<B;k?q%KRJE;wEyJ%;;VDm-X~8U<I7!7'
    'gsvCcQNSJB^CH*xxJ#wS0_qVO5H6YHOJ>XN28@gIvu76%ar+Q!C+MNi4iD9&?sf3lZkB81;CpN>3L+ul'
    '+}<r2jCx?1U5g%B@WH(203G#gt7rMjBJSc^2=C9u_w&P}qZeH{P|9W2-CWP3$4?(Ve)<(o=DqB`pT2l`'
    'fUOG$^Or!+_to!639H|xi=kNkhIEI&bvtql#DtWzxzG=K)W=VrKfAcfU{JU*bAyn$zyQ+rW$gQIXxWSs'
    '?g!lBwiU(!i>w5LXV1Pnzc>Z3&o7=`E@zGmhA5+qhrUO-XLI<Ex}0#wA)XsJw#|4H3*m({@WcB`I!sh!'
    '<6e48<6h>ja1U|UyPks83nJtGwE#AON6BQ+doAAG5B+pHk8Ri4m`j(%e&~kOW4;$fHVM7hVI*`YcWoI&'
    '@T+Ti+~&5P$LyC2te^m6&wE4kabREhfD{ev+R4C=9)EM*fB5*T^UEwU1K)C78hNnXDE6rgm@5Mw2^M&f'
    '<q1wD13}~Q0wB*%uf9eQn(9Cz*lv_`ZdbX{`h+-TDotXWP*zlZsQ-w<^w18yV?fGciX4S~+!A}U3!na6'
    'oZXN)m~<EbS}QctJzfFnbXUgTWBp_KR|RpT8(9$*Oj3$G8AKif_Ou+qBf?z?QkciKAV4XwSets>VnBLP'
    'Y!N|7_b3DI(D7WDxC;D_7qgFlJ@9M<Gf&zV_bHj<+45q7qP0J}A)vu<WhETMWhMb(48LXa>5JBG1{MKC'
    '2s^eYCm;iv1uOPYe2~a?1mK0ojsQ7L82lV@$Fc(!dmeMS%e~kW-Vzx{oAjKOjH@w0MsD&S2*Y)L`mn*j'
    '@2BIpFDww18DJ<g$8S+;7I2b&?n72_ojv>Z`Lm}mwZFXj_Tqf&6bTi+>ql1X+aVLwbwbAhK^x1+XSPRu'
    '>C=b?JiL!y>DhQO8ILX&BgF6{t!y;mZ7u=D{rUow=>aP^^!?*bWFL2I+d3+kyZ)CA$!ym7Dp6&d=N*Ts'
    'jc|g$o{^b2y1yEa3)#`ep$bO`-XC0#z!n8c(N_gQarNnVG2(|aF_hU?@e5;<12F@1y}((YpldrhJjyR4'
    '(Zk)7RNv|$@=En&HW|X7kxCDb@`Gf)2C|bIhm3e<G@k1Zhsme#S2CRg!oe8n{$cm%RURC!;{<Rfrt@=9'
    '7Q@4#7#$`HIXdpd&QXcyXJWp5r_@Wy!zT=IIX^7cya33q2xn7e762KFYr@{)CaGAm+8zB9Y)`s{fLi?-'
    ';uE*6c#g-NqA}G*=+|-J1jIJxT0NXRSY$qJJX9n~%51G(J)p%~-=rKK^keroNe}5rL!K=t@{rntcVDP~'
    'kM0-KYGx)E;#z#K-#P9~W%sY&=j^r*_h0<={XhBg<;xc@U%q<vryC;Th24u^y|Cb)Kl!8X7S7OodaPUw'
    '7y}H-W6geF==EvlI_%!x1|T!tr{nqK(IH4>1cpW_K>Lsis^gSgD!_SpV7)x({7J{N08AO61=0x(^u99C'
    '`{H{hR1wZupMn(*zoTEGjfTFGAAKO5J|AOE;J$Kg`Xli+E&gza7<>QY6=NSt(0TzQ6%l^s-K*(B6uovb'
    'm;t%x#M~X@gZt7|%4i_LdBh#+zS`-;9B;*s{(9d9lnOljO}AIuPZ;8RBSvJz1e#JK80(G5KLVdC9|ne}'
    '1I`5y&mzqxR{;<`aa}A4#vsG)hXUb{m=c?FFC`|B*1td-rHemxUumAypWsj3S0$u}#;tlsb2-A<aG#H='
    'z(M9iDBU$tvrRZ8k|bq-%!;;?{)@~iJH3wms^kQdAjgT`#zVyrVuV$Z!0$e}5#RH{HR2YiT8)t5`*iDH'
    'Z9~RFg69tlL9ZO%&H3T#_lzg5eqZ|HC54?Hp|XtZT3sa`JAc{%2@U_2gR>Y7L8J-ZPxj}Qe1AAy;(Q0='
    'q4=4mTiE&Hi`<UF@OF9GzCnmf+-=8gZr=4&N{L~|^BXbk;iwzCxoyPENRP;HCJxEy-C?3XGom;M{g6xW'
    'fLtpI2#YMrA}{9Bk3x(SFhWS=SX_d#Ewr?bwyQZ6IMWo~PeV*9K6g7op@s3iMBn9wo{Gv9YPKnP3#4&('
    'NN*V}TX(w>7S|6ct{cz4z-Nz6xX^r=A2EfS55~bf3gqi(aZAPY7%;ESQI0zxh2S@}C@n1$Y;1ApN{L}5'
    'boEHv<ZZ%1Fv+|S({HsTzcS0)Li*zS2_Qyr+`&BDbhk9B@_UpUrsTBKO?#2-#H$yu6QCl}8Ek>`hn)vN'
    'r79o}FE218uBldIbUsdE<=VCE{Q2dxr|^Ur@?&N0{9*w+OF(eV88&?GydlGd=m=oFx4^vOq~zo?WY&F;'
    '@-u5&olNx)-QzCGw(f^6p#D7?*2~3xD94Z)!xKaOU|ebgP+6B+H_!Sge}H8{?9BS(skTRdcRlC#yZy<H'
    'kZAJfcOQ-my}6@i!)=J_g1D|yu}2@Yd01i&I95v2TYS(0nR18Mo&YTH)bDWSk{5Tnb2wwA{1gRk^W*L?'
    'y*s7+wh}<}Vm{p0k#IFH74B{TDw#`G!Pf?o&SEgqdg2IWy&*_{ijcNxoJ}>Q*7Jq>ciT&a=8$@$v`Mom'
    'QcmXM+aX94@%;d!g*&Vhlyl&E%`!fCe=ti767;$80hCGj=}JBpM-F#Td2!%rE72DyGYz`*3D%tu^(4F1'
    '4!Z7ydbnCOh=RincML`h{qDNoy;2;F)kD*$kCA9k0WkE5l*uri9d`)DG`x<&Djo`@t47%QW7(~Q%LW*+'
    'TqoVU5?5^W`=Q2nvEF8Ew+7#pJ+ZCCciRtkO)#2kckc{v-4Q*<$u2D%u$^BNAoEp$dC^Q+H&)acRi^N)'
    'b@VN-38S8N-l|VstL}?Vq3*4vcdO~#BKp{EBj!&Cx_^z)e$tb#-s6teKOIPO1lHnr8-g?M^X5#US370&'
    '1HxVl5I|TXemc7uOgc;*J}aqo3qEg>I5ia*zwb<@;MDzcfi3946b7!#PH?w2z<fvwqjhf4WlZ3a1#H7;'
    'j=^TZtHC?}elh^dq=P{+@n-xQek2nND}#}wX0IB2PZtyPz8C7s&#a>+KNaXVf(0<Zc_f)rH}J|34f7=K'
    'TriO$wWQ98`$;-d*1uF;P?TAfiQFs$LgUf!-S4eW*)2L<?`A#AEvJsV9lI?r{m6W~?JBoyf<h^%iQ3(r'
    '%TNlEUSXMo1`{WcM(xprEwgs^T?ol?(Cz~_nZB6i4WRCa=MTR9>TXLUeO;5>%Y!b;lU~?;c>r|h>bJYa'
    'qVM2lKA+6)-@B)!52$Fh5^(<rmPNj&1Iq`;>G}a!cRR3K@>;0wd6?dGzw=)Gz4M{W>w1R{zP<S7Qm9IH'
    '>o2wA#A2E**5`XS(^X1Qm@4OWG8m1v_^Nmp4|`Fq`&>5*dN2LkEWuoFFrJ;fQ<K?B4Zj#u0F}O(ay%}S'
    'O~o9H1z11Ij~Di<)gM7W^)QvEr;=D#&se*4^h8XPN`dMf9iPWs-20fr%r%&FD!Y}Y6mxdd<DjH&?svd0'
    '!*v|pHTVoRq{pyz<_L@Wz_1ecu*}=(=C1N|i3(2tR9MUlr6(gQ+(0-n<IJ`k=7%DP81)&ImWa4rJO~PY'
    'b<Cin%^>?<9Cp8YeD%%w>CZ0v-<@AvK7RHTU4rPu@lM=acHfq-%=_n0Pak}vPo>VEUR@#_z1~`2zJ319'
    'v(tzD(~GOek5137GSFV_)=XOV!7@MG@4P&Cua^1&<is6VPtGHeL<XaU=z)9yD`-5;y;l?_Ukr!K?i#bX'
    'm;i4rW<q6Xkg4V`Nd`l#hXhXeez*+hQOIWa)$5GNt+?O01aYA9__gUOcyGLzcPNN7c9R^Nz00s;;RyJx'
    'F`v$E#Bg}OL&@w0o=1?onPVpAot{{XJCnggAZ|;&h4unkX}vd{l&LyDxyQwudn3R>DG<1<&dZnGKRR4O'
    'c!O*{9v#7_fR2|3nsXGn-3jmI!4eGo(CJ~9T|7PP^+1--RX?OJ9QbWGzV3}D^Vt{OUN3j=qIcW*`uy}E'
    '=)S_yk`<#-+{L{(`NeoJQVveeEMDzlV)UY|d8aMAlasVpmyVB)U9U%m!(YSv2U8G=`c4G=IvVS{2eV&;'
    '-!T03+iNlZ^~;y~|Fb`tgT2r_+RXce`Strq#Qi>=;dlEwNvhw?u+=j46aS?6<LI;J7thow241T<|I4fX'
    '<EPKRz0x;dlzlT?(67*|QTa7k<|1?ZD0hWA?RKzU52c{SCTgF;$99*n(Dkd6K&!5402cBS7&TvhLto#-'
    'nV*4sI0j@Uy^qwj@wM6-tA|(1Ea(}NYZZWVKO2vyV4#!yBGgkGQ@p%U5r*Ycf3bi~7|3@g-y=Qa4aIxO'
    'HN}$&{T_c*kFD;Grnj@{P~<O+7Twy+F8pWW9SA)BP+-n3Tfcw5>wfh^aAv1h<ht;(XJK9Kv~v$G79I3V'
    'J(J?s3vYnI<ohg{eV>DW&F1=6((M@Yw0L5@BzM(HLwc<d(dP*!s=lAGo9=#fnP-nF5!3#hT<7naHoFgA'
    'wT^$O{#rz9WDGo1NA=D&UAyX~CnVEHZ720C=ybrZMdf#~#I{H;`xZ<(y-t~Bj_1og-A13;w^rf-qyS&A'
    'd5QPdnW?DN<F-Br1*P8`T*KdNB(N@|zP`G8UiPJDZ%2yFvHbY<hGhDlDDqJ+<)dE0hrJ~q>Pw?Vk7ije'
    '`_!^iqT;R|a92-rS8=06{Zc}r`baLJ^!3ZW$z5J$`4zLq@`_eMUC9euWYz`;?Y#e0>Y@B4vHbJ8%slJs'
    'plcqSzUc^lmnx>5vYVWW*-dJw-~EE-u^o?VxtY9^UbvsV8_jP7P7L1zrCu6B>1h_cRc@|3?`m&8o@Uvt'
    ';~A`|(+lwLwDGjMnEbw$Ai3W;2t&tnEa3`fdw%GFe`^PvI5B0u5DvAYP}mk_cooqWwigRO_Cn9LLf3^q'
    'Sfr_r#wobA&8^raK`b37wk<D`v9u!FwuH1j$7ei>Jn-Y~FtQ1yPQ)xXWH$9J;sl{vMYO?ifosQ(>roPh'
    '%yWqpEb^lub|{Obv@93z<AtF|{YVf$@~t2yA$2*6EhYlrV`WT87{&`@%O;UWC5xmajtpYXNMJ{VdRzp8'
    'hQ#)588YTr5@Zzj7!6}sEoGcWu~$>4z{u3|d|SALI-%z{(hnl)+RU~+=`f2)=31`nGsm-SpSgjw?U33s'
    'fZdOs(Dq}ix`2W~g%>-LFwO<HL>L6NA38RVEer3++fL|4lz6cve9I+-1~v%=_q~_|)FB>?NOK(wlZYK+'
    '+XQIVV=nVNN6L`OFyMhhgeM}`wS~n)?&GC=?)yBpV-XY2b}c)yIP(lzjJOZB0KT#XVS&Q}5`<P91u&Gf'
    'r2tI39FW995|PLeO!!=K4*MPuVMW4onO#y_!AR0|xMf?85Yz|$pe%?3YP+!;#l#l@@T+G9jw?ey4&%_3'
    '5{C1FD8K*~OvkD&zF|<`4_rq8=Q^$*I1%-IFN|P6fh&DjjT^)i2+sF74Cn!W3+B3b(-l}E;GyuFs(r*T'
    '2&g!Q0cdD>KF8ajB4#3_%o4Dz6eO2qj_b03#tgRDb0f(;+vh%uV;Y4ul>&_H0K|w#p^TXq_?$Z;U_w&n'
    '+M(-#j0B-&yCe!go{(4su}`d60-d`A5Mu>)JsSfCwz=zA1gI!*fq7%%I8J2y#1CNOZOTx(1fdU-#PYd-'
    'sS(G5-LOdPJ8|f{u>nmAvxqpXMF4g!kAzG(KuQh;%@O+nkuFe!>qS($G6FUuAc0&<3d^I^3I+TxnMEBd'
    'AI7#kPr$e!Dmf1WKy?f_k3$Lc%qVOF@V7-d&;=7PUKm6c%qfOVB4H#6C#C&+94oW}-v#ao?U>q}yCIDj'
    'o@m)Nvq-?C00IaCA*Jm~Vg(#@MMQ(Z^#~ASBpW-9iqssz9qDk8*EWY0#<2$~67+@*f)>ayjAIb$9tk2w'
    '1SNjVERZ9iZ$&Hue3Xrhz))`B2dD`oCoFV`A4+EV0F+1;+Mv5AXVeazh=&Z&Y1uIleaI~dBG;3YiYA@|'
    'vNHim9lMkhkKko+D~MqGg23@(ShNo-q_Gu9;9LfJltmu=C5$7_;w~t1msK^Ck&rDKNE*Wcwvc`dDnAGa'
    '0ZEFA3*;vSu?)&11WqQdfISA16F!3_gY5wvRWcL<Bazq%z<_Z`9O2z{304%PKraq;EEg~i)1a_G=@S-H'
    '3QF6-6V%uTsR5krlClvb9EyYJ2d<Z}X%?t928x(dk43P#1ctF3n|Q)uK&r6=oE*YDTw6vG3=u+Hr%AX%'
    'nUt;#yB5XV@*@{>AOk`}kUyZ-fOC8SQh^0gL>y2<Ad|t~A)d=YZBWqIl#~rz;YyM5Z3fa7)GLa+5Qstm'
    'L+}V}8sC>u2x=a*0%f2S!oUI>j0Kiw0Y%5sx9)OlaEKtXx#NHxM}b1z5G>9JtPCJMNdnikfDhu3dZ7i9'
    'NLXO?Fq=p)SY;Rj9VNQ8eiQ~xD-h>Qaas_7;VZZYy9uP?I@AZwmyYe?2^35*0D%i~G4k<Q8<@lAVHnnP'
    '%5ftD3jqrWTPQslx|q32eA{y+GAisL2P%~UHXsIe0MpqD+|b4f4I&aEXc#s`*#~x<1o9;=2lvDQi3esA'
    'C>bzkVLxI!0CNKcL1clU2SjYSo@7Ky&!g}&@hf=cD1X34iGXn82uuZsagRF@P#DmaXMxy_ES!qvaEFA_'
    '@j%u30SGEzfXxncAxX7}Fq%+cC&#gHd1wd1jX`2N6f~s^>JuObsM)~V;cn#Hu+1Lqz2|}7#avYOws5L?'
    '(aQS)@&W(KvC%aF;pW1x9`2><dLiMk;h@jJTn|CR01E-Lf-OM<)G}b@xJzxaJzS3lDL9b8W*|Vh50)%f'
    'Y|2UOqMRkd4nVtr==FSRfxm;+j1T_>A;<;a1^cvKhzq?gurM6ZA0DVCmxBcc?to>3kqw@Z1twwOf^xRu'
    'Pr$sevIwjs9~@2_SeG$y2CF*nC?I?Z9;yed7g`cbPS5f|+_@mgY{I||0w<XP2@#7$oTC>4RP2Bs4d}2K'
    'kZGgHC5+F&1&%#1ynyRm-?ak3D_Dg9U!bN0_bPNa$acUt*q=6IJfsvoq?kwo1Yae7h6X5Td)z#*fWY7c'
    '2Ib&o`W$?8@N2*Vv4A&13O)=0H<tJw7{XK_#R0MdX^Hx$0jREJAiOAI6kuCC0LKa(XPW@4FekDI49R2W'
    'P_(##kpi#~?GWTK_gtTZmMdz-bChKQ1~m74&$WmhgGCTB#46)X5ZgeyaR|Cyf(znXAq<6XzYP+EfQ0~5'
    'm{=xvpX=aAl!I9#K*-xbDB#0;F(_rw)-tkS>99oK1`*FtA=t5xkAr#;K6paHra{=`ya0(wfaQt?3TQl6'
    'SR$exur5dfSBgNOMF}!dS{8_)&=Vkur3bDx>_cFI4NU!N(JU3L2<-^05F2D31#Eea2a+Q6fKx1FCkMnK'
    'urCMp0<RtPi|5%9C;=z%1-RFw@-YQk_28v>K&Ebpo`fyHSOV9G`aq~*1m<(-gX`i)flVS8BTb-KKs3jK'
    'gMK4mf|omxL|y?=7Q66@9as@Z^#L3YqFXp%X2EXBkoq901aZMk0d)I-2N1&GK-geJNbBGO9-3aApIx0l'
    '>_30-m;H-pKUcv%Fh%g{fWDKd1TK@V9Z25>6N~zw!YHhd+5wj#id!%M(OChM0q+D7M6DFyAIG2uFlOLu'
    'O#<RnOfx`@SXVcT(d!vNdy&o>A-|mK|8+zA6dV;FjVcQikO$7|`FZHaN$z!VRmbJq!RhHE?<|PUy|V`('
    '0?++(pe4^cEBCf{>W5$?IZ^m1I6Z&l+h?HmT&v{RVQilV4<1?0*+bWL9#~EspSoVznTL`4=*$O<1?M0@'
    ';_%T!KR$~e`sLn^&SBm*_}CAe_~C<xp?eygf^YAtxATQD^`<t(c_WlJ!uaZC=hS-?o`YTT2%N(B%nKi#'
    '1HL1-)XOz?tI=ka+^Y|{&D!J;T^j*2NOXCvoXP~(NZTXb&+jCfq+G?-R0sv`&#tHA#pEY<zWL#<2exB&'
    'S;=hYyaqF(CIr&$5eVuFA;nZ+eU%bx8j{)kXQT1k5x#l#Zlaf_SIU-+q7|gwOwkz4wXu8`k`H#1{!Sb>'
    'KyeKW?*_C)aBX++hr_=2=u!C4df-3wA6VYG`{?xaJPsfFr<Jk)U@;hS#AJ!JNWD|))vep#bY=B;cfWLX'
    'r-;l<<5DLvDLg;FA+u6agyPeu>UiM^nY~6>4p?Dc<OW_?;(gqyS$A10^$vAl$LD9U{|JxUz{qn?A3Qq6'
    '*k(zS1zhy=2z)C4!GlM^836LV^Dr)J@SNKAIS{h*@Im}A44v}_52Hshc+4fthPqg8h~x@5&R7}S__d6>'
    'uCYIjwx{Ioe0a6)3ao09H@5wAnVG8K`J->1J-bk~NU?-81?L8R|HA_}wj2_86kKg0-OvrdJp=28QkMqQ'
    'CJqL9A_vdb9h<>Z(qULgTSyyRCo1{D@saWgv~z6;WFD~xw#}F$9E%Cpi8!MGf=SA#hiB{H*4eQIc5lQ&'
    'n|sn@A-It?1}P}Pcm@p))D$rmVsgo;<K4=dI|o9=Lnwxy0vDD@Tni66U5hbr)?@I@Vo!p<8B1>4R^(Z*'
    'R0sTEJf(Fk-%S>+10iaTo)cOjUY2H#l*D2PORyk_2|xybt|y5T1YCqxprVw*;U4$##K;PS2afsChtEF4'
    'M1Ab2E~c~OVj&h}QYF-mJ3~Un@aVo;OLE2WFex8|Rh!ZRVR^sw)p6(G+tF)O9++Z18H%|`?_YKXqsd|p'
    'LJLdrDBudVzHgzbEPa+<#6Y(c)32vO&5f%9b&0e3Dwz|0sj;yP68t5Z$-%2-VWrPIS{*GPNVL=Hi6x+P'
    'fod|z{V4@bt<#28J;7s?(e=Hlm<YUB+EMt@YwFA<WVErc?BX<B)gOTg4f!~k9o_;cLb7^gh30%v0r7m6'
    ';&+1AXs~`Wmd+aE{ZnLM!8c~44=(g%K7+46?3}AbOb8%(ic$E9n9kq9a}zR{!kg~^yW^3n*0kJBRp?@N'
    '0~o-QUwzRvGlP@QF3z8yKECKbzc?@I(Lh6o$G{1W$1x)4JE2QFAWx53cIb1@VV39Hz-TgxSpbC1EIh`y'
    'I1fn}f&j?EzxY-)X~;-h@ZACrPh;S9&RjRNyii2o)#9;ihzEnxkzQbXFd&Z!u?27>jLlql-jg}#so>3k'
    'k7GP2=bpzM7fZS^ZaGv~peC6NDD!wIE$+v$=Y}?kq~%Ko?=3_@MEzK>9Qa3%pMG_I@%-ZPQ>-h00M4uJ'
    'N0wv7BzAmaqk!;PXbH!OLHIEXBRDP$$U_RyJP(wGL_OjV-*ZX4gnjw!+l#aF{^O^3Y3W?+iEQK2oAKiM'
    'X8uq})%tz&pt&G`1!9IWuF^vS9yw0HDGDuAVu0%)iWs3RbR5Tv3Fm=FY}?~r1On0tT*~88{XjaKCQfDw'
    '0&pXIFQk|n6oQxo%u363Bz5upnFt!#QHWg)Fvvxy&mD^j+je3Z17TS;rcf9hTNO_R=Eo9j-+ue}A=Ygh'
    'j2M}Y)Y-%R&Oz0|if4eZu?(I%!M)!}b`bX~xg7cBv8ka3>L%X&U2YV0i1Rr4%a_}&*otFiafm0YdUcOS'
    'bC8Kxtj-wz9+EkEIjX+(g|_yVoi~J)Joqdv;V^9svLq`rpbLnz71S*0)cCYpq4w>>-o^k4`y_P#p#kBS'
    'l6k6L;-$KVWK0mP353Dz1oLM=3hQxReT@8^!P7@cRz;ftPVZW-^|?w<JR8F|)fhb6Zn4m;u)%xs0`P+H'
    'xDXsFaCgAd0{;t)HEBl?r2@<e3KoY4f9GMy!5QL`gF{1!Poj#1uwheRGQH=@kVg^0Q$Mh{Xy7<pGH^OE'
    '{}?kQB8x<XV-`3IZ1CefJK|yFpw&}#{6d4`r%%XWbczXZSnGofJGyg+flWLp-j`J$S|c*_;28zy;SJtN'
    'd`5A&T?Y$Q32-)_E&yV-=_(Mp647#iLz*0HFJ|4oY`VP}bS130re@emX1B&Hd*PLqSY@A_(x%pI-vlnU'
    'e_OI#TQghRwOQM>EZVSE_p41+n*1ka`bn97Ql>v7t9;U>pLFRbUAk45YUjMtb*lmg-NXf~rh$JOFFW|m'
    'i}2jl3S+!65P4S2h(%*eW)EUt#18QS$BRSGB6Y44ay&+XA7q_56guka*nL$O$xOJb(>*LvJ*nFy;+2v3'
    'tt=r~LAm3lV^zb^NPNoB?8`>5jLp1Tre0RJN$fUf5#u4hAzED)FwUI!E=vt8n*|*k8xEUFCFKCkkPKqK'
    '+kK?!`hieXZLpS7u+#gAv6<`SfK>*BPTlCp;dng#yfebIh7K_{8Wt}d0Yto`cmfMFi!s~<5EjqL{N_;Y'
    'h*|Ih*-0`U6!gwLV`%yM{F~?J7X|Igjyiwvh3Qdrl7Km4UDn2(lEF-LzQdf2b1b@fcyN~F(<l<|8X6Aq'
    '10;kZ>00oEBU92&Z!!oB-DJ`59(T9yaZ-7c9=v=x`a@G#I(URiO=!&L(qlBk8<VqIUfctm3GVq?Zk%);'
    'O~=0yqfW9_rcg-e_ziYrn-k0=Jb8)EWm=iE+X|y=YB0)$k1n45N9RxNpuc~1Om?LWZhT8-Nk*6698G4!'
    'cgERsStg*r<Wy6L(*X1AsMF4pJFNGfKln>y3@YA?hYNN8xASZ|xK?2eF$8@(>S3C4JG?WPt#$~-PY-Ob'
    '9{!Lplc~k6$_2N<l<PFm0)O^_HJ?1b#8TQn9HW}rjd4m}$oaP2xe-IaVV+-2EvhBHPclW9cdXM|-Sd?>'
    'W{Lprb<V!|_Cf#a$Cp>nF8->>C^Jjgv&96P4;U0=%Vwwt60n6;)+lx;?I$BGQ*(`L&18U+YcW5}+B=`D'
    '*p1;59!xjCC2LmoC?>aJ)d&}p)lF@M;**QhpC_Af0tV+T@P}bPxLwx^u~Xo4rRZvbz_t*XCIDmf1si{h'
    'Hu)-ikh#>L7HyW&l3hZ`svLbn*I29HSnxo@e1T)U`kmM$wKplMsP3QC+77kGL)|KsZq|9t)Cz$d&c3}+'
    'HEl1?PBWJ+_NpRG5k?v(`*_tta<}8++0QTA)eEf~P5PSZ!K;(Wcyg$*W@;~<j<HSQ4<X6Yt8Zo{nL<@3'
    'xu@5vs##tJoQ~fno6^2zuwoa(F2IDEjAN83dT7`?Q%#Td#)&Ur6^5M`@%>zk)Y*zTPv!i(XWx8#g%JcT'
    '3@?*;o8)j1fCYD3QKWQ@IrIr;HU<GDVl0Z7xi$NuHx#48%&^Pbw6Bbfr$p}h0QZfNRQGPdYt)&<xa4v@'
    'ZG~Qz0n3CD4}qG^ouH=D8-TVNZQ){QOi-1iTC-$T#O|$d``SJ3ww#f^zT&QK&YL~&RCXxVxKJ0cpZ$EV'
    '4ncaL-ZghP!Gvn|i_DG+H+zA;EeAn$7FOo`x6hwHySP%}yvueBc{Ls`Y85`%n>n1+OlZfkhs|o$7Dkbl'
    'i;c7rpMIg)>EitKVR|rv#PF(PnqjjeXpU{`AZaOjQj4<<`Ezl;R$JoZls{==(6$mD=B*A@0VLfSb0pC4'
    'R&FLo(OkaTe$&+qXRDP+Rx_D%a&T9!S{geuG@R*FwRSVrT8;GXB~Pu}JeT{vxdhldBfbXxxYjb;+DvTQ'
    'Z(iGe(%SZ!)wYMEwzhNH+D>WPYew7t653kMXWMH!+kUgz_L|IQHkWOWscd`8WZPFF+aB}Sy6tfL-m=*C'
    'n8emf4%^;S*!Gvf_IqsKww?3VdTvAO8E>s8yzMRDZLgVBd(3v*PqNz{a^3d3L3_${Yc>4wBgk{xLz>&('
    'vfSEBa@&(0Xfwsle1_W(kl@y0e%oHt+xC>*w!h@I{p7Y8Pi@<4W}ETEwms*yZKSoen~t`ZY_xqOqwP5t'
    't>sj-{br)Im55d%56y7&q`fpW!&zwiPC{!v2W<~2XnV>)YdryNfB7GKOF!FZ_SwFY&-R*owvW`a_A}4+'
    'nt0ZF-q}9W&RWkp+oRCgU(Q*ZDQ5=_`&(=@xRB~lO&uB;Ouo!HoypPR)%m3sx(4(7S2<4x?`o~jcip!&'
    'Uc5(*lr*k7GM7@AZ11fpVW1n|<~!P-sK_NFb8(GlkJB-^?N7z^U^ds$OJjYSZnX+hE!uLKjoNNEDqYhA'
    'N~271uyyXOF-R-?aR+;tb#2;^PWur~2U#LIHl7@{E;4eJZ!>2KX>!2qMhs<tHU~yc69u-Gza@+j;(9id'
    'PGq?xh`f;5u@FJ%^N`Y*TLFz+o4c09Y~lwzmNpii6`V^N_@b`-+NgmG!w0TqhjvJLKrL=d83bP7Flt$W'
    'h%7tuT~0_$qEJeX^>2ePW)T-Oh+~h++7sE?0?&~6*H+1lO$U?t7l#+mo?YEbwr{!^*>2PqsxoRHnM+kl'
    '-8={~mL#7y#7!>nAX%XPwrmBO7_TXhU}x23chcibyVcc)c4Ng@pdAgb_D8gv%jFp~0Df>QAZH3JMvSl<'
    '!B;3XYznl-6e&+^UBRJ#;OL`Si5c$x(3rim;`$HsNo%V5cmMq9L&IWZ$1n!*{9}e@u+p|R&(hdDh6#~D'
    '@|lgC%!$G3FH6?wcDp|lVxsc@b!X_L%e6@bK{%Np;mk6jjt(6!Mx0FFsgxg+I$(LZiH1JLJqEYrS{SXA'
    'y~N&p`tE)^;wlNGv_@grC1R7n%&$d!&%|WjIh_Gzp-$9$Pi96}CJ<;_8=*pUCLw3SePAgZs>vT6nKxM!'
    ';FXi4ESP(F3nuZFwzLeHirX<bPIq?>p|%jNumxe@r3B!PSaF0djI^b2Lfhqm?X!?XByt23J_oNQioJjc'
    'D-xc|Yy+xkmqTU6)MtKZJF(|EoCMfuT{~42oG9ivQd&HSJv;LJ*r8Ei`QYd|f?6T0$`*#Fx6{os?TKuS'
    '%HUm+leg0WY_PV(laF%O&r;K7Wxub5#8<Y=K4!h5#0RIB=lyMSIWprkm35`|vSkOR#lw%(&)Mz$v_H^('
    '{Hr^3&VDGWKn860%?hN$k4!vNk`AB~KYVs^{`~auMSqzLyvjxGd;w~%e4nF2rO25>85c}OUce*A2{^T4'
    '9tT{8OkhK4Mkos%$MIsqdEgP-_P7^?j_m|4<#BZhwxRfhA6dfpLdt!ghs5I25z=xUN!>VzV<Ko^M`38$'
    'j0KiQsLvgXg2r=V8QY<6)tJIg<<@$O$j<({M0WPrD6&(kSEQkVnzo!Q)R8STJ?!kG?_p<K>q9f3TWX-#'
    'X|ac5r|mY1owhqEcG_u7+}X@BD3p1x1?<D+d^#9io2y2X7YJZ2f$;`wdZEX8^)d2u22UR)Sru(U;)<7S'
    'LRe^4*ij@RI|NT!(#W<$=5rPVvE|s{$VSX_d}jGp90$}ALFj~pxQ<UPOOQZNaB(XV!e)ogfD_M^A&(*='
    '971g0rGevc$%O6m7%$&)Fgw86=avNXC$Ob&!?+x#j8;$8@wXZjKh-^f1y4ExzadkdcVw_Zckw2zdK;T-'
    '1HHbQ$#n1r94@u0Td-S)W)}ntd4f>QEdWVAEiSMh<ey|)HXGcDOH3EYZNN+n)wQ0-56!Gh3j~8r#L+7`'
    '+&A%?X}10Y(#(;OA>W(r1rM|)PgYwADt7hD=SC*1Mp)JX`C`enpKC#5CgbQ}HEXpR@%{Yd)~v+Aul|ZP'
    'Vcv>!50#5fhAPZ{-zbfqu$%FKiP?!9OlR}Mw>M%6BN!$CL&2Y{sDCaLKRf~KOaU{q6IGf84c@~)vQFM0'
    'qRjBZ7b|Ky84tPIf)hC;^Cx7|dB4|XnOV>WvwQpD=*yFVq1&MfsKNPV6<)fDSHQNZ5pJ5!uNP#>wJA>C'
    'b_xi`jDA^qc!uO!Ir_sq4<o~g;Y<MMB*($s|NC$LdADPjC==K)<r5UsoiD#MXyhD%3ozD|D%36<cL=yd'
    '-(Ee6PEZg1I9UN%fQ~u%pR@6;=zKR2Z%tGGQ}SkTt*j7GTI_WjO61XadfNtEWpGN<M#5m0l*Twr1;J5U'
    'lQ*SdzabQ?502I)&YS7)U=VarZXUi7QwlqLYt{xq&_{|<FO}&76m)nZMufsljyfNX+e4Z1@^H!b4XJX4'
    'rS2qWvMU4YB*~%cno$9BM9x!k3$|K!SJ<U%$YwbDag*(Kw9nXhBFrP*1h_jk?nDCf9iA{UQI1`E8(>KA'
    'ZFm%e+4=2c{;qY-5;)37%2z*bwgPo~PT0-i`qqLP>*yalgHgNE`N3j7ACC;tP|mZ~3jp7x^I@q2+Fc8N'
    'echUE)D{tZr)GRehJ)+Ttuh8qhAKJYT3a)<Phs*$Fzv^__Y(TvU*x-$z;`Qg@BN3p+lnBU2q6D(h%=#*'
    '%!GdT7Wv&v;J4MduQ@-zT{qw0rK6OpSM;nj@#T#Wz^~fEFv30SW(zQ95{EMjei_{}ifARm(g?zR!*pB_'
    'nmF#vv25wjgpr(@gF;hXjnFlZC*|d}I`h<zRL(}LBPH&PaU7A!WcUu_92qiDpB)akk=6W>mDPT$kk^Of'
    '4jYcKHs*WN(ip*Jf@@~N6b41I87TMe-RoT5kg4EFwb9;qG<?_j_VGzaQ;xcC_D1<*MiD&gyvB=kGch4k'
    'v|s1%CNPINnO=+e%uroxP~o>^G#{|pi4kP|^a&Y^PMIzcq|NTxe7Z2w1!$M%x^G(9q7`mZ8@||LOeWD9'
    '{r#0$Ct|5?Grr27Up{;KrO{zBTJphoY}OB2>BKa@aiwd_Wjr3N)QY+Ez~vee$$zLpA7Sgg@5TeZ6w8N3'
    'Jck6TIVXB|(vrc1ql~w>cYZTMJ=^*0*suwS{AJiQ*~MW7#z}#$bJ%gp7C#j;Mkc654UD#x$5x{psy`YS'
    '3*jGi+Hlx4i7sQLGlQ;rLaFGgCqI6!2VK&s8J~R#&OCZjf`y5uKbk{OO8Wpj{V_pMO2B6DlR`^?D_#J|'
    '>U;8;qFh4}6a-~-C-#vgchFvLoZ-~CA0RVMCC0Up54YEJxPuQychg`poZ-OWep2DKXTmKL;8w|NCTMVf'
    '^kyjit-b8GUCD17iE9RiYc2QfqYH_*lK9qA-dj=H+sgE6X9)b-mRM%u$jW?f+Fn!B_K}&kr^K}V=Fc1$'
    'jQ4JQXb9!sj2RgYekHgT!C-M8rgr_2X^fjVk=T1q+P0LmHnPaJZb|A59es>U(AqAf>0g<wFJn%Xp~SJf'
    '^TslMq7j3$t+cVdWsU72Y3$CNvDy_0w$&F~|N78weqD>;TLi6n;*c<1P~^R-%wJtaWXWc&oiJw;IJX=%'
    '|IXYNz{auD+fTOz+7VElgA+cODJ%Xk8%Q*BpKdf59-R<|tsw?<FdWR^>1r}^Af~&wyCuYZ=p<1G<3tN`'
    'emckM9&<7jKt3%<uMa=YyT~V_rPqIjrvQiBnK{XN`Uvl!v_Ow1SWKUisVQpI&>qjl?V+mNcWWrD06Wac'
    'h>77)?eQtoDYj;2ooM2&R>jFcT~p9^Wk})w3||2M(cO3bVD45zs|Mh~{-L)AxyZOg!_dsZ=*qU#2IcA_'
    'b4K3}9fvb$^8N0_;S4#X?U{Q&w6)i!v9||X@1R}jWP)@G4ZVUOVww!{5yo}RQ=(BbZ=01@XrUQ7Q7Sgj'
    'jytJ(Q+5@qo*!Qd!tZ1Xd?u?~s;gdXNM<vGr~jAO9-`oeoe}QS*Flk?lMA8d0=Y?Ud-fjS{Z6WYa74pF'
    '<K6YHb)jk_Cf}}F*Cvbqwp;nPM2+jDNUzzUhJwt5Y4jupK<4`CH#m&($?FRy_uJ!cZH8T`VT{lIBfhhd'
    'E@2P%Ha-}=;gDRaZ}mnzyHOp#R(B7KLZ`zqdwsw2V4!yT&oV1{fPeXkxoZ{A7j!t7-3XrM1cFO6KT>H@'
    '28NjA6j4?!8NRBqWy_Dv98s@r^>MmCCazFy+u~Mo`O|Cg>U)~loi5MRiFg7o0k2R6L#ppT@>JNps+uob'
    'NwQTtt5R|nQ<11>rI*cI>-vK)I-|kxIHQ>H-oy0Wm;1rlAxE3c$OdUdDR{?OX}<h1;c_!2u@4lilebec'
    'nTRA!e!!2~h*a(^2YPc!rfw2w%F?3afyxfg=Sc$zwv#12H){l%O<N{!$Y6+0oW9r!=twwFGo``N<YL4+'
    '<B1p@9<?H*vStCsU6&%oNTdvLa=h|;%-mVpAy>1v81{GtAtS(AxQbwwz49C0IZ-y7;oexu7U_oUk5{md'
    'P4+ZO>0msb!oCpIAx%R!9EaE(Ck1a_XRIO-X7%cmh2HUt1pYF}kz5urFj^AXP~VQ1_FEzYj3dgVGr!xH'
    'PeuYBF>maEV4o&j*ZunRvVV2@Rrkp7&GVM6!Q_^L8tgEY_$KZN15UDX^~ZRFNh#-5#iqXL8gtnaa=o7<'
    'rbcVp0B=ZkvRxJ6*FXMab2Pt1R8D6vM^l2si28&{FAX$Y!D>M(Rb=Rld5fZhQH^fXas`QoGdlYM4QgoL'
    'GnAwiW^40a4$v0jQ^jm_1%;~F5bl2%%QY)Lv>9%AL)!BHPZo0-ors}2z@DA|azTbG(Uf(9A3s!&ni5pM'
    '10jM!G^tp@k5y%_?mnbZ<Q5fo8(w>1l}JNgdvXmdv#-U~Hq2BeOl%Ikwbe=p4v{j#%l7+;jVj8*8~qw*'
    'W)hCZIZJruTdgtPk3RHZ<W^Hjaff?uD$Ks7(cWiw1L#VTmsw1$WrzP*<*1%!*6mpneMTHXd8e21-t+-!'
    'Ckf-4Mi{WwV2bBI?>j}qnH`Mk^USUL^QEckf~$km4Dg>AR(v{8spQ`KOck4SX~)J2eHAr_+C1|xk%0Gk'
    '3UFB`y_J0VnZ_CL(H~i+L;TB`zt5B=%U^3b`d!a^G+xCvZ&{p=z;H2M#P%cagrRGY7R<e!wi4TtP(NkP'
    'DBwS6=1f1=#==Np(j{pfX8q;+i4HQy9=CdXcceU+OL#c?{VV~NwGoUr9htPz9S6TQ?(Ag-O_BjjXu{)t'
    '-JrV}gIVzD0-dP{=IYYiA7m?fq-P#?-+IgIGeuG@TzWg1sm?KjxwtjmCMET4mX;>ER7*Y|j9SzENi!U?'
    'Rt76<Q<brz&2J4xtjOpZY<1aY#s_Xo|G3jPv?Un|Sh~`!Am<@47$|;I*W}ur_m9*sYOTvh0Y|p(AAQ8W'
    '#iyo+mGJ)2^*r3RkmDZ?ZJ#<Gw%_saQ>Vk`#Qdq#;ho0N??9)+HE-vm>UFp__g1?du8sAn-(hK5{wVq#'
    '8maBtTD^z6dn%hL9@kFEhrQN(C|mTw#7Meu#O|sOCdOIa*l4xvLxs8z1`5@+UL58BXYXCx+eVT@;qUqt'
    'jFRV2+@WRMFPeBavLx^LtjG3|<jE!;g--+Bu$iGqhNQ+;{QAGY)i<C4G%h4TS)OGw&zd5E?&|95>bloX'
    '&&nUTI!gCr7mKZQK11CR+ySb-|2i(6kDg}_-^p#d%koM4%XEL4{(&yjeWkJeUAn(ZzsX&C^Y!b&<;C06'
    'mzSfrmlva}H}5XbE=HGc{{0Hb>`VW2K7T4!e*JNF_u=E}oFuHN=xn;YU_Qs=<)?A70zUD2HYLDq)OWP;'
    '0qG0!J{~PUBFptCt1*Ls1g0NYB#8pk^kWyto);RH8CzBmJC++8t`UY_WDw7{e1vSvjSPbzk3^0ctjX>;'
    'k5lK54CHu59D6PyPK3NLB9?21M(7v`02f6BVI1MWa^QFD``B=8oZ!d`BIKgA=l^&&{cQ;ozb|%i*}WI6'
    'S(WMTrg{)Z*ls*wyK#jzBfoQJSgRKDT};zq8~UAj@S5@8jXd}bX{MXTH62U(yY>Y>j59EAfu?;sKd-v;'
    '3O;N{@3N<C2fe+!?=|!A-M#Y}w>#<c{jiO`I|@A7NvrQpo1f7Cd6;J3HQl~T{^HL1%yn0E>wz18@38ZC'
    'ZR_vugdC-P_|AHNcYYLh7ACUe_TRhe|E+BR-m#FNOKtqJyOw}mj9b;7d<VV7AGW#px9?=xVSDjER42>b'
    'qFqMte1AO$chF<JvdQ>PG>R@eme*~u2%P#Z&(-5TR<iMVacgOsNvG}0Tl6pQwrz56cMZ%Ru7mkQv@mb('
    'Vct=P$%o4T*{SJ!p91n2%-*}s0jV({e>=qOvp{yA1=6|Qcb^Ti&jzW!)Bgb3Ai56l-$yQpR*&3CCWua*'
    '+2?_@;KtuW9?15iJbn7Kcl8l12nMcxw}{D;*>rN>d-w9V$0?_WrnvVz)5khR@Ur(CA#=FJ=V(FY*VX+T'
    'VBqC1mu%8buJBtlU5(@A@pqFEue-TAPl^A|dni6o|3nt@m)(-IW`Cz+XLq8k<CWbt@|!N|z^2#A4tgpI'
    '&VR&*X1xu5nT>JEmXErsOi4%WxaM4C&{Bs1M~b%i;ODL5?jyx>Htbl0r01(+(WLH#by8lA4_Z87LwPLz'
    'jVxm{r?+SavsIq4Y?dSTV+V85@pn@3Pn?3(M!M`!RTq>>Rdw-EbjwWXv>Tm09j<%yNP?v`&c(;>5F}|I'
    '2A3ZNf+PWVgC9AX7@VC27@7V1qf%V9BMS;0s?(i#h$y-K?qcJ*E>ZXJk#Q_AZWr-z4;l{F@3x#-hrw_='
    'Z1%gmP`K(yxHJGR3tsD_>GFfoTSwt<yNiCS3w|pFu60r7c2}`)-<?T(CxLG}ihI+Ay=9`;Zl<9BR~1;+'
    'h0Ch@*t7=?O?!yQv<C`I`~J%XcPNuFl)swAXfpm^f;kHYiTg;(^@FZ4-i1fv!DG^@Leh2-MOL{bQX3k4'
    'kB4AqyCB2Al&G)n8lH`(JLR2e+?b*#b|P@@Ds1e*qQ)K|Xsj`2tdnXkb<cg>ZG7Dhhu`7Qr8Wm0MgH;{'
    '59u-6nTJ^o;H+>p|6#HPX47Q6xZP(9?1n+9Jsng-VmJA8)A6LaCxmvpcZ9gFvZGq(L@RoWA1_yELJkMJ'
    ';9g%JXD;&bG}ZdAsTbg=`Y?;Ar|&QaWe4<lyqe7>QAeE~fExK|FIVLDXg)zPx$VfT06QF`X-p;)w#TP&'
    'cRe<HeQ^^X@~c=(blBDCbrDisHQ7{b-j6Qd^=o%o2|E=4`wu_*?nc%LmmPJz%*mEqpv=DNPU!pAcDN2j'
    'zCVr~t|NtXcjDf+miBfj>^*?2*WWF7>VkB%f}X~RD1$-1L%Z${n$dMB=2b~~S_!QakCI+M8}{V&#^fq`'
    '^*p{1gg<(pvwbyMb(6kvHQHghd~8Rp;p>Vv{}F1u7E3mFJJp1sCFvSHLI6<GPhZh#ItQL7nC!5N8W+Q^'
    '*)*L){~hOS$R#{L-p1EXGaM>fxp$n4Q)ubl>FA>Ucx7w%?$RpW-bIt~@*}}ACJ<Dj)qsUbbuh&|cM+-A'
    'Qpc$p6<a>+#zkG&>Mq;ES8nl6V)<nnJo{G$cFW~;<q;RdiQyTlU`qDyBM*gr(5vPzI|;Jot)OX0&fS8D'
    'E1KQQ-K2H>)3e@mJQ*q%GtGNg-2dfaaCU^LOx9t~Y&PCd<>u)}amu?XiQQ*o9e-NT#?~TCevAjZuv9)+'
    '40L%(U1bt*%Hpi!Ig1X@$4LVT?j}ll)vXZNZP+sU9gQbciQ|c_fDUm2`JwD^w&ZRa_hxf4JsRwUNvUE1'
    'wY#P)r4vgT#mO+!d%DS4s^P0@7Q+LkASeuM2dN0%9<Tg{_l}v&)^Ud?u|<S+Bzc*Qt@M2Ajt*wC1?&rA'
    'y-)b)9or$w^T^@5zcVsRM7Q_q&v$&sFU9z&kwYYlbTFH+Y_NZZsr)8*K<9|+Qkk#U<;6^JM!FYvfUz&c'
    'sXP4X^lEf{`q#rj$C>9lmIg(Z0-Nkea{MmxgaIciUww=jOzd*bDmIO}t}&;UkbClHA!_XGHlP`jJ+-R>'
    '{P}<WPj@t*A}V)hr?WA}(aH4*K&Jv4T|u^>>?-QW$6RsI!K|HbQ@R3i!*vS1<_7I(-xW&Y7v|33PAAwE'
    ';^oEM=?b)0b4R%UHj=B#KDZd(@rLY5|3AK4CBZS7FbDSX;(zYYBx6mg68!R<J=ztc`U98<v}j_sg2#Gg'
    'XSom3ioC;%dly=}wn}72TDwRCQ}$I~ZKIpYghJ+^Sz9|X!BM14X|nyp*hU#;(TskMvu*;8W;sbX)2#{z'
    '@6nqcI>~Bk$?oW$cV%WT+-P6a-2l2`<kc;v3en+@m5*{TRkf$U`Z`erlSVD&OV<w4o-pHfjW9S?;|2Bq'
    'eCg??>vpn;`!g%|=PzAV7t9=|%HV(Q_~PS+O2+rTC{=9a(uSQC`qDLrD*HUT2*CSM4w%+S-$}gulH&}{'
    '(Z3j7oA^`6zbK{2@@XxDKYH9_=T&U;lEuXo1eeZ>*na1oFnA484eYyVD^V4Mx{sV;gMZV=nNhBdMJI(x'
    'Q_?z8_2m<B2X%KmZu$1sggkT?@G$ttECHs<2%R?_neU=I4*kDU&Ym)<2nOilCLBIg2HnRQhz0uux~?pk'
    'S<>7;sTDn>&!ai(Eq|XelG;Ji+wqchjv24WZP#s5q;8W+npCAq&-r+|v%6n3!|7Jah_!916e+s<t)Uhx'
    'H2nawda}!i54tU*VQ<vYmM9dEs?s|_&N&<~xcIwDliMxak5n((S(gvZiQKt<^d0LK`=*C$;r+Yod04fO'
    ';kQHEzT@HUJ09*k9d1v|`%Z_A!q6X}(_ul|`L22$7GU3Lx5L6*`+kS5Y5BY8clh<@>(_(Ji?^pQFGp`L'
    'FGg4I-oAZvc?}oSm;N<bu9i>PZH|B~ekAd4%cm>&aukE8_yOo*w3wmW(Sm#!gFMeJ`Q!OLt;Q7?i4#Y}'
    'OCsdq#3R`B3<nY9V;?8jG7=oRKKA?&dBkxI$1sr-Vk-)a*iFm?(TZR-^M9DkA~YE-K^KcZD$tO4_B&bJ'
    '3n0uGBR33!z(gd7v1eO;6p+NWEZg=IKZucI;2`m0D@-f^Er<dqazev3FmXdOX#fHaNHU%fm=)nsg2t1('
    '1^wf8wjv{hZ^tZXQh<_#q2WXkb{uTkQH)TG4J#ss=lF5rMX`hZ#K3MCI<{}3ATiv;A{fPi7esDIVg?E='
    '(z1LSPwt{oe79V|MY<Sa&>N{@bzhn?Fd{&I=!Tw25<mk%o`;ZO5yJ?~(1vj_teW_NXCRx{3BtZd+}KEv'
    'fh;TZl_^&Y2YlyYwJ_ai`4J?W(UMxlM;~GLXDQZE49l|}Gfu3)u#p$Q63vhh&v&sOMIko4D6maz8%As*'
    '*TZ3A`Zz=c<0SH2(t!1<<yRm+G6}JXNl@%rv4=e02m{YHOdv91`KFCM(~W%;pui$A0hC}IgpP-Z5fI0Y'
    'O$N>BeEw7j2iG5GcOO2k&Pl@h7tN;23ufLpUVa)UD>@^NttiGMP6Efnfn|9(GC~}}G4NyJdjXJL6#JHC'
    'IU&N>bC78|*a>{gv^+b)VLv^OuP#nsjNYDJ|8xb%@n{VwhB=V6mQeBJ0OmS9fBE|2>I!DMyt){jou2)4'
    'F?#v>mkavWPw!s;jn4l5s6W1)&laoRe=n&5lq_bqz^do>J@GXrWKRDUKhanNMmzHN$>I*qY5bAap8)W3'
    'gY^f1<fHz-rOzDQqR-3m|B`2>V3~bPlHO>J7E6M;YX_);HF-G^4^W0C9Orb<<H-!+C3`|VkpG8{myI)<'
    't)5-Jd2`K18#esTfmP;{OFz;A2=mkbrvvhKu<6fyraHi@UL4$HEc?xim#^r4y?uAB?v`ZoY&Y0xI?kV_'
    ';|4}9Hx4$EZV6^=ZagK+<%ol$Af5?2>`S5099F({bVL#PR4|ss-PE*$5w{R#&(gCyIA(m6MOPgS2FI)$'
    '4mkp>98$a;mgZe^VA>^wjRwd(ph&I;nb8@$Zh3noYQ_AW=$~VcC9_436{Z~acmZ^3>0A)Fnt(ixTAVmB'
    '9TSXl<2>VkACoD^hWsJ@B7JY1u%1Hk><)x!_R@eRqM9c;xnY6EOHjwCmT<9H%oa!echlddvriOUvAQ0k'
    '>cta=9f|Jc9KlIA$cCYKq4O;WtN3-41AEvr`Lpx!l;&Upyui3HnoN!s(c#fwZU_H$_U85V<>}e==<26a'
    '%k?N79lbZ6gy>0f^Tl(%4*LHB5^joNR<3e-M91UH0*S7N#~*;Ek5n+|1MiKSVek1V#dLm>6lnuC27Bc4'
    '-RsvEm*RnwgJwL%v)lQEtVl{fD&`gh$QC}$76MsWx2FS6bpR+DFH%`zJe}WB$s&DEA-*Q6s$vKo5YvME'
    '&mA>TmniBPpdQ${L<S4B?1{w)!s)R!^$=!G><x&f8fPh%<O!Uk)kjVxn)6!wyre4n4NK=(N7yRiDWgP&'
    'BC$7DZ{A&=r6>LBJ)P_3JuhJk0u=&^>)$YJ(!>(-31}&$E(%BwWUjeHXg?1!kb-^|6*z`RpfN@=Beq!-'
    '#$hdhLpDMCtw?V_-n@{{|GQ`-s@aOd^C_wGy&<3HtN^I8z_WLkmlv<ECA61s{{8Bhx)b4=DDMOt^nE`8'
    'sg;W75n6%5z;}Pyzd5EgE7<brHp#il)rkAtFNP(7Gs1ofbPn6Gx|d9GG5bUd5&xhdj4{2%ct%Z&s+N_3'
    '&XKILZT|dt*?T>kf?7(=g!QW^3_;@(Pg=dg?49%b<5YrSQx~^jHc_#!D2eN0{ccVrij>mx$QMVZ>8!F_'
    'zW0=)I4>d$*55Y{k#5sktsuoBpy)tz{skZ9gspM{ip0WYln1_lCJ#OyFS$~y-X^JR+MCX3r8=sA5uCqc'
    '*sRsZG#P(pD=TusVNWFQrUz5(ufiNt(5Z5AqPr#NQ^j$Bv;92&OqrVKUnfB5WpZtiR|y2xahZb9JScH;'
    'aiix!r8NDlLFCI0@Rm{wOjf>1Gx3Gqp*=LkJt3^5qONi*N_$d?Optu1xoeg$75=v@6jf7WCK^@UZFEru'
    'iq6SSLxqM_%FV+`W83HfEpNR%Qp!$B*``2sT#RTVN2Twi0?^Un`OB-bH*nwm$LObvS8oCQ7cXD`_2TmF'
    '<;&O93f4aa)^K|M^UJHNmv3I@e*B?#*gqVUg(Y^Mw;o%;Uz@?pk{Dl0DvJF~<&x=#lrE$&CW2#1grUk`'
    'Qt%RTn7Pj8%gt%G`x2_g?Uxcq3z1LoI;w@MM@1`#G|MeDa>(ulkW8YUl1~ld1>Z(cB?};x1q*hOe+#i9'
    'Wq=Z&6pN?l=NIQvl;CErGWO)dt*&E*`Wf1)Z};lOYj5}hEx<-lm@fVf98)M-o6tb5I0SQOH3Ok^ax1J*'
    't)j&ke;{@1h0W*CN;2VC7u(f>CaTfWL>g5hQ#CvX?d31^M!3mNL7o?_G2Yqf_35iOe=UwDzgEU;l=S4Q'
    '1u0MAi^*d4zhufayGv_bk!~dXa|OON6fBiGl@}QFyo_}fSYZB$7MNaIgN72i7%`)3ej#TMz3<a+`ZquJ'
    'IPZnuIH;)=5{8_jTV}DKkG?;7V&0r&PxBA&=_46cu@|24=i%`mMLGBU#QeK{j?c;G;D%k!C*zp(^G2_<'
    'Frqr`kG&<WK$0Jwebr~b&F00QW^-lQYMS7)y=Oz6(6??lfhc2%E{W<1kKk^{aNSJC%T-R{&o4q9w#;_3'
    '8Q6C8ZwC1zn;Q_YcE@5=^5CmD0>A;i*+#P6V`*@de`s+bM{T>_^c1i)b6&PwEjVM$V<5lN)c^B4?KDZ5'
    'n3kS0PNn|b8fys?U&sWDlSNU$k61P1UlMUF-?KMw*v8W@*^7g^^|Kdxcy^1%s-;yOjXG(kEa+YRRxC?B'
    'a%{G*?f8}=gQT2F0>>SF<Cs?TU!Pks!5k#6@h$pLHmbK5;H%ZKCV9KgqP(VFrd0_FI{aH9<N~9o{nP1g'
    'k|jeJjM!TNHicaxwI))h3$Hf9C{W;YI$PZG_9aDmy_JR`z=ux}=oAgDwwj0h*Wv?zhCvIq+JcQSTfne*'
    'MT6ip%qe!M7|*edVF(a{rf4#PLk7!Usieb-PtfAU{a>g5+=FZS;;(N2uFE&4KaXBqzWL9K*HR*We(~3r'
    'uVvK41c|rm-??~wF5g(*C7`;{cMgA@0^=Et=-C>L80#60=ph}A`X|3m>BD!^@rruaj_KFT$8?}q-5B@^'
    'p=G~N2!%?Qrzs)eJ_Qm0QHEKzIC`X(AhFcDMT_5H5Bh`R<nPlpUtj$E_7(gwdh_DN)y4J6%`v-9mY>F}'
    'j}kZu7tk;No+0lCfssKGJmA4KFwIhhU%W4%lUHvQWMZ?Y<0X|l=n-Y6^(XA3fJA##-k-3cZ&HADOfY*%'
    '9PQJ$*PxoD!2Fd0Qg5Y`epI>Q+1+Y6#zdU&bp3gCmj*-%FgXH#VC&(CKM~92Yh?6rBbJC+AyfF~m>D#W'
    '=s1I8`oASk#vWEEYz)K$b4`JHu%DP2h>mm$Wc6Xnw>y22GCeM5C}ZUB;PQC#jdW<5m&FIxJR%A=^u@`$'
    'gkyRI0`oQHtl}8{=c|{`N7OkNxP?Z6{R>HG8P(qbbw;oOQv$LR{0cu}v_b&MQna@g*ymRt7MK*zjtJaZ'
    '*-{j#SYlOKu^3@U1r&OhS3@Hqp-yK8j(|bR;+)rwxJDo?8)Eo^DNe${zb(AN;muuC639H_KwgW{bT(yo'
    'd3s!_w+Zg@B|V<`lPloO-gzc?FI*}u_l{b`fSs~8`p5r01J;<r#N!p{Z@||Ua^>&GC*vOi1Ei)OSl~ux'
    '4r9{InE5|hzLGIyL@VBdy$FoKfXy`EQ_}NO;)7gv=I88&S*+#qhDFZ-DQztyDwaf>mwME@PL+V*^BB`;'
    'sq{V*Q61T}Hk+-6LJSx8+ducNsgxiz#W`rMPuRRE6!0UpUGp%H)ko$oSdFJtrr?6NWK3c>v8@EfAA76u'
    'Ejb3sJv9~5VD+a$0DGzkqJW3Rd@<(6M0^MGSZ};KR%ExMw;-J}_y@hGy&T`n`)CS0S~06VYr60c^jd`?'
    'uAYh&OP-ubRd}2va20YarCTYms;BhQZi;P817<$Zy`&c+uzH<nB9Zzmby+pxMejaQbOcmbVDZucrh2C^'
    'xJ(RhAUq0R=2^SCc*Ud63hp(D02)0+gPcU1Hgg%Vt>^1LJUqOl6bW*93a~&0uapG)L6|=a&e<f5ML^U0'
    'oO(h1GRH6$UkMCPtuZN;<?zM6qWD$4QhDH+MU4X5e>MJ{qyVKfo+A)y6`G8JCfUmc`ALWja?aPl?S5g#'
    '@Be#o#u%Rlb4;i>yMA-2J_mxY#=s}JP62bm)<bETZ=QgP76HkWPVP~ub889js`Mt6gR{i46rWkq$;$7}'
    '&oP;=lz14pLwkgND2B{{TtODBVhIbIp{hK44zR*cBmJYB*dVt2I%RIC5uYW71@h*pvRw@2V85>)SM*F5'
    'S5%ZD^DszajL7|rifpT8Pl*Q+6k81_aG>m-gy~aI%OOj}b5M{<3a(X+_#p(2?0Bhi#Z!Dot#7D$A~cEa'
    'Zc}PxD*sZNF|%`yXvj_DQy{U$i}9S2TH~`7hq;RL(dE4aedOY2&|HOhqua+<fGUNgD()X~v~%b97OvF^'
    '^GDW$BDbfNB*6z23f5${syJPG=cfLQsY9w~j18}-8SL*(OeT{5m2s$wA#`}1ZG?lTm`5ttM(rXJNNE`9'
    ')ja>NbVKrnj(QbRw^U_$Wf?_l`6-*tB!T2iCWVVyN{)oOTWRMoZm9i;K%Jz!!$n#aI?lX`OKJuK;c)>H'
    'B%;37CltOr${s267>WTg0KB+``+^CYKti)mtSuQ830J~Wc`TlNImN(Xr<h${e0uJyVq6~HS<$3pkON?2'
    'LF4#1k%8m{18=5~Qgb5<cUvCUxMGDhi96v0_bpjtZ{dam+|hk(7h1PzARxDemxGQNb4Q<4n>HOjb4OB{'
    '{#m1wTkgFk_9+)XCVZwv|Ky3Br(m6<-wsPpmxKQ_WKUl$Sd9g;g{f9Lcq*Lo2U!F+<xXGdWG6N2%sG&y'
    'v5xKf*BT<pJy>n57i$vW@b#BW;syRBbchK-Nzv~r$H|HPHwuq$(g)-K>0NNs@`4cN_)$(*Inu*3(EGL<'
    'q83UxERa<74zd|ks?u*+JCAwOR@NMtihYG=GO4@5p<Y<4g4fJ<Jk$k=lpaz3EPGCdk^rP=JCvea8q`<V'
    'W^Kevt0R~Xw=27r`Kzh%{`yU396i5yb$vQ)lZ>c&`OW3|#pN(N2?aqqRXQ`xaI~;;`87G+Q{ZjH|D&G0'
    'N@X?YtthRx0#_;mF0EEe&%Gd)3!jP$Em{|rAVtHL3vy*(|A|8`5|N5FhP(x)S`+5)70{BJ8p<NFFh=CZ'
    'zdAdu&<_<YV?s4;v5vB7LK`P9qd~;*S;$0z>&j83V=Zs+NU2GV^ZY-qFRrpsx`TsMtfKo1QZ&1JzGh$Z'
    'oL%MH72^}d$7L?045h6YO?=HCr@4CYyCJ<?!nG<NI%1mpu=g9eA2Mx;HXaz#5IXAONCR=<XBL=2AI`WR'
    'WrvjL>9_CUk((d0PzU<k`##-3C1@da`F~+9cG$@YHxR65B5YwWIFa!H^8y29jGICsD*P{KQtnazPkk07'
    'Fh3qIM|Al|gRckGK>=Up>G+Wt66A2UHnDig<i9F(pz}x5MVG?}Ic(hNH%_PsNR=cC*YP!>0w-GBpG#rx'
    'h@<(L!1h5dR)ie@I>s^e{AG6+{c9+syAsgZ-Y`e7?3@Tkh`#nC`}Uagn&aEwK&lj+cKPgjK{*-u3@aSX'
    'eq(<Q#PgpPFnY!rq-9=iI!oPV8=W@V>h&q$@HhSE>p>YmMJGK{)n|pl^1SO_HEFjn*Rg;B_?8mL^8R)*'
    'p8m%8#!uO1rZK{Fpz(^@rMWAGz8it=(GxF<4d>^T-EsL7%wp;&ZL<mC!kkThr*;{Y(*dz+o?ugrr==0O'
    'KQ#9&%^jmmIr}Et_J8i3(yS<I2N|yvdVMmRg32S;$#th;Z%PfLW!?8!8BPW`QkVc3c$oqUe@%$u1^5VJ'
    '%<AJk=fMoxbciDFPp#9{cgBz{Z=mQ?w-GgGJY&&G0(0r<FDnZaLNtZrmD}=+fr#-a5nS<K>9@+^cKjzi'
    'kb>h&Ip!P<S_Z~;xI9ZGb4rb(+@;ZsmW=Ph&2mdOWnB%1LH||N-Nbr$kdV~zDGZ>Vapml4(EI<`ucah$'
    '`Gc@YO93={>&yAY)!F6Cx6Fc-zBd%MY4wX&&)@x=eepFPC<Zh=ne<$zH~)CQ<jhx4EN2+>wu%XLeizeL'
    'p7I>h1-V<2<J_2;7Ql4W@iawhnU$7=eWukut4R&Yu8ya-xugl#$q|+=be2pW$+nbs;ex6kz(wY1i})yV'
    'pSt#sy<5&Co`_|_R*jc}xkM=bjdP3bH$ZXTaZ7Gveo@^PDd%s{xYuRXP3)|~H8?gN<KDK|O2>NYTIHRz'
    'cfXU&+Wxq9k|E<8Ze;Uz`H^ducgx!OZmC|6$F*k^BfH(Q;;yhz2^mwF+nv}#i4zW)s3iBs>`~{v+%j=>'
    'b-Fj2RMv05EgTi~8&ix7m-DpQExjPmgm<befS8-^kK+rh7b4qL2}wUoE!x}Wx^9hjNenWjr7nTI=-?`E'
    'Oseyg{RB#`msE5p>}mjx_@P-|tuZZD*~|FYYZ&yU7Tn|deT`dVs6aj+R2dlbMDTUZtgIBQGzF<($j$#='
    'GE}EO=TJ<?$z@6u9#$eL=%eK@f?-9bP$BFu9k7`4q;V0ZC~a~QW=ksMJyl_*8yk1#H<kl4>!0HfvzU2d'
    'S?Iz2hUSDvK?skf)CP085!50E=YXn#eEB(TU$HZal`nYs$20a~QP-D-yu1adWUDJZU$Wcvr9t-zt*`V%'
    'JpUxC-67yOsWGYaet6b1^WI=#i+E30E3I$oYH!jqvxSl!!=5zb=d3<*P*KHAT79@zkVg_MSJb0-QVuyv'
    '4afPBb7WbzC8-Lpyt`sqPgM9QHD{{Q|5#uV>=3<p_2$jx)q4iH8vDZeu1r5x_%C-)Ptbk7MvW-(#gL&G'
    '6GZ^jQ9itB*n4v&KKzZ`i%-}0b0R*zn~v$K*k6OnkSV3gP(`>@e&Zwy)`Yv{w@zIJ&3@Bwd@iylKg@x?'
    'SQ*=e0#zv<o6LSr#}dIQjIW;5m<vmGs^%!af>n>n5dZY7*Z+TaKr7?q{`fOp8FltN6&|1CdGwin?4P9P'
    '1V&IU)?y+{Q+1MRha<~!xxP4~nFVj3|D7kksFii}9+BKTsY4`RZ%LtIcq;D<(K4-qJ7d_>nn;B$3qbi='
    '=48=l%Eg4&O87zG5j2^7;Dn?wkX`O`$q1A=*Ry-4%0-oirHOQEv4Dy|T5Z_G+E-v6W%BGPC*w~;X0{y_'
    'oqajRJ6aItu>_E4G}uTvZUwKD7&RL*{giPz?l6^CZYA^9ys6()sU@>m^bc7sEBS!p)at#2%aY8gxq7_F'
    'y0ic#jtkL5SvXT6Dwa)7?eTB~d*}{Enyy&9VH)xzmqhL4(h7f^E0LGC<UdROJaVOqQD4%57*rib=RnXn'
    '56WDoXeO_qe&z?F)?=PUQ~6xZrBbejl)nUv)Gug}0oNZCP!BBc36UF0#veYep70xUc|Qfj1KzW8K4_Zi'
    'dej*)C7+bR#2I_~f#riyF9@Pe6~W3%p{aZ-c3FQ|%<kqYNxYfhjF<qj$%Ni%F@d$MW^C%aX_{`v>57)X'
    'U`1<L+5|}AdLzDK!PlAZSrL%Si&JW!eev?|*Y7Sx!M!U=49cr=-!dCNAVcy=p6`~j2Gzd6_E}s7shXK%'
    'D~whfnNKmoJO>8bfoJJLE>HiRXS%fmM)wwnsuW44f3^}fnqsbCiTYRtw0g4ywMIy|(gbV$_E6^ka#}}Z'
    '@-UQLP20LD)MLx#gMtH8@qHDKrXCvY{a4^$RsN8lwJe~<ER>a+VaG#q*0oQ_*TNoFNGVmZ6&13|jHcxm'
    'WE3$(@T4ryr~LOZ$niy4K-gx)#Z3bRmQn<eqI-?_kX`g;A&DLgK3?x%o2+<exmzJqk(LZ+EL2Ve(&qGV'
    'fnZUW;3yaGpdl1lp@2d4wE`ic+PW}rd}Fy%5cN+ludaEb^3`>VIH=+sOP5p>GaI9TE9d6ys99L8<jkcJ'
    'sn}Y%(u0F|f|kqPnK*8jaN0x;%ZtfuwvdIUmq%$PJgq=|hL))&3cJjARk)BxOPWqkYkrSzX<p(8?wpaZ'
    '%?t5UioE>R5E)JapGP!AMB%-ncJ*vos1mo1SAR~c`O~V{X;7ZDVdQE9>Xm3-Rh8w{^~FzW)PiE+mUsB+'
    'TR4lqP(_aweE*^MUX8N5$=@p?nn<x=|JYli-<d&+#R#b@`muLQR!C46`;|&SM|sxH8WkbN1z(`ak{kOA'
    'H&ppT$mt|1aJe8Q{=e@TfHdFYzj`Li>E&OTCpYD5ZMHnVqjbQ)04BJ6b|e=8(2o$Kk?C^SQ@_0x-ww*-'
    'Da*U~AJ8F=6g<#ZDdpt{qu;DQ&TTzlrSX^#N*VN$-W<!L(tVWOCF$KX(8wC?>9zrYY`)4_HlTY^#Q{ww'
    'ZODd^$8Jf3dS&nC@>oz@u(}?6SJ~b4L$80F7b~Qb7cdYNC9={f;uEBLz@T)B;iR$|`GYM^*FP@Bh~1JH'
    'qk|19!`jke;kL@%I4s?0#4iYT%h0AVJlkosWIatLGujtn3i3J-;v5z^l5xhP`FL7!)vQ1|+~&5)w=rl)'
    '@Q`<ia3e90>0NTfhz>;6MH>E}#_Zj#5Ods#iGE-;bNa=CTIz`9ZOkXzu@T!Q+i8Ey@>E;ZCMuOGYM-vB'
    'MMYr+^&qBBBqh~P`LQrhMGEbYE$a~GQhvm|9NPRe(z=oQOB63`DJ@)5R%LQ`iV0mRak_pn=Ri{;I0K3K'
    'ev6cRA}~Je=?=z;Tuu73TDe&)qo_Ty=yfXjD+|dz!V_f>=IkP~;c+P6({FEN;H6UQkZ1DI@e6z=<$!a#'
    'bH_8*J(VflLt2AQ!q6YGSv9PX@gEuqP8r7W&n#n=s+LFnd@mNxr>5isb2;>B@HhSDc*Fu%Y2_)V375Eq'
    'CNzS?N0i0Ucvrar`LO_W`c!|A{eZ_HYL8lT|NQL(c;@4j5>3<{E^_9g2NZ-)X%=7+qnNR4)y}&dF>RNA'
    'E%X5)IpkUN2C~0!XJ#hxjc%`!v?x<4xL32v^<Oi9CeB&Fs0K`kuWC{<hIQJ%a;wr}WU50zAMh{lqfu6o'
    '$25QlO5m@9#rNh-x&bv9sRnJx!Oz~!%qOYwO0|||DpcxI*N{d@C=(BtBv*OGYIsNK{9KX`<nxg#vbD%{'
    'Df5=ilu;>ORV^ehb8z1Q?DP9HTd)ubRI127l($n|8Xw~b1D;7EFjr7|X|#a23MmXVRd&mm`RCqgOf7u?'
    'y7W0v|A6!f(Qk78BQ-FKnlz4^HNgtxGgvj$ZQRJHi9xwS=_W#VZ#@7C%$Hf*Ws?En$EAE#CL+?hV6<QO'
    '=+nm;J!~``o?&KVX8U8E%w7mE$yZUTaO@T;q8DSBWT?tUK}&VqoK`m<>PtnJo4_cCgTD78$kd<mUkgC9'
    'SAQe-Oq`;TO7sMZ<i9Dc5Ki4%(+|u3jmQdA3pn<v9C0}V&E}HIb@#`8#Sc|l3=PMkGr>~){D~Ly(I0tr'
    '-Tcff>8yI(DT|`Z`pVQ{GL>d3^Gh>C=aWPS^$XJ**<dis)V}$0dZfnA4SR(bb?>~M(brVa%dZu6QQ_R6'
    'wq<E(qhb%YbW(AK702SgGk3=wz1g;xZx}mikqKGws8BebP#~Z5ncHI}Upy&TRhC2=<kLr3_9Ax>KjTk4'
    'rBWvxO~>!2zlki!?E`|-yIxKz&7|U%Yn^miF>*c&vxAW1EH<&tZ7zndw3#qRVuoi?j`RuWt!N3@ravD`'
    'f&&>c9gZ)K(qLNRM1zLbLX48YxvsoIL91Mz2=-U5Z`K2wXJ+<3+@Xb1Y&k;H-tvA)lcQ<bPC8zXA%Ya*'
    '{WUglPL!${ym)a+XYwe4ogN8E^dk}V)#l@=v?X!fM;7eNm;2d~Q7J1cRc}-(S%bEys??#OXI%pim0@@s'
    'd)ZV|#z|pWP1YYVxZdO=<4H42SBGAAGvh7{OiFRD&0BCt6_;a#NqO})st2@B)!U}n@>AneuGy5_U@hHt'
    'V9aVTWOZ%C+Sq_qZM>@Dej6ID@<uDMGaDJL>h7wd&!pd28@9rp*J$VxIfE?ysy9Wyk3aD4Dq@Mb9$72~'
    '{rDg)En2ECNf{uv6M|6^ha@4P>06eOII(NRkrM|N_8lt;90U2b;k%B9k?j%(BhxleU|>JNQC}Uuz+8hk'
    'AcVvr3Qfz1EYFM+Vk0j$JU_Nv-wcQ!xyX)en9WSw#CC!Z#xzaWvXSlMbnNN|=Cob;%jNQpyiRc;dzTO7'
    '+pkZ5q1qX%XCVY(!F5i0{UmXGn;5a_g)TAxhA0f+Z_jrVgZMFaY=A5ZEH}Ui8)oET6R?pOp=m}2vLe>k'
    'Jr{rmgTh0G6`0tMeTR6S=QxH#u<eGSVI|o1d^_;%C?*ER*fm2h@Ng8l7HxGO+GdE^pdat1zb#?3_Y!J4'
    'GB0w!poQ|zX)yYfE%~JPl2*tYCu0-=5qv2+WR%d&RIme~mX=KKy?gia{AkefjTp^&T-O=@(D2&VVx4t{'
    'sJ81E_I^Tu)A|*yy`at3)6XQD=@|4UX569fdK#~KH;q|n&*UR0wpYL+fal4NgWi)r_nyyYlirse{4UDW'
    'FZidb$-b@!2LpiCIy@RrS2OmBEKY!dgSgIcNINWl5#JvJtBA%^ax}(+Uc*FR`(JOq%3~zDcvPMwGw_4h'
    'jh!GdF*5wnG)y0OM;Id`3N1e(aKcDvA;+_v(8qBQ;}9Vq{wK8HL!v!NwjUylJjb%_#6vEeMGLzzazi%`'
    'jnMLJE3uq_Sa$3ha7YmfgD^>qAh41+!9h@Yk`7s7kBqi0aFy$iv%3!;SLcLficuTz1#18=S<7JsS=SC)'
    '!>VLwkJA4g_SORHYYr}zZ>V+N$nQe`Pn(nqFM#NH-EgRjfnkf;r~C-R-o-C(UcFPw_g}r258Tj$S;Z7O'
    '0rD{QK=bEW?aelsJC&Qz&#vg%ZI4EvEster+8MpCm&aU#%lX|F<O8UjviTX;!>Z0&WjatZAE0i8=BL{9'
    'FwY~nc}x-VnwNdDAl9}(wTf`9A8dPyRM;HrOD)BtFYOL+S8@cSt*3d~dfGr+tZ{s=Z=fWMyueNz7sR+A'
    'vh5%UEi=MyXyYWoE;dQx5GOP}oVZ3v9M8d?2jZR!KN@Dk{Jdb-Xi3lll(!5T!h1?fAne!-T_+(R(O3zw'
    'u;aO=9XK)aA~UkB(6a*&Es-CDUJP?v2oPc!2;nGn0bvb5NHY)9E)q1JFq<d2ovlc|elCFG7#3Vcp6}4v'
    'Ll9j(7lbVk$b1{F5TA;(j+-DaG(3mEl|dpq34??Jh9bu|7$|F$?Ct6T<WquP2Y4G1#@@5?`eGtGa2+6@'
    '#P@;3NaR}t88EbKBg3{0Y=veB!n=(k1B6W{M8vb~h&YzvB__Q~*+i|98T-fviQEKf9k$R1nsH%89`VBv'
    '2N4jon*_e=VjGhv_TfLz2yq;H2B-|6QUINm*Cd@oqSkoUkw7diHV9nwwhN?dSWblFC<&NK5Je6NVoKw2'
    '>?Von65BUC%SWa|EI=SU6Zn?j&!1%85OjZ(_ec3bk8(<cX%SJN#uqRDKKkk1>%URa@O@D_tM4IyBE+V='
    'u+;cY>E72qNH0Jbya-WEhnC`f+}}aR7VR9R9F5{rhr8_Pk{1vUiw#~tf-LV*dn`Tx5?kT$;ZUf<U>V#k'
    'JLcrqR(@^U208$9@$_VZ`5HZSntSGyctC{$(BDBPpZo+heSIpJNmEaPY9`n6%{D4d_Ck9oi^b6SOm)q#'
    '+peO1WX&oHFO=7CxJ9G*Lg<99@<dTXKCG%rm36ED-H?ivb5IfQHFfaw{Bj%c^L#`4?V8GLR4<mUw#*f`'
    'Tda;vbWyKWe;wz`tU6&<W|dzgw3Y$u`KMeVxf-h?xRF;`t(~GpI<xkk?zjr86Y|{a0+p7Nk&A@f&jrnC'
    'm~2N?b@NQLrcPuPLs!b?n%RCfm&>i&$}M+t7aQrCnvHDU$9{)3A?tUbixQFDZbN^^1tjy6sdWw4rH8Gm'
    'OIGhVJ-9jsyGFq~{iAxZtLr*?8iAy;dQ@FkoT}nb+C_9<n<`HxHNbqmIneUHHM}P47?uVHdVQhyY@JaK'
    'wAzE-9k#U{OXm*riRpM=5Zfs7gD|l}!w!8D1(;BeycNVI$oaMxd(<lD`AJ}s&?3~U?0T`EnAPquvF_t6'
    'n4W5e@B8qb(h(>XzA8On#c@WwT>eqTK%y57o2=S>bvU1(=@hu%(VzriRck3K9ZDPjpb}ioz$wJ~k%v9S'
    'wZOs7oClW|r{^zUUtC>P+j(S#Dy`ck*P2JGM--u4a_St4wgk^!&!(g}iq6Pz2KowXZZ5k(VlhHb^de@e'
    '4ZW`JrVK>2X=t=SQ&1<D8Vkc=RX68)%XUf_$21VFpXVz&rk^Eouo8Fw^sHCR-Ke^kN-n2dGe21pOaj)E'
    '6r%JT)xjgxwh_|<a4soj@LufFjczkwB?9wf9%o9ou=0AB^RRyzk@J@aT1$_pI$6?Bb5Az?y*AZmygfS)'
    'r!TJ4AbZMmO-y`jA=9#h*hik>`Xq5f3kAsXt-x_`Vi<{Khr|Ik8Aow~P20oRb%Ox=zy>p3Om7x0zg6<$'
    'PP`aJUTm3WLM-B8f=$;q9OMQT4sFK(2Jd1s3_J_oC#D%h7Q)yuuxEIF7+6N+If>_12l@QE;{Si>oVvbg'
    'xmMu6@J=sYxaOH}2euI&4r_e$>D$(+^TNLf{NRP}1>u?Fzqqg+H?Z5i?T6-t_xy!not@jZ_1v(+@DyI>'
    'b60urTS4A#it1Q~^nKTIFD^{L=~>{Op1MFd=NJC@3nw>8U<bjOe{Kga0{=XOJ#uZ!FwK_hsGFk7C7r$O'
    '_~+-A;aJw0;XJoJ=ed7+dgfWJUap0^9ywosY}nvx(xB(3kva~?OGKYMgtPYoMBPi0&`8ag9RAq+?gTAY'
    'f1?GB=$ka=la0jL3iU*C>8{O4RFq^db2k$Rjqj%8mGC)D?xHi{=lL7C|1?|Rb3#)fW5NSCTF=5EyIv3u'
    '=)bb+fq!m%vw07k7ccyC<GFk8J~x~T`^D+$Md+Wqr|a**^Ski`Q*^djPr^5hy<15J+pn(jY>U;^ojf{v'
    't3jH0L~gN_M_J6q)>O|BT8~$Ey1zF3Ud=XY31f@1+1b&2kdwLb!EA?pI0L7)>t38X=Z0&CXKwKP)H*ve'
    '*T#OEQ>mq^s_k#HvQ{TzN#{9gBLr0Ps8%9`8D5-)?hDUxea|%Q)8{Wvy)bmoT3o$3INJ@_LSVRfesN})'
    ';fwQ&(+k%<J-aYG6V9)d6BsUDz%1uymhr;2UYyy^^Rv^?_n)7&6Bz2IXuR_)X|K)8wQv^#+=Mwsk;h#l'
    '3gXbhP7)K}_RT27iEWq$B6fg{$gzEkz?X^R*cQmoR1&u_w){9W<H+`szG(d@{fRQHB(;JuHyvBUEn57>'
    'ypl9mZ2g1=iHhZ2l8isoVL%53C2GV<Zqd9DSk7ofYe|kqec@G03kcG$GmTQ|PJ7IXJREW0m`lmzJsROB'
    'GQ~U<n$M|LW#sGSpvg23R%!vI$%Z@!mNycnqb=u?v79K)#iABpstmBo7lhg4@KIe1iIPIXs4xu$c*e#N'
    'F75t}lGwz*7w01Tp;SPc11u22hT-^N<zAT$`{{zrdE*PQezEfL6dq0xd|J+tTC#!<$?Bi5v1JBU4)hcm'
    'tPa()UPFeU+7hjheNxO5Jg8hAohn^jVN=tnAX?kv16j-$W7;%$l9sjR1p*37qQ4KDVAm(jl+qgkA+)|B'
    'qdHxAf13JFfiK0bDv5d2&Yl)3rl%}hme@7cNtMT47g`|0_@b6-Q=C9{ys2@i*m+dKEvjWqS7YXU6h;?r'
    '!FWPV6uo>tD>X3jGsN2{FUT=$1xAy}(IPrL`pfO$zce{bNAHa%A$pSBeDR#GgZ{r9a-YBK=Rgzr>3Ga)'
    'WYW6OnI%c>sIz3XHLBC6atW1euv)7}O<CWpF?F$`bY_QAkt9P;3XNIvTUEbBm*jT#yC|H_E0|C&tWGkU'
    'ug16I|3%!q2(tj^q;@d+G^<5Rb4qu=KXqs;oYxFlsiktB78K5<B5$+P2YK_Ok{hf)iE8JjlTra`^hs96'
    'PrLiFL#p0;9}zVS<~D~W7*4aEzIC@p!6v<fdxK_Mq!*~TFY;SgzkQtc>PWqKop1xQx{LaYBxfb=<ZL%@'
    'Z255KxUYVh>ULMN<I)+g4~mj!{i4|2MMe@%?td(IiH6CjkhCmDE~aN)w!{HiE9XooHU4GqnKI^BW3;NX'
    'a3RkD$pph<@$h4%wN6#*$`U?uz>8L0CD?RO9cUa5>#Zv{b@pl&Z~)|ZQeSt7+1c|Mt!gD@7V;p6Zx!6%'
    'e!9Ggy?WMlVyxTGp5+}@&aC(CuCv0NL$`9CEX%(*bgkM`9w=87AS(hS#oqImS7&d2xd4e@EWQKjSFi5W'
    'iNCTKg<!$iRhq3^<*HKdZ3BFJ@wbdSwE)6_Hn~kJ`DCg{SE5R>2_ctR^te>~i4ADnNF2!_C{-6}kCYQl'
    'EtX+cC3u9HWe<;J#e$KnQE;SPr+l%I?WRX%*i<w|qfMt`a9T$ptDK;sZj`N~@&NKjl(w`CcUc(`Sx85~'
    'osBv;=D1O7C65=&Rcg3M@qGE_^ykrw%QyddA=3*-&oBP^^0jKTp|(}_X8n5?ug}%Dy0CF%WR_9D`;#Y>'
    'Vud;52F@E_8m-?W0J?+~TmjW7Nt2`heD(7A==tf@Mc@hxB738M{NFQ}F(>UE^|=@N2O9aj5X}Jb`|-*6'
    'hrnP}`&muP?8s9QcAVAyG=@wM5bptv1jc~Z7aH(s8A5ZqalYaqm&5YesX14F%H=Z2i=LqVU_C`!G<hvZ'
    'c^b{S*bJvi#jXnxmlEBnQe=|W_u&%Vkm_brIiad*=i?Jo^+*-z#6okmb&5-_ERUIXG%H8Lw-D)gEW?2s'
    '-cZF|bZvq=0-jH;LYsm3gz3qmAtrCcUXq)SMPp;igtY=*j;{0}?z!ltG`77c^%dDAt$4v96lAxUebSS0'
    'O~8A3B28AzYr&tz+OwEEp;Cx)HTuaLZVXkR5t2jx{-}7M7`U%2BoiG=YsuU33+tjHY+CS-x2MyuOza|$'
    'ZOdW>N4(NdI-6cbZ3Zi^AWP`-dSjZ8lnEBfm(OSd(@dK^qZgVpbhk>d((Q9L{h<BAOBq)cs}zZ1x_PU0'
    ';;N-8kk)~kk0&Z_Ql9ab62x@sd~3342@&7*hzbgAR6o(}>XQs3t7Jp(;SD}Gi&IkI$!Ub|MHtgfEz5~M'
    'S96@=c$JI?(YiOHL2WJ1S<u?D`C(em$NfHZ0I{z3Oj=@p3{KcM>~qCw%>yZv&dg#b0o4Im1)pxeX$9SC'
    'Aaz?Iu19#ObUEf7f~q(pBmXQTWb2`Hqao=mV<AmED417xCVsiU;Tl$)n(M2iscfDCM-`v)T_;|Z<fdzF'
    '*qR?@HmN}&Bch~&XToVYp=`|xi%e4OWz(fp)W8IEvP>O)wGzKn6049-YYd@mifXZ0o87|fJ!xrjF^A%_'
    'noUJPvYa74%R=Go=0_p^(H=qx?G%f0ZG=lk(r3>K1s!$97^QK23R&7)bDF2av^#DZj$9OE#WvKb6Q$Dn'
    'DstP<ZB~iUk6@oLd7>QP9xG2pHBBxXYKjsTtydb;OBh>T7}~z=#9o8~?0A-KdafDxab(0vOrqFK63ZZV'
    '90GH~$VV29t_?#%tT^)e2Q?-#R{GG3JPQYIgzeZ29AZa7NFqDH#0wJ_`*utNkliToeLu2{fB-dMnpWXQ'
    'u7yoMKS6pt=+K1(me+uw^9(;P#$<v;7Ry0}RNGt6o>~T_G8o$P?8HULcEZ4n5ulGy{P~39)-fVKh@v14'
    'kR7;zZ8}k6#TYp_ust^n6N}i|VCdMeu@(8Ag~HgjL&pgdKMXB+-*!DSFo0E?Ar4_D<IwP2*tghni4mhH'
    '_I<;(>nk3zJa^tdg;U}&CAs5I3pAe-%zQ1!3jO^EG9+cA6M}(LKW9?HvtDJq(m7h8Bi85SZj}Ue1<G=@'
    '204viw+E|5F)u!tGPHgv3}WS}6mS~mqamnDTIi&_UXd1ne7uOzF#gaqjl_=<-^GTBtsudUi9;VqEHr2Z'
    '7aK?>h!Z180w+Ys3{4My-K=I`eR;i23-;BV+}f&r?Q_c77XPbXUvcB>tC-cSsw)PuUcH@8=y02oOAaBv'
    '6B~&EyvmJZ&qRTb9K!@|W*8W#IIu$E+1T@doguh2Y{T*#;>4J^D2Y0(cI5d4nZ9cUo*jD#pn+?TrmOfa'
    't7~LO0FdPXdXR0{C~`v20_GdUt`ml?<B?9PKbd}lLM!&80GWUU+X(#_)(@9pjBU$seJ_d}6Yj_$HXILj'
    'Bz8@JI0W1!1~PE#Qf6?Odx2>LhUGgJ0dflxGxP%#!6j?r$Txrn6UVSa1cYIEmgCw07*2rn93ybtzJ~0p'
    'OMdO?eoyzirTaWNwl4nFDx9OL=vH^(9omf3O<>yzXu8bFP6AOX%O|ZLm!i$WTrW(eqBKzp?@$$ibm%S8'
    'PO)||r1jUb`=#`^a3wVm&{l3S-Pmh-$uxzcY7DjOTwxlEZlU;2vnQrhHE##5qkJZKr;enG@^5R~Ln{j`'
    '<=gd?O`qDz9@|de@76k7QQf35&i~i8t$^Uc+Ded}#QbY1wdERGhijErvXg~W)go&fgSPd~bQ6!J-IDd!'
    '(Q<e4N2GGEI$N5KYwM%28e**4gjf|AcNTF~iQ_JU!t&VbCPb`;yt^*qwoVnd-Ij5Clok23h1}Mx$hUPV'
    'w{Kt14<7xZ^%Z<=Q|ZsjNJQebnN(=G*YBs^pY^Tl{dHHI@uE}`(2rd6M_K*vi7X0ev2s5-Un0Q|SQM~|'
    'Ro7Mq%#W_y;ayh-q{!?&XeCIk<XX`-u~r7nsgzmK?ANnt8Zq(|-%*tit;%JzEAHWTfOHK<3D+t$NfHoU'
    'SVh#NtTg`hMr4ZTURgI?d?T;(E;7dpCZ^M~>o=FxdAP+iPZj)PT5d6*Y2y@ib&}oWsW;j@A4#&hiivNL'
    'v7S*!ce(0%66!o*eT{UZ)>-R%hh;_Tx_X~(mcriJ0$WI&jI|)-qJh#NpeH<9ID;>`pQGhcmpfVEuGQGB'
    'EAX^V79{{&mqS?@BwU|8sRwM06w0kuRt(Qik8<W(V2*^Pq`%Byd|Zst(n{xT5(ss1H<kH=6^6%k=V_4<'
    'S)HlaeC_TeU9mmuTf=&y^1dBrE3V1=TBa<vsi^Udk``6GZjiay5Zw1D(ibZ^-e!r5D#kX*UaUWq`xM4~'
    '3ZpiKG0*?j$z!a$cq^r@O_CbhDTbnUur|F><O8t-D-B;ldtlc)tw|$Vut;DXOI-6(>?*aq%Hf7Bhz4(u'
    'f%)FwPR7&Un6c_yJ=98&H?`cLo_JE=SwQ)$*P>yTe1Upu^C(fYcs}4jD9*X$$TIKBJABo5xO|sW`P=EQ'
    'ns|Moy}~wdvy51Cp7-UV(q)$f8jSTdmnYIjd}R0ev!2p#pv2JW*3rjuTgPN*`7Qld{R${|Hu)XCqCd(q'
    ')}z&o?OXQiU|0&ul=|eb2Mb1XjtMbo;V|axw7QIqw0(q3%4m?l1?Z*BJK5kX9ZxMvbI?l6U_%VLsp6!J'
    'r57^TJ_tb}y`0LqH)$%B&QPK$?!*)4R6Jx#q>kMA^DQhkuiz{e_BPY)a*gdc3zD2iz%?4CcYnRKlER&n'
    'es1!p%!Ya<Rtykc$az&5Q^`ZH?DS0ma(}m03l3aKa#wX*@knbM#J|#Q`7;-=3;U)#Sxn7rXKz!CCHnl{'
    'x-4z2<~Y#mlvH7>OYp5RW(ti^f2pU$qlM+B5}1bU<2Mt=;bMtI!PB%*lEoUJDXMQ7xYjw_Ex?nxQlJ~+'
    'yEuhW9~@H=N32O$+&aTB&;4~*%~{Q=Y7zn03!CCNC;*esNGwBE%bI19q%v7qLR<$#<vL5RmpTDfz5do='
    '2AP(dFF={MB}!B^7!-BVSW&_S=ChIlREs#q@$K#13Po_ofgD~c-%%HU*;pc@L0hk@laUYZ<yJTe+>ga5'
    'UTG?gV=@PckS>2I>HBzN`L?CwX&tUUpUt=9>OxM`Q<}^N&uVmR$&R*2{%y?PZJ>>+N(ecvQB#$(U1INA'
    '9_ohdURI2~_km3B0F;7nUMQ8au#3p*mEHO>e?61IyU*{{=?$%ud>dI%ZKiMg(urxhF9@2;Sqyi6kG831'
    'CH#eIuF3MP)F!D!=OxHbuo*<IVHnsB96NDhH!wo%(st^8VnmLCu@TvkV<H^dwj0<8d6sLqmPMTYfmQ^h'
    'L&ugMhOuW890xF#ZzpbOz_e}@*@U>U8%DnC$Bv1ygCoZZh)0uJJYs~Q?Iorhx|Gv<#g_ipyD=u$LZrSD'
    'seB@xm%q40BCj%YW!h%qhmmW?L1LiDAu+51S!Qfu%T9=g%-D}i!!csl@B+Y~7kRO1gm#SM$WE--jkIZ-'
    '1~HvD_PyA*9Mg*v)3uU-VA{UU4s6RcBg^y65WWrF0GR<w3_l=20Na)%v1>M`@KR~<Xv7!-0l9!SoIM{e'
    'c>>NQ;}RbRwar1~H~;oC8c$D!L8#@JG($4CIhEM$B!9Kkxi7M!2syqRdcIE#BQ$~Yz)OA-JDw4GR$xS-'
    'i((j&gbvWG?*t~Y9M?Bc64~zNNwEzntZQY)Hq!q(*{ltKWgE6#&&JXil^fqlcg5ny+aa(t!^Z})v27E_'
    'NGuC@Qxdoyiv580hBSeC0)l{^5(mdXXV`WE4^CeMR8hV0YWZbh$2wlF&|<{{LHb$qm6!Zue?S$cBY5Tm'
    'vmx}kA-T`=@``PvO}Y8l?2W<}{sOOyEu+C_mBiF7s3}BMqz2;Cml{xql`r-+4QrG!-qJ4aaLrvZV3c+>'
    'bwi%PcBzA$&1MT=O9;4^c=;>Col5Ve<n6|T*VV1CUjAw)ta6L|Robl&69?wT1ShfYc&6hLAB6!;Ax;p6'
    '>pzTLkEYAImV-PG_%HIYi336`6nB`v>Vin&B#sfmVu6#}76>0nOgzVhyV7-0n0UxASh}iV0njdRcn2U)'
    'a0n>#!%p&71LA``1H1_S2jm#v2O0pODT!j>T?vRz*ai&Qa1(j16OjNpA&y+)#1??&cwy_jZJ?Mi!Zrc!'
    '6~&0A>n0({(lJTGAW8@}qr^3^YnsH5unFJ7#fKumi-im`aWx6zwM@JV=A1iSg&gty@!B7+hd5r623sYD'
    '>vA-OFRWE<Ms{y%voY7L#VFO%QgOqIpyW=WKGX?t+rq4i>CTnST&D`AHUqPpBAoev`&J07$RBSX{a9aT'
    'prdF=ZC?1sFzyP(x{?DO#cys@d_Wh@SzUUdMRaGo6mhwrmp{LKb@B7X>uV8OQ;ZO3@V6DR!Kzrv;jZKC'
    '^XWzn+~G0hDz}aK-X>wWh1YlMROL0+@jc}$H-)8kl(fA04t2YhU1TY1<0%V#L!bHEHdVQ!0MHz6*A54*'
    'Anf+pRMlK$D<@YW8CUD`(n>vRy6|*&)@F;}(b_AQ-Xvl*#yVC>S(oGqr7@Ayt9pn<ww9=jE@L36#hb>)'
    'a?I0!2%7p^S*xcM30X@-TSi7|v$}IJfm#?_#0XX<zn5bMs|%}a5<^%RYrT-d#+3UGLJTW2=}RGprI<oJ'
    '!SM1k%~7qJ<i4&KQmS2AeF&s>Ni9PnwePMIBKd0}M)FrRNU|1P-3Lt;?#_G+r53SuF_pEzmt!oe^o91('
    'l|}Fc@rzhXE&M=hV+^-!7Hug^i&=`uj0PPFIJLXIQ=z}V<B-YxWWS0K%3swOO5LmVTxz43%HsYU?l#6!'
    'JKYvBm$l$`9fMg9{JJrjdX~9KjAnr*T83<Hy_#|er*=u3#ZWaWdfkP1)*@nqkk86%zVi^!W}#(^kkB^t'
    'xoL=Kzgmf@iWuF3^;JiZR;)1>QQBY(U00jv?;w#%YhP^8CU&Sy^w-V0(!sx85>{O)&Mg#PO^Q|>8avL|'
    '${RuJtGv{yZX0TD?G?8U^|tNQwg=GK`rYM;X(?_UooNe|X{Q>~Ln=)5`qH}U(&5fC(h7ytboptzHEf-('
    'R=3bDv)6RM@6xaFkgA$qQ`2U<)iI_n6t#!d(>hku9#Tu|R7vYdN83<E>s~|aPC<J({j6j4?7_6NT`Ffg'
    ')6F(f&32)gX%(}_P)WFb{n&>nAp1Bg4O`#7((qcvp&xNo;$g3l{?w{WvHiy{Q*3`nWr{bhIbAMb>{w4-'
    't6ag@{>BxI%c^i~?PBdl=jPgV?P7+<-eWCmT^j({b?xGv7bMnN_Nqz|i-*@OLcC5c>_gNZe)as_&+TI('
    'Iix$QI?RXPO}*ioAo@pAX_&A6o75Oisi3<W!$nf*yt;6!5<{))3O57?m!resAa7JrxJ6)fb1h+MlG~=1'
    'a4Bz46NO&F$~yIf0m$0=!IS9jcK!OnMUd909K7Lbx~v&o5R%(e@y#dqS61&W6%lAZc8l7;+NA3CGvpI-'
    'HmE>cciZl!_Hb*KxJF>Kyy$mUb+|Q8{Qm0=b6jpvX}Hq)`8a9}S8>J7Y7BEMZBSjf>cH*m3h(O*YwHS^'
    'm6+y=!ukujQr_C6mT;3!*QSavJ(4YhUwTpGc2Y-}SE}j0f-qw*n^h1lai;Dn2&b2A`*;+|+198XTrE0&'
    'UsZ!qjyBe)7hErK|D)Fn&QnxJm4a*SD<UqVs48n}1gC7}p^F65i8*}T)(2kO;_x8#fpt(dl?1IZbgW+)'
    'xS$^n3OZv`HDHw1H(R?7aAD>f&D5I}*Db)*SoOE0$f}@hTj`erQ&Ho$uut$jlYC`Oh7qT)bVjXS+zeTM'
    '$I=^~$x&(rh>ZW#W2&H(-wZZ{s{&(Xz_dnR0b8YYOAD(Kr%<t$n#JTxvE4M+6$J^hycmtiP9JtsDg^X6'
    'iaZOWaqIHV4d%yf3p?k)S)-(LC0LcwASK;loiffv<AJt-v#QI~)JaxM;_~tOG~%^+ysQme2*z($6SxK4'
    ')<NE?CU9<mX13YxK-W|oR^}Tt1hnTdd8*SLdU!^bDkG?~xYri<ZWqwsSy^v@soS#Nm1yj)ptso2w2HTC'
    'C*MTVZ1mZ#Tg7|h(^+6H9iGn)s&(&Hq>(6SFVeJzXKP;3hP+$K4ja}aZy9s4VKs6dAkwNFxxK4$<avWc'
    '>q6u;?6S55d7I9oO{o7!CUdel((vPp&+{3aTgJzh<IlYboW}*QX1Oe32xQ7RWy?r088SlQL#Jrw58lrS'
    '6Emn-bj8Gt*XWik=b)(8SP3<qx?5QKO17|;OtQZ4S4l4`N$)wGZLN;i<@Xf>jg!Vd3Doi}5M=cUO?hb7'
    'm%cRmpTE4m>Qfu)`T51UWUKUx9M0$$7r(rD^-eL#UlqR0UR6t5_rGSFQ!q8s2IG{gqvh&&j)4EOH6KSa'
    'e4iaFICx_?n9CKK#?-KgVH@ZRr*K?9Ot}S-nzZOI$1Ah|O+htn72cIkFy|H>h7y)?dvF8YEnyyu+~db%'
    'oO=r3Vh;lR9IGb>RUvHbIpLA#cmNz-%19Q)?XTN8t_#p12Biu3VDIUV%w!4c5eINY;5WWvjr2`})cCs$'
    'QyhMP>E$%Nmm8oeh<1fTdi1A1iQ%)p2Fy0boCBaV&sVHbNmW;aDhoHYL%FVLV1xo>`hFb5v1=m7al^#M'
    'k&7HcTsuxMGLRF*P8=nPi{k(#Ze*CIjcsE05446WIy8(K`ouJ`8QX^EhQu+k8{5PKc99safdZQ(kspSR'
    '>-w=7n0|z861YKP22ntW96Hz4pt|7oDaFQ1>L{d+l-WWpcP&QRrp-YHN@YEEKu8>rB(!V~@aG~UwxTeM'
    'LlSv0u_9Qcjgr{*5JC~gz5$qVLqBlc#IPL8)feJ-W8ZNtFL8|6acs*cu@_jbgNg4&*oke^BO!cr5i%1G'
    'IY#Ij7Of>~SY8+!uG8G+;CHl;MD+6fq<6Ji(2M&^kC#$D#tQ)HSUez(Ztv@QT@N;$g4GyTx30Ptei!`;'
    'N=*>Vzz1UV{V;J7$FTyyvjK;|!^n>aoQl};<2Vc~5*ZGLjmEZZ;KXuast{y=HJc!`>Q>OY|G{P_rLiGG'
    'D<HFdE7XSH45+To)_T>fJ0Ynps#$xX4QJX&Y~;FOU<a-r*ruIW9tOC8Efb79-!(nc_JcSuv2P`2WCTEn'
    'mf^)#(qT1gV8~Wt00^dK8zu@u+d_62l7MpUFfqc=gG<9jJ{%W=1OzxwVj0+ggA_Vu&`mY#$S@Fwd(ZS;'
    '&$KY`HrN3VHXy*j^58!d+D1%5Hx7M-y@&ucz^2)*haJFK+`3r2XAvWYE77-L!C??NksHPYRA2%hET9M5'
    'a<S_I2lhfl362EtFi@Ir;0U;MKS%sZ>GnPK@2UTrQNJY0R<+#QMhmZ9dwY}UVQua04WQc<aCKF;w}^D!'
    'sM5AB@VTbac5@u`jw)?eWpk`mRC~JwlJB;hc5`~eR)w^i!y~pXq}^%--%|<g>gejOif3=UD_yN(7iF`n'
    'LWB!h(VG>_?k1X9Uog8lwz-0U+vNFeRV2HG4@rx}H638BtCMwD1H0YQbd|1KM&dTrxJHvn-VvVGxMl>S'
    'mbg~!a1T`Ex-o3GgYwp;FxD;#ThD1@J-L3K_RPL&tb|P?I4L%yUxE$rC-(096Eej&gF!xImM(=%aTc3y'
    '^4N6t%Ai;c;RhO<*P@=}6(66mgV~hF#Wn=WHkQNueu{i=xX=yDdrM|C%F|cQyHZ=Ym?AbeNEySWpE;^)'
    '5mkP#^#)K!0W1ET=Pgwgu!RFkU!{{t^+h;#Q}etS1i!C#zDdaUW3F>v8ymi_aQ<j3oYzK$Z(G~Eoe<W#'
    'o_T%L_*#|BH;E$OsNT0Gs(b@L*N-ya0@&uV<cGTq*;<Dp8bY`>!1U%(>KkFaI%>U5_3(A0*!$%Rq@$qr'
    '`o(V+<i18R{OaJuM_mTLDk#2f0sL)(<TogN-zI2&E3$1{?!G>zexn<3%@X&`G51Y&+s<O}>yKV@O#W_<'
    '*)}oz+Li4jhQAHft{>B1Pl#Q__;1*LVKWm~e<!);J8QkLu8FIgrVDH3t=BeP*xa_dWz&TYlH9j$u+U^X'
    '{0C^Qu$HZ?-(52OzNx~-srY#>@k6vz*g9=L4{|Aq|1ot^SSQ7Qn<fgIcu&8569sKafb|NCuVV|^y(y?O'
    'OVF+jK^@tF9>NUNr4{HQjX>SmfF9BW)U5@ma|6&0?LRv(|8$|2KBgWUEp0y!VEWmO<!1+mpY`lM-I{$i'
    'v-&)g(PvAWPp4<ALyOOY8GLqP@7cMz=lkpF(%gOHA=+;|&L%JR_toU3rU%FO)c$4ID<qD#>IdWe@%zCz'
    'e}sN8Yj^u8H;9QM_o-`_JH$BOx<gFKuJ_10#BfCRzQ2}2f3W5;IuAu<^BDf{y3J$S7aVwi)-mnVj2Ohb'
    'YZ}9b-%-<;>TJEo(lmyx{+l$7X%6pOziCW?RJv~()28lh`=&AV$!}$qgB{?Fy2dmo2{w0)N&OESw~diK'
    'SPJW2rw2<BW#6C&OI|Q-)x{)Nd8E2aO0mL8`>|W}V5#YjQgfZ`raMaOv%gN}8$0~F?2gj*@c#k2qcB`<'
    '(jBELO5ss-M_D7Qk&8(iG(M>~OZ&zr`^G2w#wUVpt=0HMdka>}3>$SmX;4TCWe;`vm273}=T~mi_JkkX'
    'hPEdSZ9XcclbSXkRr!wxyUusy362LX6B={qsqFmm7<-nqgS<H-@t|!6;z2hVhX*^$FcddbKBe%WO$y<`'
    'HYtO-Y5V_ZJznxi@1(~|QwCo_r_F_l6;k#NHb~LismlH!U01aEc1;!ht1Sf^bY017goA>X*w}SN1Zi*5'
    'btOOZjb`c%8=d4~YVNvHR9#h2w(h#ZfT`%ZQsEyj7H@kb?KZf%t$n+Vdb`cm?KV_!)@ip<1y*&tjiSW5'
    'R=bUYHu|vbHr74d#V`+Xl3JGYZ>HO=+ikQBsHjXh&^N`%UyW@dD2iRlD!O8{%DCvPD+UFs<F*)8h<uo~'
    '7>%B#wOd?ldLjx3y2CTkL5qv^x39VF1Er<S`#!YuByZUFLAZTeHGXh**7zZ()wOT@P|XqQ8$YyY8Q+Ba'
    'T{V87r1A(mKeXc=^@S))vZ31fp)5DH>+~u+Ka}2A)HaIKed~vP>xakJ`hi<RfUz>`C_Vmg0G|L0n=XMC'
    'ZhJ5^{g>{PD(@X12u2X0CGngC#vzisY0T<EOD-{4+>MwqRX+W{lW_!$?dQ|Kb21z~|BvenS})i%ET{J;'
    '_7D5@0*L%2`z2t1UtV0FzI+WQ;qB>vyn1tbp1$Z9;x+m9!NI?!(;nTT&r8r5pD9BQ86(5bt``*jEQm$e'
    ')CKR!T+l#E^jUu9$6ScywqqKe0>sUJ_;atYoTAD77m9OXZod%D79Q)zoz>)XOb7;~t(KYe_k>QwHzmKP'
    '9O1`N;EFql;`Epj2wdb#?uiWtgH7-t2T4&Ooeg<($ZxeMNq<}mEobS>onS`T(IhP5D%HBTasdaId?0!!'
    '!Xf)Grhc{w$Rm>{Q!2AiOh2Ww1TG(piYBu}71?tQ(<|wxh>B}?N?_szgD#7Mp=h|hTf&Q^I8Q$n_*>E9'
    'dgP<LqB$P|qa4o#jOK|3aB<F_QlaN4<a9%Wp=Nhf3|*n|lwy>Qnv%mD-7}$~gj6jRwnl8aef79i0D0Cs'
    'sw6PE2i3%{>4HJMb2Vo!w*_pIGQ1pRZ_%xwGmOqo&wjdKzDUpxe*XC-Gf}!u;u`^pEYCpLGGd$<N#xnC'
    '8^;bo1V^Fg8)k_5>KMB2JFwe^MI6)g9m};010`1IIVgyt#E6h>+kxlDF^L=t(LM&)z#hR4GU5b&GK|vr'
    'r7j*DmG$=>Y++>h#B>wiAyI7lgmx)FX5s|cv5Dszfo%{>|MkNJxv}HBCdP3B&xU3vwe$lUTX4B1W@wp?'
    '=~zMH*@+QYL5OjHDI{SCxDH7aV8bD<;W&=v$G+h?ZV*Pe%iaPZPKXm@oZ!$5Jqva$h>7LJp5=KS?WRBs'
    ';$Yi#{FoSln<N%-VT&T$_2K|W%}p&*{pOg;^K?!?JBbt5j8Niww&g@&;(NB?<0ME>;?YhA$VDL{enR8k'
    'ZOcG5GNK5U?>q2c>qZ(zNC<6!5CZMFfs;6iX&8>-BA_#nN>E~$1Y--<6UW##9Um42yMjE^w~Pn}An__h'
    'DCBI}ui)s2)jeql=n&!8yez*e{|wm)<-Z;l0wdZ*M!>r~KH+f9;E43aelb3x6d>_y8X@s(|KwMFj0B9O'
    'EV3N%#1>YFY309Am__)Gf{3E&B@6hh%+crZtZ6n=5s<7{!1cw?Z(qS5qc<;JTwPqB+#G{Su~_l=S^;P&'
    '?lu=DG0=kw$GZkT#V^1|$wA6M=qYhT1t=BlCUD;^Kf<%={r#k;M4>28W`Qa^-0A%Zo8~56h-S}(!kWD*'
    'd{n1zuR)H^g*oN((<*XvCI6H7fJ=Khrim;}k4Uj2P?N(6RUHN396dj<b@DAb5oq9RXH;~PTRLV6YNn0S'
    '(YQLQS+&$TYn07Q%hV~WOsOm>tjbKOrdb|Uug0?BHILA~WFmw0uw{^u?5LIBqKjfoSSr=bKx&oNAC`)N'
    '*ovvgBDX<V4476~WzeemtGOfu1rcJLA)JE6U|0v4glYxHjDePeM;eWaa!;iMHqeklgQzQvM<DFx{O)oI'
    'y0f6>Rb>1@5fTfmLavF8lD+wCv*5BqbXkEC+QgS_9AHMLW}Cyq%rr!ho^5fQStW;b$x0XpXBVX~Moym5'
    'WETHcVEjw~R>LpZ#_<%w_ILLFR^H#r`&)T`EAMaR?Qi8evrl@x=x$`K1&*&^e+PeucQ6e!;)=5fs%+Ci'
    'FW)#%&Hv?g<mu!-%Z19~;ueJ7h09{VK~^EO*ep+^@z!_CD?OBJm)EXKUTmSHs!yI$ZW9h{yco|}QIe)6'
    'dBx=jFI5TJYB=+QY`ba=NZBx1J~c3;;uzKGV&d)Br@tu4VhUB~vU2+W?+z9)PVSFC)1yJ_yF3*|UXJI{'
    'XZn$5eH^Ye_1ovvvBYx1TR^Z*$J2EoDJ9J*Sj<6@?p&@C*V;(W7r$wkGfUUgPa^}WwOM;rgXVJg3gfQV'
    '%uY?pZ&#FY-A;CVfmN;S${5)ot&cB7IhPfyV0dCnp;5<G$W@d4if5YfBC%!KM8Cod9TZzl2R&?^_9swY'
    '$op%=cAEXCV6ra#uL^<rB)|ejDlNbLZIT5`ytkM#*l>TW-H7n8i0p<2gayninTC}NK;#V;mX?XN4HlYg'
    'mb{s!KulX|^;>E7-D>xTJ5EpJ(kokel?c02F;>hx_*Ij!sOmj5Z?VWRnz9#DCS6QlR2Eo~#8@E?sacFn'
    '#;Z?WEDOvqerBfHOUQc(c`qUFCFH$?yqA#w=o0c?{%t4!wl27_mw5LQ@Ao3{W=7%G@|;%g)uie9(fVb-'
    '^rCO^O01TD^-pdf1OxERB5*_1_Ilx059)>za0lz&rq-EWp4JxNY%klDUT+rd)K}DcXdBJhT8M2DDAkko'
    't)$AV%z5|nq_VyT5GolG))A67lq}nnS$h<+rHcNI1<WEszbiZJVYM7u$)eYjKqao(Rjnd?V==UzDeP^r'
    'd&%^nB-1?mUSB+|lRfmc<v_TqlvUYUir1~qM7x()_wwpqUfs*9dwF#)uRbcP=s%t`y0?t(<<EZ<`7<+^'
    'wveXUik`A3-1eepv8SR==q&YJTwmM-fLn;0&2^Ki#m$PA@#_kjTdlQw5wp<0s=c6BXc$>9;Fa17uRBj`'
    'QBvD#cHP-J_1^PS`OU=EHM)(jE4Ip}OS=|W8%6J}o%Y|2s9NkQyQYv@*<1AcHK$gw^eqHf*+X?h(Y5Np'
    '?@g$C5%!@(*m6I-w!*7kJ{eYZS>GzCbuX~)1=hX5x))gY0_$F2eQ<$wFOKeQsCxnQA5s8SOr|aR$+nb0'
    'H|i=|BfS;7w{0lB>HExnGwH3+bGE&lqw73dDN~jD&#pO7XP)c2j<gRTOEveo+FX{Z>{8pYEY&0r{sYNU'
    'x@NX($WpCZ+I~;Qzb@P0*2_@!&2aZ7y}d-Wdx@%|zitbOs;e%$twSOAV%1)(+KW|tv1%_?Jw6lFqZgX?'
    'hNr!l^oJIc1_QN~L^|z@mwyKq@{TcShql<d{zw3$cUfg()*%a4z3icA_B-$U$=A!vEAv9E%N6Z@D0_oa'
    'ndu$|OOG*t{sc|&6M`0#F}%Z<aol@*Cz_j5)r5*uyfYZgg=wYReEYxS0}gh2N(B6}Ax7P=KlI+S<}_dW'
    '5dnfB{gWR50H|hNmEjBaZ`M;z{?5Lp^i|P{<NZl3Vs8#^MC&2O?Ra;q3Nb?I>XbEE)ySu52Q<++J-QbT'
    'URp#Io?On+G;2R3_K7j6>9$SOICbS2Pm%AWY=_p&(J`IrVO^iXs-Etp*2V>pGohT5SE1{6CIoSW6l#yB'
    'b-iUlZ>1GtejafK8RF35K5L;2uMK-6ac3_<@Rn22%eb1Z7KDke_^5)wl%|6Dcb|#Bl}n%fkp5ljDawHq'
    'XkgE#l1aYMZehu?+bkt4rL!m>4&V^uN;!p%JWQb#i%$jK%J%dv1>OGPLFJ-y0<K(BVKqv>dIpqO5x@8f'
    'OOXO@EzH%OsEUA7WTe;5LCwXWZ9errm7j7~M0%F96HwhH7bXz=NMT2HTJx~?Cw-UbI}CayYXhC<DC#}P'
    'bWKjJ3BdEQTmvp;Q~F-4=_ZRv87*D_8P5ysOM!tbV>GATkZA*10P%@9z<5U4k!+h*XtPUYmgb(X{MCH%'
    'x}$Q(-tuxpb6+_HySR%Yv7}znh&!rYq1u>LtI-}5blJw6=%8MeJy=(XUGr$SP+lv}cB;i@=Xxv6b%XPL'
    'P^+;XY@&D;^v+c6Jg8SV+2tmb#$2^}!E8#MudDI8xSLMl5YNZcTCAoTs-A!4j?zs|SuJC&qCd8#JF^xQ'
    'xn|^aJjToN#rO-0)HKg#-GxPWUNxX1r$Y~Or=!pWxV|}jvCX>Zz?*K7<PfZFZy{zw)1k3fxq*`LiW#e#'
    '0j~vR#V)g73q+FJje}IvI@reSa8P4#5NNA5I8>mi++iRmOt!EZ)H7FMPsj`k2O3jCD@%e9#Md+-C~tKk'
    '!tc;vkZ)UYu&$9{)1DP&>%jVAT1kmdWuyAYk&>JywY60B^P>bFpcPU<bmEr$7zmrjy+~a-*YX<F(Cc>q'
    '*yV+c)s!@p@45=(25t~rw(UDnU<9#;L))@FKM6e&`q&6bi2X3^H;j0Fd2vC<3!TKVkr`S>=ovnC3_EiC'
    '#Evn-$cz(&lQ0fZgmmL+nz@>8XeW+uk~p+&7o#vS;*j_jj!et&%*3#LMBqP|G9gZ67;)g(X5x5`313Eb'
    ')imAobai9jN<56+D8LcyvSZpLv|ZEkE!zFl18mwp1^@%owuuvjjz_TVxx{oF%MJZbdb+}JcH+j7?M5W<'
    '0~7$U1Sp9d+w}?TZGgil^5H9D+t^7$7kd$M4Tk{oOpN^wd%Aj_69dUa1_?~h^8!CMqSy#b2ZgbP0>gC8'
    '0ApfC#P&i9$8HG!xju4jY-7tp8})Qe%oqmnkVU-2ieSP3`92B*CyXQF05Q99>>2@aoR}n$VS6@mfuvm='
    'xe)-=x~FRx5rQ2Dc`=3~fgK!qF7kmEO%htZVa2hZ1RiZGY=l6X5l(F1_Y>qrrf)}~+y7d9gbJ-)#mOFV'
    '-yNmD*@|6kOeLGJVy~HArr7;fi~FKke>9~3QMA!MNpQ8w4V@z<0x}h1d6W)XDsEcT&I-R%P6c4n{?yW<'
    'G$9{Qd@uRZviBPybE+?n7g?)vI7wsRZ(J2SE{#d8kwX2E@(Tlm%C*!;iSA&$>1rIaMsR#7=^_!eL<;|B'
    'acH>i=s+M8EN7G7g;dNImti3L@kBCZF?4w_SjSO*zyZB(QY`ZYFVlhOvlZoI>D^GFdJ>9a5MM+iu*&Dg'
    '%hB@wb~2v+cBE}g$8Jw)-MSrrrbadC1Qxf6pg9I;$>+j11}>T>L~c46fA}c9<IDRgYzyp4dMAOz&2R^s'
    '%q#{|@~O1fu!m?e`|$JwYmLY321{6|tjC@f`4oWi37M|<VKKX#mx<>M$R#Q9aRW7MM-0cex0*39?xtz~'
    'Jx+&Ilv%DQ0QA_CMTu-cVz{Ntg&SjjlBw@`>5_>XbGrX$mlvlrvQ(aU)?WRJ5{&Yy+|{o|PaOF)5=h}~'
    '08d}N`77IDI&=z(k}4#>d#^rxGf11moxQufym);r+0Esff4|B<`kouZQ$fG5?-U}oJ<rmWU7r3s@BG&e'
    'F5O!SfERxUG8RqfIds|=8o&hfs<@*XoB;epa~M+Pfn<O(i0Bvk4W#<R%V`}+%45X*KY|EL$4Kgz+|<T8'
    'nJEZ79)k)3WN}h)fOY(W+mUj|zt_LwpXu1eQ(l0qat;O?RjUdtvdVPzvzDib*{HxPy22G5R(X|z9Wlwx'
    '*FI%mHRB5II}%saNDO{7l2@$&QU0(T>Nxw5!Y3<oOL^=Gl@6bXae^nM&DJx1@;N4R*uT7UaoBrvB|iL('
    '+>1}w_j4jXzMGDz=ED9OP&P^Er*c(z>bCraYTVpqNteQ&gv$wZ)?5Bs7D3giyuq~;8kYlFAs%J%M@3wV'
    '8M5IkWstoLvzKA^GR$6v*~>6{8D=lT>}425h8YY88nen@Ujm=Fh9f78Dz@!Jq3ydCvAigD62ov4ACcH5'
    'ZWP-I3PNPMq2qIr$Oz$i%L^kEW5f558{^2q$gq)%kr_E8HcZze%v?oBKb_B?UJI|mDO~DsUrs;#Jf4zY'
    '#^lrS^3yn3^|{Zc9|Tr}<HV0#$McDixIT`pAhyiNCVp%O#I~Z)^%5sGLuC1;jZ7Q_k!=zujsllw6H+_)'
    '*=#||lU{u!lSIx43-Lqb2XPpqzzP#Tj1t>TlEfg99fvq}eK$fFW8bzdL@a|Cp#^Y6$g+@w+{8;~<K{tF'
    'Cv4t|{~_mQQ(gjTQ=9i}Ii_^Lp2#m88^}*gJMj|FOK@U^*us%#8`wo8iQOdhP16o769X1P--oXaV#2qf'
    'ZCbWvIR#L3mP+Zk0nQ2_af4;F7~>CwTJQuMBq3IW0_3}{<Jw8!g`R^F$BbPYa1%KuiXz{!Z0usww_O9k'
    '#z{az*RX8IkE{|L3zEl2x)(oPU%%BLB6MK_mqY}42-%VE*`^aXw&U3`0*VMJc##*_o@WJ=*1|9{<0yjN'
    'H(l5+)E^9ZMyZDgkgwxLwr^t$G>T&fAO>>vu@OfeA)yrz-w<McY`VT3yN(n1F;JgjMMhvpMv{akwow=u'
    'mP=w3Za~v8fED|W;lie3EA$Q53t|)}G4=w-2t6~1Jz`-Kdodg$!^bF&6CBw%4ouI%{(3ZR!+G#v(WaZ2'
    'zG=~;>|r=QzLyw@pIDKJkYSR*F<~M&ONnE{`7(@{?mP+24r$uAO%nsNKwg+wR%jYdkc5d5n5IDz)3IPr'
    'g1{k|n0`R%3J$tq`>`3h2C_Wg?uw>k7%OyO=V3D2wGGdR9LutRS&=Y;#UsbJZ~%ZAQ54u_9AlpnIUF>U'
    '022(hrfJ_ZfSC{i=LjcG0`wS!1i7YTC)l&X*b8uAB?&QOD}<#Rwqba-Z^HKu2?+60nue2+_^uOrz_n1~'
    'n#cp93_{0>JmdjYTQ&&-9}`Z~9&ia@j0g^p2Yf5^3APdwPK=9U*9;v3gc!lzZ$Q(AZ+I@8Ov5+f{9$bS'
    'fXKv!LukeZ^5TRfuq=-xl&2xX!<5lRo@YA<@ERoR(KHGz4`{@q$Iyhq9p8x}7}AOWS1#Z%i6Z1h39KuO'
    'B3PA`1a3@eJBlK>BhuL}3HLKDpT3&K)G3Ri2|4~8Qw?GIVM*r-64$i=adrZ*1|Gd<Y~P3-(?mw#c_9WS'
    '=r{)4hlw58lwPrCyDqRT2Y5y3?$1y2`DuiMsc9q8@>2NEBsaAXY=s%n@ngq<W8+7O@4-1j1Wt<$qJV+n'
    'ehk6{=-<Vm8Ilk=rfryk0aw5yILr+Iy!kX`1ad`@@HWMP29yZ6c^HCx68VPXV!#L{VNCoeHV7;^GL0yq'
    'uIt!~!WfnhtUkex>B4OY*Jj|Se5JLQoAH&_KI}bT$@ofWm=SW3Z=uNYogjwG*$He6<m)@IK{m1tU_5Xm'
    'gX#j}t`);xgh0}!kys#q2YbG<TfRauf$Z3H93K=6*94Xi2LSNkgNz72gbqa+P@)YwN)UnM6cW>NTmy6!'
    '(2d+ZU&-^8!NGwjL_m=)Gd<Qdeyis7EW-K?H6Ze#dN3@{?GR&T#>9e&I!#%|x8qfBHYLXgY`inY_PiVx'
    'tj?LK;BI=iq^4?W)qp?8nT3ev08HsJ$dV06ZDV)S7*u{V<~<B(?r>@zP0i!!09kZ;{E=G9dlxKCNF)+W'
    '#<%eJ;=XrFZX*i+l*i_=k$dAMk01Y$W(9pDXtMf91E}sMEBX_kmf&NFIT;DPx}S3t4`ePjH6RT6_sk9i'
    'J4lUd><h&vRQ>eHLEaj|QyVC)(P-Y)9jx^TkK@%5`|iDU!;L)LA`3&-St&%42!Ju<hBz3J2NzO19-rjB'
    'aWfc}zlC|&%d&a(n1S<!yAzJlazq*B|KHx#^rj62(Yt?zQ4VobVh+6_<r1}2oGKCZ6h#POQxL{R7)tZ+'
    'J0H92UGI7U3)+C%OB!tN&g{G$4>R*NzeUDLHnj2_oW3J)z-Oc<cboEurK`=9+H~oWj;J}@$M+9Rp2BKS'
    '&{%T`s^oTtvZL*%;DphNl$;970tsY!Si&ZL+`#uWoM(ZB7ES_|R25OsivvApTJT1UU&h0iFT)Y1y=bE7'
    'AqG#mDw5P{&{cNiUr7w=Y&LRc`aIQ5o{~#QcHczuW_LNoC(Am`6L6(qZ+HR|d1;z=MKx(`n)($df9q1l'
    '_rd(3hTG3EuPX*MCsu#-94Rn-L%c55k=Y%57yihz#S%6pHl_7Y^LRhWmf$G1=?2CKlLDk6E9}<9>I=&$'
    'Y-PAYiMlclT$y8B7$re0#)@ioVuJSyGxzumtaHY6?`^@*(qJAq04q_Ci`aMePS;jnHOj&R@gzwiyIq?2'
    'bpR<TQw?b@F${P*;8>SfxFXHk?)yCokh``(<55Y&UOZXj|DvivRsTl~`%0tH*Ka3iMBb;BF0>mw;+w7I'
    'CV)jH0XEZMIQWju=F?@$)z~EcwV>u)^hOOn#v>u9M}n!Bhvvu+xg07{B;%93H&52admrt}#dU|n={z~5'
    '_Nuu^(2;M2awuj02%3YfGs`B+4yw#hRSCM`Xa_T`M0KIBy>lq0(!&kJbx+1N?>&k(*j0tINtQt@vnh5z'
    '=P{LwWl*CHxWMRU1y55)a9Hf~QZxw6DEwhD@e)Ez9wQ_A!1>6P*cDRXvghxSzGhD%iZJ2{e*e3}5`{>3'
    '6v3$7RIjUuau<xet9b47Z2|^l>Yn7i?(!r{E4G;?qFIPl0++9!-^@z}O0YLy8^T#Ft&Qa_!S<c39d~8T'
    '1S+VZiNNfZjy@xOWV@86W%N`Hb<$14<3`x+vIrZ$ZjazDd@kT!T4YIDo!u&-CMdjmjIKAa2sSg~3~-9v'
    'eTF8%9*+VNUq7TqQ`{RAdanwMgP7|pN6nIOK0&spz;^?)*<=tIS3ZUQF6qB=7J!?teLyfp_m_28#n<q%'
    '{+%rSw!Dvz#L^e?Ju2}pN7T2cx)@jA4}yO|*|(Lya@M}B(AkOm2gygR`TIV;Q3H+N*zBiK`E6IzhS4ui'
    '9Z7B9Bli);WalUK`xXmUXkY>12I>7XuaYM-{EvP4To2LTwLll(`nPfkw?X;0SNK%czt`)1H1fZ#?oILk'
    '9qL`;2mr6iuj(WKd%@0d7{D=p`2U#zH+3d}cSkgz@27=X#~u&RY@onlpWqKVg8f1'
)
# CATEGORY_ROAM_FROZEN_SOURCE_END

if __name__ == '__main__':
    unittest.main()
