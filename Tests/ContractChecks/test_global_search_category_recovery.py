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
    'h_!~!kW%W5$VfLd+ZgDMM|))8XambJ`j$SVmfa^kyXV-Z?)AN%IUHG@tLuHEM|zf<s}=X^`1_a7(42np'
    '^y%3#jy~w?Lv8Qz>(kTY=daFhSvzL$hT<`MH&>6@t6M&1uSWfty=@D~?A@Y*%-$_a$n0%WLuOA-5t+U9'
    'Rb=)yD<iXaV;z~j4GPKZ-L8_%-t9}t?5(XOv$uUQnf1>mg-t-ofm~riC~rL^1LPACn8h8=3r~oX-Kwwi'
    'DXxF!?cVV}cy)RNM#Rh4ukeE28H=pcn)bLV{5CR(t`mJ|nNH6!O~dmn+p`Alz#tS$vh{STxt7}>j=TZ('
    'C>ZG@IwGdt)39ilW46|$%5D5w3jKM8F(N%jH%)8Q2cf4qrqLS=ho(g>4L%r|t~ToR?O|^?G={c4>W`>y'
    'n0+h>sP{*GIkQT`j=8(Et+U^pJbeYC`Ro;LNlOBp%Gdr9d%Y4n{Nh7!hI@R5Tl_NJ;XJ$j80<GSuU0-W'
    'N%q*eqDd@mWt^PUHV3j)i;1Piqz94ts!UC<o4Iq$9!po9+C+^3&bc4ls%m<bk+?g6(1d^3ZE$@P0{-W?'
    '$we^(6pc%Emj;Ljt8RU4bI-SFz>RYUuILS0-Z;0o32AoM7{Jck9|I|3d`ZvjPKw`CA>N=2-@ORG4-&jA'
    'z#D{APTk_iXH7#)BW;aA*{WwsW3x$`u?QnQIXGrP&K;n-X_l#6SG#F*qqQ9DY)*@`id_^M-n1PVY`e7A'
    'c5kjVZmr#wv9=3a?M_U!oTYaC_WG7#k;-typy!&Sp*J%0p=o=rXY}AtbL0$$y`E_i*Xdh>0kwKVYv?$-'
    '*QdjQHPY<C&>D?ggZ8$t7?*+%uHDx(&#?wt-!(i}H|S_+o3>`+A3F7np*b-7dVk<*)EvNU2g4!7poB4m'
    'sc3YYIaG!kq*0{AkxEVbX7ggiNkk3Xe<6+NT7|xUvIb=wS<xR*;_$h8p4W0mW;gWksvhRT9zQ)jKKqUb'
    '3eU!MeWuJqk~L*{1MQmhnxMRvWJ~%k?dGzTEM)sRqD?Bk1fy2LVT>zn!|~?TdA|9f{6)x@HjN3J4P;G)'
    '*5BlGqf+(TgpB&G**AL{(MO&^EXTAA*Kv)(NbhU<$QtODXZGE`X7&1nuohp2LyVEtb9+5!Tfw)a|B2%e'
    '(ld1jG`-d%gQ00T`iN5OT4LGu$khh+u&28{O>=b8$Cf&}<zfpa*RuzGy7fewH3FIl{j{<x`)R_>oP6K}'
    'F4>YVkYlm3wNx<4>H67sN4b`d(pMq^ImrcLQO{Z`7*>a=cmY}YDyvN;c~$%QKlru0EcK_IR_4US9+`p7'
    'eI{KL7Q*1gFxj%PuW4;4@~xo;m~e+YDBF6uAECcp*fF~|W*W6<b|{dWm&dyi$GerrcO#5f%i`<W!Z>de'
    'CGWA!Kg@iQe1_LrR~50-kTJm17+v?VDASlOE-BpDDB!$%l0g>R*Bsa^pZ*iV8aEO`uVB4`Un3P3V*yp<'
    'fQzOqO=56DFNkxMR!qzxwW*EEqmHjuq`D{9z8ZpCTJjs5!&}*$&li;3M&h0;rx~v0<O0j>7GF+BO437S'
    'w>B&(cPJ?DN>1L5m~8CS{oY#JB7)W6-etN*CWsa5V0uihEnlHonk4mIDV96ZE4x%HyVNQxlu9!Oc#1z!'
    'UilrpdYhEiYS0S67rSjHUmLHyx|YkOPi`2WSKgLu%lEWP#F|GocyJAZk~(lWaS!vi;w$7?Qn=>r8~tro'
    'C2H*#wcHo=ouM7p(jX}5w7p-rj11@x0&Gp&DwS()b#wKnG0L+4S#j|Gii_nL8+X&Dqf%EU<iG<a2YC1+'
    'sgg66yTZzQSuM6zO}Gs^lkbfa$32$ryA$pONLbs5-TFQ(^|(EdiTC{!%%+vi-X7i{@1=^Rrqms-`!L_A'
    'J;g(}qE~y`s{NO(9}At@n_Fw6>a0<1b`O+U<KpU$RN2ln**Zlg*Hw{hru|HL{Ot8NY3odWKlhvCZ%>{#'
    'kXey7f|$)I)*ncN3~}0vtC1v&rJ5>IL9mrL3s}jN&d<|g64_;U)?)>})WFgj$iimpNqzfrI4IkxT@d2&'
    '^Cyx6$a2-fj=1M;nCGXJ9U*F0P}aOzJ|0=WxMm}@g%vP@5S4}+qKc*@>KzHxhUDp;h|_h_^!n}f_1@#t'
    '<0JUw{OQR*c=h`9Sfs#WAum>QCArpnw1_W5tdR1(AJD4WJ4;_=w}6+bq`;W313xa_8D?L_nmw$hOXQa?'
    '4Bx7*2|o;<`|br@RhVaKuHU_S^|B1`HicrgF1AwR7IjAyQh9mAlZZssa0$g!u-E3TuRK*fv{}Y<{ru>R'
    'icgPz!|SxNa`%TdcPJh9>=lmr-SM-RqL%;;eGBxY10`&T_wy?U+5}~L`JRyL7rAi>roDXs$jV8r?nku8'
    'iUV$l_R5k-dxD5xogN?K<9&1J^evA%Ba6_%$h6%aH8da-eE>V&@97pX^$|7F2P;}X_C}gP2Br;<5wB<U'
    '28KtCzHZw+dtmFt@N}094bvu;p*!#`&v1ISXHrksw1Mrp>DURjv!QjOS=PuVgTX)_5S!AzW{(IRT8`6m'
    'HE%$i9vSp4lZ-5#ke<<Vb<?w4%j`QnYtYYzPHIGFLl3=v-*Ee+=k-i7960)j^eoLWb$~e>3`VYJo2ChT'
    '()W6HPwQEZJLvWMqrPo=-e}ZMhfel08=CaJzT=wSaA0Ykt!t*%C$`n|Y@!oK?^~Ki9BK}T<_ujID<l~@'
    'HAb}Wl9A>BtR;k;zW7ab<@4J3K|xZ!yfCyZV!?8IBNwLSda!klPN_cBY+`8CGJ4j?@(kEb+H<KxhFF+x'
    'Fo4aco@R{L1<LA+2+W2_yVFiX=UrOW9D@a`_3;`Xg5A<i@+q>CeQ9rM(eO8VW4zsNd~^gbve{0$Vs&{+'
    ';u_1J-=~>T2j;~Wh}9()u|HAq-E+hPpDETkXV;_oA+E?=OCT+$@?>7swzyoqR2i7ue{yp6_{9&$AbEul'
    'FV!~u%kmd~wYo~lnyKD?Q)KQ*F}$={sOTmVI|suX!({Qfy@--JfzuhQQk^t7O@0ww{%*Qgm?n!KZgORe'
    'eLIDaTm#@yWcTo#c?i6vb2?LA^dWub1^_IfI2kV=*G>mWV%Qb&?W(Z$D%RMB_M6#)%yZky2hUnQc=<_)'
    'O3AC4u&|R^+sMjMN-OFrtpp3L)kg=nqO7I~OFCVxW^d-<Jvli&e$0$ZA>uO4zl!o(pgRX1))*Y<)a#Fi'
    'l%T@Y4612EebgJ;ebBRnTEl@xdbH;e*Ba2iqj^Ll2AJP#N;%yqSQvscmwsDm!q5zM@{G0X%Jx00xO-y|'
    '0WHuq3&DS~3ltpG@@<E8dvMeA8QCsfWq2LT>3i_BsjDPCv3RXsv06rrt#uM-JGy9+EN&8Ya){!ylyA87'
    'HL|T~I&YNBrBHbz=1uBqGbg*2N%J%1)g?{a8F-7yBu@>zeIGW7&VrZI&|OTZ0`{vy7V#xK#(Ul<_SKEB'
    'uz<HiCKDJm>9HCB+xx)<eB?*DdJ+%9U~<JPf2+!K?8M62|MIUP>eUTwwekgj=|+x}jrcqnpRfETyJk1!'
    'wM*(+NnFivdN{SgdUns3Hip&Vr>;0C*_`3`_xE{`{bcBLcOLvoNu`<qhZXj-{R$YOlCNhH8iw408Q0ks'
    'X(!Y4=I4!7-HR8>n(%03?uA^QPmW_YVfk#1Id(4&kXr|Gx>)v2tiEHyx+PsnBdgVHo;!dO=Vk8poS&<#'
    'wA}1q8>as*9Z<o(=&U{}>#8xiI^dF1pkFisQn2Hf62(4<Y~Hjk!W>23d29og&#W?bK8V#(U!0zNd-D9~'
    '+4<@5(UX(s$7g3ZyBg&poH*DTO@5m_xPjkg?Z9Wm>f*BvIDL22B$1d_(9-qW>$Hc9$Z}0PJgjNpQdu?0'
    'u{4j;o<;E($2O@!>7Z|Fx@L}ghOJwD_*8en=cKNt_jFVDsACTu+o1!;a_A;ila|gH`rg1A*;Y>n2z}eb'
    '%173ajLgx%q{QwIZC!VIR<GB0ZDP52UgC^Q&D8tmz#xt_+yrLj5d?nnH9PDD>hj;?&-Y}mc&t$kpf8WO'
    'zgo~*cTiUW6P)AI2qyO==^K>vpTUb`Z{9Wq^y(=Aj>5)t9)`c9g8>P)n8f1(9#7eO(Ie@=K;<szSUF>f'
    '0`iB)0|qq2o5B?cRR29?R5o5FJo)R1=!De?`L!RoMS%ED1Mn`x4-szx6*Y!LA^(AsI2km=J_5{BezM=#'
    'YM9D7RMMtYj1s=ZKBkR{AvXN3V9w?gPZ8ZS?6@~pUcWwhQj_kI(I+%cHt8(p9S^e(cbHcs`d!soRK1zv'
    '`t8sKQjNkXRZuM}pXv>XuQO*JPA0NO!`Bb6Z_c|mnfMpM6l|ffqE2|9x2_V+hy%Zju|J_Kc*0sLvDl|='
    'QvzGBu&()jl<dAL27Voo_b@hQm+f~{4@}y&>W~>)toSEbuyZ_xI*YF+w5>)I>}HqDuR2@L<60_uxVftO'
    '(F@N*`xP8ljN(efQ^*JY?2z*vqgR>Kh%dy>Q=d-UJc`)0<4f=Y=zPD+3czoDr=|6CZggVT`w!vV?Wj21'
    '3A#8(ix?!<%#T?%B+ErmS-hbmcZv8?qlG>7<7dRC6Wmx_X-5r%Gxj!6*DDget3hPs1A$@qxb2Q|tz64r'
    '!?xq8#Bsnw_HBRS$5$tKNbGw)o#%I4?9RSq)PJ*xWAKzem5ro$zMz1l32w)@2HN?4=GMW9Edr{IuA-Pu'
    'PcUVDd*a<kNul;sOzZtUNDDH-Mj0TZB9I?!k8gE_q!<m^k%M*@{@HHav(?^NOfbwTJhH8CN3@FWU13o9'
    '`{74F_`swS+7w#k_>m2}kvsP4cHz|R#;4njOLqre)=f^<iw^;vj}^S{!G5hr3%hf)T2kg2fhu+4Z1rOW'
    'Tdv1w{%>z8rn(%lz%BBVCu8LWyGWiH5K@MZG9OvWc!i_svGPqAPNa;RTvL!T=(Uu+=emw8ae#!4SN*_`'
    '+pD);eAMYC`?n=L;qI|Py0vG`UnL4iJ<6l}``yBZ)|<T_Jx<5!+#9+;GX+nynD@3Es1_f6uC$_*_H*Sv'
    'OCqZL9_L_XZ+4a6@ent+;qQ_Tq=w+6M&NcFfNL=Rc2B}@t!tUMksW-y%h;Pl%+!s%-9_N7^$oa1z(MT`'
    '8e@c|7==@=fyL<dgTu4G7V*4B1A2E9&yyI=lN`<4O)&2cVtEaR@-~R%-Kv_>x*D%JT!=*_H-1!CgxS;>'
    'Z$IyEUC*{vK*>H!r}E~oEU^}eAzam)lPPUa{op(5UtHEW2{6shYU*7^5vC_y$qYz?g8Qn%aD#11J^K?3'
    'k+p$;YJ`k43J$_J10#25=p>@Jpd{+HeF**KJiGvBAwt70&wgTLRMngS$j9IKZhW~tX24JI&{eqVY$C)`'
    '_>G_q9C{WGU9tJ>vre5uN3MRB^+;2z;r<?goQwE0|0y4PApaK^nD7VcJ(4y0wK^j%Ggl<=yM#HZWHx(F'
    '-uoBKig|^?I!~KidUxs_|Lj&}G@>yYRTw+g7k8pA8qpRj_*UvBOHe&K(>%LZJS$PwtlDWp>#SQ!6p$G>'
    '1KT$WX_ZcD)nvrBAB>A3%#LIN##f>$6R4_qqnn-}<Jn@gy_cMgn;TB9S9YCR0beBy`HNo&B0D@(0)MhS'
    'IZ09U%eqd=ND?fDmb@8lY%fT2G6CS^iaX)$0Qp0bA$C8^uNVYb+s^{+Eau-yMVmPKZA-Ck)iB^)9^0We'
    'F2%_Z<at*~qGo=8jJ9=-Se6L?C=JAYb(oI+3C2%q>dVR@gT+1ZBOn%_MF4<_*J>Wh)+Ov)`4j)rkfl_R'
    'y6dR<_}6G(e6#Q|s9MbN$i$oEWM!1bNr62-I-btrD>keoZ$TRGx8%xY339Z+`0OxSD%a=v;wWK?eBu=k'
    'X37{o&vr|xT?euZCWizLoxG$x)(^b5hAp=QDUF*YoNVrlmv3ZcX^MP@G1kl=!3L0Xk-@Zoe@q8_Jq_o_'
    '1pF3(^sa)^;Kv_T?DK%KAk)S20$b_PM(LC+)y)S=!L`~tYM*z>N)aCcsdU=0?@U7H-7cc~Ksooygp{N!'
    'cNdY8&0Ug}^KN)+HEU%@#tEr+q;S=pFjezB)qrUxMP=Q+gV=;S;4K0t4F{boto_vXO1R=ycn3?ZNcS<='
    'JXLh+cxb6$p-2$rOK0+6f5$#7&A$jv0(qBg7&nTPATJE#AdIQRgWo1EPF*a(>_lT*)^X5XyI~C&=rXyh'
    'in*5JwQtJzL*8cmw<TD4?nEw3D;RhlevrVr5*qZ0e7%d}wI?L|Fi`QlkVco{WTwcg>+<)c=~(F*Q#Y^k'
    '9)v{rF=URsB~!{qS-7Um<Ck?r7R5wF%H_aHEZzbJm+fA77lXUCQrB=09_a@=x6<NN$sAZ+b^JMa2s092'
    'N;5&XO_5#V<6H8ItnHG+Ci2apom)e)jiKg+=qgi4j<?ZJoI-*Zg9qU6)2MDvk&8Rrp9)u2le5@A{9*e-'
    '3Yz*(j8qu;T8b|rmXfkeW}T49L|oV2J{^u7;s<f=azr`lgCbOE9tAue_}&%hu8RqYFo)Qsku&$%ZG*8='
    'zLvm%f9GQ|l$1zYqICpPQN;jhNDEnJC(Y0N0OKbvhQ0%yagQ1%_cw+`wuPAnQ_@_O$7JpzgfXtCtBC6y'
    '+i%p03nx;;om+c<HVa*Gd-ktTwgE*U0=~(;-`OZ2$bBF6#~<15_-;p<v)D|`=~~K-*&Rwp`NHug*|_Y*'
    'WpWbU+Y%@r$z#J5O&Az+wRy8GxSfjSJCe%H3FSMG$&HKT1|+gH6SQf0T-#!O_)s}XPuziJ0_Sob2H_%_'
    ';89E9OcqRJBuDhT)P23PM2h`tDVD)d;!q)h!kC6%MON$U(6k;ArkNZl#e9Ml*`{|I-7kb33+Ysq$xpeI'
    'tnGU!w?K6rBo{E4B0ESDF!>*n^PviBOp;=N79GkfQzURY3PBo_bl6a+X^ClT`P4jF2M$FbMHprBtC_gw'
    '(}>mEIcTJ2aPkr-tuSc5m<+32&l>Mxgsq1CECzj^j09*|s`pa>%uS1X;Xq$3Kz3JGQeec4)?l_*sj;&y'
    'SaEqt6d0F~VX#AK-=wg=6Im~@*a?$@x#WWMe2Ev;k`cJ(l=@XMIY?c^-cSW!1B2!f7G0XOxrL4&ba-0+'
    'mVgUnTGM?gY~xaX6PxjU*~OB+F6TN*$!1)qm=8)$Df3AsuCGa5U8SmdF({#`WmSgCt7$%FZv3*?DCpWP'
    '0n1m>yVKCSR?re7I6GC(723I$Hzw1<PPLshYZ`-NzY{(Om&lD;Q`|mqNWfzTN)gw0SlJr!5c|$Mif$A0'
    '&TM+&2W?R%tZ?_IKD45*$B-gn38@Cbn*(dS!1|zE>aoBn2zZ7ojC0K5sLe5$7FR3ZnA$q{Uv^q$*!*rN'
    '%Tr_lW;9+H>aT=lnk=5PEZbvAd1RcwHb(sRm0c1uT#%@;EEy%NCMDBa_TNT|l(;V62sKT{ZNTyECT*?8'
    '3G^yWTN9dO7aG+kh~rOR2y}ThiR3Kal1CD1Q*89x`JB^`YX%>r`pt4|n+8mql4X-!p_4>!cV#)X<Q%SI'
    '<wRDF<gi#LLCWB%QC4=rxqXJk84~#Q51Y#-lmw$mioLO8bE86-e}z#uBuRG3bAl9^vO!lV$>FZ7E2U-a'
    'QBjKHp724DdgO%!${4}oG0`QD?sWxojFmiownlv(txbkAny|ulYJ{~KiIUVc!77+G$Dx~WmK4g7t`m30'
    'S+I|51dSA!m>JBCM%Wug$WoSvam*}9c0Zr1oGqcPG*Um~%RIG0aH2Ev8Fu4+eR3C_2*3Uw=<LV=VUcvm'
    'DEA8f%O_bv&Y0cG`_)*=<-DwC##kZ2Rp!E+@@p0K+bfpkZramFMyQFkR$15+-}zpY*uysNg*Uznr&O?L'
    '-Fl4(Eev=D{a9(Y**&cvLf`F3Sq$!lo8RYlx*JdO`B(rn_qX(ZpkMkfO9CUSvsXi{y_)aswRv-|Edva4'
    'MECZ+jqXHnbEF;z@BMkmF2S|&a+pH{`tp+C;cTJQO!|H;a80R+rnSUQl|-{T;to{AJ!<@TbxOHvkYM;e'
    'E)Ch-q+f!E01V1D;p7QS9UF(q2gmngr@+oGDUBO$0r{mf=4Q&XR`Nl^?Id^9PjW{MCGVo6<nCHZ?z*QW'
    'GrZ)sB>vI~^^R%i4%(7REpFI&hxsNuUG1*b)tBD&RgZn?UEg5udf9Z!P$KI8_)ZwS2qssZ?1pm9_CcoE'
    'Rf_kVHzAG$srR6qSXQ!LH#(|KoOirpQm$B%8e+wr_^Pd`+OSjSgh*+f;@D`FJ243^U{9QI4tnU6xc(v<'
    'EBc_*kzGMGk9hvuekYSp@@l8bEf4yo6XX5WPG34PuG386j0Qq6G2DFiJs9^sABA*R`bgGw`kiW{CY907'
    'bx~Or)%KQl*|4rIoCu?oZ9fvBQEZ0(^SpuFk(JM!y0uTU=xCdBPtv8OTR7{ie;>SCI>sEA{zm%2%dt{x'
    '&;NuP`N;3*(R4$P<~w@aMN1EfJw5*1I`l~3yt>`uR~1anr1@piT0m5Zyae7t(@H{7u^qNT+q<`lXesl1'
    'Rz3%;Iv$h;&Eco!0H%CWtBQ~C2Km;eSTZP=#?ofZ^w{Hc>NO{qt~ihS$NAMau#6p<9JjDIy3&23^pya5'
    '##KRWauVZo3j^m@#Q$z^MW9I2JU6yIf?L!nnQiYArx$Jfpn(>og%?jC&kM1wFLf-Z6m*xQShW~Sa>=*9'
    'O(HJ^edX(1qJ&{&Bl%9#$`^Qy61<4kCX`b}0$YOHjB;eNc3G=*rER&mh>@RuI}hnz-EflXBsS1gD(87M'
    'O3%wgSW7mRXm{Dx3O@u<yJ%(HH`!R3IL2>LZV6#AL)Y?gMY3J{p3z*+8<$LW8%jHA(r68#?S^9NwIuxv'
    'NapiuOq=UQU7`xsjQYGrr;>GhC4KVw1p3cx=EXPy&OIq+F3D(P?MlRupVn}tB-U?~N1N@&e6Tw8drPQ1'
    'iTgllo}^^!sEVlbjnQK{U7w{)e@XN49cU-lVE9i-UdkA6hIB>Mud%4I_*wVXtICcRS*9y5VyL3*<JL(I'
    'e&ENY4eH2W$I8o!pBlBY9!VQLSLhNJ^0tAUP6C9iYG|`)`Nc1mS#^ebyoS>yN;Wirm^6U-xnd>}wauXB'
    'bEcUIo4?G0SH+B}Pm+peuec|6P;J<48@3Q7ikGvIYp<d)^HAc>t+m$bZ{)*=%BxGN%*X{*NPw{?*faPS'
    '{5mCu4_tpv9o{sZB~mIxap%O_I)@1FH}j%mbNV}MW}?bi!r2EucCdA+5-sK)aX=k`fe2HNfIBA>%<_s3'
    'VCoT#W0b~QLQIi?VBUj$g<z1i0J18j0@>1uYk}+^DeVf*dL%O-s4)Anql{O$AGKGxsWDu(YNZ&*&7Hy}'
    '_IBo~fM&=d0ozU=l!(fQ?nvpuyz66jNe<xBOi@Fgc+V*XJ;~3oWR*_3cU{DrNC+yHRQ#;+E~I8KNljp?'
    'mA@pXZS1{Bek?CL^ARgoUO%I)RD|bKsd{ev9lfe?oos0#0?u+;b*aw<ny8)aZ%xU$kob)J{_2Ns=f2x^'
    '!pUNa^5YHuc@ooUTO}@;p>n}n0seF`9V@!g?{wa7UnMzhovs_wQlgU%h8ZCt>XY4&nw6YfF_C*q5Jh;v'
    'MJ%_u4%nY5LDh)rX7W|_-GipGs+nX+ui3~&4igukZEUd7rsMi(!1|u)Wf$^MTy|0Y0Lz)iSLMqqk{Z(9'
    'gVTgv$lWTjD*{oH6z7&hyqt#@VCqNZMy?{rw7=$((nYSOOUjbjgA%H(vQzB}MI|?TGpFp<DlN%r178)>'
    'Rq_^PQ>XdoRkms_pG{^N)%(ENyH(<nbog#mxO5F(siSV9bm=L2ZKuf+$2+h~8Zt{7uu3*DN^USNwm)QC'
    'X_M6U2b*kw*m%q0CR!lwvIpXQXjm+>3u65?h}**b(yI6lBRO~8s#s>Dy~1_UCL8YUsM%YF__owuZv{N9'
    'XsNaRo!@+uzS4e|+NQFF*KT(%U1T)UzU=OCp5dv^$@+chGPb07chtzVW)$g5!|J;-)>hkU^7_NAXly0j'
    'ySqnSu)lPvZZIPBIb<&Frpe;<TXdCMk70WrmU{`P5w>#xDVsRR=g}oG`U8}^hBh2g-F5q(sXIg6)OFJ`'
    'h~v?rLp;sXhqSK`Mm^Ux9C)WU(p;BnmT77u2Y%75P2@e7@;RVA(-~NHe>m#deQMjppwt<9uIHG8AsN~F'
    'U|@KrJu<x^fF8Jmo@@2{y<vaUH{B5-?nXc_7s0y-puH)F1=z0S%|@{^@#Q@H5MibNid5vSwPg<GRP;tj'
    'M{mdEVyt{$e)|=<NanOP(A;8{#y<@|NLi1d>~l_y<K^ZB%b497XtClvQ?N3Yfc4GJO3Qc*?>!G)x_Tj7'
    '!vzc!N0+>mBg~P4pD)P;UAv$zOLZJ?zmk(6Uf$hQ@Z{$qV{HKpY+toO-IB3#8j>l8bOe7(q_K4R&l$LE'
    'Z*FDNmW<lnN}Ib7HqFVJyAU-}B~6h#kq4vO$e9|ec$3`;5@6m+TE))9rF?05H^OokvU0bga<!zq)p<?f'
    'z~;J!o_P51q4I)di+cV?tl=VpgOPGc-cuzA6*rMb3OEep0E3f3h&5Q=gTt`B#-J?F8!cE)g}0c92Bwi('
    'V==t3mO?+qG>E{HS!xYdBXpB>)S8lDK_*BQrxb4@W9zHeK&S%~{BTXVmSZ1cbmIFI5-?d6Sw8A0pRWJh'
    '>}$Xx`-*b(@`N>-Re|2JlY{L6U)QilYJ?N-h{YP<utpi|UMc*WXz;pz^VY`1$d0ARy|kMfk|DQm?z}S7'
    '-uIL^d`AO}ud@60Uvc(SFNlarXUCz*Vz!oiDHaw1S;VZ0d@Ukg>P?QZXFh)kW7eHl-RFgr+s15{pcE_Z'
    '_S%LEzA}k(#smY1oJT4Ma^Q$FaT?NQOH@%xbZUC<cR=XU>AV3lzc1&TB^uvc-%1eKRr<C*Lcz>B34Y7z'
    '8cZk}F(ZoIeZ&(55-30wv)LS!M4FN!E5pTE%;#XMrEPmv&THtSGKgf7D0#sKbyHlLv`)5@6*U10?kXm!'
    ';6l?key*t*rT&gb7q%uwlt^Rc=X&R!@nQ42ra@IxgL>*2Re3BX$uH+3aciu+DyG3;i3!$~nq^RKtyMoM'
    '7c`)Ac4UgBIyf{n_vSBtk-W(u<Cpj^@WIw#moorlnmeVujQnDLd8p{MU|rWVC~9o-_Pqx0V2`D4@eX&m'
    'PK;#xC;jOxoX5%wJEHUVwK~k#nFYppFa+`-3?^6Et(2_X2S_U=3}{*nQM9e!IuMh~*HBsgl@wIHMeq_W'
    'Sf@xKTn9a5)mpmj1_tI;ddck-Skc8C9B=q$a8)z85G#liezC5GP4=~*0z~lF-xEJLLX4#3?+0X}I1>^@'
    '^`rOYa&dLFW)fKo7E^`Q`xq<7zgv))@H&?cRsiu`tVBLZ+6C|$Putr-b?b^1CLYD}g#&EJtLlA6qDwyW'
    '`nH4sfT=s2R<M@K3mXmn><*?>FgX<>bzCR4(E05Rse_}xi`YQf)5Q3z!<F^HEc0ricp{3Ia-dmSX@G>L'
    'l*1*W5)<eg2$g;)C4*Ydv@==~`IDvl6$eFvs6Tf<I?4|yXBEptm91v^vp<uVix8C}R#1@h^;ZbmndV#G'
    'hg={txh#M5a)~WDBC`x7vr%P0kh6(me(i|HosH_TZqI;k-ZnGi88<U{b+JQ5Me{<=r3qGWiWkaz*(i`a'
    'bw83fY!z8c9G;hBlXIacKW^Sv6@@e<;)EB*mV%70bKcs?MG&GEOJIGV<Q)T;X#aK{?_$YpXmI8@X>4{d'
    'W;LDu@`um|<NP`LQ@?s7g@c(<RR65jr8p3VR$-ctMBVdxy+rFx2>s4u=0t@IyMWV)@6p(wQY8itGx8Zt'
    'C-pePiCg1NpQz=DJ(-=!g5@k6J^be3ky?KZr%5GG<sGH7C|4~sB2)T+39HOcuW<_<42SuAF^k1HMg(@$'
    '6+4%jQdM50s8m+7$_npF31FlmHY+-h?n_73MLSWTf@z6zMRq9{=ELNo6od4KKVag8r<N+Qesw4bSt$Ua'
    'M_^#_o2(n9%X;LXBrN#f$>qAO*Tr=TA4bmHmv-Y*@lG(-0?3;tHS98G%g8!h78Sn>bGsKe_!*^%AYI~{'
    '9S9tA6ib4!RJgeK#zBGRx8F5Bz`Z&1V-?}glk;O?%H|F(WF1gv;j_|>Q7LV#c_4+2Cn)1ESrQ(ER7&3M'
    '%iDt*=VRaLE~3VN7J@;M#PX@@#}O+^4k{j$e}aHK9d~(7!qy89X#63ZzmpR#FVo_Rj=@#Lxh+UB>?3)E'
    '&H1^@8A;5v)2%9nUaJLR+JjI+Ri7NUBxn|nteC&7+T}~d%L}2D?Dx*S5r<X%MbDEOX=5erGFtQWzV)dA'
    'rB!UQEjlQNoMliR@^|iBW*sRLCbf>RqFP#Lak_}&q(4KFIfpVVImxUOJyt$k`d}%+{-)t+iBij1FRA29'
    '905elh2V=SRj!CwO=3dW-8bf4%doN-&$<81_BCGX0D{5LKF_TxV5`)CAj4Tr-O6yi9D$NY|7mj~?f^AO'
    '`@G1OjEbzg*wLhZY&H3B3wSqMDUtzxLYrBrG?L7%dh2pquq{OCTep-X)>YDQib%BI-bF4}knOJa9wku-'
    'AD?w|%5?#gk`jL8aDNP2QAL2A34P#AuuiHHO~4i7d8C->v_RBtjWW#0y_|<ZxQG<=&?ID*XVI|~H3w;&'
    'D5)+k756Z%Xh-pe9mAle?eY^DzWZ;bwMuZQ$GU4Gh({_Gv5hX1-mB?yJF=o{D_JHZ>>3R#*b<h?E+6tj'
    'c#8Czlni~L%q9wHmB?r}Wg>6f5>9yB!xCJub@|sE`*f2SVlx%8mlw%R)uo!05fe;7;%T96|DM*o=S${u'
    'a;5m})G532o1QkQk{4Bqp^Ju-B1k){8(HV0$(eFeZWB-=sEoN%?B0w_CW0-^kB{eZSn(}lng^V?_de=|'
    '2sWD@D1Ka{2DOMG2K0mC@hWqwTvUDf!shikf?L$GI6_uUXGy0*5{3{5h+@~Ic^Oj1lj&L%ZJYCqOp{A0'
    '^1Qjs{?CkQ=|o>Rw9TIb%c(t|dZbCk)=!mZqj#9fd7agaJetk2l95ld#;WVeM)rC=b2zkynx^+mje5P&'
    'z|izTZ_qP_nxz>|-=>;v^el^N#2eUjIMiKY4g3ARZVWAb!#h+<l_TAu*6)u-w$(R0$JI5Hnws4k8lK(L'
    '+`jFM2KLAsdWJPH;QxW`5irrIYr>2)%kG<-!d+QBviz#*ySMG-G8QPQ?p~GlEfO899PD)y26cRkN+lq9'
    'xHEojGQS{9$BF9nU#f;A_JVa-!5g737=EJUqH+V!@Ws3AwD+fE_5{|&PJCiD4qbA^`XbhW$?KkE!?yXj'
    '(ziVSN?N*PZCL6+GR-yZ#wt;^+g+N5U_O6nWTW`df3AC#Ag-Ck)fb<|`C`0#65_S(RD6127=!<TJ&ZuM'
    'U(CZr;GV@-6WRs~7)))K%&!_)T?5pB3x4X;iJO<P;GfMILGE{zTE{UA?9WkTKf(Kx*}!XvC7Xt*-p?Lt'
    'f>_FYjaQgca5b44lVGz!+k8~c&)wS&TU}D784F^!283MuVQ1z;>o!`VzAkS_mA7`G8FsA1Z?!X0^mlXW'
    '`yTF(48^@u)4Ks9;ojH?)h2?7b=*&+@gBkV5^vH+Y}~TC4~Er_?W%QV)%9)ds&Z(C6%Z&1p|R3#pT%=_'
    '%P0BC%5gvVm4dktHLlX7=wnq8)?b{J3PhN4HOnIuMrLROTve3S7l^74hh6;Rlv`21zgs|I9at6U?^dF&'
    'E6F2a^<g=2DTm5FNCvEdb{bA->Fp?-$FHtxG_hlFfqY>+UDoVx&oQ-TFS2?B!F^35a6}M8Ye-L8tni!_'
    '0RrTm;rV473DPH%AMh}HEbc#a>ic)Q7el*{LX8QbrGcOEBa?<kmO5pYEBQEw^mbeJmNqMycPN;5B$qS6'
    'R!L7uy@GBfQPf#pI`Dd;;HQj|mbg>RBSrDl(mRKBX1{B-b6c%b+x%s)rsShPT})R%tD{7P&mjQ3ocj)i'
    'KW5+#@ZD<vTmw5^dGrVft|LodC;m|b>q$?%(H-HZ-V9VK3B}e(TFY`0UG~R8;nS=IaUHnD!IFE&?6%Y)'
    'XM_6dl5m`X<woq#1)hw;DOG;(=?7WX-gENazhGHxKswGlHmrouePb-PI}Y0ggYAaD?ufk_=B~<BC3Z}<'
    'wB((Gn$hnf2!@*C8wW}Kgo0sH4}+z_YNM-u{7<?lS}Td9sQdg&MARxy{`R|~hYq_iUGF5A1uK(*>*f75'
    '6scZ50VR{ken$mcxefN@BQ*#E+EC`g({O%FoXd75doWze<^z6@4J0tFxdEDr?Y{YHxZzADpchmyR~tz-'
    'X<*1Y<J}@So>G6OkwmjENq;Mc+ilX{ou%MOP6KIPeoGhME9GF*68NqJaFg<P<(eKoRDMnA3|s%ukF$yI'
    '_%Q~4STTN5Kk)%?`Aq!?Z<Q+EJe;zdK6oof!mTTK?XOwZ3v4rh;1&_^MWpOYSj$7ks1JEv5UePOZS^kj'
    '=ByuyO3eyqgGM$BG=sPk#QMXqd%$I`>(<${uQJkR<s*n6MC}ikbPnFyCxuZWYu}Mg;JPU;$5(rm>H^vO'
    '%i8${8PD!3Kl|~=cDAa{ey7veqVQGZ@EqV~z+Qg_2@y4h+qvC#li8Ly)AugV=H)!R01+0U`<cg%xJb0W'
    'QGQ6W%IvA8@{}qp;rp4nw6SsBm{e()ebPPm#JZZ)Z{<)>a|$Lg@3Vz6*!#T7ZcT%@w2aPjVy0;}t7djZ'
    '6dY-vjqX|!E+R5nqvu=}wMEk@?bUkUr4_4-@aHF_#Io+W)$`>x!>ywtxjV(!pZz-@>qlInH50A7PpprO'
    'fipC1-PCl$a_pgJI)gqTbf{CSr}bUWh99=>8T!cVkEm&DeNEGCyxwbC{Y~x@FWn_Ji0KY2+qN~W=X%<}'
    '9P~#cXQb-@)iH=OpoV6TM${mlg%k0HBb)YyCh-Q^P`8XtU{>BEuF)GV>oFx7@RX1|u6u5g%WcXk<|B~f'
    'k24CQGjOOVn_sgE9XoC;w4In!C!D*Ox|UniDSPuRD|#*+BE|A4V}(^wc_e-GNphMdp+kz?!>LqaoH_Gw'
    'GLbbJzMhfaU;V(2x!PpnUj$QD$yA*rtrnsgaacB%KIq*3NInapZadrNS*UpqN-1LEzo$=V6#IdwhAdLe'
    'jsmulB-^YOoLw?%qkP&do30!kw&*y(a%6{jLVK3Hy?r$@`Eo(3Sg0ozZgo6<)6saXTC_p@Iw0@Cr^b4z'
    'JSsDXeN<`6&FUrJQ|3|Z*C@ev6~%OVG9?#utnBlu%<2a+c?V;<G;-$ttd_?se2aCn|IQEMI+4}YR~`$_'
    '!SRG51+<+@f8x$*jU^>9@CK&5^^{inK`Ss{+Zk%D@Si`)MG8CESWKs+EX>aMn{A;NB=1F0bw0)#Q8nxa'
    'c{{yZ@zAt%XkIw%ST@ub4U#3p?ghiDLy*)a!A@8&W;7^uwb`0RFG*A|M@#mpxDnowWK@)8(^BuHEn#Hn'
    'DUK+8(n*Y_y!|+VCIm$jh-b)85ytx1<ooUIgrH<~nkhA!kuNx|<;zZ+(U7=bZ-e@!bLzgFhf_bO(^li|'
    'Wgl*}ir2*@%RhO0P}j=38zbvBHkLFmOj4QJYjs9kR)JK4jd`sGX<qg#KL-9;MT@dba}~>swtaV;_PS?$'
    '5MN<H9>WlAX|>{S&2RhnsE>s}#U~l%bQ!aVmYFP!l$3mx8J)!!7PHU6!-$XAWr1PrH<|)vMfI<1bO2@*'
    'uKB%;WLf;@-IkPX;#}hi1v7q93e8G#|Kw-`336$tVrhj`D#a%&8(waIcG#*b;fk{kgQMAu5^TSbvp?Be'
    'GJ!ntBeD#~P2QCW>M_eyZHHdtJ8|As&TBM5X{~kuczg2`kIk4b$lbAbDTkvQ*wmHYu<~U;cC;UvXw6Nu'
    '?SsEOR(_sgEhh5|8rNVjK7h<EEre~RsQzix=3u(YZa0*-y(oVu*$pa=-j?U?T;C^p+?|!)sy}O~Hu~;N'
    '^g@rYC?K=wGQ|7t89TAQd3YvYR<X4~*6DCnpp;uV7E&PQgL>G4hT%t~O^%cKBzctE2P?&XjMJSdOEU=;'
    'wbF#URFk2$e{$;wv2XG#yapBGy(^x@#~VA53E~>wTg+w?ALs}-Ux}PKrGcuPBt4b4gbTx9nxn#;J2H>4'
    'yBEqgm;%VYFxdJgR%_W;Os(aya{RjmiSbmft9(bIOZ-h*QV+(MU)a9|1ZG0J_Rx_N&gie{RZ_d@QSA}w'
    'EOai%%IlLL9+>rq^P|UUx9ECR)OfZ`=Jc}?WH;tZ$xt_J9U|<;8aEXJaT2r{Cl469OdoAo@(kD*X`Ngk'
    'vGAjh`Fqi#jeaD+5U*c7eK1t;rYa`Z(5<EOl+53ued*HKB)r07S=byGTV#g|_}#t&wpMGeC!u@5S+Wn0'
    'RQ9Htt+O^1#tQ`y?48=<=9wZ#P`P*S&}75(Fh4rt9U6b1mbv?s;an8y{>3kf3%Lu$wl)ZuCd}280b=A='
    '%ySyc(hQkosonRtFkZ-2S(Spj2aW(z*P0nVk_IH}1<I^VR0mSLf;^1(KKNl1Ds$X+gh2!xd?__S0*&Cf'
    'u^?kk&X0C)Q{q3<1uhKB2c%8N3(nLUeZF-^`BoLdNnm0>cuyuiUdxfh!8wO>lb~*Gn2aB>&7goQ!J=V3'
    '7p07MEs@Tuyi!&@R>^!yiL}*Kc4D4ZOS<H?B4}x`zu5+Fe<!k)(dG__Q|jI)XD^>}VjCkL2hx(jxPX>A'
    '>-?e7CmCMA%SCjFqod)U^VpS3uyG?^@#MWvKO7(rgK4Gs;CgQfl_hpjOf*dczTg3X;TZ6?-`^1DU42iW'
    'q=OF{(VO+Ql<j0WZE~eZkQRzZ$;Q+rx8J2<8ia>9t2j&@fg<cW@})wUB_iyRn)gc(y0pk;UP^vmVy&D#'
    'xf{A#PM@sV(z(>pnfDGaaq?ja=+-M*mBL(JY4LAyh_xk5PF|9lQs;V!b4C=_d|S9y?8lvpyyVF7yySBf'
    '?V=h6R|SnXEd&{1X5vr$CQ}0PAyu}81%W3^(B%Q#DDSoedEdn3+MI@6QK1A^(-UgytIgDu@`pccyRxrJ'
    '1pTSt=ib>FSUv<(+~UIYKFO1;>{vN*k=Y+>LQ4m7t`Xd|)!I-%wlXWTR>FA2?P>5%Kb&2XIhB*A+i;PF'
    'W-Cm5HYFf7y6A0a9hvu2i?aK982b(;-FXu~*uITHD?QA4!ACm&NT#z1m3YBb)KlZR2%k#JIEkVKZ3_}&'
    'Ke{!R63>BjkldwRGGNDQqEHt<8^@#&+1HL&+)a^u+k3O>1jEkO8_>X<@%4<@bh4Z;7LoVV<s~^}RV3JU'
    'kbOH0->KLowxZf%BRyi*B23Wg@56wy<61<KI;A9l9R@4lAL093?{T@*G(t(19Ah%S(NXPiBJrY6B|m<W'
    'Tp|Lyiv5P&Al>O&#8#mhm~9pRLEWRc?lN&)U~VKk;CB40v6Y|<I}H~xJ$pyNk7jiO_(GCYx=w?D1;)@i'
    'iJAv18HLyNF8efTRNhTRp&b-M5*c*p4E>s3$vMYQJP1Cf^vsK<G9{AnL7amF4d&liVcB%|B>iHZpi|%#'
    'WTMKF=>$I1LS|jP08lrNg!I>r#ML;9`5bJoQz4?3s*61m_hbcyZo8ht!vt^2qr_+(v(pdhOF7OnYiag{'
    'X>19WI}Qy^zR((V<=nTAjtV(>{Zpub*1S`^6Q5YROT6AAJ}mIj_V=-F_N(Ri$D6pvhea_b`QnsJZ~3mA'
    '<yJFgY8rHvWq8WFca&@U$)9Q!8*A20Zq7^IwUc}&K5_#t@{Nw_8RJBBlTYbvLav0HEWvi|Dw5pZyK%O6'
    'R8Z<#cHz}RfwKr*Zq5|g(N0QeG5XyC2PJ{4642ux)WwWdx6ixyywu8PQy-M0sb1kLxn*$IR)&0uZi91m'
    'M}gg}QHby*KHU$LZCV<X%Z2ZG`#ou;gMYWcv;Hu^>szo76A*ySmJlv1qp=#oyDP{m`XM$^l2<7<_+m3i'
    'yL5f7b<)H|-ksD*TZ-Op-Tu5Kx#U`ONom~nqnAAW10yFtPiKo$FCCL^J@2J{;)Oba2(9XX0Z8zA_vPgz'
    'k;Z*4FPEee?W(-oiXsrI=g*^<Hvx?!jL>ZhGmY&k*UKgA?rrHgi3P!%wOe;#w(huos|=%6W@+|&W3sNX'
    'SPMaR$w9h?E85F3TX$u(?!aih`*O*(P1apotan*Jv$j#P#$5e1U1g@qu78;;Etmr=Y6&h+Ko;Oznz>uw'
    'z$~4TD7UnFw~iM|FqZGiR=(#&-Zn6l4~nPE+wNlBrf2v<8b;F~SJ*{H9U5sR;c$NM$z(wr_6PFrfRu^z'
    'TY(vBvs41vH|h$c$8c5hXC#qZvKD!z>OMn6FFS-~?8-ya9bTm=HMq^4wTIJLh)p-vHoEP*nngX=wt7Ry'
    '&~$I$jqE{RGi=?^^<GbN?Lp5S46Pn@O`G=JUXSY3*7~Nd_ieM^yM>#()bLg_^x@DUp5ZvIIdlo_ncl#%'
    '`a@&r8q_ijhnn8d=#9M5$mkPq=#DJI9qHzfT9)D2w}D;R__kI*W#Kbq7m-Q{wY6K{7KkLXU@G#^<baTS'
    'p{G)RMGQNl_Dl|6?RX9*)L5wtOPn{e(YnfPLcr2V0*>k|^dogjX6+w;#NUIs(~-Bje<X~++XjA?13<Nj'
    'atAcoJV~Y$DJnyp(F@G%iCDU8%|5ctQ~j-ozDTq+0XI+cRV07C4b87Qt*_lJa%BkNF$vz22n-Eu#YaEJ'
    'T_y5=PivG#UmtK`mDWg%TmKS%v^&j!0URoAKXB<s5P58m(ciAE*cgp+s#IyPn9@1;Vf79wZVXScws~RX'
    'vs>YZ%HwZe;(FR2>uUyv81<v_7i`Pb555~;b`{`y{=rr9!6o%CF5^yfOY}X3?G>888jvCqh&m15({>!n'
    'SSCkaCkvM`0K|2l`2mNK`%W{<ysobVn~(>)69>DI2CMtEab5YC6~#SNrsQK=tF2fH@_^UdeW2*gErRi7'
    'vV@WmfEumtdOj&rKWOJs)lD$<bFI@+eyQj{d5<2+$6F&PYeESW=RTWL&;QuY_N60PEo`9`5~*Gj@Q#$i'
    'o#=#Js{}cjoa=1FYjI8*E$mB5T)g$s0c-^!D=zLn@h|*XmaQd0LrT<!yIHxMg-h^bYY%`OCV1+$XflD7'
    'DbY!#uJFoK-hl$kQet5xB?#-X+az?@p-@)|X#63Zzr#KgALf2cG2Te{sf${BY1OrGsxsCa@cD132Kbpo'
    '7rs6Y-uv^A-55guIC5w}Ujh}-PVs(r`hFu|3&(M%)Ll6A`;ZIcWEM4{@{76Iz;c$cd|7+WXf7Y<;8e)I'
    'DM>C>fR$7!{pQuNj1auq%zk+!1<=xUbT+o+2$Y020F~nkziC{#;p$`lsbq)?76g2A62x!siK5GIW2ptf'
    '5>7;2__`cjyhgv`PLZUgH6I`qnH4~zVV(L2>qwLxnBz96;*GY4mu&@Pd0esCO;kg+w*+?1(c}Y~IYBs|'
    '0`%WgX6ra1UWNv`<Ro!Wm+t2DJ%!PO3xz1$9~7;)<}`B1ghq-Vt5R2XbETTvk&UGjhLmP_3F=4e-*J81'
    'G5RY(lj~H9RHtMC@?CNOAl5NMg9uTi;-5$o%>)4Qxz9Oqsz&ep*?#?~Rw3mRWWonBcU2m=`%MNkqN~8U'
    '1QQV0wB1}(fu~!D?c(hzqIMeUtO-;|&ZHc)tPGAD7d6jzzwHO(EOeVrs3u^(o`b~PlX%j&6ckatIhoS-'
    ')DOO60jAn>H_gua?7k%il23h&MeEs{^@bF(<Qcf=s3Kk7*YMZ$s=XxC63yu<wIjewm?szDyYGWWS>6-u'
    'N4ejTEY@)7FY@eu$}^#{W8Zm4b5<%N1Sa6>u4_p?iUl@D4O~no(o=Y}?bKJS36*22n|gu?=T1n#k5{7R'
    'DDe8vQV(#MBVQ3nAF*)pgQd@A+b=$<EeGN-CX;bf2b*=>{=%m6`a#)cqWq>N_}K4!1`GKCw~{YpX*)gi'
    'XX|r>I-_$3cmPi^9UpHsw2|u^42M3W!9{%8);gWf0a@!<IooyV>tMUHf#FnppM*2{XxTUtAEDtS9c<p*'
    'TLPSZxL-dCurxU9biRLINpA;5RH~*gPj|>0NezP|)-JE2%U{6&mJ9Pq(xtBeR$NYM5N_@^Ut%$4clmY#'
    'Hh&(s3ih3!QCClWUO2|fCSTjFYY6YT8>9SeOZ8pZE&_MomTs|eKcPu?E1w$0JOml3QOO#F&(U-$RGK05'
    'D@+h-L{+eg9(Zw&d?0>Y7eB9nqSR<Y>8u@)Amn-?s;xdthiWg;>+`{}oP#^?JcH9z9#c|mq_METbu$tB'
    'Od8=;@Vpc`NY-+1BxzAze8mXKj~<i2p_2)9yNMR8A0$il3yb*ima^T3f(PZWRVF?@&-hic9``+N3`-(('
    'coMCQpw$v~O3S;a#wNZVK2)BEN;q*Jpi)(w2_?Z|hAn#8?{kGH6HpWL`p1b(bE@~zQZ6{G#}mp@ot#U5'
    ';=(456}GL!59Dp*&OB^ZoO!=<4>M0#frO%gD9=t1+`gEx7Kr&quwC9In2z%;oEs6$1vOSOv863EIY3{s'
    'P-_e5uWr-;OA&fWB7z@bN+LHodBNh+`r~j;OSjg)$JF#S_tkaXb9;TKr<qjiSp!G2tdU{Tp{1Gn(6%hs'
    '9(k7Ike*}phSpH`v=QyOCNXu-91Tr#vsCP*tLlTk*QcINHBZwAy3-$8eQ!WV1H&3=)EK}&-pHkfuDQf='
    'Y^!fu#4?<o<C2~|B!dmFs#o7qPd?@Cf$=T|?C8;aPOjQ%wvU@!&&b^~>2&Jk`?PqQY<8Wr3Z6R;XHT)B'
    'M-gNl@~BT>TP52s=h^QR)4NA>Z9Lbq_UokevyA>D#l{FENN3EopD3;$vApBRxdfdsp$7`MuSr@OaU+nd'
    'EHV?-*dt7{2h|^e^)^RyppMzqnl0>!?<nPK`k6~RR*rwSAaT8RRH=cGKqE2yVClfi4)a)f&DuyQHA3kv'
    '-O$c8jr}iw(o^!$pDw0P@u(E}#4shnkeODTAD5-*=I<A>(gmIR8;UQMGk`~x+5OHusE!O6+yUoMFzh5;'
    'N{%al`{wO|4F9sQCNJ4uyqw8Eca<}gkA>~;$O0F|bcR8Ew#J7E^j|6*wDKRN^TB(0kKq4t9rlniZGIIY'
    'T1;X=u52enWD|bZWB~a9z8V!n{-r>V6uM<WG%-^??1Kc%A>WNh;(ZZMfX%3(Sz$m~v*tKg@hm2A+m19Y'
    'lfpVFPx4v*bZrBcO7MW)^%J*|$RfTB=XmE%dF4;(JW?j$P2vdvCdi+mr}6rv293F_?>uJ1WA#aP^-ryD'
    ';UpQ{Hl2jQMFc#dkU*gy!50?SJsw6*IHTPx#eaK{q9h$J-bVsAb>%0%N3q&obJh;OW+l(YVK79yP>D8F'
    '$z0$&aPnlVys&>uoj8jaNd}ZO8W@*5v5WT~Nrs14EXf6B9XxrChinKy*q(oZfe+rtQToovzcHG^$=$il'
    '+j#l=u-gNvyh+<#y`YXfg`AKx=#Mfzi^YL|n~-8H524gQL)HQ^vW3|tgFjN4gjBN+<ry#u4U0OgtO4cY'
    '^xXp<K&V-8IFrox!pyjqE2AGL>A;euv<HT35)#k#VSZ8bV&Tg1FKB?r{wySoH*D_<nlT?iVKMXqiWLW='
    '>MZAs)knNyLS}o2S>Bwii3{X{=M26wtC_?XA<hF7o-o%GFy?zCck^U;Q)td%^c_1@M$F_~1Uww&D&Ar;'
    'NkSaF90i`9I+F#8{u-MSguw%0{W@ea0h?EC3SX7g8EXSuzD&*dSL(q0R7pb7fQlaIxpa#L#?M5Kj9dLn'
    'AuBK}Wbra%Uy+kMR-S|lX<|MXn@YJg7o!qkDNT-dEk@(>Z<k0OON15X(NP}O;9UWvIO2U#Dr`Sle7YiN'
    '4QN*@VxHRrE@4&HBBl$JxFBHJiFxrz`$h3c8y%ExE%PmZVvVCovf6!*o0x3c%2%Rrg7Swy@VA9*gZIU6'
    '(p-fK*>j-G3aYuzQCOL`>R!HGYEZxmyG0EYpyv06)#?J&l18m4=F1_;#1QNymW2Zp{obGPYJYWZRq?{B'
    'QSKBICN1)RB36pdpJOl%f2taiEc;EDBf0TaHtCWDK1vQw#0;~VmNiy8mJ@%MviO{Y5CY<$ARZFwQ2Xq<'
    'WbjBTHI)~31qi?Rg;G&`A`OJLJNL)gWhy3DaVE?0dBJmh9{eitgdfQ?jFOZovHOP!-0muqX?wt_u~j$6'
    'sBCTtyd<hQT|wUC-X2&sO6Oh?OOhUTo)y=6yp$l85zqF3(HfCMa!dwPmQ`YuSGx+B93+43`jG>?fpL&i'
    'c1l)l5GFV8mHHRfTkCeN8MZGKMM&W$JJJ=R^Q$^h$yDeTy)9`1paBQBN{@WX4A(S_bx@9I)IgJHC?*>_'
    '>7>OjEKgZd5`dWaYWBV_g0slL*_8x-EY4z57+7nRqwj=^4;$cOX{kI(l3p&CC!x@^(z>Kv#te4}&|e)Y'
    'Re>6<d@<&Z(j1asmN{1}K$5&m_u#N(_}x!)xul7Cjjwfv(DqQjux-UcGMc!1iVy+sB1z<k_ESTa#zCc3'
    'aL+<owG*_&1q?8R!^Pa8(L+(%1Fd8AqZ6^*kEr?z#?b5c4YyBvUe6@MfuoN|&(a)I*NHY93`VYJo2ID|'
    'z3=txp4PJ*chKwiM}6D$ywRw?X@dUJC5(}#+oVq{gV=^;4jtXn&0){=Jj*hB&Y(wn8qAE?BM^CpZW~Uo'
    'XN?Fob<H!#a5UT)@Y-t_weP^R<c=d_l=@>_cWV!^|DMiSzu~d6udCYrR(%tyS_su!T}$dP5(cS>YBt7-'
    'Dq!Q9cLv2G_d)-O;z}&R4|jA*f(4oEccqL!5z-1FM6za$^A6+<2E%bN`a1AqnZvSy1y%vgL4@~-T{)N)'
    '<Fiyy9G_DMyZhqun=kvaz{uiCN$cMK{pEx2h)inwvmk&!{>%UVPygk=|Knf(@Bi=L{&#=;H~-@A{`%kk'
    'hrjvTdq)F*&XSo|i~S;*zc6N%WaiZIMJE50w*K$`lmGlr|MkD)lKG1$-ldU@CDXr1;xFu2V8^q|@I$WC'
    '$`>Q~Cr1H)_t*c&AOGpU`{V!i&;ImZ{hwbf<eiJ<wCwR0(foxmi=sJ;TO{{^Q)2ldqJL6xjA8_X8_$3D'
    'xBv2wfAc?ok=47D)uM>|7g7C%K`Y`Jc+wkVN9HdP=btJe{ORBPkAM7E{|gt;fBIMd`cMD*fA|u8zB_rH'
    '^}hHbvA-~CQDW!K>V!_d2<x9%<Ri1DG5+yS|BElud56-OHxK$EnZIylfh!*;!RVY7tt#Tg@WUkyl&f%2'
    'r@C~@xeUXIs$Zo2Pc4Y@r+@M9|HJ?EH$2pxH_HFN|NEc)@t^<OzyELl`Jeuq|LgDn$$$E%|LlL|O5y+c'
    'C;#ymjj%!^)E%NewO6EEUcbG*-g|j;di?y=`Pqxtr;m@%Phb4zOgU6OwT@=9hu=;@8!r-&xpRq)IM)?x'
    'cP!1Lv}aMxAOqW^2Bm|(sp*<I>KV3f_2E<9)jUF7P4DTZ?or1cI<`Xxj^$8igZ$5>Bw>vZ&+VJNk!iX;'
    ';*Ru@OU#}_Oq1%GMI6TkSi~Zx;TVHq-!O>lI!@m+Tw=RJvPpLG>ipoZc|F5?wHD8x#Owxk9&vxQp!2I5'
    'S@x@dIq=IxIQOyWz?&z2<b<%nSC9F-SG-hgQ$Vkt5`V((`_!v=vkFX7^fr%2evvbJBpsL^Mc7@oZVkj$'
    '!%sq1-mfuS@%!J5%ErrtCx1N=olpnV&aeHzEds=M8i02heu$nj&WajC;w3M)2%N;ppdt1VV32zjbK2Ny'
    'F7TH_h40GuWX34rTT<(?&rK5H+a1E3&FPHHse6V+A9*dlnsk>h^Cvdx4E`ysh+Ufzbvf%Ss@_a-{dVXA'
    'sYc<HDyWug7?`P{bmq*%$wby@`1%3%&3V@bFYqFmvb%BWB&l>7&4>fPj1_&@kp&N5zE@_ktsCpKc(d&&'
    '*?m<E{5l}-VQjoSwcoi#&)lu&aV-@+X$jL8o;UFWdi;@~|0oepAs_g&L(X@MUS(1vz7RW4eL8XTC}Opu'
    'F2f1z#C}()bx*zZb8d91@95PBEETNca3{fR5g#pLkXSQ6P6IJ*m9<Lg$Xz17)M#N({g}6@SNTdiY8afc'
    'w}HB_wPOt;<9$l`xOj_Mxt70%ZO2>PQ7+qYu{-;cQUA>%j(MNYqLGB1ssTw8+>UV#wDbMUt%DO=1XLSc'
    'MKPV8Ovwe^o_P0BQm8!@tM>mM3x!QompUM$B9I@-ts6WQF9hz$LAwk8Y&Y)NYVQmyx=~knWLsCgZWZ0T'
    '!l3f^!;gL_wp5o7K!zXLup7B!uWlDk-EMrk-MDmj;AP$9WQh(N*rlLeW#%0_S}iH_Oj?;FtCv#5zEC?y'
    'euI%>+pEk+mNFjp*ue=RMb_-=Q5aWNvygh>_KE`EWQhYLY`mK5CQ`NaNiU9WvVU8`6Yd`GA5?qR{8gfW'
    ')T2DgzuzrvXua9z`)zdY4PBs_l6JOO4pfVeK37^%O8dETpCu7hevijhjaItK?|6ut+wgZu2U0_DQX_CX'
    '4!|`Sf4e8)x7M{x+{g~T-DT`eB4+AF-tHps*7^qABH*C*1&uMnQjEeW*Vv<V`@!MaUyFENqXE4;iswlT'
    '=Shy{?IxIa2eG_{LwOrS@~&?a%BwEM#$P#Hh(%559Q!QAsw={5YV60LAhzyh&?=y0A2kp4=CG{&j_k;@'
    '%GwUMr+)Aq^)D`KoCKI=XEpUMqX<5mU&#zegM$02!f=CaN<I4%43V|pVav&_L&g~e2VtCnk-Iaj;3h06'
    'iMnkcLVqdlprT=yXFoAAs%lOE<l}FAH@@5+GvFt9=qg-wHW6Ye{6^4*{Y-JMS8P7}tW)REk*l9&J<`-_'
    'xWC70u=4mc|0y4PApaK^7c^pt)3QdtR%gUz=86P<moO)6t^J(5_b-?g^9qG^o;JDk?$kT}*{#ZGL}N6n'
    'Fm|jj?nGTQqAgbNt<+7Hpn7(ud3LXOR-&v~wbO*wS+|rZATw|V;_VMuODDBzGGf~g#>Eh3M=}B9D^ZmR'
    'R8_puO;3>VY%$v2OU}m44JX$tyH2fuuM&p*#V-Vr9kTk~+mn+NMZc`;q>LoNVra>m(Z=?IG$#`PPOi8U'
    '-VTsIBpG7&!~BXtkhT3R(9UB1om8}mqu;g^>sAee$E*o*JM_k-I2nRG?<z^u%ny*!w$2gD65$`Efw->@'
    ')6qY{`0vTYXH7sQ<&eSRp7;?E3(z6}z{G1c4`u6a0<HXse`&~4DoEXR)O`GFv@gC{_!v|z=6Gb{O>(j_'
    'N@H;z0Jh`tbQWK+VI_GB(s;imS1wDCqXouK`l86=`aEA8B}|b|yyC%38N=t<ZYj0vK$gMeV0)>_OUh&Y'
    'z<X=ha!ZiXxLLx<=FWKeMpl-l$affH%?uJ}0>6q3rv3Y4I^gSRI6o%fw+N(n6_f@){-|Q>H<SgLE|wSA'
    'N{=>5r(~&aK2Qp-)z(q_yh~P!_y|a)(~f;-5<2g85!DCExmPBnBwe|?h?H#ZlB}F}!&|FaD?2hyNWCM4'
    'tL}uUn&+toOfxAe>+T)ICfotm&@BlEohz)!#P&+K;#N3ovn$=lVDnVbspFxgf`uYMlrNphgZ&-*ur&W7'
    'I0@ukvSHjPQi8lNjDs+y5)Xcxyf}5S0J9T~ZCS@bckPBXV4%z7t}5nQir2m=-w%14@!ytU<+&5NFs)$V'
    'dH6vB>$d8XyvWzPC|-L)vJV3l&kJdEDNbgJyt*!bPnwREo-uXvI`2V9gdaoZ$Xha{Y?Os-$~=BqM`Te<'
    'M5J5}ti<9iU~t*)g?BNyTPt-92jP)^uyZRdPL<4o)m6uzgNHC9@uf5qblVi!B|g3-ugKaiIcy@|9NM`x'
    'B-<EjUWl$Th2(e}4aF%WcrkbY{yvTB<`lWO!~LmnWi>gA{lg!&FQlNU@5D%jk*}rr5@IPS%VgFGnM}lW'
    '?d{Xy*dcxp=PpN-lRhXymF7{v<ALvC1^0^yiT;1~-nGkZ8(9?nKEHzT$(@$&?w0v}w0Fki*iPb;hdpg4'
    'v(A}hX@LOPt!=fah?4CdkN^9r0zitSD2WfKo!M*mnu)t5vH(;S>V-lT<`6TU(bY`cHn=qE*Am3w-_0-?'
    'N=u|I*E$NRsA7OMw1q6UC(S?178pNa82VnwjC<5DrN1#O(s#@vm{R1bJS8iJBV6Ko&JA^)qd%ecTsYAh'
    '?(FUT#UgYi?b*MfYy*x$1bkikeB3G^D1D#FufGcF%-C3)vv``A(<d!AX75ot>KBg3WaF+Ex0RFdS<gWw'
    'q(p$JnlJ!!zj@PlxO)}LpGhj8PAGo{nS64Qd;*EA%>+HQJRWSZK744rC{EmA%Pi>4DqW<TY>r1Q3p(Ej'
    'k&z$KU!;rq-N3U%o*Ck_38c<CHORscn?_zmo($KaMLi-+GkIiG^9lB3n|{{lekJ5sNvCQ|ek!G8^-f|n'
    '&OmiN$}eCDMfNC9z?6Sz&WEb3F;9vCUZh-BrpU(`8w7b!(_urUrX{AWl~eO{9XM16sg6-+zk!KsGoFch'
    'JC9CMGdTZIC#?XqTuesvN*FD`a>EGQ0Q*@1{V9h8XxXXvQyEyA7Jmo_`g#MhySb8rU}m%ix3nsZoxa1W'
    '%S$W1-mDfnG7Rof+MiO`e->G<vDk@_f~Dkw;(SRK)zT5TmYn)UH92UqStsEHd<_hmXIOM;K9UwXeleD5'
    '`8@}&u<1ber9#G?{3bEuKMECV`nsO$s3n{6kYavRb4rCzs&Rd%)YVO@S{8#+s#;fNsIr=tFiY_3VxyvK'
    'dk(B$Mc<!>zHbGsF@kfi>bXHX5Aw!zTG)lQ(`HR$aO`*Gb4ZDNQfo@u2b3&i%)qGP`ZHFxMm(%%^esoX'
    'NqA>5zn(2ds!Ukr?$7Yis=l5;iiRZ=8U$|+9Pk2%55;&Q0;eG01+Fm8v0P^(iNT_{TK&dU@8EykY1Lu#'
    'vs9O-C<4rAya?3aDa$lpyxg*a#+vfT<o;@n`2Lk$ax+}9sIe;<HLRv!(?RxMD@95elZ2QQ$+#zQe9sNK'
    'S*=9+iu$Ta(+(U>vkQ&t6U6by|6$PG)#Q@1dP^QzXv9~mbT$5WPD36Te9-DQ>#=Q4VA|9yo9z`kP5kz`'
    'ET=O)hpSjQQIsS3s#+&O3-H1ytGnRRKEvV+`S`;Ro9iZ&2BS%fy>ZXxMuRZ_0;6uolH!u*967Ss2Iodi'
    '4xj6~Qd-v@4W&5#Ap4-oJ^Dfdb&O!~nCwPI_s-SkxHQW6>5cj_T2C3yIE58<uSVF}Nune}O|XVdTiT&*'
    'c9s^-(XJEkZD#=;4+t79V`65oG#Y_6hLWWs597J8B*p!Fsd9Rbw%17gH@?jCNw(hwGxh8#?6`-;8n5K#'
    'fJ3czZ8MCx#h91477Z=evfRKXG~pp7iJ4d-_bfkh7_%vS;zTB6+zedTj41qK1#OJuonE^Z<J=0O#PUp!'
    'xNc%Ofk$ZQn>65o=fbcq3tWeIj%g><j{-ADV(!F_%{*e-ajQZ1Hro}}^fnw?Sk&tq%zDGiM-45O`gcs;'
    'j+xiNE1-|o<oeS1vHtNJa-Gkq_n@W4?7+WD-)mWqvZbbZHT|7NSi6|*J!r#KG962xv-REU+A^NPXFsKk'
    '?_WsoaRCEW=$e=E1mmXg?<;c64=(83SPseBHqKrw*1Oa#1W$P$I@Y!T!13LPfDwObT&3hzj`Rfn*2rVU'
    '^nVh=ZE4df08onn+^@9x9Kz;wvgUJ$8m*G1x;t?XW?kgWfK~isn{=v%`AyR*?oC|kmzJMLSl)-MykAkd'
    'Us85D39cLke;S}C9zJ|%ycE~ili3Fhb*X4iX55f>+*qVWUU~S=U}Q}mVX$eDt}z1wT;Tp1Lnd`)8<EDG'
    'Z07mR`N@FAEI09dMh)<(_#y+($Ech015P2fJ%?_|VngQ06;~Xy>@lhTXJAy{1s}^aKIyR!F+=CaVkFpP'
    'O>FrX+`3Qy-Rx_?qIkr3^6G`~U8^;t`w#qSfITwc9ON@?u@mgDlWwp-l)^v8g9A_1PAW$3S&IB2?dB87'
    'kh4#N6m>0Lw@%;k1tu;oX7h6_e<7~xG~RrZi|H--3M_0E*ftWI0}W#0op2|{W99rcz#KZSq3<gx*T-zv'
    'pcEVJ_Q8e={%j@AYatjw<UF2$Acr0CT4e;Q(-V{u<AL7$XJB;ge0~Bp|AW+rtMhn!eXBuaH|g8q2o*O~'
    '{!8*Tm{2?uMwG~h#7q#fFn}wT%M~bzA`wDYMyfgyR3|#4@kH)5^ijo#WS%Q|wGD<|@HwS*(oa?l98m49'
    'YSsZRwD{mlbF$^sLCFBXj3|*VjW4b7A8a3<Ue}yZ)ePVsbqEK$WqSrEYrns~;e37Q9L{kZHw=T&G%d$9'
    'dE!LAZCbwLJ9cOWrcJ$=o3ZT#0XIqF$2<%zMuO1uJj)IPtEHCPIf^45he6`R@hNqkh})4FSlms_&~XS1'
    ';(1{}EZ-#DCh$SPJU2{u5<7nAdN9Sd<L*6;tN(zet=%B$ofj<zu2(9k0^jLwJH+lXbaqf_2KQR>VR=D#'
    'e<yn|9%5V>`+En8{sp+jUM^*G8728oFdF{I`T(N`w`BPY*7XYP6xcWGl##m!<AIzY9my@&k%X(A<mDf2'
    ')#AlShr6sbq3nLCbem$)yps@0g8uJHs~mBsS=?~(S)DIN`sOL>!TYH$x_@;i;D*Lt-`Se11Vaw&^eu<|'
    '5=Hj26{zAZ;8wLz)RkcI(kYmwzOOOas~B$JrcRf9u?0GkP{-Xb_wV=7Ph&ycuK}Ugez-UD;jD|67_Q4t'
    'q{`3kLo?j767NJAE&BU(>iZ8!A03MOUQO>47zuwE8{tsX%|9s8WU1yqB;K?`Jh^4{M=-4J*{(WdR+XYr'
    'cvPyI9AVYS>`)}iifo^TZfv=xWd}446PNlPAw0Br;FumuV)!Sv65EPgFXC=&dZuZ`geTk$yf%@johX!P'
    '`H`78VG_8En|>5B&O?`m%nnINY}az)z+=AYxUNgRi26ywsBN=|MzLqdVVf}<BT)ULgn#{!%oa~5pw!6L'
    's|{TnH6&kZX&-}^*<_gi(jbdFG05`|OTL=%1?4JXVPKb?*K0glD7WZafm~UM?i{5>U5O8W6P4Jsk0>r-'
    'TpHpa;IVe-ct1v0xj2Lur|eF1AJW%!mCon7pyAIC<ezt~I!0Ljcu33B-uG5czJ*S|g9?tA&))H8+p@8j'
    '#%Lt^*gRQ?m5d*2xFvg^8}+37^t9V_FLWT$^Tk?RxGZ7ohy3G#-O07e1+8LXm{ic(Jymy8f)&tl!i(KJ'
    'Q8!PYt5Vp#3-(qT!pIZp$$K(?Td#xNcK~VqADX=?rmeS?sBo4m_V9CA6mdjvW^=aU1C}%aR|Id2o?y!Q'
    'o5JnEysDwDaS4On&qk!6PRlm8x1=u2Uds<hN-t=pMOAfTJ#U?@()&~Te#OJ7rNilk!#&G};i5saWVnC9'
    'urJ0}*d$oF<|X*@quf-L|Muq58<JJb(VBg#Vu?Ci#g%2#5`$SlavbW#v;MdBx9F)t)IRAvLQ^L{PT&-R'
    ';uMG%$S)9<rwraNL!H-1-&<r<!RQwppY+Sla?guN4C<G!ID559Z)Xcw$-lAeLsCyL(5PAd>7&6=E9>(Z'
    'SzT-_ZC;qBJn~PIC1L0>j&zjwn=Fc!Ja4co=U!gaWtvacBzrr;)}nbaIk6AccNmVxFvLh(U$f5pZRi?x'
    '7F1TK_^2Z_T5J~8$3xcmDV28D*~|kg$(6>#h>xPO!Z4OQF9yX*b^{vksj5_XO)Z(^%aZ?o-l~<SIM;ZF'
    'HKFFU(5xo+PmeaxAeZh{EbWm>wfLkc*k7~c#{EwY&xT64>a5enljV{VEO=eAKgCBn2YEKj$nH2S|5WEt'
    'PjATLnvc@t<dm468&h3<?WzvIimzuY{vr`GmJ4F{>|N^F(I+74UT@g=A9~yqJ+`8?G||xv{N+pI%PrQ{'
    'WOdEg12&ihpp&GPu+1&1f1ZuxFz3eo67*a+DfKTkyFpdxBYp19r#})u-k+7OyD<1r8~y%F^h)9CY(bXU'
    'O^T(fx7$e+t;RF?x{Cedl$Y-0Sm>$lS_<l6Ra$``b=&+hpHF`MynnD#(c`k9OkJ9d^%e2e>Mm(0pW5%u'
    '-Y;S`oj1TUhG;Y>6Q(m`eZvhhM_gmYo8@vo13p6H8yQ`3zL*#<*2aRr<Ey?j1~8cJZwTj(tYA!HpnQWV'
    'WO%Q;e`ms7U$L;3FAeOtw<e;_@^>V=!QZqc^<a$oWsEoGw?ca`Xwi4$dw!R9CVV^?B44KTCa;Y%99+5g'
    'f$UB<EL&#l^v@Qv_2_86)L2vhi9GDK?H`+eqCuNU_5jdz{ut?!XRwWt*U2?9i#+;Rz2kBx^A7|z#LsWO'
    'xd^xQ+j~prTe1>`w;5l~(>pwt1>!IR6hgXz-{U*j*2DXX=6nx0%jxh~Hldkp*Ex6;u@@>sh);&MQ!H(Y'
    '5<`_f{fs6Xriab4Cq+RQ)l>507U$}E$DjXPUC8H9YzKpYMZ(-b8K5A)5uVefF3qr&EWiRk|NP>a28RXV'
    'rBanODY!p?BY@m>V1|#i4YIAoC#+3W2U@&>@)++__aKdMM;QhY5cp1Nf(9NzxNF76lARylzfFn%x!vHx'
    '7T3}-+;yf7==0vC2hW-qPDgXxQg>S24riO7?%**~)p0i;SA#_(staj>_emq4HF>3|+|G@yPpOf&&W(F9'
    'Pn#uOUgQn5w4(2p!1&=n=NrMDoH@19K0kZ;SQ6W^Ihd{_Fe#w5&boYP^ihWw@M@FYAapeROCGy%12!(Y'
    '1K{evoALLLR978iw(eUN{Y>`8#YEF0;0qoA7>@V{eDO7*Z-;vVH68ruBzkigNmXZsYTD#pk)SOUkCIKO'
    'OKHDr!!!sFbyo3J;Rsa69wJ{Fgjp`a9#6`C368EUa#@y=|6XFPo;`U#e6^cCiMvdPjFJ@|Mbx#vlfSAB'
    '+IvO&Qkd&2t^TbJv3iav*-Lj%wR|HgYks6$EAh`~7kT-S<Fw{;RPCYx23G@*pIQhC#@vcO^_xx!C_zpH'
    '2`d6mm!K;Ta8%y)ZYB7~5|amW8t#h=HMp9IQd3{FQ&Yyj{?&J7U(^`-W5v(?Y-eEQ5KNWCmFa!dCt1a@'
    'a_%CFKMsVJ9_hJ8@VTwl69r@&vodSdKT0X(>FqMb8wuMgAV0z1Mfb?+(?62+&CYXIJWDq#AlAblQVQJh'
    'PmJ46KF~}YmSyV6Pk(yy?Ah~Y)7L-0diC<^&GgliH{ZPm5{%B?zy`=3;-$S67+OznIDMNvT*HS`Sr2C_'
    'E3-`VQfpH@<HoKCljR+zn-&08T>e(>*_Ag@yHf9nC)5&}-rd&mKJp?<Y4%V~@Ip@TBA?(zF~M8bI0z#3'
    'D&4F>mM!OG@0@lKf~T|aA9xdxfUo8#5VOH=FT}SO>f74*y8yR16_EKg@X$)^4}?7a)2k;}&wqL|ee-hq'
    '^vRp&-@d&1KhtN=e|Yl*vqC<eErA`dhRRvO33h>*#%PR86+4`rONM(o-^AY{J{H))wOn!LH%t~T-A<ss'
    '<Hd>Z$5H469(9=?SxJ(x(DbZ0GULQ@y@Y!d9`Qqq(TI7>^=-<ci1IMvBKcUj#OVUzt@tgBD{f1)ootzR'
    'aH=_3YE^3LGq(bl1)*b^iO-pDo1Vjxkn+GJgi~snu^l9g`5rvN9TL(wuwygf5%s9eVpXuYH1mwF<wv4*'
    'HGbkHeh|fhV>xyVNQwxD0ZHUWzROAMg|TH(CvY5(#Ux-Rp`1pp=~^Bjh|nO^gauhQr@nlkmKAU>aTrC)'
    'M2T-D9tq+&gn3wzZP}p>Q%Nk-^DJgFo)C{ZJT{}yi@m_yS^jc9ql%m&H32>h)nDnd_#;P7rHIcA1lnqC'
    'yv7;-{NjL&JrrDT5V3Wf{Ab1Zz)$|tqC!by5t4e#p=0mk2}8YwcafZMw6sV8LKbSzo6W#`uPPsWm)`QC'
    '`hOdE>EiY5dhudg?&Ozr#>Ootgg9Z9k|_mN%I+b8E&Y8AYD3`<S=|dJwbM27_$nK~ZJT*sHudg2R(9nG'
    '*t}-x@x!nEHDM}^yKC#ds(#xG14ZBT0kaf+yvzADwQD5Xiz02e_krDgs?9AI_k8hgwn{}MmC>)iPBO|D'
    '{1w>wd|W*`Ej~X2u)nYvE-N&PilLI?B!WV(oH(|hb8`~l?lm=sz<<@%#W}ou&EQ1ii`LTO<RVRjL~AY3'
    'YFBpamvS3GWH;&iOg0S328dR*`9V9$$@Er93J_`}?D*J!Mmev3iyxHsf!JK%9y{XS2Nj(AC0TK%vP@Ar'
    '9?f>CL^@Egs5QQZ|5T<XJlpT`wC*ED<zC&Th0wa_tc%PV>7kt*XU8{Q{im@mEjZJZ-=x^_w5Uw`^=u(-'
    'mWr7BM<w7UZ~5K(bj6HM2hL5<ySp^tKi|uT$Kwfte6d(=)=xHTSle>87J(FT#bzRsypL{)rk_c+iEn4?'
    'A4tsSSRWYIGoFC<6(7T_-;nGr{3E+jskZ84<I};YR?B)p&9!wEejapQj;zUo8IslAqAqODafwI=xz?R('
    'zS)C=1gVr}nS=V6I1_OqfTfD&6UH%DKI0F@JuxGur;35hXu5d0nBR@Jh06avW9yqs!*$P%Hf75XS0&$F'
    'dM9LW?@U|vcoGx(Ru-8q)t8>6SQc=7H!>$?I6gOKhl)X+UE$lPkLj8$t^oryU4b090_$~?iOPbV=9d@e'
    'DOHUYzlqw(hxqxRSiXNTpj!&us}MM~3^*(Tu=<RW0AiwTHh*P{?;W=H-oK}<uW{#}dgBk<_xiSd3;o|p'
    'reh6*pXwDLwzFB|2kj*7Btti7G|QBCh3Wrametz$cnC57Y3eLElGMLc!sxsbquTy{UJEiElHt`S5#<Yz'
    'Rfq3U?~qWmu#oc{;p?r%ek=O4BVwh}kFZC_1>-1-b<|SHmn&VAJw|Dfw1iMDW3l6QKB~LASQn7;`717U'
    '&iGLalA%L2DWBWQOR0FItA;r~*`p8q6=P#xZ)T_(Yc~Y0uQ3XfF0!_zkjn@0U*uKCigwCvdFDG&)wuoh'
    'xzaE1>Ed#?>b-FTJc9~i+{T({qb!EX6ip(fdcU}-Vq;S@r~^DIV}k&w9tWGKuSN+L63@SVc_g)JX8_q9'
    'Xa6YW1w9=+;=Ksnn#?`#VS5xmIjA4x#=oq8a9;VK)vV-$gJuQ7tvD%>Xp)qf+>#}TL+qg@?!3(wt(kZ4'
    'kIHx~?TGV+nB=*!n+~~m+{OrL>)gY3)1Edlv%uR3ZLb_f<00dKnbb<5pM55rcIUCWL^$8Yp}eJ%l}8$t'
    'Ul~hE?j5)ni8~lTZS9|ZwYLV6ahGI`lsPUY3WTTc7ul#PZ3k?Y#^VHe(PXnkGv{f;dC2Gl_%7LRol*X8'
    'iDYG%-V>Hv8Bv36`m#Y@stZ;_WKj<6;Np9XQ$8X--5^zC5QoX{nzR=BXprYGeLTP(t+{L<7q!H~UN7y@'
    'v18Ny{?(Zd@^lv-eO$zvx7Tu{9oZrmymOtSenmx;{g$`VF6DqaDEX=7p;7sGQ5`((J!YS%yUE6+QspGi'
    '>h3Y*-Xx%pMk`VMxPz$Q4r#!czxBdU?t-Y=6RqZW;LgSFB$p`EP_a!Cna9*;mW9)D57W%|O5b_j6E;;<'
    'v9_}msr%KSc^iRqFa_k%LGz&Dkgmmm1Jpq$R2-DuZ7?GWc5!1#uDK|@Bcd<xU$8X9rC&B%aZE3}J69FD'
    'h{3QCsVKE2<PnIO-#0v4Puh+4`u%K8#hv18vq}hsT`zCjWWZ<hIR@*qM=(mp*K6Eo#RTyAce8imdE@{9'
    '(PqfTAW(&<kBw0S13YeKnoC(wwMAH=bBL+0o>~s{F-u;ZQg&P247+-3(}@i$pJ}5Bv7Tt}h*@hpVh1Qn'
    'lo!cQoP%7Ep#|j!--Ghj7(70^m#AaMz;wsB^q{bG%WM~YCo1*HZS9iA`Lzl9*K(gfZcVrsm{m7=i>3H>'
    'hg8q+9tiFqH1`exMVJ+fYDyd%wp+Srp7`x*#zr)qZ*GxE|ABwLSo7P_gfOziO^=7Xv)j$>rD56Lc>G(r'
    'siNKCr0<(_^_<X~(H6nul9kc%C@w!r@0!elyK*7-loa%j#GeHTgr3O%n9SIt{)c`tG?^dmcb%wUOW5i$'
    '2>9FW7N214z2fwpd{C$F-~lA)1l&~);azv!Hf=;#EJM$3YT8W7if%1<_CEA#m0pAH%w$i!?NpWN{NO--'
    '!gVQ4w_us=i*0Zy!&wbNqU+I3TT#+Es`o`Tl3G?o{X=ob&H>shYn|MBY5}NA{`C-lXZsJ4_7iyjIm3un'
    'jurOTuRrT~a&%I`+)FN>SS+_NbgD@YwamP)3~_sKaOOkBv8-N?-wDlCCnT;2luN3Yf^?4#W)EY5XwJT$'
    'Etq`0<1A}dkBC>OamNP9?%<KO`5BcYZ!DNlgy7q&>?({Bh(|RFmO@^#D1E<6a`}%kqv5r3n)w8WA1$_5'
    'rRtZbU?Mvy^7{v@fR;fpZKk&rM-7E-&kaFZEKIS*S>dU)FOO64rq(n1mY1C=kys?EN{&R;+M;`!_^Xwj'
    'cccvePMU|<vZ~g;wC&Z9+hvYg8<-M(mDS|ZTCVlnXj)ete=TybB*%)$4`JG(Uj83%h1=B}sTS6r!@J3}'
    'BI&b({6dcUeIqa9N$t?a+#jY@x(6%oL8o+7Df=}_3-s5d*B9uiqwo@^R>(r#jpW{XsE-<I3GE(~OE=xp'
    '$*{k#Kz#dMdwA2z@-}U&TjaNvzusi9ld|kNn*j=2R{HRRIP`4Kv18ZwsBhDRa6j?=kS8YdW0C}(#i$Lx'
    '#zA0OzU?KE?|HFhaccY2JYMO;3AmfYeqegO2OvmbCl<8`Gr2{**e28^NkSdZ_ao18y(ple8AK*?d6+nn'
    '%g%J-qPgBjWSbu2)bd$Kt;pt1XcO1>d7Ola#TXB0<iK<j+YT6UX%f1GhrUlOn=lqxZku`^e!1R9P_6gT'
    'i`*}lT$Z-!NN~sYgCL|1cl;#AN+u*?rXTp!W1+($-?AgmNn+Qd#3g}aTaje}TKw2{XcY1m1m_m99GAt8'
    '<9Xb7sOg6Zjol>iSR8vKrU45GHBC1RsqeWVi-_sDjuY_^v3#Z%8_guAfoJ-WMcs(_2?r*(f`pPN0>%zw'
    'V0f5d96O0?a|XEa9pCa@pE?9s+4bEZY(sLlOmc4k$zQEf?D6qa%DA}k^K_Li_tYG+xI<mnO<dmuasrV9'
    '+a<uo+>DuN+P3LBzGnuOl`z{0Tp)`J+>j(uV1`~onTDD}P3gofnUez3c|qg?o_&gB0A2}*nfN5MV-lDS'
    'ceza&i{TmO00S}R1`df?82FLHlH<&Y#g{xFbKu#qTFZ2~YsRqOlh`qt7t_d(BiQwJ;KOG3{TRey!Z~wI'
    'o0>uFxf(I?`DzbYWyZAj*B+`SpU&2IFPG}{YBZ9!vd@kD-xrH@sq{sg@;FDbOgez5WPY@HPb>&lu~Q49'
    'Si&(VBF84rk>3Gxer$2)jZ;5w<q56HbzX@9jD`mf02YwuDxLG%$62~szqvzy=!Gb9Vzq<co!ZjIKF`tm'
    'SDxW*PngI4(GH-#<ss5krXYM}h`ahDB*=`+e?dOZZ!H`>@6gTM!+E<WYwx^P$ujErUWeg!?mScq;IsfR'
    'WG8->jd-^I7D_qtc;1{xReZY-aeIfY?6fx1JBgUMS1Hk3NOYAEErRdUTk-)<eGbB!sE1yyK;^1yKN1(C'
    'FHJm&fBYCQK5i%7V321AX1}cx1>Z^gLOfo(xYe#0fv8YjiSBLxcvSgz8yTy9pq>)6Js3e2PYe#0;rURU'
    'vb)ZgFt^tew}~r9V`TS3{ClPS=}3Qsz>NbJ$N68?rRt;I=PFZ>9~_PaCX<@972&YTCj+BE9og|9H+C%W'
    '^9m#1tA-?tI~46A5Gu;beJMm?=>T=yJqx8NrGw1p55^NvHY1Ssk0*<?WnxtQr};d*cEI|jsg720JgIod'
    '9Jbd46he<$Hl1H+U#ntEh0fS$N*UXeNK+(ssAL+vKq;yPc3N4dhhIyEDo+N*Rra6<KjlR*Zlxp>f!XzB'
    'oicJK(%vNdZoeAI@5bHh-<)QboM@ALraiKE*oO~|?>S!@WMS|R7*3e2(YnM_S&^fyuxH%PU~6D${Z)D^'
    '^2Qe+2KSCu<a8fM;C^smN?3SCjIzmq?%8%84+XD0d?NJGEx9wOxHcvmRo#-shRkL9It=`vD=t(%bAG}k'
    '@=)qLb8dW5I;X}|88TaBqxUy_#V-#f%LpQgrfXa9pT@m!i;wn64cJ`&QD>V6#{c^D*U@(1@q_V@YuHup'
    'D}n6;v@6qgeO|LzKPJ_?<}RK(k8zhlIwdhyGpPn9G#-+oN0eSqZtaAZL=D|zEG0SWrfA>Iy<0#^Kz<-^'
    'E21u|jZ`Yq)ut@hkiFjpqjJ{wA{BOcQ+X4A{&Q1akq(aK2<fvhsv7x(g0suB{ftKaHe>sPb<r&bTYWs;'
    'WNYy0R;oPfn{+v&qS?uw132RIAaFRN5#e5Bo5bZ-65BTM;8POXETMK{Mv=u5H}Ea$`#g+D;F+Nngf^!G'
    '58#S<Z(Ee)jZ*ftDZ%4Sn_7--CY1Ud{uldRZ2M8b5+_bv*YZs2d$t)-+j3$v3WCIjRWK{@T#Gq6W(?X3'
    '6fDQH+ox%|Vp!(9^^rDACJqP>yeM)Vp2SHMdJavZ#Ns{;Y?Ij@bt8+|rseV|^n-{6whJVQVP#=RkDnUC'
    'qY1YiPJ_S%m}cw;p+#Lgc8C{yrcK<?^GN7KZcJRCxGeTUFW{Vcz7xkmtQQ&02Zuc5wi~#K83v}C#HQ~j'
    '4s*OP;a=#lI3%VCbBbw5fT|?1xl4SHMWM-}#19B<b8zUD4-TWAC)#3-^|JphNgXpk4me4~l1$%D?8sw;'
    '1em|zgxut&Yb6fsC}7zLvrDj5jqAX6BfiC~HrWd<^#dSZ<isA2V`6ho!vuD%>xU$YEguGT<H$`yKXQEL'
    'J1p=#C-frEWf39lOcNSD-|4VZCbDz*bXYc0D0j*hts6x)=B4qbnw2TreHMKcjcdM8NgIcXC>duG+@$n4'
    'b|jP^3edu362HI~yD50bQ!h)asO2Y?2mOz)4C^qkqj8CQz}G3!r4w6+8pa*!cA`3_yo|x^e|M}I#(}RM'
    'K71&uxL>3gNGLAeY_FPQcq3i#qOOeUpi#bQJrVcji&u_}ChyK;-2{Wkq`!wEbRdt!&>2YbTR1TE^@=Rk'
    'ndp%s)0we68j;4|p*!z?RhYpkmpa4bR0Cx)H|U&X+5S=@M~yNCj4w8~hPV}eX*~aZL)Ju=(xG@ye8#X?'
    '+B~nwCu=;M8*M9R$PrXO8&&({I|6D!4AH`9R1miPX7HN)%NP@>wzhLOIHi5r?L}JLWoUJ>UVEEt);Bm|'
    '<k4OLWYFsgpy7%mH=}p>^NYpWcU!>O<)KP_nWi2-?XCKpGR9Xsq){V`A1PV&RVAyxZDD`{@!R*yS4$pM'
    'kz0P~N%@PG!|ft^3vu_m`zRz-*+!}uU}dwmE1bg1Z7fv7Xt61Kyx!CWya$-Au4x6LC8pE}BQOld8XBS<'
    '1ih4!Q<c>)CMYpG6zWmMQC<y$QYPl(4(~NlvCI3igh<OOUga0dR#3bCO_gcOLSpUa``40@@#1=sq8Q16'
    'z31euYTqOU;iyp(4jBTWV==%>QUBpTG418t_z8`OzdUZoazavrG(N`sjN_A_xpBD1s^;2}!f!`FqQUcA'
    '7!#>jA*^dYOZa+r%Z)XdHrY&&FfaR)&e^u~4_4x*^Nk3SKY94|!zYs#gI(nXfsD7DFSAnhpp4w|3)zji'
    'FxBuD447K0%@V~v(l8TeMKG7mEuVBSfolbNnz-P+dADo}%N_0YUAZr!E=D(Y?{0U$sAvc-K>h1qGRdM='
    'Aql>&eUd+@_AWf2erv1l8}{y_8qdkU^E+Q^ySD12w|9LXcdy!(WoIrlTSqii;j#)4O*fTPwu&(KbIYOB'
    'NgP(w7RXMytLg`jDwNC#sYi#(`fOMpZfelYY6YVz1yk~7TVJW$8t}EdbnR<%suvU*zse_t?r-BJDm^n0'
    'BPf_ecdy)g<ZQOiM71=KL?EN`sg$X6ZY)x;`hnc*_vz|wOTVv9fIT(hn<%2be%yg7l3&gxnH9+Kc~haa'
    'D$&~9#VnC5pSZG8)IdkepH+;*?eAla{M}S>dzx3yxHO8o+g%ubXX93D`>S&DsiYh7sQg3&k3Iqa9Jy2`'
    'P2>e$Za3LFulNVv5H=AKJe$W#aJv}qZ@@4&040S})rCu`cFt5#CMDNz5DV_7hvItuOr?jB=zTEHUm3VW'
    'fOd2y<sI(If@*d6nwPa}-F6`Nwu-3G;e$vmt3Pz8Kr|3LdBvlXqD2MV{#b~qT$|3Jp8yRz(e3lCNts_q'
    'sFgH2-*0gs)_R4r%htQ9l-j=iu*!FPLZ!`sDQ}o&H|H109P>DgY!2pvJeR?+@&;EYZlK?+(nY$-474KJ'
    'lu6xM+r=aw71nN^6Vz>)@S-YS_z&SRqhval&a*`EZ|zH6F`kG5*9hbB1WPGpH+f<3V#4iH9QSg_mj35z'
    'tevt~U#Y%WRsI;n8)AiNr+kQ_hD_GKh|IpSZ_Q|t<db&Fb{`eUKR=R(zps2)k1Aoi_ZAc;aH}kGdj-`t'
    '_%|XO#vrQ|c=$6B8rX<jnq)H{mY~`^t-5zPSC<qd-m0Irt#PM{<-qI}NrXZ2e6>ou_38lhlmTGC0}F0s'
    'Lau<V^KOO`Bg0!Kj|^ZY7%=xn-iyN<u&5>-C;joiDf`vwoRsgwEUTa1b1g#^L{X?|uj$*p&`G^l1@&}G'
    'uKa|%gH_W&^d3a4M3u?`r<T=ucIxYYY>WvFI=$(ZuJ$*?#Vom-e4r`g%T@Yc50|oN#AF$Nz+aCS1_?ul'
    'yPjhvF(pnwgD7T{xK2W2+l&%7Nn(dv7G+5s$HYk(HytZ+s6`{6CxLZ5wI-p7WBG|^aW{^=*oxvHv17|;'
    'NkF*eTP*Tv!adGI8vBXm`w4fgIErkG^Vsw3Gribo&am-pX3`{z5}$=;9Jn^I{Wwk{k2}mYeKTQ}?|C70'
    'xkF6ff`ufWYq|+f632^Z(k8>kHY?R&0KGj^souakvxk^Tq<*U;{=HhIY$GNjzTK1lM-vj*HZ|?ok1R9h'
    'w(UA$;@Jra?I4U83!=cM1V|IJggRE_P&a}nsp&h65qDtvUwsLx)(PG$el2QA0R^uRB$*#tMVMG_?6_{?'
    'g)xl-o5TP8kT@Z8Tnor%g6Jn+KwZyE%os?;LMw<}({s7yM3LER6`LidqU0N@d$AVohCT^hH}bsLw^;()'
    '&Y_MOg;8R{XRc*atW8710Dg%{5Ja$X%ph<r&Ma=aEw)?~MM3OaA+cHLnPy;`n8;}-HizAwgmGxa0p}KM'
    'c@`53Fvo*9bbTI>IPzW66#?MnO42?QQP0^w(es6En2C$9ySt5;7PBK*A5aD6MS%UR#573|0-*vY00LRA'
    '6<RFd7IUJ&<jiKwN)pQifnoc{G2ruvgh*wV+7V%qNy6CWEDQt3<DTzY%<_0bJ%^Ie0@>$Aj5@y091oLp'
    '&CVE*Tnvox^J2E%?#eukSanB##^V%pBR|B_7RW`$V%rAsXopega?edz;D*35mSe{O5DsX|P2zK44;zG%'
    '8QPRP0fYT)F+D8Zu%5i;(lbue)f;jxFV`Jf3I|PM!jwrE0*BdQ=yTt79p;$S4r1blmKDOUcH-d59Mg1T'
    '&-Id!Q#Xhl)<U;XLI@8Ti7k_dBw~I9+)fh<gc-A9$8s#-t2kspdgA%G9f0N`4e$jJ__QBd^3>|5H=MrB'
    '9<JfTDFtdzsUr8Za3ZFN{xzQxCa%e)i^=kC7f+r=g2Z8g@4;F~3_8U%F*zLM18jUimu1<O%L3*m5f(_Z'
    'Knrnd5<nk3N_3L^_}WyJ$SG6I+_WMWh-m}4y@XpfY~a9yy>5bRwqh^j%p^RDLf>~h_!g+=Qc(VGK*7>*'
    'KoJG^yrLyvDe7d6iwXS%%huU(;)bCWg|<(FBnHK3d&~iD3&2<by%@U;gts4uSfa`T=>l7lGTS}%Vq`)3'
    'sk~${&BOG-d3ndBohAL0F8FZ~3PRchv6z@3Va&v0+>c<3g)~WA;zyvE?8pXb?S!t$sSkqOf?a5X@bp3R'
    '5>MX(Z<XW$mIKi<U6bqSQV5?WYQ<o=afgE*jY8N~CP{q9#lmim2S%&ufDQnr^9ccc=$RmOtRR667g{a>'
    'yEh@ng^r7*@oXLiB;+2jZ0tAz-lQ;@MXV$U!QQaU(1bkz=n08$yEHI;ELq0wgwx;zh(QOQzn67SrqU&9'
    '!c9PM;t8W3w;~RfzwgGtqoI&Dkqc7BF#&xHp9{c7aNLl=I&5Hc!p*Qnp*0?Xv2RC_2WE#CB@yL8;&YVk'
    'b_}+c=LUcwPzW9vB7qqs@I3PZur6KD?~xzs!_87&r<f9ONy(}i8z7J(H?$)TBFT@ygfxlc!Q{-?F+(qg'
    'Ph5|hNf?0i3Ox`5A&9RS%n4@3yPCG)RzVDM4J=fXfvpXu1$Y+>M4abhzJB63=uJ3r;v>Vl)DHvVIX*+T'
    '$KoMqF8$cRAmLQSb6V*p8)ic(bHEd%ga<zHSQJ|nEL1-NX&yv24_w~^FV1v*LKzQD%MNTe3}9<Gadc|o'
    'w_O-|<x_R?(nxNPP#*by5P=ByVZL$b$4L;tVgm4WJz)AM1`pWd4D?pyF`Gt-?M9~OgSEoiked<EZ<a%C'
    '*kUmO$CpPT1)9^y0to?L2$-9cSQg$Iv0Re^nOP9R<6w`%Qu|`1><8u+=c_`e9W*vUPT3BHg<=g(@XUQT'
    'z?&~22rtlIHn<}pASDdI)}%=oarAmUo8UDzaO!=%)XmpXuK!d|Qa`YoR$9#kCxcV8onZ}F{u4`Lx_;pC'
    '0RNvPxDi3w(a^)oQc)O!Sq-8J`~pyI;o!B^t!Pof=b(#gqetiw;({3sjxL3HxRwi(g1_;SkL838Ji}rZ'
    '!-GK_1rdwD@THu4cGQAxJsz0}b9^s=|DyQ?Dgk&nbX>4<OtfP-)^r7v(*Xu>WAH9bkdJsr(1ZQ%4@F7o'
    ';@crac&-yO2aK-}3}5hI!Pp8-m`DK1-Q-|#aOQ(Xv7OjU0uTNJZf_8o)OEtx4{Yl+yxKEx;exLZRuxRr'
    'GdXdwuyPm$EHERBa1R_mkVB^B#a75T^P<S79>^_VT%dfCuof`@3QETT*%n906QHzgP~o7Ay@XKM!88Kx'
    'Y=eVr<7LzsWFDBT+yfS}0@sdXG88d;ubB+q!ASrp0nNjh8`%-w*9+~Cq9sPm0Qdv`1&SwNiGhs=>f7@y'
    'H%thzUE;E%SM_!l#!{L+M2F!bcNi{|3v^MqK(}m%!b$A;KDahsU;@TXu&@{yLfps8sEOx;;2{JnB@?g$'
    'SOShbJPOmbn9YeDQAZEEHcY<k?KI3gBqR*Lv2;Nxf+G$pjrk-1<17XTp2UoR5d^+!VzST$Ef+^1OMzv;'
    'dUOEYF4H(~>DXLI$L1n;Y%U7NW_R|j7$^*VG;*Va_;Jh~4D4DIi(iM}f>V~@onjYUQ>-lvs|zgC#ahIm'
    '!NDkIl=NClZmM4hALaslm<#E{Je=Jw=lr&~Th>4l5)q&UflcfX3%m{=bQajumdAbHO+YPMHi<k?QXs7Z'
    'FT@MwF<$evgU|#Ayp0OL*aFx;;I_r4<@&AzsNexJgCGdOhzDT-0>t-0Y7y5BBG_3zd=IWK*!7@}x}s#A'
    'rgPv+wBwphQ>sk8CPOX)v)XiQGlu;|lYoMn19gCYO#qgR1K)W-Svv%27r`C`Jb(oC!Q@Lob4End&QeR*'
    '6ZSc1Q=1;RUU9@30~sI2AVtDZC^gV!5e0|U1Dnf=u;?|Rq03FYke_%2=nD=Mc-9&huol8v21S4ZFnM@{'
    '&y%S*3!df;LK{|L0p=6%tU>W6;Jd_O>_iDQ!S_u#xQ$>|c_A1~7MhfR{TNgpIORSG9q^Q0%RSL5u4n5x'
    'CvUT9o(U+oRl@>64xry}ag)ZDZ6-Dl103~)`LLs0(9X6=u^zljJR8h;4+H?L#<Ur=!5)g8<J$@xOE;nv'
    '!|Gvx$7qZb9@;VNufzpm3QFA-v0KXrGX;!qViKQ#ixq&j=M6_+>3p8PPZxXfu-YsH;bwFyHdkXj%Vw}q'
    'I1NDchY4C1;DMt9;DTT3VDKWbA`Vmc5)Y<q5^xO?5=EisgX<bOK?`vb_#Sw<gmCb!{n&I}%3Lp|p!_@v'
    'F0Tg|K#vR5x92++@o3=2l(>->5papz&g(AGe<5-|j$<L_egN(tC}A)pT>`QJY$D(Su(6#0{9Txu9RwVl'
    'Bims<>OXLcOt5}^AdKg?s3`y%J_^Cf1J=jWLI>Pr*8<RZC=<HyU%)i=!3HB7M49b@LM0e45r-6D9-e*r'
    '?N6_sTs{Bk&GgO7>C-1~o`3uD>i<k%UOjt$Wqbwr*@qTHnG#Pk@D8TMbD)42JoC0BU;ishcP_8*-Yu^q'
    'S;d>kI}q0@Nqst7fKtvxIJh0W+T_$(t=g>ZKx8V${*IIRl&moSVBUQqjZpev2t*i};bo*L7wssf3}C@r'
    'x=(2@q<+)VK&>VqeI_HRPSed28Ta=M0pTvQV}+nr3vDwmY1<;W3kmK*g1abzyO7{62J(9ohqOmsW#cr{'
    'wHGjbs4VY;H3x$fbwB)fA*R{~dGPWbSVXsEncEP3;Y~oJ-)!QCn9iDjsK_2l5q~jDv&r4<ye<E37M5e;'
    'sR*Af*TrPoU`I6d5a|6o%t5rc!g_mo)t0uyPd77^&@wuC>@86z1_oY%O~hpRDGqi`#$Rm-{B%CUD-Z3a'
    'fs4rD<)B2fFafIbdg2vXfI*hicB@$iag8viVNNJq1_9bb?IE!8)@s605pAY=L$jl)*kOGkAuXSZZT~c7'
    '-FcDDrq@`9t%LBFlST~8R>QCfn}8{!eEMEgB+S~qzW)qB&2CYY)dok5TrbiLEWi$nJj&8-Ks6*zyaG}9'
    'wScXv$$c~XfIiK4`2gjJSbr?krk}_`w##TM>4bpEZeYFYJ_gP+O%i0Ytb?%GS#}3LZG2y$?X@&^yFikb'
    '<?BtXobu=IW{fYS6wf+sogM94n6G%T{Cewbw$}<fo=WGL9CCT~q~M{8P(lsH-rJI={@yd}<vIT*UEOA_'
    'U(ZuDpK+`RaEFy4+q`-pp+gV@tqqi^SlemJ7np^1T-mnD8~szeJ^!M5$Rjq;V*L$pNb5Z=6*UE`4&Mh;'
    'Y(~0pYOd#Ba~XbW`wE^NZoBDq8?LC2QY&Y7^u>DLMm!=|v2KIcVf1@jQL5TSu<P6XhW_c*(|#}RYkt@R'
    'K(`6x8wP&w{EkSDeZE-3u78TAaNGB<QgZwC3ao#=>LjS}y%*rpNGa9n)zS&p;vLDlzxVvZat>yEw+X+#'
    'NtcQxTE8RwgRa<-9!6czG?X6g0p&Gcy~BPuts&HQ5<t2|yQMn-KwW7GJpjDk-uW(<&uszW3Q#b+<(LAE'
    '5MFKLS#9a~&5Co$G=)>vLo6)flpq4GJMmEd`Wxl`KLP!btt-tdJHvRrxxU72pDwOM^yn2?@OgV10}MdG'
    '24Br`Tdk{kB2MI=Y}hP)A}$7YgCQL4d`aJ>x4h3jR(kk5a7McG;+B*>*l}0NYXQ<l$L|5rTRK#E6V0mr'
    'FzUS79?}kTb(_e}>;D^U@&%a>fbfQ_u6YOk+GXtyQVtYq{$~5P)Nbg(fyJBM^io+Ib>6%Ai$9XpTfXip'
    'Nq-XV7}z+gyC2A+vmh?HR#!86BdFZXyV`p2PhN=pvi4HEvQ>)Z{|J83JnPJ$FJ${V(aWwQbCze{dVAs8'
    'Una?n!l2LJff<qYvWY4n`q%-mL%O{tT|VF%u!?&as%3eQi??!xqCtTAC_NRa>1v9W5zy6D?ljGBfi2cI'
    'PdU~C?D66cqSAs;&Ar4*Ukp`j+}^4j-u~{*n^*0fi(Ki-+6o<{nHYBG^<Eyv4wTL|#4ZGw0QjPvA|xP@'
    'cs9FUbVEV;%}&BBC)xAGHO%z3bBIA@*1lW;yJo$V&_WrXOw{d^SN=Nb0UW=(Fsui4Is`Z>yq>@R<EEn|'
    'tZcR0WeQ5<ilb-R1&FL|{WW3N9piW91o*xZ=KDqZe$HWNp+mbdY!SievdhGZ-!C{5>?W}`>x8djSlQgR'
    'o9|i5BJUg^+IpGaZQ{;vmyS2ulUO!=_&b@;`MOVRDn$$B+s%ye{^JU>uGgEtbaj}voozbnt;2nBI=$ar'
    'X_VI7+3_tI^7*oRzT9us#Q}|IRN3cEv=chxtn|JxBs;CW>G*UD@0B`&mmYh!BbBmkD}vB{LPB*IovrL0'
    '|6PFT>c7|3TOa4R!AI+Oj8H0hkx%5ibhFC7nejR6jEx;IT~517+U6=vy9X@Q9I}4)xC&Z#RhDJOmZgdM'
    'vD2PzQcb77yLqCOV=VB#{<cZi<n`wEmaOjDos2gehpBvc#0$Z5cP-FFf5!Y0(d+h+^(L4q$ge2&W_HU3'
    '(`H@ap?P>iu<sygpWRS-{cjskG4gOMU3^VeT|wmc&(!6Z_7?iS(|n8_3<dHc%Qk%5<$eGplnUTD(bY^e'
    '(QGYR_JDhhrI`4t>pp9Mrgm)Ux}VT<DOd`fF_)i>=FNO(@A%jA&FaZY6aw!Gtq=!4U<T&vygzmqFjeV>'
    'N40Y@yZ!rYeZyAdeY;TgURXlH^oLNDEqy832(uz#dPCdsz4SrqsOOIY{Y7?h8-hC}Nnepo#-HA#E%o0a'
    'P)aEOeYRlf`_8~h5_!nGLoi*J>YV}9<iIO}9h|X4Tpvhf!QNjO)P;L~$lVvvuK4T>NjUBpqJM^HUi6y|'
    '0=Yu>dx2gBVVwa~rR^`Xyis$1KxjyymDY<`$11UP1ad$J<nYCbE;bpz#`t8bRNh0Q2<>nR*j2r8!VxN3'
    '<OJiCCGP3KmrP@ggEU*Kz1g$bZXF7)K{n|JsS&A7f>1N~vWV0OdY|w-#Spnz9Sr+GX~bs7w?lgW(GeO0'
    '`#J`wd9s>7*1cODU>jwKM!;2Rq8ae>55N~sHtRGa@3>~zHLqJU^d?VS;}D1ZX&u8H_OW%0&?JU+ZKb*l'
    ')&+N;0M-tF$EY1JLhb%XQ3SCl!y)=UbhzPs0C=^`VyxoRQzH6EO!L;3I>(^mVl~>@)A!qei|zq_7eN@E'
    'P;=x{srya>TN1Wh*i_dLnY4PRsSs{tK220t(o+nQN!xm=iFMTVN4)$LZ`NxV0K}#)z>Yax<Lv@i1)C9d'
    'e{4z^S*}}MEw7GIuY%X$SN0YPO|XSGsSjd)IYFXIAKd*hP3>b;yi;w^cg#|4kay#Yx<Oasje~)g>}VaZ'
    'DhBjmfO`XrIv_U&8g&A$1Riw(-nBaiLvAtzwE!(!fP(?<GyU`d-m&>QgRWN2L&N1lSVk9H%c!AzUSH6{'
    'Cej2iFSe+xA<a;Q9aPjo)B{`@Cl^bUv=4JT=%TQLhCx*(&jp%1edjy8YE&6c<*s<ALKb_WboDrNRA;I{'
    'LVGO)1Aof#@=5<yX{+?Ln|YDfJ#L?C)CA=lnbyMcI|KbP7V6NR&OvmkutQ&1+beq_iD}p}ckil+B!;$m'
    'u}yg*H^Ol5aVPQ!upyZlWjGpAGbGM)XzzNgPhDfl?XD{hBJpeCTJ?nVT7=CwD-w2lACgz<hWCb2-#;&x'
    'G92C)UNfWiJsd9cL$4Fv`ttgpdn2@0qLi6RBOV6oD&4HPxUE0r(7K5|`vR$OX1|l>I%}TbP_j<Y6AmGi'
    'zzN{j6vGJ)Rm;0Z$B}AHh7JW;xeeMM*v{4EJZV?})_m?+PqaS87!~ny%G1gHjoXGoZZ^kGF+$ly(+R(}'
    'J5|*Nog*}>NSz0wb!+TIur-7y_nk3TC5}emySE&)06#2?bRPcgwP<t>(kSh84$y2#X+0!uGO)CrW;WPe'
    '8sSz<F+FFa$J^)Wf~_u^uqja-dde{<Y5|>)(?a}DZ&3cL>dYF3$bh!f#gdBpkgL^Z*(p@jxqH+gsC&FZ'
    '?eMosT<0m;Zn2~jfELz)Hn>`Cg591}C8d1|m_IME<(@9cWfeUf=3&jO<uqomO4b6sQ5S20+^mH498fiB'
    '-{A*J`qb_Y&|x~ab7!X>P;;eskt^2IKo=@i56rDHy%5T@FVu1*{KX=}QsJ1ma0`&+rKPL%ebzHZ{03$Q'
    '@SgExwwQISp;`e~Dpn=0&JMh7*SOHWfz;hq4vX-q$!&8?^+&N9rra@BwBHNdM|5qzU;`tZ!j7LwGL#D5'
    '4>l+p*-n>g-^IHg1z$#Yubhag+)`-0*rHX3<dVg@@W52S=v)iGK}Ix#?0u)NTH{G3S@jeY2g^qFj`=F9'
    'g>ob^8bX`wlyTCgnopYVa5Rul#|V|mg|hac))>wq@@k9`l?kmcPh7~*RAFe!5k*CYM5e*hFF-F>JmD*>'
    'CWRe;R$QjsA)gMF(pouZ3%<fO+A{VU#fmNurpzLpVKx|+xjWRaR7t6X&9~&1WA7`KOxQUsqEZU;ivPZu'
    'iGax_9(;GZVRrq5eADbsa9~=cjDAbA2_M5v&4Z-VC5I0(uSP+?kD+xN%(A!z)=CD$lMhw8t!(GK>#)d_'
    '>n)fMQd^fKZJ>fy`&k$Eo2_Yu=nH}9AqI5`8%5kSM|D3jdkEqn`?ndQHb1rzyzXOJ6(GYJk*mea%^Dm-'
    'O@~sl?RS1K(tGb6LWZvJ;EU3sjV_paFj@oJ%LdA&*OM&6a-wU_FgBbGtgWV$(vvkXd%O`hY=#wp+r}nD'
    '0pturHkqb4TWOXWLUyJ34KuB36gi!BRa*b)2FY=93a5P!#x%Q)JLUr^@r}lF=p6h?@Y3{M&P+q?lNxrk'
    '9boQqk#5k{U8Tt;DN#?)kw*?#((NLrTVLSYowU<%K=l+m-DVXkZ@J=YJpulPExT_`y1gS%i?GTiOq{=9'
    'T(q1!rAU}n5T`35UnPgm3%lBI(*Rr3KCPluv-9wD#YunPVYi(GdB<7jTNw>y#L{&6lq?AqSL5~Oq94G5'
    '2Jb}fYtimN^Nv0+?^En(3M80PMT4HnX1lcmYGfU}-41Zz(2KS(*Nc4p!!iT*@b?WCJeMKiQ)rlS!<G99'
    'D@m3S%YuJI8PvWUbE3&NGGvJk`jX{}K7U%+P)zYc;#9|Z?9;0su|mNWSzPxhbX~0*TmscM_>{LuD4&uH'
    'R3LIza&3B*N6}13_QiNjZ#dhW=F-ak(KIWSDgg$aWgeCgtJ^8=<i2^)JNvi9d^#e{d$6r5h~32JL*>Kj'
    '_5v|FFd?p%tnuxNi=Kx)t`6_+#h+5JRMOQ-2CGh-v{0M*DVTTx>j7PtF9?six3{$ipKe!>H7K54WfYwC'
    '#dg-3{0Nck`XgB`0p;D32P=x?iZd+fA)FEHd^O}Gqdcu)%v+z;X&jNte6=2t>=Nh{TVhpUX_`plX~^>U'
    'k!KmvT}rD?Po3wJWn2&3ty_d%NQ7z<>~B_NA<LJ(rdU^W*yebWz|1IF@n@XQGQHvRQr|#qJ@x~+1MHqs'
    'dF(6(9E1L5#XkL1CxDiWw<c7bVw;m3MR<!&;0WD4H2gJWj)_G~V_e1bJuG877wc#Zy1Idisb1t$)v<#L'
    '9(n$5#xS|9Z70(`+i_bjaF*T9K-|p-WL>?wN!RJ1l&f;f&262vY%^bHL$q;uV*Lb8ZDKMCaDwpv4t-Cf'
    '?kflxuI>+V=gA7M=Nzj!wpqr_sSYr=a*QiXO%vS6eT|j_`$ngIQAW)``(i5|a}4MZkE)pH53_gR!*s9l'
    'RPQeN3t7#ubxY3(RTHQei;S=Or#6)d{VZ=Vzdl_9k{pvKjbJ^;q%{44ZV%q|iMtw(G|8bFa!%4ppn<!!'
    '7MkC(<}l}}MH%loV1G&h{W?rQY@9t!5%~ae+d5lA0Rn*;Q5{@{9|dxT-$kgi;Otg!tZ--h3>5o$B~ql?'
    '1yW5z7)Y=fs;8Ilu)b-JD_wO!ueRk(`zD~`F23S;H6QF0&~r?`eA`{OmcY%<%r(lLohj?OucR*F;64!A'
    'L<ih*+i^_T8UnaUCgjQQD}n4Oli1eLF#r%Uy^$D^^08lj{VwFSK#A~<;U7$eADFtof9LherBxXZcySOW'
    'sP1|UaF6p6{X^=ZzQ&xtxhidtXGr%;o84L7)8gjbU{GEAE^fuq4yY5Dqa|9L#v`saJ@0)<wt?6uK5uGb'
    'QOzE41vlEtc<o|Jqip4pCxsO!nNk!8*O?`Z<)kz=!4av!^XWArWV%)u>2Dx5?r)v3fC^Le64uJrc=C>{'
    '$x3K|o_8L~2J0LCVLhY@b^)ZYc)ORJ&TY!=>bgd0cOm?5K=YzUf8GiZSu3h{i303*P~fL;!{EJm9%O3E'
    '^_?h&u;r<t)pr|Kt<7eaC^(TCsN&%ifNT5h1a>wN2-0o^qh9IXgRYkQBZ;W(_J7lk)fykDP;PiKZOP;6'
    'rBbQ@$n7r!q5-PN9@tl_&1{W=<SALL?$C4XC#vd`JB49bA4B6ds&f4rfDiThdX-sh2=~9<#CQ?}zrDD{'
    'R!4)%`s~2OxZ1ERg+0?erDL#X$WsPlvtq32Obn(gxLGAdUsDqq?#Vpf+`hOa*D77Vv!S@7(CZNO<xbTh'
    'YZco9ZfA&P=_sZr&I83+#c(8+VClu-7O<9<j*a$($Q&U!+H{G-$uoqZ^07AkL84OL2S`^h7Vl;f19+!%'
    'wj3rbccJ!;lr^;K*f---%FVrlo<ee_YA|f&rA8BXj$ydLvhy%yh6qtrA~?To%=^~t+=ddKZB}G({g9n$'
    '4M`ZvXEaEx?apYZ`&gNpHYvF?&l83c^Vy$R6wl<6iUI*#M`^hn_yX23WjPrJ%J?1R>x|Lm*ggS<1rmx*'
    '?6O>cw>z38A#gRLH_|Q{9&~GlH)ta_fYY}5c441*Yph_vsXQ8-70VgO#Jh_aWUE|>n=``j`4+v+ZbfUF'
    'u29tBozjHZ9qlw19z;h_X>DFBEcMuWTN_h_hlcIE9dMc)1AV!w`#|5LbFfm2(dHiXjqKHvXv7{?7uS9n'
    'nn+UyHi!#$p=slS9ndG{0*2!$>AO^m(UCe)UcwMAz>p!#Kbc)C%c19$x_#gV@xd-MeKqOppij&P7(K<Z'
    '$ECFlWP_a*3}FMb9ZR970cq3)q^H|-N^whVFuYZ|915dvtfKBM3SfPYcq>2#obp!Syuoq}>%m~UpBFc}'
    'tS5<&)&T2tn}$b6MfaVrHw=g{@X#o?Diz?rr>nQwlF*Z871hVmo%mQ7vAH;WpO2(1QLzxTNC@y#krGpi'
    'q`-Wg!O^ukhF;TjsV(ukiFq{mQ^HWV;%ksFeLKX@)M>J~Yb<R})dhCm|9VUlR2}|aX}u?C^V~FPeK$*X'
    'R-m(sY{S$~WbV|xRcZdNBoFG_<f1^BG^#~dN|S%pgs7obm1vsK{W@6*$}28fIt&1|b2}En=qtHho|RT@'
    'UjnRgJ2d0-R1wo94xz6pYYuxU7olN{rdyvC{uo{>JHI4``%7-E0hy`0IJp*AB=Z|rl&twRN`~I4x=nX%'
    'pDL(%^0h{!423N2TS**TNE}?`IJhWq(Ds(qI!)&itvPaM>p3THvt8%)w@-h1_2laLPj9AgUQVy<>9glQ'
    'ym?}LW&Gpg*^;bp&Mu9AoT)yC)0nI=2rXsD*}0T&SaI)LoZf;gsJObDulqNg>sibbKo`I{qrT(CiSNfz'
    '=mZ{hnIBn6lCaS9tT-~`#B#ladlVk=LyOUfdCc`~%A$z!FydnEXGE|w!V~&}pM8Rl+fKI33}yEiz~aT`'
    'X?8<w&)=E36}T)29m`C7&V1YS9F~NX2PPq$Qp=3(AYsh+;1TYSkj8->n+cDoM{O1dR(<9fmt1iMs%axe'
    '@De|W;=r*SI|d|0gu{R&awFg6B=*ACvZxa{j>lpWFcWq*ja<{UJU|ekL8u7}H=D)VY-jmEEi2$&;xLMo'
    'i4xyRJQBol2=lNa+p<F&rjl5u=UL2VJRu%+cx*<Y7kh!Zv;5_JMin`;HCe6U!%+Q|E{i{M<Nzyf=OS~I'
    'jMq5hpI`jCINP@$&JKO|*B{Aj@q~hvV1TCE(6v#=$$yrbuwEMY$zS9@#>Yc|@jr9EHddlQ^QA!+cSa#3'
    'P-23(Klc7RvNF^)u%E~+7oN(c@mgr)$FMaQvw0g3%SszxcyG6_FUn#5VLckRftM~`&#o6Q02`yx*tqzM'
    '@k=^m<CYUboUk%RN83xs+m8j<(%;9R{#7(+GnT8_JNy@CDXSjAq{;;S+XkfP@l`f}Q!;qQGvGtKSSbW?'
    'F71CqLHS#Muy@~(*_<<gl8|}EdjMKht47q;U8^b43j?zZ>&M4)K46x!EZb~Z_}3lpO-kP`+xx)oKGo)y'
    'i+jF!H(R9(bVNtL{yNDhU+`BqB;(`CinpI10oY$y43`y}Ma57_aS}nHS56$;&$;;raQB*qL*SPk{uj?+'
    'l%Ico@vIL(xqQvwUf*!OZY?cNF48newAKRcQ&pmsEtWkXvYYgMCTj_114OIZ{GgrWWO}P41qd|~7>)yG'
    'l=JGh_(5qOh|Pr`_EJO36<?ASXD{C`P*kFH6u&+`1}g`Gf<>(nqeGRci9n;OMR0g_hjf<~LhGWlE;4JR'
    'hjwzD9p8BMpW-gu=s}hbHxZGSn{*CJ_`$h>YVOkbdL}|MqiYU-d{hE%@|NGdPgl(N1isQ<9?9?(_|Nz9'
    ';qiE~7T2wooAr~;8rHU)t&6z!XtLm-6^?F+rk{zpyRrU(#C$%Q$n}gT>gL57X8nd_Z{Z*Ep1_~-dr-)q'
    'j8DBrBa~t<-gq{jt?y*xlVrwMWlSpkJm|a}nZ5*bt?d@D-#AQoj!Q&3$hDS6l!VD193;qHw&wCu#-;IK'
    '4(em#Ot9_4Kf$OW^9kb=Ot6eU827}CnBMF4-JFjmGny`5F6MV*Jg~Usqubfy?=!Z(xinn&+<?En<Jg|%'
    '^1ysuciaZq`O-Tf`_p7enBZ*79#3LI-(IiM&4MBSz|0x8noDK#ijg@n!|}N>TO69~6~2x7n6Am<8Zbc9'
    '707`ruwFOdG+F+*)BGeOl$R-g1KJ$s=YwMT{>6Z9DR8es;M6kUun0((ToqZ)#6;U{{>m2LJ8bX0e@|Oq'
    '<IX?z#viut^=<nW`oEP-pOEFURI?A`<>lF|@q>1fc9NkRG@9l2F*v(4zAUS?@$nF1{!^Gl-)tSMk)-~m'
    '5=Q5h7}fUo^IDMUkPNRri6~!ytOELXk=%g5`JJ5S2w!h4_FK`X9TC^SDWe&zb(Pzr<AQON#X4%K<Uxc!'
    'SuO$p0HEwKN{gf=glDsiGyxGt_oKS2JE3@lGFL~Nqw%8_BtwU4GF!X@Rl<aC^~k{FFL*y6=J;ffKJZtJ'
    'jeWhDp=zx9Hk<2fjKZV~;Jqxp<t;<x_%ln4FO&x`nPsBpLHmvI9e5=4ZTshQrC;9DYVZdju0a=!CO5z{'
    's368|tcf<tVyH~fBvLAfK)-8Q5BoGlgF3*YGByZ+>T$4%`f3C+xe!iwa$|NFK!}#7`$s7+=;`1Q??vd='
    'WbSzn+oSl&LH!^%{$>4x^U4RUW+fjSG%FBp#Yu@olcdb#mMlRWf&q*tlnk^?Yv$eibG;#8j+b}Dc|%O{'
    'e24SD+K-9G2q{N-`q7Z7P`wPs%FncknFZcPXnW--8V?x<%%oNd{p>U0v^$U0CBpeG4$+2Qt}8cUN99+>'
    'l9GD|?nUAb22fl3r}A9MA{j`=U6M6Y=D3(B5T3qYWTUFI9k5v%j}y@FdSq;tXy!a^I1d?}0N*A1tuxC1'
    'Es?AY(|f{lD<f*KO<y+1WpAEQn$&Fr069GefehN{(BgZHQ$8X--5^zC5QllEh}v4{qd}g(^zi_DwC1vb'
    'T+|W^d%d(r$Bs?+`&VZ=$kSbT^l=eu-d@X*c4UiO@F-73kpI>-#U&o#pBtFT^^RZ40d-LFQ_Dl6^6{cN'
    'c-ni+J`oQ9TTHO3L~UW?K11$J0{UpQ64j48i2Ci228{VzFAU`_$k%B)Z#&07|GC2?mnhUwu}u=0$JA$*'
    'h0}5m)6Dlu-+A5>Hs@lf*0W4D3t9`Bw-Go8Q$QXaG!GgM=~@gpKpk{K#X;HK1~U&I8gFj6u_V{rAPY2}'
    '0SWM5ur!P{e8Fbe3>9FX8{*i;AcnXiV_?RakVhb9e&6tHJ!v=E>-V!Yy+O{*HmihC*!3XyVU!H`Y(B?e'
    'ef9`O$@qGW`>dD%KK~A6F+PtRfNelq4A~e2su1<DF=}9d$IVP5)WX<k5mx9NV(P1>mIHmvl2@mc-Bvfl'
    'uHM>oV#CU3+Gs+svHC~MTH6sjKvAN+NPglR<cbU}C_nffl()v<@!7pZ9Xkf5JI194g{50&yXZSnsZVZe'
    'mo(0=P0+uV`}}ch!o9$(y3t#HcWLYnsh;0G5Zpg#?i~V(Fe?_-lsGnQxAY&#Kkt6|b~R%on$9=3$fW<k'
    'KVPi*?Px+6S>mS0L*Ci#=JwLCY;QdN?cBf|Tw%~yc88O`Z_?FsLT^S}1dmHrM#rPL{3yL^G7Ij?h1^q8'
    '&_5D?79<dQBL8DDV~_eD`pM8_ezf0pqJk}9tH&VVZ?{`~vLLs-IDID{)ag5T00}w)ca=kU*B!S_8_^ZZ'
    '(6gJGHj}cVTMM4O54~EY*PuH^zmW1&mFfK8Kz_n?DNVOvneB^ha45rB4ML*p(M?-X(mAU4MKzLIRz&?n'
    'amUU9+AC|F+<IyOs7wC!5PxU;50Um0c>g)Wh*pjjKJMRMJx`8KDwuo8<r9nL7KTnW>7kaH_mv@T4-U?J'
    's5qA85#>g&gyyOf5?2J|m6x3$-J^rq!+2wxv+rjMCSUJ3%bL|A;uUJ#u|cvsc%*H9MkUGH_~NT=2)@0_'
    'uEHpRcvPccDddHz?T>n1lFNUT84a(M)66G0{AjVgDpkKc1rymxk>5XH1+)x;X*0d0IFb%7_#t_fFwV{m'
    'L0aQq|0?0E@KjoBp{h3}+eDP4h)67o`Solu%CJmM?rTrPU#;vsmbPaToP*f1BA#@oY<o52cA2Br2Bt(`'
    'Wi`39mTLt?)v&HQ{#xW<NsbkhAHuYs@LhV-9%c8p!tH7fhx$5jcsH3=Bz<;}U&v9vZ{%e>sU6yw`@^(K'
    '_h98c=#-8sWxqygf&QBG`T{+56kg)g3R$STk=$Dk^-)7Dq1}UW>84vc8TR)Th;P4Z4{zE}zjdi@k>6U*'
    'I~`VQp&qI9;RkW(*`8y^uJ2LbrU~JG;`<>_Oy<WV2|SBY8-9(0z_fhZOCsO%V$0&x_NjTi(uWgpH;Mhg'
    '^n4FMkibqXY7u5~i+Zt5s7sQBI-c)Gp5=N`KtnT#Oy=@1aUz$U>BL2Iy^qK?J;tf!vyfVm&7IIDuJ7|W'
    '2@{Jk9?-~v=_a-vFyhiAbO{fApISCyEVA4-^*;P^y^o+;@1qyFW#<eGCU+yaWBWl6QinT!5@RJ35;4;c'
    'eCn~#VUcgyk>@0_>rvv8z_G2!vH&f9Y&$dxc?*Jbi&&1!V#o13?mN`<!-U3el6WkRJrdJ^1%#TW8-~>P'
    '+>k}Y^jyb@c!*d&(~FH}lGDI5{m7zjMEryUlUqSTNfZHNhcPfbOfZg}#I-pC-1v@f`L0hL0<7%%ZV<L1'
    'xmzZ=H-O{^ipuU(?%@t~T{m%k6UYff4s4eI7jrXarfJ)z>-e4-SXRPpCvbr*E^tGVM1dK431u2;4q>13'
    '=O2I`GY(2n6x3aSyxmhJ=_mN|7)#~eaL&_MKZuzDPgoo{A+=2_@slWqh1tN-mgP7mi+zXrVc>A)#@u6o'
    '3X8|UW|rjvZ#y-^sJdqWzG+*)og}d-Wx%0?J8lB|#tZF`**vgq3Q{e!ohXSS+an1uabTk?2zdY!F0R9u'
    'Tv)5^bI2wvn=`Vg2jW%KBz_I1uB_|PqC!ti=g9IK6pXt|qtuZ8N_^BF48~{Tl-;$x1hGf+Wnv|u`f6(%'
    'VYRfkmujXH@z=Q_?ki>o?)6mSPU6jFI?FKs8cUbJ?~C=p%b5+c{J-1tt-Y1VwnlX;f@-3t9&#4cREcn}'
    'xu`h`SbnisAFp+!i7W1fDF*UH6H9#B#}j)GDwRLbjS2G~@G9Ps48z2EfHs@`^Kimrn?Ngyb*zB{|BS}{'
    'LBV>B5qMnu15ica74tqNH6^tse6hJjJ<ZwS%#=3y3L>XNm1>9CKmGO<jyd{pDF>f?F#dmmp2>TRzMdO*'
    '`4@NaMJut3FW-nL?ReN!!J`v+!Q2TG$cG4@pk5uV)5~HJ<AOU{O-}#;`|}4dbn9^XPxn(hLD!e3^|G`+'
    'jy~JRVVRVNPt%R46Lm{IjLh>YQ&aKXg<%aFNib(VPE8uCD@3;#n=DP}JfBaCVZSuTW8*&z3&{2Oal-<7'
    '&%Jruw^4)TIV@K^nSB^-kudHdEIya4=qxJkQ&J2T6no`FC++u1o%d&(xH$5Ml`T>cC}PiM*E3OUO#$yH'
    'huT7Kx!QJkY4=pChaNtBXk2lyW$rQ~UCi%9+9jHDoaKAfcylw$46ILX+<?Sfq{cj@!sW%R%r*8Vz<kX2'
    'tJ#{jVGBx@MCLS1T1|1c${^ZjugN>kgpnqvKfsFJ)&#72kjJZtp28;9S@`e>=t_dg6=xgDe@x{Dt=5U#'
    'e$#%erh0QosIq-6NhhA{ut^#~ziVANv&Ae$LNQj_62Cld4J?O}bE$m4ha)m$Eh+>aPS(6^MDj%4%IpDk'
    'BYd-efOGbnW@%PNohWLl3Y|60|Ik&F^J4S0cFDRZB0WAP-K<tzSXyG4eaS1%RS+$;3|tAl8`u0I+{zJ|'
    '&#r}JxHKknuCBAUPO)rO+MryX%-^GKS){95EW#x7`e}N*gw=3GF}!^Bj>FfBYl9flB2x+ftw@<sGUu5w'
    'TTeRAupt&Q%GpT%d%hc?D2O1B_#TV@wix&_Ct3|+chjww-QLeg1t4lZ+Z!?X=aKZrBL-StU}#m{zmx3k'
    'Y+0`#^#Hi`Jy|g@xsN0XwlHDw=<5cw8!*{um@%9ugot_9GSANQO?D}FaQ&2DoB6iyi`5pL<($Qxc|FQC'
    'S;tt~j={aHv30bd-WJlq`dW>w(T`+<VgMy}RUMExlSMzj=Xax>y^%{TcHn|xX|$bXl4~$z9~i*)I|#so'
    'n+N0i?!fQ<XIr#(U@O^Gs}g1p?vsJ&m0L33Xv*dr6;@cDACwzVt@N4XyE$3N2uU`KY@hznTVHa1zrEk<'
    'txDd#IOr?X@=|?uZmiQanO_cxtW{AU3o6Q633U|Yqdpkx8toTcl^ktnWeFN$?FcymN0?$CIIzelSS(mQ'
    'Gg-;w(jWNZdVMo8$75}?KEx(l9Q7JZprVb4&&{8H0$#n1BL1-U*m<+~@<BU0at8pqK%gsz5JLvCuoMzT'
    '045kmlZ7i)(aoZIW%n_<?bL2hmkU$8tCgjw=)Uf7%S8p>?Oe?s2D?;JB(2v)(FeM@B#J)xt4h#F(+H(H'
    'G%^A+nXx`<TG}hZPs&T6eO2h{_SxIbz{{r(LQ9L&hkPKVxOE&Q6p{JAU|_!Y_Qn+PQogrH7tQ9JFGmZq'
    'NafycXP?vpGq2E2nSr^p0%iKs7S@m;zsk?<Po4hefpChqOpS%o%e?$(*qrtx>lQJF^X3ch=K~DDy1l;T'
    '(9dhQ=ksFk5DVgbh|06Yaz(zq(>$>bQqilQQX`$S3zSF(opZ9-EMaO3@jF(dm=o-6bG!z{a4lCcm7dSJ'
    'h~d+l*_;7ZE)9Vva4*LLpdPf-@wnx|_=KTfnaEtx8{MRxVklL&LPe3qKifh|?~YWKIB(~mZRJBv1$LTn'
    '9>m*GPUprKop)`EaX(fgLLF$-{#f$UZ=brRY^r0jazo2wxx}XFIozToNNmTAnIBP?Mj>@M4}34ic9szj'
    '%!oTCb0Qi$krTQeF(b>1Y|G)^@myk?xXcgYI5tg(C8qECUKG*DvIq~UO{mXpGmau|lO%wTtR#$L4x^C7'
    'H$yA1&-7s7^R<a|$~nZ&{x*?&PSNmg?`u)Vr+<GVRh_9n0KQt`smOEu=W(0Pi(Srlif#OwVt@Dc&$m8v'
    'vCVO}f(_N<>z_a*Q8d#N%u2Z2UT}OVKY9Lvpwro@kc1Lh0<mBtR0ou$02I>2Kj*SG@ueVT$DS{Ffr9O+'
    'diUxTwTy7m2S)oNvT)oFI{v7R8>n_CyqK|6yE1{GZSM`^>_MESZzpsPmN+ZQT@3W=4^CcD>7VI>3neD9'
    'U2nl!0=y)f`TxbwKi2Q8?;i@`<kJ?V+p&!Xm|>%yU4sg4QghhBGPdIQJDI<IpnFt>7$zIEDa6QsID4|r'
    'CxqVvb&(vvS@_q0F^`{Ujt7BOvqx#0=>Xh$p`UuThHI&ghH9gM%INU$r6zFS^Sib!;EIG4@z$mB9Ra&a'
    '6rXK*QLvPfq3o0&z*v5HID?^f>-`oCPf$1_zu$K?)+t@(%Tntr(nHj&8_SZOmuFP`+Ob-xG{LX-rF=bx'
    'nUu(eZibqx@i<p$mz^#NmqvYFW~V~~NnPE0oLV)`J;Q)M)v}gmM>DIVm8IRtI=PK?*u?s(LT;@VR~v)t'
    't16FoE>qLZ{yM4obx+pUDU7fCv%PwnUZ2JC`V5BGQRAp7DS2;};!&IFRJK?jQ><++{;{^O<?OJDDD<nk'
    'Gu3lnvfnrOC0Vcu0m1fuvRR6Xlv_(~ztz~KcUZSGX*Ff60NlOx>i(yjH;1ZA@d}kPy*rsFx2*-JRCs46'
    'R%8_~);}-EJ2IQ2Whsjq))yo>^T!#WcX8dppA|t%Sn@4dy@ge)zM+g~bTwPbC~PwZD+7KvTdW_9$0uNl'
    'U7Ag9)gt>);$t;OMUGKacWlqr+eVbFX7OpVsJBqtQHY3yv;*r`dy1fCByhLBt8V4uP#ss<#o^xDuT8+k'
    'L23~sW7{T9-KIU*aksGO1-vF-x_z13Zj96#)!phlDFnCL;)M|?svzYCX;BiXThT3X{#-!BgJ{JOH+lQ<'
    'NitjEbqV83bF$9RyD0oJtesU1sXA55GvfUN1Ap;(GRdbc{~cB>t8@3`d(d_*l-+4{T_;s{pPKG~qO16}'
    'oxO&Ws=IsBcK567^y|9rs!p?}JD}*k=lvC2y)#-R+o}LvBwE#nXb-xh>fDJ1bWo*QH0kLSY4?I_$JJ<e'
    'E&8Y$TswSeqk1W<oIxO1q{WMeYla>y8QMv6w;Us{v6-)A8(ZvG?Yls`Di>NYAL^*ihiz3k{b=#fldfym'
    's2Q@D0ej+8=X!xn?S5M(d{B=PFNj=+xIV=)X)z4~VkSNb?U)3n!(DDu#$tGeIi?#j<^~RlSs3_{!;<3('
    'A1pLIFN)&8vlGfJ)8(!iJE5J#j>){3Mt&S6VPXfq4gdG!gz$uO=9)G&gV=M=^kL%jC4E@sqz~(G(#N(r'
    'EC}G2OVwRwG?Ll%=SKeT3rvl@_>1vNI%DIbSr}5B9qa<v0Ys%UTbuX9f?yTjmO3o_4Xb1pOE?Ba95&@W'
    'tareiA6wjc<J8Yv`Il>QeW}n6V&DN7jTm0NN-?-u`8Z2g>o<2;ulR+yifpxm-<{f0i=F3a{VU$oUE)0U'
    'k9Gj{E#20sY!UXAA?petL1twBi@fP0DRZ<RiEic|&f7g%d*`)E7r>71br^1^C;4d94N*gO;%C{2+kMj9'
    'a8X%#=goZ%i*NTKZtt*_oz`Z0ClM3(DkXXgiLNrD#o@;EmVCgjEC*pt)I+aUpmJ4BEs2ZKm*!Yj#(K~$'
    'syf9}s%HmgU)UDU;5%twh{ub)pqAHaG+}L4s_$?AcvSgzTe-gafqF{N_F#tx@x<U@XYVY|9cQ*ptnYq^'
    'f3LJZ9qEq{xN+d3-PTuisrqR5xylse2Zw9*CzG1A6%KUelYv2lzS%BK+}QD?^%dScUo|vAyF<|~8Wo6G'
    ';+H}cmKq%O%wny#TqE=OgYg8E%?Jy+P8R8c_d0uP?pIYyX!z1pt&ea#sd&g7win(U9QR8x?DWF^aMTtd'
    'N*WYY=!}h~mX3QG-4%`3YLWDAE9>;|YspaM$)LE(9`xX+{M_VLN-`0lTu;_1ll3qZ`)<D)$?wKS=M$RK'
    '?2;30lFzh9_73~-q47QEOM@&7{sF@Yvo%_m;%+S2V$V?L14gn+Z$<s51&G1DqZK`u58S7Fa9~O=^D>5;'
    '4CtP1=kZYR%EKo@AKj8WgNo2PJUh$a@5P49WqWBD_(4}(s9<^C0Y>zRtMkmc@kObRl)AB(jo#nz6)5im'
    ';d4PGj2)K1f9jv^HrgjO9$=-`8rwWD{@1U+j<y4j`<*J44oXVgR|0!q2}^(ad}95WRPWkbwAG30fIg$U'
    '4AQB|=$^CJeho(tNzo%puP3*5!b_rt?lD$z%vLo;`)=-BcWx&sAU}|oVC9X~%1Gn(ResK7&&b|;zY9j?'
    'tnWoC?C_@YCjR{AroMkVIF=)%&%&r`<P!?cF3<Ke8ui<Z?GLh^g3I;r>3kDE-DGR<=~n7k`%Su>QIYz)'
    'r$G+!d4OGEXhgUd*(PzhmBhA9JouD^HcP0Tm{DZ0#0`9l`aTaM5_ou>IJ7w(*dV8v_qQ15ToBPAXMr`)'
    '_ch2l!}dcqwH(__DD^q~FZR9I_M?C$PMo-|<(bs?Y%`*^<-}$b1c?o+U{>O}7ISpW7_=8CSdP7wo~G#v'
    'bPs9YatbCB2ZRS+6uAyh;v@<^hbB>Cai0dZ$!w3hkwt9Na(NW`LBs;v1(L+DvM{7=u8GG9w;fJ{zyz3P'
    '><6JmT|0J&7kj2n+|ct#=tOQzT%Wis_Chb<oO!+z$3d(Y8O;ZWJmj_;xQQ7Crklj3?<Wp(yfEQj=&(2>'
    'rU`S3X-I&oB(b?me2+z;$)dy$2yJt4=#>u+qn;h7#2TwtMt;N+@;ci$VgD(|qmJov(+PlLK@iz4N7Pth'
    '90V+ml7Ld;(7*|SmI+o7U@md3#EnANJ=VU-_Y#j|*Q>;|U=w>`;3Ynfd^?Ct4qM0MNyNBqnT!O$oF4FJ'
    'U{i-O;s7Q5cI}%gkuuT70Gy2{s};E$6?Jx5-r1nkYGFK9Q8U@Q=1@4cG=&|&Y?Us*!Hkb8?DoAsTDA%4'
    'Sc?BXu%Q(hpReNo6C=iCN-%M-ls|aAvrLp`&*%+jn>l}EfF~~tFk`k#cCK9I3=93^t*8wA`;}03t;Sq#'
    'Vvrd|z5mp<fYhb&{Pzu6AG?%VPsz%`f~QJl<@DV;RF}rj;>IZ+VA<x>G{yf1jG@B$-=NWqTw}Xkf%UJb'
    't^kO$&2mGQOL?T$y&kzJbXn>zQ-ay8n2pSHlHjmXnaXaG%T#^FdzH?@StdEIu@Q|J;~Y#!*t!*3bT5{l'
    't@#pD!o;i}=EMAlA;&QOzhYo)it-r#-?=2Hyr7INh83v=Dpbih_}%OT?fng?fA#Kvs%dvG373y8-@nM='
    'eI?QHSbeU_aRD~)<IaP~MdRTQU$7DF&QRUBq~J3-?jKwHiqpCa(QZZc#2}mX4S1RByNU5;22Mq0%xCYg'
    '8<hxTzD5J+=NAUUp4D?KkYDr>o^+7;dA0bM&(p<q26UE@Td<&1O6Nn-xct0cpI;?^k_9UYXtfx0K1(>}'
    'fof0@vK&GW#UOyGq6vL8OigG@EWLPkX}pZFG3wUW?h7%$4|Q3;*{wc*+!ru9rR186!U*!Txi=`_n`HL?'
    '*n8LBII=83?0fx+oSeasoMBS&eyFCpnxd#GO_v@+vZ`k+X%hEIW-FPQoe!zhY5@a(@fu!Z{b6k{ylVr7'
    '4Z{X@y$jp$00U#^zu4~HnNR);KIh(u%!tg$WIS$UmAb|563Jx5x%ZxX-uK*dt}&(b&P2L9u-CLV4t{0Y'
    '0cEw}oo#$7wFlXlVx8)pDYbx9S|^uey4Yzx+2|y9J99;@@_4H)2Vg0bFHaOtpRE2^Ltmu(pPA(BZ24(o'
    'MlUn2r`0$0LmPz!b3))Ot;k+i44~(o-T}zeM0r-ZjmtWqYcWb%NZ(gYf7(L@R-^5xl7~4obQl&vR28IE'
    'Thn)nTUPa|E02?`4lGo#NmW}!J!VpEv7@V1H-@V0l(dIRC0h#hA=X2|Itep<Ryfig4)4gtaG09=x&s<k'
    'BxS>eI+_`cN4-R6gX1&=O?}dM9fcimo3u_+G+7UVE`wRQkJh$!VT}N-7^8YStgLDP*<G2071bsuXZJe~'
    '$BXI$BjXV*i8SLGCC-pl(a=p^(=$3;BOOd7%MEx0UQP07{`2;PjKZ99=?nb)Wo@Rs^SU<Y%46OxkY6#w'
    '0550dE5JU>SAbPnyq$arSNyE1f*(k&_0%YxKS=s{b$<QpB<W4_5qzHfRHJ<PCi#EfndC(1=j*bgX0M-R'
    '8`#<Q?$>I4C$)QE=Uy-9gsnl=nmM2ZTa3cge>IrsPOh`0CG0E{pMx>dlnd41bTCE#3csINWmW)tsUEg#'
    'l#*UoRq2$!Oam{;Y*#IP!T+{e^p`WVn~?73Il@ipc4^z?WO}WRkO|l1K>hI_cM5usEp3lVy#p#s4J9lx'
    '{qt5em7nRF%DtbYX5*K&WPe&ydYqO^O9nW;Q!7*}&z#W<$$V4cw;V8QWUhWbY8km{`Re|vE#=up0qYgA'
    'b&a{|bX?d2QQ^B{yUX&c{3##I80;}x&=)G?RIH2A{!_aUP+~}91i7tgSBkacgdhJP!;hP!X}l>w6H~89'
    'uDo9<%B3H(MOl7cpXZiiB$z51!K%Z>+o`%ehRxIMsx5;KttzMFxU-v(pOr5~-zxEbv6XnMA3dZ8Wtp>w'
    'ba#(a<z4m6Z?&cr`cJ;-6xs6DQKR{9Qe!e+Ro+@6;fpoRwJ%k@CRBCr%MzscanRWchb{Kk$fGc`ZSR{('
    '>d(sy+aI>$gi0`3-jPb;!X<NwC=X~Th*UW<R^Uh{_BkP85C+VRge5G`mad3m-(s;(9b!=@^xQbMNnmqZ'
    '+?`A0dMpU3AH^>91*OChf<=-`<^>UnsU5(e9*sR21+g3Oz~!OuyOAIJ9*+s(2Zqq_arB%hHZyg*&HJ6J'
    'r0u4Pee1Al#=^`I@vb|G8r(_dad23Y4;5&Yldpb&KWwyhDp8v)vx>n87CTU(i=+G;|M*Y8=-3TQlkEXt'
    'ZKBI0wszU3I}ULV2Dg*(bl!PJXP9HM+xOiC2cyr(b@~K2&CKmA@4cw|Gg!AbJ#5ui4D#o`ovRzMdgYGM'
    'bSe+{gqXMUOS~_APu)$?cdjwpTn_;z4GeufB`C1*Bu$_8U`ZLGvx|2`yAOVvU<RkWc}gb-BQor;A(_oq'
    '_f*sC_ISvK*YEGl`Ym&kG2qxpExD<1oK(j-?&uW#vP70YJFZkQzu|##;c4!QFRQ&+{_M8sZA?qR2_ucx'
    '0-$eIodOyz#2eK@HciJW0jI=C@46N%pEh3Va5fQI>7l3kwIuwz4^4B(%|3LR{X@y&HW9soxcRr1OG7n1'
    'eQkK=y7l#}07afG$xihTY^z{u<5=*H0wpSutS0F7^H`La6<R|8oH>Zn=gpv$JgnS!uV@#mykGW+v)Os%'
    '=Cs8~SA!`t-=AiTjK|lbF^Z8C*jqtfFB_jA1`i7*VUr=$={i_v_f?<RKf}5z$DOBWMEvB-awJ#c;8i`&'
    '1wM(bX<?u*Pnfa=?<kOY2S_w{&XqASRx89T=Oh)aGY8XVHc(p#o;p}hGwkoFj`AsCuV>k#{?mI8?wy{L'
    '80<n|ja+=?wGfk;y85gbq%$M8qNk((OH=K0ouoWnOi=8r^lEh(850+GCd+M@z{xr1E`4}h%q{uj(4*3Q'
    'fJT@;_=RTK^^Q6vKn!GOd0eVMrKhF&N#dW^KB;r8diP;!p62xLX;3&}*V1)33)lC)lPjQtInY_znF`I)'
    'SLV_<OBRR$UA{a>NzDD!a`-$wxl*es3uJBU*7vgboY9O9RcwK74xTtwKVMo41g;GDwdh{?Lc7Te>j!}7'
    '{uVM(=9z{VLBaHmy4;a?kAe@tslyJiAc;UmrBli7&T(fn2CE;od;WGjeO=P;Ti<{z#IxqdtJ@D%XNRkZ'
    '?52HJ?MSukLF&3Z&HrBGptUl6C()bdnSl!qSgR5I2IHRP4xjWdCrPW}G6$=rY4kL?f~2c*q$%pRi&=UB'
    'DM^k0m7>`+R)Xx3+=c*@ES;(<RLYD~W&-6T<N7rs!R`BT=V4%7qB28BY#+q4{RDnlq5H9XDg+n2=&VRB'
    'Yty=|u-&UOAf>|_Z8a6wgVCXCe4k9OUF@jh3T>k$3Ap{Z5R)t8o<eT{4I9zz<CRI7*1OCfG$u-{(BjyY'
    'baC*Zr1hS3e^)kHDfd;&=*}tAHUs8KV;!fV=*b}#3hB&-W4um;=Q0>pUf}A;?A?gnOvj_~V%9+`;-pN-'
    'aA|EXCz&}_OhUQUmI*K7761-kD32K>)3J7*HHu$>BUaMx=0b|8t|1}6JdxnC&TgLTDIYE;d{nX4eF256'
    '_Ww8;Yn?{a5j^&L$<s$8+E6PTS1P!%><BPRS^|)_WRT81Q#JCiN}-XRXwloJ?UWTCEs=kGN1?|JJl3ne'
    'zfy5ozb?T9vdU<Am5(U@MwMIX5WF?s8K}^}LKSO~i(#`0XvNc7_b!J?6-<q{{HJAGt0WB%VD`zDD1#(v'
    'NLpcnfSxP>40ymAg}#3Qw$7UYN({Vtq3@r=fT=g~Rvq4eMRihf((ivq$!~q1WwzkzB>!nylo<*nBtet}'
    'HRUyZxfd#__q?F)ueK{a;jUoS6l{8pP0U4=vH_=Z(X*9pHB3vz6~=`2*x2JQRJSVm?&Nzm=3+7(|KcA0'
    '1M=%+Lchl!?@X-;qR17V?^=>F;)X1YDQCoUC8LfNOHWGb3fpE}Qc8&{xv*SYy3A&AAY^FYomwNAbnQU;'
    'w(uzRsU6c$I@Auh42iG<o5ul@!WSZ9G>~=>Na5KujvZSF>if=tS!@(%*!T{&n2ci?@W`T}=MX2LRK`9Q'
    'ps@l=ay#(-h<U;#R$#+Ir0-dt6jHi=%w(Ai8^;Q=IW~aanzeesr_jILQ$eP|uh7weRnOE_<C&pqJ%NZx'
    '<a@&Qm=hBoTO^{M;87I1zVHLj=C&^+^Ib+F8_36tIdg-6yFM1uvdCT4dL)fJKeBifM*-m;&;<(wY&jO{'
    'v0*%0@<@6fP=$1ZkOr~mv54B12Qy%iB$cZ5D6ZT1G5JA#`*4i^cEQz99joqly7r0HtyTr6>P3($Pgh9r'
    'JTCpHYS@*zCU&A|6&7D5FR=?sb*gDg)e1n|>0|HiaTPGbgqT(5f{Js%S&S;b18-@b`F1pz*LYjKpR8D&'
    'ZVfSOpwg-nFp3WmjNS)T=ZEVmKi!JZDw1He$##Er)BBp#*q$FDs(<q@|GVG*^MC)Fzy06--@pHFfAeqt'
    '#XtP*zx@w?_xCMh`$xy{<eCgdpBVlJXL!92pIE&eB>&@o@}K|qzxsEY;eX#a94~BqV(=f1_AYP6Z!<-m'
    'KB@E;as3Z}`@jF@pZvSu{ICD?xBun;@%yRI)4Ca-IQ|FZ_?7XV)|gvv%O}on$(YZZ@mkgY!{7hQ-~8SG'
    '^m``)^sUHG65xk6>M=&F`rCZ+=G#a4Z~x8z@SA`2KWo1K?Z5ihzx~(${qMPFzq}6oNf7*if*@-Iq&xCS'
    '2DE1WuXH~;0srK`_<dt~RhjG)!~bw3c$PZ)8J&O9NrHTDZ^WqcZoKHQoAG!iPCf~O_Pl}L{)>PAAO6R`'
    ')1iQ@8Swx8U;p$s|LouX<A3wde*0hlpa1wb|LJf4v;RfQi~r|u{^O5QSd@ISG%*yMfL5sTaV2K+**z?B'
    'k^Gcvdh~oc<_jfg)L*x>K4OxDj>9a62C;2X;W(ZfN#Btqa>6L)JdDGDk$_3cC3EfAWgeb5Gb?a8CtkzW'
    'N9#*?u5$>mtNJD8g*_c}khTDl40o*}lD0=(&y#*c84Vo){{<0oBkp>(6<8Kyg7_ixd|z5rx;~HWka`xL'
    'xVv#|)mp`3f>jdILv~oq>12{F0O$SqmRyUo>3Fhb(!z@Z5_w+i`!sO4ByQ+3*NUT9TJV`?J4}kuXHf`0'
    'P!fi*N2wKto-Md7EU!d1NF2u@4eW?GJn}6ov@C35<w!?Fu8<LpY#It-Q${!?HegPKH1Yxw5*h~{sfvJ#'
    'xe^D&vbht(`e0XJUIfU`mX<}r2sSEoL)akOvm={_!sc!qT7o;A+fv%tbI1uwV4!K<Lq!Z|Dh5J8@x0>7'
    'w1wKw#JjiSDSs%i&J+{7NZRHy<eWN=42c8N_k{0B9(oawjO{u!gpGp<3yTB-$iwj?W<?GYZpeY3ZEl97'
    '3)b^QOtFIW{2^92y&~7TvGA^?2+oKFQzlUa6y`)xAOg>Gxoa^eq{NGCJAxk_>Eg;<%krr2`7#pB3uBj;'
    'NPA+05D{?#J0~I%^B@LlXVL~?#%=1_t_^fWBkl=K`~cZOGC){}FK`eJ_0W>Gl{>o;?Dg#496s!)7kBz-'
    'EcU13dH}?)3z<yb)kzjQhyzR7JQA)aV><*Mb|afG$KxC%wL=8<_Hu1v2LdFvWQ=p>(g37~6?%aqrNOlU'
    'CHGlE%Kc^TZXZc&F8YM4_Q!=QJrKT4Lh14_@L`__m9W_sHvI$H2SN=<!L}XS;~|G-dIAKxaEV|R0n&g+'
    'iAi$4du^{ZpZ0mes6{LCfKVMEWnT*00pS$-Ajd4wJ2v$r!7U<U5ITYD!(V|iJtiWcXXb*&0VNymc|{X3'
    'O?GEixR@xAmav&aC5S#dj+}snl7iBAeC`4#g>ej4LO?wZiYcIx3nJ1MU=f6zamQ<WG1tQ}CBwdMo|$2?'
    'q?%4$-ikaDgO&jS1@gg;rRN8npzHt@6M{|Q2*8TRTpqC4u>&wD98g#m1+nb=K(OW(c$-L7AUP1L{W-br'
    'Pn2LS+AT_)K)3>IgcxK&Xb~B>o)Z%0`pgDtz+np=Hy{Lby>Ed;g~b5FMYcy6@g%uhpn5ULWJkmyiG&X%'
    'OI<g_4w)7QNh8AuY$@A{EZ_mh4<iyd9t*92d!Z{FDOlJ7VlZ!ByzQ%UPJNw;T!fpD;KU_ozOZ8vMQ-3x'
    'pwURlo7jU*b1gt0$LB(@e_Su(unyQ)p9m|GcjHFH(zTs9_Q9m`V;M6M%0Qsrawyo9z83<9K-u|VWP!Yv'
    '@I3cJu$)0;+i?(?!_7pu$?TIiWKO2V*Z_ePdyx|h5J^D{=CMUwA0}r}*NS`!pLjmAWE6t*ihK|Q5r{7e'
    'rV+R3rWH|8%#VUx1MA!3;77Q=B?Hbu#Q7eU$&;>&NxUwV0TQgof+!@u8*t1vwgq;bG>;7o%k-0L6s2^N'
    '1G53W=}J#B)ThMfF|`?3-$4x0Jd7Oys?@i6Y<U4;Ttt@bgpL=5z#1-%+ZKMSg<&#$Ke_N&xZOTsA`XHu'
    '1`!^>d}$O=8HTW!kUEwRL?2T(1m57Fw_=|=ES8QJTYdnR7%#KkoPd6_UFHCbQ6d3Jal~NH85k!H0}sn('
    'AY^PCi#6Jw#bBFx7{TM7&0(qLu%Znt4Egk@$yr=IB>*0-AAt}BzOa34?+fk%IFM2Rzk*x?)0@L~6Bnjx'
    '3Gk*IuwNn`6UPEUX#2I5K-O(f9fapgHNDd}0MYBX4E8Ppr5)2S@ItJi8G$?omF$4`7{NYAA-D!iMzO&B'
    'dEX(}aoM$lz%0S0>-b9PXkD0Pz1-c7)s)&J4}3zw(A9x8*r=N&>`f5*BE<isMA-snGK+ld>l;TActIe2'
    'eb9h_t;TCxcX}S87TOt+aL|GG3Gu+|@uZLTg9iqM<HGM)F4T4-7oOpiQ+P0>aTxO${1hgH@5CiI(HF5L'
    'xf}Q){EHSPXgOfZ$o0T*v(PjXuIu|?MY})%9+h!yfyl>p);@@^peaf+J(_nR!uMRt!EOp7u;nTE^1c^Y'
    'Fp&^g$`S#X$vglh>A2LFp%4FnhZDvY1LuYYp<}m0t2N_HUMwwUSujc862zl6=&(5Cp%vRi_~565Xtivg'
    '+7TDrkK=&(Ac}!-VdtgfB|<g~^r#Esn#M>IpohW31M~#GBn&v1#b9ta9(WwsH=TkQ2P<6oKtgutIh2y7'
    'h*@i8)0A(i5HK~cBw{ds90m-_ffhXsw#b;HbH_;#$Ka^bm`PAcjswb;fT`knwy+v6XKVe<#sW!(u)|;*'
    'fEyk=F%~k8oQR>VOso*d9liqrOHdJDg@b_w{(=`tLL85H{LUK28w=xOHoJ!|T`zU%dWn<TTRN$?e1l*m'
    '^@9MMPd~JPfGn_qIhd*<z&7yGhfT0i?fHU$oyMi44m=9ewYejR6EoKg_Z3V&>yH-9I|3CO0(E#`wg?6Y'
    'vw1*5FrTRtMTBw!W~y|#1Xb;U9YSMJ4Zs0l-@AZrj~kq~c0GIA_3WjtXK(3xZqB}(>lp>;hQyKtlnNJb'
    'yxBlL5?pH@GA_Xo1<~o-LF|I95rnqofo+XF)WL1xjMQ37>P+>Nm)Qd^v!}hxdjmX4yImIDE!Ywg6W9v^'
    'GRY-2_=N$eVDNfuUj%_C!OE~5aGgQtg7QIw3cN7tk-&Gt$daOrE8%1G2P{;J_|&q!z;gi=BIH&Wh7q_~'
    'Ap1Zb1_20R;(1{VoE5;|!Bq#(3$$x3l%N^eQ)Xn+?yl~J`pmOp4n7kBnFhihR$+q@1CKZkT-ySwWS$)Y'
    'g;Jo?5L{}|&4GZKgH`Uiab?SRJ{}K&tI#4Yc70f4G#5DvF}Q7(>sS<|1Ct>Gn*($+`pqGjl`j0v2fB13'
    'P(3k75ZFafX92hr63m#G7?KOg61IdDclvCW53W6p1?Qk}BMLGwij;)`hDFQ>C`>Sb?bs6zxFeA#ED27i'
    '^a)TWIOxPTxq!J+H9F`9I{=f1N5oL})k$mrMz>cjT7?amm!1R82iR*tL?i0Pl3C0Kj)^#!ci@wQ^=hMi'
    '57?(*fA~K5ppolZ9L&j<R&hO;4+VKW>!$^twgs?JieX#{R5hbEI7AL?MrZ|+2OtkTFqIq&@J~Sy_zt*>'
    'K8P<^jpcCWfN@IQyM;mw7DUV#9!ViD*)|tML=FY%AU#k8U}1Uc+`|sQW&}@&SR^3e!iQjbi30CzJRFYS'
    'jz?SZFkOuLx+`X1F;`){)ZxG=f`wp*MH0<C4x@oL=J}rEVsK2_v4E-j(uXNq1pG8f;yCgH+x25NEFlcT'
    'z;}I*5aGlkpqA$`?)j8~>h_rnN*geM9z7TzKFAm1v(TfAc(ET7aJjw8>(1=|NR{-s8w*qfA(bJR5Mb4N'
    '1Y`pks6Yka@VFs&v2%nIh5|fQ$K?TPZ}3qqa76;x7(Xb{Dgx}2II@@zq>q=tT`vH)3P9t5X5_)YfN2(h'
    'K}^6i4;&xN0fO;3b#WSO^@9(uK6`$8asKqGfAy??;q;$fJUqYXd;yr*h7d$nBA5o?r1h82f#T%w%<GI~'
    '{l#p&<IZw&%)f!&B$7$qfS^vQ4)zBlOa)K}4dvjiO)j~7pRj2;5VPd;=8Yi3KAB=ciDC7L6hf(kArM|<'
    'fYoLDSiup5C<j<Dm+Dj63aQ?-4D41BkUEpmyUxao2@>uv7X-w*E_bFxbh6Mg^U^jsg6nB;Jq@mx0oT*u'
    'dJXBlh(gMvF2^{<`&tW_IaFr(U@pLrMy-#XVbxUYAP?<Ou!U~PB()yu!aD(7ezTzWus)dtQ8Bxxg?n!>'
    'o}IkA9hRlv#mIIoJZ}?&$$UAPGT6bam`jD;pTitx6Ohl}0WYL&c*+jnUkp$}>$vw_Z>h#VFz^(tA$~Om'
    'ALl}VMKcr6R~vjb9AFL0a?`*?r0`Nu;4Tnt8C6~nostolV(H$lG)p6@QHC_k3581|KwEaZ39O02mf*@o'
    '8H~hiRvVfV_Z5fLg@k)~rr7>$%&XHP8}zSX_zFTNnKWWxFl~lSU;>_)<Ndb+OB2q@y}sidMbB<T-VCl2'
    '$u}U^qwx%EzY2@IlcdXlDo8ha4x;dZg8j7y{b=w#dNW_A17st4^|7!veW?doEu*ZYQvzmo1M5u+Y~nn}'
    'QX-knDhQj6Wmlln!uJ!jU20>u3M6e=UM^_jj-S67a52(Sd{&8dHni{3e8o-y*DE)(yjIxoQ7X@5m$S1a'
    'aTQ&J3~KNQr0n*rzxPng!6bY%p5D$%zn<3KdML2P!@DPBQtH(msX}Tq(Aq$mip{$EVuZPycPracg}^>5'
    '$McW#XKjjsM)OBNA*Fd-D{7|tl&aeS15$-jQ$2qvbl|D%D|m$aY?72fpH&-f+3;qqKjED(rg(a=m?<@Q'
    'p<2#Y8+;u`y|<H{I#)({-M8xv{q*@+y%$&8Rdd>P_d8`6__^{sDy95<GzYFfLsPiy`*^DNU<%g1m{t;0'
    '_}*i1X|$B8^lIkhZS;oBs=s&s{bUGce6<N*-i#*+NtAv^`3F_8qdkmuL31_+4jha~S$Zmlaw(>7227NP'
    'u*OLM=@#vl>Hq+BnI+T!aJeetk4mNjgbP5y;8x(p0fg{;70)WWkB_E8Xrfs<Wi`aYh>i&&;JOkGrLSKl'
    '?*A$1kJ<e4Mu>TB7?+FdYh?TJ=t4!0o|BOnmbWp$00eA^=^(Y$s+uP%G2(Q=2jf#!>A4yV<!Gl%`g(jT'
    '>hN)*hrb4Aq&h9Gwz38}Zc2G0K&t5YEg))3hdgbfSydm#I&GGRv_V|eCbIGRpMy<4BEtp{uE_LSRG_a-'
    '(yk!oK%u5@mVYbZh8h&Oe6yNf%8H}PyqmuGgiK$Hc~wdJRJmhd<4oUuLq?SaamKZ}7_b|)%hkNAl?Q+N'
    'Sf%-um*P2ASuXzx_(j86WdeOX8q5b|sBVc@B+l&YOS2cQ{h5>l27{iz!A|zIY@!^9I(7hXNVV6r%Lh~g'
    'R&fnOH7gHN@s@2l)d)}>rI$o%s+yu%1XOjED^2q&AdC6UnZV|bHD3Hiwa!qgxt3U|i=mv2TU(XG+h1Q@'
    'JumNEq)Jye%cvmD)UX?`*YYqnpj5UYHX*<Sz!$9)ApwabW`pZdH56putR&3REju4w!%S~0hZvFs=VwzO'
    '*I6wkG)jz5t{SoGi?WsU0FGZ>7_J9(Dg-!kw4T2IWKmHP=2-1^G6p4bA<#3e0z@|}e?a(k#rR$J9ztCS'
    '^Rv<T?NGqbN{3b>*kuHx3YV!Bza0s#$W3EyPzhhlVIQeBnALpGOfrAv0MW|J{CYtvznwYWD8I#5$V&5{'
    'li^Uz>%^wUXrX+y7;sU4TxHhPdh@%g4pX`{HS|{Q?HZ~h^L}-uky&$P$2Vihr^~MSa=leA4`@&T)Or)`'
    'gvvO}ysr$&N^37VK3&0ko*cnzkG<NFO4hbjLFhUmp>-IQt?Ui|U4g0UzptyeI?i!{k5=&*AyX(OoygbY'
    '#dP*)Acnj$Ha5UiIqk}5n~U+ddcZQ7!>pb?o&>F{D$6Wk>t0j!$Z5Tid`;D-a5zG*xtgoHg7AdQZ%Vye'
    'rpnIlobUAfdbtJQIR3?AJSUfn+gmbySME^1;3O|e;>Rr|m@;4l+BtR>Oz&-7mOm6If|;C8B*b<#xD|@u'
    'W>w*#WqU*B56PUAPt3@@{uc|-j{010JbFN;RY9aT7?b-*<(-Rdi3k|>XbR-<Y_<?jmzhKjAfZ45pN~xk'
    '6NFS+DsBOHiLI8zw5o_GfR+fG%!N^<qQ_w5RK{F-touAESUz|o9t;=L)2V7oUlrO?l6`~8qnBb>omKLJ'
    '8BdvqWN`cQ!Tg3#$=h;K_N}m#gsBf9FI(#FWFgF)gsBZ}!)-JNsiKK;C(!ReZSZEeOC;%YvY3gpn{i3i'
    'y$e(#lz%=L@$uWrz%mlK$-7N3y)M-&16Y#-&&ibBin*B1>Ojg0_WHtLUAU*`^K}7jiqFcBl-Y!*3l9;^'
    'qk7X(_uMgZFhYlj@X7%4()PQ-Y@n}o)CYuy1X^jeHtQ~<up*EhI^dgZ<>3=KCD#~QEtQ45YZRp&+JK$c'
    '8!e8I(;_X5la;vbfzO!61_vp&R%?@IvEAAfT!Cyd57Hn~iv*!z@L3UQ5cD?T*~Sp5SZxe@M=jK1$G5`G'
    'ggZwlJd-dnz?vs(2;{nVYXWSc3^52eFHH;sKK~x*;&d?|W2t(>u-Ck9!_bR7af3tb@~2G<v)jiuF+!0T'
    'HpNQoGT0Q{Z35Uh{0*bF!3b+tSC*AQm$gF#T3{6}XYT->uRThW(0ZRRhTnz*DKJ~v<QPod2}fJI|8^B{'
    'F+IR9RS?D`)D-zl>%LZC>y6D;`!zMhOk2JEu@Y`%*q3BDq=db0W00A)t^0;ZC%L(a_qOO_K8FE7Y?=b>'
    'TKzd*jDS_}0ZFdD^$91Fd8u3R`7ze(C>HpYwS__vY~@XwgP7i{(5Ny8cY93J_!v3w)EM*)v(y;m&G@2e'
    '(7AYHW8fJ(+61he0o@qj*1)0($c2GMlYn!9M^k_|?as!Kiwr>{K(iKLV}RRCKXZULY`)5%^Ti6$aOo+_'
    'sJF6=3Mv-X1+8o%L-5l2mWefF7^<>^mZc}n08fmQ-UKD>z0?lsE$yIYP!p4<hbB+m`8F?jm4%bL=3c1='
    '$5tp+Jq{CvrE-waUW>rM?+d&)Q-4*)ij-|;UZj<?%cn^dL3yOpT6lWhp<c$qI<&JPh^{2;P#4zfwxP<u'
    'YPQVHYj!G$p=?TTQJ%<+GTdui=ez@0lgx}P90REt8s{mrH#OFm+`vigt_uMo@qu!!YC^hHVKc#(xyH2*'
    '$#a$GYeQM*pJx*t4zCNZm{98;4rl41)`{-=^6H;^BedtL3R{u^-3*i}sjdnQG&!^`BG0-&a+F!`q<Nh*'
    'TR4<l-_RC^P)eW$_-l%xg+tXW*O)j`U6Y|rLFO*9)(5t6>pIPMR)7tkd#>k*w=qUeytH{bxxG_kQ^>{U'
    'SQ{f`O*E76*SIq&IAL;xVijrfKy=+2YYDc2@Z`2L#=OKa2z>K`h7sVqWs%9lzpWOH$w3OGoyh@;Eh(di'
    'q(ugnvD3@~yUQTloGE7JZ1nD)lBQrM7fpDdBox}_7!0+5Nyy`+`0wAK{7(u?8yI2+d)psPm?~{Koh~Mo'
    'LRFRfk2Qk2#Va%pf2G7to}z8md1?W)vJQ;FHEI)Vb~Vc=?KWV3JHbAbrXXikbaR-yHM5b^n5`<=2=qc-'
    'Yy@(#5;k){Riu5JA1IkqyBk28>D<cAv}!<2m0mAZtnENoD%A|kl``!qWm*?%HWL1LG{Y+An7D8Yko2Xc'
    'i}Bl8%^2|&%naZ?6ml>cR4o6R1DC0@rLWF5ylq#w(7J)t%~dvw@FkO5<(Qg}ViioeVytMp7r1THjroEF'
    'gwTc^KhWEdsny@upe!UiQ>uLv?`9Ny7TvXSBJy%8L2GY?Ruhs-*BQeDQw5`P8UF$qQ4F&7oxXf|DxG9i'
    'Q&8-zcvU;*n^-MO;3lIXw3xLSCoL*hW%v$9!S<OLAy;%!mu)l}!`ZdH24h6ojW(Aju4L#q!BAfyik2A?'
    'GXtLf67*y$q?lqY4{TO66*}b(>9nboHcB}w@Hw(Ema$hTR!n&?SrVxXv%s)S-JyD=N;1`Vz9P4(eQc6U'
    'SUD{sSH<%}{Bki+0h0x7e0RHGcJ+jO(d=3{FwO6bc}uehAI(k8om*#04(}vhgMxk=L7O(1b#V(U^9+Wk'
    'XsUEe+0JRJWR)pbTQKk3ZBvr8U>A(q&!(_nY)vPK?kPk!F{m@xSjJ6LRM!);yC62Qe~Td+^J5Fan?9CJ'
    '0%Ta;ayojpn1f?z=uk@cDo+naYV+PMWS9yMKF%E4n1X2rqiaBG*+8lEI-Sk166#!Vj1A8k)>ccD(&-$C'
    'oi5Z3n`Q;zR<Q|HyLpBoo0*|FTV|F9LUx(?H8ZW&cBDP)DzpCf21#+!hSR<UV}{+v4fBCy=*HkVbP9f|'
    'XsQ1uC8nnK$r^Ty9bj%!k!jF*t}<kkWOmQYkw*$x?^`e3x4OVroV3v^A!&!!9<wTyH<^mLnE-zQ%Whkf'
    'Y3~TsBCK)(6Bm!UP~Gy{6bXYI;!H*4^V?za!mcsg6u>sbr+Jhbb{@{Ag4FjNHalUEH-cBbl~GVeY&@Qv'
    'kqKeyYP{K8^c`3*;GJl`R-GCQbM%gRx53d2wxG|FJ*b&%wplx1ZCe|&+YSnBdeIi<+Dq5pEHhvWecxcM'
    'b{!IKL&Icy#q1}nq)A3C3%;o`sC6l(rO6i(WM&`CCCe>a6dEBzHN~FBsfqL0vx_HKq2Pjyu4@#!&esjj'
    'fT|mOO1nE`Pe~do5IrlsHnYlO*#}9t^tfa<f-l;+w6c9P!%8K;0gcWwcT0%rZ67(gZeH{T|7M8KM5K8O'
    'woL`Gi|D+me3;($5Tgwf;?|NizM2ZvuCd0|;Z0tAItEK+Je}%bRm({WYcp?yh)1v<&~@p8@ThxrTf6b;'
    'b`DvM;@NpZ!CCiKvo_>MsAShCWHJGiS5F?yDUu7pv80D`MzCpDlaq|>w3-p``mEY<L~`>rdPK6hL2a<a'
    'bcv<D)SG7@%j1cd&4}qzTI>61@_aIj>xSIALTFDT)R17mnv#(&UwX-~u4psnIF&FnMyBGSV1t?2@Oh@?'
    'A$CpshP(spwy8We76Xn!eY0Ylep=rEBN=Z+sA_}FNs1!8MW=9t?j9Qc1~SLgBKj0p(SHle=nvI8N`uZb'
    '&~mE1bgCveXh|dIZw4Hb+sZa!-NKHmdVz!4?Eu8xutC<<^PBN}+$iNL+bwieXKl6^&Sy=uadu+$1kT#T'
    'bQGY4@c+jCwxjNI2x+eFcT#6-h1XMxH5}W_;-;+w%#|Dy38wlI8M&^}vV(6-+80^WG_)^P;xWa53GtW|'
    '6a8lJ27H+6HJ;WRV}3`b18m(=GeT7a>hWkMru9>svKy`9OX#1?+iO6QVzSi;);T7nnHO|h@NQ1rt>MU!'
    '99lz8E3E_ysM~0v`4wq4bDm0+@g4&9`wY-;!UV*g-~BNnA3(0Uej6x2pfIDVgX{34LQeC$2<s#`xHTIq'
    '++d%EVn3}!io4dsT{92{QY41z>De2sZ(8F@*E*o*t8%7w6Ht+hF9crA2RjAy95*lDHrH(=aI-OUgK}qM'
    '%BJosC6{oJ50o}B0XN$*9TT>i04|aVY4ZD2A-m5twoP;l0EF~!G)A<1te0QE33;wiqP%1HhN<ukQ}?%X'
    'Uaef(B;x@u4#EVJyB-bP<FrJ7lX|F^nDaMGN*kmZ()H42H<ov{ygAnxRMozVD{-^|ss(d2vls1n#QA>h'
    'wJ*sQY<A1%O+_SX*dxy2##kAzO-vb-twPhJvf?yRssiCAvxKpnl))xADm8f6zea@g=LtsY8;FJcZ88>+'
    'BZ^wWI<YlQ-;g<(Dh*Kc&O_E<y%OKgn^eJG0$EzT)k{vNHsxw{Rim_<5dIv{JgU*3HwQ%5imF|r0Q(&*'
    '@l&^9@K!uGGPU*kT8bg8XsT)T-GWscv)MHYT2cdfJhTCLjo(_Zvx!2GaVr@0O8p*mYq>vq6OG;eFXC9E'
    '@qygVHBY9^cwDtqN*(~Y{jNbYAStp3_SJMTn4=&$Bh%?S^jzzSs`bgWVHmEDVUUgTR6hscO})NaWflv<'
    '{g(@hCqeMj<6CTX)Tpe_226~rHOo@iGR-y}gDpe08Hk-N$LbH%V5Wkb`K_pHY9hg%4(a0d@h!Pd()BAF'
    'iW>@j9iqA1sddOk#kPW58DdsCs_CioKy_Bp9EllNW^uRzY^0@Qp?#q;M+lDApWtx%456ufT$_F)QK|0('
    'jHi!BZw49zc&BqPX(lW;q1KI*6}0NuHsdzs=GH;mkeuUWFl^<OjHd1!!*Gpd=kA?pB1DrC!Rc*dQMYF2'
    'DwObWF(r-bhipu%Ny1P%qefzFb4E?w$K2G6Ny&|QwirrGXWz0Y9_S@43j_!grR7rKBUneDr`ym_#&00s'
    'WQ;Dwb_*C*NLY4a*X8=F-O<blfr|mV(RNAmpj$D#MvPnl&KUD;!fu&0rZ8Y%9}Nzc%V|i&n~P{<t6Zp?'
    'Gs^J!3cby0MQe(#P^`mi(}dU@t(^-Gsw1ejHm?&b)nL7qjhTdpnsMF+I75zsxm?w4p!et;Oq0bJa}Vl9'
    '_STbV6b~mC*S>3-NRtKDhzd5L8KZ&?&@EE|$MF*BJ4qH}B6T9WgeFvgAw!tI99$=sL(MC7+rTxVgH34W'
    'YSOQRZkY}+dWvO_Gizx`1{*7ALI!9%W<pO5(x{h^&Q|G^>Xuq#c+>HuDU7<Yigj;M0jqn&n*-9|ls5<G'
    '3d=Rj8-uBSUR>z1wh|v*18mZ5Y91X`-FF@=IBY`0L!;EHOaT9UJbgWz5Y}o|(fU}X6CamGY$^`lrXv|k'
    'R9p&L+z9YfaVPo=w*vEZ8b{aGF?7ks6Jv?jMZ{ykpHhaxg_whcsoNobkenu~yT;n)OuE1h>tBy4f@;Fw'
    '%dEGBHqS+qHg~gRV+AI=$QDe!C39!pTh-?8RMVh2CRYW*v{9|XQilAiB1AQ{s#Md2>etCKP@W6b(xCyc'
    'joYyZ#$3tm?5vDx`wU=%>`;u)wj!nz9Ku{v))e+cFT%hWMYle4^wGRlc6vz+`Af4_gUr-ToLs9blIe{r'
    'M&{xgB}460-J(0TX9?6a`Pv{-nnG6htuzjL8V9`;2fZZ@%HFb?kH<re))cve`B0G8GegenvR&nc>Z@Ro'
    '3e+8#DT0QbN7&WMIN<9&^?EOPy)4SMPiaMpYHs3s0K##JzgHhVyKwqv&z@dgoSt3vFTXx@{Gjti=fJbA'
    '$Yq{wM>3**WYajXB2Ti=vz&mqo-gdcrjZ@^e&AUlaiUlTzI3=J2@3;y@Y&hv)%jP?F8->2d3O5r>G?(f'
    '!CzgSUjppIgKoF`Ov>S4Bs#er?OZR&l+Qlz%x^?zD#)-S7sFvMxm47dF)|v7X=l0^%{qfo=j`zbKzcbk'
    '_^fjvr{mksgv@V-1KQD<K%M9CtNv^9!BpgaMN2IA!3~+=`?=2+Ai5EenPD`+<dJ<+Mhc`8(+e7adANEe'
    'ZAaCo?*Nn@E&K1qvu9U;JY3UZzpqkD`$s2WL5+uR#NpA&giOJfn!Rvd>F1xEK7QJNa(?mEIc)EfCy(*v'
    't|vm*i|r`jj_rAo>wDa#(qjSj2n`6A%<(0&Wp@L{#rfH@i-)*<h_w^+&}WB-YEt()_-r@JwQ}%1wiX4E'
    'kZ^AAmJCKcu*|MSk1Y6L-gAJCdbZWGd}R@LaV>=R=i>YM;nC5Ht{f=kGV5-x=h5S*4<A4M3McbkcHd85'
    'ygb0xg@gG^py&JQccg^XZ_~w4tbRkf!{53cIR;`vO4?lL2R-WJC(oZ<TxBpQ+?csRNL*k5Y5OwveK)jh'
    'MhW)=ZgJZR<A6n0g2A(A-<@Ba0@&vl&n}lUM+QTbQN}~xqujGO{6}3*xZ@Dd4IJBMJc@<zLK^tteI*?x'
    's<Ck|y`^z4b62>Bxa(a{!RiH(asOHXo4})FGU&Y)@9u|wI-SS1>uk)W%VIxtL+UZ#iz1tZUhFUuI+VM%'
    '3?lf|wLETfThC+m%LP_YfU)PjA^JG5uY5p?26pXa;75<YIqyGw{MGqo7MX!>IWCPnSZ);iR0hnI0gnU='
    'yvXtdr;>r7@pu7{=ciX+BM41(AQ5agN;<cz+-QA5oHCUru}vr|sy@_zL}7Yphu$$DWidsL!ai<^z1f9N'
    'e=g2$$Q(>M3;?Ya8tERdfONVm<L|NlvHYuoIMR)*hzcetMV<^Ij{$pHj^GjDt^_H}V_OiQ6j-cHJ#H}|'
    'y(qSbAf$Vg0e9$lE=*hn{>O{i$G;wUHiDTa?Th=A%<*h_F+tJVpWP79V7Rgp4&pMCfG~#NGWqmHYc~Un'
    '03w7PTa*)!fy{yxdni6gWIF=z!ed8(oF)u@j<{pl0gFA4x!mPm><Mp)jH69@&PvABm>?rJ`45EQIzN5b'
    ';NSPt@!J;`h{_Bwl$qnVC^ZW>Nk8`?tGLddef#{`Q<&OcUVVFUzIBR(3g7i3EB5V>3F<nb<A9)zW#lv4'
    'qrUWML<1h)N3Zm3yqJtf7mE>M_>opNn(#K4fZ~3A0m}4%6&(8haVN5mJGN~d70g}#%Z6k&>wJ}{vd#03'
    '!_-DN!C%kFOdQ=`jmL%TXyZ_YBLwdcu18>t0;TAyf}ptibi5ex!<iV$?5p^NvB`m$0lHq`tWVIjog5zJ'
    'myzh<?n$a|^$>ZbdNP{~;m=5=he!EAGG7DP$&EusyfYfl^@qdcQ}`>H&H>?IjCB97d-N&~4%cx4I1|(P'
    'IVg+a;ZTeYlZ6}|cVg$L#Pc&TU%pf7rR3og2DqFb7HeJrWLJc<sWJ<I48=8J?{Je;ELrW2{t31x-9kXE'
    '{tWSn+g3cs<4)0-Y9sXPIB)`D8*{B5P97{WpEe#U5+!A}R<9n=;;nB|4iEaV`<tYPbfh8A78H3%?ZLY*'
    ')W1jfi)l48lM8VzzSr*@cc!xY*Y9(7+lTuv{`&r(eEIU_i<d87z53G)5%I$A#jjpi@Xw$8QFjYxXg)nw'
    'E(VMN2IaA4zc2LqG;<wx?{5Q;neNl^{PE}zq%s0SqZFWhNCnk#N-h=Pygaa89(4Ys<5>Wv4A27Uga&$F'
    '8R&iSJrk-3=d4e`3Wwj(FVRLrU&)U?kWQbEu_ka|xi<Zgc$*e~xI>J+|M7~k4<%^5fRTy_KlAR@bRmjf'
    'I~mM?+;d{?j`6{L=_+M3kl;Mx4s~DcbYhOT;zxhI?*d8%9{#4=tL-NY@x2ivGGYQvsS%9zM&uuX&y^1Y'
    '!_xuh0*GgkW|OM`h@QAEmIPyvVfRCUa7avv&AFEn6G-b{ppDYSpSrI!PwG$br|zo~(nI4`y`#At;cU3i'
    'M^)e;^C6V(nyA?(91=;AGC*cU+e!aLW|f^@$9`3Ef=Q6$L~rAvVhAz9sz~5>pWKM=`QRFH3skK}$nbr-'
    '^{=)eV<ExwhlQY54)5mtaP@n}6IZ`4eesgQPLEJoMs}^P5|5of?SO=af6KvHjD{f61n(#Nb4$KIoGx*`'
    'gYi)OOw%pweDOtYM`3uoylmef#3k;w<2E<%dMc&Fu;clSnD%hgjosWfVrHaAWH=LtWc2PZ(VrPn9E5(z'
    'C3rxt6$OMv7G;qabLmGR#t9f9Byub+LD?2sT1VT}oC=(23h$>OCKaE%ouJUd_+Fy#@<LBV<q9?1l)MGf'
    'xI3h`jFzptT?vcphZNV1=U?EnM<-lpzRZu9!p#TcU>*hXb+ovpVtNdiSLZ0l9gsrsn_85XmI*etICQ1N'
    'uoAj@q;2vx;UJh~UWn<pT9RLx<!vE-@%;o4BRKA09&Wl@8ddo{$_-O;+UcgfNOt1Y3)l%z5$O!J!1=?@'
    '1E5kB5Qmo+7!uc1t1&tsC$VzvT6X^Y^4U{(LJaw_GIxHlfSn~ExaJHSK6l=b;X-r-u-;o>UU5=#@)<Jg'
    'zDN0)wXII3`iJgu7iC-bLl;p09u4c|;y#pP$c*8Mp?)wfwE?KCORbw{eUv}IvLJS5{qa=WqrbbJ^ZVWY'
    '<VHv|`SZIE$A#Y9QM2JTM0G)2SE<;e586B|F$WwgrRgm`Xn{<*!)s3f7I^A+ICII1JKZ^)u~L4Dg0}f_'
    'cbMLtQhr+rAbK$$?(0annwJW9HvpB)C9B|T14(Bw7->CmgtFccq(4PS+ceImno{feLjAk#r9yK^y;0hv'
    '*%T=!^YQHvB#QWcfYHJo)(OfvaJ^<3AG|-9B?bxl-1q>>B>Z$GAB!W0JE*)k@U)fa3zV4#UHSy;PKbJv'
    '-D(G2cS1c}tr|qZ;f6Z~BZhu=-S1v0j>hVtY1GF^w5I?V`b5fPn9hzngkl<AM`0BYh0;|c?EJCpR>EZi'
    'j99LdZeEEiHv0Wg<GWaIGqziU@5-LoR^q$u2fHR1&9%FC2Dt8sp5tVf77p0XFA9+Ps=&NxrmPz)>WnH='
    'c-A`lme+()Pdjhbr><4^MW;~r*3!GxbZ!xS?6wi}Cj{NU#%Mq3$ye`jN9&&sq&Wg>@w*MdnfG~frqHXM'
    'GWr2wuLTGotPww*-3%rjrVgK#RJsM9H%XkD3XI=(CR1?ge!0LF^k51D*JUTTTN_|LB!$sBx9Bn^@W=wT'
    'VKm2Jv*6X>oqs<WfMwFbAeneGehoj835J!yNK&&`4Zf#~33}fPb>(N)QInqv^c%qf7~njT%&8lAWr&7('
    '5_c|`NRe7n=fwRa9VzQysxBzXtja`gmI0yhX!!2;)~D<iovwGYp5>NP$K8(ImY05HzTI|}TQ)(V6x2lR'
    '?#^W>1xc^4%t3>R6G)@>Xu_6RJNqt#WI1T}ftyTU%<=|M_rvoC-+pzsC6d0bN$%xA7v)JW?7lnzx^wm0'
    '-D1&qa5JAzX7}&i)6xf2v|0(ce+0`S-_wERgX47l0Ia(m*e!W2RQEhgZ@S-kum0ZoQ08^LLkHhpd~+#O'
    'CA;;P+HqnrO&9C)y_@MOr6^35^Ew%fMq7MUyo-musMdY1n+3g>{%w|Et~VIZPTr}>Y^8=@j46Oh-%L3k'
    '7s{q$4#onkALYjj`_<}?pr3k}%F|OxtgC0N-8y<Arb(qh^^T6uV=nG}%wgslOgfd_N>hqCyXkRIQaATI'
    'V3*-Kj_w+K1{>02*gA8BMSWmciF;V)?R0ZjdAdXer++Fe=7rLe5fyGAoS1QDTMqL>5k!poj7m#H+%6sj'
    '1;09G(9vd){Vxu?Up>D1=KS<$m;LX~FD@THdx|bWbmDj?ZZ5lT%U9<8^QWf|zR{;r=TEOL5sqGOEim6c'
    '|K{20!~W^T)#FE}XIB|$uXbxDE&E`ZAMSTv9=ume{Qz>}4y-5Vkw_wg(L(e<K7bW8p61>w3X?B}!)14k'
    '*<4J3w-z&@GBn6k^Oq!pA=X0zCwxC#hVv+7GyLjxM&wr9?_7d7P<i~?bQQceUd%fbL>jwEj?La>*s*W~'
    '{MMLHXE$Ovyx*Z@b_35N$lc5_6Z1|_EXJM5U?LE=rQSk&0j;#&n@-A9ouAy};?2Dg;Gh%;Tvq4h%kCc?'
    'E+M=@HXo0U;8Q@y%LC0hirnsm_wrx~27c)Du*)u<9`<@5%jc>e(iaZ=HXL8~#*_K%i*B!%yLZvM?R<TH'
    '`Ve$q;b_T<(J1cXUYz`5JQyhlCubI~_AoJe(bl}vmfguo+N(>)N5`($Bg5gZVg7?D2t|D-0)8Eh_1%Nn'
    'ufcB^{`&2;nE(3aOa1@ZpUlBt=pJq6eZu_ueI(+3AJ6c+eVruL?`GI)nfi%;Qv7lB+4GBM>J$U7)tvw3'
    'RsZqR=igrGn=i_~87}Bo=+&tF8Z2{>xqXzoLY;OySg(gtP-7FdPvK*`OIYao)k&aL*E9eN`3a1gFTbI$'
    'Z{p0)z&#uTGLzm%>e~2PZH?8#t7R7SjLEeMz`37|$5SxSNq!OPsf{UK-lzz}@~OXAz$OgjyOZycp7Dm_'
    'z2utW$%KB7KdQ%8cSqCP*>ouK7e<S2ZDtq#Gw}`t9)Bn>XP2$tzu$Gg`XM;8(<^dac-gbCu6EkF2N#PD'
    'dZwO9@#}>*z+m!ymdw7-!M|p6eJkm9jCoo-v0jq9YNa8))`;ly1QS)?&)7|Ozq-t`$CQX^e@?FRcTJn!'
    '2d`Skzf^xMqBSxG9;%~yXPd5F_0kiP>7%xjdKPp#;Mbz^yI5jdq?dgQCY@fV%reLG<(_V%&+J<(@c>eQ'
    'FW9`qd+W?p)ar3tpM!$Z?+vcuZ#EKG7gAqeT|F=R(zCZC#pYOke0xJOeNPnmsF(6lFX6-9k`MKz(V|DQ'
    'ESG(1*(p(RR}Z+Wr@5=RQKEh+AyIuKmr(lpW#8m3ud@7#Sz~!cE1|CBg)K5`gM)V7|0?xR{*qY!d0l3n'
    '^>xrS4^H271iwoaQ%>1UPQ~mdHPr8ZLG##-$F<x{-bpXq&)$vZHv%Vy?}1V;4WaZj3*IU>*PVB@Hy=;4'
    '?AGxNR@CVQ_;=cPT3t+jUrUhO?;M1o<2jaa1+zUr^uWKh15TWnGG7RX+EFNMi!!{5Xbanmg&%vNXIr7`'
    '!XGTsR7c|!T-)YW?2;gsjuYFK7s*&!k!@Q-+MeSx9z`Db@pc&5gi<GBmK!pg`WA75(5)icV7S1wW5@L<'
    '2}9<&L<$!9Q4l+n#Zp?9i}&%u(4&4Nh#&b@5R;I)oW&Lsf$y<0CL|2wg|TIm$fJ@)QW8f7F=r&OBSJkc'
    '0zpG!`?d@jb1VrmihGQPF|3v{PNUeXsZ(HN>Uq8`Ttc1Da~$ah5p`{5+n#io#Uyhr*Y%m>*|yKzK-zXl'
    'Z5hDs$4+Sbu~l6_!Jxv69Z4AHf?FaC0^1KAo5z-gcjRp+bR$Z<*b=_w5<&x;go68COakf<k4B`q4u(m@'
    '4zX<lH0v>!d7dL>NM#uCz#+mDk?Y#R;vx6(Qa<;69^0{qiD$c(9a)@t1}#S12U`GN*@CdZVF3w3D~<vf'
    'O4?EYrd<w5Vj+o0<On8wE;)yN4~VcL;knE%sjXln={nr9Ek_9I1AkB!!~wP4*o|W1ival5vjWGJp&y5F'
    '=t>F0c|jCl01KvLRTtkdsP6}^BY<-q*AJYC`o0%Nu%Ez{KCH$KVhRN3dmIMzfWHNEUA*ZEED`Wf_)XP5'
    'Vi*Ke9K!%Kv^<~VZBP+25mIIe*j5UXOESlGSwLe3TkN@!<eu$wpT#ka!kS6}Ms@&V#G_Eg%nN+Z9T6}g'
    'DRb@6^*}~~(6U_;1t3pIEP~i4RxE+eT>^-)0=u4#0R!9Ibu0o@6u7{=F>xFxvVGzQu<<r!C|!ck2T5Z2'
    'T)@<bW5I4%B=(&+^xfEiCWTo<9M&QLyOu{nCLACohl1va{eVapsKNCjDqR@?n-P#et|f)#QEG(({+G<6'
    'j+GB%Tb?IiTo9F<hXJ5E2As#C1bSu^wgLFtq8#Xg2^cR7A`9je!zPh1l7y4e{ymNrT7mBZ_k?y#ZO+}0'
    'Mhs81Y@1mmU{U}91c8v!b|tX_4!R<uLEw4>h%u6l9Y;lKj^K`TILK?8!wTcr0~HB+!v;YMWEjRV2z8GH'
    '5hH>UKV}xlk<hmy76CrWMn+&LH}C`01d<aLI>ZkpvwQ$bBnxfOU6eCwhfc&p2I#cx7>GXPmIRUONlHZ%'
    '&jHz)fTWIH%85ttGPo5)uzf+`_%STnhZWM;3M6nY13k(j5B?Iyk!Nui6uHZ)8p=q>77ZkgVE|i5KL(W_'
    '1cZPjMa2d3lY&?V<q-lW6IZ|<1IY=W!IHuD0FEjdih+?x>;z!II3$kn?z#jkic+8#hdP!E7>8+4SfKO?'
    'izx-A?cfP&?1R(*&UQ)J2oes(LG%OHOV~6ER2u_D%&EsB*jxg`SdL9R;V>Z8*a1!sVIHn6BMF8GA+FOT'
    'T%k-#*M?n-Vs817i#d=1p&`g0P;0<Bz5uDff+!*ms3DNaVDAvm<)AhwXlzQ#2Ci_W$oMt`X$$HV#a#$Q'
    'A%G!x1U8ND%P0gj4_bjTPzqsSfepq2%d>!@W9eIWxivUM5ZT;uz>cFpA#Mm3X9QLTke(!g>sr7EaY((;'
    '0!bt+uzHwHBp9qR41tak-C92igQgXTbEY^g2*B_a+=JZ&QgI#X1LsS}cJTxXrWk<01-Tgc_^b`g;qx#I'
    '>pA7Pk%5JPg@i4Xo(x^gTqVBkxe^%__K*XWN&y=X13Q4}Yz1y;V}%A02@y058=~w3J5B=m5|@K};(){h'
    'vk8<8n6t1Su^oW9fr22iz|aFCwp>p#BBke1_?h?>ymFL3V53ApIB^7~g2TASod_rl=*qJ|>_!$&#d5eq'
    'Lg{#*YW)BNl`p_%2fC1?T0|I4D6o^`Shzg21L4LXu^kGU(gpPikOS0g;O%fX@@?2=5BA>k!0%!%DtlWv'
    'RlR8C{Q&uZf92Tdnt*U~;a3m$(sjL%aM*CrXJD>}pkaW8fLXzopaE(buyWj`HrXDoM}rg`NMJJ%pxg&b'
    'mMb>pBz95G5@83RT|o4DKDEH#L2Jf`|AG+Yg71QTS}(+fUKdyx4(JaLRFliW0t0uzvcbp(Psjq3FmORR'
    '+wdn~URYTKR+0}6rwy#j7&wDfop%%vz61}|1J(;I2_~m!`5^9G5M(xC;0A${%z%W5#Ujqp3jr#2z>fxW'
    'SPaOtQREWFXW#<I9vEK0b*}GP0pJy^LVzz&Q-XUHIviv>;2Z2un=u|ziXKu-Bmsi25<f!&6tq2V9#}wN'
    'Z~}vJ@G^Z4K05d{V1Zb`8zBWBhJYJOd=Cs^Dv;s;*@3h~{nG$c*D?@Z6fp|0Egpbl1&*^#fK`|iSp<gU'
    'F>@$d+`vcyScrBA@|b(BPeRKTwc<I-G64gcd%ovd#E!ut2pM9PaVLmvAl*0w-7die@vRVsLbu-r2|~a^'
    '04hu@le^D#a3spXtPvpOZ6Flz;k_7?GH7cVS+I0iqHlwUXQ&YD*vH2~JqRB>Az{-XY;s<J#3aCSMFRyi'
    'o+~U7Q4d%bB!MeMAkd-&nJ6s_L{R7nki^mh*BbUAu)qeUezj<p3RZ-61XhR*GLHhbJjVk`5qiKW7P6BA'
    ';t<%E1ABqj4*JFO><E;A6Zit$Yf|}`0<C)R(mWtjH$+du7GNxaYean@)Gz|`IrPDG@uR>dk&BTgP%I#t'
    'W5Gec5ir5a9Y`XtfGCSyc*PE^h@<)djt9{#95AzBw`53tkW_-WV5R`NeZT_<VQ?U9Fe0RN@Bt4^ug=e|'
    '&L8%lKlsc3#j~HQU>}$wcy&PE$y5TDN!JdfZ-a?NeNbT()<^At%Misa7=Y-k0Lp-O0tup43h<9(Py-k<'
    '@U<oZaVn-6phm2#o5kq$44}P8XN{0w&h`Jgp?wODijPK>1q#Rm=k@$N^y4J=y11(2^6lXC^pSTKMCabw'
    '0}z4d{yET+=be>%+dK6`Fp``od=#9XKl1G}P<yUba_lg+&w~e#Ea&W@>pBlCCyq~Duk6gj$bEF?1IB`L'
    '5Fl~*=%F8<#Si^*Z%5}aZyS8<2TuI(!Nbr!jZVS0ch%eZ!kBtfo8r6?${S&P^|Ev7JqpjkE_nn_VSMI='
    'kIn(#kz4BJ8oSkKvr6vOhumgua)_>tfEgsZyjD(Sf@`Ghk?!Yr5=~OB;%X{{0{3Uv)A3^RlRMx1aMuId'
    'F}ti}wsT&C8Br4g>GlW&^@WgPDzLsvi8T$$Z2q&+`0WVaym~j$OVcZ5%SO=((r%_`jON-{z6;3*yGeg1'
    'jvJu328MS7S|Yf%JNUz4-+S~Zd}uxJANmh0@7#TKdU_s*5B<~1*nhAX3^`)5#9E}@DfQ~s?QgoWdc3<|'
    'y1G+DW~Onelb95qpWl#KDJeqn=~H#Q@Py1>BP<83FfVcgFD&ss?$oTitd)9)I<VvOv)F%x$8BKbxu*{v'
    'onmaWq{#v<`gsICmH*(uqu>kx`QCXLmo<1!ZTlPu*?IUNei(+%`GbeiqZmBq5@thPEH^}Q1srFrjBWf{'
    'MqSs~pGMnLa(6zwT6YCjHOU*>{<+LdRq*`LH_x73s9L00LYjhegTDXafg4*62|Nm}Hj!@V2H>87bwjC3'
    '18NfogFKOgXX}p5;3?@aETk=@4XzWF{NVUV`2^azHUu({*aO>U%n^>ogzH3{Q2@atWz@s7b#UwK*aEvZ'
    'Vxi4F>9G*pNE?F`lwdrA1_x@27z;7E<kazQWzC%fq2eJF!%u+=OC+v^2c53P7&z-OcxJID!QYG}w{0u('
    'ELf@oelVWWI+pJyi`Ib<HAl}0tq?CuGe=5dF@z;p5X1x^13=f4#0df}LMu>FO5t#i`*>nx1;PWz{OH4H'
    'pJAdtc2pPBS#q%u3o@w^YR8=+p<;M+U#%s%;&_;p55lTVX@Ri3U;65}bMWoxH7XBGv7QXYT%`9eJA=_='
    'F$bZArFax@1zX>@P*s*bOD|%eTZ-w|Q=#U@Re`$1S$&nv3BT0XSOy9HlFa1b)v~bC=N+w%mJcM_Y4yYs'
    'P`W@hndJVI0;kq#!>XR(G0N!r-c(EkUM%e>eCaiHW)m{nSXg#(8m{V(z=Vc;oXiey0Tdxwy|O}cKB$0r'
    'K1=aC!D}>FzZpwsjq&~|GO*wqGtvhadNQBE*B^Gy)gmSYkUYgG{6tLW@8G!!8BF2LcYxjTNL6cE?xreq'
    'F}nc_;K{GP=$e_q$!8bm&rcs;^q*gx7xieMp~GX~1jpkT5%itVB_5Ec$1FSax#uv;^KD=>8O1CB!e$m8'
    '<6E4EBn&|SWZ_?YtC}=qq%HVvfrqCt@H%I%8(Ll{BJgVQST@9iLFq^@uss-%$As7dI1<KYE<Eqa9Q0K1'
    'X28cW9+Y#><Bp3Z-59qVDlAZwOa_#BJd_sq<JfaUn?%y`rGxhtq9CGvELaZwqsLFbI=^^+@%Sm$l|KOI'
    ')%GLHv0@TCKCw|i_$;)9<HR8Rn1vA>7Y5`Z1!$fJ%0i+Zaft7^BwoV4eD>|d*?Ir*Q@pfvuJuH=ap}!?'
    'aeXs?D5PrrzIo7G5WoU4Lm5};ApwsZC*Tx?7Ai5obr402P!>9l<HdyYz$3QpaW4V^=>#t2ajAYFolO%b'
    'GX(*-5xy5vObrS_%mHSl<vNnOc>YWT4eThyt_B$7BGl)OMTKoUv5bMRtQu1&434deCj;|i3AS&)ef$vX'
    'whcy%Oh@YM;eO|!>R`n)K-gFYPo3c2?<6~j`;}ad{PNh;Py=-nZ~iVfiaNx3oc!g>?N)5Xv9dVClU2RC'
    '$D=vOL@ZWk41W*FoV*-W-}*vZd&|xn!b%=|mX>gsHU?Rel^M_l#MugJmUL=-+O1Igc4BX1fP{S#y8qCC'
    '@Jq=&RWI>UT|+V^h}Hzc;C6!fGa!ZaIIliNe$L?Oqa>@MO#r8NE!X;7r6-<^;hSm<o^7{SXja(ZJ$V6m'
    'L3msU4i&gN;Aw&X1;(1Rqli)g<^%<c!-K!`Fy!D2amm4<p~NRqMMBuHDKMGdb7jb*h~TLoSX?x494;9+'
    'otS@&84{62BEm5XoCP-c@tz&=Fmll9sXBh4LGjZkWH36#1URhqL53aOxx>IF9u)7(st>IZ8G7)Hg7feO'
    '?<78>INYv-g{lNNn@<-2G23(%h+K(iIlv)J4z?GwZeKRt-VC}D)?8CFY$dZ>W0t+}N=vM=Pflr5YqoC!'
    '7u&xrS+1>_t?k;Z?OGOXSgZThrYcSTlQR9JOg|~pACgr*>C#WS^ph^#s!O$VUg^43frD=10#?(&zm1n2'
    'eC9=X?rMcG-WZ5HD`v!^F($JIu`gnWc!A@^A!m^~*9kcuqreZc&KwFIb#?5%s*7YM+|}tGmZ+Z8Z4&Xy'
    'Nc>iokgTBG@zSxX;b<g2WoY(gBUr{}-YruvtJ@@Yo3n`VklzrkE(;iE&U=@o2A0i&j*Sh6O{J1@fM!Sr'
    'vES`JQg!`6D5^GCODWjt{lwVJb#lNe145^6bmVY6o_^jLVOm3n7#j_XmyQ4;-cdY(1)9Ye?g9vl=VX3!'
    'sCL9G_<`&s84n72=bkaNe0~1S^Ye>>c4bGMKlsA*C^|{N9I-BI<4(z7COY3?&c-<w-8?)vOY&(H33m+*'
    'hxh>!LXmVW_`#7WX{R?C1cq+1Xn2piTlYAryh#sUz8w9bDJ&g4LZv1&=5y&Wn&FMfSuHQ_0nP;Xd@VOl'
    'I*+E~Ux`sC*(y^gBy{`+yRpp)W)hyfMCUTCOxkUQ(KR&~<-$i7&;FzHr*_caKRYJ7(gruaC9@=>OK*-Q'
    'v*A1A?71ux&|h+@Da2`jd3MxkXUQGbd(R*Ir7;E-Z^pxgy8qjGHXU56u!b0dz8&>2O}QQ38O&BYgyN?M'
    'wpR~-NSMjg;#TE?+hEFd8fbw(`@ot{9$#W9?H`U&P3^`wr7z@s+wR<mA>c62ucj8&65l78qRTthX|3-0'
    '${aIA0QWj)-+cR^|Mla`t7jK~Rb-TzCG6Q^g3SjE3bJK0)B_3F!YXSNJCyd5k(Q~s#<gZLz{$0kA7<^H'
    'Pgd;4a0w5lo8OW(t9lfZTd`_{i^=MywnFjA#p%zJ%{T#r^A`BSupiv6>xI}U@VQcSwLoB7h)ffJG5Ugy'
    'zeSsT6+XyZYEX+dOKHh2A!JpKKA~%@)o(0#pkcniF<$*nY?9iW6jfCBPik$4TH~Q^l}b13yk=^JKn`c$'
    'UZ|S3muIJ$%NBc85vB+ujgx)6Y9YDXaq;Zum+k6>){Q28P4(c_$z(h^)L1jM7f;97rtpW5Wa-s6vyx1q'
    's*~K)YgN@OF9S};Z<9@F-!fRSi(waFLQTdo$`m~`?47BmM|<PM7qAM$&WredE=KBX#hj;d{@t^0zP-W-'
    'f)<9C$-GT+I0(RkyR9fvy2c#(1T!0hfD$nlMa<lqebF0=(P3uT<!#zm#>P`3cYT2S#z?Arx8ODEOk!Me'
    'xt_K{FUx>s!ia}J&E`%}Q|S#rTaC7GF*GKqN>Z&^vMOTtR=9ob9(P;LNMB!ZS2yR)o_8uc6l+|l3)s(o'
    'zE_7JJy7qOJDgxbHTy+oM}?ccK;M>wpgIdHbN<`s&!1gfsc_z9JBGX(4;QrxAMDK>PHHB!<JiMywQ38a'
    'NXx}WT8U4;(Cl<^e)=#y7(rrq)iKSm*%36ywsnxS6g{cM*@pbNIA5zR@o~zZG%;vf2@msDhpGUQ?u<DS'
    'Xm~3(lcQ)ZUv0nXYKF7bN+he9%sDx@D_1Rzof#U=bgEjrnQE;@diRp2)@`24ecxOH?41!`gMM6VnQd(*'
    'w(U2sZ9i#k`^;+FLsDDYIc;sHwCy#cZGQ=EE$6fCHJxq0*=&1FW;2`1w#QVqy=AiPE0JxFd2HQwxP5O~'
    'Y<o;%YbA$m?<s8i%V7IGwr|_cd22nlq4kWn))U_LmhZOLOsYL*yX`00Z4bF_``w^DWxBN*{`e8(x$Pm%'
    'ZEsm_?IpSGNe{G{;$}X>?FUG3YcaoVujy@j%5K|Va@&4#+l;5S?KQK_cw*b0^V&Aj+S*M=+e<duK9bS)'
    'oQu|SD%yTC(b`HxE0Kq0IC|1v8k*rOw0$R`wVs2vhZM9uWuUd5fVRK<kG-Xz?KAsqU&&{C%{|*k>RJ1l'
    'XM0UNYd!C5pJ`{UXPxa)=<F}&tj(0OgNFSrHX2+=b*QEejSMDV=A6#t=<w?NQVU&!dH$=MCxdsj*5|wK'
    '+Zr$4qee;^R~?y4DNMHa)|4>Njc@ZE?N3zXl99Q%#<R!inB4ZK;(9Qf>*%GiK25h;1*sNoxy(jww;PqN'
    'X#%BDra0I-_tqGs75=z`J<Pf`ZAhp62&aQA5gi*(j#?KPxyrYhGleucV0I&hvOk*xqo#=hTg%@P#t3me'
    'n@K0KToOcH$n02%AoO`iY0RyFMy}0W%VIY110G8o3(pG9B@KL0SAK2Oz=h!h*Rn%9q&%P&x1|gMFK`&O'
    'tUyGT9r-RNBqmWPCCB==K^U`$3mU|+M`i7a>}-K&Nc?N7WX7h0$^47Mi)YWS?j_qdU5sou>I+pFwU5lD'
    'Dy4271Q|<`&l}<<7kH2?P=8yt0!@t9lt-|$>asiOai-ns>O;G+Vl2>(hFAL|+Rf$i3>pAGxD}8y1r{Sl'
    '*p1*Tlo~b#T4RcoC$_HOP(N_=(X7M_cYkQi-dS<|hxw#6RsFkv{`8??F|uPAgLwWiLo--uTbpNTY#zge'
    '$RPR5Mo#9$VD*<JYjnHap9wKh`Tx2zbkgP8q=F!vOptJ9nNUZEju#_NrtehBk4YV{yxc@XALAZ_TXHRo'
    'R?1#tZ$5o@za4Rv1X5a~FzgbsNnqyJBEDy0GVh$ufU;00>b)m3qbm~#w5^R$Av%+gGvPk46b{wokB-cn'
    'EDG?-Nm3Tfy}SjJcuQMahD^on7#yd&JBLtP2v^vGFz`|Wa7U~-LKjBbQaGXQ^1$|4NFowBf(f64*Am5E'
    'K!g<u&t<j&)wIi@vSR8pKeV0L^BhhB?6j_(Dhf^%a~vrx9>ks<d4BBBD6o8R^c+F05LRUi!_(X8W|{Ux'
    'wnk;}F3HK;=>RrZTjI$_x$9@CX|uB5*FxeeTV@}#UQyzM)64Vzwz(Xcahl4yQhV951JmN+N9yP7_I}zQ'
    'Xg~hd9Xe+}6jdMtw)<uU(&0xY9x6!((1{;DyEuP-`uL*1Oa@-%qISLjHCMjRQK3@g%%O}6CL=H4k>doM'
    'S}~6UE<+};p)@0ug^uHRG2uM$h;4h^i$ceC0+;f*x&+%$e8P_`;d>$FzRyEqap?$YxsIf69K<mZG_a#E'
    'v~0!#%Olk1jzvM^IkAlG(6?$#VW)Cyy+veae_bLwdu$ZhDb*{|&_GRFP8RCO7MdP*_R;sSv#s@^8PF{?'
    'Q0%nWL$T9#8^uoBofJFmG$!tBW*HR9yw?Ku;c`A5jIPa9qsa>du$I7hgEhU-<GlJ9`8k89kCLp4HX(7v'
    'OEw`aG%M^V5|JH(CoO4Y+adEg3xe2kY;a^F<~csId@GIvYKb6pLPA`}r<Ns1ASk%F6$xRpLubH==gN>r'
    '5fKg{w(ruwakyl{_IZq#Z#kG9;Ouitg838J(zjt;4pT;}r|S4y4T_)Yp1^`99f9AFsm?nx*r2<3lUBWr'
    '&9#AEU(IAXcmocXTGcJstwXa5f`vRmsOA=cB%c-+*bnkgvMrkp?!+ag3*<InCWh)-&*O(?R;C4l!6xG9'
    'l^pJy_{}t1{{d;{$jFfI&Gv!^T9YTMtppXj`sH&Y6ILTE>wtW*<l4`*pfQtibg-JWT8;RAesXJ8;^0?*'
    '#hNg0#kq&dMJGcQX1{NgMo-wyc)-N$L=L92`Qh6eF@+Hf6M&)MPgc}F7m6RA0CuK;nc0ad&4LE+;U8Hi'
    'ZxB&tc;Sl`HJyxyTy4RL9FqAHGU>eE>$1!&=!4n4{c!Z<$-vO<PzBWB{IUu!-NY+k+tdg*P3PAOGUeJ7'
    'CvQ6igkwg(EIm9!a;+TwVV;MP;lywzfOC@L;O_tZH~+lbF-(*RY?$&1is{amUm7%W4#5Q&>q-@B7mhmw'
    'T%vEU9z`dphkl%_fGj}A9Q@DO_*Qhj8;G~2ssAZ?Gq_e(2q-P~x(y}rXgs}b1FkYSrD-E!FiT2f9HxTc'
    'sIAGH(y-qU3f2cl>k{Y9^mi}_Iw&^}--s!N9lkYdgCOW5#i*Cc^Z^PwJP{*8VJ1hN56A7HOnG^@<okwH'
    'xx!L+k~7(rfpwDP&~?qIfH@-PDY*q(t-CAi(lul=9R0Y-c01Z<Y&;R>k!}Lq9UFHdf%y(k7?~)?uDuN~'
    'B=|Nwioxvsb~1n0I%f$S<s;>*A2(Zpx;-cC=5T#$L5+3vkDbA&UFrN_F`th|hG;0~S?dLW@6!3O)B)|T'
    '1;4&-%{FR_2)<J@J|x4z_2^a^11Ce39C59!ncAl?`6HP2W8ZrTeeW;w-AdrQmALo*!`^L0kV^!Re>lXM'
    'P)TM&zk7@P?j`WsYTVbHpWm*VZ}8GlO4TcRR+{+oMhM_nZDAPUo^`VYm@|pPnFYU$?ioe25@Bfs;l5!y'
    'E(lE=cjj2O^k>3IPR&7~sjf!on#Ys!@>-pF>PISPqt%fTcg8r5$Ye5nhjES!8K}<=2i(YN{>aK|zg5WV'
    '!*PcV$5<Qly=iHTU^BrrGhqsYBH0X-d-v{jE^o+G@TA&kZ#){l>wNq8q@yWE-8Xxq{4t{lo^@X1MY@@o'
    'kSW@)^LG=N!<<a7#e8O{t~IFeTQZst*zCjzvVQu63`VC+7YNd3_iR3080iAEOLN^ft!&W>H>nL@Y%wO2'
    'XpR2<%B&NyRJR#l<<BplJ^j+?Fc~fRU_3VK2d#8sn%}t6HRduN4_0c$TzcSg4T<DG)S!>B_1<^m0bh#c'
    'LnEF;0@a)oy*p{iV8T(xTiiRp8KIu-e0FTughc)_Y?|!iFazVHK-W3!IAx2UiWwsl)S?DP+sb3BQ4ZA~'
    '4UC2Gk2-BQ?3zTEG18eqS3RLrbk&m|Ki7jU>C}wRz656;Jt@J$MAIM5At<GN0G|GsASfkZGx$lNCBPLg'
    '0A%$&`Aku+p$H0sGP)D{$dWr~FE`F`YTOTy8K)BC+Q^67YdYM)2cx@bFd5EpU~oUFaN9HCmI-jH<TVpC'
    'xIcO`l>XLU_S>%Hw~fR#1H-kJ`}Wa=#9K*xYbo!oDD7=!dbKkIer-!EGjU{PJ~wTzscHMjOxsgp+J5tA'
    '4h+V7H$F6k@^8kB3<tjwT#I0^xDQji{>U`OO`J&VJtu8jN?IFPWLvi+^@ff<MkZ)&7t-{vOxBk%r^-;`'
    '*xh+!89&j8!P!>Y*xs_n_K-AoXU<sdiUiy0i>-fsXg9yEMer?x);w`Ym@X*t-c;tVt|GEzv(`?Svk9DA'
    'j+%dGZVO=J*y-)3+XC$fsLsI&AIy{$f0zv<nz>Im8Vrw42*cJ813DNE=I?Yh895Ns-P_#~;y!eesDp8$'
    '1vx*RV|9-?844hu7NpmQALm`<lhM-azrs_1!|lwRWIcU^cTifO#}h23Ps!92HEL*&=i>HIRqner6jp#8'
    'W@N;~aH#h9l<5>(GqX-KaaXJ2WT37o=({qc@PCFcfdA<3yM8ctE1^{b@L>PY+k;$WT%uuU=3sPXTWW)H'
    '^^rNF?}v`V88rERcj9n{9Mbm8y&u}zYtz`<gROVau5>a%I)#Q_K@c%b2Kfl%y5=d-sF}CT$}6<cjGQPH'
    '8)(O!RJ|#?3RTaKF9qRuG6g=9)h*RkFE%8znZeWlOKcBOaKp|B_v!1P$k54!P;-IYB)2_#5Ac2`RX{kR'
    ';h^#Ede^#8wGoqVSFLN4#edta{9B^NbyB3)>`+5NX2LXj5(6M}{q!3g#`xs*1(W;jakn<ZuGBEbXa5o3'
    '*+`eLhkF|zjNWiaF4ebsBc9!;j$f<02S%aO;h4R?-+3@lJN;*wl{~<|{KVX~isuVD9L#P6PjdpnC7K_p'
    'G${i^Omd1StCkF3)!4G-$7YVG*S7jN-5(QID7I~JE4lpXHF)(sP3%sWXX->e0hfSRsDdHY_aAvG>|RyP'
    'm#rk(s-0CSIg6=CRJ78|X0CPp!55v;V0fHS%y{o%`tHm9;Ovm2O=e_+G@=x|<E%7a{+MvNnUdHC3f9Tn'
    'DVa<}k|sakM{PtZ_m%^_xg=9J2{dJC(eXfKhv)O8fdt#hlAfD20?no^lQ(2AL?=#PYz1^A9H^Pn;AnC&'
    'Vx93sj1G@l5mH&R0OPJpkzyoLhB!H1`8{UtEbWl1*;@>Iyn>JsU@crlFw0)~4ey*No6T@<tYnLHL-xlj'
    '*vBS&8l`kF9#3Iki0Y80p&O1vY>tzHH?K2RkqEPT^~pl-_(cML8RSSVix?O!iEOBE$4mPykpadLWzw17'
    '?aL=40gsqBc0jOC6RzuieR|oyI{m79WccQJ%hq6WOF<2Gm`Z#T_k;l_S-JXSyuqZD^QvM~-*k<+YzevE'
    'PZCq3HEn=5Bs<xz3h?V6|FJomUm_}}vzMbO!C^#w!lai58m?fqpp_~zbjG|z(ZQ%jw`sY8M8g@KeSrow'
    'wC@>8(h9S+c`pZO3-PI9HoAgB)ocj&KaAy?6(8CRH@qQj`Tr-2xr|Q4P#s{;&VRWe!<A^tI>C=0sz*%;'
    's^5VSK_Qw{tl-D0vR8K>(kOC^in|T3y|7B8A+J5T2A0{^;%XaaDibC)2j1FhB?N~^8R2F7{lrEUW#Nr}'
    'jWaU|N8_9&yz;Hq81F|PdN6XUsie5WJvS9*U(;ysv%3LwrO3-Hrq;5<f2?v;Pc!TGtcgA&j-b5LOL=el'
    'fV7i@aZMu(*lIAv^Pl&fqT$RAM)i5-*8Ta?RCU4C!D$BgPYf$Q9jH`t?|r6<O}eyWV}-tonnP`#d6-DR'
    '`#c4>tdrhKzWhw%4EX4eEYl(W<;>q_N|WWUwH*Df=RF#)Vw<-t&PQOl7%yV`k$1w-HAoBQ-cDPIZAqw~'
    'GG`R<A2f5OpKD`bq%i4{v<|cW^8G{ynPZPzy}dh99?T^?9Q}Tl0L$74#+!~z+USmhUmJJ!GJ__`046ly'
    '@xE@*-HgF3_;i8JR0MN%Y3>iQ6+O~3kGpTZ<@K2&sTMB1oy=6{n894!nr@Sl`Zh~T6J4q$pASZ@>Hee{'
    'j#(>%6}G9$SkdOU1|wEvbPcw;Y%}8nx21pF=^NUT3<WG*=~j^Q5Eu*;zo~0-?aup0>KC=v<)eTjTlbGX'
    'V&CFZ)5A)5|LA%iZd=Il4~Mo-9S_^@c=)N)VRK^s)amd}W9WCF)8U%8^HKFWT$_8V-455r`qb~RG%bG='
    '{SJ-Pc5SWR!`(fV%@mJor{u$4Yd(}M`e0%tT{vQQ)rbGTy=U!CV>$A>e#NY_XMq?YK!}GNC97-Wdv#)4'
    'S|sPCD02p;k!B48VZgTH)qmfr>c@1?1CVczY&pvAxkfNkU0q#W@9MTOPTa9k=&=v?IQPNAL3M>6j#B7e'
    '`GHSIu@5_W*oyTL)@{K8NcH&7aj_2F6c3L?n-+O|(vvcMQl>wUGJQH}>`9kC>C$haORw(kb_V^k<CB4V'
    'Ht4(Or|$<Z`|jZM&*#8qUrNXG`JR~h#m#JWeY1SU#&oIZER6b;bF4+5g7FgM#JgF@K-%c<WY!0$7o<LR'
    'qZ_Yz&_+?y=yqAR(djnXc-U<;I->)B)Nc3c&BmzN?2cN^gHipU-s`o8b=K}QJD#`SJQ&vN%xkk@tI@ru'
    'xZ^TTAAeZ)TJ8F1)IMOWHT2rOA!{D&_v*b?eGJGAhs^W+q2Fz`;CH{%@#_cs{@5QjyF>55yZ87vtMEev'
    '179X@aVb6vw%L`jr>Pz!5mrnlte8~TX5w2<hHZ6)yp3TjUPE7425&R{?bw6gkZ0^%Tw~eNFFF_aFv&nO'
    '0*&`}eqP$k3O?+O-swzP0e5@bziZ~<Z}&DkZVS2R`(ZEowp4gj$W`A~FF(QmJj`X^Yi|2a<%_M|GiUG6'
    'tp~pNyTF^j*IxZ?&&biP4=?QQZ|hs3uriT?um3LU{_o5Sz%3gIS*?v<in|if2Hd>s$qTq!{9!K_|MoXo'
    'TD)HThq}qKShC9sp2v6RU;%fG=Uy^ih(}@b#`1MbEDEO{<-Yp9x0Ss3Jh`;kW@7dF@-6N!w|i}}Q``mS'
    '4|jw4LtJ6L`3`eSH%vZU2S}lz@23`!?;-46bPvdy0P?pZ+*21w@m(O+<GxSbAWz*O`8xdv=myEU0se9H'
    'f@J!Ug>-^sxie3FAX`Y|$Iu7z>!IxJ?K$T+-h%lc)mMuV+nt4zTj%{r&EcHmc%konB!A2*fg|SwV{_2r'
    'b8mt6>+*IEIPl{yBO26-3ZHu6G8jd*N7E6XrMaxP#6R*o6d&mRL@N1<wIrU|Zxwc|6XiKxv96Kd*f<AP'
    'sg(lmR1}iG%t6!L27j6bz7or2TPIT@RLf`1<rXbjEI87<#RuPSmTw<P?z5_86B75AWz%Hc4zqH+90!`*'
    'VO6;;{+mT3Z;o2j!f3gBEFPsyKUx?I;TLk^pV$Q|MjBak)di=bt1do@+cFiO+VR;HIQ!(042x%+i;wmQ'
    'BzYfz%a4LUl7a2eM?w?8X)gd|`uBx)xU8iJ3WBn_5)V-&S1PVH&h`;?4__Hag>gmH!#!v@T*>ZnW)_R#'
    '3cT#MxKg<MN;p*j7Z<Ntxpeu#_{~!JTXEHI>x$n}g=;pBxh<;p?a_tA3n_dnsO~MR>@7CEiWvg`mseP3'
    'BV}d3Htj)6(;lKS?STr@9{+K{7Hu*j`J36un*{%2J{Q4YahIiCU$ISb8ySfQuSv@*Nh_j?EO$wyH&l6y'
    'o1m~&kmX-m)t9{s&w{W}*{SNrG(XXb!C6$<*n?G#JwVae#+orJr@5?q?ylJSx&px$2s(Amfu+h{e#V2^'
    'W`$*#^#abERPzthEienm!D9N<El`Yr((iQ81BrI}>B3;L`A&$;<t~VDck)Ix>r5-|7OzE1Z^E8cijZD+'
    '-)Ap!EmU6r1!e)t`I}i(Jw3u6lmhs%ww%o-LrXV305@`ICrdUh&nMo9O)Z5LV1-9sIAW6tt?}{5-W{7x'
    'Noe9{TosFfp4o!Fu0qPzC7W8z`@8FRy|dSqP^bY|dU)u?LC!KRE!}!)*p}R&jK8vH^nL3%oJEuG$BDyP'
    'a!89a_rA5YSERA`0JdJKSm|VgbutaTj3A;c26=>W-2yJ7vuWn#S$UZjnw5-Fwt-f4q<SN}3RTbdSAy`P'
    '-*fhK8m+!a-}p4zYWnzCOIO3MJGA*nIO8>WWV79&Cd`YNZSn{MKx;pJgTq)yo;R2jc#9f0!!BqT>)1cy'
    'o((yL2k6_lv)bX1bCtX0UYx|0?pC3T>&J7icDL77akd&xg6M|%vL+B*qGg53q$~_EHx!YsmMphw<ScpB'
    'PKr9Q)Hbh&&t2j|YWZawJpC&RyXEw3WyA$I0iH+&L(;$Bc`59Js+vC(Qe?}og2s}Z)q)8XO?uf*Ti1Ua'
    'IbkrVYKj^A9u~KMco>?MeYD9e-kDACs=72+AH^=Wb0l_&VAVb?@M3FGCLj2fA|jO!Rs)@$lC4ex&RJY^'
    '{6y8^W}P&!U@=wFOS?v(-LhrxqZdrjiQ|o}Kn}43`KGiu+ISU?oY|a(<w_w!N;eBI?y5wJl}H)Vq#FA@'
    'c6yf9$W^_I;Q?C^GyzsXD}vqaWiGf=Bb&|g4Nqc;7~M#662sQ+e6q&}v)KaH#iP4VICRT#i1auTynUS!'
    'M<VR%)we6Y;sXI+1vx~sh=tKaWP|>xD*H{y0PBRZ>CCV9<;6&_N9-FrAlMgT*FF2?_}slX{`pzOa_4!$'
    ')}ZK8pux&g;@jvG2Ab${^?U4KBIO*P*yP$iV@^LpZuj@X)F@0FV27lm->LwA{?~um<9S6WLuaeeNN`wD'
    'pMbP7&~OIvgkn`>DaV|n=wMW<%cN!?G@MoJGc>5Bb=NqFE6l?1Rs$48c&V7J&LC4YTcZ89v0QcW!Od{X'
    '3sRK-Ut2B5-5Q%v0z2yebLCB9(WE=UC$H#HTY~Bb2oYqGiDCuctICdhA7m7{K*e2z*PeMwq$RIiw1H{s'
    'ntj@aos$WL&4FE8g@oXcC?Pi6KTK?tI14-aInC@89L)?%IQFd)8}GXhJy_{#+EU!%n%fGqCp6j@eKmlu'
    'h`sDmDp4K&y~<IJrtbD6M4uH$aJ<n=`C>ak>WDC|ZGyqJ3Kp3E`Ql^^XLqn6&u8YY&mU}^E*K|HHQ>Lu'
    'toV4KlH}eO?Gzh1wW_s)zOpWdO6NRm6yUv(0M$9^h1APOoMy0({<Cg7#IG>_q8&|UwzX7#^twmur`Vd7'
    'MLz_?#rh$(kNhSKeg<g<?!{aykynKJR5?SyziH)+Yg}Vt<zQ09T4mi|J`_60-u9UC<y}+qV6Whz^6z;B'
    'm~JCjzjS0?#O*lvzf{kjHmE2Du%QX757j|;GXt~Wse#T`1T$`$`w#s@51I4W-1TPaGh(R%n%-&=-5e7v'
    '+0^zmDblx5mL|GXYM%#TVY**jhGW;t7-e2lrCHJTmj)wNUU&_*`nbr74_p?v>bRDcMB@PEN*6+$SFpiA'
    '@!M*XD;DqX)GsRRmXC}bS-5}nh<%HvOAqfw_eXc<VctZl-;QigHy##$<KfdyhrgbgpKdzbXbk-THytLt'
    'okw-oVFLF;Z#ztk^>p9i*1Y^E?mN7@y1UyM^v{k@2JYFQ@1DOuJ3Ad*fMWVmx?s^V+9Pf5fmpm@qYu&E'
    '625dtU@Be%U$~2zH+2{6Iski~lzeS|i>GmQ>*LmF$lBwf*Y?M4<~Q2)mdCt~-|@$Ovp)8F2OYoN>3MC|'
    'I;gkm4X@Sno5OB>bTDp=Jv<R?&G^@o+0dJ~5%^-G8x0#antf!8TY*Gl<a-CbZnxX;Sa;;N_nVzzmyP$E'
    '&Heq(xYHeZt-9YGw@1z1xCy9rhuzk&)vF)WeRj}mj5i<w8)O_z7>w%q?$`?^s|Efsoh_N``O|=kCIu?v'
    'Ua#I74*gckZ|)CAo;ULA%^|C|Tb<FkJsh?C&baO$^m?uRPQ&Yt>j&c|^Sx2G-5nnE*oaWULt3J}(PTAr'
    'N2_QFige-n;5VXUb(<QpTOR`Xdk4LCgN=a<%xkwjuij+!dbiQr2e>}WnsvJEy0_2v$DZG5vx8B6?A5(y'
    'v)9pvToMiV%EN47I5)Zh%f^i`D(>FE>dzF_y%9`rzttFxo89`p*Y3g;8$HI_oddr!9QOQrd)VD?`1|$x'
    'sNo&7{oc6I@p~Tg{qeAUz&21lZ~8feA2t}<XAS0!+RahhYj^6sZhODp048J2PGjG1Hx5P}uj_T2Y{Y;h'
    'zTfS&+8(QSS!;jPAZ(83^F3i4T-?l7*Eh>oY)tnT&BCZp;f-4KDHtztM1RyAj(j#6cUx`0+ibS|VZG<~'
    'U>kHstkdoS+YLvZX0zGqdA{Fnd5uQPZ*@D(Mzg&?^m`?>AK&zkU%O|=7r&gtb}Zimi>iTgW+YTRS%I;R'
    'U!A<`pP$1>gY&-o^7!R1efQ+upZfUMFYn*|5l6o)mxAehwpcp<8=(U<Ud*N-s^_<k_}XV|j(>}vu-1Th'
    'NB%xptYDvxZt(mGK+gbHssNG8rT<pXl&9Y3DEJpUY6y{8^4ZvN=iVY>K2PlcSI{LdhvESgXd-crKx>nk'
    '=STE}c)<Jz;l*%fv*pp?^z?$DRX6<3k=4eNQ!i&C2;<}bAwYf|tooUcv<~sS7b{n>$Uc32@&?!I?EQtl'
    'T2jc<YS3<~nY*dBL6FOZgN4K;@kz`DA&VlHqoWa?3?2GXI5f|4-zt}pkb6R~ELLG-zw7b{Vf-xa-Aaw*'
    'DpgmNE0r4EhQrE0m1jt|XQ^@T2^en)A!tC%9VBu-%EV`+ZpX8QLnlsF9e%PohA<ZlbPlY0d5f(i;E=^*'
    'z&YZ7*I3A>DSuF3sP}>~T^2N&t-wmAmnzs{+Bh@}f`u1E;Af%v-(M_di*o6G_#vEqLUhIS9AekSE=^m~'
    'F`9e8;yW=IyblV;TQEAxt8AcMbsGHHc@ScACEyDZ$@eCc@?!X`{D*1fA1_beT?~$2UbyGK95)Zz$ROp*'
    '`fktL9bbKEx9%#X{{+(&NxUOwH(_BJ;qhsKspj~>H85*gM*|<YtY1}~pN^5z<{*k_6@o#J4Bo$c*B^)n'
    '4tF-wX*8S8Cv3?SW9XDyFyKe{G+PK_#n(9PaCQPjy<nk?gdm)+&}2~W-Gi(0cDe;-TCjhvF!G$@s3Raf'
    '$Z1Ios-bkmWCY_lG$+UNDLefYOp{MDMJ2ff=ic&$bIGA(6a0!AFYaR&r6wM;7R^}@`~39%;HBES=a)Fv'
    ')g?b{7EB)xSg3SG<iQpY_6e9nu?r&NfORyN6e?8=lwobNN70cZ!T{3{54c2q#Id>-!72@~J#Ceq;@1rF'
    '@jr?SKT)IAlxpKoC~oD;!9LIFa87MXFW(Oa{dX4<zrpFB&uf_K0}-C4JpsKejlrTs(|PDE!I<X@9+j?Y'
    'c%B4J2p2|<l|CuB#B)}@<Wb_yJz!N>faR@}Ym3<@JS6zJMk111i(rOfKivb0QRigUB`<$Ih@5w`5L`wK'
    ';jN!V0tD6!9&YtYY6)oQ<Pyv#I`uUN?!HuC%~9Jc-ZqIZHVJ81XOEN6RL}Qc7CvCsnrwxjA`(zwCu2hk'
    'NyqtC-`Yr{gt{=1FTIpI*$*P_PwMhsnT1X`!$acG^<loL1!&a#eK!t1)69~xt?G!rS+z6M(oUg{e!*du'
    '9LJ}Ua6nYO4L+lk5?99w6r9+kObQ=Cz;$9HVXsyyNo0l2HBm*DJ=$Px#ryMD+7&QZTG_=025LFS3w=kJ'
    '6UxfexIVQexx@scGc*(-pDO$}ZMNidV{E+SDJz^*f};)VrmFF<&bcO@SXPD`G`;k4OKB@9t&arPaYet4'
    'rK8?aCQA9)tCRDWr=Y<8>i*Jya|Y<YK6&?Ze{eQ9d4~b0(lZbZ$FJU=oS&bZzB7J&?mR0!tE9~tQqWt&'
    '*66nl@U*SO=c0_Iw`gdD*NQKsxg_dRQjDQnNYXSCmQv$Bi!T>vyVaLiZCrk7LTq7_30a2@u)b9?4U5f&'
    '$Qm=Fc>5x@c|-PTgZ03d5uCjQN@=@+^z^r|8k7K(^h7Eizk1bwB`pOWVM<d^KD?DW*0`U@mapCOC!eX|'
    '6TAQmfjIU50uocWLSMrJYpop^Bh%CuZXpkV3g>6I2>ffdZoaVi99zjIoa$n^w&00;vTS0FJd-IOpPlXP'
    'FI^*C#k;_iMfZUB^7!KT&FRlcc=Brv-bPDLzM8P|G`Tol%>Knf?y3!%_ciHUks3?Lt*Q{In9p7K;JC%2'
    '>ps4fI{pP2T|kWank(e^q016}Q@VQLaM=sLaa2_R5I~0Blwu0_=;h&V<LWSent!;&M`Es`7moPz@c0XH'
    'lDauC|E^@nIr$uD*l0cpMyzCprPP^(`misY2oL`-q0?6-`fWB({xq9w!{+k@AMKJr9pYP8oIx~L;(|hb'
    'hYvxw`=D+nL9{eHcykgu*tFP<N1){>T~*92YXAhQt*AW2L|>;7AP(e>7m`+wI?zylWYR)H-FCie7tox!'
    'EQ^*4E*MP;m@AE`mydYKBMPxheu^cP{`1yU8<Y9MCcfBNNCLja@&$jy#J0SoH?L^n@k@HKvTpwLg5%Go'
    'UZBT9b!eC$4XNH-|5i*(-*PnC-F9+Ivq6-klF0EKTQI`I^zSdN$S?<sE0}uMdOZ8S27JCdw#nXJ7xTTR'
    'UzX_-Bz*WYVdR3K$E(Y6HCaRi1BlKNs43zSDm;k!4t~%FaiE}QI9p8l%^^v9eJc+`pbwvh;8Se4<!Up?'
    '-z6XTJpfHaQxieMcmma=iUz}}YB+YvjOWz$0R$L9p*L}1lfkr?I_rq^(9nxmyH$1mH3^1%ui|+Sc%E?S'
    '@8NG8P~ZKZPXXV->G50l_2Bex{ddw*{;B`-$vaudF!97&>)+|WdnMn9R%38!@SSIW4?!TgF77$kC6VO1'
    'xOrW-boloWA6|vQ5))oE{F>4}JJ~KBp|3Gu{0m|zTs@Q5gyFjftN|ttMZ7rKr1v1H=S;oD2Uwd@B{}$|'
    'n)5~f?b#dn!##cd`n-Q}cvT}c6MYJnHxfCC7w|Rzo{0BcP^6MX4`lNioMtKzAl?_)NtK+3nON*Fh|nIv'
    'txGZVUHT|6$=pJhhXndcA)F-~<CnyiKR&wvmqj7-Ga|A+dM8txa>ldOG75Yq_Pv_F=>}tsqCk@q;5p5Q'
    '6aG+4m(P*-;Yv)=r?W-jn;Hc=%Lu1Z!~dov96hXYSOCleV}&48=qCyfA*5qqtLu<2w|WtUA-6v?7^ZGc'
    '!;^0)(AX-)0cSiS&Qd6eoi~7OdJcy41xj484gdD$<R=%?YTbjx-F>CLWVD#;SHPV^Sb&g$O$EQgkG{9`'
    '0Fy}EI4!8pRiZB_DV}v1XtQ`Knzbycs?AtHsG{M5IzAs8i3#R`2_1ohw9!$Zk=mJJLtj+pg042~9td3|'
    'hN_sj#E%L6PH+?y;VAU9gf?k@fwoCXu<S-&I15SZs|_q+;f6K$vY0{q&XJJDpnkSoO^ls^fTcG|wf~)g'
    'uv9qlq5}L4B;7*J|1vlXo_FhDUp=Slia2mac2GdMOlm5sSBZ@!-KtKvUa8PX6+R^HsFY;nRyN;xR}|Zp'
    ')2k+P3@o+S#Aej#YT8G-R@7}J_#F6H(xfz>D7}ak;B2<63WHr}!rwR-Xio^Aat=Q3E{&_OfFCi+&1*51'
    'H<Vad1|eD>+(eh6N`Mo~%DmByvka!J1~$G5Dq=<Xo-oz+G?NwRu$V6b9(MFsV7WQLvZh&i<ukD33IB?-'
    '=NOXIOy(q{wibXp+GHB+WcweQVS6lQETwd8fBC_949byHNiC(IYBr~*R#Pmas%p8$wL}#O!avK1kwg{M'
    'BU{iVJJF(f6JBD1Ni_swcBP5D*kIqlc!*zBp?Tha!%M>wc{oV`Eb+lgBvDLF$t7BPKJRDGo(+&A!Gc!^'
    '3sUgoj9@(&WximaO;lZh7v36<2xf3<0E^EAz+>D-ahX9c`U>f*=dVoUDfWhlmfi#(nL<eMxWOP8Kbi!<'
    'lk~D6CZ35AJAypRu`bmlk<#*1NqUl6`aELurB);Y>d9gFAz4QPDw{3nd=9E5LGPKK13Aap8vn3UFhjFj'
    '=RZ|5EK^BSL7TbqZ<FN^^!xpbZH}^vZIT9>iGy6#A-kQSHMEQzt)@aOeLkYFm1Bhi!z)zNbv#LiN+|q9'
    'Hq#i*@YQ2J)fM!fzrui*mp@Pfb;*2rTN#Hr0h7D`7MwPrue0d+22j?PHb<a}UCtR_AT$L%F`-o4dQ>Et'
    'wo;88sPG{svt<sKXXo{@d0hvo^E!doENS}tYoZ0xj7ZZ^*Q*FVD=fg#(;@@8bHk8;L{i2CoHft?4j07q'
    '@z;AvSyR=fmsYx&L63CANHT~KEy$3RXbLgRG~#_#JVtrrfyaca!)-JwSf+$pgb^UHh8AEFd6;J0Mf_GM'
    'rf?Hi1wbDVUQ9u3ljQ^~H2XxCVWEw)6hXS0c=japLDGdjC13gQJWWH=7T#H6t1BorSXeNjZzi&QnfV|i'
    '5mSt`QR!AxTa$$pffSy95>hY~h@66=0ovg@ZdWGuwMA__44kgFAtCF1(!;q3KF-9Uk$SW-zbn^1qw2?~'
    'j1uX>WNPkEj*|#X;kVV))9FIC47SHt69H2}Y!RiDxs9BB^iEtijMC`~4tBU^o<{Ce#-nJ}@76Gh@nC+O'
    'TFgnH!{?uh1}Ef`Fp4M48z)na5{_ZVUTHFZlYuJ%C|z*1rGgNVXxA{l%h~u;veUX7680$?CRi$e1!)AG'
    'tFo7DyJYdErChUNa@G}|i4E|aTykQr8eQYGX*H`pBK3&&XF6$6l?)(F%&Ii0R6Sc_nKO$$w%USbrCB<w'
    '%3oD+>x<Jk{`ac?=Hj@zO$%Jc%cp}^{XsR}2?>K%c~P;e<1U&;SBK$D3A(xb|1qhR>wOu4`qX@LXr&Wi'
    '(A;Y3#tUM)@F_Xbq`Mq}H495F*p<-!EyrB6za*VzGo+C3+VS@iWKq6z+FKOfwF&?H<#CRirdj(FbRES!'
    '(!O?P&9^Ls5a8o#frQkRP-RZZ^xzdYNjN|K^`d_sSCQ@PD6<OJ7p!Q~J$Lcfyi-*Bc1dy~`MB)BlU1ZS'
    '(8SmLaqJL--|I5LBeII}p)xthRp$e{t&-P*$K6-4dJLoZss<H)rkVtNIF^1W4w32c+e>)l>P4L8$KNhX'
    'xPV%|US+$#P<9zs60d~+2%f}DWb7-ILzxPnCj=-7Zp1>IE5E>2&~oXwCCZP_YeD4V^vjjIo&0?Gm$`yJ'
    '6d=J4r@4vAOCf)!@j+H97AKvqpyRmlyjCzq6A+yw#H)6}(BSkIx38ozSLS3s64c%?$|Pt5AdDI&w_@Fe'
    'e^rHbmqI#T8_I#o`}$xD;cGAG+ZvZOwdn`2DutwtjxH7`$=GL@p*#CPe^$ivpB4Z;mJBk~EEk;`hH0VI'
    '^-fL+5r@C=pSztjeUkZUF8#<{jmnyU<=wtcK5K6gf1+GDe2WYc-A*S#_<`icFY#ik@>m2EEHTi^vjzC>'
    '5PT0uyeJl&?^n`s<_@NEGURO<5ESNY@)6@Bx}*bU&3J-_3c?gbp7JxE#l|KS%JDbxvj4_8#+Dt7M+8fa'
    'Uw3CAxIA*6+;^%vAx8SrzHdzfCu{o<CqM>XMnvJS3Dd&bH(<srZ*I8^CTtamr0iGW)_k2&rRh~Pe`-3!'
    'aK;f8<_OBE-Jf<A5JNA7?PV-^EI<T2WP)@4D}JkO?p9})*AQ@eY1^EWAya_S3a3ZO6;86cT*T-%lO>kB'
    'pjoE4DEIYX2>UzTcN6pB^)b@NM;yRC<IdT6#rZ$_HPxD2F-w_%^(H{No-@C>jfjjqpo~02Nf0fRtht<f'
    'Vo$>}tBBPMkg=^!o@5ZJsiy^A$|NV>GbU`7Yaj*u-qfh-Z}p7j&#LWAS8~a5x1ngZ^dX6Z)PTLoeR<fj'
    'tq%9%qeLZ|zO31!q)DS?bGGeGSw}sMfh)PoAQw!QpswrZN=D_xvfN|{>U3~JtId|u8FAOsVB&|(n{16g'
    'lxO5~*!PG+NY(9dqhw7irmA5+ujE-p*-UVE&njw#mMR%ec%SC)DeqeSY>*h?7?q8QhqWvWKAO%!RC6kO'
    '6CE=OV6sFx9oNi$G&zYxWpW-Z?6~4_cv}J{C#BV?##L=nSTb-)=8PvzL||1aEu(r74R_#t)K;8_45LJI'
    'hs4YmJX>@`FD6YA>2H{ZYRaWZJ)d$fO49G##lr`7#q+yyyR5+DaE;~XJU?<8X3$!gOqV!Y=_IJxUa2$K'
    '5?!)YM@AbA<5U6_N1RCGlm{<)!XsK@;PEh>fK>ji3E5!8w8^XMWvRVJ@~|xtO3m0sxna_TP@rw|`pxO-'
    ';QW#>*HdL&(#i%QP2%z>`oz06`@F^Z7eoxr=MnkRvY8F7I;ZF2!ynnL_;hhQXX4}gFu+;SUzOYptJbNX'
    'lU+3zP6}N~V<FVjOQ+8Q>(jFr-be(RV0N-k@}N~naFrHVirsvKC30vaNe|a}H7Rp?b9O!9e2~=uE=1{n'
    'R=_L4__p>LXNEDUJrS6y&4-`yW9d-s6M&$p(tCtofdw!6FR_I0?5Dr*%2T~pJv%OAyraT0=8*&%lfqMG'
    'NG4MzC4wqdC(}_A7B!%9mljmR&nTos>`X*s;1O>!yXJhN$%i7BF=gb&A^upc<ORx9l3MgLi3#M?r(`B?'
    '?yccWlF6;5G5&9><UG2`kfR}2d7xG5z+7pn0BHg%a}~JT(*I0FS=Vv<2fOx0%3F>=d$BpXxxpenQyh3F'
    'NMs@7G-#r*h6YDJ9t=9iTLGkSN%aCMRVt^1zLNCbYsR@RW(43!#fRifwP1i;IRR7$lNET#2s)&<ebT+o'
    ';a7?uq1VX^Omm+zLNVzB1Wc`z<X6Exgj}hTAUzm(yG$-93$AaLyIh4uw;>Q7=pJ{#d!cf-Fo+SdPZ}_>'
    'EB3CbR2riv9tLBC@JW@H@S#Y1UN2^=xy}-&6F+7qzzp1EAoz&E+?F#MdKIclY|dBMHA+XUk?Rb`aJKWW'
    'dHz{$KlRNH`o|Zi*ii77i}wR@ip)7OgZ8Riw>UNc#E_DWmx8O!th?c~&O&%APtOnp#H$;{MY8MCK!aA`'
    'NKIsL{AXSSz8x}IZ*i<r8R+b1b8*A2ER9MSn-$n*M+Pt;An{T?N!iPT;`$_9$7FIdq(fA{HgKYETdvR('
    'fm1DJmfV`z*ko#~g#5~j(7eqQ0c#>Nad$Rt4=Gviy+iI2YnWqK<mF^?tcw|TvL&nv0iwH`Hn5fa{T>YK'
    'r1lo!5uv~_!4OHMEp6#F3P0BNX|o1528ZYTZc`xbrJ)sKpCuxiQHos@;24gvAh2lVD;s%|3`UVneT3Cr'
    '4nf4(pd!NXjV(dJ)W4jZU+^BD^NTI=r%4@)Q%V|!8>@$M$L8W_vw4{-nNtwa(9E6b&dzA!MUnGTY_|dI'
    'Hc^B6dNP|W<gtiRSv85_d5JH*NV$fv%6wHtOxumH(+p3jbf;LL?}E;8r#wd@%ujd0D7nwIhA2Q5^ekg)'
    'Nt3;zm2MU#4pzBOHeilt&*B-5Dw!{X3dV6d*<LL_S&RzIOX4Rz+o1)Sr4BzngT44Cbj|2^(&x^lo}Irk'
    '^@_+sYC+@|PUL;02ovQN^%=czrflg6?xJ7O0xFxLosQM_ND998CJ~RfCp1)AAsAkSj+~L)<o~@S1hG!@'
    'A5MdsTlg1^!>hDfn?<!1@&Ta%LNGci%SizCu17o)MpZ}ub}GKDq~U4P<Co5Bbih}U^Gsm)&Hdp_*CUpK'
    'hn*BU&;e?WsGQPAu`W@%sghx9Y|pnF5QxXi9px+dUNks*lgT!0L+nv3YYe^7ht*te3#0|Lyz*5g-Spfk'
    ')l9QONF|J}4wDvHY8UYVlpjz@?PA!eG$Ma+i{16_%Q0fLB*hR|B{v<ez=F0iG!B(1yIet#mRT@aCGAFZ'
    '0{3Kwr}&0ouLC2_VUn(_Pjcr$n4@ZzU>*J%ZDSs~yP+^t>JX91A(T;<l!@uUR9&dDL6z%YEj`MeiGiL|'
    'J9#O2289kWy^Lm&K0(~JNI&z(xX)y(cK%d%|Mq46nWRX}U_FW|tE06DXg?;#$!URkvE|V{MyaqEmt$)V'
    'BcmHCfuSWrQ(aq<vvPa06eY4+fz<rPn3arE^<tDL{hH+DLqYMXleIAp<!sc?`eBD+8cFYws@~A@*Ct{-'
    '!V7FYpNoq)hR3nI#BZ-;!G?A`5bpp$_z5|qB;XuZt~TTM*Pc;KpcLa!s?w+#qLAbdR*<2<sJ*357j!Ml'
    'CG+HPE~i3vO@%NeEE>aaYAzML;GqoU38$n*Ms)%kl~KfDos3)n6BeM3Pn9b14}Jiqw!5|TH?<GYnZrpH'
    'sOl@6l+4MLBp9DEEI>6ZK8b5R&KtSp?c&$M9}t#<DWbo^_80lZI3)g6+AC!($`VYTX3WdJuK|!zA0=?q'
    'YZk;;Yf3q*>%4zWtKvBwdO{$(P*Cb4H*QUD)PV_7=--EmmyIj60Bb0ck6M+ZAHN%iPgL+qkCw(RluB}E'
    'utv%#6Az~>SE*t%WJhZM4A?dMT-HstEox-bvgPZXQE6V~O~kZ0c<un!`BHTmB#LoThuBu7c3M~dPZFWR'
    'D{uwn5>79s?}aKv9M&96m!`~boZ}Hj`T%vAbHMz7%n9K)M*c{zjlz&dZL=qsLwv$DgS+cjvW%gUKGf@L'
    'jBe+C2qc6rMcn1Nydv|8a#c1k&>h?hkT{=iX1Lj~jgBbu)x!40I-5OF@nIe(kdul{93q-5Dw4G$UsXl4'
    'PMYI^pw;Zt71PI}Ynub#djU4}C-ZB8X#DC2c1z|ImJZ<#6iovm9;%6Ht?)W3U5Rc2{cNKW+7W{pcs2vH'
    '>uzf$Ef1BN4Aw{CNHCR-x#Pun_#;1%&K#MF)$`$oRLB;ew7!m#%9_dTONj|>HkVY^Pb@pg2Edw)%r{TM'
    'vR=PdbrLUTz4LB{uj#0#UrYL;BDsOFWf^Egvxi4I(VU^uUj93!J65RKe!YD|;$({sibO^Q@z_NqcT1G^'
    'Sjra<6H%3j$$-3igt{Jhg7}C(v4>VCY|U1uq<$0K6TiMDSLu2=s0@<|Ew^>EMh;}Nd&5H2Z(J<6jW!qH'
    'b7LlyNQ~($PU_kPztxL?+W2!#G91{D3LKvt@}O#s&LG3qMvT_@abJ4{QOlj4I3P$<-*jUm@91!@SKdN9'
    'pK$1fPIMb#Qx%?Qh436A1dD2$V&I%9^)Pr+amr+}JBF2Zg(Z5!cm+3`2ce85ao@+~oyM+tOh7?FrT93C'
    '^+BanH0W2H#$YkfbKd|D+AzG7JRPb@(<CviP0=3#JUiqg3p`^==b!6fXT%}`OxmF!Uw>+~ba6RF$jVzE'
    'qk6#j)cV*IO<x6{jQbhn0%!8Ag<#f(K$h(w)>j9x@`G1-((fw+S7y*ktjt#ht=8$PWX`0t@sPBfc;3c9'
    'SN>_LI~j+m?)*P}VD9V'
)
# CATEGORY_ROAM_FROZEN_SOURCE_END

if __name__ == '__main__':
    unittest.main()
