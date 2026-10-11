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
    'a<Z8FSFQoE>Yy1@*ng(*RQ;4>SUC)Z;a>^)1!Qrz)tM}8<<#Ieebl|9C*Pl(o#Bnqrzg+9JwAPTdh+}g'
    'D?isC^*qzksWZazTV&*E&WKuuYwLzK&^@hZ5eonHi0)zSIn5cGJ>4@0rVek~y<DxhSI6JKe1_)qi>FV|'
    'j&bxsUmt3Fk6)jj9zTC|e#_c1dp8u1*}J)V%wFB{F?%)Y$LwueKxXe26=e2qSwd!SlNvI6a*D|8t*;`p'
    'w^<pPy&LPu>}^m;X76^DWcF@fN@j0uEt$RTi^;5iHYscZN)F@-6GD0GAsHZ_h`=oFa9(&qoa|P8olkN7'
    'GjI2f|G}%%BQPRfzJ7%l^v+mhrPj2^RpGahL3EwyL(6n}j%ga6XW5=La0dpVSdy)$Q_Z#9{&3_Cut&j2'
    'AJGvp^`3@ByBxE%CRJ|Z*HY-uGmH`GIl5_Dqdo{d%`uJMU^p}_YH9Gn$aJ+)uWt`~!=W*>?NNV3b;Imq'
    'Nk9<5eL1sA!;ZPTw5_w>oIHI6qWSC<Zb?f5oXXe!5_`Q8JN)89aE5z)hFknH-QhgD{TS>wHLq4aF-i8='
    'xuQudZDpLC)HVmQREvqF#-s<4`KnA!uba7Z%pOZuo!Uf=0nWJ}+^TANm65nRfY5}0*lloq69WF{xXDE^'
    '0~C!*c9#Z-2di#<Y;(`IX~2zh2d?N1Ti!UgxCv=?*BHRg+aCidVth%@>`sc`Qz71<4Bx#7zYh|;EWjIt'
    'R8HOE$7fALOe1ZLLD{NjN@KH0nz0BYJvlgLLCzhZx@nfFTvxkkbECB!>}*bpw2EC68s4-W8Em_>*LH8N'
    'HEyllm9e%9TkTFvwVb7P{r38nVUfyk#GvPzqoFr4^r2~cu4nY%Pjlo9hP|F?5!dNkg8{XALu=?by4R<}'
    'fi=?X!O$9wT!Z$uuo#zu53b$UG|#aHTHiH1S2yTrXq&cX;vYKojG;L&`+9%iYSbLSYzM<3#h`>SgsEtB'
    'n>kd58l+LA#F0u(`)2cE#7RUA+kYXA=vsxof3gN;99hvHP~z~pdY;#EM`kzl@Twl>!X7_8JwE%62MW)|'
    'b$zDHLy|RRc?0d5^qQc&mSju%F74*Bl`LfYIigJ}z67II!C{OmZNu^A)p@@8q5MV2mo|+Fn+;@5h1TEX'
    'bfZ%B+k}kzuGu$x8qr6dK`h6#4A*gu!AS3G`p6pSmS^_ezGn6Mgs>K0hC_^z)pL72XIsIyr2mQI5YjVs'
    '2Q<CbBZHx7Ir@lF>{?>k_Q=%+_OPeBJxz0T(#MuMy5(XECfBnEeY*8Tnl%EN2>rCOEBk4}&76GT1TNW<'
    'FOXxgvb9t&$?5vpcSpIFkJ48n0y)VAVo}dpDi~IWsdxcd`6{bTC3#i*`9Juzye##nomS?=#2%S}&3z_a'
    '6c)nZ#W2~jv9D=uDDthL2AFV%JSf|GxgVjwUDz?ZH)a~OXm%)&o0rGC5y!ig#&;u(SIgq-+QK+*6D9Al'
    '%s<S0k$i^NT2~dZ(~vR1(->X%u_)7+E-oqD*eKw<dy+vG+t(b}ET8@p!WuUcLa$)Gf?p#Q7GnWb<baE&'
    'EKOo?LNADOl~zp5A+@QE%cG93R;0Qo*S;EpTUzoPoWon$oX;1O+(zP_E2kN*<>Ug(?G|57M@rH|X16vh'
    'DR(F+?@CVIjhJlg)cxLC+aiM1;NE4rMka_A>tK3Jt}S1oS(+sET`873(kr`EE4$PxE0jtz26&1;QC|5S'
    'y?UFJ)@slSz!$r1CSMz`yt<alrB7}cpI6?NYs>evOT?N-Hh6Fif|5FLIB^g2x8f`0SyH&>?Hm1VRwZif'
    '7q#3M^_`&|*3uv->9oCHxQq<w4+3mW+bWf7Zgq3@r!mU1|5<VH{)&s`85?)grlV3<Cgi{aCI@)<BdL-z'
    'mb=2rds!{ERZX}JJCpB?6URN4?z<E21xQ%ih~4@=EcLiOkcs#G6wIcT&E6i~An&D$rKZ#!uKO_Gs6E9)'
    'x1v{j+N%ARtse`W+M8Qzqw1_tZFUcoS>xjBj#SysG}$^uCf8MwY^ME8dHn44H)-oken0n{<8M!%H;`G8'
    'HiDSVDb^oIgA8%ni>r|&i=~<>QbDklI15<Gl+Mr7ViMV9ch+MCzSO|d8py(C>q&k4ayTg4sa+7_@$)B='
    '1ITjK!j8D-ZkXq%l^r2!S5VfxSw0?Fzqn>2wS^Thf)JI48lsA(B<dXr)Q05goru$Q()9Z6_4VH4)8ixf'
    '<oxN$KX~=}^jM_8Vj(Y9b0xXfd$fozL#&YUy&ur3+B-{MWVe8qs-(b}uLD0W-Wg_J#hN{=rc30PFAU$R'
    't_eR3pZo3wT~(N8X|CVBdiAml@HT~Fwl20(;}&&C6jFJ4#FL0b)o=;LRIu0Pt*<;)J+xWIbp8D3jEYZ>'
    'e#7guvU2x_HFqc-_Usjo`Q7oem!g*d4t)#sqyr^vi1+g=2igQ>d-<M_>le9k38uY#|H#Tot?oy($BF}P'
    'i1x~oNPB{aU!5Kw<KumE==3d*IwOnF!N|1T9yK%|6MX<X-tXxaG4&BO(g!PAKlVnNK?bG`j}fnD^#+DV'
    'jlOQ%J$qp5#PD>N3=PvJmZ3ZFEzfXzwr5gL*R+A{x#`#mwzHviqFL6+CWFC19}t_;zGjaI9a@glb2V>3'
    'oE{nUEt8Baosgc<b9K|RT+8e`J!{a<hE8fkXG0IYe&2BWr04ZaG8{Pii1aMYF?E1B91KRTXPc%8eA4%N'
    'c2DbBjyve}`=h>XdfsT%PlrzSGaH)py}sj`-f&=Po~>)9)+e^r^K7CMNAFvjMjUDmh~^Ak7b_$gIyFWV'
    'E4^tBz*<7c>5Jb~S3a+e9~30z%L_xxA{H#SH*#TGt_NG^=#=V1%_fFMEu&|REYE=5q&=59WawxEYcPP#'
    'r=Dhv*agb!iwMkyNxRcdL+4#u)f|HbtM&03AA;S|PVy<Tl6`4!YSHjFdSkrZZhUkEFtXWBx?**CO5z&J'
    'pWmmMQ3vM57l_p*7O_83@!fO81D`3@IcL|S`5~^zTuUG=r}AW8)wZ}?y;K>P+<$U%_V~pQ#~^uy5HHm>'
    '{LAteezm$v$(pI&ep6)bNin>%S*YkH5<3UO8^dJrxxI*zI)T#}t5TgbI8A;LUH)#mSC}S?A8vAGjD0(W'
    'kX!@cQDpb<oOuYmrE@w{Ui2Y-<^}*Pp*R^YAJ<L?NMhI(@$IUx_A1uchW4A;g3NQ<$_LL{K6v>_h)T(;'
    'nXs^vS=-3UQA#W7Dy;+yt<^^dx1y}32}?R%t!8iL;XOGyJ$}rLOCjPi&A*EBTcA4!9@ZEf=+x_vhLoVf'
    ')C{U=Lw(d6+I`Togj&OaMtZd85!V{fzN2|WBL<k?Yf3rYC|DSRGnal_X~NJ9cJhq1>&o^$tGIh(5CJXF'
    'H4DLivI`U()beeIb$f8r^cmSMU1fM3%;|gZw5h8kJ+XMLUa?w6jjeSOXFIxRk}Pf#b#jQ}vy^YR^fj`r'
    'X*zF|%%xCyBj!!&YBMLhmPzw7<<%uk+ZlL^$s|t=ynP=wiOzzT)6iW^r~>w@LKg8QJjQ$8DE8Hju&{u)'
    'Lnad#H0iM#0NeY)1$^X3xq1>0!eDa6D}SrXbL_;*+W+#eA?no)Y_;+Qf9Xb!l#Td28K1BGCc9=g<h4uc'
    'T1i~ZaC$hk!FqPjmo|pg;is-RDA}Ch_xJaCk^N-obax*7N=c=f0EZR!v;7JfqLQy?5*miwf*IG@7HKEb'
    '^ycS{Ro#mh%9`+KWbTDro==WrHevZ}jyZNO4v<?1a=KXdO{~6S!n!40Nh7P(Y@R!S6X#{__MD%qthC(h'
    'U>m0YE*((8zUZtzD(k8-xjNvIQ=nfo0#dN!mlDN3h-}`pF2Wo|-g#^Tmd~s*c0P#JQD2;%e0%cz=-K({'
    '@zIl$=f`JfH@h0;BAhtb8clwiJ-C72W$nOc#OmU+4LE&w)FhFZR?yP*+v~K4i^y_KJ3Opu;8IyN$+0w#'
    '(w;@}7{@lLLFu4xYPx2QdWNlAefU&&!RMr|ruTGH_o!nJ9owM;$8zW<Rg;#^82aA88rfD)2MB%J!^%h2'
    'kc`aHz@)_P4{cp{dKPxSv5Dp4d5JSJHB;}K1A{o$a1)r7M-ceQ*X*ztsLOwkKi`wN;;}|GfWAE9{%S#M'
    '-9cRiOmL1*BbeNiq;F8te+Dm(y?NUd(5t5eI0_rnc^LkZ4hAIHViJ!FcsynAMUSKd1C_g=W95t`3dkQG'
    '4;au8Zwgl+Q2qCmQQ3Hz@Z_&2q7zmp<kx=S76IZr4Zyn$KSaC*RMZ#}h5QFj;$+Ye`v@>k`N@7`t6?hV'
    'P)VCoF-rIr`<ON+hS>1Cf;pR0JVkWRu;boXdHwq2Nlm&-MxW3)*`%|WcRb8G++kjk=yz3TQT1ku>$gJ}'
    'NHq$lR6(_@e5yAjzRsL^IGM;A4PQUNzB%vOWa3{0Q?P}`iaOza-nvROBM$sB#{Pt|;0bG~#A2VeO$lth'
    '!n)@BQL_8082EKS-ox0KUAEs*Juqq8szYXIvErX#!Orm%>MXvR(6$;;u$x^nzv^r~k87#u;pVF9M=v}N'
    '?N@MIF^Ve@Paz-pvqR2zj9z6@BfbzjPklOZ^C)81jxWIrp!5AMD*(UsotD<mxzUMT?>~fdx1-{4C+OlF'
    'En<*ZGe2h8kSrHLW$}iN+$G{mjTZLQkDn2nPH<y!r5!a4&e+>PU9U*=t_G2j4+Mtc<F-4>wQ?<g4cm^V'
    '62}1#*|+_PA77o|A+hiIbe`XFu{-;cQUA>%j=@v@R5p_0`GNwHCb%8r8ffSHnOg@Zwg{*;x{6{tJ;9Xq'
    '?TL3EC575kF|GIaAT7uQ8)bluia>s_J-*cyl43MuM-JLu_-DIu&sKY9F~KmW@W{5l9nmVfcZEUa?}s1#'
    '-~*FRXj5pB<3~2^M()_F+l5oN8=r1BF5Mk?SvNUZFFpixK34F)2m7@iE$q(GYDt-A1gg}Dv(=9kY`Gqz'
    '`M<rXnCf!G0=LLdo{W_j>>_z)Ku8%r%6w!g;}wpk$I3ThIFT}La!o<Xpx09Np6fcY!~qgEUiAY%Zm-^Y'
    '@lmIn?BAB~guBNE>DHb#f0Za8^(c?>?{^CuT5tA#^f(=>b8qMZ%@jP*V&2<wpjv$NxzdVK+Rv5yEQzS{'
    'dz^!nz1dZM$3xuQhQCWXkQ#!M8iCt!0ItFK+dT=twXS92Mt1P+E@N*JF;h44b{B!S);Hi50SC1&Xp9k-'
    'ViZof1{R~+4-U`%TEz1j4d~rbJWpacPjWPGH^IC+h~+gL%G)54cdKej>uS8_a3L0z-1t#l5oS|ky#2ht'
    'bv@fw0VVq^oywcTvcy^>hHzDHPNuXy^@H!Ie{oskB)~K~tEqPxMVOv+B{Lum3ht{4!wt46_3TeDMAioW'
    'sSz^HC^!h?42;~Jp_7Q>f|97)_966_^Y8+kg$ND1Jo|}}QB`vSARm9@yYc1rm;pb*Ls#LdvxyK(;WvUd'
    'aOhb$bj9Yg&pLGu9l82h)+0@=hWmQ}axUW2{HJ{Ef&5=wV8S1$_ej?0*XoS8%v_Pc?-J&ulG*GzdGB8^'
    'E9Mmn>pX38>D{S!{Igq?(TK)qRAKB`U)+hhXhd7A;9IGiEJ5|`O!Mqs@vKByvudXat+Q?^Q9x$k3~b*h'
    'q*XepRg)3helRYEFgub77+;C1OrWabjc$5^jAx6{_Fi%}Zf-caUfFeO1$>n-<S%|9i0trC3H-_S<RnGW'
    'FY7ufBT29rTJmPJvArP8$pnCtEAE811LO}$hS>cuzhV$%Z9faNvzUJ;6>Z|^w=KoGRl|UHd2EN?xD+Qt'
    'kmp?`iJJKVGTPQTVp$^mqcjlr)nPjNCm27esV^&s3>NpqkAPT!76AYzUaNU1TbHnJ<xl)eLzYrO>aL^a'
    '<6onF@y)`=plUJ4BNK0ula)~#Ck6KW=y*Dduh_7Xyaj2z-;yhrCCJeN<FmtTsa&7ui=%`o@`+bGm?>lU'
    'Jlid$b{)tvm>d!~bn=q&SU>RI8n)aLq%>}paI(2GUcQl)r77|q##l3h1RFrkMF!LU{V^Tz^)#Fx6YyIE'
    '(z^;ugCBoXvCjj_f=n073v8uF8>LgSR5u?e1=nipsD0igD@A++q|#}}zB37(ce{w{1LfQ+6H=0{++9RU'
    'Hg`!@&b#5Q)vT2r87HLPk-}AX!c@)kR0F1&6qR-N4q_ATfVT*oG#qrUu=Z2iE8&V;;T<fsBHhPe^HkBP'
    '<DsR3g(5+eFP+JQ{T=(TH2)$v3FKX}VcaNEg1j({gD|EN4}P1xICZfAvlESNS;s+l?S?gApv&a0D&|^>'
    '*S;y=4|$vM-<DwIxf8iCtzh7J_(1~eN@&n0^7Sr?*Pf8<!$8IJLK<C)lbIr~uFKz(remdNOx?WBdk_-g'
    '$B;SlmP{!dW#O7Kk6+diSriiyDVGB)v3Ls@T(*1RT@3ElN?pT2c%&cf+)9g6C39eP)$!-xA<Rg8Da{1k'
    'Hbr)ck8jB<vbIYOo5(kZc5V&HHinuPqN_|HIo?J?aS91u3?6{LPougyMK11ee=1yAP0nKf@Q3XSDQN0D'
    'F;ZdVYbm~jSW3z=nRP-Y6LDR8`*b*Vh#$nc%Ms<I4~kHwc@*$?;Cok~yDlaq!W?3kM$X)4w++Th`C0-4'
    '{+*A>P*NgoiPjNFMHK_2AuVK?oiso51B{=z82S!)#yx77+}{`$*%oFROi6Q99+SC?5XQKkt|G2;Y`;+}'
    'E}TdWcW&+d*(`L$?b*LV*#;Da2>2%VerKbAAoqRLAAe-K<GUSc&SEn$r)w!UW_KtZ<qOA~WaF|Im&r+Z'
    'Z%d$jB##YKG+|)O)#lB%;C3pO??@^)CzS6%CO0mU8<5D-Owgv~acztB;X~ylJ#hz?37pG$7=(*xf=4ZZ'
    'Gg&Z^ksQ(UQup=F5-IkprC0_-i9>}13S%066<MvXL(_Uhm}YXI6!QsIWSib;biWXCETmIaCO_p;vbOJ`'
    '+yd2gkX*oEitHdsz~p~O&W9?jF-eL6T68F{Op(CpC<JLx(qTiPrX{AW<x}%y9XJ$$6k(LfuV&(!Pa{@u'
    '=b(|A!O2UUw8EhIVlu39J!`y&5w;rkvl#SwG7_L=soqZkFgGpkg#&%D0NGt#Nr4eFT7%hMrN+*-V8!Jn'
    'QD9s`hQSV{eUrlePGr5rVkb-r=8_B2^CezXOGe<DQ|ed6<REnsdqWj`4Gfw`SafO9<`z1B(BWzMTLLbS'
    'X-)T~u#HRkO>D;ZWfx2Ox}57MC7W@bVm>H2rOYRlxV|QJb(N~-#h`?$mQ@)lucrB!x$(<lqo8ZI1T0@g'
    '?@mMST0u*U;OtaAS7_&2-k3}aJJoj5tZ596{Z9BCTp~AWO>z6cApwsWC`DY~VP$K?L+m^6D7sC|JG1G9'
    'AGAf8u)^J+`p}BL9z%+RC8QbzZw{>S0_%fvsmB7RAmACUFwQZHqc+E2T3oGsV`}T*f7xl3Ve`A8EKiXI'
    'n9+D)sJ{}HX|j0EvTTnf<&kmz+8FWMS9VFva6zKVvSgI7nv_gy*?$`;QsTONBh)k*w*kkuo3ynWC(x@j'
    'ZB1yBU1(IFAdWwMA<*U3B$BguOCCw6O|j8$=W|X&t{Hrg>Nm@=Z5l9bN|sG_g-#N^-Ie9kl5@C<l@nPx'
    'lEY%11Sx~3Mp@Yf=k^&EXGq}JKWr|WP!fzLDfY&W&5a6S{uM^ukR;h9&k0gw$_8DfB!|1Qu9TLwM@1=)'
    'd%_1r>X8=`C}RYR$3&Mry4MxVF;?>U*&6kEv^E*eXu=BHsS(y{BuY}(1gl`$9EWbgSyCuRx=!2~XTd(M'
    '5j0X@VrDQm8ewk~Axl{v#xb)b+5LR3a<+uF(n$S`FZ0w2!HLeuXV{JR^~qgyBK-P$ptB<fghkRJqueX_'
    'FP~%yIb(J!?^k0fm-Dio8DoV6SD6cQ%CA+_Z?9OEyJ=4!8KEZDT4iBReCK;nVh`K67vA_ToKnG}b?Y@E'
    'v@qZq^kb#nX7{vy2z|FBWihxHZhoKJ>25s9=VJlT+~3msfqv<`ED4OP&Rz|*_G-Sj*XGT=whS=H5#8JO'
    'Ho6nR&5?Q>y!YoJy9C$9%V7=;=*vrjhqHxJGwJ)az%`{Nn${9KRT9nWh&xab_o(sX)hXqwL4x7?xHM#Q'
    'lYR*v0x&4sgp(&Qb!;3a9~|G0odP?%q%>~01>~2`n42ljTFD0ux0BpaKgk_6l)Q_MlDlgux$B;i%<z)i'
    'lK4v})H|l3J7`NPwYXv99p;<tbhW!yS6_P9S3UNncYTAs>t)j^Ly4&W<2zySBA8rtvKz`Z+XtCuS1I0e'
    '-h?<3q~3#aVp++0-RP(`ao+KYNx5Q4YKRqg;;Xi%YQs*Q6C$N`iesZy?!+XxfIV@-Iq0EN;`)ndtmuPI'
    'M|K6(JmUFp`<+Za$*Y|zw>;>VPK@_gJALWIxK1;LGa3lR#BlT3_h8)nd=%1M=_6U!>36D)np8$R*F|Mj'
    'RNGtHWy89<a3YLSw*5$iMzI<C&+`UyM^-*_>efEZqN8ojJxQ0AZsDx6{(bOn=@@fd`Wxv7FULx)J^vGG'
    '<RibIN7D^Gn(ydw7cD&`_VoC3>(C>C^XhhsUsW(QljfI6YXMOu@)CFpO)CjS#dg>VZSUSHqNU95S@|5W'
    '>UdBZG>4y>1DNtjttvjk8{}J?V#%Of8cUls(_@d*sn?uby5c<QALm!!z%q7Za@@k==t}pA(pLiL8CM0h'
    '$w`dUEexDr5&yfv6@em6^W50>2yRiQWVXFeoL;o?g9ciV7G6AoJTJtyzSOatQqWzJV%1_S$tB<ZHi^6x'
    '^p&r3i4um9jpRE`D_`I-O7J3Dn@~;_32X^&Gs=<8+GVZMmA2*LB1V4t?L4G=b;C)jlh{C0shsE4C_OI|'
    'VJ+EMqTOX%EBp{d?V^=&-(+KD;uyb0xg~_f3|-5|70Gt(dq#6PZ(K6jZ7A)eNuxD{wi}A6*OK%zAeqmr'
    'F>S6Jb%`oiGwSmiol4g2mGsHy6X-v)nHS>-IQOKOxg?{FwJQ-rep<tol32e{9&NT8^TF!W?=7M7B<=&H'
    'd6JT?qbj1#H%5=;bbXdG{Uy!Ecc7hIgW*3Vc`0MO8PXM1zs91<;%D7kuPQrQWSOqKh@pzIk6R}>_<<jn'
    'HmD<i9V;&@ernXpdL(W1T%k)?$lC^XItdW6s-exI<rlwLX4M($@fuE-DA~{eV$uNS=Zcv`)HZ{f&zWW>'
    'Z2mF}UKKN@K1nK?z2ctOLA7DGZP-GTC|=G+uDy!J%tMJgx7J##zmX3gDz7f7G9wpMApypoV9(%R@avQq'
    'K5+dxb$HWsmPn}(#hnvx>l`Ay-^`1O&FSy3nTaZ631=Vt*umDNO0<}J!~t~#1|m#70`8nlFv}}CfT>3`'
    'j!_zK2{A<mf_V@26@o$50?4YA3S>(st_8Axq_itI>ygZWpu+6Ojxt{1e$-y&rp9pDs+D3KH+Kq`*xQ+_'
    '0-7O<1Z+EfP$DWHx+A3r^RAECB{_ggGer$~;ytGn^dvvSl2tnC-gOagA|a?)Qt`9OyO5f}BsGDlR{oNl'
    'wz2mj`LVq0%tx$TdHsyGQW2g{rRurucl4^pb+V;}2sq1W)ulccXrgwuzcnT2LgF*>`>P+mo%?Rv2`7sw'
    '%8xhr=SfVbZI!rWhROwR1^Cm&bgbw`ztefUeU;?2b-HdyONmZ87-ocos84o7YF2V`#YFBcK@{Nu7qQ&t'
    'I$(dM1XUxdo5@$zcMqD%s%DZQy=Eg9IZRxDwz0uRn~v+F0qc9FmtDw5aoI)n11x76UzIPfNNPxX4^9(y'
    'A$P09t_Va)Qk+{3@p2wsfT<sq8@Y-g)Bc)EN*B4BE-6c94@#)E%1*T_6qVfU&787ZtF$Di4SZEhSIJwH'
    'O`YbSSJ|q$d^VY7RPO_4?^cOR(&4*N;nFpDrH;CZ(xs>9wVftQ9Phv`X~-;Tz$)3qD7nG7*#3}lrA<=X'
    'A8fJ#V&g4~n`nW!%N~gLp<%JiE{OHpAZ`oyORM5LjO5&Tt74gr_6pZYn{2qZqh@az;@eVty%q4ZqNUdM'
    'cYgCt`bzs<YMaUyUc247bdk|W`?9;od4{JtC+qj2%h;0U-BBacno*=L4Xf|USX*tY$?FfdqOp~9@9rLT'
    '!T!>vy1|Ih=a9Lyn<k6bZ_!n5J%;UhSnegDM%c~)q-^3KpGTL(=nqit8rpC~b=U2CrtS=NQ`b$)AdW|e'
    '4)HWkAJV=)81-D&aNwQZNON7PS*EFt9QZ}IHj(#S%IARgOlM%({o$x*_o;0YgHmVcxt?PVhGb;xgMs0h'
    '_Q>>x0D9mKdal*)_lEsZ-*iWWxElezTm<hTfcB;w7GS%QHyg#y#Fz8%Lxh$7D^iiS)|NS#Q_&kC9lafs'
    'i?Q;3`R!NaBAL_HKy!;(8viu>AZ0y*vd=j+j+dJkEMs<Spv8*wOu@=n0@gP>D=p(Oy!SkG>FR}S4Hqy_'
    '99{BKjxa|Ge!e6ZbnSw=EY)$m{Yp-PczJhI!IPhdjI{+Yuzl4AbxX#|X-K9V(h>YEk;c;LKWE^wy}6Z5'
    'TQX{QD{byV*fb|=?n2Z^l{7`}L>`Q8BWG%?;!SoZNPu}OX%#yYm-40M-3ZHF$jaS{%GHwcR_8T^1Dop_'
    'dg9^3hsq0<E$aCnv4)EX4o1o)c~6xfRNO=!Dc~@W0}M_EA=Y4d4-Uij8iTSxZ?s@J72aYZ8kk0Ejm7ZB'
    'S_=Ib(;xy*W~nt;jnGZjQEN(q1(_gKoKn1rjIFO;1ECH~@WVCbT8@2)(TVR<NWf%OWcjG0e7gQ~v#$Y*'
    '>?_LA%M;dURt0*?P7byQd|ksHsS!@RBNl6b!y09<d!_JiqQUF>&08B2BRiHN_tI`|NQT_Lx%0|Qd*4&y'
    '@Er{>zRK>~f5q8Ty&xhgogIfJi`iQ8rC3-5WD&C}^0kO~sW&;sp85PGj9GVHb)OefZX2^*f>Nxs+iM#x'
    '_{t>C850a3avrH5$bloy#A!&IEm1`&(W&XZ-vOaZr}GBL{JxxTmS}u)eJep^SLxgO2n93iB={|-YcQc`'
    '#Ed9*_YqGNNT2{!%w}^?5@||`tPB@tF`t92mbUFxIj^CQ${><SqT~e|)J<_|(mL5rR@4M2xT~0?f(uRG'
    '__?NLl=?d!UD%o!Q6i0%pX;4_#)r-8ng&%(4eF_9ROPXlB)^=C#I3RNs+b0YB_>!`YL-E{wO0M4T+o2d'
    '*^w!h>fq4S+?&7nMe-(tj9=ovzz17{UCscIY3`KrGV+W0<)Nb2f^}Wfps2CQ+xHs0gFTkI#XH>LIx&*%'
    'pY*4*a2_i!?1;|a*Xl4|XBHUa!4SxUFqm9rw^FilA0VxiFraBQMA5c>>p)B{UqfZ}S5i>*7QsujV4Wg`'
    'a2@oJRcq<88yJ{Z=_R*UU_}>maJ=E0!Bx%VLaZQ8_{F*!HrdyL3J}3xe^3122r-h9zaNl^;!H>s)sNnn'
    '%f;2znn`3WSWFdG?_;bS|87BI!s}c*SOLU$u@d<tX&1n2JZ*0S)vYU5n0OS=7Y?u?ud4SQi7xrf>)R3n'
    '0H*G6TESW_FKjgQvpbkl!Q@nk)N!5ELg%+Pqz;b$E@A^^PZQ&>4p-I(v&^f7;)y6;%7JESr2!I}QVy4h'
    'N=%@0AXNIHlniP))6Qr~<WH9FR~!@xqW;|d=qNv+oK-9nRkoVt&;CqeE<#j_SV2L~*IyxMXPR$$A98`r'
    '<g)zH%O$qth|DsS%tn;~LCz+M`L!b&cQ&fWx;+EFdE3m4XWY!-)x{1K70nAdmnK-jDPAb=Wurjy)cr`_'
    'uvKI&ad=*iP0od){J42vRTR>ch!b8ITM9D1&UtGm7eR<xEP?fbl6MSXqW#--yo)8Xp~0Esq_Nq-nALRp'
    '%O64?jPvK{PyOnV6b@!aQT?-8m*PMeT7_vo5_Qk(^%AW&A@n<snG+Q<>;g_FzDHw!N|hKq%*banoz&wD'
    'CvJ^9eWI2p_GES@3zoBR^zfU9M{4~woF<h#m3NfRqFlAmh)n4NCaf|)y~ZtcFdXLd#Vi)*7!lY}SL|GB'
    'N>zE0qEcDSDl5DzC4iBN*sSP0x-T7B7wtrW3Z^B>71^a+m=BYSQVh}`{(y-Wo?5EJ`qiN%WTgOv9)W?y'
    'Z?bNbF6)tllCa=^CztECUKiIXd>A=%U)qgN#XG@R3m|Wr)UeB#EhFo2SycQk%<W#>;AfO3f^>;*b|7%f'
    'Q7j3@QsLs_8wUlN-+tHl0Qct1k5z;}PtK2pDVsaEkaa+vh0jViMy0f|=7AJ8o}i4wWJ!1sQYm@2FK-WO'
    'oR58{yNDY9SqKJ263eHqA4jYxIjDG0{s{u|bll}R30p5bpz()r{!UJ~yiAKLItEt}=e8ilu#e;sHs|Lq'
    'XCyJxPPeKQdaV|OX%9jPRef^YlAu{QvSR+SYL_n+FE4~rvfn%RMjTf47d=mEq>Yud%V^Eh`_`uhlvc6H'
    'w&<W7a+X1P$ltkhnRTR0nAAGLifU=0#pxo7ll}}z<{Zkf<Rr6B^jP_D>4T*N`<sTRB}y%4y`+*aaRd-G'
    '7lJRURJkHzHHisfci)(IEyK!UJm>y1+t+xl0|*8~`#iU*fUQykf(&Ohbt}X5as)~q{in@|xC7KA?eijA'
    'GAgp}Vn>tuvDM_iE#Td3rAP+&32kPf(nvD5>aELd!L|^kZ{1RoSXW8IDI(E+dl$J_LAJZvdz3^We0<i;'
    'Dc1!|N=o>V!~HRAMHK;dCiH<f!8)l*GyzwP=aFKj(*jYqHOep}_i`Qv;UZGdLz9qMo<+w})EuO7qNKXG'
    'RNTY3q8-H>b_|1>w#!ds`0l@z)+)iJ9_y}&AReh$#5TH2datI-?Z}F*tz?;uuxm7|U`tpkyL`wC;VIH<'
    'QZn>~GMgx*RU)I^l!?4?OE}?i4@+>t*5zMw?9)wRh|N^UUS1?ORhMc~MocgTiKm6O{d-#To-dit$(7=>'
    'Q>X08Z+hCKN?uechAtXTiXiQ*Ze*R0CTGe?xlKTgpfcu4v3oNznFzKtKR%wvVa2zIX&!Lm-utK<BG_zt'
    'p!ji(8q^|&7|;)j$E(b#a#8i^3!B&H2yRi!;s{waoh6+LNf<&LAc|d+=4D73Po`^8v~A8aGEFY2$n)kh'
    '`#&?Lr4xPO&^CV#ET{H->X9ZDTR&Bvjox7@=XF*y@@O{8N=81-8mq1=8`<mi%;C@)YMS0NHR|<714GjX'
    'y+O|yYL;d=eVb~w(X%Y75pQ7A;ZS#pHSG8Mx-qo$4ewAbRgQFrTE9OU*;e2199P#&YHD_GXn1x{bNjY4'
    '8rUOm=o!|)fd2=!N5Dj<t_d^JEW2-R3U_7k$nvYI@7}hT%UGbKx_edHw@7rba<JD;7}W7CDwTlb;m-KA'
    '$^3#a9Ve>Of2kUh*bCNS1#g7DVEBoWi^>f^!x!(e)83zw*%Me7JMoFtICRMs>x)<iCa-&v4cq49O5gJQ'
    'D{1MHwPC3P$u!rr8>>XwZg*)Kg8BTRk&WU*|GDl}g1BZDS6_S<=Zo>~Nr>0BQ}OAAVGRBU_Amn3elZUh'
    'fqNETO=ue|U@)~^GQVnIbq!DhF8HZWCvINGf`2w=1i9Z;Y8}Tgus=tU{RHn%W&^JwmTVfLdOv%p31TVp'
    'HC|y(!PR7HOoGh@ZSzq%KX-3CY;{SQW-N%^8W3{rhn<-Zt=njc`ntR!Ro>c#X4tV3ztzr2(cjIf?|ZmE'
    'G8FetP45PbgnMHnRGSDQ)^R_P#(M<cOT0-Rv2n}lJ{VRzwyV~eRoAz*tIDAnRzRR6gvLs{eHPEzEuZ8k'
    'E64rdR|@7r)VNBQqK{QYSbuR=DiC4H)hv%t7@46Ba8*%OUm&VJ9Cq=KQ*K55{%!$<bzoJXzgvmAt|X6y'
    ')raN8r5q~zAQ`X*+G#kUrMIJS9>2P((Zr6y1@eXQbXl{%J;&6Vy~yej1ot(Kz!5<Vtsy;WvBGm!1PG9K'
    'hUb@UBuJl3e!#=*vAF-xsqf$IUJUI*3N<E#mIi*tk4zdGS?ZKouH@q!(%Ws>TiUE--l1ULkzCFMTO~au'
    '^$NO`L{VpX>A>rWf}b)<TH;PMj}*mIOYa=knf<QS&TX|$ZS$AGnv#$HbTM54t&S2EK8FDCa_&16{+NL~'
    'z;~<ta}Dfx<<TP`xQ;A+o%lx$tS3G3Mt6jtdNWX|BotdCX)Vi1blD#Vg-^2<#C6~n2TSf9v)fXKoDJ%)'
    'OTuvmmK(7{7kDxXr&RgDrypcld(X*x|AJ+)0qHpJ*su~p_l>dG?l^2047MBox+C^#n7b-hmDn-a(vo)$'
    'YDT|{AQ)<jZyY4`6AFe+Jq(rxtBtPu@jvOJXsslYqVDrA5mBo+`P=V`9y;v8biI>c7OYGLu9x@MP^5bK'
    '1e8oB`yCZ*<u=%pkJKOxXhWF`Ps8~!aW31L?7?s;n-BOsHju!y<_2ggw)^I*;f6DrfL>6+Tx}%Tq=6yp'
    'jCYIRcuM`9MiR}wB>k-%ZnsH)cb0-DISr(F`7K?1uatvLOW?Z_z)i~Em1}zVQ28~bGi?1sKh7q;<Hs2I'
    'Va51K{lo{n<ummoyj7}r^Ki;;`rxe`3Ae7`wZCRrFR;x3f?Gtu7m>0rVJ#0Cqdw$yL9n7Aw$;19o3nl-'
    'Dm5#d4I0@j&<x^E5bF=a?g5v%u3Kl*zRF0Om5(5P5Vb#C(m8l*pA<%ktbIo|f$OHY9AE8KstaWAFKg!;'
    'WIVgC{Ordc+u5o*`<+f>i^5lt!*hU}0ek%!Bt+C0Zs&H}O=er-Oy9dao0s$O0z_DZ?q?o5;v&)hM)@Jh'
    'Dzm4W%2TSagzsnO(#FPhV^XDI_DT2L6YFYHzm-El%_*3~yw4WOVDIxPyEP5s(lR>BiJ7L^teV*sQE;Sv'
    'Ho9v`xQNJPjh=H^)D}&rv{&nWmsYGU!k?dz63e>hR?nB)47ZMo<n9z>fA;TutRHcO)=aeSKCwPB2F}p5'
    'byL#~%dv-^=?waW(4kJPp4N9g8-CcjXXqodKcc3s^)*em@p`Xm^*6asymXh?Af`L8Y}?kfp6h7?bI>1+'
    'oRO{rRL3CBfEt=T8c~CI7EZ()j%?Z+n#3DuL)|hqfmwNvxJGZdtjCmSz*9o<xbC?{F1IPGn2$h?Kh7wK'
    '&cLCfY<|rubnLjX&~{=@opA1A>RN75r|iwQtmwIPh!o4Gj1^Wz<&pH!C&_7=gbpck52sRzapug!$wby@'
    '_<BZufAs@9=4z9Pe-TVsB~x{hv|5N}#9`T3`k-_BBl#?Zy6tS6XQAdfD5Z#r|DHafQS1kz8nQ?=I||rJ'
    'l5DeDaCXV4jq+);Y`SuE*rMYA%aI-C3GG?(_V(4t<jV!AVxgW?xYhCaO-JLkYS9Mq>wvrmpBn3>@~F%l'
    '_EDuNH>;O?Pnk!tU!w%yRTR_d$&_5sv9iyrGOHiR<Q<IZ(#V<nvsxan@GaKO{yRU2>qJ&pUwJGz2gehN'
    '6wr1q{fRrLHI|gbz#EwI)>B&P2d%(-ZD**p!hilG7b)yuV=<kQvM@X2Z?=VAkh~W~)%h4}MAfhx<n8os'
    '#Y5B5p?Tr3W7$w&G)R^VyB7?r4nb0z1Uq59n9-or)n;oNy(Ce=94*<W;zoE!l2K8XO-sF(wuF(Pr#PbY'
    'NhdLy^7i8dnh+FCAf6#VMHuU2lkc~;6M~Y}X{OX@M!w*<mM=SPMnmF$y$$M@&Z+xy9!~wBPFsz;mwmX^'
    'Dqa_tEdS)~L0v2BZj7wk*jUoMFiB-<uhkiGSp`xFHs-Y&q<Pt|{22IW6)nm#%~dQj+V<UX+UuV2L41V)'
    'c??6erPYeRHNWlOqdpb_6`y33(`C#eT4u5^Qd06&W^@)`Sj;{L4<kNemj#Bg-)IVy71h74(E*rMxaRjV'
    'l4bFqcUw}niF1u76wLTZDKsm|{ga~&B*>+milr4&sT7~AY<Ri-*<q`$ge%TE431_qO0fM#&i-U?$prGm'
    'kH|6{H+feksK+c*wH<nm@5FgmIj_+KrM21t;O)&%JT_y#Aa}>!r5uiKU{hCm!^)Ta*wKDuqBS?swh#XD'
    'SowK|wV2E=Xk3HA_y97uv=FwLqWY&%n}g{pyWLRU_M-fuWH+cddRv~mbA6xaad%dFtNyH|+UUD8(F;Ao'
    'qJYez%MkCoXY9oK=HZ!qS;f`{S*OEQfl_YeSV)1G59(nH8ipT{HaSk_ljKouAFLGnF-~`;EX^cX)JhZX'
    'QcZ^1{>iN$#J<U|@ETNz_pW#rA8+hLCWvczZ!w!qe4r!Td?j+`lm@DDlJr#G5-tpbX^skW?#MjG?p`S0'
    'U<x4n!eHy0SgmDWF}0S*%JJ_OB*s&@uJRp;F7Y>MNj(^2eqsL>5SR(=+CxW9IHSL&S4r)rN3}<!v(UL5'
    'E3Z$2cwp8a&W|3a-J<JNQRCS%nbXfoklmOsB}3h?b%?MVYur=_#7WR*oIGIYGJUjV$unSMq;+zE#KMn0'
    '=I=#|Hu{kOL%e?V^ubWUo2r;tL${XBQ!;;t_N7Z_lkf_UWnpt%Y>^!<;CK59*jlZ<o`miJXURT1QrVko'
    'w$9p67%vn+uy<;Yn`ep~LFL}PLz4~D!~E!ocWC^5TITLkhI3J*`xn0`F61s0+u9&tnlM*W28fYgG0$l%'
    'OEYAWrFP%n!gwK9WmO999ykI>U2A6eNE(o=7bvqfQ5{I}3i2@C`{0L7sLXNO5e5-(@TJrQ2{eM^#)6DF'
    'IX~LHO^N?Z7q~DiACNX7FE~?c^!e5u<y%z*CxMCm;60i6cr8Z~2j?8lO@g|$VKRQiHiH7L1dE3CT$D22'
    'wM06r@=96tSS9l*CDK+`*@<~tE$NcmilC*%{$?Az{hi2GMw>ezPN{pJoV|R?iEWI097sz7;{sahtn-IP'
    'pJaFeFBj1zj*f<Z&SO_D!N!ev#gq3w{cwOh45pRhgX_H|RF>F9G0`*)_<{!jhGW3net$!pclAAik`6v-'
    'L~qvHQnr)jw8@nsL0TvtB^y(h+<upaX%HUbtl}_r1d6ch$d?LXmWZ%NYThqF=+YvWc`5mMiM4X}<ZkF{'
    'IeoHbOXpHYXWl!!#L0&xpj)qKRSI)?rNzI+A=Z{KIeAHHN}cN^&KXfy^KIc;u^)FX@{%LR^ODa|w2NvO'
    'Top9lv=C&3nTbE~n@kDFhg8`X76hIwL6-+`qrBS^<b4y9YjYZQMTHVvO;4z)uQpRt${+r)?aIC?5%i~m'
    'pL=I#VEGVCaf=Jn`y@}YvSa1MMP`4j2`wGSxkhl;R%=56*~+ZUS_$J7x2M57{cv_k=2T9eZo@?ynyoPL'
    '*_43T=%Tlwb!6U8Ez0iaVeC7YbmvX{VEZ-(t@JSG1t017Bbm-7RN@6!QBRHMB77<><0Og}v@J-8{pi+M'
    'N<0VBL2{RN$$%ZJi9%icY#ft9WM4a8aW_TsZST#h6AU|BZ$JZc#@91q)5&taSVZ1amzU&_RgqxZLH6x1'
    'e5YcU*otb4jr53Ji!ec}zYhb-j%yJ`>XecIb{MRHe}wOEy~pKJ(+DM5a*WCRMn|>7iNuROmHhZga)}7+'
    'D)t+8gLJ2B5nF|3V768K2X&9)y353Ifw__FfZOq}##Vwd>@-}&^z0o4KbqAE;0sAo={gMp78pb8Bx)Y4'
    'WE5W4yX@1XQF%8Ng?3O3No3HWGxTeECFdMJ@gVq^(lalb%9KdP2XPJ#G?;&5g=N#-lk|&uf=+=~kclcw'
    'rW5#33z>EG0zln764GBg5?A9a=5w&UPKAhCsxJ0O+>;d)y6t)n4->p8j}oJG%uYX~FXcGTtfko(rm-bh'
    '?l?3w`9f>dm2=-dIx6Jk^-rM!TJuivPJCkNF7bMg_^`l7+uz5!*{_!4A8+Cw9~Q-&<cm`>z2&=dmRrq~'
    'scFzvmf<Py-chdYCx5C{Y^+%~xj8R+*G}@C_{a^o$TvEwXN(ikO+KZw3Aqw(vIN_;t4MNt@5b5QQ9-F|'
    '*@agN1<oRLxj9o{M>{E@#prhn9FzpEN<fc)P!}^+-9GQ)^HM9HO?^;~rh0|1<d(r*TN&~tx(&|N9R+r?'
    'Mj^tN_;f!|wrOclE*HM%?f0aW4*uN&&-%jvuW!LVOh5oOTSB<7jK*pR@2()P=!e)uNnWMc;ET;5?b7wR'
    ')=3i=d3RDLZ7F)Yb^G&{<dSRAC8crOk6!Zh4~(4rJe@60y>v{v^}Lt*i5KbwBDAUl1|Y%f-Ite>L>l+G'
    'yj+q>w5#%RD~dp<o<EOb-UKv`FhaL2%rv&ETrZcbySJt1Bo+j3)^6Q}*}CKUtul;OnWfq9jmf&kVl4#O'
    'B?svmu4pgEY~7XBx&x#2?#m_DHd%LVvEF3?&DuuE8gup6bd{MZyZ&Xav|tXfs3o{O0a<`=Y36Qy1G98W'
    'qTJHz-8x<<!C1a4Tlt<BdE3BHJ}90tZ@Y_io1WndX&6m|Twxa(b!eoOgv0s0CzAzj*dNHd15zf=Zv|$k'
    '%~A<u->55)9>Z11pOHjv$y(%<s{0HPz3dQ{u`3TvcX*Yi)ZjLE)*eo0AvWDu+vv9MY8Lfe+v*J+L({#1'
    'H?jwP&9HSt*Lyw9wFf<SFtmEqHEr5=dp)XCTkD&;-nY$u?-p+EQo~!#(1$~Zc!uM+=FlayXL<w6>JN>f'
    'Yf#HD9BO()qc`$KBco5ep*yk+cchy`YFUP7-v)MN<J(&Ol!ecbT|_D+)Yfi&TOg9mf~m+ulLJETg`P_N'
    '6*26H+A}$Pwc|OMP-CSoEOFk<M(ZlG2?0wd2{@{=(2vw9nYDlX5q}TjPDkGA{*f>OZyWeo4gl3A${o;T'
    '^CX#4q^JyWMlUe4Ct~TYHT%dmPxZGV`XbTR1l&B$SCRbnHZ;HLw7zz?$dw_4$0T@9A}}<t6(9W=ca_Nh'
    'J*`m|eSN@%Razr4Zv9L6(e5+@25_jf{lKLkLFBPLMt{4uVq-MQsZyoEVoK-Wht)f%xG_A%+UA9k&u)bu'
    'Dv!T?iR)>9tgjguV$_eyU$8A#KlpBZ*;Rn+`3G0Y2ba{pxQsi^Ez$QBwpVEWYCwueAnG)HPup=QW0@Rz'
    'oh)3&01(%G<_8=`?mNva^SZtgY(gIFP8{q;8m#Wu#&zXmRuuP8nUarft+rw*$OB$)_kp4}w+P0U$r4IN'
    '0BW?l>-nTi{h*ykRX4%Z&$UiR`K6)*<vn^NA8(DItO+GhocnA}J^y1n+n0`HwXlU&NThmAz&lb3ccK$^'
    'trFy9a;~!xuf;iOw6HHJaq-qi2e1`{thl)Q#J})kS+<r04JlC@?q=n37B0b$tvvvCnBb|~qR9kSrbH)|'
    'y22|{c?SwCONoV*lpw6jZj;bqheBN?pz()r{to+0e3<(&#dss(r!H#krB&C$smfSyz~{fA8sKLVUHJMq'
    'c<;|cc4G+r<H(@_eF;=RJH`9i>HCd<EgZ+4Qg`9d??Wz(lUdY+$}i?-1It;)@@4Hgqq%&bgHs{<rX;yk'
    '0aj9_^qW`5GD7fbGyCO{6hKSY(b?FNBTy3B091}E{HAf`hO3YHr;;HqSP<~dNf5uiCyFk=jinX@OE?jA'
    ';p=jA@f!V#J4KR~)_j0eWL5x;hIQ&AtRqo&V2<0MiZ|LGUbYpG<#EMkH&G4Q-V)e3N0Sd|<^<t<3ebN~'
    'nXTi5co`b#l9R+iUAmjo_Y_7CE)=40e^9jIn$yT36B;RgtV&(k&6R3uM>dvD7*d+yC8!^<f5-K4$LOyF'
    'O|DZZQk{|o$al#BfLO;24I)I5ihm+WG!p>G=RW7esT#fWXZ!V|T7{HPkO?2i+*N7d?l&3Gh^_+X5==l~'
    '({^)F1)gppwu`r?h}vnWvnEg>Ig@hGvNAYsT+}?<{k9*Bv(Rlip_+jCdJYnEPvS}AQcy(o=449SQ$P5Q'
    '1(<5j-84Jvv-_49NIvy77OiJ*)*DjDl4szeql$ESU&CM1tM-ymOEjme)Q$izVV+!o@4gQjWqD7qALV{W'
    'vRK2RzsR%uDbIw)j(z7H%~`385SW0gyRIeqC>GcpHE=PVNKfI>wo_lRCRC28Zt4jpoI4=_KVFHNqrmGw'
    'OFh74j(kNReZ<1W50*ZgZNK=awj7AVm`uh^9c<Qh`wN@O>j!0*iSnD8;A6k@87$-n+)BQXrS0_4pRLak'
    '>Wt1E-~l|vbbP$k&_=FvFdX`f1{d*VTkCW_2V|{d<!slbuY>K*28L7ZeG<;(qh;ere1wLRbg+4IZwYYv'
    ';eP!nz|!EX)A{~=CA}RKQK_1~Jl!F0BsC0<Si8K6E`J3BST4*bNteC?SaCV2LAbfwe2K-F-R0W}*!+3i'
    'D%f{^MqNGidEpo@n|y7zt|7eVZjAD?E!B5ry9nHUTe`)@{e&jnt$b<}^AKdDMkQ+yK1b83P-%wHuP{NV'
    '5mmt|df>%9@`3nqUHrTPic+HqrL%TGf{^QpsJ8kn9jd)Vug?d^at`jm^9)W?c}z*Mk;cLT*Ud!iGiiiZ'
    '!Shn&AX&@3k)%a=@f9N^KYC08hfXHc?Iv2VevmBHFD&B6TgrAD3LcchR+;$tJmXi%dffN8F)WGD;YqYI'
    'f>uk|DJ}1w8k_if_)vKsD&fR^fJ#+yCX@t=8Mf$Uzt0t-Oh8S{>mMgF&8gl;OS#~%9#1Gsb#gBKi3^)J'
    'R@k-@KajVLJM*wvapwKbJ<L2|1rmw|qC7i6aQkA$S|H{d!FG9<U^>pXaBf5}7t~nE#Fn<u<N$riLai;J'
    'zq(NaEJf%gi3om#DT&<V<OPdM>yN`ZE!|rG9#hlT+*j9i&+YY{o@P?5XAK<9vPOnUhn8mQL))@kd*oS;'
    'Lwb(Y8(Kr%(?+!Cn#9ySb2K!~%~G+KuBs3EUY~k8)jUlf=uUrV^}PWd4Ge3fQDXrAcq5k@y5<tgv8}#s'
    '5zBCTj!Sy>kPJ4ws$P9dJ^7Tk2gbV?u%k!wIk{@5**<P^JtKF|q|>RB@6+OKve|XgDtPWZoIS;g9z~FK'
    '$fG`iZIx`loM*pNOz$4iweeib+OLz=&ocUt6dNOuAe}MSexkU3#PW_K=Mr?ngdQm1z9wmD#En3*vdBzS'
    'V~;S+9#nq>*4rG-fjVYaYqqc_zN3_{>1QtOSULXPg2eUOQKbe#0*%D*gQWv6JIrI{HEScK)Ci@wbVEDW'
    'H1@yzNl(c~f4Z1H#iLT>6T_4QLuOiWeq5HKo4;SkN*8qMZz#T4&Hx@&X7@YupgJ;Oa0i@2!LXBXDLJkH'
    '?whv<GW^TJn!IFt@p2{u-Br#|J{GpWBMV#<(-{Ww*%}`v(0{3L(8_<5&Ij-1J%azob=X77wE0zpXfcTe'
    'xw4%QkxlqrlL6!d_-a%P`IiDcQs|Zi(Zo#oun!V2hkQ34iT6c30XCzCW`zM|&6?v}#j}{eZ9CGqObY9y'
    'JjrMI)3ps)D!~JG*H7F=B8&Jkoa3E4<&{6B^GKP1H;E?zm>_?Kp2q8w8Z_pzzVnz3kJTsH)jzeqg_C4('
    '+jJ5J7ZLD;LIQ<;1YcNO_jnjN;f!{(6#wl(ijs7^cpnMe)Rmw39>r>V%~?DAnw2~ohrtl-LM7TzC3AuA'
    'z{!)b^1}Wtb>b{yBpFcBXkc9K#4g@{BpDuFu_PCib@1dl9<m_-VSD}s20nNnN9j8w|HfzvCwJ#IZ{y|f'
    '!)_0x@+NI}^@2L`6mmk&pg+p=EEWg;Z9<B*JcLsJ3|R}v$QEXo4E{)E5>m}RlxM&sG%V_{vIdlo({~Se'
    '0HJ2V;Y>2$3p3+du8e-1qytNq(jFMDNk}}`hxtX#i-jx4zn}pg`?HWV-mtwdXvTa5g~iYdC{`Sds<WIk'
    'Rv+<-37PF7W_fe6CN7W*o-_E$tY#8lgg6gSc*0y$z?kom+|85WO`$o5(Rb`r88MS{5%6%7t9XmaBnffw'
    'auj%a>P!|W`fF@T5C#u~_3Mzy1Z-ZlDSTB{XRHlu`7$-*U#SE0QzZ#S11fr;=h7`27(Wv^GH&%Rg{;7^'
    'kj2Z4eML_4Sa}jIq>1@lY%1l}T#QPDr8GI-wHS@hzg;4EED=_iM@M;BgLegx;)wS}sj&TI@#%`7HK1Ls'
    'h<R=gxP(<%i<mA@;(~x>C+5W??H9!(ZFEq&wamBti8YQU$!hmKZep@&D_@Di3CbV-z~2_K4c-^ONplq{'
    'WY2*zE2!o=M`2~&s(bl%sX+lN>=rdpfSTVMR;vq8OB%JJm@kJU6GO0<SQZXY^m~8CtNqovRmBUhM!8c='
    'n6$|MiC8H*e~!U8{Hbb4vg|iqj^xHy*`!Mr_$WCz5i`tcTGm+YSWf(1%HnepLI{Y1f_O-zL+!KclEEXX'
    ')Kp&B6(IcL7fMC(i8K(}?%W?|m#LUs#hEO}=LOI4dGM>m6MiJqFiKLU#O@y^aJ#EartJZz##Y@Nqq4ar'
    '@RF$JbOm{jdwXEnD4lynEJ=FUc~)HO@lt|VMm*aCMr%Y4$uSvFSyqWrUhOJia*+JB>qido2F5{7*(q7I'
    'L73dUSL$C_Z>`(8X4t+|6d{G1>_}IL&adi3B~zhW^tPl4fCe1gDn0TkGhEX!)<HR<Q3Fk)p_pv!q>~oA'
    'usmf+NdRKvtJ(X$2+kq{XIB#Vu{euKVPLIMj=mEvK5T%CrKR#DNqV_lo`gcvO6!tx88h4^K!0_pR0V3Z'
    '^2L}tN^?klS>{}^07>#L-GjrD;dejH<&q}mHNMsvLfb?A!nPF)$!Oy4DMAFiizJaF+D{Ex8V8kD!95FU'
    ')lSe77cjsO4i|HWMh``4544Wek50sLKcea@7(=h$H{3qyc|DU12aY}>Jxg;;T_@UbFc`U>ZJMS=^uE`#'
    'ds@$O+(ED3AN6h1^G2iorV08>moP?}Zj(N-3}PFWIdpVOH-|mf^DN8kIfEYQX)rTlk3i%Zx@|bUo;4!W'
    ')HTl_!_jbKz-zBz)V>4Lk~@x!QR<Iz-K{;u{(CxS{f5WNzOHKfTlGz-Y9Ul_buFpGNEoChs@WJTs(_7a'
    '-We2&+z0(9iYu`MKittN2^M6s-<2}{L`W-y5XqV~&O4Ad7!1e7=<C3bWe&>*7FY!|2NB*UcI9AJjL%X*'
    'aePi4?Cy)pZ@%oy0waqnC9Qk^_m>a8BQmM!&w>E{_%HwaKmC{g{*QnCzyH5~```WX-~5Ze`|E%EAO7ZV'
    '?;Q>NIZI|<E%u9K{=%45l9^M-7n%H1+WNo$PyX{i{n!7FOXe@4c$Y>pmQ4R5iNCO8fgR5-!w<PmD_@M{'
    'pBx4J-CzG7fBdKa?vMZ5Kl{^v^?!b`kasSY)3V23MDrKMEQ;nVZjsyvPKo7<i2g~%F^UlkZan|p-~P)#'
    '{>}gVMON=pR*NF;Uqtm62Cax^;7M<c9htvGoPVl>@TY(CKmPGw{V!ZV|LI@->p%VL|KUsY`R?R(*8Ad%'
    '#QwslMTwm^s}nl;BCLO6k&n!p#`woS{V%>q=N(FC-aP1wWd6dH1+ILY1fz3Sw5o^`!w;7<P_Dv7o$Asp'
    '=Q0c<s(z97KeZsrpZ>+a{}2Du-|$d(-YEb7{_lVG$AA8B|Ng)I=YRTd{;$9PC;#c6{<Hs;D~12(pZv#P'
    'G{OpvP<M#>)LxNtdHweKdhg}Y>GAVd=VvcopFTc5KYj6=Gv!eE)H<5Y9)3FsZM;Z8=FTNH;#^m(-LW)}'
    '(w;>%gA8nw8k7$DrlxD=sAt%^)rU`YSMvyUHNB^sx<?&*=-3V&IF>`54e~#il7uxvJhyN5MyBcZh&$3p'
    'E-`x!F-@v#7I7RGU=fR$hGPtdeZwHG>o|SSaEa{>$tKy!tMh}u=JgEo)ml7%60;lFdBpwIg3hmMWZAC*'
    '=D;r(;oQff18<)AkrToOUp?mUUhz_~O#!`nO8g1C?^Cbh%_=ZS(c3&8`9;p?k#t~w6k&JSx-}424L=E4'
    'dB4VR#qWPJDjP2op8WMhbV40aJHPe=w+Im5X#n13_#t}AI4f!liI=?GB5)EXgNE2gfI;qA%xPn*xxilz'
    '6}~IqlNqCgZ%M7oJ~v5(Z+8fDHm5T(r|uaRedM+HYSLZ4%%9k#Gx(>lB6e*?)a9(RsCqNS_1mEfq#A`&'
    's-Rk~VPK|)(wQ?4Clgtt;p+$3H|Jd&yugcK%I?OglcdsVG$RiDGFJ3qM;1JM`CggDwr;G`;?1_BWcO7u'
    '@aurQhq3YU)PCm{J#)97$F)@Sq$NyWc;3Vh=<!E_{-Z=Zg?!-84msa3dX-6y_(JSF_36aTqlndtx(p|<'
    '6Z>7I);;ys&$-d5zN1$kuvD;$!<_`PMSQe~L1NAPI1R+KRn{t{BX^1TQlo`E^<&<qUgaz8s9|u%-UjNz'
    '){ZrZjQ1(!<Kiu5<y!t4wjFPEN4adr#qR7&M*TO7IOcsmi$)T5ss<!Ya685|(9ZWWw+>Eh5m0S(6~%OV'
    'G9?#ud*a<kNul;stlIy3EEG0TUFv|0ia>rSw{GxMyb!n}2kkEWv)#C7tGzR<=tf=Pk!@Y|x>a=V3WLhu'
    '4?p^$*iv0S02zK{!*1k`y}DgEb-VHDcH`3BftPiYlO;NAV3&e=m6><!XtkuwGiha#tX@hH`$Fv;`3**j'
    'ZLcyPS;~0WV+SXQ6j`&cM`2u9%|hyh+barulO+z2u<>fHn@H8xC%rhj$^LB#Pq=%$e^BjN^H+%iQjhW|'
    '|9-cyq4j2;@3+ypH*|q!O4`|CIZ!P=`dn#6DedRVeU?O2`8^(2HCpK^zvCfpZo}Ut9Y_tqNsYkmH~`mR'
    '{Oz8E-&)r)aU(nUc9*d?iI}MydAp0iTk9Kei-3dL7c|BQOEC(kTw{;c?FWZve=Xv9jRy4YD4r)VoF_S&'
    'x0_(z9mMh)4&`kS$-BNyD6hI08-L|+Ar>{IbL_JetF8#Msj(k}g4nv3L92k0ebhYEo5Qm9JF+9sDr-C3'
    'p8COe)W5i_aS~vfoz>L4j3W4KekC&?4GQk73d0SyDfR46FhtgVhb<?!4jE?@9E5QOM()nAf}60QB<i+('
    '2>qqFgNlY-p8dqgsH!;ukdMFd-S~2Q%z&TZp{sD!*+ht?@EbuJ_A|x3Ua|S?vre5uN3MRB^+;2z;r<@0'
    '!OG*){HJ{Ef&5=wT+oOmPRknoTAdM>nJW_bUBaBOwf1xJ-oId0%qtYudD`UCyHoG@XSXV&5slHP!q~CC'
    'xD$2Jh_+b4w^BD*g6i3s=GndCS&6b{)lL&yXWdewfXu)dh_^prEuGY=$%t(~7#BmB9mxcYuS8WQP*w3p'
    'H$6edv&Cq8FF6}GH=JCr>^ijqzDgMK7rzihcF5{`Z%<BA6#cTUlQNP7i=icNMjP7;(ws~HIJx3ZcsoG;'
    'kYtG65A!PqLDu%OKs$^1cT&+Nj(*!xtXnk<9<wIM?a&*S;$#T&ysIQpGe1B^+d4-qON4)v2I9UtOh^9&'
    '<G&{ppEUuMltTuKd*VkxEI^9@028m(Jd~}w3AFMj{-q&HsUUUNQS<Sy(Z2X*;bTy>nB$R&H_6G$D2>H='
    '0N9Sl(^-7QhLz+kNaOvMT)8Ykjusd{>5C$d>+^hZlrTj;@rnmCWelHZyQS2w16c->gYBgzFDZ}p1MjV2'
    '%Pm1l<7Npbn>*v>8(CSJBHv+*H8V(@3H&NDnD+0F>42}N;ry6@-y)FSRZtrI_@j!g-%u80x>#OdD?QpM'
    'osy-x`9LYSR$E8y^DbE_;v*oHPCNFUN$9-WMN}Us=U$nRl62+nB2u!sOR{p_4R5Vxt?bA+A@z<FuDTPZ'
    'YM!SWFwLZ>th;v*n{WqML$@Rxbgr->6Wc4{id*5V&8~DGgUwS#r;dk~3Koh4QNDC05B7KL!_xeV;3SZD'
    '$%b*GND1=7Fb=|)N<8>&^5WFR0?bY{wq+d$-L)ImfPpTPyQ-LLDPH@gd_UxE#(!IamFG_6!nA^c=ivtl'
    'tlO$j@*-dFqIm5I$vzBJJTIitr8t=>^6I+$J!v{tddAev>%0dc5q=DrBX7x+vQZYUDf9Sc9g#&b5s`8^'
    'uo8>6fWc+E7v9C-ZmrZc9E3;u!OpF;I8`zSR#zQ=4j#gc#Fx@c&}~y>m-zUWydrD6<gkf+b7<$*kZfb9'
    'c_F&W6q4g@G!&<h;Kkqp`1>@fn^WZC4)>?RmDS`d_78v9zL0{Zz7r!AM!uHfONgbUER$I$WHJ%gwYN`)'
    'V~6-boVy%RPWqq-RhmZuj|aYo72Gc-B*GkGmqyOqXSWT;O8Hs>1OA<l$xu=vZT~-e@7m?IjVy|OpI^cF'
    '<W5U>cguV~+B@TMY$x%_!=AR2S?5f$v_Jst*0x$yM9FrK$N&9Q0U$+El*9+r&g`{&&BWajSpcdE^+KU4'
    '*E$NRsA7OMw1q6UC(S?178pNa82VnwjC<5DrN1#O(s#@vm{R1bJS8iJBV6Ko&JA^)qd%ecTsYAh?(FUT'
    '#UgYi?b*MfYy*x$1bkikeB3G^D1D#FufGcF%-C3)vv``A(<d!AX75ot>KBg3WaF+Ex0RFdS<gWwq(p$J'
    'nlJ!!zj@PlxO)}LpGhj8PAGo{nS64Qd;*EA%>+HQJRWSZK744rC{EmA%Pi>4DqW<TY>r1Q3p(Ejk&z$K'
    'U!;rq-N3U%o*Ck_38c<CHORscn?_zmo($KaMLi-+GkIiG^9lB3n|{{lekJ5sNvCQ|ek!G8^-f|n&OmiN'
    '$}eCDMfNC9z?6Sz&WEb3F;9vCUZh-BrpU(`8w7b!(_urUrX{AWl~eO{9XM16sg6-+zk!KsGoFchJC9CM'
    'GdTZIC#?XqTuesvN*FD`a>EGQ0Q*@1{V9h8XxXXvQyEyA7Jmo_`g#MhySb8rU}m%ix3nsZoxa1W%S$W1'
    '-mDfnG7Rof+MiO`e->G<vDk@_f~Dkw;(SRK)zT5TmYn)UH92UqStsEHd<_hmXIOM;K9UwXeleD5`8@}&'
    'u<1ber9#G?{3bEuKMECV`nsO$s3n{6kYavRb4rCzs&Rd%)YVO@S{8#+s#;fNsIr=tFiY_3VxyvKdk(B$'
    'Mc<!>zHbGsF@kfi>bXHX5Aw!zTG)lQ(`HR$aO`*Gb4ZDNQfo@u2b3&i%)qGP`ZHFxMm(%%^esoXNqA>5'
    'zn(2ds!Ukr?$7Yis=l5;iiRZ=8U$|+9Pk2%55;&Q0;eG01+Fm8v0P^(iNT_{TK&dU@8EykY1Lu#vs9O-'
    'C<4rAya?3aDa$lpyxg*a#+vfT<o;@n`2Lk$ax+}9sIe;<HLRv!(?RxMD@95elZ2QQ$+#zQe9sNKS*=9+'
    'iu$Ta(+(U>vkQ&t6U6by|6$PG)#Q@1dP^QzXv9~mbT$5WPD36Te9-DQ>#=Q4VA|9yo9z`kP5kz`ET=O)'
    'hpSjQQIsS3s#+&O3-H1ytGnRRKEvV+`S`;Ro9iZ&2BS%fy>ZXxMuRZ_0;6uolH!u*967Ss2Iodi4xj6~'
    'Qd-v@4W&5#Ap4-oJ^Dfdb&O!~nCwPI_s-SkxHQW6>5cj_T2C3yIE58<uSVF}Nune}O|XVdTiT&*c9s^-'
    '(XJEkZD#=;4+t79V`65oG#Y_6hLWWs597J8B*p!Fsd9Rbw%17gH@?jCNw(hwGxh8#?6`-;8n5K#fJ3cz'
    'Z8MCx#h91477Z=evfRKXG~pp7iJ4d-_bfkh7_%vS;zTB6+zedTj41qK1#OJuonE^Z<J=0O#PUp!xNc%O'
    'fk$ZQn>65o=fbcq3tWeIj%g><j{-ADV(!F_%{*e-ajQZ1Hro}}^fnw?Sk&tq%zDGiM-45O`gcs;j+xiN'
    'E1-|o<oeS1vHtNJa-Gkq_n@W4?7+WD-)mWqvZbbZHT|7NSi6|*J!r#KG962xv-REU+A^NPXFsKk?_Wso'
    'aRCEW=$e=E1mmXg?<;c64=(83SPseBHqKrw*1Oa#1W$P$I@Y!T!13LPfDwObT&3hzj`Rfn*2rVU^nVh='
    'ZE4df08onn+^@9x9Kz;wvgUJ$8m*G1x;t?XW?kgWfK~isn{=v%`AyR*?oC|kmzJMLSl)-MykAkdUs85D'
    '39cLke;S}C9zJ|%ycE~ili3Fhb*X4iX55f>+*qVWUU~S=U}Q}mVX$eDt}z1wT;Tp1Lnd`)8<EDGZ07mR'
    '`N@FAEI09dMh)<(_#y+($Ech015P2fJ%?_|VngQ06;~Xy>@lhTXJAy{1s}^aKIyR!F+=CaVkFpPO>FrX'
    '+`3Qy-Rx_?qIkr3^6G`~U8^;t`w#qSfITwc9ON@?u@mgDlWwp-l)^v8g9A_1PAW$3S&IB2?dB87kh4#N'
    '6m>0Lw@%;k1tu;oX7h6_e<7~xG~RrZi|H--3M_0E*ftWI0}W#0op2|{W99rcz#KZSq3<gx*T-zvpcEVJ'
    '_Q8e={%j@AYatjw<UF2$Acr0CT4e;Q(-V{u<AL7$XJB;ge0~Bp|AW+rtMhn!eXBuaH|g8q2o*O~{!8*T'
    'm{2?uMwG~h#7q#fFn}wT%M~bzA`wDYMyfgyR3|#4@kH)5^ijo#WS%Q|wGD<|@HwS*(oa?l98m49YSsZR'
    'wD{mlbF$^sLCFBXj3|*VjW4b7A8a3<Ue}yZ)ePVsbqEK$WqSrEYrns~;e37Q9L{kZHw=T&G%d$9dE!LA'
    'ZCbwLJ9cOWrcJ$=o3ZT#0XIqF$2<%zMuO1uJj)IPtEHCPIf^45he6`R@hNqkh})4FSlms_&~XS1;(1{}'
    'EZ-#DCh$SPJU2{u5<7nAdN9Sd<L*6;tN(zet=%B$ofj<zu2(9k0^jLwJH+lXbaqf_2KQR>VR=D#e<yn|'
    '9%5V>`+En8{sp+jUM^*G8728oFdF{I`T(N`w`BPY*7XYP6xcWGl##m!<AIzY9my@&k%X(A<mDf2)#AlS'
    'hr6sbq3nLCbem$)yps@0g8uJHs~mBsS=?~(S)DIN`sOL>!TYH$x_@;i;D*Lt-`Se11Vaw&^eu<|5=Hj2'
    '6{zAZ;8wLz)RkcI(kYmwzOOOas~B$JrcRf9u?0GkP{-Xb_wV=7Ph&ycuK}Ugez-UD;jD|67_Q4tq{`3k'
    'Lo?j767NJAE&BU(>iZ8!A03MOUQO>47zuwE8{tsX%|9s8WU1yqB;K?`Jh^4{M=-4J*{(WdR+XYrcvPyI'
    '9AVYS>`)}iifo^TZfv=xWd}446PNlPAw0Br;FumuV)!Sv65EPgFXC=&dZuZ`geTk$yf%@johX!P`H`78'
    'VG_8En|>5B&O?`m%nnINY}az)z+=AYxUNgRi26ywsBN=|MzLqdVVf}<BT)ULgn#{!%oa~5pw!6Ls|{Tn'
    'H6&kZX&-}^*<_gi(jbdFG05`|OTL=%1?4JXVPKb?*K0glD7WZafm~UM?i{5>U5O8W6P4Jsk0>r-TpHpa'
    ';IVe-ct1v0xj2Lur|eF1AJW%!mCon7pyAIC<ezt~I!0Ljcu33B-uG5czJ*S|g9?tA&))H8+p@8j#%Lt^'
    '*gRQ?m5d*2xFvg^8}+37^t9V_FLWT$^Tk?RxGZ7ohy3G#-O07e1+8LXm{ic(Jymy8f)&tl!i(KJQ8!PY'
    't5Vp#3-(qT!pIZp$$K(?Td#xNcK~VqADX=?rmeS?sBo4m_V9CA6mdjvW^=aU1C}%aR|Id2o?y!Qo5JnE'
    'ysDwDaS4On&qk!6PRlm8x1=u2Uds<hN-t=pMOAfTJ#U?@()&~Te#OJ7rNilk!#&G};i5saWVnC9urJ0}'
    '*d$oF<|X*@quf-L|Muq58<JJb(VBg#Vu?Ci#g%2#5`$SlavbW#v;MdBx9F)t)IRAvLQ^L{PT&-R;uMG%'
    '$S)9<rwraNL!H-1-&<r<!RQwppY+Sla?guN4C<G!ID559Z)Xcw$-lAeLsCyL(5PAd>7&6=E9>(ZSzT-_'
    'ZC;qBJn~PIC1L0>j&zjwn=Fc!Ja4co=U!gaWtvacBzrr;)}nbaIk6AccNmVxFvLh(U$f5pZRi?x7F1TK'
    '_^2Z_T5J~8$3xcmDV28D*~|kg$(6>#h>xPO!Z4OQF9yX*b^{vksj5_XO)Z(^%aZ?o-l~<SIM;ZFHKFFU'
    '(5xo+PmeaxAeZh{EbWm>wfLkc*k7~c#{EwY&xT64>a5enljV{VEO=eAKgCBn2YEKj$nH2S|5WEtPjATL'
    'nvc@t<dm468&h3<?WzvIimzuY{vr`GmJ4F{>|N^F(I+74UT@g=A9~yqJ+`8?G||xv{N+pI%PrQ{WOdEg'
    '12&ihpp&GPu+1&1f1ZuxFz3eo67*a+DfKTkyFpdxBYp19r#})u-k+7OyD<1r8~y%F^h)9CY(bXUO^T(f'
    'x7$e+t;RF?x{Cedl$Y-0Sm>$lS_<l6Ra$``b=&+hpHF`MynnD#(c`k9OkJ9d^%e2e>Mm(0pW5%u-Y;S`'
    'oj1TUhG;Y>6Q(m`eZvhhM_gmYo8@vo13p6H8yQ`3zL*#<*2aRr<Ey?j1~8cJZwTj(tYA!HpnQWVWO%Q;'
    'e`ms7U$L;3FAeOtw<e;_@^>V=!QZqc^<a$oWsEoGw?ca`Xwi4$dw!R9CVV^?B44KTCa;Y%99+5gf$UB<'
    'EL&#l^v@Qv_2_86)L2vhi9GDK?H`+eqCuNU_5jdz{ut?!XRwWt*U2?9i#+;Rz2kBx^A7|z#LsWOxd^xQ'
    '+j~prTe1>`w;5l~(>pwt1>!IR6hgXz-{U*j*2DXX=6nx0%jxh~Hldkp*Ex6;u@@>sh);&MQ!H(Y5<`_f'
    '{fs6Xriab4Cq+RQ)l>507U$}E$DjXPUC8H9YzKpYMZ(-b8K5A)5uVefF3qr&EWiRk|NP>a28RXVrBanO'
    'DY!p?BY@m>V1|#i4YIAoC#+3W2U@&>@)++__aKdMM;QhY5cp1Nf(9NzxNF76lARylzfFn%x!vHx7T3}-'
    '+;yf7==0vC2hW-qPDgXxQg>S24riO7?%**~)p0i;SA#_(staj>_emq4HF>3|+|G@yPpOf&&W(F9Pn#uO'
    'UgQn5w4(2p!1&=n=NrMDoH@19K0kZ;SQ6W^Ihd{_Fe#w5&boYP^ihWw@M@FYAapeROCGy%12!(Y1K{ev'
    'oALLLR978iw(eUN{Y>`8#YEF0;0qoA7>@V{eDO7*Z-;vVH68ruBzkigNmXZsYTD#pk)SOUkCIKOOKHDr'
    '!!!sFbyo3J;Rsa69wJ{Fgjp`a9#6`C368EUa#@y=|6XFPo;`U#e6^cCiMvdPjFJ@|Mbx#vlfSAB+IvO&'
    'Qkd&2t^TbJv3iav*-Lj%wR|HgYks6$EAh`~7kT-S<Fw{;RPCYx23G@*pIQhC#@vcO^_xx!C_zpH2`d6m'
    'm!K;Ta8%y)ZYB7~5|amW8t#h=HMp9IQd3{FQ&Yyj{?&J7U(^`-W5v(?Y-eEQ5KNWCmFa!dCt1a@a_%CF'
    'KMsVJ9_hJ8@VTwl69r@&vodSdKT0X(>FqMb8wuMgAV0z1Mfb?+(?62+&CYXIJWDq#AlAblQVQJhPmJ46'
    'KF~}YmSyV6Pk(yy?Ah~Y)7L-0diC<^&GgliH{ZPm5{%B?zy`=3;-$S67+OznIDMNvT*HS`Sr2C_E3-`V'
    'QfpH@<HoKCljR+zn-&08T>e(>*_Ag@yHf9nC)5&}-rd&mKJp?<Y4%V~@Ip@TBA?(zF~M8bI0z#3D&4F>'
    'mM!OG@0@lKf~T|aA9xdxfUo8#5VOH=FT}SO>f74*y8yR16_EKg@X$)^4}?7a)2k;}&wqL|ee-hq^vRp&'
    '-@d&1KhtN=e|Yl*vqC<eErA`dhRRvO33h>*#%PR86+4`rONM(o-^AY{J{H))wOn!LH%t~T-A<ss<Hd>Z'
    '$5H469(9=?SxJ(x(DbZ0GULQ@y@Y!d9`Qqq(TI7>^=-<ci1IMvBKcUj#OVUzt@tgBD{f1)ootzRaH=_3'
    'YE^3LGq(bl1)*b^iO-pDo1Vjxkn+GJgi~snu^l9g`5rvN9TL(wuwygf5%s9eVpXuYH1mwF<wv4*HGbkH'
    'eh|fhV>xyVNQwxD0ZHUWzROAMg|TH(CvY5(#Ux-Rp`1pp=~^Bjh|nO^gauhQr@nlkmKAU>aTrC)M2T-D'
    '9tq+&gn3wzZP}p>Q%Nk-^DJgFo)C{ZJT{}yi@m_yS^jc9ql%m&H32>h)nDnd_#;P7rHIcA1lnqCyv7;-'
    '{NjL&JrrDT5V3Wf{Ab1Zz)$|tqC!by5t4e#p=0mk2}8YwcafZMw6sV8LKbSzo6W#`uPPsWm)`QC`hOdE'
    '>EiY5dhudg?&Ozr#>Ootgg9Z9k|_mN%I+b8E&Y8AYD3`<S=|dJwbM27_$nK~ZJT*sHudg2R(9nG*t}-x'
    '@x!nEHDM}^yKC#ds(#xG14ZBT0kaf+yvzADwQD5Xiz02e_krDgs?9AI_k8hgwn{}MmC>)iPBO|D{1w>w'
    'd|W*`Ej~X2u)nYvE-N&PilLI?B!WV(oH(|hb8`~l?lm=sz<<@%#W}ou&EQ1ii`LTO<RVRjL~AY3YFBpa'
    'mvS3GWH;&iOg0S328dR*`9V9$$@Er93J_`}?D*J!Mmev3iyxHsf!JK%9y{XS2Nj(AC0TK%vP@Ar9?f>C'
    'L^@Egs5QQZ|5T<XJlpT`wC*ED<zC&Th0wa_tc%PV>7kt*XU8{Q{im@mEjZJZ-=x^_w5Uw`^=u(-mWr7B'
    'M<w7UZ~5K(bj6HM2hL5<ySp^tKi|uT$Kwfte6d(=)=xHTSle>87J(FT#bzRsypL{)rk_c+iEn4?A4tsS'
    'SRWYIGoFC<6(7T_-;nGr{3E+jskZ84<I};YR?B)p&9!wEejapQj;zUo8IslAqAqODafwI=xz?R(zS)C='
    '1gVr}nS=V6I1_OqfTfD&6UH%DKI0F@JuxGur;35hXu5d0nBR@Jh06avW9yqs!*$P%Hf75XS0&$FdM9LW'
    '?@U|vcoGx(Ru-8q)t8>6SQc=7H!>$?I6gOKhl)X+UE$lPkLj8$t^oryU4b090_$~?iOPbV=9d@eDOHUY'
    'zlqw(hxqxRSiXNTpj!&us}MM~3^*(Tu=<RW0AiwTHh*P{?;W=H-oK}<uW{#}dgBk<_xiSd3;o|preh6*'
    'pXwDLwzFB|2kj*7Btti7G|QBCh3Wrametz$cnC57Y3eLElGMLc!sxsbquTy{UJEiElHt`S5#<YzRfq3U'
    '?~qWmu#oc{;p?r%ek=O4BVwh}kFZC_1>-1-b<|SHmn&VAJw|Dfw1iMDW3l6QKB~LASQn7;`717U&iGLa'
    'lA%L2DWBWQOR0FItA;r~*`p8q6=P#xZ)T_(Yc~Y0uQ3XfF0!_zkjn@0U*uKCigwCvdFDG&)wuohxzaE1'
    '>Ed#?>b-FTJc9~i+{T({qb!EX6ip(fdcU}-Vq;S@r~^DIV}k&w9tWGKuSN+L63@SVc_g)JX8_q9Xa6YW'
    '1w9=+;=Ksnn#?`#VS5xmIjA4x#=oq8a9;VK)vV-$gJuQ7tvD%>Xp)qf+>#}TL+qg@?!3(wt(kZ4kIHx~'
    '?TGV+nB=*!n+~~m+{OrL>)gY3)1Edlv%uR3ZLb_f<00dKnbb<5pM55rcIUCWL^$8Yp}eJ%l}8$tUl~hE'
    '?j5)ni8~lTZS9|ZwYLV6ahGI`lsPUY3WTTc7ul#PZ3k?Y#^VHe(PXnkGv{f;dC2Gl_%7LRol*X8iDYG%'
    '-V>Hv8Bv36`m#Y@stZ;_WKj<6;Np9XQ$8X--5^zC5QoX{nzR=BXprYGeLTP(t+{L<7q!H~UN7y@v18Ny'
    '{?(Zd@^lv-eO$zvx7Tu{9oZrmymOtSenmx;{g$`VF6DqaDEX=7p;7sGQ5`((J!YS%yUE6+QspGi>h3Y*'
    '-Xx%pMk`VMxPz$Q4r#!czxBdU?t-Y=6RqZW;LgSFB$p`EP_a!Cna9*;mW9)D57W%|O5b_j6E;;<v9_}m'
    'sr%KSc^iRqFa_k%LGz&Dkgmmm1Jpq$R2-DuZ7?GWc5!1#uDK|@Bcd<xU$8X9rC&B%aZE3}J69FDh{3QC'
    'sVKE2<PnIO-#0v4Puh+4`u%K8#hv18vq}hsT`zCjWWZ<hIR@*qM=(mp*K6Eo#RTyAce8imdE@{9(PqfT'
    'AW(&<kBw0S13YeKnoC(wwMAH=bBL+0o>~s{F-u;ZQg&P247+-3(}@i$pJ}5Bv7Tt}h*@hpVh1Qnlo!cQ'
    'oP%7Ep#|j!--Ghj7(70^m#AaMz;wsB^q{bG%WM~YCo1*HZS9iA`Lzl9*K(gfZcVrsm{m7=i>3H>hg8q+'
    '9tiFqH1`exMVJ+fYDyd%wp+Srp7`x*#zr)qZ*GxE|ABwLSo7P_gfOziO^=7Xv)j$>rD56Lc>G(rsiNKC'
    'r0<(_^_<X~(H6nul9kc%C@w!r@0!elyK*7-loa%j#GeHTgr3O%n9SIt{)c`tG?^dmcb%wUOW5i$2>9FW'
    '7N214z2fwpd{C$F-~lA)1l&~);azv!Hf=;#EJM$3YT8W7if%1<_CEA#m0pAH%w$i!?NpWN{NO--!gVQ4'
    'w_us=i*0Zy!&wbNqU+I3TT#+Es`o`Tl3G?o{X=ob&H>shYn|MBY5}NA{`C-lXZsJ4_7iyjIm3unjurOT'
    'uRrT~a&%I`+)FN>SS+_NbgD@YwamP)3~_sKaOOkBv8-N?-wDlCCnT;2luN3Yf^?4#W)EY5XwJT$Etq`0'
    '<1A}dkBC>OamNP9?%<KO`5BcYZ!DNlgy7q&>?({Bh(|RFmO@^#D1E<6a`}%kqv5r3n)w8WA1$_5rRtZb'
    'U?Mvy^7{v@fR;fpZKk&rM-7E-&kaFZEKIS*S>dU)FOO64rq(n1mY1C=kys?EN{&R;+M;`!_^Xwjcccve'
    'PMU|<vZ~g;wC&Z9+hvYg8<-M(mDS|ZTCVlnXj)ete=TybB*%)$4`JG(Uj83%h1=B}sTS6r!@J3}BI&b('
    '{6dcUeIqa9N$t?a+#jY@x(6%oL8o+7Df=}_3-s5d*B9uiqwo@^R>(r#jpW{XsE-<I3GE(~OE=xp$*{k#'
    'Kz#dMdwA2z@-}U&TjaNvzusi9ld|kNn*j=2R{HRRIP`4Kv18ZwsBhDRa6j?=kS8YdW0C}(#i$Lx#zA0O'
    'zU?KE?|HFhaccY2JYMO;3AmfYeqegO2OvmbCl<8`Gr2{**e28^NkSdZ_ao18y(ple8AK*?d6+nn%g%J-'
    'qPgBjWSbu2)bd$Kt;pt1XcO1>d7Ola#TXB0<iK<j+YT6UX%f1GhrUlOn=lqxZku`^e!1R9P_6gTi`*}l'
    'T$Z-!NN~sYgCL|1cl;#AN+u*?rXTp!W1+($-?AgmNn+Qd#3g}aTaje}TKw2{XcY1m1m_m99GAt8<9Xb7'
    'sOg6Zjol>iSR8vKrU45GHBC1RsqeWVi-_sDjuY_^v3#Z%8_guAfoJ-WMcs(_2?r*(f`pPN0>%zwV0f5d'
    '96O0?a|XEa9pCa@pE?9s+4bEZY(sLlOmc4k$zQEf?D6qa%DA}k^K_Li_tYG+xI<mnO<dmuasrV9+a<uo'
    '+>DuN+P3LBzGnuOl`z{0Tp)`J+>j(uV1`~onTDD}P3gofnUez3c|qg?o_&gB0A2}*nfN5MV-lDSceza&'
    'i{TmO00S}R1`df?82FLHlH<&Y#g{xFbKu#qTFZ2~YsRqOlh`qt7t_d(BiQwJ;KOG3{TRey!Z~wIo0>uF'
    'xf(I?`DzbYWyZAj*B+`SpU&2IFPG}{YBZ9!vd@kD-xrH@sq{sg@;FDbOgez5WPY@HPb>&lu~Q49Si&(V'
    'BF84rk>3Gxer$2)jZ;5w<q56HbzX@9jD`mf02YwuDxLG%$62~szqvzy=!Gb9Vzq<co!ZjIKF`tmSDxW*'
    'PngI4(GH-#<ss5krXYM}h`ahDB*=`+e?dOZZ!H`>@6gTM!+E<WYwx^P$ujErUWeg!?mScq;IsfRWG8->'
    'jd-^I7D_qtc;1{xReZY-aeIfY?6fx1JBgUMS1Hk3NOYAEErRdUTk-)<eGbB!sE1yyK;^1yKN1(CFHJm&'
    'fBYCQK5i%7V321AX1}cx1>Z^gLOfo(xYe#0fv8YjiSBLxcvSgz8yTy9pq>)6Js3e2PYe#0;rURUvb)Zg'
    'Ft^tew}~r9V`TS3{ClPS=}3Qsz>NbJ$N68?rRt;I=PFZ>9~_PaCX<@972&YTCj+BE9og|9H+C%W^9m#1'
    'tA-?tI~46A5Gu;beJMm?=>T=yJqx8NrGw1p55^NvHY1Ssk0*<?WnxtQr};d*cEI|jsg720JgIod9Jbd4'
    '6he<$Hl1H+U#ntEh0fS$N*UXeNK+(ssAL+vKq;yPc3N4dhhIyEDo+N*Rra6<KjlR*Zlxp>f!XzBoicJK'
    '(%vNdZoeAI@5bHh-<)QboM@ALraiKE*oO~|?>S!@WMS|R7*3e2(YnM_S&^fyuxH%PU~6D${Z)D^^2Qe+'
    '2KSCu<a8fM;C^smN?3SCjIzmq?%8%84+XD0d?NJGEx9wOxHcvmRo#-shRkL9It=`vD=t(%bAG}k@=)qL'
    'b8dW5I;X}|88TaBqxUy_#V-#f%LpQgrfXa9pT@m!i;wn64cJ`&QD>V6#{c^D*U@(1@q_V@YuHupD}n6;'
    'v@6qgeO|LzKPJ_?<}RK(k8zhlIwdhyGpPn9G#-+oN0eSqZtaAZL=D|zEG0SWrfA>Iy<0#^Kz<-^E21u|'
    'jZ`Yq)ut@hkiFjpqjJ{wA{BOcQ+X4A{&Q1akq(aK2<fvhsv7x(g0suB{ftKaHe>sPb<r&bTYWs;WNYy0'
    'R;oPfn{+v&qS?uw132RIAaFRN5#e5Bo5bZ-65BTM;8POXETMK{Mv=u5H}Ea$`#g+D;F+Nngf^!G58#S<'
    'Z(Ee)jZ*ftDZ%4Sn_7--CY1Ud{uldRZ2M8b5+_bv*YZs2d$t)-+j3$v3WCIjRWK{@T#Gq6W(?X36fDQH'
    '+ox%|Vp!(9^^rDACJqP>yeM)Vp2SHMdJavZ#Ns{;Y?Ij@bt8+|rseV|^n-{6whJVQVP#=RkDnUCqY1Yi'
    'PJ_S%m}cw;p+#Lgc8C{yrcK<?^GN7KZcJRCxGeTUFW{Vcz7xkmtQQ&02Zuc5wi~#K83v}C#HQ~j4s*OP'
    ';a=#lI3%VCbBbw5fT|?1xl4SHMWM-}#19B<b8zUD4-TWAC)#3-^|JphNgXpk4me4~l1$%D?8sw;1em|z'
    'gxut&Yb6fsC}7zLvrDj5jqAX6BfiC~HrWd<^#dSZ<isA2V`6ho!vuD%>xU$YEguGT<H$`yKXQELJ1p=#'
    'C-frEWf39lOcNSD-|4VZCbDz*bXYc0D0j*hts6x)=B4qbnw2TreHMKcjcdM8NgIcXC>duG+@$n4b|jP^'
    '3edu362HI~yD50bQ!h)asO2Y?2mOz)4C^qkqj8CQz}G3!r4w6+8pa*!cA`3_yo|x^e|M}I#(}RMK71&u'
    'xL>3gNGLAeY_FPQcq3i#qOOeUpi#bQJrVcji&u_}ChyK;-2{Wkq`!wEbRdt!&>2YbTR1TE^@=Rkndp%s'
    ')0we68j;4|p*!z?RhYpkmpa4bR0Cx)H|U&X+5S=@M~yNCj4w8~hPV}eX*~aZL)Ju=(xG@ye8#X?+B~nw'
    'Cu=;M8*M9R$PrXO8&&({I|6D!4AH`9R1miPX7HN)%NP@>wzhLOIHi5r?L}JLWoUJ>UVEEt);Bm|<k4OL'
    'WYFsgpy7%mH=}p>^NYpWcU!>O<)KP_nWi2-?XCKpGR9Xsq){V`A1PV&RVAyxZDD`{@!R*yS4$pMkz0P~'
    'N%@PG!|ft^3vu_m`zRz-*+!}uU}dwmE1bg1Z7fv7Xt61Kyx!CWya$-Au4x6LC8pE}BQOld8XBS<1ih4!'
    'Q<c>)CMYpG6zWmMQC<y$QYPl(4(~NlvCI3igh<OOUga0dR#3bCO_gcOLSpUa``40@@#1=sq8Q16z31eu'
    'YTqOU;iyp(4jBTWV==%>QUBpTG418t_z8`OzdUZoazavrG(N`sjN_A_xpBD1s^;2}!f!`FqQUcA7!#>j'
    'A*^dYOZa+r%Z)XdHrY&&FfaR)&e^u~4_4x*^Nk3SKY94|!zYs#gI(nXfsD7DFSAnhpp4w|3)zjiFxBuD'
    '447K0%@V~v(l8TeMKG7mEuVBSfolbNnz-P+dADo}%N_0YUAZr!E=D(Y?{0U$sAvc-K>h1qGRdM=Aql>&'
    'eUd+@_AWf2erv1l8}{y_8qdkU^E+Q^ySD12w|9LXcdy!(WoIrlTSqii;j#)4O*fTPwu&(KbIYOBNgP(w'
    '7RXMytLg`jDwNC#sYi#(`fOMpZfelYY6YVz1yk~7TVJW$8t}EdbnR<%suvU*zse_t?r-BJDm^n0BPf_e'
    'cdy)g<ZQOiM71=KL?EN`sg$X6ZY)x;`hnc*_vz|wOTVv9fIT(hn<%2be%yg7l3&gxnH9+Kc~haaD$&~9'
    '#VnC5pSZG8)IdkepH+;*?eAla{M}S>dzx3yxHO8o+g%ubXX93D`>S&DsiYh7sQg3&k3Iqa9Jy2`P2>e$'
    'Za3LFulNVv5H=AKJe$W#aJv}qZ@@4&040S})rCu`cFt5#CMDNz5DV_7hvItuOr?jB=zTEHUm3VWfOd2y'
    '<sI(If@*d6nwPa}-F6`Nwu-3G;e$vmt3Pz8Kr|3LdBvlXqD2MV{#b~qT$|3Jp8yRz(e3lCNts_qsFgH2'
    '-*0gs)_R4r%htQ9l-j=iu*!FPLZ!`sDQ}o&H|H109P>DgY!2pvJeR?+@&;EYZlK?+(nY$-474KJlu6xM'
    '+r=aw71nN^6Vz>)@S-YS_z&SRqhval&a*`EZ|zH6F`kG5*9hbB1WPGpH+f<3V#4iH9QSg_mj35ztevt~'
    'U#Y%WRsI;n8)AiNr+kQ_hD_GKh|IpSZ_Q|t<db&Fb{`eUKR=R(zps2)k1Aoi_ZAc;aH}kGdj-`t_%|XO'
    '#vrQ|c=$6B8rX<jnq)H{mY~`^t-5zPSC<qd-m0Irt#PM{<-qI}NrXZ2e6>ou_38lhlmTGC0}F0sLau<V'
    '^KOO`Bg0!Kj|^ZY7%=xn-iyN<u&5>-C;joiDf`vwoRsgwEUTa1b1g#^L{X?|uj$*p&`G^l1@&}GuKa|%'
    'gH_W&^d3a4M3u?`r<T=ucIxYYY>WvFI=$(ZuJ$*?#Vom-e4r`g%T@Yc50|oN#AF$Nz+aCS1_?ulyPjhv'
    'F(pnwgD7T{xK2W2+l&%7Nn(dv7G+5s$HYk(HytZ+s6`{6CxLZ5wI-p7WBG|^aW{^=*oxvHv17|;NkF*e'
    'TP*Tv!adGI8vBXm`w4fgIErkG^Vsw3Gribo&am-pX3`{z5}$=;9Jn^I{Wwk{k2}mYeKTQ}?|C70xkF6f'
    'f`ufWYq|+f632^Z(k8>kHY?R&0KGj^souakvxk^Tq<*U;{=HhIY$GNjzTK1lM-vj*HZ|?ok1R9hw(UA$'
    ';@Jra?I4U83!=cM1V|IJggRE_P&a}nsp&h65qDtvUwsLx)(PG$el2QA0R^uRB$*#tMVMG_?6_{?g)xl-'
    'o5TP8kT@Z8Tnor%g6Jn+KwZyE%os?;LMw<}({s7yM3LER6`LidqU0N@d$AVohCT^hH}bsLw^;()&Y_MO'
    'g;8R{XRc*atW8710Dg%{5Ja$X%ph<r&Ma=aEw)?~MM3OaA+cHLnPy;`n8;}-HizAwgmGxa0p}KMc@`53'
    'Fvo*9bbTI>IPzW66#?MnO42?QQP0^w(es6En2C$9ySt5;7PBK*A5aD6MS%UR#573|0-*vY00LRA6<RFd'
    '7IUJ&<jiKwN)pQifnoc{G2ruvgh*wV+7V%qNy6CWEDQt3<DTzY%<_0bJ%^Ie0@>$Aj5@y091oLp&CVE*'
    'Tnvox^J2E%?#eukSanB##^V%pBR|B_7RW`$V%rAsXopega?edz;D*35mSe{O5DsX|P2zK44;zG%8QPRP'
    '0fYT)F+D8Zu%5i;(lbue)f;jxFV`Jf3I|PM!jwrE0*BdQ=yTt79p;$S4r1blmKDOUcH-d59Mg1T&-Id!'
    'Q#Xhl)<U;XLI@8Ti7k_dBw~I9+)fh<gc-A9$8s#-t2kspdgA%G9f0N`4e$jJ__QBd^3>|5H=MrB9<JfT'
    'DFtdzsUr8Za3ZFN{xzQxCa%e)i^=kC7f+r=g2Z8g@4;F~3_8U%F*zLM18jUimu1<O%L3*m5f(_ZKnrnd'
    '5<nk3N_3L^_}WyJ$SG6I+_WMWh-m}4y@XpfY~a9yy>5bRwqh^j%p^RDLf>~h_!g+=Qc(VGK*7>*KoJG^'
    'yrLyvDe7d6iwXS%%huU(;)bCWg|<(FBnHK3d&~iD3&2<by%@U;gts4uSfa`T=>l7lGTS}%Vq`)3sk~${'
    '&BOG-d3ndBohAL0F8FZ~3PRchv6z@3Va&v0+>c<3g)~WA;zyvE?8pXb?S!t$sSkqOf?a5X@bp3R5>MX('
    'Z<XW$mIKi<U6bqSQV5?WYQ<o=afgE*jY8N~CP{q9#lmim2S%&ufDQnr^9ccc=$RmOtRR667g{a>yEh@n'
    'g^r7*@oXLiB;+2jZ0tAz-lQ;@MXV$U!QQaU(1bkz=n08$yEHI;ELq0wgwx;zh(QOQzn67SrqU&9!c9PM'
    ';t8W3w;~RfzwgGtqoI&Dkqc7BF#&xHp9{c7aNLl=I&5Hc!p*Qnp*0?Xv2RC_2WE#CB@yL8;&YVkb_}+c'
    '=LUcwPzW9vB7qqs@I3PZur6KD?~xzs!_87&r<f9ONy(}i8z7J(H?$)TBFT@ygfxlc!Q{-?F+(qgPh5|h'
    'Nf?0i3Ox`5A&9RS%n4@3yPCG)RzVDM4J=fXfvpXu1$Y+>M4abhzJB63=uJ3r;v>Vl)DHvVIX*+T$KoMq'
    'F8$cRAmLQSb6V*p8)ic(bHEd%ga<zHSQJ|nEL1-NX&yv24_w~^FV1v*LKzQD%MNTe3}9<Gadc|ow_O-|'
    '<x_R?(nxNPP#*by5P=ByVZL$b$4L;tVgm4WJz)AM1`pWd4D?pyF`Gt-?M9~OgSEoiked<EZ<a%C*kUmO'
    '$CpPT1)9^y0to?L2$-9cSQg$Iv0Re^nOP9R<6w`%Qu|`1><8u+=c_`e9W*vUPT3BHg<=g(@XUQTz?&~2'
    '2rtlIHn<}pASDdI)}%=oarAmUo8UDzaO!=%)XmpXuK!d|Qa`YoR$9#kCxcV8onZ}F{u4`Lx_;pC0RNvP'
    'xDi3w(a^)oQc)O!Sq-8J`~pyI;o!B^t!Pof=b(#gqetiw;({3sjxL3HxRwi(g1_;SkL838Ji}rZ!-GK_'
    '1rdwD@THu4cGQAxJsz0}b9^s=|DyQ?Dgk&nbX>4<OtfP-)^r7v(*Xu>WAH9bkdJsr(1ZQ%4@F7o;@cra'
    'c&-yO2aK-}3}5hI!Pp8-m`DK1-Q-|#aOQ(Xv7OjU0uTNJZf_8o)OEtx4{Yl+yxKEx;exLZRuxRrGdXdw'
    'uyPm$EHERBa1R_mkVB^B#a75T^P<S79>^_VT%dfCuof`@3QETT*%n906QHzgP~o7Ay@XKM!88KxY=eVr'
    '<7LzsWFDBT+yfS}0@sdXG88d;ubB+q!ASrp0nNjh8`%-w*9+~Cq9sPm0Qdv`1&SwNiGhs=>f7@yH%thz'
    'UE;E%SM_!l#!{L+M2F!bcNi{|3v^MqK(}m%!b$A;KDahsU;@TXu&@{yLfps8sEOx;;2{JnB@?g$SOShb'
    'JPOmbn9YeDQAZEEHcY<k?KI3gBqR*Lv2;Nxf+G$pjrk-1<17XTp2UoR5d^+!VzST$Ef+^1OMzv;dUOEY'
    'F4H(~>DXLI$L1n;Y%U7NW_R|j7$^*VG;*Va_;Jh~4D4DIi(iM}f>V~@onjYUQ>-lvs|zgC#ahIm!NDkI'
    'l=NClZmM4hALaslm<#E{Je=Jw=lr&~Th>4l5)q&UflcfX3%m{=bQajumdAbHO+YPMHi<k?QXs7ZFT@Mw'
    'F<$evgU|#Ayp0OL*aFx;;I_r4<@&AzsNexJgCGdOhzDT-0>t-0Y7y5BBG_3zd=IWK*!7@}x}s#ArgPv+'
    'wBwphQ>sk8CPOX)v)XiQGlu;|lYoMn19gCYO#qgR1K)W-Svv%27r`C`Jb(oC!Q@Lob4End&QeR*6ZSc1'
    'Q=1;RUU9@30~sI2AVtDZC^gV!5e0|U1Dnf=u;?|Rq03FYke_%2=nD=Mc-9&huol8v21S4ZFnM@{&y%S*'
    '3!df;LK{|L0p=6%tU>W6;Jd_O>_iDQ!S_u#xQ$>|c_A1~7MhfR{TNgpIORSG9q^Q0%RSL5u4n5xCvUT9'
    'o(U+oRl@>64xry}ag)ZDZ6-Dl103~)`LLs0(9X6=u^zljJR8h;4+H?L#<Ur=!5)g8<J$@xOE;nv!|Gvx'
    '$7qZb9@;VNufzpm3QFA-v0KXrGX;!qViKQ#ixq&j=M6_+>3p8PPZxXfu-YsH;bwFyHdkXj%Vw}qI1NDc'
    'hY4C1;DMt9;DTT3VDKWbA`Vmc5)Y<q5^xO?5=EisgX<bOK?`vb_#Sw<gmCb!{n&I}%3Lp|p!_@vF0Tg|'
    'K#vR5x92++@o3=2l(>->5papz&g(AGe<5-|j$<L_egN(tC}A)pT>`QJY$D(Su(6#0{9Txu9RwVlBims<'
    '>OXLcOt5}^AdKg?s3`y%J_^Cf1J=jWLI>Pr*8<RZC=<HyU%)i=!3HB7M49b@LM0e45r-6D9-e*r?N6_s'
    'Ts{Bk&GgO7>C-1~o`3uD>i<k%UOjt$Wqbwr*@qTHnG#Pk@D8TMbD)42JoC0BU;ishcP_8*-Yu^qS;d>k'
    'I}q0@Nqst7fKtvxIJh0W+T_$(t=g>ZKx8V${*IIRl&moSVBUQqjZpev2t*i};bo*L7wssf3}C@rx=(2@'
    'q<+)VK&>VqeI_HRPSed28Ta=M0pTvQV}+nr3vDwmY1<;W3kmK*g1abzyO7{62J(9ohqOmsW#cr{wHGjb'
    's4VY;H3x$fbwB)fA*R{~dGPWbSVXsEncEP3;Y~oJ-)!QCn9iDjsK_2l5q~jDv&r4<ye<E37M5e;sR*Af'
    '*TrPoU`I6d5a|6o%t5rc!g_mo)t0uyPd77^&@wuC>@86z1_oY%O~hpRDGqi`#$Rm-{B%CUD-Z3afs4rD'
    '<)B2fFafIbdg2vXfI*hicB@$iag8viVNNJq1_9bb?IE!8)@s605pAY=L$jl)*kOGkAuXSZZT~c7-FcDD'
    'rq@`9t%LBFlST~8R>QCfn}8{!eEMEgB+S~qzW)qB&2CYY)dok5TrbiLEWi$nJj&8-Ks6*zyaG}9wScXv'
    '$$c~XfIiK4`2gjJSbr?krk}_`w##TM>4bpEZeYFYJ_gP+O%i0Ytb?%GS#}3LZG2y$?X@&^yFikb<?BtX'
    'obu=IW{fYS6wf+sogM94n6G%T{Cewbw$}<fo=WGL9CCT~q~M{8P(lsH-rJI={@yd}<vIT*UEOA_U(ZuD'
    'pK+`RaEFy4+q`-pp+gV@tqqi^SlemJ7np^1T-mnD8~szeJ^!M5$Rjq;V*L$pNb5Z=6*UE`4&Mh;Y(~0p'
    'YOd#Ba~XbW`wE^NZoBDq8?LC2QY&Y7^u>DLMm!=|v2KIcVf1@jQL5TSu<P6XhW_c*(|#}RYkt@RK(`6x'
    '8wP&w{EkSDeZE-3u78TAaNGB<QgZwC3ao#=>LjS}y%*rpNGa9n)zS&p;vLDlzxVvZat>yEw+X+#NtcQx'
    'TE8RwgRa<-9!6czG?X6g0p&Gcy~BPuts&HQ5<t2|yQMn-KwW7GJpjDk-uW(<&uszW3Q#b+<(LAE5MFKL'
    'S#9a~&5Co$G=)>vLo6)flpq4GJMmEd`Wxl`KLP!btt-tdJHvRrxxU72pDwOM^yn2?@OgV10}MdG24Br`'
    'Tdk{kB2MI=Y}hP)A}$7YgCQL4d`aJ>x4h3jR(kk5a7McG;+B*>*l}0NYXQ<l$L|5rTRK#E6V0mrFzUS7'
    '9?}kTb(_e}>;D^U@&%a>fbfQ_u6YOk+GXtyQVtYq{$~5P)Nbg(fyJBM^io+Ib>6%Ai$9XpTfXipNq-XV'
    '7}z+gyC2A+vmh?HR#!86BdFZXyV`p2PhN=pvi4HEvQ>)Z{|J83JnPJ$FJ${V(aWwQbCze{dVAs8Una?n'
    '!l2LJff<qYvWY4n`q%-mL%O{tT|VF%u!?&as%3eQi??!xqCtTAC_NRa>1v9W5zy6D?ljGBfi2cIPdU~C'
    '?D66cqSAs;&Ar4*Ukp`j+}^4j-u~{*n^*0fi(Ki-+6o<{nHYBG^<Eyv4wTL|#4ZGw0QjPvA|xP@cs9FU'
    'bVEV;%}&BBC)xAGHO%z3bBIA@*1lW;yJo$V&_WrXOw{d^SN=Nb0UW=(Fsui4Is`Z>yq>@R<EEn|tZcR0'
    'WeQ5<ilb-R1&FL|{WW3N9piW91o*xZ=KDqZe$HWNp+mbdY!SievdhGZ-!C{5>?W}`>x8djSlQgRo9|i5'
    'BJUg^+IpGaZQ{;vmyS2ulUO!=_&b@;`MOVRDn$$B+s%ye{^JU>uGgEtbaj}voozbnt;2nBI=$arX_VI7'
    '+3_tI^7*oRzT9us#Q}|IRN3cEv=chxtn|JxBs;CW>G*UD@0B`&mmYh!BbBmkD}vB{LPB*IovrL0|6PFT'
    '>c7|3TOa4R!AI+Oj8H0hkx%5ibhFC7nejR6jEx;IT~517+U6=vy9X@Q9I}4)xC&Z#RhDJOmZgdMvD2Pz'
    'Qcb77yLqCOV=VB#{<cZi<n`wEmaOjDos2gehpBvc#0$Z5cP-FFf5!Y0(d+h+^(L4q$ge2&W_HU3(`H@a'
    'p?P>iu<sygpWRS-{cjskG4gOMU3^VeT|wmc&(!6Z_7?iS(|n8_3<dHc%Qk%5<$eGplnUTD(bY^e(QGYR'
    '_JDhhrI`4t>pp9Mrgm)Ux}VT<DOd`fF_)i>=FNO(@A%jA&FaZY6aw!Gtq=!4U<T&vygzmqFjeV>N40Y@'
    'yZ!rYeZyAdeY;TgURXlH^oLNDEqy832(uz#dPCdsz4SrqsOOIY{Y7?h8-hC}Nnepo#-HA#E%o0aP)aEO'
    'eYRlf`_8~h5_!nGLoi*J>YV}9<iIO}9h|X4Tpvhf!QNjO)P;L~$lVvvuK4T>NjUBpqJM^HUi6y|0=Yu>'
    'dx2gBVVwa~rR^`Xyis$1KxjyymDY<`$11UP1ad$J<nYCbE;bpz#`t8bRNh0Q2<>nR*j2r8!VxN3<OJiC'
    'CGP3KmrP@ggEU*Kz1g$bZXF7)K{n|JsS&A7f>1N~vWV0OdY|w-#Spnz9Sr+GX~bs7w?lgW(GeO0`#J`w'
    'd9s>7*1cODU>jwKM!;2Rq8ae>55N~sHtRGa@3>~zHLqJU^d?VS;}D1ZX&u8H_OW%0&?JU+ZKb*l)&+N;'
    '0M-tF$EY1JLhb%XQ3SCl!y)=UbhzPs0C=^`VyxoRQzH6EO!L;3I>(^mVl~>@)A!qei|zq_7eN@EP;=x{'
    'srya>TN1Wh*i_dLnY4PRsSs{tK220t(o+nQN!xm=iFMTVN4)$LZ`NxV0K}#)z>Yax<Lv@i1)C9de{4z^'
    'S*}}MEw7GIuY%X$SN0YPO|XSGsSjd)IYFXIAKd*hP3>b;yi;w^cg#|4kay#Yx<Oasje~)g>}VaZDhBjm'
    'fO`XrIv_U&8g&A$1Riw(-nBaiLvAtzwE!(!fP(?<GyU`d-m&>QgRWN2L&N1lSVk9H%c!AzUSH6{Cej2i'
    'FSe+xA<a;Q9aPjo)B{`@Cl^bUv=4JT=%TQLhCx*(&jp%1edjy8YE&6c<*s<ALKb_WboDrNRA;I{LVGO)'
    '1Aof#@=5<yX{+?Ln|YDfJ#L?C)CA=lnbyMcI|KbP7V6NR&OvmkutQ&1+beq_iD}p}ckil+B!;$mu}yg*'
    'H^Ol5aVPQ!upyZlWjGpAGbGM)XzzNgPhDfl?XD{hBJpeCTJ?nVT7=CwD-w2lACgz<hWCb2-#;&xG92C)'
    'UNfWiJsd9cL$4Fv`ttgpdn2@0qLi6RBOV6oD&4HPxUE0r(7K5|`vR$OX1|l>I%}TbP_j<Y6AmGizzN{j'
    '6vGJ)Rm;0Z$B}AHh7JW;xeeMM*v{4EJZV?})_m?+PqaS87!~ny%G1gHjoXGoZZ^kGF+$ly(+R(}J5|*N'
    'og*}>NSz0wb!+TIur-7y_nk3TC5}emySE&)06#2?bRPcgwP<t>(kSh84$y2#X+0!uGO)CrW;WPe8sSz<'
    'F+FFa$J^)Wf~_u^uqja-dde{<Y5|>)(?a}DZ&3cL>dYF3$bh!f#gdBpkgL^Z*(p@jxqH+gsC&FZ?eMos'
    'T<0m;Zn2~jfELz)Hn>`Cg591}C8d1|m_IME<(@9cWfeUf=3&jO<uqomO4b6sQ5S20+^mH498fiB-{A*J'
    '`qb_Y&|x~ab7!X>P;;eskt^2IKo=@i56rDHy%5T@FVu1*{KX=}QsJ1ma0`&+rKPL%ebzHZ{03$Q@SgEx'
    'wwQISp;`e~Dpn=0&JMh7*SOHWfz;hq4vX-q$!&8?^+&N9rra@BwBHNdM|5qzU;`tZ!j7LwGL#D54>l+p'
    '*-n>g-^IHg1z$#Yubhag+)`-0*rHX3<dVg@@W52S=v)iGK}Ix#?0u)NTH{G3S@jeY2g^qFj`=F9g>ob^'
    '8bX`wlyTCgnopYVa5Rul#|V|mg|hac))>wq@@k9`l?kmcPh7~*RAFe!5k*CYM5e*hFF-F>JmD*>CWRe;'
    'R$QjsA)gMF(pouZ3%<fO+A{VU#fmNurpzLpVKx|+xjWRaR7t6X&9~&1WA7`KOxQUsqEZU;ivPZuiGax_'
    '9(;GZVRrq5eADbsa9~=cjDAbA2_M5v&4Z-VC5I0(uSP+?kD+xN%(A!z)=CD$lMhw8t!(GK>#)d_>n)fM'
    'Qd^fKZJ>fy`&k$Eo2_Yu=nH}9AqI5`8%5kSM|D3jdkEqn`?ndQHb1rzyzXOJ6(GYJk*mea%^Dm-O@~sl'
    '?RS1K(tGb6LWZvJ;EU3sjV_paFj@oJ%LdA&*OM&6a-wU_FgBbGtgWV$(vvkXd%O`hY=#wp+r}nD0ptur'
    'Hkqb4TWOXWLUyJ34KuB36gi!BRa*b)2FY=93a5P!#x%Q)JLUr^@r}lF=p6h?@Y3{M&P+q?lNxrk9boQq'
    'k#5k{U8Tt;DN#?)kw*?#((NLrTVLSYowU<%K=l+m-DVXkZ@J=YJpulPExT_`y1gS%i?GTiOq{=9T(q1!'
    'rAU}n5T`35UnPgm3%lBI(*Rr3KCPluv-9wD#YunPVYi(GdB<7jTNw>y#L{&6lq?AqSL5~Oq94G52Jb}f'
    'YtimN^Nv0+?^En(3M80PMT4HnX1lcmYGfU}-41Zz(2KS(*Nc4p!!iT*@b?WCJeMKiQ)rlS!<G99D@m3S'
    '%YuJI8PvWUbE3&NGGvJk`jX{}K7U%+P)zYc;#9|Z?9;0su|mNWSzPxhbX~0*TmscM_>{LuD4&uHR3LIz'
    'a&3B*N6}13_QiNjZ#dhW=F-ak(KIWSDgg$aWgeCgtJ^8=<i2^)JNvi9d^#e{d$6r5h~32JL*>Kj_5v|F'
    'Fd?p%tnuxNi=Kx)t`6_+#h+5JRMOQ-2CGh-v{0M*DVTTx>j7PtF9?six3{$ipKe!>H7K54WfYwC#dg-3'
    '{0Nck`XgB`0p;D32P=x?iZd+fA)FEHd^O}Gqdcu)%v+z;X&jNte6=2t>=Nh{TVhpUX_`plX~^>Uk!Kmv'
    'T}rD?Po3wJWn2&3ty_d%NQ7z<>~B_NA<LJ(rdU^W*yebWz|1IF@n@XQGQHvRQr|#qJ@x~+1MHqsdF(6('
    '9E1L5#XkL1CxDiWw<c7bVw;m3MR<!&;0WD4H2gJWj)_G~V_e1bJuG877wc#Zy1Idisb1t$)v<#L9(n$5'
    '#xS|9Z70(`+i_bjaF*T9K-|p-WL>?wN!RJ1l&f;f&262vY%^bHL$q;uV*Lb8ZDKMCaDwpv4t-Cf?kflx'
    'uI>+V=gA7M=Nzj!wpqr_sSYr=a*QiXO%vS6eT|j_`$ngIQAW)``(i5|a}4MZkE)pH53_gR!*s9lRPQeN'
    '3t7#ubxY3(RTHQei;S=Or#6)d{VZ=Vzdl_9k{pvKjbJ^;q%{44ZV%q|iMtw(G|8bFa!%4ppn<!!7MkC('
    '<}l}}MH%loV1G&h{W?rQY@9t!5%~ae+d5lA0Rn*;Q5{@{9|dxT-$kgi;Otg!tZ--h3>5o$B~ql?1yW5z'
    '7)Y=fs;8Ilu)b-JD_wO!ueRk(`zD~`F23S;H6QF0&~r?`eA`{OmcY%<%r(lLohj?OucR*F;64!AL<ih*'
    '+i^_T8UnaUCgjQQD}n4Oli1eLF#r%Uy^$D^^08lj{VwFSK#A~<;U7$eADFtof9LherBxXZcySOWsP1|U'
    'aF6p6{X^=ZzQ&xtxhidtXGr%;o84L7)8gjbU{GEAE^fuq4yY5Dqa|9L#v`saJ@0)<wt?6uK5uGbQOzE4'
    '1vlEtc<o|Jqip4pCxsO!nNk!8*O?`Z<)kz=!4av!^XWArWV%)u>2Dx5?r)v3fC^Le64uJrc=C>{$x3K|'
    'o_8L~2J0LCVLhY@b^)ZYc)ORJ&TY!=>bgd0cOm?5K=YzUf8GiZSu3h{i303*P~fL;!{EJm9%O3E^_?h&'
    'u;r<t)pr|Kt<7eaC^(TCsN&%ifNT5h1a>wN2-0o^qh9IXgRYkQBZ;W(_J7lk)fykDP;PiKZOP;6rBbQ@'
    '$n7r!q5-PN9@tl_&1{W=<SALL?$C4XC#vd`JB49bA4B6ds&f4rfDiThdX-sh2=~9<#CQ?}zrDD{R!4)%'
    '`s~2OxZ1ERg+0?erDL#X$WsPlvtq32Obn(gxLGAdUsDqq?#Vpf+`hOa*D77Vv!S@7(CZNO<xbThYZco9'
    'ZfA&P=_sZr&I83+#c(8+VClu-7O<9<j*a$($Q&U!+H{G-$uoqZ^07AkL84OL2S`^h7Vl;f19+!%wj3rb'
    'ccJ!;lr^;K*f---%FVrlo<ee_YA|f&rA8BXj$ydLvhy%yh6qtrA~?To%=^~t+=ddKZB}G({g9n$4M`Zv'
    'XEaEx?apYZ`&gNpHYvF?&l83c^Vy$R6wl<6iUI*#M`^hn_yX23WjPrJ%J?1R>x|Lm*ggS<1rmx*?6O>c'
    'w>z38A#gRLH_|Q{9&~GlH)ta_fYY}5c441*Yph_vsXQ8-70VgO#Jh_aWUE|>n=``j`4+v+ZbfUFu29tB'
    'ozjHZ9qlw19z;h_X>DFBEcMuWTN_h_hlcIE9dMc)1AV!w`#|5LbFfm2(dHiXjqKHvXv7{?7uS9nnn+Uy'
    'Hi!#$p=slS9ndG{0*2!$>AO^m(UCe)UcwMAz>p!#Kbc)C%c19$x_#gV@xd-MeKqOppij&P7(K<Z$ECFl'
    'WP_a*3}FMb9ZR970cq3)q^H|-N^whVFuYZ|915dvtfKBM3SfPYcq>2#obp!Syuoq}>%m~UpBFc}tS5<&'
    ')&T2tn}$b6MfaVrHw=g{@X#o?Diz?rr>nQwlF*Z871hVmo%mQ7vAH;WpO2(1QLzxTNC@y#krGpiq`-Wg'
    '!O^ukhF;TjsV(ukiFq{mQ^HWV;%ksFeLKX@)M>J~Yb<R})dhCm|9VUlR2}|aX}u?C^V~FPeK$*XR-m(s'
    'Y{S$~WbV|xRcZdNBoFG_<f1^BG^#~dN|S%pgs7obm1vsK{W@6*$}28fIt&1|b2}En=qtHho|RT@UjnRg'
    'J2d0-R1wo94xz6pYYuxU7olN{rdyvC{uo{>JHI4``%7-E0hy`0IJp*AB=Z|rl&twRN`~I4x=nX%pDL(%'
    '^0h{!423N2TS**TNE}?`IJhWq(Ds(qI!)&itvPaM>p3THvt8%)w@-h1_2laLPj9AgUQVy<>9glQym?}L'
    'W&Gpg*^;bp&Mu9AoT)yC)0nI=2rXsD*}0T&SaI)LoZf;gsJObDulqNg>sibbKo`I{qrT(CiSNfz=mZ{h'
    'nIBn6lCaS9tT-~`#B#ladlVk=LyOUfdCc`~%A$z!FydnEXGE|w!V~&}pM8Rl+fKI33}yEiz~aT`X?8<w'
    '&)=E36}T)29m`C7&V1YS9F~NX2PPq$Qp=3(AYsh+;1TYSkj8->n+cDoM{O1dR(<9fmt1iMs%axe@De|W'
    ';=r*SI|d|0gu{R&awFg6B=*ACvZxa{j>lpWFcWq*ja<{UJU|ekL8u7}H=D)VY-jmEEi2$&;xLMoi4xyR'
    'JQBol2=lNa+p<F&rjl5u=UL2VJRu%+cx*<Y7kh!Zv;5_JMin`;HCe6U!%+Q|E{i{M<Nzyf=OS~IjMq5h'
    'pI`jCINP@$&JKO|*B{Aj@q~hvV1TCE(6v#=$$yrbuwEMY$zS9@#>Yc|@jr9EHddlQ^QA!+cSa#3P-23('
    'Klc7RvNF^)u%E~+7oN(c@mgr)$FMaQvw0g3%SszxcyG6_FUn#5VLckRftM~`&#o6Q02`yx*tqzM@k=^m'
    '<CYUboUk%RN83xs+m8j<(%;9R{#7(+GnT8_JNy@CDXSjAq{;;S+XkfP@l`f}Q!;qQGvGtKSSbW?F71Cq'
    'LHS#Muy@~(*_<<gl8|}EdjMKht47q;U8^b43j?zZ>&M4)K46x!EZb~Z_}3lpO-kP`+xx)oKGo)yi+jF!'
    'H(R9(bVNtL{yNDhU+`BqB;(`CinpI10oY$y43`y}Ma57_aS}nHS56$;&$;;raQB*qL*SPk{uj?+l%Ico'
    '@vIL(xqQvwUf*!OZY?cNF48newAKRcQ&pmsEtWkXvYYgMCTj_114OIZ{GgrWWO}P41qd|~7>)yGl=JGh'
    '_(5qOh|Pr`_EJO36<?ASXD{C`P*kFH6u&+`1}g`Gf<>(nqeGRci9n;OMR0g_hjf<~LhGWlE;4JRhjwzD'
    '9p8BMpW-gu=s}hbHxZGSn{*CJ_`$h>YVOkbdL}|MqiYU-d{hE%@|NGdPgl(N1isQ<9?9?(_|Nz9;qiE~'
    '7T2wooAr~;8rHU)t&6z!XtLm-6^?F+rk{zpyRrU(#C$%Q$n}gT>gL57X8nd_Z{Z*Ep1_~-dr-)qj8DBr'
    'Ba~t<-gq{jt?y*xlVrwMWlSpkJm|a}nZ5*bt?d@D-#AQoj!Q&3$hDS6l!VD193;qHw&wCu#-;IK4(em#'
    'Ot9_4Kf$OW^9kb=Ot6eU827}CnBMF4-JFjmGny`5F6MV*Jg~Usqubfy?=!Z(xinn&+<?En<Jg|%^1ysu'
    'ciaZq`O-Tf`_p7enBZ*79#3LI-(IiM&4MBSz|0x8noDK#ijg@n!|}N>TO69~6~2x7n6Am<8Zbc9707`r'
    'uwFOdG+F+*)BGeOl$R-g1KJ$s=YwMT{>6Z9DR8es;M6kUun0((ToqZ)#6;U{{>m2LJ8bX0e@|Oq<IX?z'
    '#viut^=<nW`oEP-pOEFURI?A`<>lF|@q>1fc9NkRG@9l2F*v(4zAUS?@$nF1{!^Gl-)tSMk)-~m5=Q5h'
    '7}fUo^IDMUkPNRri6~!ytOELXk=%g5`JJ5S2w!h4_FK`X9TC^SDWe&zb(Pzr<AQON#X4%K<Uxc!SuO$p'
    '0HEwKN{gf=glDsiGyxGt_oKS2JE3@lGFL~Nqw%8_BtwU4GF!X@Rl<aC^~k{FFL*y6=J;ffKJZtJjeWhD'
    'p=zx9Hk<2fjKZV~;Jqxp<t;<x_%ln4FO&x`nPsBpLHmvI9e5=4ZTshQrC;9DYVZdju0a=!CO5z{s368|'
    'tcf<tVyH~fBvLAfK)-8Q5BoGlgF3*YGByZ+>T$4%`f3C+xe!iwa$|NFK!}#7`$s7+=;`1Q??vd=WbSzn'
    '+oSl&LH!^%{$>4x^U4RUW+fjSG%FBp#Yu@olcdb#mMlRWf&q*tlnk^?Yv$eibG;#8j+b}Dc|%O{e24SD'
    '+K-9G2q{N-`q7Z7P`wPs%FncknFZcPXnW--8V?x<%%oNd{p>U0v^$U0CBpeG4$+2Qt}8cUN99+>l9GD|'
    '?nUAb22fl3r}A9MA{j`=U6M6Y=D3(B5T3qYWTUFI9k5v%j}y@FdSq;tXy!a^I1d?}0N*A1tuxC1Es?AY'
    '(|f{lD<f*KO<y+1WpAEQn$&Fr069GefehN{(BgZHQ$8X--5^zC5QllEh}v4{qd}g(^zi_DwC1vbT+|W^'
    'd%d(r$Bs?+`&VZ=$kSbT^l=eu-d@X*c4UiO@F-73kpI>-#U&o#pBtFT^^RZ40d-LFQ_Dl6^6{cNc-ni+'
    'J`oQ9TTHO3L~UW?K11$J0{UpQ64j48i2Ci228{VzFAU`_$k%B)Z#&07|GC2?mnhUwu}u=0$JA$*h0}5m'
    ')6Dlu-+A5>Hs@lf*0W4D3t9`Bw-Go8Q$QXaG!GgM=~@gpKpk{K#X;HK1~U&I8gFj6u_V{rAPY2}0SWM5'
    'ur!P{e8Fbe3>9FX8{*i;AcnXiV_?RakVhb9e&6tHJ!v=E>-V!Yy+O{*HmihC*!3XyVU!H`Y(B?eef9`O'
    '$@qGW`>dD%KK~A6F+PtRfNelq4A~e2su1<DF=}9d$IVP5)WX<k5mx9NV(P1>mIHmvl2@mc-BvfluHM>o'
    'V#CU3+Gs+svHC~MTH6sjKvAN+NPglR<cbU}C_nffl()v<@!7pZ9Xkf5JI194g{50&yXZSnsZVZemo(0='
    'P0+uV`}}ch!o9$(y3t#HcWLYnsh;0G5Zpg#?i~V(Fe?_-lsGnQxAY&#Kkt6|b~R%on$9=3$fW<kKVPi*'
    '?Px+6S>mS0L*Ci#=JwLCY;QdN?cBf|Tw%~yc88O`Z_?FsLT^S}1dmHrM#rPL{3yL^G7Ij?h1^q8&_5D?'
    '79<dQBL8DDV~_eD`pM8_ezf0pqJk}9tH&VVZ?{`~vLLs-IDID{)ag5T00}w)ca=kU*B!S_8_^ZZ(6gJG'
    'Hj}cVTMM4O54~EY*PuH^zmW1&mFfK8Kz_n?DNVOvneB^ha45rB4ML*p(M?-X(mAU4MKzLIRz&?namUU9'
    '+AC|F+<IyOs7wC!5PxU;50Um0c>g)Wh*pjjKJMRMJx`8KDwuo8<r9nL7KTnW>7kaH_mv@T4-U?Js5qA8'
    '5#>g&gyyOf5?2J|m6x3$-J^rq!+2wxv+rjMCSUJ3%bL|A;uUJ#u|cvsc%*H9MkUGH_~NT=2)@0_uEHpR'
    'cvPccDddHz?T>n1lFNUT84a(M)66G0{AjVgDpkKc1rymxk>5XH1+)x;X*0d0IFb%7_#t_fFwV{mL0aQq'
    '|0?0E@KjoBp{h3}+eDP4h)67o`Solu%CJmM?rTrPU#;vsmbPaToP*f1BA#@oY<o52cA2Br2Bt(`Wi`39'
    'mTLt?)v&HQ{#xW<NsbkhAHuYs@LhV-9%c8p!tH7fhx$5jcsH3=Bz<;}U&v9vZ{%e>sU6yw`@^(K_h98c'
    '=#-8sWxqygf&QBG`T{+56kg)g3R$STk=$Dk^-)7Dq1}UW>84vc8TR)Th;P4Z4{zE}zjdi@k>6U*I~`VQ'
    'p&qI9;RkW(*`8y^uJ2LbrU~JG;`<>_Oy<WV2|SBY8-9(0z_fhZOCsO%V$0&x_NjTi(uWgpH;Mhg^n4FM'
    'kibqXY7u5~i+Zt5s7sQBI-c)Gp5=N`KtnT#Oy=@1aUz$U>BL2Iy^qK?J;tf!vyfVm&7IIDuJ7|W2@{Jk'
    '9?-~v=_a-vFyhiAbO{fApISCyEVA4-^*;P^y^o+;@1qyFW#<eGCU+yaWBWl6QinT!5@RJ35;4;ceCn~#'
    'VUcgyk>@0_>rvv8z_G2!vH&f9Y&$dxc?*Jbi&&1!V#o13?mN`<!-U3el6WkRJrdJ^1%#TW8-~>P+>k}Y'
    '^jyb@c!*d&(~FH}lGDI5{m7zjMEryUlUqSTNfZHNhcPfbOfZg}#I-pC-1v@f`L0hL0<7%%ZV<L1xmzZ='
    'H-O{^ipuU(?%@t~T{m%k6UYff4s4eI7jrXarfJ)z>-e4-SXRPpCvbr*E^tGVM1dK431u2;4q>13=O2I`'
    'GY(2n6x3aSyxmhJ=_mN|7)#~eaL&_MKZuzDPgoo{A+=2_@slWqh1tN-mgP7mi+zXrVc>A)#@u6o3X8|U'
    'W|rjvZ#y-^sJdqWzG+*)og}d-Wx%0?J8lB|#tZF`**vgq3Q{e!ohXSS+an1uabTk?2zdY!F0R9uTv)5^'
    'bI2wvn=`Vg2jW%KBz_I1uB_|PqC!ti=g9IK6pXt|qtuZ8N_^BF48~{Tl-;$x1hGf+Wnv|u`f6(%VYRfk'
    'mujXH@z=Q_?ki>o?)6mSPU6jFI?FKs8cUbJ?~C=p%b5+c{J-1tt-Y1VwnlX;f@-3t9&#4cREcn}xu`h`'
    'SbnisAFp+!i7W1fDF*UH6H9#B#}j)GDwRLbjS2G~@G9Ps48z2EfHs@`^Kimrn?Ngyb*zB{|BS}{LBV>B'
    '5qMnu15ica74tqNH6^tse6hJjJ<ZwS%#=3y3L>XNm1>9CKmGO<jyd{pDF>f?F#dmmp2>TRzMdO*`4@Na'
    'MJut3FW-nL?ReN!!J`v+!Q2TG$cG4@pk5uV)5~HJ<AOU{O-}#;`|}4dbn9^XPxn(hLD!e3^|G`+jy~JR'
    'VVRVNPt%R46Lm{IjLh>YQ&aKXg<%aFNib(VPE8uCD@3;#n=DP}JfBaCVZSuTW8*&z3&{2Oal-<7&%Jru'
    'w^4)TIV@K^nSB^-kudHdEIya4=qxJkQ&J2T6no`FC++u1o%d&(xH$5Ml`T>cC}PiM*E3OUO#$yHhuT7K'
    'x!QJkY4=pChaNtBXk2lyW$rQ~UCi%9+9jHDoaKAfcylw$46ILX+<?Sfq{cj@!sW%R%r*8Vz<kX2tJ#{j'
    'VGBx@MCLS1T1|1c${^ZjugN>kgpnqvKfsFJ)&#72kjJZtp28;9S@`e>=t_dg6=xgDe@x{Dt=5U#e$#%e'
    'rh0QosIq-6NhhA{ut^#~ziVANv&Ae$LNQj_62Cld4J?O}bE$m4ha)m$Eh+>aPS(6^MDj%4%IpDkBYd-e'
    'fOGbnW@%PNohWLl3Y|60|Ik&F^J4S0cFDRZB0WAP-K<tzSXyG4eaS1%RS+$;3|tAl8`u0I+{zJ|&#r}J'
    'xHKknuCBAUPO)rO+MryX%-^GKS){95EW#x7`e}N*gw=3GF}!^Bj>FfBYl9flB2x+ftw@<sGUu5wTTeRA'
    'upt&Q%GpT%d%hc?D2O1B_#TV@wix&_Ct3|+chjww-QLeg1t4lZ+Z!?X=aKZrBL-StU}#m{zmx3kY+0`#'
    '^#Hi`Jy|g@xsN0XwlHDw=<5cw8!*{um@%9ugot_9GSANQO?D}FaQ&2DoB6iyi`5pL<($Qxc|FQCS;tt~'
    'j={aHv30bd-WJlq`dW>w(T`+<VgMy}RUMExlSMzj=Xax>y^%{TcHn|xX|$bXl4~$z9~i*)I|#son+N0i'
    '?!fQ<XIr#(U@O^Gs}g1p?vsJ&m0L33Xv*dr6;@cDACwzVt@N4XyE$3N2uU`KY@hznTVHa1zrEk<txDd#'
    'IOr?X@=|?uZmiQanO_cxtW{AU3o6Q633U|Yqdpkx8toTcl^ktnWeFN$?FcymN0?$CIIzelSS(mQGg-;w'
    '(jWNZdVMo8$75}?KEx(l9Q7JZprVb4&&{8H0$#n1BL1-U*m<+~@<BU0at8pqK%gsz5JLvCuoMzT045km'
    'lZ7i)(aoZIW%n_<?bL2hmkU$8tCgjw=)Uf7%S8p>?Oe?s2D?;JB(2v)(FeM@B#J)xt4h#F(+H(HG%^A+'
    'nXx`<TG}hZPs&T6eO2h{_SxIbz{{r(LQ9L&hkPKVxOE&Q6p{JAU|_!Y_Qn+PQogrH7tQ9JFGmZqNafyc'
    'XP?vpGq2E2nSr^p0%iKs7S@m;zsk?<Po4hefpChqOpS%o%e?$(*qrtx>lQJF^X3ch=K~DDy1l;T(9dhQ'
    '=ksFk5DVgbh|06Yaz(zq(>$>bQqilQQX`$S3zSF(opZ9-EMaO3@jF(dm=o-6bG!z{a4lCcm7dSJh~d+l'
    '*_;7ZE)9Vva4*LLpdPf-@wnx|_=KTfnaEtx8{MRxVklL&LPe3qKifh|?~YWKIB(~mZRJBv1$LTn9>m*G'
    'PUprKop)`EaX(fgLLF$-{#f$UZ=brRY^r0jazo2wxx}XFIozToNNmTAnIBP?Mj>@M4}34ic9szj%!oTC'
    'b0Qi$krTQeF(b>1Y|G)^@myk?xXcgYI5tg(C8qECUKG*DvIq~UO{mXpGmau|lO%wTtR#$L4x^C7H$yA1'
    '&-7s7^R<a|$~nZ&{x*?&PSNmg?`u)Vr+<GVRh_9n0KQt`smOEu=W(0Pi(Srlif#OwVt@Dc&$m8vvCVO}'
    'f(_N<>z_a*Q8d#N%u2Z2UT}OVKY9Lvpwro@kc1Lh0<mBtR0ou$02I>2Kj*SG@ueVT$DS{Ffr9O+diUxT'
    'wTy7m2S)oNvT)oFI{v7R8>n_CyqK|6yE1{GZSM`^>_MESZzpsPmN+ZQT@3W=4^CcD>7VI>3neD9U2nl!'
    '0=y)f`TxbwKi2Q8?;i@`<kJ?V+p&!Xm|>%yU4sg4QghhBGPdIQJDI<IpnFt>7$zIEDa6QsID4|rCxqVv'
    'b&(vvS@_q0F^`{Ujt7BOvqx#0=>Xh$p`UuThHI&ghH9gM%INU$r6zFS^Sib!;EIG4@z$mB9Ra&a6rXK*'
    'QLvPfq3o0&z*v5HID?^f>-`oCPf$1_zu$K?)+t@(%Tntr(nHj&8_SZOmuFP`+Ob-xG{LX-rF=bxnUu(e'
    'Zibqx@i<p$mz^#NmqvYFW~V~~NnPE0oLV)`J;Q)M)v}gmM>DIVm8IRtI=PK?*u?s(LT;@VR~v)tt16Fo'
    'E>qLZ{yM4obx+pUDU7fCv%PwnUZ2JC`V5BGQRAp7DS2;};!&IFRJK?jQ><++{;{^O<?OJDDD<nkGu3ln'
    'vfnrOC0Vcu0m1fuvRR6Xlv_(~ztz~KcUZSGX*Ff60NlOx>i(yjH;1ZA@d}kPy*rsFx2*-JRCs46R%8_~'
    ');}-EJ2IQ2Whsjq))yo>^T!#WcX8dppA|t%Sn@4dy@ge)zM+g~bTwPbC~PwZD+7KvTdW_9$0uNlU7Ag9'
    ')gt>);$t;OMUGKacWlqr+eVbFX7OpVsJBqtQHY3yv;*r`dy1fCByhLBt8V4uP#ss<#o^xDuT8+kL23~s'
    'W7{T9-KIU*aksGO1-vF-x_z13Zj96#)!phlDFnCL;)M|?svzYCX;BiXThT3X{#-!BgJ{JOH+lQ<NitjE'
    'bqV83bF$9RyD0oJtesU1sXA55GvfUN1Ap;(GRdbc{~cB>t8@3`d(d_*l-+4{T_;s{pPKG~qO16}oxO&W'
    's=IsBcK567^y|9rs!p?}JD}*k=lvC2y)#-R+o}LvBwE#nXb-xh>fDJ1bWo*QH0kLSY4?I_$JJ<eE&8Y$'
    'TswSeqk1W<oIxO1q{WMeYla>y8QMv6w;Us{v6-)A8(ZvG?Yls`Di>NYAL^*ihiz3k{b=#fldfyms2Q@D'
    '0ej+8=X!xn?S5M(d{B=PFNj=+xIV=)X)z4~VkSNb?U)3n!(DDu#$tGeIi?#j<^~RlSs3_{!;<3(A1pLI'
    'FN)&8vlGfJ)8(!iJE5J#j>){3Mt&S6VPXfq4gdG!gz$uO=9)G&gV=M=^kL%jC4E@sqz~(G(#N(rEC}G2'
    'OVwRwG?Ll%=SKeT3rvl@_>1vNI%DIbSr}5B9qa<v0Ys%UTbuX9f?yTjmO3o_4Xb1pOE?Ba95&@Wtarei'
    'A6wjc<J8Yv`Il>QeW}n6V&DN7jTm0NN-?-u`8Z2g>o<2;ulR+yifpxm-<{f0i=F3a{VU$oUE)0Uk9Gj{'
    'E#20sY!UXAA?petL1twBi@fP0DRZ<RiEic|&f7g%d*`)E7r>71br^1^C;4d94N*gO;%C{2+kMj9a8X%#'
    '=goZ%i*NTKZtt*_oz`Z0ClM3(DkXXgiLNrD#o@;EmVCgjEC*pt)I+aUpmJ4BEs2ZKm*!Yj#(K~$syf9}'
    's%HmgU)UDU;5%twh{ub)pqAHaG+}L4s_$?AcvSgzTe-gafqF{N_F#tx@x<U@XYVY|9cQ*ptnYq^f3LJZ'
    '9qEq{xN+d3-PTuisrqR5xylse2Zw9*CzG1A6%KUelYv2lzS%BK+}QD?^%dScUo|vAyF<|~8Wo6G;+H}c'
    'mKq%O%wny#TqE=OgYg8E%?Jy+P8R8c_d0uP?pIYyX!z1pt&ea#sd&g7win(U9QR8x?DWF^aMTtdN*WYY'
    '=!}h~mX3QG-4%`3YLWDAE9>;|YspaM$)LE(9`xX+{M_VLN-`0lTu;_1ll3qZ`)<D)$?wKS=M$RK?2;30'
    'lFzh9_73~-q47QEOM@&7{sF@Yvo%_m;%+S2V$V?L14gn+Z$<s51&G1DqZK`u58S7Fa9~O=^D>5;4CtP1'
    '=kZYR%EKo@AKj8WgNo2PJUh$a@5P49WqWBD_(4}(s9<^C0Y>zRtMkmc@kObRl)AB(jo#nz6)5im;d4PG'
    'j2)K1f9jv^HrgjO9$=-`8rwWD{@1U+j<y4j`<*J44oXVgR|0!q2}^(ad}95WRPWkbwAG30fIg$U4AQB|'
    '=$^CJeho(tNzo%puP3*5!b_rt?lD$z%vLo;`)=-BcWx&sAU}|oVC9X~%1Gn(ResK7&&b|;zY9j?tnWoC'
    '?C_@YCjR{AroMkVIF=)%&%&r`<P!?cF3<Ke8ui<Z?GLh^g3I;r>3kDE-DGR<=~n7k`%Su>QIYz)r$G+!'
    'd4OGEXhgUd*(PzhmBhA9JouD^HcP0Tm{DZ0#0`9l`aTaM5_ou>IJ7w(*dV8v_qQ15ToBPAXMr`)_ch2l'
    '!}dcqwH(__DD^q~FZR9I_M?C$PMo-|<(bs?Y%`*^<-}$b1c?o+U{>O}7ISpW7_=8CSdP7wo~G#vbPs9Y'
    'atbCB2ZRS+6uAyh;v@<^hbB>Cai0dZ$!w3hkwt9Na(NW`LBs;v1(L+DvM{7=u8GG9w;fJ{zyz3P><6Jm'
    'T|0J&7kj2n+|ct#=tOQzT%Wis_Chb<oO!+z$3d(Y8O;ZWJmj_;xQQ7Crklj3?<Wp(yfEQj=&(2>rU`S3'
    'X-I&oB(b?me2+z;$)dy$2yJt4=#>u+qn;h7#2TwtMt;N+@;ci$VgD(|qmJov(+PlLK@iz4N7Pth90V+m'
    'l7Ld;(7*|SmI+o7U@md3#EnANJ=VU-_Y#j|*Q>;|U=w>`;3Ynfd^?Ct4qM0MNyNBqnT!O$oF4FJU{i-O'
    ';s7Q5cI}%gkuuT70Gy2{s};E$6?Jx5-r1nkYGFK9Q8U@Q=1@4cG=&|&Y?Us*!Hkb8?DoAsTDA%4Sc?BX'
    'u%Q(hpReNo6C=iCN-%M-ls|aAvrLp`&*%+jn>l}EfF~~tFk`k#cCK9I3=93^t*8wA`;}03t;Sq#Vvrd|'
    'z5mp<fYhb&{Pzu6AG?%VPsz%`f~QJl<@DV;RF}rj;>IZ+VA<x>G{yf1jG@B$-=NWqTw}Xkf%UJbt^kO$'
    '&2mGQOL?T$y&kzJbXn>zQ-ay8n2pSHlHjmXnaXaG%T#^FdzH?@StdEIu@Q|J;~Y#!*t!*3bT5{lt@#pD'
    '!o;i}=EMAlA;&QOzhYo)it-r#-?=2Hyr7INh83v=Dpbih_}%OT?fng?fA#Kvs%dvG373y8-@nM=eI?QH'
    'SbeU_aRD~)<IaP~MdRTQU$7DF&QRUBq~J3-?jKwHiqpCa(QZZc#2}mX4S1RByNU5;22Mq0%xCYg8<hxT'
    'zD5J+=NAUUp4D?KkYDr>o^+7;dA0bM&(p<q26UE@Td<&1O6Nn-xct0cpI;?^k_9UYXtfx0K1(>}fof0@'
    'vK&GW#UOyGq6vL8OigG@EWLPkX}pZFG3wUW?h7%$4|Q3;*{wc*+!ru9rR186!U*!Txi=`_n`Cy4DWyjf'
    '>5gD;Xm1?+DYXMCYr~^$d^)uU*_mRW>YX{afK;lpi<<8LWA9yi<H)iEvG4UOa&iVka)wF8`=OfZYKo$&'
    'G+lZO$*P{Qq)FT-nXP1Ic0Qz1s|5`F#cOzt^@p{+@U9IQHVhls^)76~0}PCv|6;p)XFmBa_?&wqG9xl0'
    'lkvEbRq7VIOC*yK=iYnndEax-!A|qZMkl%3nJaRY$6IYV0862Kd7^mwWc9}y`Xb%`%p_-L%TE(CdYN%O'
    't-h%r+9)iT69Q*xMfSR406p*Y4nU?R%CpLCT-E_yi&4@-`o3!V(;h0Y8f{0FJj|h?!>|aVsvxb}n!Z!q'
    'vZ_~Id7NZ*V4;Fds@fvzF_UVG9bK)uF;r!zq&-wB*;1$vu^tN6Nto%g!jblHct<XV!_?f@9ni2MDH|@-'
    '(adN(>LofG9H${@>XXLnDC~gSq;-;_$$AiU8O+Lkw6?ViYXoS;7}eWhWmN;n?#d*rs5Ut{yWe>@UQ`zt'
    '8INd5q#4gBafYmlhHmnjp3&hN>0l~ZZonh(YLZ9upSLGu6y}smU*P92Ycu7Y*R?rU9`kmA{E8U{csVOy'
    '0rpwG0<6m7?c__i;%8MA{6K20r$*`gLDJ8w^Xp$HNpG5u;Pd3C8s*D3$^Y}tBqu^YUzZ&<d;Kiiz|OXJ'
    'zgFuzsoeuR_j*AmYz?y3%mF3XViczStHDHfa-AhDVP~269E_2sT&M=8gDLt~`2EBxvjW&l^{`!|l=Ql)'
    'N~io~8hA-&yK3nR{<qblznr1ngmgd85pGJiOWQ6d(`$8vOt>Zo>W}}pQ_y>CX?s-a9Z*?nC}EN5pSP;1'
    '{7lzW?)@Y+8^5e2`_r1z<Fs5_GQjbjTA^Bb=8RrQ=9>z?<$zfubM^C4%g9a3SNB(KDbF?vSg(++Ys^)r'
    '<H8<@3f~pmU6x<vPx)ZRV2{y)zEB~jVqKK>pW20h5<?mz$Zbu#Qmh>({P+hMe%vHY<4pmYn0iHW<^4)g'
    'F8!D-%JTF2JhvPp!Bo)*Rvj+hPSx!(Y@TjcZ5ecERXHWco!x}|tb8f@R*CnEt;AdX=pj8Q%bY!=yL+4}'
    '@2Y2ht2L$2fAU4A$d<Q`8qI%`8k6y=^41awU#w}aeW~g-p{jddmLSECgU(hsY_Y#a9)+20d*4)2e_meL'
    '{;(Y<RD#L!j#LsCE}2V2c|b!!q{^AG0!KQr&j|^GFko&ZEMa-JbVU^V7K?rA5Q{pY=f<&30-M|7?pz|*'
    'V?jv$D0ZnYC?$>%ERtL@FNjD??EnV#Xza--h~0n(E)RX*jr`d6cuWXCFocGWqvu4inW@`t-tSx`Z8ufy'
    'TZdIM7G{o!cil<U;7&4+gTs=1s6eZneDwqTVWX{6iP~(LRSZV3*ntXN9OdWu$A9`o$8K1fY!CQq6I~{;'
    'waYf$afo{`xSfor^UgCm!yJ>{zV9wL7=1>r(<i`bW^QMB??v68!MeTaVXMAkkU#hBT-}J(D|d{hQ+dEA'
    '#Jrtf;(h6R>TZg@bB)>NdI&ISVCd^9L4l1YY5KGWOUe+PUA!aOeelx+GdShVQ#v^qkzt1o$!xZ|r<z{3'
    '$3r%}et&1yZ<&*f0mnva$xVghq&m)VN2lnQC9?e4aixm+4G)Y9Pjgp%S?$I0XSYRfV_E`E7-_T?0DY_K'
    '6wq)X-l!I`X*yO3I3-Sc*R@#rwDD4hvx(434?WedCE?$FXqrQA_My}4A4(3liRcx?&A+u=8mj5(Yr`|w'
    't*>VVDDq@UcB+41TLn`a$AWhhC{c-IH9@bR$D+in&>8~Z%t4esZw960VdchqMY~w#{jx`#&CVk?r!7Xh'
    '8cdn_{xoA`JiZ={QH-R(-U{-1+4ux8cvvV2n+%~&*TFiwulmIP8P-)f?mR^!;wN90Be@a>uj+9w@JVb<'
    '3j=+5!jvs|M}f>cK%&8Ou8fJXS|MgRC#h(iIhZ!Hf!adw)WLe1VSi6`lurqJJ<A^TpWb_L@ARa^U>5>w'
    '<l-x@g_z9L)n~;Zof)|mJstgDnrffxB<1O1f?{8#SF6j&n7FtzS#HAwPR==Z>BHk<Zpj~q9+mC`G{W@3'
    'FEq=pcho5XVjw%q<5C4GJuS^o692sRNu6WWyAM<IG^c-0gTe{BmafBDxW4zDTmco#fzHa#RA`pIGMC0#'
    'vOo;z^5sEFV(zDw!{_PAm0C?%AZuH<zL&-4jAnGGVheP0@WiS5`O;b-aAm-+Mfb`V+D%?qKLAAcw~&c4'
    '&osmc3Z`$=<&MOA6np?q9d>{PNdz(~ol16hjyt0<SpBfw^S9&a>ym!o`UYeno;5#S-F~P#J6uI%H|@J>'
    'N2+BHQrG2a{`VROt(ECJiQYWV3|w%)T8-d0822o9_@sY1Nm>n;Ian=Cqo>IgBwdvwO;NvH%+d=;NoxGB'
    '6wRiw5@eU;HUyw#=~PvrQf8bo6DTJc*RK%?Zr_hP4+HBGl^H@}`yig}C-BP(-H+u{A-Ld0XGLmRo7QcG'
    '?OvS$DIMNutEspij1E=f`(%3UVn-EMXd5j_!0pF{m|Pk66nYD2*obZ)uT09c-evxvF;QZL7RRoni-Qj('
    't@ot+yRykjxvyGAcTSnM88A;8>o^TXPY$tANM|-2<8>lDm%*^|0#`?7??&uqIv$M|vkqDjCuKs0OKW>M'
    '$;_!@63VT%On4Eu0C4z1dCVx8j<xfwQTz%Vv66N-7g9`h4GH<>i3FE*cJo|M`EWVmql&fe3n*l@|HsK#'
    '>olT{;IZFJo<17UhFamcQo)U7M}S$<5`erVgLLkhs*#6P3XSYUi{3tMr>yvBiTvX`3O#P%v0nB4m5R&y'
    'bqOYrRYuFJd_?&-s@zJ4;H~k_K!pYts#uF$44YLzE1uT6cR5U|U~0VOKP}r@C24p7vro1}86-(V(h3s<'
    '^ke~GzysDO^!*F4b>0k6V&KgSeg7N=Oudn}>hK0Es*{S7e*Zg4e(U=zvjtZt`A^HD%upa938EyZDX;0v'
    'y--QL=LL0twO#26cLl4aVAE@CVlJwb4LFsHo~>-FVOlD#FebFe#vXs6x>d<{C*QL%7nAAu7x(ZVkY6Vg'
    '`aS-5XKGClMXvCC*OHVGH)LT<IU}Ac8Fj2!dQwtX*f!&mQc7IOh2`4PWj2cgAw&D_)Edd8YX{P|g-5AR'
    '?U;trp?1J!NQ52OJPw!?z7P?kfwY4_3eTo-?ASt3-**noVxu_2#&@{IWE{(YM-~k|hd2SHGWM|mjTKmu'
    '+kx*#%o8rL0vi@0eb4fwkka*ICd*{lI98C&u>thftknZPh5qH93Nj6Tg^mWSdZw-#&kR-T2}DdH-xIdS'
    'oS5*~A`$fjkD}1^g&%k}w|ya*?=lkEKt5i~nHvP$^|6qaMeeHBBWdLMk;S7p3JCXrE?6L7%dt?84ddC8'
    'N7D0vDx@2PG>AQqMbx%Dm;s9<sZ^~;aoxs`$q(w=hhzM=3$BLhSarYCwNI>WwJJDOFM?Egx<Z2Iap^}@'
    '!>-IVu@gnBu=px@iCs{tQ%zf{RsiBoAA5I?tAH6M#H>0ORGb6OVpRDZcuVulx1+(l#@p)sWX0-qYlv9`'
    'l~$dAQGAGC^ggIMKU`P&=~jeRkp!zvw)?A_-q)nY_WTG@{hNRJ-~INV|NGzk?f>@w{{4UZn}72!{^4)`'
    '?SJ^Yzi%1aKRSjd*JLpI#PB~j!|Q$c#Om!J`5*t2|NOWA)xXmW|NF+_cwyrcga2@}cX=~@n<?t_Nu{@l'
    '>woy$|NS@r<lp_~fBmPw{V)HI-%ov>*3J0D@joEPuZ;J!#@upSK5>3a#(dt4*Q)*>{{CP7=I{Qe-#ZbY'
    'Z$*BR06(-*k1=A^-{zAy-#*HJ`)~e--~6lpS@ZpG|JA?#?Z5u-f6qPp<#pgsg5U=f1X&{>-H}f+pf&S<'
    'rTftd_$U9x?;F#r%4DAy{)Z#Mv((Yg==_sT66AY(BSxKf<3)$vjK?!^@<|Z1=MDV!U;O+3@IU^Y4h3Y*'
    'fdB9R`lrA7XaDve|C@jI+yDCi{KvofPk;NL{V!Tx{6By5AAgj>qU4jMiJ{;Gv_h4SD>0kT?qQLO<fmNI'
    'qvz8xUnoJN{<@|05tAfz9A-H*h;54s$MM`q`i>-#6Gk!TVH^gG1WZycnQO-`^YFx(S%J$r@fx;1T3^C*'
    'okM_K)h{tG?CF?;v;~l4xN8-Wv_0y2p7bNiXy^#|FNla6ao4l0z_J(<#1EP0`_iJ)^?786)U)u!-Hl_b'
    ')+!bgtdfu(vcqCdCzEsmIPb@|<XW6f$CE9S7G4yP$n#>~r-8#IaYL86Rvg9Bg3mnLVN!%Xi$eH;k}!-t'
    'O06*TY{6||c_p$z;y4azU`NE^k#AX{WnmL5M>-;Mg^Xxq(@+STGQugb0dpdxkr#-N&^Yi&RRmPbl{g@l'
    '&7Bz52fG6EB0zq&v@8-vuu-8K!Uox%9oak-Hh1ID65Qe3meR(aLrzcv15NWDDq=uWF%SZZ=M`6`E!2J{'
    '-n|`9`9pzqrkL18(l(bN=hSgzNF12HCwx!x(2Ia%Y}cV7Y#dBjSR@cY9*!R|D{`1{Lk|3Gb2B7eu%0Jk'
    'iWQ{i53$1O6}i@pg?BAQa7HYcGKnIfFei!v5qO@<U5hy(C0=CP5&Y;#7gy$5mPdWhmyuvz7`wbg+7ly$'
    'h=>!|IT4YV2Qg4PlQsx5Zd2EGZJ;X}aZhmK2gnYR0m4FjfrD_UhnBRh+}Vv_uV?q>@L@l_xYI{tu|E~p'
    '10a4~$Yk=aPO{KJ99Yukk#Id3+ad6<8`*?89_Jvb9U`!|munL{5FoK7W1KUW1|U7G&<h+X4XzC+xz7?('
    '?k{t9`$$@I(I;HBKQ3J9f$(h-N|%R$5Bo%@gw3|F=^w~G5NbdQw(Zy+4>>H;6CluqO9ZnBkOn+TOp^26'
    'YkRHvw9gYpEn1NWgz5k(`%>5r2&d2oIc9<0v8f*kZV?fK&<R{0{tA@oF%bbhGZ!=tDA{n&E1HODvOBZF'
    '#YBO$gv}f(LG;;i<OD2~6qLT>a~C)%jAO780_t&4OaYBt5RtY3iy-8TJ6_w1xgL%w8TNJa%nXwy)pY9e'
    'R^*Wwv<wI+kPmh&JwM<CWe2F35NrxZ09HKa@_@yT9e_dMfWopUh-Kdgf;G3m+eE4Y$$?ny&&hRvq6BNv'
    'Zc*X{!WCd6#2^boi^#zBoRBcrXEsO!4qNEB0U@C4eG4QiECv`ZvOU6xC&}Fc)r&zUJ0cEABzz!Q>bfCz'
    '$h0^}8W~1lOW9Ur0S`ES7?Hs7SZD>@3tizz!NL|0gL(7fZC{mh>g!D8BHV-oCoVbjg&m71as!V7jYdk|'
    '#2###YXSN=J{N-h<9ZQ?b-=#*L|Bo$8#f}BuI<FJ4<?l#%b1B!1_Je#L&2`}y$~=2%FYKP3*@zg=eZw('
    '<qRU*j)TY?ZYH`-W}mzvb22T)1_-3si=0@1ND5*wk1gW*Fgc65R^(Io#PgXYqY$K5<bxQ9Kzva!jkrZO'
    't%!nReiY;ySl<>0Kf?7b8E_6F&iAlPo^)MI;&rJEkYGI)L?Q9rfMd3?EwJmPd2C=<rk`A+D5aYmm<{Mn'
    'S9+46J|#Ynsm;Lp4q}kzVeAM{rM}H$%L@qOBC>2Jbi618)^KUuw(wgm43pve$%V(l?e+;1aS((ti0}aB'
    'OQV3wFoeZ~)UkXZ`k1;Q@CFCH75m&_v2?uH@&mBMc$w|y1oWHjG6z_U5(!9(BL;iUz&LRjcvvn2A!FNE'
    'tkL!?2HVWT2p;!r4ofwM6>VT)$frL|&f@AR0q}7B2!tr`h3#W|UvL+|fs_LH733P2-W;}@xG+^qfH&oU'
    '{Sxt*I2H&(+pnzzvTl3oAUt2H>7Bj-h+fBKuy+wC?U;sv7h(;~2;?!SWCy&*2=+M&!8KqqiUsD+`wqd5'
    '%dQ;+W(hW3$5%>6>%uJS<?eQ@rqmvJ;1ddlt`4lhM%^r7Z-USlA^s;N$`&w_S>$71-#CiE3j*oug9Zd_'
    'HD24g)AJCu(9Vd2gATk;hzDMeCw;UZJTNF67k<Zbp|%^j@C>J%!h<1=!<fh5r!XOWCoaK>zKAW!-M|mw'
    'U$iJe%K=+Pt_Oyjg{GNsUEc>Q+64mesElI^L_W5&_CbUNO;M8R(Yy;0zUNX7c2f|6El<Ih_r1u1iG;vX'
    'mI%O1<^d>4$ECguefS4FoG`W+I5#v19lIS`tr=(XVrenUf=T+8ARe_rhs7Zet=J~Q2R|J|t7ZGtj=11{'
    '90$w?Q4E9&J1-?K5wc;RM_mxtG)9^LJq#WmpeOJpVZgyG27|-#z~jKa=@i5`SmDA460$?jp_DX5%vvj('
    'rhH3<fT@8c5rg^TFkn~?wCG{5MaCSRJ5GW)21lL7OoB>s98k6dOcl?wh1GaDTkCH&7DzIL9R}L~-0;|m'
    'v5;}(L=0_ZVue8N@Er(Pf{Fku91JY*7raOk;&{a4ch)f8SQsC(**$dWdZ|m-OPti+(n-DL8w4w<9|Yih'
    '`k@5`WPuIL!BiCiwt<&EY=Vty&ld#jG%h7|;8B>a%^g9Un7L-SuVC_7f3#rU5vbS@sKW!ZMKC~^%>xpG'
    '`AnTCB9s#_Q>Du#sA>=F5E_GO01g2A-UW1f+~B;m>)F$;XD@X<drQ}IbN1z2&nQ4QB$gzgRJeHK%?9$3'
    ';9B#LaS4Vfh)&-QVi#<UAhazHY-{YH4sHu)q}EzeXR4>X%pQ1|J?&-Q8{kRW?Xu`@!IqGiz+MoLNiMO$'
    'FAP8hgV$sGA_zPQR)+0>>kK*<ln)wI;Du3-1ilkSmK0@N2_K_BV4+&Xr<Uyno(rfDA-BRXjKIwT*$474'
    '2tWuE&kJMVtN{KFt~z*Lpj~UB1kK2vG9#0AcXc<^XPy;v@R<n6G!XW%3LBIdc*Jqw+7?hH^Xw2PlmeZG'
    ';8KHb4g|~`ta8tdD_h3%@puSag%)wK>%$VGxyVt7!ELi#$D$w|m<$=%9H5)gZw|q%bm4D4(4`ZB>WM*u'
    'z%GJ13&5q2V8+D6kX%TXuqCXx(`U1MaP4U<I0uCrQILUAq$~_DEMi7LVS)i{$DVM&9f>?)NpM1?Pk=hX'
    'K_|Y+1<aMI(Lp!Z0hl~IB8IZBPFnjny1i=ADr~^K^c-+Lz+MX?8c{cv%wjfhOvJ&w1D_nMR~zknz&-{0'
    '!}q}lja=8_U{1EQitE9AD9GzsKP~XIEr5+u4C6|msu{JxA#z|dLMxCw0D0hnspMFIe+q)YcfeirL43h#'
    'EQd1(j8p2~Efiv~AY#VwND6t$wz(i8awtd#>47Q$3(HgI9(DjWBX~l@A^`yxJ_OTC6nJOj;c)zRJlcwf'
    '>0;E^T`~KLxeDW@4hKdNECf3&l4#~}7!ABJ&-WY`gJaT;1x($SK1|sn;HOCv$B`e{t{=N$31JupzUzC0'
    '2qzW+wLFh;&!-Gjx6fQq+JFJ{=)w5#LB0^5g&t+Zi~X2@%k5QOcV_=bs-(x=SfC;ZsSLq{0IS|3ARE9y'
    '1u6iC#|^oQog<tu6yT{kE)P(9gO6%~D-yuQ_(6$Q5n!Lhk;Qx<eY^zjdI7jq02&W8BM<%sOtSzCVgjCd'
    ';P_w;5RAvEi_>7MAAETA+4Iwj^QTw+t7rWSr~mBY;rT`93&6}agdnmK!88CTt-pK@6eovgUS}lhFJ|K%'
    'cb1c5{tfgdkxcRi1a(q%us;}KDu6m@C<kwCa>?cUgiXtVm?ft-Zv+|k$rKAp469G15K0{kf$$;&tS;Nf'
    '3XUK|IlzLsRG-pTNcE;=V7H2Z)R~Olbv9m1kZ^ywARyLtxiclAlZBR<m$u0fTu+1RX>h#^xSj^rYe?@!'
    '6jB~_ImRj8*IK~Lp)$({a{-1lYJKbstEO59d1!}%Ep$sJsr677-U;aPn+3gx^~ofNirGCa+<SxZ?Bw0;'
    'uq^#9Mz(9=d7Bta=F7>H!477{Tq^Yb9Of{afPDTAcp+`WQ+D|NVt^7_$Gz`*OEvz1fu~>%@vAZTI2Qse'
    'nwfaM+TgR{0Bcy5n+7f-g_nW?cY$cjsPcN~l#IX>OZRrASsGD|GNfTnC|nu=+OpeCU`-UZ1XnJ~U?gU<'
    '+R&W1uQ;qOB;3n0#r9`oUY!=%pnna+R}ebMq!9yyX)|mB6Y#_w@4ppTns8R`^&RIZdUhl7W^kQIz5%%&'
    'jb~u{RaoSmBwYqnLAud%5QPsE?5{QGM}zOtoB28&AREc6kA=1AOFhVH8D%A%5-_tHSZ`8b6X!XW63J{<'
    'LD+08y8@jSzMr7&QX9KfAZg3;azPV!{QS*;i;<S%vr4S9p?#O;D|QOFUb&g&wZevvQh6r3oSiL+tLP$R'
    'P=iMxWw&Sjy@z5BCgG#;^mbPI^|bcZLxC+G-aR3cQm^hv6;hjl)&|N{Y}VBmBh1~rTiKQ>1ol}uo`0M_'
    'Yf}s~nm+;xDb3?rQ8U%2RNW33kSdg#>iJ8d15agN!6V#flcWUttlDtPhBs^d3GaL{#nXeuOsT;O)pEYt'
    ';Oj8zy`AjTxiZS@zFlwVr_ayoy|~)0n$xbk-zmeu&z0X%Ddp#*IdJ_Mn!;t@$5XurQ?UNUw3490_a1{w'
    'qoq`(S2HJXqc>z${k`+=Cqppft4;XwW;{tqqVzk;Kd6cw?P077nzJ!*;9x|`(o->%OEG;jV4^&PHBJIZ'
    'w`jLi2LPzcETIN~%T*D7R5BGHTmT9Nw*oH?AcW_ucvjhcd^8n86V1{ot05LfbW9Kd*Oh1}ef=tN|4%`G'
    '%;uLjLd<K!xLjOcBioNh7b<%6oQ%Y<yo~_{AYemG2dS-A)jUy&5vL127@w+2&(&ZkM>}28*W+7JhmR9I'
    '{53cu)oF3Hl{Lt5Q_33wQbosa0a05z<Y^Pls`@b2X|p_}4dSXck&V~?9BlFt88(1$MW)xH0)1_gb_FR1'
    '3N?MR{96e()S$rSo7MDERvcC4-SovLWcpgnt4h+R${hn6XZr3NGO8?yGp^OefZeEFuI62>JowYcD$TFF'
    '6wk5Ba`{idFB;A&6X@g7U_Ky2bxXV=ab{;<n!RxC&!ikM81(!NcCxQ!6XihEu>*iZs=cONKA;+~ifb6E'
    'S$U9(w`|L)Mu6%ly(Cgo)fCMlpsK4}X_{XFS<G+F1U7f9@!~hCb%s*SwZuwY4CQRx+NvDh{`%_bd3om|'
    'Rl2%aMg?i6hTV9*mWQzcrLqmN2>~VmzG$Tg2}mR{8(fd7p&<KaC1I9s+4<-iW_nvW#E>L7Kbr!%&T1*4'
    'QDS^@)reJJl&z!(aQy1Ra6PC~A;6KN_4NHGi;9vk$7;8eF({D>fu3m<Ai7!k1H!K>#_zKC5b8>ppN+<E'
    'hXRIHI<y+WE+ZIKxJ<41?MQG%ZW?QYO88n1`$)CHtmb=WlKCqKh*n<a*9%(t?ac8;`7OReR+|5u42NP~'
    'CpI-k3+1cDfQ$O$DzmQEo8MJ+n9{AOp|^5x*H9gq_p2+7%$h4Zz8OP4U3Sfv>#cfuK!XCH)|+T2RK{86'
    'ePu{iT6@v)=?dQS<Op7S?A4A`vbL=XLe~iit;48nWpDWJ3QSf1eO<lPagGaow2H?FnL;t?M7|y`rn5%_'
    'G31r8u>q#aX;((uT#U!n1D44gX7%jxBxqe#S!M}a_nN9lPV0^2YpOnl!x4JT)m+^bgePQvQ|jF^Rd#mg'
    'e5dEv%Pj!M@h=wRIk{Zi-jeCNa)<f_CwWN{KW-_(lmR2q&aty#dT;Bp{GmV*%;bC`A-1c*tx)_ns|pV-'
    '+Z!@}Namz`Vn*)uzgU2F)aQER(E~EA3L?G1nA}Gy?_6w4M8L2|Qy`CLvxRuN%p__62?ZMXd~7<HAf(b#'
    'aSOOhY_%k&RYgPrv_#lsE{rM_Jq9DEGUn1_-RDWc^1&PNV7Qo`PE}L-s?e5_>>ErTy%fXhtdbYZc*;B^'
    'gWI1E<~Mvw-j<89Z-u2KOnnG>*;02W3t{FYOl@czZlgI!6-|^ofqn;SgEzxnB1xZ<#Y~*tj7zHSU7!-7'
    '{PV$xkKa}XmXXL!-fe>Eb*Ww%z?vL*PNw8m%*Aw82U1qB*B1us!aY5ouM22Xd{%~}%qBctc!+2o)tipG'
    '=Z=ws5jsSKR|b%mw%-kA1AVQdJ|HwC&`PVdS$7$Q6@l!~0pDaR51+^>xyI0HsVwAOqbTjr2JF1vXmNy`'
    '7HMIeti){(e8x03I7qRzTAMtJ?bfE?3S^UckOq-jBnS<I&x%NcptlLnHik&WYGc?tYM~Z8z7=jJ+&Mzw'
    'nS_Y});w85AlJQH6JQHvh(W-4X<``g`S(B<r;GU*OVt~Oz2<crhF;`}8ysSnKW$=|-9EO75sJjHDOOsS'
    '!KUDD6TrsdZy2==Mp(PLvaAfctQ{iI0;_O2dk64*?NOS9*87Ap{5Bj&f!WF?$6)GCINI9%x2u4Q=>dMJ'
    'f-okbrpRYn_q76BZ)~>Ouc;ws+Uo6(m2e}&z9hpTCG2$@gUqyT-8V!!$<0l?w?!B8ISc?|(-dIW>d*0F'
    '1gwG&NOJY9PdJ&(OWlgkkFj1yvB0maEfk7iD{s;q#PnW;MwL0Z+hdx>$H;l7#-MMQrN$s{#urV4&cz!W'
    '1JBseCSc_Z=*9rI1{O^~E(|o91e^;zngYCOcQ%GxWC$7onzaBM1Kei%nFG9G^Hm0&FII?#OHWxwy_IED'
    'P_eKsXk`-_f|u5}OspZpP?a6DEInxkcw(INCMap|rFKwnX$LifnwUI2G<oXIw|T*<ES%gm_ewQ5wnC}u'
    'ahND9m4k%#S_B4uU*Nr&`l~Wlq--<uBCVWVK253!$|IfD!qe*x^)eRLp`8subR}Vjy0BKa4ORYCvt@2x'
    'vr|b7Wm9^K@<eWw;a=l9=N-VBWM*XH7)Z^~I8ULysj<G~22N^sT?i0~50q<F6Vjy$n+d+mHLiU~o~t}x'
    '8_GKWJe%lncwKnKgj)A-I7<(;PIT9oSO44_p*>es*pdwBW}s9_byaAf$)R--dDaDzqs)3I&FiGu!lC5)'
    'hPF6_QUWc&UsDV%9I9ry#>A28nhb3UGIx=+KCq2j*J-}90&Mu)b3I4AjWKfKrOngH?VTE%LM}GP+87~g'
    'qM3xh#+^yQ36moft4NavqU+XJORx=uC%2t3<|U3n;F}jTi~!#)i%cH=ZMA4j4pJ!XOb$?NNf|vPEi$l-'
    'on{u;T?XOiOffTOqj&d|GzB}kXu|s>q0lzRV5kL5LLM*0fBy#Me^OZ5zz{Ro+x}?6RB6lUbTO$Es;b<7'
    'tP#{LUZHXLD<y976m7H4QwyM#bzlsxQJY}1t64^Aw*m9p3HG5h1v#sto5S3#nT?#rY*oodpcm?5Ban-g'
    'u$cp@BJJD!K*^li-2mE5=T>f}RRe0O^m?gcZ3ntisb*lVlxa^X)4EWzk?_Z(8CE&R#D!acq%SR9jNi^`'
    '#)z+AW&rP@kb}{nV)@q`xJ;cbeRa0sZM(vS)(xa?uCiH#FPYpb$JBfjt6<6%V@2D&z-^mu%oi*mgf{H>'
    'f!>Bpt^URaWg*#_Qtg{~H>2RQ=&qF$k(XNuT6-(Bnvh(&&KMq;Dj1c^_!r2CVvx1(^ySM_=_IR~f?{XI'
    'tJ*Q&#A;yzHyI6~#jMRZX;HZ<!*@6ew$H=}xuT1@Y@^W_&aUk>7$eGVw7EQSB}2yvhWY|gw9Js08SwO%'
    'peIuy#T09KV6&pB&?$FFr%k1_QOa3?&ykI>jJ-m!V#<Tbl1OEk1%_qn4%I7FlBvG)6}eUIW0PdU%4rd~'
    'DxMeOmy3Z4m@H`HyW0h`t0&}(X4k@jX?|zSTbf1qXl`om+&WWocqj216!hB&+O)x}i(6osXD~cPQ>9zV'
    'c1~L*t4z7tf_dj|o06mjyI|CQHii9SYdS%6Pa(RAL7l<IGH#lpx}KQb1+kI+TMW^dA6p3C^s#IbAj9&O'
    ')6uiV92`SKhf=y%d3rEXoA-7h!&G?iapus*6ihQ1T?1On21=#Z>1>9TQ0IbUY<SkNwpyZ;PUk@EbfIq8'
    'G%EnNicP56%`*(y%nZfZGP5)gvdhe`nQ67QBkfsNnf13fNQ#p-oc1jkGwe2Qm=7dFHwMq4Q}9zoOZ_(~'
    'F*UVM*05vj0CSUyOoPsIl_8rXvwLQaJW{}V-+Jl3)djxdq>Ww)NjtRmm{qB~$yChE1o#VBcH5dvdq<!a'
    'VU-h@xOmKk>Xz50NEqZ0XDT9}-wu-(c8%et0Jb4M&7;(?^Kdp5q`vR4*$IQZ5xnxPjDj*^<MHH-ObAm~'
    '<IU!x@4$iq??m&p>eOJEqj$`^4UT581$~z6LCs{d&DsHL+uE4jc2Ho`i?%S=Ub_BfnE_kq`vz;Z>yU68'
    '8YbH-W<OyiO)_d(@J*FLtxGX2O}>yIGy7mJS#H^)&<Gi-DfTo@O`OM`T|B`G1s7y=U8B%-zHV>^RNdfH'
    '+T9_0O43k)=vnEtnN=RkK1jNy$0fTFe9_LOmF=S$Rx0@oXmpmjTS824`^d?4^P)HSH$!|TBF$T{Z7PUe'
    'MCVQA!}PX?7;Tskx0bB&)l{f<jWw<gZ}Q^PF<2_&=~M@+T25M6n|T{VJc9Lru1gn$N8PL2+Ko@QbI58G'
    '&(0GH&bqgnwIM%3CA&T$lL?@_dh%dSkz5FlB|Vfgf=#=coMdFD)r@%8XVs1)lAEv5Ba+PxYJ(-FODy%J'
    '-aG?Y9#6z<MogE|THjBT=aX4nH{{k8LVFsah6MZ7l#F!w(o2SQMVm3lsf3v^G8GR68_djx&oeC#v1{5l'
    '<Q-tQP35t%7;p^gn-$yi)A|M&$#^S5RU2$hQWW7WI)x*2_t5Y+kU6Fn(WkhI{##f^f2h_`8g!n4mQ(Ge'
    'Q#HXsOBy+UGvJuqR<;T27Is|K3mnXD2O#c-4YIDD-;C$uMk!a>ZlS9>YqQ00K5L?lvlFW)aMmWKqW~?0'
    '|2Oux9d(~WNON_+lR8@~yq;35;n-#tH*FnYuH=|VFx8jH$aRgD9eiWbzR04cp?$Fuk0}OBh{vRu=r@Bm'
    ';KNj}@wDC;^E)yfVC$Be5vn3kk4G~xt)JSI-DnkGLjP>uUIUU8ldVRu&M_&?yrA2HcXQ%y4M&FL&>C`D'
    'X(doV-9`(|uSm0*^HidY_Ykn(XMlbaCLs3w?vD}q0CLs!+du&Vg&9>HT!$YOa+=>oSSP{3t=U-N2KzJ='
    '`)MUo+_fI=nt?EoA~94?&)#5t(;8R0)&V_Vl{2lIfQnpvA@FKG*eRgrxOw@uxo#tYn~j+plsg+!Hg#Vq'
    'xrBp!ptOkzxY>^Bn6T9ZaFI+%li#Nb*?q3DZK7iUAf$hzF{0&Tz5M!3$a94f<sHK}OoeZly1$+CYUR=<'
    '84q}I5GI)1^=RN8rzQHE)I+_*oWEgG+91u4u9r5uvAnb8&AG;)s`g!6iK7irEtsR3y=ccH&i8AteMz=p'
    'vs*rIDk4$C9&rvg#>#kYV#=Uw6`CfM6{m?(6$m$(C5+{y3^u`0slmhkH6o-xPcTy7KrG~Mld*stQPdLF'
    'iLG(^hRn%SX@Ht{9<m1OmH2+%qzd*D$kO7iUUE9MDOanj8l~NY@aKT$QH}n*IUu@LRP7Q4*zaJ8pSlf$'
    'x8k{xsjb)7QVd~5Q%$Sy7OdKs&8|_<k{Zb4p$))m{MLe<O%#HRTfwMT>i3{q%l*-tXzccX5yu*h59D^P'
    'c`|Lr<Eo`n@&L%~cMYNeNs&FUucnK^90kc4nNHuK=UPuxtxv8E!*G2JgKU(i`Z)k^>h;wsvse)Bzg$o}'
    '34)&<-(styMrD0AU}9XYS(d_<X}0MYY#Fl6K<sQeR)3%dGZoy-Z$({G6AA8gNEf${Z^?C%u3y<u+)(K2'
    '5Y6RItwS~{wiVpU5VO)zO;4Q%s<VpbNX)=8i^COQBP|^Z?F*GTLU6SH1c%dS2u<bV+VmTVN_`(-JbgTR'
    'Gtd~oJDr0`Ghw+2wQi)WpjF4V8Mi4nw+`Bd<Qyl1VJoj>G<D|~hHET4ckfISA)1s3PH!8Fx-~mjp@fHv'
    'DQR3kWMf)Q5{A+lH4<x^GivHS=B8#$N^Z=v#ZY28`<6xVKrd-oAV8QXEtdix!8-ap-G+uTegpX?V{|FD'
    'TfneF!m<;)F4te}j%G#(TnyNawo94^-HPEgV&npF#+YvtcFU|Wg#r8eXmGGxPD3KzTtp*V<wD(@QHIY~'
    '=xtUjT2pj|VjW(aCdB4w?Ob?J9YM9Vd7WUX2J5YC%p^S2jPo|Y8FCEF<*IH2y+`L@nk>ecdr&vBx1L0!'
    'csRMZ_FdCNnk=wJRImxn7!_=QZkY-=j+aQ^NwOFdsT0{HG@$|v8N&SK;5xA!YF??^2CfkuY(g_vlYSj^'
    '%XEOzQ!IO&SxZAQ*jPamGC<og6MAZpM!ke|wo0c|x6~TLn~o<<VbqOPtb2<JSluJu9FPX5yg4{mSgv8-'
    '7)<r^;zF0TmH6lyV3TfB^XRDRzVl$gVG|l28l_fc0{G|S>Fe2quvW8**2glP__#D;Q*rn<9m!at;!@D!'
    'Mu4A+JJDyj6_~HnIJ&lup-VQN7)!h^A|3<&lrj`9#2h3{-45}C<TP2`HP$v~(gk){|9VUjR1^MQX1y)6'
    'c`ll?xtk>$D=^tbwqWWlnLF#=sy2V8ng-1=xhfE*jcOH^GUQ(sA*!iWrJ5#GzfP8c@?5Bv4h?{9+>S*s'
    '=1Oj7XJu5|X8;>yhhluT6)~OQ5ayb)rm!b^5eCL6y7if(kLI<q(@SE=Uz)WVWTtN7<XT;kOmAE<G8fk<'
    '8EU8M7TvKuOQ5F7*9MW&6tcQ+rE$>HIOwG~=q+(j_LkLrJRWMarpO)4hl0GG8FF5i?J6%+Uj>6ypzgp-'
    '5j5;P!md`v0blQ_*L%t9Wl^?$N-I)Sa}(DC5ROayz54Lkh0{NK_VnuF^z5pC`Sq#e2c0iE2cB(3F7s?V'
    'k`eVIo5q0^d6I>m<pjj_d|?MRjqJep1J4SH6U8#{rNcc*SQyZQ&(2P-&cAwg@mKxJv(u+f&oBB9{_5)d'
    '5?~)5bi3VWQVs_r(aG&-=Xyb=eD--~ej_?lL53Z<7!G^MrJ~M^k<my@JJZEz))|aCXOB++(#z4oXPpB%'
    '9p82)WPURo(2mXo>O6;E^<R?@rXu$%T4K2mZpaMZ&waK4(T#}A45JAqkL;5&QXrj}UeEx{!__lsJE}f?'
    '2cYz5*?%vdJ-Y(r;hGNneU)0;KRN*mYCL=+4v$VIWD2&_?1l46KmX+P@zeg3^NX*}VSArEd5kZ2JrTNI'
    'Y)1iiY|o2a-{UTo9t)^PXh67RjxU)lyBjbr&d;7*JjCrotev2TK07>Ale*WzXS-Rhm4olGwJ3;$gmZhh'
    'WH9Q1Wp*ukWWfjXo&$8$v#p-xD~q^`YazTp7vIkhkB(k+<v=NyS$A_ij~+jL`1t8pIGOjd`+oZ3<pH)X'
    '9L!$=J>OTqBPFbUn=Xc8^&8S1{?_ftF%T0{(&j=x=usa(dH(F;DuY4c#>@>u;sOIm+n2HLyP;(>O1K|z'
    'i`!Nh2Q0D@44ysv?)>5uz&^itcDbB6G8m$aG9LOK<(|#qKk9PA9fx>s;Mg|fQ7nWP(!dYzE9o#%jg5Qh'
    'EscAbyTU!hUGI7dRxgN*`_}^41Rf=mLGQJAcR%#g={&YwXJam17W<(aQjhsw6xk&7Vuz8?q1?4)5W%mm'
    '<#C(adLFZ1F0g_Ej6LrS(Z_*(<pWYQuxlp+KYIMldH><#ug)*C$P9eTacShia--O%GGML@cqCZhMV2Qx'
    'l?()p#|wZwKfU@IL1?N2iD0`?(z#vbM(Y#el&Lg{Z9-X5^`ZVF3e!V7^o{{3iz#vx_Hj$>%`SZUb8&V<'
    '=3vrc0BEhyNcVUJq|;p)e~<N#<zE%Vk#1x~R4_>?@?;Qs4A|3h1dj-JB}ic&+kyb4z+!Fcaf<=zMX^N$'
    'A>E@4xI@QtVd5(AKVHl}{`J7K5zIVkU)-l;j%Uk@35wSK?1q2_!<ChA5SN(*gfaY<$)_(`yBSyn5FzZ?'
    'qMU#XWEQO0L-9c(+Yx{l9y<c$G-2>_#2w2HSnPSs<u3PPPk2jY9BtBbRx+-}1R1%>e;^Fk`RT(3|GuA&'
    '-@dRwRAzvo%pAW(sae2D`neBT#dY@V+vm@o!qooq>f4L+ty3ga_^uyWv2TY=P}d0^2Lx>_BcItG^`%cE'
    '8u0KwdZlOM#bi9XSd0+EkF>JUgtxf_6!+^3P^Jg0;L!JvJCS|dv2E+9VD9=~HYBrI=c`1OZJu`=rZ&O}'
    '{(44c;^_WrJT7EM8;2?!A$WgqJpx-4C`Dft1jW^-<Hd*{&csk=U&SwsO%B8i(DedmeS)s-<nSoJj6@H2'
    'Pf~rWhsZ0{li6ele?}@jJjxG}`5MShZX7b=ozZx%KO82X!e7aB4hRQhr2B{6qgQ!wxQ-LRnV8PcL0JqB'
    'hhlV?Ead386FWyGo}Y>N@|{vIB@dr4z~%g~Sn~oPyCR%Tm018}D6R>6hnu8g$!d4>Pq01d76NMZXNXVS'
    'w&FP+cZ$YT8=+svffEqhm}~WL@?eqqwDC}pC@HhGdi8)7Z+(+;c+ijC-y}VxBMo`BpvXgN58i#D{yn;1'
    'OskohT!?G&y?*DoGnL)HexI}3KHPut*Z2SA%a<=-ynOlU)t_#Nh!=J*e)YnFfBxi;x?4Cy^Xaj2F<=ZZ'
    'D33M!eWBN<nd`87e;a_zbf1prk4J|fl@S;kr2y?iDyWWAa;X64<$?9`pz|jk&jK)IfEGw6G|>CXK<|t1'
    'nNUSIXMGA*IQ))&i8dPgN`CZ#bozXZHG%uewds$<+qC$@9b)YLk5`O+C_(E5j8sJUnRl<I3sLmi$zTTL'
    'o)dF-j1TThS1F@`1m_WVsQYTC6LY*3Kl<x^7f>qj@HgFFZ9id%?~NFd5ff-ijbN-dBL4_{u6!66o(?z{'
    'Ks<{yn_LAz^u%?sBp8DXyB`XKLt;v7&b^eFKwAF-ZImwl)P1FSQh$O!bzhZ`9vZjm9nIwkXTyCyssaa@'
    '5219|M9ntgkVul00WvGvPWmr0tL*eT_N$T;OoALIdK(WFLx>SpMFPM3<VJkY2iJ&OplUTjhVRp@f3*!6'
    '3kjY-ECjuBcsJ*VtKT!8xcYtRi<cC3dW6a{vTJpfc<lUX2P8E7TMo`*Gz5_*ct6>nTk`$kbcypFjECZ9'
    'nr>m|i!X9J3d7swW%~vpE^)UVx4C)OQz<2e9nWvXw1=Z^?B=!+Gb24B!<jfFqj!gi{>+HtAoN2n!2@!w'
    'C?G7dD2u$9OFs%RPQVBukz;WQ%C^wbI@+%0RNzcgcs~s>srcOO1cesH_Y!@V7kVlxSE$*h<SmfK-66eY'
    'v~1n&N?2S!q_}Q8{{o*qI^ja|Wq!mIZax?X^C*z7qs1*1(__HAI!8I~fE0q?)S|SsOt7)Vp(`bZmC)5A'
    'ZIibN2f-xsLQKEalKjdnZwu**?<as5!Ep!kaMRt=sLJnAZkUqOPB-mEvJ<afz)paQNN2DG&L4Ij0F|nM'
    'IJ~^TkhrE=jnVlyiIr>Dvh(Mc&z`~)V#tq`x$}z!>?{GnHD}oHx$}k$7osD8_1*&Wij$I)&yZR7J<89l'
    'ZFMr$KXi|~DBHRpx`6ukXjm^7_n{m^W(-dZ^@DM#4M1gGYTZ2Rqx=Du1+g>hkEhxm{oVDP-|zM(H$tMx'
    'pWl5rF7)P(nhm!hste+}O2r<1(B@%@IpA0+O>gl*3uMY2UV8$tz*E1&nM+>W>CWMdmGV;*w9SvZ!}RWy'
    '^4m%P(Tn+TUq`~#yi~Zm0jOjySp{DkNIHwbNb89sl=X%n{V77)rg1jalv>Xh>fdcI6`DipjnXE~rbs!N'
    'k8g({QN;HHj27;&PEgK)>ov>x;QhfYF-Xwo#s^R);ioJ4SR6UrLFL7Pr>#U^pv*Mr(kEDVLe!J&Ry*jr'
    '6YAk=)gTHEH{3B8G4#9Ze)mdoG*%ByqdrEWJq5tfCsHQEbavb!6w~lJ3afZ1l&%_K=Z|H#5-uBH#B!Z<'
    '^GaN?(eH;E-^F^HvE3ScSN6oV65nk<*fqguuHC&ez;#FT94EW9aKLtcQGm=>1?ELFW!+d&XH=QOv)0kK'
    'ye5o#+Ig!!b*;KDI)%Eomfo$VbBpL>w~d%TA?W@!M*B%mzIu;4TK{w)%@J6O-)#uayw966g<kEH(GLiF'
    'EkFQajri&8W-#e6b@;5L(k=MBN#fL0VEn!_nSxXI%LTTe2U8fhE<3^9+5qz*DU8;+MVB#wM;5RRqd5kf'
    '1+ND0{QJoOERzlf$;6xSYxt2&FsuwllA670@I75j(EDDfD?hW2n*3Ct-v}1K0OyfpPTjyOLp02jxO2fo'
    'iqw)iC+;WdNLl|<bwN>PRVH$?3<!-!!*{>8K4rJ)biJGPEVrCG?sn|9y!0dU?Y67jvIz>MpeAZ}cP>LI'
    'NP2~34jN3HKpM426SmCS*>@o%%R##j++_M<mN$U9AD%z>_N%)sk@R&<axV|MC{KD}_vHc5ovYvO7K^@v'
    'oB4b)yMOPVmOh}O)k?tqBUl#so(?P@9H;9CVBPJ&Zpmw*y60hf)BVnS_4m$)GOz0$I{5bDn@gc8*{#3S'
    'juVS%x>%p@-Aq?0MPaI(*U4Zs+TyF?T|DeXweEA>Ea<)TZ?gn*y}@{P@=i@=D>eLLOaWB-X3FunP&O5F'
    'Fcx6_C_i4<uU3Bq{nW!$o}Nl#T|Hy%*3lC&O)3SdcXWInb8+uu4l~za(y8oLno`W!O^<_;y1Cy0yA0QH'
    'bl2cB*pME>)|n$L>I1_{+`}?&r<=RV(<Lf6{ZnBvFO;5)sBi<}#EdiBa+n{AAY#;KR9Yh9cJUx6_|-9k'
    'jy8kre{tCT>haY#=chlr?0<KDaryY!Q*;TU6URGobJ=}czB2EhKRtc$jXsq+e|mL^aP)d>f%*3NH_uKV'
    '_D?Ua9zQxgyUIX&wOcc3*$2z~aKH2N;JsSv2apqYU_CjHL=qW{7NQ680j!|$H1}Rnn0zrDF1u^Y=3)Z8'
    'wU`N&p+Tmaza$w9u^tjQ;rrn-oJS#>;a9ISBDdmx=Muz$%H!9jtKhxyV&0)3(%4OMZ1yh0j)f!Ox5j)r'
    'yAi|T{SGCw8+aZ;?q-gen0I<&G44zT6M?ub^%mL-Xr=YubW*13{Nx@NZ|;o%2c<yZvN|tccK_&b3E>U0'
    '`FL~$p8`5w9%#-{<aQ^#mj_EQ@I$AEU3T&Gu-5}wK3DyazHs2T;rO~Yp3G-obbGzry^G#$=j-#+hoJik'
    'M@v?WMsXMS;^Y_O!ALncIkR}Rhl$aPw&tC->`qS7UR^pqI(EGt84iC9^B+t>DC#>A@at%-?;gy44SvJ$'
    '*Ke=I{MRpE>i^IFWDfR1_h>Wk6Xw_NBN6xec!uBY>m;duH^WxT)KC1A;*X=xo?kpurx<vx=KL?O`j4MJ'
    '|Mp7Xd{Oqza6!L9uSVt9V3~`|?W5ck>a^RzdOeha8k?wn3Lo2D!a~=tP6DmErU6*UPhix1`3-%26K8$~'
    '?%^1ane;wV*T&asYpfn#Ewi9!Os-V`&i!mWo`Qi+@{3SUZA|g<MnxEwPyNLLHen#&oqUh<j5ieTCD#;B'
    'CiHv!Q9ZW0JDT3krbCgxFj{nLGrRDgiFY9I_(Op?yKMdb{jU4f55bw8UXkm<%btaGwbRZ$xL9=1Gxbc0'
    'UoX4?29xizWcGay{xzHHTS>QL%+unD^^)9GD-G$jMns<{n5g=G#%{X%)n%SNrbJBpb8?-(YufBSc-1=o'
    'rTS|Tt&uVCP#x7f+jQ-!m!6PJAGMv-v!K%fzZR9>#S+^hz3f{s>GV2fmN}j;_jDV5X5U(g2ap1M!R962'
    'TW6-CR*&2I92As(Z*UENvys5Mkox-S>Ur6hp1mC@HplYg+Z&SUd!ooky_Ao72_N>Be5fyt7Co9}x$INR'
    'PKk=Udca*h&0WQf67@?7iRvS{gwoe9`zCjJmE~8=8p|tM33VkeY>`<T9JKTPSE+~cm&EeV>oW7KuY<06'
    'aQdbr_+6@)a>{OUDrPsSp?>!Zn#XoLuH|O(PI}>f_HH!45jZh?50rXo2&Jc4@K(9G?!2qL`FNUTw~lA9'
    'qE0WszthIk>SFTyT7u+$=O7Fn&#{CnnC<zY2mY-caN@+2`9e6<jzVEul;KrGTi9MK{MZXU+X`J5{$P=&'
    'IvS_o+BUahmjtnNoY=O!NXF8NY}*pj_8gz_DDuFMx5LOLlsXZ!+>qJSw}=yjZWYl6!v(G#JFZ7b7&6Z#'
    'Qn1L6g4m%fmeR6ZypI=#9`z$Z{K&V0n1s~jEVh^ke2<keAz>IVj4hi)9+fPTk~lJmIU|7`5$bUf2pSUG'
    'w`ItfV@Z%v++#G1VYQTT8pU2sodP3M&+~2J66%DW<48Y<sB1IZ_N2osCYfuwuFo9LwteOX(zZit%K&yi'
    'c0${at?B{_1{GfHNWwT5+!A3B*na5PJhm*nBX2vQ8&TrLmhdf?5E|Gd6x{b>5>SVDG$PG)FiawLh;0*~'
    'S&zBQ^BgHdD#L&W4iTP+T-O#B54n$*^11Kx*p5X^JlnPG$l}a1XffhG*aG;<7K8;33rG-JaTLH%(v|`+'
    '?Q%d83rR#GM=;@Y$vNzMK!g<u&t-N=Z3QDq*Ws3JIYLk$_=B<_4yf(MZWI$=1i-JJ6*#U8{Wy$6S4tSp'
    '3!(r6STG%{y7-1ceLrv=0i5f&e&9sZ_q{NJ{RFP`VKr_LQy@6s<1nBH{4JR4;!RgziGYW~Z>shY!yusI'
    '7zUuB<@p?MgNm4mkTOfawo;H>k~yx+0va>eV$Y2v_iUg0ERJau)>H~GvI7t!9)&VyUf^@?h=2)6nQMox'
    '2Qm_bmhF-#0C_@U5yU>RVhMEa5<rX<*!64-7}(~nV-cXDzy;=wiQ_nt?GrzMjkhU7=@NuKND|BE0;WbB'
    '3wFaIvG2s8@5Tl+Da<0`uoeN>wLB6s;Q%Q)6f{Td2SmC+4Xzha>B<P$jDQ4kEh#LIQY#ejzhoA5tb7>T'
    '@;m|Kf~e#?3;@+J;5-f`&@-d34Zz<P<v<rqz<6O0Sum#<Hi?9hB%GA??{Tcq3Vav1C$wW~bMA&TVtAru'
    '+sq;XlL81J2!xcjD~T0w&=nC40@ouzjFD{YI4V+e1b3vvL0;P&Rv5<~s7TNoHV9fE!!V9PsCy)c7!j2C'
    'F|$C9guWHA2=GxhG6F-nfghkIkesm4A$};C<pWS6S!jdqqMT7XbRr%yK&NHLK=dKEB#2y3QYxBw4#>^~'
    'Bz5dkPCSB_!L1;I?F$0Ok73b1tdPc5Ac1ok=usAV@Ru--Jd3-a$X!;|P)0(wXdr0}1K2|PF{u0?AOs{S'
    'DlU+p6vQ$pj}SPSxB~VVNKW_+mJGHBa8$`q42(o#CjbM+A#sFv*Ckj{lmfjt)UjN^I81}W0;Nw_OerXB'
    '2TxFAAEX9wwoA%JkZ>ptq93?k!lqfE+88KePCXXE<`Njja%|!WhXJX^4sdb^^Kfk$NiakRah)dN3T0Bd'
    'HtbpybIXrh%z+FD4MF~ZS_97U1xN)JL=ka74S`Gsdxv-~2em;#V^dN#aD^*H#<v+rTTrhk?m{360Sv(-'
    'uxWf>Mj@zq&<d1+QV0VJY%msBo&^*gOW(T7t-&FJ$mWg%b{qu?aYL{;Bd{`n^dt#f*8)C>L+XVVNFrf@'
    ')x&He!C;kP2y~R_*7{KxG_63KGsS5^0EVyN9_%KNitA7xIA1!piziSp#Q+2@$i>LVXKi2(pNC;s&nd@^'
    '3@ijJBy6GdWawh%D)DX4mB^^Dha9L>3fO=c*a1vuD{w;_D>R5mh@fHE5M>|OaT3UvxE$OQ2P7VtO`v4J'
    'oQ3^}?EuUT6a<k4h8_^H<$974DLs$E&&03bm81Lt8zln5i6bx-9L7EFL_lFcSDpo8H?nXlmctzqO2-3L'
    '>jxmHd;vB)(1j$`BEo1wft?)3!sVeI2sZ|a?NHE^E~rm{9H3?cZ-={)Z^Jfwu=kz^eiw65+1tXY>P0K>'
    '2gnEfE5}CH1caLlzk0ZruIq(_!-j)C19LqD4FfC$%nG&y4N%K~mE$h8$@XwP8l>Pr0-J#V<vv)lT(K!9'
    'v5Rt+2s;4n0;1RRsRjNHS~EWU7la@ed>8D~dLb_Ky1>G4K!13knp_SR7`OwL4MsM2LKc{WfeXsnhCc!G'
    '!pb7Bl6-JDZD3u-z!|LSyrY2dC3vVFuwH0MFgZQT2XW_uAhQVrHwc_$1|&o*7IBVV2vD&Del(!NVnC*i'
    'B9|~e0~a{<!0-aDbA8te0Iy&b0(^m*65OlM;UL=q-(Y{*jPa0C^pIjA2@rgh_!%0YpzU$<zybn;6Bv|('
    'm+5ox(ZR0)3&aB62r2k51l(BSdteAtffNVG4x}aOp9Y}1mVxl1h*5xT@c<kvaGY%dtiqhgA}}P6nM2Xy'
    '21W|NLbOAW$J}#$5?ZdP70*$Y2^i4a^F7xhb_^Cl$PlZHJ3(v%>Bb@Gb_p(sZ-p=vy8Sjt5CRqgP+?-3'
    '+<mTtBT)`!jQ}BU1EGKq@5P{$L0iknf~CU}eH%nPLxo_+K0XfWLHOVa37ZCClk);3CIOZ!8YrOgTw#fb'
    'dce9M30x@xffgmmL}^(df<jM#B$ghy*02wO1vW7Ct3|U^up+c0utIE*c@(haIUY!g&;w4fkewV5hrqrZ'
    '*bBUN&@Y~6N1z0pz!%_Nlgh^wXw`$4<^h?yA$k(F0AmSUBkBX8h7p+0p%1Q$9|bmvT#Ph<Vgb<{3l92?'
    'fC*miKoWTcL|N>@D|TQ-9MuPKJcw@LfSComB}3|iq!PphGX>D?10FyKg9BlM5h1OE4|r&Lb$)hr{;>c2'
    '!C&?-p8Z?}`@j^zs{{H@rV_YJx^^Ia8%!+fg9@XtK57SChA3{q07Pd6PzJmcND#GBfPWl=8o-!=uQdsX'
    'Q!&i|HDX=eEJm+q0PRIOYlQrAuK(8!?Ne}6d^D;oP(U6yujl8XA1Arj#Z?`bZwIHRkG!)WI`_^VfCxPI'
    '&w-Xa@2uS0-l-pgk>o_-qu})Xk#C=Y+H<XvV~4SQ9z1wtIcE=D*Lh$$aeV4}WoI5n?xQmwFczGH0Exp#'
    '5B>Noe(0BbJ35DX+u&nAaN>s#9)|8|bPB$`tKQBR#?+hI6z7dl-U#EXmz`7ZQFsn^$s=$I<1;UObPo8A'
    '+)^*s*sVsJRdTOB<Th)QLv(Ef%plR_wQ?#GTqA9dbU(k7Xp(XjS5qMrxIep|ju(@k-1+8*yB^q%*<~fO'
    'o%0&Zh?)>cw?`nTFN73Rf%R2NtZ7JQ^Pi2zZ%6p%)w_vanqDbeHi}k|b~8m|G}p%RT}VFIP5L`=+yKQj'
    'FuWVk62Z0I!5<F$-lIq1L+gS6(0^cg=kBA^)AKld=$}@`{)5F}$Ptqz)*|&zsaLmdf76xK<K6wz)tw?T'
    'GmT4~#H8^2{D#a*NfC-qpQ_`9CuH^-VL4!hd664<VTt!~r)J${t<*czfgPWp#r`8aZUZCFJ$>-#6l0qu'
    'O%`y`&m-`u{09#n1!n-r_s+w(tif|?+vh;Y&cg@s!!UHtA3Tg6#o#fQFdOP(xgnA(;5cJtY~$B5>bl1M'
    'G}@k$yYu1Ix+}1%N#5A@&t+z+g6EIEdG_o=)gr|b(iEH<^!*PH+}LtR;8Ae3iF89Z0QU^68%kXoP@6ay'
    '<cS<STX$>*Pf3SiA#EXTaGj{+2ggUsC(zEdA&_~*9@sWxj&Lj{Tqoj;0thB4qaL2EgIj0E7TCQJ3vKR6'
    'kA>hy+8Csu1mhVrI8al>Scu6br;c|kYwjEf6%U~pehOSzB5^G|=yWZ{z*&#MGmAY5{$?z>ZCjCN!BQRY'
    'gYlHsv3xgKv<`%*IeJcLg?L$-IZ_gfAuPdyASM7A0J@$eP7rVrT7imE3Ws~##}gwf5FR+@M;|`>3={RS'
    'qq>;Rl8c2{kV%zLJMIh#6~m+ZYAwkX$HSz25LRtU3xwtU(pSfwgKtN#QF&mB^<*gKBE5gv8H^^2IS4H*'
    '#iM{L*!sSOs<QN1dJzNNQcS;|3N<&b3e+Xe>Z@c<_@&0iGDz^3WF`l%mW7o*?`U<jd?3+It0$I#(gmu?'
    'B=@HjIJHh2R`mprQAXGIreY%SVrfU=ORuRjn~>4Q!m^9ga8-W<CN$*ZWOjH9pa{w8l@*%vK?TI~S&H8Y'
    'UZcVK%~(2XjQ3BGfd$`~kv_Q4llct3{;+ed7BL}!<S9nsCt^B(2hUB&U<z-(1MH4Rs#?=>H&vmF*$rR-'
    'Pk!}9*USt~KD#)7e){;L|NP>-s7C`09UcQGI3CA{pznk(@qj!%X4#?7J%?GIZv&&rC}sf=HnZ>;-{L$Z'
    'VF&^s3;*I<)ubUKZNYa7JUoqo*Ew_D(DFhNfme&ivLPM}N=JHu?ZJRNCd3xNkuWxM;dxKypr?X213r%N'
    'pqzUicU&y##<=BBVS$=tGN8=kp|rRk$DSM7B$Add9lW;?1rhaQ!E)dqJ%0Mt`Ni{#$4{}Y`~f(xwjWuJ'
    '6_eQUiH!onXQ3q=CkEliER5i|Fdz>pK=V9M783P{LwwIA@e=msvu`iX&ijv_;-#f?ttYaLOK--D>znyQ'
    'Ayw=5&4cEG02YWD%D74o33%i<0jDUmP>BJqgD7Hzve0oHFD9G^9<gnYdl3joCvYi`OZ5ZkY??TkDG0!g'
    '@V$^?YETGb4lpY%*OAo4^JgMxU`HW#HNYSjp+0vkDs0<{WekL6)tEwIaBNjP8JHhSuzmaO<A+$cZ7^bF'
    'I#Op3_d5qw2P>Wd!p1Uq>IC<GC)q*VujF#%m&c}t8mOCi^LM#X)FIB}<S$=tw_+=fmBk^Rtm@T09?d}}'
    'VzD}7_<Km^<mIUP))(5^TXx<MR`TGpw1mU7G02jv%z!Q+&Q?&fq*LS5ZiU*n6MGv2B<z#W{f7pGUrOew'
    'dWo0n8j>+Vv?dS+w-d~t0V%A<dG#^!a|TZzC0P}10yw>Exz^_@J@IS|-&AApY`eumv%&`N$qT>>!s9}4'
    'sKDI;PYe7nFxI3UMU)CKCn#7P9{in$AqQuOOAZbVB|eEN62gW}fywlqD?=Vd1W*0I;-Z1$aLK^w#QbB-'
    'kccc25sq2lEU>|k_w0y=k%LxG)$t1ril06qgV8A_z+tTqGVJKi9R@b>pm<+aeQ1ry(1T|boQF4fC-E7@'
    ';dUJ?R3*UKe7XRL*`}*N<Vr-#0S;+$u)Uad`?BfwX3&+e=9-#eE1BIIv+RXeT4I%ba!Q+8vwah|*#2$F'
    'a&66QZP#XP*Rp8CTHUWURcZ2{l<6mB`bnAokgW1amwwWvpLFR~U8<e)O4qFl9CQ;Gu$l(`ZM^K@GcUq('
    'S1XM1#z5p*F(Vd@F_}GxeGxmv3mh*FIg8Y}PRQ{X1%8lq=1}OUt7G?7T_iK%u1@!`MD?U@lZaPF;<vJd'
    'WCi7pmyT5pM<ekmL$fa%!7?`UZkc*n-6pZyoJEX>{Dx?CS-?1R-n%R{uxu7|Y-~7eDwUK2G($3o{ciV>'
    's_O?rQMJKZO2JO=C&p&3lLJ;65IS|EBZuSh^z+UL(;7O&*l1Y1bOaFbj^YU{&@9Gq7eH7%C-a*_wIgQ1'
    '4`e6Fcu>$g_l%+C>+^4(pI;QTD?94^!55}S(Mba4h;>;TcS;5`(fJN@HqNo==HbCvl24;ZxNB%Q#1D`V'
    'ill474~|SpJH5#uFm#he!+YG_y2nZ7O?vS1<>(JhVd>xzDm9@opG%L?3~x-%YI$)Fa3;9tYq@dKc{CmW'
    'N{l+mR+&N}q2o8$jcraalknsvI+tl>(rzn^uBpK&7e2ap_8*-;wS)ft*)iFbHn{OEnI#!rdUG_H4c{4O'
    '&t;i_{*qHoAx;C#v!hNsOYX4Vd;Z`rjWMWrGafF~{ol^B>EK$0HN+6~?Wl)o%I)yZV7A&J6hA$%y?XdV'
    '!c3+Xw<;Ih22-xnKnwiY2iAP@_!3KL|8R_IYB$CyeIe)DcIQS60f%{hHMOXg_&&)LUEZ-yYjw|8=9no0'
    'xYs%R=GzDTuODAtJ-hg;BBRVKVb2y5Y(8L6kS&{`9!S6zR#~Iip|qcjv`o!4t~HYZPOioLFl+C8vSK%e'
    'OL#Ed{Fba))uWi)id7?AOjb9w6^c(TPJf<k#t9glx4<8U{or<8FT_rP&y}L91p?bbWSRhs(HCs|E!yO('
    '@ImHMgIcs%N=tSLA**uq30-5Yeq+G{4f6$#@#=SClhod%sG_=mQfoWZ8V_}=RJvK`HB&1Daya|;Le;dr'
    'JUh)?w%DtRFhv+?ob2OO3(4J%i)TN-Y*#O|ZZzp@st2!5CgaJW#+s?Ucsj;5g+GKOORv6}m1GK4o#dWg'
    'tEy&s8E`s&n`}z^mcfc$47&gmYBG*drs$zz?@Tp4+8ZanfK?cFUc~ovF;ZtM<~)`2@1A}0?G;84v@pC('
    '=53P0K>!xqZAFpNHRjMKnAsQvl!&n?V&>NDi{4O-4l~0pZ_~aqHl7l>>jT_3MpE6o1+P(O662D~^|Tdw'
    'Sq3Z<Mmz*+Hg|%WN^bz#YP5xmp)o;Kl4{M8RS~<l!tHDKxZ83@`ud8yx;bz5yi?hsSmQ!nz<&1gy*dQx'
    'fqK{6;RF+^*)K9XD%|V^`nDVd)md1X^WQ#y{_NsPh4U`kG33>FxTsb5U~lGdQZu0)#~wDTRa+QES}r!y'
    'N__f-W~Ynu(}(H72ol4qj%kL?j-WZVt%Ibc=t(WkHssI6`C4s>k5m4ni9y>+c$l|3R0WW9XUvg6!&|wT'
    '97S{aYWq!BGn}nfB3aF3&dI@DxoT<b%+PSAQ`OqdRBJWTyO%t*Zu4C3`{oj0?~M2w^y6B~Y-=;IZNGVK'
    '`$=otXI9%DlG@tNX=^*BZLb+^`%7qRIiGE>>1_MWX4`8ro7r5pJ*KklEt73uiEMk!W9zoV?R(2&+hY=2'
    'D>-a?Phs0%2HWqkecN`<TkE+Et!KQop76G}e7C)3QtdI@Z9mCwd&qU$?*{ED)2-F;$B!V-Z4YT~d&_cb'
    'FUf6BdZ5h|H}e^8KR|+8i}`JPO>f&%cH91v+xC;&W<0fRubFMe6WjKj*S3+?)^0l5Ub4~lk&L$IT(p)`'
    '(e|5()>a}~i99sJ(UbPl&<tmx?K=sr^&GT4q@e971FiK0wEg9O>@EFlpV?>oN<Q0b?%6(4&)UyC+iT)k'
    '>v?DUOgn2m>uirgXMZ_oZKj+ZH0*D&(cnU=Lp611WH9+M=X54Vhgav9TId?g^IzpW8N92tKHqiU)_CzA'
    'HB!>J>d0J5VY0oqri6iRe4FoRf1)CnjLgL~o;^;-<hDN**Mr$yM=y=_X}Z-aNVRCoWj1QN-Kca;6DW-`'
    '#lhCOx5gl?@W&nOVb-;2Lptq8I2~k(=-7C2)Vj#XRld!fDWu5(vl}s#{n;ECHBA)QTK<+WMu_X#OgfR}'
    'k|6RzX2(JVq0d7~V{QdBa&7Kf7PE;T@L1Ydcvf&OY2b^x@@u08E({;ImL1w5<pH(0EoBgRfy1a}1tPNS'
    '$ags*F^NJcIo7`o!k9%|&>)UIDr-+<XA3+-;$K@OGd3Me=3g9MJbQL^FWJ87Vr08fU#QBcePk|GDRuK8'
    '$XJqm-Visrz=LFg`rEP<XkxskJc6B7m)%K^GwoJaAKHx-V}W)wyxJepZZ4N+&;a<st$>^<uoyAIZUkSU'
    ')UYYg8dIb^v2_K9`hla5W+i60`$J>)&Wh_l%qOj>>finIrw<K_ksZSr#Pg3Cn!!rj+B{2R^B5*X2FYhO'
    'axy0dtG_H+qucHNOo)lf|JR+NlP=dL6$IgAf`l{6ggQEOyclsZeWy}>OzME;<t7^X821?5l51hKQuY#i'
    '^Xa?$?TD)+kkT53VV8(a0yDoB@jVlhdFONnl!ZD`?>(6rU70|jZEb`K(V2vt3HO1eaHuAKbY$LSQGi!Y'
    'lCog#<t>=RTiVhxWGZgQ;5gmgIfU9mxWX2MftM11J7UEVx-im~!U=7c2e!{b5|PLeO!yqUmMHcDBCJSw'
    'F0&1&rd<w|6;q%2q3y(;=Wr5Wr*-XAQE;M|<49@oAolFY^J9lbf#rjv=Ll+ruqs;^p59J3%d{u5H7bL5'
    'NlxBQ2e84~5>GzLT|Y}ro0a{(77}0CGW(eIiV`23UY_^2&E?39(^S@#+RK(5m=+H|Qa@+6_tXAB`|+>t'
    '&^h~|r~(<V-8U<c4nH#SP)Ry~PW<rM#rgBo#~1x&GVm%Fwetn2x$=FE3Y8*f4rN?08F>MZ94Fw^ig_Gx'
    '88U$lr5T|tbR5Tv3Fm=FY}?~r6gsvOxRl4$CD?}I6Mkd~-wP@CeI62vOGik{btHA;AdZQkfgOdRWiu97'
    '9-%&WED9RWiDhhuzExuiJC$4OEh0Pn>k`@7W24AUsa}zW25Q=JvQS61(DbmgkG_YUZLJT@fNrUQVyDF('
    'ik-IGD0bTJq}XYvF>z-z%b-x^y%w+!m-FdhbZxF0O<o{?wFJf+tm%aw=her^&lx;@lw?)335hFSvI$|K'
    'Sz$+!i0lwNX-Om74w=tc5X6>agCiR;&+(b%TX7svO9Y`465={OwJbpbLBYkXNC=x9Is;BTSB5-_h;Rt8'
    'eU}D~!zB~8&ttrN%fajbXP;XV%%8xPz76AYm@-;DRmb0IQ2bQ)1QtB$2>gajb>5M|2HnM*wCZhat_}41'
    'Y9`ac8*sSPs&2t<9hzMbEaVA7HMamH`Lwveevp5XZP{#aCoVBvAh!WCF;v%j9zQg*GA$4cHW5d!<Z$1_'
    'Z>HJ$4@fgdMuvQEwii6mnmk!;C8*fdFP|Hkuo_`m2jq(-*M6=AjhT$2gVn6nYQ*>RlUuVA2fz9&)`WR0'
    '&OKBvIvJ`k`+cJ{dctnT114rCaxk6E58vL1DU4v401O3xvZDUEQ2g)&urmeB%uZBk7BqMd|HwLdgNQQ2'
    '3tz0L>0~_QY70)}kj$TuN$34umt|%_AI$FUhodh~28M2jDxe1EmsNP_CSC#Crbf7FI=^0!Dc7brdD|%<'
    '95ec5>ERiYYvt$<^E`|UCx$ZtoRb^}cmMCd`RCn^VWLc6!<0`@On1Kg(x8!Z2rj@_SE^9EaNHr_5`BC1'
    'C^|ts^y6d&WC1$n;D64>x1#giK)f|g{ZGl8!L_nNKxwhpZ77jP<LPZ1aFxL+O&bY=SyCF~FckzxZB5>k'
    'hW&<6us%3impE^xzk@;0LAiPOMocN}@U2-J1VJAuM!i&~4^YtIi5L+IGdb#fIBpMR%FDwg-#4Vn6_&b_'
    'oXM^Xtdk^%u4_gG%n><H$t~Dw-Cbdqt|6P@=*LaA+tEH_<B2ejbQ9q2*tio3%y)Rg$V54I?QMV|!MEX2'
    '3})xIlli;WIZNOuA1Pn`xY-KS?KxpLhwEDlYOJGw><mWjO6LcQ`FuPwL_;~xS}y>6m(GW!4rq5R`1N&b'
    'wozL|@SU3RAsG&?N4LrtI2o$sh-+=l)INpDAHlRA``%0Fdw-GdRs!Fx#J%?)_HHYJTq1z{!y(RuN-`7r'
    '-CN{$FM;1y<G$wn{C3@ZgO`p{s$S8v(!`fHLIA&N3&RNateY*soJkzcEcj(~&nTjm2umXf_YKo=L1^N*'
    'Gsm)}KNCiBY7Pobbu~iQJf4)7*XqnuKT<gxt&WtqGsba5CX?YijB{kjKz(*N;6_&SM^;w*twLTOjyr5P'
    '#@d+gO-o}0n+dL&2~!vp$!4J3yLYd1c|)dxC)GxK<I(V4=iA389ZfmvzS$e)j~PYqtn(T#(#^z#OwoRw'
    'znj1u=45&;<}*WetwDv~lF@v?W+z6F_0uP0Fgj(rK#(@OXY=X8NEe`8n(Mx4Ws6q0Np1LIi!qr*YxMV5'
    'W}S$oy3P11e}4Jw>6b=_$!N(3<FQ#kXr&X={Kl28F_-apuu?1L(gT-kNF@KE27QFB_r4ns_);t%8u1(w'
    'sOFsL-APLZ6OJ<8;@<hq2=#2|vtz?1B=VPG(_|Ni85k!8y3S$8DO>zh%ov%V7Bw*1Rvuf8a;W}jU@U}x'
    ')M>+E*Ce`(k<JXd>ItQytDgM$xgK;$r)GTiB{=iwNeLDvn*L}GK`HG6@bt$7K`8;7!A}Y;0j_ufAgk}m'
    'XNqzSMNklw(Vf^wmfS&mxp9V5<9>k5IF%UJMn2qL)8P(27~M^S$#8}PgZoK^+nx!xOn_S@ubH61{n4AD'
    '^tbl1-*zRxZ6vN47_PP4w~sC)-b&(IOL=caX>TjjtDPb6Yg=NOi6blXxoLY%P1{Fi+MW{A_M1O*U@+dh'
    '@u4A<e=}xeIQW&|S_Ff|eVE$yN2W1u;zVNaIceKc(%Q%(+qxyGH+1wdGC^y*kfwiSvc8NtRfZDB?#>&_'
    '_=!dg&bHFV_LeoahorGPbH-{{B-mD8Z2jv)yZLo3f^QMD=7~eXbU~5#rZRtZ6_F*IwRXasP2k*e)ciYh'
    'TL2r!PH#Wm7HCI6bq-GWV5Y42!)zeY%ze7iV0d&w7`BEO(7|vpf2XU-$bp#d-tLwV_o0(S9gGt#$oc6U'
    't9#7JPyqR~AiX~PIPW5#jFw*i6`ledZfE8s>**uBgVF*$o?tP3N~Wf$QA2w?7q^G1a^J0?umbEbBO@k;'
    'L$$}JOsCkInRTLxyIK_|19eS7-<2VS|1*36{6}}+^@F)v39TA{2m6QK9^@k95)DH$2cs+7QX7=3kIWf;'
    'KXe?<pvm{U6NfY8khW*;{m|B4o5tQAY`uearIQKLDKzv7f{1A{$VV90HBX5~&Ae?^UZI6%<V301Ks)ZF'
    '>P^{IsCs^UDG0xlDe#%BZmF(%u_2kw44(d9Vta^!8+JyxPhST`hE6VonhWG6x$W6|fcHD80>Tju2aR{v'
    'yVixOjhKA9YF(Qw{@ZTl-x4*hlOnxlhZ+hp6Q<FV7yy~;r{CZ(#wV{YnA~rVyR{j1rG_y+`;Yj}M!JMO'
    '+}rqI^oB!nslL@4@$5!*{94^TFbbUx$L#g}&Vzy4=|9V?<N^NWC+4nIJYUe^V0I&TniB{v(fmlINf{Vo'
    'l2b%kwPg6J#+EHVHgiP1w$;b!{+PHzv2BZ6$>mS4!K?3SVt2YcQzzmHxCFdH6%47q|HxBe_o`~XY$eH7'
    '?W{`4SxiNuqLp4YbFJ$SzUYhw!{dx%#(NLbcVF%YXNMeZG9w$L5vAZAXQlb_$Artxl*B$zuuk4i$z&pu'
    'H2DEPY9ms)w;brrC7HTOpeaj>jt43`Jf9~GB-l=t^xUiwXf|z`ydi@jI&u19E1)CcK+Ti}N0W;Y>x?I2'
    'ba>Q?kjk0`7<XNY6eE!`#L4l>?=f>{X@^|R-eTC}6@-icYvC$_S@z0rc;`gfY=(PdC0nE$vOiwIJ~r9Y'
    'D5Zn(cnbSMREIPT-EbUYbDR{sd7ZI}M3~j9PZoN|FB166AV+dp#K34tWJ7&BUfOSo3^0x;lg|8ZUp^TL'
    'c*MN11A={;a9#K7)64$V=~vw&!#B@cwg!`13Tm*!RN|YsCk!~r%GDp^4JM_WR~4K3rfbY)OUU(pl9(E;'
    'X#>0=*~xZQfM5UkkIm8i5>Yvwy&O#m4kPLlCcQM!a0ROctyGbrGv+Od4n{S)P0JM|8qVnK3pA*qea}#m'
    'R+z2LdpST`h))%>(G?V`W<$9DVJz3I_|Rs!;SFia|36vGWppBj>HvFo{>ud!u0&JT34Z)gJ!(o&{SJf('
    '3eluu1wU4my}J95Mv+@o+--R6g;gRAdF{zHu*|*|SKBaCnJ}?A@YYr<Avi?J2rt|3CpM}m3vcvmoS8{D'
    '8s{wGm2b7ict85kgOOWJCB+@?xv4Pwnnrt{-3_2CMP6nxwU!<JW0j+NnpwAJP4pRY1m&Gx%6roXq@5&;'
    'YZ_s|R)Z;?|Ge)M4QF;Rs?RgG?$4K|stc|TPBXxNVp#F%K&6s<?=w|w(xn|6EA&;=9BT8-!$bn!=PAHt'
    'o%B}n<!2gaz(;>%nGW$UXZ}7@nk;{<<>+@k@6mV_+q`9QJ_5tVcoEx=yc345L0T~PcG^m8OG5pWIirC8'
    'pqVrMTpJ4`g-MsBb(r;+?<YFQ9DCgA?cI^`U@qa|==ZY(Sk^``-gIQrMt2<i+PJfq88k@-Frf*L_jQBr'
    'W(;P*rweqZBABa7bAOPn=#idz+<ogUug?@owQ%X}WTraD4Cdn2beojaw^>@6=u$2Dd@yQF_b1J8%vu?&'
    'uuWCQiZ;JB7_lOwYp~U2n;9RtE&bz8-_Vw1C}8PIw}PC9z+j;GO<j{~ciulzzo@k?9|auQx_|T$`xc*?'
    '9#+EpN7wUk+d__iIJAB0c-Vf&!%v+Kn-lY=PKS3IL%#!^4%fV$kE++<+T2_1cDOdyr+$Z}Y5Ak*cW9)x'
    'Yiso$?(V5<rg&UCB_H-$^Pz0f2NNUd!V$ZxKA0G1bz`H|vJVyNJ{Txe*Lrc3R(a)jxH^h?*z3hsjE}I3'
    '1zSMX$6v?AIP|=D`2X8`)9yBs<WTfGe+5kYToBU`RQo~=$EHYVn%8Pcm!#TbvuT`KvLv`cfCj);YxMNr'
    'U*uMmS(UW`1&ZpyOdpX1sxl)ZBO_yv@8mY!W%;E2WxBsi|3H`NzS7wKF5Tay-{da6{rdIba{TV};&Srt'
    'ay+?u`~LE5Jh^=PA6GzTU;3x__s`kNuRksxK73rCql7dSUCdWw;&U9WK24J~@QF8zIRb7YzN3r}NMGRh'
    '@nrQeFl-028r}1dr@NkklF-w2H?rf%aeU3tBg60_%djKO)_mUyHRQO48w93dhnj{02ZfgIwPbgc$BFZY'
    'T3|U^6gf6RRv0*bhz#5GHQ&+_04@ws5XWKc85VpWyKb!6W}L*K;e~-6w4VRt!~EA3Onj5?;<9@$SiLIK'
    '-A(l<j<DT$!gk{dt4Dt4&ag%;<hz)r!#4Cg^WfFvzZ-e*8`4ZSjcYoV^mpwGd>m(>Y=OpoJAYqy=M{Y1'
    'j^0I2*$#Spci(H~@w<D=8Miy>^ZmGuzB>v$+DWVLPMe?Le;%jVcSX1Fg1@-4K6Bj_-FoE4-#hI5UD^7('
    'J0VACAHK8R-<=<YorQ_)xc&F8`hP1MfOjk;s8Soh?5-tX7vq+-C*MJD@yBg0{_Q(icGzD057o(Xw`k`P'
    'Jl|i>!5#D%FKsfu6OE$Fj^$Nb%mSyr%X9U#j}>oxp5I!WX3}Z<@&^6OyKS4?+g$_m$LnDJ7%j}}dzg3B'
    'Ve;`ZKz3^S-lu>(1+(|Ab3iH#$lnfe`z(;%XMuEX_uXfM?6X12@AN-FHi)VN{P&RyqSPaIk_n<xXZCp@'
    '4Y=|5kO#8;D9@ii?_GTimM8|U{;-VDv&DS&x%d8J)T5Ns3+8d}H=>Vqir`i6SA_227QYXcSbkl9z6Tg+'
    '`O6iVw393RE|{;U(Q5SFWW=j(uFg~9zw;i7kJLYrg#2Z<B(B-t>Dbww$m@7zcMbofi#o9BwX%brij4Cg'
    '(V<CigP#}EIAzO6T~(&Uqjp?#t~6+=!+;|}TYU8M)^Ycd{5czTEJEV*)v;(&b;3F+FGmN>pRgf67XOA;'
    'QE-oM(GF%SJ!9D{N94;6=ECFeq~aet1*wg6)uF1+C>5*f>{r$;Go{mRboO+(?$N^u7S}juzjlWpPWv!8'
    '|CJ$#6L2^9;iIv^$ytDr$<G%;aoLV6D0rw&cj7Uk<odgdjqAEZ-Q!2bk-)fJ#KS#mI9$Kma%LR{!|kxy'
    '@9sk3$|K>@0Jto8t&^t9k4A4Dg}?1C`mHMXtq{1@MVZ@O#lC%aCh?sFzU?UPO%?W*iC(*z0{^cpu&fK0'
    'Rrj%Jj~bfx7?Ej@6qxq?mkaJtCL<_+y@-O@^zSI9EEpv2BQDnuy2f}H9*IYfNh=FU+eH*v>6UP9Xz)EA'
    'f}QOG5C0OPzPf98Hl6R3ccyV;f}Yrkz`3iiu}6y<dxW5|+L*CUs<~7>_jR}Nbvqn>heH?I9CQ@<OKUu&'
    '$82XFW-)-X#MS(V$rf15lj-tqpDnN(1|{}%5Dkgl<kQWkv-+M8%I)3};=b~ZYMm1;>n%Q7t%Dgl9PEO7'
    'eSMm_$fJ3x^<QHzz)|^OW>HVyVGha;=y9}OEM{RxogRQ1>1Y>gba!+=3nFyaky!zDI11(wn$5@_pGMvF'
    '*zEP$O?*hNVm8rXSEE-&NOjd@Q?PkIxqR2J-DM^0Q~>Nh{^+|KStVR{)b&!5EvZ16ebk-M_pR-49g2K^'
    '96MY`3hC~|y>Bh;?NZo#1X-`YTkg~a=_my~g%OblgM5c}-5oTe>r%`slk$`jS|=VQwSYG4@#~GqRru<8'
    'dLamZ^gd_%YP8}eedB7h!(#c^j#|T46>a__)OgL8Z0>fd846aYYxFPyKuAA*ji>1xc$#3c!!Bx647(=N'
    'bPoM@oU_4~@CbPuUpvikC~4*1aV}1-rF*BNv-abqt=+pzt9bVi&Zeu6DCRMNpc1VIBuuJ<Dek3<NW7Lh'
    'PSq&c@?keF>fBa$*&e=hi+2*s&(q+^PafFKm)Dg?oDIi@C#Zrc$<HSq3j3&6&A;v>$d<N(#vwTmOT?~d'
    'axZt2*7Z*(z4>%D6fS0*_pto@uaASXqZrF%9rny7;|)b_p8m>Cc{e4o`(&)qrzLJ|&BElT@n9F0%14WV'
    'E-tC7Oae+-ly$r$(cyBOG?3tKqNLZ|3W42*EeF2^(-~IcXksg%gPlNnC_9`jd6-AN#XXuI4R*q$M6m$d'
    'T~n6QiKPtVWSHqa-Q+A)@KrI3;Sp011O~Q)RD^Dim%QP<5s}$C?(oF62$7B?7uncC&!_I_V6j-jz67NA'
    '2_3y-J4A6FK799gMrMiV_Fnzzf$sPv8$UI2uw;=AW@DBO@?)6FZ;S_Yj;Jn``D$IB%>-wpdtnC{`;wiy'
    '!yiwtCfBEbJsfnLdA?(5kYy>5$&NV3?;=kaa3b>6r<lP+F6XRb)1>Pfb7Bd(XMbU$#?Ed7oFUm0yDGq+'
    '|L6a7NAoG7q&qvEjWCW*u1^3u70~bsvIS*VQAa-Jl8X*z?R1;c6|ftwQ|J{pXh-`lP!hc`cLsMl!LAU`'
    'FXm2HpuCzp!u_|ATt)Ul#qf?dWLNtC=wY3BBQzrp?A7>xAA(uNnnWe|;+#C%6{GqCm<W_;BDR93dSz$1'
    '58R5p!;5<tTD!7JWJg*%O9K=3Rb6ePo63Yt=D=B7J2Amwq|9-${o~k131#7oeu}eh0*)4vB%JA1xr6uQ'
    'O%I)9H8o^+c+a~sv*&KKFXC<hT@mu?7E`(C@Tba0DVU<#lVg3ID1u3?mhz=*2WgL)al1ws9INRP`+vUl'
    'RMT}kSxEhvrTg=*T~!y%9H+wIf9d$*qlQYt_r3^KZ1~cKofZ00HHRwtJh}+Ld%*`x>!j}_UVcS!2IuHs'
    'w60D3Ddb;-(qwX4%ixb5_t<$ATUoLg&p~kMyol|0-U)-&AXUJ=o3;{VL8$x488Y}cjhvZCZ7ez|Oq!C`'
    'k*F^pvpcA}<8eo~w<6@ByMTwmKV}IqQAX&z>B#*qy5r#g6>|23Nm(#J7dPSXu`=jBE<h~UC(w0e!OW88'
    '{z<Ip!F?X}S#R=vMo4N0NpGVS=^Qg%qr0x#q;TCPl{B$Rm7eqId}nt*YlhRUlo2W0R0&da_gjN4R>AxO'
    '$m+>1BR=r9OoqKlM_VFLK&ndb1Uct$z~JKVDot*;a6eJKXlGqM6en`$`q6i+TkM-2w!-^&*YmJ!A;WKn'
    'wtdIL-FH0PcRJjjnD?CyYlWddK&Qi;w)0)}I?Tbo({6{kx%T}I8`JW4(eLo<?bojdm*aP*7nhTFm*dIR'
    '`*-i&US7k+^re4|R_oPsa+?Rh7C)ls*VXeid^m|fRQv#RF<CBxyU7xLn1Vb{F8R^@XIzcT(-JERk&}dh'
    '6DJOebw{%T6u7Y)C$XU=v2VMv<NASvEL*cQJ+S=P2t6&b6FmuVMX-wbKg<?kFq^DE7mGd$(4c7X8(My5'
    'K<H5%*uLj^dVstrc1*(!J(QS+VVZ8@dQo6$v6ncJ;U@-w=7pXWTE1p$F|vI<sR05GNHU!vm^FweNidx~'
    'Eb$+Ai#3`A@!gaJO)^jt-`A`#j4dlR%rFXqDAtS+X^!Pai4#Uv>?T@l`@Utmdf+9Rofs$%BG2(c+eZ-r'
    '1s7>qJ&$G&;Us!kt>GeFPGZm-v10YPFr}x3fPUZh9UUcr1{63>5NHO{G*9<U7&nGhBiD1Zz(i&e#IA$v'
    'NJ|1OFbv-nrd$&o(4B|X!gQ0>N04kLD{K{?e1zR!q*xCkSe|L=QDS(S88{v+QTGvYTswBd(2q4I^h`ZA'
    'H7(Ku+ll=|cVj<5ah!yXjcTx7w)_&rhdM$g(oqmOM&tyJtNET|YB~@ZGF;t^9o>%HzzaMBMF>z5$DVIF'
    '0n$8VnUPMQIlaGs&V+;OkBf&7AJ^w7A^nRM^VOJ`H%6;Z(`1cjj3XnAViYBw<;0$0IB}@?u@A?<jgaej'
    'Kz3o|8irx{K^!|)pzBs_d9I-wjv2;&KRu7H$EU9*?@q6Oyn^F+)B=j31hUc+%AOp+T&L$3Z^l<wFw^DL'
    'cye}n_TzYR@#g0-{_Ds0Z~h(6esk2H-rX;j>)!vYumY4U7k9v_??3n0$1y_p_;2<Vjx`{(!@r*`AK;uu'
    'A94K&08bjMKL8{j_5Uq>=IAc?eKq|%I?)-+?8hkSP40u`3dPj515`npyd1L!FhgUGb3Ev1wg}=Cd4fG4'
    '|G?vA<17~IlgqbnugPe`n(ryF!hC$`M@j%;e*AwtAZ-Vmeobep0=(?S!EMH}-@dwdjrZ%_`)hHxIFl#4'
    'K~B?1K24(<M$R`5HWF`1OxWCXj#jG)1xG+U5p>9hOrbd}ee385Bl0<8EX#+vZh8}HA<Uk|XLm3ne3e93'
    '9SsH}(hUb40agw%-VO`%wj3CD2_d5aG7m74%Rwe|My^}h9tm49e?#i$$YaT3*&~H1hdo*V9a}n=2(Bg|'
    'kD~@Bj!j1dBWauy`u7OUDK_{Q=?Ce1(}eUCiWUzbOp})eI1yDpmgI(IFkOK<hP8z8a=BO@_218boi9FN'
    'aM|j5gsPX%2zEHSSN8#&goA7tj2ArL5|N5uM-te>o=%^=pU!a(Ccq1fD-LF}qh)w_^sje=|2}*B=KAvV'
    '?0Rzb<Eddgn2wHav}b<sEV=#SSYHSIe*p<M#V{#XIX}YV(Pe=|*NdkgfToW`Fz^F6+U>CS@)ToQo+L%u'
    'fQ&&NxqScT&G?c%aC}gYr)Y6^KSOJj(vOI_B?7XA-xf=TtgPG90i`+sG?*?^Sz<cBf54JO`kp|1byQWx'
    '5IP{HCHmh7Y@jYs)Cr&-*f~cA3AOC8#W2F@ku~*#m^iUFAewTVrC8!8@IF|7q*S6fua(bps=}X;bdEN{'
    'Rsl~LB@z^|y}5e({_-q6=~p*+uG<@0!WIOo04T11OR$L(OVB5vrIflbAU%+|?m0sHGRQy*>RCkK2p)mP'
    '2+2&yW?>kIl>iRO1kJZ1z5QtOLOTC%tc|E*D{{}Lq)zt+{eDjhfC>vddw+R3esj&Cy?py0S0n6BglnR>'
    '6J*evegaY}7SF?A4GII@{Z;>Vglkri<>77Oa}}!*_o-hj<^)a%`#I1#Y{&XDXNt?kCtQg52LWM(=`E)V'
    'Y+4kxtPFIDWRY#t=clXQo5dW|QfwxyUPW#Q9G7_9=oMn`y#G8(B^WYwehU^e5&MFY*cR&#_gJDxDP2ZB'
    'J2G`=mE7{Z=M=@Vh%jisZxkZcrZrkYibX)tf#Uo#K1vB&<OCRrxywifzJJCKemq@KrB=L6QrWaOU*Jl0'
    'SpPz?e8-Sk%a3U?{hh2V&k2V;mb{xDOt!xQb4)?U%E__nmcUQt#{tgv)AV=D)L8#I20|~BYxBH{A+U<e'
    '<b>uyfs?ZvT?Q4?^hu4#mmT0Or52d1c$H@23%)~p!94CUVI>uHg=10JlTu`Y<U5zHS-MpCw<r{qQ)4C?'
    'mECQ4Q8|j1WT&A(!y@I%aN^iDd_ap^&ySR_lU%mRQ5_W{n#fV<JE;J4ba;Mob@mqSyZ@a0IDY*Oz<+h|'
    '=C9++cb6A$uobL-2(01s{HKentBbd9q%VKy9rh0gMPZ5D=Z(h}@YiJUq9jJwl8RzKVYy`fA*Bm0jIrRD'
    '0%3^q7Z<#k9HzI~e7-r&cArC4yZv0^Xdv=2UWc`C@u(=}kb1eLLJrxz0Fp`6bM&c3yrA0%s$>qNqF_NT'
    '@^2wlqzsVb6Jzo8{Cs@QMG0!=Dq@d6+~_(MsGp#%{B|#2yz++6(E@A)hH3ma;FwI&+Jpuw#UYqOsTnY('
    'lUiY!Y85W0@ds43Uf6sJEhiI-b+%m%Xrde~b)-=yGL^$~&|Ll!Z-m?I6v(`&#dv3@*Qc-F{xv@y|5zBW'
    'R?_3I=A=A<FDA>y-_e|Ec9%w5k#55Lb2+{>WGodsm6tK-c^T`<u|WBV=9peug9Z~i8!@A6dLd^I-SqJ%'
    '{o5Bk%6s8E3TkSFgdyj_9kE#8M{kaw>9@z()AW}c{76Ps<b@OZJUsq_m2;OTrl0jCKF6Pf8+LU+n?|TF'
    '8@<xPh~l&_dMjLkL>`@d)F<C9?(<(Q?uBW~X@bsnLxwuWZ{1P?5yoO&62%i9!rdOjbu*i;){??6FG3u)'
    '$ab?C$aeH^2lA1X1_Z1<kQfyid=W<gIG{J%NV0n*4G!}UB`)}=P1l>A0<vbx%U0_pWsEWg<ekR;pWkq&'
    'NzBBQ^ptTb@$1G|ONjV_W-&Wi7zOl*l{5YoV#o4^ym?DD9)Cz)98|5JywHmmcfnM&w2Gr)C+(aBy^Ei+'
    'Wr;_Q%=Wbz-x6eylv8owsH1Nh;fnt4xfK!2LE@U;1s{q=_2vS6xjI%SZ&z8ATk2&>l_00Xzhgo!FnZiS'
    '9q%Su5rn~ry)|Hy*(FkIB6hmaY9oXK89wKW<sEHbl9$&TX&4NA_$>sTqNdeW{g8joKkyeAG-s>L*%-40'
    '4D(ks2u?#uu}j5xitQMN03m1|%qDQiVA*StbV%_DT)epd%lw~va7~Z@`WE22e0%!S<kjWd{~EvH67kFN'
    'UoYP9sEJv?-l~3Q{N|j$v3f{Ab;0i({xS!~GnwGCHJK3BGnwE+I+^s3f0^TlALi3F_O6Za$Hd2UpjO=o'
    '_yVD2-(U!tN+;746L6mc34ka=EL#*kTub0s>fHs)UttgWgZ$(->6)*{KfQYme@x!KdUZ9vKE551>tyw5'
    'y8g(4<8T4}($5L<eqb0G<iP_TTmjP}RruNa3_5=GmO;igdp=!ZxdR_jVp@Mjer1p-kIKz48TvK_Sj7ah'
    'm)OxheRmD2NeawgF(B1eI_^j1D_%UTSJN1=^PR3=R(EkgBm<Ko;0LlEiuhx;T)IX=54UWIF)3sUpNxn>'
    '^9YYK7~y{loQymyP}mfR2j-ds^B`XlGY}r>6v*nsoNjmeB4&D2&Jf0s@8IHi{Ec*IoR>uhRy@KAH}u)b'
    'yM$wU1p@Om=B(@({@3e^mlN!q^Xy!s!2XyMT1NE`K%F6Mz#M_>1mD7!aj*^mk`-%j&9G0ezL;T>Jv%{g'
    'Yh_Cjq+*U$Va05OAr?^ZU0x0ihXgyF2{;S}E{juMH=!B<w`{QCbEY^B2mLhn3WZm?s5p=^;y_-Dg85=j'
    '?(+1wVs8`N<tuzV<&(?c&E7d-ycaH&hI@xCV!%$x8~xG$EPyqpFwuAg{2lPMC13f?^mzJ%r-9V;0}0&7'
    '%wa^jnG*je$yd^bglO4&uos>-7?7C;bV_`F3Ve{t&h(t!5{oro-Z1YuK!vR(L`9NlWvNHJ>qH3%exJrT'
    'S}MKISX4)Ltt}SoArr&d{r1njYb+%&P4ONy*Jotj6bkqf+pcMt$ND327p$jqEK^Xyn=>Xh9NShDL?3(W'
    '=^Yw@<er)eaj^PxCV)K`1W~}l@_sp`#>Dsm<gwm#JrZQMqjw;k6Zi+c=RJvU%08MLj~2{oCv_M8fm*8&'
    '#MM)_V$PE@sVbf(30#E~OX*fJtg0!!u$ycf(}0-|crWpV2&`TunsB6^q%NyEyr|tLf{qa67MQ<ufT=zR'
    '3@#JHYX}d+mwDE%#;<AAS<b!25rCtIaF7#=(<Uw>vh{S`hlhukm?A+gPXT7App}wfKM?U}!8x0yu?WHZ'
    'v!q^Nzsv~6qAP*nu{9>8G6`SgBaC0sD<uO@ENU3g{_E*)C<Q2`afv{%RcJN^nj|mh<R>OF@HyWAxBHnG'
    'zyI&}j4(b0=7>;ncK!BJd=3O(g@KQAogC(vtq0RG-8=>rE&`G%oz$aJ<<?@}RqjnH24}Hl2|lyDla=0`'
    'zenhPEyTmX9oj?qmwd<!$Q5WwDwdG28LY~a=Kw48G~z$Hi47vluTtiQ3h|j^m?7^zRkrh?9OV1<aYZMp'
    'xT3riDZ{{tF+`siSY%tTdO|!1qu6plfdggtBut-zS`1mrpM#uKl5?#p#1AHLWXDUCE1t&>*!mWfPZZ3;'
    'hr5&-iORp?X3XrI2RP)W_9>9qqUH1+lUnVwC5O3;^Wo)PfIc$*2{czG-l+ERHK0l$sgnDL9c}3x-@&yy'
    'BmT&0Q26#Vk|gM$Ou?Eh)+MJ)?c7wKF>y%ojFI65HG}-UiOGcXzakDrF$52<vW-yi1oKGg+OS=O1IY~|'
    'y^81mj5kC!bX2R5s-+6cE6ONJ%TLj4#tB3+ndB~NE;%CXZpEF$sG;^_0O};(9V*h2&~f5bTwya92#-sU'
    'AOq}ceTLzC!0Zt-k0Bc{27s4$a9<EX6G&+BiL@odBH@}@Do5<ui+Kzjb{><<i%w5{RfNmKJ8PVD3~~T$'
    'ENC1bXFQM`#lV{}q}bd@!rfM*3Rf(%CQ&CG<GuxJ>>b>2fIGa8%|h!o4FsgN@M6#rVeY{v(WZ@u&)kt%'
    'ra!55a`U}c#6C&!W6Woo_fH=4d2-e{{OPdpbTRl(LH797oYj~io0)34gQvtPe~?9RWA5|?Pj+0fPRW7H'
    'jdf(#zg7^5^kBKMo~?<2L)Tw0iRbte(;;RkNb-JHK8_^z-wHgwP9NX{q<6t>!wZ6$<0q1?a-@c5p!RLo'
    'L@g9>m?Nq39V9b|RHfdsW*+mpt*kgOCHo4`WKwsDLp`@v0k4_wc&G{zDLf+lS@fI?IRS9dcF0A!G^j7P'
    '&B}<EMn_N%w=24q>8q*n{`zfZ96cYuzCIl`Nk&w>{PyyEd^yZcLQarQmCj5voGc9~zedtM8Qv!JKkV5n'
    'RaPZ$MPa=qxDpX?X*628^a5Kh{FYy6-ny^?DH^t%kt+fFPZV;Nh?KW6$QGD#O_;uyLrZFED2m9;7$J{;'
    'b#_{!9|~H=3~SnK9YxcGGESaHgRtSVkck}E<)d=Pnr!e$sfmyC@;|S~S6L|C!9glk;r#_En%q5KvyW-c'
    'uJGxa@QM86JQtFO(w2<IKBkZ3Ts`<+<6bW2TICNN5zT$r`xSj25^V`L9vI>fI_%;|199PN5}1J>&bS|D'
    'hnVQ`r#JA(?Takb0e^SX#~UaFEu=30FT}+TJ2|5Ug7t!hEer<7JRaaa$3O|=#!#>d|4W>dd({6^p9Bfq'
    'kEW{$UjEVG>p^)?z?b`U{E!U^ayVHVTRdm-Uj;f)`J?foi(!NmHtO`7CRhZ-N)m=^bd9jU87x1ab7Ag?'
    'qWOej`#_2nAqN1DF~Xj|?C!#U4ViRT06N<n;t1xQ6X6Kq*ItlMN0ir$?tTTSl5yJA$@LO*GW0vFaI*N7'
    '{5fFHe_F!m8E4>@dA{i+b(?H-+GwlS$AH7%_{Z0SB7X8t`ao2l1qMs=u6yOA-N0N&0tVnyOdzYzceCmI'
    'SHd@b%r-NP5yk^e*VryiT`Bn85Oj|ody#E8J+I`BlTR>-sl&8QCWH%fG5ZbMWkgN~#Hx6LOf{VsMx_2w'
    '=~<jRhM98qNw)3(+&jftQP>VLT?_R3Y%vFwhp&_BPQ%_D8%B$|??@Pq2RLGw02p`~0}6l5kl+RQ2x83o'
    '<7di)3AE`DdETE|r_1k*Az9u)(5LP~Y|c0#(Mb$*>FF;j3mC#+4#!K{@{ED7@h}lw(Qomm!r`{uXEcz4'
    ';!8N@6b(uSMs~P3ODS_ojiS`0QID34@50S;hc~6I21B6#D(Y@*Jv2y&>-ZQ3P|v7xb~Whzf8^Ujk~sf@'
    '*`&Dun!WYqe0+6wdGU@|u+sO2%r-54@cQNZpRy0W%7J1))3aI6wtDv;Kd&hBWfV&p2EMH#gq`2{w3X*H'
    'hjfV^R%j%RnP~w;N1e`7q!w9eLD(l+?MX#yP<C}Zzmt+CY)c|6Rp>05J&|oG?7|qUAHYTK(-!ezXg{~j'
    '7ri^mB%ZNl!d6XJjJbqC^eg2S+i!s2yrY)f+WexbEfUV(pmwi|svFx`foo7~JjK0ju$7ka+%}3kY3_a}'
    'iM9P{?Ic0QH{8hj?Q%m~FYcDH^W74?9#3n}Fh+K}W%*qpp%Of%Qrex!2olR55>biojo!n~d%k7t>gsfF'
    '6sfG=ep@Iisy8Md8P4ZvvRi6Fo(S()SpYFN-5<+kSkFbaixQH0mP)iY&2`-x?VK2RN=sD&dEUWQ+?Z77'
    'Df$V7TraNZVA#a~9QH-Myjo#eEVGx<v0E7Qxfa}``hA64V<<p=KPWRWsEOcf%dD&vtTY8FXULVmFBq!R'
    'uO$@YaimO%+`~d71%9*`MldYN6v~DDr32<uo)j*^6s2`e!fZ*oyr(kEbYtVr{KkA>V*Rt+VHPvbEDJrj'
    '--3HYqac{al52xfZUnZ7!8yQcAYHzs?F)8Bw(=zn|2QEp=5>8;$dfHV1zTO=`GVc9&kefIaDAm`?D=O|'
    '?G6UVafL~x_rpm~m%YKv7IA}D%dKzeYH!mrv$>KT!yY%|OI9B~D68Vetv=K%NFxbWYwXcGE`}VXhGThT'
    'i7bn@BvIkzcUQ#gi83Fh;!KtLA9E~%9HLjR-@d)Px*?E@u`iVG^7LbY|5Eq#Ech(fs9`0(2r>j?A`5^z'
    'lEa&Zy|-8Fmw!i}*>BgM?-Bd;{d|g7MgAI;hD-@nhDySv<c;GjSP||bZ=JXboc*TWcqy_+9_Bz@tc>hJ'
    'j;aKYO=dsGW3k{A!dH(g%!LIzReh9S&Z<Xbh<`fi_5a@k(8@IVJo+843_E+CGmp>cKKvd3+CNUu35+0I'
    'tocNiy6Pn54o8yZay>r7nFa4&{*5NSh?RBJ9ueuC)FC3*TN0=ko|2s*N~V=_XAFBv6DhN00VrRKoGknu'
    'b1~+%Vtx>KB$zEeP(l(I$S(J}U<AsX>)E|i=Auf&(pWk*TR=%5tukz)^%W?ijGsN>Wc+DJ%(j!fvrl5Y'
    ')Wyj!$x?Qk4kU0i<t}i&mPC(#$g)q-hagJr)GN5&&^<OVPnTI=6`-AIF8(JAK+46jlF6|J9S%(|cz}`S'
    'YZ4)t1}X6+VaqnRn~$WTcCzjLB=yYjl?rBfzH@9)aTt}!Ut#Vq@`b!%yM$he=LXw*Y2HiebCMIJSieZV'
    'w(|7KsD}X8ALLLEOzIip8;YhMKCYk9J8t!P4u}W5X9akId8(aZ_rV-}5(Z<Z;`s-X!G--60d|8h=2HkJ'
    'rBjjX^}}-Ua4(X?+gY3u6F@eb;aey|u(tJrO#LuV6T~Q8;i46!%q&TC0NGh>b{A~!DuX*I+i^KQ#TM09'
    '7k|5cf5}SZU14GnUgi6iS>*v4oU_pkwe&EH76G!)jCrSup~MIXt=6)Od`!3m2HAm=bRn0g|3P!pngOGF'
    'i$Yb1{Zc<$3L8!e7qEoAq6}KKApzSDI9zE;w0e6myS|uL5g9)WMd#4Ajs@}9(i=VJvJ|{k`J<_ZMtNi9'
    '_*a<+<0mBxs4(PY#bL<t;GDJf3Hh4a!xFioEE=Ljx>(>u`kYk3hVY&hCGeF0J_X4;e|s})3cJ9uYk$Qr'
    'Z7ytAT=>~-UleQb!Jy;y{#<8wJCkmOOsQEBoRQ!*7Wyh_&J4k<lE9G^p`aiXUQ>WT^|b^ctUfw3NPJ^S'
    'kP-Ed7gyIbwfO3~LF7{Yj>SvL3x>6EyQOnec2qB3mU8C8h*;1pUFpF=Gz(U%-WfY?mvGux*2$~cVzK0<'
    'p;t#~?mDg+eHN@z-4S+~?kaQoPF6Sp9#`p}+~G{Z3EVjoW=&_}=VXaUSRK7JSWXhd=MfI-5O^=EHoaKo'
    '>bkY@!{6ij`?!vE8b-&h4pKEgwc1PTpps0uKKn|HGZ1Xj{0={T2WRnTteTM$?LYKx#JIRy`Cei1KZ4Eq'
    'MQ;`SMods7sz+SWi{2et2aLMNw^#x?l36=xEff$g_$rvKsChnjLlrLsNsADHlfsJVzc&OxoFVbwJ)LCX'
    '(hv0G+v2shSdAVq9S|^p39e3#_#y!MNkC|1z8dz#Pw&{LgW`C?^2YxQI>eEH2mC6gJb5tuN&9i`ssSsE'
    'N4!SDpqKdOSREDaqwFq8@1}u5)@V+*H2`GumCmvO-Ltw2!EDxqYzTSmmNc**_2Hf$3ycd=iG%Jcxto6I'
    '^+&Q;!QHZefiN$T6;2VIAk_l~g;NYCmCQ&VY;d~%aVduF7RMMKY)~4AmJSQIm2~5f1fdDNAjmC)+q}^H'
    'q{)hOA(<_3Cxbc2>p+P2u*eCI44&Li=OtIo8l=N*ZX3DrKut;pzeAYghk%Ulk|RQNAgV6Yfc-Se?qMAe'
    'R~wt?2U6vxpD%$Wj#%7AIX#Yy*fc#(`DK<_+NhdPp}0`<1Un@vax16?F?IV0$$7$;xp_*GUSBk<94IB}'
    'uz4x8@-*DKk$N};ziA<nn^RV4I(CW)Rq}7Tem3VoQPejBiFj-ClzhxEKJ2Lu#xY+_`n6bVnJpu)J(75H'
    'EcpuykshI`EkR7#MP|dJP~PBAZ+WPsP@RzG-r@0cd?w|9_ju<<3)1hDDBVL`HIBp3ACg%WtdQ^@9J`Gf'
    '#^@)KV~SPFqrTidh4QI6`aqlneH^ZhKN(F(s41=$MKs|8w@?H#py&v*I2@tMH$WZ>K*vw@2iX_#6h!Sw'
    'W9~2CK7eOBP9Zf!+~GWD&igDu_~d2*65|;Yb}ia@R}-S`;*Xg=z$6EmMQ<ScGY4d565r_dDoBew`GNW&'
    '%bfKU11KVs8H{3x1N*2ViDFo#{R_7$E*~a31k@q={63mwHFR_hh@b#|8!X=Fx9J8{V5A(hAq78sH#484'
    '#w*cUnyFB!7hFLa1)+>RT##J(6|3MKh4XWXKA_)^M3JpQc1n@AY^IEI@v3Ygvdlq!2e8jKX?|ZWcBfE7'
    'f5>mAs>D0O5e78(g<&qI^kV-$y9zN36?JionEB`4X@o6(06O<MVE+L33E@v9|B)C<g-sfxdQGqd`2<!4'
    'b!)dg&S6ljDY}W!-D?Lxj`<RcJ8uiXJg=Cq^3*|G$qRS*o_zYaz=sVduoKK|%xqs&$?Un15V`JAi7Pf&'
    '!#p2##DhyV3NxzW=C~gDP+i=)*tSJD9QeH#AX9&mKW2btul|ZY6LAX17U2`f()H%JrZ;wL%|ERAw=9oO'
    'EV<ana>V5VG@DB-*L@!K1wT|_F*tw<&jd?x<rB~5!(Y;Rxbn;-O{{#}If;AAI>A(7GL>dZGeR>&%W0j1'
    '>V>I|Y%rLiE8o1BABoX!!(Q%1)jMw%_%#vq;%j+blsPxBZJ8U|u-HQ_omiY9<*exU#NF|LZ?^5_8^TT+'
    '<SynsDj1Gu7|3UR;`Uhc7mssRl@;O!`ScNzZ%7@)C-jNuSn7nMX}SIMJC?V&eF$%Q*YioanUvjfjngDc'
    'Mwas?I|vfaq6wSa=4|*<n+b6wW_V@=M4y4)8ms`@`0EiTIFKRJ;ppNp4W>m&6liEH#0V*uZRHgVTIupw'
    'c)oCbldjb?m$LWaAy^9Kk;7o#TYX;PbY@&=6OY#;h(NgreT5C25~XMc&tII}nLJ5grzcDj{fJmawEO9t'
    '+mfj6!%J++1$uU5RLTlLRU4HG)}SrwAa!WyX=~uYG7OD8FPdtKILR%m&ica!SDSoz1Zalo@?hz1X558='
    'Nhrs)dD9H8;!=zdDX-c_^@#SVYTFc9erkM@+C%XTR?=+;#;h7cR@X+XjSX1k#;Y>!x1r%mHd?Wr*~n;B'
    'bywwmCjHuKt|j)oT0<Ah@*@dTy?OB4^aJgO!j>p?wIWgDql2^<XrUq`W`MDopg2e(A0^1wUBl24E3%C!'
    'v?9-lUCT&3OAB06b8X9s1Jg!U9O$MNcv|cxao88f&oNgo@(@CiANabVg@&U?2{HpG(i}H3Y*+V?8`^;x'
    'nlPK5*okR*K8&gBwqXXQ8>eHJw;aa}#xGW@2lOVz1@AUK;BUV<{TXX#qyhyKgc;X4?)8(za!sT~y5rk{'
    '1~7!a2Y)-RooL97V#@@`LeH?hIEXbpbYdN_k!ZfIhgx8Sq!YUofChuYLz>~~u^YJ-avaC9Gz-P1?faUM'
    '#HQn#o@<5?(&9L_b>H!vI1FtAH>dYa-H*wjA0Otwu3)qq4mBQ`mZe|f(st)Ke0)xpeB8UhHSMO!GzftR'
    'zT_P;Lg;2H*nv=si=6k~zrQ#?8Z>+(3hrrK*BSk#=C!Z+%IE}9P1iB({TKjFt5?)|L7T0opGh?HDd<nc'
    'xP#sGI9~N(9+A+V*+)=puYg4W&*Q%ide8pSd%0N5dS80*Ju57~q`#F-_O%@x1OQx}@Mt<;FUW6bc?=93'
    '#C3v0+!Of=`+NkfBAm|A(KH_PY9{*H|9bnCA0yUxqx2-{p6f++WO<1m2b$~an(hMc@S{KreZvhAoG|1Y'
    'f#n#M@5YfA#eNXD@Q-i6FNyLbnXVtifnyn_nK*$BXVHl5D6oAy@-^RZOd~NY4;f};Yj8+|!1w$l(LB#c'
    'q9pdb(vx&ZQgL{+ZH}v4e_T9#__#htB)1FOfXAd|J7+D2C1hPWXa%d{y*LX0JM6Ur>#GEp$T!5wZ0I+p'
    '|EFz5nHPZdsIEEG`M|K{;*&hWus8ns?d$hK!TqZn{=h9hm}N|%6Ce*$4>WzARLg9VYg4)j{p^Zf-1Tq-'
    '+G@l@)6VdHy&6#sPV&1g(FagDdAl;Ihn1bR(gdD*K7ic_^-neFIxZu)eoPkfD$71u5NlJQ8b!EP54Jr;'
    '3T%#alIG&kmu3gJD>;JD)^nM*p4ZS8Y4zUgYeC|Nj%Oy84Pu-Znx^OZh91VYZ^lUy+p&%k3t7JI#EGr>'
    '$a1XMaX{R&;Y&@gnV*)}nygT;1m!J*2GK6i90)VgecMV9NHj)*jM#E)-Sn&|a6&ya4c{?65G@1O^PLFh'
    'HUdD1p#?!4`Zge}1_*BEA=*U}OlQRAiS8C_Bv-rzP%O=W%gAvpJi8B~t7C((1p=9C!WH6Tan`bv!0|Q5'
    'LU3iE&`f+U!GHy!<!S_!7DaZux&Y~vpw|K3CWx^2tROy{$n<Or$R}}KATboW1`0G7+BO5tG_~09bsvOx'
    'GYB;hHZ4Cuj$ww#GBhXA@m)$LYLtH14@{8Ab&%F!3tgZY8&>2X*Y{&D1cJ5`&$aE?j8Pc5@SmgkaTGZk'
    's0^S|0G$=r#GON|I(XJYfGsZ45M1=84Wz3XRv1TN;t`b~3@zkEn8u^XP7>WlrmH!I8|W4?0D<s~=NfKb'
    'KFPF&=l&?~kMg4)<&+51vY$YWuP**J`SJamf5)QXO<p>y?)rYr#3or-s(q($?<*g~7a$Cthp3{bO8!3X'
    '@1Vzua*jfdM*gY8UG`v+1;oRAOBRqIi+j`@i;sZBMmT&t6sj;-1b53GH}cwwuWj4%24K#go=h-r(FLcz'
    '%T0j?lqdlG9rWIjC#dMeQ^HK@x(JjrxrT2xQE{>tnnRf{UruMLYFFKK71bjvR*`$5xQ4?mTD#{$Csef}'
    '@*47CSskgY#{}qxSggDU74fs8a=pwiw*g<~8{BVKR~Vywv3RvbuDIP|RcxY*3ajetST2le`B`C9dXeB-'
    '2Bb@$aD_-!QCV;!t&3VYMT2x^<vrbT-Bin`xz{-=EhZ!93Arx?%_*2{M|E&zCR$P1v5cV$g>Ln1KkEzJ'
    'R&C{$JGqOEv~|Ts*6(A#!zzx|JJ3Z@$8NWwzvGgR@?>Hq!nX9VRXxb^9mfY(#b8^Ms8c_x7Q4Exe5Vjd'
    'O6xsU^|2`{=cHUj_tm6iGN}OO>+OM(_qFhvv@t9V4%GTW@1)Hr2TJWh?GD@8j-_&kxk$Gh$BWD$bUi;Y'
    'ea-Y;J@8_LJ@SSZ=^*EuPUK*#oZ}{*j(h`Qud?k#ZlagF!`Qk<Suj1;3~&1Inb5;06~0P6VEJ(-w7~sQ'
    '$v~`o44JIleRX(03+8j+en*1>fMv~~uyn|6{DV?(6$7Ubt4AL81lIxuJ98dfj!(}o-i)uV%I!S7LY30('
    'A~n-d>JfP;SCl%3tdYRUo5dXEM^PCW&Ol!w?Z|oG#+Z%JW8H&^YJ;z<hdBXJZ1Wi|gE^>^D}{yOu&n=b'
    'wPiacj1dk*>&tva#q_fz4pNlvpH6!D+>Nq(so-*w+VAm_U>vX>rx2k_s0tpgwoQm05KBoZgB!L>x2ny6'
    'l`zatX`CtE!qV%V&qIC^BBw78l$IV=C$gZQN>A4P-I{7M-kzO@(^uDNkUeI)dW_uI2z0~rA~$d}+eL}('
    '8-W)XuHji$oM>8Nm_D+AO-5mq#JcIkv2A-^>;fCicrm_NsQgySi#zdR<ax27>j^TD6QfwSUCjz?&xn1~'
    '(tyF+vF>}00q-MS_d+9xV@r!2&2fFt&_c&b9J@To=a)78|DkniySiZ;p8Lu<9lx^mGuQM?%|9Gg_~_HO'
    'jZ^EDJN8`fmFsx^ndQD3o0jdF&E9r>eeAq^r5R`ErfIy?4BtP6*Xi749{fg-H=Ck7mLYxLHtg|O2b`XH'
    '_UWk&gmXT2&tF;6B%bMcXYRS_z4F|1ANI&L4Ncb@uA^#-GM9ArvgMwi8=7SpXPWiWbgY-|>FJqcG<vxb'
    '?rP+GeNnT)<)nenPc3yEPFDeb@(|A6D-d-rQGz2iBXszp{@q!yTK_vPXoTOyF`r~4%2u!^l1g_?M#7>b'
    'd6~MIKxlkFpRSqDY4#AFF+b10qtBlf%lI7O6vznC0FK79P{^*Ahywa&Qa$i5wQtt%f%WQ@d#=5-&+V6*'
    'H8x+Jo{oL@+&*o;2QMF{vlyeZ$$ApHVdULXGT44~rDvP1uIl9B(Hjj?$0MZ0mL6p`8(C8|Lufo+)#?6P'
    '^L;tns3eRn&Sqyv^HEOb#s{+*_TdbinzlVYwazu$^v`VX<*9LYrnkm^lT)drtFrBHva&`eVuj~9Y9a)b'
    '@~B24gzk^eeEXGS*{-AO=IP5<r;hL2XAQ1i3C?B%HV_!bFUMz^?!P)8pN?(&^lYp-I-Fla5*Ws>V3zYU'
    'LwjW!ug*;C<=Lt4x-ZX~2@F+J)ZY1}wAbY2O1N_YZp<7b$m6yadXaC$RuUoCboJ1W6I0W*0GVE_g_h|W'
    '2tG_K%QQfK#*(-h$A%mEdK8*Y(r3*Yxj&JIm84cM;-({OxC@rQ60aoA6>Fc+z)`V!NRsLAco@(@L5Z4>'
    'l3O@01eP<I;98QCNuPPu(gK3`<4mIz`pJ$+k%uD+9C0b>w5uX~h2}9$g{E_gRT=4eDQG;+gOpkb(qu!L'
    '14~=~;?Y+3vnih_&BekNU#tv}$`^>(<Km;L7!o0cgiv7`3UETkVJ_|dt&rG6KWFD6`=U@lngYxaLWZIE'
    'Amv_(4g2{L-P2YTZ2fHI(>Xkx1n}GHJ`hV*&>>0v6EZf>z>+{ukwNNEo%Cul1jQz1x$KjCp5Q_0^6*sY'
    '>T;W!Mg`&879Y^^emTW$erIV}Yg!;6w<P@iunu;0(o7+}5fFmw8xpEh739aM{}}i}?5dEMhwbcXp<;Z>'
    'vSqPdBfU>)+;y&LF^tb@sn*2_WXBsDm-4+rIozyT#(X^`&PQf+p%#p1*hJBj^I5ThiJl?a_;`s%uoZDI'
    'n;k8~!=rz_8~nE-r|IZMd*%nvlG`ti^>xtymqY6F=N%YuB0nCFSdDaC7do>fi9K*uq_#$R`jnJVNd~L5'
    'dQ_D4&00z4D@tc}C=p3K^d#3xMc%6FExJT^i{Dt`bXvg#b766k#r=AEH~o7+&5JM#a87Io!%vf1v^b}9'
    '_xn?Yw%mEmkd<00@6&?9QY!K`JAELVABEgt^+^<aEgcsMNC%&IW&E@sFFB;*z4tM|hCyj_aDw4H>%v=g'
    'd*p1=JGeJ+wnch@vim~by6Wwtv{yyy`Rjxln8jUGUnG*1xRbM8zp=%`EpcD<GR5sKXUByzUL6$0&-ysu'
    'kA+7P&OW~=_H~BIu#mLMM=qvkoj0)oS}W#E2sQqBx0oX4NGr3lvoPl80A+$<zIgaZXogePY_fn433%3A'
    's{oq{ssn|?q20Qqsk2wJfCC`M<LbIY#Lg~fw2GCKNyq~qzEN<0^XX(0d-<$wVyv6bp5+~u&aC$BwppR%'
    '&@G)O%ks|;U8(jI2a<{cWJQ3u*n56)b@uk>F-ZJu@f}FNYIUbd{N=?c7z@s>(rn!#SLJeV6X2VRzeU`M'
    '1rQFD$!$u>CsReb5>@hT1F6iS#--p-tU=>O;)sNxR9(b9QjQh1ScX}Z;7Lp@d+~%<EST^b1xLzt@)v8_'
    'ZhBOPbwy(o+H@)gr*#yv$_XOsCfPbl4<LO+Xe3K;mz5FWg>)F)*{FjN#f?}idAeM!Q^Q4y=gYUJKTTd;'
    'zWuK;PcNLj9RKy=jcByNwpH?G^?Tzt=i*yk*f=sW%P8RH_!*{HX3n^U^G273>-R8#E@1^%Ky^aW<mA6z'
    'U%Z^WJiQuwHnSj-H~ORhS-^~vw0G2}Ug#fi<nxlX?~8Ay$I~A?ja2O?H7&Cvk44yNR`*jI5<P&u2Q=bo'
    '16p5bK&K@Lm2_jd;vtp8<m^<*)t_>?O!C4fs6S|@XtTDgIVn$}S?8PKl&RQNA>v%3I~9sd;`%;Rq8nn}'
    'Y|bYXRc$#wF;$O5k&Z1?s;!e>a%p+Yw4+%u8oq%@M`IZd#PEhP?xJe!+Y#_|Y7yED#AifLW-Tmf>-2)$'
    'JYubgF%wn_coJQyL)@k4r8KrZFZJcwC9ZfuA!KB?TzpcKaYev;aUw-l%p1m^+1j(1Jf>2xay9D7Yi<lt'
    'pkb1Oe1DWYkPqA!7LtjMg|*0b{M@>*2%8rCqwVR`D`UGzW81P=!3nK2l+LD>QR~5y6=V*btT(3lNSR<E'
    'e0YKrm=?<H8MV-yp}SFnm1>`}=?BdhUdXsAStUypQ_Wkh6PGPjfV2u!Ii4uLNiyRvB#5ch`Nm|^5F)zk'
    'Ar=&xsD7;5)h8ZCR?3EM;0-!BiBl5bku<^^7RGd2$#TNq%Q;Sdyi&#!;JP=grEDe7S>oEV@-U6(qkbPe'
    '09)4$k(S6GgJUud`Mu<{%0M!uGqc!nKve*i!Kd19TtT-SNYz%b>k(cmT#m9sP!wl)<e#DWWIdQ}6eOKx'
    'EToACIr9q5#4q+YY+=QzxV{RS%H}C>Sn(;|b?jA6ZmQOXjrmb#lN#hQA_^*aCY%-%%34-fB$8?`n=YlI'
    '8YZBUWvb|_k@zK&Sc!C6VF)Etl#9*E>=t70NlTNnIRu~8V$KSZNrw0=3x%?q7fk%aJ%ke6DK?PW2p5c`'
    'Cnvdrjw)k}&}u$~EbXm1m+3I=j+=%f=LK1|4OQwyp|rk;+$MCJRU&jl*rymh6Ao~Xl&8X)CY22pMG5oP'
    'D~0LBj||86P1m#{Ck(vUatu><Y~6FCP>YfXg^`{lhK9_@2j&z9ZeZZ(THi;=h(f1-P+=k?r4OCZF=EdS'
    'V>8k{3z?zkqtNtX<oJmlyJmy~knPZOT{ko|4*@mAIIY4BZ6nrQd4lwK;GuH~EN=io=NW!pP0=i7Su6)7'
    'Qf;rDJ+%l*X)v_on28+(rsaEj6ae}V#-EEYZY?czy)g75FEBmZGj%IWj3^GQ*fSm5_Y(t|%3$b7Gh-uk'
    '9V74~)ATLNPh8(O;C<6}bWa0Tt^2VLI~n<!W5d2hhK;l+2qV|kY_q!JA<1*6{Zl9<jxfoMJ}ra$dlVC2'
    '%SfQV7a&7oHabHwaO#&tN;v72#w(o%>)?p=IeAzoUR8lIsn#H+@$2SbH7Mpq2NQ-?FNHuXJe2~D!+aD3'
    'RZ0t;l-JAC0+5drA{@r=>$;Y>VdC1crpJbt#FifWE|8e7;R-G$kc<~4T9SB{9|XFuJMishHT$Z|>up-F'
    'uj1rZR_$w^Q`WTjU-kO(8(&?;tYTGNF^G2cb~>TMZAva#2)S0IB^vN5JBl1V@Z7-Cbl_&176TP~hL0RG'
    'b{t@50o)p<W;hnIq8Qmh5_VYa$Z=7iySCvuX5<6_4P1LTUB$IYT_ZCDfD8-J6PTJAgqH6Zz<j;PwtU~V'
    '9MnnmC*4f~--z7M3v@t&srhaM>xWA)icLeaT_+4J9qvdk(kusdB(imY*azGtTA;;^OPRrC?s&T9X@+YV'
    '2*}M#bl>%Y5H49g4qXjsFtIe#4}dTX$FOV@0E-hKJxlW}yRRVo@{(VBy5H0NZs}eo$Hv9K8ijL|72WDC'
    'yhE9Bx(RGM0Zo-T*-0QuY5An~aVg3y%ywZaC8dcPc!$aeq(g6!a*Ec)klL?h_e<$-;Yz9@psn0us<B&o'
    '$rOd6Dh#!4t}ul~H&=Y8-V;-(nzsYjk(>$MsUxYR{99{#Xla2Zxm{1u^r@`uvF-HzZmqK=)lF*S{C{cM'
    '3J4yotOVIf%)gRS8?K>oxK?o`J6T9sEwZLDXj|`0H}Po7Eor}whPxvlk<z{DY-uX4t&Ya3iLq)DVwGdu'
    'S;SQ-j=Km7ld;!Lh*$-AcU{D-O%=D@mT`NM75S8f+*(%T+q#t7x3A|1kA6}53cfa}^k-xw!tq*9D!AP1'
    '_fzlB_}2CQx+~5&E|dgxLtB5rtN%UYMF9;`?nm+^qWBSu0+zAr%F2N9=&Bvwb!9+|%-*9`f>cVbC2bQc'
    'Wl%|_%!+2eS<KUjk>~LPRtbZ3v5a=fJ=_eCuHh))TBIgU0;~%wi<;z>#=qXOOmXRzw&~&<d7XEWIi52y'
    'ot|C4y)4he&8K;a;OEnF^8rm8r>KjQ>?TjW*5>&{lGQ~_e2a|rj5@l@RacWx=LzdA(v2Ett*afDC8_J;'
    'eY#l+dt(c1E^#taf*?f$r9nW?XtZz!U-<bxSglmKlO^t2h26RYPi?X&0pO|}%F-a=>g-81U@cN8w^~^~'
    'JU>0knQMVK5>}l4GK29bAETv|&YL6<s^V@+^9M@|k8S5^kP%s)saSvQ?j&8YIqPd-JrQ}|4zm?o^1g;C'
    'i%lwOe50gA5w9C$F4hG1J&E+iQjWJ-;-ZML4YC)j59L0Eai7AdOktGyUz<F}s*AT&>e?i!v6*7XY6mOR'
    '8(BUOIk4RD#k2=<z2llRtOW}P)-u>N&&94n%PR>tWI;H1dkW0=^WAJZ|CJc4&c#D51bJi2P0(XcGCVUV'
    'PkId+X7LxWr&dOZpvBVx2TXC6k|T?}OLq8*?@;+pQu&+duZnnmroF;8P_qnMv&{RXsC3>X0S9A!mGVTI'
    'h>zqxKj{hm1_}%vZykP2+Bzab^H1?l@gtzz#q2lu2!F}TSWngqvTxb9gJB^klk1bi9xOPxr<h=q<_@D|'
    'r&VQar0pYkQbvsg&Ok3@-th)s>3CvMnuA7S1{q?|O%*3$EVYn9_JIis>E%?+y-8E4RE82oaVMHMC*mPf'
    'B30y0pKoBXc@1YVx3`&YCpEUCEQoU+2G?Ym-u>0mN(#3m{oKl^%!WE)D+UP1d|na8RPtafJAIRZ+~2L$'
    'f&y2N+(q4%J<`|)@n^g(f1v_)Zr_9_^QoE5>}`UvM4jJTm8GrJ90y9B5-V&~3BDD^Or{a4FZGmol(5{E'
    '0#lQH{B}k-T*Q&cc$yMQv}^&Ip!ybpYn-#)06d;61-fDU5T!7xgJVkKh!qKoTW1)`++TIooK>u<A`!4%'
    '*c8P<4j4Hju?SfuYvxIk!em7Wu?>jAb(UT)RRXMd{k35RnU*UTpp<Qi991<2MU^y`mvDjkthoTyAdYc*'
    'clWRkLb&5V4lk7Ns0zTWEs;^9tyk5_kb`@v6^;Y<A|J)eO{GzU?m;5N%U^N&9&Ie&Hgr6-;p+E``|Y?o'
    'lM~gH#`D3m8Xa4*qb-tuYx8$&XrrtWf}}Mns&Y0<>}}<tuF38t#n^iv(EI^F$@%7)QppRuu&iF*tuOP}'
    '6B)ew{9cvb&^XDrmIYO2`Zh0}n5O%Jpt)K^aOd}Mn`%<RpQ+}GEZ<UX5=(SW61YjMd!emqT5NijnOKqS'
    'X?|?ucIs}Tg_ah_T4;ur9>l(B+MXE%j$v!IVIZr2pcDb|(2?Q#e&m=ajyxF4H51#{U|Ks2O@!>o_Cwcp'
    'BTJ8CD-JEgLk>=AaggTwrjzJ==t55K6<PXUAEq(7W+L?!OXXwfy!6E_5_yH0OVc(J*AHzo@)9iwEfm2j'
    '0z;3C*f1011bXC#x@KvStvMcG&<UML*L*XIqtHx@$PSfhn;O!sC~}?1H7wnU65Tcu55>5Bo#~l|t%ru='
    '>OOqx+g_l1L87@H@;unKB#CUjK7|)ci$@c}5D>@(xZ&*ibVU<zE(w?TFsN(}!aw=9pMvT9lo^B?j)^lQ'
    'rOheDZYTMxh0cAU5r%=~+P>quNYi{BI1jw!CXwZ6zGHY==-WXABO>1dnsqHt4-Ct8wIB&id-J5&niSSn'
    'nX$F>-zJ;22C!_yw(Hqg7^8IKJL#^N-+0ppmZrI}7MQVVB1=mQ19(&7*-j9-9_|gP1NC?)0D4NSI08D0'
    'P0MrO^o2kb<r^=SUuJf!(P|wm*EA5MpEX~(puhG9SYbMXXFd=cLZ2Fv`$R7<**4sin~qK1$Zg@z@H*Qv'
    '9DG(vOx=Q-LR3a-AU=Jm0CiaUVqej)Mi}EA?&1#D+$8}<XjfA;<QZ(2ILO&zu>`gh0QX`qe<ipR>AjG='
    'U3>7lx)s{xuXe&Jx5!_`-TGo=!Q3&5lgPCk-LjDz_#RFnPJ$S&e?PJvoGxn{R^T|me*-txV-F!Ch&s$)'
    'wLzq?5=#qVvB1eq1B8zxLXKs_U1{5apE!Z0k#tqf0HAH)@D@Ox#6F<R^*hO5^^gnl4DcfO2jm#n1sVXM'
    'DG4LsT?vRzu?ZM5;U;oyD@0yk`Eh6?D>48y%kdlMZ3D&lVQeDcUSSmAblt=USvo?A?}Z79^)Ruu*w%IA'
    'hOrKx!o?SafEOds^u$&qh*vW4E|{})x^g+<`{T7gUXO9SI1M&R3|Hl7GGADu+KlAhRAytgt;NXI(n4{='
    'lAz>Hp*~azaNEMHis_chX11w<sm#FarU<7TaNh`lCHdpcqaUm540IF?smu%C7{*<JSXFYMqxj8@iVvv5'
    'Im=5AG>GnOmLkp<bn(->*W;hYZ?0KrO+G@P#^0991}kGFhr5omm(z`ExWiM*Rc;#dy-mV$1F!Gasmd+Z'
    '@jc}$*M+5al(fA04t2YhU1TXM<0*4|L!J5CG*!8y08k0Ht;0b}2)lVURXG>g%E^^W##Q>flu}Pi7oO_Q'
    '+HCPVT6^iz>qM;DSjRFc>k>V~G{$mzMGrB{)?$^>c?=}Bc;nbuig_Fmfm44=YxNW&AuEY!%g9J&R<{%r'
    'sD!aWj9_W<dogCPys*k9F@(9X+JzL>rrdWBVpy6<UkEuY#1yIthL)eHk80f{_qAO}sd8!6A&|-?H4KSV'
    'zS|~5@|RqU<S$~7WF@+~51P!~opKDN60ub=m6gC3V=T+`h33(fdGHzWvsg<d{6K5d7;f1t+LD<TvlNj9'
    '4mxCTDtCLQLVth9A(QfCzpxO>U&I(n)vMK9YNMFS{Qey7HpWsp-4-#ImEd<BgINuH+n7u>%iJVJGe;8*'
    'LpHZwO)-R1xunfvsA?6x?m|2(5wStYXX!QHc?f8|(6U8HXcPL}G(@ytuEdl@jBdgD$|Fci)+j}k))+(E'
    'Y7_k(BvL8ui#6KB4wZ?1+pH@U{Oyvks!DNgq3|kFw5rh9amJQx1g);}Ql+|WsJS&)+&a|Two}_4L2K)G'
    'mnWvAxHdY|7An(DHKxZ@n5y-qw(8R1&NI?-h168}X{t4Bovv23&@QvrRKV}juko0wnp#s+X1i4}rY;n<'
    '$JNt1R?{9+OY2lg>qtl2P(|xrL+egKdp!NDWA*IOw6k3*XFJo)Hc`!Xp_wTav!_r=xOx59$0#8CG%F1o'
    '-@ejttK!g4xGM3mmrH+YRHoSc<CiHmzoRn68`qpJ7BIGq=eAL-U~GQl3dTiMxUzP!a-*fWc3r!e;Ia2q'
    '%UV|k0Cruwc;^L)m6pA-QpD`xwnd2B<ib8i?cvui-~ZG+CXzzBv#P^%_}$bSt_Y%kB9(^e>c2^i;gkxx'
    't1+A>mCmaRH!3mIxUO(baBwj?91ikE6@?oFR@c`O<|esqY6%ze1{G201+28G9}GZN)(@VA4|nbB2j@X*'
    'Q8{?S)pS`iI42}Gsp2aq_m@`hEff)GK6ZoJz{;fR<}=8NI2%+TuDWe^Q+v2EOKcGs%`f_$RUK~36Tkm@'
    '!xWbrR2nXIem;#F!)07?vl_z`OB+-dE<14hy2AUq!pgeBMJ1-bqOkfxE|s@7sU=*e(>19gjE`i);Fn$)'
    '+MU!9rj=^CuOLj=%VrgX3!JID3c~4S+dLkHbG8<>gUdz7@2hHXAkjvPdcoBa_dj~QV40#isuWylUtw_>'
    'c~x0aBRFL%k6k1fPfX$Kwmxuci^HST2UbB<R}!?s(9ym!a85rQ<aEZmYQRBS->h{V;M~l&im5j%uA76Y'
    'w(4&|krhGNw$d*JrliJiZlB<JBKh)~3=>LU>5NLfxE?Zj$I=^~$WdYih>ZVKV=AYV-wrl}s{~_3z?4Q`'
    '23x6hO9`tGr%<w%ip9vK*lz3Vih=}LT#UkGrw%(Q6aso0MV^__xN&*s8uR0}g`FjET9kAy1*<d~q@X*r'
    'DdU_s9w-Yqi@Hojon*lz&L6K%BW}&(d2QfaFn+U|zzyiO3i3uZfu#ZJ*=Dl?T~TdVm~T)M&@N;0RHZxg'
    ';ssiXjG)TmURm6`SwMehWxWBWZp(U?qOrSz-fTnDD&C@<d=pKx)@R$ciucB+Gsj#yJf9s@>)x$M!%@&&'
    'q-hM#*1Vz#c{h|DHmphBFy>^#YUDIPq)|C?b64faWrIZHLgW?fva$qulg^`csQ-v&_h@;f;K$?N?-y`x'
    '2_IWcfA7uUJT8GX^JOtZAW_aSTMh)1At4kxbc$yB;OBcp#0)GJT@i8PO>l=+_n@d&SP2!Kx*J&f3bwF@'
    'OtQN0S3xf;Nbi!))~e%m@qNKSW2Ny=47GF%7+HM^<}|eHOP?G4&o8d8`q+kgem*|uY!!bX;S7H;{`u|e'
    '_kv0OD)(Xbs#w~(|25m3oT(8v7{^>aSgl9*0q}pa=25taKWE1Z4&D?F=4u_xBWzfVVH@xZr*K?9%&7$t'
    'o3!vZqjj(ZO+hqm<=*8_5a$*i1{0QWdr$-29U>kJ>G9DtmYxE*$b$es#p>}vSqK|>j(OxM9soy|Jd#Cl'
    '`>S@2>H>I(L16+q*bV-Ym@HvE>;O&>d`DNTkiKz{8hw{wioy>tUCh&axdy77XqP*rM}PVg8$Ro6Kx|{g'
    'IRHxY{hBl?DeG!bX5q$mDBISxI0(EzciqT~B3lnE%k~p94(-4~$Tp)S4z$4XA}b1$#Ev5`NbFG4bu%`R'
    '**{PkuJF(>rtczMkM+pZ9NR~h9@~+L9AFoTW@~|Gq9k;E-?D8t(mmY`0~2|+m*`&TA;gE4x*C)hygtR)'
    'xWJA=>_}NG#d6ndq;1+9WT2GRV+Vvp9!h+}bO3*LphZUL`;m`ACqhODi!_5IGMyj@!Z>y{z>Mv?o^2<Z'
    'VHvi%5WgL{mTfqRrA3xy8ZL?)&#<i+xlR~ck*Pb#hhOa=&=V)HG~d<?TuW9n9N*V$tG>;_Z^4oi(Z%_3'
    '?`plo7x$MQEu}n)mjKd;J;07`?`ylR2b)eoYK)6pS6&Ohi+%-#CJ4Ic0x`O-pIC`y86MzSgG1oNfg2(?'
    '6_Mdak?$EO)T|gbIyOx$P7E8S@<9e@*#x0cw}Qs~4>mg~wG9y(0h#Svt~UH;Ky`Jt+Eugegrv5pX6^VU'
    'oM|mF1KajJ)3aUA)Xl_jVt@<SGKvGowRJ}~T`%(V*fkP8)I1<WLvtb{>9CqLFk~aq00iAIH9hcr(+Eu8'
    'M;_+dexmul1DA#!xNuxF<RRcZiJ`?B93<b;y>6;mhng0|aPR4^?dV1fybX51fer9tV0rLg;G0^6d^_^p'
    'Aa+6o)Bu}i+D>c%&Z5S};vEBN5nPF`0SorM&<broLZAX8_{9KvFbzAlZQ#I;A7Fw*9y|<`=4x>WT)Hn2'
    'zfih;PyKu9|7O(BiLy~G_omUpt!r;@5<RS}y}bc+y8^DN>h>0q&Kp(QRs}v+RNAhOgWgf4?Xql+Rz<b9'
    'OCb4f%W2oAH*8f%yFNT(>q6R%R`5NQ&@PXz?y7k9#=FwhDt1veyDUUFmleHP!R&6Lnbife>tmZs2)Id}'
    '-&RGk8~BivNNni<Yh0bI!y4GlmZqw7-7pfjuEupRo5_yww8k|d7_r2)Xoq{GBG<KHyB(CbE`+gmQP}z('
    'H`e3pr)kgRquNT?ID!*ngZm}O0DmIy-W;QOd^;G(A+vZXXdY*=={k)~C$9|h)ewHbv3U*ZNnX+M2|HNK'
    'X<Tegploe9%<rej_l67Iu)H^CMiZI7B=1UP;bM$fX^<j@3tv-IS0bwTUgHhGjsjBrS>`Qe6|k8DN?oOs'
    'NcDL*c2n~_9|XUzcD_l-_fxKOUKty{uW<fkE1XwGg>PHiyqOTzxSn}+)Of2(=9@&3Z&dGF5mmkcpzWi~'
    'w*a=jEcxLsL$=ybL`?|S2AJMFN_``Ymq)EPsUF@oioIXFKspL)uU`CSLGCSz;g<&|KIt;}WkK;x3*c`P'
    'B)>uF`zAs2Taj(ka`)9S^&8!QElb?j$K2Q1Z99v>uReP9G5NbaX4}N<D_6FY82%<y+dihhnh?8)@!zoh'
    '!e%C}{!Vhwch-8Lt%<9frVFj|)+?JXY;IfKvgtwxN$y)WSg5ld{sXjDXk{zwcb81RZ>q3yD!%L`evEbs'
    'Tc_>IAQzJOpHe4<HYxtwG*Q^Zd;0C0C@4z;v@0y$#ul`DQ&4A?pj{h+I<f;jh8d_!E6`&afx5E+J*Ek$'
    'TMJO<2B00<e|BL0=|U}iN<B6j+I}9v^s^hw&khVf?d(3?nte92`aG7=XG@z;r)R4}i_fDOe0E~**}1vr'
    '`|Iga-+kjT+HX9~CNJjq)#Rn32gmo+{$<$9C5|@g2V?#5`@vX$gnlrsyZsa!#Dt;!+%}6HVyti7A*Nv0'
    'd*U5pC?b2`UrV7sSo0W_hoZE341Kt5^O)uZ2OgnyO!G7&0`cye#*pE6)HJ3%TkokfjUlW5CQW1N!~5Dd'
    'jmeQp_f2D()SYeKG^RTFt*CO41H4h!nEE8a`mQml|6${{F}w#$ZryEqu;fwp4SKN1f@z~JCQ{{*@-8X)'
    '3Mb9SZqS3JqB}~(b+Vi8D2>m4o6I+I_;=YIrRm}S19V3rxZI>WN?DY`ljx4pBCC;#NgFgiDLG5~#wYv6'
    'C+fy0jBT}Qe4@Ms%Vma*I-k@iB)PJOs{Bf_viA9v+q6BQ$F`>JNllxNQt70k%|}`O<H4@;9chB&LBoVb'
    '2|cBqKb~UGl4g+CXCxjp%|JZpCgbp6XBmd<hLTeX51OP99&D2`C{5e{N9*w-BfXOzFLfDwIh|Gt6U(LS'
    '9c+-Iw^Nn<QM#@u^X=*?_?KG>Ht4z{YlMTGmRQ?$g#~GE(sf0i`BpLYhK){SnCiQ(<W*M@l&!n25MWBW'
    'u9W!4^TpeqNV^ScZfo9dquOq>b-N7_oHp$?%D^gbw~?1vTeaKBX`_$ZZlmqt&WCxhlhm-Be?8r9-EO04'
    'Kt*Z7fx0P%d^I+SpvZS6E9r{SDC45Dt{51oj@x3CA@XtBV$^z;TDQ2^^hD$ibcbi6gBBO<x39kK1E!_T'
    '`#v=DByZUFfw_GfHGZ&m*7!lv>Y6uxDCY>(jUO7cjIYD}t{OjJQh9=%ADZ!w>OzzS*--5KP?Q^+b$aEU'
    '9}4daY8%GszV*Yt^~2L^{XnfDz*vcO6d!*$fX{%1%~wDRcRd&y|HL~b%6p>&#t6b-g&gaEaERn#9+A4x'
    'oJ-7>4-;Zc<xl^8HVuKX{dD>_N`{k{|9L&e^@4THuzG(YKghRZAo2_HjYs~z9ABSayn&PO?({!jzdb!q'
    'U$iv#8h`uX;NQ||kM4rsSD-VV2ty7DBa2V2ml*vdh=tkI8Slwl&_GN0S$gKDREVUuV;r6W#7(~VOE0&a'
    'yvhA%jB{pgA2VkQjrF6>YV>=APz*?0uQKWH8J>u4ioB;3;iJ&A*&T#&I>H137x{{MV*SBj6Fl%iQdDqf'
    'gNzRTsS+jWm#xrpmd@M>W|$p~!@{morF%;XIJl$(;X4ry*@r3iv&}#rnLV3hnFV9|IiAI{>0nqiStO#!'
    'E;URqrJp=1uHh+$iB|-=EDi>v;qGAtFQWWB{Z!y@M2qdnM|eeXJ{U$Ro^u$Li3V_SPM#8>rzoU!gM*<K'
    '4_FLc2h%ymC>}K>hx_0&5gH0eRZ?MN#HQO<javbblipD&f$=>kCw@g24D6k&ICIh#kWI?)a+JM=w*t>F'
    'IXgZ3aZG%XpdI}5(*-e6+E(If9tsUd3t~fy;zUbA$F%JzvQU8H(05!-_k+GThN}Ax?6zhgOV?e?unkQM'
    '62o__zzf4f3j@<MJ;#kA6k0}r`xwMp?4Z~Rv?zhEG_5dxp^L{xW&K?%HsU~Yk!~lhg~CX85$;kD=!xaU'
    'mWdo&^GprJ_^0b9fgM?{t;cbcz_Y&INiBWPj19P46Wup-OScR!am+;X49|~aFUFAgKH%C%p%-fwvNg-H'
    '3^#H$$Fe;?jJxbD;KvEFqBu@sU-umYcFc>A;Y5z%I1cWnfHY*qrfs<q(mXp!3}nL=g{JL9UL4jpwMg}w'
    '5tirioPc%|CAJ<0iS3w%75a(mn3@|WUJ@h@?sO2?fgd0@!Ex`Vp#^53g&{28wcx+TjWjeLA>07L2imhe'
    'E3pz?(=5#nfX+ZF2@*|5acsbPq9`_X%Y{Y3t^|(m8d?~8An^)B$mDF^ui)s2)IF&Q=wRX3v@E|U{|w0q'
    'rQaUr0wbD5M!>r?KH;!sa76lIKOY}a2$1+Cjga`IfBcI&MgqnX7Fi5<A`8pKw9;=d%q)CIKt$g3k_CL0'
    '=IGOS)-;<b4@g!l;ClSiyVvl?<n60hSL5sB+YzV~%QcO!Wq=mqZly4Zff`ge-WBi(egQg)1StWbC&Uru'
    'pcJs1z<sy+2+yYX_p_c5g(5te1**_+r<-Fk&2736#hx*RHG7r$s7~KqgB&e|Im!8HCAqnr|8ac4rM;Ts'
    'L>8h)q}XAok#K@lM+P`W&ktmsbc>D|8tB>y72QfpkBNesX`^^Fs*WmF&2`QSWi!(<Rmv(+Dhmp$FjJ~&'
    '7DrX9v1E9~Be*Xa%V0fh7-YmdYROwP&c}qMQq2OSR&M<vsTcuSG4@zU8<fR>DV0?Mt(d<mB_RliVB-wo'
    '6f6hBD#$ogYdB^EGzlJVG|J08r4racK?*gZE;Am1uq*l9`4UuTLCmYj_=6xM=2!(^6B#9Y^JKH&vRrgo'
    'juM*0mu(zihNmW*L&MAzM3A0scAQBihjht87zbq+g)l}+p5bf}{hDL^L;x1UFUiKy6vF0r_WoAh-^%-2'
    'd4DVKZ{_W8<tnpJdcCM_WTgd;u3&!$e}{K44m6^QGYhJ0(m_vdoG0f0Qakc|_BqRi%Hrad2;YUPe853g'
    'AvE7CkEQWecgrh0B(=+H)+H}8f~2fZo=|QR4s5iX-jkvvbxrc}%VA!s0<`6D%7bjXY6VEyFj+n|Fr@q#'
    '<>_MV?Kh`C3&~;vRZCep{r~p>3z#OKN5A8vf$O_GXGLB{_u=pOSDf{6*lOx`FR^2Z<b*eXpiRfqwvZH('
    '<^(KCP^3F2RpM%mbh-FV&74`fo_ZP{P_4|`D;reG-OG*Ju9=;fl;5l<W7|%4bb)29?1~uKAgzxsML3rw'
    's~~tHOTkgcWylqi{PJg-@FKQl%0$213mp_&O$R+}oc701p3D2I#dezgCt$KF{jUsxauQ$;Bc+z#{x->i'
    '1>T!a8LYWKS~ns*%p<#|0bvgFLZ)FU17LZBxus=dZH<K{n?*L$<cMiYt$r)bzFY17aL4J1RC*;VFB4&R'
    'D#o&z2frvX7Dc@W=Pl+rMqTz|%B1t@i^2j+k{C<GAu)@Q$avMsi$#GM#?Q=DdkJ|jA@3#Ry@b4%koOYu'
    'A6-J;%fHR!-^K+u_7d-2;{9GE-pnZ6Se{eLy^1tFH*8<_OD+25uf%fsSN-G$LNEYdF9O$8ZLb!7)u3)D'
    '0e7(OZEBsV<!NOB&gQaR;q`jaPJBhIhqlq2jfL1cfl@qK-%6^?%A9vEPYUaM1fh~3p^cEdp=8;l%-WNX'
    'Ek*QiEMVpl`d!&!56k7yQWo7#0_C_SSG9=njm6Mvrm(lg?j_U5l1ydx-CjJcl0DS5<v_S9l~u`F^4G1('
    'M7x()_wwpqUfs*9dwF#)uRbZO=s%t`y0?t(<<EZ<`7<+^Hjt*8ik`eD-1eepzNex}=q&VIY%gvCzzxLB'
    '`npNw;$}(9__l)PR%`8E#LV@tYA)#I8b($Nc!l=DZRcq$N-A5;ww<k0?>#-0-%M<6(QUk~*vgwO?OI^1'
    '6}`81+J85qYQC#%OChzix9In4PAy~UTL`echw6r+YuSO{n^5;6>|=?r#eR5Ag;%wFGA!$|zEx1`USQn|'
    'tb2iVFR<<f*1f>`=mP6r9NpVc_X6lYqyQ?IOdIr*Z76|m)K#`Zddqij+faH__nG}>(p#?QY;!qB)p@p5'
    'rYiKGZ8=Y8p6jZPw2vT5)%UsDT$U>BQrodCRVNSr1IbdVX0|P4sYWerzbE5gmu+yXWvJ?AxO<b{UZUE)'
    'L{-vXw}C{}RhQkyp^$sAYA;sp#j3qnwHK?No{8$o3r%~&(_T#aLyJj+f!InSo%Yqm-++a@CrsMHEw-*d'
    'BEaZFR+*S|$bwa`dO^7OjrRSd>!szDX(86t8h1bBy+N_e^ce<Ak1>G$ESSg7P_Ud$;T^h+QSaRYYi^2F'
    '6D&^A&R{TCj4R#B?f*sx6zuerF!*^xjH+*c=-rU!G++850)j#P;~xD5P))ij!w2MN)>DpuPd>)<Rnm&%'
    '=C~5Ew+FYZ^$_89w7XS_7$J0Z%9^Yy<kPeR8ta@Mer66{TtpR~T-^urto;z%C&HxW+cr_7)Fm^XJl{##'
    '4z8J_VmkA~sy>BfJ>3hfjdLJpLOCU`T-WVP2%-qd)gDjldh>$bLMudh9(D!^;)3Pptc5bXHtbE<oxK9V'
    'n@@!=<8r!MA|krRM<oO%G!>NJJz;+fmp=I-{kzaplmf}nK%Pw{6S>fCZppmcEG8_WvnU-7;9%o&IfaZo'
    'Ord3qPX*r6_Vf(}-TvW0>7pb7m#-<e8lhi30gA1NUVOQwZ~?ax=JHNddB8C;(rf3S;$l!XpSnrqC+Uhv'
    '&vJGG%Dd#k1dJaE?5Ij>9`^pE?h^eFgI-D6K+7COya$P{NvSmfcs>?uz@=<T-HSEdWELr-#0wzfWsZFb'
    'FrZZw+~aP@xPdHy_>3Lkc!AjwZ=05Dvx{Yx`kt@!Rk?WGQL$rhaXGBHFQ0;3+<B3hQ!i`89hR?9Y|N_E'
    'Xb*C_Z0${SP_4=yv{hnT9_<FoYsuM8wb<-jZ>70zaJ~;JHP(Yo6wjRAnW~)!)e0xM+?diRRjX&rrqKDi'
    '9IwlV`5X@M{d8W5)l@@O^DpTr-Ac-85o;y=u@&8!m8g)Kk>l|QFO!S$=N74Go=v(7v+lfNK!v1352e$Q'
    'YXV%|96sM>ops<%w}^8H(zZ7jv!UqF*el&Y&Uo33WzB$FL0PiP<l7vPNV{>6YFY=|m>mu(3=Rx!<pzfm'
    'G!;7xNWx?Tt3fq$W%h*3pm3ltB{Z@mFhRVf2|;+P3lV;Y1_QZm#X(ym!KOVciq?VlVp>6oPi3R($dQ7a'
    'R=z6-icLBA{{cS&H#`'
)
# CATEGORY_ROAM_FROZEN_SOURCE_END

if __name__ == '__main__':
    unittest.main()
