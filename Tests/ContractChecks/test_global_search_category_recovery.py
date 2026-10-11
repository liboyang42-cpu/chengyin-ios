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
    'c-ri}YmeMWwjlPseg(T`JeheXMUhPAvu=&LS}JuHMlI=9Nj<x())s<fu!<ulnUiEns?ij%@E5P)HP#>e'
    'Sa{b43>$_G?0Ofr;R{?Cdw+~Qv-f`TU+_5*!DlkFvXa59(zFuYs;bOnoQM<W9VgD&-`{_{n9petKe(8O'
    'i<vT~7hV+4N$iDzLIOvjABi0+m+)pd_iW-THi_v)IKP6g66b*zD0UdY19lv#`}_NQ?mV0-GZJ6=o~3xx'
    'SvZfCm+<GF_?<*?7ao~ib(KpJ;kUZVZ=*2i!gyUJrqh}0`S9B!@Zy+8F&{AbOPz-HyJT2^VqfylU%_XQ'
    '`dG~5@g=q2MJhgUJ`c$h{#nHId`@RRxk{csd-3}8@$vb|^B;~+&yLSvV#?`@qwmj4@9*uMzIgFUIb@4y'
    'pP%FG&d)pQoJOJlp0+#cj3EA^H^$q&v*Tw^&tD$B`VPL|Vsm;}oYO-#rv!y!aygW%v#ZwL;}_3gogO`Y'
    'm5vmLp&vb*F9N+cI;V~YTXBxq_W~M4=L!B*L}P33^!4-S$ETY;%fTJJI{x;>=|4RG7JgYj@e4n+h<_eY'
    'GPf^t%b<4np3bk5;f|iY_%@xuDIjVww`uh7SqSvw{hnApRX^IWWG}dgT6^D}oV`Nu$pc5T*~3#n%y*3D'
    'u72?7he(Y+cy8R<`{wBE_&mkW*>^`qe}K>Ex@{ZO&}`Z>MviR}!?j(@woKFLTW)`(kF}B38`(qMF<sLh'
    'QcCr{ty>ncbjz>?Vq}54Y+ReTWIXDREW;%F$nA}cp-uaP;b^GomJYydx8Lj0!NBS3j&1gaqmiZe$<TBL'
    '8X1n=9Cj;aJ=As0gjtS_u|Blyq20FzeTVk+0j#4x8t6o)de7{+1HIRC27^JLkU?*x>HQuV>p1J>(ZBhJ'
    'uYi~j6?j62X=dM8TAOQ*`-a}9WY}{occ8h$p{<Xcp+=p7V`|hM^&HzVZPRcGEYxwRYYyyz4htKOsiwE~'
    'UYwqMd-D9~*?ED4av%np?r3AjcD0eMX|C?j!I+Glk?p!B8H_D5G{#1M*z1iD-as=nzz8(}#6SZC_FH>L'
    'PmW%`I)1Vef=>FbLk(&=qu$sV8pPEI9gP7=gjf`oG9vD%M~80D1tJ(b{k{WG9NngtrknkKiTux>96x(?'
    'g!p^Y?u|!X#o8C*LI|rLgH;0V$3Xm%$SU#G)uL&&7)T}DobnITuX@335l7vMPZBY3Ze79XKL$Srn+vWV'
    'gC9<gf0ILN-yICc*087d3=0@&OsF#)k+C@*n3Pz+55RCe*tfm|d+2DyruNv>OucUo3}O#QtsjH^n#jBJ'
    '`FFZX+Z>GsCM=|d^8p6PDZ*8lZ_mkxuJRY4&%!W1#5Hs#KL!fC*a!G7%y8Atw$m>i;y)e!q(BY|_`(}='
    'Dn{mmGE9lbTC!%n4QxbRf7}}|22#WeAi($9Y*!yD1to{ON*pm0v1WYD=3Y35hc=sk?!k!qu1cba&g0|X'
    'Er{P16sSg*1W2UK2JWbr^rPcl0J*hc##Oo{H)QBLFcU<B>W9RM#25#P%?+sXhwJ$>x6cgOIY2Hf8Ce8B'
    '{-A(?RkBD_53D3W(<FPOa>-&|Z(1%T@dD;!p}ll2v~lb08wB$9P0OMHk)CtRwBB}crMG=(9qJ<*-#8aQ'
    'KYnc;<N}K73fA-+kxhbt&J&@TE`q-eds_X?c0$I&zKWU2#BC%m_9=PC>@wH8SY(D>k;?PCp8*Ex29!>b'
    ')C544nXNW$Tdf<GeS>wDto>$Y`ca4v_(!jvTk>mea-6+4;M4?lPfwnKzCHQ&_^e6@<k6!#umlH0KATlh'
    'j;t6ZrXOSWef<_vAz4*PFtqHR1~y&4Hyo2b*px#GHkoeH@pwpvU`0_fAl8`nM?*0GhAx_HgT6(~v1>T)'
    '*d5uej!=g`Nl{pw&KK!+qjbxJPkkx#MY8<)OP0>t%!x^y>C+c^a~Rw&aD7Oh7<QkGiER#sx;g6gd)B}h'
    'qOa6<N8>*DOG9@+$F|)cXtoRU=?}F&IHDwT(w{zi@#2&@USnfmk4#H9H65H{YXojJ`locH(;=+Nal!o7'
    'EZsHqvDqI})6)7HIL(B*)ExG~dp!B}`HR!MF9&Y4*|QykjKLQjn>P5QHu%21zG3!8<DoThscZF#Lu|c2'
    'FvmS=8CnmpGu9~8#zf2ca$KmOAJ=B_gl`!EpE3HyfP#o8zz#fyZF$H)_@2y8S!CoQ`xqZiKYi-?F`b`X'
    'QW}eIbaEhHzkK=P^c4eHD}vI^A~18xf6Gt*v3TZGJi@s)opAZlbn-Vm=Y)3jkk9S`pWTCGb`R3oO&$E|'
    'ZG_PtkEvDQCYd0HdQLGucgn(ZE0(j2$)&)az#Ur%e)xcW_&|IJQ}66OJ$><yj-O{F_h}t*OeDCGHxL+r'
    '=mFadVW@G>>Ql=i2Br4MbzI<4fMn@|f#I6g*mOq&aHyO?&l&dny-|PMH=Qvd&IUvZP@Iw0?~h?AeZ#dK'
    'T{EevS-p|rT0PC_TlRQhfjDuE;lP0Z2bPO$N*z-(Yz<~-)*(s&Z<67N+GId&-Enn&=<2RxfDr1_A^z`z'
    'NU#U4?%1QgYfy7M8aam11L32M4P6`2tqB`pyF&^~9F85w92;ZA^2iw3{T|hcHXIoP_&EaE;=;~qV_S3k'
    'eUObVA%;mzha-4X<^XV`(SR5OXY7)JWnm}}h67-(HG-Y99YE}`Z}$2+>?Z6V$YIUY+yNOH_GmbAY;sEm'
    '1Bf8J`?iAwGSplP$LkZIS=S;uO3I;zbZHKVW{&^`bks9+YJk{uK+f8*{|N=Hh`9m;0}ug3YFV1rb6jlz'
    'N@zT`$GQ&E-UdP+P(!oEV`>n0hzbCd2`qhN5|H2{eQ4w%9DkhAxkm$=J`TZZ2rz<^LDCF;G_r|n*s!9J'
    'LqHz_3l96RV~#<Gh5;*aM@Db#j>kryxFcsgG@LPP7*G;WbINc<P~U@DmjM|7!l<iL&DHb)Y|d!dN3{p4'
    '5HyJ~fPdVvgHcF_fMOd0?cnx+W+FXn1lx*0Zi;FHm@#TQ(C!AYjG;NQb*6J2AhaQ<xj~PBmh8ia0Lw9S'
    '3m~8wKuuk94Kf;!s)&A#ump$}g{O5;y5n)rG(fKOF=lJJy}=MxMD!7?XfPh@1_%_}?Ym>c0HhKJcGLuP'
    'kSzo*Qhd(=I@0<!9aDQ?fF$diAW$@OY|_El=vly6#>fC1+lFaUTLW%G>US-mp1$2%FSJn#+om>lEZre6'
    'f7b;$3mn=T4STR>JzdklR4{cg7<6lBj)zpYKtK+t1|oY%%-*=)y52i_`SSF|564fKA;-eIjhY2r<tJeR'
    'Y<42m-QW;vEy8B=kOhC4`Rx+VNB?O~ry)=xai(4r31PTikZmS}ZWJIJF#qisSF)AU-Tvh9?cT}vFP|NM'
    'fBgK_(W{deIYX)B&MbxGGw-V4;q2{U^m$HyxA5k)4P*gZ@8MbR6!x85(9UF!MU-772xBGvoWIKhC0<08'
    'Bj#Aa2gmbyIBzEp@A2UUFbp&B2j>(#?4Uen{Jc0f_B8A+I)Lwqzo5nE+bo9RET*%Ff82#HM@V}lvOVwc'
    'De)tC&kGzNpF^Xg{8DLQ>{}H>CJ==0m*M^be#uXld7Xt%&p&waCG6`to`?I%*Tv*GGIOg|4iA-e=VU+;'
    'uY-3%_#sfhd78!GXQzkw2(86OW@|(boP5|zA~m7wMl|j!#03clE;5UYVAN(#K^jEVX;&Seb#fahrppFb'
    '?QjvqZ8jL2wa!uu*k^Azs0sf8xb$ftzWElv%4e{rlwPgxk^O@UASsYfjskNAR-mM?$RtxCnvp;(HossF'
    'UqF5fpv5wOS(sU2N|U!$o56_)XS?=f6!zoA+`I4s%%%YO<I|WHcSNx-NpL}(Rwqx8Y<NLbHZnDJ&PC`c'
    'J5CU|-{0Rq0?`;N@g-G22rLkmh|cMw2gtb!&-f6Fr5|S@A`*7wiUs%>KeLpM%2S@g`q^9SBbkU5Hp$jA'
    '?>$ZDlBf#cV(<dy5fAN0i`mTgsF*~8g+&q-6VP&*4n<h(>oYHiSUgE}fklb$x98S=`_Z)Xk1I~%+i$c7'
    'WAea#`)OcacUnK+?+S3mbs_=axSV*qDfJb}F5S}d8sX7aH5V@m@i+wWMtfTwhfT#xhs|O+Z=uK}Es@`o'
    'pbsZQ5H(ZW^%&@klgJFT?0Yu*8z+l`G?@fWA)Rh2W-3rHwLsZt!<S@EDO_9tTaeHh89fgJn*?FNl9B-b'
    '&H_lrCRKRPQ<2cz==@`_cal;Q{#7E`Bvy?AuMj%8-YbT(fqAHndtd%y8qHo3hys~nIy~^qR+o&0h6tAe'
    '>4Jbaeoq4sL&OEM7z7fVbADNG3i9S{j#&yHRIp1jK$^moe>i=!;=vUQ%En=<sx&N0l==+zpYso=6($Lt'
    '5H<^~gDD2gQ&ey;DS=jL*lLt?3R{O8wiGn{r4j=z(RNijSbitN52^B471mcTXxz?rDUUC9{K1z7q)eG6'
    'g!kUGn1)Hu9uRqzw6a<kA~y&Hf~wCiA+3<(SEi$C#E9_SFO@<x@0UtD-R15ooxg+{5bfbSPS=-VNa{*C'
    '6ckP672bY!`HZ%zS>``4&$b0V7xBZ3bVk!f1Of>(5)-?HN!$FZ6-vLGuxFx{x{1(TWn(6?uVC1MGC!qg'
    'Cn;gzUy0OC^h}o1KE;4+lJ3Iy6?C-Xf>o7zd5MjX2y@KtR2@oZ_=}i8Nnm;bGar%4s<>>m*i2}1J=^6p'
    'Gh1Fl_~C~#HEhbroD|bXE*HT&)FE#^iL=7iL>N-(i4x3#aWZ_uex@H>GdwI=)B+`MT4<#L#J5!vqe?oY'
    '4{~sMJ<RtOmIt<7>`lRGs#-s|Ukt4<Rz4SVQXu5QBueL_`6u}SQ7X(Bq5ypl&~##dfbERmXTL9VHs=|^'
    '(!z-cE*I9a>xbx+%mwL!(Lw`<sa=MGoNbRUhx%(KQCwXWYBS7=J$_q>5g`qPnF1qm!)(owT)_cI*eO{o'
    'ZdcL##}@@(bLEC0xKE``nJmvfp~#A_WTeA!HR1bneZvOvZ3yTG|4N7uil?{<*;Nr+vN0R8TV5mGO8u-C'
    '6(vERlNhP}k%;USD_OmY(%8AhZ1(+vLIFCg5|PC(l}L1BFhyH&t=Gz(D)9TgaDk$)V3t=|g2{J_+)#GD'
    'P*O0rYW=raT60OY9y97&@}M6u<(3-%9|$+Hk|X${dQHFzJ-S)iUNKEF!+2LY=l`J+T<M_a!QZ5}VOsDR'
    'j0Gd2mAJ>gKtIOkHkb~mt#K=~m9x($l~&9eH1~5Lb;SY8L&2Cp#4Lk@OyZ{Ei6k+&NC8y>1_Av@?FFEH'
    '5llmH-oaZ>4FMiQR`|>T9ZPdw6H-`X@7#>l9C_Y|S*FIbYb~iiSg<{BaumuY@^xw0Wgfe|uaX<>HYbB`'
    'S0^tf&~7zcJ}bFAuUsUCt#K)w(OoG3vT#O~3|RrAC?tx}k1E}o#6C(<wJfNU!C^y>VU+JGt~?1s2HLkN'
    'MZ+UN?qQ5027O1b&~FA?n$dKYtq%5JE`GwloQ4fj;uBv%e(dDTWyYUCf!Q<@3;8+;pbIfk_9*$=Z(1-f'
    'Zl}R7nW~J*92^_~pL`AHoHKJo;1H&V3&Od;f_$Kf_w+mt+x+oPC!M$WM(#AA!hXoJ6dysIqr_;p{-V`M'
    'j8WB#*zrQL!u*CMvns|)Z~=Tncy#k}&HgRhS0#1O6*F6n-3*Bd?tIS${j1u*K*3@rq9gbw;4it?roN(>'
    'Do5s5PhcfB8hohvT<_yyD?4k$V;w&Is|R9^=}s|miKD6knJ)QNs|h8WFT>7ZG9nLr6+RRfE7a*b$HQG`'
    'w=51{&DjaaM;Q4$e8>Lm6d(IA2Uud~83pfU=wZn=NQ4ulK-e!vX%jIE_?uyG!tix1o?Fs%zdTg*y>+{_'
    'w`cpHsFd`e6Hnc8u5EH87PZq0g?Lu>m_&(-jA}HZ@#|R|Q~GjPV;O!M=k4yLgYjcGuCC7Y5kE6yk@s^T'
    'aVuN|@DR7$a~Y1adH7o(514X!9;@_YmCcdNxvMappRFa0fjXX@#xXhvsqTAu`hsOYrg1>A;{5x?1s^bT'
    'I1T<iKFWmk-pV9Nl)MS>uA&b*>%Urvtl|Uang=l9HW^#_gYv1cS>62E!8Om$Ev5)`)(oA5e*|_hp|s{9'
    '!yD~w8Xi~!_y(UT@4Q!KJ{Mf{GKn%*?mY2*K)PoZ3jChfgXf90otjfonLt;j5+_;08)X!O(Vo1yS4=y<'
    '(L_)8<;ER^0XwTLlN+dU)x*qFxfymcdv$}n=5$4?Qu9-2Spt4;*twAzza^1yklriEoxtGA_Ua|PD-Re?'
    'vBB4*#aBib1lYJb{thF5$`kr^nUFJ5Eu5%>F?0_6d7k+(=ZPuKNZ-FI6LN;jRN&umhLXRhQElgoF>fXh'
    'exsth-X*_*LX$BD=4hzr;}&kto6994lx(3l1k@v@KePi7Oc=AZ{e=UVjN`dyf$JCX6bNpp;&;&Uz=u8%'
    '|6Ln@0ox&>IfJ+S0?W#ayda860Db}ogU>yNo$4_Awe+#-E&`i>=O~#*_0afm`h<#eR$-iZ9ARojyTuXE'
    '>a5XDIUFV1*3Bc1qqm4x=1Q$WDVq@*Zt`*V6xN9odqUk#wt9qBSUBU6wd>|<$d=6i7OOp|CbhzMKr@fC'
    'x&KTNXAZx`lMg&kK;Hxw00Z!28=jjH1Ak1#Dd&`bFAe*Or72eET&d~EQ!;<Y5(2E&_Sb7$dpBJ%5?L!8'
    '8ZK_7#7Vqtlr?y=BShUfSkUL-H=GNH7=?x~_LhW>%)37~TQD3Ltf^pH-7YRr3FahdTdlUK8KbVUzb*{9'
    '-|8l7zInbWO4MXN-bH{>&r%9nS1H^rDGBFp>ISZ%lVu}<hsP3ExZnqi@jAj~S42@1c&qH$R=KrHt7VY5'
    'QMy6M3FF{7Yqr~|wjiH}xGDLdahES?4ca$wbh^q~a|@tWs<pBSU1llN)QQu?W_dp4(fM;cYyb<D@t8gL'
    'U6v4fZu=o7qm`KHXUfaDH%&qTS81vfvoL+wJRT{SE@Dp3%2|?kgpM9aq^n4Y$b0IjISSgCV3-6zTnVo|'
    'hqt||SV++UDe8~Z{TDk@@Y%B@!W3i@n%OG{UXs&tfQPaWligbEP9FS`yK<M*513;@V@a2#HiXYkd)lG('
    '+r$AsOx$?^=1}~s7$K(>(>b{cjD>L>v0Oa#%B=}LTvmyw)p#W!6+Q=_nI)%UfFZ>;EJe(9#XQ&;IjTLy'
    'tkbAnOgrsNZnOCnXR8G+YG@(}zW2(TCD^B8vnp^>-iV3F!+i?e0v!DmgBCm$7iD1*1>9S)y=yjbv&|E8'
    'ubAixd@ap$v%O125X=@QgZkP7&BWzOSIMVRWIVTg4wfY=p7Xs=xHc!IGp9B&a#jn8H1RR{ZaX)6C*|6*'
    'Oid%}g~)R$-oE)R_+)B11PNo3%qXLi{Bk+h0&cR8tMmx}Ub-ZtjnWR+=7!>~GR2ap5s_E_A!3R|*d!5G'
    'CZHdJbAD2uhC3K3M3up~qVrr~I4m7t7hT%oq7z|QokqjMY~nkcCaa`6d5Nx<#Ko--+v`qw^-=jPXTE+C'
    '<*zk=1i!)5S9lRD$t5~p@Eo3uNJX;7Im^sAN1GX33Jb%=jspa1UCAQSZ4)9lp@q#zw<5zxX=yFxFO-3~'
    '4ROevnMfv5XW^{fxdTc~=fiF@y$+HyFmapctx}Z>lpt?81*oN`pCqY2Z{A*SN5WI@Bc49+G)6|Viy%u2'
    'I>#x2!*>3TUI|GnrWyK<I0oM^lzc;JM{#;`&TMz_4UV_<!M!ZYv)YfgNJN>_xN7*4f3+0tt6;_CI|oV9'
    'PI8G1HaL&HryO~zILL)P_Ql;Z7L9^!`*eN1x5{70&+A|ln*-&6MYx}U%kCEKoGMLyD+_{+U1{&Hvj`*`'
    '>!m}w<a_**)I7Bn(wha&IlE*8qB;vBpF4A4JHa8#E@<h*aDxEy+G|%;x2+~iPF}Kc06c%K3ID9T%f!4t'
    'cyGlWt2CsFAB%A|8MemeRY%WZU3q47_+_=6+ggrbFekPm9Kou$>@_f{Z1dP9Ih2wtKFVSoMRcU|FWfw1'
    '#PB9V>09L=EBf0`8O?ere^tT~ip+p{6#T539p9&C)j<6`x(RZ?bKv19jnlA*49mjE9b4rVeU1UAd34LL'
    '8w<X&43)|xvIObp8NQ7^EOaTBbu-8}`dcx>H6gL(X>|D%JIk_{ueQYX2Rx#bCSX(xfp~sZ6#y!vSnzQ~'
    '0H?D7Ih@i9`msb46`3=w+eJED6xRNR)7>aKmaiiw1ZV!lua4hZ2t_2g%PFD+a7E-vwsX3{G4<_ewmRj+'
    'rf4{&M-jq_h`<P=GZtozn7do@J}NCSb}EpT|KykX6EI@<EN=x*@DcRY-S{Czy}Nw3uPBPSem&$9Rx?}_'
    'EN}j#s9m?5RI~2jf&=JuH_CcnE<d*k;r)OkCq#Ffbz~u6zMgVg2-u%!1V!MZ@TmK2VSzbx?syT;)i}pM'
    'd7>RE)27O&g{4#*P{yMhj<Tx~bc&DV3Fpn43J4<OWJ+e|;4x6FLlLhmx{+4Sc!pm+#c$>-H@uy!+I@B~'
    '-Y$|KLuIrg!RI7s@3+#N8notHPLd&rURu?HaK<n+7+V2;g)Q$da3$CKtBknPp&~Fb?p_SrX>-RaJ4EDl'
    '?kXpXxqsyv5UUQFF@^nS3QyHfNrsifP#FG|kY7L+cUx_LVJW8uzv-jy9X<K}<m?P@j6OYi{_XMU%hQwR'
    'SVpWh*86&Yq#4?nU?Cvg)cd`@J=CaSjESY&+CUpSJ=@Wop*6Dlrs?Vf_|I_-(l>i#oU0Z0>iGMY&(NHH'
    '@$~80F^)dy>mzON@$1vm<L9r=Z&^EL?}p+rdpB2)*{fSVX0Jy5n7wTa$n4#sg3R76OUUePQbT4>P7#^C'
    '^;Kl{HY+2ucViuyy$uS<?A@-C%--!w$?UDIC9}7EF`4zxCWTEv$$?y9LMU%NBm?9V5tzjt&I?b7lijMX'
    '^C_->=I!3`KX`R|1V+Tm*RSw`-WiLm)SC9BD*QG!h^`ZTG&Jp=ZJLJb4lQ>$a0UjUSdy)$Q;<|ne>8Rn'
    '*rQ;qkLj40dQZcmUAEa;lPb6IYbo^SqOk1Qx@iu_eGqz@Z5qA7Xk-rQP=gP~rlXB}eQVSkjf|0Hjr(J&'
    '8)hF%0_y#7U(T%3uw(8nZR_keCr@92Xg+&|ThfvMr}DMG#9pt&4!`&ioZ%jy;TFG4cR0^(KL-0v&8wA9'
    'Op-lzu4ocVTbU#$watMn)na0)G3h~MzA97G>t^m8v&Yg^r#4YzfOGB#x2l?6WhCwnAT;40b{kxuPr(12'
    'G`T2dfTD59?$QA9VAZXUZSMIt4Y+acz!kk=%bVmD=aXi4jREYu{V|Xt#+UTW?xgrV72*xb@ZF2>`yj!~'
    '0=z*;<<u>HeAYC?G}6`>l&yNEG&Y;08H+H|lY?Ux<lF(On`W8Hb+wx|H(JZV&gQg8tJp=M;Z56-!M00#'
    'ZTIF{<JQ_;8Ed<+)$YVp%UNpIZ?A6|7O4zJ40?_^9=T&fADNcxxJD2DG{^Q})a#i;;@JJ+U_ghx(Qstj'
    'y4$Ct!EmfugVAt2b`09v!eU$sJ~&oi(_DKv(E5(yI=Vr}Bg?cj6aUbuYmCf++1L96N2BHdW;+;-C<Y~r'
    '5lls++svUd)F6!_C5}{T+BcgQBTgb}*!~M?MAs_x{gX8)<H(BsfD(t#)$_cTJ2JbWhgbD57xwt+>G9cj'
    'JWzNxsp~Uk9+Ipn%NuCdq}K%HwIo~8cWF15tz;qF&k=1>@g*3w3JzmjX&a6=ug>$$59KdHzO-pf*lZwc'
    'DzyG4ryG^3-y&q(cg()o(}+HH4KlRNq2bt$F&OK8O&<>j`p`A|PG1}L`h>6+UxrPL@v!IgdiJ)0Z%O|X'
    '+a{!E>NaS4tw#nUb7<>hO0jFn(6YvkHn2uL-RWtXt&={s)X|3ywqSBxYtW}#Po!BRpo!2=E4#9vCfv-)'
    '2TtIUE%^dD7Aspz1(TevpM7_fYxyXBB_fcMTp$+ptfhisb(o45kd?2p+EkKPwV(fkU(3r<f7)qfPE72P'
    '8Q9!s(nVn*3|<VAEgSoq)`lYA8ft(EcgTaXt(W@|`rCyavwLHvQHy4W0=ap4yc==6TWNeZ!g#eTzOF5d'
    '^EOfP9?Sg0%ooXLc&&9+5jzbT13Zn<aUP2@jp^c&!i|jr&bucWWU+nCfz9&iKOwA1BO&w()+_imQeiO`'
    'P(=>7Xv)$g27P)#?5nh5Vh*WIZCoC8e6=FgJ-PPP5Zuy|-{2hH%I18&pyW0Z_gp#6a4jbnSZ=rYayn9y'
    '9x}VNVM)0|L3vkl@@~XrW2f%-*4h>ktOoZk(={?dtXK!rV{&cz3eD0asqad$+>u_{rCQmgR#~A`nlZpr'
    '{E70)@95Rrq_kFpRsg=(Z8Q1Wc;(f#TrPcb!}z@Nwp?4jr(Gh}JhH)qYY>#wfkWRp%-@QykY`EZnzwKC'
    'w^@~_wO`b7U(|Poc34Y;prq6Ge&I4Qpg#z(HEpX@uDR9C)t|;F%l>D@!TT#NmS=3-O`DENU73&r511U_'
    ';g6(B&P47CEAM5s*j6>+HtbBkH%=V)Si0{{xECN{Z6kK;`>@pG_CO}y_fs&NRyKQkc!Ru`Dwdj3cew7u'
    'e53Xh58aAh?P;s_U$%ZMbZT#It&OU)Mzz^JP-cybt2<I<JJV$A6q#ICMY5UpGv)EK*WaYAGx`18Z;rn`'
    'dEP)~McN2rHm6vBAPq9aX)mruk}Q^Lsz?RFR$?z;B~v;-Pm4)pm)%*975GvEOKTtto2@7H?aSeyY^QcX'
    'h{w;LNDd&&RSP@fp1Wb5pH_B+s9ix>^Je*YWc}irjno!azz9NA8fu6tnv$q@Bv2cYr*|Sw*Gbdsx7XKu'
    'k57+};FI&GC;#Bp>(gVA0*i&bSk0B>TJO;!z6`NK%J*JCt7`8oeUaS)UaFD;W4;c&xOiuneHCl=u$nHB'
    'SH3WOtGXuqFnsPg7j#u&o~5~d_v+QlGQisuirKo@N{w689Z^W-<q=OJ5>>+`6jQ-oo43C5RQ1qi8PoOi'
    'qcbW#J^Br=)5^--AJ*KVbl9_3IOcc9&t8gN0yy+7(31|7up!>huN-I-l<nnvLatxr#wD2c^8F(#C$+jC'
    '(H<)fxFOmrOCs$FB7Svxe2kCx&5_+7y3`&I2_1}0%jr==12WMEu;cxnJ|w0-rbhZ;MeE1jSTo4LwBRw~'
    '_J+NI;ZmcoTUO5+SUNFW-612xw8+rVZTOaJ*geZNsjF++z;c~*>;&7{&^pnE!?8sMgMmIE7Nvd78WTDi'
    '+IG*;+ySwBWY8a)WIWUf=@~soH{GE#H2ZdMIOu0XCpDt8p+|1NZ#aF@b9*Kk4Qzc(dPB`Nb$~e<491RY'
    'nWhPR(sz4SPwNeBXVB~S$9>Cm-SN1e4xQ|0HZ<wGecLhJ(O{^#madsvpIF15YZ0B;dVi>C#HQweX!gi)'
    'utJidQ)5i~4jF4Uz*<7c>5Jb~S3a+e9~30z%L}97kPKnDy|Dw+a$MLtTc=bXX%;awIy8F2@z6D3H)+qI'
    'HW}I4U^p1S=2KTQ#_R%R^+g0`!=&A5r=k5Wt!j?Jg4OzXjSs<YX(#y<S;@Y%H??T^8@(~!ZZ|$U0vOqB'
    'Ctb0+JSB0B<<IZa%%~0X;tRy;5{uaLRebjx@xW(_b<WxKXnu$*GS?DF%c(q>SG6rJS1(ltCikD5oIQT='
    '!!bx+A;e3y4ga$Ig<q|%QnF^Mx8D?*dr}N9Z5ArJiNwyq@WwD%d~PkGq)y;;#;Q~&4Nj9^M3=vt?iHrV'
    ';)k1D8Drm0AtcuTcof+=JZByPZ|R)Qlox$SpSb}5ODImp%g43T0g@PYMSQy|ti6ggwxRuIwjlG|w(`NV'
    'mJe=z5~5P_Y9=h~WY#vaa+K1Fx=Jg-LTmNW!L2B(X~L3DSF72Zd3aAwPLCfm<5GyYO!Kdz{1)iWfr~W;'
    '2Re28;}IpOFg1f}+DISwMphrIx6<KgpphQ!xx^U`Xy4Xcq7ehk?=_{IZWJsG!I?|Htu$e120MAi+I407'
    'o>knvF^GT`=$eJ#KiLHe4r=+f!@51VY5I(8m##9r4(9Ydc-qualAc(+R<BqsqsG=ciL)JDG)WdWi8?t%'
    '@mb0@T>2W>)-;_rO6F3iyb<#zb+wt3UCX5TneytArtJ*eh41I7fw%9&Cec~&avC}dpDJL#Dr6B~!ehMW'
    'jbdHh2n!2%+r;-_(4@y|0Br9C7x0l6<?2a12m}9$SN>L&=h%srwg2T`L)5Dq*lOhq{?d&cDI4*5GCp7V'
    'O?J(0$ZMC>wUW4+;q-87f%WX1FKrB~!%rP?P_jA0@9*#PBKyhE>FzxEm6A#|0S+tdXZsZ}L?vI(Bs2`U'
    '1v9R*Ez(Y=>CMj@tGX92lr`be$lMFLJf9rLY{K%{9CPem93Zz2<aDv@n^=9vgmp{0l15gm**tduC(g^9'
    '?KwYJS!uc1!8T0)T{@tGebHHcRMu6)zdGQOQ=nfo0#dN!mlDMuh-}`pF2Wo|-g#^Tmd~s*c0P#JQD2;%'
    'e0%cz=-K({@zIl$=f`JfH@h0;BAhtb8clwiJ-C72W$nOc#OmU+4LE&w)FhFZR?yP*+v~K4i^y_KJ3Opu'
    ';8IyN$sTGhrM)4=V;sw*2Bm|(sp*<I?irRo?8B$J13o8pG`**rx=U?qWLq{J*h8CcQZ;GmjG^xihGT2k'
    '(*Z)?a<TH!a74!Dcwkau^+%Sj+r440*LN&3bnv{y9-Eq}_sxMp?BQq=n3YEm_{rDouotMydyhZgleyxu'
    'Mm2!GJmUUpL2KPXT?I^Vjz=Sy+>@klP||+}FOI!=+Z52Nrvx|(8`HTM{*n#`B-p}_Cj~s7viG7#(t&}>'
    'UC@bg#u5eO503{7Xoxq3D-fvOd&;P6vP^jL*Ar2n)d~5v7dS<L_)Y`xF2fHIZvhoGhD0I%fs;5HG{imv'
    '%u{}{-`HxH$~jchrc{g)zQsPKjfo*P{H|cm<`hp6oipsXH&I@{K6z4;?vl}c8Yi1{7W0mWS%*8!D-!*#'
    '>MW|>OmY2I=m4ok;gl+<mX%NShQ!yIJr8|f)@b<p0rt&)*CxJq5lq1rnkcHz`@D6PXhv-KWrF<)Wx*5H'
    'Qi;VrZJQF<dWCh(_oHO@RWb1EfV_vXF}rNPqq<<ywpE+V&|<|u!GfLRDb!hf<<qtrQLvjGGQa9<J&$Xt'
    '=;7w7>P0VH7wuPYTrr9(5l<l>__IUKcZ^<TQX{?)J5N38J9!kbYsZ)11<?6^mlc5D`c6yh=iKPTuJ<3p'
    'xzkZ`xD#}7jutUUteF?HY)F=ipt5*FNA42wrA7;D>c!89MSa{@TxmxQgERIvP}eIGy{kcF<O6|W__*zk'
    'a;;p;U&FTJsl>LyL-s7s_u{J)JS6s9kIwTuE_P>MGU~rs#4&ivpUOs3JYP^il8@UlseyLBpSg8#VvB%k'
    'qpK*U(-TZt-=28)QBtTq71Mfu57L78*eC;JR0Q&a?eVRykQAdKJ95zO!av)Md$!s;iwTA~g-5pa?TA*<'
    'y(<hVe?PqF2M?Ikr%j<njvv{u8@XezZWm77ZhX4kxO8{mW!>atz4#E&`9#6{9_-h8w6Hrzt0iTg5vWo-'
    '&Q?EBu;qG;=KuDlVyep#3)~_<c`{L6u#4oG0U>4hDD#n}j8{0Co+#ghp)Y0J<eGw%L9eCkJ=b+)i322T'
    'yy^vB++Mx);-gMC*}pB}33rbT(ycvf{wh&G>QNr$-|rSSwBGE!=y5t$=ibl-nkjgq#k{xWK(+YjbEOrf'
    'w4W>YSrSp@_c#YDd$X(jj)%Cp4S$z(AT<OhH3GNe09=Fdw|f$PYhBC4jqKptUB=!dVy157?Jfdut#80B'
    '0uE|l&=?~u#VDL|4J<~t9~_?jwTS068qm9=c%H;?p5$oWZi0Dt5X);gl(#`7?^e~6*422;;X*7bx$&bq'
    'BFv`7c>8&O>w31W0!sE-I+Z(zWr?*&4B@KooJ?tZ>IL6X@8Yt?Nq}i~R#WdXiZDItN@hSB6x>%8h8t{C'
    '>e-)Qh^!6#QzK-YQE(8(85p@cL;Z;2f|97)_966_^Y8+kg$ND1Jo|}}QB`vSARm9@Iq~K8m;pb*MOWdf'
    'vxyK(;WvUdaOhb$bj9Yg&pLGu9l82h)+0@=hWmQ}axUW2{HJ{Ef&5=wV8S1$_ej?0*XoQo%v_Pc?-J&u'
    'lG*GzdGB2?E9Mmn>pX38>D{S!{Igq?(TK)qRAKB`U)+hhXhd7A;9IGiEJ5|`O!Mqs@vKByvudXat+Q?^'
    'Q9x$k3~b*hq*XepRg)3hUN9+!Fgub77+;C1OrWabjc$5^jAx6{_Fi%}Zf-caUfFeO1$>n-<S%|9i0trC'
    '2|Ry$a+0Fxmvx<#ktA3QEqOEA*j|w4WCB3{iaX)$0Qp0bA$C8^uNVYb+sgv&Eau-yMVmPKZA-Ck)iB^)'
    '9^0WiDaFYU<at*~qGn!zjJ9=-Se6L?C=JAYb(oI+3C2%q>dVR@gT+1ZA|Mu^MF4<_*J>Wh)+Ov)`4j)r'
    'kfl_Ry6dR<_}6G(e6#Q{s9MbN$i$oEWM!1bNr62tI-btrD>keoZ$TRGx8%xY339Z+`0OxSD%a=v;wWK?'
    'eBu=kX37{o&vr|xT?euZCYuB{^<PpR>j&Oj!<Jiul*Y{xPBwSO%Qv#JG)2C{7;9#bU<1gx$Y9#PKc)k|'
    'o`&;d0)C4?dRIYd@Z*mv_IW^Akm+K1fvxmtqjXA^>gEHb;96}Rwa>d`rHGG!R66b0xBbw5w~MGgP|m$F'
    'AtmX`-9@BibC+c0yc^zH&05)!aYE`HDO`0YOw~M3HDH=aQCWBIAU5F+xQoC}!$Ic?Yd^KU60W!v-oa8U'
    '(tQjzPZgay9$G3`C=x{Z(wRKi-?0Zv^DcsuK;9)A#*HE+$PL3d2xBVo;J3+(Qx^*`JJHydbsTipZdd~b'
    'x=ik>Vy>ll?VIxbkhdBCZ3$MMJCO_13I?8sA0)7@ga&;gU+<!L?Fq>~3{*TXq|v1~nJMz>y8Jz9I#znd'
    ')XnR>2O$xD44ETu$&|8D7OpAt_+=fDMKKYPayhUPi?@KmWxE&N#o%tO)HNK0NBY6et+Y5*G6z;yZEp@9'
    '!i>b1(oE28Q)HL;_?EmPYrEvIiF|Wt=hl#HW2ku{y2=!i<83q)r;y;q-~ssiG^(3Z<l+wZr^1!h<Sh0N'
    'f7rf|f~LL`BNaxzmf}l@rKBvAStrEz#dYoN)8W`5eh}v_N0gI3C_<IyQNZJY=U##Cy6{PaIm8Z)?77Eo'
    '8%&h)wFCzII}ekgq(s^hts{_%Dh5bHTF5dxX@2Gf7(a0^^d0bwd(<$wzcDPbEzC5SlIE&BCUXZNOmID2'
    'MO^3Dexp`gIFTCe+}iuISm=t|vwwxM4JZl`@J;Uh&PD-2?)#`e{>XO6b2`$T#b#no*HUiG?oc|)7mhc{'
    '#$_)qlauh?mO%MPE*qw3!oZlT&6{n(?Nlt^kyLI@DBpohZd@ccAd#h+piRr;+7|1>hssHM;tnhm*q8G#'
    '2p5r$M=gQvFPO+kj_7%*`+8@I6#LauEQ6uMp+W+MF%7?ptk&0|X+0uLGdWO-`2;JnP46_iUkEuC(y1zw'
    'pK>W#+xJjzf$BO)E?_W4c90}s@;@Z!LlxGTB*g$N+LTwONZ@o7f;1@Uu%S@X64Tc5sd=&v9Ew1SFv{dt'
    'GjYwM5v#Xz&`8bT<Rwm8VbFXr8CJQTHQvJrTMheJ4Ej773DB}s@23Emn-=%NfxcLP?5?h)z=#>G!ECQm'
    'V`p2i;_{LxFfJj(V29GaNnw8{vR-1b6D9?7$pz{85-+MHBXG?r^{ZlXkh+N7kqW*B2F)WZy5zUHg^nL|'
    'cv}9JfD2?=(|svy<5GSToAG_w#ge`*=Q>KsW?ZM34@yoc^GPMHuSs29rK))`D50ulRffu|X+CCd{Ib|6'
    '=-Mp-%U996)6lzC&=Mm!J5|pW+PRiDCey-BwVgC;8iQlM6Fvu*$c<W4+&-{Lz+(nV5!ZKE*&6W>d-gku'
    'ZWHs)EPCMuZBZtyaQCM^w4$%akRo9TsRqHD18cm%`k)-@vcM?_c!n#CbIjtX%`uo3S1aF`+B*1Oc3NfF'
    '{7xv#Q)B^VG+r3$uY_fqES|G0+ha+2WSqY?M*Q}bT@o`~kf^dO86~VHCDU5=-$sg*I1b+kHBH8C!13)S'
    'ZLKB=^eRnT6Pjcf8r3I=<4<1*ba^$2<SgEjM-pmNZ1mgtoYRnN1|OvQ&2ns;227ihWs_Z@lSFTKWjVFv'
    '9Ij&JL{^UEuvjNS%HXL{R(8R;eTKyu68QBGo69DY1fxlcy|H6+qe7T}g;6&oNp{K8M~Y0@psSSRa97rq'
    '(z5obD8+G4_@GEV@<IY-j9~GY=#oeGx`H_-N*+I3qdt$;Cc_y`SYbOg!di_)N$Q$l6-=As&`mf?3gt-G'
    'i96#g*vB=3MhZ;K4CY27?2RI1Da*q+W|kzopU+j!me5ujsh{y>o?0O|(HZ#+yYaq0xr<JOUw;pDc4ULF'
    'NIGPcdj<dHlPn=;!fxgLY9i%wUe+^XqLAP!b74;TwTk-f70Yrr?dc;U)Wlk=EG*x%zZWI;u#J1+jqk!K'
    '6)ak}UL!&a1D-)YQQB>GPwR)!b2?HMgL~oR_qm<!#*=(L768rtExjM;m%huAz{u+C)lh4%=6ic>-rQ@;'
    '0D~OSy?t+^I}zL*smH;4ZyvHsaBaLCX48Payd-!yTPQV?zF!MmQ);4VEwNK2(X5WR0~K+P8b4m0Qmz^#'
    '7`~57LpC?*m*61)gR)IHc>+_%#$oco@%`8-u(L}_<Az&6e(8+4newcae9&+^$sP5R+)+cxyXYvnyOxr>'
    '?kUL(FS#v=zjQ*qV;Z`Hwxm*v8#dlyzR6BkyK8mzrFVVRV_$mLH`u#gHk~q*i26UC9R@D~|EiPSP_EfN'
    '$TYi3@t*T0#E~HN9+VTyO4jQ}N41Fkj#o^|6-!b>thf_jwKY{6b?TfDDXmi+8?ACXCcy>li5<>C51kUn'
    'TSOB@A9OmhE2!oX&wtzRWb#Q~?NqttLBDijyuaG%ODD#4nkk&oKqw}Lo6o)n<KE|^knTz!$+}LzQ*G3w'
    'GTON=DyyQ}-qJ1`*42d*VU)7%MItnc&Cq|IH;_BB@|jb&_GuO!ZFBBPy0ml)XPx!$gLg~En3K}qNI!Tv'
    'R%-3}pHL$o`TabaZs^f`M~}N`=^?SF$Ddn=9toURw_E(Gf~lD_zf4*Sh$@knz*}fqNhm6|!&Yc}_f`=t'
    'Wq!}f=YUnmgVLbc{L~!4luv3^@e$r2-`W&Q2IbON+N_x#dz?<a=H${9=TZMSzxoE2u_Ke?78XZWx=)n8'
    '5<t(mDyU6PVw`Sa;QWgC-wmz^6lt30#<oXri#jE<?S10(qKy|c(1Nt^;tAw=A-46Uj^&hs?vfO%7Gp^+'
    '`S!O-<fWjme4R^_FpO*@-)UO;0*_IG7tz{;a;ivROK_V}j%?O0Yn86FEf*It^3!kUA>FGRPEwu32AWFc'
    'Jg-LSd6@`n$;J}xF56n+hahSft&IC78!HpX_$|sUAuML-T0X8wwrk%rn#+0PlF4pEX(vq@ts%7CP)xm+'
    'q@MxFd|r)dbKR&*RKc22pV#PAvTm=WPd=YO|C!Ca7)QXlC&kPq8Evdxi5T+J8m^SY`i=5vv)z~vR;PY%'
    '36&>tA1KX}lx!VU5p}*XdMu~wvy|yCX+FLK?c^E^|0&5!nc&TkuBiGo5mgpH>)v`*+0i1)bmc`1Rg`_)'
    'I?2HcytuSM9r^26d0FvOqgK`<X`|-~UBW`%Hn7u4fRI%UZ5A!R_{B1-&QOonaJodvh6WIm1~5NY%p{_='
    '8Pt5vG~=`R%Pe?R%$WKlsc80!dtwLGhTXPd3sItYIUBk5DjG8nCGOl>Ypwo9K76RWx}?gCTu_As7<+;}'
    'gMY!VQ)2kQ@#fU#P19K-r9u>EPTZ|?i12<hFDf>tzr$uGs*EL^eehx%TbC-)V(t<f)DaknF!czy)AupU'
    'D>{IwM>LL68gB_PMFxU-5B3#;LDmAus+0<3ODC=cvVWwsD>&<s%z&W6?8lBWS>b-vUgf67aM`MrVjMSj'
    '3YXa1nX3YtA&UfTJAF_hDj&Kdr3dq_kJ%+TfJ-w)4SC`|rxf%gKf{t$I_chZ5pN<Ps8~|*v&y@Wn!zMB'
    'fvHyhlAN}&_agbRyzI<JtXz5hjJ8q{o=>Ifx$SrKs>XG)rG*GM%W2i6J{M@BcDBDYCFeroGxGbZAHJP?'
    'PTLOs#T4bo8~pPmrqi}c95O@Yg0}*^>0&xjbfe$tyxqP^a@smwH>9ORCmjqkLPFFhyCF3zIk{pY_m&`v'
    '@PLb0ZgU;5KU0FL5!KD)tLixiO=VRx$&g;Nk&7HAE<oE@V53bZ_0fR!J=4oB<fFLkqIv<AGmWpxmscb;'
    'q`e2H3A>QHRbp2Jq9iHKEr)nH4==#fkIIc)MUZKK%_XIaTuqmhC9?-5R9j`I+7*gQZuVwQ*{xMtlG6sh'
    'DyFOCEy|`&^Uten)m%QC%rdI?fwOn3#3kwQ-KcQs8oW|R-9+iqQ}o()lO>LKV3#yxmNa0MY+{t$U|ei}'
    '$hgubsqGIo*#NQemc>o9K-^^y#QV^&SY{W*`fU)mh5Myd@f}8T?z~m8%tm{K>!eLK+}lyJw+!)ZslDC`'
    'cv{g?Yx_ID`6hj({VuglWecy}?p(UaXrz7F-QzsNQ=OCb`_N@<N%QWgk!j5+(wBzScV(=tw$<eIhg;Fu'
    'O1gJ<kGf!g=~CTbMCfzKT-r^O#p}1|Dz_fP_B<^25>O*-=KxYRagfiWOJei~D0dBQG^V=a^j%Z8N4lx&'
    '=FlLvOGh?wHCG?ezCIZD9LKQXo!(e;9I6dXQybgxi$2^$-g7CR1KKm~!O-fD#yzV~EsGeG+9TI-ZF4Xp'
    'V@n?l4A->AraJ=A182~4hW&nT)F1avXH1B*5zxy;@Gb&qZ^~f-wkvtFQS3~7IS)TXSn0na6?toInS(hM'
    'y%EyU+cCMADBqXgenl>lIc*Izx0t2zPs0yV)*~qUoKxduxp~1dX14}ftT@jUtc)dKeY3ODG9JTw&qIf<'
    'UdYyP0RzR+B`@U&bEM$sOL9TiE~v{=9Vgqb<RplfcQ+M0`FY4#TL1%FS8Y(YWTKpgWXd5O!QT>TES>&y'
    '1}@v1TiLWFqjtB_<}QRybF$_xM2%EQQ{+zM!RR(}rp7AXWOsrDn75Kvu`_WgUs~Rcu-t{L+^wiwEh%qx'
    'UQ;-*xvrrn9zJ}iykOa)uJ;jZxQO6jq+F8sR0%@GN#v0N4g)#B;A9YD4VL%dFl?_eC=2vP3zk#iE_~6z'
    'G*W9UhBwwy=*O4_5qL67t-)%9ZnBPAQxYtQk5q9=@g_31zIqLWIxxWx*OY5H_8~?mzE2?mlU0%BqmJ_F'
    '`p?b21}w6#C`T_(Sfg1L=q)=r*dFk84SS?UIPs2HtN{*dl)>(m!oP_Iuj@B&ZA^^pSc=?BySX75a{K1a'
    'D>LmqSBb-SG{E>OyKny$XHWHlh^TaS9GWa<Ysr^lVG)o;%&N%OBI2dq<QRMA^OrDY-Fel0UP!rZ%ytP%'
    'vC?j@ZMfholQ?HgFo4K;q=Fy^jyMyiA#Juq6{SR{ruTjagf5-V8zA%ha=uxj@y+$E1d&~(Z|frz%&e2('
    'x16rQgrX5MqS)O>JW(Kl0#q@Z%|S_|DJiltT<pbs4z^m_wpZo6hCV8TNc=>}3pS{m;?ksbvYo7`2~coX'
    'F-Zj%n!fRKP0c9vcRaeVH8G+@nkYZlJNJwao7XiBs+t<qQ_rZ%V=+m7ITwjr6XjJg4F*e0u&&fBgK}%F'
    '`boK<0iClWQ!LfNp{cnyfANdtO$Hgi#D9Sgwg$VL0U*=dDdlD47xT+QMXv?xx~4%<W0SY<HFyVmEOm=_'
    'xWjc~B-=mfO=saeR$f>UoxiWuVZP2RFvf!+kOyJlUuCyavT`3Ft&}jJX*ERAwtnkCOfFwTW%XB5Q1uqU'
    'OSE8}B86}r^pI6+>9QLbm{;j0w^v|A7jtmD;hVu#&E!I?AWrzjx*9gw*MbTV!C!w*yx<5il9Im{5MQx<'
    '5=Hf+_vLbNb+u*^Sqm0Zh1L6*D968BkeKi~mo`=a@f@r~?kDX6c#Ws+ZJ@e!#R?OT;`zb`Hsn?Hz9Z2k'
    'pLu;-LIA+j9ZoA)%jJcIhJJPjQ!1F83XwXlom%Mp_J-8K(ceXEpzLX4{MF&g`e2rMwNN|}#Y;KREUh#^'
    'LQ~4&5>bf>bPj|{Ka`R|Eoa&pEs6Ze(*25qB0<!jyB8hh2b8mlWunSfv;5hgNz6rvN)an4$ocv!1no@o'
    'E$>4vkeOVTKYF>umK>2;hLYK+G9bv=L@~d1MB~mz^;oxOz&CH3nemL98N9mKp`xOBA?MNrD>%gq<-Kea'
    'NS?YM$s4wctR)W5%dyG1P?R4x@2iSJni6rs3u8+`#@9J-?c^c|QHv$8K2Y+G0Zg=iyN-9UWHvN7bDT6b'
    'JD9MVPJj7B=z($m9Q~<ZJ(9w~%qXgVR_jn42t%td%}1i{dA(ku^(KUV=P`4lLWW(ysqeWo_NG*c!NZI^'
    'M$<_>&d_&i-02gwJh3OU?Jro)!qLNT9v-Rn*KnFt@>JeYI*W4ELL)Mz516pZ{PY^P(7|w+&lj^;oMS{_'
    'M_sXVsVP<EMT$ygHLI-fu9N^qDq^#u^XR^GWL>lq1uB@9C|6{ca$!D9E=n;-fA|9?Ubt$h66;rol8}`G'
    '5PAd#7Qe~5QM#;04obp;|D9Z}+j?DGr|@Cq%zbG$J{9i-V=aKZX;Q;3W44T}!(~zNyD+zVaf6>xnh4S*'
    'zS)7mF-Nf^7)ynVi*FnhXny-$;{)8AGe1@l{yaH97N%_O;6l~`brwD=-58b9#+nCG*m#064wEI}K}e<K'
    '-M+j%sBu2_o$exP{AVE;6iF<fI$j*HqU50BLHQ>L$kTC`=Ok>s@PNi2!udNn;qo#quILzCMV#A$6vIA}'
    'N7$U7yPT24Ogr7GQs}i>5T-o{B~<mvaZ7?`;mC^l%c@<zRJ^<pO38lj+#7LN)nD{HsgX8O(k`PlPw!iw'
    '8c<rrCflNea>!W*<spCP&Sln-;xnmrgca4&LW|Qy6es-|lFT`jVaZ8mo#?Uh;nD+33HCP)PfL_q_IgPr'
    'U*ZTLYAys{RH<@B#A*@~!tTB??^=eH#d!ApXST2LS_cpehW2@GRRLS21_T+-YU);o>*WZPJo-<Y6LANq'
    'N!sT{wq#Uf-NlY3^<%5ae_O!2*-DWN@Dtk1LZy*pZq-|t+k$N&O5eJrB(biNhEqhM{q`<$v4U)Owf88A'
    'LiqTsn^Ud}n3R<8Bb)nU*orCw?D+J7>tmf%CGx=)<9Vc*>9j!9ZH+R_$i1A0LAZz%^w1<^mS@qi6g3BF'
    'oG7U-E*1AMu4qT`h8@G8rtR_*8NT~(rL{_MsLQ%*B8W#S7O{;klisW8ayzo3Yb#kMBkURtE7%g2$}S)B'
    'LU@Ywnv@KEq0A-<X_d%mH)SGk+!9WB+`|%Fuyy&@9Q$;W7-BOOvX>XhP1U8Elo1n5LE>qlZU3Iuyyr{i'
    'b8@A4?9?f{@|&JEsgf5}ilK{!lOjkvs~cJ8qsf_aQf?DaBdCnIQtaN0OeTUY&5w`gaai#!Vwwk>xc46F'
    'h6pyB9w=U1qXxBzAqMn=;_@nUs$5ik`oiY*If7f%vN%FkO=n4`LK21$2Z&<Vq<I-q#*^t<6m6UHj7*bD'
    'D)PL!%>K`eY3W2?IJC{51IwvBpL(Q8#nw-iXQOwR%6XmDj69mnvXYTcv&O3H%0~8jJ##b~jx<g0nHqI_'
    '<AI^+gWjNLjI^O<*nNv?meCsysYcv^MMopuA;VF>-`9=NP~Y$l)l%h1XQcJ}<FPgD8?No>nn_K~>WvK7'
    '>S<2jvd05!?2cSxI56P<f#nh~(Wzs?jI^QEH#dd5vUp_qRn>QI+skDvP*UB!D(zb&I#}7*>n059_!gB)'
    'K=N>B{MuxGL70vc)#<-f4N2?;>#%}1LSHcaM9D?v2B6`KciCz0Ps!{Ftc#ua#A+Nm<cjr0tOJwRJ;{b`'
    '^KqqbdH$8ObjjMV)PZE0Yub%fqHMRjG!4Og{?N!q@uB}*_bNeLGmEP)K8y3kc()(owe3`Vx?vcD|A9S>'
    'K(=4Z!$shn#aBLUg9QwxwnOGu4XmyKYQP0Q^{DUUWi0q-b4HN+U8UA>3<LXf6xmPk{$w`r8e++&A*%PY'
    'hngUkGGF5r<`i5_rp6@LY|u6zmGg7=w!>DJlxfC-*sTE}*M8WU`OvzJmZ-1G8&c)1U1)|KEAd<Hj1>Ld'
    'ocg|p`y)ef@6_~ez(}|^HbS+DAYvW&6KT9h@V&&F^bs4ktnPzhwPU+#omq8#Tf3?pnqdV5N<wI&wA*L#'
    'oZa$CezJ1h4}PU!E<}y1bSe5+RfP2yXQcuWrd-YP2!)Xu+5lG-W%UK3>ce3d|2XAV)bH;WP*?|61^T;{'
    'sOw7dNLYPXPF%{NvJa90YoMKmJ}tc+h4c8;RgETg3@(r_jHk<*{p~rX*6c-Ak07|OX#|c4VrUKNNsASp'
    'vm!u%yfZw%Y$HK>#Qy;gvnS&IL#Mufw|g<P3n|o?5Lz1e89y><Xk@8VX1S7&b4YKuWp8P-l6i-Mc}H?N'
    '6Ks|Al+-KeRuV;><)s6!CklSbC~1j1)jU!ZPc6N3SZDUTRy()VI<?JT25U+_deg;p1++R!RQMbMz{|O3'
    'Q}|;B?f~Dd_Rlr2<CRB`fZ#f^^mXDNHL#xa#2eiae(KFYrIJu=jij|KC(&hp927pyS`gQPTO2I8cg$`}'
    '9db6Pzb*;K8CY(_3LW6dD4bH|2akS`W$isD@4X9_#RjBfzhlEn2;DcvV!Pw8T`<^g`0I|?t6}b{TvcMn'
    'WJ^olIj9-^E`ngFDZX)#)K4fFHuW%A8mu<D>c{`2i=wrXNQ%18zeGf>;^c3?D|+a#3)A&Zf?2RK8Mt2F'
    'Uqg}V<r7fi`}-XgY~?oClaJIO3}{1{3s1xOF|jY(ne4%EDVq=YJr<C_wB`nADz^LPtKo(-@j)-BV6HZj'
    'Y|_Axb;i3za6F~{P9uqCUy}Y-4!7H+zdK98lbi<9y!@6fzE{e@rX}!Q3E(E>@5(hje5m}I(iyh?p&w_y'
    'XL~UQepoSnQa|wlZ~08U2yc}t?mV2bn?86eN5ZWuc<rxQ)(dPifZ!Gp@I|ETOIXW8#;6Z@T@b7&h;8*Q'
    '@aC)+iAv21XM;vI3p9hc6U6$%uzSE|uItv>w68MKX5}M@7ewt3mvj!^+9!okB5U7~P2jpIF2`4UmFfc7'
    '`^(z-1{u%pD?j`3$9A@=&VHxU*rM=N<nSEeX24#51_=>0hTFN_c9YqbIMeqo&*tSkyZ{jvq5GM~j<`s)'
    'zfpcjvdZkKrt*|3EaCf^xwNry-I!Eqn0?Yccg4Dz)NkcbP;&|<G4Hd5GT8gP%5F`AxU`JUa$=@wHmhcK'
    'MHC!qpN;NX5-uV#S)=D%7PUpwDecvI-=!6+i}2?sq{OoBxz+RKHp8u>BDp)o*q{A759>!<p*0h&yHBi-'
    'je$KfE#1^~V`y6=*R%(HLg+}R!=Bc6Tnm0!x@+iTvp=S$rS&yUxA1zeIqYw8pLppmu|Z5{FtjX7(|V4p'
    '4a`A*JhsQW4p41_*aK>4)_6<};tp{l?r3b$-pC~GKpW{pV-uK__lRrshRb?Pi3U6+Bv0y|TjX+^vWoc#'
    '<oM%^g6IrvD$3^9tU||*8w+hG=F|@74yLZ<7In(re9MZSONU6Ye9A;&Ra72HAKgz*(<F3Ak$X6mN{lmm'
    '9{Rql(eU+*{Ql|(cFff#zIPE!StV1|Pg*TRGh(xBEPc?q{gHeYLfv+@&9hMR9F$Uo@4cr_XcT*asD><3'
    '&5i=Lk|f)#7Mxu&YNLGGESs(z9k%E=z;a}Vc|v=ZyuE!jGWl{rs#vHe6>fDre$&x-ty;7}{5l}-!KcQ0'
    'sXQt(hkaCO%FXH}-&5vM?AIv4cNN8SdNL&!bfWC@s?6#K;=hA29U9qlZ&u6W6~4u~*?;E+ah=HO>MM^0'
    '=iu0<NC9p8((|1;t+Ave2HwDwx1Q2UKWGK!Ydb@&75?)lxkzCL8;j|bl!e(Df3q$0g5<p@s?Nt)BdUho'
    'AaAF4D;}Db4$TXP9m|ILqCv7`*u7v_bqJE$B-jb-#f%1}t~OiK=p~5?=4i=26*s~=l8lP7Y+CBQv?YuT'
    'J;f2FPdbUwl(!!z(1f690`Uy_DZ*GEn|!~$oe-3)PBW!OGx7z;wS3uWF&Yy0>n%{fbWWX@^Kj|~b=qp&'
    'z3juSR`I&HWcep=59(T3cVlGT#>SH7g-I$?d#%oh!zz$UuraUIAkE8u<;B21t7uV{X|7_K(YEJI(q8wB'
    '58^8f$YU6yEv;7kt@&;L9`&&hsQ4tKoGxP)(K3^Tk&=?HGNZHj!eaJ0co^{!yDTt_{YF!utf>BVjSj%9'
    '!Zp8_kt~b<yxWqpO`K~yp<u@QrO>P-_fL*CkRX?KDwbAArBZydvf<_SXNRr260SJwFgTjcD8cp{Is22n'
    'B@@UKFCxouoa9}ZpdPbK)pqDMz7ywN<-A4{l-6nofVVe4aoLRdf}9<DmvT6|flXcM4J%*vV@LauiPqdi'
    '+aCDK6XoX_)?zZhpm7Zb;{(Xt(n8o~it3+6Z4RcZ>~=$W+l%stlHH)<=xurK&h>qw$K6@!t@^W;YNPMY'
    'L@)FRivlu>E<?QUp0N|_n}=ueWffZ+WStII1xmS<V<81%KB$K+Xc&G(+T<jePm)KueXvsO$0XgEvNV%m'
    'Q7cWjOEnp4`zN=45c?*-!fQ|=-n-&ie7vy}@e$YX-eNZMJ)k4pd?m8ylm@DDlJr#G5-tpbX^skW?#MjG'
    '?p`S0U<x4n!eHy0SgmDWF}0Q_%JJ_OB*s&@uJRp;F7Y>MNj(^2eqsF<5SR(=+CxWnIHSL&S4r)rN3}<!'
    'v(UbrD6da~cwp8a&Wj$W-J<JNQRCS%nbXfoklmOsB}3h?b%?MVYur=_#7WR*oIGIYGJUjV$unSMq;+zE'
    '#KMn0=I=#|Hu{kOL%e?V^ub8Mo2r;tL${XBQ!;;t_N7B-et3n)vamT0w#W__@Vj*dY^~N_PeS*Avt%D0'
    'sq9TPTW4)3j28+Z*gLhy%`-)gpmOitp~;5nVP15^J2d`2EpzuN!?`HZ{fl1|7jhShZEX-RO_-}G1H{O$'
    'nCCQ+r5Q5GQoHYOVZ4y5vML344;%rct~E1!Bn?Q`3zS)#s1Brf1$h|nJ@CVPDs$X+gh2!xd?__S0*&Cf'
    'u^?kk&X0C)Q{q3<1uhKB2c%8N3(nLUeZF-^`BoLdNnm0xcu#x}ujNSM;GDy`Nl>>oOvaDcW>CPDV9~Ii'
    'i&DnBmPlt+UMZ^{t7JZ<MB3^qJ26kIC0%k`5wx_}-)w`ozZ2QYXmba|DRu9YvzJdfv5k?B18GTMTtG{m'
    'b^g%klMFB5<s!Po(b4eFdF;w1*tij|c=Fz(9}bX*!L(95aJ{#L$`ZRMCYq)JU+@6Ha140c?{A3xuD&Nw'
    '(!mFf=*@at%677xHn~zHNDIZIWMk@*+wama4Z=g5RUD>{KoNEw`BEXw5)t-D&HE(?U0UQaFC{-Ou~yEW'
    '+znkVr%%>w>0IjQ%zKBIIQg&ybn6wZN?|UqwD`9;#M%-jCof4&sdK%=IU@>dzAaoU_T$b)UUKAkUh+AL'
    'c2Nz3tAfUx7J`g0Gw~;WlPLlDkSg24g20m{=<)z=ly_T#yl-N1ZBE0ks8E8d=?XRV)n;l+`NJQ!UD;P9'
    'g8o$SbMNd7EFXd?ZgF9HpX5nacC4JZ$n1|bp``;k*9h*~YHcVWTbY$vD`C9i_B42>AI>hxoXW}5ZMaB7'
    'vlS*jn-UNkUGz4zj?DY1McMs4j6EBZ?p)sswr^w5N)K~h@R5!`lIhH+5-+%ldTKlu;ZtcDCsDMZZ9zip'
    'N4LgO;yI8GlDo7^2JBc(6zbw<<Cqj8``Yn}yD5@ydv8{qVAR=q0~(k!zMc__`pfxZ5qVD?UXnvrMS^Vy'
    '*|);*or+yzE2=Fv(j#^)!UV1UJ`5;3u0<57Q%VBZVXy-J5x&3m9+yi^Ba~#xF(&gH9n}hbi5Gn;`SFwF'
    '5)s%{>^JNN=}y-owhGO_Y^(SW>Kw&&mx<#7b0gUSx8q-ptpsJ*X}E~#**gk;G^-Q97m}pXbs7XLFoxDi'
    ')I3<pD7>zB*{4aP@@^^$?VuQv$e=@K=-2d0&N+VKLGUr9XI?awDUpm1;v5`kF#jeB%ci?0=@;_^odT~Q'
    '6IGT>C-9*bGVAIEfVz1kq`!6~uEt)>=U{uC3K6wbUF?y#Co3p)+w~kCCU{dGB}VInoqkAP%5k1qOS3Ob'
    'V@t5yacF4rh1RGm=e~V(RLIHepF#z+=AGi5_{7p(;`JW!VS$gfzmIjZUoFQ!-o!mVEQ&eF7pG);%Xj50'
    'x0)$a)1a#?!&Bb9qg>lh{#2{jShH?&b6)bUo#Z?5ksEN4Z*)}87$>5ed`f3Nxe{)&1lzT%NOF7c#@XIc'
    'L8)umg;xs&&LVWVIa6RqJ1L>X=ywYolmw1SK#zY=7c*AfKJVi5QY)WLeNc|3dWEm#mcd<H8S*8%4ffR?'
    '1$MJWA;OpVbU#qGX=zX{7ry81_oS5${@nu4`ojRPZ^1tJAOM>!AzWBSV>N_#SCCiqLu{fXuTpIA#b%Ip'
    '>H1vjq=}2XJE@bl6usTL{dr4r$+hT`(zxwKFM0Y0Moxa7&K9R$IwswE-b?+&3v~h!TGasqkl^+1%gae3'
    'jr&|)E=eWYRe8A;MIcnyn@2Hk0vbmcq1zT_8rxN_mrK^&+tPCq3xYRmx9-Ah-EsX^8Ahwj((L!fWL;yi'
    '7J}@OgLDm7w3lPH?#gQ2fzf*R<&tZgth=^Y@3MeqZKGt3x%z9m%1o7A|1wuvFb7!F5?r2uEWo!kbGN>M'
    'Svn<AZfW&y9WRt%EZ>!_e9w!#ZD1%L6i=DA-Nm|1&+vsbjHW@Zu#1d3G}21K;r!kce?c4e2lDQKl!^0O'
    'ff;JER07#I>I$UCa8>eWB#~RP7I~%WK0`z=JA`HI%0tr~UZp8DxXqolhtpYzO*hsyy6rpKkh+dF?2T+g'
    ')7^nPwg!F8uyjM$dp*su20dpm8uqATTD0%<dQ_*D);D#%Z<+nxE!^CthPRrbk483e4cm6ikwa+DbO*y>'
    'e`JgtgANVDrlvbGdSiDyHu}UJIpd+>jCFHFheN})ZUeir@olYs%ED*JE+Ul@YHPQ?Ef7g&!Bpg-$pInv'
    'LQkdsiWqi8?U@|D+VLDrsEJY+mN;)_qji;;Pr%Yi0*>k|^dfaiX6+w;#NUIs(~-Bje<X~++XjA?13<Nj'
    'atAcoJV~Y$DJnyp(F@G%iCDU8%|5ctQ~j-ozDTq+0XI+cRV07C4b87Qt*_lJa%BkNF$vz22n-Eu#YaEJ'
    'T_y5<PivG#UmtK`mDWg%TmKS%v^&j!0URoAFL3Bb5P58m(ciAE*cgp+s#IyPn9@1;Vf79wZVXScws~RX'
    'v0LGX%HwZe;(FR2>uUyv81<v_7i`Pb51tcWb`{`y{=rr9!6o%BF5^yfOY~fY?G>888jvCqh&m15({>!n'
    'SSCkaCkvM`0K{>gc>#x!`%W{<ysobVn~(>)69>DI2CMtEab5YC6~#SNrsQK=tF2fH@_^UdeW2*gErRi7'
    'vV@WmfEumtdOj&rFKFjc)lD$<bFI@+eyQj{d5<2+$6F&PYeESW=RTWL*ZbJc_N60PEo`9`5~*Gj@Q#$i'
    'o#=#Js{}cjoa=1FYjI8*Ev!pQ9K7|>0c-^!D=zLl@h-ermaQd0LrT<!yIHxMg-h^bYY%`OCV1+$XflD7'
    'DbY!#j_}G<-hl$kQet5xB?#-Xn;+WjP^hZ}H2x6I-(jDL4|6Z37;hx})J3hmwCY+oRT=9I`206i1N=;)'
    '3tt}x@4b1*ZVaJ+9N9FWFM$eZr+7a*eZLW~h2ywW>MU&feaMAzGK-o}`NiC9U^&ZJzN|fGG?x!_a4KZq'
    'lq8obz)Gr=e)H;BMhISQX1_d=0%++vIvZPZ1WH01fXZ=&-!!S*aP=|&R5HW`3j)453F5c+MA7B9vDAWK'
    '2`8d1d|i$%UZY=er%2M$nh%hQ%nG2<uugr1btK9T%yAo3@kZOl%eDftJg(U6CaNLZTLL@h$p3(5P7uzg'
    '0R8ur**bQJm!W|!IY}JUrMo$OPhs@nLLmzG2SqEcIgM=M(@61RRqD!au2fSyvaxi+kkSk<LH&sRJE@O5'
    'Mt>z}a-B+%>Xa-%zDo`O#5!hZ5Fv_G{1Zu{nE*gO_c<p{)##l!+pizhDx`dZO!z?Nj!FY(zsZ0`bQRc_'
    'U;+Z0wwsG8@N^5YUA#R-)J{X4HGvArnUsT;mBDf2qUPD|x4mGJg>KUc)dbAfbC8&O5>FbJf+DIrCsW#<'
    'dck)rz*KwgrrBAa-M7R*@~N+}Xgzzg-jG6;JOdXURiwlF8vdGIwU>liqB$L<b_93{^W*}2_kGYP%X@<T'
    'DEB*(#TpL%MV{SHc_uV=?Ah;V&Prv3zyw^~buGz9vB2i2fs5%xdJ2!Wo%)J3p>j-hQ%^AAT%QE|cqM9%'
    '0<Zrp^#GSS@)d#f5epYTSo&<X{o<qAav%<4;!m17*sSaJ7dDmG56UhR<u^6K$A0HCSjZ2!m3$#f+v%b|'
    'Tc0D;8J*j}19*yQdw8p%ja+AAIP@6}F5=6!*6Dl>$XdtB*{(}p2iu(u45!-rB%H}d%f^xT2n{FcVDskQ'
    '65#a1{rXXWrNLRJ^ZoludOIkhQZ;>fx<lSbY8V``c6k+D{t5=LT$oRiE`0^C;&M`haC5i$5{ogr%eND-'
    '`SZ9{u<!hgx_avK!ZBVp`Pyz>LwL{K80BYMs^`dd5xD!dbc>Dq2~E0N`P3-pA;?ILO4cBJj;2$g(hQ+r'
    'VS-R2s)AMYz>9n21M%Xz_<02srA9ubvvxp&kn4%4w)!j`s=Y+7&jZJD4(`D73{F#dOi8hk#=-*E%|z@o'
    'X@pn7^HSs>S<AhVq(yo06(b}sdQ1YF`aX5Ki59FMBun)Ri}>-DvfYM)2j#F;CO$sT_*JqV=RIx=OCq#+'
    '60MA&)e?3}%e$w>CcYj%RGx=Q=sOQksVcTlNwAn<i(dBoTp@}NYGPjhIFV^i^*&n41&8(6r!3XUzVv(t'
    'HgTe`Z6#hHZyR^!VYA}Q`<;83dBO@L6b(dqc7ovc#f-H;%r}DV@-D%2l5gSMh+r<Lv66``ZK25l`jUlO'
    'TR?wxqXt-t&`S~#{0LJLxyi{37MIo^hjUuGwf;S(rmwlLuIsMT>)Soeq*`w{u(jcEY?yR3)J%P34Tp|3'
    'c89i2diJn48jf^V8`GX+5>t20@yIkcOT}Kgsy^tued_8|b2WXS+x^k7?+)mAU<}6^H3smHJ9em{YYrLO'
    '*0664$<VNSwnKW>hzvHos$P9dJ^7Tk2gbV?u%k!wIk{@5**;EkJtKF|q|>RB@6+OKve|XgDtOL3oIS;g'
    '9z~FK$fG`iZIx`loM*pNOz$4iweeib+OLz=&ocUt6bmDeAe}MS-d7wiVtL1reF-|jrw0nSuSr@OaUzhc'
    'EHV?-*dt7{2h|^e^)^RyppMzqnk_8fvz78S{miAED968Bkhoqus?<P8pph7Uuyo*Mhk2sBW^JUD8lm)-'
    'ZfNJ4#{QQ-=_&c>O&8OrcvOmfVwjR($V@BFkIPbY^Y;r`>4HxE4aFDB8Nj2;?0#n+R7VC3?tpVB7<Lja'
    'CC3%Oee?D}hJRUDlbdWWUe08oyUH2L$HMk^WPyufI>R77TjRq7`Y#m@TKSLC`QW|0NAUlo4tq$MHouAx'
    'E&N!JE87VX*@WLU89+XOuSUg?e<{!-g>G38P0W-J`yc^x$amwBcwfX5U^8lHRv1v$tU1nAJc|jOwk?gz'
    'q_9rPlYEvxUE6@A5<Fmc{lsk~vWPFkIo`QbUU^eGj}#xgNjw3-1o<=cG+v+7pfQK_oyTl=tUk%E{;BmX'
    'oFs$WqJ9`$M8FdY2^9Jfd|`3j<6&fnGuq8k{I>@wO49M-eI#&FSKjwriq-a-vv&A3D|t2!gCW|5O0=O$'
    '<^tb=lP449h4ou%$63TkGN7c<z@*%XUA+HDGCaIuNiHbs;K_45WJ3VLcD)M>eDFSw(sxGwjnNcN?#^xA'
    '#>?M_-5yBgP1^421$E>p<b<3-f0XH2EDrqJgcNIe2&MiRvKEk$EzB+%{E^Beq?&yw&wxp2Skz%<4JaR{'
    '?;h{~Ld}B1nPk2fX2!K#8T~j(2bL_QT`*jeka(^S^NX4n3s;VRK?6MYXCZ04VS8WDjQI!(i=h`#tk@V;'
    'XE|rAKH?P<GTTGU^5$esTp$-bXYiF-%_P1EaUP)Xgt?}GG2bJ(n<vAYLURtI@7Sp_VkYMz;Nd7oaTmUy'
    'ggAIP3Oqfv{RN8t8k-V?!2@Ca+Qj$4=2e@*S7mj^+Q61CQ#1aRIxs&~l2A0Dq6c~|-J*f<Gm#_XR{v7S'
    '3JeQbyv*2F<Rnj&C*eYxn9s$gQf|$~s6<#wljB{B(fIt^C6dPyVTE~gl!rBVR{$xFcwdwX+fNpst_WHK'
    '+SQ7f=k|b0Se3Pi=>jD#2v~MvUOdu%Q9RN{2c=ufe9NC$<7kqscF*M|CY!eMl_;E`{NWG$Z6Vv>ees(#'
    'SD`}o94NDbYOZq>R_3j`mv5IE6tKc>Q3D02`MqJax&XDLQ7el1a!4{U1bc~P;Q&Ry_h!7>U!7Z3yzpw2'
    'JH>=ai~OI6m7??J7>vW8s)i)Xe$(YhZhVzZx@3Wml7ka5!>p!djnz)%#NVYXJ|`iBfH)|KheSHmKD#a%'
    'Jd#RH<%L}V!Y_WIR1}{`1EKBC{c(1gipf=+$#Q&N@Eo59ze+seM=}kgBxOqM{$T>QyUJwR9&l=G)y**~'
    'n_B`eiE2()koUN^2bPV}xmU!Jq=%hn#kC$UC5UCjvprz6M&ytjlL3`wl^EsKt^y_p$zMBOWCL$t9ORUp'
    'l2sdo$<2GE{)P3{x}9r=?Mp=wQn<;EbcN{rs!mig6}m-lOPT;^z`?E3BcC$EH4S4Olp`87&?Fj)$;M7P'
    'X|W5-Q<jtjASS+=z3+?QEHZF*C4nD{vzQbH)*9vLJK^HP2Dn&SDo>K6m&@fzC^W6KE-9BW!(9UOSBFYf'
    'phhcSjJcyUhvb)K&J_!gB=6EaI4l`{_tRW1X<}aEYn>sqJ=8C3Td|OgChndhM8La95;>y%)R3idP-zw1'
    'vyfKp1TAp^0}SDCF}G>-P?YvS>sbA0M=bXvs=k6Ta{GP5>64z@Gs$RR>toUzYPPBCL>mnTW5=~j)6|IG'
    'cY9V(>kVyZ(Chcdeam#+@wmTfg8tGajIpL$q)&zhv5cWPvh|^Ej(U#k4u@vX9`s00gP9R)3?k3aEyM2h'
    'hGRlaU2_dG8jm&xy!IMK?K?0nx#P$frT!S#-P%L!zo&E7Z+N2Y>#DZDRo{fF7DDw_*OEGngh6VenvJod'
    '3fQFPok6k4eb9fRxDre7!yTQHU_t!-u9We8A*~QXBx}|<??B#QFdP@7uLCcZIV>AkU=`3DM0lUrk%L(='
    'K1&6~@i}#{yDtvE`LZtyj4ZB{wC?@iUq1Mb$fTw}3j+A#zx?n2^k4q_KmPUq{{Q~%fA`0K^DqAHumA0T'
    '_?y4IcQo+lESY(=*e{a#3u9JEW=<VnWb#jG>;L{g`Op9KU;jHUnZJnQT^h+)GX0Ar{=$w0c09WbKjb>C'
    'd@+)Lauo1)fBk>_@t^*?KmKq3>`(vI|M|s2-nm##%N~Cb&0iR^D4MglMRFfFC6+HD`X?2~C`K^2@%(px'
    '`!E0aH~;e&S-neHEsD5*5!GK9v?88?C%rLtWd0Iy{;3kepZ?AN_{V?szi<Klr+@XY|Mai_hcD6RyOY;h'
    '?~5-I`wOEMC3fDdPUz%|u>OffJ~C?>;~)R@zxX1ZcPO2C^Pn%1`3qMTxbkrljLuonsv=GdKU~s4xe6C`'
    's!O-*%P@?n`bFCR)Pg8~`WOHHKm1RB!$aM9qx}E-zyH}E|M|cD`~UWz|LMQ^zyAK8{HK5V&;D1g6#k!o'
    '@*jWE2rD!~-685zdqv9S_1o*~y_ZL)$IoA#pS^f}`uO<#^u=$^ltblH>u5H6_^lsWc#(k2?MrOLxvp5d'
    'J=9!Edqb)jWMG-ppmfkTHC;2uJ;Tz6efU&&G?!3E(|fw9yVSNuwq?_SJ+!I4LH_4blCVaI>-5du*fgCU'
    'amM=CA!g4erb%^eNNn2ySY${{!!`z^zF`o@vF*NVIK*;BWRvXV)%n3+^LmE)YAvqk$Lt1n9&vxQp!2I5'
    'S@x@d+3?FnIQOvVz?&ytWQVZ9SC9F-SG-hgQ$Vkt63=J%ed<-bSp_C3dYi{1zsMOqk`By^BJ3_(w+7;>'
    ';r)=6_iGGS{QftivdJ>x$zM-IeQJZ+`L!1~MS%ED1Mn`x57AS`Sy5w1yyWE;fs;5HG{imv406w6P8(az'
    '1^#lV@Ll<y%ortnOKM&Axk(~?yF-|>Ih~O?b<VKpBd^6*lkW0m{=_Do!9Rr+v1>D;E@z!Z)tf1<-wGWd'
    ')hL`&1=Vs512Z+0&g^;U`?5yE*AK97_PaKCffvD)-HlWIq|#|LBR2dpQS?zq7Cd};ZkfflZmiSd&9<Xt'
    '_f;|Q>wvt6vGMZMe&-fFbGM$ywN&(^B}`wquI~l(_#;98Q6io~KJaIUobMRD%A`hoA$Fd6)OYeIVzr_!'
    'LmzfxzpK=`r{4NGH#*gK^y&ka3RZErlVG-pj}|dVteF?5fta?+TBUU4E)id9w6LaL%-htfe5D;V49?iw'
    'Kwa3{u?CUxKBatIyv3|s%U{E`<E`!}m+iRNoqfru|7H=#yw7LRNWxClfFvKcV^Ra{d_QyR;KUXI)karQ'
    'Os6MPazVEz-hGr5YEQ+g{lCXTVZQ268)Q@j@<X|GgQwz!z#Tbgcj2Gy#ywl@onb{c>Ijc)>#EnSqI*{u'
    'RQ`T=(GSIz>hb}|@FN>`BX{i8?ZT<sjZe25m+lU{tec!H(P0C-6x6HCykkeJC1svTE0bjPQi|9YYUjvr'
    'Fj8!LmHEh0#={;vI6<VynteSA<H~9lQZL+IQQ(^_ae#!4S99G&s<uAq#nDanZ%cT>-Q)d(YR{U#N)(WK'
    'lt=mZyM+y{H~W0Qjn2KH3p7*G&KApoYVpzMN-IifKUeOvB%;di@uaHJN>}+E4{>uF{x0c2Y6wnh1a8Lx'
    'xCY~I_ayw*x|WF>*}=EFjJ-+3Ox?)aT?F1*-+)^L9Mry`F-BO5Q8?uqd$evpI6V7n5zlKhpm#^{Jc;2v'
    '$<e&s1oQ47me+77Z-YqQ^=(3V)y3HOD~AiQs41OepQTuJM3_yDy%-e4*1Zf`1(fWg=ArH!mbKrJ9eGw+'
    '+u`=q3%;Y?#bu3?0MqQOrru=~!DsU;nE`1~a9>pzZm><MXMchrvi3V{Ik|PnIHTYoj59EDcZL<*gasv0'
    'x9vmdFU1{HH0<*1Cq_n9%?W^f{Eg?tm)m0o`~(+Wg{#gcLM(;f2->ipDem=(&1au=>Kr<9^|P!;npzF_'
    '_gD>99-rnv<zo-z|Kj3;Ml5k!*67#jj5y3(k-+Z~=7g=apOg3A1+!vap|H-=CYRowddEMzRT+(Fj7Am4'
    'j`hWzsEbCl#R|Tay2%n$&(1W@?iJ5Ulr^h%n$SAymJ$VI2F^gd{Q+y~q*hHvY<t0^7{csGCSZIesxpD9'
    'iZ{CH2{N87M%#PI*|@pk<a%Y-sTJ^5!jQlCg&?v+R^NMja+0Fxmvx<#ktA3QEqOEA*j|w4WCB3{iaX)$'
    '0Qp0bA$C8^uNVYb+sgv&Eau-yMVmPKZA-Ck)i8L>njp7BcT$RzA;|Ntl0?nC02yuT9I-4B{!to;`|2<q'
    '{S%D;p7<VX0xBto3>Npqi-1^w76AYzUaNU1TXz#^<xl)eLzYrO>aL^a<6onF@y)`+plUJ4BNK0ula)~#'
    'i}L`m9gnB8_=*iH$y<=d`z^V0S%MrbFn-b(MIP7Z`Qj*HihSY~4`#|3KF@Ybsa*%M3?>`fOZhJ;kM#rZ'
    'tzpY8K}zFh2`8I7<K-J!S(+l>VT?61NNgW|6&XzX_s4X=*VAx*Ou%muNbf2r4SxJl#nx{q3o>0SFR+y!'
    'ZIn*QQr&!@6kMyVqxN~1tQ7GPkV>Z=`?eq2?{*Q@2g<ouCZr@?xx0vzZ0?e*oOi=pt63{MGEPXnBZaH('
    'gsGb6sRm3lDJtvk9mFQw0oKqh2?w1ktjNUnO1R=yIBT;j-N#__RMDy9p{0U_B0-cdoymj!9ec1e?;<z}'
    '<Xy61+$d6l+%SxTFs2d@ew(~Fb+G`m6OC<I$3b`PhBaWI%jB*q=30u^zA4`id7JUymSE+%6S*+0VBmT9'
    'K?3Wx>XW?4*SjcQdqT1g0~OB;X>=)0W{SMJE`Lv&j+LG<b@Mv!K}dujL*~d^GNo*kg=@+@epyFkQA|Xn'
    'Tn?<n;w@ls+3tmRF}PbRbqxpMk$$jqD=kiy%z@Qa+na-jFeCA$G!t~&6xk&{z9p~7+AcY4BHtX^xiuu)'
    '7;0XKt}=z>cpDAHDI|C?cmV!Bjq2tUxwymqsc>aAIg9<nAGR-~psDY~NQIHFrT7wJDJjcj)(P=_ab0`+'
    'bU1d1AH=!K5#^*0icqC_6!3W9xmdyd!Y2{t5IZ!o=N`Ll@c*;-u3c{1$fD@?`4x;$?zD7wx6JpWy)z!i'
    'b`qaF>}flhb<QM93k1M!ZL38^lx+8S{NGO%08%7HNqj)<%wD_KOx!Jz1)!=>FBGaSjrz3&G5B{gOoq}D'
    'Y0I^aLMo~lU=3{{%k4??53>cvPZ);27c%1>HB9Mm42$#~vk0aXxhhY|is1;CxSn%EUFYaes67`>w1zu-'
    'dw;PAT}gZPZz$V<qYwdKmp&i23J6NyXY%W>f;uxc*5)jpCg$`>%Z=H4l#cp^<1yK|>&0#5Bz)F$Pzfm!'
    'V5%kzz}#=%^d0VA#qwv8%BK^`pFt*{TqK`BB5N~2Pc4rJTdWTs8ZU|yci1uudb3Iw=_Z@wQOknPH$r6O'
    'NAwrzVtzO9ERko1IBf!{vrY}NFvO;jSCJ>fb!btK2-8d+8P$A(J=vz8HM(C3IaboC8k3(&DOtUfSdBAK'
    'U61k$7($Uf$`df<ADZ)_Dr?M>Vt^MZmz62<amEHg9@KQ$P^oE&X=~-wJY5G4)j_Ib)Y)%f;@XU7qTbG<'
    'lhh2(f7D4U04*1j5xo*d3$WZU!ZyHuRzQEsApu%;>itv(mZrrY!hyctfb4Frq#&3Xt-&p=3S+15u<G*C'
    'imx}Tg^mn^dzAL46!xD*)@v+wBBWp`xu7^-l0~(21g<5geo;*hnrzldI00V+gXS3)U7C-ig^pj0Wm<mE'
    'fh%k}(0!?paVNh?%=nK&#hSjZ=Q?W1W;~>rAJv>v;gf1y-zjx<ld6`*pp>fCRT-+RrX|c0{JPkv=-QqG'
    '>sQhDr=jm#L2HcQ+^c$S(9VOrF`X86q3yI;(-<84UHKeRBA?WnlJ)^53mG#os<{4)m8}sE>luB^(QOjm'
    'S<J6zi;*f5R=N8#e6*^sCy=6H355p1n*#^Dz~MtNo`}FH2zY@jjB_m4*+^orD6Uq&G1WWxUw2w{*!(Qj'
    '<td5)Ga4@f^>@lL%@;4Xte~-`JTkezS|h%HWtZFxS1fAmN=6N<DcE$7{ntv762>GUCPgyt2^`;ZgKkzU'
    'k-nn7YSOd=N7L*=qxuAK{PBMnbayqm<gDJ3M;03K)hb<$|DDs22L>Os`ptT5n-iEeHOppug-#Q{eJ;!C'
    'OwZveR!$V<NWQApNzekkFv{vKxU|o(I72@E@WbZ138lek(qeDiv$@eA%)h{>8?vOh<T*!<EVjY9QIo^x'
    'x~`PgwMRoKjz7pgsB(|KkU$+HSUe`Xk<q<#wK*=0GJblazKqsWhBHoKh25(Wc6O2|$xsulVbhj&Xq%m-'
    'g>$s)#CzLWK*s}uM$4F(87z%PppBtqsmQ~4E-XoLKVPbxo}=wGQvZ!F^L&!+cfm|OdkQ=5VX?+5c{$)v'
    't6kd+BW^L~C9Xw7%e5>wunA3gNJ(NQR>(cej~vEq3ZFQU$rv{S*EJ&wzgR&V<9MgnuEjXFf+(>((<82%'
    'SWe&(8u}&;c;LA(tjhw|A)aH}3H77E43d~Tv12ojn0DN1(7nxeg*CkmhZYv~`UbP!@bXbZi>3Y@lec5$'
    'b?^%4qcyp{G=8jq{DxfTbLu^4X)!zSuhREg)}w5xX<ki#rxDgJW_u6XaFtBQ66kDw_qw)>r|{WNDdYPW'
    '(tBLMKoz>?r98p7Dg672T=RnqIyaU>vbK%07mM{Sbqm2$o`;ULEdX$QHzHufUm8~_xs@Y5fxk8KSTX&d'
    '#Bf{MbP52}A^`U*Z9a#vIi0Ne9HK_6q^a&s+=E#cIWu4t|JWv-s$qW9w2FHZm-?mU=Mk3oAuI1!RPL9Q'
    'olb%)N5P*4=!u699~v*kHTGoo0YhCX+LIYK<Q+E_sgYM6zB3qElSdeATBK{tfB+Y`zs8VBUD-yYF(;dO'
    'esg{@U@^;0JfBemd@8=k!1FQc=KO$Dh;7fITe8@YIda7n$1HnH>i-!S)px<iGL27q>_g1Z`LP%YHdzx}'
    'J_fh$(|<Sn8n7rHF`m47A$-?r&FKCEe;Qzq3^)h*Ok3;(JM5$z><^{zkMZEZQ?-+dk$aXRe@MIeL^9;;'
    '(;!7%i`T8ww|s$#i;LO(9Lryb>pG1$-{fL?OTGdNn+3Lw#O6SQn0P1LiSbxDe+@8)&THuVO3L*y+chY~'
    'M!S8m;etO~iSt?r1`s)qCm_gSN4!=U!Rqt`rNnrk_x>3eT|1wjfX)9P_2KF~-d^8o5ZO)ob~r-CO_l$W'
    'd<`ZP&x8>r@*y!3ge(l;isf<zN}@=F(3O#@P6XA7&S*T5dkuY5F(R4gN?vV)p%;8kX`S?w6$1xUyQ`XY'
    'fD0`?_|lwgIdxDn05Bs;q)X#VYy1b>ho{#yCsZ{9xJMnr!EV`}!O7b1uWvYCA3BF~9LEjAAT&+OaZR2$'
    'k#C!p@A!@#nt^FkFXm=!J3+urlK3$XLyM6h^gPe9!@z2(<#vwZh{s`&IB|SRT_@spWCj*@6Ek!i0)u#7'
    '7!b=h3AYJ+5HQaT6Q0D5AG#h)vF*5fPvh!8plNG2NP6c*i-GHv3aY?&y4w!1y9}KjRGPuPmV8)V5Z>R('
    '9*l<=SH}L{L85;FZn2k3*<40R{u7LbKe9f+=)o;nK7)0=0y_ov%{pb|?!kB<CrC$f3w9*oYA1R5M_aXc'
    'G1B2KYfUJ-Un<?ESTye>gp#2DyV5F0+-Vj!TzppNi;=#0ihA&Vs*CPl-3hp%vDbIDCM&^^13P`oVZTI?'
    '{cHuQcni2yEfjSnSiE!!W~uLMO!g{<8@Q>{C0}fTjwIA^_sjkJee}~<5cg|9=(Qj2&3riPq9umw@)N1@'
    'v-{8t_pHP_QAUgYKArmh1JXx_;=WhY`vgY9AI3&F)O7O?iZofO`45RV?GR6HS^W_Vt9!Pq4w+S@XcQim'
    'swPKRH8MLCiLxTwr=c5Lu4&l;jl;yHzDEcTEgm?g$C4QSiLJ!8BG-$!8=IbKS~1}XcLT3YBx)xLWm<k@'
    'CQg_HF5{*jg^csir6IFJ5)#|BoH+29Z#u5)QZJ%@k}zu9ETU2D*>Tur%*F^*|0v;Ke<ZWT6ACCbvh`|1'
    '*G3J=ms;A#;AJ)$=D#$^;!X_m{KJy3W_&@pN>~`!W#{!8j~2=;`c@!UR-!vcX;D|=!{0<DHti#dOBk1i'
    'I0$&G9Xj5R(N!)E;l(Mt)7*#jHC?6ixh`n<^8@+kU8{}}mOmcS^0fE8m6LCw)9;{yBj&Sr{Moi_?4>ap'
    'i9R+@7Gfpi#~N<Q-seU=={`N}Hr)#yNc4QM78fo{*!m&=cwl#Ot#U!DSQsW1w02L`-IQPjbe!;FH&4{f'
    ')90!bcJG3{m4-0#M0)a`%-`1QVD}wBTK|V;uZn5wZ6zw4<%&K0Toy$f(VN+vt@wZ?O~4hw8>1(fvi_!U'
    'doZtRsB2upVE3~TDX7!3&Fw9z3$xeq!;#VpnrTs0omkIXXRGx7l)hi_aBAsrdf{--vSGMr&@375Uoh;8'
    '@f9`+R<3yozWgXRRpr0EdGv;46?3#^pQ>1*&Q@_{*|fx97LXi=dhx9PZT&5Jst~nLI*-uQ$&V8_g`hYE'
    ';sx>xgykuN_sdY{HPZJM8C5X)1;;1-va{UtViJS;<txr!t<u}s0#@>GEc=ku6AUzJmVf$aFx1NWJVsU*'
    '8%vuPrYVp7(_~2)dW<6-<^3j$q9xB8?8>>97j>EDlQqfSj<B_8UQABxgY_MT<1q{|($?3k^L`t;Mx6zf'
    '6)HaJNR1YoMfLHJHGWE^-E}tez)EtZ@i5|}sH`xI<<5&iv69_@#(SzN6<$+ICi$}Dzn`~i<tffJo?%U>'
    'c`Y=n$^Fx#4K&E5dlgH2q*5(DDGK)2EV*(2lf$#260SPybn#@l<OB;|m+VjRk<LM$%`&n(4$D8)In>h|'
    'vbg4>G&wmXrsu{~S6{oT1F+)j*^0kN#Ej*F*gbofdUo^)h`QGsHvWem_e77aXe~{2Gy{M6()e<VwKZ8?'
    '^YwrYCIRRqX(eoPi|U_eBRR~ualZsT7fwq3OU-Uj75Ye@yYuOf#E<u9rRy#XKGa6PKNG!DxH?;qWp<Nd'
    '>FVuv5=E==OunvS|2XBPJ2@75s=JngdRUcK;78pyzs%>8UqA03tW@;4EGSc#W@CLte6_ku8p@~kd$ae8'
    'SWV{*@QfiE4a$V+%vj%WgUk`vSn+1LoX>!dkoZPMSDY^<#*4MF;P3dVFO2~Vru!Shxg#qWlNc!9U<w)D'
    '>+au~aMxEXtmR7sJMOKCsI&YX$!_pBZAm>CV}2Rqjrpz69t>La-T0p0<(&y14~EE>DZR;S;|vE^?tLJ;'
    '(+$g(**g8R#cVw~nlClh)PEumyKVc&=AUTLW|BPsbe%s&y5t#bW8`&mjm#pCK34Cz+{yd{ferEVn{O_{'
    'ZT<G%()pIGMB#15m-F-vk7a>4%m9UuZs7O$4z~61zM?tb1I}_fJeEypCfjum9!2bh$`Im{;q4Slo1(-}'
    'rB6Sj$%g4+v+PMx&_(r>{J6!ry58~UKUWv>ITYK$AYhR&H&6yB$Zv$_bg4@-Y$Xe@z|TLwc&5Q&L3pWD'
    'Wlak158wzOcO97FV{L<MEAa_y6V-thub@1}JJmf%BivDjK?DT8lbWD`M-c8>v9V<5$M<hj;(u;8xUj{w'
    'bPRW$sRR1Fcj>{iCWh0|9Jkb+R=301Ca61j%v5#U&BxVX(TM6oTHt-s$Y)JnDJr*fW9w6D<gIh#Ud+>G'
    'NtYLS11+uSyCpDwIMDe<a3^O@t+db2UOtw@wrmcjD+x>rXsxp@9~yns;RU?fWH$&M4gZqIZrp&4i|zop'
    '`tN4^{Ug;?$C$1AmPJ34y>T(ov<Ucu2LOg6{sCWnP3YU<o<L0pKRSut97a;rS)rOXxmP4;3&o>k6Y5gh'
    '@7gd8!b6=^d{sCC)v<@jmj+>$i?GL&vR{IuYl~c#rR2YtSgU7G-Va~xrcdH7(;=f|g+~!}t?%ToYJ>J('
    '(Y_Ss`bw*Rt3#}wV@meY-BT^!h{~EDDc4H;^VvmSe&jf<`5aZdXn?`hz~iSDf`T!(;!pjiQvynm6G6g?'
    'z|$q@$^#sgcfDH){;|a5!JLNs;zA9sW}?*87wy!P@vndNUD+2khW=Rbb3fY|SUCh!C2?hXAN5IAajcxX'
    '$l{L!p`}N9t`U50tMx<y*~YBQTJ?`oN_l#_Oz}p-whG8k@ORNYvikIoWPP*q+!fE#%?gP1@Q0KFcl;CM'
    'wv!Ju6NhD)dh*kso;-W@{Mq#N&#zv+ym~Wz_2kWWuYm-kvp28-vWIwSZv}?d(;H6TW)Ii!;Z)Ycnaav6'
    ')4bH$6wkP^E5c-Xhv}vTfEAa&m3wyOP1LT`JK_nogr;}5b-a(f$Wod;loPy=6THYLcu`F7mNgE7NWDro'
    'YmjBjIoUg>U4-E2Ec^%F1SH_AISRyV@Y@UV?S=ZbHvTTaElvewehoad68i%okN@=Q$<_0p-b~-ToIZW>'
    '=J~fTul~>U+4CRXJi)Axk7r9@2dtrTmT-byV5Tt|BU8l=XXldPp3XP%w}_7gc5p3MocRrtg-f>+sPA}j'
    ';`?zFI)O)B=0{eNBrG&ND~`-Kv0N|V9)(Bz&|)-V9&>%0vM8cFjJQZX7A|qRKzJ*D3*(C05^X12<{g}B'
    'PL^7gn)=MGz-2+`SZ3mL=G&&{uq32BFbUz5T4rnq31hwok8p>CG!E?8On5{+YO`1sY%a|_<7@emXkCq;'
    'c!?iGao|{v9Rrdg!eKxXxsmU35_@56S=0#}$73-Gm`Nz7k!!k^2M8iG2sL3r*3GFeAE;#o+)Errkup)@'
    'TZu=4I1XVRR%BatXv0(z%k(^p*^DQ|qYjVFDD+}4Fn5-}oX@Btr$|kJ4@31=x-9<4ky9z+GXsIPS{tu%'
    '#y`I}AY%^&*BeA^9Vh=;F+T8<zqF`O(pZF~-g4;J`*^}oZ{b}eCmby;Qh<<!+Vf^J@ZPJ+2j8W)yr}-)'
    '241>&J-c4K*p@r_C7rQx%LyS)Sfyl2ft9j*h+s>9AA{OZ_(N9rf=TUkjXb`}25{SEo|jF%JCBuJIRZAX'
    'S$h2NYky6cO5^U@y05C=_QF8XH+{e?MIY~SeogHf$@Zd1+wFZ|cb{r=%f&rkyqm33QAuU=>#viH@&$hd'
    'c0M0hk4}rvj{xj1EQZSp&7xwcq&SJ7&?_g7?dRN_1h{)m%^~n#b#-wLFJCh_(fFdZv^cp)(;(4W3$)sm'
    '-TI~61`ydz`aY8lL$U#)Rc(IIPI5B6RgwaP8VNf-_McJCtKZ@WrF|ea*SE)x`1e5t=YC06oT)5Rl#WNU'
    'T`G|d6fA0uui-zHsR_^ayF9J?h*7y$cWEKCE;{QXvqpMoC&$_GjaUC^tV;{dH03ubc04UA(|$c$h?}J%'
    '=KfI$xXD|7_dZ=Q<I{n26ZGyb4fxOZ^5OA#f*@ZkmYemH%^KFWoUKJ5MO?9&h$Qc$TcYV_l5OJK+4=_('
    '^EuWB#`TORpnb*1FzYuYdkg=_Zd9tR`q=n%FsjwEUQlywU4@?qotGnPvS5Z}b+@Ps+jCqZ(m}3ur<!l}'
    ';2=RNrCH{nJ|@mYoCsj4qWOez%$3jhgK<yHi0P?fATydSUM}W$<87hxzt7nE=F)K8bE8e!^21fhcbDD?'
    '+1oqQmOY-tguazUrc3puCn=T%T;Gk%i5ZU1joG1MP-j>8HtJ)#CW~vp08LjQ2d=<+-DIM&V5j-z#d%6q'
    'qs4EccJd*9J}8#&UkvD$0{1EePAvltivX-Xqa=WsXq(Mn+2VVL?Y;N!Y3pm;`KR9a!}h(tZQnxwx02~t'
    '!{DcS1&Hlz*7!j?Nju5V4I0fd<y~R=|CeR8Ha;Fg%zv6X3yvi9FO@Jluf(Xfzn|BFOowE6^+`ne0%X<U'
    'd(=B56fG>|JV*F?Yq8&oKJAEDsq`c4(Q&~z%3>Y0RPyCY7iEu8S|lwYl*?G`xSfyct}fOEq<sF0OPw=*'
    ')PiK_P)*9`w(?Rc9_gxKj!*XJ1AoQX*w>pGs>a$4f$M9G!la9=Z7JmPLHrka)v=<Ta$BDHPE<8+|9r0W'
    '%X_-G+^u?V+yKv@f*7~4CfX>Ap)y62NU7d0ZmQVW6b<SCkIL8}0IJ8qChDtEf`!EMZ(klst=bttcE{O2'
    'N_jy~2ak9!LboP!&wJP&#ZM0E2f6Vt>mQs~K4>*7`QV^gfp9BMN+g;jWhS>|3E~iYsEIpovqfv>-TR|5'
    '9!opoydfreZtSK*?j5%=LfSg_u-&w$P0TFtHbUDgN6~o5IAA8VQs`%&38&q8tS%AGcX23hsbuAmM&(z='
    'l9GD|?nUAb22fl3XJ75Dfn?kzStDhRi-`i^>H9@Cs!H1do2BtML0&Z3EYZw)+Hf8+Isv{*_FHF^|63wi'
    '8K(Dy<yJ=2V4J>dkeBL$)eu>f13S3*9^;gch)*|2)fmKK^1CLjg+3bO`AZ)Uut#ey8^}d1v9Q-mdvxsB'
    'biaRfrh`1)g-0J3vF7cy9BD_k$OZ3Q=cr#%5oN#St+Y!ypbkoYYI$f>K3-G@PkWEqC+cppF{xBJ$+Nn9'
    '47oQ6=%dj}R6p(@>bFB0Fy?Q)FqFF>s`f;yIUcxku{+5n3N=)0lSJk*^_gYiwA{lq^S#n{p7(@JRaLC*'
    'EJf;mHE7;O;2cZ=d34Y`XgH*6G2j4o&<Pa>Wp^9Qh=N_*Sdwcl3h#*M3;Y)>4RPt0%~l-K%kIuqg)U++'
    'Y(y$bZ3%e<V&?Y^&(@Q6qrHAVTT^kTINPieLSfg-+cp{S*?f+{`s@*mlJWH#_gOIkeE!|+op>HO06?@E'
    'vM~r$A?jme)W86bo0;ZP7F2B!R_GjJ>Z_-g1AWYrSErQSRyV`0-r96x!^&scXhN(f+B;&_+K$)(iW22T'
    '@)PGES7c~G`N8*~yfp@o&+aAa*fB8OF)lqQEZs8OMc;`^eR5m7q;Y<2g8sGK=Z{+x?geJmjoxA@zTF|!'
    '^ScLv`v=XvLqHK`#iE)L$A;~eE}AEPyPB~PP3N0iWYT}&pD)(@b~GW3EOFE0A@A&Vb9-r6wl^OCR&J_j'
    'cR1<$CS5%z^k%e0@VI1UbUcd7kJ7s)v*4~=$UP+m{Uh;bK?0#C@;@ds_Nf1%pA1drNBdnTD%cXXdJF>o'
    'cDuzVSbMKHeJ3B(={tA;2|59Hl|y*f9k)#z(G|<kvzwYWld_^)3!c3Xy;`N$pgS|!Q*S#}Wja4Nke_f}'
    'O4BV^X8U3r9LjK3gOKQYbkkOpbdKtMQH`XQ6;c0C+_7_j_R3l(x1L%6>XLsw#NXNeL!|u#-ha+8qLpKX'
    '{q^h5dY&AeR516F%O@7gEexG%(nBpX?<+&x9vqzcP;o4)*W-6WbJYonD+1+`>ZKsvql4MQSRk6S?`I1p'
    'U+*}}n$;uX6>8kEL9#n|q-}miCCM8LCKMs~_A0vyqXgnnje@0+mn=%(?~+{pqs(Y{t(;~)!Qn@X?NzDz'
    '<tdoRPKx~g0V|+o5KNotEyYnoVcT;<kQNJ5Y;jh2D(%bTRJ^J6jK1Y%XG$a%iK>z#QMI<{o+kckW#=6!'
    '!@rZ}A-1flwJ&XZHRN`gqt*tdL|<h!xwMvRJvW-xRmWe894yJPV)8?nwy2l?$6MicHAkw2wde3|GObAZ'
    '>>$68qkiAW%Xm^dv@!RGX_fB5%6rf$9aYMHjnV@BHR<&Qdg>^=#HkgsP<JD_w;t-FhFU_q2j$XDw{$Y>'
    '?<)}Be%Bt}w6eTS+v*nit>v#b8SJDid(LKn!j_dj{2&fJ+jH#L^*!p_G$Gtid_Uxg$^4ikfoCyl!>@4='
    'n3ivQN#uK8Y+0PzJ~fY5`fvj7Cb1uwp6>w&64;4FEy7H0Q7^U$bxD#?$MgNjvs^C<XlMqJ$y^>LPUNyP'
    'ow#VO_Yv8q$2hfo7E&v+xf9yN^?e>EVPY}H0~$Fn-Nd#7MqHYNF5#i?Q_CidMV8y9-iKeV_YqX<ee@#t'
    '%O#hkZ8{R%vHc(jsly#ViLsIiiJ0jJKJ{4Wu*kRU$a9j|^(b*k;Mi7VS%4NlwjCOUyamCzMJ&f<vEz6i'
    '_Z@2bVM1d!Njw(E9*Jqd0zysG4MXaCZpb2HdamO{JVY#?>BUAf$!Xx3eq>QMB7VYw$*mxvB#MBs!x$JI'
    'CK$&~;@X@6ZhXhLeAlNA0akW>HwfF1+%1#b8$j|`s}y^D{FE{-Zu~r5rOQ1vhb-<;*L4%uH-Vf$<iK_b'
    'a4|PyW}3Ebx{mLefn_Dkb^;g3;sQ4$Nfel&mr$mm=1@~QaZBc;z;s>^xqxS%A{l^J0%9gU3GJ8!ro&xs'
    'Q^sO=hB?4MjJbhBVipE|<gny8b7Ju&56B#NHmue%UGADO?Dr&gOy<Qj^5Y10y&d?l*?m6-ahPz<T+^mz'
    '5PPmhOnkoDLspqFt^Ku!s>!Fb_1(**I=vc=<gM&;BmeisVqGeI(WX4kkt~xAAS#(3ZQc_Lf>rF)!YGz-'
    '42sCH$#dj)z?>gj+<D{F&s%vyYjT}eVgRGz!2^H=q`6Axy!LUHuGVkv&>wmsikw*O;CH9Cw6V`~wEmT6'
    'c-s@^v46A!sBd|QG?gg`Um4=A{s;*&BlBO7kMmm#N6$NSGxu=b?#bFauT`>)I=<IoxScx>l>#^|01VlQ'
    'pJgMS?Z1Umjy#?>=TQ~k?nB((VJkbW&Gb$pChk>A^cE6bWkieM`}CH4z*C=tuqNuES1VAt>e`RQ#pp{D'
    'PvRdx28@r}NjDhe*@4+_t3<(f(!LOn*Dh|gD@GtHR9B*V+dm#vzTHN~svoGQ1Z@vSki`>&gJpO=6sPR2'
    '^Cisf^~7!B%F!6v{Sg0NX@5G>A0cq#z{PR?S9PiSX!p6w6yyhoV}Z$}CT&GHtn$ggC{RasJjjh53;evo'
    '$oHxt$>I)0y9k7evT|PvQCK=a9e2+{X-erJ^ZA4E1eDDPr2XT`B5j!%RsU%|53e1terc+sRUA($9x{jR'
    'H35atqn1tQ7uwgV*ixZ0Hkwk#_9W62i5)7L1}{*GYJr_r*6HEblA+3zL2;Em=)q5U5sX_Y$wXjwJz1xW'
    '+=;X|$-djKM)JFH_xd-d*(E31B%f)I>>c*uL*skSmj+oF`~!v)W^1%A@l;miXe;a)w=>upSXzIT-io~O'
    '1&G1DqZK*b2NJj+9GDUoo)M#LGN605oySALD-WLteRNCi3@WaT$wpPTWU(Q0nZ6DKKj?}JmCu}?Fo`^r'
    'I?tRNUzE<NF;#}l7TM_i4PWugL&-9NNTTW57W}7i@7v;|eNqE9*MHR6=7I6Qe*JZ{9eDg;Jmea7mHSFy'
    '`vC3Av|XRqEY^=n^{%;#r_N*CWspuujMYr4feDR=r05Z)*OOa2;U!T+_ZUk_j=Cw@cXRI+kP?s|$lHpj'
    '%W5N)igdLp%Qa;0cfqKf^}R@i9o|&l#Gn7%lvkvKV>v?lER3o~KB3_3@@zk&QNPXD{$O2ni@{bOPdC{b'
    'e7cn?&-x}^&Zua1vgZJf_&f+4&S*rq7uhCpxs}AWO+5INgf>g4otRN%vBV90i~2qfBNBLKXa%9o>A(ZH'
    'V&2;pC3&NieQiqcc+;kqW19)3K8OFsz8Bkm6tKjJ6W6sollq=*M%1>P*o=Z8v0)X=N<7zMj*c0F_5uaV'
    '@$B|#nywg@Id6TW4U>rj!UHdgT!$xd5`~^alPIycPXpUzwnyE_BDQI{JPQ3FVu9@fNn%)87}DdXhVW>@'
    'ZHLn!Faf3+`$1??*Nz?H#hz&sH}pIbI*}U_*C#HEz0eCdXP)oGaS-c8M)ScT54r6IZeoUk=_ax1`-#IG'
    'FHE=>IxG%}X~LXh8WNx?No?*C-(yi|vMBKbLfaf1dgX(|sOO2cSYy5He@jxw%#Q<360s!Hw-Y<^7$E`X'
    'FE}ALx#?Po13L;>Hp1)@Y*phru-%AnF{@4Xf=m4X$QL=W$K#mToYOFYUF-TGiDJu#LESiVlhBVGpZN|8'
    'JkJTe$a7gl2s_h+hR=68?39V@96lYEjTFkAvPJ7gk&St2ys2ho%66YcUq$1ZFI3XTp(0AgnFKc}J&qj-'
    '<%a^aaGAs}@WpNl-tpAS(kg2CiRD56<152D4D4uJ;vVpIN_6SO)}e-Rhq|4pjwvr=aQojKYld;)tA`IC'
    'iYo3GDFzaXi#OY=<`~{c7rdw|qdI7mZ(2{pz4_vmBcsW?^H?{*ATsIip$HwwBQbOalKd7941K*Ki*+V?'
    'q{wt;ERRN{@ptIX`(G7iaLT35FgevgnamA3Ct0??l*mz|OabGI&8;DBg<l%af8UTbk)?Df-V>iOES5IU'
    'EAq)259dbP${BJ5)z3!NKKYJ-S`b6DFd7wvZNC}3CjT<VM5?Xr+zn1?Uv_(u7Izt1ovhd1CY$vQP8fN#'
    '7XTUbdID&;;>gYD9sc}cvG&~-aCUj9QeUR2hfjN}KBtWF)edRY2;)aeR((~;>Tg>Zpg{cg{qoh4M^)sO'
    'A9_;$qUCVAh~7fn{q8;r301a{Dh62DtnCV?@Nydq)i7FY${w#bbph`IW~*yjfoO>-HNprC!?A{jXa_+r'
    'rQ}p)HH-;L%npTmRB@D7!=RLj`MAS-O;qgizAPcqvWi#v#j+LDu76Wy+Om*XyZQdLWMsU!UZf~Sa$xT{'
    'd8^ttNkKSjl!QZuK<HQu@KV%&_)koGIX8YnBjPWQ+p(OG)F6$IF+bz@Bxr6N?y;)5cBJsz5s+x`JQv19'
    'Dpm;Vn$Hrxp51a|4W>;t6C}*b{-krZE&YR)`00Ejg5*yge*N&tq{U!Yc|joKE$7RuR6QsoxBNnOV=hcJ'
    'yafZM)@rjvv5z#&#90x{Wpm3X9ZcX_fu1HVIB(u9+rn~3dwo~#i>QmyjorK3-7hK{f(uap`j<?ys8vXU'
    'uWO&=530Qj52)YTs{4k$`>4iq^6&i4m)fqaI_d3Q-^bmnwq@Cw3(eLMO;xz80z}hIC6%or%>CSQD0LEt'
    ')wBh&Q|_wz!J`T#b3*FTp|U<3mWP`fbhBE)s7k?<yxG=Q>b3@a?JiyW+MMbIg~qS)Num4OxQR;748#Zu'
    'Ceht1_Z~T$tus+A4I~lBsC+7A>YN*k6s&$A_xgRhdfU?Ps}o>Pjrb;tsIMP)po-*|b4g|ea(v!YXst@L'
    'Hg_>gB+DnRtQ0lS(eh^%<8b@?SR;QoRotHDl`}4lqV9GVhTqw^)!P25oO~+jhCC`i(ZHimz&}SWl}QtM'
    'ftTA&w$3a5fj5Lrgaps#u@c-a#`_yE%nd+E;Z$|uQmUOZ6_iQI^&7;3`{|*$UO!XmVI+DV%=1?UE)k#|'
    'ok@9zyRx8K9lqve?OL}T$i1y1Ds=cDQp@TO9V!qF#7<uE=%i>-0k=OEVk+0BbLb~P!%lSjd}~tX*AZ$Z'
    'jn4O59Ei1E;q0>Yt}3OrZ$GT^-JVcsGhoUarrFK;MKZ@c4kMd`xggJFFs!`6)rlMEH>-4!ZZZR{h&E+X'
    'x7Kzs$w!5?o96^|TPD1yiWmMvc+4o7&ZYA#QT$u`Qdf*8qQEu6cs#*UO4&_b7`&Kp`xM8$9I~bVxf*My'
    '?A2GQFIJU52JwbiVcIDlqNpL0^)Di`uk2ehS|s_TowD6W1@h02<l*ltAJ(Hv*zUarg$dj$i`-s8wGIA_'
    '$c8b<Y6TwtOoRqDB9|uF%!ehYHczYWUCz}d1&O!nr)_K8sbV=WdqomqkUU?l(r&#v06k>@81TS?8<~(R'
    'VC%e_p~T4W*2yCSm<a~Vy^;6g@CGcZNykZl{BO#Bbvh^I`!LJur}tdTPz6yGYT9f1b}w{N?^QuP-I6Om'
    ';qGA7G!VT95i3!pa=@u&b)KF2`X3u(LW53kx}~fA4RJ9`?j|2-%J_1X{@25$EE+Lc#vkz4<Ap)O(BZD<'
    'm`O~D6VM=v86~ch(AYMk#7&ae;g&^N62~!d62?u(N*rp@$mdC59Z#)EXyRCY;#u5{V=uO%I7sZ+@>voP'
    'Zuu6Ae422N^N_}VV)=f;T`P_v+u}U-Jo`*9HkvbRJe!#`iK4`3p&19RO>94olgQ%^b4}k&nB{w3NL}s_'
    ')3;zDiRYSb!jr`DBAT?xu(8cbH5fo|&s3^6u+HouW)i92Dv5uuRw>(viHL9ar2o-`1h!30JN6^XjJa*Q'
    'PMCOhLP9$TBgTR#@F@Y(#4MqX6*<(6;7Mxw4r9a}nEqE^f~s|bH;Z43T2es4D+EdAhgK0LmK!^+n|NVN'
    '<G|+de?KHn$Q;)KvY8<Ii5F1U^Aa-#QnAnqV%PLsZaGn8_FBbeiK!_0hU#9dg}b3oLf4HvFZOMgz_xR!'
    'V@6?=nDCiv*%WKj&@g~sViE)qY#cKPT#GY{n{JCO7e!GJ`&LM77J8-`m?kE2+KJ6!w<lp7T5-U+1zVoQ'
    '!~)FmAP!xh2PBSsmvlt{IJuIv4@J~-_D}SDVH;-RBJA#NBc{dd2-XKwfq4;NKPxd!5`;jgzzKjrmTQF;'
    '3%JFcC@?v*8MBhaGC^S2{&5WWJR%`d*`;<wSY(ngb~y{f!11`}yB4!No>0%BB(y;Gxe=p|?=#24Bwe#J'
    '1|$~)BmBIWt+%@}Pa{^{(Vy`+1>MLGv9twpk+ImeK|I=F6uR7V6Bf83u#Dx{aR7t^+H#Zl9N5DKp=5?O'
    '<xaq0KU+)>OE;`1uetP$({%NQT+7RKhnB)YlbA4N5{AHGb{P8HcU^}$Cbff@xS?f*@T;9TxH88y-Pm)z'
    'B;?c$B8RomEtC+#Lq=lD<ROWe9|5=1!~$W)tk|&}3-~Gy8IYcMK5hq~c}N3%0R%qnhn76G`sod)Z?lJM'
    '_;5;r+Ec2?JuRGwDWZSPr-X@Xa_M5SyxYZ-XOSRrSm1lG77~L_aZOAP2l)USAJAo4w&k*bxk-ct(k#$I'
    'oSFpC2agh+BtO13RV8xD6f-xi$OU5BKyEMLmJJ&?@L;c-Ae*h&3pq0hkD}1`9S^<*>bVq@zZ+1nG#pSw'
    '!9A~N$ybUxS>s|tKf$tfcAU6jXhosz(;$gKG1?w;fZGBvRzNStE(781$03%evOv1PmZZ#fPrVpfkbWvJ'
    'SxoaVJ#b#$acO5sKcx$PT!ey<HbE>VCP)}Fu^9Iw*kU0~5|{W9C?-3yL0UVZYjWy?Ah%!_+8{iA(7eRc'
    'x4>H^d4T0W^i0>}db$+Cr-@oISZ>_mphu$+wv|Z|-*K_9o8y7eYC50;fa!cfKp%Q0NF6IkV8ex$OTg|;'
    '$Z?_LVre{^M*#`B2P_*qPJlNlOlA=)2|}<pEHgA=4*+^X;@d6_Odm^@aXaBOI00hNf#>gK-IJ+wiJEW|'
    '5S)0zsK>2{gXQnLG4N<8<W1y)lyOWzAH(MYun`<LWUvk!7@cr4Y*A>9M_}yRQRIQy;YCSAd64)VWxE}N'
    '?d7=vU<ed~2Zl&s1_?aRya23A7xa7Nhx%}{l-DVy1YA<GYQ_c#q{t2Jh=WM-BQPON;&?DQGj`0-i{TU3'
    'qh=BYAiY8l#6Sq*D+Y6dnencsZMansgIog()ns66gJ}WY1p^W1xtOn?I1YLfPMrA2urBq(fOwA2(Cx8!'
    '2%1YjHZVvyRq>owy2*ywP|6(e1S#QxPdpaI76l8{k3gCSk<A0w_rQxYU7t|KL({SY+YJNQ8crOYTKH`j'
    'hF<wpoxC)X+ar`mz8^#&!hM);9Qtt*1hAL@d|eNiK8nEu_BaE*6?x32QDVE1>G@!-ur}mo1oWHbP#d;b'
    'Ou+HwQAmO2G_pWKfENPhCMA}Iw?-`2q(EjCgzz}nqp;MzSSkB~xyAXa&}j#aO^{QzLt&v<gA+V+-wp8Q'
    'O9;XX^p_3pNC-#?1F$t|5=I=oUe6|YjSZZ7UoUm@b(HHr)sxf@tfrM#bHT~r6m4f%1D5~9l9;X^cs#)W'
    'CkbvuP<Ax*@Um1ChG15Mr~<zLR9iTBZFMVJRPZ_I;@apDdW5)OMuVeEVIHpK!ldADyyRm!p##sbn8om5'
    '5Jy48A~1X@=bjz4U|WwzX2Klb3*f(Ket}8=9u6HBtQ-^V7>+ev!Q^y+0o)k8OB3WH-VyX*zxzW`Qo8td'
    '2oav^#LNNXD+I$AJXkQcLK7wufO0oESR9=Bpiyim_L9JZ|A5;YL?(5eF!lr6It{P(3|zS2>w{GVlk`kZ'
    'Tr8{{Mga@V$RgYW#}DL?X?d{~GS0jx@~H=M3m6wDpCqhB41j{taX_}k5%L5mEgMugC}S@n6m~F;Ks(#u'
    'AlrBuH3pdnCM)-Vg{;7}<CqLZ%-(AzgLiNe07^jfFy=;fg!lDAJEUld5i<b(fPaDF30Pua<AM72Jj)Fe'
    'LTs0~?C4d!orSTKW)IO}xX2xb3*`b`6fV#$+o5n0d%h2@jTe}JaT6>o28Iy#@iJ=S`5<@*!Ai*ltN@mP'
    'BM*<lbS-9cVn@``!>$dJFMB%;^9~6K18^)|P>SG)gGysQ3BWju!GR|+BVYu9ubP-FbV19-5y(<t8L%E5'
    'K)1^@&RaS*7t*o0$Q_%D!m-(%eJchELm!RYC?S3va|Z*v7RBP%A-Ld_C3vUU1=kd73&ZLH%XG08F=%iw'
    'iWw!n){>j*7s7|R03YT;`Y;b?x63)dE$)^zkc318XhC2TJH!I7!v~!OHnrt(-**#G%a%<d50n&0>%a@~'
    'LV1kWeC;4K!2xfh0x-4!_7Aviv1z%!>i{Zvz|0^BLNMY%SbzZWeUMtjb%O|YmJi>9>kD>0sH3hZS*Ph7'
    '_!8~7X48}^Q?JR8i@>Zl9ovjyf6*kMpyogwpkEV!CF8(%9#GZ}LE1&I2LTTtL47d!640Cx(X_MF6840B'
    '4%*bF2d-BfamGN#hcQTzFceA+bXi2fVfDb~vLY;cO=#$H6EEZ^9s&A-0|lP7#s#c}u$Dm)pa4uB9^vz3'
    'D$atZd4te~Rak)e1Uzd{yb1U&aTq&MLQU{}6Ao@8m{nc~29t#*C15`Wl?P6_PeKPgW!G{~w2JH5dd|t)'
    'Y?@~R%5BxK0FVRd_gmbgv1OZy4a5LPJz+lVC>OM|ZBncU?-I`jbKV010IM-=Ms2W%V(0j_0>{#gD8;aP'
    '7~nA)<AjHH4Erl_L70M4cSY>h^1)02<C~boC*WcQpzV3X(N{X3r|;9nUOcQe3qiOUor=xX7|*g9Y!prd'
    'Q2k+omIZj==m5CjmpT}{NUVs%)V;)mDVqdbgM>s;==tEfMo!Q|oCLlHUM?XVd}}{8U6(S~izz5SkAlnV'
    '0S3_H0`=|rjzv5gxG^Pe<V6HrBDeFpOY~oe+>hf}h`Aqt`v*!G3`v)OYyg`GxBzTyCjfsJre+5L2j|Fk'
    'n2-7o+#(aKUmpnL`7LS+fQFAkaPoll@wCtZH`%oSG#<)?F8miTO?|Mz2nSJSd!SGW#!JK@1(=6tpMLw('
    't0z~_e|j^0^K$z1$(!fjzP$QB)0bDzo?jVX0e<$O1yQEN(+s?WY4IE=AO_F8Ey>sa%F><7>$`W$>qu7d'
    'Ch`u%wMtT-&K97QGZ7AM2d_3cbyll3Yda8`im|`rWIiP;%s-fSpGYH=J{STKMrL>!Y05=AiYWtFFqiIA'
    '+6$@Qv@}qw2}qyGNUGCxvqZ-IeM3OF%j{SosMSK-%uCv~2<}3HyO7{6O5iRexQl`O-ozp8QCHbG&2;Sr'
    'Odl%C`(Vw%AVu8||6Pcw_CX%Jd<PcMEm`I^L|=Fl(C9at_#vjVCLk)Zhf>5}%+hRfcRO#(zng{Sn0P9}'
    'XUlalnKsxFO+5s9{|<8yEv~TMUS74O?eNph3?;OTP9A$p)QN$CS6~w{S$>LxU6b)wTLM3w&+y7ayJ_Ge'
    'a(Fo?(JV}W>b#zKMHXO?<+R;umO)%2%xRbt3YS5E_E38Wth}|Fa8yK_sov1+XexGCUr0#Hr()YbO<8wd'
    'q_gQY)?w=){N<z(1GCjIY{DjB$|#?{7ZnM!cCYV015mSD6lJx+5hK@&Gy@B;!y=EebQ@3&i4(6t6n-sW'
    't7>xJ%s!w`^IbkbIU?2{3$^Jda**vZ+DbYhV6q!nuey(c^GuTj*(~cIY<8C2flnLXS7>`JjomJgq-FVf'
    '6Dz0u`MVk83n|63PFrV3`xfRaUM#=fI-Bja!j7lXc_xQko;@je=pvL*gR%Fv<f*^+410Obze!iOS?kyH'
    'RLy4`D+1hMWym(K9!TgA#6W8UWh&Non(_r^p&eJYt@1|y)Naqes2=i&4YXK)102$Nk4r^O!K%ae!4#X3'
    'E}WX{`PW>ApW42HXNTKvdfkRA>Z8=k*&Thc-nS8t2v)4y;B^@N-d2>Vb`k9QcE6#2diAv5i~E`%_5jdr'
    '0{Mo4-#fn}l4GAQ*0AfJqAA?={i~GRe!T+gpRYOzDtzw+xHM8qb$YdQg0*-@vhMFa|FE2c8Q*QfuW!<&'
    'Vu{x82>+lfcBF?<7c>o}M|(hd%~$WRA5LoswVeczZqaV(4ggSBT0##1ueW!;%jI)hK)3=F%x*cRKqG`#'
    '+jv%6I)1a_Try4Jl=Tn`i#R2Sfa^{?l)wH)x&Kc<e`M=Q^UBUJUT?0iaoeYhD-k_<MHYPC-o^j}5U{~l'
    'v)oqeYMzJ_`6nATOP`2~f!$yTM>}8Acj+zfvyYV?{tldx?!34qWe;}TmGWAEbkXs9K=hUlRo+Cisy~c6'
    'Z?=cD!(81avh(`?2Ah0A<^v$SA**ZNfxmWHyMvSig_^(F{w=i|dT?OzW;eZ57Dt`;ZvNtrWc8M>yGqiZ'
    'ggXW{&g$+5vgj;`ORm+`jNS+;ck`~c9{iIRBEPJ?6t8TRV);LUUo_7;Gw2K1zE1SA>&Tqt*|*+axb~Mx'
    'GNUl)^LJoIWW8*n3Wz>-0PK)%uSu5=xCX4^9)@aJ9^~S!T%l+Xpgu}ZMQXa5qGbehb(K3!^IKqx_03a`'
    'wE%m(_=BjlAXIZNvC<bq6&ts=Du=hfd-LX1d*>ooy0W%H2WcjT-Fdy2hp_{tvkkEe0VV*xXr~AXNF<)k'
    't{2@<P=2$MFw05yd~ppkz3m)gP?@zaSHP}WFD0~4#wQbXJLQ$XPI>^x?=B4ML7ff(jtZ~m@Bg^zC<!ZD'
    '?RJ@h61n2&nRWppYg>O!*mcMFT{!{1uY~!2k-ndE7+UDiZVX#QFuLqAvEug&&IG$jtj#*%s~A=`x9#S8'
    'ma@n@2Z**_=69R8^V_B4jrJs#O&|VF=5xO86PrrWLiu(xW4!;k!mR7{<}Y0xrfp}N&U))`Uz|?wcUKyv'
    'HFtJ=ONM;D?4B?8TXk_jBN|oqc@yn~&NwT*FAT{}Yi~L}-NJjNj^L%o-t9=GY}<+;bf1t=9Y$v>d&hql'
    'V7mJ6b@kTAId1ULIvyjGN?zm>`7Yh8vTtU5&N^db2TYgKu9CL7O4IHEOErhApFOUE)?JllnXzSQqJHeO'
    'r<+vM>F;iyXyq6Sysy7)(lvR#xxFQ;yLKnz4aZ?BA0F{S@Z4PsG|`_izeM!9ePq1}rV8>aioKcLa>2A&'
    'S9oY1-Vp3NNZMyNR9^qv22_kZ97`8plT}v``Ta9>Ii|gZzV9?2V+TWlyvVW*-*&kl012f6I8Jmm6HPQ*'
    'i<Uj$USlaHzUsQq8lb5iTe|Ki^jr#-LTAk7XQO#D-`P9<^?b8>vJ!>ByFx3(!4H^$`8w~9-33fly5Ujn'
    'oXl?jK3m_g6?xw-RJ|9LkTCrrRAozFN;bl*NSNNxc6={=kUHx5qd<R=UEGG?PD#>NWRvlyH)%`#cL<ac'
    '%733NSo*#*u#!X`^6n5!*QI)A05v)AieLw4>=4%nQdzL~7Y23Vo*#1e1+*(ZJ3|tVJBH|=A(|Kcrh`DP'
    '(EVPZS3y{3099%G%Peoy+#e7c5@@CMBG$1=Y#o6d&;dDoaiWV&#;-9x*(#Oy&?rJXoC0=LZ=7(1iWWJ+'
    'IAw`@I`AdaSmPkg)@pC|Y_?m6f@_dX`ax<$YLg(;48ANPHG<wJJWnx1E>;J_K2RF5+41d=-hXt2#=yRg'
    '0cxJCCXjXSRtMNd8KMzzRhno9{QLv(#golC&B!~h8FtO<)(pML6W2JzA%9xOFo%6?9V0Y}VO?9PE`xQ!'
    '-6w#x!{0G#2aHg=|4|e{EXr_*z7HL4I3ECBEwdP_`1F*BJ`&TswWZE6sJK{-w)XV>HsGRrfZs(BMkmx9'
    '`Bdt@lfagQEf+S`HAE(@-f1d?8<|fN)s^%VgJjaSo@!zpb^Q@9KgFB%8U_HdsSB`UPS<$509L_fMBN{o'
    '5=NHmR#(fbW7MnQHTadig+dc-;Z5p;m|sqisL}^_e@s*R7!~hS8}uEsR2$^o_@Zvmm3ZS|;3Yd+2ds(#'
    'Js9BLz@iSwje$m;fGdGVU4VD(&cTqI3_&eG%NF2Zfcs28eSmjtzRsYlmGjVWxe%7o#nv)vD4*9Cw6KXZ'
    '!OM#+Dr-nHRAC1dbrAIcSH{W35+&`!+zz@Z?4V&#mC18~CQsk_4zC(jhEusK-l>qqUMO8X4jt8*Dv;1#'
    '3&Fsja=d)fe^uHleeGsm<aLkR=NdIZ`9`L-u>8(Izl?=Cw5M|rT`KI*7uNR5o=9REw#?nTY9fiDZC-3s'
    'p2&?b+<V-KJOXS;W=0u~hSUs+^Bmf{9_v%rSaQ4Tii1e}TDVp{A-xu1GtP>H-QI`fmAc`*q15-!%cTs5'
    '_l4KYsC^HI%ly#mM7O@Y{^#BZ?Ug8HrqYOqfx1dJYc6i<4>`1MV$Z%nDxBHxq`A(TCpeU>6ZC{b2qka='
    '_%+3Ff<x8vuF-L%T9cteK~`>q_6N3ebvaKO7JxOMd)5=JPccSCyqxlMa)0Btp^%%+u~UptHqms#ukB7%'
    'wL#|y%_>sofoR<tI}vOR;mLhxj8%!F5%}&c2Q9!4%OahJe|s$&or5$=JDmeGTT)sNNt+BTZKs(Hc9%xD'
    '6;n*l+34~1dAeY$izaMJ6o;O242oJnC*-sc|I-_k|EfB(h9NSb?R2rEqCVtmwOMuwRdwzjH3;e+uTVSu'
    'trFLHind!U=>(vKb)XHdR-0hACsj#lp91F3OKiEP3vyXS4~KbJGiy1G*{hPZKyTE=S|B$oVLb;_P1<+('
    'fs#J8y90EX&h6aUsRz_t>0RWC^)%3hO4S2%t4uG1GVKes90`B1$gos6CNA6pBzbA+Dt({zj1j+qnE||K'
    'Jee(K9c!poz?F(s$*Z#iZ`(C4v~M7Fca_5;d}?yr98>*KtcEFfj1}$o0{0PJn=jbF2&b^)XOax1g7<?B'
    '%0{-+rP_D#u1CR_(cLR2qAIr(S}(R})gifLu`WC?6)-y2!f%if%^-W<>8sXwl1WxQ1;xR#QN3fn%4(q;'
    'iHwHOCOc)Ew5jHk<~tk><kK-irE;OHeW*2tbBMeeV?<>_>&p`tGBi~fnsP)@ks*<3@bnAN%N0-f3ad$B'
    '$Db9KDR;=HL#4D<&e?*mu#L8iy+*O3%Y!MiNN1Q0hGp&!^($3UDq-_2x#igVN+lC^PK&6N!o1?YZ)PH3'
    'vWW-Z-ENp&KOx^VyAvFkRw<+3(rm)Va8vUj>2%5AgUqW@(C=et-3GHPZh^Iu!SLimm2NBBIqy0wGUa*;'
    '=7ZGMB}p5opw)iXh5cr0S|R#EAbN;FUBX5YH_cJqPs|>IILQ8OhN#VtZ3M6TSXKqdutwx+@p7{U$57Lu'
    'lx+K*AB^<gdxwyrD?Iq3bZDasrXGyefcCP1a_RLX%dnj2nlp?IX9H`iDW&ve4a^>I#0{Ha1>m-^2~hw!'
    '!;np;Db7}!rG}7QX@0{@s~Sa4XI+)nf4V_(oSedG--9vDZsU&mKuUb0@f<n_zY@GOeU~%SQ2V5Y9c>4g'
    'yIiCjbahv0vPnwR({tpJ1D15V$m!M>_;x4lG#pSp#ZI?bh00s5_*zeZzhTSnTa#|@2-G61atRaXFBlgs'
    '=T0dSW);NgipW>Vq4UD7HrzD8*0fKnDAnvdJY8|p-*?z;CqdqE*7;UOLm9C&T|OmCLdDg1y}9TIu%N*^'
    'k^5S-JJ7tN56t@%JDLIsrc}|OXR_ID?SL9t2XD6n960o%EzI>IU;nVofIa+ug9XoJNca>QrrdDle!@zU'
    'WyG@JA5jLiFUOo{@{J5xqJzF<xuVaX7B&=9ypTB6aUT2h>PM_la77l^Jqle{>jsxV^$kAdEfUJ7Bm)(Q'
    'oRwUgUgc3V6Ow%~Ueg=SHmA9?vVSzqN~KDGL1&qVCB*7>iaWV)Ui8lXEis>tNb??S>k48w@%d2su)4iK'
    'j1EkQt0ilEyW*nfVUMfByL<7c6fBi=wUWWA6DKXyW_}7LUch=l*X0Ysqwei(?ZKzp6=V&HXIB{oXMM4q'
    'wI)A8B)k4dmP<f+_vFEfBDvxWOL_=r1Up|1ImswbYZ&v^XLTA!q%vQvM<lxhI>nY)6<C@kl6V@jJbvU^'
    'Ms%0bs?$^F`D7W_19$5dp%)UNngsis6<NsgrLQU06&<!Yo+L0cN>=<Cr?X6N_`K9N5L=J^K<)s$r&Jz0'
    'ivh==zge+QKh+7KCF89LRj1hIBu5e6q7yhmcMlDJ4VhzN5z`n~F?|oqn9jvIT7#}`pkk^Q`BZi6pn^x9'
    'znd{kZfo1gbkBC&)(f0vw=)oT^8r~`uWr(HIw<9;+;VeUXD!>z*VzzlT%K4zfm559i~^h>{J%rr)2RCj'
    'LWZmRgWP$t!s|K5YL0D|adWBz%&i>b3RBYrH*#O2<-oqtX<w94Gtj=+ipLxSI>e(YCi=td9r!TaYdqDv'
    'Oa4MuGi=?`GeXq_>ct}CtNy7?WkNs88_cgy*MKC)<Vhn~&oL=Yzo6TLcYWfnh9gaKsD_-Av=V6GZmosp'
    'x2!qLd1_I{dk)y2Qb4~B6A&9`Pg6ubfZVpu)=+>zU`A92m*Gc&oZ)v7>MS_B)f+3^***iseqM<bsdj->'
    '(+~y{EQado<vXlz+T%)B9nh<7In%xgsJM%-I9|;MI|cL{(=Xq4*R3URvomvza%X4Cy6!8fOE|a>gf`Iu'
    'x7>Cd6Sjr`ZjuRk^7~34d&(rXb#x2>giLQFMx=b~mtVgNc`Z;PykqzWQ{e}u?(g4uy>e+)#sgj)gbAv<'
    '9s}ItyhQ(ydZ@24=Wnh`8{`?%{nBQ4miM%{IX4(o*S?EeakK;K1m<Xo7N_xut4+^)Uy^Mg_KDA%npjk`'
    'M_j>;wlZG3n9?X)x#US<#Yv_V1;TY^31c}ajZJVwYVdq|jR={p6-N3Sh>iPOXDpz?6upGCvNfK(BWtn}'
    '8ldN$hqA%?hJRQOse)YqDJ<UZC8u+na=W^&QQBPy{~OS}=+U3I0z}q|>RqA$`yCYc>Dw@PFP;aP+H!p-'
    'iXm)yYH0P{hE;2`*(C~2qz0;ZI0fL^emjAkO$36pTfwMT`uCu#<^D(_YP<d4v}3i#2P%{so=jWvxO%CS'
    'Dgbi(%YbNrDzXRm)oL?aqab-oR;xSoT>FWt`s7Yw7}m$oxQ(h@zXsq#y}n*$78}C-uQxHC1i^1FZn4$T'
    'pt3$YFfpz+EK6a}G*9Um>>2Wuf!M4VYdRBy=?ZRENzvETM234Zk2kk3ZppPu*Y9j7?kMy+M18qab;w%9'
    'wt(9iVp%$h>520|aaJ)Li6vNiakvGnrKMw|eIYVO2#z*g;&Ac|VW@npO@EN6l=lJB)r-ZunZy9z>6|Tx'
    '3CmrmeIsQJtvdG2_>^*U@1UoUoT(ZNTY0I`#GPXpZm{e;Oqn4<RFw$MZyWQzH9NPVglC%-8C*YPXIeuN'
    'hVmH=5^K9N8tOh)rlw6w?#%Oqp~QUlCl<vsxul{%0M}7kE(gAVbxc`KhJiAE2l+Z<bUC(9fMJ1zq7%C;'
    '*Wc}qW=RNK&FGD^ONIyCn&A!F$PM7MZN6RDC*B$>7;q|&24}@`1~T#PA_mziSK{W3Fnqp6Z?jv`nx-oh'
    'b$F*VA$CVQ&4mZi5mZ{6*9uELw%*ppRN<jvJ8uV^CdWWuuIfI}_vjp~)MB)`2Yn-Z^&}dxht<WkUxp^q'
    'lz|Q6f?a6ZxL^nLiMfE`cuM*%)nas{PL!80gbOfa2=h;7*UEC}d8KY2xIuid3r$~5`a0+n^8rRrvFvea'
    'Ed$wLX9Yvp0By%o=xIP2bph$=Hl0%3QX33!l`e<E=o_o3dy4{C-y_}%kO8N>6*zCOT*G=WnC|DrjV|j+'
    ';-fXdI^Cw>(NWQT=j#mvA`Cn<%B@NT`0wfJZMG!zq*+Dvv2-Us7Dj9?4&Ub^X-iZr1T7K*{8XgGlp-lG'
    'UuST1t&XABG+k;-yl!G14gQoc6t4IhBuw89@iTRrEbbahn^Sdxo%g>U(*#wAzgJrC3EDh2O<Ld0lARUk'
    '>>}GR^%I#pb#GOgzbnau`Zl>J5GIXk5th>AUo|0Ws8uDJCUn0}R)X@1i<S-pfbHClMKJnGZkK1JRoj;U'
    'Yupaa_&im_bcsXgYs#9#Udlyi7^CUdXN5n8*UHW>iQ)c|TWdgO>Ml;M#TCi?#uX)NevOi$cdBmF9owf0'
    'YMy+p5h+6<i~Cj*2Nx0t7dZ|t3LLb(WwlPzxkPJ@+}V20$=ht#dHwCvpI$w=dj8X!>6@3+D|`Cv`44ZN'
    '7+)Fx_;|J?>zlJn;~!_L&*3yCYYak5*>QF*<r`Mq`xd9SAPXw4?&j<M4d;3m^90ZZaL%ajcyZ$UaTGd%'
    'M_uMeR+1zvG(9Vh%s8=JFX0}ANBq!YG-4ieeVei<qCAYaSo;|f?2Pb)zTjt{;N!NFEi*&eJqECNv3Z)^'
    '5Zm*2W^M&83qr>-6Q48RHa&+WA?1Nd2&dFCV>?I~^F4TkJ0zrWV8>>{BkEC`#er3ydB!DIoPlcEh!MQR'
    '52845EXR%kNfF^NAc@?_cR7i@Ft#k}1dijem;}s(olPUxbS)1ML}(Cd!otmF@iyC8K2XaFxR*GLB4wh)'
    'w-S#8aU8-ttjM<P(1xibmg#vGvl&l_M;#uUQRu~9VD2n`IiFEQ&TLIqYxpo!f2GUfj~qF`ircx!93|s5'
    '&iLmSzb?-9?T52N-~IJRGFv>MU?mu!={9t2)N%5kr6#PG27dAv`H%7O5McbzoUe_QDA0Uqkj0%*2nm#!'
    'AnuR7|BkE-bq(w%a?6FMa%sF48u>A7&Bbiq2E?+`#uwh(?dywjn15K0#%<uGi`TR3#S6g3Xf!r1{$l)+'
    '&e*u+gb*jJjM35d(((3V0k-t_F{pnP4cd(5YW5EQ#aYU#M=+@}LI1V^>3MvW4d9dvp79L$5HD5=L7Yqb'
    '-%wEg)*tNMH)J;F44@=rp79=lR@JHzwRP8OO7z0OEW`To@thBs<t)oKTNeIx$9t2~x6AfEu)9ySx#i-X'
    'FW${o=>i?m(XYQwGRhbH)eXt`xU%By=SKkc7Z$^1g=SGPR8pKoQ0SEt$M$n>{sG**rr{9yWrzR8GZ^LP'
    'pI<!d15hqsGq~3`oUdC;i<65q4HB)jK>JjcXl09K4~Xn0eV@r%g4qDksy07pCpnqkDoFuCjRc0{fEney'
    '`YnD?+6Q8D;fKA{&~n9>WX0Lb_X`x2C>_PGkB`C1fuLYfYsBbKWojbOsA>@$p4}ncrG?PC=&Xy(8tI{('
    '9B0QjUj3)I3paX@<-<)x<mD!vgA#slZlIdGG`^mR(9GzX!yg}&fSbJKckj~`Gd_W@w3kORd<FjVy?l5)'
    'o~*@ntL0|>WV42~EobW@u05J8IB12VTcYV_BJOUie;_fRk0x?G<B7U?v4&Z{A=z8_hrB27r~Doi@+ad{'
    'uh9sl*o!xw&1dU7+4v-x@l_d<3O^4zFGr>?!CY&*1?)Et6Q1J|kq&aLr4c1zvIhqVa+j^Syp(ZiJeY&}'
    'm^c$``|wXNYRG)TI0X|d;}6C?F(an;dVM$Nqsfe>i<gV}-53unZu#hTw)p#ut#2+3*F87jukSdvXSqBu'
    'U)LSCL3Y0MPRRZ=SrR5V+p@=#n9#S^t8}wq$UiW1hOOpO*}P(8PRww8Zp;>kCVPc%qdul<vbY8e&~ycI'
    ';0mnQ4LD7fKkhU?$q40T%HM!Chxz%SSiXNTpj!&us}MM~3^*(T(j`|#mNPNYHk-e)#rF=|d+*=V*4Mc6'
    'PrdPn?R$OOzJ>m8CDSKlxh&P}!+3dlHf#K#our*)=mw2u`F#w|E{!kCYHfTxgqZ&nCeb%r2Wup$f2oAg'
    'c_l`*{r$WaWI80nt4|`z7a*&E{#_(DAaH&s=Q+aHTZ{cx^l3-LHE_yk25VjA_UO1^9A&YNS}J)Ep-+}e'
    'z&`*edyLW|X$j%kEF(=ogwg$|?&?k`9-++D(dKCUs0GQ;p_<GV??9C>;afd2F!>AK&xbia*`p8q6=P#x'
    'Z)T_(tG><V`WmA!=>m8!OK*A05IO$L65|Wy0Ze9@sCm$SV|)i534PoC`CRFj_p}=P0f=kR1*6Fg@C+)5'
    'aT{x*jj|XjQ#6T`3L?<&TGqopP0^qZ@TiOp0-$;vY@)szflMxh)1BOy9R?7h<>~%W$_sirc*J`Vx;2@5'
    '-oy4NesWMh$c=wl|KPmxL91EG2M5gxgj;b^BGDu%Gr1*85Qks@;|V1LEz_EL_x@aO2$<vL9dX_elRV$y'
    '{IB+7qA^0sQJ#J@WGYlIgR$~6ZDMADw-MT2If}+Z#sM>_l|n!JOgQb%V|9sezKcV&p_l8*jo4B7m9eDc'
    '-hq3OxPt-I*8ZtHSF%V3l5v-0jg&bqCJKb7?-$vqDs2aBmd4`*G`t=en<bh#PaDodMkl~`$$smM@_$Pt'
    'E5r1ju-wXs8f?>-4RYC=XOt#&+W<gL&p{xAHafKU9^;gch)*|2)fmKK-YKHC7W!zA=P!Lcz#gr+Y#<l4'
    '#KK-L?a{Gg)BXO{nGW)F7ao0F#G1F)a-<#EA{RW$QxW99bxm=J2l(d(W^%pbmvTTIl>F54(5QU8s1Ba?'
    '9<xux1Hcv&tSV7k*tpM-dy{}Z8m&b2;|`*JJEQ?){?-daxeM}jn$FwK@y~zmFv%qfHB@YqMCLK|nPuU$'
    '+`}~Uz0!A{_k_*47^?Lwlg)zGg63@m&cPIrM+eP=hC{j*0}fCJoltR5cDKRI!-vM38*VJgH8;otjb}gt'
    '{1+?@V+~)h88$-&*yn~gwlRnyuE-deaVF#uh?(CvJX=rNjrRKeY)x;FGqcSqAry8!$bA?k13sJ2F<75H'
    'f>AQQUgJJ1CV<bs16hpEBL`p`&=x~B27xL>eQb;x7~pX;(+IUNHd=%gI)|A0>Z#>GAG74uDP_0S&9JMt'
    'Hl5h8@|iZ85Nxde5wq5I#12rDC@+$qI0v~RLkr3ez6a&4F?f7-FHy&if$5HM=|N%Xmf0@)PE_iX+u9|K'
    '^J^3IujM{}+?sGNFsp9#mfu|(yF;qycMk;j51M<2fFjI_MKvXk4cjgK2lCImU%p+<*oda{%`GzNKk&~N'
    'YkoVL5Jr}`>G6<vcDuQ~G%VX2kAFKiFb7u{G?v}rr0<(_^_<X~(H6nul9kc%C@w!r@0!elyK*7-loa%j'
    '#GeHTgr3O%n9SIt{)c`tG?^dmcb%wUOW5i$2>9FW7N0E0EiX>r$p>}%4jw>)PQYE|5Z-miZPP|{#WM8l'
    'rl!rLtmxK)XYWI=R_Qh9PSG!<JXK{nKRA$|a9v8%Em&szVjCRFa8`qm=z4V1R+My(>U~j-q?Q#?|4`hq'
    'bAa~BS|_)jS^(;je?7$C+5SVM{RG~B&M=~tV}+0Vw^z@Tqmv5eUUK=wV!4H(Q%!oPW#)Zlh}(mMGao9B'
    'WqCxo(JP_3>V(7<0eR(RCrJ0`VD>QH*yil}*@DT}JI=CZ^@w<d8h31v><%7jo1alh@;1KsY8!%Yud=H!'
    'N+2H9C|C-4VQTxMo|okEA7w_vYvnZa2@XG6Y_CeyFHgZlc2eZ`4_E;$gJ9ZBZz+zXgA0C0UL}mPb3>5U'
    '_}9NmI4eAr)>^3QP02P9B`G2ji(-B~TZ}R+lau?}6Y*CoJCCL9*#zexwycOJ-6`8%4Y^(BsI`G9(N|eb'
    'F0JKSK~XiVtB$`GIarco#pH)D?I(Pf-n2*A{jG4jn!};K4jkT1rWHw_9po2s)bAU48Bc15Hs<~?t<pVM'
    'c@H|Jqe|JYQCgtCCcVBuPaTDqIJH6+>TV?W)<b>NP)lg{pj^7?mQIHKeFfs%@7lwg_S0`&s$1l@mh(=B'
    ')mo@WDt-7t9D26r*s<$-)VFCuxS#lb$P<(KF-Zc?V$_CT;~+3C-}aKo_q^D$IJJFh9<TJ_1l&zxKQKMt'
    '0}v#z6N_4encSjYY!m8|B%zMy`;lk4UKG&K3?h@cJWQO(WoJ5Z(OmB%vQ3Y1YWXarR%CN0w2ABcJWj&I'
    'VvGkga$vfNZ3m3FGzne8L*J*CO&E(Tw@tkdzg+JlsMh=FMQ+(S1B1!k2=3T^5QNm>j-SL>$%I7A^aG!I'
    'EOc1pTXy6*N$h%*xFm3FE3zy=iyzw#jY8gn;M^jX<FeRsJdgVhHT^K5v700wi(`+(G++Utrs;+u^*uLa'
    '5ivd2aUvcfme2HJqnYG1@Jv6ls2dSK;lSipkWdmuz}R673=b2GV<&NK&Hy*Q<6FM#Q-=U6yS^KQZAk8x'
    'N$w3G`GKOcJC%F5LtWQRT;Bw80+9pTCBVhpjG1ZLw&^;)X9kv)Fxv@SAd3s!kR(xHhF(IMhMGgz=luBx'
    'pvR1Z5)=h>7a(u<R7v^?zC6ZKxi_5iG}aGdX225`2Tn+B(@Oj#ieX_kaI|GPj>%%*VSX4moVhXg7@)%9'
    'F|e6sdBEFF%`mF&8Gvuv7H}s?Y)Tn$DB+Hqz`pT9J7hKwY@32q3vDM#qR9400!$p(C<{U!fP{<d@Ff@4'
    'YWp0r3Cre;Eb4)H6*Y-pgQ+X)dbFs}Q`0%J{00T%?$RhVq`wj$wFiUonK)&4Z7)IW(R`U$38=o>+D2F{'
    '?d_$S=|uc>ZixGe*@1gKmAI35bD7RE%)iFcCGh)VeeiN-!z};r_Izt^C9<ti-HM=^=&6UC1vOP7+-ojs'
    'jslinEY`<s9cki<dtr)!Jki7wpZ4*@-h)cz4|HR~{0F>>cO=6waUP(}X8$~#@Yp8MieepW;J`nlaeq*-'
    'USk9v7ykfM5qQPCPf1NltqEUjZc$Hjb~rPoO}>K2=}@KGVfIhIeT8F=K3vMdCm)ReU!Z659;2`4#$Eo!'
    '9emMB?BdHeB1$_RHdXNG1YR(A!UXam!Y8O#N9**mSj4#Cj#kqXK*0X|0Sw(boc`1O)K1X#<!QYvt&gM6'
    '_HkGy<>AwGBkDxmk`E*Eyvo#6e0O13!$uO!nU7PG#_9^uEygBG6FSf5(_+{!&GFdy55od-J$~G<fZlU&'
    '-u7+OV0jM96;Ea#Mq4C|dkBlqB`Z3Miu;rlg9XK2Inhb`eNyNB*(NTI{9$E_R0N9Hv)T1b6kAikJIbN9'
    '&|9vy9bVc!)#{;#4<8y=9Bi4p%t#mWJCSyYrW|MaUNzp_%rXP(lN&c6F&C*ZPpNQuF)MS8y$LWM^ZjbJ'
    '=55%5k|mKj4U<+=+^sT*_StLljx%AT$>|TUVz)H`s~+U>Dx#;biFFn}JOa9sU~<LThVma%xk0OS;<n$k'
    'AFHX}91^N*UrW-7Cp&DC2GH+XSI%rPOOa5FmA1q$k6Q!Fq2ydD-|yjw%vg&GfrpbdFB_3OQMWRCK-~!6'
    '>>uEq{ia!(l~E^(TB<^4P4ho=)#SX`e63xwE{aHxk4ZPH6&IG4SY}`HigOi2ODzLeLhr^kzX-Q-MCP+='
    'AsH@>$(*a}?5$HQo0T>wmnZZ0s9P54>K2PI$-I7=-Y#J^Tu}@!U%lh-_2SwfhP233!hb7LW|Yi%X3W-;'
    '&NFO?g^Y4GlK-CXMkop*$RobT;=e5hzRZbMgV^14t7W(MGg1MFn$Pw|4E}i}z43^FmKPXWRrl{Cdpld!'
    '>qk8Ru6<8d3{37LNrEj*SUmc=0qq7%HX3FO=LsQV-nGoL^L&$C${k!k<=1Au?fYW2MQ1r@ac5qSa!uAT'
    'mbPPXZ)<EFEvUDJbg;fwBWv^{*`OFeiCt9(B+g{f&+qx&XlHNaQi~n9U|1S$XPM+04A}<;u>B4K@Zjdb'
    'xV}5^yZ_l1tsU4(cGaqc*@OFJAbRDN%r}~{`9_5mmgfiM22?A3Ci!ko7BWJT4I|s9KlIj@oZoNn_j;?6'
    'cP|e53bnjcU!5E4bWP@$Ln3Qc6v%>#@>W6}1^K8C#=1uP1y?0U+gVwHhFCj7PQVeS*ar?QG71(8R?kdU'
    '^0@Q|zPMiBjLh*^+pG_<$reYw1{0`gBjR)Or=NgVZ=;AmtUY$#EWUiu&W_vxfG!Z|iXp_1fh;VAgb{!V'
    '#?fTqN>y~Ts9xE9jBY!%+tcO36z^(fDJr_JJKS<n!FM}XvxmVhl@v+qby4(zZZ3(U5B{nWG}1IesSb^d'
    'z)WVWkD8YDitv;25@=r)y1IS#b~Etu>4VVH;`AXONGWa|M+rq_{x2Aq@4dY-MZA>nEz(7^Ip@pKf-F+G'
    'x7*n#wZP0Pv{Pna?yNwW{<MWPB*?Gwv-?x0zj+{>;w@8Sq4Y8@KN>ctJ;}O7jN!cb!u$CE1F&wdZ#ney'
    '8t(bL*gM36I3J?&Y_VLCZ|^iutb<ha>ZjC5=j;L{l0oO3EH+D++Cuz})hOl!d)pkZK`~s*RZOMlb1q`|'
    '^kz0^fR#%_;0fHz@c^g??Q}eDc`!a<=vO8(SM)|VX{Q)U)vZubWbx0okkY#&l_k#GIcQt?P*Z`OCY%TH'
    'c9he(@kQrd+hW|0)re3B8nr)`{Pf$Wt|^=9n5^8;@>njhX?hN~C<zkVabxC3)TL2KUCsmFi?N+$!~-+p'
    'j>(*e#!lpfu1Czs@*>-ExOY64*d{LXgE)>&(_x9}yS^7iG_owhLuwQ1bK8ugh}$Fy;3F#uqnN`eB=ODA'
    '3hXmISonNxBAs#$v9rHT<epPByxaR))bZ)x-$+$w>JNagR(LA%9RGRTrt@N#^POTFzoyvVz5Vm8&s=PC'
    '+^t|k_4xWH5J?ox^aQgKF1HsPU&>FOe<0{|b}A&HM3z7-*a+1DWhnrKbn(x*tWA6=NZGOHOJ1O0d#c{O'
    'dPOZGob-Xw{)j9b_k)f<s^bQ#-3c#dEY+?|AZXir!#H~or|H`Xor5LLigFhN{rZEGS5*3Ey5K^IiEP(f'
    'u$BNX$!7k4@$--MJL~(0LOA)fMd@~IqXA~vsAt!pf}7MFcCd`CIQ~xNZy)F$RUwAS25ky4@*mEgtn&%s'
    '_ds1F2XGetHDJu+Cz|6ypw;YA+GaWccV6hHo~_|ps-vOWXrMAWJbbAM-1q#hZ40;}Aw|4(X?#b(t`fy('
    'TV50_rDP~O<p(g9Umnh2sNH(M1;Y~*j>zx#U5#~0SNXEk`ik@rHS5N*r03-s6~A_@Rw_;Kt9>b7k6|Vy'
    'vZ0%y=4w37RoZ2zOTwj5pO@L`&_GgG_a3KKjdRa1;7_%zrP<NU>S$$YH?mG{V;wfJzN(O0tHssE;QFe{'
    '<DJXYbhE!sYJT05^>qs4>;7!7o~GAlvAjNm;dRtFYD!Apo27WvW;&HE*2ffUn~Q&}Eo?bEY$6K%s_snn'
    '+?VY44Sq=$Y(hY=y`OBBq9WzilG|@JcIh3~?Mzxt87lyHZ@s$z>E_L$>QcNyrA+Tm=E-eq0V);V*@+cd'
    '#f$aN3-XT4=4e^UqK5SaNzVLn2IyT}ckpLL&=Qt>OIB}T)v9kO;~8DemNE+4jKRu)-^~{52jlSxm|~Y^'
    'lUudOK9u-a%~6qK6xAKuv-P$SWvf|ynk?!q)OHjiA|dU-`qiEyXc-CIt?#N^xj0nERd#W>_x5WOaB+}Y'
    '1j*R8iBq>}4|d!wEP4U2$(L?l=C&InwMKQf`c4YLt+se!1d1w1xj|Z#MCw*_OPoI!5b+>dal}pDeteS5'
    'R(M^)_|lxLGxRPBzYJ?<6+@~{)$)vZ|G>ase4b45Y0H0yRm<w!{rDcVT?=J*T3y#k)!nD2JD}()zHMi('
    ';iT&B-n8BQDm(qUuDhz!tmzIYy6<^^1y}EkR>`(1Ko^Nt^&#4W?x;F<VgVggsTNIoIz`&O;M#FD+Fgr2'
    'ss`5%U)rc%3M*$22o`Da;^CU12TO)_(%db_$ZKroE7`^t`&Iic(5}jbR?LSws`Fu6RZc%zJoKdN+BIs1'
    'EM~x-_|&;xU{kx_mI)u!qr?j$*CDP?u}oS_gMgTcPeMB;f$4CU+mx{wo?(vZhK#v^Lt+*Ne&n#^c)|w@'
    'P0x#>IPmO*GRt(iYsOA!C$VEPFQ$<nM@g92fp5eA{Wu{!;hedqP0b+o+%tWc_<TtpRypazI-K;eZ4L_p'
    '_~lY{ml=&@cKx}L|N8<{V=w+<{F2Vt_-Gb}6lVv!z;yso>CD#VJ+UBI#kZvn3xC5ZnZ**0K@o>dc@OIy'
    'Fz3e>ciuSl^H%=lnp|Hhw1XIU07fH*SFchGZdN|d($)IS9o8#;A+91@?cjH(w$x(hIa>dUH+7ddkNu+^'
    'Kz&QMbt+qgePzhH0!WY<ng1eh`bf$g?MI@Uxrg(1PuAXft<nXs<9i*3+v!O@8g)a|ke&EhHsW@lG&fvS'
    'R^EAYpTpwYeTdsTY-Ojlnchjn#Jx(1-a?|QjA(JVF})=puq(?!SQGWos}-nRRZ~miV)UgsmX)y{w2P`v'
    '@s#S>f!P<f#WVO$+85&SVlSxWwHi%Wo0aPO+dm#vzTH-?uYRDO60|+o;XynxIM~@ci*v`BZ4>LeAL8FD'
    '?N3MgBLr?7xM;WaRb8q++I_Av1^L0@TK&nSCT)cSUHN2S(4cR&OA|MCJZXJ}H_ulMP0;R8w2MXsB9{22'
    '5QU`%M?JGx>n+#FeEwiO0cA77g07QAy5POe-kSSW)e;)MG*#;(98W49GKcMjHwVZ4QVcu2us<BNMTn9H'
    '1r<7Dqp79io<?^?<F#5Oz1zw<J^WfSRCzKeuCfO`_$fa(xs{SkL@3vjb;@Kt48^|NuSW8_vC;X2<}|zH'
    'M4RL@?UB91K743=&-v0I3xj{aaKdbj)}^=`OSafE)cJsstkPRi|7ihYaPMeE&*cO6=^h-I(#yPz;U)vR'
    'XWMx^6uk2AiO@&4<j$ZXv<}bCGWdJ3A#>SY8U}vQ6&EU4o_Bx|ed6job8dW5>LaCY>}8|(H+%)k`#|_y'
    '5D8<4CGem6r@M{zNsR|sskO#74~+ly>#w8jz~g?WN~MF668DwB-dDoXpFW>hKPJ_?_7-h*;yR$u=q`hF'
    'YBIX#?6qIR(L+-7h|=rHt)1|asG)m|RUETbP0_xaJJ+4tNeajh<Rw^nW3@8UxP6tMGubn;_ulV<Q90{-'
    'kqSG!sl16l|GBB}pAL@Y2<fvhsv7x(g0suB{ftKaHe>sPtf$~|J$yRf#7{Tb8hpByI@W%ZE@xDv{_bgz'
    'Lwp`!R~Q-*?nSmqTy7<?Z4(bZC85m{YA0qCSuAk_-=e<H!-xbPUMCK1P6sx~Ddznx#yJ;6bjVp?4fK5t'
    'a?Y^*kWDSeHWNyH4*!dNFSh+CV2Kkau4{QF^*!5+sBJm183jRN!z!4Sc&^199Ww^)1qzm9Z>6Vcx&qxp'
    '+P9p7$;1KSffq%t!;?6PLeHT|lvv!Sfo(F|qi$po+q7IBg?<pRz;=NoF{~^MX`5@}al&nf(;zSbrWyM|'
    'Xi?XW9pc5FX%jc}JQ6yQ8xz+jE{na;3pi(<@5FHs>qSQM!66U1?FMdQhJooOvFZDX!yGS6xEDGs4vA^P'
    'oMIXhpejjh?h@Z)QE0L#@dHBJ92|P(gTtt2$0@PK>Xnfnv4p(N_D$G-%JHaUy4-XEpjZ$@w#yMURu~5X'
    'i=!l<lsGhSLZD@WRRowzTq|*-&~=ZsZ}Ppw<Jk2oF)i4{UKn_Z&m-RsB9p_`F?kX(Zd)cJ0WhZr{2AEP'
    'p^P{{3BO(Yrb?ttv@rl@<H>48?nXtOU6yw?D79J`k5$x6_O3Y;jx9}L2QXWu%Wp8_qYAry?~j&kLOPb>'
    'zYlC^MaJi=`2WO+F_{uf94zGzUhgaurP(uj!`Wue9~t1u%L2@pt&*K9S2@E%|9C4Z1OI*{lwGSamzx-5'
    'hEeZ7wJjiZX*~aZL)OPGrPfoja<Jg3Qdv2Dw+_{%@w2#biU(M>IW<l3{{dsDaQ-)FG$Ys8ZdYLaE2=91'
    ';%u|rkmXVysdcYME(%?i`pcAHb}MEh^PD6&tW>75o8&T8pYdL$vv8J4j%#d0BgQxf(-F3Ag%;h5<!5WY'
    '#FQ{G>xcO;|6#~6jQ_6~7@MLzhW~di2`VorV~b%$YJmz>G7f$>J3)JY1L|MB`=4ss-AlsdW6Sq1a(G`!'
    'bUap{t8!d`4g9$CAac=o_`?@$M7uLoH!dmoOpg1<7Qf=O?n1O%Q9UupW_<%*=K5}8yqSShks0&ZJM2a!'
    '0-3MT0Q&ib!LVob91G+ZeS{|+WPV;PKIZduah(C3W#kqtD3#LrP&6(-uh-{S$)9AwiUL|K2A$6mj(MOO'
    'RD>*t&_gi@V5(?B9}QCz+7e4Io?RL*V{DAN^|kv#%<n^8)^B#J&mZ>%j7}-J=AtlyJZ<g`3iu|OU1Lh='
    '(L}l<*c;j#2Y*WKfXdqN|F!q7KaMO{p4j*PD>$XWRFzb$&iAA4v^3S#)%W(OUsF~0YG(WP5Rnm)Rh(v#'
    '6qD?St{PbQi`VcP>kob`ylVr74Z{X@y$jpe0S3m-A7e{9^U42$&xuFANoFRKl4f;Vy4_V|=81?C=kYry'
    'B2H|*#;4WwAeAn5sotrj1*}q8TvT`Qrg=5dYVUULh+OOTvMC2*n#xa3g-)MlUv}^pdj4~rOfJ$-6^u@I'
    'Trb*B>gRnF7AzQn3tf@Ds~Nz^Tb}{Q)kJyK`Wlxqp<6yxS4f|UOMmvq3amyu5G4-_Y#2~1f+#9Ti)&3k'
    '32n*hRkv<OjSdhhU{Y}{qHI%DTO7!0)jLxaI7Q!~(h5tVKg4<{SSKNoYlTx8;jlrxnoKm@mp7ncMN&Fh'
    'iKUt8Y&ujv8v>^Zc<R%g$5DF&?k-m+37PChL6*U6eUH|<>%w*-lqp90>#*{!0c>|`5f)ObR?f}_PiCw3'
    '1|t^{r9zsEj8rgWv;?~9HQA%1lIY-8vO<H$5Y?zhi=Xe$$Oz7fkiI6)Pir$3gV$1@Teo??LVd*@26#BD'
    'SONA`u>!2v#XBgLaK+EsI{0xcy`E@g@CWKXufZ>WsW!byJ%Z2GPaVpaSH=H}!MtEXzbM;|j(7c}*T5$0'
    'Z@(7fJMDZ2cH#A!o3JIxPCW;f;1#3L^<RwV@+Q|rT?w1y@^jFJ-f|%>I2|uAzQTV`jV2?2xfBnZ9ZE@;'
    'U6t<gPjuo%^)|cG7vgVYkMVL&c9rOUQ4m}$w<)$O*z`^}LMp8(kou!P8r0l9mST@qcL%h#8p2rQ?$66='
    'D!-C7m4`ppu<<9IY`?B4J=5jVR0Ahly+XV4%sIcH`m2p!+F%}JW<MYAnYp@r^(ecR@}g3}I%Br1G1p#>'
    'Ywti5{BC*OW%E(~2^%LA<`@z5l}I_&`yze+)FuWrXtFnfTz6@g=GuwU$3MvFV^uVJzZ75>s8?rKzRMhC'
    '8po`0mS1$&xwH+%sk#=7E?T@^s`sa`MY+wcWss>=5tN(^HVg8r=B4QOD!h-@3UB+R2fa|1TYJ#6d!n6p'
    '+cm#zOq%+S9}ViTym7o!|Etod+H0#@DH9%*JlAi^RhNvay!*0&DE`Bcvy6v(ykDcp!rZidx2vW8qPemC'
    '?cO*cHkhPmq*PwG;a;MMd6CaaEcVP8o)uf6%Lws3-=lWG4Q@DQZ1W&=4H~+UMU2Su9Xkw7;+f3k+xHUL'
    '4)y%V4MIC|c@z<ga~i}frj8eoFfu)8)QLhT4!qFzm}fKJb?v|nU5AB)u*06%@DJn8iF%kRuiHEu+^B0e'
    'MebXsRdWclAjF%_Bua9pxyK=3Q6CD@Vo$#K0luhQ>(rn&TW%ENDGYWjQWwX?KK{{<9u3SLOOyQu__a@V'
    '^~tSG*mT1p?&0`;K3gmYuc8F^m~4)HH_^fDGise&0oFTn2kE&NaefBt_Ugq}dBmW&?mM`-<Jl`)T9aFO'
    'AST3pJ3q(s(htSi6nW+vcbm&50MbCyw+n&>8&}fgY7dr_A#!)|hHUrYpD4~?m#eFE@pwum13Do|lATl4'
    '$L(>E4UgY%-SyjKC1cF+A~khV;Y3x(IT^?;`b~wbxOUvCV*ZW`#<i=tnO?SgvH99<-P^b=0XvK`+KGTX'
    'Rdo(*xZ>}{6|#CeRs%W>R(i``togR_MvJq`Xz4{y@oPi++ZRm>%*{V^p8uj@b5%xX6szCuxir+StFJq*'
    'xvqUZZ$MEe8>&<H1=}{9sw@j`DNrIdl653qUXMkK+2U#lptA&1`g%7i4Hqjb@72v>oA;Y8aqhMrS?xBT'
    '%4#r8`uit2kn!wxIzuy}iGASYU3&2ea`33u67JH3SX~Enb|&tL{bQ`Fax!>{AmYbAX(n<F7GA~UjN_Ad'
    'H7zvslT#|N;FbcJTSy|{xfEbxCPs+6oYhve!4jZNG8R(^kvgEK1n>70OZgF@?~?pd|M|nm56@2<G<L<Y'
    'MlQbcj`MjUjy?+o86@PM4`ud0g=$~OP0EYa9L>JiUM&tI<Hp5}o8>AHSgmtz@`oq&+EQE&J#Kst&=j{1'
    'K9VY1zEP(EiE%tgmrDgHy;@rABz|4`q|37E_Qlkq%*o$%Qdp^L<2szR<NIz<D4>FSp!2p<8_mW?=5(GV'
    'PoxK5o-U*)xUZ4J7kcGNjHW4(($tmbvVNVhA0H~z0>d0!acaN5R7wP90KSynYhGwqy-;2N#PGLPiE_{E'
    '$PqM5&&A;m6+Ln`hM*2_fCWngHcEFTKRYLb=?qXmO!xA`Z1JvP+*h7}JjILMmsi&>swPKSMz)IY+AXOz'
    'T}Un4)8g+P7Ft`&x60nU&NW=Kz}imWD~fwjSbUPdoT{san=Gt0meF%{1W8uq&|B2+SBXA=q_)QYLddMn'
    'm7uz)(-6RtG^lDLrL=d+R8&rLq2Ep-xPCsiE(UfLs(u8C{w9QH{R(_qq5E0<l5@sc-CB_tRu$d0nC@&1'
    'NcixbraI!c<LQyO_+E8yzuXbU752>*m2msrVoafoyQaPeHdM0PCmE#F^)8DGjmnADB92X)E)G98MDObM'
    'cY(<og|E^^56-E?47g7k>o`sLFrHwckU=t;;c+5dm%+613P(qhPg8ogm`!J^WPm8*v`NY^McZj7bE}Ff'
    'mD_HZ@FGqD@bHa@n9(ww$lzJB_$>rt4RJT)F<;0U67f$?V+dK3yVtVIM`?$TTh_X-k&tZuPgGlF84*kH'
    'c;8D=K6a7~F~V7^f*a|L0ExO1fP5fh-S=G8$fGueMmDlVPM^dnnI5IgKiN{~vBJl0)%P<OmyhcdCs0+U'
    '=}|r+;u}$JWkB%M_+Ttj11nLiC0<Q-tAJMDt#WiZQB^P{--@3$y;?<GcmTauQz8I~x{$O*2Z23#0+{fC'
    'F>-nS0<g~eF<J~fc_GiALxVaR`5+c=08yQ`?DTj4k&0h=p5uJM)p_yLrY!3zk)V<&iZ#tWeX|!@x%Z->'
    '9%a*|SGZfCnwm-PFo}h%Qa<6-EPIw=tBEcZSDO?14PNZ=XX3W1_|xe}I%9mknElm5{0r>Y={)*~KW^Px'
    ';{}1u9oIJEh!WeUei$)I96P3wWrVR4$C1rVld?F9B4Wpk8@3tS)TE)uW8d7qwI-&qZF;e5awm%1$P6Pt'
    'wj$GGu}`?^nJn~Z%w5g{8hNqlc`<j)C=4x=^T>6r!+yC@zr)70m_g$(j6D_@k?&Z<@}ejXT`WLjct*@j'
    '&vgUpaGMyO2?L2;$8cgE$F>{NxXBJ1%kc7hY=FHTYxO`(A%A%&l1$@YV4wk`PQ+2;q^D{<9uG<2I^1-q'
    '6%rO2B#0c&g21<3?s|^NOqa*hwJ8Zq5FaOG)b>1PyI4reAls_-#8Ke5fx&_>@Cb82E~v+0%CS(73GJCN'
    '3u4CssfcaQkG#-vXb_o(13jQYOj=dz5n5OIQT-tP`Fw(ZA3&%fZmc>R9GIuZLAxqAZ4ZL9dAh|0&y&WF'
    'iVM4P$HY#Btis^i>`OcVr@D}`C29pA@8q)g!ATo36D7>z=7N@ez+OySzXNYco%wn?UUqm}yst(qR<|a&'
    'YoOJr6&az2NJh?ssPn^Qm7jx_)LM#QyUrf`;%@jA=`cONgRK75zxW@1{a^k2U;Xv}@&EqqfB&n0{m=jI'
    'um8<|_?y4oGq-=|6rS9Y@$`Fz|E(*$oQLmKeLqb8`~UR6`1ODDZ>7TjzG*lf*!W(-e|xfbeK-4%E9&&U'
    'OWz}}|L(8<&tLtMfBUQd{h$8&zy7~|KmEC`oAJHI{}weq1Mj-VTske^YyO_Vd=bV=SO0f^`!9a=H~-7;'
    'oe7YqBEPo)zim*DIbw0Y&G*s#{#pL(fBirG>R<k^QtyBLFaOoA|JDEadmh=R$AP~$1iwW?kOu*JM!vTJ'
    'dxQU(@5dnEpZu4<Z%QvJlYOu7zdaGW(1Cu==bsK#lJCPEpAJ6FRs(uBn<f18dqc3lXyDiX{NMkF|M_oZ'
    'Dj*L7{=fhGpZ@Bf{hPo4@BZ1Z|J#4}_y71m`}KeRze#)X|NP_s<R7H5X!vAfVW?RFZBgaph9}G9Ar`q%'
    'KNT)LdcByjl`u5o+cj4o(U|y_MGY(RLeq%2WjS^byH-pB%MU`v{LuF(@n{^enA&D&QwLX^so~j-5ogD%'
    'kIF-ME%y-Mt?JjfFYM)vfwcvaWU^@#L2Npa?KrU;L^Sd(4*z)pu>)p1rr{X|rJT4vbzC<#qS$s>VEU0`'
    ';EKB)hDN7RtmarHK`*kyV9w`rJpk<YvwL#OFBY@;noe^k@JQe|q3cGT#bRRnHnoi~2x9|2b4-iI+;?f<'
    '!w(Vh{m_Xb!}lGNGm{%mgWVuu82XWC2E<~4YZ$&^;3Za8Z1KS6aS#P&<a2IDl(2}Hz&Y+mf#Y$XM4{)9'
    'whU;wSK^QuCbL2qAIu8$i-7o<v0)HDfQj;LA126j%)n$mH<=y!24@yyW*nP%=aA(!;J~i?9$IohN-+om'
    'n&(U_^%ZJA<)1#x7VHVfI#ZNy5^0mgK4Xz(#Xhm1`wn-VnE6fsB4gTC<io^4hq*yK4&q_C0W|`Pa@%L1'
    '&nD|fq-)0Wf-kUw^zsQ-IK3ga@?zmlL*a}P1G-Ft03^%`0*`x+V>8>JmLCx(FwFpdv|<}aW*deRxsDqL'
    'oH~AJvj*FqC?SLgjKIwCfP~BoLE33-f-z%eWSh1Lauo&4;f%N*szXeHVLraVz&Lbci@sLw;*QgI$-^al'
    'IMN4qMhF&13w}EW;g^L>=AXK37CH<)BQ{yUZ6^**A9UCbOhPS(F|gDY;dr-~Z4%StV6kIL8KZXOf%Pza'
    '$Ft(N$FYGVkEjymQMz|`grc?NBf`Y>$F(Cp<gQ8l*k-=x!aR{EhRHVY(m$|$VAMbqOw%$Q<}(<k!@;0)'
    'n{a9n5Dj>g^eN8U$M#O@>4+&sts9X8f@*;%yD>K{FiyS;cFX|3V@7VknL&66M#r;V_!cD7p*#S2rZ#vS'
    'aI*eyctmr)P_vWN4kqwogPYWfVlaJX7+4<l;|QF-<uV&I$qz$730~wda7<nl*kB?}4v4^Klv&Qc2Xi}_'
    'MPxFPmuKdbOjXnAs#}3WLhv$Rpuj$uVeGgbBWOFo#rS|JEDl_8sLebYTBZkp!UBh7L|~R(7X-Gy0p2UC'
    '3L*z)b+jb6qq#7wb+Z)_%i}f&j1Yn?@C_1swqyB(+AcN08Zekb%k~HXU+)@VQDHEkaDnL%N}QN%H>ges'
    'Hre8#PXg|O$VRs9;|-Yx14|S80bnW92n^5x%k=}|Sq}9Lk2${0t(a4P4~)Tm^Zdg|lye%%oyc{(@d<W3'
    'X4K_o$b-Q4oCstz5cVc?VA5;@*vIfWAMlUu1PsOj^Xd|A1o3v>@G!PbD-2zLRBjlDl>4#A(QjE1;7Zr='
    'fkWWzTmV^MuVZ+gxjrCgFxh741^w}6F0aWPk@sXt7WLc!gA_V}6>>01UI_5mAhrvgGa}mv+z38#Tx!ID'
    '57sMi!3+doz9N7|%!sNeqNbQ%1a=M3x4|Heuw5he7y}dMI#?zzwr$+RYe%t%0_#vO@QG`C40juw9B-ZM'
    'pBtE#8L49wjeL^@y#c>z$4*SqpAwgakx2o4dm&hJKeRZwQrBdm;dq2H9vG(OTTbAEYS>Y@Z{wE@3^&7%'
    ')Pcv^>2?X_q38J_m~apJ8wFkz`#ucDk1WFlp${Y52i;)cw?da$G>k1LG+Ymm7;7@!jDUYLZEAsvMI;6$'
    'g#m>*rvOeY3K5n~!N`~<7Hc#egTgd3KY+&_lfh8?<B9}WnDQAd)LL9OCjb$y8-Ni7y)a$8-WS3J2q0q)'
    '`U-Xppf`i*CN^}{;1Eq&fL{U@63YNXXu6%9Kt62O0mAFlO>c}1!1P)+g}DpBX@`;TIX>3V48R_POST|-'
    '3}BuEA3_5f2O-D(^R7kk#%0^|ynY2%kK;?>qh(>1a=E(=qiHlp4#b3<VyFXSFwr;1FgKp>av%STW3(**'
    'lWE}My}n@(KokVl*98v<+}e3;<)G&YdZCRO2@3;wmk<Y{9w&AYKR5s=EE|5ua-pUj*zgRCSOgFHQRs&('
    'ggAwA?pk33O>}u^#LV_wAO1!}30@A=GO!&0ZU#a#ZriR4DB1=AaH2R24KVq5owW-l%-fYExjULSF~W81'
    'hyiZ$0>JVS#PY5a7|;<PRLbBUz+~ouleFx}jeQsXf(XYC4GO_c<oTAlA6e~~XL7>WpoRgRbPZ0N$OIo2'
    '`ph>%lW-T}bTF-k=|*P2ICI0$qb`_Y5L}q~IA#q}HWd7*4dyxuQ6|6-LxczH@!XhD&|n$@;IJHsIPl)|'
    '2+TO3aPEQ#nZ9F15!sb7rK@aq)!T@3=o%o25a5qRL17ulqJznnIAj>yG2(?G1nN;pV{l291<sZLRB;@W'
    '8#@nYZT-!i4N~mG3<EZRFg&zEEMy#50Y$7#3?IZD{sjS!!9@TH2Y?0ff)m7qSPpU6)*8l@fw37)9%4v0'
    ')FIta1*yX{NWEtjfsG^A^C0+ieFFr@01V6ks&Wsnfsb971QXq!%L(8#7RQkVk3x4%W^rPL)b2<7YC4~f'
    'M{D{WfQ$7(Ivjv4oC3p4<`Ey@b7Tbpi5LNx8rv)eSM2}}i9&D<paFpIZD6;<dhE9hJ%=*%9O}?>n1-I!'
    '-Zu+90}sQHFeY9UaT`y(nIJwfgx1WbECwJ7rqeaO&<3pG`KI9jw#GZuA#7okbQ+5eriLQQ972>ilu_ox'
    'F|MTDr$u*bri6q9=7NAtvWW?Cp$9G)q8`)bp6A4XGE56XXYje;d=OAU6c#zeb1gqGV%{W_a54J>2-P5N'
    'WSEZU*uV<zGsE}&0KzP=eP9ng4~#Hz96toj^5A<2)gkf%@7jqa2qT9AMyl)Xx=yG|9V28AGZC<9VC-QO'
    'CO9#Oh(pgd4UkIem_A5o1aj&_NDaQ(<Ir<J<&GV;M#jt8Yyw(^h`2uVp$atD1qvaAZH8?b5m*Nr`xGz-'
    '_-2foeSnoVeCL8(S^>D85G)AHBDgaTLW&q*Oh|gN3u*{!(ux~nHp7L`J_<Qw;BbQoY+w)wgaN=Jqy!u$'
    '0AMq8xCP-z;BX^`AT)LfNGAm7#O-qcOW|r{(hX(+IuDQVNjwrOt)n}6y=vVkOyGR%SP*;wUh{$|i0m+?'
    '1~oxr0tWC7Vsb#QCgOYGegyc#bs+`~Y};S}C-*dp+wpS3$-88v3p}k$V51eoyb`!-8krCfSuh#C;l<1Y'
    'd*A?6vJBvV1ct!1AY638e8Ff8i%|=}X=HCV3LzkfkWyTdLR~UV#t9Fs2&_ZwfGYrm<%o3;(*w*1kq|M6'
    'M<9gv0ebP8=xjEb%s$MfYx%HPO-J%p%#l#8+I*?SKv6jL0fz-K!aN48K{V#Lj%8zVEH*<9U3X&_x@-`L'
    '(_#{af$N#J8`^#YW9WOX?K*^TE972eI1Xiw8&PoGF15jF0|zjo2k_y7eIYLOorn@AbVC9mx6^vux%r=p'
    'k{;W+5OL3sVjmy`pn8XZZ2*7@QUC#u?K2y1j<9^6L!@fi%tP-DF{%NfhzAqndJV3M0DKY#26aL7@esJ}'
    'co0?rX<X0@9QYeJO+5g_1R`_Kasdty%*Tm?(}2|vKfitO`uyth<<02k)#%C^y}EjGc{O+hoLR>ZWR@~a'
    'V+hhl>2u&X89ehYXIcL$nQb_;td{vJ>{Xde@*WJesya9tPjM@NSZHWQuhcnp_+F`LGZKkfy?M{cWJDHN'
    'P-4=)Behhza0rYS8Dn+X5ms;nBg%jl^rd~5)>7)$tsZ8pj!2iz$XTbe)f@%)=PLqcU6wl&CRz=&Nxvi}'
    'M{+|+ZYaqObL57S+;B&Eual7GtScx^{k(P})*mbLda&dGq|xi+&9I`YU6_YB6tK`enQQdWmEI}%^1D^^'
    '5bKl0U@DS_(zp-Dv*h&C{iLb<uBN7K;CdS$&zEUuns5hq#as*a{tWt%%)vf?1G=EE;c43ZXf;L)E%V;n'
    '-Vzu8K*I|_L+oY-G0qhSM3eB>*#uuq##qC$SvPPHnw};F;R2D!sP%ZF1(^aA({r17mYt+V0BPtG8ke02'
    't(omzXw3z;I1?etc*>KcGc_w52@UH?3Fq=csQtx^wU<RY9^FFoEsT!pG;(0P*o~W@1Wdv4(FcyD36o~8'
    'Z&*i>y_=Hv<6C9<#^iQ7O91<|801!wZbGVNyU}Yfg^va8uO#WG<Bu54e5D)6XY#spq163YHj)jasihMJ'
    'Cb@(0ssfwX&siL!m?bTYO=Z|E<h1sE#kOk+cH2;r$nts>sc`)A{h0BowBkuC)v0*j6u#n30k>J0+1x8s'
    'VwBcB*%a)o*|>@!LXI`K1k!YR%I`hlOMrw=XN&u!@$0(w))S6bJbZdV=8az6uvJJ*2BHnLsd!n}h);3v'
    '=5}Y>s1VqLW;*|@xYi~VXu5m~64F@5rK6_eo>Fl-U`*Obs`m5OTqd5HzJg1*ujZ-*deW}B^un9c{e)Xz'
    ')O>opN`xD{5?9W*YrIUO+uLfUE(Iv>`gXUbU%tNR_F^_&9lPCizO}-@&#m7PTgoq|OVIiYgu+eV$5p+@'
    '3qb#T(aKQad(R-GkyfhJtGSi8>3fp2fA8|+d;&1OU5BslW^*MHjo%URL0j&~2%~IhE@q&C<0)w>PxVx;'
    '`QrVU^5zsungo>Y5x2A_0IbUmp#y>ItcX84nHChTfCb}wjt2*j!s{%b)pQ=8E;yG$lLloS%)&I95oEw^'
    'D;d(S->C5a9Q;SJyuRan*_p=m>h>1Zem1=l*`wEF$|ub+1^__d249RdR%;7S#Kws86&ugaMWyF<G(@1S'
    'hxFC#o_En><%hq5V5Ge)W>eWg9IIBo7b0zZ{2CIStwT{Z5mt4lQI^f-lq$m2t|OJ#{}eF!luUM@a6=Zi'
    'yoG#KMZ1NS1Ba^LZ2p$gh7J;#zS+(%<;_uR-PJF?Ad7c=+18T26yX?PoW-Z-WZK#g=R&KiF})MB+%CGx'
    'BKY%XVw+!cD_&5QboehIE}A5*1@zf;yd0B>I3?avIP<-4tX??wS8+V1(CFoRyve>3CMuBVf&)N9+Px-2'
    'K9Cwf#T|fZ-X3W4mcMdpCqiAEp32m;g`#-|v<;P8b@NLQi{;$~$IBf%y!c#PogrLvC$rL(Lj{c6*_FfF'
    'U)|iiZXR4{rz<bZXkpDnvz6C7MHm$-tuaKE0(1ak(N-A}ut+=^-%i`HApd47W2UF<a(W9ry>FdjP#c_I'
    'EkIn8PEKg5z$X(IvC4z8t^5GC-`*IOlR7OD90gg|@4r~Jw1fp!yPwa%iCl4vOxqBVmz6&z?6zh8E`JW8'
    'tA+XLboODwp=sem+X-x%!DyppV#FV&oC$H0TpPFISK91TaSdj>*fY18zjcBri!#4jMXle?EpIfR;u}<@'
    '<<H1u!k1lgQ!_*;U#`ZCcW+m~x=wF?(>7qzQ`5n372fXPI&$x~cN)1dw+?)BKwb~K<ICMfoi5Oz0qFE5'
    ';)K>b%e^mvWUH~)EuUueUaKW|8L_upQpsamk%aD&5-QVZjj}88yCBmxelNSXF2Qk4jMj1)Ay+6ycjT+t'
    'YLPr0^9gIsjS87It6e#7b2Xc_PgtrxB;D}1N?NydmU+RJcTIH@r}9Pe9bKQ`;S{6hcA;)Y;RRXVHF~#6'
    'm7UFdzV-TbIt36o{@H4_B-g9^d$Rb{Y*D{vB~NYQ$0;SaWuO;omw2<FKDTw<d{Ll|rdpp+!ge#h=R)6-'
    'w)7C$-jU@KvLwwnW)xokvlVzpxvn>xJ|>H{B=iYJbsnjCaItP90;WB7CGspuR{UkUlV}G@XwV?$ql@tz'
    'DK)l=Ysg*WRZD!))<o1$Q^qEDU{tv18GxMDoYTv?uT{bF@q7MwvRa%k#HI9Ysil_eIc^@k=9BiSQZ&rC'
    '$~+<C`=5=McWgmEG|RHDr6nv(cM3(@(sd?lX%;L@XKIzOu|G;JA<9;w-+<d-yYWt0(${2_@Qb@yL)X2D'
    'lrqXc8&BEnLu+C=i@eLbyKuT})msxN*@4$&LGJmIFOn{l@`k;;F(?~%y*}TSP}O|4rX*k!t}Z-5Hcz{C'
    'N1SuV%)t}`BEnh|C|cWZ#>rS7>*!7hfdrzoPLs6_6t*O?!3R9gR~|l%7vvUGtBrOcZ)!z&hkej4`i(ud'
    'Q1BvqXeV!R_eVYljeBgQ9<6p3&wAXtE4dom)IZ4{nObKEdnTVZkv)=LXFT`Ogf^=?)80@EwLb7|aWY|R'
    '3$<$!eKb&tWP2i6j&A!PTWdplBwVy6JrlnC2y$`0TF$Ukeb2N@QFqVO>mu<Uo7faj_tDJe7`u-a>dbIo'
    's#LbYebHTKfP1H30ku1{P&&GjRt8OLhj2t-Ee>aIAYQCJ8mZL!h)|0EOvW+C-O7EoLB*MH#M+||S;D37'
    '27WG*Fnv<h%%{@#?S;0S*nG9$zM4oR>K)C5aU+vaOeT|v(0BW2B$3#9)RX9_lbd*MD_Sj=&;Xdtz6jgK'
    'Xo&|SU=(aj)X}#QVPw8+bSl2sM!Ak+O<dX8DAdsw(PV!V^|=bks{ZJ%&uRAFMj<-wjd}%^_C~pyU+kN7'
    'A>X(&@f?osgH{1R?@VxQVzCd(wTZ?)2^SKNeG#tW&YdaO0l{8~<`Lk|1lK{o{s>nvUu)9EVuc7?h5{K4'
    'Gh|d#v9K#?fr)yer|VlPG}JRyfrHZ0ll>4^;AA*QOZ!mcpka!GcB85w&k!L`*Z%Ha@G4KIaLm0`4UV-`'
    '+D06G6qYJbLcA6Lz#nluH`9Goy%i~|?!3^Ivzu>|s-yB$ZfjxsxI?!c3uS5-6EIyW?a-B0cG^(vzuIk>'
    ')nj&I6GPK2y><IU?gVh}aGY}sv0Zj%<mvRVHAC`TQ+wZGeCh;_#$8t&OyXk^T6Ls!Ez)M3rF)G#FOnB3'
    '&v&L$)}L2%nGWwtuU=5QE)M7Aq0@?Pd3fE|y^-2$QH4$IfZmOiD5)+A4eYXLT_>Jhi4-KW+e&j;H21J5'
    'S)R~6HX)qA9_W`G!yXn@^IFr#l4{9@?n<(7khMFp%BgF;-&qjudEK+TM|>Y`6wJ#$S0~rs)VM3<dN{U^'
    '7V;3SPx>Y8R0SvcY@yyo_PHQhMq_)T-9vhE-5O)j;`B(odO)KW;+t(zpNoHM5lx?s)LOef8>mN8y)Kg0'
    '0j%CuGiz{Hk8}%Ate>^f?RQG{MOz&-VI!g>bf0Zd^a6cSo~7o0bcgm|6_)Oyi3H|$G@VmX+H$d2&0D3a'
    'THimm6V)|QVej-aC*J2OTD8v89!Lvx&>P)eF+ufKvz*i32hFeNcn@V?l=Cincbc0$b1$ngYh7|L)N6fl'
    'FO=(@a6b!Fb>4UP1*QJnZiVP>KDYH{S{<lrr#IA&bwAXFOYMhd=1hmenRca`&xAjlCRpVhH!j=*C3$G+'
    'YW5-Nm?OS{o&milJRVQSEz7?a$mQy6$)mG7p0=wUXxBt)b(Fhh_*CbzJ*NF<v1+>9GFP-d3S2koy~Tnx'
    'g0K%9KbF&wtJS|VpsW?UzFd2i@BKLVJi9yXi747F#nxfQ);=tktTToSrh-Q6GX6C-qMl^uGkwMKRC1G5'
    'M?<l(;#KFIuR<-9<0K;xS|$6;lh&21>iG;u&GhxrLZRrQEZf*?4rkN!_Lw8ePjr9##Dxu=DGrS|vMAjl'
    'k@OJhr=;f#9`gm(^1#cA7F=$*Lpj~mO7|)`8To?P^tNNK)~xgu!Q@4xHO(4esl%aerAl(ucfKU|;`&&%'
    'nXvV?h(Z<5EB^D<SR_nV(avYLYkJqs$k+954-2Nnndu*C*70L^sJU_K`m)0tg||mTzfPe02F$X!1(taR'
    ';K_G&x{a{2zA9Pll<RDmH_monmb7LTdd1Iualal-D@G3mqjv$+Ic}tRQ_bpbW_A<Bo$zlx#oprBTJn7_'
    '%c=w!mbY9?U#*r981}R%CGRTN3nQI%Zxb{6N)JBEE!y-&vmcI@h<3t2+IpQQ306W~a)!C#WXIZS$|;>M'
    'LD-{}IAOC}0k|wTA!;`#n6gQF%CqHq*+a@M*T3DMRcS`{hpuwt-(Mq|C;JH6*Kn-ou(1LkNKS5gT!+@='
    '7ebas@3k=Picd=1>1_eCDn)&hE^1Xzm?SrQ{VaKC!gAh*dfvJc&orrWSAx0@ZGXxtT;6=am;EI8YgBgK'
    'nEH;6z%9Zk=g@KfjB#;W-abvjxWKr+GV;ag=<~pCZ@j6Y-IJacS=w{(aIxT|d+boX34^@nto5mknlfUu'
    '+5Cdc2^B}<``wGafeSrECsMD)O$|M3^oD-#L!&87!HB9k=(yReT05XLtvjpR1_|8tpe^)usK>wC&VV)Y'
    'eTTK$WlDG-9wvWR%x@;GBt=FH3;q#hP`gUZo;qJEkhyv2Z?jx_MPV;uD7rY5JndsW_TuUVRw%e4)7uV('
    'u8VbpbELW^pY-hx`Bjn~9f<6e99zH6BfSSnUg>d7?>JlS=g`Xf)_Qg-#R=GHEpxMlSlo|Lle_MVuIO)0'
    '`1;5+ui<uIN$ff~-_<@W?uW?H9XG_4Hfwyj;NrT*4o8Qpy7+PiNM*KI$Yj-?H!YNUz7HXu!g#>f=>g$V'
    'cXnEP=hf{3vv$g77X<}-J<NLDQyd{SyS^avIk3F_=D~s^x#A2<dWc{IFYVf8B_rRh-GsN?tNjEbh5q)s'
    'L{gogeW=7D<<cmYlh?y8j~6^iNZ+Nj%JbRh`edHhJ8Emj(4k~#Plo+wL8h{N={3c=qPr=_c?><HWWk?s'
    'I!^jcpXaVT#9PyzlTX0ieL9cIU?4E)4lCCAr}6~!vg56eRr^qLqFIEe=md{2+(Y2s!_F}=h*5;27=3_Y'
    'j3#0njY$_3DDCP{ceM`<N@e8o{g~nAwx*Y`u2ILVUf?*nAA`A@?6B+V_1$ba+iA;H{<hGp&RVjXER$Wl'
    'alT{S3{I(IG7GSW^nYc3_v7vh4B6e?Z<Nlx6<*g8+jDL+&zpTMU}koVD^87KROGIpWrN=Ii7)c3*%4o4'
    '=23H?5A&#si9R2{hZv@Pji>U(nBS1a7_V;Wn4zj8^=z8(Mfa^u`H2?!C5+FO`@4Wdb8@d4tV`UK*1w@!'
    '!}tEoU5Q6M*`X41_Hva#jdb@~Xg(9o-GZkEWxOZA{SgKB_W=R%&hOC-nGYnhTfciKKp;3Hs)Nh)qhQYN'
    'XA#OGIKJ;US6ES>9nHS3M2fRE#98Yh4J1Si-P5c0Sl_h6k*+eK*I7B!t{YHMi?28y%?F$Uevb8T->T#8'
    'C2>>fd5?Cd(&fI+E2%>`s0YHE^g%a&V>)iw+J$hPP0*X)7lPR%Cb`|mjRC-r(VgUow2$5P*H<Yo1xrM9'
    '4FBL(_#L<Iuh+azdui2<2Rt|k9aLvMb_kDkiT+*cp<d&jzlkbspm#`j+csMn-bH$HZf8<$?_JEyQH9hV'
    ';An0x_7f2o?`!XTNVaCO_q^UzC!#$^#0B2;R>rH!sUB@Bmoh0(oD@n?AiU3A!dOnK$4hX;*5JwL78x>H'
    'Dvopqh_(9NXD*;16rGH<!W!rA$&xID2k3a_ArDw@_{ZfgRj^YcDdKHka#~}`Y;<k2v{ed!3T&QsxSzK`'
    'MAnMxT%rK)J4pG{^}^t_eBKFa%kk|ghmgtCuGM#IM%^1`mn_(m8z}N&AB0Q#wg;R|1cQ1<!RS}I-$7T}'
    '`y(f@x6}W18ry4rpfGd0Z>G&fT%BA>kpQ{>W`}HmDzXRoYOxwG(U4q_#o`l2uH8&kxpVsfhUGSTRHLHQ'
    'FM;^3QD3Jri#6%~>s5p+LGaVFd%Wssr?Ng3nwVGHZI{BDZtgQMSkvS_6R}C!)@Upm>npigoQkec69w*k'
    '60Po^-IH6jUB5L@tT^;C#s2nAl_~dXwguhR6!X?mbWf}YinWT}nV6&1FAp=qy<F*7i!a2^5rVCa=GdHE'
    'L)g_mmb$-_sg&mdW{YRj_hZQcJkvRz?`ABkRJ&%%YOd;7*W-QK&9#m0!*b44V|bO9YE7IuhURv*ottN7'
    '7bB`l1nbkrylc(QES2zNwIDm!52<u(mkmR@M?0CdYL9je9}8XU%}Q4KxyMwZ?){!k@mLNiEfB!_C@rUn'
    'PhlJ*rl(;?8((35pE)|s?LBZ<Fd@B(U6$)_cSbX31g^&PPU4c?lWz6&c2eXTa=j^EmG+)hV*w40<kH|c'
    '9nOwITph$tSmjEboDsn1ON=(#6|Jc|LQ$r-PY6+MZ9fMd#Eqa5ZQd#_bx^$wW2*GfZkksi*Hd87-(J;q'
    'q<@3K!9oqDxA35AX0N=7M(D6Qxc1Gi8)@>yc9McBwcezlLVC|qz_2}KedlU0eQce`4`CN6z?32MKOWyI'
    '<k0a*-8ynR$w8G`e>LgLr1vZbm_5a^$GNfWC<c`g>>>t;9doIt9kx-YlrFOEl;V`y&h!?u`K~m&<|@k3'
    'q9E3FiMK#xhgIGJof|CIu-utU`}N}5kaaKl(GuZ4!=~M{qvH0R$14Vtu;ZeUMwN>2&t{8v$(+!=?kXy`'
    ')%V876vS$C_(8YS+eXFI(BecuoQg9sqBs?}UuWm+TA4%FbT;p8<8__z^bk)8pm4>PU}3u65I<I{$>OZB'
    '#GL9D*h%-}F?Ce?i1%{i-NQA{b)D|-WJzTNecmEl)Ac>UopQ7);qOAqV1G(33WP~eEz(jw#aDHV+7(ra'
    'OB323C(BWJ&Bc`tI}od!jzu#4mE6wvs#kBHBiy4p)bn#+8Php7(ch)4n)X}{qK7u>PJI^SWA|Fw`j8mv'
    'msG7CcBWQ&ax0EV>JwL#Ecq>3hR$1c>(1C-D5`q%b&pKhm9jW*C3!HEJQ!*o3{xI7J!Q3=%_fqqnz`fU'
    'gp+qkPr++?UFDUySD{BK5NBW(NE&7yX}2rmfUgh5>qGT=Q<kmoQYMO`Z~S%)#xdpJ+s_ZKtkK1*mp51E'
    '7dNBpug)#k8$22uI;IiW)G^H<4k9-&qtG(~C#Jq*SRSz*mz$m$1*Ye^o@4mL3c}cPV~aU4p}rR#KDao)'
    'x%~3g)nAORFV0`Syu2Dc{)?N-YoL8}cyMs=Dvl@PDIXMOba1;O3zmE_Sl;o$f|JQ0UQH%Lb*N~NP%@qJ'
    '#bB|TCWG;GaPjOED1AFUd@wkS7qk1poGkAq<7gmv0u5fnuku^<!GaflMI=`E;Ep8te&Mqfm~Lcbt{EvX'
    'MP{Eiu>!hdazJB%huJgwI;v6h2}sG-@_%2wdUXTL!!aF=Mq+E}==c;6)NJyeA0400$pWxc^2T~ApMP=w'
    '?B(di<<*y$FugBcJj0g{9PZmrXa*j$Ovedq*I{-PJJgFD5_yEh)N*5L#s?J|SC<#BuAboZA=geZLQjs4'
    'M5i7O@Y#dB*2d$Hc(o{)1f{vddorF50h!(MAz88Ua%h1Z4NYTcxB?L$;8+M7E&0dg(ed${gLo{QOL9;h'
    '&(miwpFDf{C3fb!_~5(6n{N;C>ca8zTaf27@jFUF_S<4L;n{B}clg`EAfACRp(IrY`dPO6?8WO>S2sBh'
    'ayz89=Mx(gAU54NbY0swOd1j9ddy&^;fEd#48_5VSKnM-odem|SFf(qo}+>x%Oc8r*NK>8GWajD8DW-1'
    '9NV)@ld>S>-0>sN_0NQLn2U>zhx(Mp!`xZnA@Xi`y8zS+CgbdugPOpjWIi6g<DbraS9j-`X<L=P9MI79'
    'Z9j6T>jZ&Gd?&Oh@vVs2X6yy<t8F;UWTxy#^79o|P=L0V!wJSXFt2P(>Ke99)$r42&o4($o_%?FooA-!'
    '8kQXe4h%O4-6-~`9eXU`)N=yE;Vg<N7#fGw5P5xm^A(biQU?~nv;%c>yVx5oSBSMzNfE13$)x&7eu>8P'
    '$n>2PV9IKN8in_`DZF_ApZ<(r+>s?fI!pkS3XL3`WJCrB8Tfl9e{B9LCsu3+Mi6ltM-l3z7dRBu)37)T'
    '2(x3b!Ynj70ZD<unvuf{3ZfT;2H}Jp9OuX#S&j`I7m5GbD*1;$9(Xo@o~!GNM-f@#+VX0SrgfCu5%6F*'
    'vIYTSx|4uVivQ&H)7Oo?A6f($!OhT!7y%nd4H&V5=7R*L#epv@v^dylLgD9tS%&G+&~d2EZ03XxcT#2?'
    'SLHcx8M8LQMppF?jA2=yK3DYjyT$Co8v{&bju_g^*$1?mHJT)!`<!=N7q7m4{puxj?ayz%zPeo7MG|q>'
    'b^{}HO`r0}wtUM1LmS3{OHC(oV>b#SkNIa9m0rwN^V#%jHAN0TmCi;AUUdj)?#lxZ&;v$r<hmz=z&sh4'
    'rg2=;clkG+kR%y=sa#ogz2it@gj4+Wf+YO-ENhSPcp$-{NJnrs8sAO<i-M%cqk`bLM$v3FWk(60#Q9h8'
    '59TJvJOOsS!Cs$YXgfbTE)GNa;e%7{Z)Fojr+S*qC-5~&>Cthqk=&ngJSen7rfe{sE#-$3^(lNy7E53_'
    'fRTeA92~zblEZPF0?+tjc?r&9ax~%7BQ=oYlR;=5H+Vkb%k-T_FR6!5De!W6RPT9#klB(>)n(QYnebae'
    'Kj9>aT(X!Q`4dc!o<d-){0#Yt(^lWdlR;gZVj|@0*svn8PPwv&)q{2Lsq#>rDQPmba`eC!r#wjoKFG(;'
    's-lN-Bq=AW2z5xz!KX*!@8h$2S<Ut2ir?~&@|}~xB0l)b?+Uo>^VyrfJp18KzWw&ix8J^f`=g49cw-L3'
    'w{Hyi>xX}Mutqbao}P#h1KI#Uc_P*CksO~?uA_sqbp&$VeK}h`n;wBxMq&s`f!b$ns7|!Fw4n3tq4DkE'
    ';D-ap05VO8)>tP5=pzBpNBkq@q6lX)iU5Vf?--Xz&@dAAV+5izVl%7>JQAVJXv#n6;tyNQ*mu9XX6$nV'
    'S+7x~I>FDqd$U;ay4Oy}35a{a%x!5O!j}W#jK(npk2pgIZ#M=pCu{j5|9p1<EakZPtEX4uCrt6Z=TkDJ'
    '9HG<{+Ir86kHF_5hJogzF=HHrXQg+Oiv)=5xGa_gZIH>q=NjXnphUIrjm!kf`Xj_B2l&&$Td9-s6a4Am'
    'Z3F8ec`M$LT8?xo;q!4DI;ea|<)CD0))@z7NwfmwMzmh^-{eL)7!J(04Lhik9H(*`kAy<-DON>-xcl^u'
    'e`MoZ<Sj_GXd$Qfdg|Y<W5z0m$R7rRQ8~O@h{MJ2xkz06p2p%0jh$?vwT(P54up9e{Ad6c8vbrZXEmLG'
    'N#ks!=I5S#JX)kY-=KJCeinKP2ag^VW)zw?o7?t^Af~)q&)Y)3ySbDG&CZs0d@;mUE3>(-#av5I$t2-N'
    'Wcuky`Olmw_I%f8F+@PN5qN|KMnnTAWU(9gm?xlwkiarn49>O|X&tY3b0TpjC48h)Od>ybKS!g5`90<D'
    'ibhXl<!U|Kf_wnc*q+i$vt{M5OR2bgNNC+``3RpqK4o0$WwAv~x0sBBe$?34>FPe>ixc3ySVuV-fE9w@'
    '#Gs_LRNPn-&^0o{!syDD*4bO7LD0#f5tDE2$$sUAw?_2&$2l;DGn~O9T|HZpRmC|fG}Ex#deYvgnRxpK'
    'W&&J<?!g*5KNvg)DHREEczJ~>aVfQuqsy7fmCMj_@Tb?WUcwW6!cGL-`KuMoECIu{q<G=;;60hF_<)1z'
    'eE{X<rwu!w6SITw(0=Bz)#*b1aBy;fw(a2a0kHl%1lH-`J~vay9Pq?cKY&XK00p{~zBw78{Q;E)vy+Tw'
    '3yDYn<BgoZ+Z<0;QljeXPoGa}qq*bVnyZ-Vn!K)XvB#e!JZ#VhY)i}Zni#akrfiAY6~UTFeM>N>UfdYY'
    'VULCL6B4v8j@tsg2aV#k21MjwKA*`<xagNicke(-^(F7%I}_2p7*D02I7VCF6Qv&^rF9;s>ZZha9*Mu#'
    'y;KW_#2bwvP1U5FE@$@>uqgcF7_)^N&<WZ(2)&YA3_cns3XovTjSrwr!cQ~%Sf4rEAm#Omr?o;~<IE)K'
    '#w%D`DauYBv|H%fO7$okHJE~<N;n2B`tCtF?#>*?&hBB?tWPi5o*H5p6A8$$NKOVM!fkj1!Bt!o(xXP&'
    '#bw#Gf=kDku`G*j(TNK+`u%X@n^dow+wGutO;>DN>D~H;-98k}HV?KYxVB`^v9l?{0qp#yhM8|`;Kgpv'
    'dS^$Sb7g|h(nsI3jx@S?=e7RSHoCrO)%xB}ez%>^t&@+<7_qoQaPXIy?I*+d?RPk%-B$<n9)VK+u3|Wg'
    'F>e71z1?V|9~1hHg8{-C@r&ecJReZ8_$;i_J;c0f<J5v<{(dlDKv4Jd6<$FPP#Cl>-@(n^0QW;i(AwZ0'
    'Lq<i9tY8|ZOH4L%){frg$N3nL$pDjN{Qc}5{7B}QRtAtHdM_^cUaaOAeXqokpJX69zu*`*0s<IgKh(~t'
    'J9uS+z+B~>YdTWrmc%;oNNq>T$Cu(36alMpnVU2rG@DL7{oclu2X(9K2l>cy&8p+(z;4Y;zhkl8dY9XD'
    'gF+*!%I$96%g~6D9AT4%hCWsxd&Q$lE%P{g8$<FMw0XfT)-UFD1El-O<>Rlv+>S)_>r&*tJv=~rGV~9='
    'Jp{S4<=Y4Krtk1>xtu3w4<AbF11?&O1j0XpWsx7s#PZ>Z9zPH}SWoPpyyN2bJlx)NHuz3_Klt3_bvZ+a'
    'Utc}H=Ax2a`KA2?vA9ha>+^j|WR+4hrXqNqkEhc$u_~U$!@H=;G1uKHdZ@ok6z7KHS#tVGbY`tI{M9T1'
    'Qu<A;@i<Vr;7b4tFn+WjZ_KyZm*Ag<xRqxpHnC>U7@K|coG(<RK=F>u&*NU)Gu*?>BpKb6%}z7sOL{kC'
    ';H2)(27t?O9LL)lPhdiZ6tB*lVo@JxHpV$@^0uDbY@aR>$>~4g26g<{iGzsS9=AfusA*W#^|=?&$fZ$i'
    '@PL{1jiBKd%M3Ex47UHx(ZQF`Zk}JB|MYtF&E?hgvsW)MBnVC|=hQCj?pyOG_x|O}^T*HSs?_Dnn`@*a'
    '$J>d_*RP+yI)5@czq)z$^!(x`NA2xq&m?Uh4D<8Z;M>FR#85wjo!G*4wH}EgGM=vZ5bOh>pxL7EUR|1e'
    'HJPNhYa~lP2i;mFT<p*w3#nf*8Beet5(MGD87;$p)T$Z&84jl8o}Ue_!5oNv{1UoyHk_@Ng9uC-y;I9('
    'pK|J0+XDWxvz{h*d@?y3L?pR`=aJ-Q<w*E)FyyP*U_PF6<ZYw35HBD~8@?ZCr5gPBA>;2KPJsuFNZ_yr'
    '-+p`Whes)e_o(Kx=`nl??D+OjYK{=Mt@OS<Ov%6xgCX9si>rsjA=vVzxDV-(1;0&Zx5L?dnLIie4h!cl'
    'hWCT7F3+EU@2hQ1jTk}k0nWwgU(Lo-5#SVHaW;nv^di>Wie)!yl8owf`xw{_hh#GOCG>y10HY|+M8L1p'
    'nLK-t{1W1Z$uB?L^5rkT{Z{@z`QZ}q!ohKM-zW5MG(sUBjc^VBU?ew5jSg~Zm2UmSuY`UaKX`rhN~~hw'
    'v6{<2zZpGy`TFY{dGbZzo5?Er5~CWizXr=(<W3(Ij!^5{4$AdVYHDnv_o;nsa|sJszgi_)WlaM>$S<JP'
    'V)+eud=q<q0pZ~cn5phQ6350%wKcMbvticU8B@3_0Q-J1n=JsKlj0!6Q<W}W--!%E`qZDTU=qghr_+xp'
    '&v-)dp*p5`I*&f$kK(cH?5IAS9Zh)gz-Zm6&HTWB%0Gd@V^28l*`?+4_nXdFKY?I&aYJrv4|~?u)z&xn'
    ';9xO8&($-jf4%ku7<7I_Rqsa(;%mB;r;_exxKE2I^rFtHHKz1VGGfFOC)&QB!%f>?P50U3mWah@Np6d0'
    'O?NvF-nNc^qx-dp^vIZaXwT}6*K}>Fm##!+gx)Tey@(cLcFSA8izT+XKI~i5X?>hBuN<$_IbA28`L{Cj'
    '09Jsl=(53kWo4?n>T%sY2Q{VNcQ}S$y-1*Jq`tbjdENA-S0AQA&9VIW`U}bAIZ@Q3q1L0J(!*h@hw{*9'
    '-J^Mx%RiOglqj@o2--E2+Ess1qI^k-s9cg$l3qUStIqNY<X5j6=@Bg@UFwB3HmjmR8_$0=dZ>6vtoXbv'
    'Gfzh{=~^TwPdY-}C5kC)b&D4~xzj*>`wLRXHasrvrg}#oxKBP!mv<aHhVOw>Z%m<aH*4N%*4K?^wX2Wo'
    'U3O(Y1ByDog7{8?r|e+zcbyE$+2GLkEypsr&8g|Qz60^C=`mu35p_AYA~W#0X+#u{BAVQELhgo+@0f;f'
    '+wg@!cJ<NN1=}>45!%EHW6KIn!wKRrHUiT$cx*bBOIZ*&5XYN-V3H`Z0&3VkH6zy`mgn1TOdB-k*=A_j'
    'PDFg4IyQ+p4cx#Bt%!zkY#274$MbzBasy7>z%{&(_>s+MXi)CC4s8M<p&7>y4U+^;6w@G%i4}Vxqr@`<'
    '5;=@}Jo1U@nz2u*WyD~km_s8!gwaNnMM3Cv^eNDC<T$R$Z4z0&V_C851(9u1({y5s8Z@T1VcRaX9Mg2E'
    '?Zu|)M`rB7?1z?bx}nkDKtZG239Xn=#yB&$?|G){TP6z)1JB5tmTw0UaYBQ;hD}K1nZ)PJbwc7r7IC70'
    '?Cyi16QM;+lYq=R)TWMO#jzj7zQ;U^aEAxBZE}P8%*8|b%yn64hCC#WX&Yu>FzWP(7;zp<4tiyBLOqLm'
    '#Pf|X@Sv&Kj5%=HX22xslYj&kr`%;RV=(U?;YPq6o0<*16|@xF7Bfu4;yiLeKO*XdUS!&#9fZW?9_XuM'
    'c$OXeZs>=;9mmj|;{_fju%J6ed-DyAx~^wi95mOmUC#<4*LC~=<`cBih0)kv7=ggK4ub|A&~Hv{8&A4|'
    'N_foY?yhbhISd9W455L@HyoGYX;2<g?nl(%Fs%_-u9#Z3O}!|jFvX4?#LO{W=F%{X0>7hEfR-(w7_h*P'
    'L+W@gV;1))k0WZEzU_dG1fylzB=EqVkdS+!ON=lEIkyQg#_-H;7y}wMnQa*aq{y>Dc|&4ZR$#is^<d)7'
    'h@y4zd>1T<;W7?gBbEWPVUW<ZLf^H+9y}@ZB498U4%{^y;!|#cC|MDBj?nc;Y=bn|P7uX*9Dte;ut2sE'
    'bHj-u!{_in)r&4DAKEq?heNwyDjD-VV08#Q5B(VAnMN=Tpx;KsKrSeU_Ixiepid!867hqWFw!`_$F_XK'
    'b8XNb-wY#@G24#<iYr>CNe$xBn1cX#9*<+wj)~zh@D)MidA3797=w7{z)^^r#hDdb4D7YZV1!}lfQtmb'
    'VS=FrG4#U_jJiX-fD#@NH>3vG5#Kce8UR0<W=5bX+jBki1TiDjw}|V<)Np|)iK%ab?}`|WOy3HaPl26='
    '8G_LJ%!t9{I&l>7T_OimX9AWwv?E3wf``EkFM#RuJj)GX&@PNH3Jos?&86T+Y2d&&ei%3gv%!(uv@K9Z'
    'K{g^UjzVa_<gpuq%lAA&z>=cl0{a<(SqA6fgC-N3!yJRiahJl70egT(HB7}oOC+>B05BE_13bGP1B!|w'
    'kQXbm3>!EO-H2d-u}f$eMc}k8TtN+8uo|G*Hffqc!loFQe$e_DCd~lXM!^xY$e{sDE`eqY%OnoBD2Qrk'
    'fhPOV58I4`7=Q>NwzW&TLO@E}gjowhX1IZkdmud$`Cxy*t%2sa9IOKMf`C}yhQKBR-XV_7z->g}u_Mwn'
    'afKsA#WyKfTX3&v?tBmm4hq2nz%;HK2R^uY@Cp$Hr{H@AU@+<#jsX%K#;&m~tidL{z+{#MI4%MSv3)?C'
    '0iX;Jy_k5mZGawxe&qNDSR!r!>Y*ly0kFot4|1e@YxgV+LMt%mRA`##0r2I_f!PF6v8~7j&5te9#uX^&'
    'q6Y>S>|)^JvnD8q%Y5JO7L?;edIl2aF-&3X#J-I?SBYync8rP&bI3qSV-6D#f;s?nHay!mu|fk6IQMo;'
    '8=~z492bN55}QGIVu8g2*aS`n;4I8XXnFuQ&=3R$06h?5!**gy;@EK__?fsZqH?r9fKdVvoG<{WU{U5U'
    'D*y=txpE9JyMcjSF)U^gKeiljwXO$-%H@FBK`vs_E+dQ(3UG25a+~?4$L$a-wiSV=w84D>We+_YL_5q5'
    'Tob0*fw^}ah`Xqb&fer!+bCK@KOjC3Us)!GCScrb_|?I=v~9;H3?>}>8NhWPJPfE1C@Wxz$U`p!D928{'
    '$@+9X0#XPdLCwH`G8d366KcvxXrrAa-1NY^fa!JI$bfhU(TofKc|O<$*9LsrEyaaV7a$A^{D%Xs$!37S'
    'ARI7E0ND@;82|}A8=SKVUxD(%$O1q~E(Dw=s4k@t47Ls4(LlH{M5qp^o^QkeIUU0Vb7zAgGYN$-2!dn^'
    'B18-tFosbGNU;TRG_b><Af`KIE}?x2A#msb@B*!~UEA=0uYd}HK1WXp;gxSOu<gKaz@H|i%#R|BkU|m@'
    '5coFvGX$XE?Q!w|0Ri9y1!WLrx(s4;h-(0W7@!+|1ThSOFqXIu0O5$E!~wIt*x=n)1JGT^9(RI(MnKzO'
    '9t2hpIGY4ig<63@ph*@|D?-E#isS)8G<~qg%&}eK8#eEh&k@K305o%4$2N!=0wVA!a+Na63r!H+&<Ech'
    'LkQv;J~V}4zX=wE073vMRLErex(>D!F@QB3jJyeg0x`T3f>Q=>9R~&s9fs(dVB#q{1T%E;ac~dZg-D2-'
    'k>~HSUVy^H0l6YT0gq>Mg9niVstcCDj=9GXQG!j34FgP&?{Kihu>+ws%!6kD29Dfz*({N)@XY{FhzT|?'
    '0&Y2$1D3*fKvN7<CkxCWs4oNcf~Xz*i{qF9I04IZIfU1w^)dybdWg~-5L4U7NW$a*mLN2WTo6=00Ql^?'
    '5W2X5XOh6iOcOX3FwG%n;NJ*9@Ma5=s4HN~LK|K&JtJV~K0xEabaM+}7R*-cM=n?@PHccFz-|}#07e)B'
    '2opd=Y#e^ZMbn$hi<`?Qqt}oBe025dXCm1LPy~+-$TOM3;L_MOz1TGYVnr^vun5K%nI4OMG`9c%F<1eX'
    'f$n%QnA(^_d>n!sz?^|AJqegozQ_^n1zp{(rtcD<_D1&_DSx|^|2y!_a|l#i1XTt&AP0ii%S+!4)!ys+'
    's*dT~-ud}c=fVpvor}j{0x#W5kR`{tX!f>q?)m_dtiXTjonJn6%?ogQw$ZR{KQu4B$4?FG;)!irj}0pf'
    '&uyn^&;7uDdf@`cyh|`3q5t%W8(xG@+-7eFm(Xt$V(iCO_~h{u-#!n{A-1>0+r`3|a#DBY`A#g~iR0PJ'
    '*17Z4zXV+J6oSI=!ttM80>1;h(aRlXYp2O-I9HzwlU3CaSsMX&kjU~{1(yk-k;EehUu+c`Rj%S@!MPy!'
    '$G3~wYX0M`Z+_nPz<SQ6mCQEwYn%|#A+T;w!BAiEm@hciS7|V&2}zbeoz6Z?@y(l0b2&6QQkq^AEhueP'
    'ik;cqnakUle7ITkH}ZG~7I)zAW<n{0JBNe6J?=YCpZZUX$L<sNvEf|WPtVUUL;s0;-kST5SK|poPBs`z'
    'EN4o*x_0_^9a%Ts{mshNRuh@)#<kqUB>4RLjwFq&NQ6(Hi{*tEBzcFlEI?sSV0(_=;C-B_<RGn;y2Txs'
    ';pIi>KE>rW0D1QL<EQ7C+iVC~AVj|mAf|F3KYr?603p}8^uwlr=iD?eL6EH{kHaUvZ(Tlq5<CqdVr~E%'
    'x^j6(Cb!^m4rQ#<*Cy_|!~E<tJq>5)^V@PLkkusL8T%J@W{QI6PoKYfbtP(%VhQO8f*Xwej}Gn7u!!eG'
    '5Neay_H7TsGe9>{WJg|P5(|?&frV@9mPz5M*rHfSo5v=EPEpJbPmV=QAcO0kNER7;XquE-+%hP)t$@)8'
    'NYFT<k%MdN5Z0NY0k}7yzR8@}p+1C>CMGE&g87WdI}}~STu7fo)`9n4#ymLWA|DcA`pL6lh{QH<q0=@f'
    'g<w5|$SibXh&RKSnWhmq1`O4LI2c!HEyK0dpk*RN^wF_=!^gwY)QV$bP^87F=Y<3)13}w~iRF2W`-Ug7'
    'l-yztb8*GU@VEnk`SIrm4{)PC-l)zOi8@$_1(`$%wUfbwM0|35CdQ(UI3B6;L0Gj(7YHlHrEgCLhhI<M'
    'q4U5k*7FHpa((`CFrLm=OE6kkiboI^wB>mVQDy0YK8S%~DQ>@BaM3p=3e>4!^{wg?{t<0s86@~d_2lqv'
    'T3G3efpkad1IjyPPo#wO07Yli`6)q8jMIcsy})IZ>FvV>pL0A|IuQJlV;UrLGOY|OKR8KO+>b!Hq<o@!'
    'ho=DQm@Hn&*j!91AfGQZf9H6N2J1It>8u%^KSc%RtkNU7a3MSMKuy2gZk}!!QO%weriRYupH3O)bNoR)'
    'k<OJo6`0nf!b6i^Ux{5%*RQ_5y12x&$o1)X$?ub++|(5~{^qb$7+X3qn5kPX3nmIi=tgovHsv2wwJT(k'
    '9I<#lZD=;ZLRo5KR<28L@UgcKa)(y&$#F7xIh*pc0ppXw=Dw8(V125yMz2&j3Jn+eiCjE?@&ug8_1CXO'
    'QCO^#bY111ez?BbLV0l^GfIjj+vL}EJX=5b63HA7GFedNF)#ld+?Co2*F^?OO%+99i|LW3Qfa45$Zr}i'
    'Oup=`78A*JHC+v4Vm({7iAL?4AR+7fld0xbVj4Q2^t{cqKz}SzN(*`y=QroiUwv7or$5foD;YCoaHZ)G'
    '6R2M;-r|xsYw=?C3l4J$zJ73JWd#KDChl;9VbfQh6)fAy03AK_>0|(rtf(ZD7PD(%^k#aO1`4{On8~%!'
    '%17BlZ$$mc!?#}yq_x!!;X$G3A-NYvj_}bpXG8PtS@yL2;SD~LNtJlvk$fH=|6(AIK^7a9pB)zLoPG|_'
    'DIRU25U&*w%Tip4T59%-fjHz;q%J->6yMF}<*#P*T(j$CLbmoskUGP+-bw+<(b9f9r{SXZJh&UI87kHM'
    '@VI6Wd9qcro3$XO1E57wWeWsVCBsL9V)yerI+n-7(uowahm?f<sO5#G+H}0B7UaNGvRp{RSmZ!)ro~Nv'
    '7@4CHtCgqBQsuvH%r#j#K@@QmnuRQoDz@J6V;yN}dBmG<#l+)>;>F`l;}<Us*bI-b9hLx>qJ|NYJkFW_'
    'R1GVya-y}*&FoeVgQS*9cP^{S(ZyPcr7*y9W8AJRFt%jad_2WtiVJ><wIIl3a<qsJj(&1~{FhIjU5lb<'
    'e=+*%^7-q_E38lP<>l4ut7k9qs+z;2v|^0sd_F$>!-Eq<*+sO8<-xH933NrR4*d0v@ir~wir<_+dGYKT'
    'k3i?!C}kzo>M0s-JWGzV!xO;(pg33pcNAz&_jwJ9yC@ZZrnAL89&-~FPO<o^#?8^ewh?2QPt|?+DLObj'
    '*m4uuc9MTwe&EN42RY0xrm_@7Wdk@VyIcT5@LA3+A8QGa+{VK7s<^q{TaXh4brn}c67D%CgI`R>k<>jr'
    'ISQSP4!@oLV31y7cJ=D~#pvnPtABL)QX}8TmtQ`6sq-C}=o4>ke&_P#6a7Y7EIT^*c3L`WdZ>?@9-d)A'
    'ftq8c2L;K)nbpNnp!+!i%)Y@Mst~LwYc=7RWSfo#H1`JgWbqE>=J2@O_?vXhH<vG7KZjpNubw`=zPvem'
    'n?KO2I;Z;uaxFg>%+p1=kIUTyTf3o8V0$EJVCsF<JMCiE^-N9nbetf*K-CqY_)z?)dQz)GZ_Whiw`qs#'
    'j9vDUQu*`On9oW(^Cfmf;j{;(ds20%ugXa45zki3WX!nI`*i$j@M_f2jD1qwlnnTh7>{K9nHsJfqmYNU'
    'YKTnKG=fj?9=Qa}1JF4>#lI^SPCT5GurUY^v^52zBEAB9aUv+4Cs_DMPIvku8bgUEax{v*wn|UGk&=E1'
    'nxcy#RUSDVGoeFD^R7TmuK^g}pv6^c_>Z1Hdpvr4etj9Z<$Um^7PL(2u^?6i6ENiib(O(@ktG=rF+eoA'
    'iu=;VF~v#s?1+PR%7&6dznZJL5i1IK&R+QJ^}W$O!MY5hJBP&_5E?Y$cJ9FsCdrXBbf;0^Dqp0UIxhAl'
    'drbLjK_{i6fPZ*=TySZ++eKCaQln%#n+h+UDzK)73R~1=HG=G&N6H$5`)N3vDswL0IFyA5(moxD1N-<L'
    'Sh|HC|C{mI_(y>u%JSp6|Kl{HC2-AH<jzpVj*OFmyvIoL?PL%b$H$_jW7#BXRK+q%)GRemTm_I04`Gk8'
    'TvDfbWwM2sMUxqQSHwGcub9U^@bj4AuCDU69+?B2&6Xz$fGbb<gTW2r2^AyGalfc&H|@nZ5ru39;_^!@'
    'H_iZ@ji-n{B;?knN|963$_c$2h{{KR+0)D=R&dapR3GLbDDYu1UyR|2xj4dywaAvI53&mTN8;*B?EmrL'
    ';h<nii`CgnR{JDh<b4Y?cu*ft<bdkA8nL$08UAA9I0ok^xs*<&;%dF5S7uX9V|s(YEzTvnNHG3&AVxDa'
    'tLL(fFFDZ^!YB#kq61PIVA&0UnO)^fUIxIo2p;w?D=m9{`TS|k<p&zUsY)>;)jgd`hpCt2J~$Bd3I~AT'
    '(+(?E2ufh92VB$*1U;MR^e{M#Pldn&1eD_yvT`IqUSF^(nkw*1e1!bfNtSBoMJ^3HdiZ?&K1<c7GF}i6'
    '%m+=zAd}){&CHd!-xg+5wRZKjxH-4l)|P0d=0e}P07f*oDTb*_*6VSp&d$@AvAnV&zE1-V6-t~8&`_6i'
    'RoMj&qFwQb8hbrRD)vEhHsYUVh)9-6b|XT{{`DONb;^uBG@o{L{rZchT5`Ij>o^Ln72@AaR`O2rAzNV*'
    'iL7s^)O9T<>(mLGc?Pie5=&(%pIOJx=g{Tc)UGjVO4Fofs}9|Rt)B3l$gb&%W>X{gB#9~<KbbApNO^4_'
    'y++paB=fQ^$mh_k_`OTSu3dSRhk4(I<m*Cn*}YtJzIJTl_9E3u9hVO_JpacyA;ma*bEHx?)ZFl@j;}WH'
    'P|d<<0Vzc6CF`%@2*)~w(3;Bo;nghiw!)7JECBe$bqlQdL_~4tCG-!5HdGh+$jr-$BFLb_i+gcj3f`kK'
    'nat2KNSv`$iLX=j?6WE3csdl@Rn5z#4`FTLoh3)8_8y$NI4?WVw|a91HWGV^*(*N5!hEM2R`zPj8&s2f'
    '_kfducQ}t<Pje<sTO-Wp%eGYFHm#D40Z@w*f-<#Q!lP>V2o-WEQY4?PZXr<2ls{MaIIs6Ag{oKB%Bxvt'
    'noKG8gP)#Mo|Y>&C#7Yll2qfXr5vN;rE;BmIbhAAtu#Gytr2sd*x1>IVHTDfb;?If>gNqIP<U{CYFCX('
    'bw`fBl0Yq)AB8(7oW$i-I!&hl72oD&aT|uz1X5G~wxRu3$=gu@-yYTX=eT|)bjuodg@+}PT0etot47AA'
    '`YCI+zPfEH*LP#xyuvdX#$B`gS{iGPuh~lDN!^x$$|Jd7t9f>PeORIq<cUU13cXjRxpqfHBNbHbD(qBU'
    'h?K9Uso|SfS&Hq+<@1~KEh%gHr{?8XS5GdlPBKj>;ng%y$rTS@SXsBq@rvTxNd6z!fz}2%g<N=LylZ%s'
    'XTX)!Xy}C()NtXa@<7WGDHivIDOchuy8Xlam35W4v>3IokDlavCAOsDX*D2I0c?@}^~L#`fGG#&Cm5Zn'
    'aa6<E+TB@t?|>qoEwGoYuBNJ&ZHhs1DovWs<G;AMyv}w|J$R6!CQ(B8qX53&ea=1xQM;8vpZatu>_qu-'
    'ea=tUy<bC3eJmfxbM5fGq1RB<LY#i+NCeC3`aoUa_yqS$VWM0usl@oTSjNYPGwX-u5QQE;71!Q<ku8kl'
    'cW(}H0&`2;=>qY0VnG&Waw1RGEoW+x`}p`wuO81!22>bs?1g;tba6YGMMsA}JQPdH^V4x6E}c6%{`_G5'
    '67qNRlzya00?Za;Q-jw={&P+a>Q*mt(1&@TB4k1KO)edcV?=lu17W{T@x=OUK^C8$XsmW5+5AXx`$1u6'
    'flvUXaf<6lneW2iP84{nbUK?GvCQ~LlY1y$`$BwrDs9c_{W}1S%F-r}u(&$9L>S>{_D=kIte*d{0P2}#'
    '(Aiu)>0+0ynCLUr9B>Xh4!`3+pC45DQ(n@Q)=!|(<S1ugaf*T2>qWakibpIj!>1@9$*23tc=}G*jjyuF'
    ')D`Omq483bViyT{d^dv7VxV4B6E5{t__(45iyc@f+oC~mn6t@yOn>Ap9SCd96Z)?9icJu!YK3P9fADC4'
    'MmhT=oAw_J&ZpTm8=1Tgv08gNP8k}V45pY&tA@6xIdXbCoY=t*W|fPM!fz9v%N*YUj9K1&k~UcMHYHKE'
    '{b@#Xz0Wui!#mD}OL&<mnlaqVqBxgoe>GUZ9^wtO^TL#821L<AA-I;`;-@*~cKo4SrkDK6skvlBtpO7='
    'Ty15maZ)7Zu8#T|!)wG<h$yNA-svL1A<VJk%cw5N_c|BF)VFX}yY*&6VDzZ=S{yxrwHQU4(}(vW32;}V'
    'f7OsQw@Xzk9X6X^Ku}+7hanqa?mFxyX}1V2wM8CCUz2riUKd%epODWjcZ{YDr`sb-VMFozN?4SBU0@>8'
    'DeU4ZJ)BEq<D=Ew@X4B8j9F&5NU*#evzl+Jf3!S^(k{$(yyz!}%F>RSu+R_3Kgo9dD9<(EfF<W#CbLz-'
    'OIw@5PAx=SAlqnWqzDzfNe;)VkuPKx|B-mH>`OFIEFz2w7OXs9!G(u9U>GiD<bJ4&(j2CqP4(k!gUcTL'
    '=+VF|CKHvfdxN9Z=q?>C&YyfB4<v+k>M*f@Dl}1jtAaumGV3H0(a91sM$+aj7oRfYmj)(9$^}8JVwHR{'
    'Os2fj6}U79R-;90^IIjOkUP=zM)W+tgduII>RjHY%IxNZeBz5LOqI;YfmL~h*5K$|)Zm9{y2RTnP6n^8'
    ')ek@ApVUuy+)@4b^>mD*62Bb}NHP$2UgXjvWSsE9H)tKjGeVrjGw3MAf-3$}nz;0Sb;V<4wyRT@9|i8k'
    't)KY90!@)jUZ8SoJYp6~QkBaHWbql&QfnK+lAdjVqZJ&qedV!)8ifZ3?ANTenAQ`ZkaLzT@@AFF9eH=L'
    'E}*VC;+GRvnSag+DLhq-rE6_cDH=W*)FNz^%!RIet{ST7BN{1{^iW|mJVGY3TPY_w`>@YxO!=nFL@qa*'
    'xs`Ppj&$)*o!w9aShIFtn{{vP;fgHNs+AM`AD#%*KPu;n3U*ay$g~e!YfV!^IfGR@3o<sj{3tf8+-6(d'
    '`7NPon3I6_;&Y5o#tY>^aG7%nqE}oU%9f`}n+`<d7=Qs{EMA(Z!Jr-z$=z;vn)e5#(Ctwg*z1wzqBuQs'
    'ifEopUBp-uEmqaO92c#TSAG3gdK2NA=L#`&1?88#QdwU0#WNyVa9m<N0K6gB6UxW8cgvwVIjC#7reOl!'
    'Jfy=Oj6SFQLynlziifvi8!3jp1fytWd@4)+vMJ#`MZJZ*NW7Y`Oqif&lL<N*%3*BFnP_@7O?RnExxy22'
    'q5_xLTLoY^n?>+L_c%Be8EDhHE-tvZx;(#mb(P+%sIHp<VaUCz=Pe5>@hWj`7#<ar8HuKyz<E~2TYpwG'
    '1VUD~nv3!YvqCq-3_MB)a&`VQxk0vBXX@UPy{ar7)<3(pZ+HSF$0bavsovIy!5En9ex>Ix>Zb?I^|R?F'
    'A=AoG%`FrIKH(v9Osb~%HmSFC=%tKTF4<95&HCQddaRQDT7w=AU(}ia)lOY}pPfV%>Y*)bYYq8an!`1?'
    'VqG$Q4Z4`&shtw4P$Yt36=0|K_jdtUm%X=2fG7u!nc+k`ZH=WjIQ-1pS78k*hNL(6<82A8i-K3kVwObk'
    'OstKnjS+>wSTR@~TRJKvxN8JOA7B!_`n-lAs??s!F#ML0pc3k@o?YL_^9|QG4Hmx2K2}^d*8&)>wW*bU'
    'AVgf-#|IDSge1w}LMh4>=!x3Z_jEFwEz)YwN9oZQtdVp<k~FB(S0m2vJ|!aFO7Q$lGX4c0-Q%`naVO%v'
    'OiL@^I9hPAo+|CVSejsZa@CEAnemqggl0)jnesO$Zc8GHOd#I<1S89q!gV@8FOSHlYU5Fnxscmt(?TNk'
    'saoxQ&tHQUeS<+29&rc5`6j<0`nKp1)WT0LH~YmPA@4<QNG#{%NA$(uo-c_?QHXC5yBrmba^)6T@nF%n'
    'R84sS|K~ebSWl9FzY!h8oo|0RFvXUA`GI-%w(5{($>|E^Ky(AlSMumc4+45WB0@%{$;lx9>Am{&xJs|)'
    'j^LCJ_$o?Xkr;l`p3eQ|j#cR4{_w(G_h|EzqlzcVyg=$zj%!dtbGhBpfvml?t#pukb!>}FCQZafh{t|K'
    'BO>(OYOd7+c_9w+$ypU%<wt|V(;^^HRtfW>Q5j2Bv`99PUA$b;V$f94qI|G{cK!ZJjG8UYF(h`pb_Fse'
    '3*M@D8Lzk~MLG!KWfolTI~^sWwDM%O9N}IN_$T@_he3|?mJqxJdyT7E0<PP|+o%&7kG7q%DEJVy1|zzR'
    'zT`*<9e~V5x>GA%UR^DTSl3bw{YV^=JuIJ;&r_^UV{zNFpxAWVbM2Se&izJ*lq+YJn{S-1WkqQOo4c5<'
    '$K*C$=e{hpv*u927Yz%H6n1B-c4cpi&FH*Dy7Z7+q)cToJ(!{-Ywf|5loNG_E7I|+HjhiId&Mq^rO~n^'
    'pDB)?4C)l)Ophl0I@i%NHH>oHCpH=(X3q_z@QB>gNSHJiS@uo#@(q6a76o4*s;r2K+*6J8OLiu;fODL='
    '(^-U=RD{bXSX@H);qXMXT4M@@{lQH;XfRG+h_eG26dt8<r?kb=PEGl(*n4n@`*iS=(~;O?fJe<m3|p}l'
    'l?M4oPVt`QIc`nR6HufDUB{;mkFzh>7@+p3vGp%{AK<g3Q`r-kpW(7)E-xkm_|yTtxG$XvbDhu7CL<B2'
    ';>Ri;P{^TZqB~%JwKA9`vpadO3R={=-sA$|x^?pn1ZuXVs6OU*rKpcK?4CQ>6u0NRDpnuJr}FFfW@&#k'
    '$`0I`1_(i=`)#=R#(bMjzy^-2@7js%e)evb_(;=E`8;P9LZ!>oHKI`gW$NJya@8)j#&%TnM_z`WhinbD'
    'C01=qw_sGmt91h@Vh)-0hk1UJZtN~?lqvZ<OsuI#H|@9<7U5WKdQ_Y%1--cNu3RDZVMF<>DrbH$IH#DS'
    'gRbk<0?h2|)g1h!u=11Nw}dH;)9sPq8s>|>)=0PUR&PK!u9hC^0=ft7I#4pcB3CZ0bh>7Wc2(~g$7BC|'
    '0T$=O-3*lt4<-rDbT+nMY{KlNy&A<s(rXq`OQjCW+ky11k52o4Hd%8lTX<4m11_H@8qXF*K#1>s0hszj'
    '@nhA|?A3StlYmpW=?67X?bDuO=|5bMn%*XdZ`B6we8rYS#1Y~$rz^yDpH2^RD@c{W;Lav&35MbqHD0xc'
    'U&^vs#g@hX;PrH;Vhb9Memf^qG_&?7K*s3ee*WXl1FKK60Wr(0ee>D$D8KXUWKeps?wyx2d@bMg>TBg#'
    'R4q$jR#+$65cbGSC&C$7?Nod(7AjWg*>=Y_!kjeNv|d^Z!F~*}lfy%?V6oIMo|UpH3D>Fg^bxVqTrTZC'
    'l21HD)CsET_=o9tYQuW{dRfz*tp#7N8`Wu2<>eahk6%N%;3n5^k}bZz$v>-puFZmoMZJu3s-n;kB2kh6'
    '|M2TmEkb|_Q*yGqC{^k4(VBrZh9$Y(^KB6bc5UtOR3Vd`Lr&-n_fU!kZ&zfItD_c?=^*)(;K>xMyo2-x'
    'f)PA9-ImpsVwO*AmtCP=*d4{Q)ncTu<sBEU5hCRARA+}|G&7RNHAlsx)O$)3Wk>cmr->^0ogGfB_n5kA'
    'o3cSvA~$YVlP^`Cl!mn}pQDJ^Cvo&<%Z$_O&%XE5;yzMFxxxwEtL5sTRdPh&w#`|m-(bdRbGAtgKTRj)'
    '$CaYxTDk2ZJ+&n@)puH|b4qG`I%=Ku>zIlvrlHi#bV@^Q@>S(kki)IToYrLMwx+JuSABd?Q}pq{{|{*z'
    'd1e'
)
# CATEGORY_ROAM_FROZEN_SOURCE_END

if __name__ == '__main__':
    unittest.main()
