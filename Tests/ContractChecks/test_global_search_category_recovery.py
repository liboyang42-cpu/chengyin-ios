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
    'h_&2-Juuv1-*$VBJ~V019*(Hp8)AiVukTtt$1{4PzCE-o%QmzjC7$W_-2wd7H(cGy)rxy{{Qb*kXimR)'
    '`t<A=M<4X{p|<z<_37#H^H=A$tR1s=L-Clso2$p{)h!>hSEGK+-nIo~_HI!@X783IWcD_xA+sl^h|J#l'
    'Dl&VUm66%Iv5w5%28CqyZdXZW@Ajo+_SV*t+1tLD%=%}O!X}{PK&~($l(!y|0rH6m%;FB`g(t+xZq?WM'
    '6xToVcJKHfygEGsBjV-jS9n41j73&zO?zAwej6D?*NHx~OsD6Vrr~*(?O6kNU=WHW*?KzFT+8hbN8SK?'
    '6pZu{9T8LSX;`$&F<Wa=<u-mTh5kIl7!i=4rfH4(AoMiHG<t*K(6p$f!3QJL)kZxKqP^kJ7~1xzKcc!}'
    '_OT?O-XHbl%qk5#=I+wA&VF<9^c9Havsbt!EeUWcU;9h!^-ApUix0sW?(rFJ@ym3F^X&Fxu;0|YTKU8z'
    '*<<I5Cb6`YadJ}I9LQ2FCYBnL9z^D=GBv$!=FTyDEM0YK6Ey}n=YDXjs_9im;_d)K6aHbh!SziD_@Cn@'
    '7sU)vG%nd)8Xz95y7jTmJ>RAQH_jcnqBm@L<J{sVq}g3#06TAg45WzhB|Wn{DSl6dc!M&0_agj0Nbs@%'
    'ZxB*Bb&DULH4QP1v^550tDY&1%_eEaB8>Fp;FtwDcYx}qS*CJb?WWC*)^f13IW5vEc2Q_}({^OA?b2S`'
    'y}8!7wRTs=+AeIhJ2BOAmfH2(>sy9JD#H<jo@<VV-pJ60rtP_&(StwDkuw<fdZtBOr*91g)anhbq2uUY'
    'pAHAsNV5k+Ycz5V+S|fnTnaw8c3;yx#~NsT*YI53prfH}+M0=f=+rZY=D_Uh{ei1da{#j)42Kkh62=gw'
    'qS0;UP#J2FMv)RnDmCq!&5IEy5jAZ8g*2jT75e_k8kBKlMSnnv!{_RGUdtVs-O$6UdYB7){Pgtr>^mMP'
    'JR8^bnKBPa)|BN9v}@99g7R9DE$O?oo6A<RknQJ)HmUd$j9LYUF|M=?$D3E@`R0f67a?ETG$w2|kTn%r'
    'f0NUVO4V-@GU~f#-|T5bA9)6`9Mdvf$2A5cy|3vbYoJ@6*?0Sz)$0?&T6`G}F-BI;?e&~(1>chXCyql%'
    '&(s~z^jeP$hNk7{BTBJriDla(R~y*Fp6>QE&Cy98Tk7bRi!GR3&mQ#Y))Q&g2xubo)5@;wrwKQ6@_`e$'
    'WJ|t4j>XE>Qo$sr>u28`<yt;UUx^6hBo~N9J!`38SRJO~1!U!`tTvV8Rqf~h;Mel9)Sq@*nG+LxWCk|('
    'nRHQD2!j{HWXs0BrnRBSw}u*E!X5IUZ0qHIg#LD6$L!viY1E?Gp+Ih49`8mR?^YV$jWAv<i?3@7<Gf9j'
    'yvH*CF!M$78D48$Rm4t1#sE)ablu0IOk=vZq;O-Sfb;H223c%hb6~T4`cDXJ+(-z$g7pf1jZ|2S1yqp('
    'E}F75iNOiIAkI}<F)@eKrZz5*I=)(w>YiNtY6xy=$!~BDZ)I~nUr=%ziF>Y`X1JD<3oN%=d^sH{Ne`Lb'
    '+OVYDp`g4gIe9l?vawV5duwfr2v&o8m+2arAXcn{=`p#se1&FdlGJylSnf!#>{6}lQmd>`D$N++DgH!x'
    '<#+VzZBkmRK`Q`X?6#SFZM^d8S}vD9xnX=>d0Vb6-_tG;YaZF)!8Hg<>cHW|J<Q*VuaIX+;hMK^^tV}+'
    'sI_0za$nSUhIUv>gP^3-_I}|qGN3;Qur+O~RIa(z&DEdAD9iq5#lib4E|zC(+)bN~N?n<d0}q%S;Ng#?'
    'O3qmB3M=nrwb)iQ;Wq3{zBf)B_gK2`PPi8!VQnLJ>-(_O<Mu!%-uF{5n^rb^dw7GqmnxQ;Qg^uS!+fLm'
    '6c62sUhQeC_FuMsEOcsbZmo@~vqrVqJy2$ii>o_QWjoVk>lB$>S4Fa!_A}-2v)A9Gtuy)k+;5J*J$c?h'
    'W<}ZvVm7B(e;^Gq#Az?CMv^R+YN|*D!B*ldU?o#JKTnHEWS8Apj}`b*150Zl3!AMc_3g{yplqjhL5RoC'
    'pGXcM%T)_I;-0%<o}X5Bgs5FXS@UN3cx3(JnvK*JR=@~CR2piCDw>k0cO+07lBahfPS;7(>$lg}dyh|#'
    'kKmK@rzij5)$7w^kphc_yjabZ<XZ31BEAf<Ldy4kK&xu+EPavP0$!?;0%N`o{J3~$n0*y%_OO~Rkzc+r'
    'e5<-9{4jj(yBBm-VV<SAe)sCt%QC>*6pGop*h-CC)E!Ys<>e7iA`(@@B@|P^UYobR@>KQEW*O7<^P@8='
    'K0W#kuhYuP-5=K6p>)`@S2*T($Io7hUIIAuEzpw=l&~S*&#xS46O`@cdqS>X<i;hK_VWEBD<`$OAJHBw'
    '4!9xOD@!8n2_k-VdVGwJ_syZxw>;{MEJ6n(({_8*(11+z0ql6cr(49-N7P6ktZ4n%8)*g^m^M5{yq?t?'
    '7#=nHx^4IDfvpq6(_Jz&Oq*DS?!dP^!|B<cNj+WD2Day>V<*_ohSrH@StFYa1_OOSY)bo@JtA~yIZn^j'
    'ya91~WYD)vGO~0+dPdLHP0w;Iv+wk*K|dQhsS%wGJ@op0!|juv*E7j*;OHaLvoy!l0p@Tp7`dKpnkMi`'
    '-|N{ut!Fvzpx5t@`nKtLqftK{I@!-`Xwvukj%#|ufu(u2u9;e&*jCT8iB257Z)qBFs5u~-Gjv_7kYwo8'
    '7}35<Mw$b#mJo9K;y2Zm&uilc1xfkx!qBpa1<UP?T$q;Y!PYrCrTS2_iJ?);=vgDnGhjDq&!r9-I@-V*'
    '3}ExArx_!5fwKA{0<&S#?zGd;d6!l-$6&!~eZ0npV7IiBe2T1OU)q~mH2jU;7;m>59~}XVY_^lGSY4iy'
    'xW@A5_i1L-fqC%-Vs(i{>`zpD_Z;!SXNq;s+4X3Ch$}MJ5=hIbJegOuEiP9tRR$*apPZaMe(}RGNM0et'
    'OSKLEviyZ#t*%nCW~#T}6q$Qc3@>dKD!Pfp&cX1;Fj;(VFQTMQ;B>~SR3{BilV3!aznktArpe-mn_L-V'
    '-%cSU*8q4F**!dG9s+OaoX(UNeMq0V0RT%VPR7f}wbKET7<NT`yDF@`iZ!;O{bsfx^W3)b!LybRUVajy'
    'Qu1mhEbL^~HnMV*(u%rDE5Sl*_0hqtD6470l1^8v*_(NIPfkvcA2Z`ph`3DiucG`G=+1$MH3kPd_4=bB'
    'C8#hpgKFAPAN7WIAM`At)^MPa9_@L=wFb2BXdcms0p|CbQcgDt7KY%=rQcSXFf@amJY(&;vVG4g?%o(g'
    'KnrxuLhzsL0tE-PeA{8&9^5p2Mz%{=8D0l-`W`%O>MBW3EMBWutd>z@Yn{Z|jxL%ci<?B99HRIv<r^-2'
    'jcjY0&Ko6jDOBEwd6T-@%*n20()>($bxG592Hs*a$x{Pw--k`2v*6`4bQcq<fc>hFMSKa5@t!w|eRU%&'
    'Ea2^s$pi*XdaMS(_I_{yANf(Pp2UMNm|XG7->UK)JF&9%zx->6dUXR^t$e{>x{)JgBR)^Y=PSR-uGtNF'
    '?UK4y5?3>v9!_nrp561MjbU~8sVfdjHfQ+#{e50!KN&jRod>^CQmH1uVTJu{zXFD+<m;J)h9S3L#&xzu'
    '+Q~G%`FUei_u_@JCOjIMdm)$SljE38SU#I$j@^p`<ko?lE|z^0tM8bwZb?_t$Z9p4=MLb+d6~OC=jSRb'
    'EjK&ZhUvdc2UM^xI;)S$x@t_W4!GnL=ogKE6zuq=M6nMdn>VeCFh`Mh9@~KBGpmf94`OxH7pEuRo;*K#'
    'c7A$%^yK9E@!8qUu12{CCl0noliy|!Zs2!WJMbB?y7+7ZPTw6hNhGEfv~>OUI_=>ivRu;+4{I8@R8~!L'
    'EX|{|XHh)Hu}x}FI_R64u9>5rVe3{OKGj|DIjO7ZJ>Aqj>exfacId#d9J)!>q@^>4zBjN&w$;-CLf`hV'
    '@{u(pBXcw`DY5%QTi2bQ)$8?Ln^-QMmpCI+GxfeXFo<IfH-TAs1c9G?%?^8ky8QR}^F5g>9&1zs=*uJS'
    'uNJh{9n@981n2lPg2_Ee`UWNaXYk_Ko3~8?y?RQ3qp&fZhv6^jU_gQ`Ch@p{$5ZxR^hi1|P`L{_R?b+W'
    'fc)X{fB_Bhrf>xU)qhVJm5rAPPyTu$I$?D}e(eWt5g@+P0KCiaL&RG^MU5d*$baA@P6iFJj{x(OpX@ib'
    '8m4j%m9!}pql9m<k7;9Khz-9hn6o*>Q$+U+JMN8@*RM~W)TFy)^a+iVO*)Ht$HT0{9p)8@ephuCRd1%a'
    'emiu5RHJZ86;#X0r+P!;>&%&llZmX+@bv@ioAa(sCjLb*1zTvWs1x4jt*b;c;=nIs>`y2Qp0JimEcR*J'
    'l)%<2tZTj>CA+VRfnNvYJ&cXnW&0h~1CzF`I%I|xEB*-<>>N*_&f=>HZL1LlyV)i4tIpQ*xR#0@Zmz0+'
    '^uqJdeg(%Bqqq|B6!L*TJLG)F=v5{);tR3!)Ta|Sk0N&M_!7JTI^XZI0`ObkX=(kO8=cto{zEu-J1P!$'
    'f-cU{A_j>y^JA6`$#M}?7H{atT_V2JXkkzN_!+V31UD8}+EK&cjJ*xi^@>FAY7iOuKwua?Zo8vgE7$VZ'
    'u<dv%aUAfFecPY-@zn_)68oM{=lLBMyR$DD_1`Sw7(C@qWg{t`FDM{sg4;2!fp)&1xpi=2i-2mQt0<<^'
    '6HHm(o_P0BQm8!@(|Ugo(t=E|Q3lAU2;>Lb<6B)JDMmwf<e=S!f3_R<Y_)e56AW_-k8JDP5v`(oR~S_O'
    'e)!Q3J}~KoHiZ^Beq_UL<c__%T{v~S@#%Ks(%pfVb(53z;zK~^V+HSfuwU!Z!tNZcmXvu$ph}%MTm4wU'
    'mg_N^|J$32sV+w>aEtup$yj;8E|O;kgp}c<%tw|oUg2nZtb7xO6Di{+*A%1-dM#z|xvnEi93WxiRX_0K'
    '_Uf${A9cFP{%r|QxO;4nZtYp~SBU~rkMb!0ez&lp^=9u!kJGU__l7ReOu-W^=DjTks>Mg2E3GJ{{am@v'
    'l87q5$2nNpn_cC1JjBgy_`9S7sUbM25x5-(;2Mm--IMTJ>slsmWC!2wGWI4BGj$_xcM*7NeFJV0a8Ub#'
    '#u#BKM&XoeU@^M=;PC9PMLe(3fZiR&^CX7zBuDdh6U@7VSYE@SybU6Gx2mSJuEuK)7h+M#jUUw&VKz0!'
    '+t2%3*RyREP_oa`sk}KXORPm=2v_yyWJ=ppKlqON7ne0o0!*{BntGQ}gy~6FG6T|};J&Ib++dqh&;A5M'
    'WNqM|8X@D1f`c&5z{uShI*BMQD2cjlA3}dQ4==!3h|sXhv!56lRW&C7^6@vm8((gZ8SoQ4bQP{Tn+UNK'
    'ej{iDhn|H)S8P7}tW)REk*l9&J<`-_xW5M==ORAMf6B)m$p6I!Cj5bVk7SL0t<H$c%oPdzE@4h8na!S)'
    '_x=U5VqT%J&eJBB-ko~KKf6^KjcANU6~>PB#hs{&MzqBWzLmPk5>(I5G|%o8&q|avt9F{uI_s7a1!M-!'
    '!1j$oTBVa(H5sw(2jgN0vm=>+@s+5`1ga|D=%y#gc(xdA?<HsB=7y8&m0hP+z*h-F{^A#c$PN#cz@KbS'
    'PEr*8vaXXdk_3yPC2vL>+Y8d1OaM5!;!b!wK>m<qh}{qKD+WQ<_On1ci}`m_(I$?5+fuAsH4J!{$9CwA'
    'OK~y;dEQl$sF@!iqivldmL<YJN&|6U9j2pyg7K4@`m%D!U~y0U2#5t}5ddJ~wVH>rbqV`c{=~mDWGNM-'
    '?mB8d{x#Yc-z<C#supuRGVvxkSsA5qQee-Ij;FKuiVZ8tTad>4ExB@8f*dU{K0C~o%Jq4^I7*lzpLoTC'
    'nKFjYv)xi^*MTg9$svJ5Cod_F^#kv%VaqK+O5<h;C!0It<r`U9nj+s}j5RYzumR*;WH9aDAJYL}Ps8~!'
    '0l!5cy{n)!`0+;-`#hj5$aJy1z*c&+Q930{b@PEzaILnE+UH%eQp86<DxG%hJCo3Pw~MGgP|m$FAtmX`'
    '-9@BibC+c0yc^zH&05)!aYE`HDO`0YOw~M3HDH=aQCWBIAU5F+c#FVE!$Ic?Yd^KU60W!v-oa8U(tQjz'
    'PZgay9$G3`C=x{Z(wRKi-?0x%^DlyvK;9)A#*HE+$P2?b2xBVo;J3+(Qx^*`JJHydbsTipZdd~bx=ik>'
    'Vy>ll?VIxbkhdBCZ3$MMJCO_13I?8sA0)7@ga&;gU+<!L?Fq>~3{*TXq|v1~nJMz>y8Jz9I#znd)XnR>'
    '2O$xD44ETu$&|8D7OpAt_+=fDMKKYPayhUPi?@KmWxE&N#o%tO)HNK0NBY6et+Y5*G6z;y9e)lU!i>b1'
    '(oE28Q)HL;_?EmPYrEvIiF|Wt=hl#HW2ku{y2=!i<83q)r;y;q-~ssiG^(3Z<l+wZr^1!h<Sh0Nf7rf|'
    'f~LL`BNaxzmf}l@rKBvAStn#N5!bc1PlscN_(7bz98pgCpa@l(M*)uqzIO$>>taG8%prDZ<jj3`+hDAe'
    'uO%?x-}#sfB_-09XdQu6R53sr(n6NmN%J#5!1#%aq3?ia+@prc{f%LfZDFRtlr&f6F`2svVT|kPD&jiF'
    '_8Yb0!im&y=hohz%|ch)p8YG7Z9q|ofNyf|cQy(La^FY&@kh2hzT1)JEH)E!x|VWdc8AhYzHq!rHZFT{'
    'nVf|8wgk#Y^4Ks%69&dyZQg7PZl_}Tj-+yPLirA4a^oVo0f{Wl1Z`R#*S1(6K2%Q96L(;lz`2}<LAZz}'
    'c+?U&lLZqQ$q_v-bzko+kz&7Eie)gAI8;cWFs9*Gk=6P-G_6O3X(k6sF`r;Xw&|Tl_X{D%LONAt@>4D)'
    'Yx^F`El^zt$ps9i$PSVOO#X-De5k@2lcX4+MThdr6bYP;LXZX}9X1qdT4LH-J~dC)fkP2U5k{H(Y9_Av'
    'G-CC34jQQ$oV>(ID-4=1Cc`S%v&MTEVXI+3i$R|!BLP~L>irY|bJOBpIM5dhklodl6c{n1HJI&HYV2$a'
    'R$N{Z1;!<080=8mH!1AzMAl0zcEY4!F1a8*U*bizWCX4`rG8aR4pJAfH&nsbz@T}AMVBURZlU7`9iEoI'
    'CEx;?)^uMA+qjh9#AbY7cCn<d%ejtHvKiMY=7W+`%6w9Z>uXY1SE*`V3`(eKS(TykYMPIk8^0_z3c7Yn'
    '!17h}?lknS6|}?%&Q8^Hg?6sxjmfmIQ*9^Bn#SPR?}X36C32(I6t@o?67ZOTQpEKgR<=ew#J=;6qT9s0'
    'Gn-!cL0gmwE8P9553T6yF{DUXLaIUV=D->+us$f4dMt1X0-oUt;~cX%YI6*x#ns9;rnV0Lmz`D_HoqIn'
    '@)TKs8I2c)`YU0XCX44R%l24O9vSDajS;_nWtYSZ7bL1IOGXK+Ny)U9{kM@KC9caiLQRu#8*qHPNn5LN'
    '0=-Jp)`TY6g+}!W;`q}S0$pBBA~}n<<dKBh6dV0^KIb&#n!yLDezP3grUBEYWZ7g_=p@nGU0F^oIftuQ'
    'IgynkIV{#mkTQ5`l$Bj@Zl7Ush6H~7!{)LHCBbNtVsGr&+^7)dUt!b@Ns?XioFGM}Y|vFoa=0t&N@-bp'
    'RFvYlCwx$(9(f^wGDfg?OmxYkdtJdCV<nHDtx=yxYm?!OCakcX8ey$Qq9k=qunMNlap)$TC53XN>%^UL'
    '7VP61K_dkwW(ISk5%xwAvXtdv95YLj-OuMLXG>@+jnvQhGEc1#oal^vhTV8ypWH<!!mqyvIy-VeSR@@X'
    '%DsaB@=2DEGiJB)el?bIIWOy(F;+-$mANpd{8~l*_KIb>oA&gP5o%(sRTlQdcfJ=T_OOk6;f?RYDHSYQ'
    'w_YPc3j>}(KUUgpc2Dbv(04mh7K3}?=J&as?#7dRJ{ADY{Vly8=$F3BlEBF7?A1_fujYGuZQk5#%K(EM'
    '(Y<|dqdO7Y9I3~_dw(9XOK@$x9Olq~zPu!OI9n(+lfGXITvKYIX)Uo+CDE*oxC0e&j~YK-ol>qEBpAMr'
    'OG7p{>6hRk0E4nkIC%n7$Hrmu!SVgrDX_CkO5=uGKz`|rxta2;m3+`}JINjOliX25$-C$%xx1E<yY4B;'
    '3@^DYiNAD0y<-}>gSMnniyJoHVZO;uSG#L<^`&=x)ni|J*EiU^UN)UFl!*F2z7qy7g2`1UyP;gOeUNE('
    'mEt|;O^72w>OCkYmX)m6jgD#)=N+$@lq;5`hFEbYzG`c#Htf_nAyQhWI5t}4PE3Le*b^t5gC061uD^)J'
    'iazLcWLHqlBcA`Z-^t{YyxOU9%Y%OD#CU(T)0a++>oik1qk&LN3^$*B55~REM<LynK9Y5vey7@~NoBNi'
    'T~t;@wY{ZXHms`)C&DOY+mA$O6q}*{JZ~U(WaTrbZtc@7I@;#klXPk67S1~B-v{rOjxoojzmb0Ma;((a'
    '^FN_RKJxo{G~Ljn`HmiU(b7X=Pme#h4m}b$uWq;aRRvQsX?~fs77$e;FM+qvw31L%Y=^DT_U^4BTFU&M'
    'mCpgIjt8YdbNHz_fGMBUs^TNOLB6#qmJG_Jv9wt;J@z=Add<nDE6$_-aenm;EMrF|$1N<5u5_O$eI<aN'
    'aaB;8oWwZY!oc|z@xL2f5h&6$&y8)5;1+dCX50J3=|vkqXrKjY;l&fk^FnOvOC8H81>GenRxQSoT=MO2'
    'lgLX!U->$hC}9}cNWRmw@&z8F1TUhs3FTCgz?R@Pqa4|+UDhgHX<IHXV&tda&O^FaH=Lw8i48QB%6VRm'
    '((^JA){>1S+FiD_!Vf{zE?OD)O*U30j`3TRTS8dO(6xMAk!;t#XEc}d#wC;8hSE-&G+IMwyP=qRElEEE'
    'lKH$E)8@KSm#Bg@qdu?Esbt+=NuPW^f&Md_c`=TFb5DwyOETJ6yAm<vr!`zDiS--h(Pq0bAFNLO-V!QL'
    ';yzHCCn?!Fsv_!qWAs=~*JmlyU($Sh2inOs82(d|momniAze}RYb>fPe%8J9s<NX+mg&li7^*1yxOI|)'
    'ANX-;gF5opvGTIwr$();N76>m6}p6lylr5olK>&B8rm#ce({TCR-K_9ui<owk_`<YCJkVIu9!(gZ8NC('
    'oM~pl<}b70RWW1glcb{AEAELMR2z2NhAl*i;^l1Q+N)^HJe0U|Ypu2V8~N~|^6HW*Gjc%{5@75J_6+_7'
    'zfOta1J|EZhc``UiIfUa+&S^K&LP74&Ah1Coc<1*nW!?BaQ4BE9c*2yM2opc98gDKAi~rm;Lgbev%I1M'
    'n0iFx7^U%+5L09znD<~`AsA#WfUHWXK(=(^S|IyJO1pxy9?1*{D$IWDDB~6GN9|Q^Y7CdHS}DeHbEj~L'
    'y`8x#pc%4Az_!x|C8F}7J5qWu@A{Zsk^{IjQ`C?r-g8PpPx3P?S*4TiT^I2t5`u~)6+f%I3#l1QQWKbJ'
    '<uA!;8+$L3AIr<me8kF?*UxAx72)|*s-D|^N3UvJCtF&GfU}%dUFvgzCTeH<TT^l_Bt9d*zxv_Zx$m}}'
    'aI%=9{CI<Zp2T$8R*6eys9f+?fInSK$BJ(BJDs=NS4mD=r|X8al<1^`VMa)Z`eZkxW+f+AOyu4YL=hfv'
    '5zB3^1NLW1P&J~unS51!_n@h)Y9<-dYc_I`!^8z>8yjr2>9{@`u)b${*@b)*mt9mpz;dSXRr&IYq=vNj'
    ';51<ua<@wCia?Yk#ku7WFX!O}nEFw<k*f$Y?XS6{bdjs+lCos>poD6x>{Po#QOV8T%qhFIN=tIuz*og|'
    'mApmS)M@^Cm93h~XOme*^*(U+Zk4zs9ljeCE?t9H>ZqG2U3!XM+i9}I@eb^ghRl)%tddQPk{gVR?GG7O'
    '+9b98!6q9ZHr}$hi57^v?16Y68Wzj!f>^%|;<j+Vv?{*CNY0(NDwf%3uW+5T$%cD7YW9{PzAd%aTLDii'
    'T54^7=QrP^ue9H#wyA94wcDLb7a5JTFS~o3XLzb}vVI@Bj4f&29W^qo8AbZiu==iywbizoy#8=28e2*C'
    '?(R_+>@Qua8;l5j4w*~4X|j0z7G34mW7wXD<z516gzX$a$|er-d2~sP{s85!p$$h=cip~c>dsI%b=|ZK'
    ';&^oE5Kr^;A?@pfQO|V^2j1z8G}on?Wt!T^fnRiM6M4_2d=6;ObOx5)AC7u<pV~GtD0POO>pA9NNJh3k'
    '7#N;uk4$d}pa<@t=UV-KZ`dF8O?O0yyAjaKMer^HXm8440k$i7vr+6!d^rz4L|Ey+A{BXSZJC2P6}=JC'
    '(c3Y(7%ShG-+o0dk~wV+G`E<g@lV4KQr06V`<zqbc)5AOGG@01TC6zF6s(LTV12W*(lQ>yd(T6cu3pI2'
    'Z~+6w(IqeC2y>+1=Sy-y*Dk2bQXR+JujC|%mv=W6Jo$OZSX%%C+gEK+w`8oGhGfbi9l_rcX)K-oa|SNk'
    'n_JnmC8Kt?(&jFNO>?s5E<}w~NmJxb<iY4Ra;C;A-eh-z1emvyR<Sd2DPLONjj-H>tlX`rTrDYYbzW0A'
    'u(__GCmue0sJvj=qMrW|Yq*HuV5D4<_f!c&#ZBaq0uBQ?z~E#MVhxt};4o~jF(?c4Mhlix;VmYjfoY`H'
    'SPXBhrO=Nt4I=PlmRf_=2;F2IwWcIkkO@-7DaD(}*!t=<5bD4LKU`C;<=BT9o%lY51WZ;%mXA8hr|UmA'
    '`x>ywzM>qxJYkJyRiL-*<Y0Ti*EQ^s8sWq{VzCA|tWgHLR|@|o8oaLGytOegvSTT7FYV@rWXSECJFm>N'
    '_dO*J-_Zc$tL(o0SDZc73nHS@*>PyHn5`vWiiJf$7BQ<LUyF#BdXr=9na^Lsn04n>_jw`ZwlUi!D8)*<'
    'y|&?kuT0{cF~I;L=aCA695~`koQAa75>=EEotobJ9T2*7I&Xl?@5}jSiN-hAw-Q8lmA<WyP%yJjg5Pqw'
    '1`~=#%!p!lAMr$i1PV~aY&Hiak*1``%5ZTO^EudRY1>|v^BVf73?i8%N?x!*-4vH5t&{C!MNNQ$yNXFF'
    'xX|>CpKEGHslVgVg{_GZCDK^=x!$>FeAv9MX;9VFpq_e0RUV5;^2@nM+!`ydifJ%dVuE$0W*L-QYt>K6'
    '1r6w&9hqXO4h~Jtz4?n@ByTdv_$B@ee6Tgx<qQCs=1wUuBfpqm9x8e*Sl2ZTiW-}|eXqeg*kh?%yu%%?'
    '6C>IFNq;&E=dtp_j_CY-tq${bW`Qvt41qidgUMBPD<v!U0n$nd1DaMt6m9Fb4#ed0HB?rAB?VP)5xhhT'
    ')+tg5*Fg_iwU#csfq{9IUUGW{R&+53#~Z#GT-8i2#0uhsU#zQPlYK3y01^E4_rwp55F;u1`vI9K&V)o!'
    '{pfwUTwGnPnMBrt#Z+PSKE}%N?-nE`yw0VA6+nC!E0Ir<b^*M`)Alw{-MV6hiAV8#;Q$-*s(Rm%=#tO8'
    'zAYgDVCoL16|Cj*!bU?syMrkeOiqPJ9oI=Mbbfn7>fq?_A~sO=G%^0_aAkck%e-1Bo`~Y59B7tS8X%!5'
    '<#36p!~{AALZu%{$)J`q?TnU0{$%NX#X*rE>d)Pej`9P_S;aC@Wvf~K?9U|TB1EN#6%^!r{S|_Crumll'
    'As5I@F3TUiTw+U($Sgz2Y*ZN#<ZPmtUpu04XQO(o+cV&sx6RCW#?1^~UF=X%(Y%mzX@V7;;)U{FHVPz9'
    '-H+rATSe9qhv((k<XkAqkDK>ZMIlXzIN^n{r6A+$oVRvz5rnA45?CK7dB*@I+P_`LyI3+C8k{*!8k-%A'
    'Sxu+E{2}zgIDd}*)UO^%;b3MI)jz9sDGr38RhZ@@QTM!FFVT7vLcjBvIZ+|QF5q<Hdo=c^REfdEjC@AZ'
    'Nj=VR;?}s+Cu(_OPiAMbU^xp%55IYMq}E@<X;R5kc}M9i%2f-E$do={!YcFAYurKy!(l#O%wlnl5rG|b'
    '#m=RsRFxMgDwWl&vckJk0vM@?&5F*W`_hqh(M}YoU|OPFkzLA#`7pUC#UTCR514r2sijJ+UmZ$9RtiAq'
    '5g1tfChJD&vK~1o2@C#ra=C8nb#a}-hmkY)rQP^cyc3MI0P?0u4ZDolGO`YrMaA#J-0sB<enx2`NSF9#'
    '2Li_&#gbqw6)rBmaZsT7?RSk2aBt51SVj2r<osBevblo`SqIcv_^fneR7x9b9!O#13CcK3mV^f(m6CV+'
    '^7f#{`Pg^5i>UFRg<w!5v3%<Kam0#}gNg^`pCBMl$6cP2u=T<N8h;4q@8pEb%e1(nV{jF5ZVOTj`$!&P'
    'bAIk}MiMjabgN3C*J?qS_8^o{)hEX-37Ul?E9Nh&cKK5A@<J#j`@M5-#9>u`(etE6+E_`ujMhB8Z+&V&'
    'X%(Aniw?>mXBm`-{GB_OSx3r*Nv$KSsFoI5oGzj`>Ccd4&Y=uTPBQC6kChLXK3GbyziD_{qSSKMODg#i'
    'M*vZCA^4(7l`A4vlb8^8_l<eiGOR4dbM8O0eT~;TfM77R&vUB^*eW$3$Z%Fuw=!HWN1)`<f7+agJ3vj+'
    'J}<H*qay1rb~LFUTTTAk0^ZG5ie!MF&}J4YjU;oc-n!ftYztBP)-5H8b(J)nA`<Plcae(~WV@@qM@baI'
    '$7kJ~a$Ufrq=X+i+#kbMR1sijLLYb&tdpul6L7_N9w}xzEf95EqYN{0FXv$pE+PdzGzppIS#&H#%|RL`'
    'N~()X#XXEG+EKh=$1tdAyZl6k@BUk9trA@7vF@4(;*p9)Y@^Gh_iDP_j;!d~N|wn8yGFwbwuGg!%ZI!W'
    'o+7;_B|~2*vx!1lB{JGgnaCTrgcBb3uml%uUH&!4KHVgS*i41&<wbH+b*Uz0!~|22cv@)Nzo#|t`I7mZ'
    'Tq!;~b;_>%rl(D+<VBTY=%V4I2-42#M%MXga;BV=+XU1IDr2q`yEh|~iC|0f<KuZ8R(y+?<^d<}y^p#f'
    'g3YD}iXYdgK`mm40sWwOyvm#^7ge9Wuz7us;1;zkj*wN;S<<PHgdxNMqS!TQUWSzMWV#kb+vYqY)8vwh'
    'JZ~<u|1)D+I?)#nZS&{Aa%#_~9%)js^;6~9=pCkVUS~BUk7l#1WaQJVvFf_Ak-c8e91g9ars+LXqh4<`'
    'Ff@J88}y8!W@(1gx2a|uJ<FmR@dh>>4t1AU!+yW78$(Oq@D9~d<w$p^_4}idZS@V$adpk4re^nshG+LQ'
    'w{JV6fj#nuo?#6P_<vw~1Wa`5nlK~Hvis(ya90+OEWfJy?rnRyj0H-nyH}-si$n)22YcOwK^@<sQVB>N'
    '?u=iX%r6MjaiTi?m#QI&y<i<y@J8qhhMy?8sN4WFeDN+j?fog4J%M$x6Q5X(Lzi5!zKC^T^13J4ux&oB'
    '^exZ7l9n!68<skdOmj`Uu}YNfc9*6hn9m;?*(g5rpX**Fh-+qX^~Gm#z8LSGgm`T`6`x)h#^8To4<nH6'
    '7xQotxM%Uzgtox~22<N5^Q#6{*8nx(f}i?y;^t*6_-AuQko#Sw)^Q92`*Rf8Pw@U^Ht-r^$)+Ky_p^tZ'
    'AeJ&;;}zx<Tur9NB-m`wHXoJqbN9BxR+p4%#)8<b0U_6Z*qQmzx{a2ouge=!<*i+4h8-*MTkVV#{oS1U'
    'zK8oGLvioa^lrdNxHmRJwTU2N9rqJyyhrf8#GCXH8@H_PgJHE}yK0?Tb$wgAsvMeO1q4b$Xsoo`XYrif'
    '@=1QOa@-GorC=^ZjjMDi`dC$j^%rNQ0uiQM&GHC^kr~<mR~2RT1)}Q1VHf{6<yO@1?-o#42UZ38yOpTx'
    'O7cipeOOLh%Av9kk^yU=orV)ydOHf|@vEyEP3#z4AYT|ymo@v_b4;z-i>w|&a9`6191+CO8q$*%D?DdK'
    'fB<=Ccz)SNg7nGc2RzIki~A3q`u^SS#n3LKP-8-9Y2au4$fTi>rB0dUN<PjZz1^0*rOis_9SY_h$>mJ2'
    'Rnk*Zub^8=6m^!D4!oWy_$i~LCGJ%7NKrhs^v+?O+3#BI+*a$<Hh&qcDf#G67t<Bc>L^j+a|i%0=e|SX'
    'j~TcFe7D*^*T9Zf9z6nr>&VjAiGS3<deRebbVvB9Hv^SQLa{ZH*0P*Lm;G^2_%v%lTnBD(u;kt`yDfFd'
    '*`WTqBphd8xe+^bfhVJIN|hgc`azbp_nf@<FIW~EkdE_?4J#pZ-x!PSj>C4rV7uY3J7TYfxvO$ji5-(I'
    'EqUjlX7sxVf}y7P#z9g)p<vk5!(eH!+UTku|C26?)=DBN>OTJx5w(hwzx}T0p~Egr*E<Pj!OCRddU<~h'
    'MXHxiK*?mX-%-I<Zi7AfNDab(Hk7&WG@Kt3=dzv29t@YV`GDVJ0|`uPZh)p@yKlZ4Za9+(=mizb)kcy{'
    '8W^(9c((|Sr_|qRB+=|k(%;JAcANBfXDN7+(?FV+-_phRN;%lH1imW)+@$<nxu%B?m0wdj!`46a<80zP'
    'evE-1R*aw2Pkg{zK2tx!TcwIO52x&=58ld=aO(<Q`)ii<0^1BAxJ3kf5h?o;*7A@s>O)=^1S<++TfGas'
    'IqOHFQnSL@ppnf2%^>asvHmdZ9&nlKx^*_~tBkZ+`3T|%QTxLsorAabNnw=8+IM6VxNeHe@zq|Xx<K~+'
    'vUa{f#<Tm%&wl)|ovo^~-{~~AD0~$;JO{WLu-BhKLPU+>c5b)bWVR*F^u5coc{vX+K!io;e&(?wE)wl;'
    'lpm6;GJC42Jf#Xt_<m+CZERdOCRG|{pLEYXv92cdTR9ZeoPtTr`)r{M_CBw&ThkyeEu*uXm}#2Ls+nC8'
    '1xMOvqq~-bi-=6t=sA}~ZP9c}d$rzoX~pUy{P_tfv8;P;^?bR_aO<c@?oKiGXaCN}`Vm)X%|z?&6YC>m'
    ';0#S$H#Oa`9DC@Q&Y({S9qQETX?@qT;fJkzhCVX;BWl`OU(<9OulJf(f0O&fOLvJ4V!8v%wrx%8xt=yK'
    '2mR5=8R<GebqwMRsG-@T5jBWs;Y7UQ$fmuaNxXqJ)GcEZn3ea4YxIW8dQ6E1JS8NL>z-TWa+|V>`3U6r'
    '<BWpn3>+%T=GUx3$Br8dZ71f`3Fj`RuH_bW%HDj-ik?e{NU?m%SYcIE9!Vd4lANYV=#V1!a4MA;XU;sF'
    'Ok|CQuV>`<S3j_0t~QzY7r~TOGF2x@tA%Jr9F~ox4?4F$lFve@+s?Lm7HXb@Qi_=P@97g7#eN{FA&XSA'
    'qkyd>$u_G6XP1oHD4#aVrYlE>EjkXc9NA%>(4Hl4Z(of}zFd$h7V1fbTOE(zbTnS87Htr}4#<1(sj*%v'
    'kIKwpA61%ivwF$*lz9~UHA?VZMKPV8OvwcuEBm}Ev-*Kd-ocnIjhwkZtL5<u-(ubDzw?8*PGoiUmB)f}'
    'a6F+%0d42fpSW{cV@XL2yn!iiJ*Aa?&<f1gc7|Fj{O3<{k-`o(7Skyy3$ru+W?Se5$$L>$osY3bR1Ld9'
    '-cIjUJTxsGnimc`mJRhqgJj9Dd%>{k5G1upuoKpc84XHZZMLS-OA-~#(UN^CZiIIv85L#OwA6cPOBfk?'
    'iX%#&bP}T}Z$D0;2|>{W;u-Q&gt0z0`F?vlAt+g$W=f4_<O_~#`LfeyG$iiV+n|2woVqXP;nWZ6wAHwK'
    '*@s)L;&pM!@=x9#)U~qi#>l#jjU~+slT@bmTAdM>RUnmMV_vI4nwR~`kAZ(y(V{HVT*We@ZQmWIz3v$w'
    '#8()Q$1p@&TCMn7^V|MC>SG~L@kvHGUB)b;WhM(FB_&^FMrZMb#q4wNFybS2Szs9Zjix|ZQT^*09e`Pd'
    'Ykn^ySr-3!w<TqpIM;YW!Hl1jLbH<GKRMb!f?V3ESXv>KO7Y3chL_u)9k%L9xZ<qC;Al3Z1lw=q>`(TV'
    'OdwDEh%Cc#lXqo;ddxCa+o9L^PMmj@^BPT1TB{uZ-roGgV>9Lpa(C=q%Hik+Hg%;ptbEyz9qmUZT5}U^'
    '``|B+m7ix=i^=?g#x)p>4<K_(3t^ins(%`_Ihd}p+YRMyFUlWEc7uwex8=Dz*Y}AYcW0%y>d#uLjlMe*'
    'z0e~p3dk(F4Dr5u#!jqn9-hgURcvjLbvj%XDCJg;g%pVSpdPlMVfYbgljCGQNgn0)!Ah|o<8)`r(oBLy'
    'tu)~-)nuscpWOOE?3?@wuR(=)?}}&f@y1SMg1CnF7PHyJ2Rg#dS0ZOlX`m`6Nl)c1;lePO=BO~|j?821'
    '?uGIVrU0@p47R?B)mruyQ)_vw9RF@XVmy`WD&LXl5`UAH)PphR7xr%fftk>*J#^%RGx}?KmDFx}RC`1^'
    '3!Tfc^7<r*2WI`@{OEDoExKM6HJ&Y#IsL2z*^T*9GSm%QhX}i|#!ZDloCIyg$peNi(??sDJOegHS|=As'
    'Ed1zW{$8|bqaO({#Oqg29}E?|sfvj;bZhB6CG&S^U%GTQ39s;27B<Jl7TMtfez&iHt<~D=N$4JMmh8hL'
    'mA$EE>#Plh@j?Lvd#Coed8Wt_RPNn7G}$mc%#V(EhsNKhW$r#@I2T2_fANdrLheGbtqlUE33D}NfEf7|'
    '^PI-AG(#p?YWMvuj2CiMR;A$Xfg^y_wPuEoqyfo#fii0o)qxbRAP?ic4}RE$${e>HVGscaUrJ4oKqEMA'
    'EXbIX^P}C{l=#ndfeXX(0cjKRf-|*7pKsk!zEwqV5}4Qz-jj)s*K#CraL(b}B&b^(CgVqJGbrFnuxMD%'
    'MJeN5OQf?Zuas4fRWhGaB5ie*otUT9k}kQe2wGa~Z??hP--&Exw7CP~l)CrH*~_P#*v81mfwUwrE}*5('
    'I)7;NNro5jauHqP=xF%oJa*+0Y}|-fJbCZa4+qG@U|K0YxZYbrWr<xB6HU{AFL(f8I0n4!_cz3OSKkvT'
    '>EMG#^k%&+Wjk3;n_MXpq=n*9vN3hZ?RROI2H_#jDh^Xepa{E;e5nv-i3oe7=KT_cE-iAImy(~CSSx2w'
    '?uM?G(<f`TbS`yt=Dov9oP1aUy7h`yr7)LQTKroaVr>bNlb58X)VW^boDqdJ-xjVF`*G(YFFA5NFZmor'
    'yQqf2RYBuT3qeMhnfMdG$&`S6NR@42LEy;}ba?<b%DXK=-ZwG1Hm6}%R4BpK^n{xFYBM#Z{NWGVuI#H4'
    'L4PXvxp#I3mJh)cx41C9Px2%yJ629yWcJ6J(9(gNYXo;~wKf!xt<1`-l`vj$dm6mc4`-KTPUYn3He95k'
    '*$NY%O$msNE_xeUN9O(1qU?Si#=e6|cizMgwr^w5N)K~h@R5!`lId(hC0=k9_0)JS!l%+QPNHZ*+k%AH'
    'k8X{n#B(4WBzI|-4A`-nDAdKz#xW^G_O;^`cT*(a_TH>I!LYOS1~f2dd_5yJoh;{zMdUqoc}Wgg6$!Q-'
    'WZw?McPe&?t*ExxNRQaH2otpW`!JyFxE4{QPALgshrtT?NBI8Mdt5FxjZl&$$C%7-bW}T>NWAD%$&a5T'
    'mx#cwV!vTGNO!sxu~ldWW?RL7Q1>XVyG$Gxm>bCsxE=p$Y$YhePQyh^&)!k+qgkB*zK|r9uG1i3fibjB'
    'qUOO$M&Wh6%RWsSm3LE7Xa~iRL<Su?L%*h1a?bG+4}y;=J@cZeOo?QC5a-}PgZVdBST@}~NxzsU=oEMb'
    'nW(a4I)M+hkXctR0MyMRA^o)@aW&3jJ_p<DREVgh>SB+?Jy}7a+pg#EFu|MhC^1^c?DRwWQjYV?TAF=f'
    '8e4+pjzdF}FSJHoIrr_Oqe4zz{}d{qHSZMf#3z>S60i4&4-0&>{e7&P{c1V>@h0x^VNuLUzBnb*TfQr2'
    'xz$XWng(5E8J_a)9p&17@~2wG#+r4LoAZ))?IhockKBNZe50d!#yAn(<WoAEkSpOPOR!zLiX^x9Zk+8M'
    '6_mP`U3j%n;4DIyn==J=w38BAjDEMkK}q1M1oZd^bunYr?ei`^FSYX7)Cc8gs#o|*ZW-LQl_6iE+u&T?'
    'QD8S~6e4_yPxk|5o0bOUa^ZX4eotEI;NLCqtUnC!`WEcN1O#BSC4>vhXsm|t?h5jXeuzz!<W-6dzSs=X'
    'E?u8%oiuTgcPDkymZG;?w?A)5F1Z$6QX04Y=p|48z{ttZ)7j$GOUI;J&wHt#c%e=pLaRDp01~|3eR(-a'
    'q;a3i%O$BqyDBfYq6mcQ`SU2|O+e!aBXrxsOk=ys^>WF&ds})=VnOg`?bcnGtvjyYD#K`%S(^Rcn5=6o'
    ')<Te7a*(d!iuQ8M)?HbxJ1|=BzFcx`lXce?>s=PmtZkI6F;{<0SDC4@>tE(d3+4ceT7t_HkOlabX71KE'
    'FiWQ-$}O$lt>c9fjODwsmG60xw+#&CgW@Ukw!2uj=^4I|hS4<06?TzPheldSIGo>mGFi}u{eiqYAZ6nG'
    'R$zwOER{g^jk*HqF<h1W8A;@ptVLd_y3Y{N%MM`~yYkR<hgWGz4Q_L1?csD5V$+Sajc)s{W>L?zt=`Zv'
    'G~F9`BYV)-3|lvJz1P!Rd(d+SL#sz!)24m5*P}YMwZ5tAecSB!ZsF!GHN4dfeK>T8XE=^)4qZZfrZ=#x'
    '{?Hh@2DJ>sp{6%9dLwT%GWx_Dx+BYQN4hzrmSuSMZD3b6zOB_yS@;auMWj+fZSB^#1tQ5Tn2J0!IUwX-'
    '=&96S5yOtCJ(I&%JD!6HHCF1v66eiqw5~Fn5U_NTfTKDK{YagXS^LKy@%JF^bmXn>9|<Gywt=7J08nkB'
    '+yPBCPm(D`ipmgY^a3+`B9`u2vyW`^RDUa?FA{A{z|GTq70F+3L-VUn>uYz5Tp2=mOoI0$0z(5^@zIZQ'
    'SBd=J(;8*b*9Tl!r8N@c*1v=w?M^db0EbH34_x{YL>}8?^tWp(Hb$eIDpeXRrgRQ|SiOUa8^cqqZC)7p'
    '>{j@p^7z}AxSsaM`kH|uM*XP#1>17<gYU+dT?M$Fe{hw2a7q1(%ed3r5`9l$dxhq&2Be4tqE5s2v>k^s'
    'mdTOV$--p}0CC-Ce!yYmzSGPyuj?zpCgj2H#KCT)!Rmf(TvtA3MR5<6Df!seYAcq4JmB?qA1Hcri(q`2'
    'ETLosphl~^o=?iu588QDbrVeeT<dg{Un)9K-lIqI@zw~+not78xzFa*^FOw;ed$P63tMP~M5@;Wyd$M>'
    'Cpux*DnU*r=Q<nlTAY(c3;U817jJ!Z09!%Gii^8X{0l#pWot>$kP@}wZdNX5;S&7V+5=#R37)zwnoMA2'
    'N_0}GE4(t5cc8$slvr3v3BtPUHVGYeDAZK~8h;4q@37Crhq)h9j5iW~>Y~<OT6Ha)s*LppeEu7%0e&XY'
    'g|Cl;_x?O&H-^wZjvN}$mp}!yQ@o#@zTXJg!g1Uwbr%l(KIFnUnMF;g{9<l4u$*NqU)G*8n#%_|I2E#Q'
    'N|H+zU?o*bzj<{mBLuHDvtJ%b0km`-osBIy0wtjhK;^i?ZyHx_xcZoXDjDK}1p(ij1o7K@qUiG5SZYDA'
    'gcDI0zAi@>uhFl#QzU6=%?C(DW(Ck_Sf@V1Iud0E=C}>2c%$v%Wm^GR9#?F36V;IIErFeLH2HvLP7uzg'
    '0R8ur**Z>$m!W|!IY}JUrMo$OPhs@nLLmzG2SqEcIgK1Lp^@Ups??R;T&bpZWMk=sA*C5!g8C8rcU&KL'
    'jQ&c{<T{li)hStke3u*mh;_`+AVL(W_$QJ?GXa2n?sHC@s?j@twqHN0RY>^+nec(kU6lszev<)>=qhk7'
    '!2|?0Z8sNH;OQ1(yLfwwsGWv7YXTLLGbslxD}&?4Ma{F_Z~MVG3*Dv@stK5{=O8inB%U-b1w~YEPNuXy'
    '^@HzNfT{M}O|!E;yKjks<WpZ`(R%h~y&;7xc?K>zsz{gjHT*TbYA*@3M02`I?FjG^=E(*4?)#uomiGkv'
    'QSNsni!~hji#)rZ@=R##*mvI1oR!K5feE;}>speJVu8(30~gbY^b{U#JM|T7Lgkq1rk-HJxf2rb<CUm6'
    '3cUWa)B{}R$X5i?M=V_YVCl2j_KS~d%YitI$z<Hr!Dd~zzp$yieo%IqD8H!*KK47G!9sq(t>g<?+D;Gs'
    '+4>xz&gk3$9>7yf$H!X@ZR9!!!=cY;a1md&wNB@AK-M}|&URh;I@s=PU^vy@C*e#!S~iZvM`$=n2b(wd'
    'mH?+8?$?h3EDg>&o$udQ(%V51m8$8>(;f0gQp4bgwacsM@>ei`<-&ZDbm=RA6_=A5gqyp~mspJ1UA~=w'
    '&7a4uf_>*_)YVg;7mo3=$=7!48p3<-#wb7AQhispi@@EtrCV&=PiWHJ%BMy#4?#w1RI&!)b2Oa_m1YS2'
    '3KN7HQ5CGB2VUGGABZ2<#m_6CC^ec;I%@|c2)Uk!YOBxEq1sFI`h0LK=im-J&)_tb$CMNsX)G*o-Au$j'
    'lSX(IJTFBKlC|6$Nm`T_Uok@RqsJt0=ww3OZlVS22gy?X!XkdWrEIsM;6XWTm5GnfGk%q<$9<0*!;%Oc'
    'o<u7nXtji$((>-9v5BvT50&Sk5>DI)s8khaLP@ZgVT)e&`&=Q)1k}X5{&6DHoa%kFlnV~)@r1HeC+E_i'
    'xUh+1g>5VG19{uHGY^{;XWsAJ!^{&_Afad=%Ci#$w=ZU_1!BGtY?pTlrsI4I=SBo`L5-D6Y-tNk4$zk@'
    ')Y=02s~a`IQiNWTh~P(<lE_U?Ua+{d{y3b|(yjIHF*SY7eRW;;++N@5X(rWr*1*v$Yh;*oXlbTCv@OfE'
    'N1o+4q~}<@p*7S!ZA5#nNle`{M?=%xEERj{s`{Ys^{J;*&C~RO?(~ON-y6`;z_3OdH3smHH*%?=Yc8=I'
    '+v?jEu?(l@xTI$f$za2)>eaW@lTUejV7!X~J9;#qldE=`?c*lbGjjJ#I-NTCJ}urRn_VZZg6Gb|*;B0O'
    'Q3P3sJn9qJR>}6udG<TS^zIQ|8_%_@{W@v=ETjKOu`vP((iwB@CyMJwEblmSE<q<u=z#+6Ym$~m+z2Eq'
    'i_And_6XDLLG?#qz0J`asAG1uW(#}bJ4*SQe&*7SmE+$nNL;TSRcat4&`1nFSUT{s!#q}Avo=ynjZk_^'
    'H?(t2WB<#a^pt$`r;F)RJSs&#F-%D?WTqA8$7LzH`TK>ebU~;7hT@Cm4B$~^cE2+Zsv`picfdIm3_A&z'
    'lH&^CzIl5f!@n%7$xF5uFK05)UF8hrV`2L{vcN?#ona84t?^+3{g(;{t^7yneDGf0Blv$@hdrcBn_oqU'
    '7L!<zE87VX*@WLU89+XOuSUg?e<{!-g>G38P0W-J`yc^x$amwBcwfX5U^8lHRv1v$tU1nAJc|k3wj+(p'
    'q_9rPlYEvxUE6@A5<Fmc{lsk~vWPFkIo`QbUinixkCX{`lXwDv3G!#?X}mtEL1QlKJCE7$SbdUR{Zs2('
    'I7tS#O($V+5dlvqBv9x_@P);7kB5;H&S*DF@!uY#C`reQ_mRL&UHOUcQLMJtoVCNRS;@0;7!1)aRH6-4'
    'G8gy`oIDvTFYMn^C(a^9k^v=+2FB%1?Be}LlHuVMOL9S32Tz{kAsYe^w&!19;Dh&Zl)f|aZ;YmJa(8a?'
    'HeUWd?Djw^Z_;*GFQ_9=At&Sv`lC$GVsYT#CZt%)Ln!snkhOq}Y+-iE;Ez-$A=T_dc?L{E!=er=Ye4xp'
    'efNL|5NZ}2&Ls1_Ff*>@%IL>QI<RCZ?SbK%gv4`wm|xVqSh#Zh3mV|DKMP6Y4cq&IX3R%WSPZ>@V#UFz'
    'I?Fj@^%1X_kl7w$mNzGB;sUwgIfJjvY9{eTi1Pr2C(JbkjQJkP-8>oI6q<7weaB9f5i>a#0S`yHino|d'
    'k`M<kM}eoO&SZh2zs9BnVemj$zYdv9z~)t(!dGQ=#@fJ^FH<xAl{zp#RgzFNprQwQF5RMm@iUPl<5vGt'
    '$O;S#S-i~HSL7s*l_%jsnwZbUrc!Rr#i&GBN|WPVi_!S}+a;365@CgTbd-lRcvk=^j(A^`3foT>pRNd6'
    '1KQP!nCJF@OIVe)i0J|)E(ln5VqQGbeo;KqMhB%^%Y4h9SmS7ttajhyCMKJ<@|7r@p#0$v{B0rI;C=C%'
    'G*_WQ_8cg)f@-dF6jtV~x|eU48Wga?ZczgTsQJBNwYmVcq){u1`Ep1yF$8;wW#IrtzxQXn+FzYpRlM+O'
    'lsm<QNsIiSh?S!A=NOE`pQ?r=%YM`4NN#+UO}b=(kCKBEF~h8;WsTL2<;35mEIub8gn&3Gh=)Wv)IPf|'
    '89b6oP347M0m3hSp;Q!~NCTnm&i!$AnTp9(oXK*0Uho{B2fs=@;YTtJqa<ZY?EYZ_x4X(@+8%IfY}L&%'
    'Dw|sZFNtbSSCIF(w+EJu(z#c}lB9>7XT`N1FC~a&#IrqMv_|BR9FqZ+WtAA^)vf|22gzT%e&hgeU>xL>'
    'osv}>gvrf&rT&HW*1DZ*hV4s55mLCxj&z0S{Hjh=G8MW-Z%dj0Xu!d((j%WT!!-?K9h4&)HP9p)ipj=K'
    'I%%;B%Ttz=1Ry59n!WFf;4Ct5b|rxyi?f&%2G$zo=sV%!!v?rmS}ISHq?gO(Nhma}v@R)^F~eN~^jC*U'
    'RiH*IUyQk<G>7DuWzH1~kR<QYJvb~Ge)rQ{E@@(3<7=HEv^~@>Y+JFAj3(}$B1FKuND?`s{nU`9aZqU$'
    '+_R8Y?F21x0Rs%-a4~mi^iY)cK<ilj=tL~{BdWfFG4%R<!|juv*E7j*;OHaLvoy!lb)pRigOTgmrfF(K'
    '?|VJFr}Zqy9rXJBQQtN_Z#3#}nxMaQ31g(`Ht7?~AhuzdLr1rCbJ%k|&$7&(Gw6|?1~Vh}2t=Nt+lJHY'
    'StCMCUGoew91S-Hy!IMK?K?0nx#P$frT!S#-P%L!zo&E7Z+NWi>#DZDRo{fF7DDw_*OEGngh6VenvJod'
    '3fQ>jok6k4eb9fRxDre7!yTQHU_mDPT`A*FgtS5kk*rzcyaRcI!EjuRz7G6Y=CEvFfmJ|r5aE4dR}N;y'
    '_$(C^$LG|+?!LJE=F7e;FtWH((z^G5fBE1$B9of_EC}F_|MI{8(|`Hz|M=Jc`~Um5|J@(|&A<4&zy7!X'
    ';cx!--qFCHvt;JgV!ue{FN|3wnK^ZQk;y-$t^fP~<Ujw@fBo;cWd0(GcWESJ$@DLh_zOE0*zxQ#{E+Lk'
    '^2JF0$x*=H{q_Ix$A9|o{`kNBvp@Y;|K}GAdFNs|EqnY$G=E{tqG-<I7Ri0!lvuuq=$}*^qZq;9#`E9('
    '?Z5ov-~7*CWc4m(wJ75LMO1%b(295lp7h4pk@-u+`KL+<fBHB7;~)Rk|H1|IpZ?Xq{?otyAHGDN?@nH4'
    'y)V8<>@SR3l-PN*I-!#<!ulr``N*tkjDP&o|Kf{u-l25n&4a#3<}X}X;L68IFgj;NtBN=={BTJF<tkj%'
    'sV?1eF2gXQ>KAGMQwyT}>0kW&|L{Nk4G(qajq?BR|Ndux{OAAn@BiC>{-^)u|N8rX@}K_cKl@*~Quu%V'
    '$$$JsBdpK}b%&@=?G-7P*Ke<{_g)^I9zTC|e)i(^>Eq+`(-*%vQx26+t)toO;kT2}#)|}G?p$Ic&UMAw'
    '9ZT~l?O9Ya$iOzKLFu4xYPx2QdWNlAefU&&HIGnN(|fw9d(^Rqj_uHaV>#5>ApdhINmwJqbNgm*WSVY|'
    'xFdb!60_$J)1<m)5yx=>7O{wFIL2VuHw@ysj??!Hm)P!*Y?7V4IzRYpUe7RJt;O>vF}s1CN8Dd6==`ci'
    'mi;PV4*YTv&V4L8@aBmhIU#KD)noqd6)zRr6ws@u#GkPHKJ_ZztOAo1z0Kp1U*wD)NeAXf5q6iYTLW>`'
    '@RN|0_iGGS{QftivhgzE$zM-IC)5G8^J_nFivaPR2H;(WAEKv>v!ce3c*)Bx0w-}YXo!6T804PCoHn+a'
    '3;g9!;k)uZnK4TEmejiJbCX2)c84%$b2=k)>YicIM_!AsCf()B{E1CEgMSJuV%KIwUCug-sy9<yza6?j'
    's!=$l3aaHA24-p~ojLPxGLbbJzJ7pxbKbSV3%m%X>~5SoNh+O2GvdH6V?`f!WWmFi@0D3>>&7}Q-fTNc'
    'c3%|(zYfTI7#lB7?RRd`Gk5EGTuVhyTEg^&=S}>89)Be0KT5<?$Or!Hkn<g*SDDm^FT~DMpHAF7ide0v'
    '%WwiavENl{-BWM<oEx3$J9_m2O9iVq+(|H7#7B!5B-YH2(?CpHWvx;=a+ioNHCotHKjv-fRld@W8U|<V'
    'ZJ;h}?O21zc%M=}F5Y5RuH~;`+woR+l*@Kp?9RSq)PJ*xW8UYpXe42$YCzHiw_{ub?R-CT>)^x|0o6uV'
    'QB0>NQ*uGKC*FOO6lzb!s{OymLSYltr4Gob2;_%y>jqE73xPXw(C)%N+l_m++B?IFZqyYX+16FBTSfP-'
    'FsS_f@S`7!E!E`%kl{x*>_+a`tJ{TBw;P{sH!j^Bcv&|&S)#)Rb}6V=nR&;KR!hn}lU63l>ZKI1FVxPF'
    '-(aNJ_A2v{rHqF?c5s47kv02z6vma+ETmqzy`sQ3S>gZ*8?WZNiBxTU(u<>;?BAB~guBQ42i2Z6f0Za8'
    '^(c?>?{^CuT5tCGejA;8Ll<bKq@6961J&ZA&y`k`(tfVoXGuhr-{Wyrqm{1mJ09ZZHvC=Efz%M3)Ck;;'
    '18@z--|k8Ht#vIEH?o6ocNu$=h?%;Px4Q_uwY~wj2so&HL1T=t6r*s;HTG!TesFm9*CL+RXh83d;&~Fo'
    'd6J`fy9wsqK`gJ~P~HZSyzAS9@~Vrm@mCHPVo_5%$39E3>WVO%8v8LQh^>1Wv<fKMN6kaMIV@|xBRle}'
    'vbMwRsULht{fo;QCjq9}SxvpmD1y)CS26?Apy0l$Fx+69QqTSbLuBoD*m82~ka0%AK^SLX<n9bBxCskN'
    'qHf!V&|iu>sA$;b*-wm&s+to3`S=^(jW4&y4EPBix(ZjFO@vqqzY(-yKU3W66`RjK>(n`P<mzWxk2JL!'
    '?(eZ0tUNx=f6B)m$p6K~1&vtZw5-vu)fsV_xgvqzCCmw1Yd<IN{R?Kryh34}r%f)sJN1r#cB?WP(HM;?'
    'j2-KXJ5d*nXp0qmD|M44sGgl^p4}^+l_+ag?KGiv)-5Fp$PAo;c>4p^(n+nFjM(;raWRD1kxan&N>pV6'
    'RTXb^(-UMoTa32%lCyDh!^!o^u2U=EtArtc@e4s@hpfK$_T(f*(J$*dDI-a+7+UgXw6VP)&B+9SlPm6o'
    'w*%x4Nru?{Fu!6DWNkkSw6mChClzht=(jD!x>dvAF>8X{4!v<HPKF@QyGjx@^8;kGt#ib(MEFN(AnvQf'
    'bo5U!{(Ca<Srbr6Ib^W7Cw>IP0<;JKF!5T=L)p5UKr4UZUmCKM3Q~6+H6Q;P?Tc>~J_c2bIUbpKlbo!K'
    '(pa1afbDoZoyAvdSV`W3G~RE?mCF+3Xo2yQz9{mzKF=3N2~*?~uXr$1#_)NzTT1OZkYzAA*j{S#lJZzT'
    '@ZK7>+!CZTZkBMexienAk(H$>@*T!lGlRsLz^@{MY5)G14)}T+&W{QBEduFX1*O4{KdRXJ4P`;5i{%Bj'
    '(xZ*iDOswU50rvywRO}!?~;`wJ_1tdv}50ygwDHNMD>Ak?v)8CNmuSJA|;!<BrE6L@YZV9%8rZ^QtwFN'
    'sykt-=6R|C(@cuWx_bw)33q@sbW6fP=L#z_vAq(mxE0RY>`M1B*gREq>Ue0WV4+A5<x6MsV1LIxEX}_N'
    'P6BzCY#29+lprq*;~<Qw#Dm`^FHT)7!0be0Th?*VUAtio80a#&tBSdn;<aze_e0)h{I?}odG16mOe+|8'
    '9)6I(x~=*oFY@&+ir1cy?889C^FkV3ij$cludd7Alcr;(XH4C^&U+9N;m43U@|H{~8)e~|GLK)@5m^)y'
    '5h<4gE3tSB7+kh{;av>w)=FK&L3pGe?A%I=Qzdg?b=C3b;33RNd@0QY-8MybiH~o|E3&pr4x7j~hjwla'
    '$u@?X7ow|7AvxYgLvacTUJM?9zfYsOIYln+aDOUXSxwGj|L}+H3n^&oJ26sW<ZCIugjh<-GMRNkCKGX8'
    'd;4@ac8DLuxyupdqz{TvrFj(ac;I_j!Tn-FBFrInY2?iRfA-$B%WWH36#YKGg7L|nmhSGB`F^x_#^cyd'
    ';**CxZ6~wNnPh2!0NAZ<wWx@a?H-T+`>6szilius52&5lYxkOoyCt#!R2AxlLe)&%Hn=qE*Am3w-_0-?'
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
    'fof0@vK&GW#UOyGq6vL8OigG@EWLPkX}pZFG3wUW?h7%$4|Q3;*{wc*+!ru9rR186!U*!Txi=`_n`Cy4'
    'DWyjf>5gD;Xm1?+`G4%aYi}G`mLT@Menn2sU`Wm|sdztBQ(a9_RF$Snk0DvrGnO=o`y{iK%*@V*RBE+='
    'fxmbSud)8Hwin*D0mFu21H0aZZFqozvGZSSckj$6{{^3OZ$xH9W@IuRH?m6IVt0vTGUD8O&pq#Z?m3xu'
    'Kv`{gXB(eN?LjuCSf_etN-ZFj*2yKAE_RwvHaf}O&RmhJJl<-{0ayy<%M-=ZC#yf!&==|cXC^s2TYj3D'
    '(aVhMY4uJ0&_-dwoDeumE3(%W1L%3DcK|XqQJz(9<FXFuT8xqw()U%<pY~9J)o44a<Y5jC9fm~^RRw9)'
    '*7Tj?mQ}s#%Ht%f0}B;wQq>kwkC{|k?C5IMjiD+#CGDY7$(BNWi1kpgPQpx|6^^ur!#i>@9H!>J?tq3B'
    'N!f6rj%G&VQ7_Ti;5ZFIQ=c?mM_~utCasecP1b{;%V1XSqqVJFSR+6y#;D#7E2|nnc2_20MYYMv+5OJL'
    '@uIrG$aq9cBF%V4i8EwXG<1{K^o$PINC#8NaswWLSCc%N|GYgRqcEpj`T{?HS(_>Eyspi;@|d>^<X6lv'
    'z{^?r3b4=e6<}2sZzo^E6+f%0;0ID`JvB<_50ZXfonQYtNqW<K1fM5A)hJ)SN&cUACOHxM`MT_=+3RQ7'
    '26nc+`?Xr%N$nokxz`IiVQY}JW)3L97NaorUkxU@lj|&L2|LTg=U|L9<w7+$9Zb=`!tW<mnH9iZs)y|w'
    'rKHzYRXXJ_)4)qI+f_?n@V~7V{pAepCZzj$j&M`DUD|dznO>_SWWqH$P=EZ#or2zDOWUJT?|{luLkWva'
    '|GZUA<!8F4a_=Xp+4yBG*`L;w9;fBfk^zqI)C$$gGiUTdGT&7AEeFgRnX8|VT1IYKzPi6^OL?|Yz<Pyj'
    'U1P2~9T)aMRQRsg?y~$Uf650l278Pa^o0sJ73-q3|I{u7lo-+&L2hf>m16BU;m1G7@Z%<F8gB~F#MCR2'
    'EALl|a_PrxQI?<A=egw=38sohu<CH}cB*cVVe@pmYRjNQtI8=k?(8PyXXQ)Lw@SQUY$e|6M-S;iS?25^'
    '-QD9<c~?F2TdgUD{*x~{MYg<k)M);j)R>G{mA95i_+m|S?Mqd!302+uvIHr99CWtAVT=7W@+iz~+xw=H'
    '`t$O__J{2_p%P4%cchZIaLHUE$^#k-B2~_e6*$s~eNIRigaLCSVF}B#r7NP?w^-~`hgj4JJvWYR64=}p'
    'cjpqh9t%S1N3lzNK`C*BV3FjKc|k;CY6mc=M`KS$LF@)RaCzwaZsf<l$74eHfgv<}96cwB%}m{H^M2<l'
    'X}hUn-#V<Cu`qK)yz5S)26vKq92}P9Lj_vp<f|Xx4;yWrO4Me{tYR>N#ST>H;wV4IKmOA%I(Ea-WP89@'
    'o9Hr$tzEY1jzipo!R=%`op+wm8RnSm_I-E3!RRw`ojw6hGjlu3doSw#4A$*U4_oyWgZ#N~=jukRUb$m5'
    'oyr3~A?EG;67NgjQ+HGJoomcC*F%6w14Ca=2?}gHNz<o2SW<@Q?BX5K?t`Bun87J;p3=#|hzvVyNM^Iu'
    'J=OHOJsz^*_4_-se#@L>3^+DYOKvJ0C)II|J32+bERp5Ujw@BnZ+Ku_c$&N7%W5x{Kf5h@8`BbS!bqdF'
    '0O(s)r+|hF@kX_fP1CVTz$tOkyROB`r;V37oK1vQdg!TsEeZebL(?2`vk#qS|4?$cO+>FCZvL(1(ojuL'
    'UmKpeZhbu~K#?a)vQzy7+bWpaI2OF4K#58us|kAjJQgKph1L)NXAYwDc{3;_4=Xp`E84{>@0UH|Y<3>G'
    'Ic+i0)nLlZ_oo>n<MH)qjAA4O_EwPB%f=^&!NWpH*klNGx(?Raebp!S&#<n_apx%-5kL8|9Lbe9cvX*c'
    'flp#<S{Ufd6Q*pzI|^jp0TK<Kb7f47)e14oIY~w9%)zvo4b&Ebrw-QB4EuYkqkKx(>sj`w|McF2d#5KQ'
    '2D=bgBNtzJEyQG|u0AUU>CDKj=;`SH(p39gCn--C6BPR@y;@yH#>B;)$#NSeaB|MMOCKH=b4&g>^r&<n'
    'pb@4IexX@*y`xSE5Chp+9+xUm>1k<xlKAJfPwE`2-hG&wr#bz58Wc|0wR9cM!u7rH<O--@4s=#_rb4sy'
    'mAN#|k_BQwmoE=e5_3Pb96nD^uGDJE0$JO-^}Q@UXEdWj6<eU2gC|ba&zIH$fhz-kExK2}&~Ea=`T-!i'
    'zlBVcd8Q#oP%wR?E_Wo}qu>K@>aYVWNFtC?=~S}2bKDt?!Rm+Yp1&PWUzhaz);Ayv@vQmr>h?p`+2JZ8'
    'yJ_E5J5nuskh(5U^S{?PXst}&N%ZD<X5fMY)@lU5!MJC+!zcaANz!V#%)x4D8a+*}AnB?cX^Q&oVwPS&'
    'N>by0rD!&dl_0w$w;=!}OQ)&|l``X$nLs(oxPFaDaQlATc^FuisLT)&+XwM%KY?FX=zc7p3c&?0IxAAk'
    '+O%#fZ1?I6Na^rKTTR9FV05S&-zU>+7dxuBLfdFb0&YJp#N^7jr_ftK!$x%bcx6(i^)B-VjfoN~v^aJp'
    'T^xKUX}u@i-<3^P%6-)`x^v33&478*SjTB7dUA+`LOQeI7_SrIxeSJt7q~hydpBY?)A4A$n03&KI4Kh{'
    'Tw2@9NoGzJlTdE8Wx|WN1%SgB%40^!bgZ3cjpA3}h?TUvxsYP2Ye>j1Pb9dkvzzC7%7@DdA62Y%UqB(N'
    '{Xb5|TBi|p1dsh*^7PS&Hq;8ol?rYwI|9s-mH^}}8KiU1RE<2WQfOo+TJ-j5J7vX3OXMHlQRs04kM*kW'
    'uT)&tuS+n2tTI|&<s-_!QRP-T1aFOZ1}ZeLP{ms0V%V$#TJf~jy~|-z1ykcK|7qFQDoMiwn0>M(${<M^'
    'l2(`?peG9e10JwOq3>USt@CDp5(95u==<j|VCs#$RfjiVQJqwr^!wjY@>}0$nJu_F$$wfFWrhL?Nf0GL'
    'O?gdU?uAO~Juj&HtL;ipxGPvS1)E-D6LV3eY{02p^lW8Y4bxI_g)yN$Hum@n)vZdtJNcfCxtL7Hzqp70'
    'fc!d{(C_ibJ5y_dC~}48yOyMkxFHK;${F!o$*5z+(vy<9!nPTglv3hKE-crUF0)x22pQUUr`AX&T|1Dz'
    'Ej&tnYR5E`4z&X=Ln7?J=5fHJ@P&vN4Wu0eQg}9vW5*VP`o42u78}JGHon6xCgWHJJhEu$Im8Jlm9dWn'
    'Xsp1J+zxy{VxDk`71*#4>3fzZg_N!zGg&6X#<7BIjt!u<X00CZDfBP*RFG-#D|9qq)iZU~cxI?tPat9v'
    '`JS*n=EQ`@7Kx}Qcoc=MFZ{r>x$O(de3y~P2J-P@&fFm2u8)PZEOJ-19!Vq5k1QU=Q9!r{bio1vTaJZ#'
    'Y#7g$Jd&OVR3Y6Uq(SU?ETXpM!3<a=Nu_E%it9FhOny+`J{;q}U2rv2$Ey3Cu6<&4t5w0NdJ&|`(-jgt'
    'k4rzQ8g^x_iJd4~g~eCNOYDMDood=rwE_@#`q;aBTm{T9A!gONpyC{G7Ng4Vz+0MUz8wwbHQrY5Co5K`'
    'TSLqmsI=+?jN(HCqxV78`Qf_CPq!kpiX>QVvfW?Z^u8uFw&zEP>fij!|L(W{{NMlPZ~wRd_wWDP-~5|@'
    '@ehCdZ~w#J{e8>W{?Rc!xh8|rCx-vQ8D8(hCsuC<$^ZDD{O7;@ul}88_}@1U#|s;u82pE$y~~^N+e}fX'
    'Pb$4dT>r!0{_nr}C;#p@|LZ^f?SJ`y{C?{5v~I>Hj{gBUer3F;HRhJv@`>|XGUoGUyjJ!9@b~}nH-Gm('
    '{oaWHeJk>l1o)widW;dP{x+Yy`Swx%+kf*v{N`W%&zkRl`>+1>Z~ygw|9kG)FRufC5(Gb>Ajld4>5hDo'
    '0j-(;E8UMyz(4sfe&3j0RVMqy@IM?0o~4d{M(3Y&k|5vP8!_s<8!tNSW;~vWlTU)6J#XN*|Ki{OhyU^K'
    'bSNNe2K;~j*FXKuKl``;_}~1q-~QMC=Rf|<fBM`1?0?bn;{W-Z|M;U67A2o7O$-GmpcSfoT#4Cyb`OhO'
    'BtPYv9zCCq`9cXA_17(}kC-H(<1oviL2O%8IF9E=(sv|@oG^+x592UkBw&(q$y_^jnTIFN%nDr2iPy08'
    '(fSge>l^~?s(y)iVNb^#q%D9X!(FS0r0r4H^Q0e9Mngxye?dgth`XL`1(wB_Ab!X^-<KAZuFoSoq@IN*'
    '?rt1gwN|m1V3maQkR29tI+>&kz<EEuCD-C?I-YEqwD6*UM4lJ>J`Ef$i5t4iwc;q27JTN}4wEAESroz#'
    'l!RgIQEG*uXA5o%%PWx$631~!13MxPk9^AtEeo4iInoi4D`Z3?n}$Nzlo3ve4VV)ljl4jFgvNnKsv@9b'
    'uEYVcZ0^LcKG+qQ7Xk9KrDc&Yf{hB@5H`s6?8xS!u(=zDmf#NOwv;yZ9CCsZ7-*XJP!R)~ih&SNJg>Mi'
    'ZK3uv@$T(-${z}>GsVO%lD4@FIj4>zL*l^nJ>h$jhh79EW4jIwVdG%J!XkkH@^Ji!S&_qp8*<=ho0}o&'
    'g7rKRQ>-98e~1-MugJA-EWB$ef-_>llt~l;g*j0ah`{q)?pn+VDe)rPj^IZ}y0|jevOMa0zKjI(!r0{{'
    '(w-P0L`0mx&WVV`JcxnXnY2NeahtlfYXe=;h<kz)KR|Yn3=kIL3mk+)J+!24<<4#ddp)~1hY$Pd#hpGH'
    'i~Xs%9su#{LMD@Ub&`b+;=qzNkA&;V*bae*-N+`)@i+%b?GS;zy<D5vfdGju8RML}Gyv&gg<jxDX>e^o'
    '$$gfPa(|h-+egxxi$3A1{c+(+4}@=%P`W$}eAp*KC2Y2ZP5(glflvcdux-coc*tRyo&bR^Tq2l7fHdGy'
    'Vv?NiUfXNUr+uC<YSD^3AXEoP*_Xn0Ksbdy$T17_j!peYaEpi-gihf4@K>NrkBJEAnYo~GK*@%CUeQEM'
    'liisWE+z`3C2ZzU38K%ABPU>?q@eU2pS!?GVH|^%5KxbUVhU*Ff{3&QSOg(w-0|98%=K_g$*`}RXJ(iz'
    'sisqxw<3?kpk+WnfqbxI>G=UCC_6yKgkV!R0<hvSmj^6%>;Mc32Nae?K`i?|5UjZc-X>BNNDjnme@?FZ'
    '6D3%Sc8d}x5Uv0lAqH6xT0{n}=Y)j0KC?j@aM(h}4F~~U?^_^IVKKmPk?j#iJW1{rs9p>**%5I_BH;tc'
    'Qr8W!L#D++(#S9ZTgtW~3wXfs!-xcq$3iRMUg!!(3Kq727|fd&Z~Lm8Q(tEy7vUx(IC06DFYH)EksEjv'
    'Xf#stCiY;{Tno_0@wpJ}AJ>aGtONGdC&G&4-MA64bZsY&eK4u~SjJ3*G7zY@913=&?}dONP<B2TSs<?^'
    'JkR|QEN2keb{s_Ja5K?uGW+BWnUiTTHb5Z7UgX3AL{bogd2A8ahsjygwIZLwC!WtN8HFIdA|J#+1mcT='
    'X~ZqMX+;zi^P?cw!1}g0_z|ve$$)bZalVIT@}%ox60b{TfCTHYAPR}^1{|}EZGl}U&0_<@GX3NlMJe6n'
    'z-&Noy3&&j^(parOl=0%cMyX#4`WAwD)nt1TV6mI7m;N<q2om%u!c+HwuRqnVVDfxPcA$bZnsaEh=U-E'
    'L4*e|Um68eh9N8_q>kkS(Z|#cfj2nlt=Q)di>2emmLGs6#>;FsC!pVKmpQ;<lt@5Q95L8)2F8iQz{7GG'
    '2pQYPVvV+EG1z7vM)0_2b6Bc5tY`xZLq7d!au!!l34n*|M<7IjFKi#%`+~aw4x|*ouOQdJ^yaYL#D%F^'
    '0=y{)?3akg#IZmS+J0>%kagQr2jTfrP4Dy#K=e8;gT0GDX~#4Sybx<>Mj($tB|G3fMzGIO2(AH>Q7kZj'
    '-ggLgTz2gsFiWuMI=)gmS{G(nFL$?NHKq2*1D{YZbah}2HtJ>xdlQ7d2=PBDQMQ1Y%pxEA`o>WNUJyuM'
    'A2c9ftMS^_ot}rNg?2_H9CYA)LOk$#Jn5tT;DJHmxbQoc3$@+Ig=aYB6dnv|9L78bKZOb5J8=n4^hIn*'
    '?goAc|Dr_+S`OGUay>BIEHur8>-s)e(Jl~xM`avaAo8)DwGSdJXo`|dkLF#7@I9Auu$zJiY<UX4yzfO8'
    'Oe6%BvP1x8G7msWIxh8P=)*tY;e@fpz`3D8=-BPhYRx#47fXv-7EIE&1o5a1IxG%(XvH=WKKSV%S}ohB'
    'cEknu<2YbGh+-gI*m)^=iI5EgJ?etErZLh4=wa~i06l>(2?GvhF&G?<2ObCZO{XBn!3q~XkdPgE4yB|i'
    'V%A#OH04_=1WXMqi5ScuhXKQKphXXZEi&fl+;I}bF*xcpW)f7A<AAayV5)eYEv&}N*;;?Iu|Sd`>@e5{'
    ';D*OejD?INCt_$T6DtIAhwnhZ5>y0O;b35azu-lZ5XU1Pzq5w%#=`iR&F-N~*GpZxUgD(omQLy|-ym2?'
    '{U8A6(+@2mAPa0@4yLLIunoNQVH0drd%hrGr*SE%1CPRVZSDx-#LP9reFc-x`lAK&jzGnRKph^KErJ2U'
    'Y#xvh%xCIE5uu!bnJQf_K~;NThtL>Q18@M?_b#B@;|AxgUC*9&J$tF^*;~4vo3k(HdPV`dA+aO@rNYG<'
    'Z#IyR1lO8}j7u;?L3H|d5W8S&1fgwtU|VAkb#PlaBem9&I#WI6W%j_!>}fCa-T+V1ZkI)O3$}#B1onb}'
    'Omc}0eqjJA7`z_a7eU}jurh21TxZa^pnTAv0xyhuB=DUuvZN^EO86N40Snb4KDBHw@LWKJ2)Px8VFYd#'
    '$UcyVK>$LScwQI-X9e(gaMi){0_|E0C1^(Wlo^?{yQ{mQKJ%=YgU>`jrh%}BRoI}!z$1<W*S3HvnP-PU'
    'p%mye1eY3gb0A>mV3m7rT-h?7kH<scDzu1;T_2Vh%|(tv3~rm{Iu-@#z+}k4<^bJ{esc(Br3-)afi9g0'
    'R8I^N1a=YBSpY7D1T!WkhU7xBge_skoj#l8gKJM?!8s`0h=L4^B4uHKVG%O|3KI-qJNASF?nvYbOM(+B'
    'eFD@84m$BoE?}-yjSjlO4#4E$5iyi~b<*0u(d|`>R$&9?rRRY20rpxD(TKXSWEQi5V<Hab9r)y6z1nEs'
    '1NJG{AHEMhXym#U2XnHeRa_6|LqT58`e}iuZ2@eQVi;EfRn4dk4v_<!5n6%d0muUnOeMzx{8JDFz60)}'
    '58?|}V>z5TV4PC-ZlMr^1ralbM^ea3w#@|*kwZZ`NDov2SXiDq_pk%78Nm}G76}Nr@FAF9qQE;F4~OHo'
    '<Iz?;Oc$fR?uyx0%vBgKbvQ7JU?JFHkwi0(!)V}*dA{ek7#x#!EMV%s^kK>t0Y6QWIF9_lcKz55O9;a-'
    '@Lk^{L^!bssO5Q#dp>2Lx_#z?(gqBmM-Rq_5AuchEc7TNUhKyNTyC%Ox-<JfQYAg^#sU>VNM#5n1X%SR'
    '0oecsDo_D9JZ{Kc>>S~Qp#V?Sae08+8+=p?T#*1a#t%xgiU9j0jx6Q_>Ek7E*9*X{0?>G%8F}z8V44MB'
    '5EJms1IGt*fM7gMU7QA6{ouo^&z_%NoIkzlUp?zzIQ?fA56>?;UjSydAq0_?2&MrzY5nDMpg1`^^ExA0'
    'e=!^HxU-xb^KYOxiDZ&DAgGh7gZ;q>QvuXLLpgYBlS?k&Cu~{{#4I_zc_YZMPo`K<Vpx45g;45X2!t0I'
    'V0GC(R&WF%$^jP4rTUb%LaH|{1G`lOq|RjYuCwuCf`t3a1p%?H%bh6^oh-D>ytGY@;CdQdPlM}a!1Xk^'
    'UPF2>qLA{a%P~&zzSaU}4wYFxm<uqZQR`!8ST)r;$U{36Y@u5+Nv(&v@J>LN-z?}otWPFERLt&a;ocjJ'
    'XD9D&hh^z^F|u6?&)dXcGG9)n40bRp=2D^e=P-xa1myE~zzb;`p0dOD7Xy^gI_`bfTdMI73_JyEh+mDt'
    '$GH$-(agm2)drsp2Ux?h+%#|zDZCUExC=yEMwQn?r(^`CSh}|>&C-Z!lpzgsLgCT~(3ah90&AkMCAe}?'
    '1|u<>)rRK8eZ^sQA>m%0DYicw^Xjz72K{RozJkz6CXE;vOq*d7n1Cndc>k@y(uA{eukScV(X$(oH-qa$'
    '@(sxKXgmYkufihlB<V7s3et_9gD8BUV1KPaKN@_G-ptqO0NF@heJrd^U+O_t%P1@9lz^Gtz<QGcn>f$0'
    'lt^Z?3c_Y%*%j!t@cjgBm)h8^0!dqzmkXM><L7S%T#U37pH*U=4eh%$U$Ilb^~%jGuN5|Yl*%*N<?L)p'
    'TtyclgBm;nDZ4%E?>!WAFbN-xr?<1xucx)Q9tv#n@a_qjlzMeXs*u_Yv^G$tVzaKk7-8<_-O9F9A+XQN'
    '@%-cbS({>@(fkomNNFC|ikhiDrRsLTfK;K>RL@@u9e67H3LfD;n<ORBXVr#VHoRHuPk85xDV`oIW=aiS'
    'sFw59249C!@9ku#&XrMK_w9N^KYe~y@5R-2)tq+S{Z1JMey;qEN+~}d&4KIB&=fBFKA!45n1b~$rj-O0'
    'zV{eh8ZD(Ny_z|B8@(a3>hGO@KN*4<Uv0vdH{(e{5~bf!{y|mjXb)pu(438d0|z5gmY#~CT#D(N0TbmR'
    'tZ@=Rx<$LCIsiajW(hR_T&{}vqmror;Q~-FxD|MD03keI#k0!p<D;n%nrN0zSq-r;qGN&xxUNJ)>FZaC'
    '`+o}hV>Z9M5n^5&#^vJr8rgn4x=_)h=VT;?<!uZw00A3fI!JA`s^*DGj5uBJ!T3~FdaedTIoj!xz8>F-'
    'I((ey;jh6NsZNWlt*k+gn^N8gkSaQU3y9j%Ay1oVR@H~GPMhT+Z4g(riEO<7=U|hM$glx~D>A(n73gb|'
    'v@1wCP^jsf<=;xUp#}vm->jyWvf`*R@1`$4A=B4lUR9DlRqhzrIMa9EkWpnpoN=u#2JA-day9R2<-wmm'
    'R%w3arFf22mdk$ve$jANnLr<p2J-<Ks$1d}i8DL<((Hw6e<tOC!Jy}Fu#<f)n<xjOjvW9TQtdVE@&VO='
    'Rb0bR&B}vRyk%QXH3C#e=_Qexs-|cb0aab)O4Ixb$YOqTCa}3<jTgUBtuvHrt|eCLVkl?h)>h^4_SaWe'
    '&&xX(snXTWGAc+jHSEUgwLFXsD3xu9O$aan@I@;{NI)Wq+2DFq4F%aZD+#l7%g#sFFw@)0A%-Nu`Pmf6'
    'byiCWjS}ONt46H)qHHBSfa6yehU-C{3IUEBt*7rlSyYsSIaa%!j6sQ92=q*=0MX6L9}s?BF@Bf5hfr6-'
    '{A@ISI}|Xq(xKG|b{WB_!ewg3Z%2YFa?@BFRKnMC*hi`jW;Ne4lgwW^K(z8Qzh2PFZ)c7-%5U)%veNwL'
    'WH=P_I<cuSS}0#F23*u1SDAIS-u$kr!<24K4ZW3nyN2q>ykA{uWY%2S@y!_W>9T9STyNFO0~!<nwcbQK'
    'p)$@g?<+&H(%OrTPgn4sCr9wwW3P6klC^DB5V}rCXdOmnD|^F#S7568@9XNVj&oe#qg6ac$P|i6C-U`p'
    'F`Ydch#{|xjSVnWPP;PN=3+dq9<WU2Fso;eCqe6~$}&sXy4O@aa$0XBUsLrd9FEXyuIB2lAUq-Sn^NzV'
    'sj{;>=Q};WUTy(6j(@Qj&&lQD_LfZFl{?fgILS+r_;E`KrVJQ?c8;9|(|cQ&<qrjlU?%4i39(%bZiV8v'
    'Sygyw+1`-(Loz4j6EkwJ|HT5dqdwOgj~<X|RS@Y7#^gRydFNtVA_9gzngV$|n=QoCWhPMrNGQ<2=VQ~s'
    '1R<4{id(>4Vyh)Fttui4pe4d4b754e=rI^Ml`)qd>po8kmJi;D2gAkmbgG)tSB18eWZz)&=%pA|XO+BQ'
    '##81Y8QlJSFu&nb^0r)*eJd;_Vd_K3%a*!3SqL*HVQNF$a2w4*s%WCz3G_Qq8@w6r5=r`;EN0^DW?WKr'
    '?*f$w<)05meEhaDu#7}*@@^AMuS@mH0M_Kdb225jVlJk$I*_u0y}mG57w+l#d|g1B;<GX&Wj5jI!b3#!'
    'sNQtcJ$H;8jL;z>yfT2iwEb={8|Z5t^#P$FfmT|r&AQ7dtO#U>4)`WpdH6(5$u)*nOJyPN8bxV`Hel!V'
    'MvEilv`7o%WF>BU;4`MN!9j|x)!O7)Y_~QAS0J0rgEWZLB0*>vd{#sn1iejowlPF1RvW|KQ46)$@vU$('
    ';m#2X&m>F?u;$4c0=e$pngClULkt4WOB2I@&%Xz{I9<%gSgPJI>@~03F!Ul%+~5$q{Am-z?Dnxuj8G(o'
    'O|jCt3^oOKn*cTrf5WJ4Fv8l^m1SknW$h4w7FdPL**k#eYmd?-wB9F-;kV&H3d~kEIR;aA!qL|5zg-1f'
    'Ob_r&6@)PfHAOztx~~=3dSkQIeoYNA(^hYPtb`jG_9Yn(DPgbM7-Xhx>%Jk<Np5c9y)C+!&tU)%o2CG}'
    'R)3BcBVZMLK$5F(eZt9PUg}nSevI`xiUodUZJ|&ETX~b_Ag1>!G^)(O-5%34K1R+vH3ogdEHwssGrnjV'
    'bS~c57<k5xHUTSVKsN@sHLz#`a$%s+B;Z`&(G=iKyR$LmB16y!(5wa67~nS3&m7<lo3AqHe6d0_Tzbkf'
    '>a8rJf{KN8K`Wcc5WKX$Wnv8(hN|qKW$8&Xz!T%7H$h2zFSUbuOFO6;)WqcJp~+KszRe3>W#QzmxmT*e'
    'u@y>HkHbV^sT?G<*CH_R`vULH)L)gcB4wMI7is0}@@Y~<P#)>D7M@;rsF$&@4()6RqALkI)P=RWZK(3E'
    'nk{qlnw?5wD4Wt-lqYhd4EGw>Iqv}0Br_um$3SX^#(4_uO^x*>H*iwB>q3A?e4t#bnvgD4*i7(cu5s-{'
    '@?7Ql+ECW{=h;Mu!|TE;Ce*rz!&!Q$b)vhzy!z+f2<^G5!j@z}Hv^?gs;fc+O%AP#$g?hx9A(x!X<jGI'
    '77iuXH?+keloDtG{+eQF;ZQZpH71T!*JNl@khzPj^?_~Nx=!<*6=1{Xp6fZ{ZH$o<FKwPqZtv9C6mqdS'
    '*2V}~6U`+2HSSCbPM92_SVfvV5M8&%T7qpLJh|<RF)wip0^hu#VFdVYS!D9?Z>vRPa*#r4XL5jIOUmdW'
    'X_0|t>@>5$?lK5BXNs9Q8@;=yq$$|RMHAj935B*f216}i67qN{{`)s5|C7Sf28Niy-u6cmrb=5*r;ACY'
    'P*vsrV~wD0@d}N@Uny~ur)ZmXo>~B{tOH|kjoJj8UClB|yA7D%POuN9DactB-5lm_&1~c}W~)jz0=-Zd'
    '8-ZM`gv}gK6=~n*2TJDD?gr3iI=6B&tr}2MrPoUpYdg@DN;Ly>rA&KDnbw7xjf6iQ&9KTjCNA6pBz<Y='
    'V*GYiGe&#`GXr=Jg&d3q70bWoz-8)e>8rC1Z`&0vv~D1EbCt~^e97ciIi}{LSOrtA7%STD1#a7PW4>Sk'
    'A+%w~5A-%<YV|iZC=1EXlxp9^yBP(aMR%>7h`iiN(Ary})r92Ib;j_(RKciR#=k&D6oagNr!QZgN+(&>'
    '6cjrvUe%8ICRPg*xXEY;EoN=TNsG!=8NS0&uze;*$Q51GWgCsgaCU94!5C3?qs`@sD;YXYFw_@_qGg7}'
    '%z&rA1U;DwDW+J<1Dh31g-*FcI&CVYjZ)4Ee2#34W$YD-6;mEemP9JUEHErncc@;el1%lTugI-xADbi-'
    'R!)n^Rq?zKzg!Gdz+^!i-`y^lT|FURG`kiKO!GTq-qI|>M{`qi=hm5$!#j!BprGGI(54M$UEBi8JcHpW'
    'nkwB=wsYDlS!K%A7R)<$+ms|N*af5ZvnlKsThj@mdkWD_4C)LvmT}V*)%C>eE{Kin-(rZy{MbV9rjKQl'
    '02!9IoQ|F?=HM6_I+W7A%F~09+Pt?58K%O6k28lhreK=E=o-*kHc%?PPG>W$ggO@-W5ctCwbc@(bUFuO'
    'rwet%rda{FRcu1lZk}PtW@aePmYJo2kX>ee%}lGc9cj<H%B;V=K~kKw;k0kTm|?eZ!+anax-obTor0e#'
    'TI#<^iK(f5vW6XF2bh~wWEymys|?vBncXvU<dFi_`_@bMtuF8tCvEgfNZO&b$E-@_O{QXQCct07vfI{V'
    '+B*WZ2&<gH#KmJSRJXh~MZzG5I8zb%{C1eUuxkuA1+WeAX&$A9orkljAoYER%}yBPjo_7UWfYVV8;>Vv'
    'WI~v_8gDiieFqi{cqf{#Ri_5S9KB=SZE!S$E$Fjk4{9cxZPpH0+t$YHwu1tjUbKa|_R{q?%M92;-#1vR'
    'U5A9*&@kCvG5ZNCX_8UPf^Vt}YF&zHY4U{xnb`+($#TmUg+|CwO|hqOYT`Wh?BWSlD7YY_>l%fw^L2wW'
    'py~#n((Vq~Q<8=XM9)gE&8+fR_CeAuJucae;EQ%Ht!y97uu{oyK%=wF-4bGY+ec2Wn-{&ozZv2)5oz9n'
    'ZBs$)B06s>AEviG#Aw5WxV2=Buckt^Ypii~c#{{Oj=@qHPp3Lq)pF9p+RWP^;t{L|bX~e2JnCNE)^2>d'
    'okLcmcy^vpaMr!mtPS}QD%tf3nM?rX)sqKvisV9YEa{<~5p3Gk<Rl|It!Bi#KC5;dk=%TZ9+7NrP#Y{U'
    'U1F&(_2wDK@^~U<Gh(`w*7|;$JfF<sx*@l&5ZcoSH6+-trevhcmtHcgE82`XP9@BYk*Rnn*kEQhe4c4}'
    'h+WgZA@2aYZ7PqA#eic_->lfCpVl|PNXA<cs@h<4lA;K2(J36EyN8Cqfy^<rh(5(t^xwiV`a`vj(xCGU'
    'w47=$ovH~ATGGh*n*qn<wz5rFx3J@?Uf^JMI{<MvY>;*J{AN5KH%ht6b_-qAS(`0}^H~#ZoSj%bfwML-'
    '9R+A1{J*ik?Wp@4LYk}loz&S{;q{ba4aYXKxM}MEb0x<_f~melMy_kL?BE-d_C*#o4eg7ScuX;1LOdqL'
    'M86rl0UxG%ji>d-nBS4<09&`zj8GMUdOVtmY5mlu>_)5j68dNJ_8O3+m~1tIb&g4C<^|mryqgnuYdA6_'
    'ht`nON-Kc^>NZ+venpzioTn0HyoZ4OJ_GcdFafdWcYln?2av0--v$a0D9otp;5z)MkkkAw!a4~KZq3FD'
    'H`u44*iS2w;;!{@*9?S#6p5jFdiDnEo7T9}wGQa{s+?)v1XSeW3xQYj!A=1^$IZ*P&2<|I+-%I;pxoJ*'
    'vZ?z@$t4`*1Eoz&z|D3{$AqmWfQw{8n*2Uh$nJBEZ4(^>03rPwjS(#$>*d#PLY^y>DDN1)VJdvX)cx(8'
    'S1Xq`$#}qvgD}D5u15p+I4#lNq#o)e=KKwl(gtaUbiK6Mjpdy!Z_YIaRkiQpN*rx~YQY@M>_s~salT)B'
    '?Mt!+o89txQxS<8_K0)1F;>QF6H^9dtI#y5tT;`SszA8OEMY7sWv~g3N(~<NuMr{rd4iGp24W$9n~VkI'
    'h@zITPHc_SH)KwxN(0oq^N=-Iuf+HBCRMPPK$aG7^^()6O}ScK)hO*Igg*x~k81Si%>mK1qH32Yz<viy'
    '{M2n2ycN%lOl`fsmSPAinrd2ow_w%AY<7);mefEV4{ZQm<F^*<Y@!fk+zLj$Qoje?TJDeDL}R!Ai#XP3'
    'd?2@T&68;}9#<`uk_SL;ziSW;NQ&%%eKlPS<|s(c$aMM+J=c1oYJGBT7>4U(7-XY7)z1NVQ?IX9nZ<%|'
    '|K)<>Nf7+>_!e6oH7e_~0TbhD&9W4>OtVeLV9Stg24ZK+vHAlwn5p1qek<ylnn-Y`L%O(qd`qsAbp6VP'
    ';)X(BhiEQ$Y8|psv8~`%hM1L(YI^ECP@PpYM`8w+Ssbna8)@lSXkVzz5rU)jCperwLue`=*QVb{RO<Tx'
    '<LTqkn}Nmv-sv1nnhDEIsC6S{1+6-^&A3guxpmMsB<DC83|o06qp3T`FkEBVxqD}t2+^cOaC+NV)UDaM'
    '3MD*TOiAPVAsf?bk}#CcsF7IPoKaKvF*h}1QgUOSErt@)*|#i;2YN}%0s+EAX}J{m2-eZ(={7W!@f*lD'
    '8KX<F-2#Rc5|*9Vb-Dg(cQi9X;9|gTv|Z9X=vEA`5hE9XGsb+Iuv=!0DGb=xM}vdqavBox<{}!|Di`YJ'
    'j52(_LT|HL(VC(w6zlNXG$A%eYv;m)>IkZ>&Fch9HCS(DV<zFDW}LSH&X8kZE?0FM=sh|I(_}Hm+=IH2'
    'z4as-#ly+PweOlH(qw@(qJm9m#;9Nebjwu0alAzOPLjo#NS(+op$QdW$Pnf)2iJ+^Q1eRNHgJvTU=y0T'
    'n)K_STc!hyo?_YK%vu_f!Nv-jkOA6`nb1>%H0mX!vsF5!x~0|_-gG=^3ZrhUV%=L*!0I0H=72Of<;}sl'
    '!g3As#$c+S7Z<v$t;9#y0Go81nny=f_nij|4x7;M&?vPk6Tm+oPhZa_gteMgv_6*U#K)x(n~KA?=}5*B'
    '6_<h*Hv;@r+=)KJt-ySp#?iHP3|+GE#8~2W5%C!Cr<9>^A?6@q>UM}9B&W&huCcZ`lP<8s`qyKMpqlXa'
    'GV5)j&2!PD&D|{7Sb@ndvISFb$=q4@R<-#%)ih|1$yI?cZB(nUlp+7B2vJR~D%CWh`gO7ll;=XVbZ7u<'
    '<8~~9F;{XsJ1e8wJ_FbwI~3!yt%&IahcMTaHHAIVi!d-o(XG!MeKfC?on8_{{?e?~ATxCnC)etVWP0O@'
    'k-4}=$xu60x9E=TSpqdpzBY)IrjXTrD~*Gm#z8N|L2rqJvbU_}<MB|VHAU`VJ{08j%#icCY*%@q`YITt'
    '0(A#wilAZV5q7mQ4)}Ucz1~Y+FN?D6Q(BRtnwz*DfN)&m@70ITE}Z_^v!_=Vr)O9F%dbxzKj?hXIq+;N'
    'a+zn_k&LJx*)$HU$dfGeEGHnY=L<WqX=De!A9z+soG6xoFCFel!oq+ae0Fwvb^g_}i@)k$o}E5@dVbM='
    '@K;yomjL_lpxf;}lX5s1iB4`uJJ$;`<+IN_^Bd8b3Nq}-#c<e5E){iVjEqKN+L<m!v(8}DIeUBpkY0`s'
    'KI<IF>G-xYA@iHzfOd2yQ0F=Ps{fjNFcrC9(Gtsja6@MJe(tjch;Bq=W*AK{d1RlIkpk(&^nwOp9<H8A'
    '+fnuDI{>9e%l>=u?Aa9{57%_q@2k|({?Q3oP~+hnad>nxAycrWW-pvq`uQiPkDvCRoL_u(4%_?W$zy!E'
    '>xt0yVmk`BV|!lY`W|<w^jJVWLIc7jb9~8c+1-F~aensf;vsGyV(kPy^x5H|n$*1xKHJT5tsH!htwlj3'
    'B%Is3C4*59EVFCTBMUy5_Z*<3o^ACkUs=RmTnpj-x%hs5cy#olD+fxs%(|QFdGz?{!^cm*!pXds-S^WM'
    'FAuPF;b8s}==r|-9Vub;+jKD$tKX3B@V9P9j)9nvk~SCmL67?Q$@6CyR~ZZnH)d`S5*HXi+P;i^-wiFB'
    'QNsOzTimw7IAD>LVDRkOcjp(U0QULCv&-eok--pUl=0B_DEDj*|529{?l{DA1IM-*k76ObkOqEuUrC3F'
    'YHZv~Z)x1i+!gL2?t0f#uzEpc+`ksUCh#bk40^A{yZfP^PUo@hIvaE8ve*yZkb2DbqR1wp7dwoE4&|;b'
    'g9v_gEsxvW*7KPCa)A{TVC;Esh&~SND<6=efn7Tp_|fBU&ifA^e|3JDMP}ezj!PpCmK()Bl>u{Qz$3u|'
    'FS0zrsbnB%JYE3g`RUcy2trdGNCexBlFscaH(H+%r%a_uY!k|gst@%aQJ5aup?3^OSxk|mu#a0}Z+79+'
    'pNq2_G6$0m13+tqM!Lr<Af4{Y_<O8>EdQz?j&vg{qJl|Ektc)5W5Ax4BX~r(D?tkL*cJpR1r}>lk6R2#'
    'FN!T92<aYWz#TfC3lmp?|M6n>@vjG-jbP?U`{F(&b39vKOi;A;XEy{i7_O{@gSgBjAdKO+Og??l+ReZs'
    'fCyp77UcwFAhTe_9*PeV*^U6b@YoR`rwN0fBkovsz+%s1E_b;Xd%{~H<7ktfvyyQ&CdkN5{sUpS&QBjU'
    '`1k#E{Pu+fqA~*vW#;%TO3eaJ($9U!Dz39<-#&l#6sGo<SKnToZ=E8c!gu}1ihVm|g1S!VI3Q?a8Trii'
    's4smQ(SV2d(JMV0FDB#B#bSgQex#L+CcMohptxUOfHFN`1&6+W+==Ytj%`~<1#{Q`vLTtxI$tHKZ1cS1'
    'Ftrg*@Ygdk6G!(~<8dK7+Bj6<2*LY<>k-(ZKq>mFASkXr9WO@wa3+Q_`zn56Y;quGfUXxf>l1WsCx=J*'
    'Wh8pIdy?u~Jw#rqp3Ejg_%l-J;Zc5&%-2A6a^sK@?~KNC{oyeA6#h!4b3iy4Bi%pj9=*zg!*!eh&ct+n'
    '4$5M9I25D9WFbe#o!B`l@%&88m+zE%DS7yW0WRl<#hMoY*%jezs>}i)Lvc;mJKQ7{OIEw1e}e5vw-8XP'
    'KSO-twiVCuxKlKy+6etR4xE74#$2n1lLw2;r;Ue-L`j*g)vE`zc<Y;#!-Ib8{wC=m9cjq31w|fGd+_cH'
    '_3zRBVp`42<U(AF@AW&!ovG~p_4}ON_Tm1EzrOz`U%q_#;^oU%ul{sHM7*$j@v9dW{PQP&)ZM}vnop0F'
    'iveSRL3ym%?+d*?&0L4w``Z9yru%d}e>^$_sf@tTC<SOAQbBc`l1l|RFAuDj2c19Zcou*u1GGRop@H64'
    '26|t7&x9(%IqOrf!r^!HOSI9@SMs9|q|@hPtO?v#u1$X=-loML?hs?|f4pMsLkU_hV5B0#&%ApzU5KLB'
    'P6jg|_ner!V|;L5x=I-hBsh<_L)}+9otWdT_|aeQyMR)Ghrj9eYWoR8d~d{vjF>=EY6N4w5&1{pbLGRp'
    '@N~er0ODDs+2kq!q9?A4CBYbE*!@r-91>GvbMB?Y1k(B!XrpxTr|v7wlll|<sr#yg^w79f?`SSZI2-Qs'
    'Q587Id<dnxCTg|`heVR343JsTcG7>5S!Ji!v0s&(U=rjw(c5^a7($G&DiZkJCpY4IKDb8Q0#&OKGJKzI'
    '{i|)rSV-{vVIk<1!@D^@T>YN$#MSRhU%aHS(<4-tkzK2+#AD}AJ0PLq-*Rvkqalbi!TZVn+>-APr%Rmg'
    'U_2B*({u|vUwo0<Q5fDXFWWZ=af!R_xXsPGo=Pb(?09}7rac^WV>h>rm>KC28P3EZ8NEA9^k+sC2caKw'
    '2_BGZMFC-vMOoy<T>4RnaRNpNi5!bdP_~7Z*3ot~rvhi1!ux56NyX=GCn&TqzL)5`ywFooxkAl0C2xT='
    '?hffKqh;%ESHj}@A;op$`4{-?(FqrtFY_a&aPz@9m`8zp9W8FDm>vV>)j7&>2c!`ErWU28WrB?@4qYiR'
    'tc0!}X`8%FI0z=07h?LYmgHAvd0R+dd_Mui2#!0Lhnwz}Mpb@~a>JCIcDiXVlAU<<0(JsaL^^{laQ?9K'
    '0H{<2#Np)yhQu}1YK+duNvvGEmYqMpeD)Nc5JP^f%$;8>U}p&kt~tYo&z(19xDXuytoIg}SDcibe1^=r'
    '?@@kcZL5>1{-Jx^McLN<&;``LN5gu#xDVwRGGlmRs2_|=Z2&6kQtRefALS3QEQp<1e>~Op=<lxQ{C>AT'
    'xe*dg{`~I4aiKSN)NHs7QC$$%RVw!AgEkLK%mK$rX?lwfS|C&I@Y)lA1)lmH&Rp{1PInGxtdyUkplyEK'
    '9j14ul;2hYh+fQx`#KV?=B2{j4L~Jx$tw8TK+;(ZMp{oCp{zFq=}!^THjT5Xrqp`AQ2%awsn8r!Z<ID^'
    'Hbu(Ge0)0ui6XuqV6<?Db%JsZT(4Qi2k#GNi9v!sH$H$e2|r!Q$KuH04k|AWJZ&ZV0%fK_mp;L|6QZ7E'
    'x7tD1olp-~s|HbUxZ#e$h@szI_q$h$qp^Bu8uc*}?I{3;K9MpRrnBP?p_qo(QCP)8p>)*<JAW*@m2lYr'
    'BbMu=n^)qBjebAW_%7DljP2IoyRs*?mH2M^!LA8LbM5Y(0j@iu=Q!D=g#)(pivnc6DljjaDeK0HI-|-I'
    'p0$p?<uzf{)6QG<scY4J(J9ouwe)T^om)g7yKTh$2|@R-G1^ah^3{9X(fX$YX^y~J{BA>V=6&9rDfDWm'
    'jDA4aYXJfXYs61yH-kxssl#U_m2Sc3O%kW30^|3c$rPNrUoNl(J($A4b=e8-)&`glNny0kExL>eJhFgo'
    '7|k)*EO<3|=ig5TV3~9<NG9HlU&D`Nf?;JalGN-~gYW5Lg5LK+UHO@H)a0iE{YJ0=1~`u-bLs|O8KPmH'
    '#GMN!QlysDIdMNpN6Pw_stbxTt1^+BWk6^=8ov9z^(nhWr|aFUXSwCnakpc)<)t5)Z?|3LmQ7G71vOE-'
    'yK@;zLDDNMbI@So1k$KIny_Wo&b|vFSq|EL;3m@-v%CS+{qX$3w_n|DiKMS<l6!g3MS0Q-yDtxb?p*zL'
    'w^;NY+|1{b+5LO>wDbWLtyTi=AHlN7_jF+S;5c1B0PAiCc1vCh)jbc>o9=hstG{<XlzCn6(80GC-&_h+'
    '$!`6ncAQvD)5ZFH?`FD6DGF2NyiNwA(H377@8V%Es&$|1W<l?zf14$k>kY=UlXq$|TdCm}V+x?sH&c$s'
    'g|exbgRubXNBQx>ezp1|=%*g0^7K>^>*^V6w~n5OX;LXry`$svn2UQKbC|gXlTKx~(v)J(Zh9P))Xn`4'
    '*k!nmqq_#5!G`o0w$2=3Q6Csq;vSZHJKfw>o-R?r>7NRVd7<=VM1>m&CuW@4mc#r|1QDY?qtX%)w~Gfs'
    '!LN=PbhH^{|BJ)!SC6m0IY0f`W&gYLi_6E)o}x<-ojBf!o6GLo@|Ai2{ORd~Z}h3u`O~XQgrnD63(U9A'
    'zj=20uzz}S_4v{0*;NMGtKFJO%RX4<hx?tE2k+HVKY*OL1MA6oB$CKrv=BXz4`2n2r@8lv!sLtLaM@jB'
    'HWw4%t;I~J3=J~X{3Xd?i1m=b3EvNw;XDf248MAv5xEujJC`61R35)JT?Oxr7xNAUk;ZP4W3zV|b}SqL'
    'zcuF5*^L+u?{_Gf-N5q*ayN6##JtlJi*aW%m<YseskhKxKr5~Hrjs&N=O_2Lcyn(AI4A`Im(_XsvinDe'
    'O9*d}&Bvo7_!Q9b@<4NrBDXu?y*yZgfgd_O?6QlehrJ%i^114V^o0Yz4ae8L@nk;xqTB1`?p^e5J71rl'
    'J_OxYI9jq|G>W^p7bm|M4@Szt$(hBgJxq*Vv^DRvWp{Ft_Uh8{(Xs3G$Z+^;nEzl3LQ&s|fL}*refMDY'
    'Yw#O}zkYiy=D&XVQvZMUCv&hDx<{LNpD@3EABni%$20tHUnfcRyBW4xrhej|6n`9j_Wa_RI>o?iHRpeM'
    ')qni-`L|d4=8Lj#h70-?dNnG)2FqMzZXe~YP^aAv*6X1Z)YwGrQ~22K5*E6CbrNXRH4VT*egdQB%WvrG'
    'n>h0`a1Y0T%%t~`x;DO6TVwU`YMBK+V{)wmaPDX0@e~Ynl3#>+YGaC*H!8xgeCjV2un7bC?&N!<XS|_!'
    'FS(|8GNIq&kLt12-O==RHXVxmh0&s0o7si`OuPeu#~%vJ*=6hZ?|0p=ehAL&^om>;UiK`ktDSc4!NsD3'
    'o~dV2{CeRHFqnLwCA05y@UPii-%7e2W1bdIte51jT4_kHH6r>v!9>;fGj`M6uP*cKF(qQ!pOfqSUDIaw'
    '!K>EsFV$a*XpM}4hw7-_*`{k(z4U}+`l#)so&}u___e6~E|%C9>1E%7NvGE-v&`{)xu@IcGyB#`Jb)D7'
    '3pOwD-a0cCwR+sv=b)hUdxLBEn~en4h1AzqSI^77^z7|Ou{o9>-`<c+-xEbX>ZN?tOZc$2<U@UFwCK?+'
    '%VnQhc1l#-)dTM8Y3?d+l&D`yNK_xmC6vB?**Ce%t1Q1_)>vNAN~kM&VT;V#;GmuNze+unza*A_UYD6?'
    'eI0bogVQ%1!S7PVlv8$-Q!%?q4fVTU&^)%|aV<BKchU>@vv;HUjlhZFd!W=yLnuAXg15@eb?05}&BxO$'
    'yLCK+6?J+6{+%|SRu_}s*AgW6I|pItc#b7p!EDbDJ@9YsfD<RC%ooC;b`%QRq71Jh+QRl?;m2O+*;eSf'
    '@CS=D)zLTw*S5J8yCjIE<HWY*MKYFFWZRaIw&(baN0A49yd6e1q11_(<%Z0rzD1lMbgPIq7%p(_*l|5d'
    '!jO3`k%C2j6vPf?v6PnO;(fd@^r#;R;zzy}#3ZCHXR*aZ;Crl$2?@h^VQkqX@~C8yl*Exi%oz#nh)|D<'
    'K+urbzAZz>97}?X;vS=646CJ#(<t_8>J%86dY*3!mry7497p;=L|vQNwkI8CG09xZb$#Y|w(T=FkhUFC'
    'TL!TEu@l;UY*iOfFsSfiM-s-l;Fbu3!1hDO=CNhr9eLXc-G~w|wuEoFgwVhyq2Rt3lYlzJqY-JYgJBY}'
    'Lu{J>&3epbp65szQW*w3aES0k<hr)7c*uRcl+S&i$961Y;@PfcM;2$EL5mUh!4|+*wjeBUSU`f%ilYFA'
    'lC~6pX_o_%SV$rgIf4nFOU_~610t+QcrLR`YAYB?x(>H&%MpV5z#o(aaX@W1cB7d1A^?8%tiW+)=*M9k'
    'x>CY$UJwNsz=G*m)x|dq>idD~2;f}D^#doOzVC$*>?d%g536y5m;%B19)|%v;BUcP7jL=(O9VU=ep9uN'
    '7zP0q$1ng5Ezjq88&t$hgp^qVwv~e9lFV^k7SNc%7JF_axo7*_XK_rUu%=RgksW{-@hFrr^8%l9M+8hr'
    '%3M2iJ&=(gv}~6|0mu^)iy-!i6-%IVmjGg{z^-Rwz`!<l9g6@J1uigeOdQ9FY@hf6Y`jewN|zw?L6TTL'
    '7ce#ASg;!wiG3#yeK$6sNnsWdhqVa6uH})C2?t2Yp`bZpKOoWtYH+=XN>@g}W&|XVYe`{wlv<&H|0T1i'
    'W97rxmgfl=7epoJVF0L(0q1cjfu0$KZ2<nZC<nS=0>%r2$bvb=ut_A0B;lmAe~)8@R^Yq9J)s>_n{zj$'
    '5yKNL+h!ICm=r(&K_H~GT}iBfgRY2Z5V#%zVvJ;C$5D}*Be)|S4)WUOu);X@Kt+PyutCrQ8HRBTLfs=l'
    '#E788kC_E>B=oI_MSzd8kr5cm4g3H#f#igR4)H_DEFXXp$wC`+7v+rFp%d|t0Xi)^2BHtSB|+qRl2Xyc'
    'b3k?`AgN=Qa^exZ3~mJxY+n#KehiEDVTCld0tuYUK##J>gTI7v<XPMWMeeeyhB6YeMFUA=7{C_Nk3r=J'
    '0U;nsQE`F%q#%|-d4#~p#1*i|Kyt!ouw<}3fTK!=Vqhc^I{_Fl4v8bYyDq_sq7>-Gp^oJO#$g&17ASqf'
    'VoE`2J9vT``ye%dvt3d)f`mhH5dFaQ5;n~O)y6;(bLz1OHkZIKmSYo7I1ETNc7T&Zn1^f2NP;0ki0d>7'
    'S16OxwPDwym|K42Vh&_LXbAEL)EaP(FF-1=Ac}|sY6xU9*gM2?Ij9W^8k>@`fh$}oGQQ0~+JbsTaTfwn'
    '2w(^vflcH4G73S>gI1snltLI-V1u#1@+_d}So+poZVe6*L^gLEu;VCDh#P{%8G)4nq$f$>x)$(398xc|'
    'KoSWHtR7|)2?nbSL!hHXx7LrsplJo-oGDHV0x*09_h2`HR9uJp!1>a#T|9w;DFz^LK`ur<K5GMW_&f~5'
    'dQLfRWMCm+Az=%pCqoxASBY<Xu0%$KJ>)>8Qoshpzz$$KTY($eSfN2gLIe%NhA8{Mj*~#X#O2_gI3V%B'
    'Yyu?%<}B<-YzJU&pdg4WF!X?kE!UHbNa=YLekOheuN>tM*eDSYP8@-$;4toSCjtrsy7DX#yOD)cu^jG@'
    'P&yu{T0a0m<qNRcfi5Je77<1h3hd-K7A_C%K)5kTY=?rTbU}Rr<N!4rcstyUd>gjegT41W@Vl6c%H9@E'
    'RWDk3KR`a<UpY3qCLr8g_|?O`bX_kb95x*E8JO!KXc%B2U{<gtXn<M<tQ>c#O}2;Y(I5o}64(p`DEGmV'
    '<%&%?iCvVlMA!jn7ZAOkPc86w(3<h#zaRv;;JaX-)(df=*98`a1Ny@Q)#P%pz`z}_Y%sFH6SBZ03|vso'
    'Hv9>g7giR5mE?oNX#?vr2F_qr=N$!vFTq3gfb~L4g30MwK8QOP1er}3xIy3~Gaw;iv50f@LV$`L@S_18'
    '76USE6uE@)8Mwf)2Zk4Lo$I?+0C)wf5a0{cl;B>44hPu|_y+saW{iiFqK6a{Nr2$1#Lv(G1#OR;2Nn<*'
    'oWP(QyiA{ij}CqfSRfYgMo7VjA>hUm-vdLK3Zytdb|5WL|1<#AwG4z8MT`P$iwEFXf#YlwU=`*>7J(so'
    '%p8gqH!xBF7NQ-3Jm#M3lhATSt$2>IOu&HVp6|I9v170ZLWWpn+zDbENH-2aw@YwAd@F>Z(CxQDf)KC}'
    'fC>}K<nD7F9Eox;YXk^+8wdq_crON}4BA>o7Azf>=-VLT87c%j_VIC055fmeNZ2$8o17OQF$u6-(Le!>'
    '=L$<i)C1N9N#IHm2(&0cCQ8c!5fpj?B(e0swT68NEU<y8UoD!Yf)$}1ffZtd%%gxU&+$M~gdT8;h3w>j'
    'I0W|Pz+T|BgMRTmI|3!(1ik?Gnp8ffK&u|SG!Mws4bhXZ1sF@<8c`nzHH^S~4t;Q4{3x(V<YJ@=6bp#v'
    'Sa8s91WfR92a?DuAj)DFUa<o!;;24=<3V%_2h1$kEg4cDB$Xg8m??m6AMgM|7#s*2j0kBRe85A~tMjv~'
    '^N0QC5B{=$@$Ba+*axNvULDYPGL^t((zOHW+hAf*A5<8H^-(+EGDL9;1|T{sfHL5nK!T{10{r6`)Bwf|'
    'e62}9oQi1%s1fVxW-)p_186VOStI0^bN#<=XrF?k;-gVzfdcZtc|AW5{W!_JF0Sghd^<QjedL`5(Ybf_'
    '07T%qe-5<dd1vL`_D=l}j3g%t9|fo9k9_+K)ShdV96OBd^WecF%Q<`Ky3Pa3iQ`k(D?9Travz=ffU)2l'
    '1V|h{dg#Yz@k77d+tE49+Xf%|ffGM`@Gx{wqf_whUG;XpFs9zrrZ{he@<te6z3iNNkHT}XOCEt!7@v9J'
    'qjSJ_<d%B5#%?v*tde{6A-7qZ9HMI@U<QdUua#4o;2LRrr2F}uM3a=OxS9%~!2Q|vbiA1S<jyxg-1WeA'
    '%q}aL?VQ(OM%08rx;+9xeIcZn3aqbEVogIboBwPyemlZ9uij1c()3E%vQe~xw3{g!qq#Pg??UpyZqnb0'
    ';|3_Mf#KbNmI$ux4*qc1_Z~e8A6gImhyDZ0J9i(Qo}S0yL;tig_8%+;Lynj%u@<R!O1-*u`<t$;9`Ej#'
    'uI?0(nQ2_=BqoLD=Qm_lN{Uc?`cxe+JR!5!2+IL0%!}N>3roC@J2mSrYo*?y4(#~+EcPGaaT^$U?&*U^'
    'rx@ETX|jNeejb5O<v)1vC^!Q^zIPtRWeuKF+dc<Eb{;;6ABLfG{@`KsC<c$YgxOFR%MFoS0mm6DV;jGg'
    'QP(y0r_uJ5+?@}v)?I;BP4dRJe=ajq6+D0R&9i40sun4hkfz|=pznWp;Kr6i0*`{LO{5#T0k~&i-B9Y%'
    'fZD{tAW!7r*}7vhcuG193uy~!gX=^kKR7;8K7n?w4S~!f_Q19obA)3t;W`m#6hJUZ8TIgN9o#xQw!rR<'
    'SZH%kdMpGt(#9YKB^b}3!GW40#zIUkId!~SS##$=sCWp)@KfNz5{YZ!L8ogm2F`j6o>}Zk@Hb=0ZQF`G'
    '3zq7DAB?B8j^(?_qIDod&Czp0E5ysv%#o5<3}Fct1Tg`~0MPX$ae{!0&<a$PQaIe>KAsp^f$+dFKl<?5'
    'XPBsu9o5BjmRu~vf=sG}+Hq${s2CpIS8GYGI36bDgRp8-S|BX%m%cjg9DF-^jmiU4tS3V;7wP@W&R{fI'
    '%t2^jDINt}!PfUJRF$RA(u)}AmSXz#RH(UeRiG|$R$nD^!Y?&8mO+BQBr`d9wJfakc}J_G<pYU!T0OA@'
    'lrB(BCb>VQz^QfGu&O6`j54~uHx(0s7fU+|UwTcQ*@TQX7M5L{hO7D`FrgtIC$qy_07XbvudL9V4=Ny@'
    '&r<wO@EQ%)Z^qJDW4wQg3@rG@jP${Up3G<P^@p8vwTKA;Bu_C4KM~XUJ9utF22*(R9bk7nQq`K4yQvCY'
    '%x(Y!c=D?+x@Kl@^4Z1t^V7!{{pT0wMLim5=<pag!SOgo1bruTi3jBAG0P5p?m5izd>a@|MllP3u$hI&'
    '_!j3O2}2M7S@;*<swNE?X$!tv;NfWuyv~{HhL#tK2)tT6mJRV>P&(2JY!3$HF(I}9j)bw93(tEp2R#+M'
    '8Srt82j$%JxZ`3;H^wc83JcUElL2KO52eNZIQHDoCXuv!>EOMED2S*Z3zh@_=<(C9&M%%{JbsFG<qyDl'
    'wf)F)teC`(PizzrJ_{}3I57x6W?=-!g#md;0h;H5vXH1p9O8Q}iI=c1pM86AcHV#d6fZ5EYdw)|TzWHJ'
    'T;I$e3aMJZZyq!k1h7ENP{vhyNWde<2{=Weg-Q%?9Yhf$l!cDtcroET@Q7`D+>1a!I)O`hT&f>PXVb*V'
    'OhEu{gztqEQ-eYfbAVZCxsIeRo<9>o13L<_s{sbN2=%#RQDNIoEMp)ntHu-xgJY}W$-w+rg6-RHA3wyp'
    'ZG#ab(~&xRxZgRbI#}@x5H^;<Qzy9hJIM~>ekGS9zdSZI)Ii<Do4?DAq7HE$Cx7{JyA@k;tSk=kWL2;3'
    '@n{Y*5sTFs!{0+PCof0Ux4zKU-m>$Cu#yL#r6nAujX{=VWd?Ksakhe*C7l|db}Q7ro!HwLAYq?`?msjj'
    '{8BPc)l0lo*N}_}qBVgqxSe4B3`k);&a01+pEG#+D9Ng56Ts<R%e6jN>4|4!_@)|zXWK0nniV#9PhJ3C'
    '5FQtTLj~>*cv|3pfw3m-D56w=IYGhV@Zj$}3^_PMTyk(|DDg>Dkq|a)3QVT=Tp98xB6#Wt78ea1hf4-d'
    'C*~hxhD2nMh;YmTXMqiVyk|!|j2yIjs*Yc1Q2g`>8H`Rb0S;?@kYPu6?l7>42gUoc>O*Tph8{el;5@v+'
    'JBiOI4!7%Ip(+8+=F<g0%r;#GB3B|>4sb}5gYCtv+m}tZH-oN(HP_S(TgmL!m}M`#(h{relT+H%n(dpw'
    '#rAJYmTPNfYr8gUyOu>8*6Mz>sY;Xoq)b04(@)Cuhh&vcy7ZGS{iI8`>Qe2TSGsOh;GmnhfYmhcZ{uYL'
    'pLr3UyINt4HwGfliW#wJjLGal?2FhTUf_6f$XTS$bwZBEDDZ=<GlxP)T^+lx>LQs5cXhglC8{TNn?$@a'
    '62FxtBr7O)ymYK;I2wsh8Jd0B2$r##cgxhv>Nbhp<}6}7<TpgC%L2xk^WJ5tfn~FxV`IZ%Q>mmJpc#@u'
    '?0375R9!z1imDCPQVMo@KQT6QogA>rfY7NM9XTA2r=NF5nAXrC#zw>9r6YidcN9-xfo3s=y8y!CIho%a'
    'svR*4ejqzZ#)E?1xn~S5U!Q;T{QRPzUD;9R556!xicS(RN36@*xKlEiiOzSJvvH0^HxCcal6)FP!d*kd'
    'A%1{_P$XRoesE+;+UZROfuWl$8s6jX);&%tZ_<O8FGqi93QGr%P^k%x`CNL8W_V+AR?CZffHT28U(1b?'
    '&ZFu0S7Ovjw#pO=2_3(|ZftXcnS>`V(YZ`3lXhESbWIILx$x1&v;XM)sU7t9&yLBiw84#U$t=m}(wn2n'
    'Z1~PNdoIfa^p~7!3UL}>o*i}CS#pQ<-tz~4X^cU|oAGd=?*De4O$XO1tRaS=Z$~{$Q*MWM2D8-;q4?>6'
    '?bX8{5@s^BxK+8}Hkfjq23p|HKCtGK$Cp@2`-fvxQ@b%v=?gjEwmUas2sq61tEok`#P><2=<<$rTC01$'
    'GRI62z`f4dH{U+!fBpFK>e<C#6&Yn_346AfVDkZkf^69g^*{o)u*w?64yFBMq-AQZajlsQaB?l?hgo~)'
    'lNGx$T*8Ct=C@?csvgDUR;(J~VzRoatx$Y&ar*OQGfu$ZyaoO+><72&dLecSe6AE-EfCliBGUw5jJ{yw'
    'Z_y@Sg%2{98q}iAQd+W02w9b*Pv{zJ^&1NwXqYc>j90%Co22$8MHSWklUm!M)_AB}rP9qhubEmQki*%x'
    '7pkW1<=JWGvc+Cigek&E<76MNT1f78Ts-^vWxINzb)!jNQ$2WfG8s<}HP%e+#nUmiDf}TMS$g%&tRz#Y'
    '>LmB{T2(d6%Yf7I+hkMPw+vS7V%P<kP?K?tGDQy!duOWY(cU=m1+2ob^CG^Vi;+58G3TkAfA{R0Z?7<d'
    'poQUOGH;U{4g#>?ZYzqEt}%x`!OX@WphS#C5i_@DU-X7zbeI`-d7Ji?vGJ71T_51SF_P-uEqIMOlNgs='
    'uBWZg%Q9e@FybLlv$+%0RC)u@R--Lk42=n@l2mJ!tcuvZ6>eX<$K94Q($`nq)y;Xc=bg$9#Tpmt0`{|?'
    '@6{nl57fKn4kwsU&3=*DQQ>AU(6{9vsLsO5od5Ru^Jf=VDx7!Ojv=qc!$qya2YWMzlbQ+bIQFnvt=hsU'
    '(sHqpR^rnyG&^0KpFT_vMvxd@bxbpCb_C6_Z5<>nMNevRwjqBm&ev*7e4O$pO$^#r!o$4Pp(=o+J7bOn'
    '8s5sy<S3fUSKDv8n&E7<63J>Nb50KK%2i8aXNHC|ovPMurdq3!-o50hb(`mM-#3>4duPPgpdZ&-W?P$y'
    'ZTrn@+fQ2CKC{~Pkkr<8PFve4ZF|jV+h0Ok%lT}3O=sJ0Hrrm4+05p$?J<>YZ<%cSN@Uw(9$U8^Zr@uL'
    '+a8nHTFGJCdkWkBGT45P?c26<-dfLXXg%Yt^@O**<-6@QlWLFIZu?1g+e5C~em7`OnQpCyKYj#xZhJ^`'
    '+gp}fdr5A4(gSU#xS7vz`vDT%TFh_TYkJ$BvfK8T+_s<GHsh&nd(CV!p4hhMyta+BwszCe_L7aZk7Tqx'
    '=c2WoiniZOw6+q_O5~v#j-IrahGsYmZQn^~t>>WaAq8zu8ECC1pzSaJV{hqa`^-MuSMu3jbI<mXde(mC'
    '*<KURTF*P%XWCioS!a6`I{V8xYcu8SpkaTDjRqG|9jd8ABZJA8Ij1u@I=ni+)I!%_p8qQ6$>3eB_4%&*'
    'w#JM1sF9M!RY&Gh3X|=<H6;vm<J){k`x6zpWMnR`@$7LrCb#{mxE{>rI(liWPt&bdL8?VtF0)bF?M9_*'
    'nm}okDGs*Iy)_1Dg+K0K53{aK8`5b%!s#GOM90RHqt-=6uJUc>Od(AUnB9n>?9b-FsA;0W*7CQ6F+yC='
    'X3~i)mjsa)GCLL`2z?$>8gnb4k!y3;vY1W$fXC9t!n1;NNdsThm0ue*aAEkswd~LiDG#W{Z7GAm3mir*'
    'D-e-oN50DmiAfYn$+7-z5XLOxf(CKyQCWK;J6qrx693vNnX&0$GXLW6;@PvSd&%}q7bDw^`a)Gk?IUxk'
    'N~xO%LB^8g^M<&|1s)^|)Zdn^KojFN<q_<xy6jGRoN2eZ`p|By7z?zc;nn_#c5}Hrg9gA4ZUy8_fyIas'
    'b|d%-rG`y`)|evYiLEO*)DIkeG%GQ~-5(mWcUD~gVLoY1RsZgvKYeIejO-Z3AfA8B&<s}E*5+9no5wIA'
    'GDtqNk&`(wSp8+m8r^R9XF^O={=e=FopiZ2sUQd^6C|8jCe+cP<Hd-R={uG3V^Rk!FE`Q9$GFGfmRt*?'
    'm9m%En@``}Z%14uft1!L47)^Z5}5h5i0_%0%sZzupe)phdhf~1=*k2FZEGV`h|VPBOt=p$g+n#@qa*Vs'
    'ivqlIl9UB=FK@vl-qMzqAyaWX2FK~{&LPwm!WFh447`*8+z~5|(1nq<6i#TnJg|Khl88i(V8Z9%wM4NO'
    '5Mf2abD3>GHSKb!teE=D4{ay*JcpA2JFRP{ih>ix97jrv2eD^Io*z3j3M?NSJx5S0gjLzX@bq@NS*AUa'
    'tx*}gOLFpdI)Dw<mU!|}?)q73+N|vNwUGGAmf6RwSCshR^zyvFZ7xS<oTjp_)Lypiz_fVyk@`8iy`T06'
    '+K+#AhtAm#MHR?^?Y>!oboh~phf2}`bmE84F3z8yKECKLlYv*csGToB&6V$SRHzg=b1372$;b<M<TwGR'
    'R?Opo%a93dD9s3Eq2oASOgIlbV%r|~qR_FOz@<E{F2ObwpYS6~_+Ci4@AHsYTslHpt|O@%2XRaU4eTfk'
    'Et|2x@(A_0V^Pp}PAp?P^sO3G*s0uFZxPwqUzf<v9vek=O7)5~G*Hu)lZ866g{Fs{ee^x-Y-@dJ26Rge'
    '6gw^UQ0%nbMzPa&C&f-Xjfp#(Sq6nN@3nw^xSUT1qib{3Xz~I9tR*nsU`;RdIIliNe$L?Oqa>@MO-Nkv'
    'l1&H;%?dk;L}Z8HNlO~pcF26rf*`gW8ywk)d5+I4--_daS|SLYkPz4LsbvWg2nsH4MMBu@&>3*zxiaKY'
    'M1(_#?YlH^94?u#eIDcGTMlLiIQ!g^VEzQQ^lccI!<5nLsXG2vgW{*UC$Qj2N8mSPs`HKvHs~(iq*ZTY'
    'b8Vp4S2LLo-hjiUR&@(@>(K0iU?EQss<{Oq$*08y_JjPBY|CbYJ8_BW0=W&CiJ`jI^Z22em1%)su!%T&'
    'C5QVaelyM1e?Xc!GBV_Qv%TPf*5t`*D?!Dse)-(Ugw+VkIv`&xx%P7{Xv}0B9js=pRwKTjpWK?2IQZ3H'
    'u_nx0aqgjV(aBJS+3y>r(Gzwv9xyRGk%Q@Me)#rAOko7W1YjumlNI&Ph2n=NfSoB|W_F@Vv!KCy_(#^s'
    '8$^^DUie}~O()|aS6gr*hh+YQOgiuPx-2sb`e1f%KOB8|GB9*IQ~@<OzpTPbH}MMCHZ{Uc)A{v+Ou072'
    '$=gl=;h51cOApVGTq{R^nCD?+I5C_F;GE<*xch(q%|GvU3=?Gn8>W1MV!HF?mj;cTLvR7cx>AMOh2stZ'
    'm+0H8N6`uDp&utJAPdkj2mf<6z7?JC2I8%0>VHb!46c<G0!oX$ZbOMY8c%QAfU68nY1&8_%#zX=hp8Yq'
    'YHRYQH0(Eog7v}Cy2N=i{T&Q~4$95LH)2X*hi}c=APD+MG3uo<eSm@vPsE5&n8{J+!*P2kQ(hh}`Mx1l'
    'uCUad<V<#DV4Wm6bX_wlV2;RnN^Zec>+TA>bPd@IM?Y?|-H!Gd8&8CJq?-VD$HtvVV7|i>MkdO!Yi|P#'
    '3BC=FVlX?uoy_00&RGIS`AGTd$IVutZqEt3Ib7dbP-7kaV`ngGS2{mf%;)2gAsWhg)_MWpyL3J*bwImo'
    '!LP4dvyIv!g74If56N(FJ-SuKz{yZ0M_g-bruHdJ{s^Z1*!NyS-}{Svw-WenCGNfduy<P#<Prho9}aOQ'
    'RFav{@7^N6dkOru8uvBl=eO(T8@zOsQuT_Sl_tKt5d!#CTNp;TXWeW8=1k&nX2CC`dqxqhL|7U@xNn$_'
    '3qljeojH~*{h2V5Q*%&gs;d#Y=JBMwyjEwP`jN`nXmzB-oiUChGMNnDVVomF2I{lJ0XMRmKeDpgZx!<T'
    'aNJ?TG1kU>Z(157*i3NEOqjx;NHzoI-o1OB%NsHkJgGL?8;^$XI^RA%>1fJP_s!lYf6OR?XPwu0k!~g?'
    'WQz9d{M`iRFelS%F`pT#YYi&=mW<{DHajtbte-w1gV8C|1%kBMJ)2J#M!Ep)(p>jVD_gX}O=`mzTa3vh'
    'TBE<eGV4Sv)osRC`SZ(XPro!eOh!vS7>~{RK`Wh@<~Oc%jk%1+gOyq_mmauWLn8SPHRvO3z4zUCz?WkA'
    '(1_=dKsDz??@n4Wm~fQw7Wd9?MyO{ypB)=EA(6ifn<l$B%)mG)&~*+wPTAt8V#de>wWxv7w({6&ltcAL'
    '17jilqfQ$RyC%_PjC5wuRZl1tUG?P0&-I{7IyK|7FTt5dPfD;b(ey`i2uf)mfTuqu2ucaq41Q8*32?;='
    '09k!cK2wxyD1w5ZjPArfvg8ih%Z)Rf8utTa#;L@(HuB;2nhtmH!RT%pOolTY7~D@P-1bbkWdhtPdCde3'
    '?vLIKrN6b8{kALlZ6k5bz;LbQzI}8d@m3PwTFQGXN_$(GUhNElU)vJPOdMI6&rREFYT7<B)Ap2@w%`1j'
    '1B3D2jSmf>{F^Z&!@;iv*CH4!?!(lsKQfJR6DJaT&q>>slGa8R+14#dy`iIzkqKJcg*5#ull5iHsWOx}'
    'c6Z)b#!ob2aJH2;wzsUYJtU3YnKM?qBEh!$V(VWY+Rd+P5qyiFHBTH8rVEO^H<kITtB5SwthE#7Yy#(&'
    'qvqe4+XC1)c6$5iwm>@qs&jC{2Qy{GA7%rIX71CC2E(Hh!mu^OfDVR(`8!=rMh?Vu_jb30xDTBq>R_B`'
    'LC#O-Slwezh62c^1?lzS$9Wg|WVH19ukaM$a62<6Sx+C~9h4U6@dS(MQ!+J0jT+kHxwt)4mHTcDg%x0j'
    '85uD#9I8D&Wje*y%&Zel+|{Z$8K`Rt`mPKq{GZ_q;6J+it{=?ZN@&#pJlH?<_8=D-muMK8IT&5pmfE0P'
    'ePqt)`=R4-22H--oj9B!hqOI&?}xVb+BEj|VCx;UE1gV`PNAV!5JXIqK|aE`u6ar{YUXXT@(L|9BPUA5'
    '2HJ5aRd33!Le=x*OF{UZOo7j2bxU>Ciw((aX7Kd?65B%*+^{pkefl~mGIVkw)LbAp$!*Wx1H9i!6%dYS'
    'IB2}P-nA}NZN%i;RqNVh@!xhU|CXq6ofPRcJJe8+nJ|r>!~n=#Km7)WF+O>H!Q_5>+^x;9D>aPq*?+`$'
    'Hqs^R;oimvqc<FqOZBbZh-Wvd<Jao$fl=smIA*W!cODGXPXAeEB@gf~KQVW$;`xFO2eTW&)0{wXiRMQt'
    'P0GL!lbj;TswKl$HMVT|v6&<4wXHr*_s7H)ifvomN-lqT4PJdu6T8#pnK}_qz$M@ns$fX<{YRb(yH{27'
    'Wh+UxYG+kS&SEMO6|MBLnQL8t@I_}d7#?R7Gv0fczWZ`NI6LHMlNs3{jVJ~0I4jMUKPFsmrX==(f_3tC'
    'N+uJLq{$EXQ5%uUz2!h}F3HqQ0!>+3bUaYm;rTpiAi;LBq~~UhK(lGf<P8}N(TUR+TLB#j2WqA?IGS9H'
    'SZ6#Dqr;<CgjCinz_{yDq!@{mAx@50evg?uOFQIh_7=k)uOMUuSPNGX%(7R0!#gL+W;5IyE7>C5kp1xr'
    '_OZ#HMkyVP$5YrBqB^8$=!WAEo8zS5&FhR+B*Ls-eX`Iyev!am204<;A_hiFA{*-4@zQ=vWPou*nRMoN'
    '`|`<1z$5039T4o(gzLIrpI-K_PQU6N8NPYmvNf38Qc!~(rV`)8Jz>B}R<8aSZ!jt4ysFsLH(g^cTSBh)'
    'lf=|$O&j11$xgPb0{r^Ne{7ECmx#*g?B!@ma2QdaFzKa%hAUVtXr+n_oiT4wbTF#XZCb7%(Qrm*U!Xw^'
    '?R$ojw8Cs{-pc{nLVT*2jjo_jH5<bH4`aDz#fLV-4R1(W{{P8hE~67MR0r6z^ItB=a3z|uPVnQ0>QPgI'
    '>USVSP>3cKEBLXh?A6_eG>Y7!;%>uhFRT)2$ZJoofo1l!xY~x9%7lr{fw#6=3Be&!MtIqNKe16oS$Lyg'
    '<IGIL(Ku%buY9XD#{1ES9*o>-Dk<)8&rOBd*EHJu>}~*EDe^LlskQ9zAFCYI)6BX(YogDHBPj3mQr??B'
    'Anhb!T+;{xwi-<F{O5hAXgITjQGK4db$`AzRb6m(aGC-B6T^y62P&1^d!MOdlP>MpSfQ_?=1`kw9wrj-'
    'K2HHI>!i1mFF(^b13vmA%XEl;IrI0K(q#E-El0oWd5^}c*yb&Z^AQ*>#*5f~<ee~d4bp<Sx6@W)TN3K0'
    '%ozpz2hE)6=h|2pDNMQ~t;4Lpd_U1a=Gfy_Z|{zj2XhGzN57vXz_K=i@unk_HoD{B*T$W_%%Dj!fC)`_'
    'yssN{H)AjhK3$+Q6~SCxn)`!nMUV8%<L+B;d3~lxs)b8$Co|PKW-u4GrrV^XzRl9oM3-vG=Yvsex<6@#'
    'W7f)Gg>9-bR<!x8!H5+ZU4yMI+sydDZRsC(`i8b7Ljg-yx)tO+1O@}eZ|a&{yYv2$`bDjE`6%GX*8QW8'
    '*thu9^so}%Kf0cW+ZJ;C!=dd{$HVqJ9)9X{*qoR@bvnG$82TOPbhzg2d{n&-*XG`8x5KruKJ_~+P0Jre'
    'ze6LnU0bX7aCc8-GsWZDDfzJ1nh#}*KA0Fu7mnCn^})nAs~a1wmVKyD_rXA+y4H)M{QvEJYj@kok?42*'
    '3PjnnBr`M(fOyJLvb03a=*DCDO7bKdMazRn!(vR43`vcx`0Bsks(t|7coDKe&3M+6oEeG)x~r?J>)lm5'
    'JuAQA>L~4xoiDc1`V4hPa0jUR`s=u~KDx>tz7lD=%koLzgy}b7`Wq6a-ztrLlcnEe=`SKnuOA-v&c|;?'
    'r{|M5=i|x6+1vA@@#OsMuNOdOpE{%E@;P7m<;~*m-Oc8hB($mMV!j^JnB!pmVVZ1!PrP2t32+<voznb('
    '^aUZ0C+nNQv>jwMhUXE_a6OYGp=TIwWXF-?__}FCrs+kNX-B%P`@R$E#BohG2!^H|>N*J=5?Y4$NOs3~'
    'oIHQ12bQBpkz*5Lg@NOT#I%RL?pt~Sz=a_R;y8>w(}Le)*Nt_17$<RPdSPG(kDmYLZvK7^6JO=Kxa>X('
    'w%wFzPf|TeAZ$00u-$~hwj;mwU|6FT@@-7hVjKFMMew%cza4$>7o?eX8rQU}>F+ug_%y*l)dP)vJ3nsP'
    'iwZt%NAF^!YzMu)+wV2=^xeJH8@D^@^Zm4qzFSH>+DWVLR-2#Tzn-SqcTKnNLcF-OK6C9A-Fo82-#hI5'
    'UEBJ*JtaqKAHK8R->n~oou!HFxc&F8`hS-;0B>1ID7)JDX?HCF+Zea1J^2oLi$861@n61^WsB{_e^Z?-'
    'cZ+tB!SnU?9Na;V@yaISJFzI*>{wp6#XNE9t2|e~?qekypXaw0ubH&kzPv&I@^;%MYrAV;{&XG8pQ45N'
    '_8#Ufb(nm*8z4J%eSf<G@@sH=@A?i%jRX0YL)^DpAiKW>(z@UG+ij3<w?V39`fuPiNLdH?uj4LAsU5kK'
    'n;>Q8%(r_W4Y={wa1Z3mM|uAIxpr|AtVj%8{caVJXN&plUVD2w&=}=t!93P}ruJB?2wrRN30Z;^Uj{4G'
    'UpMzlfPt02T+>Ng5#hJNd^3&KgRkaBe3|5G{Yv~--b3+;`X|zqzf4ME&Hh%$&Savf<CV!8@l6|bU{kTO'
    'gPw|<^LN?Mw70=ei)oy)<!)P*DRI=6YtB_BEwz|%Bw343e%@N{K9WCY{gzcoJYOxVCUqyQmGW|I(EJJO'
    'i(~O$WE}-dl%g%nR(Zy<S-SMc7Ush7cT(|>pMum!x^B@_=ah=3I{(PKWu|o6j?JD9*FJg#!D5Yb{;@p-'
    '3EGFj#Yc`HLBQ?cM~ub?r)L31rvH5*6_;(vgMve~x)V>4CD++qZd}_X>YhF`jwZ(KA|LKa)8RVpmNRQH'
    '8E%Koes`A&SDgu$CctIMYppb0elmJ%DgAAC*>82pZ-vCQHp<-YD);THbBXUH@oh(WZ)It3nd-HhDe#}F'
    '#IiO*R_*7eJ!xv%Q)H$+QDWNHUoN;sos6RV)glUJ(|?ngv0%`+yF#z;wT<yMA`(xYlU9|Iwu>yX$}JJr'
    'Q15Fz1UuUWk^UuReYMx{Y&zd5?@aT?Bs;Mcg>zSFV^5Yf_5?{|TXV)*speAm+{143>vlN&4u>wZIcO>K'
    'm(_SkkJ-*5%yI%}MX32Vb6a3BPo}HeZ?^?@!=U7z4zeS$o%?k2>1=yXh|=xe5#k<1N43_8miHDPtT(}o'
    '?DuxTy&is@caaD4)at*)C_uORF!QXZuka4a4(M^PSuAE@OPwBo8rf*48*<xS&Vq>Cw&YfT9gc!|L}oL('
    '$D^pd9-CT+OX7VdiupwQZH-=+A=OrsP08o|tGn;|(B7?tohpExryqTHBbO<cEp@$AbW5gCW?!|Z^!?I)'
    'xE58u-;N)yC4+Q#>fSG{?d?+8djegrvs>=e2I-V4dL>Rokqq(``gM2EjIK>JuS&}+)zDgrD3vQ{eNBir'
    's#l@t`SqnB{MP%NeXB+*Z_+PZjkaGbAKOxE_`0Iazl9pF`I61;PBkOJnzW4`t^i2aPha6Qtpm?4nC!5N'
    '8dJkA=`^iF{}tca5KDN1dm9g}-f*aB<=*mLoLo!yR!8UU$17XAw|A}L&0RQ~u5U;zast65+Vp6eR0~rq'
    '6+tA6rIxR1RBU;_oe*_ytJ`c3U%ACQ$>kT<;OT!wVz*dcTM=<S93P&d3Z|t0{gtP}KB=hr^G=d%Su1Ev'
    '$+=q*E~2SiZs%Ip?+&&3bk>&yGv0ex-T(P%aMq1cCu^~1HXW}obMy2gKjrO|#O~0s1|L?~*qW!wPvhP$'
    'Je5zD16^EFTQ><9Wii(Al4ggidD1|FyUCK?w5tTRo3<SM9870u#IcL5fDV2F*`aK4w&ZReX^SP9cY8Zw'
    'QnFfre%F+xwBjj4ob)rhr=2@XHGEaR#qfkz5F`e+gR2Pb9xrvnwE@-HTJG?~w}{Y=B&XTfQqQOM=wPu}'
    '!M+5v_X!)lWj{o59x;6TG9&Xuv@2JCykk3l&c{!k9Q?9K3$t<02K`Sz)!#S|XdO{)8uRtGJf8{9Nc+kT'
    'F!mKcb^AYzE+&_w@ArEx-#p*3Hpp)&(8;=j<F|277;qx<)nDTcCMuk>icOQYYs|?d<evSBs~S6#26#hK'
    'le;Rwpa1!v?a_RSC`D$cvr)#;iueSeQw0rIkS!<^MJ>gcD+C?P+Uho?E8r5YRp?73XiNJpQ4$lFJA*r&'
    'U{{D2g1OZdl#1q-aR19_t}^>zYIw^VvMc+4aJNak0h!SN_ImuUyI_{FCfNu+J*JPg#i)J*E`m}tQD4EY'
    'Rb*#(AA}cqhk|<-R(olc$d;^jehp08*Yau`?Nlb@ItSj`+KCGekut~2_D|y*rIdv?`WepJNjO?4ns8=Y'
    '<qqDj-u2MRt)_<T4)?q*H+xQ^eUf(r=!%k8yO_#lhyPmnC<9YAdvdI=6+<xDYNdQ?J3y*&H*VVqgJU&a'
    'Vf^QlRyJL`lZ7mvS-C%dZmYUr7C4m#|5M9?k2xwS-}@w0u@Ot_w^rz@tT|LM=Fvt1-U~5cS|@!c`SNRq'
    'GdM^8p||bgPa*##l_pcKwe)`Ld5^7Eu~jvT@f;MF){EGF<()8C4bl?Wchgp)Dhc&l<_sPD7tNfRC~YiS'
    'DNLG@R#&!{54a3!?|9s@?X5|9XfNTR_rJ3Qn5-kT-gIQSi|#o1PvOp<G$~I8XhRbApXvtP%>vYdZx`s='
    '@?d6{=6)wv^bj$R?YG`kc}7WU2bbOkYuY(xx*@l1w@DGUO{!_4NtK@S>3nChpEtv4SIdY>+f+$fbo*O_'
    '9;;yf4s`Woml+?pEt9@BX=zI&3P?@qogn8J4j2gjwyw$T7VclEU9__<A0;Pp=l0Q8Y+HP5diW^3e|0?%'
    's}|D#<<R!6<KgZ*9)9a|_~pd>t<&LFW#~81=`d&Qd{w;;bFlBU+hK05Z~YD%)ACo*@9^RJ;bHH5{AP4|'
    'K6!IKo?N_r^XBaQ5(Lwy&LvrI*3YRl4}dM+km&vT`3An6M4&3Z1G<>37QyXgMcz$8pQl28u)N1=T%Mj-'
    'QAnI544gP|NNhN|6_CJ<-8hL&J&AqWjUCqy9AeqJr5l0e$7bm1k)0SxfEB@N=6^R^gu!gG23st;k)R>b'
    ';%BnD=Rg=y9N50+c}76ID0YUX8+s%en&xomCaxC+mL7YF6PbQu0%%_7S)t|YwjLAPH<B$tzyV37GXk>)'
    '@gxbRv%3}kal6=%Nf6&oY0@MICGmaT3d7j4VsjWqK@i2d84}&G+$eFv$co)Wk8R(#hOQBKiEbw*iG#><'
    'ywLVZL_xtKE$ipe>@J){ck2xZ($ypeyAchm`@)o-9s>G(+jk6-02)Z(I6<JBMAtpTAHujXteUu<qX$DW'
    'OoG^Th#l!kpa-VuyV8^!iUYRuuv(aIvc3V$X0k@F_~Zt5f01H6h+ug`%ZL)w(}#iM!4eIh5XZG+Hw^t)'
    'cS3Jy#6w+=jKFqcKQY|c4@ev*p<|ORSg%@s1>!@4kRdTh5IJV#1dglwo-@=9ATnaQ#xQmaJ8}ar@JtdB'
    'KuH{XzU2f&_lPx&3<}L?xqQx*gUg%6-MgF3F-d6uqQ!hYrtXcw`olEY;EZu(hEYtS#Iu~(GfgKBbwBpu'
    '7`PE}9S_JZj9k++EkB53#|jL?iY?DI4bvHhvEND0<E!!LWb$To`NIVq$L=Gb=qn(XdP4b=J(z2BeENEP'
    'aRD=(UyLV5qoW_jlhfBfjq$G^-oE||&VJSHOmCNq)kgd08V#UiwYUXVy}Z}>*D)bW{G0!TxdxPW#P74!'
    '9h}qX2J24%c*<a%9w52f`LFbu?rrdKJ^eR1G&sxb#3a!s%V4!8F$?VgRnR6c2mAqKXgqL^gAQhkAYRia'
    '_yg*HaJ+1s#bR@Kes*?AN9%9-odGM&CzjqV1rX-P|KWhF9c=nDo2d@)suz3L8OuI9Iemru_2%uRyjz0F'
    ')7_w_X`r5_!4^g?HV!rtw<M-)ZaOFH^@M>VA)YEa^h<8g>{q_k?II$dbH=i|n;S!K!aRi8vv_uU1Ikxv'
    'c2&368_;ezqzhQtN4)J9=6&SA*d>IH2FTn)Bv*q>>5Ph7)*cDHm_L*9=jda}Vx`f-lzojAKu1sKihyVW'
    '^5`}=aeO+e7%Af%vcCsp&afeVNWVzmn<liUP_(!MWtzU!!;7fKfuc98g6SH}F|-oKtJPxF?Yy18pD#Wj'
    'xO{aQrRvo)iXDOO^)i5yu$K*kc)|HrgjW3ODq#0DgFU;P&hZW=zzd8k4ra6ND%|h>`L_2zM`y1u&qqg>'
    'lZzilrtKgdb+7bie()^0{^VE>z0QAthMQuTmaCk1aXhvx(CD;y`VMHiD}#X#T<O<+?d1qDtxl36tw+b8'
    'kDR}K{d#=PA2`_Cj;CmGyPS~?N$E$%+=>9%!l%WGBP;9nw8y9p01c+ARF{~}mv^XHr0+?@w~eZ*7(xrg'
    'v?BkyLkD$%q7DJ|z|I9SXsV^g7sClhqifQFm<F*wgJ`O8mSRbqz-6$xVN_CbUTdEhRE6Kr>l}|!whDO4'
    'D3PLw@6E;8+w-IJq+eX&T-R5uge@pk0Z?4$nqm_#mXHrXODT0BAR6dgOM%di3NnyF`7APU6puh-lw>A!'
    'vk=C9Er5MGLG!Ihr5|fv$mai<w-GJbirn)lsk6NyAD6TMsI<VNx98{M*Ovm?^RvHR3^1GsVxqVcbkM6#'
    '0$MAo=V7n`gMsb-x^q3iniX_;xJ_cNVm0Cpi;KmAz$sxr2ReuC*xU=IxLSO`Ld4%m2%}7IHC>=<QMR%&'
    '&>50tw#}ZOuC>>TIhdvBCahmYZV1dvJZSU^^>;4s2dM@_r_OJ|VkTo>G7=w)^}8i%6e*>v$md69+gYVj'
    'UVF|^tf~mT$L|}1sBF_3tsuoBplGk;{Bu6a2wUa^h{T*QQi1OriGv?c*UYGurAexrYV!qFszdvW#Hx&;'
    'vsNF|Wcrb=EYAu18o#`o9!$Q!5_3#JN8{w6OiJKW`Eh`={W$%IOpW)i;~;36UYqAt9D#LQCZ{y_3Y?rv'
    'bQM&j>BB85Uv_}MP-}t7ilQ`AUr>f>!93QuvXZL0(y=J)NhLBt^PMYVmMs<jT~vyysWDTHs$?53Do4?Z'
    '?$noPSf*SRPRwn?16tgAaipZ36uM20>X;hQM2||}Nfn^({_*L>(HY3Q|DOCXe)R^xKRJE<{rLRN`RQx)'
    'f_3(RHH?mbJiWL$J$tSE_?@=j+3yvVB`VJwk1gS^$>2pzjIAYA#ePJ+Wd1It3!#kh<d_0s$oiL1ytp1_'
    'JZAI7<}}-V0oB&+7aB(cm5=i}w8G`1QmTh+*IR1zkliaFnMOS)AGW9$Y#YIp%z;!?ET|y=CDe+P0SbH~'
    '7Dva&<71&pFgI5bd*b0n;#i`7ineO$UcLBI37?|{*a(Da{5Rm3+|c?Q8mLu=V2)DDfE%663(HNba5atJ'
    'k-GK5<}+vonJ}#L?P@?1)o9s98dWM&H9ULG^)Fc>TxX|1<wcJe?`U*6dUf`FemwEDG~QNCPrRDb@+7{P'
    'tQP+!b7t9{n~zoLCOkfu<6C{sQZcB!iowpySXYh(sz)@(^wJtMNa%dTjINnL&K|nz;5VJ?7aHTe@EZd)'
    '^+Ljs^Wc_xEb!5*gJ;I|LH0EJaD|U#R7GDnWY5FnFL*h3bz=5iN8xkgIgqgH<!l;}j_UME3nR+YzR=cK'
    'fkYjhe$}DBEtdJ87E5W`YMNlPUD2Tq@U3e`AktX8OQL+jLy+w;h@07Ty-^H)brJHgMYfyGK)0iF-BXXO'
    'G9X~>j^?PS;LA7yzyZD4M$+A**Wi$Ul;T2++H}3?DWGd+yllN$F~+E3K;3DK|NM-dCXtDi(o@E%<ewX3'
    'EurcQnZ^8MAqv<Lt7iOb!jI(@ee;@bJbp=E?A5KGzM#d6+h8htTIJC&NIR!V@A9{NS@MyivpqE9Tapfv'
    'aw-8F3-nDRtmyxEZbcPy(72|z!MmbUy}1HkZH{fzx9dF0kF?85O@f>a|As5M!054mI_@S}Q-r~Y+6J)6'
    '{Sv7+5rZzQ+6bjUj?ejGb<5h9<n{GN76u0&K80XYY-zQ%eaJuNANUgtn)B7>e2m!w`gsuzic?=P>{2zJ'
    'VLOH)Kna=$vk4qBSoTIH9Uh|!gEeuizV`3gG-PKLi&9`w<IX?kzt=!~kH0?yc+by9KTb~0&;CAsEi~nq'
    '<L^&ji)@Nnz~8EWXZ-qDys^GZz@))<_Wv;lhBTSrnVU=~OPWmZ@J=S3gMZBN;k)^CgHg8ueobRfd*vn_'
    '1z#e->=%TPn|dm(amDvJkOrtY)Z@j_Caed6J?%DFy@$Q&^zxHmrE9(%|M=z={4qH@Ik^~L9$XKom|1_A'
    'Zf*o{0xqCy_B}=3cN`<VJb1vHYhYTWjsX5Xhfav(D#-X|&!=nDNAT!Um-{pNkwa2?gsu+g(AO!zWy~>q'
    'i68mVn@ccRQeeJEK<d4BBEBkCytvz}r!nE@K3%_R24kWm2a_S-JGvf*_yfLNwnj=1*L;aFEpQ6o45*{C'
    'i{tbL`0oOTqYq0IHU;8=x#qxB=ugx=gd>fBtlrJpcBd~QGi3UQG=?ghi{ptm(xLIb78|(a5nj-t!%yBh'
    '9McO>q%V=<@?-e-SEny07_{^3Tm!+*SP)u9^>;v>A#A{$fKCO!!jEyV2>_BcZ+p$L&qQL(G0C5u5Rhis'
    'QY39zU{zW%AEA$m3(ELvXapn}jHcjl7=(_F42_DNTf9}c?lML<2tAw2B0g15g(Z88%Xd0XItn)wd?~6<'
    'B|isSMI~r<Q7~W3snkyouow#uta_ID3bJ<&IX4FJ({MM@cLofWzR?-{a{<gUg^6W0;BUa`R$~2E(}U@E'
    'o(}recQnN#bDU8<Xi6ic^k$RZr(`Vf*4I3}*P}D_*pzsp3Y?K?+3e(9Q{T2&UOyjWAcf7QWJa&ss``;E'
    '6=husK2KxJt4bvw&;Q5-;9{}qbA_Et!ryC`s84X4atSu>Gdgby1^kF!Zk7<TxuJoD&2*012UF1ntK!4)'
    'Z6!f;qiv?QWB@vT>QuzE_UBwxdoHQ0fQQv`HDzwc_zpBTZMqpqT3+`J=<yW(p7vZ*IH?-V$#HGT0e84f'
    'HP|b+KP1I=#8)i1bf$mB(<A}m$gq@dCC6$xr5ARSZ)2KT^A7hCMI<o)G9^YJ^)L-?ZNp1>phdDKg4_c0'
    'VhGsmoy77og?$U*A$(a3?qd9k<)`HWaRLFDXN2icJfoWim+02Bb?@)*pCd(r2A=}VQNd~|!F~`L`GRvc'
    'OS2Y&`MqL@U<79XW3iRM@aVTmsZ7Ba{R;6b$FEf2sqYN|?Yx@)Oj3YS8dnGe{YSGY&?J31r%`bwLd^LZ'
    'xZO|GP5ytzN0jlEU=C+5J_tH;i7!yFogC`8TL_7n?H&gU>xE?YDGR>TMZkC<Rs^1kd0c#5Qg|&Nk7eTY'
    'V?>r4DRl<Ksz&fbKD!1~4YH!eO=yM<TK)7nKnpvL_(wZwM0ELec3;0lqZSzE$Xlj%c|Pld{{HwBq{Ffl'
    'q`YFO!XT(IB=-x{;x=ndN*&=OTMa0%piEH0^eL#t?56xd$SEqhD6BG@;$z6pm#kPkkMGb?7gSGFajL3V'
    '5KeOnro#9~FgCfKQHIY~0J5~T6@q{tG37knf_$6N5Mn(j0!@uXIvbSRKC{K9g38O|k>#{54=K|+9bU2k'
    '=-;2?<q&+Rh(lQ)z~Rf>84NthqfxmwbY%!2g)c*^dH#>MA*yep-nuJWs<gbKvQX-*DSEmDfhb;%oWv9='
    '9Ki@FHv3|})tdk;J=`6pTheTA8VFpY=L)pA6{vCnhDV<ve0RvE@DTU;fH45Px&^*XH9jDr#Ru9+40W>&'
    'cP<Y2v#0YIINdy^LWE7v!b_Cf!aEzhCkz4^HWpO>o0-V{CNc0xgcLo5G(&AYsEM9(2M~*!aV}VJpx%O{'
    '0o>s}Hp_<l+}u6pzAokoQ6?LFkloNYd=^1O<@#`ITw3gXNxG7f^2NiP`H<p)m?!5@!*BbAr;GV|C1j7U'
    '<{Z5o+1$G-VlowR^t~+U8oARaoa~@xol4AC_|fRDKhzM3@?f=pov(?5!`5H$V(0i1SLSCVNb;dlF^-~t'
    'UrRiGn_?~oNM*rwLjl1(=o7_g=$6CND-TC+Ni-<nFh^3=J4k1csj7U-ngzMHZDq}Ysn}O|CewZ^V&J*8'
    'N_fq}z5TMhj>03-pT%HDUl4#$G5bQLO7rk?+gzHY(&z}P8FIyFFncxiw_l!Re#_(WtIJWp$^F5Sm(R|R'
    '$LIa*B;*v@)cVUzw8_d;uEZ!tAjjK;{U3vIl~$t?U?{A&0#`Bu&do+kS6<-Dg-`i~=FR*yXtS{8oLni`'
    'e_)XFyF+<nUv-64o22Z$99mMFzi8!huYfxK#nGt3PLs6#8JfI&9Yr5OX==Mj;NZh&Sq?d_D@GNuFxB&r'
    'Qj-|x<$qs}FS6{ny}eYe!u<s;n#!Js>}z(-R{C~B`9%J4aeYx_zgCRKzh;l)^*Z=n7lA1r4HXY{sRiBF'
    '-jn-2wOX)OKp(T-F#3?@&ce?$mjWNoxF51ZBzpYz3Ld$Bk!2^~Z&w}MKq=24jnaRjQE}MG88g&33!Z7v'
    '>m7&?{xZivDdR>ccv1cp-lOey{?MUu{pDb~p5XGky@$Q(IR2+)I)2E91U;OtjW1p>`3H#(%0kGv=wjv{'
    'gN?=GrU|NmXe1$AgG+)6XRx|I7Rp?gq4|(wdrwL4pa%fQ7+_E?lU?{%pKEsoptHT9v0KsX5RMSO_JV#p'
    'V7z8<`yRAP&S}?&mn-CC<Rh$bvUpGb?D6M6tYGwvGYA*C*mQc^nr?L38%ygT;P5y8=V7mipL|@MaX+fA'
    'uDcS0Wml!OYSM1tH={9r_!bFdeSbTf&finM@k6$mX<9E1G~J+sm_<48-4JXKjlak@oSj!H<J1#O)8LS{'
    '>4YFK7qg$yKO%EFAl8y6=v32rVMG?HRG!7_UdWWQZ?bLwy*9#&Oz4l8ZX|krwwQy-Bi6}mr@l5v4`tEz'
    '9Z188oJ52PfPt40Q21*`BzOD`s4<(Hd&Yw)wCNCe-k-XOt7S%?F0UuqQ@0_yGY)A&5yxD5`isT_LKw{9'
    'cqv<+F%Ui;62S%g6~C1Zx8*)#xep9q(lKXfC}m)Dhl{gRGN;rz$zluJ(US39kSw>jDUY>aDD)4q?Z(%`'
    '@_K}gk1&9F#*DLzp7#IfuZ4Tv;s@^Y6$&VSOU=&$x}424+t8Lb_iKt{cGywUL<D2X`CB5-`B{fuy<3xk'
    'GFqm?QwwuCPf=22gauWd+N6gycX2Yt|NK_DrC=KhS(N3flG&FcHIFwM857AiaE6y@PxZ(Q63g$?1Ia-I'
    '1Y@j5yXB{rA^FRZC&jNy?l_g+#;L=vMEbq08&$NL__oN>n4+S7WAZ73VxA_uRW2^5h(Iz0W}5Dg<#Md&'
    'QXb`VSUyWF+M8a2`eL*TVi38`bvFz1Zq(w&q>{Dhjgl?_2yu$A%kftJ!*;G%W58BfWo+z6xQ&Far7<nC'
    '#(CD4AYb;X)Yx(&cz9&GehOBao1SwQsJ|E7A?eQwig6qzg*NxF6gR_1i$SA)MGATDYF0X6J{P{k5uKuR'
    'n=3k7QZ6CB3N!6^QnKiT7?|3amfO#gDTPcUU{Nj!i+ORsxX?M2q*=7P;2fZ`!IrP+l#(^eSH5DwzC-$A'
    'UZWJ|qH1RpEW*O`1?#XQ+y>9E@WwO#{Il#*H;3b(Mse4^JJbv{=D;=HD_pIx@zT{^r}YPOce(qTa26@H'
    'g&35V_Yt-Q^F6b8)p~<|<AY*=IdxB{BP(QCv{+=dO31EA6q@6n@RBoC>E+I`2zrQ4UY(ttUtCeh<wz&v'
    'yW(D&#D7^3WER}3#S3`t7m5tYWaZ)Rt{TklYiAey!(Yff|8#l3B>dys`4m@0|LRo+$ffcV6~S?J;{*#9'
    'IOZ(AxOMU>@LELq#w&4Lb(p>KDmHW%a#SVx1v4)Vj>SWul&>Dt7^MYkXnRse&UU0a1XzHb|9c0tGEMFW'
    'A8}>qQhd(+ii2hN5kGbg(sKeMNP;z=;k@nIdbL}draxbfk1)0L&C9>BjA*&!Lb=~fc_($dsf9QsDu$<2'
    'ms=^*$~n#YTB#w<EhYfvp~%U?kI2QiZ<Kr6;E`aqc*h7yVj#QR=Yp}4g>W*tQ{@OvlMwhlJHCL5ys6UQ'
    '+@nRHiZXHbq?7T7K6MUE@-AhC@iIrc5R#SbHXTUfXr;TrEU58Enk@J(yOu=W1ySk^S%Y{ZOLSvQS6RV*'
    'pq*(h%AAF{b6HDta`e-{q0xdn7-_zt`5<X1Tr3IwC&D{3P^ulN9-hP0|0h-|IeWy;@j>Nb${b52PNgDW'
    '$h%J}=#}~h(W}4`pDUkJTy4d|7OL3F(<`SQ3S6g`Lp?C5XGCl$nZCQ(JYzC$eLn}p1KzXB48c6L&d^CU'
    'Cm*E2_^EjQj;8RVcPv0>8)rU+)FCz%6|e7Bi@T*v5@)kGBPM`sHbW^C5m?)1L8rc(r#A!`UEytJT7Qt{'
    'wSw+k?%a_)J7sPidY}7zJi0u?i!Oh=e0$DoCtV;hNUw^0%X~k848hsh6@~OL%N_x`&zyOuhM~d;D6MW~'
    '7x@f81q`|ahv`DjM}K9P6Pf{2_7;PxkYP~%Y$a@XTTsFh`rbLT<&FgO9|*Y8yK?2*gY5crUPol&Fce*o'
    'U+Mspk1dnvImfu<6U`sZa%f5=R*rvFdD?y~WdSvgoUCd9JsyIyKKg__<o2*auc(T-RcIFrykVKsD)<oI'
    'v!Vu`^50*B=AD<`+?&D$I0lf`LTC$RyGGz=(!QwH;K5+yX@A`2cRNy~g6uj*oY52to?xX|&K$w~ifLDg'
    'gOw19xNJ(HdZ<7MFPzIA62Gt}$cg%g(~C=Xx9sAwL3}(fV{u7&#c*qOSmoS|9c@=HD>-vvL{u~@SGu<s'
    '&4Tq>JL1Rf98Me0F+Q0s7AsLRblpuaFJdv#qhOudj<CyYS9w@svc?;bSiW^~ix)>GAaf?%o6gnG$%@eA'
    '4JI{s20F)Q7ej{<@8wrK7wcTXpT|UdmROh>3!J9O8p7+KlzA#Qds%@zdhwydf0CnFl22O5@X;GMi$9@h'
    'Mr-$er(Ma}7uTv>;ZbJE=lnuj2R~C66pbCrD|(^bl1;#=i~folP*-K`wC6-Xx!_4KTQm23PC^w0f?`F;'
    'z$w9N_U|hSAm-uzk7m$ISL_Sp;JPT*7VE(s(g6hnnBe-bD;5FJPXbCK^L1a7zrE$(_KM?4%Nzd-Y>2Le'
    '2YeMNPaO=udHguH^?((|qfsMi&~ua=>uy0FWwIodO}!FbqdDDf0U(>Na+c4adw%gYn9Z7y4JD7=l13Or'
    '@9&o4SRgLwRcyAaR5pF5bq1<h!MPH;U&FjcRyaj$g47P^6;3gnR5~Mju)*p2-%Bxkw*<y;uwG@lLpm%-'
    'D@EeaH1r7*5LC*nh{%GUtZ8}r*#b*k&p}@YLR`WkCnEoBvYgH<M9l`Y!!MCGYDMZTiN8XI@W2lR8D&YA'
    '5*?_jt28Y%&E>e;1T@sfC;E<-Iq2kTqsSu`w^6->K}T$Q38VDK>>g30G82WW6V0!2l%gWHf_f0su#a>F'
    'MEWr|PsJ6d7Y$2FDXHLmUIwi?jqq-y5e_MCTDZ0+D68`FU5bgat6u5)`JBCyYL6L6G+LXd<O7cJzE*ZH'
    '4#aBGpXDN)d>MJ`k!Cfb<}WQod4wfU2Qgz8nGcUad4=Czi-a7hY!$oVf#c`+Ov(Y5xO0OAYwrAp`UE-|'
    '44pomwS*N?{(~8U$S?*!(wj_ZT6Q~XS$)Q*=Hwj>5_B*r5Wg8rXhIVf3!#>9fm@U$Gmxl@EDrOa#0IEi'
    '0qFQtr<eT@PeIk5H0J)Q^Z`7xaS92@@($-Yb3SGX%BOG(&|IXLvTNDTyPi;M7r*BA0M{H;7X2BzKMz1='
    'F7eNjUIlGYq}Z}JWL2=fW`L6XHx8qm;=sSEN!9JwS^tt$#riRFK%hJkRLG-ARx-iRfd~rVKL(3e#&x;@'
    'H5jP|t<S*E-p$-6sq;$qmS!eY8U-&Qje=6fA1-LFLd2Hvj>7plC-2C|uB@^($bl~Mmd`Urg?d%B5LM@3'
    'u>;uWtMnF0E_bI;T)8i#Q{D9r$`N`j!<u6*XY^uxpNm3-p{8JB5i`HnMiF}Y0CW*^!1#cO3E?+N{76ov'
    'LYKy1yCqnGd<ts`b?et6&!JZ=HupJ7xAr&ya?F={+(o@;9(hH+DlVwd2K6i8I3I2nc-ZioB*n~UGusz+'
    'I(sf9L@jes5sJ+fx6NlAiR6;cN;9hC=2)n<UtaaISkGTN9QfV~(5XMDUvogSSKpI+s!m~U5uQMPDP)et'
    'UNNjSf4A;j^V=eF&8-gV5$6lAY|c@yyB~C<I8<RVm_UUy!BSlH#Pj*^M^-3Nota)ns2+Dt^WL%+0d<&6'
    'wVBF$M;W5k%R{~Tg_S$mU@+4tee-nQm9yRYTJFWNcU~{>H5v5cYk6Cg2RG2SEF5j9_ApN;sx!2D3HzOf'
    'JMK`jeYt)^*-3*NGP#Hf!to4&eAc01kBxZoAm>$C6XB3gAECEeSb+GDJ@Fj1PB@yD+ev@pw`0CMg*TP;'
    'Vp8EI<x;NkWt@tU)!R8OBnfBPgiWM5AHLFOLIa5zo_PhiXJEGmYrr=CJP-s2I%GN=TO870diA{o4ULr;'
    '>0-}g^%VrIa(O&GUlQN6ohiGqqrJNeR#M%}FqmuW`!!yg!%Ay7o<<QtavAz1K5#~qvKu@vI7KjdlE6++'
    'xF&i-c>SB@bS`{J%=VeEo8%L<48)F{N?Ey)dZ$vs8}tR$Hd=J_Jl4U3It<G^FS=@qILR$*oA-wgUheV{'
    '8K4=atCOYMnQ<2mCaLJl=T}n~CN9GW)$;0nR8Q!is`pLN<)_XkrEiGX;8MD6!I`zik=3>n>$4qL)y}Ib'
    '?)RCFE7fVmcjmL4R&}x}A2aD}E#6n*&)e$g!fZ&I-)06_3;pNmJ60&4FHvcCLbJvPdud6xLj5mffblRP'
    'aganlNr-Q_ris0iZ8Hk3$TMTtG850z19zyqw&ldZ&?Z(K7(+eq^w>?}up^J3W3FE05kewA@C{QBO~;55'
    'G7OwZcihOdUBe@8Xa~b^2(uZ9oeV9{hcOMqHiyB`jnlEKd(mR&+0*s<j=WBBA==RP#M`e&KcRI-?>Tct'
    'm~$QMjhtBSkm!-&_;#QJ459DA-;Qf1I&q`e8UkdYXWCvI#JUkWu>sgfbl)&SJupMsqE|^kgF)dT-Smvu'
    'ja-X3j$>K6MdG3D`?{ILL&qI@?l6pq9>=k5_>SkqVQ8D!wb&mTeoP0wxtqUV!)R9mY8;u>C0=0xrDIGV'
    'pVK8DXs1{?X_`!f5QyMYb%XA-V=AZ`8dka0-o8CO?)DnK5d}+@*LB1`Y<cY=UmBMps_8oV+7AKXw0=d8'
    'UeM>Qr;}+k^C{R*)VYJ<ddye7n@2RYXLbXI?FFz1;CbR>PkZ(!?d4)I(>`hNJFhIfVxOuedw3ii6acJ&'
    ')t$~a3;Kzy4uFA!x=wM3%`!jn@39hZIGvO3H126zCVIdQ?cx~mg6x$i$?#k+vLnk&j5yF;-_Q*gc!wVa'
    'dgz;ONZ^DK-wZ6rw0t*?yeRgA0Gn_7CVWUrPtwr!gE(+3b2v<#z=pGE#&#6gz8(3xZ#qLWF)fdn!^qa*'
    'kOqP8`AMRCo|!~R?0J<ZX`f!j5!tqn>~OtbLDsc{*03s3jJ@#BzV;}v9u&A_z9HBDAwP5bKkYZiqX4{l'
    '>6SyCPYhcvKByz~wee49uii@al`pQu1J^y?<hqP0v;yRQ8i8id)0%8e?%GstLVNA3tIk^G1)lAE0K*8|'
    'pK8*MRz>jkF?q_Xs{3R~tWAMxl;K)G*q2kJ#O7#=QK24vYIcCz(jzEsJy&V#`4-xuJ%F{29wdI~c*Df9'
    'L5=gm;n4GZ(+FeRAI3=%+p$3si&(zl#EGr@#B!|IaX{U(;YZ!rGCwQiGFg*g1;$$j4Pos;1rWo?@NFw0'
    'pwXBKF=NZIjiF~nffE|x(Da?52dZV@dcG6E+-3j>G4&vbL*E93Z2>~Kd8l=f1k)Myd6L`3hU9u8YaL5B'
    'K^Qr%g|qvhx;i!}TcD7+Ll7Y@s<W1z1dgve76Fk#!eQcj2?7>`ma9`x9@B=oB>}j#gFFgF&$fVk64wP1'
    'BcW@OK!>62VW1C(dTjcJ56b&62z5|4Ek7WRISh$q>P}*yETt1Qx_;ORhM<ufpsm9ex<E5FtjHm*@5f#U'
    '1Z^jtYuoWKCSl~l{~g_rqsY<0WB`)_=&ZOV5gg(*XtRpZd~uOZK+q3uAYI+G!Z->OkD3HwXb~?$8jm77'
    'Ner6|UEML=z_5r32!v-m*K|ATNoKv>z8&RnNBK#Qa!Q10aXFyIlheOVet7%(FQ^(`<+Zc=cEAT*ZBmt`'
    't?v}%e(8fK0AcVvL^UP!^YXZ}gOd8Ca}@4q<e%E#WyyV2LEO(*;0Fz|xJS*g_ykC7gu|ypVHpOC;C^9C'
    '19fffH#h*8^QR|M%pcM7V0%x40uQJ#06IJ9w4hE<(|4hQnKbF4T+ZYgzS+dY$zEs<Wxhx*o2jmkY138I'
    'k6f~f+zZ7u?0-Se-(2cMS*?h?g}h%?M=Gmi4z?kxl}j)Y?@Q_<tNijyz*qT(h}&%|j8VN<Ty2pne%WHn'
    '*hCw3{L00#TDs5jv(kM`kYFtX+LTEWA=UN!YNu#$ow-y_w_M-P^4Z<%9F-O?Bj*XZqa@9hFxi%>Evihk'
    'ruJeLLvN)NW8L77-^pEUq$t#=DhpfpvD0D|$NC*;qo`xM+tAr@$wzfExf0=H>EVm&L00cL9^5hp`-l>C'
    '<&T!DU2RvsD^W-)>pj(VOQ<U6RJw@vt4XP3QUlDx^<F9OdqmXaF^;9)Ub(%X9X@81y;AF;JRJ7Leyp-^'
    'm`e=HalB|4gs$f&Lth{It`T@K!HB%+MF!~kLnm_3E9bb0XAs{c7*)2N$W4sua2Q|rAWNo4%kZiL-$|V!'
    'Qst{M0+t_V!pbOjD+b~{3g~3j;j8`SESS%M`*nK-0IOP#pmr#H{JlzWO9oCME+4tCNudP>b{0H1ACHbt'
    'Uym;?s{K5oLRD$lMQPbkYDeUuTr=wI^K#XPuNQNYAEnI6a0K=W?MExRgT;IVjW>&=rVWa#yEz3>Zt51U'
    'f;pIz>k<#cepS28de3%B7z0d1>!^ICjOk~WIA~G2-yLfCyBk$<sSt8fnmmb;U;;2rP>9qMt_&VwwoRxV'
    '5G$8bdRKgxuFEz9R>CnqWqGE!g_Yu6%tQZ6iJZOMEA{m7I*|qYRC#jS-;bu+jJId!VRUktCfOs?HDcn%'
    'W?+~@FLDD%w_TFhz8QFd>6)Hp#fh#b=Fle=u*oQllGqqJactY37rVd)GhU36h3RjVyttJpMxGa&hLI4H'
    'I5CM0+tsbW_RQEHS~@UzJ2rgJG2wk;7+z=wact?aqdTtenR@70iDOqM`TS$U{<m+9Y}YVt({oRp(fGtR'
    'j@+R))cyT_O^iN$+Z<UZ?$~p^6W8(lBg;J*4=vjpHhbIkjj{9cL^qF)hePwFZu<TRUT1SxMerLz-fW8M'
    'T!!?0+qB1H18{oe*`tvSgmXN0k54RR5^v~vNAB^^JMr9OANI%|nz~^$Tu0p$RUzr@Wy?K2Hg(H1k96zh'
    '(6L^+qtTILHhQ@h?t0`ryx6kA)ue&vXDfB=PuBrHxesUW1XSH~l3=E0MD|~7e-~R^{{;&g;hUKANk?LA'
    '1tXD6yK6EMs*?0&7G?sa@$G!N;W4M#U3kRfJbxkg9~P_lnBW!2h_D2X#<MWUE?0yB`bSzl@K0Oc+`b3a'
    '$%%WczqF6-m%23`o{UCg-#xZRkKcorchgyn=xnl{gl!mow~`FLe07y)o3F0!<l*Rz2HD0Vl*LvaWj-5S'
    'Q$0gyJYL=De%SJRHQT5qj4wEwtsTuLIhmh*Fq>f?&cJAB+vAaStlLBX$o5{2%%daY(b#WtDog3AYWth4'
    'tkH>B<2>CaN<bx#YNSFK{`knZPaMm39m5!oUY?8`-?xt%h+YNGW&<`*7{)KhN4nvk9FIq1+a4W_b;p47'
    'YbpxE_ylG-J~H)_p?PvNv|b*KeAj(>)J$Qhn_{cXucW;uFW17IOK{`v7)c+u_0WraGq#e5xI@<n{Wuxw'
    'h8~ci7we%lbWH+ZCYCicL4QU~d>F^38~H{Q4xOaKTY`yrqDU)Ay<jv<$C_6MtM@c2iFd^wf1yF3Vttn+'
    '(~md|*q~rUO=!t2ycYt?nM|;j<Ydy}QMI&yAby=$lv3Bi0WI>-Wxz?TsqrT=kJ(jdHm6*bk*$}3Ca!tV'
    'QVT(P*^u3VWep~AwDoc}6%(a*vC!j-#sIB+L8w12?$+gyNLNTG6{e{Ghjbhs((YVK7n|7k{9I%|6beW)'
    'fH^|wFx7qO`TF_Fr*n8X3E<Ou8OS9o*pRgT2_0M9z*0a@kwNQF9cpdd5ZtR=7*3L|E4Q6n+laH$0J+8B'
    '@BM91mtU7DTx<kXU}Zx}Z)K(U@zOs6U&vaOuH>PIJuOj;=PO$l-!Ix*k7ZovnqtEEyo&0!41w%mqg$!a'
    'hn>UC>txI~QyO;U?iS{|c!ti2TtjnoEwR(X8f%s`qA$74RMLVztvv@U0<ZAnc+_8HU`6Q6ha`8uS<|W-'
    ')fcCftCV!GT7O4PLEmDB_o4?%Mv_Q6$u&_?x2k@N&dKfKXI?U$)h<E)D^IdmZl<@>e+SI52(tjsL=PA~'
    'O{>u2ZPMNEPaWEF=QTrC>Z4qyrG%AB$X~M4d#dA6x)of066G#S2Zhqn!3R+jKkfHO52-BiZUS@(Dw~5>'
    '3+Gvv$2z%@^G5GLV&FZCRCIDlp>AFM_A%P4BlWx>VXkF)7t2M6;va71Y;WJ#;^9`fZ}~Fi?XG6Wg)?5C'
    '4kga|INymy<Pgs8UljX>!epo(t@AmH=~)-;Yj|g>0%FRDe6Pe?UwT?-f3vy~=+xP(S+pK@^q{_I4|P(j'
    '*Fohn#57+(4Bsd-zWH>jf4X|s$0R5>pFO*@S2=TeVDvF7RHC7k^JG`#^F!C#48?(z8}(TQ9icNGpI#iD'
    '{WJ!3nJ@l}RL62Fp-y)cH5@qq%H&YCVwoigrLhUv&2`5j*5tYYd!={6O4Wu;gKtaD=ezAOfnSbGDGav-'
    'jh`jU6$GVL7Pb~Clu*G6IF8lV{ym$9CFM=}S>fGDOr2%%L=*v-h-?4dQXGgEw^mmvq9;`v(|QA0g#j5?'
    'lMJ}Zv&J5g8m>}g#k}~BV+}&j<_JU_;5A~b<wnbo@$vhb-|G$7^5qJ{)75&Dn)@l5&(B6bPEO9x{yr9$'
    '@+L3G-=DsgT^;C=q;J;0H-3FAztx6kAfvKuldle*A;EGdz%?8<wlu7I!vQ*n6<h$(NmmUge}8rQa`JL?'
    'G4^ckccX7~2LD{ZjEbhz?XcMGcbG4{;!W@3tLee?J5Q&z?r9~+?8Kw`H_fVL>V2w1^Y?&aJiW)N^7PoW'
    '6rqY;sn!W(I*fX!Qwfl#OfJ(}@Bnpsk26wvGt-=gRAQCpTgX(Ir*(<dLK_-Mr5Uj*4%3GEXxGfegtD2c'
    'X7#0}MXC<fC4uME9;IYW9w(JmC;4L8JhT&9MPqp0T(PzvJmYhv+LN+(<;mAdUQL>HomZ*y3<_&8FbMh9'
    't`;B4Nu?$gyEswFeT~<gBl5Lp*<xJf<%Lx0Cx46*Rt;pPa~0rJy~jD2aoV)Z9BYbJ4mIB)mQj^us7+XX'
    'n{>8v<!(Dzs&OWuQ*D;?7EC6Wr7ts4*5sB>*^Xp`^_nlEaBHUmW`5bIY~E_?s(dAVY202NsA^719_1<<'
    'EL<`wGYlIOK|_ex9)>73n^-`+W6}qaid4xkuHX$eIL&pD;86^tE1n8-UCSK8kJZO6KVBt^2(WevZ%bOs'
    '9adPMR2`=Ad@Oc=1MqcSQQd+5(L12y(9acTPX&_OUYYMl09poM6?|p;ja68yfh^k!F38}ef*4bSO0sYl'
    '*<+^e)Ab<Tl#q0m^`0iL=e!K;Hg~Z{o?6ndC_@TL_vc@bLLI&+Z}_W%kjfh0HRd##AE%egmoHeFnG#mK'
    'ZuH3dd!qfkm@cJ{Eyue|pQxjpMk<g@JQZ44jkAnSQLP@9-hH4BjkItzpF@gkEatpimEx?;?kF%u@`9^i'
    '*kLBYKB9rrWVYZ)J3P#l`z!M~NR7x-$kNV>bCnL$-l=J_YF?S-+fb)A7YeV-$ZbNmdwbPZ*ItRywfFx4'
    '^#De>'
)
# CATEGORY_ROAM_FROZEN_SOURCE_END

if __name__ == '__main__':
    unittest.main()
