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
    'SVpWh0t(d(EO#?BjlQ92#5KkPlZ-6O)hyEM^+toCZBxrM$Y3xgj^+%gV-n4F;Ug_yEAG|t_b;EJIsM}4'
    ')3ak7ebCoO+TP>Wr>DoyU!C8wcFf)l#bfqvt{$^jw|vZAjruWr+ZK@7yF~?=y<3)$+1sRs%$}SgGJET*'
    '$n0%aMrQBEIx>436q4DyT_u^l+n18rTU$$JZ~J00>z_>un}Cu7xx$1{-g-y|$R{E&i#wbbo)9OyRbS^*'
    'T>s45z2krI>huVVh?lQl;RU@j7Fnq^?MYSmZEO%-C;Dh;+CAGe4c8r7?r`7?3_`IaTTiE&Gj#f+u{*#X'
    '1!H|o$Hdfo8W!!c&DNS!xs6{-p+DC!#-wNKra2t<LFj3=Y4ir8kvXJ84L%r~jyCS~tx<0@GC;D9`(vsb'
    'W*<ue>iuzF&aBd~W9}|(>+CltPhWv(K6`~*(vkqD^0mLjUa!OszxWWG;U1si7Qak)IL~fB2K!CTtCdeo'
    'l09~=Xc9|XnItE*&4Db{Vq&Q==|N<^DpS+zX6_ub$I?}&Hc?}MbM6PXs+wM9B<>C%G~pk18(g1H!2g^y'
    'xhQ6UqH)RY(g5*b)vb?h?)f$ixN+{l6}@50o8%VflV*2~0qnf}F_0q0m-Ni;r1(7*;tk61-HY)1Ai>K5'
    'yg^9i)GdB|)-=R4($*N1t$L<3Hk+gwi!joYgJTxt+ySbaW|_)$wVO6KTFb%C=Cnww*hQh?P1}*dwo7|$'
    '_vTvT*4kYeYrC-3?!;8fS!&mBuWuO^sSHO9dX70Bxnn~gnU?FgMi2fp$M#^<>zPC1*!|&PK!?52aAe!M'
    '+oz+!aI9H_(QrI=4BFemVq6M7I96ZNTzfds`i|i`x<SVy%d|8T|In#xjLd=A*ZTuUqvil+I~a{91|^IU'
    'Ohu#H%%L*WAdMm=j#O&eH=7qDP9kd9{tIbD*DCb=lQk&g$cp}e5{J*#^SqWjGP|LNSM@L#_W0@P@!5Ag'
    'P<S?}>oa8@lB_Aq8)(<0*97IYBwNyVX*ZXxWFgzn5p7cOB^b2|4r5$t8;&=x&hyO=<u5|Mv}sJ(Y#?hY'
    'wEiZi8<ncxB4pfm%)Z&vh(2}=GPKR1;n<Eb80&pa9}frm&^7x`UmN!Ngs>K0hE0s|u;=u8_O^m=N&geu'
    'CZuQTHfVaSM+PHvXzOE2v1`fDvc`@!utq)I>1mp+lRmc8(T5JUU~*h*(5G8Zq*)`NiO^3gyRx4q+|0=b'
    'PT-O)`2sl>D_ctilbo)feRq^=`6zuQB9N0@AQttkrGjB~n2HyWm9MheRFYS<pZ|kj%ga)K+G%A@Oze>v'
    '*xYB*MPVTfUJR2h8~d8ph9ch@YJdrM$b+)2m-`X=+l3vodt;_ii)M!cxp{fK8*#i_X?!=rc(p9Pt}Tr7'
    'Hc|2(%lyO47s+RMt#wrqI}I5FJdM$D9*Z)K>Ee>Yjg11%yC)fBv3<>f&GP9#A*@LwA@mB?EBG~1VKEj^'
    'MGm-V%F-kTeR@IctF&Tb4yjFTTpo3NwIbC$x%Sl%+|rWY;2hq{=6t@O<TeubTsh5fEhiUPZnyYyI#QAz'
    'GP|{5Nx4Hoc~^4sZp36`r|$RG+7=P42KO%0H8Mf0SO?Q%a&7qv&C(>P?@F=UkzU!QTG^#mS)o*#F~C#&'
    'iSo+t=+)b#v{r*w0KV95Gx^$h<<+%ZE`4&t_`LGATwA`UT_V;zvcZFE5R}w`L*F^f--@r0XG!6jw{P^f'
    'S(T`@U(|A6)OUt<SWAPTq|^3(;W9FyKM1fjZL3tSxz)|ppT;Q5{%6I(`ztP%XKdU}n~q9dnUDhym>l5Y'
    'kEBY@MD7YJ?`5^vRyE-^>`cBlP8|1Gy6;Z77a(D6BX;Ziu+-!BKqlVzQ!txWHhX(`gS?k2mYPy`xbDMz'
    'qxKXJ-HKlAX{+{Mwtg&hYHx0>jjFRowb?yTW{r!hJ5psk(`4%unOs*zvYGZX<?*xE-=wWG`Tg8)j=w#5'
    '-auwW+6ZDcr&xa=4Kl=OFRn(CES74jNCm-GVlQANQ#wCSi%Ddc-C2(n_)-H)Yak1otta*E%i*AGr*=Vz'
    '$IqWg4j{`_3p?VTyJ4Q6R(6D_T|rs%X8Cwz{o<O9)D~922trgEYKSVDlBjniP#cn`cOp*LNz?1M*VlWG'
    'Pmhn_lk=x1|KQc@(_@hWi-o*c&6VU@@6jT@46#DW_g+A&YVRz4k=+7bs*(a@z7D*&cxRY>6>Ijenl6!7'
    'zA${Nx+eTEeC|0HbX8%VrMZ6h>eb6Kz}pmx*}B+Dja$?mQAp+G5l<o#Rl_9|Q^8)Fx4!aJ_0VP+)AjSC'
    'Gb%nk`VFts%F5jz*4&|V*t1tS=6A=>UW#4<IP@*hlMa-yA>Plg9B31i?d5wyu3zNFC7AZ|{Ua+UwYneC'
    '9xD#GA=)cTBJBwxesy|$jF0!tk=-A<)E*BB9gI!O=}|)iGSLUH<NcmKB&I&5M*3hy>&M<$GswWS;4$L%'
    'hP{E|Qlqb1R?iw(Ix$?`AtS@I$k5Pj3yYcAJ<Bzzt83c8a-DSS1l!rrI?;y1u|)=hfj%G>rG3pB6FM5&'
    'cF)n=0kL~z&>xy)Jk$y489hfg-Jvry`*v?Q=x0MGHKMbjM{d7wIDOJ{dnOqTY<*06L(MjIfH@ir#*S;5'
    'rU`t~cY9V(>kVyZ(Chcdeam#+@wlH3o$O~eH0is2+cDkIV5qs4u9;e&Si_!c5uMn2f2e81rsjZX_Q-Lt'
    'LXx3VV@&%F8EZDcT0+R_i{DgNKCg`*6eQ)#3!~wX3}Lywu>;d`T-Z8Wr&J$l7BMtBG<w7F&^2H;Y0sfH'
    '8QI!kI2gd@W7)bfyFgie5rNq-X?NObXunIVnq#nFwLV_sL$F)gNj^nZvM=pTEgJqtZ;ZFwjgO81MmF0?'
    'SFA2iNnB(3^ZPV2YQwzv0<pTpBKCY0-#te>@R?$rb9OzNAL5G4wFJ^~Do^HBZHvp*OO=7i{U;}9k6-+7'
    '43bv}@ltKWzbt>@SF5X(teNWVH$~>26vIoKg^F$>v2!rIF-#VpTZ<^E6F8l*D%DAY)8rS?<?p6@g=w<*'
    ';U-tc*tb&%$u$5TMRpF)nTNnzI;S(`MIX{<ZUDd%ij(p3aqV<~B!*oP->wR4uVRgDXup{)$UL{LeDJL0'
    'gPWg(sFb{#2@5-!wT-MCrL>~1(n_$<T77hIE6Qq`u%y$~YW8Lx-jkEl<HyXn6e2Fu{HrLx1-f(KVvWIp'
    'PTl@^L<uTP&7hh#(#O4#)dxLG=x{X9NRReh;tU70Z)+~mhymvJno>?T3KoXo%%$H}nlLnjojhahy0U%G'
    'D(>DGL_iC4%|h^>>;eS`wS3!Q-5%UDeMYuRR~cRhbNU`UZR#jVPb^-mSFDy%V{4tn*^VxnB#WCwogAY0'
    'Eae+6eT{5un$8;~b178bh<TH`+RVwWWzzgid38zCb_VXk_w&@i+xKCU=qz|S4V{Hg6|i3wvWPF?G2Zh='
    'v94}}g$2BA;`=aY(qlCMw)cVy_{fWL^&}pIfq%s-f2+!K?8M62|MIUP>eUTwwekgj=|+x}jrcqnpRfET'
    'yJk1!wM*(+NnFivdN{SfdUnp2Hip&Vr;a!%*_`3`_xE{`{bcBLcOLvoNu`<qhZXj-{R$YOlCNhH8iw40'
    '8Q0ksX(!Y4=I4!7-HR8>n(%03?uA^QPmW_YVfk#1Id(4&kXr|Gx>)v2tiEHyx+PsnBdgVHo;!dO=Vi|J'
    'oS&<#wA}1q8>as*9Z<o(=&U{}>#E^j9dOAh&@UPRDcJE#iDC~#Hg8%NVU8m2JhlPLXI2?IAH?dYFHTRs'
    'J$Zig?ELij=*h|R<Fm7yU5#=PP8@8FCcn)d+`#X$cHlE&b@AB-oW471l1NM|XzBXxb=t#4WVxmt9@aE)'
    'sjQl04>gz4-jL!kj%8AV(m~(Ubj=+13`-yO;ZxlKpOZS8-qTIprM5M)Et?MPp-nfbnzVGr(02#Ju{G@J'
    '0HJTWSovr;B4cwrFe$P6BTLuq-mur}I~Ex_cwS<UP0iH%=D;BKaI^``$|DH;<ZE`=3)JPk$Di-XTya^W'
    '8bDtjaeuX-weFy<0wy@eqY+H*Nzykc=|6)P$KJec3h32S0vv^n>0AtdNe2TGY~ja~0v=D<d(k85z(D0L'
    '=tMbVi30M6#{&j5#GAqu2vqMqWmGm<COrA;iKx%&g#6kIoFYJcrvZ4E;fIK~fQlMJqLBZ<Nt_HCVjltK'
    'DL>h7Y&A^f94cv3Dn<$4Vjt7S#1I>PS1@ODil>Oq8Ft*8D6e0iJgG@{$>=_flTA8{dB?-7!yV=oiGEjg'
    '7FBPixPB{ifK;P!N)=Sg%BOlm;_J+whrTasG<^L4`)0pu6W_ZCreF(A6xHW_-nvROBR2dp!TyA@;0bG~'
    '#A2VeO$lth!n)@BQL_8082EKS-ox0KUAEs*T`+0es!e8SvErX#!Orm%>MXwUX<Lmb*v$@^Uv;*g$F)@S'
    'aC24lq8F}<_A5B97{!%{r;rc)*&*jUMz1od5nqU%rylj4Jc`)0<4f=Y=zPD+3czoDr=|6CZggVT`w!vV'
    '>8Lo|3A#8(ix?!<%!^qzB+ErmS-hbmcZv8?qlGo~;%CI7K5i_ow4;W>8G9S3>lKOK)gUtRfxs|)+;&H~'
    'R<7l*VcYRkV%y*$dzR;W@zn_)5__&k=lLBMyR$DD_1`Sw7(C@qWg{t`FDM|%$L*NZKs(>h+&Vb1ML@OD'
    'RTR_d38t)XPrUmmDb${dX}!M(X+eB!lmRj-0{OxA_*Pd)iqViAIcRs`pY6syTkW021jC%dBis6RM62lD'
    '6$X{RA71o>2TbbIrqCkCk8IeD+_6`;3#V>3KHY9yx;yZ)ZgR3-d<f`#qTqcG_G>*_*qx)*k}}T-RH+?j'
    'tDh*?ay>@#e|u9g)#Zo<ZjqlnnJ6#VMe@vmkTQIf`N&enD;!NvlyAb&mojd0O+m__*HZSL>pHT;0TMP|'
    '^#U($uikp`QKy^i-<I%%yT=CU)}A$gl_((fD39{*cMBU@Z}wjFI325VZ|DNe6g<&l-rI7ZT72}m(uz{r'
    '&z1WuiKy~>oP(9U*;RhWL)_ekze_rh8iJD=f!lEauEF@*Jqf?Hu4UpzcJS>kV{Z~MQ#bN<7lF6dH{ccl'
    '2emI~j1iV%6i&GY7Ngq_4$uBt#Pb>r=-p8~PhvPvax`x@!Mr<&<ux42+aQv6t7=N?YP{xfAr_U~_)#4Z'
    'W>aIl{k*?*J=<0RCHpL$%ALcq#9AbVa8-9srnEivg72tzaarRez%)CnsdpJgn4WYcGawBL?yCyJ4Yn!u'
    '>`yR6)&~Bm5i-swI0)kmjNF}}enfFWNz`ro5c<n`cmd8rgoa(7{lv(qsyP9WkH7Jp_;P#9fS=%^t8mrX'
    'M2MyE8$la5^eh~@V)NN&ojQk(T>UKTk)~F|{XGCV7x8KSQ$F@U{x2>t;Sbb%By03*bw(U!u1Mf_33F1('
    'Z1$YI_b!+f^9qG^o;JDk?$kT}*{#ZGL}N6nFm|jj?nGTQqAgbNt<+7Hpn7(ud3LXOR-&v~wbO*wS+|rZ'
    'ATw|Vwr>>DDxK7-$%t()m=r^p9mxcYuS8WQP*w3pH$6edv&Cq8FF6}GH=JCr>^ijqzDgMK7rzihc6g`+'
    'p1(agNm2C6x=zYS5-f(6ycun5FGzDT0ib`yo$z*m{2|E@yC3FP41%ofWr21U^Y5ghO&tBUrC7IW81OES'
    '?a-Z+;$#T&ysIQpGcQ0!+d4-qON4)v2I9UtOh^9&<0m!sW#y2;;+}XB5DU;E0Kmj+H4kO$685e9iGOLx'
    'QYuK@b<}+PYqT%ES$G&!E#`P+;!Se0GD_p5z@8T!PiOHJ8&;CHAdUB1a^<oFIa*+Rc9<=d>+^hZlrTj;'
    '@rnmCWelHZyQS2w16c->O#++xFDZ}p1MjV2%Pm1l<7Npbn>*v>8(CSJBHv+*H8V)C0pwg{Fzw$T(*a*k'
    '!}&1*zeOOutDrRa@kbT=JfJMdbg{g^R(iBiIwebW^MO)ut+tNZ=UuW=#796Xop$WoerUhjMN}Us=U$nR'
    'l62+nB2u!sOR{p_4R5Vxt?bA+A@z<FuDTPZYM!SWFwLZ>th;v*n{Wr*MPR4lpmT+_pW0ptSKJEkV5t@9'
    'J_ehoicTF5Efp*j38H-IOdjm-*n_2c7r{v&?~)DUMv)TahG86pF_n1m+vLTmiv^gSXl%<m4!UbMtN{aE'
    'CU;da*HXOpP5FMv+l>FV1S`*-$c1SI1JA<`5?EJ4gFcb3cTv3dgk&EEDxMe8=u(`_6nS-B{+=`)D?MZC'
    '=5^kKkO)79%#pWbO4%q2*OYnuvX022n21QZ99W6PTfpG5-3#wxaJN?K8V<rE{b1)-TAV7G1FNgHHwO=4'
    'M&e6pCg`>)vP*n?OJ0$+U2@n&zB#mWYe=>+)VvT~WeUmhHX4dkNbq9t0Q`L#)y*k#afka;;mT@q7W;=k'
    'Y+p!0Q{Rb^3L{@j@g>AkQkKcA6XN^gy7u<zaO@C2h;x@C%1Iv-p-S^8;PJq7uRwQQ_$0y{Vuwcd++(*5'
    'CQA8Q0t5b?hsjV<B5jG*5lBT91Ee7>WSN~bKl1{NpEwx$4tT~rYM9*L7#7(UW*SUMb5$Obxq}cUxSp;e'
    'u5)a^Q7bN-NDX&x?fqFSbj9u2ze3pt6om-*Cii}4qktgyebgU+WV_=z9cj*DGcl)YDK}<!C>`Ys$D3s1'
    'vKN=hNqBEdpnN2k4O28>V9eF#&9>lnDwgj^DmN#T??5IuE|MFN$kI&ErsZ*Mi}m3{<s?0E2bKx!%Xt`t'
    'i^#{LmcaHGOk^ZS^t{x4y|YA${c0(e!BFB*A%Vh}hF?Wi>+8_89ucOQ94N(nf)&}OcN*O<gd7X$RF%n3'
    'xs<H!dnmU+bsZ!ZFqk4cND?slACmK-3TsS~Vt^KH$}3YOa5@S>8kBU{P^f8%X>0k^JXr@0MIc2OW%8?;'
    'xaQG_)!R8}q-JpP5+|)NXug;Xt6a|-?_q?khW#uCeV&X2Xj!WFQvl3Oi+kZfUo1d&S65PC#EjNpwpXdK'
    'vn^P0c}Wx)myltwLuucnu)h;oFR|DOlY+VAg7kce7uAvxxaO4lRWUh8UBvE41z!V$<`EWM^4r`(#}7I@'
    'Eq_bE1v0Jaz7)1`DZh!$_`d97Nne+99i?P5u2akhC8w16q!QQHq^_<~)w~##P}Q<3L*>;pA2T<8S!@(^'
    '?UsP$tLWWn=v^yli4mNgs^<#rT+17iX<?_@PMS51!Li>7pMy)}My)AsAJ`<|F$1ND>pQG$jd+MX`yEBM'
    'iFs!hz3_szC=*t=`%@oU(br>0k+6hRgW%19HC|wSP!4rj;1mQr!xhFkW^vT!7)*<+m2XUK9sDmltukzW'
    'CzRzWvH&w0FAVip!ZJ-3&smo3v7|gQ&R-iNe*4NUi5V_PR9Tjc5>}IvX)XJ2BSlIahi`<MCgV2X_;!=F'
    'R+9vJm8Pu;O|lD(>J!BAr!NG$yqZLE7H`QT3AHIU`t5wqX~;E$4^sVRIkrs$rcKGR$*#~zqPM%UoLX`Y'
    'SFv&;D@Srztdk&R@YE<PyWreD!{Q7H{Q8H@WfMw*(Imy**s-}$A<VzRs2h?byX5I3MW$@fRZ4QWE9**W'
    'S$kBJ;<zV#P^2DtA%QYRuy{;#$)kH+!5kAMkDskkpGRwx;fyA%u$>xVtwy3Gbxp7erp<BaCY&XOa-{3T'
    'opBcI;~GID1tw+&bE6UVMiH`<<zXB%OOoBs=PGAQXe*7>&-gM=tq`2(jC_XOcwe8~MJK|qzXv)yvO!oR'
    '9Wu(jg8%YKmXI@HxAJ~9k#adN>zOf8NN|<8FsJ-lMg8`QWx1R7^pO#2Vy#scmhai$ixPX-#=Y>ycj1%@'
    '7Oh*a5ut?v&!C?u?KZoo^+V`69Vv^!y>RmT+)j7nNj@J7fad;|-VgLk-(^W)WOepxsI^z~y}dSX?zLrr'
    'L5}F&zPHhx2yTwl<KVqF57{NSHeL?1X+U3I5<HwOl$uH3uLZ6tHPN(|*r}3eR!7`{invFOAFoa+R}B&j'
    '-^ZmPo164Y@DPAO*(RJkfvIETF!|v4e(V(3*(IfM!!01cbjI9FdDcokXt<r^j`~UNsG;Otbd=m(OUYgL'
    'lw^jN+?K>&I-%Y%4c$RoQmMra8}BgRWT&g$wYvJ!yT0nNFTLv<>|HOLP8mu>{U6T`gBO8+)yZxs*K8kT'
    'nq8%M&v_H#NRWCD%86wq>vf}}TEu?GD<<WNC8;4++=;K+nyQUDbxw$s)+vsSR=FLM-~#r<4(FhUPKo0!'
    'qKTppIvv>+RP%`EzwLK2`6RD)s@(FRUpg_~U+wgz6XQC~6wYWM6cfYEXWxTy@AFYeccqVHU8movHfmBC'
    '?OYd?RZ(qkX_pP_>cWXIO4;@z5gNs2=s(XJ$Q@bv%&A-ZG>eY5Irk)8TDpa^&iePkyQO2yN$GE-AG{nZ'
    'wf6i^sF9ESejZIX^k}}L$6d7akl54X&#gm`1kS75Eq+zO)J&RRCancTmB>rrEi|np6cyWHE400PtB95|'
    'zh~uhz^daxY0zwbY7St^C$*~h2yc*YZHgs>a%n7W)=ZB*PN!aTa_NfmsDGSaeFMwbk;!oji=!*uCrV!l'
    'pl4ha)Fvk}PPZ^{entH623G`%G|h8k+atI|os!x1K5=@{#tRx~L0Wk61oFHP+xk++a!NsWNs3jAu_Tv#'
    '``aY)QqWhv&Lv71MmCb~G_8Dr$0)&zXl+6{RV1(_xXma>Hfxu)N>|#Ji;Ecf>9_Nc?$r$^sZL@8O{H?4'
    'SEKa2OoX*$V~KW`ZLRP_5Vea|#(k5Gm5F2g7Uh-@7Bh4$A6F#XweK0t<-BppWVfNTlO~PU5ZZ1ird~_Z'
    '&wyk;ug0{wZqy~JV9lt{Yji4Ew^!09pHHCw%w}GUBjDVVV&;;JHrB304EbpdS4v|2MtQW^Zp;U(Q@^)_'
    '%9FScl;%lFwvMWZI^P&QmeciF%Ji2sAK!s?at((6l;ovM@McI?RQ;NWDvO_WZ@sGQXpv>Q@*;*R%06zL'
    '<lqHfT-u<H{B^9ntoW%>E9;T8(Q}0^VIglD*y$ud$f|}mi<V#fVwqKEsK;wKU7}<|1Bgijn4c?V5>eX>'
    'YCdP0@!9-k7Q8BEOns76G<(H8v4d*EZriYhC{eteja+*bjhTlMcW$k<R(~TOK2%;^Qe{Ris6qmaJ;9#A'
    'zu?y?F?`^7b87RZ=`4{_A&N66?$$X(c)yt!6`RxFVKWm|#uCmxc(IMGOO<FbcZm(^2n<A+dIa3*`<Uew'
    '9l+Eh8pkM&w}hA?1Hrrp`wGDzYXM|cN(Hi|6W0RSKT_Hiob^a%Ku}@!V@H{+a6f9Va#LftY}HCJj+;A$'
    'OYH5;RRPVAMFO^+J}42D58aW{gL&7-?2;V7rJ16JJaL~>3VM>CVaY0;bnm)|H<1ujEUEZe<y}b4V3L}^'
    'R4ac;PTSafk^ER*cIG2iuDpImTd4@or&9IY_B(o2<2u>WLIj-UwCYly3p7zX+uxd!b0P5=`Tf-o-_AX!'
    'ZHNA1it^(P{&^D9X<H=@nW1vQTLIp5F`X#7(eHHLZeJxiZJn+g(o&+64u%;aA?lOekeZd8TrrV*OAtkP'
    'z(p*#xenN$DM8hU>Spp)^_+vIvZ|S6NUzz*MGg}eplvL$(WaC7Xu$fO>17x4QCxOWy#ULZ##iObE0P-0'
    '-h<PGUC7-ku`2>mk`(8bL%f`a7hvi~<wmX|$h5!alF~)4rc26_*@F_Qt+G??3PmM1do!o()+#N@X#-ys'
    '(^c{oWmBj5=T)|9E}u<i8P)s1*}GNZl63fPRJe2vUa6yQqIBsgdTqPO6308ROBymu8n8+>F-mSQF19~p'
    'TxpZk_6M76fY^A;;wD-k?y?8seP~!LvkPMVHi+B8{nD!V4kI~t-l|w;qrJj)(k2`3?WoyXhWNJBUT+0F'
    't!SyW{hi-@lfKe^m)fSXh1YI(E?s0a(!T8Oah~C+&dK_H=rXpXd3V&vv}P3POT+5BGS*hxYV!KSt!Qi|'
    '-MhO-U9i7&sctYL^f_cM?WW1%^;>k6TaRIT9+rCvs1dev04bX|$mh`|G5Q0PyM{IzQ{8d;uBqE2-PCn+'
    'Xb{__Bb&IItB+`3AB=mBW7zOcZ>%{E)rO|2jcxcvA8sP=xs=ZV?V0vqX!S?qp4F$8MGQ*qk?Xj&IT(?#'
    'r4I&%Yg%K|9RcWpGw3<Pe!n;BkNc)GCdAnY=;b1K7Xh?4<*)$TmAu&~b|$`@haV!W^k0#RytTH>!JLZT'
    '2<hnUm|RSh@5^t$A{WV=wg#G8%+mO$;Rh+}5tMz-sd2L0ykHr#TLUdtoM#GF#uBi;*;#2BkKw)Np+i?M'
    'WNWy9f#T?rmvV$TQt<O7xu9zo)McrTlkHb>62!~9n+l%%JY=jbfPt;6HmF-NQBFfL<&cixZ;3RPPX9Rr'
    'm+j51Y}%4hyIW~<7s94FS#uYnMyjMKawqa&bQ?KSV-;_*J3#`>TS=?fnYffME$>EH?m|}XR#dK*l(#ys'
    'DIC~b*U%FWA3juGuxwG+`-nAML~t-tF3EeU1fk+2@<;)PfgE6PG6=B-%X@Gbw$~Vx1$v_e%c*b|zGz??'
    'sWleE8*3@_V@!hxJej4|U^PNFSx2oY2^PdhsyL;16B%1yy#_)ZnBa$N%C#K(5Tg^{r;vcjs>t$DNBMO9'
    '=Vo667TH&nqn9VF(X0yemYp1I5BR!<JyIi_ct<SO0EacoVE0Pl-$aAg^_#agCPsEFMee2D+>i{peRJoP'
    'nf9Km#Nj&{V0@L`xBrT>r+Ps|R608jO%}7Y<V&%z2*@I4Rpe_C@ltPcj6L)DOBl26yy`wLq}(=Uy9A|J'
    'X}8xlT=11ioHHgEK;%49L68GSoQczrHd~^KQleASd%puhmrmymkokQ%-z?Gi=K5BG$ga}2^$`kY)=BVN'
    'PS;>U(TEvQ?Cv9;D3Cw_s+i5@pd`|i6j>QA_F_H<TP<zdt8!jLAC*BQexl?B8`Mp4Y0^5`PFB<eD7dSb'
    'q=E}g-}t$vW|aCn9$na)7*Qfkl%MOJd&Y;&>zW2tO%3X)XH?~}m?XcPi^Q#o@~W5ygC!<dS8A3)xwTgP'
    'q+HN|&e@SEmg?Zp)ZClD_(k$2gN$F|zrY7ugI&%5kZJCe@-p&^`Q@Ra*MfCj)1aua$=mlDyn{WKy2U%('
    ';W{yr?Vt3fvv3|OFRX~p-`DCeUuPB=<G~QfgD~)~vRf%xxet(5N*K_z8lq@hzjYucm#?9+`YS1@dW+yC'
    'TCh%$Lbwik$f~t;*$oWLt8|mwE3l%AIXK?%&ETqLav@d_C;Vbv4V&z1K?R85ufHc=aD*61$=?fzuh>3`'
    'qWaPMa=Ey=S~H2P1&gV|>U~U<<KHbvOn9A38!Lc#4pt)flXd~T#?$sTP~Ey>g^5S;d|?9{@~V2@k?4}o'
    'yuK|V0AT74rxmQ_^1?zxKf8k|6--WrNFCQsEp&c+L+aq@?;<u(_B1j6>TqR!Fw4AJD4vMor5tFMRvI9o'
    'Ddlj9sKf+12STMEO39#>GwqC)ME+#ye#JqNAnMQEi;nUG%2~xSQDv)H{_M{r<|0I;h!qs%eEk)IcBc83'
    '_aPU^OfJhGy<B2Tj>s%S$!t^^5aev4m|r`hac84?tlKl-o43u(c*e~PUR~@^QPI4Rb7_JVoZ^M@UN#CO'
    'Pu-8?4O>Ol5{KvI*yLO&%8#4(RYf69i8$efv85p6>zucCauI~6#S&N_D0#;KCfdJU$GccE8ycKBP8ypX'
    'Oju2)zx*Nez&L-7{?xA?N#S5-6xBbgbtn#mp;egXBT@IfUN6yl6GFf9m^o1)!!F>|_gor#Q>w(^VMZRK'
    '>7*WK=sPv;^od%Y*pu1z7c6Jt=;1dHkJS2WI87>fD(@(rMY(FB5t-5lOju=pdW~D?U^vX@i&-qrF(R;|'
    'uGqQMl&bO~MWwQuRaSUcN&q7jv02f1bYD8MF4~C#6--N%E3!+uFdrrtr5L0?`~ed$T(wk*^{Yck$VveS'
    'Jpu!Z-(=k=UDhK9C1Jt;PA=DNy)Ld(_%L$jzO);kig$vs7C_!KsbQBfTSnI5vZ(l7nA^R$!Otj71nCmr'
    '>_Fg{qgWD*rNYI<Hx3Fkzx}T90q)J2AFBv|o}3>GQ#N;SA?tuT3!jy4j7n)^%>yZHJV6<U$&&COq*C&3'
    'U)~<nI3N2?cM&!Ivk(l5B$iJdFOFDIa!~Q0{1XJ^>A1^t61HA=K;sYL{GFU|d6^bhbPTQ{&TT=8VIRpO'
    'Y|hVJ&PZaWoo-br^ja+l(;kEps`})(B|)=rWX1et)h=HuUS0^LWWRUrjX138FM6KTNSi2Wm(iN1_pMJ2'
    'D6L|XZP7tF<Sc{okiT>1GV4h3nbbPMifU=0#pxo7ll}}z<{Zkf<Rr6B^jP_D>4BvL`<sTRB}y%Oy`+*a'
    'aRd-G7lJRURJkHzHHisfci)(IEyK!UJp2AL+t+xl0|*8~`#iU*fUQykf(&Ohbt}X5as)~q{in@|xC7KA'
    '?eijAGAgp}Vn>tuvDM_iE#Td3rAP+&32kPf(nvD5>aELd!L|^kZ{1RoSXW8IDI(E+dl$J_LAJZvdz3^W'
    'e0<i;Dc1!|N=o>V&HXWKMHK;deEPuku}-QI`QVE2JW|YbS|IASMj2-0Ue3cHTto_bXc98Zv*=ignu9b>'
    'lvEd&ihCGWw4->#j$u&KcKL}6-~G4JS|vEtW!*Iq#3L1p*hZI0@6~j<9a+(}l`NAHc8!J=Yza$cmk)U%'
    'JVkm<N`}5rW)p?9N@TQ~GLbiK2`4=6VF@nSy8LU7eY!~uv6%|l%Zucu>QYV0hzX`3@wCvke@|=P^Cj~+'
    'xl%lK>XcpiO;4Lt$%`t*&_%;Z5u}~fjjZ$0<V-m!w+W~bRK{E>c5g-|6Tz0|$H((HtoRl&%>z!{dk=L('
    '1e;9{6fdq(gIdH81NuR6d6hX;E~-9#Ve|SN!7XZ893iWwv!qiY2}6hjM6qkqybLMh$#gA>w#|7)rpYB0'
    'dEQ)R|7XUubfPaD+UC!J<<y=}J<_CN>!-@I(K}4#yv}My9?fQ1$;hW!W7TzKBYVA`IT{T|nx^+mjk>+@'
    'z|izTZ_qPF+E6p>zC|_5=naQdBksVWqmk~A;i%v5>&9rPZ+M4lsdA(<()#`J*c$c?*LHNxq^4%|Muuzk'
    'G^cOb<AF7HN3Jm(81VnVatWB|)G=X3+R*Boo5EdLJhJ?%>btk?<uVp1sqS8t_AL?}tZeLc69#pBi%KOR'
    'dAKuvZ8E<gOvj1p^k1rmB=&-JSiu{iFBpEJ<f3u|(D22(?6mi%WcCEs#ZG);H4Yte#rh)FfywKhWW%=k'
    'xYD;g|4LfAWNldLKr+oW?Zzrmw%c8rhG0H_Xk?@K(0{Ibl_0K}#nl&|#ra~q+Yj;Db}ByIFpR<fz#c{*'
    '+b`zfB5=;)E1$N(0tQptA@i#SR@VSE;DVoe)OYeS7W}h0Bgp-(QtLQ|f&Dp(>?e4CG8=dev1HQ_)%)2)'
    'O%O|&uki|V3a%zoV-jpOXq%79`MG=BVXI5ZG-E;R)_{;}KkUqWXx&Cj)Ys(=sq)q?G{cUS_^ozEivDg+'
    'ec!|Vk)gPEYI-+dB-|Stq1r?cv5xzRG~OflUgAyqh>crT_rb8*v0b&!th&CfT~!XvumS=lAv96i?X!5!'
    'ZuulXSvl?pzfv$4qQ+Ia6n(5J!upG|Qh^9lu4Z|J!pID5fUAnK`T|k);joK;oN_Db_jd~@tOKh8{oP8`'
    'btQQutUfF!F6B_!2g!gn&`v|2mfnuSdHm|CMiV;*7swaJ(`C*6_8e1d_9ClC5Zu=^0!IWfw1)Jg#R|_^'
    '5g<U`8J=IZksv+d|A2?t6LJ5cQ{TVay%^es6lzQeEe-sPADJ{XveYTFT*=2dq_^9$x3pQwyhFjfBe|Rj'
    'wn}<R>J@Y=iK5Q((t+0#1wUn!w8Wii9w~~amfkt6Gy7euo!e@i+U75VH6<Ut>0-J9S{)@Sd=3HN<=nF='
    '{4oP}fbUlO=Nj1Y%A-d>a2;9tI`NMhSWkN5jqV6P^=6<_Nhr2P(pr|2=(0Z!3ZG^zi0i;D4wl?IX1Apd'
    'IUCepmxSXCEH`3>4)A0YPO0*PM?c82_MVgX-UZ8I1JbeIv0){I?i*vV-Er717;HEEbw}*gFn3k1DzRg-'
    'r6uni)Qo-?K`_)5-#AF>Clm~udKfGXRvTUQ<A2gc(OO9)McwCLBBEAt^0(g=J#^TG>3S!@ELfQgTrcmh'
    'p-A=e2`KUX{f-K@avSW)M`{oTw4uy}r{VmV*q7~0_F%Y_%?JD*3rJvEa|1LL+kNxZaKoASpchmyR~tz-'
    'X<*1Y<J}@So>G6OkwmjENq;Mc+ilX{ou%MOP6KIPeoGhME9GF*68NqJaFg<P<(eKoRDMnA3|s%uk2Bx1'
    'y%+;OtQbG3pZI{ce5PK6w@MXv9!}X!AH0<#;no$r_SY=y1-2PLaEl1|B2xAxtmPqN)Q7w-2v!utwt5$M'
    'bJmMQrDlb*K_i<5nnBzNV*O#*J>W9eb?a=}R~c!u@)5)fqV|VNItOp<lfo#GweQF#aNQJ_<Ey<&b%E^t'
    'W$k=}jA!?ipZ)k_J6ly}ztd@KQTQrycn)wgV6Q)egoql$?c8p=$!trU>3f%F^Ku?ufC!7w{mf%WTqN4x'
    'C_f}wW%g84c}f+Q@cqnO+Ss^mOsX`@KIxvjVqHz@w{j?`IR%rL_t`=j?0sHkx28c{T1IC%G1D}gRWrLH'
    '3XZhTMt3a<7ZI7P(Q__~+M?-{_G-QF(u&nZ`12D|Vp;dx>iKe;;nq=++?`_V&;Ff<^&_s(nu*rkC)UTt'
    'z#f^FZfd$Qw5^eA+JinJbfnW^PwP9b1wSm^HT1FBA5+uP`kJO&c)iyg_BXjtymXh?Af_`IT9&10J;&7s'
    '=Ab_w+hbh^sJ21u0W~yhJf;S5hd2>;G`47OWD<9vjr5_h3CzlS#5H=uWj&@u1D+C+Cw0#)a=A@e#e4*E'
    '{BcG>bOtsRW%FxRp<~C5g|-uOYKL<NQ`d5fI%RLZWkt`WL!?+fWumYuDvzX(?kA^d5;~;FJ)BA<#+f}2'
    'eP7mS_<BZufAs@9=4un)y9lPNlBwz^trnsgu~{~jKIq*3NInapZadrNS*UpqN-4tk-qR;EioHNoLl&uK'
    'M*&+&l5JKC&Mq0XQ9f;!O;?T%TXY;?IkLk%p*>69-o6@{e7PW1EYy<<w>lob>1e!GE!rS{9gz3nQ)9hU'
    '9+jEHKB_e3X7!TqDf1}yYn0%-iefrFnUV`SQTBONX7vN{-@%v;jqJHMtL5<u-(ubDzw?5)PGoiUmB)f}'
    'aO_j0fVO?<`OciySW*%LZ(zz>Pidtev;y<BouSqW|M`<#q_BgH#dJ!_!t9K{*%o?1@?I2G=VPo9Rl{zO'
    'x6`{74^2yl=7qzKWkY?@AXzf(UNEdW1W9cY?1c4VMuSpUo2_Z|l0*e_v}B)(8{r*EMnzdRE%jd75=Mre'
    ';)v2Goy2I$+m91yLQph;c!vBGVXTi$zTe(X2ufC`nNp(}`GVtGzU;IZ4T<~p7N}o3r_RfHIQ4=$Z8h#*'
    '_Tg5mcwJnw{FAo_b*-$sF|uxBV@dPEB$cVXR%gUv6-Xu6nAd8M=4HR~V&I=uv?$9oSFy}!+jAyquY1M^'
    '@f8N-F$~d`RxAG2{I-9O`dA25e3DU4mobZInaRRPNy%54(OG<9G5Z`mjQEIM78u5UqbX2URR6k02Vhp='
    'n%~Pvmc@VGZAsZC&NZG;FysAFXjYQ@Cr2AdkV`uiODm*ODLz@*@N)aJ!&Y4hSDbYi9L;8wVEc`n{mI^v'
    '3FL_vk!3he@~%u!k6ET_J9Hc0iSw><UZV+0YqbNw+nb-bY{q;+&W^oHIUL=<rmpmcl`s3Tqy5N4Yi^=#'
    '5B%kc^79O9F_~Y`xCVpq0c37zA#5{6^-rTV2h&w{yP>@8MfpR?ZcuUbwmf&|`aaR)?yU4y{aH)3(RXK}'
    '7kY$60hvXYA>Mb-*opPc!!!A^imeT@PKT=krQFJ~kODCu)Wa4u3_l`ma+1s^$)nspSSj{nlI~1dnn|#z'
    'l_uP!nhdr5lUqNCeUo3|HK-8pUGXeF-q?xwh--LnF`M}w&=GFF64`S~164UmdMa-T7ly$!M};|eWFBL8'
    'FO+XE1(1DVu=P!>*0QgdTFVpV_;(8u<EdO%`Hn=F_?xt(9*i-+uzm{&%!GFBp(8t-(O=W6q;}Jz+9T3g'
    'XkSj0*C#<dFzXNJMUT^N(e<jR@obsQ>1QR#Zp@dGp>EhZMA(frZYl)gBxo~E9x!y7KH9S68L%<ZI=Mh%'
    ';YT0y_o77`{YZczUcY+!V5HzpRZOg*TTACDnZHB((xEdyyuxEy*c=C2WQPm*-MRv{R%@>(p?kntvJa0`'
    '_NJPxvo;jQ3k4ADo!aB(nIcC}xp(i-WW)3@FFN8K8h@Xbx%-siTomd4#V?8rxeLX%HVBv|%+-_uV&qrM'
    'bDGG~44Gu9-S@XJUdUBhm4dqmjsQ~Eni)Ql1|;hR%B)RP2U5I(JdF1q_+dVkIc__`AOa4)l$s!cMsVC%'
    'kTECcN4vKv@t^4e7l!2n(kA2uXKIZ;-@2oGtBT+xFtHcBC%%W*awKtZ&f(l7s9PH*<40^WDBw!4Xjsoh'
    'DdSyBq_ZlolvR&aGM`c+ZFQBMn5Wf}F1f7;T3YOHw!z!qiEL%GxdY;qy7$T1%cq>!#>mHkv?MStpry__'
    'e`xech8OU15nbZwX!z$mcI6Um+=y2^dGFB=2gt)<S}7j5-djRtiCq*EP1ArccmQBH2E6U}H^hEd-xDb5'
    ';Dbi=X1y(CJ6TSfTqzQyh2l}NF?Gr9cWIag;UUf{4pT><2)mAasSsv~2z#XF{St&OEpnNclAo7YD`!vc'
    'hOU;=Cu_EJE_HO~y~9hKd{_dy^@>)dFqc<a{97DiZ3&Z;m!ziDxnAO&5rsA17OoZhapxj0IdVKN`5Z;N'
    'sD{B+LE}veK}MLF_!Ga$lz@Clm2F``;K>qnc>p)cyDdT9H!-<3r(suAD8bcqg_`<mGc~3B;Sbxc?5h$%'
    'e=7L7cXkGr55W|-xG=p>@+2!eR!&@G_Q#sg(t(_71b1z<HWZMp%*w2lFkW$c8objFXP0D7<>cu$T%@7d'
    '3KO4A35bm@dK+3t=Ka*7?0z1`o{dR&uI~lgw=rm?hdD3!NXH+^bmmiu7hFX>HJ*#`skDrfC|c0AAR+dn'
    'TVpBl97qSrUD_oBcC01}b@8)tObU^G?RdrA6v?-}H>*xC>TJCM4a^x|&xl3+<$SS-yr&K?$swyE!M20!'
    'TVeQ4#V)ZG)fOA+5xW*)f>wVY29zDwB8t>0B?0U(SONbC-`{$V%cZ6fO0wh_llhH~YK6YUi$0b7_(^h!'
    '2<$5M8+L<qr)v>gg=S#3Rs08aj^et@#BqVSk?erm@vp{Kf->whT*UP39R)v{)d}DWNmA)L4FVPzL+d1J'
    '9;{>(Ue~+q)1*;(Hx-3;Pz*_A(4jN*YkDQ;96#|O_?Xf&FPh4fNX7?o4h}S!e-nje)7_Kwi+O@hfme`;'
    'Dodsl_)rU(b@c*3-8>S~Upo?4V=v}&u)R)&h+3*H_DI~56%@MddJYd0yeW?oqjkbgKcp|^IM1x5*%zj<'
    'C0On_G&K1_Yt)r<-#$7j<mB~Fp#oa-PVr8BV(BjNdXM<9z(?EP$GX|Cmg669;vOFs#hm1eQ!>5fyK<IW'
    '&6KHW&{dY<DevA<uI(p(s#R>PSvR>kFL~Ea@}2m|4Y<fRI;v-k6VXjRr8A#g2{&1S?b=l&xxIJeZ11R`'
    ')V1uwtAzq*5xU%*DX^oRl+a@Iy9EwP0!JmF$3Lix8LMuecky|tmCvR=C`VJh!dG(3;I6F<`4Zg*`|6GY'
    'yIG?U;Y)nFA1K?jG$@w~-}Cl+(n<&aZh>e0VSv}SU>|%CfX$W=E-a(58p69P$Se9GHc^sSDK_|GGf2C1'
    'eXe!V#6{kn)Ja>4-frFgyd}BhT69Ti-1efEJpBVBCqGYTi&HNhlWsllrGDatI)MnS>VN@A@Ot;<<s^~D'
    'eJ(GTq!R6_yxfW+5UT6VqnI}VjU$ZEZ3{Dv?JC#HCF|~O={bo7!JD;PcVV{fxPGe)qg7^U_IqQpuCZ7P'
    'L3YVOx`r#-%Q0JbWwq|WXubP#$+b<^U0bYoSwOS4QL@Hd{WV=>rpm5=nJX=r11xF@E>A!f;9HuxTi?Je'
    'osuZGw0gIW7fLXe@5)xb=SAK&Fq999r_9^#V%?@^_(B>+(;!#aMMfPOX(i!se(#CDpbh&2d3Qj{#QCkj'
    '47FJ*f$SS~1=3@<D)}>#$Sqlmyi#?aA)=QZ!ZLQ{q3I5<(v%w9=FZx~=`6&i8*3Zg_8o0VUB?>sMz*2p'
    '?!X;egT7{1x}od6p5|DCo--H?d(<&4+IM<As#8nro4Ve&%zp0{ZthaUTg}i%Bb&H}Z9C@3A+%?@gW<40'
    'GDeO;hlXKO(;XSTu{$0ced3Os@z8L_x;di5q2XG$fnC}7wpKr7;WK0xkxB`*wOij7h$ORMD)P|efRKBk'
    'r&51K3_GIsOb%b|cn&7iM5zl)oHw)4y2{KaVCf_QM|Bo@kvb)__K!c}??K$@$Xne%5=P){13$|FpxQ*a'
    '1Db4}BvXnMl_AdP1!nd{EZwzcAKB)q{#Ha^B-)yQo2U6IlE2=D=2xB8*X|a%GKBD$1n)@%h6c9cqaWk0'
    '5_!L;HOiu|54f;OYb3_4e+fU@oo2uQ4wbeSIP@ckJhsQ^Z`W3Aj7B+Csx(+k=^Xs9dIuFZhNoEDyfE_E'
    't?)zT@wYE=J?)S6H3LJ8`ce4{w&m&v&xtR)3UEFD;41mxl6n`Hai_T@dalCu3e8^)ND&D{ordpeI}T+m'
    'lOwN_h07QK;yBN|fWydrr<rA5*H?l~$b;R9gWX7j)&1JIu6)dj;vOnf^0BSeRxAa1!0YWkQ1s>&!T2&+'
    'Ldgg~jaGL(pOmQ=wDYLyCYbuU*6Ap}RCJ)cM~~#=tr3(pp#+L^pUtW3eQam@(vhqdw$KWRRIdqmM@r#N'
    'bi%Gxf}BjwbvEL)I46x3)+Hql-umbOwt|oq7k8d`7hWvO){>whC2GUntX$5*CHS$m2fz*!Jat<%nZU}F'
    '=%i9dcx5W@K!If`v9OX7gmu}?4{dfR)Kvl+e+cLAu+PMYxffH6Hxhp8qSjtobuFB#jP(Y5{u`<RekRd{'
    'uaATG-aKSChR{EbY#Pv)Kn1i@yq}%E-w4>kaoj0&7B>Ap<ia?aMNO#uVs19DoMkLu)}Aw(%Lh6*6|!$i'
    'l1mj}B~?nld37u!1g|!;Umi&Tv~(SvjV(C>C7}&K<+#FcnpAGM`j~$z8RCKk0pFYi@!NZ%=<?fGYC*7s'
    '6HynwE=L!y(XY5uBxz~Q2S`O`1<+_%r#`|u5@iSGxDBd!qwV5lTLD=fS8R3@)sXEift_>Ye?T)Q2<KCP'
    '{(H)79XrI!&_I`*Bo6A*-JHIsFnVyI5QY1Lq7~PiMmF(jq<FC^b!9hKs;M2>SUO=yX@-}ee#HKr)W;p8'
    'zY;XLPNhh7N){mBB?kav9WykD5Jf8fi6qfX03e_HoD-*N^v;{@*N<uyQa(W@d?0g2rGc~GWI!Xj3hYZT'
    '0f9~1%|#V>x`o&--ku_Ar=iZ8K!xN?%0bJ@;J9&7^KAFqUNFf*x9Nmx0_N*ENX$KnCyh%%5!IcODQ!=^'
    ';5!yzsy%np?5xl3TVf#j)Yn+Fp1oObNFhs}fs2kR(&2p#e@(C2OF}KtoQ_gE0=$HIasj^kK4_HXJ;8pI'
    '`yI(*4Tt_B&+ex@6B;}A>~}P0r7}Wb0<P}5mgJ*YU~|;K#dIP)g-6>?eZ`tkIi|X)Czx=qPXd0t5;aGG'
    '*MF9JfXf{Dia`2^g^M37eKy;E@lkC#5Qj1GCruq})^+;}o6744WtWNao0{Nbzw;R^<OkeJzL2HubkU!!'
    '&k^d3&TZfUJjJv<yw%V~uCp;5`iuq_@nu`<bUp`Utz+eE*QKw6?al^<Q|)~c&g7$I<4AmjhLd!#d2??G'
    'aQfkX{V2fF;H=a6{(U9A9TZWin!Y^UA#Wr#431d4yoxS=1p`<v%qK~gz5-ZrIjKRox!Zh+#hBgY+X>kG'
    'dE6@4cYa1)J@t9v7%!WAZMUu=yytF=^0O_~b7Z>++<jZR#m4=FCf%)kY83MjWTZwVYY;w1)2UEthS0At'
    'L8uW`!76&-#Xa(YcyV3)yaI|+BcIY)J0L;G^+Z%#eU=W@UZU6Mfnzxbci?#jr>Q)qq}WJfVS(#rBKDay'
    '!mHqUDRPjk<=#lrqP+Nu5t0`@CV@?TpE}({3)T;krTT?M{CG>*ZbQL?a@Z;pAD?IZDp`;79yf+15!yV7'
    'Rz}cj2|K0b-BV)|Uk@KD&qF2jod>8?72BsISj@0RFZ+G25XA>IF|U7|$TX*VA1&pA!+Pvfmg;0*dcFgj'
    'I8oTP5-*UqjXU$OS#jq5&OOXLVFeP32BJJWL2&zG##$ie8^LyYmtZ={w{UJmFc;KV$;6hn(BuGp$wI9y'
    'puf6N11v@8C5Z@rgei&K<m3g5OY4urIW65<{~lA**W6dvb=T?j?Ve^*tv4Ll+Hg2FOgb8BrarQUL&qAs'
    'L)#`jd)ONdN4l$xY0oi<sk`QQWSX0$VlQ1)AN1Wmb#<z_nm*9&{%F{D2Xs6zhGUHy1Ng@sJJirMhYW3N'
    '*tdpcXxKg5Aw6qE1{+>gufC<8e9GGc<6R8c(WCjCT(#3|A1Aq<k-KNo>D0;hY4JAM>^f-`JZB!xo?=Ch'
    'BFH-AQJ=uJO159lv)?JEcaP}Wc&=sb*GcPV8U06!g%L=Q&X{ZOD~=bjyyM8e1fAg10|ngIBrT0N5lB`R'
    'nTcxb5vJLL>W{#Bo1-~U$Lwm&7MAbXO8J_8=F(1-<KHbvT(2EfY9J)gNDMz%I`Fc?JW*b=Hd0EBP<l%@'
    'v~x{k|I45BlzjB2i|JE5Dn&jqOi3_grWNPMWhuJ(`-QA@L8tzP;)~@B;8A6EzcUZ2BLfC^z&R8QI|-MP'
    ';|k!ud3zwkzbvfDO|};=XEM-T<qYLxVf#C>z(p~gVGy6K@nHh}mkI~1{7310@Lt{{_<vG|J)}&VUqy%('
    'ek{n9?SzPI!ta_4ARoY2qhiRv6zGvcw=9SzX3B?skbpVlyYWc8FX9QX88tL33@B^X9Oo*Y#RN{<md0gL'
    'SSRI4KFgo3ZNO3q9<aN9;x-al#Fyb5@7yV`yeXYWiVxl-o&aEi{26*0uTN^wn8W(cV>UcipJZ46)cO`q'
    'lEH0JKMXD+;0c8U3jGMau(<B=FtWoL?Pe+d+k+G(>3H!z5;&<V?|UxAYJ1IDJN%lJJR66>5bZ)G+E68P'
    'f$zY{lZo=e`YpBNEMg=XP||2%Qtreq-hU(+9$v8|7nF7I<T)O)Apl{!-US9ecppdUJ0t(bXbLBH=QeNS'
    '<?q9852W%YZFlv8I`R~9Le8K+%JeK22mWnBinTn1QvVED3&_Y8W|s{9NM#aI%|4W8z$7#*>ael~l#kPQ'
    '4|o8fX2Ic1GT#d`<65qaew?HOOP10u7_Lc3JlBW$Ma_$aE62Z}0UrCakTl+~y)S6Sd<2EX&<iM5Y>cY2'
    'oHJG*@rntV?IC7)bFwBbkPDtO_{ywi5?_Qk4^Vi*TvNc9?~&Zili^LFIfv1A>{J;slXDU9aFnCC3*S#d'
    '9K0L_o}SwN0!4p~O$ox_fv|pU;`?Cps!idmvN~gJV9S@O8UIQhn4c<1C>l`F13i~+(ZKkb$dPfYe<@@I'
    'hJ`F%X6!3+k|)ZOa3M|1=VDVSx8`D0A}poJ@vg;aeE#hc$zzGI!aO?4!y3FRfD}i(FG_{&CyP&41g!z>'
    'YDLU*d%z{E%38#9ff5%4EITnT9%;WQ9%-Y4(ye8_<xi|}G)Y#w=W-L1O<Va&6i!h7@CW|3kZth3_)VIt'
    'P$7E`lvzPF*EtF+^H$x<w@VEQSYfxQfdbV0-mqF-fLhY16~%lxB$*h3y~MI`fTG`fGhXel&aEn5cs0tM'
    'V#1_F{!he8(Rp(W#^Fy@Ly~2`>2f4DzRD(DvcN~l!HJk*R@1V^YA15y?@|_@lMq5c92CSuA{}a<U6%|V'
    'Nu{Rp!ma?}7r#&{ich40(01qkIJ->6<SNc&IX*9Vj?aT%C7$pjnTAo4G9`BZFoD}$Wio9KI5oEF<`|XD'
    'ErFLrHK!}cd)(Ut%SP$kD`H8~!_KqfT920!#4_U99xz%Xa!8KJfXcE;jPhz%0h5E|uN^P4fj2M?a>`E0'
    'stv;A=Dkw?!g_1n&NajKrJ@Ka++;_(LUevrCn}i=-J-W8O#n3D;8y98PnqGGhOrLH5seyX5)H*<V<(-o'
    '*oEaOOG*L|6JO2V_eF3P892L=z>mdQObP>QjdJvzaPeUSTr4e>CrQ%F<?<vHnpRqul*^dmE&=+hL!~NE'
    'qm?hl+)<iC^2;*kiUmlLcj+D+mJGl9X)c#EF|YBp&Jfxj>KC@HSV%?_cTW)_;9Vq%9MOJi$kI5dv<mK7'
    'NUL^&mbicchH$u;+cbJ8N_(JntbVj3mirM^U%?o;{l4M!Nzd(>WHhk#G3gC8+thWUjRu3U<65R^YDDk5'
    'J*%hnhPE^4_50(#WxDQo+}|`of9Vp&Sko=iCqsi+#?Tzu`cOAVJ;!y2L$hZOdZeep%!oAxk!R?ZVfT8&'
    'F`=fexds`HM;ilPdkv%Z9hjEfab%2Ae~jyH?IHHx(>d!mJW=*_RomaHZ$ecIp?a%pNgYPQAT?3V##m7W'
    'Y*O>ipjhNS=s!_hi6!{qj!sFiApU+=%J{yJRtO=IHEW!AAa5`jj*HRPffvghmJKYh3TO@@yie@N!K@gc'
    'rGn!4oI2Ru7l+?`*_Q=I7FSAI_x|rMAACn-Qq!LW0sQe_{`Y_SFaP}?|N4LbfB*Ks`{Td)7k~HH|Moxp'
    '&EMWT8u)XT%)DCc7s>pEF{>mqr;aZ&`KPq?fB&ES=YRUI{~ediUqtaPjbtpD{zVdhVaEbHo?V6?a-CMb'
    '7|B053i!Lf{y+ZsPygK?|F?hkr~m5z{9+;RTr8($kH3iKFN|3f%~{+cxeuHY%NG&-lZs;$BN*Ix{=2{Z'
    'mw)`5|M`oo-leP-McluL>Msmh5zoMr-WWSFe~CE%R0-iv|K@-E<G=b}xPboCzxvmI`q%%%m+14|$?L55'
    '#TSYFg;9$VJ8xDebn-=5|HL96nKg~^kAM1Ke38yOl+L_)&=<-4g)0kO`8Wwi=d5T|5hsQpE@_}#g^N1X'
    'rCau87)Dh6BJF=_L6krJi+}$g{-?j;q3*m<{{Q{o|Ll+d{NMilfBVn>^xynnfB#SZ(?9)Z|0`Dt|Ia`9'
    'kH2Vy6&j)L5cR3OBIWY>?e+EE%cIld=daGsUc5eie0+ZT;x}i?q4KG9G@CvA)(<VbNI>THB{t$*SFGJ0'
    'YA&U{A=L~ruuN)DI_R64u9@SWVd=v@e5yN|OQ@siJ>Aq@YFi`QvgyDc+SJ}4|8prxSR=%B`etuznof^6'
    'V}0xpvu6|2q`EdFw(S5cG9;#98-r2bFo@&WcHcD|VmTwSNp|w;{NS&7J;Qvp7T5D*b^|+)xW8J^`BjZ9'
    '`&Gbf_~jy;dsuYf%@Z%OL)hS}$Nb$ZUMjXJpjS_c=d=4h^(x-10+STI&Et_@<cuCk2j)c)c9*SN198>x'
    'e#pxEHHIsG|C>?SWSQ{fuP35DwL$It+6$Z_KzyeGc$eXa=qcl@s4*m7@^Xv7Nt_HCVjlqpxo0t_jjiSa'
    'e>qh6u6$2sj1s;jwJ!VIBoV&dA<WsF&d8iPXIS)+*W#;5clk1ZVw29`pTdgRwHZ;Dv(BRG%@o&fg$|Hv'
    '6i%svYPp7inHoxG_B`}`S)<|W2iQ0JT^qc>i(ty`#;JZ%=`@-V8-AH6`lurd9=<%c%wk(N)@ku(+flOn'
    'su=inK;FaHczJ5SbBmt2ThHTKDtgiqrY~IA_X2wSk)Z!55l<l>__IUKcZ^<TQX{?)J5N38J9!kbT2Ysw'
    '4?D5nRchT+Z~dGbo$5P!^#Mx-t2o?AFk8e&ix?!<%!|`NOj~8GQaW;%h%Yr-SW_?NZR%CN(vBJiXY6gD'
    'E^O^sgUEQFQa&!;Vpgu@uVLHqR(F)kc3kYvzGT#YvxsBf=d)-eVW(<9l8@UlseyLBpSg8#VvB%kqpK*U'
    '(~~K=pxYDgK1vF;r()Iq-(#ULUv;PrGAaW3q1?K`Q}IIJjvTbR@XvPRo~`!Iu%a7vgh#e@)$3N#y(<hV'
    'e?PqFhhj^0`2b}2kqx_%JND{!;neNMr`wH7cL!e9O-`2Ruz_6)>Q!dmv7^<JGS8%yNwRt=MeGZ;bL2M|'
    'DYm`Jd}Jx(VUHc0AW~$_z8-~fWi<<_7jCa8@J*IDK*GkWxo#p=Tc7me=qCHOB|PEo@%}-zXU$(F3P?T5'
    'qx}2b!iLtHeZJpD=ibl-nki{#i{(JI_~>(`6{WPFEB9FvQRVk|Qq^dstNf0KxVa5~mvkUC1Sd5Dx8nd@'
    'gYma}5`Jr4%fyZB;M-ls-XvnCZshGQ0&lHvz%2p}YG2S8BP_)zoN|plTDKn@p8d6m=QSG8yQ6rX#BiSE'
    'Xx?sud3O-YYdDm*K_u_`Hle)gVr=}C!-ZJXl+LlwQmi^6%%;X(3<_fFUIwiKO7>CnP<IZ?+V9AYJgcnj'
    'aC_<n-%;=4vc^e(X?9jq?=p(uv-y?GfHWw$uPO{T*rwF8Kfw@L`yIBN+&W~OQE(8(85p@c!wPP~f|97)'
    '_966_;tnbrc6s&_BcrP31VBFi#&hD!?J)y>f{U)gRc8|+mcnlYZP?Eg_j<+Vv(Gwp4jsArS=J*>t%m!1'
    'tOhHOPxGJhu?O;hadAN-mN+eI^lNoS9A>Ua;CBgg!q(c)$$RgDSuw9rSm$YzOYcs-<DcECj7Bs@qY7ik'
    '`r=O1MI+i`1>Z{DWC^NgXPRgCif1LtnpHbZXq|OSi2^bMXCU7GfVFf|t0p71y<k!dVRj@FFuoF1nLt&='
    '8{PB-8P67@?Y-n|+}v<-y|U}n3iv8v$Y1<I5ZNKC@4Y=aNm2C6x=zYS5-f(6ycun5FGzDT0ib`yo$z*m'
    '{2|E@yC3FP41%ofWr21U^Y5ghO&tBUrC7IW7(8Z8klUd<DaFYU<at*~qGn!zjJ9=-Se6L?C=JAYb(oI+'
    '3C4d<e2+B&m6SsUi+kclKrBFu000xO)jX7~y9u=NC;p`&OQ|4r*HQEFuhG8vX5nE_wV30Pi8sl~$|#M+'
    'c>vgs$J1GS#fFvSElA`2mRz|kL5>y}Kk17ikL&Y%ag;DcKJkhNGi3~)XS=1;t^-*Hla1}A{Fju+`hoY>'
    'u;rE@rE#-_lg*v+@{O!4O_A>~#+n%<whzCG45t12V>;mLX*fS7;I{~*cNLTdKmMp<>o=4InJ$(W*h-H!'
    'N~dJ0Zaz>7uGQ92`@Bn5iuedfrPGdm+Yjw`yNK!o<=iV1Qj)IRT|`PYcS%;xyWy?Xtd$)ZC#2qy!c}*|'
    'RL%2L1E!f2m38+HViWEFYv`7QgU%IJWMX?ITyZO$wb_;KW3YLu=+yDhQo%xzAj+4{<iY-qJy@D|5u60_'
    'F4-_{6e&S&7{);uQ;7$^O<tV3Sb*7y#<r~Epu2X%8Zgjha#s~|EyZi!l<$YU&G>Iiu=3oAT$olc@I3q='
    'fpuH;NnYgZT@<f9A=!t4isywix)difMP6N(zb8${O3#?Od7bwlB*Kp&bL1_VQZ~xMHDw;ZtRu20CL&TU'
    '2UcS77BIMM_rkjv+^v<mhJ)}(KiIjI7N<()!0M{)&A~&Mk@!-Y3A$~H>=GZ}l2>GHmmD^cZw~F;8j@`c'
    'H7`V0nL={BjfUbB61*5Z0DqrGb#sbb+~NLIxU!m@#s1+B+ZR&M)OTW}!pPTBd<n6Xlw~sOg!sO=uDyLa'
    '96Q7h;@stka?%GysM0(Ncs%f2tl)m(lL&K&9U9qlkKHzyDCKJj|37>0+U2&5EQ)@gU%~j~PD^)p%X~lD'
    'JL7R|C-KR{p0<-&=S;G+KmhF4wpvs~$###&|NT?}AVpG?#0S*Q?6rH%#N85E0ICZ0LZM0w{@o0dp|nKW'
    'a;>9~iYf+JLtDsld(!;FY=Q9;hN16;%(zDlQ~DdjB7Mg!f+<C=%2TppIKm~a=iE@&Ir<Z7&xI4M;m+RP'
    'Uo1jb(w_Yr$~NFAM8Maj&&RC-g3|Yy{Q9e)&Ww$<Ig6)>IepS{WA+}UqkiFdOg8R%aa%bFpY<G6LP`Xf'
    'stE%y_nS9;hr3s?{F$Wk>4frUkjW<($tRG=+Dy<>%j3Zo>%)h}i{iu`w#<UwtkOlg$>w;}vY_*g5E=Oq'
    '{YAQ%-wixV<e4E(n?UNUQ-drFv1#O0<jHUyTGS)LG?Pb0HJ@Nlw&`b$?pH#Nm2|4c<fl?fR_`QM;|x^S'
    'qx=GfP-Ktt1Wfsd=6tBi8uO$W;6=)1Wr}>9u|bdrH61ooYFc92S~)dO*MUQIkm?w9_8XYEHshJ7xAW*E'
    'HG}gXb<zqz%f)0wuY}P8EH{j>4X~dT(4TThfR>$lKb3){Y4L|}pszO|yPGR12xdlWa7(Mg*y%g0y1caF'
    '>&<GRBg5bxrTr;|{b!N&8jGC>DOgG_D9)E;Q7s*TYssl!RFi`yn{^USz}LW_d4@%o<|ApL;}>I@mfv&W'
    '3Y!jeUn*qW$!`)f{-aQ_rmyR{j#{!A4=LtHHK$bgq#D<EN?qNgs%0@KrK)vRhAOLR39|&hE;cH<w&%e5'
    'RrLL7==)aC8Y4LOs-7FP^B`|br-fZ;J8jl92FHF^K8KXZC$*-eeL%@V#te)qu0LaCYsABPM&ELDn}l~3'
    '^Xu7Sq{@U<?*0rPt?KIuq-a<|p+WHGzyU9C_)v@|B5(=<Uf>Gj9Lse!k{B$CtJQBz^$z~momL$-KTCCa'
    'iXy;_#*0Axow7{x#mg-#XsjuZOzyANi0@z7B{#zriyFI<QNwBqHXUUDwNj*nF-eF?k&Jr+$M@Wzo7GCB'
    'uc)t@H0{9AG`rBKK0zFR{2vD0T}>`ItGDElg+_d}N>}55=QQMj!3V8=vmV>#1g1^Rve{mt)5LF|%W^u?'
    'bGV9?6Gb_auc~ztv;Z%RvbqZ{?K3RSkdHt7u(@tRX)v0!*c<n3ZZrt<FEHwcEGaH|&XFUFZE$YX<nXz!'
    'E2VYq(NK!x53&!c+@mifP{#-skI8Oibnjekj!UDApWdi1qxF>Gj8j-)_iBWlog_*!)C6nTw51)|W@l;P'
    '9PK*s-gXwy@qnPwGA3pQOQR8JV<=fF@-UtYOH$m=mnx^{XnT#+f8)zMpJe-8FjLQ-!j5}btno@-4mi|m'
    '*EYk5Ta0;$YthhhEz1pTLK7ZRl9-7Va?kQ3hcTPNCr)HC#?8QW&4|J;R?x;c-s!b#G0v?ZN-WRxi0dYn'
    '6L^G%zDWZfcrFa<vcPqS=a_av{U|VlB<4=+*vuoQ9k&{EZ?j!tO>e`Yg+;x-!K^pDeALilsei}h?U;ET'
    'yaM`YO|CDEAL}2#A=mkwdJkG!%ntmk^u3n#C|hcpSJU5Vgtd#=-h(z=CDXA4I$Phpt}Wv!eD+hy`2L0T'
    '9v3iBg|2xiPcUu@|GpyE{NRGljpdN6ZR704V!cb<LhzL5p<`_e036?q2pI8~##Ksg<w#H9Z;d=wO#de_'
    '+?F<-0syrL!2L>_&mnA1Cu=^3sL?8Es=E{SVAe&>3|PfKwn?XInBO$5;@-rierfr6gynt6%KH_S`z2+k'
    'li<ox@TUQK;^D)G#!GRHJ(+#LP?w7KWX277$Bjj5<dui-3`W-E5eAzU=^8U2zy<EFF=SF#wh?K}$!4D4'
    'oSzI>%yJXYXVd_niZ3$oe2ls|Kj0K%+jHoaEH-40Tye!Q%N~>Ze+EYNUGT9?<C7ly5HoasEJlJ&*2I>N'
    '!L9rB-_5=TEQ&{rC$C-z-?dsZy8pnR2G}D5&OtuY7CXTXJLv}dLn-`YJUH-F?WAJlo~6hi(r!MH3_1HW'
    'NKx0~b?fvkUtr?mVm3d=@)zQ|PUFotxtQLPufW1)fo&tPInW>`-U)YNJXX$M1I(fG8v4GHa(&Ep4N9@m'
    'ZXay8;Lld#ycU81M9$+02y)mFuT@5{Iz2%tF&^l>e+EX^&gUm!^FK&^xH^xw*S8u(c9Xsxj!<z^<-a6f'
    'g9*hmVMK|1NX!Hw3j?@fxm<ygC=wxbWu&STL3N@t8c*b2LmyR)NanecSKDCd1)oz|C;eo_zya0ns%9PF'
    'LW>W+G$&h59h3|J%!m@{()iLE|H1a*>2=KsRm}kIQHOA_TefF#viAGy8_w5<&fy%#al<eOP1AB*lP6B('
    '+ot6^zGH`GVA|A+xf$C|5O9+ue$2zrVk8JX&$H|>uv%)loufG7aTp{{9G_CxiMSn^fyLd#3>}BSAf6Wn'
    '#PUtTZ2}(z%yYwpC$Zy)t_M?WJMP}oxcU!h+S(10-g(ht;CiKkD)61|wnOYLLuUt-W^k`1AC?z{_jj@f'
    ';~~bCvA=ha=wE<a?B!B6mr;`c1f$`PtPe1Ha7&iYU|p}kPJw;1P8qp-FdoPW(vjSP9Z9&_NnZZZRxMtP'
    'bhyh}6Uy$FO1CK%%{vL9B<TOHw8{~8n#BzlpVj$dq;H<09=xCGqWf2O0&ZyR^_{KBN-*TWPTz9aFHvMa'
    'TY)Ox0&Z0cMO_INFP(x}>iZg#y^7%mZt8T&7h9ks33c54a{qoG{WKQD{TdK@?T33aAI`dHiQ&5ZM5_Gk'
    'J~YEUEAdX0(W1Xkr@sGy^wFWX@744^fsycsu@Me6-TZ?hO_pl@L*h+4#FJZAe+0wop6#kbW>qN~g-4~T'
    '$q`nK%nn7OtjP9h=*E_7T6RF=Fmb8x5yC@@2af5nB!+)tE3vJ}^&;-Zre~T~OnAcGz-tqU+KED$mLHjk'
    '6DEPnxamhB<2-a}$n21W#C9zw4m{?Yj_bPAi>RL@jM_GfXcT*P9JU#=F#^>;O8D0w$!zh20!oc+z1q;V'
    'QA6^jmi94tnN5cIFAcJ|6N5beu;i;5Ur??R76x|NdA-J?g>s9&708v9=+04E)Rp+~H&KaA`-tKa#-$++'
    '0v>CJj`w49m5W1oamwyA_aS{vSLuAN3mX3XK>m5xs$+!ZkB788?R{_M<Xh<UJE-7@`RpBkwk;cbX^cjq'
    'kIj>XSjqUYhFh}txlvELPfxo|_d*8}JzuQFh07AQe#k!_*qvOfT+k{OhDimj-BWcpC0GF+C%o9r6Ls_S'
    'xhjR-yI^mnA&fkcp1ddXxAi*MeFu=%|DoBdV%mCJi3(@AVh=x;MG;5zW;SOlK43``a7FOO=n1B*zbV`v'
    '%&Qve8kaEG{cJ=E>a=WgdrRuV?6v%Gr1XMjT2xgh*7MfcD!o6Y?^isWS~{FwINY;r7%mz#ONRRw4Ethy'
    'g-wE$YhHpcKgvy2`EPF?y&+k}9Ie@>Dwe3TRa{v%Eisq{B*&p%JnMg3e~X?fMD3H#BQ$mL;{;A2C{BTR'
    'f&2ntdCK7ZGSqpE^u0w!6^wqt@kzhzEcd*a#GropinCX%^mev@mHZpaJ|y)71C5&HpFSE4wX!~sk=4b<'
    '(&mL}$|L_YSrUdG<48w&zsaI#$@2!ga_;3tU8ebDO|rKmY%Q7>lN0-3eTU(A3`2~x^)>6f--fPHXF+9!'
    'ijO){qs3-XeLQ51pHgXeoy|P3l3Zy#jQA)jD-2_~^I}k}WH+Gko~lZP*VK|pzAX9g=dD_KigS%;SQBbq'
    '3(abB|MX}B4RYyT#nK+BREtlFg8em1ZruOm@NB4rtIj%IJXtO|!GhN%`%`?RbC74VjO>oX@=tXR_4I};'
    'uK6fUPELvGxiQt%*RJXStoVAi;x7_0W4R!9&)%h;9eo0#?)8R^|Dne{(PJxGOA{T<z+b*JzT9GMO;*=@'
    'Jz#@L06Ixp3ESMF`sdk54s&kYFG0_RlT!auvl~=}KGNszeEK8t<NaCbx(kC3wbAd-M6VRC&K6{u-K1E$'
    'db^!O(P})CudCQUPI>80j)k7;uBD(JR;3mAQMb)6^ZDf0&-(`}6+JEs%G9OVSYHuet?rVB@~Qpa?ENBE'
    '(|H3tV~9qBGGRJ1);HWBbHp`Pyjd>iGvFg6zLC)t=ZlH)Vr?w=JHF~mV*rEc{)TYw$O^_J2Ff>>LWcLc'
    '`*$YX^%V<i`O?6Sdut-<EPqF`8~jaMQV+(MU&eT2ek-&GgBE=^zUOy&XTryWA@XHPZ}QqW!@-q%AIR=>'
    '!?I<zPXBB%TaS+BON}-4pUA^*+y1fnCmOVwWDfvc=Z}#tc?R1Ud7WG%v&f^5)jKYCGXFqeL;U>an~QK;'
    'zrD9~z9lPBc$@L%JiWtXSs)HGKp~_X_&vUZZ9TlNXwLV5vz!i(WfPjocAbMq5qqIBg!p85JH^tbC^1y&'
    ')6ZzKVS3msdr}m1Q9UI;ZgH-zcl`O!)rEWx#da_VSR~91lmQCz8{s)!>e38b$pS3!^Up7yX>eE&UMf{t'
    'lY;vLI0DFB2WI$K+aTLYe8Sp9b)dy7D39?@bq~@Aca&ie0fFzNCTQRhgu7O3EZO<-{o9oIpW6*CY;i3e'
    '!(C_UfIjbCdho1?;dC^|Ep?~W?QpgU>JA<=RULQpaWz;pqPmb4c%L-#S(8_a%I)0P`ji@Z>)f~(^R!vg'
    '<wf2=ODp<r35*{ObiNVX$(d6t?envjk0r4!n}g{}0+Rw->#WO%Mjv%}0k1aM4MIo5zvQtSH(=wUI{>c!'
    'yBUA~NOjdQX6wFX(a&UWTud}A0>0n@fZ>RLz!zT=`gXV{P}9MWPNFx5kyLe7sHRQs6$#ox@hI7Zx|H_2'
    'HcW%?P-hii6^=l4>>=`{L73$t?D3@Rm*D8yB9~<;`R^sx>e-X`!&kfMleo)t$S7IiQAAzqJNc{HpuJbL'
    'FNL|j((2#p5Ub~ylD%~IRLeJ_vgSw1wG#h)c9EAKIZkUnN7XJGU~o0?_^E}UV9c%fQ@`nyfD+_Hkgy`~'
    'bP2lh07vCr?^c3;EHQa7r{TW1P=l+PC^hv(J2hqe>tB6W_C<}MKUVzQ&vph@4#8AOT$$cSeUeoiE9Wk<'
    '_~Srm>5-mm1fSb#JyAfmF)OoH{iBppp587~ypgc20`e35U38DEKK&zE-|Reh#j|v?0%AS<A*H|_|HQcM'
    '<O9vbVOgf0{Pd?M&z?PhHhul`t5+|t-b`OTdGp<CAi?PD4QznyAzs>BfuZ&EhSRs%!!>+3mGy9@vNFpw'
    'FSRzsGj8mPFj?MVx@iGm#pQ41o?UqpwJY_GctS0q>D_G|?;|g=lx7d*1TW+SFY*aq6cfB<je{UkuhPvL'
    'WZ7~~_ReV+A$U3q|A99F3HWM`0x=u>_CkDnp}wt+zYB1SQvsP@0}rjl{y@m%KfQW#_57zd(>E`tPoKPb'
    '{_V@F|1*8|{D(JBFe~Ka*%H_RYp9$hoM0E2X^h6mRI$U^xn#Jf^G*CM;$wjwT+0<_e#2zp((MH5J6@dl'
    'ejJ5P;8B<Pk(DF~3r)|8BQs7c*GsrZ;SoQy7>$_6T;HZFiYN~wE|QOhOPnqc-iqJCxZ<`%+sT%B2dA2o'
    'rB<b;K65K@Sr9swnfRRfw&^)62`LXuLO7+C8QVd^nD4<O+#w;213NYo9#N0lELH`ZOEb^-T7D#2SK}vM'
    ';s;S2IF@6_fTW0U7?4D6<hz{2UKm>zbpprnSWE(D63S`hny%#mf(Q*lO<0h1bLz_nYFPpI5{FTwOqBRm'
    ';*lVZLzssZ*_IvJFqOnIJ<nn`;|cMo!(%fFz1R!Po#ij*GpfibQWN0AQ2muIi$8MYREqe_K%lMG#%rAM'
    '&o2(h*h9hf1`%7w$$wUi5B%gWEh>~W79pv(96I(so-ou~co)eDM@x$oAY`HTyx9!A_p0*2cj+xJs{glv'
    'mo8q<t`{%1<xYM{XKdVZLWmPqDVb7WrR*Le*wWv}pf(i#kk!3lQafEEkFT-;+_stLWmE6YV`W#4fX!=`'
    '9zXorUlXR%xVyIQtLnGCFi`YOA23VN$Ge<gQ@cj8y(rRldmq@{r`p_danBd;W~)?GQW^dF>m;Lm!C!%$'
    '&&SoH)8g|Z0Q(Dz;j%)rs2D0KP9iAu%86t9IX5Q(?p{-K2>e%FU7W+q*9=ZHzGy8iPA<|kNVL`ht#)O%'
    'ekr#BM0S(D&t$`pY=CH0n;*23oJ?<(qyV8t!j6yqXO#2mxA;M6ABfHM?Xe^NeNe%<Uy>DPD$5k5<I!xF'
    'N~8k?i(2Dr_)leO!n6G@PwPHnRPNPXS_rL+&br8~ksjK~adv#;)qfi6(t<Nh`Av!)Pm9X5U(XieW~qp|'
    'e^df)@|NGdPgl(Nbl}_sy}L^T{`0+jcs!mU$QO&{X8mNdhP5qcYY|8hS8OIC$@}P*X!@CCoA`FN{(;1N'
    'j`e|YJ>v;zU-2=_`VGn6!auSbm1?U#Ha;DUYPGBv)LdIv;pai;<;a>Wm?2r+E$YJd9G8f6kZawk=9@h@'
    'NRUctmN}@8i8B!=0$8eOK4Bbl<um?Z+!Hfmda4-6jHZj1i}~GnTd4f+Gq%3DG+g)GXj8WQa8>f%rFTO1'
    '_Rh3rk0&vqZ)K6`Qhn)3ie&-UcO!FRhU0T%cBmNC*%iKx`k1cC;u<hO(-p{pE3jTSnW!w-X?}Teo>J9l'
    '@tdffe2AY9iskzk1G=Tay$XR-%Yefo0ISa^2_PogX7g9J_}*cA@BMq)`WkossW<+xeXnoZx6uEsWIEO`'
    '_^Dn2Vmq5Pe$Y<RPBL_ZMzc(LSD60)Wm&C_kB1QRpQg@&BT4;BC5+B1F{<tF=d~cyAsJqM5>dVYS#|gx'
    '^$rO|3kx~V5x(A9?6;y%J0eyp{Rn$>TriHZSVt|De7Vv^*<+LzNlOUjG8Q{-=cBr-i**4hpTFW#=Zqh<'
    'AQ?JTlk&N(yp)PZx@wr?lRf&tUokfJ^=5{uv35h?`WmA!=^|@e3b}j`|3zMPtZ1j)mS?^bRgK#}pDX?H'
    'o-QtTtKJ(oz%!^I#%-*LHp*hCOwlA#s`rbVDmFGngF3*YGByZ+>T$4%`f8M5A@Tg%mq${ob_S5$arTc='
    'UeMFQBi@V9t;yW;9=1pElY{y}Zv4yo2j`U!TFpv6IA~TN+=`PDi6%*z$t_ueIK&=m;?CP_(VBVp{-}({'
    '(vCQ9h)JFsyXla7$8C&|w$43lH|=Q?GYh<p(DuqvG#)Yzm`SY^`q^i~X?Gs0ON8@X9LifNS$U*U`IWJx'
    '<lcdMk+_2a)YkslS9@z98Fxw6NSWheqCj~1evyr;(ssaRX*^Dl7fm)xG;^LdoQI4~fbWw1)*0phmPl5H'
    '={;e&l@T@ArY{@hrMh4>L>A@14lcgOIOQYa(+yHJ2634Du1Ra5j|O@E(#Her(VEK!a#2ex?Df(f9XmGN'
    '?_ZtiAWwJU(Z@xsd3!BK+L0}C!8_ME>Q_`m*>8C(?NSb?gOZ<G9vYR87uCVj-edNOx|?iFDpgMMtnMB|'
    '?o9&vXtWa5k2{F^?T`kH`CBgx<t~V-J<)282ku<#PI8Gt4HerYk$FsgW?48b_b|<Tuk@YgJz-N-6>B?7'
    'k-A?Enzs=+2U9>E9W)Ob4(VD9I6xhALd8MZ-3BwFU>7%*<eH1ZJ0ki5{{>4!T>53R702|lyK_~cix><W'
    'k&04VLLPyb`F+E)^`zZsuiwwsRNN`fHmihC*!A+ZO$K~6pJT8-djz9oe7(kfR!jh&e>Zz4o<|M<5N(ER'
    '3<6b%`q&sXFu>zxrn!^_Ra=A=I)|A0>Z#>GAG74uDP_0S&9JMtHl5h8@|iZ85bKHdj+nK!BX)qIM0t_?'
    '#5u?n8Cp<&@I5GRjltuydx<)B3`}>7OAiW5x6F3YccN0C+}18>oL`%ue=Ya<<JN?GfmwB<w^)jAcS!a8'
    '?t$R`L38gAP=r~rsHViRVY{V^=84~~W^6>$`Q{dx^dI==i#5L;O$Z}P-1K<JJG<T7UK*C|jmN*0n=0BJ'
    'PWrw{SI-H(8Ep|fE?F5JkK*#9^sdP)xGNWOPf0=lNc>rlK<J75kI9TZ>VN1bLzDT@e%FZ#wuG%7gMh!?'
    'Zt)4$-YZVu$p>}%4jw>)PQYE|5Z-miZPP|{#WM8lrl!rLtmxK)XYWI=R_Qh9&P?{y+fG%P&JPacCtR1('
    'bPJZ*zSstbGMv>QB)T5mv=t?tqk3OdBdKLY)ISt=>>QxIvewD1rxt*^<X;c*ceei!X+MGYpEHbT<yc{V'
    '{ra<>Cr2k0%)R9DiN$gYL#LYbP|M8w$`H2)2WLK19LwtU_?^&Pbwc8bK)IxPDM<I|VD>N;i0173*@DT}'
    'JI=CZ^@w<d8h31v><%7jo1alh^2UM*MF_sV%C5pFfp}D-U@7D!i_-VIB$xjvGa6nir<qT1_|al}RjPh@'
    '3MR6XBENsY3TPPw(`I^0anw-Q_S_Jp#ljR@oE4r*`|>yyZ)!cGZ+Y375{X5ks^myitu4BziN9Lec}L3d'
    '@1%K%EvstnOWR%zxn1U{wSg(oS6NLit>s$Jjiz<g@z){;OLDB3{1B!s>gE6OR=8cwk!oS>IlP-pE0R7t'
    '$S>rm-#79yp41L)%>7|nrF*dQ9&}1am9k%>v_OANdVPVOItnjwYK1J+-AL}Ohx(|YmeB4&xpdPloecZ?'
    '3dFbHwTCyYEN|1cx<!6#`Rh#vJ1NVavl*bUWu*^4h(piz96NS>kNP%E2=^1;4|!rTKPE}wS&Z87Ya9fo'
    '<=b8o`JNYB7N@pP&Eu6moPfJY><6ajdjNt2c4ASBFq2!<i)}((k|fmed_VFm*NXxgnn7eTmxqZHx$I0Q'
    'E}H9oM7HTMPA#8>)QW8Ggf?+~pT|j<Sd8(2Mh;9jvF(5nmnNZ0c<B4ovI%36<+iE!;g{=u1l4*Uy~zD?'
    '$z^Gqjs$mXKL|qVaK}$#tYktWX8M6oJr+7F@+~{^oFsNVN?Z~+wiQ_xpv8}Ehejc9L2zyn%W+xkIG)FS'
    'hnjwv(AZ59kHxV^Vj8f3P}6k7kouk*vWS?T>o^e)5zA+KvC&L&8hEB3S=5b)pKxGuD@Z7bB4F$=28M?T'
    '#<7#QHfMkv-|;Qq^{GREm0jNr!Zsv#%Ov*(ko?su#U39&rHqRkKTlWba!<`6i#ybH-Nf}xASVzxuw4RN'
    '%*~jYrfr+9<9lXcSqZb9zy-3nzzs<f1!m|alxe6r)Ra!#k~t|bofkwd;Mu202H=%|n2Aq9J0^kYaF^SZ'
    'u^66V4lod7Zs3rZg@GSAEIH1cSbWI?G6$XwtF=s*yJiggJ&7HYc`=RrID%bo2R>|e-;Y5YCY&?Zw5b`y'
    'o~scPpRe|iRc1_Uf9;`a^66}S_j0LDuSO$zEBoBY|9!Domr7r>DUWj`%cKK{O6EtK_r!u=6+5*siX|L_'
    'B64i<9QhqE=f@Uz-Z=I1R-VwBT<4V-z-V~z0AK-WuF^TLeVnDM^_x5NhhB&xCssT7-Ki~Y?DHJ0f8`n8'
    '_Jn!tAMF6@TOJ}!WeUPqhPbOgLW0c5{1@co{MN$J^A6q2J)F0Dvi8nvl`Nx<?{ye%=gvc=08R@4Lw4e4'
    '*@$QRZ=sYUkLS&KRK>UZ5Vv>O%1&!Dy_1NEdzBKsg+x~w(IWUhy(J&;)aM|qiF)YO3RJGT_9JmI`qIRc'
    '_{Wa{<KuSH4F-93VD{T8QShC#FT~@ui(BoA5r_)amFV8~k4Kenw~?{x2kI$7+k+8g@x<U@8J-WtDZA@@'
    '33GcrahteuG)8tm#J^YCpN{lL2;4Yuah(5EU8+9XeXcSE`N82>U^1ymTM-Vcd@?W!)R7$za%0B=Kd&(I'
    'y=q9ZxI@t{0->U;+?PTWmJU$I-Lp`dQaZ?d{$M--WitY4|9G-UTP8-;f11z3YX_`fn(Am3$CHYO%wc;?'
    'Kq2&~Wz+eE_O&XuROpP2rj)Tgi8MuGhf1cw3zVW-V5gOJdib?usPbe`TxAb>@Kas{<5o&C5tv<1)+r-*'
    'BJEAG@Aj*a{BGR6{>^E2$%!_}XWAoshkf|a_@48nK^6x8fZ>GM8m&t_l@&SK3VX)w47LWA)?cN!B5!;F'
    'VsP(hMNapD1nvh1ri6uO#3-8#=$>uo@lf!}!zV%?-I6<lifd!CQPnM3Y{*=uufxC(y5d6RGv_BvA`hj`'
    'Gv~$^rE_Xbl_9f5HhO=<SN!r&vWy^-Xu7rq|7qO&w)kkD)PT+PA9c2QVEnINe;sWH9zPflxrSZkz7p6z'
    'K)W(+*XK2h^<z@KYwqHy^B8v-q*D@OHIr&!LgOJRdPM2<<kn7jNz~9i#!`}_Zi@EZ+`9#&1mp+uwj%1X'
    '+DN4$U2V#84cYr$Fe+z#FH&KLH<dT>=RY^)73ttuj*vbJqpFclC^)-3+s|m!Z!@+(SQp)5u+_)YO|}M~'
    'Zl%hzzDbueDw>__Ie;TR4+4iX8WHYAwn<!WC9!Q24?ZQK%@S%SW)xX0aRc9?zR$ym1fCgML1=S2@Bpru'
    '_qIhz-Y8{Xn-V<Uw5jFTW<sgY;eWC3#kL;>EOFw*buG`NzGs^ewJj$$qaa9ZSOv2Z&$XDNW5%GpK*4f6'
    'yM3CbD~4sxTOVn|Wa5DEz>6Z+;YplCq36&fN-XZvz&4rfQ8%)PZCWmmLO+ODV7ow)7*-aB^!TYEJeqLZ'
    ';WP+LfN92l5L(o=V~2RLXWGOKJ&%M=<i^DHiOXUy^a9SA=R0v6#Cnm@d~nD^Zo7e-m|<YLNo@Ll;xNYx'
    '6Yhl$i$h|XFsGP?1gJ_9o4dsKSQMHpO8kJ(HV21Z`QR|>d7>@WSTFnElGHKt<A9SyEXnlk#Ev{hNPzhZ'
    'PRLDex>n-AjsljAFuMd>)wm99H{x5&YLmU-Qa=FlMNaJTI3_mdG)!REx_(Ha*z#deH;&vS^drY-zQY2~'
    'b3!ljTow_+&NQLn^PLVmWg<I=PlshAg>t8C(YjG&V_q6>s#%$`-DlBP(YWRdm9%lFh>~$8!A(k!V@E>y'
    'p#UvhCh-e=v73T-JoU1)idueRdC>p(%CHUtI~td`2Yj6pT{^LKsA1fpZYQc^%F7ts{&&ZkVI27C;lqcb'
    'iu*;1frR4X&GxD}hBwj$FY3yu4jSc~))R4WzIf%xX!7nn)=e;oO!|8$LI?6l44r`_zl8%sU$4kworxYP'
    'GMyRAqY-KR9lG=WSA`jza;Y;+PBl;_bA!%FmhCSka?~hO!1!WwYlvInm&WtoH)Ks@DIJRU#AghPrOoq-'
    'e6q&FxzV<Ah8#ilvr)BAz9XO(#1JivMg?KpZw9Z)zl<@FYHK@pgHzg<-Cm@{U4~XC>$SJZW_^PbMjq`2'
    'KnA^@02;11ax;2|KfhS4eYXXiT^_2`muc$Z)84AjDPw%KLmD;0_>q!TUsbaD+ZF~W5WjuDe6{3J6}jby'
    'o|M06IovLyw-9%~yN^Obm2ISo0ai9^yTU2F+{QvRj24@+$Lmd9z<Yq%>Y7#{T4G9#FapDHtf3*=LC{Mn'
    'IaOH=V}cU1L!lm39Ocz8C}m<k?(kj{6}!AIONg|r;#GdJYz4LJ-&C2lEF{)$zJDzl885CEDT<LC*n3Xi'
    's`gD%5RMup;gBH^Iu--G6!jne6VqPKji1nn_{-yVEGHy2NaJJ7&p18_nj43EtZJ?uDg1T>BpN)=g)xze'
    '6~emavxKi_x7=8RX_L(a3G=c)>6~p#|6nD4I^T#O`ICoVKYTK2G1ygJ5XgAT`7$e256Z|bzmVOS3sVhm'
    '!GNi?+ALA*BMmcgRs?g|-112W6S!8Or-=*Bn|I5$u-wsJ-<A6!>SA<b_wIK0i;9Ne0@T0$C6g>_6_ViV'
    '+9&ygYVX1W>bJJ)zG3e^s_~rsJHPX#wri_SdVAORardfiS$5_^vvovM6)vj)(R5QuWvd8tKerr8oy1`^'
    'ZGr5RyQ+Ths6xq{ka~2etj~t!;id-NtX43pQZOZNw)K^|tpQ)VOV_?Or+Pu5@vD4N=>9ftqS7-1F@l0g'
    'boa`=N6u#JOjJt)Ndz(~pGuiJ=f)xhs~^a{exI)1w)Fez1lUs}zKJ60>&G3aBKhT9l39TqpEng+s}ilv'
    'UCa{6@`)=eMGbVc{8_~~-2Oh+$lpyBx2JjKj7y`ayWNH1cQ$Udw!bPTpGvwRkIGLp@aPlp&yh=I(nMb1'
    '<#v;;^NN4q4Pg@@!Lxa+1h<Rv{ss(l15i>pRb9B0YUfM^Wm0ne2C?9NdMK{f&s2ICiQWhE{FQ-A1ZYQR'
    'Qr_XNET~q8uX$O!)@=uJZ>xw39X^QEvid`Z3Pc03lUF=CDOyy(?T>|+%C+en`U%jm6Wu=Fnw0r<gjz|X'
    '^ZgbFVy#y=yKKFyN~!JJ5378)Csf)DnDT~cc5{A_%rTF{$mU=!$a5JCD{pXh;s*N7DqW<T%s?xmO_|iK'
    'wOvf|QDN=oIYHf)2`{SRh5ry9GfJj&={!pm|JJ_L72}C0aE&k?Pq36yc9RzdFDBeR#c?l(Z0Ucl#@Z=+'
    '^_A+2RppOCydhSYcFKn+YRF{$i^%LN`__yWNj_<(Z1+)t{PQDu`1{I-^{5iIdv8Hu0=LQ{w^vYYgMTBk'
    'VGOcbfrmd6p@EIarAapPVF{|u)2e%yb9G5U;;s5=+ZuPOSPslykwh3I&sVFoTdxj4PZ<CPJh0$KCgcj('
    'I`3vEF*3Y$^2h*Yf&p`H<h?k&0gGzVanc|Eo3dY>&Pn+`%(D9FJ=Zc+K@^3W_L{!k3!T(^RZvg2<jPOD'
    'J6JUhMDIbwN>r&FaB5kdXQ#gY$Hth@pwpXf>1uyNT+EWY$p@M;zFejM^>8VRMogCR2mJMTVURF%xa&D)'
    '5>w&?G>BqGiR&aZw#_JUlO%SyWl@&IaZH?qanrF9hgvl9c@kL1Q)?2MIF_Gy7I)*=i>)XQ5<9khmIQ=b'
    'zQrP+CfwsZq_Lk^zMpW{ilfN3IFCKgKGTbh<_sIpW+qLdDDhcn#(`@S+mGWU^0>oX(>D`l`JNY2mpjDt'
    'Em%n6xu%=&ByqfmCT%ioY_n1g2GH9xmFf+wGkb`cMC!Ln;@_)P$~Iym;@dsxe>5S1ZBx^Z{m3$7ZriRC'
    'CZ3&;&<?_gu^<Y3N`N#mOQ>T-4s|1VlA6B57;y)t|J9eEYMtQC;@6^<6j1OAL6Z5QRfLJ<#*XVIUKrCj'
    'usQtS4~Y{p$F+cLCWwCG1=RJt#EgMdEVP2yH9ePGP86BFR<T)PDoVbgx)*EVZs?QHbtBJ<eVZk)?HuZu'
    'Q5YpAeCAp<#o9D94B(fT1VIEF#|#43;>_Zv+hWT_Q53|!6%w0;o@oZAiHV$cVsqH-Nf?J#9B^*ImS-`s'
    '0CPNuL)Yg4i6h@7T@e6It|aY45%rw?6FpzphMBksySv+nX)!y3^#N62UIf_BN=%akArLBX0w9p(TA{@P'
    'ZZRhcOwMe^tR%5a5E!<990NX&NQhK+sT~m(nIw!|&cZNoJns3f#Vn5})N?2aEs%X~#Hi!@%<(Wu*X)b|'
    '$;H43KQCtM?XJwzh*fv=XFN_pH}XR)ZGl{5EVgYBk9HV^F8ADo1#So|V>xyl0O5eP+$25+_OL-HnW0U&'
    '6EN7%7SqGh4eQBkE<NKkUA-aK@^amwrEt(BCQO-xA#j)-hCcUQ*I|xH?I0#@XjvirY9|h^%rQ+j_FOLs'
    'Idy}`VJ&nEC4}&hk=QbMNFwG(!0j}#K$tNrb}YvNzKTNzq$i$_+W}}E(g0roflvFPB~Pt>dc*14?BN<d'
    'oKm3nlqzyh3nyZV=wI_GVd9!xx|l5QcJbs{BuE?<_#Ui<#Gq4L6O+S1KETEYbXk^dxh!CA5@CTf3$zfY'
    'CIR%pqeLgkkFQNtiJUUU%uOqDftWUs+e^4*!v+pK*y|?9W-InW&P>9iDD-{DgKvR)E(PW91{5p}2NY3o'
    '&nsH;m7-48xR}sSuxy<jCvF&8QE2-#NMcZow#OXcwg8M3(2KFlKzRFch$X5lkS?$#DYM;EFGd!mpUO)X'
    '(>zQMoR@c8+F8<1>4F~@p&+D95Q~Wk62?p{#{CGkSV)t^C4K~o$&PH0)=ub}ocbWhE!c%N2u~k0FY)v('
    '@K#A4U^x&y(>1xCE`{)EqE-x+8+SP9(I|v%Ws<~qTrBM7cwn@e4(I@2I-d~Ghn@*i#|jeIaG~WAuzM47'
    'T<Ex18qelYKtk>T%f^lq;7tmXS;R_$5bO=h3{BVrfS!=}wo3!k$C72-PB;xtfEaY(`FmOSWGY>vCfo!B'
    'C!R3saVz3r`TK4RJQ@ml6S*K|923yT@VNkN1jh{-tiuLIC)^BM6k6jE82fe<d0=*UQ4&!eBtA#kZpUDI'
    'd2Rq00)^m#ArhED0?#uq0PE5P{T}(DKHMzjb&4qgmz1oUu>k@pazi`fAd>tDOh}VB9!$=R9W(S|_{8<7'
    'nS=pIuh0WA5Q6xM!JJ@bysK#&ZWY8J*T6zG8Q9ujT7Y-KK*V`2=IbYpgWiM_Cq6Q)OZ_k)p5rrgdn_J;'
    '=F*Q13=&RNJg1dzvSBuqG6y_CN_gNCk43RX!9w*Tkmf;T^T72z@ZwC@CzSEfwCuok!vMC16Gx{Oe%pni'
    'S3XrIFOB5(2<4IQ2N8&HALbi}ew+jWEG7V7*8`@HV(@@H&OmQP9<ynb*luKcK3FTP4Y?Ts{bo7ThAkEo'
    'aC~_bQlL4FERYc3g@Cz9iDluf5z93xkeLM`JP!6KEVVCI%6?#OalR^a+CgIz<dp4DSSZ%u1kc=e1HAbX'
    'g75<UWrI5s0#d>NY)zVk5l64rvk6{f1E=2COWk}O<@!(cB=rNUX{FU%a56YW+Zon?<v+0`rt1eD5Agp<'
    'f*TQ(9SuFaEER<znAISvz%KyR77kup-HH|!d=9#}HhP2}AugEF;OJ7AhikboDfk;N`B+Zqz%wjnF+3Q='
    'Q4p~R3}4E*XGbmA*5i?xFvs@-_%E7Ypb~(GL&pUx$3#1ZV@+2uIUQgCHwN$01o?<}1U=aA{!o;ZF1{T?'
    'gy%XjbHMlt!SDqS7L2XXgoy;8+)WM^2WLKL6x)ftB=F!r;PwWQNnIz5{lK<P!>c_57cThvU{%2+J(Cj`'
    '3oD0FzydR}2=~D8136?`UTlSoGcSsK>Vez>#s$hJ32PApprCXdkZo~<JON6}1{Ds<*h>h79ZVz8&Nev6'
    'HeN=JLFR$U$~|BqD{$>NCPNXk_nOJz9h?M!63{%1xse^=eZ9~QDOzI041ho2U!ZsbmKfN0puRoNa>IlW'
    '+a)eLdR1>{VJxNDLv$D}a);qUxj+|%3v|nND4fKe?}KaO1twtJ1PhCSA;f*WjGA~p2p&SPQZfN6fF<C_'
    '!=o@=i`ksm5q0#iYs2Kr-cG~3Lqfs;97`9JA~@op(wI*IFwSCd;7QB~7(w8xCMFAA&~kAEvJ_YbtVajX'
    '?J|w?mX6JZbZjni$L6ANY<6egih;t=M<X{%h#$w?!N9IXvG{ceE;wZg-YIs$HO1P(u)4r9U93e68XSyb'
    'MoF)=<fi(C@L?{%hq;hG%){C3a?WpyyJZa|ArS#u5ZJ^HvB2x_L1%$YZF$`H-2~LKWs}GQB?Zzt@It&$'
    '9^*A%I|xm1z}u(*j4gou18!SvTCVRpfC?TkGYEnZjCc?hAV7Q{q!w}AAcCFc!}s9&f?W^ls4Gg=X*vhK'
    'L_4n8G^NVaYck{_Fsn_+He=XdGzloEIZy}a*92h6IPjeZl(j>Ub`k7BzynB7A56XkG-pIK?JTu~Jz<}N'
    'Hnr)2>lH_wF_7_L3{oTvg;E1u7Ey3mJ+Qf~2#a158oJ!X3;BshfWF{BfoH980c#<wWl#ht0F#GD_&k}4'
    'v*2moAhcl>7GORB&l(hO0=`Qe#!i$_6MWx<gWCvZl^24+WT8n3*pETwfm802&;d``wcHb};(E58bMiKu'
    '=9z$UTQw{I<N*5p7B^{Z*=Aw`F~Ctzm=8P31?_B`6zjpe#IwPi_do!^YD}9^8|<OjIlisHv2-I!F{~a2'
    'c#Ot4;h`PF{z_aBrl8ba5xcc~FjK(zCMNL-xL5&bd){#LmCons`*g7v539{W5N<}NVskadvup+%h0_33'
    'f0&?U0UkIy0515Y4hAn0E8;M9FY#c?CIQzVAyE{1KDe%t6SNQ~f$xErO9%(w+K)}wrOfqW3d+x;;PQHa'
    '0ra>)eS5xR5swCLOo<zL5doLT?Y!<1{TCwl<2V*#?g!xhff5Eo(j_1pz$OAN02|v0z~6<b*+Ia;IkFw*'
    'qy7W8$OP-x2f}!Mi<$zU;iC|oJYao1Ep)(5b}aynhcclH{{>7_A8atfL6q4ZC{%*+5^+cY=Hc0=-~ROK'
    '$<_0p-b~-ToIZW>=J~fTul~>U<<+z2SH@R>pM7XSlqvBv1Mgs3JO>Jh!8315^7X&6bm#K=?%nb_l2yEk'
    'yaREqlGLZO1t{fAgoE3`t4&Uw)vC?f4n(G6?C&_4Pss}N59Zw`(g>vwhCqao8D2)3a?y@r$^aJ3rTdij'
    'Lh3gy4b*A^(q}S~>NMRfk#T?D5D@M%J5~s4wa_;6lC~{^yO7{6B)E$bxC;sHVj#aaaY%dARW?pDU3&r3'
    'hsyFkSaUE)QTM}t7h<Y?kOwc{fkkvnmbnel7v2Ok`pqVOi0P~eh>Gl?6!90cG@IPr&fD_uW??xdo{I3<'
    'a$QWO4R%CR4}spl!yH75E3CJdS8ZuK{B$!z2`!_O$KDckVqoAE*hEa0pW<NGWc<~Zz)$Bhyz<a)8n}oY'
    'UJgn$3lpF^uP0uS1sG&GZMT|b5Z4HE8s>z;We}h})E)vWZ>=UA713s@H#9q%iXGM$64LUi*!E9T)}0sW'
    'Y<i7#*g6P*IcdbeY&8s<unCwl%BSx|MZ&Dz>-*0D)a({TS#5B{$n_%4zyj>B$fGRX22?}h#48YmUkli('
    'n%p<D59rf;mk&^mi1o)pZTg8EWV?*El1>Pi>;~4W?qlFQ(<DJQ%Q^^~on?36)5iA|+Fnazw+kd`S-#%H'
    '$|-;TZpQdRO7X1I*4fd%h53pX%dfZ2W_zu$<EeC>$sw0#PYNEo2qn~D?7b~{>hC?nUY_%B($#I&`t>|j'
    '^BKpA0C!j!vdyap5;_Di(Aq$minX1le1TbL$CYiXywN|k+w(7~hdg2fE!N)vhqT_~Qc+W|>hOIq#b%@n'
    'r{;S8HJ9P1wy)sX;kKJzx8aKVD7A8SM_;V>ZNwvj73(&59Y(*m6{V_O1iQZ7Z|I+1J?;16zUGHL0Cbx`'
    'zG2|^&hLoi*yoEi?E0r@3b%d#DkZmHufY1}t4@Ln-+KWrjg(TIUM-zqE#8r=`+LtnEazaxcbo9*n{=sI'
    'qV+q%Kj?}b>0#6bO+)F?9#CHM)jRBm(;7l;Cjq2ev|G9Z0MwP1&;!8h?Vay(`P>!|t^ftITaGEv2;tQ>'
    'p4FC)->f*7Oj9^zJ;cHyP6;C5x)TrOufI|5{}a$3*}BravNMd=o9k=b_UYnEM2}vP1)sOKF~9%>Z1B}A'
    'x7E6uC*nl@$%f6+C*opYHyFav&X@FEddvIlW2J|`181Z=FK$WMgB^FJycQr`bo?F=y`@8yH_@!>52MbT'
    '?IG<jSGS4my#BwzCSQ>G00?i$>Y8`puU*#eAmu=z=5MxtOYMdp99X>BO)r(jQRlszzxX3rz2)n!lJqCx'
    'j)9G{y8D4FIt${GYjriFH-gIDysNDT|Kx?pFKaKwD_f;l{*T}n&9lx7`a-s^6TR#@GG}@At+yAh{biEO'
    'C=B}i9hebWFPo?WqK_Q_JEYrd(&YoL0js!&p<0#)xp*sAC>jK)kJ3|-ny#j383A2g<xbQ57T98a^OR#P'
    'z#cFDASx{g)!a+0^u<uc#_g@j;qC9<ym{5$xyY5StgX;Nnu%d|Uhm~$>_F*kL+nC;34kx!DMA7giD$Fx'
    'MK=_b-|QsJa*{n?T*FLnJBJulX6?%ruxr*!2`!ZI$wb{wdF8K@9>DRt3&VO)r$d0F!t43_KW;io!pc^='
    'U8bN!t~h$8U4Y2i)?X8L-7$VwPJr(#VZL9a@8=wb7CN*W!xj;YF1t*u`2B)2!EO?3vrhObhLz22yZN4_'
    'Eb`6)qOF(t-6rn*cIkMdJ&9%0hrg5goUi-Drc$&}zTM0i??0|E>w3NUOIL?!+u5eG-a6bDr_=l0l}2gJ'
    'ogLqjA)hb1=ga+8T^!JeMwNZuL_47~&PwkKL$cG_n~qPn@Ls7Sc<HfsJ5njzwjv1KCnQvd(b>x0@!tiQ'
    'uKs&nz4dX98+^2m#|Wj87x_fKOE;_Rn;D<8&e+%i)8(|Qq;0O!w0po(%^~Y&kE@_{S7ljdY+0J9A3N>o'
    'Ce?KMyPGFkImQC->u;NMO<r$qZ^`Pe-N|^vahS@7N4yX`ch>?<^k>X35xs67S#N@=g8YhNZ)Ue#Fm2Wq'
    '9-4<Y1p5w>_Sp@U*Z;Nw6(bMF(#6+g)fGg3|4dzuX>XzLJI%+~!B8MCvTVb*UG4`!La6|b6J5<j6V2A5'
    'We>R5Sc-|Sy6&?EXllonuKNi+mx86x8FTsBXx_|s_Ktr&->jajL?Q65&<b(z17={p&ii9`0aKN3cvL$l'
    'v)jMV);DZL-nR=??}a5KOn(Sf+0vJijW8<`rZ==5-%B5)j(Ywm&|hR1w;{MwlJphXWc=w(+EV`=0;PoV'
    '-)9S!zV8gIB$0=_I|S2psoohtO%A*w*ufb)#Pxwx7VQ0nL0!1#hunPu?TXLNkc8uoA^K;C=0(5hAdo9`'
    'zZd9L5Y`z$RoebC%NsTK2ZV+MT4}wAb*vIwM<54uKn`D==wg%cYm85}O65H?iqH<HfL+xaCmf-oMNTkI'
    'S>m1!e91J{I7qX#+M7L_?be~-8f24xkQ$NNBnUNwFN;Wxp!W&SQw))d)xoe2ltyfJd^@D~A044Fu&-l)'
    'nkTCXWZk>f0k%<wXaro9CYk|1{{VdPWV22)@{VhUUGus%LvQlLH4bsepVl$VVINz^2u)&G*H)^_U|n$c'
    '31IE;cZ}KrBh>DH6h#n=G904sLx&sA2Y^@0EXFE6Jtd-##58YhsdEe}E>@$hJ$=6oxac0>cM*iq2{lJP'
    'mAdaFuq9#3g-vx0kx8p}nhN1Y=F>!VB|XI;nY68^npj6&f5gjA@n*e-0YGf(0_>R6HQp|ORj?UR_s6D$'
    'k>$G8)$-~X^(uG`er0c=&;(m}llma$mlGta^ugU9)6_mj#XHpoea9@-26;EWs2g-8-Z&U|$&S_mt71S8'
    '2Dmq{r~`6ipiw8_O5jl!;9a|OFytmfPz%tq1vnVsKGRPh;2oQ<Gw5pNJTzP`gk^NGwTv3d=k*0GY$8qY'
    '@?wk18qy3^*g-`dL_NTjadNRlN&7IjgDwg?Xc$yw@?4<F(|5kZt45XKRPKs*DrB)2N>`6VM|GwOB(&E;'
    'Fz}}wFQ4>Zm9|P>yO|ex-Q)JTMomz@k!dX~zcbJ;W1$Z1=^R9t3On?LwY{<@l9+}qbN8;ANMdN47u%F4'
    'aw81)9(N*-02`8-QHG--HACV&hxV?=`qVX+-0r&KAQHb8u2oM+uSM95vm#-)_aS+uZg_7f_5Jg5DZ}A?'
    ';WaaA-^1ZDKlD1$tuL?txi><4B}$p8G~!{PuF}n#i`)7`4y~KmvoDYeXZAa3uCwL|4khaZJ>d{S37i0a'
    'O);F{P_?{kbR4PHWav<kmD`~Gf$dyf&Xa}(V9n>A^+fAaj8PFUr#zk9-?(ik<Ysg16eE;PG@bBkyHizd'
    '&^bc0iqv@^TDQhd1Y1LRa^D$aRpMv_zI)3-3-H6TNax|-UW-QOAdS*a=K#%?l-5JiCId^`X=a1nr4eq$'
    '6w`Aydc1v}F4*d#37Zndp{E>!q888zIW5Hh^aka>s?Mxohzw{uT`Z}n54l=xmYqUXox4X3g1W~m)DC~E'
    '#C4vc?G{Tq0cc?zXoIWOCfMysRZ`lgfcf(hTkh$CTvpM;VIJ1ZT25p3s$?zD8+EZ3$jwSv&jD4F_8oqp'
    'q)+Yc03D`tJ9l>K0X0{87rA0R4RoPW^}yUJ(+i<Y`$8>8!e1;hEESH43%3ACURt_J-)B8z#BX3`0Ph)3'
    'W{X+J8mbj=rD9d`>g>SVc8v?|8%W(<<**2!n%p+WRDTq!Vagq2Mf<(LeMHyh3pOyqDeU-}Btxm-{a}N#'
    'k?nM;_FcT|QSfDS_sWT=$}NS~i!EApNG@5d3lB^MjLx<28)QT?$liDQsx_Wul2uPZaj<Mu@0hQ$S|~>%'
    'qan1(P8la{s`;e(4o3s|bc|4`TqtWFYK`F>BCp06QJK*C^2CJ<O%;Zw98pwcNMss3{Q~rI#S^~5YEszo'
    'XT@d89rEc=DXo=rw%{vlqb*~vQLO0lV9G4g8D@iFnY%;%N|lsK*nCTFIrhF%$%LKLA}XaYulVnqnFyF{'
    ';=y;f8)nx}$T!XI1P7*7%ILQ=oA5E*)I3N!U2^y!^J*0I`xsic!7PhgV69{@Jo!+i+sby%yAF#?x!!{L'
    'AhmT#(grGMwV!oizuB5rh`tbr9%4|Juu;TKb5!>evxguKvVWT)YV%_o!RtPjRRJ=r5xH8t+^oSd)O08%'
    '+kWQ<Bfa<DA!O(Z556cJ+USC*2ctEhy=<UddOgW9EGN3=3}eIDz}jj`DLq*Ov&S28!)90kxNU4g6hO`}'
    'WRq!%vz2D4A!JvY-!RjvMv>E5SEcozZjc-&r*PW$U`(^yxMMz$65nV%ht9#T1TRhB<;*nHKB-|x+X3b-'
    '7wHCF-Bp@wk`ndw9C_q`CEYG^y7dLV-AOwQ2UJh7(`{Cv@|G*U))U}w*s}Z9q}w|JwFs+R!o>Lt#zo7y'
    'Q;LLH1#!9}@>O!^ys)bcHw~~g?b9ksH9HSaSDf_s9d_GEkawJQzLn8XMl4O2Psx%{aW!6VF8Tp1Xz)(t'
    'z838cH1FsG^FGCnra*!zRW#_CY_?lFphnig+wA}c4!vj#bG^vdKP)p~4}afa!E+fBK81!UH(a@&u##jM'
    'u`KvUltJywF(;aQBSV(xpf6dj=<}zA4aF2MBu;gl$3DIK5i1m2k;Qe7Lf6&0!6i_AgHL&jgz_oLKm{Ua'
    'CD*1`c@)irWM7Qe^oFy|X)dkoA5F7TsS;q&S>|C0vAUh&PVSo*y|aHy%%>yLya(I5g4j)bK2$!eZZ8m{'
    '0~6wE$r|6TxafJ<<LdD4Ui>KqOC?>cWU%VQNei`^pMr@OupZEL`GWAMdwW}Z@ac91S%c!)RYt*CUu<Ws'
    '$&V1pu0N9H5>Vbfd9b2Lt~kSz9>N*H&R0WDGRo5$#=P}eoyHNV%vb9X$u5CTu_aaomZpg$o`x)sA9<D$'
    '-KDhZ^wfDiS;qCi-MU5Sg+!<(!Tx4N7P5TlYl?M6hi#503CxU=6@SL*EYll4FZB(?)?+`AJHYNKmB-Fv'
    'z%l4=R_xPHbpmL~cxyt{DYiMuQG~bX1dh<%L&IM~=9pN-G{#j--@`JdbFq%rpsO3GnCeA7RUJF1;F0I='
    'W(<?t+IBMCvmLkf0%zIn48+}hK-Sf(n{=HHO1Ubx+}ze#%Qo|MHbfhjC)Q8k)FvjQ04E6l@6h)&>b`=I'
    ';p+Y%cb=^9dd{($W1D5%oaz8`E62FP)HK13+}CJ1uy1tQ7iH88v@f>eF~@)o@u-T4{xEw7K1}x-PxbDS'
    'zmU}oTetL#P&I*ivB>zUe`-^i(9iM)^Xt<!AjvU#(g@abOiI%)==R`UpSY{xNRu3@A?GBm1RA(oYoYlq'
    'YYuasT9omg1NNsB(67S;#Kzgv6p;@gx2>}^6d(|o5!JzE_)#Ed_+5lL3(ju!#tL_~&p@%CS0Y8KT_Dvo'
    'gn<N$p?Z4x4(prtxYAVz^lDqqv~L0`?&2$sSM$M60X@g`%eUQiYYE)!%v__~*_pDg`%3B(4(<b?O?1F5'
    'w;jiXts#J$WI~?&z7oiuGKp;+9RmO%(;JBqDIfdg*Y84J3zP`&82-Uj_<^bW`*&WiTw0a!fENd0g6giv'
    '0QWdA(Lbaf>TAsTo2$|Wd4_bqwAr2IJuPm|4F=V<@8VV*?SMLgIa;E{X*}X;)AQb!WE+Tm;`62^7S-$#'
    'S8$`PjMpxvG|E;kc~V$$k|{-jaGhDgSWZe~6C9BmJfB`8LZ)klk^Tl^<Nnqe3#c$fFJY~0jVJHOnyiEd'
    '=y~U%Y_PuJAJ#*vU>86Ni?@5p>D;E=uC8m8b{E3`1~e~v^yjSrk+q_Fmngt~2L*omHVod2=Ru~nT;GXe'
    '2wR>ST79=+)!J-!iGmZUfhrzO0l2o`PGDyffgtTxFzS{5J?Lt=Kaz;rZvQv!SgrAa3gw0;)0RB0UMi&u'
    'fZYBvAR3^G?16o?+RWA{NS>0_>JB~Eexj;Axl<U1^)WPVqbk?00r*g_uUDDHhH(GuO^hc&@Y{=9Y;`oK'
    'tj`WijH?aHQrI)iQ#uBFhCF2;HY>)O&ctB4f}2%R^ffh+;hxOn&Fza@a;?(!I~$5S3cU_dU+z>LvR1Jz'
    ';C6;smX2b2;yh5CRSZXB36@?QZUJj)>DXvrh|Cd!qfM7MoIFDqDj#dpA0#T}eSmcJV)1S!F@SeEXUk#2'
    'au;gfNLfRxj(syerQF;*=qV&;ss_VWUTQRP=NN_?EISWVW{40~C4%$Y#=LLM&TS~+*=9us*ALm5){umu'
    'd`5%B+U|^ox{sBqX_JyW^E_cFF`xa3Me$57sVES@b(EINfiGYkQ<jrqpp4%^zRnn3j_ng*SRkS3#4gMA'
    'ce|rm5&~B<dL!+U;X$`%c!M@_12}D)Zx{B7x5f$voXVrYS+SgfOuV~@LAJ`3xH%&XpKsCI>{hg<=?X<1'
    '-YHFp-O)~S;X!l+mDc99!cvc|x3w`<cxc$p+X1J^G0>N*x)1a{ItMGY7;WxB-^gA)iAL;Ub#d*Np@}qQ'
    'V1u||7n(LM*a3ZFE?_vGlD<o|7#*n-<s}T^0t^|#{FB+WvK)F|soMu`5FhM9(^r$e4*JA=fYDPddt6$}'
    'KsMM}!4Nh;+p!dS8jwa^Kzh1Orxdr;2E$vW%b_s(#wzOGq5#(Sh_?b{z$tG9&KoS(upSJi`+0Gr%X*Ud'
    'XbrGVw`q8ERCM3@dc%MS0}qXIt5N~}d%Aj?EeSnoR#AN{-HDHd5u1y{_xVWL5)}(Ui-Z6_6)7>LND9o?'
    '85~`!W9T(am)a7qo0vy~KP3!>E4~H^)3-zXOr0i+yT;PyR9#@_{jbL~LDk{!mDYQLHqT9y)_1dHX9YUD'
    '$Tm#<MCMN2Tb1VTO7ft-O)d(ANuyeXr8N0hO^6z5Rf(nv-LI3CpuFOurNaPVJGWyIjJ}fF<ymRf_9eg?'
    'w?i{NPZcp;;t=|pvgWXtauFKFXu9=T;g8|9vhzz~xWDAq8jzW~i<4_{MKZr}Mai09qh#ovs@rtO_NjuJ'
    'Ctqts%23GSzLmtmg~Y){j)RK=2W@Xzt<!Wa(V8Q7ww`nHHrsVxfBW>OS5K~<|MX`1=H>Lto<4j2!<#3@'
    'SH?d+o-N7x=Iqk=$C>JLIE~2~gV0iToSjSgh86d|#px}`f{LrV`MQ6@xt_&50dxVJGwM5DocMkmg-+m6'
    'm-&&EBnb;m&x#{6PAu0;xJTg;KeQN)n8#e-rYwpm4<jztentd4BRrum_}M4;xb0-i%usfZ0W4l@o@O`1'
    '_WYfhTY<}h(6P+K=ghZF&tXYOd0-O4DYeYl4id(E4<6wT327YIv6=9QdemldVAW@yamf{Dpqe&f1TXP}'
    'C=MLUv133|L^upcA~*6~PGT>NEsHvV<9IA40W)D|)5tYl%L4=v8ibm#aI;yw&32X#)UpEZB@UxVnJDqC'
    '#3Ml*hcFK-vMoEbVJeAbdY;8>#uMUEhsS0Vda)OnJIi0rXH=0hTa(oqJ`B}g>9Y7EM-H&!b}lkU$#{)3'
    '{`tkPi?e<E;q1_NfBlin7EdTx2?l7o4P6^`ocw303G1bSpZrDsV|+XW82>ZpYhxt}G+!EIac2}l0wpGh'
    '`(y9FBP&B)1N({Ga^b058n1;$ehgc4F`Ksmv8=T5h4*&*`l1}>AJ(IB8+hsB_3V1_0<bX}jg5=H7{8=5'
    'Hf}i~#0e{7bhN#6y!}{!E&Y8A>R&~JHe<P(y~BTTma^&*OsY)KzimKz9$#exI3<H;JOe(&i<LqU=hFT+'
    '6qLX92YdGonaw!^C<&Qoya%9FwQ59d-L;w$y)ZD#uzq|z=L2Rr%d*Xug@4`g-lX*Hvb_)N?o(}Uxwz+x'
    'ce7QxKu2`+>#viH@&$i&Loz<Dta$tR5rF-L#c)}nSyT*_6ekfBdga8i{hXVB0C%rxI0Sy#;eYWAM)~>Y'
    '7ti_tl*`u)?)44l>(<iZ<RVRjL~AY3K2;@J*<#rPBD+c7XR?-HHbAth%@5j1PNug?Qh-n+f#En{Mmev3'
    'iyxHsf!JL5VJ|hbT=6AYarW~40!1ZCNAc_9W3X}{C|J}QF*;P4ng}$iS_Fq@cSv_>A+#<!>msv8dT1xd'
    '+3}56|0(XmjUHtAa1#-Exk=}sgddz6sOBz>uV*4OGrH#R$44dLCU5!O`*g*OPv9%<<&g|uf&Y9jA0Ce<'
    'YjNFbxmiEitYK}-*}8~pk0uKaTH)xHX!@CmyBq5tNX+M>iCoWkqHbQSVb*U*_7?sj?+N@VzXyf<$@tW3'
    'G(su%;*DqX+4@d4K1pVLRmP;k&x6j(k?Bh?*V=9Y`;Ehd=eR_qgIsHAL`j(J!9jxDWos@kWn3B$=Ab?%'
    '&IH>&{1c2CGM_L`!34|rgK<yHi0Qpv-_7}GGNb9@<zjv}#siC6KDwPP{yt;tn@huW&kgwNJC5yHE)UGt'
    'b;oUxoiDu;vOi6hgbB{J?C~Tf^zHR3-7FaL56qlltGQG*uNavVGaR2Av&EswUg6uQkLj8$t^oryU4b09'
    '0_$}HPLt)2JIzlrLV20;H=xa7em*Fc?_Uh)mIC)G1Wqjj4vT<v$yJf%OiZ-R=C5q=y~Fn2`}ef<HSYXV'
    'Z~S5VUf;HFq5oUS^a)umOEvp2US6Kf8b4?!X(t)FL8DoIAA_??<IA#I8y^oL=0Al=^v%}68cFJ3Dq(b9'
    'iBWBTKd%Lu4$1K9lZf&K$SR<J7s(9>oZrcLj_~!?V!suA+7WRLoHClhT35L}IxZMTS*)X$N*+Y$ljRcd'
    '4*<#@qqIm`LU=aIND~lYbU&)Qx)X{=D06kRIT}A|K{9lxCbPvmP$f+GR*wu!{(|@OVUADs=mUSn*x1*b'
    '8LGyrZ?n0+#wbj>0N%^eTi!B6jz6=+_(FLAlUXKe9<<*W-+@O$-?o1~SNi2Wtp<Mp;u>_pXmSHQg9>8Y'
    '#+qoOEQZPyO(La&2=u#_^{`J<G^hhSDr18Hs2&HKsINvKlMCT=CpTt?0fcCIx_^}Nf}Rc@@m_>(P3E5W'
    'usw>O9MlhT<6qW4IIn!rYF6^WL9+tkR-BYbG)c-#ZpjkFAsE1TLdihOv}WGDKi3-q=6HEWoHxWI&v!Wg'
    'tNoa0jF57arymWO3f0SCto%%ym|5U$gtk|XqVbS%z)WhT(9b>-PP_A1T_T+C;t*}<<+^esc2s_4EGfBn'
    ';9ex|U;wqXe=5(FERum_+$C8fWsZx90^#ZVMK-ER+X0)U@i+kuuSdpaiDu5zhVzio3GiLA-#VlG-xA5n'
    'Fuf-%w=$vz+w^6FT=wP}rAgg30Fcvj5Xhj74lTaNIOQYa(+yHJ2632oim0uHJ{sitOCJxgM{6z{$VDx&'
    'u-8j_bnMu4zkhY6gFM}ZM;{ll=Iyl{X-Brm1&{Jn1o>}WQ(WQ!{<(pfT<`d$98d=(KeaqGDjzSZgQva6'
    '>=W?-u*C$cO4JrM?la`xB%qH*D^dNpgQ(vQX~3Aj^}<l@f_$B(^R{#R^Pf9Ra*09>7270{c}#s~SvW2C'
    'FwK0g^quEDVRJ5qYCX$jv!J!0c^iRqFa_k%LGz&Dkgmmm1Jpq$R2-DuZ7}ojq4DO18%uJ{4YEMv8IS<~'
    '1xv$N!xwCZ%}@dMxgm~i3}T2YG6rUx33&u!=JyTH){}Oly?#Gi(;MW>Y_m!Tg<TJFA4bW5&*pOs)@P4k'
    'l#H*}xX+3S;PdZ57UT2C0oVq##gL6bpbAkR8>0pWc-+i1LM@Dq7GZ_XA*Q~1YB|uyEO~WG*==<*?CPye'
    'CpN5nri~^98>@fBthF7n0~967i{vNHL9WQqg7Sm!L3wKo9-rMy)Ujh=x?@~=P*}QUwu`<KmHOnic1h#>'
    '+64V;xz8WBCfp0msvEuKcbCTQkm~u}1Ht`+=H4No2(w~QO^IW}c1!<({PXUYZ&x!mqUn5di%j|t{PV?{'
    '-;O4PktJ?=Jmj6-Zf-9P%l5|O-_8xp!4(FLWp_B~`zBpIC-i2tMew*}Wpq4>%a78#CbQtKT*y5o1^pxO'
    'XF&p?C-OfgGxn(ep`Q#*=12QoCo0$ywt5T#{&u^?Ckt}Ri_>@VL7l#X2auo>a925mcinN@v=Lpg3_ZK4'
    'X)`G+y0zfh`_QXZdJVc$^b09ZRhiBY4&*0Xm(p|#mf61828S}7)gUCg9^JGRC7q*sUsNNhWku9K6nE?#'
    'puMuz$*rdrfV$*g5Ak=l{}5?Ef%l&?jA-Rp;p6`8)$`=&q=LDZTt2Z_Zei$DlOAfBd0!dg_Tb>mhl*oa'
    '9#L-eN@%V+A#p`OUU}IG(mgtuJ&ZTDIs1OLVDj~jv#eP?B3_}!9UCOOgGbutXH=5BjW531hTz+)>?({B'
    'h(|RFmO@^b+Wx5LCAs`ZnbGiCIn8{6!;co*t5WsLQ!tU86#4xFRzS-jm^RZ}iX-XZf*+Ds3FGYC5TrH!'
    '^{*1n3QwiA7OHwvvQ0!uiipIbm|xEpqYTUB<i7Sq{ME|NV`+Of!8wR6E8<Ca%C=WSZkIV~ZD30DRaTQr'
    'Yq?fXR1NE@<F7>ymgHD5`5{dE3E!nR?NN4rE8MQ;aHy{Xhj)`{Mbc*n`Gp+y`$k^IliHz;xj#&+bPrbE'
    'gHGwFQub?<7U-`@uP@M3N8u$-t&oMf8_B)(P#-na652f|mu|YHlVN{ff%x{j_VA|t^jnwe7Wu8^ywhQ|'
    '7V42oAAS&rp6xky?D`({ZJH47C%zx@#AJR<lEAYVwc*z|2u#bjy(IEIFSaaBZJ(OQD}6Wtcazu;OwacK'
    '1PScKq84E$x2PA}gt{b2sN?y5<XNs41vE5+$Yd@L6DM-nnND0Z*ZYWU(_@@kJ`1T8+1v?j;`%<1lQ6Lu'
    ';{lBvm~LX*0V6I=LYMH+_o-zQ#v;pYQ}4qs*ZT;n^*(x$TXxRCU~)HtJGLJLA$7RpCoxtsArUkEz^5Jy'
    '9TxeP9eGX?yB;Mj2^`ysEDO-$$F@VGkhdT>w}|DqEOs2v<Gw>pKTK%sCW*)5*ds9wSU{+0x?xCt&kb2b'
    'OwV<kh=+*fGriboCOHi}(~m6bM#N7zFu4^Zltd9Qb{GT0!vy2lNnD#Vz>V+tmhbx1A;8M6?*?HTlDlP+'
    'djm**ps4Il<sR-(*L4%uH-Vf$<iK_ba4|PyW}3Ebx{mLefn_Dkb^;g3;sQ4$Nfel&mr$mm<`DKdfBpgJ'
    'G2@^FMM2#K$lE<tl750OkFiwl4d*<K^@Erh@Px&I6H?o>5<iJzSeOkQZCQ?Eve<W+9|jI*Zp=LfsIYhp'
    'Y-U*=@U~MkjH-JE;G4Du+({CfQU)AKxZ@_UZ@kbBnau;+rXbZq+li7WvOSUj69+cRf{+Iw;o>@c$%VDr'
    'K8I|=vN<D*dLUj!P2$&J>dLwvEh_ZXbdD^)LBY7YG)fKWuf#{~!C-tQPT5`COAvcBUnW)ps;{=T5mrlk'
    'd#PqR5r3T<;=W>b;9gH9?j+t^rn3z5ud#Fq{JvNpyqwuE%m2GQ-`ZP=Y-?1vBB&;M>LF)AO_d1unv0sF'
    'faMp9_3>Iqnz-U#m|`GLG_k~|eLS)Epi=n*-Iy@{0k7g6$uLZu2WYd|KMyB7wh6SNSjQST@Xu)69~7+D'
    '7=g#dKLAw(UNP@eQd3fE!WWxc)YF_D&P-{OuOM<dRH=5D{nKw>;h3WjmvZpQ2jl-2=$X97=<B(0mw#~w'
    'U$hdt`0|a2(vF8s6+AkD7tEb7fqaPY3F_6+I=w6wF)p~H)${}qus?qQL$?m6|8zgK6LfufS}#lM<LI+}'
    '9F|FW_%z*!I#IXe!^k|ZGBp+7T^QD|kpy$*<J6?Fx<Yh|vB}be&hz=S81_qZJU0Hruz*~TA2%$Z_uQMe'
    'eH%4cp2Kp*li7#S7761X!s2tuiq4|qJ|)FqL9tg(bkcsG)OmlliHjqDSlJ>Kfg<*7c0Cit))erLa;Poz'
    'maA=tmv&FJdg$T9hsG5LTjnk^(#8Bvq+OyZ$63BtjW;*5%)t8O#tlf!MQY4bDqLR7%3Nb_0?fyJznZOi'
    '8@8ZiNn}pLq}3F6s|=!j_L{uoOc-f$`U9-kZB4+c2YI}T=qYSsorMpNfUYE%TyeIc{Kr&o&}yBy?Kkbm'
    'YN|Jfgeu$Dl62z94x6L_^t;xTGh573Bot$%E%D3a*1&QoIhV@!dpII9)}lh-;bhIrMkG(vt;`-!H^Mjj'
    '2RLWHX_jVX)QO^&s?b@}{106<IWIO}YnQBxBGThy(#>kcg{38y*_XWHTm{im%fOY;yK&7g!mS*U`RrOq'
    'hD&2I=ju9p>lDjor47pE$^1R)mPNX{#Ue~Hub-y3OIQt86vN9`?>KzDxHgC(Ei#qx--?tOC3Bt`v-PC&'
    '3>#u0qnwT8zvsIVih>C8i0`rZZ;OF1bE4HCb~oK>+3o#|Q~;vpv%L|6e;!G1JYt~b1%_7D{X5Ct&X)E1'
    'Q4fG?-;)&sllw@LU<(r#kG^g|y8)Aph8e?oLWr1mE%WR=-(;6^2iH&ewV7}GzF2M1S<YG9nb)ISlXZ-x'
    '?HJtK8e2yT>TMw%tgqF`8vRH%C<ahsSJeTDGg<WWdww_C*&DgkVh1i5mPXrICb<Sf_JILxzk>igxOp(H'
    '?+*O#f3`(y2ey)3wJKru;653MUb!XnjizkAQDKGU`9Zk>)k>d9zMGSUjF4o*$oA<Ez4ayM_uKou-m2u?'
    'i-W#GEictq=f*l+llkS4$XXQzvY?{8l~6}PKI((9uF-zMRmstIR+gY4){c-9aD*xLfdh+-g2jT>Gn17('
    'F8zTouGcpsb3E2I>qBg^#Zj-p1S;By_}u*IC*alFDB=%mkDWJ*FCVnCBX<Cx3k14i2r*<J3ritk1Ym-3'
    'G+DS(72PbVS9Twx+fMEFbh$9ayINU_itg(Uw_H^4-OknQVX#XjMbdg*6n&tZOQPt5zp4a{G>uTILn9+F'
    'lNsxyrlq|i{G_}D+E<0HZlAr~47_~$AhfhNeaHt=id)A~LJ^t&3kK$UZ*NQyFXelSbkS_i`Es-%i&XCI'
    'cJ@gvF!KuSlo^;iD^R9CZD9=w@~iyp{?zGj9tfv+%hXsXz0AvxhRtbDvThM$IB&l2em=ketlR5b4*k4_'
    'dp<Ar4zVE4hp0STELY^)JIxd8AQip(DK*kLyFiI#&^afI%@U@z5WizJiaEjFHpgpF4A*iMQ|bAfix@t='
    'navqs<<by%0{3z}0O~<I9gkZcj87Q)m5Iz1z0pnDDTY#YD^wI&{Ie~j^zKMyiSu?2+EzZ)RA8qG=Rv$3'
    '<#cX*(RtUl824i}BGiFK?T;lt{r0JA%BDIdD>t+}mP>4!p2IClg2Z;*nE4TPX%teI^T79FY-btqz>K(K'
    'GAE+36FH&l5i_#9$hI8r9nU4UiOc*Tj$_kwSYrCF??n-fEQ|1v+JyStHsdJbHc0~b$V$Q}<}eCLd^5BH'
    '`%DiOK3|(ir<_CV>~9mf=M)X^_P!Q%eERn{Qq`II1K_I_o{Buje;&8#yx8S@r`X1?DfV}7|9tB+7uy_n'
    'E7(vyzWxbB5=ApT!K{SK?FGk|@{{Ku2s)je3P~uDB@hcXLUlk{3P2%U{BtgA6JH8acI^3*7bw`Cs&}tm'
    'QOgJ?ePFadA`8d;pyQ9~xPfYS!iyP8wJQ?{+V<Ws&K|^R`gTI+V2QJ$+{Hk@{@~;lmHwG7xKLsu+w~T#'
    'CBRFvng3t>{A2yj`u?F1PCji>x*gkSfEhOG*)^!(CN+m0EMqH<zmxgf2f9a9h+(opn?j8IhqEW^d_wp='
    'P#4JooP~c481wjv=6DcjHG7n{nGV367y7AZYq*x`Xs9+CsEiH|UupvPJ-=()0<K6%5pP`@-x08@MDf{{'
    '7X?cx8Ol!i0gUCBhcg&zx885T@C1b;^80;PW1Z4fzAUxAB0WUSy0I+jd3i>~uN|wEN)!BQU&_~Gm`RCj'
    '=w_(78jo|8cG>BYaB0-%Wp+9=kkr+^$Ej80+%pXLQ!Q(0b~Lj(T3OnStdrYVhfS=nD&*E`akVkHzN+$g'
    '=Q1_j?5~rWU-x8vox=FKKijLP>GfGGug_q39W{=cl9KmkDIT?%PGyVrF~!>E;vZ`ZTh0!fh(f=rJ5xRP'
    'CHsAYUy=oz5D;wdC!3|HNV&D-_FIizdWUs8lU7s43c%f4ukL@kd2^_`6t7Sz)4P*-a@$&fN`-fJVntT*'
    'V*T@iyd$$YT9&e?VSPc8Gk=@`dKcFn{8<sSgeBjS)mvD#>Kn><Mpv_?jKVf!urlCxv&H(sczgn;*rnOz'
    'RxPp*B|cVjROA>%b;tH>y=_F<Y8Ia+i+T&S9fgQUNIS58wWkPLMgn*1yXsah4%Km$T^#Pc{n`Xv9HbUO'
    'GPZ5v)NR^>9d`?hUchVerQ4Ue?Z!y0QQfV+lR|K-EnXObq6$)OkQOD8x)t3L=g$R1Jcw2tag(<npCq#t'
    'UY9VwG$-o}y^F#x!`fNJkg8L)JR{yeFz^?jCzE{I^50?AvO0G^z6WjBLfM^G*L6~L_o?X)D7uPo+u3V4'
    'sk*y2ZFj%QPQR|}uIe;vx&w;td){Bc)jOkAvaJfxMWR)Gi1wg6s?MEQKnGQ-MU$RRk#;Y*c3h2i*P@TA'
    '!L`GeHmaAx${7TLMOwUgxMt|VlA)b6cgr#I8k_k_wz0*2)xHa~t8$?g^P!IFeArf%(~lMpJ?Xl3jhZ2g'
    '8L%flb*>lK)b6)s!Uy#z@q);8i0e}<lNQq;AZFr|(2hx9I^5+pWh{ngm}9yjV{YJ(n1z8KIV?Gz@WDdU'
    '^P(sYJUgMxGF|SPu@l-!?3m1pY2?RI5+-)w+wgxsP6$spXRc{eGl)I+OdlpbU($zFPWrG8Cw*+2!-4>Q'
    'xm4X{MkASBe{SUezQEMji@zAZq%$@?nuQ_7*}*Pw9Y9n%v$c6oEC^QdZK=b;->^z%v4mq##9>q3!+HnI'
    '`LV^FH%|S$m4CS=*Ov<IAO;?Q(TL&Is}zHqm5;M@wSIGl^@?AJtH@S6_}!^3wb*%%*1zIS-6hUr|7ZtL'
    '-_mWJ$`)Z?8M3Yb5@bf^zsQ?Dk}^m8k?3ab;k@0GwRc{tbOG%6UWeg!dXkSu-4HcoCw`WVxZNks4HuP_'
    'ci!CRu=sW#;`R<(*=cR2cM>siuTrA7kmxESS{!anZ^;Mj%5o6aL_PFs1u9q7)RMRueQAzmWvmD7qN-Co'
    'rFwQ?_JwWn48D{0g?PN!3u<|-MibU%rTYH%k4Kenx0UOwAE>7UZ4Y*M5KjyacJ|KV+;L{x#QN@s`1eZt'
    '(~<rNfg1-d+HHMRm#U9;pQ}tkesH)}e=?~_Tj4-gJ{cG^=$q}*#El(KT3_MK^HoC=v^x~-qEUf}C4MPH'
    'VX47U&n(t@%QZ5eKNwFy*^IED>tvBGc(1d!=6+SRgoZCo)%pm>lZuDTVSC}t!EwJ7!%i>k4@YegqNG7V'
    'h0fS$YU#MA(OuDatrkh|wz5tSzm^PDo(zhs>_HEH%Fj)1r6dy(%JpQOGFcBpvG4Y)k^F9KbUvXu%`Q37'
    'CizTzWbd#K9~$3tzBI_f;2$uYFk7Q_DelISE%pp`K42uP^j6e=T7VebJ6h3m`M`a;2M4C~GB0De$$;+J'
    'b{-D}uRMGr^wBN3GpGoy!?Uvt{$6azT(*~nfgg0mg$kDE9biPCxH`|A8()<ANU0lp+35WZUxD&I5Iz?~'
    '!q{O6{HOluZlirt;{jG`t+CAm<A447>u5XhxZkN#>7b;<eI>B>m9X@u&nMQ8N%gM1MO&S?4(Kzw%OIVa'
    'jP5ym?bmShkQ6<l^m=k@C%hzT=pJJg$81$owD0E5b?0`H0`dcS30B@%t&B8oU*+da_KfVk_q$+J&iY=Y'
    '!VYgLZ{p8?ZtDA|gJU^D`Yep9Mn0k7?DA|sqfx)j*#02vDY#q@pUyY&(@nMppKhg&wcn)685OC&dm7{r'
    'p9k0#hDL;Yk!=!}TS;u&#Dh;sXtRXci5W!}OWeS>sPFSIB7uk3i9?&yfemtsd4G#>&IJ)2au!$veP4r|'
    'Gi*O(Q_Hc<gi@cw|6<>ZZ9fWF;>3yTTAoRL&o(1!TTX07L6F$63T7pqYcWU1j6r*Wg5}s->1mp-K=+XL'
    'EvH~IaX@(BMUm_9Bu=8xb7&GJ7WZjjo6Pp88(G9QEtf~3A4Dv$T_8yeD+@!~=9+k%aNFTD2uy%!#(of5'
    ')U{)Wc(G^N#0@=<gihqf#Px~GVlVUp&Y9;saU8^Yk<ol`$U|<sft#3NV7f_c`hMat#|sngg$|2DVwy0g'
    'n1%$XN)ns9#P?Vfnk-8EfY3GvhhF*MFzVTHO02PZW#mUJA+NK26ZW5SJnEP(H=O_|76g&)azu?4#zDa1'
    'C<!Pf4h@_TXqjLY0p=3dO57-P-DB;Wd@u1hcD+hW3pTMA243Rx$hU*Y<gj&2o<xk>mdQu}%;^Dt1~zpl'
    'BMwl)Z`Z!55-AgH48YlVvRaY5QBh}?<(&;mtro^(6*ZH+YYv5DOH<eZ%vS008_f8q!fxODqh*_rj-~kT'
    '0~=bA@%bwLKQUrVrUVlQOZkJ>JIh3A_Ke<ewwd!s26*za05fK*War9N&aluw-ipe=zh4Pu*J{k=CI*>d'
    ')ca3u3rJlW&wt;L^|4E-^^~j}EO@F^R!-loLv?BVEN-0Q0hVn}O;h}Tz!)l={|y?=$Thax6<Gg@>I#53'
    '+blO^xs*q0-RqHyLYJlfG9{SZirL6KCkYNKm8t9|xlGk(yjSTgoMn>Z8XM7wG0wqsgsoelMfYO)*_tmg'
    'B}~lvVLr@%7;+5b|0@Q@rYMi$|D8*M$_vWaVpx${phA_5gWt_g(B9vG`d9D%r<!*6l5qLh^8Je(-d7SG'
    'kJaa@92Z~%Kkht;Tr?j3@C6&u?hMt9OA0=d<NmS5uQ;u{5bah}PYkkI-+-67zMB|tX5dt0#(ee;yHSZi'
    '=4&*7etuyv>{&g>0{KNB;YkOXpI3{I`8-`*XFz8exdjVKrF1?NjmyvL_4!ruCt0wffL4n^=d*-k9;gNt'
    'A<H53Pz(Z?Dw@zo!_<Vf#L|mrm&VH&8>4Q0?Y<E6`%stlo89X3$9(~#Q%bJ6D2yOan|p%-zDZ`+m{NK)'
    'k?sighW5t6pHe%ZvNk;0#-~$zkew<1Kla|WH;ybz5c^)gA}41sBxjgZydSEmuBIreO4FsskgVz%OPa)e'
    'lG#dTX6HjHwOYWyU%ZCbSbtdC3-8*1VZ*S2UGKs+Jix%%`7gG+cjlA-g3q}(A~Pa0G8vB>S*32VyF@Y>'
    'aqhk6p7%ZXoI2GzQ)&UJv`#L`bg|QXve8NIcIJv)<?&Wq4!}|<U!EwQK3V;-hQ3JmKQqbM+49rGj9zA3'
    'Ppfb0hc*fe=7hjmT9Li37(mZEy#tV`iSn#+8<%xJ*J6~kkiM^){<Mb*tVY{WB@c6G=rAmTs47USwx;hC'
    'x2)<_R~{!>9ayMfld86edd#HSVn<i2ZVXk~DQORtO12d0L#&5_brNR!tZ<|~9Nv+O;V?D#bq6%8NXmu_'
    'bu=>?k9vvD2FGa#n);;iItn}BHff!tXtEvzT?VsqAFXZe!WscuF-G-vSXtEovb!<~E2>RS&hB>}ju+Jh'
    'M#dvr5^2UWN}M69qM@6-re}1xMmm^EmK*R0yqe_E{O9cn8HG9J(iiyo%i2tN=XGt)mB+kYAirXU0bb6^'
    'SAcz%uK=sEcsuzLuJ~D11wW8l>#0#Xe~|R^>iqiGNz$9<BltY|sYdzoP4fS|Gs%h2&(~!~&0astHn6kp'
    '-LKX9PHOkS&b?mH30s4#HFH1-witz}|7tMNom^*0OW0W^J_lo@DHp22>0pZf6@EXl%B%qPQax<fC?&nF'
    's?sTcnFd~x*{)jpg8yx`=r3nzHzD26bA+4H?b5c($@E$sArr32f%@Y=?iBPMTiPC#dIwaN8cJAX`sb}`'
    'DnHXTm3u!)&BiZl$^Nva^f)b-mJD!wr&g#|o;jlzlKG~>Z#iJr$Xxw=)G~6@^40xSTgtPI0@f>J>l$;_'
    '>A0{5qQZB@c9-Q>`BOfaG1z0Ypf6O&saO}K{ik*zpu~{I2y$D~t`uv>2|xZph95Uc(|A*WCZ=AITzS7z'
    'luJKmi?aN@KF=-3NHA42f>no$w^Ma{44bFhRa*ufT2)TTac4InKPz8~zE$G=Vk_}hKYB<H$}(pU>Fyq<'
    '%Dd{B-)c=M^q+juDYE6Qqek=Jq{d{ts=T#C!WV0rYhS8*O{nVLmnBH?<Djz@4qNQ6kw;->+uk>o)Ss6Z'
    'wm)pg36)^7yd#ywg-hlVQ6A7x5UFxztiX{@>~liGAPkrr2}@X>EnN}CzQtmnI>e$*=(%xhlfdS-xI34~'
    '^;i&6KZ;%I3rdM21dAk>%nKqCQ#*h`JsNv53Su|lfy+bRcOyUcJsuOn4-BE<<LEh2Y-Z|qoA*0cN!v{o'
    '`_^IAjD?va;$3$VHMo<^<KVC)A1cr)Ctv*lf7od2RH8OpW)*`GEOwwm7f1Oy{_&rF(XktrCfftP+C-O0'
    'Z0)j5cO2p#3~ndm>Adrd&M?Phx9__P4o07m>+}h5nwi^K-g{B^XRvN>df2M38061=J6AVi^~xQi=~N!@'
    '2{CWymv~?Lp1PZ&?_6WHxgG*c8W{R|N>E_qNt!<G!ICmWXBY2?b|3sS!3<7$^OQ~wMr7DwLo%DK?y08N'
    '?eUNeuixL9^;_m7W5BVIT5?n2IH`_v+|eoeWr-|*c3i1qe!~Of!qeOpUsiju{Ml{M+nAPs6Gj@X1wh}b'
    'It4Ubh&QT*Y?_W$0#1pO-gPZjK5e|z;cOzb(nC-6Yf1QbADZTnn|<gs`-hUlZ6bOFar192mxgM3`r7c!'
    'b?fU{0g60XlAY=w*jB;R#<AcX1xi#RSxwOE=dma;E3}3HICBuC&znIhd04seUePXAdB5xtXS4Ij&1s8~'
    't_D+PzCX<v8IP|=V-zDPu(yJ|UN$~K3?3Fr!X`tg({-@U?yEkre};8cjyq4$i1^8u<w&l?!K-?l3w#n='
    ')51Vso-kz#-cca)4v=W@oGW8utX7Cw&Pgg-XAY*#Y@oIfJaw?1X4v0T9pzKPUeB^e{ipXH+&eufG1!H`'
    '8oBt&Yau2xb@f>>NM}ZFMNdcnm!{h1I!SrDn4s8K>DB5oGA1tWOqSa)fs=F2UHb62m|OD4p+}|r0F5wx'
    '@C(hd>m7AUfEdWm^0-uiN>5Aklf*x-eNyLG_3p#eJk9Cf)1Yv|uBGd67OwAoCs#lPbD*=bGZmVpugs-!'
    'mMjnhx_o(%l9>Cc<?wlWa-~*N7RcJxt?y;=IindJs@MYE96WKVe!jF82wWNPYtg;(g?5t{)(-&D{Vimo'
    '%rgx!f`aKAb-5$)9t9tOQ->X3K@x$CN~e<Do#W1E3|2pE_x$a6`nsgwx4r>ch-b}@SGOOk&JI@**-iVd'
    '+L3D6gVc3-n*Y7VL2G6DPNFx@GXobKuvR1Z4aPmo9X{z_PLfu`We!$L)97h(1xZ)sNK@2r7qj#NQj!|~'
    'D@C(utOVI5xeWm*Svpl!sFWF}%mm6w#`SANg4_4w&cndEL}iAM*glA7`w9HALic0&R0uA3(OHpN)~0n^'
    'VY^pnKuU)<+G;AU2ctvP_&%9lyVz0171~Bi5^(!*AtqPGJ%!!^8aATa$19UEt#_F}XiSt?p~bN)>Ehr+'
    'N$Wl7{;q7YQtqpk(VbJKZ3fJf#yU<z(UU_g6w;Xu$9SCx&t)*Iyuj6w*}D<DnT|)}#jJx?#7UWu;nLb('
    'PBL?<n1phxEfZeEEdU(8P#!Z%rep0qYZSi%N35jX&4m<GT|+{Cc_P7Oo!vawQ$Acy_^4v7`vMAC?f-Ey'
    ');f)-BY5ohlBbVGw4qiwu2gVi*%4rtv;-h;$snD3rfTG2l|mys(W19c+bJtPS|b1WjzW(cc&t}_f2HEG'
    'eqDkIWR=nKDj!k)jVia&A$V)NGf<&{g(}t}7sF;1(2A$E?p+R(DwrB?`A^HXR!JHj!0eMPQ3grUkhH=C'
    '0X<m&81R5K3Vr_qY@Ig)lo)vPLf=1!0aI_}tvb8`i|VA}q~HIJlHdA1%WT2bN&eHaC^HmDNP;K{YRYT+'
    'axYX;?|DJpUu{=<!d=0tDcJNHo0y9#Wdly-qGv1HYM7RaD~t*4v9ZTrsBTsA-O2ZC%*A9n{>44~2jthu'
    'gno}d-kDkxM3E~z-?b!V#0^;(Q_hIzN=6+kmY$T<6}HW|q?8g@a$&i)beYZKK*-R(JGDkK>DqzxZQ)Vs'
    'Q#+=ibf_J084_U!Hje`)g)c<JXdvw%kixTR96PoU)c2hOv)Cxku<;#kF&W1);E_c`&mm4gsf>LrKw|}#'
    '<aXfu5%YvgtiXnaNZ+$ODWr7$n8`93HjWi!b8G;;HEZ>NPoaOgr-Dp_U!kJ`tDdQ=#xq0JdIAxX$oGWp'
    'F()QGwn#)h!J{a2ec=b5&23*u=DUnUHjs}ObLIvCcYQ3RWs$q8^++0deq`||jsn6xpbHiV*m5k?W5am1'
    '<dO6|pbF^*Aq`^BV-dA24`#q3Nh($AQCzq2WAcOg_Td=+?SiYJI#%89bnO$XTdfLC)r%lip01GKd0hHY'
    ')vzmbP3%O`DlEQAUSb!N>QvK~suh5^)5qT3<0@c=2{EhA1r_Ijvlvx=2j0>=^X+Ibukp5eKUuLl-5O%n'
    'K&4eDU=$xB7`+dw&JWjBe!3N*RV2Y`lkNWMruQ|eu{}RRRR88*{&&Cq=l}jUfBV1vzkmPV{^sBOi+}jr'
    'fBPT)?(bX1_K%L?$u${_J~8|c&hUC4KCyZ`NdCwF<UjxIfA#M)!~ec<I9}NJ#Na<1?OooC-)4$BeNyQy'
    ';`$%{_J9A)KlyjR`CtF(Z~x2x<M&gar*$(var_U+@hjs!tueRUmQS4Dk};n*<F%^)hrj=qzxliW>Gw_q'
    '=v$GWB)|`C)MJcT^|$%t&9{&8-~OBb;Wz*4f7X2e+kf@1fBUch``>fVet8}ElOXs31wqybNO$Cu3~0^#'
    'U+I2y0{+Q=@%zT~sxsLphX3J6@GN!oGdlmIlLYzR-iT4>-FVSqH{<b4oO}`l?Rf*g{TKiKKm3n>r$Yf*'
    'GvNRGzy9fO{@K6%$N%P^{r129KmYM>{?p(7Xa9?q7yr-S{Kp@quqgRtX<{fi0j*Hw<4VltvwK+NBKaxT'
    '^yv9?%oj?~sK0J$eZ(XQ9fw&C4Px7(!f`w|lD;EJ<b+Yoc^HQQBLS0?OXk|K%RD@BW>(;GPP~S#kJgv)'
    'T;~vASM^KG3wt`|AZ-C88SYv|ByEqno+tf?G8#Gp{tF`FM%?vmE3hoa1o1=W`M$KMbbTJ#A@wXgad+d`'
    's<n#61gj*ZhwQMJ)5#=V0M7gIEx8tF)A3}>q=gp+B=Wr2_i5m8N!-w7t`$eIwBR$(c9;~Q&!P~1pd<`q'
    'k5VfPJzH>FSYC;2kT{M*8rTtWc;s7FXj$0A%8`zUTp=SG*)$Zwri^e(Y`~ldY2*bWBs2~@QWXIeb0rRl'
    'WpgKn^}(*dya<q=EiH?L5o}cGhOj}lXGb;<h0WbKv;=oJx23eP=a3VWz(CWyhl&``R1AcG;(5iDX$!TV'
    'iFa?uQ~pq3ohc@Ek+jWa$T@W!84?Gk?+M?NJoF+U8QXPe2pb0z78VHvkcZ<(%!(W)+>ir5+uRIE7p&)r'
    'm|_L#`9rL5dPS~vW8qy(5u6bVrc9y;D9nkXKm?xWa@S%`NQoEOb_72<(#4gzmgQ03^JOHM7sf6xk@mz0'
    'AtK@gc1}bj=0Ob9&ZG^(jN8<;T^s0%M%)ve_yMwmWPq>`U*I4d>Y*iVD|dDy*z4K7IegepFYffwSnN;5'
    '^#F)p7c!Z=tCK8r5C@jDc_ds<#&!ri>_#?Wj>kDjYKI8y?d96U4g^SS$r$I%r2$9}EA#?KN`q?yO763S'
    'l>5uv-9D1mT=WT7?T-srdLVq8gwo|<;KM!<Dq*uNZ2AYX4}=<!f^9pt$3qUw^aKcW;S#|t0;B<t5|iY7'
    '_u5`-KJD{_QHxgO0iilT%Dxn~1HvivL5^9VcWmlMf?GtyAanxPhra@4dQ3z>&&&ml14=gB^NJ>7n(WT3'
    'a4}IJEnzc<N)UZ^9613CB?YDL_}m3f3gZ~8gn)V+6jMMW7eu5jz#<4a<Br$%Vy=f{N``&iJTt>&Nj06i'
    'ycKyQ1}y^u3gm+wOV1BDLD>N+CIp+p5r7qsxjbO8V+UYRIH0gB3S!y!fnd!o@HUaEKyn~f`*U*LpD4jv'
    'v|E%ofp7)b2r<Zl&>}K$Jtrj0^_dOQfWsC#Za@g=dfx(x3X1`Ti)@cD;z@G1K=opf$&QFa5(ytjmbz|;'
    '9WpHrl17FR*iyC?S-=C1A4Vi_JQi93_d-`VQn0WE#9-dMc-vRyoccNwxd=BQ!HG-Gd|}5Tirm1XK%<e8'
    'H?aqs=30P0j?aZ)|F~YnVI8oqJ`q+V@5YUYrE5EJ?1M?=$1-Ljlz~9K<xsFIeJ=zIfwJ?#$O3sS;d$<d'
    'U^#=xw&Nf&hntCRli4S4$ec`zu>k@p_97=1Ad-R@%wvnVK1|M{t`+$dKJk2J$tVQr75N|rA`o8`Oe1d5'
    'O)H|Hm>&hX2G+O5!H;l#O9q^Si1R%xlP6sllXzV!10-0F1yM+RH{h6UYzyo<X&xIGmgy(gC`#!j2WA6$'
    ')0LiNs85N{V`?+7zJnN~c^EqaRH<+C*zy9xxQHy<2^}vAfi+wjw=Miu3&UjiesbZlaJzlNL>vTR3?e*$'
    '`O+w$G7MocA$2Sth(4xn2)w~TZ^b@$SS%ecw)_ArF<xf7IRX7<yUYO=qeKFd;)ubXGcZmZ1|F8nK*-oO'
    '7HhOUi@`SYFoMTDo5NDgVMQBQ81m^)le4&bN&q}uKLQ~Nd|~_8-WS{ja3G}seg(M(rZ<P}CN50X65vfa'
    'V828>CXNMy(DrL9fvnq}Itb5~YI>({0HW7%8SGsIN;{@u;DuO2GXi-GD%k<=F@k-LLU0Y3jADWL^S(o{'
    '<Fac9fmwo0*YTCo(Yi3pdbztDt0}cd9{7ZUp{oOHuu(Tl*qb2qMTq}NiLwREWET0@*EfzL@Pa`4`k(;;'
    'TaDMY?({rFEwnQt;h+QW6XJo_<4GUw2M-Ji$A#aqT&V3vE<D32r|@7%<1pqi_$f>X--%0bqAy}gayRfp'
    '_!lio&~m_*k?VosW}#^&T-W!(igtkjJSyYZ0+EmHtbGt+K~t1udNl7sgzveOgWVKFV9QhR<$W)*U?L%~'
    'lqCW%lX(D2(s8LTLm&PD4=0Q*2F?u)LdR~0R%^zYyjWVyvS5<FC5T6D&|z`NLo2q4@WD?9(Q4T~wIeRL'
    'AIAanK@<bw!p=*{ON49~=usEMHI0!bKo5h52j~fWNf>Z2i^1S<Jn%TMZ#o4r4pzAEfrRYPb0{TE5wq6H'
    'rYYZ2Az*4?NyK3OI1Ct;11)+OY>_cX=Z=#gj=@o<F_WN@90!yw0aL~EY+*HC&er;yjRlenVTZvs05?2#'
    'Vk~4FIT1r!nOGr^JA4NMmY^cQ3I_uV`~@$Pgg74Y_?<P3Hx|anY<3S_x?bwi^%5tww{%i(`3AvC>IVTh'
    'pMGco0a;)Jb1+p!fNkKV51U}4+VcegJB>?89e5O`YjZ~sCuXi0?kkvl)*mgHcLXXn1nTg>Y!M6)X7hlA'
    'U_MhPiU{Qd%v9-e398xyJA}rd8h``9zIOrL9yd5|?RxgK>)A_P&)(AY+?;(m*E0&x4T&WQC>1W=c(Z|g'
    'B)HZ*WL$zF3Zm1ugV+UIBM5EF1KS#VsDs<W8L73F)S2ojFS7?;W>0&W_Xc>9cDpRPTd*Z0Ca@O-WRgp4'
    '@CyS_!Ql1Sz6b(Of|X%A;5viO1?7VV6?kFPBZ2RPktIbLSHj2W4_K%c@u_8df#(7$M98f$3?p!}K=y$='
    '3<40s#Ph-!I4gj^gR2gn7iia7C_yu_r_9Kt-Cf-c^_geI9DF7MG7W@1tilE*1|D%7xV8mU$vis*3Z+1&'
    'A-L3_n*#we2dmt3<I0xtd^{ckSD{5*?E0|8XfARTVsP6m*Rd!_2PQ)XHV5ct^qWI4D_!`T4|M57pn77E'
    'Ah3&|&H`{LB$zQVF(em~C2R>R?)2F#A6$DH3(i5|MigXV6e$Y>42zf%P?%r<+p#Aca7Q9fSQ4C2=@Xz%'
    'aL|cwashLtYIM*Ib^s<1kBFh{tCQCLjc%`6v<e$AFFgmG53tvQh(^?nC9{|f920Rc@4zPq>(xg49<Wcr'
    '{_uV9K_l0-IGB?yt>Stx9}4n%)=vvOZ3|$d6vMa@sA@)SaEKh(jL-@s4?rGxU@AEl;GcpZ@Evd$eGp%;'
    '8q49#0ppaqcMF9WEQpvfJd#3QvTZJih#U&iL3*GHz{2v>xrZHq%?O?lu}DC`g%82>5(VDbcsLxt9gnu+'
    'VY(Rgbyv*3Vy?n?sl$O$1Pj3qizJ$P97Y3g%=10R#o(B<V*yk5r4LiK2>5A|#Bt;Yw(G}kSV9<vf$#br'
    'A;O78KrPQ>-18{|)$KDElr~@hJ$f)ce2_21XQ4+K@nSzF;BtGF*PYq_kt*qNHx{S}LMlTrA;7Bl2*?I7'
    'P=N}-;c-LmV&@1a3<Y?qj>`ko-r%EJ;EDvWF@8{@RRq{4abz(cNFOhOyIufp6@bPA&B%j)0n;o1gP4G4'
    '9ymUj0|eu7>f$um>IWZQefIqH;{54V|LR%)!s$P|czAx%`2sMr4IzlEL@*7&N$W441I5YVnb#S~`it3k'
    '$DQTmn12JkNhFiJ0YRNq9qbQAm<pf{8p^?2n_P1FK4H^xAZE$w%^N|6eKN&@62s~fDTGo7Lm<4!0ISRP'
    'v4SHAQ4X+RF4d>B6;i!v8Q85NAay3Acb$zF6C~VUE(nNqUG7YY=wzW~=A~_N1lQBxdKz3W1FomR^%~N9'
    '5rvdTU5;^z_q7%<bEwSn!CZhLjanZ&!>Xy)K_1$nU<=)nNoqaRg?9qF{ANM#VSO?QqGEPW3-{h&JUe-J'
    'J1k4Ti;?YGc-|%kllgKoWw3);F_#LxKZiNYCLo``171km@RS|CzZjr|)^YE<-cpT!VBjfOL;PwCKF);z'
    'i)JRCuQvE>IKUc~<)(p)Na3ZRz+E8PGOD~DIwd18#nQc9X_iJ*qYP=76AG6`fVS**6Ic_4Ey0zGG8l>3'
    'tTr?!?kf(f3kmn~OtJmhm{+GoHt1i&@D+qkGHJxXVA>3uzyv%o$NO&umL{B)dws__ik{twyct|4l5aq+'
    'N8=gTeiasZCrOt9RgiA<97N#*1^a6a`qAKf^k%+J2gpY9>SJMT`ce<FT1Ht(rv%LG2G*Mt*u;5`r9?8D'
    'RS-5C%dSADh3_Y5yVS;R6-e5$yj;-49Y23F;9{hu_^cA^Y-r!5`HGzau2*hmd9ASFqg0;BE@x*;;wrib'
    '8PwnrNZIXKfA67~gGu;kJiVQjem$+d^-y4ohj&lNq|~cBQiarJptXTA6`OVS#RzjZ?^d>@3W0rAj^`ie'
    '&)O6NjpmPlLQ3<vR@6-ODOI-v2BZq5rh5KT=)hCiSMUh;*(51}KC3p|vf<5If5JOoO!4$!F;i;rLbaT)'
    'HuyS>dT%E?b*_x^x^LGT`swqtdM~cFtLC)p?sv*C@N?yNR7&~zXbxO|hNf`Y_wiKk!4#~2F|8!1@V&?2'
    '(r77F>DA21+vp9MRe$gN`^gZ@_-Yfryctgtk|_O-@(-$FM|&9Sg63=t95@(}vh-98<x))F445bnVU3dj'
    '(k<F8)d2wNGE1ld;Br;OAC*i62p52Y!L7iH0|?>yDxOt#A0JJH&_uIz%4&#(5gijmz;z`WN?*T9-2YS1'
    'AG7)8jS%zNFfJF@*U0wc(S?d0JtreEEN^3g0SMR-(?M#hRW(mkV#Mi!55}je(sMN!%F#}j^!4~w)Zybq'
    '4}T5LNOf9VZDkE|+?4W0fK<`(TR_y74td%{v#LIfb=oWsX@j_`O=RQsKL?w9M1~C@T#@Ous6bzvq+LPE'
    'fkI8+EdN%*4K*lm`DQh}lodync{hFW37NhY^Qw~csdC4_#+knRhKwo;;*4u`F<>`pm#cYKD-Ztku}bqR'
    'FU51LvRwWX@Qa4C$^`m&G?)*_P~8%*NSxW(mu4?q`!gvA3<f=agPrVa*+e-Ib?gA(kZP}Kmk+20tl}Dm'
    'YE~Yk;w{^9su7?%N-v4jR5eAj2&n2RSDNNmKo;|xGl9(=YrOc4YMr4}b1kt_7ehH4x3(&Wx4*u+dS2eS'
    'NR_T`mQg{PsbM!>ujOHEK&fm)Y(jtufG=7pLIM&=%m&w^YADFQSxK0sTXsIWhMC@04lyJN&d;VmuCrQ7'
    'Xp|VATs30V7iBBy0UW=&FkBDnR0we7Xgz)Z$)chp%(2?-WDH8=LZD|_1&D4|{($i7it)SbJ%qXv=4Yev'
    '+o6D=l@6^&u*(QW6)saNemfFek(<Wapc1~8!#+}NFsu2VnPmRT0iu<c`SpTUemir#QGScBkd@{?C&Qtb'
    '*NIJy(L(uZG2o*9xXP@n_2zd~9j0_^YUr)p+ci{2=KbnQBeUkpj&H`0PnTWu<$9}L9?+lwsP!h=36*h{'
    'd0!clmDXN#e7b`7JUN2b9(%PTm8@;6g3xtBLhCRpTiF}_y8=_ye_vN`b)4e@AFbjsLZ(nmI+3r(i|Opq'
    'Kn!_hY;1t3a@v*AHW%Y@^?+qEhgm&)JPBG?RhC)8*1e|ck<)r3`I@Rv;c$drb2V3Y1>p&q-;{c{OqHG8'
    'Ip68|^>Pcqar}$Lcup=Cx3^^auH2!1!AV|{#E)A_FlE39v~%n%nBLpEEPp6a1T#6GNQmufa4QtQ&8osf'
    '%l3xMACfsKpO}$*{Vx`v9rd~1c=UiwtAa>xFedkr$~za^5)m-$(G<wz*=!-6E;ET5Kth2AJ|CM7CJ3pt'
    'RNMmY5?d{aX;l$X04)(VnG2&zMUTPAsf@YwSoe8Suzc`FJQyyfr&HCGzACh(B>M)FM=!;&I;-RbGoCUJ'
    '$>8?qgZT}glDFle>|0?e2~!_JUbfWT$wHVp2~!)|hTCWkQbiNxPN3g`+ThJ_mq^m*WHA$GH{+73dl#rg'
    'DF1vg;^ViKfn_9elXsh7dR?kl2Cyavo|7rL6>~A2)q#{1?Dd7gx^Pd==j#I66rYtLDYFSr7ak&-NA;$o'
    '?zv;+V1y14;gtd8rR{fv*+5_Gs1FDY3AEB`ZPr~zVMQQ2big;+%EKpeO0F@qS}F^9*C<Lmv;jM>H(DGa'
    'r$t&ACo6H=1D`RC4GvOlt=1;bV!O2|xB}T^9;88}770Sb;IksqAn0wvvyCBAvDz5+j#{Y2j&FsV33rZA'
    'cqU<DfHhCn5Xg1!)&$r>8DbD{UYZyNeEvPq#pz-`#!~f$VXt}JhM^aE;s%G<<xiU!X19-RVuT_wY>JiE'
    'Ww0r@+XS$2_!~xTgAvxQt}H8qE^CJfw7@D{&fWn$Uwf1$q4hpt48IKrQed{S$uXF^6OOia|LrQ^VtRmI'
    'svwL>s44Q9)_twO)*G9x_G@a0nYMcSV<p_kurJAQNC|u0#vn6oTlWo-PI7Y-?`_e=d=3ME*fa&$wfb|s'
    '7y+x`1Cm^Q>l02U^HR6s^JA>nQ7rH)YYT-U*vgwU2Qj@@p;2WH?)I3b@iB7VsWIpqW~njAoAE`{pmXuY'
    '#=tXnv<X-_1G+K5t${@okP8EiCIROHkEQ@`+MSId7a4*^fMzYg#sIgOe&zsg*nE{i=Zh7h;nGu<QEz1#'
    '6;v#&3tHJkhTx_3EfZ_VFjQp+ElW?D0iGBqy$MR%d#N4NTiQX*pe80y4^5uB^KD-6Dhnrf&An0$j;&Ct'
    'dK@MSOXVP;y%vFi-xqjqrv9po6)D@yyhtl&mrs)_g7QeGwea-1L%ocJb!cZp5M4>wp)Rb|Z9|oR)ohuY'
    '*X&dhL)nzxqCAlsWw_V4&Upv0CYc#oI0jNPG|p3KZ)&VBxq*|~T^9mG;sfPc)r54Z!e)XmbB${slIJSV'
    '*M_prKhGvQ99|b*F`?Ey9L~~1trOk#<<&p;MrhAf6}BV;x)~@{Qe71qXmV&>M4okl<S4V=N%J~sws0u9'
    'zM(A+p_D)i@YfVW3x}#%t}$_>x+X)Lg3MiHtq*MD)^(citN<H6_gv2rZ)1#{cxm%=a(k!7rjU!xu{K7?'
    'nrJ5BuW@HmaKhvW#VXR|f#|w5))H(3;mK`hjCqM;5cuW=4I{vJ%OaD9e_JgYlY<mWJCg$xTT(_3NsA0D'
    'W2cz~c9%i8IaAEc+34LpB~8IjE}HN@Nhq|<F&JtAlaR+t@!!8e`JWV)HZa5t_O?HoFjd-eI$caEg{ms|'
    'A8Q14i&tnI{z{3PJVo2A^V9-pWgQrUYt$y#>}r-#+HJu6c7lB<O+n78=;knYYi1*-F<Vu#5$J`w*a+le'
    'C2Zz^s!01bKTtBKb~k`F)47$KY1M$5D!pE+SlfZFRH_-6D`nbK%Cs)jY$W{gXogkJF>&D*An8j>7vs0H'
    'nla)lm>Ix(DCA%?s963r2QE`*OJALBc-yXUp>+ePo2zUV;Y%jB$}u$`#VVL`#aPjHFL2wY8}kJV2%!x-'
    'exSD@Q>(wRL0L$4rd0bT-pwfZEV^suMC9dGg4W&&ttKRwt}})QrV2*oGX4cJq8McDJAL``R65D3rl8na'
    '@v3&rH?dlnz)eO&XfbOuPFhs1%J3bIg6%UgLaykdF574{hO=vX4aSJF8*MI6T*=UJf}y@Z6fH9(W(GX{'
    'CFsdiNHN7)9@wmCDs;*n(rHsEZIp6W;B#bSEMu=wteEm(vLsR&W`SXux<mC!m1L^#d_`_m``9FzuyR^N'
    'u8QY{_~l}t0wxRE`0jSW?CJ^mqS>`@V4B|<^Oj~2KAM}FJGai19NtO11_k{#f;Me1>*5wz<{1o6(NyV{'
    'vYpdb$tqK>wqV}5+omLG!7doJpG{%E*qTld-BXBeVo+zWv5cFhsIDhwcR_4q{}w|u=EoL-H+?Ld1jw+w'
    '<#hCHF$c%c(4my>Rh}M<)aJci$S@Tie4IJ7F$L2MM%RGWvVl_Rbvm12CDgg#7#p57tgV(PrPDbOJ6)(7'
    'Hq8patzr|ZcJmBFHZwzUw#+OIgzPf&Yi3%l?MQppRc8I|4U*!d4X1qz#tgfS8|DMa(2c=!=oI`^(Nh0S'
    'N=!}dlQrxZJHXteBGaJrTxG~6$?Tq)BaalY-nU-5Z*_sMIBBC-LedVcJ!VxZZ!#5gGXeermff}{)7}xN'
    'MOftoCN3Uxp}OU@DG~-b#F>i7=eNV;g<WH~DS&N=PxB}>>^z)J1*z{lY<9vRZv?M=E2E%{*myiSBNM{Z'
    ')p)bH=sU1rz&p`=tvWRr=I9;sZiAy4Y(bwTdr&jkY_oR2+O{@kw;dGN^r9`ywU@5HS!Tc%`o6(h?K&jf'
    'hK9-ZirG(CNt29P7JO4>Q0r1mOOr1o$jm;NOO{)<C^SNbYKlFLQxoU0XBSVfLcs+YUDqgdov$050aZ8n'
    'ly-N>o{}_FAbM7MZDy6nvJaAO>2b+!1YfjsX=VFphLuWw0~(!W?v@bK+dgt~-Mr`x{>>1diAeJnY?}&V'
    '7twiB`7pihAx0Y}#H}T3d^HuSU1N=_!<)SLbPSftcskX=s+N-$)@I%Y5szR!pzG2F;ZgVMwszyw?HsZi'
    '#k2E-g0t?eW^KriP|2=O$YcU2ubw=ZQzRFHV@VI?j9}BQCMOx$X*DC>^;xy!h~(yL^oV40gW6z;=@LtQ'
    'sW;C+md6t@n-SBcwAT02<oRS4*A2OKh0vZxs3F0AH6<fmzVwn|UD0ODaVlYEj7-Ht!3Hz4;qy$(L+qON'
    '4S5IHZBuz{ECw8d`ewy8{j|OTMl#-tP}K&TlN3dGi%#JP-90q?4P=g~Mf54IqW>0_(I2XHlm?w=pygD1'
    '=~PW{(2_>Z-wZe=x0P+ex`iEA^#TX8+X0BXVS}uz=Qrc|xKYYgwp-|`&f07-oX?tQ<Lt!h37oZw=_o)8'
    ';s1^OZAabb5Yk-T@1)Mw3a_UWYdE%<#Z6lWm@7FZ5=`|aGICv`We4Awv@f!#X=q=p#AAv96XG!`Ci>0b'
    '4frtCYdozt#{7;<2iUr$W`wE;)Z@`iOzWpMWj9*Im(V|(x7UCq#bm1ytaD6CGcV}2;N6_KTf>ndIkbkH'
    'R$2)ZP`A-S^DEM9<~)@s<2?lI_Zgtygb9c}zx!iEK7d?x{Weg5Kw(Bz2iM_8g`DPh5!Oj?aBDVJxWPUR'
    '#eQ0e6nCwMyJjE^q(}_a)3Y~N-?YY+u601qSLICWCZHl0UkJRK4|WRZIc{FQZLZr$;AUgy2IbDilug}N'
    'N-p6bA1G~N0&ccrIwov20bC>#(&YE4LUx~PY@6s900`;dXpCt2STDbR6Y^Z4M0v;X4O8J8rtWX&yjr=m'
    'NyY<S9E1rbcRd=o$7zZFCiPG+G3RfXlr~5+r0b>4ZY=L?d2_BYsH%MzSK?>`R14;4W-r?Di1Yp0YhRKr'
    '*zA_in~F%(ut%K3jj=Lbo0u{vTZN`cWyNWtR0YCKW(i|CDT7ULRBG_Be~k#~&l8N)HxLW?+hi;tM-;V$'
    'bz*Crz9DlmRT`k?orkQ!dL_P}H>rZX1hTYvtCyTkZOYZ^szzxyA^bU@c~ql6Zw`pA6;-=L0rops;-_xI'
    ';H`LWWNPd6wG=~G(Nxpwy9KK@X0vM)w4?^|cxVIg8o#w*XA^}W<5n>0mHIvC)^dOJCK|i_U&OIS;{&;!'
    'Yo1J-@wjTKlso`(`(1-*KvHB6?5pWwFh@ahMyAtu=(*MtRqK;$!!TSQ!yp^wseTT?n|gh<$}ARy`!5$1'
    'PlDj5$G6z(s8Ly;4VV~LYnG+3Wtwd|23v+~GY~slj@2Ki!Au1=^IK8Z)I@?i9n!_^<6Cl_r0Z8U6gL$5'
    'Iz)51Q|pk8ifskAGQ_NORMS)Ef$FTHITACl%;Inb*hovqLi<8xju0HJKf&Sj8A4O}xHkPpqEg=n7*8LM'
    '-V8Jb@J{Do(o9%xLaiGqD`?fRZN_cN&8>sBAvwp%VA#ql8BN_ehT$5^&fPoHM2IFOg45f^qHfL3RVd-%'
    'VoDm<580SjlZ2skMvcVU=8T%UkGZKClad?rY%!FW&c0<)JkU#876=d~O3S6dN3f1QPq(3=jNd@M$rxRV'
    '?G`Yskg)8;uFLgTyQ7&A0v7{zqwSLBLAPRfjTpHAoH6FxgxxZ0Oku#jJ{lY>m(!4lHy6>!R=H3&XO!Xd'
    '6?&W1iq;fep;(94rU|h*T00jWR7X&4ZC)o>s=<0I8#4(HHRHSuaE2TMbGfS9K=08xm?n!c<{s3I?5!u!'
    'C>~BOu6@@uktPeQ5fyAgGe!j)pj)N_j^icLcaki|MCwF#2~DT~LxwPaIk-+NhniRFwt;Iz2b<8$)udks'
    '-7+0u^c2e;XV%h?3^rEKgbdJj%!HmAq){&+ovqR-)h)Hg@TTKQQy6t)73<!j0#^5kHwUD_DQ^zW6_#t5'
    'HwIJvytvS1Z6!Xs2H2$A)I2(>y6-$#aM*-~heoMYnE?Lzc=~!aA*|J`qV=&%Cq6EX*i;<8O-C}8sJIlg'
    'xDnu|;!gA#ZUyG+G>)#VW9X8NC&m)5i-^a7Kcx(X3o!=?Q@2C>AURD|ca62pnRJ02*1sN81l5GUmsxKM'
    'ZJvuJZSH2t#tKY!ku8{dOXkkHx2nzGsir}5Os)!qX`@<&r40F3MTlx@RjH;4)vuFfpgb3<r9%T?8@FQ-'
    'jJcBA*;yIY_8Gti*`XMpZADBcIE1;TtSRh?UW9=$if(=8=%ab9?DUct@|R|<2AQdwIJs6=B-0yLjLgL~'
    'N`~60x<z+v&l0F<^0h&vG=;40TWK8hG!A+x4th%*l)Ys&ACHF`ttoN`^PwQGXNH{DWxL7?)mOnF6{tHf'
    'Qv?k=kFcwialqGm>h)godRdfhpVEpH)!fAO0EFWbf3H4#cH#8To;|&~I6b@SUw(b+_(A83&VgrJk;^>W'
    'j$}mr$fj{%MV@4#XE_0JJzv;?O(Q$-{lK$A;zY3weCcpc5*7yZ;Ip&StMjj(UHn!5^6d2K)ANh|gTJ~u'
    'zXaHa2i<P>nUur9NOW>L+PPkkDW84bncs-cRFGjuE{4Nia;c~@V`MZE)6R4;nso-F&e`J=fb?>7@LA_T'
    'PRF;M37Ovv2ehLzfjZCOSN+%IgQ>{<ik4XJgBvo#_j8{uKy)J_Gs9?t$s_xuj1)*GrWZ5-^KkV{+K#GE'
    '-vKB+TK3<IXV0zxdAO#-eqW`Q_K!}$f*KFsh{L0k37LW|HGAQ_($7CRef+fl<ox2RbJ*S|PafmTT~CCr'
    '7u!+59ozFF*Y~(frN;v55gHIKnd3`l%kBn@i}SN*7Y}j!5Njvsq0bHv)uirq@Y!ybYvtg3Y%K~RA>rKK'
    'Eg6h@V3}Qu9$E0gyypNN^=zwW`N|^h;#vsr&&Bui!=s}YT{%$7W!BwX&!fjrA3lEi6;9^8?7pAAczJ-W'
    '3kUO;K+pHp???%&-=>S9Sp9}{hre|@aty?Tl(f0f4|>$cPo6)!xXNHqxG{5skhs7A()MNS`)+92j1uk#'
    '+~T$s#sQ101cPVKzB|7-1+dRAo?R|yjtqt<ql|~XN4aNn_>a1raK|B@8#uPjcoYlag*5QP`${@YRAb{_'
    'dQ0P8=B{uLao4+^g4GKm<Nmb(Hi1XUWYBvp-rW!VbUKf1*V&j$m&JbQhSX!e7ezJ+z1U$SbSQUi8AR}_'
    'YkAz}ww}lAmkX?*0AtU4L-cWAU-^I(4eZ*<z>gk(bKZaW_^b2FEHVS%a$FjDu-qv2sSKDa10D$$c#-7^'
    'P9+0D<M9F@&rh$uMi83nKqA;~lyq)axzYNBIAtnLVw+G_RDG!bh{E*H4!vVQ%3_Kfg?-!-d$S9l{#=~h'
    'kU5xi7yw!;G}1j@0qJyC#@}Q8WBFGFaikkr5fw~QiaZ%a9s~BY9Kj>PT?tZ{$F?9qDX>_ZdfZ|_dQof<'
    'K}h!~1MblAT$s2D{Erv2kAFSzYy>k;+86gJnd8~=VuGTzKf58I!Ej|I9K>ZN0bvZkW%B8Z)@}wC0YnHp'
    'wkRhc1DORY_E3C~$aVzag~yHnIZYV+9C6380~UK8bGggC*c09o8AqG+oRy5LF+oOd@*fDpb$<G=!N2dP'
    '<F_v?5S1BVC^N@zQEC=&l78+(R&kv@`}X;>r!cj@y!!UyeCrem6~607R_xm$6V!D=#{oeb%gAT8M}6tj'
    'hz2~ok6!87crh7|E*2xi@FT5kG~sP70mc3L0+i_iD>(H1<4$BBcWm1_Dww<emkr5m*7+(?Wt-<6hpCNl'
    'g1?@TnK-(?8jlOv(Z-<)M+n{@T#vvO1xnFZ1wnE3>3A{Xhchvh*;nxkW0M0h19ZK>S)ZV5J2^bcFC)>z'
    '-IG+`>LKz<^<*{~!k>{!50CPLWWENnlN*POcxN=8>ko&?r|?%Yodd$b80r3D_vlp~9IoR8a3-enb5It;'
    '!=V@*CJQ+_?!?YfiRWixzI><DOUc703~)I=EY`dL$gT)yQ)Lza8H#Jd-r**xShCt3{S$0Yx`lvR{TbpD'
    'x2<@N$DN`v)kf&oao_~RHs)GAoIF@$K5aZyBudI`tzJE##arK`93J#z_cuuo=}1GKEhzGk+JkprsDF>{'
    '7t?BHCKuvbe6Qa*?o4I(uixkFwh#AT{Pq1m`SRt<7cXDFdiAFpBI1SJi(kF4;GaMFqwW^Y(0qEVTnrck'
    '49a88eqZSIY34fY-roiwGu@}-`Qy<cNM!_uMkzr1kP52flw2ynd3j*HJm~yM$Fl%T8K4Ey2@UkVGSK_t'
    'dnQy7&RL&=6%N0nU!skMzLFn(Ae}xRV@=?`a&7t}@ir~~aEBOs|Kk;7A4<@A0V5R=e&*e)=|U8}b~2a&'
    'x#z^(9pi)h(pAc6Ai;UW9qPW?>BJmw#gG1a-vyKkJp4_!SKCh*;(H@TWW)rTQX?4ajmSR&pDP~*hNlD0'
    '1rX07%_dg?5Iu2SED6RS!|sOy;gFaTn{zKECXm*@KpUltKXqSep46Y<Pu*7~q=&|>dPj3P!r5@2kE*~y'
    '=0hmmHBqxoI3$uJWq{0zwv+yg%qly*j{U0S1d|}giQdLT#SmhIRgu8&KDiO!^T9RZ7N}Z{km37u>tAg{'
    '#zKPU4+}xB9Nx|O;p+E{C$4^9`r;*pogSgGjO<!nB_2C}+5rg-|CWQZ7!5(B3Eofk=azhbI9=j=2jijm'
    'nWkIV`QnS*j>7PEdD*@}h)djU$8B!j^;AlUVaM|uG40`~8@st}#LP&K$Z#eO$>`l-qCYdDI0*faOYneP'
    'D+&mUEXpD;=F*Qsj1w?INaR>tg0d~Nw2ro`ITbk56y8rmOe#KiJ3*m^@x4Uf<%OP#$`xw1DR~Q|ad${>'
    '87*6PyAl@H4=Ju2&%eNDk50JIe3>6Hg_{q?!8{7&>u7OH#q=03ug+19J0OMNH?=4&EfZ{Pap+2kVI_3+'
    'NZaIX!a*>}yb#lGwIshX%iBWw;`<38MsVE0Jlu4*G^+A@lpChxw9`#{k?h2)7qAncBGMUbf%Au*2SBAN'
    'APz4tFeI+2R%3KNPGaTSwe0-)<+G>ogc$N;W$yf90Xs`TaLpMueD1s<!-ePwV7<4%yyB$f<TGT}eUI`p'
    'Yg?U6^$*?SF3Ps<hc2N0JsQ@_#eFEpkQu`hL;YY}Y6DPNms&T^`Y3;ZWkKxB`s1m#M}K!c=l8q)$&HX`'
    '^5=ISjtjlHqh`Zxi0Xp4u2Qi_AGCQ`Vh%V~O4D0>&;prqhu59}Eb!FtaORR1ce-;pW2O8Q1#R==?l8SO'
    'rTn%MK=fih+}DwCH7^zJZU8EoOIE?x29nNVFw%PB2xYw?NPmiuwrQMAHKo?`h5C2fONHi;dZV;Svnf(e'
    '=HuHTNEGq?0HcLFtP_-T;Cjt6K6rmHOAHe9x$yy%N%-kXJ{Cs~cTjn8;Atz-7br6gy7URwoe=dTyVVZ5'
    '?u2@{S~ZA*!wq)~MhyM#y5GH09F5gO)2NS;Xiot!^of+oFr6KD2*otKj>0M)3Z<(?*!g4Gt%S=47_nR@'
    '-MkW4Z1nq~#&@yaW^A_x-<3VFt;BcR4|Yv3nrnCO3~=2MJ;%u|EgZ0&UlbtoRe^cYOj$Qp)EQN#@T_(8'
    'Ew2fqo_5}<PhG3-i%y~Lt)+LX>D(gv*li=`PYAkyjnRJ6lds<6j@CaNNOJ_%;&&T@Gw<`}OrcjhW%L8W'
    'UJDRFSR;NqyBSP6OdUQesdNiIZ<07Q6&SzoOs3$}{c?dV=)n{QuFFnvw>H3hND8BMZqa2-;E@Gv!)T7d'
    'X2Gk$JO6$%0L!F<K{D}X{2G2F6AUYZk)&p?8hlR|6ZF0p>dMcoqb5HU=r@7|Fu-{vnNv6L$`B3nB<@@='
    'ks`IE&WZa;I#SlZR9#S%S(S<0ECWL0(eT~xtxwr4I$iH(J<Bbpj=LSZEie7Ze7o%`w`_t!DX59s-JQ!&'
    '3X)!7nS%xsCy++%(S$9tcJ^He$#T%{12>tznB@(i?uX|OzWwTMOC)_=libULF3OW$*nN2bbm!`~yTzjK'
    ';ATFb%<kX2r=<_5Xtfe>{|J^vzNZ7r2gm990a$lCuv_w4sP1`~-gLk7Uj4oEq0H-ghYr5I_~ufmN_Oin'
    'wd2HMnl9GodpFZnN>P|9=XEj|jkfrzcoz?QQLX!2Hw$_%{o5?TTyHR*oxD?%*-8z+7*hb1zL|17E|g8h'
    '9E=56Kgy36_N&z&K|l2{m8YkYSXa+jyLI$LOp{81>Kz@Q$6Va|n8VC9m~<+;m8KMPcGKgaq;Bqaz%Ije'
    '9Njhe3^t_4uyy7Li~7K@68Eso+v(=6@^py`PXAO`%nPL_BP!fLI5FeQwjAb%B8V9E8I_iZxLrI53VwCW'
    'prg$o`(GS(zj}Q2&H3riF8kk|UtB(Z_7q)$=*00(++23wmaokF=TA=`e4|gL&YxagA{@QmT426?{>`(~'
    'hyBxwtH+N{&#p4iUhURQTK2&*Kiu!UJb15``T^v`9avA!BauV~qlM^!d;lwGJk7mV6eeE`hs*97v$>c6'
    'Z!Km*WoVG8<}XPGL#&4cPWXPf4ChhEX86_XjL5CH-?;>Fpz`>&=_+_{yqI?=h%|PS9Gkt%uw&r}_^mOY'
    '&ThnTc)vr*>;|4kkh_^<Cgz=<Sd2T9!9*Z#OTC5m0$ORkH=UHJIzPF`#hZI0z(FYxxUA00m)$=)Ttaw*'
    'Y(5?x!KZ+Zmj{}26uI3A@8!V~4E)gPVV7MzJ?!;Bmd{l`q%R!!Z8*N}jVJTj7u{YjckiNi+xhzZ^dacJ'
    '!qJiyqfy+&y*T;Bcra29PR=Y|?O|f{qOEzSExVJGv{#pokB(ihM~1^+!~6$R5Q_Rv1pGQ0>$?ZDUxVK;'
    '{Po*wG5__;m-_#+KbeEQ&^_AB`-J)R`$)w7KAz!s`#MRg-_5YqGW8Sxr1<0Lv*#Dj)F}pDt2zJ6tN!Ds'
    '&%eFWH(!)}GhEQG(5q4THCW~%bNeWFg*xqauwD<PpvER@pTfs>m$1<FtCK*hu4w=k@)H;}Uw%Vh-^7`p'
    'fqOUxWG20j)V1-o+8V2eSIaEu8Ix-jfO9_^kEdXull&soQyWvfyipN`<x_vLfK3?4cPHN?J>w0<d&xD$'
    'lL`GEe^igH?vAFnv*}ReFN_x5+RQHeXW|_QJpNE%&MsTOf4}Q~^+RxGr&r{<@UmxNUG21U4=xrR^h`aI'
    ';@1mrfWhSZESY_ugMZED`c~5I81uAvV!b4H)k;Hptr5}Z2_~w(pRt?nes!5=k0}w;{+wLr@0vEd4_>v7'
    'f2sajL~CRWJXA;Z&Nf}U>ZK<n(?@M5^(^Rgz^_H+cd^8_NH6;qOgg<znPraW%RSvjpV_xo;sK-pU$A+J'
    '_tu%IsMX`PJ_iM*-y2-R-)tnXE~LJ`x_VyrrDtzPip{b7`1Xcm`kpBAQ7`4AUc!gHB_HZbqeYKqSuXq3'
    'vQwhst{!k#PjgpsqeT5uLZbReE}``G%f887US;_ev&Qm@Rzh9L3tME?1_$lD|5fUt{3Wsc^SaDD>+7Iv'
    '9-O}E2!59;rkt{yoQl~^YN+4+g66Ruk88P^ypvwIpS>H+Zv;*Z-vgyy8bax57Q9t%t~>8)Z$6%8*{$Ol'
    'tf<oq@b9$ow7Qu5zLp@l-#G|F$8#*<3TAtL=z)K02b?%DWxfy&wWCnj7G-!9(H6EB3qSTk&$dF>g+ExN'
    'sgA}exVFu$*d;+M9VfOeFOspeBHOlvv^~dXJc>N<<LxlA38hZNEH`8}^)2EAp<6|?!Ek|V$Bye!5{Ark'
    'i4-jIqab!Di>0(I7w_YRp-25l5I^#*ASNMoIg2eO0^eh0Oh_2U3uDVBkw+zqq$G|EV$MilM}&G@1cHXd'
    '_H7w5=2#MB6!#bnV^}R^oJO%%Q>Vbl)bo5>xP&^P=Qz?2BI?@Awms=Ei%I5MuIn?$vu&Tbfwb+A+A@IM'
    'kDbu=W2?G=f<c8BJCZQY1-C>P1hyYKHjga}@5tLu=th)yu_b)VC4>ex2?h7Pm;}@z9*szI9SoC*9b(%A'
    'Xx3vc^E^k&kjgONfkT8RBG<Kr#Y67nrF`!DJho#I6VG-nJF+<Q3|fr154HflvISv*!vYe7RvZN|l(eM)'
    'OuHPA#6l90$PrBVTyhTk9uQ$g!gHBjQd_}D(sj6HTaFOa2mYWehy!Z7u^Yw27Xk3AX9bQcLq87V(3KK~'
    '^MWYA02WNgsxH1^P~Q(+M*!zKt{*rN^?fglU_XH?eOQef#1sh5_c#pb0e=hTx_HwSSR&w|@SCcA#4re`'
    'IEDdeXn8)z+n^$5BBaa`u&op%mt>CXvVg`6w%Btc$vxZWK8s@-g*BA|jO+l!h)1D}nHTt+J0f60Qs&yB'
    '>w$~}p=G-y3P7HaSOl?8tXKk_y95wp1$I3f0|vIa>sSP+C~$#!W8yeYWc$PqVB>AdP`U)650b?4xqzt='
    '$AaCkNbEat=)182O$xJ!IIKkgb}f&DOgKPF4h78-`vH+IP=o75RJt+(HX|T`TuTbeqtpro{4beB9V;Kk'
    'wmeV3xF9My4+B7T3^<QN3G~b;Yy<GOMLEy~6EI#FL>9~`hD{=2Bnc;_{d*iMv;yA+?g{Of+MK%~jToM2'
    '**3FCz@z{I2m&Fc?Mh+=9CSrQgTVC&5Mv}8JC2If9KjvwaFEwFhZV-L2PzWuh7E!i$S{m!5b7QYB1Qxy'
    'e#|V8BcX3aECPI#jf}uhZr}%~2_z>hbci2HX88b=NEX_lyC`SW4xNaH4A5!WF%W&oEeRsmlaz`ko&&No'
    '0ZARZloOBOWpFEqVEcl=@ncxD4=bdx6-eM*26~i59{eSYBhTV4C~}uoHI$K%EgDD~!vMCBehex<2nYd5'
    'ii!*5Ck3$#$|D3$Ca!=z29gs#gC&FQ0UT8_6ayoX*a^UZaY!8D-E|386s15f4s|RSFb>n8ut4b(7E=mJ'
    '+rbmm*axWrob8gb5hNUngXjmYm#}FTs5S<Qm{X5Mu(<?=u^gLt!eKzFu>+hO!aQ7CMiLAWLR_awxI&qf'
    't_`~u#oY2E7jqy3LPL;0pw@tMd;wB{1yMvCP(vV-!QLUB%Ry~W(Aboe4P4<$k@0N?(iYS!in|bqLI6YX'
    '2y7bPmr)369<%~wpcKNu0vn74mS+J)$I`d%a%*siAhNmRfE`DHLfjB6&IqgwAU#O}*R_BT;*ffw1(HZu'
    'VD&JYNHADs7y=z7y0v~322Cpv=S*>05P;z;xCgrlq~bc%2hNv{?cxa(Ofdj~3vw~?@mU*~!{=cb)^o~n'
    'BLfQo3kh2&JsG-~xk`N7b0sn=>>&p#l>#;(26h0`*$Ujy#tIE05+Z0AHbmJ6cANzAB`yc|!~uy1W)mnG'
    'FlS*uVmknH0|h~3fuRRPY`LCfL`u)2@H6o%c;zU6z($FHaN-C|1&48uI}uPA(3NL_*o`clisf*JgwpXq'
    ')%pPlDqn!j4s;<&wTLj9P+%v=v2b~42f~d(VmlNxr3>m4AP1<~z}w+&<lC^#9_+p6f#1bkRQ9%Ts(R7N'
    '`vLL+|H`q^H38w~!ml3grR#bj;jrPL&%j&{LBjwG0keWFK?Bq>VCA?=ZL&RFj|M3?kicdjK)DZ=ELUvG'
    'N$jGWCBhCsyMXBRd}@KegVu}>{{<n)1>Xhxv|fk{y)LjY9MB&gs3w<#1qSYbWrL9oo{$A5Vc>#tw&72}'
    'ys)wetRx>CP8(R4F>nT}I`1eTd<h<^2do!b5=>6d@<H6WAjoXOzzqT?nE?qAi$$EH7Xno5fFBL$uo#eO'
    'qsS$U&%gzaJutk0>s;Tp0>CR+g#cfmrUdsYbU4U%z&F^RHe)=b6g{MvNCE_3C4PnmC}?}!Jg|Vk-~<Nc'
    ';AQ$8e01<@zyh&=H$n<N3;{Qm_#PO-R3OCxvIA*}`lkV?u4N#+C}I>~TRZ^A3LIyf0IM)3vIq>xW9Cq_'
    'xPg%Zun_GK<T3YLpM;hxYQ=MuWda5?_k7Q_h#iAP5HiFn<4zFUK)P`Vx?O?`;#(mMg>JtM5`=(-092S*'
    'CU>9f;7F8%StCHm+dwGb!+S9(Wzg0#vS8`3MBfGx&rl)Qv5${~dJsN%Lc*p&*yOwbiAjLviUta3JXcsE'
    'q8_j=NCH=iK%hklGErI<h@j9DAc>_1t~KmKV1W%x{c6!H6|4yD2&@nrWF7@<d5#B?BJ_Y$EMzAK#38UR'
    '2lfK59rTOm*%2rKC-4Qh*QD|>1zPpsrFlT6Zit?QEx=d;*NFN+s9^-=bLfNX;zxl^A{Qe~pjbdO$AW`?'
    'BVdA;JCH<P0Z|sa@QNK+5l8g_91o&fIACVMZpo1PAgKg#!At>k`+x@!!r(yIU_?mk-~%3-UY(y^oj>e9'
    'fAE+6i)TMq!9FlW@allRlc@wQldc^|-v$$l`k=xntdH6Omm!K<FaXh60h9sn1QJB86yP7npaw8z;A>3+'
    ';#5pCK#f>eH;d8h89;lH&Ke=Voa_H}L;DmQ6(5Z%3lxwC&g=Pk=*LO!b#Yb4<=esO=_Btfh|ayU2Ot8^'
    '{d1rt&pRvkws-1>U?e$F_$W9%f8^U|p!Qs=<k(?sp9c>fS<cx**L5CPP8^@QUfG$4k^AV(2aE;hAVA{q'
    '(L+Bziy!*s-j2>;-ZuEy51jbngNLDe8l8e~@2a=+g)#M}HpO`(lsCfo>SgEDdla67UGfN=!uZS!ADsif'
    'Be&GcHFm4fW|iEl54p|S<PcpO0W(N+d99qv1lLI0Bi+yMB$}jL#nn^@1@6zTr{l%sCwIR2;jRa^V|H1|'
    'Z0EcNGomI0((Mrl>I)&oRA7CT5^EZg+5Bgt@!Ju;dG&6hm!?<BmW`qnq}@!>7|pe@d>4`rc9Z^295+C5'
    '4GixFv_x=ickqY9zW3-+_|SUbKlC41-nske^z=LqANr@2vHxH(7;?m9iM2?*Q|i^N+uw9$^>}x`bakhQ'
    '%uM4_Cow5JKffWfQc{HC)2Hfq;R%_&MpzD5VP510URdIN+^Jc2Su6DpbzsNmXR-eXkK4e=b59>UI>p##'
    'Ns|R!^z#UOD*wTQN5L5Y^1bsgE^F|d+V(jRvh(mk{4fli^9K*3M=^NJCCrApSZ;{q3OLSK8Qb`^jJmF|'
    'KaIAh<nDZUweAY6YLYj${d1X_s^IyfZ=OB7P_;<0gfs=`27Uj-12?uD5_l9`Z6e*!4ZuAE>xNR72Gk}F'
    '26-X}&(<BA!Bf&<SV&t)8(b$U`N8p#@(HwaZ3tu@u?M!zm?IpE3D=1@qX2?Q%BY8D>)_Veu?2Q-#6p{U'
    '(qkdGkv0Y?D8YCJ4Gz>4F&1KS$*JSr%9=X|Ld8QUhMxi#mPlL+4?10oF>uyn@XTUQg1;F{ZrfJmS+G<G'
    '{9rt#bu8aa7OevzYL1>0S|MJRW{#A^VhBsHAczS-27s<7i4z1|gjS%Ul)~X2_wmHY3WNua`O$~ZKEp(P'
    '?5HlLv*cnS7GzQ-)Q&qtLdEdtzFJFi#qlsHAB0t#(gI<5zx35{=iuAXYg8VXVm%p(xk&F{b_S!#Vh%zJ'
    'OYtb+3bwv)p{gu>mR`g_w-nQ_r$Wt*s{(b2v-&ET6Mm_&u?!OYC7H>=t7T!O&pTQjEgwj<)9Q&Opmc$1'
    'GRgfZ1x~HghE+YmW0cYLy{VW8yja>%_|j|Y%qC>Cv9RpoG+fmmfe8)yIGG*Z0w_YVdS!*?d{6=Le3s&O'
    'g4bxUelwQN8sq&_WMIKJW~2`;^khDRuRrXZt3^x*AbE;W_=%X#-@$VeGMK`f?*O~wk*e0T+)Y*JVs--<'
    'z>{Bn(KR!Jlg}>BpPxRy=s&+WFY3`iLx;z}3694xBIrAzOFSS?k6Cu;bI)Ox=i9(&GKyIMgv~5G#<w^R'
    'Nf?3v$ilz)RyAqJNL%pT0uN7P;C0SiH?+J^MBvrpv22J3gVK>+V0$nij|s5_a3qY)TzKA-Iq0e2&47<%'
    'JSgX$#~l|-x-o7!R9K)UnG7iNcqlFI$Fb*zHi@L=O9$^QL_tLTSg;)UM~|O=b$;>u;_*|gD}MmatL;aY'
    'W5pzPd}5=3@L6aH$B9AsF$*I&E)2*+3eY?cl!Zh+;t=0+NxX!8`Rv<^v-AGrr+8`UT<eK!<I<b);`(O('
    'P)ODKee<BXAb<s8hBB_wLjoQ-PQWP&EmUHF>mZ64p)7P9$BPN)fk$lH<6Z;;(g|G3<5K-VI-4d=W(opu'
    'BYZEUm>Lv<m;=m8%XK7m@%)(x8rV^YT@5hEMX1jmiwfIzVi^NrSv96m7#v#_PX^}45^Udo`}iT&Z5xaj'
    'nU2)i!~M=d)xnBqfUvO)o;tz3-$`~5_ba&^`Q@>xp$6(E-uzu|6m^L6IQh$$+pXA&V`XuOC#!mOk4JNm'
    'iCC=882%oTIe9s%zV(H+_LiMDgq1w_EG^+MZ49y`D>I-Ah_e;cEa}wvv|FL}?Zn>3015jfbpN3N;g^zm'
    's$Sxyx`t#-5UmM>!R-X|XFv+;abA6l{G7qlM@d#in*dJlTCVlEN>4l+!#C9!Jlk%u(5$e*d-4MCg7CNy'
    '94c^kz|#W%3yd{sM-in0%n1q>hX;S>VaUN5;*x_yLy1qKiiEIXQ(!W^=gN>r5y4YGu()X8I9xJtIx+tk'
    'GbAF5M1*4&I16m><2^g#VdS9IQ+518gW{)8$Y6Ae32<2JgA6;mbBBRVJSg6mRUcX-GW6gX1?S-n-bs8$'
    'akyOv3snhlHlHp4Vz%ij5V;c3a)3jc9BeOU-M(zPy%}^RthuIU*h*%%#w>f`m6lj#pPbUB)@<JdF1CML'
    'vRqp;Tidl++qEp(uvYi0O;wuwCuRCcnSN5HKP0Ps(xsnt=_g&fRhMe#ywY{60tem11+1ole;Y45_{@v&'
    '+|>$WyfF}YR?LV+V@zfbVqe4#@dC$-L(U>~t`l-RMu8t>ojDXb>gw2iRTs%jxU17WEKxnF+a%(Zk@&4F'
    'Az4AW<E3L&!_i25%Fyh~MzD;{yj!MTR<}v)HfIszA-^G7T^2CTocAtE4J?}l9UB`Cn@T0+0L_pLV!zvc'
    'r0V*CP*iQOmQt|O`-!oc>*Rn{282%C=*Z!CJpH^g!nB4CF*X_&FC76yyrXym3p9%{+yxL8&&mAeQ0<6W'
    '@B`UNG9DE4&OKvj`TG2u=jRs%?aGcifAEFrQFM}kIbvPb#+{PEOmx1(oQ-oVx_NkTmgLhY67Cur4)Fsd'
    'gd*u$@Pi{$(oSzO2n^k1(eNI3x9)LLd6OQzd^!3<Q&>89gi1|l%;(Z$G{YN{vszx<1Dpx&`C4wAbRJE|'
    'zY?QPvQ?%~Na*+tc4M0p%p^Q{iOywOnY7yqqibp~%7u?Ep8ZGXPwk+;e|AiEr44R;OJ+$%m);yrX2W;J'
    '*>hPYpugl)Q;5?5^X#b8&XPN<_ntraOJfWw-i(I}b^o{XY&y7BVGS_^eLL!5nsPh5GnlP*2*pniY_A^v'
    'kT8>}#jVN(x51R_G|&Qn_JK8@Jif$I+CLnln%a$VN?*wNw%xfAL%?C4UrjBlCB9EGMVEK1(^}p0l{sdL'
    '0Pc0pzWMe+|Lez>SI;i~s>moaOW3o;1e*^S6lBY0s0R|Tg;mxlb|~#9BP~;Njcd(hfRk%6Kg`-YpRCx8'
    ';SwH9H@_uoR`n<*w_?=@7n9XZZH3~Ki_@Pcn{fgL=PmGuVL!NC*9);z;B%$uYJtGE5Sb<bWAp_Ze~UKx'
    'DtwT+)Swn^meP`4LddEdeL~k*tKV4gK*M~2W4!vE*d(<#DXOUMpVZn8wZ=o;DwS^5dCk-cfgH}hy-+o6'
    'FV9Xhmo4_HB1{oR8YlaB)k1Q&<Ko%RFWc1%ts71Hn(D!;lgW5;sIg{hFP@IEP2mqA$<nKDW+j<IRVTTp'
    '*Q%;nUIv_w-zJ;VzGbjt7sD>Vgqn<Flqq^>*gI2AkM_oiFJKjhofq-_T#VG&iaAf^{JUr0e0zlv1T73N'
    'lX;uua1ek6cUw`Ubd5Rm31&710VQHAikP`I`=U1#qr=Rw%iFZCjE$#6?)m`tjgeIMZozBRnZ&r{ay@N@'
    'UX}sNgb@#cn$4Y{rqUaLwi<2WVrWcIm84p;WL3oOt#JF=J?^%gk-om-u5QkoJ?~U@DAu@87qFlGe6J2c'
    'dZ6AlcR0a>YW9oFjtVz>fxayVL3I{Z=KQzMpFg{}QsKPIb_{tn9xiGXKG>T%oYYKc$FYaaYSk7-k(P^%'
    'v=X0wq1ox;{PbaZFoMMJs$-gAvm<DZZR;RuDSA?ivkm!kalTet;^UM*X=2c}5+3HQ4pjjp-5GNv(C}7n'
    'CP&d+zS@4%)eL8=l}J`InR9Y*SFTzbJ2Nz#=~T6LGu2v+^zJ23t=l}8`@XpZ*gGS>2K~6!GTYirY};>M'
    '+kVp8_L<eThorW)bK2TYY1?Z?+x`;TTFz(NYdYJ0v)T5V%w{&1ZI7vJd&^|oS0dXU^VquWaQoh}*!Gyj'
    ')=CcB-c#82m%;XXY~Qw>^VWK9L+crDttY(gE#GagnN)kscH2*~+a7Y=_ParQ%5-Zr{P82mbK66j+upL='
    '+DmfVlOAX@#m#(%+YgZ7)?$9!Uenw5l-;(!<hK3fwi!=t+iPZ<@x-=0=e2F5wY8g$wwG+QeI%ppITx+v'
    'RJ8qOqP3NXRw570aP*|TG&I9mX!}k=Ydr^T4=HGS%0O#90d0TzAA3tb+h_LKzLL-OntQg7)U)<8&-R*l'
    ')_UIAKGV)x&pO+q(Ai(kS(_<m2MzmMY&5u#>QGG`8W~K!%sHLO(c#tkr53sd^ZZviPX_O5t<QJew>4h8'
    'M~##;t~xT8QkZP-ttnxk8{g(T+MlS%B_nfjjc1S3F}dwe#r0q|*U?L3eVT5y3Q{fFa+!_VZZ|4j(*#PR'
    'OmVPv?yWIMEBtW>dzf`?+K^8B5l#nLB04sn9JMYoa+Pm0X9{U@!0bj0Wq&pYMokk1wwAvoj1l5`Hj_?d'
    'xg?0ZklC>iLFn_4(wJKTja-|%mc?x12RxQG7M>NHOB(p1uKe1lfeXV2u4RXINO?dlZc7;iUf?ilS%HWw'
    'JMvvlNKB$oN{;n!gD_?h7c_`tkILE;+1UcmkoebD$&5`0lld2i7tfwu-AlG_x)|AR)EBBUY9E<PRZ87F'
    '2r`x=pEtx!F7O~(p#HXO1)3PIDUV=h)n#|m<4n8N)rWRt#aN&n4X^e`w42N288iTXa4R5Z3M@v9up7Zw'
    'C^c*fw8j)EPi$Smp?=`#qgja=?*7o2y|d!_5A#WDs`_{T{OLo(Vr0iK2J!r3hGwwRwl>ew*gS>_kwNmA'
    'jhxJh!Rjwd*64P-KNDi2^8a;b=%mZFNd-YTnIPfJGNFzR9WO?lOy8-LACo#@dAW&(KE^!;x8zzFt(3jQ'
    '-hBG*emmkS38b_}Vb~>NlfcZcMSRc1WZpTQ0cD|1)O$~6Mpq^fXj>bhLUbk}XTp78DIBWFA03%DSrp)v'
    'lcX$|dwB~c@s_r<44I1CF*r_lcMhSp5U#KVVc?|%;Eq^vgf5J<rEo&q<$>+9kVGVM1QR|7uO*7TfCwuR'
    'p37_ls%e))WyREIerP+f=Q*4N*lArmRTP{k<~UMXJcvCz^8DDLQDFJt=sAK~A*{+4hNrjF%`)wYY>mp`'
    'U6PZx(*bO-w#1W<a@WsN(`IGAuZ6@{w#+_ey`sbir<dpbZF4y?<203ZrS`IA2d2ftkJQiE?ftYr(0=@@'
    'J9N%|D5^jPZ1>Fyq{EL)JXDenpc6lQc5(jv^zlW1nGC$jMeTe6YOZ{rqe7*~nL`;DOh#V7BgY9iwPGFz'
    'T!u_wLup1R3mwPtV#0ag5!?2-7ln@P1TN)qbqThi_=F!>!uLYTeV>QK;?fb)ave$CIEZ5+XkbTSXxWSf'
    'mPe@19gBj-b7C3Wp>Nfg!cOJZdW*=;{<=hV_Sh)0Q>s^_p@EvVoGjFlEi^ss?4$2tXItw-GoV{)px9}#'
    'hhnGgHj16LJ1KVBX-wSN%rYpHd9MZR!{vNB7+ssIMw1r^U@d|125Wku$9eTJ@^c1HA0=58Z9?LTmux~<'
    'Xja%!BqBQmPg>H*wnOG~76h^7*x<-U%yWEZ`BoeU)Dl7HgoL<`Pc2K3Ku~aTD-yzHht7Z#&y^vMA|f0@'
    'Y~Q7U<8aA@?eiEf-*PZJz}e@P1oJ1brEkNy9Hxv`Pu20a8Wca(J%I&JIs(5TQ=NBYut9h6CaroKn`;BT'
    'zM9E&@CF<%wW?dNTZd*B1PghBP|Ym>Nj@zuupi`~WLq{H+=)v}7szeEObpevp2rW(tV|08gH6QID>>XZ'
    '@tbM3{sYp?k&z+ao9zV;v?fnhTL~(5^~>i*CagwS)&coq$+e$rL1QN4=wLN#wHopL{N&cG#KEuriZx;0'
    'igOQ@i%y0r%zob}jh?WZ@qmfhi5yI4^TW3{VhSS|CICahpRA~VE)+jJ0qjfxGqV#_ngtEs!#}c4-XNmP'
    '@WK}>YC0JYx!QsgIVAHZWYT%R*JYVm&<C@7`{C%zlYybzp$e$M`DGPex`|i7wy6<rn$E8mWXiQEPTqD3'
    '2*-?mS$cSe<XSoU!#oco!-?Tc0Ousf!QKD+Z~l3=W0)ut*f8Z26w{qAzcgs%9D)ll)|D#ME*y6VxJ2Jx'
    'J&I0H5B)e<0a<{KIryKm@vZ25HxO@4Q~y))W^k>n5Kvm|bsI|L(Rg~>23%!uO4CNdV3w4|I7|h>QCpKY'
    'rD4Az6s!-9)+NrH>F;0=bWm;{z7bOjJA7-_20_qAicv3>=>rsWcp^rG!c2}jACB8Yney^*$@dMZa)qVt'
    'BxkZK1M4Koq3fDa0dqvoQ*sNoT6b62rEAD$IQnsu?RK=!*mxq$Bi#hJJ2vh_0`nc7Ffvh&U3(i~NbqfV'
    '6oc9M?PUJ0b<Pqv%16pqKW?@Hb$d?O&Efjif*R}SA3K9lyVCi=Vm=>_4AD@|v(^g$-=*_msRP<w3x0jw'
    'nr+k;5qzg+d`O0a>(Q+;22O@5IpSJdGqq1)@<%Z3$G-Ox`rcpUyOqFqD{=4rhrQd1AeRUr|8R&ip_0sm'
    'e)ksn-AmxN)wr)YKfhf!-{7UAl&V+stTgfEjS#@E+QKlxJ?mx*FlQ2nGYfth-7|`4CBo7O!hOSZTo9T#'
    '?#!`l>Cc3boSK6|Q(cYFHIFCd<+VEV)Q?ooMyn$w?u>C9k;!EE4&xjdGEko#4!Duk{E?N_eyfnzhvN<#'
    'j<Gi8d(+Yw!DfPMX2KK(MY0(v_wL>6T;7nW;7PU7-gq>8*ZKDGNk>zTx^MPI`C~>AJnOv1i*z$FAyc$p'
    '=kF#khdG&Ei}}n@U29O`w`4RQu-S<bWc~CB8H`SuE)b;6?%900FwzBRm*%=}TG^r%Zc-b**kVj3(Hi~z'
    'm02fZsctjA%Aa38d-|o(VKQ3s!FX)e4_fKOG{14BYs_Ul9<0=gx%9y08WPEWs6iiL>%H&B1HKf?hekYy'
    '1gbeFdUw*2!GxoXx43tHGeSMv`Rv%R35on=*fiP2VFt!Yfv$7damp4y6*ERAs6`Eoww1?Lqa3O~8W;=V'
    'A9dPr*fohRW27^Ku6jbL=&C0_ey#^y(y1AreF@GydQyUgiKaiALr_Zl06hIMK~PG-X7H0jOMok00Lbcl'
    '@|mJsLlG1NWppR@ktKJ~UT&P>)VLoYGfpMOwUH0E*L1jp4@P&>U^1NHz~FvT;kIYOEfe5Y$!jKPaDVh>'
    'DE+Oy?6+OXZySkg28L@b_wAz#iMNvY)>7VEQQF(e^lE1a{MwdSX5z@od~VuaQ`7d5nYO3IwEgDK92kuE'
    'ZhUA6<=>1M84i9WxE8@+aUZ63{gG*mn>dl!drsQ6l(aUo$hK}t>J1%zj7-qlE~M#SnXE5kPL-j=vAgre'
    'GJc{FgR`x)vAt!D?ICIG&YZE@6$!T07hC`O&~AQRi{M)Xt$E^*FkMjOy{XJ!T}5QcX04qtXA?NL95w&W'
    '+!nybvD4d6w*}e}P@RJlKA0&h{xBOzG;^PBG#DP85QeQG26QkS%-`v1GIAiMySKX~#C_-_Q3vBh3vzxs'
    '$Lbz)G88~QEl95qKhC?zC!?j;e}$(2hufJs$$I(-@1V3mk0)46pOUF5YShpk&&BPbs@!*LD69ZG%*cp|'
    ';ZW`IDbp#oW@epe;;vT3$v|CG(064>;r|R@0RPe5cl}`QRzj-=;KBZ(w+Fe%xJ1Ly%)#i&w$ujY>LYVT'
    '-wz#!GidVt?!@5?Ii&5Gdq1?b*QT+z2V3u;UFl?kbP5f<f*@j=4Du1ib<I<vQ8RCwl~-t?897lZHqeec'
    'sd`g(6{?;eUkbwSWD0yHt6Qq8UTjEaGlQr9m)IVn;D((M?$g&nk)e|dq2>a)Np5@g9^m~>s(^4r!$ITS'
    '^{#cHY9l7!u3Fb7i~qJ;`L{%k>!e7p*`bDl%!Fz5BnCj{`sp_~jPc3q3nus5<8Ez+U8!M=&;BF6vym=g'
    '5BD}c7`@?;T&i#NMm)Pw9lut04~#;m!!dh(zw=<AcKXjUD|vu_`H8t}70(xRIGEiCp5_FCOEf=HX;KD;'
    'nB){uRxKI6s<CCukIfuWuWj{lx<4kaP;A@cR&x2%Yw+rOn%JE#&(w){0xkisPz6J(??3WX*uAQnFI!2n'
    'RXeLvau!pOsA#2^&0OpHgD*Ox!SFbvnDO4j^xc>H!Py~4o6N`tX+$Y_$60B<{4wEjGbOPP6s(iCQ!<%|'
    'Bu#$6kJ^Y-?kxv;b4jLd5@^cOqT_+e4$tRF0|~a1B|SH51e#4-CU3}Kh)$fo*b3-KI8ZaC!O`Sm#5&`N'
    '7#$w9BBZir0mfaIBE?9g3~_S2@_WqOS=u32v$q)bcm*LNz*@M9V3xh|8{RolHk;wzSjiUYhU|}5u#Zjl'
    'G)n1UJf6b75Y-_~LpL0U*c>MXZ(e7tA`xcw>XU`u@rwlhGRTo!7BMhd64_ASj+gdZA_I&g%A_;D+m}y9'
    '0v<7M?0{gOCS2G3`t-7Yb^2BJ$neecmaW0$mVz4WFqQZw?g;}<vU2suc!NnP=T*g~zUdls*%ETSpCqP6'
    'YuW&BNOrPa72wxD{$q1AzeH3{XD>%ng2RaVgh?+AG+e=IK`T{c=!|)bqJvS5ZqsrFiH0*e`vMJWXx}rG'
    'q!ngs^Ii_n7UEOIY;*;Ms@V|ke;CU(D?YRtZg@l5^8Zg3a~Yk8p*p~xo&Rz{hAYvOb%Gy1RF9exRKEiu'
    'f<iQ@Siz4~Wv}i&q*3G+6?Yq6dtsGGLtcAw4J@;-#nm><R3=Pp4!pJ1N(c^-GQ!LD`-zPz%EBA{8fRt_'
    'j>b7lc;#EIG2V|p^kC#xQ%P}$du}SszNXRMXLkeWN|BdYOs!>y|5)Xyo@UnVSrdIm96@=fm-6290cj@*'
    '<C;bou+?CS=RfZ|MZ=jLjOz2ut^4z(sp^8OgVPM~pBPqrI#8+P-up}yn{;W%#tMBEHHX?f^DvQs_jw9%'
    'Stq@feEFHi8Sv2`S*An$%bCB=lqSnxYdQK|&wDgp#WrtQoR7e8F<!*>BkzQvYmgSqy`8oa+mcW}WzHzz'
    'KWOGmKi9^>NMX_?X&q+$<@<>aGRGdbdV6=IJeW&(IQso80hYB9j5i&bw9y?0zc%jdWd==>0ZeGZ<9*$r'
    'yBUL7@aY1bsR-uk(%c_pD|)179(Uh*%j+{mQY~D1JDI7@F@w3dHQgp9^=+1xCc0EhJ|B!))BQ;^9J5vi'
    'D{NDhv7*gy4MwcU=o)Nw*=EKEZcG2T(>Jsw846gs(ybupAut#yepA=v+MV~0)GunS%SQo6w(cK&#J<I+'
    'riYdA{?YY3+_sS89}aDwIv%#)@$gfp!{)^Nsng+|#?bFTr^7XG=cDR%xHk7zyB)5L^{L-sX<Gg$`W+gn'
    '?b=$shr4?!n<*aGPRWP8)_f>i^ufePx^Tqqst+c{S>4!Zwd_NMx(@~l)wNz6rBz<}9j=aI9`<^%72_lP'
    '|LwhNd)r2mF#27;f~(!<r8uE!+%NKYW@U+<=!|3gNOE@HRkVC?Y1rIQB$uS(czpEVPxTGx1{xQVfGlT}'
    'nJ1x0pu4)dy1MRFbp$&=)%Rb=rS;Ke_VAtDrd^g#db&)XF4I5IW%^WU?CCCjx=X*wU3znWe{eB=e{y~?'
    'd4DmUT)z8oaXOw{y!($!AhWOiljZU`Tlv+e#ofnGn=_P<rlO1adQ5zdqxI)$vH?Evb}>i5ZNzt!@d4=z'
    '{63znKLv*EU{<4h9`bb8Gf)zGy6#4H9664!8G2+GUSt_|q}iJ9JE4Xg*KmWtH0)5*P~f1@(!DL&9p!Q2'
    '{Gk?Djuu6ZjgS=vjvpe!Hhs;vv;=?)Llneu7<+~VzsIf{Yql9DacFp9U<X^z|LJc2>l!A$&UbO?-V0W*'
    '%CvV=J%}T$8&6m_uCRLKx9$vU)Iz?EX<BSU-<b!m9{=sggWr&5+G$+VvZUX&FYsZUfwBb}_wD?B)1FuG'
    'VLN&kJ!KvA_HMt|%)@v0mNRZU>GS=tjlNq7JnE#?cdN}$@V_3W*>^>^?}ER$wLWw072SH^#@`)w{;q8O'
    '-JXymv=8sB_jl_@p|dcNj@y5C)&E=B0K8=(L6zG0wY!#pZH!yip1gzJ;t$(g{M&c3Y_YxgAF7jOw`k`P'
    'Jl|i>!47(imo^#iM5Ac4V|mpUv%snE@?1UcW5pYv=eHK8nY7xzyg~o+cH1WRx@%zma2?DaqJ?>V5A&8f'
    'Og>x&NT;UnrxcLKVD|1h2c*J){Ou6;lm*g#7D(%M-=}Plr)-e&JN*xk4WjA*|9#|wDD}urGC@@8%u^mn'
    '18)31<bmuz%Jb*XdzYVr6^enY->o9_Y%!mG>3ujK^(f`^f_dEgjp$>oB6!{V6`>{E;>%!#<=4%ZCBQ(-'
    'U#`idtz6-^!F)4~)}!wxBVKiLwVo3Ho%c|Dp#F&@<S)A=an1f#$Ik9VUdJoDYxp;9)PYT}l@59;GR}WQ'
    'hbFxZeqK!Dlr0~%Rhbfx+H%dg(x9al1C9i3@xjkq%iTxv=WN)r2#L>E%c4ou32UXi933=&!iM}<{5x7l'
    '!4lu1EzDMW#<E$C$d4_|g~#ut;vYK&sf~2qqN>g)6|3s(BkPu#(rG(7dpcbE=-~v5Yn-!>?IDQMJ`B!3'
    'G6Zn~ZU;YnG&VRn3otVI?+c;0Y)cjtJXEVY@eomR{qADp+AdM|@R4yOFs_SuxCae~>$h9Zti@os4x9aU'
    '7YbJ%36}=IWx;E$G+ll$dTS~Ct-I*As^GUm;947HZo7(o`|eEQodmvh6!)eId&@+xZl=Khlm(Wx;j(H!'
    'Htj(}(;gx+?STT*zW;K;Ey`pB<!=^IFq{4Z#gqku#C^o&`a#<mZ^I+;;4x`sA!%Jik(F)<*M<h)<00s5'
    '7kK!W5cSnw!?WqUQ{I`zjR|^UD*|U%VPg*#HTD2OW3@43tyFWVdhWj4___{<?{Mfsn}e1je`$?}^q6(#'
    'VHN{8OI*!=m~4T?JejU;pRxtIVNhaE2hot&PCngyI;-yqq1^6{5O>czs<lqEthe}Ry$NRMaL@(!x__Lx'
    '$fJ3x^<QBxz)|^OW>HVyVGc?M^f=lq7PGLWP7gqhbhPsgx;<LXf(YHVWLAJ3j)HlFW;3$KCsBJnHhX<`'
    '6Ccv6m`!xp*639cQf)Qa6l~s)F5mUOy{v>z1;GBpkKWzLD&exFu9uQ*Nd?O6tM-JxZ*7NbQRMsM*x_1I'
    'NV^mFzO}U1rLgw^vR=Pi?$ie9C<Q%*5s?Rje1~@34w})mDdv?)c}fYb6_1iyKpXb>^+x0>eDyrO5QIN^'
    'pR=cGwBjax<7%|SV)@vXTEkZrZT=(Fc+Hn=Zg;8~3f8D?^e_QHNI!jpr)eE{nqbml7d0w|U6E;8hyFXx'
    '+2BiffV_?SRx=z*TDiBJi<4{V-s<SA{dj3>_x92%-rt3@>G~6jc}yUvM4JH#lWJj#rF0RA*HX)=8YNpk'
    'Y{x~N+v+yk!<TMxC$aoI4W9g$2X^!2wdE0K!?EEBs$fd;-$xz_`=D3NUpoo1rLCZGNY32~u`8O~%k89f'
    '{maYVd^#Hn7c<U#Sbh2H!{F>F#xhxpJ+sMpLy?=OAK58yrzCctj5Yea!i}w2nEW&zbYZD{uo&p#lG@57'
    'pp->f$14&YF2_j&33d}Dy=hknY&UE<_$`>uuo6cTTLB&H1kyv<;%v#?JnAi$Xnr*4gh`2F0k*rQETt7o'
    '8OF&l(|g*<S*qZxViv;#rXUCmtb<g9c8{05;k^-&*;?-K#I^{LjwI*V*h0^z_UK@-Si!yor1uFOy=6N@'
    'aUMQ=`*%iWiD>s;{ppVG_yrq3HFB_IkrrlSmJRZsVJg2d9?&|X+EnJNb$K=uoRRj09boJ$cIpm)Jh_})'
    'o&4=^&~oN^$I>9nQXrEZagN_co-p7<<g1S{gNa<uS;eMF+coCI5^~S}!bFYEZUdYl*%P}ez@Pu;|FlQ*'
    'DWar1JDrU%j#jQu06G=W@Cvd8Wmi#4KIW2(4rXn2o6;4q8?II86*p*0`z}xty)Zk2JDs2_#Pf@})fFhO'
    '=9X~(Z6sHbeNZvH<qhdd{~z6L5^scN#DTpY|L<Ke%UF}B1fQRgN84gle*hDK5>3Qb@K~?xEcbz1kvqJ&'
    'yU^N|RU%u`+F2Tyu&?TB8|_pkWHJZN+UmpvhmkVJ$@ULp8zq#5Gx{mc+6g#XNRn`-TjdVkqc=UYlGW6Z'
    '-QhiN%gmm;(Y}hi0dz&kt6faxqQf66AEjW5YEO>!wW0_nwOY#8wjHEBX2xwBVQ{RbEA0RI+EY!}?qnhL'
    'XO`~IU)!oKm^n^`!T-|o#YYX5gztS7s@U+Q4O=VprD_gU^m()qfcJtAnAS<}Bwl_^aR%q;-?X+({3+yL'
    'h0<hlTFc;%9{1RK6<b-d7|%g)X}yT;cistu)*w~D-c4JHvLMu_$Qd&DH;tT`NNp@yDNLG@){&?$AG15C'
    'z2k99x3?nXp}l~I!9QmSFi}Qmz3IrZi|#o1pF+-_FewWLXyYavK2!$Xrv-=wPYHBwSunGtxqlHWdT^gd'
    'eb$?NpAnMkAn9$iCY@uZ8+6-tn-s3wq>?69snT;kop*Nkvt~H$N*R%|O_d-;x4$*mVin9kf~=l&8S#O)'
    'WisqdTG|qU0#a4F6Xcx10fURbtu(oA;eMogQD<E~6eqHC{pdT^EuNYlZiV;nuIFLdLWbWCZBHE!yYG1T'
    ')ah`4Vt(p$SSt+u0XiM#w4Lv&*I^F!PP-lE=6dRP*qD~Ti++dqH~04k7vuLQ=NFUr7vst0hxhN_U0lJ%'
    '^tFG5)|>Tna+?Rh7C)ir*Y)!ad^w3gRQw2ZF<C8w+sO)joPs=0F8R^&3$DiHX^9nu$VtM$i4zCKx}#YE'
    '3f$O@li1Lb*tgx-as9wSmaSQu9$0>Cgq{}JiJk<wB3Q-zA7_g&m`&E8i$$LVXi&8H4XwT~AoM5>Y~S-d'
    'JwRR*JEq}=9!gBZFikgcy(qA>*h`$q@Dl?-^Fq%GEnl;>7}>s_)BphoB$>_-%o@a#B$&?bR``$G#Rg4+'
    '_;yNyCK)J+?`u{V#+DTuW*7xQ6l+F^G{<tI#0euSb`veOecv)&J@69EP7D+Wk>_}!?W2f*f{V1QpGUL1'
    'a1!0EH*k@zCNb!ZSh4z2n9|ciK)-MMj*b#Q0}31`2s8s}ny33Fj2pwMk?T2HU?MXKV%I@-q$PnC7>4f('
    'Q*H<j=+47xVY<os6G%3bHMWXRKEduUQmh9NEYGy`C^0<E3>*)ZsQU;xt{uB!=*OB9dZr$mnilDS?Zkef'
    'yRjdjI8H*xMm1P3TYd@RLmeR#=_rUCBXR=A)qKw}H64fy8Ln=|j&4V8;02z6A_ORjW6!so0BIhw%t$BD'
    'oGh2mnQ(CRX>s@Q)8-5%q<_(3z8(|v#%TR{nr!flab$#1jH1M|oY*rACk{0~_Td<~5po?5$S#ar!!RsA'
    'h-1eJblr+A&oy+zF~ivJr|0p__~iBE{mIpjmv9`9wt!+NfvmKIvL^>H*U8!W+wtWk%ye-%o}8YX{y3hT'
    'zx{cP|N8O6+rQ)4uaElE+vQ@l>HW_dD?rI=aSN<^`K8CcjuBeozu8YX)_~9s|9!T)gL4{v!u2NrJZZ50'
    '0FZpt|M&Enqub#3_4FU;rOsGpKSoJ!vJ6&h6jRp@Pz7o7a?BpU42?O?@t~vGB8b=I3HE^eA3R<*&SJ57'
    'dGYSu6&Y<<^E(Arn2#_0NC_a!kN<}Ur0rnSpXp3hfS0{ExXD=dyVvJ$@P57ja3$^*XYyn>$Y~nMr)gBf'
    '$oa;>M&d1r37ebF(Rw|h;0TB(f)4qTDKv+rZyg<BL_TMXWpy{#O>aUigxRzB><&hRuafAhqrqTAy5XQB'
    'z{(-U+hJkeEeFP3Lda-<%ma+%a*zp~k?WSWN5WRj-;nw_@>sH1^+;jLVUHF-$Cl0&f~yJ0<EX)jW784A'
    'NE+uQ{d<Jw6dU}9^o#VpX+nAmMT<KSrpZeKoQSF)OLD_1n65z`!&<_4wOXu>`XA=M&KI9CxNLPjLe;Bh'
    '1Unqv>tz5Z;UF6Z;|0&RLZsr?kp%Xzr_*Pb(>cz;1bBgQ#ldWLv<eT8{(3w3@6&g0uP#nbuO^p2o*1@+'
    '>FDTMd*%nvlAEuNbwB9;8%Ve*hDo`~`4JwEE(;{OUOfE>G<_t3fgiZmZic;ACm7T6Bq`DcWDN4i#fP_V'
    '#~18@<AZuUMT^_z3~f+KKO*K<2*?&bEmjO!S+}PHN_7BeFkPjx#B{#A!;(e%o<MwcR8__hS|Fws`rkWj'
    'pe|6<OF%uabB+uWYT09pVT98oYw86taboX4H03x;vBXc{GT3~gRH8VqmCtjk!rzc|j%|dk0-iETBq(Bg'
    'bNTMW#c6udFR$@jH`la;EeKQrP+b3pU=t^npwB={DRp5$dLVNxIYRp~$Uq9}Sw!Fn9)ZRP$xO&*VHk&%'
    '01n9n&9@@G{b=(-I{$C1ji_QPa?huvPWJ}=z9a=eg$15|xVRX<z2eYby!(&K5q2lSHBsCNGU#<b0jU*>'
    '=V7n`g@Nw=x_>jmH7m&S@HX+eiq(kw)Grou0w;w19OxXjWAlYG#ns|7E=2r;fH1=JR?`JGEs9!J20BHu'
    '$hPV8({=CdVh(C4HWOB_A~yt%OFVA$3bA)Czl>4|hD@E`g2hb4zMv#-i}kxDmMBt6myyqoOx;-}w|wt8'
    'MX@X*47T4l3Xy8l8m%D3BB1C%asC+}rGzbV0*u7mWh4XNKjjBMp024<E8ZrlY}%VIaHTq|f1y~uW5}%K'
    '$26J#PF9xZgu@<7-c1iC+h2h>rl4cx<XCk};HUEA0B8GY`a5Q7tbZK?p_j?Ed0xd3SjA;>Li3=&$=QuA'
    'gNkYTWsS&}9pF8s7MQGfm1g1#zC(M#Jnk`JB^7mrV^P?XQe=YUJD09mx>WdgQ79^>#!NISyW8-hauhAe'
    'PD6o)Maq@o#IbGofEKr&A1Prcxonf8Ix0pqk)zUgQUU1b@a+8Z^c~!H|9A4^_|1C&|MmIXzl|^6U!1?i'
    'R<Qmdu!fVfpUy8Y&)>b3e*B?#*gqT;g(Y&IHy&HSUz5R$k{De}DvJGt<&ycwlrFe1#)4xCgdxgbT<~IY'
    'n7+;C^UZ0t`y8s;?dK9l1CfvMI;@3@M@1=z)XOaua!B_ANG4Iw(dQcRf^H+Ik~xryf(5zAzlB(lGC+<`'
    'jK!0)v+)@hC8(LJh&}#rqw83peuB30+r518${RjM3$PIwrtyCQ$7G7uE;LXn4#6Bs&44ML)C$W~t8g`q'
    'KccGj!sb(GIhjzbv+Zg?6Xj^BBaJeVsT`hz=JJ<#Biv-CK;}hTjCXo+b@Jxj-}2+}uZ8hyB|ZLXPRbMb'
    'VzOHN1I?*scVTQR(oL9uF2}cqjHP0y@+t;BFJoOf7APOl9Mel{&|pGmBW83>FXZf@>puRbfAgY8c`y7%'
    'K~1fYFyuVAB^C?(==Je4{pL7(ntr&(k7QIuUU*5LhsR&Aa_;iP^t-;q=lFAQ!>*UJX@vT+(JL*CC{FvL'
    'x5gDn<k87jee&C4ng40A6s9ew2|C*~8R{6nbwde67>jjD6i;{vcY6%i&1|~fND9Ba2yxgV+s$Sm+tI%n'
    '$VXNh5U_SfVpL@CMH~U(fZl8)$?lOfILtqkxZtBUU2l2{$eJlHTW?mBG0GT_cN+VDe#4z6F%whLQ^u*p'
    'pBrN>A>s>~#q4BZ6wo79&iL1e9m{L-<_+0+{3UsDP_=&YLN8w222;_}DvpMov~v>lE`H0FB_264+kG>>'
    'CCDHtr{cg-N8dEU75%s8RzxrdiEDZrd@LH(n+x#e>R6q;U1d?;QZG}g1UVi4Jri<)(c}K<csJ3SAPh$A'
    'Z2+6hE|FRjvD1ZC8zB_P@Ht<sZfX0Hyu98>!(iaUrx0|CnpRu&L;gAcz+Yg{oUJxzW6TyX%wN$UI1MGm'
    'E*0Y`wqqCqgrIpao4_H1Wp6~%VLqxbSR=<8_Wm)OhV-oBq7=BOasQY3zxLqz9{=qfz<crT<fqB&i+BGu'
    'e#<50SL45(zva;svw*!-{m%I98GmDamw-xx-#Pqc4h(5B!DntVAuMS!!H0J;=^y_x#}D7lryJ~b8{w~s'
    '@999T(h=|l0?dBF5HeLyrZpz`J_phO5r<g3DB8I8z_Hi64OYLx-t-6g$*<EjUyXly{|5e;ynFrna(s1s'
    'Ga}c_`tx-2i37*s0=lN(6XgBCFfz!42fVogrbTK9VDB^N_?27+8QbjnbdBW^d~}J){TcblAW<Hn>tizX'
    'O$xAzIc6`hBY*P#3RIR9n7?5_s;zh2zsgs<xZA9!F=FRFUB9db<3LFUCPlyxWIYt|$85QDjf5U<*b-w>'
    ';1s?Y5kuz@9%nGZ|1NMi@~}W*Qy?CgYYt3>{6x${c%%~`tB-TK-RX;%8B+N}7(>3Bi{tS((xGv_79Cje'
    '2rKB&XD9Chj_D-`(pQ+{vSavPZ_Zy$u+z@7a}5OhV@_xp)!zYihOhy11Tq!;3O~ldCICp*tnD?!KD`oS'
    'hDrA91i@{VEk%%)IaY-gvk`_^aKU$cIW!y+?2IPhFc`Ruju{%cc5ZQ2;rfU&x>4xa>@H$c4P;od$JqT&'
    '#z{wEih?hA)yd7zz?M-7l3f(c7jts!rw5pig%7NJme~rjcV04X4A)P?-Nd#tV6fzk{^)-ez${akXk-Ka'
    '4LIG3um5^_JpIAbK)(8cgm`3zGa?5~iKmogHfcjb#vE_Mo~I24WTpX~5}&97XQWa#J$X08w#}C}%=;Kn'
    'VY3ODk#t*GJ`!(5QC5P_(-_B9r8ggo|Hv-D#bPsL0z112|Fw68<q4)!E<wkAM&?bSfFH4yn+AkzJ`u;l'
    'W;(~x2Nlsdt75~kZAC%!skfQlq7lgWsZkM!wLfQ~+H*l<1w5>lt0^@*#&;mO^`@JVAmtss2RWX=Kj=O0'
    'Nt{&n=H$4xV1RpBCmI~6^$$U?Jz*>6Tso7#;%Sn=<w&uVZY9I2n$ioq$+j^Kt@()e5?_(P{8d5>N9xPe'
    'xmAZ3wWCGQCW71o^Vblt**k&dWdeH*;bHhPAKc~m4UJFBIpR11aGVhihhh=k#JNPap04}w@bCgtBuMZn'
    'zzh|%rV{K2BAzceXR|bFA((%W6cOyf8Npa|B``d;+oV(`;fs8Q@hkeTWZ;SI4FlSLGyM&v0Hri85eT*)'
    '&89$;<mH@1#e@hx=Ud=*KNB<g|1&-%j8B0%B4(Uky}J;f0})wa3glcThdE{y!n8~`k3ogYg=Fd}^}SR%'
    'z?dJF`<;qmTx?l_cP;OZrMKzt5n679$Qig*dkBBX2iJh4fmWop2??;lN<VoHutHBG{-d2JBC`A{wQr~p'
    's5yoi@|LMuo)7vUzi%Ib^imapl$R@I7&tM8=*t2Nahr8dh#X-QTMj62pzNN6=~GaP!A<#dkdsq#PFQI+'
    '$;6NyFHx>|9^YX*T~IzzFbnT)Q)(o}fmDvk&Ut`?b84Rg87^8)mzdOQpDj7eWt<N$?;JFg@lT-RGVw;W'
    'k8c1~0!fwJKkR5r=lB+`)fw?zR)fN~r;#K<2W2YPY_TahU1~R|`izM~if4=rFDM@5?_G>5oc|SZD2gF?'
    'c$F1}f+rYKO4o)hC>%&`Lg`gJ|7W}*vPq;`sZ=dhSYA;^QQC-#1~yJ0l5r(>QFF-=VaF`)F-A?gp8`-Y'
    '@$OKOmIRp-|Kl1P%s_Ztfdm;~uk14n-yLR;n0XA@fH45Px`q3K2%11bi_fHi85RjQ%%(YF&z{d?;IQ+U'
    'TwZi~>eV7#9^TpD^kk3&U}Hh!_%!1o=O_l=j3LE_NfH>h9#uGPnca!H>lpVf*llm&h6CK;eQXwlw`<5C'
    'wVD^hlL&JUK8x0GJbdQ3#4`QMT6Z|#dqtF#6luo1t9ei6F`p-A$HU(a3r`or1QleDU(MN<8M2vCm%D;W'
    '-1i4rtT*OPU-4we73-8-&D?xPcKyDBNTdhL&H8Lj3>>=tg7G}ZpO_9YLqU@F(DHF4vHwQk@pbwDA0WL8'
    'ZW>+?%y2)Ebd@7DJOi~Cye7V(fWsU~mG2;#L8L16mNoOO*KK9RfhpNncqWs&OI+`{wF-F6yv##YI7#6V'
    ';m@LvWylGDi?%~9%BA6dxouX)#xy#Da$sK32~A&3&HPvIGIQzK_|4VHuu0mY;^lW2XXA@ub`o-ebgFb_'
    'n&D(+NSQd2?#b{rq5sD|z*1#Z@@o{<TY@VQ0T)K2rAsfc<-(`@Li5&zHAvC0<&0bj*ngssvy`R0jX}1+'
    'lxxEDy&PInQ$tZiX2uA4{L9mm68%unGG<uQX6q=LCX^BNJZ^*yp9NRsxGo=+yWnJlM@mh6oLB$%YJ8am'
    '-5ngHVin$BkfO=mbDw=pvwMYaH-t~*ALm(<Jm|J$H1;)p9B1{x?;7`qF()j4=!j_U!``px%aCYGxJAJb'
    '2isw%M;fvVKa&s+{BXwoFgwIVkH5W!M{ZtZK@s@3>ptE<A-o|C4){u(@vxIKY9QDwSb)P|aLgkImN^DW'
    '7&nH3^#WMo^xdQWpZX-6U^$wuCwTcsgZqQ>@PV((bo`JF3351D8(TbQ^7jHAs65wr(Zzs63LA9;P7^Ew'
    'VkHT~HM&Ar;0#t@&bTmlMA7_`Vf#ReDj^2|k1@i&!0hhAe+`**R{%QO8{#tNJr>~z;n!Y}Z%35ZjBbAg'
    'sgiNp^~<Xj=49x1Sm9*xEBSN4p8vdp(KF7#E%SWSNs>3&=(HtQua5zTzwv+W4~qE7yYmB4eHIuj&Cu?Z'
    'lXe4h9SJRfZ!v+azueBI^Ir+y_%YkeG@2L>G~HmkG<B}vcSF!UdhA8E;q<(cJ5D~qB>E21HklAE%*E_C'
    'Y?l!^9T2PH2{P4mUKo*jNTp|SmKkQs**Dp?|7-6A=TBif$aEvn>$AliR35%gsyhvPb8Hwb>b@gkI35a#'
    'VFF;_Weh0%HA8|I;1h^3n@?XT4<^v2L*#jXYMm~>Glpb&13{m<4Y4`nC5dBVm`hK8QCYwc26H%G(w1io'
    'gpG%Z;FA7|zZDL*<vyb!7ZhK@F{fxyGBC2k#aT+3Q)(2YE{%G$WPBHHmRr0j+iEZb`g>7#W9y;eL|n(m'
    'Fo1eSm9xu1@Bbse7ShT256mXb1<>rRuV>@S(~I->#DbN+H)OVH@ryUFKKzt@aW99I0Zq?lJ=^LnKYdwK'
    '=F2FSG7NlMMF_jY^9e4`X}0MK-L26`8Z*-Zh>kj)r${Zb(t@y0wAz;yNkrMz@%&awudpqNuv9^|X!c09'
    'rLYTQtbPC&S*Fe8!_a<in=g8|lu0~e%Y?0(t{HO)gXmYvE%x64!Ffk5xwV-{Ra+#Szd`L@7gaa5vjW$k'
    '*m#V4+h8j#<GF1Vchc;BCyBNFaqT2Q#y8x^`t5Q<TQBaG(fMwPUXRDMXBZ>hZdra;NT>vlzLa(+GJ?eN'
    'heTB3d!zTT^PX=RySiH48%5IVx8D|uit3HY$B^@Rn(UTZkSD@BRu(|aP4~xg8P;<#@S=pIo~07)O|xS6'
    'Mmr}4p8QgkYMys+6*nf;d5V4lAuEh4Iv92_0EhihFRxaZ7R&5qbnGn*`dka{QT@KctuYiJUk=I)3~C~{'
    '-!gwI1uIQf${BLy-wTH7^k)ghcpNFGBKNQmNr4|Nh7k-)a*A@fy6J%V<S2!UFhyydlQ3ISE<>seGws;8'
    'Grut(m{|WTcbG-jGs{8`?zdoxXcPqVSaNMp%A&v)F*pZU4W!GLw0*(O$X33h;U6!_i+Nq28}eieP{CGL'
    'c)nn_>vMzdGhB)38GHU&R^@}iaa>_i>HYAsr_0`8W{bGStL4_WbhS5WLE2n#k719S@g=JdAC%R5<5nN)'
    '6{L{_>kank9T!86Qp2%4vP70eTau{o^1CbIl}DM6QgNnA{f{{oK@QRDH}BqETwW8%#n>0hcX^_+z<;TG'
    'dKP?<tJ$z(U<4V0F_8s89m(NM!`{0~_Tlg73;T5SWr^6w5A!Kr75QsW8Zsr+BPt1(k~faCU`4o#ymjI#'
    'aGsoc<E6+Rd6)xrSu?T=IjRyoHkth#kHvyh2wy#}Fc%i=RP|AQIjbI#A^zoMumAtv0j*4vFQeb_%CNKN'
    'IrI38mf`RCWB)ikCoqC=vF1}=>gt%3I~++q%+>f5=Ni0!^`A6FMy$c3_J~ODqz)0eGLt~X@RaNfQ8KNZ'
    'J7d^Wnn;-~3qZLqa<cGu%*B}3iupm{kzls?NC`<`AYJZr!3dN&*Ry-4%te)krLn|owt$jAT4mV8)>oj6'
    'GJf`ilkuk^G22e^&OV9pQWqz`Bum+CI*`E8l)J$7S`t0}G0Rg$AA=~hQ?KEALrZL6p02VEEI>QcT>MWK'
    'fRu}4C6i+dIvko_a0esJHzYzZ4N~Gu!j^4rHy=sm?_}Hi%hWT&S1Op{`OdLH#bHz?e}%cf$QSa4?Gkz='
    'o*QiMrI|3L&q+>@Vx=Sb+RD=_qaFfWe~?2xFsWyVZz!66{Iq#S@3{4sIUpYJo|Wne=Baju-3N2@Ss09+'
    'isv6mP8arD1lSG2m`@>?lukvi*N>~k-BKipce6MnCV*@<!?#d`U~QWPnfh*?ri@X#!sRVUL0XdN0J5{%'
    '>@L{cRR(ub;NxO^f-S1A&;Rr4!v!m*cZrEXc$M#4W|aqIaLz_^*3!c)S_H^GGv=Kth7uznv|7t9@-g8O'
    '7-R=trVF_^`45_{)(jZcTNJ87?3eo4QrK|%xPT?>6=l$>4GGwOz~M@hr`6ko+4cFnipcn3C_0Dsbu5U-'
    'mfq+&m!;sX${$TNG|C$*$G^%v7(XdlK!qVED<eaW2j{F?pOE|99+t=zWzi5N(!~O&+~=eUHiY-AD1oQ^'
    '_c2J``P-XWQ`iNLUHfZ(X>(z_;=<2v`=VHb4+b5t_vbph+o^ObWJ=AN;EV*fvCvmZb7lx;H3yEQ2n7Y9'
    '@ah8us{0azuuAI8An}bQK}OU+o?l+kWaG=L29ZnoI~Fe~FBsOw?Uv3>*-^cCS<0CUBVs|bbfpIe(JWZ6'
    'd#CKUUBGE$StqY&i^Yl;kzOCA+3dKw^l7k8bw}7`x~t6TJ6YqDcwEnWa*HzwCvfLXm^Gb=pOY0LVRiJ@'
    'U^z()pGP>TL*TtE=YO%zRe;;Z55L5f`f<hUG>nd09i+N{YPFYEOeL9cefE<WXCT<5`5k`p9?s&=ST!TX'
    '+<)j@i*a!`^1Z_1e*~NJi{3i;jhLWFRFAl#7rk4w2^e*eU$F#qB(rwXgeV|f@O3a-Q}cZ8hALhNk`^HX'
    'CxsQ!e_s;-afZZy_jHnlOTW;MZ;IF2Vm-RUbU?rWCb)ii#1{e3PXa<C^YySNetXNl9TdkCmN))i&>@Zl'
    'Jm6O`<;jELZ?+%jwi>X)c*JWY40?fYj`dODKFaQr^llm`WR2!@TLVBgU+FA6&^@cf5X@#x$cB(dx1@pn'
    'sCP?#EHExeZ4SDt<Zk+**B{AZ1$WB=2Ex2VRyaj;f>aL}6izXmR5Bxdu)*p2=cO37TO4C}ut8}cS~@J;'
    'R?>|_5`-r7f*`ld3i14;$(r;lnJsY7gE`3SK!{6N<b+2CPnOep$yKuf>2ROhMs871laj&j5a#$HAmh8_'
    'h!7o!s;e|$KaH}x+XTeb#wPlK)V=BFi)D!;7PnDOk0T>CO^;Llm}QnWsykFDL)1LMPKk=#3aUX&-9AEc'
    'p73LCo|2^37Y%C+N=Z6wUJ9)|4YzKj9uC28T1e#PlvSFJonk_j{F|<y%{fq%|II)m-r77RA2W;(d#ZzR'
    '%vY2CELLS^%gAewB;FiL{=!0}M`&tG5L0%M+3+Zo*ZA8T9x5r+F{HV7c>ElnNjcyW@7!oXI-?S$dx-1H'
    'aTxkTGOL0W68?i@w=u&Q{X}w1v1)nLm;0<xJ~c-liIbp@!?p1@qX`K$#nq#TCS2eaieLs59bp!SBUJeY'
    '$YTNM_^JLN`yrl!s6A=S{pH&S@Jz=kq=tw)oafAWpCt&N+$=z1JY&MHMLX|$LbP4{HPZ)}<RG)?9b|vz'
    'fXqzdJKbIdX^|&CP(Nguv%X>gMPxFAQ4DclUsWVg46C$%;a0^3#YBgIIz*q}N0Y3Ej;;X_6u{pGi`V*1'
    'x&aj!DF<yx!Oz~!%qOYwO0<?{DpcwPSCB?QC}R&7Bv*dLDtJfX{9K@q==UR0WNVO}QsgbWDWhDxDqDyw'
    'b5P#_?DKV+-<ONsDOB4Z^4qB@@s4nW0nL43n9C`>*uT%NLJUJi1>GWM{<U`!VM`x?&V3HpKfrxL_#4T8'
    'B!*I9lg6lC6D&bKfmK1>+6|9$7!<3I?jm&ewgVu?e2K-KHxOW+SIk#=>L9M<g?oWdK7U%^!-f;s31)U?'
    'wlAt=_FPDaT=%HN6`QMeo{u`>!6iF|8C7v}T)BLxE(2X`@FE-z{N4+YsXxnKGeEOfe??!2IE7=2@Cjt;'
    'dUIU;8@sjUAJ_dGmd7U+VeDf$;$i`s%>|b0zKr^UAF8kz96*I<f~C0fiD&cSA8F-Wd1jI(RzB{W#Jy!b'
    'W2!KjN;9Pyp&6p(w9Y~G!qi4K7|hU>Z=TPO#Avr+FZZJAowp18nh1LFwY)CMoEzA-%nfZ=?4g!UEY6T}'
    'R`hq`?zqD@+y3$mVJ8i87jqsJ497DJ<g-3;du;fN$2qIY8gYYs`UuH4qz>Yj^oi$K>V%_dx&8DvmbbWn'
    '2yc4V^GUgxl-+WT(<Dnqmh&cC2olbs37g#JZ1_@}32`K5cxEL<pMl;QtO48j=Mg73kRj9I=;AO9rbS5<'
    'XlN|N2q~A_$}1SO(&e%6eBt^g{jF&(W$)u%uo4O>hrztJ{<6mD%((O>9<N6bfpQW03L7{jO3@6Szc{%w'
    'd6K|RPnab739*W3%julklBn)8p*21xa)F+Xj7nJ{sA{89!5Xwj9i$cwJ=+?1una>Z&x@v-B2IG4s<ZyE'
    '!PO=o9s!zRx;$9Aof*3@FbU<jc5ko2Ra}Y@BIQ-vs2<QhRc)Ih%TJ9@QX?t8!AiPq!I)KJ$ZFe&wX*@M'
    '+;~;S{dP25$wn)-Gdmfrs_v@1&!k^l&9%gyS8M2ES$-s8sy7dQn|`F7Q`i!v{#PVwd~}c&11(g9#0)St'
    '6BGwY<f8=nx@#C(VnwzQg;wMlv1=KLXK8_JYOZZLabViWiUZx$0#A$GBo6!H_&Mh4MIJ&Z@&jKtw9s($'
    'C_!f6M4ID9hVAMeazi^XLlb7x6FV_2&xbK}-8Rg?bmMgF^5*2Y75VvkeTUwrxZr)s2mI}~CqHBDj8vdt'
    'f-vJc$Gv`%Sgwh*NOycY&;W+e_uy~GwG$1wQEZt2S?C$I7YDJXhfb^mHWJO(^-v3pko0Vq0?=Skct|rm'
    'J$574LXP8DmS&;Yw0&PQlGt=y({s%*LRuWhw(dKg6NjN~;5PQYsrxY*^wZt^*ENiG&7sC4(?aztT-xpo'
    'hmX(6l8<}mxTf7SnFb*c!PmS)MhM+Z1v?OGaoO|UhY#mxM}vlMM8T5Ab)C`=HLu<0Yo!xJHC@NB_hSG!'
    'tzOaA3)*cx{Y;{nPeFeo#vSag$MLFn^N57@%szo)dkHK8cpm>a=so*O@6}>4>wWFP@2u4Pihe4a?0!2q'
    '2mrV`;n8%yS&&a?bqov~#C3v0+&%d#`yQ8O52tf<G>r$nnu+fF_c!<a7_kl=r6)=ETraXC%S-e)&|F{F'
    'bQgGs9|c<I8*Yf;gdyJuEXS~XH;%k0_JhEMfB6P{NR%hZbp0R>9Lq4x#0hLTi$-imf$iIoula^!8i`?f'
    '$S@;YgF_kwzUL>2=6OaEC9&s~o}@#Pio>IAb6n->)8g*qr_C86xn0->JSNTEIcqsAA?wOPD_9lp&QbX1'
    'u(uUh_Yzzp-w-Raq2HMPpEe+6UI5n3y5>;l1H)E}&+-Vv-uUNtZ$1bG_b;#c12_0!mNA7^fILh+(DZpy'
    'Ewf3kP3b1|vnzUW+rtrP>k$u4JH_|)dPFri$?vv8A3^2hjm@YYR(94(6L{+R0CpqPKh>l^xs2fYF<Ho~'
    'Ec;|ZtWAMx6yaJu*!~nLusPCmnu|wYn;qb`<Oo7r&t=+rUPD`?DSWT51&JRzo|#xSh;d$Mnx5wydKlZj'
    '87E0>$2v+ZWcj)iC${Dz%duj|0ddcUA2q#Zep+H{vPQuQl(!5TMEgZ^Ak0YjZ7V?_(HIFbV#~30)3c($'
    '3H8u4e8==av<zI&cOsbE2mm3576ftV+kmhdAh?-_XctK^oe`TSx?OCLT=5n_u`~lNBgeJy>^_LDjt#;V'
    '2xP7aSBQ(nS<6lW$JZPS!IgnRGx5Cy0~Umqs}WGPD6-qu1xTj^y$<j;L4>_$1@YNLre|9~K8foBiJ{On'
    'P@uukwi#%qsl|q``yjlVL8yVSY54(i3^PQQp*e|;?@}^Rqx8dmV1h)hgR~A?=mO2yup$S!z8`xb5VW0m'
    'u5HI=jKau;|2vu=N0Fm}$^a?_&{=U!+&RRmgJ(Si*y17$!9{P{K)RY?g>e)n9#ILx&_Z5>X*`PTB++eT'
    'x|(CSfo>rK5D3qBuHp9OlT4d^J{{$!qx_&pIVHlh>?cs;>+}Dd{P^MR-?3<TotMt4`@<hIu}Kz|YTqf`'
    '`^pFL1qg%ZA*$%9lE07p9rRdH&QZwG$Uk-1We*lvKs?O1WC01XxJS*g_y9<3gu{nJp$daVaQEzSBd@La'
    '+P*Ds0OtJZ$prH)y5Q7zxhe2~5(S{&LGK-Tf{IQ&CCsF*i$FP(Yxrgp6(@V4Ih6VG<#eX1#@0<&Q9ZI^'
    '6}cCRYdGAa34AVeLRBjwuOT0n)sf12On`2P#mXh9h+h<y>t%kq5BM_Q;C{Qh!WiX?#j7oH#r+nmViRpt'
    'SXE!ga$!`<&kCc`iv-s)AYJ-|D@3Y_%7PndUDV1c8l*ET@9CE7rdmGDz0Of-F&Q~e$bBhjPQhebs)H*t'
    '(Td8BWei;?bgO6kSzq9`YAg5L$u2h1))gCBzmNSEt2kEgKpRCJ+ueqK$0Z--$;3*8+tR~c^&rc493Na2'
    'gWaM;o%&I=*wuFBJB2_}TJNc<k4;%QC*>mAuO=mvNd++XHwQ}Iw}sba8^hAzK&>zIUT!nWfl_-=yTkUj'
    'W2xL>F48T>@gg$_UC&QUUo(AI54;#*kG$bUI>`B^6FJx_=eUWdBi}&St86=wo9N~4Ft+Yd7EF&d!|OhL'
    'C-m@1g|AW%Sbm%dEpUHSG7#$?LnbSCUmY%I!F&$f?`Ti}u&fyrmJYd%e^3gpV&D{F^~l4X;98(yXU>C*'
    '@yXfw+wtXPxt)hss8YIJq-HuwJt7a~no{SGH4=FFb}>i!QB+2TQ_xpPgL2-tF=iw5SodI}+TiQzZcacH'
    '+kA$rU=Hf!T47;0EbG5qZP`u<V}t|I`Z8ZpG5suwgA}FvmzTYK?nc?YRB$;-?e};|Fb-IcQ;5(dR0R)L'
    '+a^R0h^3^I!8O~Z8`WmON*Ly+G|m)nVd?eG=OO<kL{48GC@np#PGmtpm7c8oduyuAczbppPF`Q7LH3yG'
    '>M?R-BhU@gi`>A`Y!@ZAZv<XoxQ1t0aiVF7Vfx4dHW`Ic66>ZD$F}Wxu?uW4<Hh)9q4HZPFK)$)k>|yR'
    't|!PqPK;vRb~P)oJtOu_O9KXP$GY!12E31S-3yH%jx8;AG{^NlLkk@%aqRLSpI<ige}~qI?dpbYc<yWG'
    'Wc=FJPhHb9HUDr};iFIAHcqV9?$~p^*RJFFr<VJAY+ANwHhbIk^|ABnwPu{2nWphdGkpI9UZ-=HdGH%S'
    '-fW8UScdd{+px!D9dLT;*(WD95YE}yJ$r3QlX#}*ow{eH_u6yMeApw~G&EgrxQ?nR%3RXf%a(g~W@wgS'
    'oNCr9)3IK;Cnu+l(dgw$xT}$K|DtAt%Si*DpIYiToUQ}><RP5B*C6U%pae&1M(FTG{kyYZz4<#XXoTOy'
    'F`r~4%2u!^l1g_?M#7>bd6~MIKxq6hpKh4XX?7Q$GC$AX(U;GQReXkU3S@+607v6lC}dYFL;?LXsUG;3'
    '+BfU>z<T}KJ=0#<XZ9=28k?_APR71_W}j@o2e0m?vlyeZ$$ApHVdULXGT480rDvP1uIl9B(Hjj?$0MZ0'
    'mL6p`8(C8|Lufo+)#<*k`MsQNR1(G>XS21V`5-5A=Y!b{`)~$MOxqrxSZA7T`lq({>club)wjlelT)dr'
    'tFrBHva&`eVvXlHY9a)b@~B24gzk?|efzaz*{-AO=E<wqCywvirwy)N3C?B%HV_!bug0gE?!P`8pNwt$'
    '<aDe#I-Fla5*Ws>VV1K~Lwju+uTM?u)#-`vy01=~2@F+J)ZY1}wAbY2O1N_YZp<7b$m6yadXaC$RuUoC'
    'boJ1W6I0W*0GVE_g_h|W2);}#%QQfK#*(-h$A%mEdK8*Y(r3*Yxj&JIm84cM;-({OxD8gn60aoA727_c'
    'fumx5mn75Q@i3r+f)X_$CAV;12rOqZ!L=kOlRopRr3D1>*O^8s^phQtA`eFtIO0;$X;($~3C&}g3Qgw}'
    't1{B{QqXvs2Pw4>q{)Uf2bQ+}#iOm4vnih_&BekNU#tv}$`^>(<Km;L7!o0cgiv7`3h<JQ!(7_^8zHfY'
    'e$UQD_Cuk7GzFL;gbYLRLCU=n8}{=RTGCb(Z2fHI(>Xkx1n_CS48)QZbVySFgpAEIuq4n^WRN;kFMBl^'
    'f?^Z1T=q#mPw=30d3dUHb-7JVqk?d4i;rlvTupJC-&tDLnidGiEeZcVtb<*hG*d`#1cc!FhJ@-=1^IF6'
    'KL)-KyDB8+VLN+Ts2HEJY*}pANbge`cb#im4CAv}s&#P!+4084rF^eY4mYcoG2cvy^N|@{s0HI0Hc|BC'
    'd{%5=qGyOUK3<^_Y(*T*W=E^=@aV6%ga20KG#y=Q&-~z7a`V-(?g#yUJET5;-hlxp^5gM{)kw#6p)*U8'
    '*aK%xYHO6IPe}=tWUxxBM@3oRtd(@WqI7155|PA1PjanP<gKdSq6>7p_>C1#rxi>v7ZxX3EH~5J=|2K$'
    'UW8eIb7DIfewx&x#W|(j?@txla_2QeR%)qSrUiwiROEej`am{63c11RlPLCDIxZBD4nFhB_-Q|0a!AE{'
    '?^A#cgVN^U1jBjOg}3VV$l0VjxHoXNMS6j<`$FEj>g}VnS4Hai>x3GZ#a&ciB$Ac5m9t&HvBkqJabNW^'
    '#qBO<$AvRq9TdgS`Z(W@g+~(3zPu>*b%x2XkhIQ6E~aOlH?aX)E9OiHHU4?Gm?Gv#E3>k*Fy`j~WrAV8'
    'c=$+YhEvvTvVac>c-CC20GkS`1BJt3yLCxZXRl@f2SAR;)pdu6on6jo6)P!|kOw||qu~DL)5#|G@>#cu'
    'v2H$lmUmb>v)Z@2%?c%lZs|N(mVbWeO0}mrkW>^PD+0vD-m~+|(|13QLE>kNZ$bK1t2<TVFE2*HSa5cg'
    'X6qKYDwlhk0N-5vE#girfN-EpZc|D=nJUtjsFH6RNM#l^E(L#L4H|b6M<fKL>LTuuQm6%kOZhm~u=kJI'
    'G*r}S8D<rPCo!@5#S>o5V8ZJc94T?YU#w-x=`kAC6_inE+Np?~)>z1@Du`&EWa}tBob(Z)$t=NZ%nBYk'
    ')+qFBhHH#2oH~u`*O8KIZ2V!*9}GqmQ({%+>1w@6O&sZtT)aE^Y4ZBw-G7aFBI4xL_;2TLMe`1}!jd<u'
    '-y6R@6W?mX8j=xYMi1A=&oFH>!^aJrOu95&>4yPy0V}u!`V`VDC;#>4{MF>u$>rFynXQq$(I5TK0%nxt'
    '!lOR*SO0)xq*tubUwl11p8nuzq`p6?ewi@`EbLCR3ZdGNXbkK<pcqdZ&`LxDIxRt{q(#fM5vjx`=dnsb'
    '0VzMsWHfx%`h)FMa@N2#Cl4xg@O;~xGG)9fn4HUgCqg+&TnUKEenYIq&H03)QZ7d_rizp({IP{fRe17C'
    'E-j>)_C71d%{LJKXw<`j7zk0uYg8?OTLPX=Ekc`t_>5@Otl1@PvR;s|N33ZvX4gtlP@*e!FuWA!lt#hl'
    '<-<Jl#I-RfgpBM~i_dB@t_Y1UPNc}6dCRypTYDD0$CM9N*hW2h&HW*YK1{}tZ<CS-@*)1hLNXz<uol_k'
    'pIa9ecGJ>;w2_^9Wo#E|6kHZnIH5I((%IC~Y&}@AD$SvjHOw?~DHB12FJIzRr-d@lMlD`v=x&sXrP}9g'
    '`a$!B7jm;oR>@MzRP&Z=&t*#$Aguybjy%e5lFaxEsbng}zcJY~goy5Xhy{fvN+Rov^_d5pm9n90c!Lg3'
    'BANtvB;E0v1w7qUvYhbua*mT9uaxlwxIzwVK3mCiR=5hSJWS*HsD}s-z}9t5q$Tpl;Fyd<K9`(U8Azs{'
    'X0|;Js0zR`_*DCiYweZ;soDy5J;F<c%Tab6isB595i~TPtOwJLf~2$DhBQSXXNaLW`^8R(TiAOluCIdL'
    'vU{=|R)dOn9eb6No2m(7V}6ubuLil?iGs4838%%>vn^{e5=pg}O_x$p4HHnwGF9}|Nc<8>tVBAkFqx7m'
    '%Ee}79t^PzrA5ry9D;XiF=wUAB$IuXuR__)3nu>IZbJ#~DH}))hYRM^moIarA5~@>p(%X|S=xnjF4JM!'
    'M>h>z&I__^8>-ZaLJ@uuxlQOct6AuVuun01CLG`%DP)B;O)48I$`|JCTnZzN9~qACo33d^P8fKx<rt>!'
    '*t+LNp%x_(3L`y93=Nr)56meJ+`zzbxW12&5rt0wpu(6&iX=LrW5k{v#%82@7BWN6N1^G($ng_9cFhQf'
    'D%+vwx^8G_9s+8JaRP=L+D5Fq@&xJez(eO!UETtM&NBSGo}yXI@?8!}q}twgme(RErD4;KV<vVGn3nJ9'
    'Q2^*e7=JFpxV5y<^}^7LyukEq&(y6jF`_uIV$XDJ-%ku=D#NBD&5VuEb&SA|Ow+e4KXHBEfcH(?(LD`V'
    'weH70>}2F?jt%=388*_QAdFmBv(4(-h$JJPc3Pp7IKm`1`n(F3OB55Y%t)ZW7a&7oHabHwaOzh?N_g2T'
    'jchs#Ho+0;h;p|{ysA=WQdL4q<5$hWYEbrz4kiq(UJ8L&cq#=P2Lveys+1O5Da4nj1t1?ML^$Bz*L5v%'
    '!^E{?O^*#Pi7h?$T_7=E!?j*aAQ>-8v?TE?KL~VRci`9Es{2(J;@h>fU&YC-tnb%6`>bi1!0PqoH@>>w'
    'S;eZ_Vi4O^=4piv_bJX~A>>+-mT17M>?m^dz;gpj(}A05S`1X|89s8%*l~cJ1#oMan&DW;ieh93N!Vgt'
    'B*#U8?%Iaun2{3zG;r<V#1_{k6_Csj05U8<Phe_h5L&)t0Q2=C+wy(ea!@OEqI5S2d?Rv0FVF!Arslg5'
    'tRF7HC^ikvcAYS^bhsnENV6Q+k;v8oVjpmqXn__tE_w!+x#Q`Yrx~tgARsp{(S6qoLbzo0ICM3j!Nk%`'
    'KLElo9K*6r04z>`^eoM@?7o8R%Zr0O(ft$McT4v&IW{g6)+q3!tUOnHfgsA<)Lmff1T<BSWh)^orG=KZ'
    'k6=;eYi<|NQc}dIfp@5kKw9(`DW}-FY|{2?>3%8wJzPmO1hki1Of~kFUNS{VsR~2wHdmO!qMIwzQ}2l>'
    ')Yt34btLDEx9UhLDHON0J+!nGlib*+X!=yv0NHo?e!JG$k~%2083DgEZ5jj*R@RJcB|AV#sSVfAIIyd@'
    'l1>&<R<*2YwA$V~(@x}?a!a;fN5kEbk4WiWwYD@B*H*`7)kIu13AoBJ?kxVQ6vu6Zh{@P%Ct$3CyxT7K'
    'woSdaZVSFW%G!O(l5bnq?%TWQ+qbX$2akSL`U>uw)C4p#65)8QCly>6_WP*}XngC+fbErW92bfQx}mMV'
    ';B^9@@$!KNDGVg}5>fns<paxDb!81fd34ndcU?meBeVCQH6xXhYe|E}N*PpADYNq0Zx{14V&r*zhgHI0'
    'Q!Kb$at}8Hq-{6~xE862lK|`2%AzKDP4fF2mQyahvTb7dPG09Oa?EokrjygFcNgUuyZMAr5&V1tZ$6-D'
    '=VW$ql5R5EYi*v7B&}V<#J9+8&#0rltaddCwVv9(MPgFp{C2g&vLwk}yia#ac5iHf&81jIN)V)Ipfm{R'
    '8I2as;0wPjgY{aKWm)2`RoJad@U%_7B>-HNZCM&5T%BjB25gID%e_{X56@4Ja^_kfj)XO*zsz7f%ExFa'
    'rSm4KhN`%m(oDk=!{fH|G{~JS&uOf`b~{OIY|i?&u%3v#ufx2?EqPzV<i;koH@;DNqlniXavW=d`yPFw'
    'V<|V>EyYp9<_>v|)d%(|+3_jau|cw<%qh3Yc&xgjOXag&(jS|tkgOiDG7*wx4w2)_O=L{ZAc6p{bHm!Y'
    'a9}Ni2?Sg~E40y)a6=Y^!@Q@!roY_Irt@EkS?f$Z;zBq$w($f#_9VkIgYspsK@%?i0`}?3C=v91I^ck*'
    '*iss0k(0@;VeuU*2};I+W}2=dvY+X>unp9J!`3WwLMeWocV56@TlZ2%NfSYn-25+lLJxxid&gUcACtC@'
    'NZb5d{9o}apxnjmH~0$w$V+2SHVd+E*{_3PA$*f-p2Hq2I9O6lut{@=QL^Z&ay!zN6g+*SMpkE_7jpD?'
    ')39_rvCz#yBY}hrF=(eUlrWZB93lI_M2hrsDrV`VNmnY9ilSf?O|cX4kg1z0a;MKXu<g8ovzXi4Obe8n'
    '<xv*IIS+$tGE60bYS|@)TauG*WK?EDy<{r}2*-S05yn&wVJtg+lY!jt*1kc3E6Dhw7R(-LY_0e+-j=^m'
    'Q9QSA!jt(V&SsW5!K|Xr1g^^GR_d4orS^$cyQ);+3bQBE9o3h5N<2zfZc2fv$y0teBOET`NMt-s2_;%>'
    '0h*vB7lCV>-Q55@o>c`}WPBH;Fsj37N+OOGsf~N*BFfxfb=90!tg0eqaJv92ih~?5a_(XgvP#y>(<z0?'
    'iW1^BAPU!6dc9N$u;TT%4Kv8}VY#TKY<1+QsxdvPq_Mn&3(RN31*irQkJH=RyG;<n9S3rFq0mQFsAg?3'
    'jT*has-lJ*22AaB9Jm+xcwcT*jUu!Ji4ZS;&FOozvwYjoMYRoAUoMvWadjpqsws_Uj%U?8_GCwUqzTt%'
    '`qt1!S<M7VYgAPFY?cDNl`p#{5115q?|nq`I{+o;#b-(-F9E~ye|ZPM%(G8q@b)u-ReD3?bl_SRRGAap'
    'yc}bi7z~2udJ(~$-@~o1Nm~G>nk({wOSMTX(K$)rCb8~?wx(&Z=~-rCMYgB;v5i}_yNMQBS{!Sk8CrS}'
    '`=)7oW)L`rt=Wcwtp0&g1jIu}hU@#0W1=|nU@X^6Y+r+E?JzVEvLo9MUE7T;J&vt7v<we9IQ_*zn(v!V'
    'qVu5(*}s=$>3_SM#^{QP)R!#jk0t)n7xzf{6=p6?@Jw7kw9Uv%v>>!l1gi)PJu+g$Opp`kksIoorA4;p'
    'cz{7CbRu2z%_xpSGch7NR3><8NVlTMbt2cWbSFx5+ekbV<Cb`)XBxI18jh>`@U3rqf$jx~=6cBUVB3-;'
    'vi168Uo0&iO$b9kAQ#{!wrA5dP1U&|T;k)Pvf&8-=HGt`rt=eK5NbFk&ZU$#rxd%bWV#l*0ft5x29|64'
    'j_V>#^L5}n@RFNEmZSNO;c2072N8^jd<$sSwLCpAEZfzBBsA^a(`RdvUAM}it)>5M@?L8I%QkGkK9Gem'
    'N;kfhj*a<^H+^7fnj33@8Ji}uw8SugHzl6!1d;3Eev>*-kB0)Fr^JdQptIPtJO@r+2vkwN@nT75X2%+>'
    'H^FK{Lq_^pLzi><u|L2H(-A!Lk=PLW)R5dKdU?sV;YQzdZ1P5K3x9^!*_PojwNheg7t|D@GExKa>1ze3'
    '!_pV~iY7S181Hdsc(~>+2rxnmoT?#DVY|dZP8W+6u%!UF7kl}h;7+9XLYjB&!E5VQ*e=tx6;`=NrYr6M'
    '7$Xbjj!~RMuI1>KjoiTZaI$d{#Blxlk?r8bTHCM!#{vEuxUn942pK`tVy3GNB88P$S_q2;PHq|?d?XQa'
    'EF11h+YbE12{er)wrU0dZ3Bn50P-aE0cEb=N~WuaT##pg7s0<kj&WU}0T7y!Faq9{fanyPfFToZBFDBu'
    '<OP-=hc>bz13<GJzj1~)P>dhOCIapiMgdOjO?;50Bb4}Fn4nk>6I+XIT}N&h>+mgHd_f3!F#=6bY(*-0'
    'B@=IhIZLN2mree3yq=ENLmV$ogN;(iRoR@(7uKkXBe^$~d7Il-ZRBccp$uY4_;RaIAF2enePLEbe@g{6'
    'x2cz@%++kCT&EnG-w1&vndZ&oB&#bDv=ld~%pl(x#;!oDDo)T+q~}g$3RHog<wXh_#DO+TCg%$}|LOgk'
    '@lWHoS1hz9A0bfVZ_DM4m9dh;t|Rj0#H1ST@R+iin?{H4liJ+C>$`VS^A_v)o-&*30$5v0Z{B@}+FeT*'
    '`OM1b${gQN=Lk1VYHleURKo4n!J#FD-8}EAoQv$`<jSS(Dt%r`sb@<Up6brpZSftgy>#hyB35mzW0{n7'
    'fu3O+W7)r=hnVGcu^Q?;1`=DmacnHbJPwG!Ny4R7eF~9~l|-~>WTZ0xTZ#!(!q^~2ury7+7&BO2f@PN&'
    '!rWNfg%s8%=eH1ISekQR2stdo6sie^7OJU_YTYGEcDs;L<<hD{AeBpM7!s*`cbgE&Uve>$zlcGSmFQ|e'
    'Xfk(q$}yBm#8$;rRsvs)u`JUUnnzdW!DqzJVl9>M1FcPCxMj0wOJ-Wk5=Is{=#asw-0e<<{(i?Hlk#N0'
    'un@{$#28A|tJPd;r<lt8{v382W2u~OkC@9!@Y{~TtOkDDm`pXx+$BacM-vT0HuqjlF@#gOq}^huY8Acq'
    'LOd%Gu|vpb={4Va2xz^~vPVd06Z+gWM6_S7#FRyh?!o%XBS=fuC`FXk7(=(!Ci)#DQYr0=HQGdn%0z$L'
    'tSc4#+a+OD746(Z;Z>w)RiUxvj4jy+T3rvON_E>&b8D`+wWzo4r?x$S*4A$?PfSU1+vrSts7#$|Ob@9r'
    'RqIRJs!NBRXQbsyuBr0VRBPBfU9D=NZDy~jfbY_;@sO&TT2oVIyHzo!HWamo)zey5(;iYwYgI{WNk`jJ'
    'MQdL}YfnLYIQ^_;_3Xj4vo4jh&UCX~RI@HLGo@no7-|kTuQdA*rDh*zO=9EQ*CgJmjPxU}Up(yP(w`a?'
    'G&cYE1&z(`sG#xA)v1f6jxFQ4Z4_%Ao8P$BaZwenta7Z}Xlbsls~i(N_8w~i?8*SZwyPX>Ub<Lm*()nr'
    '%pTshT=6!!un$qC_|2;iKQ)huq>y%2pO_BcO=aSWAo@pAlbEjln^YrCsi3`T#CcL_y$*4s5<`tE5Z43;'
    '7o)@BAn#OrxItibebr%ZlG~^1a3OC{5rtmB$~KjT0m#Zq!?W=2cKb@hd62fKF}&ky+N>^|6Ox<M`<0XX'
    'OY8g=iU>3xyFnFUWm0wX8RSHq9cmR<-L~CSDQ?UXw+M{p7ky{-i5v68@4qrJ#pMn)iA$ZIkG~pm8OPkM'
    '8ZpJ-4t0pj4&ze=;-?D44Jr^9)t&m<!|JQMR5IJ8>TsR**QDMsKA;W5WO`v}w^DJK*0gEA)-Yi<yVV*l'
    '@TvA{4X4*~^T-v>=eDRaTrOmOU-g9pi8i*VEL<&{|Fc&XmMN;Gn!=Tq7#6{iSE?1&gj2Ti(B*{j#1y`E'
    'D+zCHn|P2)!YZihiicL1M7FOXoYN!+IqkBpZg7xRLfg7xaBk)s#nii%;myHRTOYWf@`|ABTN9W9Q&J5$'
    'w@>gqk%M{lh6$ywbVj8HT@RVOW9bb~<S4OLM8<!rF_lx_Zw5QURf4f1U`q2agRRsKri4|9Xee1r#bV^5'
    'Z8!B5NI`-uE=FP8QwOLNN(McSa?s4Y+_(^QjiGYi63`MjTNHmT1*<e}q@X)&Q}8)&W>A)T7Im45ipqlV'
    'oIhTjaJ)5-=T(GrVf)Rh2RESGD##mE50(a~XPeCqbVXfaVZK34=(~)`6P51Jix+4uGJ-1Gd}SH%W}*MB'
    '6#xgA+ARQHipKUzf3pou>wSwB^<6a0TJP?*^}csLojK;x;`wZ$u6MU04M#z9k)|;`d-IAW<lRtq*s*$f'
    '!|0S9>z30{l17Eg&8`ZU%La+YCCe+=Wo5DQCf!WyQ2z<dmS}aP;K$?NmkT(zgpaMKzxQTv9#_Dc`LdWH'
    'kSOPvEeC?hkPr$TIz=;m@XHddxmV$mh#PN%TeMz+qFP}kRCNDtVCgH^!WuHk>JniEy{sU;OFG+DU9^ku'
    '3kDi1jg(@jrCY$r>T@usL116|+~|LHes$T$Hq^7T@fl~U_zMYV_>1w+@7{b6O!AkxFSA$0BG~==Y;$s^'
    'M%=U<bM;`o87%|g|76Xha1nnIoJ&b>3I}t&3FZ+tEXJ@6_=OWVt{>;rf{0C8_?OWpSb?S>nznN9@+XKJ'
    '3=e||OSnC#f$kO&kA?L3Xc|jT0bJxkfS+RZ_@FG<jXcME_Y@C+qYEDMA_NGic8=--c!)t^0y@|={*jn0'
    'VLj{sP7wS?SFDh}aX1@&mtcy*4=|n2(|frFs+?$-JETW{`V$*I>wrLPW5hWCO7n6<TAGygKPa<sV>^^>'
    '>slNHUZA^f<VBIK2bN{~i5Z7>U?F6iQ4$AQV0n=hg-K$^kryO(sOh>Ho5<`RC=FM5Xc*IXk*>#jWNMD>'
    'BTJ9%$V3jXi$t@vz%x-2y1sAOwj1f5?uLPhJljijFZ2-NLreV+%1dLPU~HUYw;^_<ELLJ+Y&Oz94G}U>'
    'N-MVmLLv_(zF|6mKReJOBlP{qN1+oTBZNhoK@yox5CmZyyBc7|_Fd1m6V0#;TV1l>j$F$&oW#;1%Q6iY'
    'MUH3KR*YOHjIGGj9puADI|%f|2`tUGH3L_j)eOh?HQTChi11sm;zV?QcHFz%tnkJCwMUCCkKz@8G-401'
    'quaaRu0O)AQ;=%p;?|W{&2OW#L7`oO?zupWuIndOVp)a<c-G($IC0>H2u?+0xKZSL1`0JRhK-I*Q;QSB'
    'hN*mz0k&+H(5SCL<4y^?os`<v35|fv_AOUMem9`nI$PV-y>5l1_NaU9_$HibEinVz_C3?HUC-3b#BgGO'
    '3)nJ>1IM*>M>kzB^7Pm>5<S#BAVfoRA|q+B?lmxEBhdf^-7qyh@O;w<Oy5Ty=GuOu`Mv{}h8?(YTr}h%'
    ';5><;#TpzW-_pHy>RyMM7Q}Gx>8|bQMhv_ScEEuR@M2(j@c+O!wFvok<hw!agb1hsHqEr1*aDnIjmyeA'
    '2GSz95?uop?0caV+J1yU1xE0}0D3SDJGO1$z>Xhaf<qoW43y?-aR^+xFA={`<o${IpQ!(vQ9mcjMpfUN'
    '#uaZ}rF)k+V`Y`@9iZz9xT^Zxd&ETVRFhj3B3)6FyFOyNqng}hc^_Mq-`+3P<hw1rU7rZCSIO=A@QA%j'
    'ZZ}%N_f%}VJPy09GTS@vN?WVwqQG`pz;G^qdbiTr?Zh^#OKaChI+qY|lZ?Q<%4s+7At{l#r30*S9kUjz'
    'Wj9-zswQ^BNZh(=*uiWjJHpdy*o0ujV%VY`?t#i-*M{x3Pzbva#@a>+>?Ll&$Jb92q{&ycHM4O9C&mW%'
    'OOOHnMBcqVM)UY)FpxuL@lwz{&SKMb8k<gD8RY9G{D5Qg8dRRVq~jBIu$a@h*qT7u+QOONPdV@%7rJ91'
    'aL$Y-GJQ$jmC6#w7_rhIMGO~yrl_t&RPnvW8-N`Jq)fETTgqx>GY6Eqo+pv&^Kf)i9X%fe|5O)!myqwr'
    'ToJu8HvFj;`lGFdUKtg>Zx!@rLRjO<=hac;Th%<@C5n8f%HWEq@*M!(KFWL#VCxH*A9fkCwGBnogmCSE'
    '>D{B$cfxpi)OwRT<J(5D_lp-uOF`|`i{CBCeT%aB<-v)Mx?p};P<+!;`TGRP?@%PaNznXWWZSebesxU!'
    'PB-9|#qjH6?(6Kft;OJ1AHDjR{BDogJ~8{sm30!s--K$nkLj-_#5Q95cWl(Kn~AI6N$z=PO&Yc}akbN)'
    'VXM6L%JvMq+gA5%&(K1W``)b>>THMq1Wg#WvX%AQOQwHnzp!&EzU(D_h{g+hr|rui7n1lNQ_qEMQvCO6'
    'x3G)%^xL;vP?iMPt_1luwxI4!L9JPWx;6y0WCwZ(Gf<mWpocU9wPyo*NE1-I7NFJ*KponDIxzpVp_V?T'
    'ZX6A5KM!E~>BjQYf#GL6yHC4jpWUoJ4`uY()8^Ca*=o_^^I!&_PV7CMn|r>$?l1LyIv%1?$Kz}VV}4)l'
    'U@E$Gd{2#HhP_<kXrs<C)*rufjP*z89J6&_pkgbTFtnfBX0exy^{so!6zqDByq63`WbgZHKJ*7`Go$iQ'
    'l(w0n4{zIMrg_1E2WT?WJk5we++BMaGJHqvWy-Vl9!q-}vifh*UZy_0Z~OK#IZ|oAy-bt3v(4MfR42a`'
    'RSt51cj_-wpCnk{UnccG?A&06cWcS5dz)@8d6a#FZY{E4+Nj@&RC%PlpGv;MN%OHAbZe>Tqf&95bkj$r'
    '@!8)d^Nk$-F8io7J^X)wJ}Ly4yYx{hi&A*>eN?u{c%&lK4lPnj&e>Col&2OcO<JTd2Dep<6y<$cE?w-@'
    'Bc(=l$rVUcWnz+*ZJ&v`PlFVCh-(_8)HDPsm18Ozf|O-S9(0`<NmC&Y8m2x<=qc?H@)*0DG=sc8ck!TU'
    'uHr#Exrqmz<s!2CN=`mJXp(GruupQKG;RN%ts9Jt^j5mT)aCl+v|lNpESKDOutPFmr^@|<^k-3K=GE2u'
    'FSjY|(4R%t9S1pmvbH}93+LXYKZ`u`jbiE@TcXG?)%Rz~E4d;ld-rD{z?Af7De<J|%e+03#vIfz*Ss-D'
    'wS{Nz#vCFz+cf4V1FO6-M_yvxsxe1SZ++Ot9NQl5d_V|0Nev7C*VFCZjX9czUX-RLsM}}AS7Vb{i+umG'
    'lKvTuax+@%pMimDxq(I*A|IxKMy(HO>t-0co`~FmZt+aC&<tby?W=DPfoW;?4iU|K&O3I9U=HF&Eh4PW'
    'T0}@%UGo+Z<s6~9MMQ%(^mVxJszn4Ql}Fekq8aa~E?HTS4aFW2MY*wAPgvd~qVT?;wqcw;HHmm?67hJN'
    'M3mdk4-}^Jga02ozFu?'
)
# CATEGORY_ROAM_FROZEN_SOURCE_END

if __name__ == '__main__':
    unittest.main()
