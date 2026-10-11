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
    'E6i?KqmeV{QP&v`9oOo4{gDRT(zop%rG2N5wXQ73)LqwfZPOTHaXD%Zs5Tn)2A-a)75D1+`<KtqoPP22'
    '>De)kKIrR1ZSV2x)6?VUug-5-J7({O;xT(SSC84NTRvv5M*Wz*Z41ck-J*ib-YrYW>}^s*W=~ELnZ5N@'
    'WcD^IBeQp79htoi3d!u<u9D2&?Mun*t*s@qw|z00_0J}SO+d+kTwy{eZ#^Uf<P#B?#U0KIPl%J<s;~1Y'
    'u7Bq3-tj+pb$SFw#LL&O@PghMi>%a|_P8qiHZq8=6MblzPR}t-!}BcLvj*<KAQVfo^>nJamfIhWyaDzo'
    '80jNABBtKcuxOWKw$`M|ZTwma{dtBlB0WbpO=|?AQ`a2R=naNL)1sCJAB;>_8}<73us0kUL)#wpM^rb='
    'K9&U3`=h>`S*2me++Et%*>6ssz5>yF_6oP8B>_(5Yk!HoUWpxk@gX?FJwC%NewprYp51;7_M4hlE1#Go'
    'd+c1%B$l=^PEKl@16iuY#8P9@gUEbUrl!};+&N~CrK?VDqQ(H{+z)P5HNDD6+#Nt@!awXbxV{Mi|8v~r'
    'qL=}S#wEK;1H^+>w?4MH=i4;k#<>Gm^oA{OoLk(4G`njIVCU_RffO;mq-S;~#qX&QZ%~HsUWDHV30@Z9'
    '4MHlXZt>%@rXi-0w#J}r)ib5B*(A+agpr;c9J3(j4p7}R%T%tb-L$#US`KzLr$t)DE(#5A+KvpiUD|8A'
    'H`f}s*6zw!+l8%mC#G7?QoDY8eao;&WjJEcbIsAv8yWi0v_01|dhn+?at6a*&$Ni^^sT{wTD_q)bR6C5'
    ')8W7xY4%`fjYh6Pds|qHOTh=%?rWOoSOcx^8lI~gbTqV0TQl(woqER59GHE*KX5f_4q&!};gDib!WhC-'
    'G`h_kDnkv@C{p4`rKWwec`@Q7qK56ikVbT^Lf=1GgEEe+=np7y_*^~DYq=w{8+v$E4|8FUpPn9{ea8cZ'
    'XXCm)Q|2MbnzFosc1?OsP+m*2C4HB6bJ<E3vi%&<CKX?TQLErE#+A0=c=PH!-~3SiBIHY(#)QoVvZg}o'
    'Z*sa(srqd~Mt#@pn>~%_BhMg~V_JsmxW-_l_ceWF4Rp&h`)*&edVNAzi!Z|=#>ncqy`HnJ;9JuF#Bm7e'
    'nYsg-Uh9#;(6k(VL@9PHv21(fY6E-N)7_q?IXdZMOC8;Eu?3Us*@HgadLqpl0ZoK{TG^HTG~s4WK5zn;'
    'Y{?hMu~^w!DwyPS{p`D=T+2u4D-nU5<N~p%XDt;BtHV^hfUJC#)uxiXs{Q;Q{90a?`qNG;b7EqT%)sV8'
    'lP(GiVen#@Y}we?v^Es^)=&dXxI-S4ZN1!&(BCfXnB5yQjaoE26v)lX<K2kk-Ad!T5yq=!@pWxsoVSUR'
    '_gLm1X1+*1!)vXpir8t$7~pA)uKQS&X-pTF6mD!3aNa%1AdBs54s4cB{|RA@8wsITuwKEhkqV2kfGTpp'
    'MN^h0F*u<Y#JNf<CgzaZ)W+pe$5$&--IHry4Z$rf`3=tDt!&Qc3rcPyanF_04A*jUf#r6KFQ+3V=^?XQ'
    '8<vzi6qI)*C+|i~Hg@WMZ>?<+!D?{tGF>AR#ENw=Jto(duh1+_lKQR`%N^;JU8<E`YLyjAr5OV}#h)mz'
    '{El9|O-gGuXa(Sl-8Pf2jaOb>%jME1H;m6KZ_Bmid)g&p%_AE;xCTK<9XOo0hxuFa74j@8T=Vvg{x+);'
    'wf2iz?u+`)&<<;95R`P<-Y;B62J{C3wx(^B$~CvTx%$%>W!e9%ICy`>#qx}eyJ^!=sVft5-~p2ZJp7SV'
    '$r;OCVdcH77Tc;O+=iXW_r{6i9!vM#3HJgdtZl?@eIJ&3+#blp`+f>$)5>OV4{wn7QpHkJ>JHa^m~Ygc'
    ';-Op7t37Si{>#>ng--3wt+i2g)~GhS2g<B*adk(kY-gHmog$O#sz^4|ex^Kr_WGN&btb=``_1vUC(j$m'
    'tVkO{%;ps952QhcIPJyNNRq`;O%<si*h-uQtYk{(=V>vC?6N!Su>xOeU}+6xVYBt5zI{0yl<m|m2=Vy&'
    '6UhN&xoTlY+;ca~^V7<X5Vb2PYu+p$kE~x@vys}u3K&6%N<$4%MN<;>js$8$^7Kx`={jk8{r38L@A2vJ'
    '5qxs~^yDABdVP8<Qed%=7pu9FT<bkr#FrsfNcr9mXjSc<r7yBuz)Mw9V9eKn9~bWov#(;!9#+#O^2-;7'
    'Z&lZXABN9;_kyk}%(FDt?_RxnSq6BULNQwxTd8r2x+4myygcGbM51cAgkmb#YxCAuo~j<&EMvNUeso5~'
    'r$@ixby``u`@@<$ln#6L3dj8J_}NR*O8|$y1$xqf5;ny9`IQ50g0j7QPssI)+_(hOUcP^1<)l{kBidud'
    '0XIZ@Wl5wxLBy|4kB{;3zBzRImPehDMd)B;+HQ{;8jy)TfF1Ambc>k!h#KjG6|En8Bh4TK(}u^0*Ry&9'
    '!=pxDx9y%iuyta1x=V(JX%oxP9r%`KI6d1lsi$k&!1mm9>;&7{&^pm9Yh;tbV4x3(O=(}VM}!V7$LYD6'
    'Hy}=r4EmNyMwU)U&*-_j=~=F2_MM(J=x0MGHKMbjhhD#LxP8*|dL|hT9DPK3mgbl`z#I++BiFM{(*!>0'
    'dp*0S^(@C7^!oi#-!?sOH0q~AC;OQVP5NHnaZPVHur$xsHB;*o+v<5X(TSt?Elnd1H3vj<hOUbhk_??1'
    'BieV#NOJ(z5<*U2{HD6{d2RflASqv77+MywV7a}K3)6Bv*g8k2R3B<KF*Ir!J!@on2J9y7xzr&;M;lm!'
    '0c<|?G-JdrP*z_=U^YzJopu^J@6xK~7%W(=kJtDR?3Q+tPmz`EOM6p`hQHAp<L!3iqa%Qk&34iitIJao'
    '*I54iKFy3eFfYD9tS+&L{fUb2o+BRkOtH>6yB^ICaYg1@0%<vwC-bVd#pUXy%E09QlasT@FMc=%$t#3-'
    'skY%?mcQ_;)m2K?O!fAgB6ClQ;ib(&MK_VyIT+p;CX3JQMU>PDoX%L4>ZHMG@{8#5chkMXG+F#`lPhEF'
    '+bM+P8UT+XyNBn@L*Ol))0y(359u>E0ALBl$$0s=b~->3!>)*LSB14#vBoyE-^><dp4(PFc-Hd4%TGd7'
    'N?y%`g`LdWMplkeT2WVNC0J;!K03G+Wi?G$(&=h7dovI3$;s*QV`f|m5tnKHRg~WX-8t~E#^6AwUVk*C'
    '1Qn)cP)!@^qu$W&gPtYS8V)qlqdkwf)`0dM%_ABy!2DiQ%IQYI!VsLf^xH}khGwvnXRKXUw(nWR-5Y}l'
    'Xo0R-2>z2@px~gEZ#%5pgPW$$$ad)}!|Py9--D-3T_x#>#cTD7)iP>qt&=$0(M6MFag(T%LlmE-e8Z)$'
    'k!?-Wd81@5g~}T-Z&FvAIoY*Lnx84JE@|4%z*|fvd1~P8`>;uL7QCE>?qWg}uwNCjh%ezW-t$JWuWp2e'
    '1-u<HnZTe)kJSL!-VZL|BR|U3lXwsYlPg~NTUDN8Csx+}mwydWuWn$gl`r^9H*%zG#OKNQeC0RUHM=3N'
    'T~gOd;%bJ|!>J9{vwOa@F{}<hb;Uu+<_y2Tzt4;8Cqt*Z^WaxXD%AuytgxT$SHKXJd_9xUFyt1@xX!jn'
    'JDH|8KX0t+Uc6A&ghwNDFXZxkavZY>%V%@Uv3qfV+&Ylc#j<Z=^&Jz|E$K=cS*>RC+yR_8FLSr&{9I+F'
    '<z@%lF#UJwfC~0SXZ2B8SB=Tl0hgQt{h|?&f*rq<DE2{Q^QLtX<|y*cV;iu1W|gt?L9CAY;`HR(ljldz'
    '&QFhzo}4^CK0CYF)hHL?#KG2R^4sje4g4-^2R<WK7oTmw>ARyQiNv&mmagAkr#)OmmTTJKVNC;<%Bo3@'
    'rFoS0EQ-fCwn+_22Ypl1HFMN6Y~AX^r@9M1Cv`Qwr<=M*9ee254jnj_LpQ0Kv~<SM_XgI;wt6~1=-VDv'
    'KC*^nWR3<VC3b&k>$=mkdcD4D6U)W(5@%#;rrtLP263$6CNL|HAn=o~*<mkGm;WArz9)0VV~uJ6eR;(F'
    ')q>W#gSrZs;2fVuFu5m5-=L)b3|<_2^R_9VS5FCW6gH;wF#IJQ3`nrWBpw&=c*@?39!UoVDtAH0${9-('
    'kUu;gFrXpc6s|y^`tK>DvhgzE$zM-IC#+7$ul>L+0>pP3fOi>wh<FRAs4*l8`461L$)F+j5n!J3ll{h4'
    '!&J_pk~XDcl<+O~F>Oo?vEg?Gb2g`Vis+tU$Gx%g`t`|^nsk?pKA~~4NoO(dc$js#!@MHV@2bwC>dh3_'
    'Z-*|BY7|bXf@)d$RBuRpojLPxGLbbJzJ7pxbKbSd#J>opU<-{Eb;A3+b(LsF9Qb97{Rw5k6V_6R#XfDD'
    '64-i$b<OvqWcO7u@aurQhp{ocY`>#=VA8f#hs@Ao#XrG<o#QFgS$s92Z8f4`H@jqh)!BL;*HY2L%~jQp'
    'UU(kbui&_16jvgiLO$?khn(*iy~?CUd?9w8`gG#vQN*qtUxF7v=lfk&0DkK`Ev=t(qZ7N{e+cJpN5$bz'
    '(8W1g#2~R|e$28VSuTRg;td_SOT?ENE$pcuKO;7s;Kt%gJ8Br5vA2P`UXkcs4I(2S2n@r=ZFiJw<y!t4'
    'wjEC;jsqUDZ~GHJzB<7}V&C)WJip^&clITt{+mS{gQxtdY$V0=1qCEca685|(9ZWWw+>Eh5m0S(6~%OV'
    'f+_3U6YoAs3bm(VTJP^cT964g$^aP^f&5^5e5)%Y#c0Tm9JIUe&vxUUt@h4hf?-bKk!^iDqE&S73WLhu'
    '4?p_B2PU1+rqCkCk8IeD+_6`;3#V>3KHY9yx;yZ)ZgR3-d<f`#tl)hQ_G>*_*qx)*k}}T-RH+kZs~;=a'
    'ay>@#e|u9g)#Zo<Zjqln87nW?Me@vmkTQIf`N&enD;!Oam2bjuB4ym<nu3%;uchog*L7rx10-y`>IZ(@'
    'UcL3=qfR&3zb)YjcaIIytvzf0Dp5e{Q6A;r?-n++-t7J8aXMD#-p~b_DR`pAytm~*wfN|Br4^;LpDXuS'
    '5>e&%I0q|xv#b1$hq$>7f0uM1H3TO$0=MG;T!ZnqdlG(YUCYFc?BLs7#@-}irf%fzE&^|@Z@?`A4r*V}'
    '7$YpjD4cQ)EJn8<9G?BPi03sL(7U5}p2TpT<Y?Y*f_Zlk%WF84w?QQDR@Ic&)p*U}LM$q|@uRvT%%;Y8'
    '`+0xsdbX_sO7>Ygl{bfFiM2=!;i}%8Olf=S2j5Zu;<Cm`fN6GCQ|~g0Fg@u?W<VMg+*cKb8*EeR*`HvD'
    'tPT8ABV?RWa1h2B7`Zz`ClSR3B~iESL+CH(;RQGg5gK-R_7fwcs^$bhKK{mc<IC+a1Ac;suEJGk6Cswu'
    'Zv<`N(6eypip^)Ab?O{Ca`m&UN19p<_xAwgT*RmOPx;sb`M<cpgg;R4k*v|L)fsV_xgvqzCCo`Bv)Oa<'
    '-oId0%qtYudD`UCyHoG@XSXV&5slHP!q~CCxD$2Jh_+b4w^BD*g6i3s=GndCS&6b{)lL&yXWdewfXu)d'
    '*uGInt8`MUCL^}}U|bAgb|e!pz7kcLKvl&X-Sh+*&laQYz2t1%+;DQevg_0e_$pz@U;IK4+2NrQ_>=9)'
    'Ns6Lh)^$=wl3+2k<jrVfdqJ9$2>>To+zD?7$RCmnvHM|u#URMqeimqFG5<~~+QiXsTZ(n7h5_&L*bcpM'
    'DNcqU&$~(zHS+^xw5@Z*vPAetX&~;a!*ujdFn&@~UsetoEbfUP0kHrr0su_BR`XD{E@9uwpZJ%CETw|f'
    'T}REwzefAwn}v@-)nblECf+0`E2A_{3hepO@pKknv0){73(|PMC08y>kfR00XNTERxjxSqM+sBp6R&tM'
    'Q^xRlwp&W=I*?^BIV5oC<R#^?e&D?|Y`G;!Y1}N~WOHY{d?PDMQ{+30v1SGdHh`Rq45t12V>;mLX*fS7'
    ';I{~*cNLTdKmMp<p9ho$nJ$(W*h-H!N~dJ0Zaz>7uGQ92`@Bn5iuedfrPGdmXA(N^b`jMF%DGo2q$FLr'
    'yNHx*?vkvWcf(t&St~m-PDs5Yg{$s_sha1h223+4D(mhY#3tMUZxJ|YIOtqq?WeX^!WFl|J6LK(x{tx;'
    'siITILrVn<MS>__I+F+cJN98|{zY&S$h&02xKX48d0`j_VN4|+{5E-U>S6(ACmP$bj)U&n4Qs$am&sjK'
    '%(WD+eN(<4@;2kYEy2ojCvst0!NBwIg9O%<(4bG`>s=JDJt5hLfr{saG`bWgGeurqm%k@X$4bwbx_O=V'
    'ASA+%A#>y{nNl{&!Zl?czpNv&C?+COE(ca(@fI++Z1=*u7~HLux`u=BNI%%Ql@_N;=D_Nz<IllEn34EW'
    'nhCmXitG{}-;!5kZI>K2k#7#|+!~T?3^gxASD8X`yp4w96cW4`JOF>6Ms;(FT-@RQRJgL5oW=g(58D?~'
    '(A0Ngq{7J8QhW)ql$2#M>x4`u;=1<s>2T~2KZtXeBg#o16roD<DB$tH_pU&9T}()XIm9lFoVm|#8;q6m'
    'wFCzIJ0Fvwq(s^hts{_%Dh5bHTF5dxX@2Gh7(a0_^d0bwd(<$wzcDPbEzC5SlIE&BCUX}djB!0(MO^3D'
    'exp`gIFTCe+}iuIS?G$}vwwxM4JZl`@J;Uh&PD-2?)#`e{>XO6cRSLY#b#no*HUiG?oc|)7mhc{#$_)q'
    'lauh?mO%MP9vh};!oZlT&6{n(?Nlt^kyLI@DBpohZd@ccAd#h+piRr;+7|1>hssHM;tnhmIG6J<2p7=='
    'k6Hp}vS1=3IilyK?(3Z;QtVetu?&V1hYAT4#x(pYvRYq<ruB$0&E!BS<`b;QHoep6ej(&oNT;eye#)g}'
    'ZQnz=1*+>Hxq!hG*+G(k$^Vd?4^>!Wk`x29=ulpnB7xIU2-2XW!-hglOH5nKr{>8za3}&P!YGqp&BQgI'
    'My%e>K_fMTlb1MYg+cShWLV{T)_4yiY&Gm>G3fJTBtXkjy`KVLZd%+62l`?Gvb(yH0wZR$2D80Njh$`5'
    'ipxu)z_^4AgB?oyCWZZ-$a;yzPM8$TB^RXUOT4I-jKDRg)US%kLFyv*hAQ|P7&MQt=+dOkEp+^#!_)G&'
    '1Y97~n(j+s8<+B%*o^PXE|&ClIoDB2Hsd<Qd{A;qnNKQleNF1>Dpk#kK?zkYt1?txP4h8x<Cn!oLDy~x'
    'SiXwhord1Ef|eM;*{OQ2(9X5IF_{*2s_mp%(-<84o$xuhL~hiY;`V_<0v<C^inzYR%GQX7*mvGhbeouW'
    'X44BlXp1sog}XoXp%r~Sh7<`)NHqxF99ZK8)(7QMj|EOaz%yK7oMRS8ZH~dTxLWzf)YifOvePQV=66F`'
    'o+1k{qw&H}e<du_WbvG3*&a*EBjfzFG2*wc?2?$_f<%>N$tYnpDVf%?|29&j#C7>bsA)281CDPuX=^o3'
    'pjT<yn$RS>(5OB^9Dn*kpv$XCBxmuKJd#kGVx!;A=bVOIGx#9YZ<b@*G+^44ESu~Kog{j@E6b@R=WrD('
    'C$e%Rhs8PxQU*_rva$=#?K3RSkif5h*jzTDBp6Ln?2R3p8x_L*D~!4!NwQ0x6QszL4Z2E64tHf;DJ^S{'
    'ic%c+gb#|;BQGRS#t0UVi7t6`uPc~itmN^tHR|(dZ8DtEgcY_^Bdpa(l%%c+R>8D64&8*aq)?7@owzg3'
    'f_+>gXr#cz%wTRb!rmxCma;sIV`fRR`}thuYzb|pk@^{5=BX8e6P=OIup95|le_3d`1SWdXGabQi=;zF'
    'xmWOCKFJbt#_U$!uf|d?=Vd)J#tI3pG8g8QU#qC!Ua>59)1E#uLQSl-%EF%b&iA6k9=35WyzyN)rGiE4'
    ')@wv)VZbx!$4a}+?rHrH`ff+cVsJ0q{64qS-FTAE#{!_azoqvB{nB??5*S&Xy&7um)qHQS&6|5|8DNkj'
    'y0`CbbSHwFBlS3V@6SVa39gNo!yFpWmzM+&XA7lf()VkDYf4QtttED<B%0L`cc3EfQRBy}Q_59?1jF}n'
    'X~^a#{SrI`U{JORCr@DN*f>l+IKCe{1$K5xY20uN$S<8SH&dRqk`EegC%L13k~?ZBc^4fech^#K*F7bf'
    ';U%{v@t01hcT7Wf(3Vtcal^(t%s1KTYIm)!zVxoIdhAQ@`UZQ~%cfI?5>fxhcf#OBFuCevH<W9(4>HZJ'
    'QoQH932`Jyy$9vQvXb?>(NS&UyyF#<a>bI=5G(G)S8YwzhMhVmL`v%v$40B%iAit)d*Xz1&_k!h^%v1t'
    '(FdK5><X%R#Pi?wJDGfvS36a1dC)JN81Juk`qGJUon{JWG!Tl3;pVgN!MOMND5Sg6N3yQd?^GK#sf>26'
    'i^{5~wzss)hIMt}L>Q%P`;iEZVl(ug=MChJtbFFwt$mtBN86lxk}fUX!dYki`{3QuG3L1RH_{JYj+I(_'
    '{wLJPM}9w#rW<-R-_hePT6#$A>G9{*p+^Ge)$JC)s$gm+%`cPI0-{RfCGZxSRuYPe?XVTv-n~^sOPSxZ'
    '@;PAD@t`zl4nH*qFy)h4ReXdu$hS7dl0msNmNsjq#~!CsuQ|DN#d*{}&ab|KW$ei0xP`^hmF^RzuLRID'
    't_o_ClNhI47&yNo{&#~b0!5nUxv}jL+@em&Y<r(Ly=dbH4YVLFym$h6UWjddsbe{%pt~f+s>N86OTPVW'
    '5_u`;D_`dlB@81Q$#<GozQALY;6=1Hp`0ob*b>}klp~w9%UY!?ZOg?)jQsT5c}Vx_hLcn$v4N&iInS$6'
    'dR`{NTC%Z3yUVs#_#ueeMJwaJ$;QgWF@B43O9+b@x|WYClI_~}jOKFQxMZ^1P})h8Mr#OdHxyH^CFy5C'
    'GM`st+FUp45>>Ef)aNxim8{z<>66bV(0^t#FUApY?nyCoNk$uMS0aY|w1z7sv3{dG+H5!GgVm|uTSDbY'
    '+y_eYBqdu%RYaX{j2_GB`YdJoOPY`GKs&hx!+%QhQpR{Qq${d^jYXBk&$_o>Rd%$<GF^EQLltEow@z~K'
    '13xZpP)GhcR$f;8)Tov9NZRPRLYJ_Rw+-xc5+Gz%Lz_j*FMhGisx#E%HJmO{vY`RQqyfy&6*GybZ3Z=;'
    'GtErc{ACurDrQW5l2kN%#XYfuYQt{Zu!Sg5yqt|(dlikDhZ1*gt+iHvBOg9gUR_dUMlPsA0*pPup25H1'
    '*C{c4;QDjw@TTc3ky0UwJ15@OIYfBBnHLqC)8An;6II3%&OZ3DgRM)IXfgMQ1L_D2M3{O6+&P(GmREED'
    'Q;%pIqcq+UVu}m|^B(Lg1cR&vkX0!a$d*oA3uOODX;*O8Bbfm~h1riCWxT@usJ+Tfjp4FYE5$f&?i4Pu'
    'w=-7-G(#2%*mnA$L{vU>M@kRoT_3YcasZcRiW>67drm3nNq&YUt8~)6>muGnLQt`!;%Ak2AvJ?ZY64TO'
    '{3SVUWA8=sV|m$`k65|#`WbDdB0Qf;)pOhL=v9sDWJ?PXaF)}mOMNcTMD1*UYf8?A#AoF9S3i6^_uaM='
    'P8L&?A8+u_lbBB1DsjmSl?&bq@TZIESkaAsr}K9ED#>Z<bls4a5}kA~%m@ilpX`RztmNd1iQHR)D8d6S'
    'V!6$A!2V1Lszy{dldr1p9yFCz%_Kv5%|<SAn79CKV}p%09oI(#*7r;=yO59KvWw~mSk5%QDqmia)R6Wb'
    'oF?o-?pBFi5r~qcIJX?)<vhFqQ$H#<auq?Q{WX`AE^;+pQkKjflu&JzooZJoD!JL4Ic2w2X-Q5S_^Oz$'
    'lD8<EI?X??vQ=~WY%<HJ-UrU!trC}{!*`>?rEBm?9d#3>OHa{jJ5822-ho}xkXh1zRkDdua)WWP{UPH@'
    'o20fs*kl95##<IQ(E@RoJrM6h!(y3T5bL)=+!pSaR>gN1$+`1Z#WEZ16|R#u*>G=1&E7J^x25)aE8uBG'
    'OReqi{N|hVmG-;THkB>BcDr-wBBPP^Wp|JB3{Q1V*6%}?u_evBqeiARqex#GR^OGew%S&c*B@?0V=L+2'
    '-974p{iREFgAt+6A#-UrO%|`;qO06`4BPXt+)F@>u$==)*~CFUk1mPPAE4YdwBd;AuG{xa-5KhpuA7!Y'
    '9FGni;%S~fq<wub>bb7rz&pK>=DJj~Oj8><@QZG3BJa7B&jIb3&cL$!!%@%fQ`;s6rOwcEJ;xjj$;j3R'
    '1H&`zk?9Qq^uQhTT&v&j4f~_M>5d3-Hv)RO2;M~i?M*o>z;-2XHj15zFX!Qh2rK<pq#|#vEpsrZqBlZ1'
    'dOIc;W99qu+pow)GN-M9<`%Ow{%QC@%6bH4pL1#)FE=k(#_ZNWixuaYf|aoZtZ#N!TE=5|?|JCb)eG4g'
    'E?}TIy5yxCVU861d`T|o+68r4s^fV3m7E0e^6sXBCqEAvYYSjt`>GA<mW-9tkW4wGBlue)jiu9n&cJ1R'
    'b1R#+WYq3f+T4Y(X-?MMg{YA#X^Py5JQ&?Z&eT}No9s@I0P|MTDt0C=<x9)E5th4<mAe&{t0m>F&T9$>'
    'HrF-u#KVUVl@}~q)bl@L4Hpp{jFe0Ao+?48xQRScz+oT<7@Q13tikdg9ER;R24#WXXu)zSyv0N`Fpbn2'
    'i{Xv66#6lyK?I)6Qfsgpp_{Cu)|3PbGC`_1rFat=TVK5fLLHdkhil5U9QzQX6W^zhfXS-J@=-_mbp7XM'
    'Ujr7|SCpfdC#=z|3iOtp9BdExx`sVcBb<0gEY<*rHOgT3O5xu`gV*(&w>Bn5b}U8irQO_+47q)C=arfE'
    'zNf_DI~rhomEE`hinFJBK}1wKI}S}2v$f<)v9JipB4$<OYZ38MZ*q)1^Z82{v+lg=J};!)HfFm7rC4dV'
    '*EU@6l}Vg4CKy2EJW@fB14o>R(~ve>qKZ<YQ`39D145Th=M9kgeL3GO(fH>2R)WZ`(zo>y3TD<x@LNvT'
    'U_#M|8By%+Bc3RbKmn?l&E}va(v%cg87|IZJ_lPZZQHAIUPB+1K_rtz$qP29o8r=>b+VnTs0mPTS20Ni'
    '7n;8Db4|@C^>;kFur)EFL>enU*E{!&51ZFD4XT<N)Kkx>%40D}emNJ3TVv%_F%1SwOt7xhEQ4}ut@=s1'
    'paGq;BU3EZ!J(<SH-GVq<V^+{zr=rm54HxooB<%y+$rT{<QMbHLq)Fz>$;{vQDc+0?=^S_dn|Q}ceulK'
    'VkFx?=}%|jJXT)V5uLxU)nUHQEHK7{A&>`QFuBTZrDWwkKw2qbK+|f7qHX=wftXyrhRW)%q@e08f|qE)'
    'Iz<ZMI_M#**3xA+FfgyuOKz{giZ15hc*8e?tD4D$SV5fdi*+?@vabadAcDXCp7_BLVk9MhKOhsunUE-|'
    'AH6S^i>s?OlgL`Im@2H^$5=W3-Gan~*SU1C0*LQoCGttqE`Zl~+TI4LTUV?w@hF}z9AHCURqs0zUGkaN'
    'w<QDsOx@wMg0);;*l6fycQB=b$*B;j<2tE@&Tnr>9UT2##0JWqCdOYKuB;DcnO6(N6H&aB1I^M(10*!1'
    '94--+m_X-1sPscA8Psy7ozarWpDf+4I4BZC{ki+mQGP%<t5_zgY&FZD{h7pEgs2p;f`Xi{ze3Q?G~e<*'
    '<N}$=W%;9*OKiyznPn)MjVc3zoJ|z-YezKhY*deRdj@>-wwW2vxS7GLiybN|nip~|O|XJfyinfDMuFt1'
    '`;ok1tH@g7@Vp$GoC`(yar3^aD5NP7C%iDW6l8pz^VUu-f)KS>0_y`M?-;;D`?u?O7fWVCgEPlTW3z)X'
    'tLgNYKZHIQ=g-lf`qd*T9L$WO`e(H+#ep!i3e$Wf>Ymr@C0cJn=yx77Cn{vv1)NTNkH-F#DlvGNk<Vy4'
    'smB>k+!}ZKL@iJ3$?QxPEN9{9;WrPD)cR{UO)7aR?<k!`xoV*inbHSLSY>{Cja%qoILzmZSuD;mBCw;b'
    '*tyh{s`4U5rLvk;R(MxR03#K#S<!iPUplfb+KB=cOiPq2vP-!zA0`*27^FY^0TVAgwN#1qt3yf1N&yHx'
    '0t1WRWZfuT)*}ZcVZr}SF4t|nF0NDfFmmR;v>Ts_cY?7NK;AT|VV5ymM%Ll7sQ6u&+r7BK&nQg<=@Q@U'
    'K;W38SQ3n-!o|fm4hl5C{jTu=?#-DWs|bIdoF5BQHg|9#>wr27pOtQmN@-)w11W4gK^ce1lJFp;Qu1zJ'
    '-X7FAANx*s5jFm^5DbbWmQP(jj#yE0Q1PJr69nYxxXW`AwqAHZ;}7Bdot$uanHE=c46Y*1Z9$4*AIT$Z'
    '&d*)WNMfd)ZdEDtS}h3E9)uFA`sBDJL9=jV#r$Q}E?+8MUI?XRzjyA9IIQX~dY;rs8!Ks-(VD0CtxpXo'
    'tzwgH(Lp)nEQ9ipzjNm@>qwa}sda=E)zU(X(?t{~{TY(XIh0|^NoJksvGU>42TKX|Hw{lqlv>VuNhM$6'
    '2q0=M1YcCCaz(^y5);DizA^7whLy#5&i!Y$ukl(35DbR)d2Uq!TcrjB8P00zR)*{42$VefPn#2Q2dGKf'
    '=S8+;RAk-7jwbbEtI2;`z`NN>kqqz?+RQ?wkz{VwTbJ8{Z6QkEx}_wsu9AjRM56unE^@JgY<IQyD2YP&'
    '_^g{#t_zryl<*^m`(xOODgx|G=mT$pbyAgR0<IX(BgIUo1)^?ilwn5h<va|+MWmpICLyyti;ktJIY{F~'
    'Np*3lxQB5?JBl~#7zQ<Mm!HV+-G3{sRf0=B)?E`pJW{cUZFHIRUQL(VkriEA$ub#X*JxP5matTI`H&aF'
    'Q>53VWatZJHc?2cL`J(Q6M5s7aKhsrmf(V|%fIH>r<=qOo2ih!yhv`UF4d%rm|zMLPYZ4P_q66cUoxMQ'
    'E5&E0PT7^;^t4Hpyr@zPT{N5&LE2f}$T}ZQ&XkjKn}8ZYWz3ag_hw`=5o~FGd_0fCif<9qJmAE=_fa=Q'
    'u-WuL@#7jbs6`AhpdS>ESD91gqUzHZHm}bS+@hAn5wdDJOF9*jFoZZj6uTzP%aAgjOxL1l+ni@)np{$m'
    '=gnpIe`ZWeC;GynZT=isPVM>BBTXu{eyThhy~9+_>#Szv(QKBLjC`6kR$W&%ve)aG!=W|QG`(kP)a#7~'
    'hNcgCgPt+eEX{EGHq~sSXIWGu-oU2Aq3#lE*zfmsV`%9c-l1Bm9O(|Vet$Hwt-j$ouCAHX)a>5S@a&%E'
    '_HAc0ut(m|GpvCD{|{`BfQe3B6K14YcHi6-?#kkk<yTeTy=^a-u|P?6_o}pSk?3IMV6U4nsN-8yDgnvE'
    'o$+gv`2}G*PE@D=QZ*#87p%hy-Uxlc@Dn8$l^cMDFWzORy+0+hC$KJd;uEWJ=#nee7qJdZUiTy$w#~<t'
    'zUBE>($Xbs!%_#5X|8EER*ACR?$R^_^Z7#~8^wqIbKR>1am_5QzW6N87vtTN5U*{g;?oPm82k_HVFa@M'
    'VjeC6_bk4e&^B1WU~0Q$e$~M08lVPT@Kc{o+`Nnh|7^|(a=)w8I*wsre~u#i3ErQ~23|uf*)&A;e)dok'
    '#8T#KyuzG<tI5=u1e*=o=A&|c?%sCT>XI_eSP;84AmrK)J2M|zx6u;yb$LUoytNC>uwx~DtDTXeznfFv'
    '_i%q?DDIt_-VGQD_r^x3HW5Uu<9;HI_Xxh1c#}S2<CfKZFsycLSFJOvu5W8sl|wVEfIvwIjg@x$ES|Gl'
    'KFLp3j{Cu{6wHOFag{DbAFGP6{^G1uAi|WZSstM<GD92Ss-mpEKvaD=?BXA%+=}}B-2w{hz^Xuhw-R+-'
    'NgfHS56g*5IaKyRGGGm~({MsdZ%5%gesxu&i5-Ir<O}2JvSxpKj;S?!k<}vz?rR!>BZ3%OLweF;h3BjY'
    '5Fqai&oA3ZkUp9GfQQ**asQ!H-@n_v7}|vtYD@?%4g8EBnKU%A)G4!E$;UaQx7)I}v{}i#L&3Zwxts~M'
    'N_tA_6?7|!qR#Ttf!7lSKV_7(#GPs$DT=3--Z`u@`(3M@+iIQK<}ZUaB_I9iV!8ra9VIG!4guih+;=Ga'
    'F#~si?^gTg8rbp5qenn+9a;K1@sAo<PkQ2w?g&5iW}s3@D7Hq@T9%XOvOf+ApJpwH>%c7zmfSmLx1|m_'
    '8`NKygyRe>H)4k_@MIKDsq%wQKghE7o|E_f1<PUs(sACgVI_p_8)LEEao8>xY&ZOMN9@%wcU7(`v178O'
    'CGQ;6jD8nEFw_*^I7sRz6bzes7%UA|8(sC|f6_(KT1g~D-REB-qE>P8x8D^#bl8RIdMCjwSeXo5FYm9R'
    'NcHjwD49(5J1W@9ZLlXFsX-XfhB6nPhVx_MT(&dWgW*y(AMkr@Ac1Mk4bW6<_sv(s4QDa|y`X}*+DNiV'
    '14Gss?-s%Fl=?f3B$|Cm`dc~NZj=7*ECo+;8c6f<Te|pODF>UDz;`8po0PvR*YxnA@@q<G*!qWloK1Yk'
    'k1_DWit&^Bi4S<oXX;0It5osk;gsF<!CN^JZe77^f6cO9V4DF1w}^l*B4uB~S{^b+eaP#AU`0V}t9OAn'
    'XZ=W2YF0QKG_qNs8N{6+)*pu511@u2x6Y=0m60|pA3^*eYJa$-bMV$aDU1?X`;Ke^*G+LbzS^r)7s%dU'
    '*3LJ`cy?d;*^fWAvsHEWJDtWBg|8xq=KwbY_WCnOh^R5#&h56F%(ldtzIS;xFX!O}h_DFV&pdX-MWX$U'
    '@<WnUW=}Phr&M7H-_OjYjg9NZq)Nl=lkT}E*43nbD~E!bQ!t5npDmQZ-se?zYZ}C*WptJkGflHuHM1+C'
    ';7I#ybk~w_5s}FnJ?FBhEt*bguh#o6tyo=zKR+QQmUYjqo-el<ZXFfL-6_WY?BDrVKjI3lnP}a8Vtr%`'
    'oS|v!rluQ~V-G#k8T1LEL!DYZt?zm^{IGS;&_`x}L`_@kYnpE3^<LBJZ*re_=`OKBOm|?}wykMB*V6{('
    'pg$TpBV7lmjzOFOH8guPq6YCSoQO9Z*|aw_i8s)Ox@Bwvv+^Esjoxrsk15fBr-bBj-E)gvZc|n<AAuZy'
    'oKX;+fkQ>v{F+th*l}Z_?Zliq;oQa4wcMgk*_&@!(R1k#DV9$eE3AsjBk7}0lG8K^9a7{TPNfp#%$bLi'
    'iLBA^^^E-f>IZhr)g}}FBABvDrs^bVwGhpS!?LmTLFe{I@>vLV+u1hHLd|nfN)Z$PJ$*u>*bhWCWRYri'
    '6tI;f*=Dui?2=I%<<n-_bmi!<MaKb_BRk9!+Oy>C?W>W=mkUzGLOrQ)tK;#Tj>c=%q7CBL0eKHTHP%bz'
    'QJFdHqe@e5RxkOUGLK@vMhU*FD5lesDY>9yWuI4NRzHx*I~dcYku&#awLD(oTdbS?cYYApiL9=^@>p;V'
    'jwci;pzU1x6L(H)EGdbBH!$U`r?k=!T7mi6&QNQG|NKcVQrN-9Vmc*dVRpvfYzw_0c`u5p^D)+ls$n<C'
    '+v(kkho+@N^TJ`rvZ20ckSrN?FBn!Gf}}PHcEWlwqd}>w&DJz}Nuq)|TCz{Yjqr{nqoOREmU=I32_r*K'
    'aYX5pPGU6W?Z*i;At;(aJVSnpFxJN=-*0ax1SPA}OsUa~e8F)oUv}DzhQ$4P8`LkIQ}^XOocckXwi<UY'
    '`*5pOye=+T{>j^ex>nZR7+JTmv7~unlFHOxt25%V3ZxQj%xg7B^Ri$0G4RhST9jp)t5{~V?YrZ&*FEEd'
    '_zDB^7=~y|s}+B1e%rrCeJlhjKFKJj%a}#9%w%Dtq~xp2=q$dln0*c&MtsCB3k+kw(G(~vs()Rh12C&_'
    '&F^I-%i=%pwxnzm=NeBanDLWRXjYQ@Cr2AdkV`uiODm*ODLz@*@N)aJ!&Y4hSDbYi9L;8wVEc`n{mI^v'
    '3FL_%k!3h;@~%u!k6ET_JM<dgiSw><UZV+0YqbNw+nb+wY{q;+?vA}nIUL=<rmpmcl`s3Tqy5N4Yi^=#'
    'AN=L9^79O9F_~Y`xCVpq0c37zA#5{6^-rTV2h&w{yP>@8MfpR?ZcuUbwmf&|`aaR)?yU4y{aH)3(RXK}'
    '7kY$60hvXYA>Mb-*opPc!!!A^imeT@PKT=krQFJ~kODCu)Wa4u3_l`ma-7U3$)nspSSj{nobF6nnn|#z'
    'l_uP!nhdr5lUqNCeUo3|HK-8pUGXeF-q?vu5ZCbDVm6!jKu5UwO61Hb4OHbM>8ZRWTo?w^92Mr=k$H^W'
    'y->cv6hQWc!PYmiTFbs-YAuhI<KHbvjHhy4<vS8x;&0NDdN9WP!u~BFFcaFfhmM?ZMt@DOlG;s=YL7@~'
    'p>sJ_UY`W<z^p%<A3aXHMc1pM#<OKIr=OJ|yD?u%hPq+v5MejgxTz3`lc3EwdBD(R`e@6NXTZit>*NB7'
    'g&%#)--{M)^dkX=c>U_>gQ0>qRWY%KZY`asWd08AOP9_j;T0as!sfWxB0F5b@Aeh2wOV^U3EczEl6`oj'
    'vNzRiowcDbUMPTI@6;YQ&lEX=%DsDsCL5-Q`Oy*Y(D?hb%-yF9=b}jWFMd&6$XzJ5wL!o%VXmeO5F@{0'
    'p3_*CX2>K<?Y_T-@j|Z3subKka0HOL*39scG$2_oP-bnSI*{TO<YBz`!4I2Ind7!23?ks*OQ{JGXavWN'
    '1sQX4ezbd=691VlaA8<JAZ<ckaHiJi^Q}9|x2gzE0u%eedouCyT8<<R&N-Z$1a)h}Wc-M21_fLR77gpU'
    'C}q5BiF8)wm9pxwO6F5aq^+*96Z5oM(j~VQK}(DM%{F-ZJCUu7Hg`arQujVNd-;?T+Zg#ckd_3-1+>&z'
    '=MRlO$?yVRE}}~u9S#4S$F5w0jT`ZbC+~gw;Q)CUOe@6)*LzE-EU}AXqG=lN1rGoW$AGu}{)Ra3>U#nu'
    '9emJ;-mJH!Y$wZUlPg7nv`{=sHl{AQ{VomDAUwob#bN3Q6k*qqFBQTp5n+$iykCOQrA03DQu6Z>Yvt_8'
    '-O$x?`ee<P&ZUmdymxqslMhQkw_eez6z1|ui+_tltSw=3@{-h)I@e2_GorBO+rqVCKki)QB}b0uC7+{c'
    '7u7JhDrmfEA;<_b6My12nG%o>sj@9B2s~MWE)U>FdAB9V`z9vW<}~bz3MIIjo={U?ZKkG_Km1|am3>tr'
    '=uZVd_s-71@*$Yw78j=XNuFe7$I6L|%>GytS~`$(jo_}W)`kMIm06j!62>cTPlI>*;p~#kshm9BhKn>b'
    'TVdj}DFLz3MQ=mv$h@Cgl-<w6*mp4L&YSqb_H7JW>0!<bKGN|=GM!DR#0##Xo*K_Z_*7cPNfa$;TaXa@'
    '(XFwRcn+k4<Sy-!0XtR`g}V6JI3|V2zIMFgZi?jF-kVh?7<RVafClD_uV=)jljVG|h`gsRFUcXRBEhzU'
    '?Au}ZPQ@;<71b6S=@GjYVS-kF9|n{i*CLA4DJ22yFjxWq2;bj&kISW|5lXV;7?b&pj%tS!i5Gn;`SFwF'
    '5)s%{>^JNN=}y-owhGO_Y^(SW>K?^)mx<#7b0gUSx8q-ptpsJ*X}E~#**gk;G^-Q97m}pXbs7XLFoxDi'
    ')I3<pD7>zB*{4aP@@^^$?VuQv$e=@K=-2d0&N+VKLGUr9XI?awDUpm1;v5`kF#pC1%ci?0=@;_^odT~Q'
    '6IGT>C-9*bGVAIEfVz1kq`!6~uEtr+=U{uC3K6wbUF?y#Co3p)+w~kCCU{dGB}VI*oqkAP%5k1qOS3Ob'
    'V@t5yacF4rh1RGm=e~V(RLIHepF#z+=AGi5_{7p(;`JW!VS$gfzmIjZUoFQ!-o!mVEQ&eF7pG);%Xj50'
    'x0)$a)1a#?!&Bb9qg>lh{#2{jShH?&b6)bUo#Z?5ksEN4Z*)}87$>5ed`f2%awXhk3ASrjk>vK?jkCR@'
    'f>PJA3$GRmoJHtzbEd$Kc2Yu%(eD;GC<$DZfFA##E@rH{ecr|ArB*(h`k)+5^$K6fErYwZGUQ8i8=R{<'
    '3hZW$LWD2z>3*PW)6$?^E_~11?@22i{JRC7^@jmo--3OZfB<Z^gm7UQjnxp|T|r*a53z}oyh^db7n?!a'
    'rR#I8lO`_m?xarIQuKD~_UA3hCD)=$O5?U4z2xa17&-ZQI$NB2>6mouc`x-7FVqP{XjKOcK!Vr1FE1yF'
    'H12bGxg?cnSLNka6oF7Ze;&oW31}Q)gl=1yX>3=yUM^X8Z%fZfEC}AL-MS02b;tEvWf-k8OS9h_lXZ>7'
    'S_raB4$?JT(O!<(x+|-72S)4NmrJf~vhLbqy~_fcwT+TB=IXEMDl=7f{mWcw!5m;wOK^DtvH;)G%-#A1'
    'X6ckfxuw;+b-Yl5v3ysy@;xu|wt=C1P&{Scb{Fe5J;N8$Fq#Ir!Y(rE&`2u@hx2<+CJWlIKah6^q)eRO'
    '3d~TOr4q=#QCA>6hO3f4BZ=ISwa6<~_ZcF3*&!@rS00+~@G4EI!ENrWJ)F)$Y`U?w(QV(=Eb6(o)f+m7'
    'rh5Z#WDok9Ve5vj_j;OZ4|?ukX!WRT+O+TXdQ_*j);D#%Z=3zzE!^CthPRrb4~Gu%499WJp-X7b^ahsI'
    '9~wi~pq61c)bxf%Z{&?eMxS^?cVrpvNH>SnvJB6@4eZLsx3&5y3!fpoh*V0bt=;;zKqQ$3Q;~-z2ZY=U'
    'J(c<^V%QP2XL9&z$8#{D#!6jS;=GxS)>UQ`0+vn^a8zfZAE{F^YybEo{vO1gj=a_VBVh#IHt@3?0IE%t'
    'JD|ztNiwBKQ5oWlUSMWV#L``B_K|I#>TgB#MWU?<xOtkdBKhlWXnxgceeG_MD?<p6N${RTU}#_~KKe24'
    'Dv|$tTB9ub`hW|ov_@jw`j_yd-Dw64;81D%flEJv$YXnq{&sD}#%PpNrAmXvl+M8qt9MXwV|a?S%?l%+'
    '-3mWc9)J51*VF!3Uo$Yos2`QTU|X(!@ZI>bs{q&Y53Z6AE~$TU8F!jnqVFkeuh9I}fE1BH)M@yhw&PI7'
    'GCA@(S-6Y=Ag=q&4>*k6cbZw|b$un+ggn@tIM|IeSlzFU>&nNhDDI&$B_G>bZN*ZM2fW_y14VCc5sWXB'
    'C6tT+)M$0r^GTWdK|7DCZi1<wYn_hrOGO9Dd-O;?-Wow!6H1^s_t~6!{>OH<FCEEhVGFI0NcEb4ccc{V'
    'L?`T8CCJI-TxTO*i*wRwVP8_>;;oMkU@Hh&adG#Ff8ocnY%K{IQld88&C2C0T!J54djRY(!Be+IlL@R$'
    'iB2kYg;%EX4is3H5(_ISL0FgFCZWR)g}O>W;}7Bd9rl^{F!y7M@kYW=UDVo3tFDDpm9gG{&woQTz|SPQ'
    '@bz)<-k*o;#t{0)kwXLe5~zT7iubeA_ZtCQIF37|?!uwphg=vZv#1G`U(C%0ma~lI%i42BbNN6Ar$Y8k'
    'Nph(ItfWfmH?NLmgy7X?_RAwFfR?VKv#}*dpd_>bs2o@LP2<W9S0D3FB|}`WAmE#mAbxvK6kUEBODzbN'
    'a3bo$*X8KqHTo5IiX<(q`2eZNtN<Df>(obBN22V&9JfIgZ?rwUY%3tk<BH90q8hTjC9rdjCLhqu3Bvgl'
    'p#PpSTgM6UGBnU7Cy9f)bT_B(DU2RmC`94@plHQ4r;$S@G*bLnmAbN<E7jDFY%HBHq%^}zP(Nb-j_c!&'
    '(O(IgT&Gf`IwcE`?~(%mv5pxUM2I34|3s2#CIFDnea?wfHG1dI_UlKr3Mro;6F!i+tJ1*TZ!(|}T?Ni1'
    'n1H~h?dGBiJl#TU7jI7ywbM{%O`t+@Cgq@IWpLcMsCl;gZ9f=iq1$vqH39SW93<wR#FNIQpor?t$&|LI'
    'e()U&Fx8&BX?E6U_boAyeClf~TF>6BH>8jy&%i}T73uQ6hQFp)?Iod>XiitD9RXg#Jh=eheIGQ+@}6Kn'
    '%KeUHv4%r`k!SZ)o(YW|`_4O>vr-u$FacM0T}$#&EU-Ch;9@$Fp2DMTr@mrMs2o$>)DuiNcR~Vwyb?7>'
    'f!BYQdVtFu`HDdLh=q$EEPXcHe(_OlIS_|2nT(q{*sSaJ7dDmG56UhR<u^6K$A0HCSjZ2!m3$#f+v%Y{'
    'Tc0D;8J#=819*z*_;{<Kja=toIP@6}F5=6!*6Dl>$XdtB*{(}p2iu(u45!-rB%H}d%f^xT2n{FcVDskQ'
    '65#a1{rXXWrNLRJ^ZoludOIkhQZ;>fx<lSbY8V``c6k+D{t5=LT$oRiE`0^C;&M`haC5i$5{ogr%eND-'
    '`SZ9{u<!hgx_avK!ZBVp`Pyz>LwL{K80BYMs_)8n5xD!dbc>Dq2~E0N`P3-pA;?ILO4cBJj;2$g(hQ+r'
    'VS-R2s)AMYz>9n21M%a!_<02srA8A<XYGIlA=eX8ZS`3?RC|eDpAU}Z9NdBD8Jwo_n37^6jfDlSn~B(G'
    '(g?4D=cUL&vX*-zNsIF0D@I6u^q2$=olL0PO|)SBAX%zkSj3OFl<hVYJSc~)GV$?w#;=m~xbJaeSQ4Sb'
    'lW1iGt(LG;THZZ1Hu3fFq4GRb!ioC;m8#-QC<zubY|+bppDRR}fSQ=sKTc$tQ@xLta=~Feo=}$R<Xrj_'
    '7dCOMux%xNAa5IY=3%qq%=?{tn0dkqBoqxqd3J)}_Qi~~K+HFS?eZ?cbewPD+=yT<sIiiXEp4I60s4}K'
    'T3bMWb)yDYiqK0E5&Q^K61mCA3l^8wABS^Vy0!j2rlzmCudeH!+v__$&7@k-8aSF|jSQ0xEzQ)2wq?2Y'
    '$g>=W^c<@<w1&E;jcCs`iK%<$XlR<7rD88#RUh=dKJ|2}d73`Zo&M13djmQe7}iLm#sL2DMlLmU%_Wv&'
    'TYcLimf`dqm-Or*8Ekk}z514V@+of*jCV0$M~~)na@9_=eca@FM(&<Tr&A~2r^VZ3v+JZ)@Z5Pgdx{l3'
    'iXiKdM|}d@D%pNH&wi(v-aVpg<GGf#Uni}fW%M5@Hbx*pI%BT=L~;Fy<sC=PCFq0+Jy5`XP14ec8-ZkH'
    'k(sE*9$}h2sQw77w>g>vb<D2TY++A)M=4*^&s^HEa{RjmiR-naN)3br8j0ZtO9x(dn8(U%)<#OH5lV0A'
    'hIX!L?0@-_o|2FLbTNI3N2SOohA9b#%(UYCxGY6Cf4`8GF6h+XP<*kR0X(YA?sw)vb!5Qc4mgK`VJG2I'
    'a$Eu2H*XJQ_?Lw>dCB(T<xB>;tDK>HENp*A7Pu&;GYsOhH9kzB|5D+gmH#N658lgr1pklgu!ods^Q#Ea'
    'ViF5-Wji4voAA3P1IP#P)u<TqF9mv}&@Bt1iJ9_YA0%K7`EEQC?~8Z>Y(@>u3IocTHOIM%XEA}>cBFBc'
    '6xK<3lF#y|Ya6gsf(PubpSX=g7V%{`$2)h*D}PGokum{q5>EgyLH-Oqjn^kNXv}4O=P?@|t5344e`<XT'
    'C&}Qp=_Cv;BH#&y1Pc8KzOcCN@i2128SQ2%{@a5TCFywaJ`%X8D?jl)iq-a-vv&A3D|t2!gCW|5O0=O$'
    '<^tb=lP6>4h5cLV#972hGN7c<z_{FrUA+HDGCaIuNiHbs;K_45WJ3VL_WTPBeDFSw(sxGwjnNcN?#^xA'
    '#>?M_-5yBgP1^421$E>p<b<3-f0XH2EDrqJgcNIe2&MiRvKEk$EzB+%{E^Beq?&yw&wxp2Skz%<4JaR{'
    '?;h{~Ld}B1nPk2fX2!K#8T~j(2bL_QJuqC8ka(^S^NX4n3s;VRK?6MYXCZ04VS8WDjQI!(i=h`#tT-4|'
    'XE|rAKH?P<GTTGU^5$esTp$-bXYiF-%_P1EaUP)Xgt?}GG2bJ(n<vAYLURtI@7Sp_VkYMz;Nd7&@fMRw'
    '65`<HDDd>unJiHB*VvRG3?2yU*CCS$*t}{}_^PbVSR2^#WopL1QU~UzN)n0&RP;d4rCT&GekO8c-0EKn'
    'S%G08i<cSuik#%J@+4eH6Z5&)RLZTn7?lW1X>z=4F&dwLyF~I>BCIfvj`FYu?+PHr5$}sqVf)GA(-lE$'
    'K)YHI^V}YA39GUeF<qd<1p&)W%!^0bFN#On=%93KnQ!?MYaC6I)$V)T#AMS}z7mBKlt27|zb#}Nyf1!}'
    '<|<Uko&#l8P|bCY!pgi=_wwyhg929AEoz_uHNQ8kRu`a_G-^dLUk*tohF~wTEF7Td_x_Am`>S)SiWgpu'
    'a;KOuX_5aEu~KyY9D{NAQ`L}U*>AcW$&IhFNtZ0}QF3r1W|-Bqtg+g$ocOzx#pfi15D*6i@sLP|+Gp1#'
    'gGW-Ssl2c&K={Qkl#1dLX&|)Sxj)V>Q!%-UGg*$$3!dZi;8%$!{79x@l%!0F-9Jp=c2}89+XGIGt-3iz'
    'Wphj5B~i`k3i2NJ_Q0}HI`@iLlJv0ithm<Wr3A5zc(w<O)`%REV=|z!tP-QV+Eu{hAo*+8j~w6)jDwuA'
    'Q?hD<Fu8fJ)W5LaTDNn}uzjg0LJBw8k**M(U)709rb4&qZAlXV4LG<}dgN1PxTayOgK|Wp2AV`eG1=Hj'
    'CoOhidCHQK0K~*sv-f=woJ9uCt|ahdaTb%pz*?gmeJ5Oe*Z>zxOXW$D^m4g835BMW)+OaKX1Gg${_0Sv'
    '3e;%ji!pbU=8*id%(-F#lH^^w2ZtrY?|z!gB~8q0e62HtwukzKZ7UX%(Zt<Tga~*SNg_wIpBl0>4l1pJ'
    'dlu5FouDNyV1OYUF6Iu69*WW)XdSB`orvXrMAcU?hF-sKxP8*|dL|hT9DPK3mgbncPPE}*FmgTHG);}@'
    'eXnQtw4UX-gI>Qs>f5I0jYj=V6ZDrZVT?50CVgTV#5OE*=;)Si4tuWWS(e#z20hZ#U}nS~fygs-+i-e4'
    'YecB2Yo0-dqv6JY*IvV@eFvr`cN`g`)F0!zTYHH8_jJzs4Ud(5UDfut>YGs2La5&AT2hCRFi1^QvoTgw'
    '0UOu6Gbk3h5Bg6OS7Hf%xT8}NEXZWPD`otNkX8sGk~M3bcOY*t7><k4*MT3)9F`3%unK4nBD_!R%E7D{'
    'pQVE0_?$Y}-4~bNeA$-;Miy5}TKE3%FCTnIWKz?g1p)l=U;g)h`Y-?eAOHG)|9}7Xzx(6A`4@lp*Z=lE'
    '{LSCqI~w?Nmdw0b>=()Wg)yrnGpCL(GWn;p^?(1L{O5oAum2sF%wI(DE{$X?nf^r*e__W0JDy#JA99^m'
    'z8J|rISTl@zy3e|_)q`cAOE+1_NV{q|NLSh?_4aWWskpz<}Zv{6wO)OBDoKo63Z76{gaAg6eAeic>cS;'
    '{g;3IoB#QXtlp)p7De2@i0Us4S`p8{linCRGJlCU|5OR#PygnB{Num+U$}t&)4%%HfBM(|!<Xpu-O1~$'
    '_r({9{e@AB5<72JCv@^fSpUQ#ADK0c@sEG{Uwo0yJCx46dC(Wh{DmtET=_T&M(3<(RS_qKA1-O2T!o7|'
    ')umg`Wf(?O{UYsuYC)7g{fmG9AO5Gm;i2xlQU3q^-~a57|NP(n{eSz<|McJdUw{8k{?kAGXa6f#3jfbP'
    '`H#P7gcTa0?hy5<y&~oE`t9}g-pixY<L9r=&tAMfeSCa=`r<cd%AxY9bu^nj{B{!Bc#(k2ol9)Qxvp5d'
    'V`(0xJ&S4v8Q3N@C>``oP1np(&#-l?51;C;<`L>@dQUfXk2?0yu^l>aEQdN9<bN(D32TISZr|*UOw;WV'
    'cchP8V)h(jnpD>;;y5nAA{H?X#~2LzhCy7{ar&O&65Ab;O|p|$=Ldhy>lx;&wRrv{W;d|&i2JJronO_+'
    'vR?(vfnP4dxsOE$-aPRmCxi{Ydd%Ow;-zAn0($k7_!D;Dr(VUIRbY~$w|PABi=5FT>A?Ib!tSzlYap%~'
    'eiE|sevRRZ-~VP*HeMz?`Rj@3ggT&he(eWt5g@+P0KCiaL-dq!R@4|0FL}8|;3Q544Y7{^gWR*2)5cbF'
    'fxjFod{@3FGe!yDl3JI2ZjuP!?hxi|PG@9J-7_ru$ZPS{q`Q2XKe0(?@K0ey?AnZ|%UNep^=69ew?h|5'
    'H43LxLA6}Nz)TILGiM%7CbCAu*AK97&bu~vffvD)-HlTxNu|?hMjZHMtmwmzEO_|xy)uh!-B_o^n{7wQ'
    '?yF+p*8zDCW8>wi{mw0V=59TYYpLi-OPId!yon#s<BtUWM~Qd}`M{qYa=v5qDw7)Vh1hxO(}|l$5vvt-'
    '8BSm)_Pa{0d+M#9bE8vzN3T9$sbCd{I|*is_-GM>#G3hW8i;ADtW`=!?h^5(MhkoD$GlCw%2(P^!{Cg)'
    '4b+9L9cvI7?^DXh#aqnEwfr?~JKpM!a@mfH-PxCn`fnC-%=>&6jU?<;4M>{cc8qJFo$qIE9h}%ApxWpv'
    'is|%ZN-pU3#Ji7@LhY$owg2~6C~Ts-)Bzb4f&5Tz-QcNsA#g_y+Fkf(yK&D}duLeDjk>}k+q&v?tLWYp'
    '29>`be)L1JrMi3oGW^Jf-N+q#b-QrtcH`6S#-+OhFY6{JOLW-4E(P@}Gw;~ZYDt-A(#j-Ry_6#Mh1xmt'
    '8;lg&US&SAl<}~~4o(m$vSwe8!nm@Uh13hTR}}arOB^6!<JDX@k*cjvdU14<{o4|raQArspxU$MuM!2M'
    '9_3N~{cd4H>&-sjZ=-W>=mO1@w6n!>pjv$NxzdVK+Rv5yEQzS{dpxdcw9-|6$3xuQhQCWXkQ#!M8iCt!'
    '0ItFK+dT=twXS92Mt1P+E@N*JF;h44b{B!S);Hi50SC1&Xp9k-ViZof#vZNP4-U`%TEz1j4d~rbJWpac'
    'PjWPGH^IC+h~+gL%G)54cYT{sUUe}x{>tG(ENV*U*k>tLT@hweV?PE3v2`zlRskjZsClS2hh^<|WJjJ='
    ')^@l(^@H!Ie{oskB)~K~tEqPxMey1DN@hSB6x>%8h8t{C>e-)Qh^+k%TTX5rGR`PC2;&Tl+?`<sH(^0Z'
    ')NT6^`b%*K6%D&Q`-zcJRdWI$AAjS!@#XfI0YAY*SK+F&i4aTSH-a|oXNr5hV)NN&ojQk(T>UKTk)~F|'
    '{XJHLmB**~Px;sb`M<chpb<-)mNojdIwLMKS0wPeggIer?dRmZf5EJnS17FWw8^D+r{3|;ZdFDj8lzE#'
    'v15I4C+eaRZLxxHrEanW)w46rvwOv}5@pS*ohG!-x}`(`nSnD9Z-2mAI;mBY5!-$+E`~5Wk_i}JiK<MX'
    's^X1qdV-8+i_!L8ayD*mIJsWgb!r8Cl`!Nlej$kLkk$9zo}8p8`ej`wWh4m}LrdO_Hnta}Ihg=(a>bqS'
    'c7XgL$q>6A=2r}YtnFukb{6yRq@qn6{kEl8w`v$XW=)XWp*JqY$q?juS4pB~et?X&b&gn;2>&Pz#C>&`'
    'j{XV8e@`YpYXT}MhYS|?#E*bjfEED&CSI#~C|h?EXys4*OGB1YLF%rf=Hp+Zeeuo0$DnF4$0HMOl9QED'
    '8jJG)upN)5v-pY)E6H1s#``U~a#?~LEiiu47eyY|=lS9&VTyd>6%S_07(UN-OQ~H4vJ55%+e=MeQXcCE'
    '-dn?#TY{9v%@R&FcgD*%va&QqzQY)6W{@}&_*G;u?cX2M0bftU`7r^%MIgPapfvdLM-^MYp)AOBvAn=m'
    'dbCkGB};Ylfl_d-wvO88U9wWdM?fl_cI-Qo(0R9us6J56y)q#s>B`+jq-1lKWaYdY-dfFC*^zNV>K!Ru'
    'btg>KJWn-Xnn_VvckduJ;SR8dZb>-kTwz5fwpYRxx58PQUFkjso2QCS9S<!PEEEZ%eCbRc?C;ozrTG`Z'
    'Ng(f%4dX_U66A$p9E35Ic<|fg#i@%0n4M^B%Q_CaYd5R`16?L}RWa96y!K7`e#qO5|F#4x&z;DHX$1q%'
    '!w(Wzw^g6yMZVre@!AuTeHf^CUPz-$aWYfn)phxM(sZo!jH#Q~c@IJ&{1`Gv-jXS0qbyug=JCrqB8y@o'
    'BIR;mB^GZ1gUfa=yo<rzTB&O|2#@rGom**fs$>qVt~&l4JcJpEFQu8F+os4a@$oHrMb>u7VH5f0(9W$P'
    '*~U=wLUffWB*)umC{7{4i@^i%_i0o&r^v+}?oWj)tI1jHAO5g?Aq7o+Cq^oad@aS75KBo}CbLe+WFoF>'
    'Z=Vjw4)KFHcR8Y*^g$7-G>-xv4}1?RxL-_2ggL}6jhy-a&)&OsxosnhqTlCNFh04{(%s!M-;egrcpTeF'
    'eDbiT?PS(DlPoO|0K2uV78Oyl-Q)3pKUDxokrXBI0kt!G?Oro+w?r0zszSX`sG5n}2A4+tT7nq-yBQ`!'
    'X^FJuT1O!jRSd9(wvgrar1^*00^=tPL*EOTagQ3N^f!h@`i@xyQ;J-br)0%&giBn{xuLFe^e5Dw3nyB`'
    'oxQ!kScI;mJ^MG5ZNO28fUirRk6Q%<rSCKO^;bci85?VJ7Ecp%`lRK?>^(|H{lf8>Y~1zYwsI0a>p7@|'
    'ln5|Y69!=JH*fk5cdugkGfCys3FXfqlTR*^Pau)CnV_eZ$Ac}_hYyVx#fdv?nFYOBrHgcv&GD#ZLFXGG'
    'GV&w(i*zx+8+ew;Geev<fz(;223Z(l)5xpHli@nFs7HipCXbA2KEa-B)6W{+uY?>c=~Ru$Po<Qs-bt*+'
    '8K|yD`2`H2$R6bhnDP(J`B0TL=1DQYi<HaC6!|z~gCGxTI&7%aw8XTva%!Hg1BdD$)iLVqH!yK+#xqfG'
    '=g~=O2IoKOq!oaci^+&y38MvAZWv)3U_UFMKjn}BEj#soDg#T?;t%0KUvEHmH&;>+%#7CHmR5za(|1^P'
    'd1=Mho7F-`hQU2b`%?=0&m!wJ7CRAAu#{X-oG;0uS~>#Pl2gB^CI?M6>m;0juYp1H42v$!N76#aFUB%0'
    'zvsXeHXZ1`RLHoK-y~-IN1<X(U)OUTwPZ6MQp}HPPO0!oHLmZJy1GeK%VJPURqLt@RaVmyW(j^>Y*ch@'
    '&w=%;==;;q_pP8cMsV&`JvV6QLEe~73%k&E+N@~|j{UBD4k?jOYE4P|fRcrb85mVuf5ytzh==uzzUAmP'
    '3GXcC*R#b)l?kid{TV)5)z=e9(XfO<gW%19176_pp%_m@;1mSBz!k<hmg{UJF<2B=tKXRF9sI95tvYOe'
    'mg@2pMSvNN7lHaaWtrxSms?iQSW_OE++VE`-@md;ZiXusHFhPVhSd~oI>`QOrAP^5k`R+38TSN^@3}!Y'
    'tCdJ!QC~G_+JU2KcA-&yf;j&8KMcCNnp|>LZ^<JIjreMnuEzh)X~+YE4_f_ZJ+{pWOq-fzv%Ny6iQhh#'
    '<#eX!a1|>jigF}hRqG^Z0bUqobr)RPXIPveAAk5^bKQi}U^Hp5H}2WoXb|RKVAKs+Qe5(!BS#k7;M}Om'
    ';d5PAO6%IAp%lj-WFJ(yM_)*wju9*#likSZ-nrTwmqr;sy-{CA>nXz-r?A5A)d)K~Nt9%$3D&S_OFOj9'
    '&eFm;+I8Z+?JS_<0YRf>Ow0_HMkCP1P_k6yVLTU>q`03iRZh>*_8O`G#+P|M$@aTork*{89rv(U<CVM|'
    'aH!R;ZH5uI81oX>qM_wlmK)fFCOo7hF%v7~p5;dlV>X3PoXBL1n}O?^5rto@pp9|7(`(maoLfPZSf1$-'
    '*G()Z@CXfklLkESTo~46f$I>@G3|u<QD6p1%$?Y=nMX`JZZ+uMX1l_g-iAX9i+X*7S#NmxsG-GD|BlJq'
    'G4ncj1@zIHTwfYL)<1qjuJbwd9<;QW9r#!2doAlxw$wDQroYn&YZtS<2W_}Yreg_ow!V8^TgFrP?5C9R'
    '{R`<mE?}SvUGq|&VB8e`eMPSM!3CWg%OP3Y#@UO-dY8I|;3>~T$J!PEIKCSZFyb$btCZZzk)FWc8hNak'
    '{!e1KEp0jl0BR9{`;|7IL)e^7)_e|8qgB#WcPH+_tc#o(u!?_dlTOtzziC><y@^Zx((>~N%lnX(_bV#*'
    'OUh0s!Ih)nPXqMC!-o%zm*N_GGW&p`E*0&`j2rTf8;jJ)D-YipjI7Bc3^py&HD*A73*290$fT}pBhr|Y'
    '%{;$3KN+x?<tCobr~y6|Uu59<7<F@gz$wJG=g=)#Y{(qB;)-LIJtp=442<f#;A5G_Cq4EdX6XD_j0Bsk'
    'i7g+4TleX|n|%#f6pt8BUcC^$Yqe%{|A9XZutx@*gM6kfc7h#t(hc^9QuxPsaNw!hNyW%LOOZdM-FzY$'
    'a`tJEqOQg3*6CZmz{JJHY<`aAFT{17#+z?)F})>UfrZTi+eTt@pg~N$6Yj)#ten3Fm_z3^^nE4e`k3t+'
    'lwzaZKG<-<pRL4sEd&FIoW~Oo<gg=NtBhcEdV*47JkWdp42-Uw&riVSe~|icbslf8Z#9VQCVe{`q2i{>'
    'e@VUu6N+cTh!Xjbm<d7_25`l4xdJ6oBtq!QNL43->O^NWp2)q1KB^dz%yT8Lw!zQ~KBu%!`pJrc1FGFs'
    '%{st^79V_RPPUvnC>a2l5hc>4@ufBXgYCo9>zWg)ngQIS4&h+8Y|r3i?f2I=oUad^!#R%QhG7tzrscRM'
    'Pn^iNP0M$D#}3WFw5b<!Gq#-|;3i4@n1`XoNDz9SXW3z3wbXJuM{&gCFi4y@KBcY`aXT^ti@S*#Iu3zB'
    'JTDB0<(q`t1U?9u=Y|PSV#g0%52o05+`Xr9^&il*wHqY8^P<JT^-2X*;5*%IhuB?)&JHTg;9g5UEH4P}'
    '?_>|gLyRk9fA1jCzW}$`%cX2Cqa^<cM#CRjA7J$0mMovax?X{u0{dp2GIIA|JdhKlBe?}Tl5n+?y!@lB'
    'TD%zPaF?|vl-)0tZc{9pcM?KL(EnX&l_TyniyJOJtMkQ3-#kS<ct6!e_pj~*+|bzTJ6n^LV90@;zU8oA'
    'qR4)>0#&>P+^QCex)Lm2It8=T_cbPa6~hhO)ajBhwm?S`>bU#m{{24sX)K8QH6Zlb5BFw1oORI>!*%(I'
    'RQcI`Xoh=M;+-g?MSq`8eg6UJqeF4utLc3LBjFEYBOGeF`3FUsEY<vn#G7`AC%3Hr2!_=?+f|3ms!}ux'
    'k4jaOBdi*k9g0L*k?qsajV;%-?108$;!@uugohRn9MfY-4FAMdVq1~xMcj=|&or%=@Pxa8*CrCR6NNG@'
    'KQa?1Oahm2(~m;NdFaxR*&zvu?OIM8c+58)*LA5EQ9nr-wQUyBDE90)Y%^wK1gd|O@UK6T+2RQWlp5K3'
    'wV`XHhU7~v?PKsVn+)?`8f0-N26_Hr$yYPJpj;&^4D7P=dW}a5<raM_kSi<Eoujm<EAioPq7s|-5yd5p'
    'OG6w4Jk|~!@5ksW7l-iTl-+6WL;9Mo()nB$H2nF2{PV6=#|X<G4{3SY``*gQx6tW#P{9%N**pGhTQ>I6'
    '7>z_9n<opglJR2=w`A{gqn>o1o_3q=g$^WozF3P3mnCfdkbgX|JGoZ5pj9jklL}h9r|ND>umU<xc(I!&'
    '>gMTlRSLUz!QM(k7<nQ+c~9nV>vgdE4j`@nL$g=KwDq<U70z<S9)2#1B97?IY|d7Ez>+55ir|gW6HHlu'
    'Q@A~tS2ff%E@80y*@zU>Y1!uXmehsWYx&_w=>^TSsH#q^=dH6<dVfmauXs4MbU3|mxM$fgTr_Bw4EHY>'
    '_Qm)Ln*=M@yaZo<l$)yZ-`+fWL$ZoFTC-18EKz5xxUy_oVlWFxjzhh8*8jHt7Clvn+9#byXzJw037kSu'
    'oC5Iz`31uAl)?LDsPh`>dy9-J82y6dlYZG*?s+kZLH+U-XRlW2?Q8)n`8Sq*Na_g&8a2y5eKZ(qWqlqa'
    'tBZ}L%?s0%NB(KDBn&;qk&g0ylSR>z=M8q{+{=r)O!LW_WN$~<S~M>vC-%Ym4#V*nh8St<Yu0(c4PB$o'
    'g31aNA9bWgi_N0?c*q(*rPA&?n|WX*xzczT@ljM(7{+qv#h_TpZb0KbRh0^_sU?$qS@Pe{Teb2O=Niwj'
    'Ce*wZn$_g~>Cpxn<kG#0r9D!q7M~Oa`)iimxc|xF*-!~ropri+vRrb41+Po?r}#+cAkStQ*&T=FpXway'
    '=?z(2^HG|doD$P>W2&pKUDW|t@%3!QUnFA2azX5#y-Phi`UFJX>kS+KLyvo+$5ynKCOVpdzkF$Yxy9O='
    'tgiWbzy^~5bdt0Zwz)<1&$E#n=G?enf}RT}rT(R6H>e7Iq|e>?^he^y`?Jz@7X}|{qu-y2UMXCiEyyyv'
    'NwIYGb~}lp)p#afSFwMb^3t6g3q93cOF=!XN-OZAZku1`^U1HD_YYPodR!KisY|o5z9PO_-6aj>Q~SNy'
    '`$ep#^9Fdv5RC?9!gOY=Z@59`h-<8Pvs}(+z(+`YBcm(M7Zc;f+F0;+eASo600z_j4dL986^uy?ly5MF'
    '4DWUK?@YMsD;C!BrGXvy)<o1<{*Gif_?xz*9*i-+jPb_&R%j0fE&6VJ&+qcigpUV9<ja)a<h5~zgDdww'
    'klpEqWy@@x{@G%-9v#h>8f)r5k%!&3{bTb_G-xx)9ss(|A0u7z47M@yI=Mz>kw+h^cU<md{(-=T`1#E@'
    '7vZ*kdvED{OID)rHsi~AdWXldKpbX(LP$68dwd7mdU#*aobLf=IUOF$CNz`nItPy;_CjR{@yYOZilt3a'
    'VyM!mpV4H)^srg>q$ud3dP;uW;#^(t`17Bu3;7(1?O+hFNSGTa0~F*p!gIRRr5U!81z6zcpI<!F;IJUP'
    'RI0Kj1@{MV1dzK9%<!?cLAI6ngtdw4K#NyU9^;+r9;6ZOD8nEE0^dnZ(7+=Icdgi1vh(Bnw<+;Iw;Np8'
    ';#xX}yUx@BecrqD;8_#H>1d8y>Q1ZM;cOGs9Xw{LI_~D<YOrWTbs;VAK568$Ca)Bg+qtpzDK+xexp6P%'
    'X|trui@brBR`lHx7(X27d?UD%GpAPC=Vvb;OJZ9#2h)`VCIz(CS(guuKI-rSUTv})gpP)P$zwNez{W*)'
    '09^fdGyeXO>Z)VR)_u#OpUK|1m}puAe8B?%!x8_0FTN)9?Ql<^rh^}yL~jlwsp_myO`F^+610WlQL+hj'
    'DeZS{m<HjY&MLkt9D(ZCL*z??Fv~^Q<4M^s!O^uvF3VE#-%G63vnTI|uXfWXahK_kQL@6Lh`QEy@>jJ%'
    'd#`9;3Uhs>)xXstR?jgdd+F|}mTyF5&5x98CI0#BA}>F3oYs7fs$Dd|;A-IUQwu@Cm|O9ue$y!dCCG^&'
    'VMXBS5_IJOj>@~<tpxvAV)9^4!+mj~23IptYU+!2YRdT6zxuB1iyA|JtoXT~?F_6Of~k_YGQE%bB&#@9'
    '&Rt~j$AQq&BR$s$KDX6+qJV5;R%WgGM=7N|y<MhwBVk(w<R|#M=pI>p`bV<9*?I1YXX$1I#CrHcN`X86'
    'iE-P>2bzh)vP?bs=}%9dJ$wFa`ugWruU=lgnZA1R=DXKGg3;L<*Z|o>ytKChL+j}cr*E@|Yxr;~>)}jg'
    'WtM4PYHf;V+}IUivb@7|(*nSX%iqd9yYeP#SLz+{gjzz=yW2Y6M_yzp%^u1LUdRbv<P*FoCV0yl2SKD>'
    'rJFU#vgMrYozpHt@N^db18)Kn@YNgzVmA2gh4}VDeOnuU7vL7B0y4h_9$Jb0fsn_4diCV$`A=`AZ(dHH'
    'K6&%}+m~1WXZq~<4{x4eR>;S*C9nh5P&rFD!7eb<7>$vsVu!PH$#75SoA_JA#{xUJmMhNuhRMRE+X>Wn'
    'yg2dwI0~J>qb~C!D@hU-nw}L$W}H~AmvE25BYtQx8ZnQ#zD-#aQ65HIBp(ZxI9(vT6~BdX#cheUlP&WO'
    'PBkY>tx8RO=2qacAapD<@j3Ht({or7QXZIua7ryRwu6K*--AcELqZw{c5Eg*q8_zbtO_=lW}fl2{7AH}'
    '#!tM&52845EXR%kNfF^NAc@?_cR7i@Ft#k}1dijem;}rul+(yHUCRRm5gLS=upsN^)Rzy`vI6cU4x>n!'
    'DDkbtBS9R8Fb^xTEjzSfDv4!!p2cj&6XH>a$7U3Iu@{&-%U{lCRFPApCcuZG`YT-)f8@xi6!DpXKwGVi'
    '*Er*!UmTFJhl1-3BDRi`|Ew4v_{m>dR48dILQ-!zbnJaRVW_w8E|L?DmKG^M$U^OTvl)2rRpo>4(pz3s'
    '|8D~?UA&%MFJ5fRo&1u{*tq3{5GSlsGNr&u**!$CrN56sZ7BR9t9!wucDhC$Uu6ThZ8Oiyrrw>$%B~y%'
    'o7XHoe)zS&CQPMqcWvEQ)o*)Ypy-=EV3wkfcR9bNc8z3vQKaqmKCrt_wYlZuo-f|bR;j3@GWzw`Nk;jC'
    'zXCg-kE=(g#pg!=_7@hzWrb!@F;r5VL{R9J6UX**ZcYN+y{6_6_^-OUIER<78JuW*(OO!ZT%>7`XsrcW'
    '?aFTbQf>o?>?VDm$%Y}>0MV*8KWHa8ncgZ%0YZ(09UuG8DCgC0@q^Mn5S#1UV@Le^pn`M1BrDETmMKcd'
    'quDN%NCyfQwZ_-*pUTvPXZu~A)_ugN+^f5^5Ly?Vb&**kJ+zbK?D)p3|1{R61!tP_n-n{q7L{qgo-M@9'
    'QW10is07^PEx&u8u9)%Zz_|%}cb5kI=X?3^csxOnFBZ$q`pISuYg^9NB9J1k*i1x{_t7oU^fSpe@$GE='
    '1Bv+@>jUF@#uL!K;$xWg8<M?+e`Gf*)mD9Md^#A_YFRI+xwfvt&x6j(ku_N`L$bPC)P?OiE)nS<*Sb^9'
    'H+yi9AeGWAb5I`>XCh7nuvF1}!Z_y2XZ*pqCuYR-R56elO&2d0^Skl3Q2F0yY<+WSxbC^prfm7)s^q&%'
    '?}Y5_ooUM+Phvvf$|BRH`qGmW%L1<NM&`r}$LGfEP%)^pD|{REF<q0zHDG|IE06<MV7+cKQCYCl{PN;F'
    'rK-{5H&HwJ5I-Lj%l9t^bW4GI6#}Q00f$8ZR-aK4KuomF=C5q=y~Fn2`}ef<HSYXVZ~S5VUf;HFq5oUS'
    'bgW_UQ@sMjb~bDLpq-?hWatKsW|{J?F#Z3_vRWG-4<Y71O`QctlKPiQ7@b#QRNLRrYeA+%GQ9dEqI?0e'
    '>hL}49TJKb7IK~=e7&{UZ$+PWM66W$5%%b~U>s$!j#?`Da;1y1$0#k5mJrHiEOy+^M|D>h>jF|ff5oNF'
    '89!=4GIXdW<#StkDHV@&)iB2=d-Q?7Vr=Z|%?wpz?S{bhHAZ35Mb@?ya`_<si@fSs(N4K7&wMAU8n=Hw'
    'SNi2WU0m)~y*F-vXHY?m+gKBAl*Le)qDiDw?-w^!Y;1}Kb$~}@Y!Cp|<6sl@)hNM2;`z5PkEB-Z3?RGX'
    '>>s7Ppr?aJyceNcley<TY>(n62la#8_?Pt$&MP0Znw5NT(5yhX6(=PUO_DN`Te1Xkh&|NAowwPdHS_NM'
    'Q5lb=9dX_elRP(e(;@ec+ZZ8joqO1B+S4Xx7I+(>?UkcwJY*a&lUgbCv(JRn?mSkP2<N*vl($r}@<^ld'
    'D`QE?y#x0maR&pat^KpF_SQf$?vkvLGRMV4f$;SGA{$ku?SReFc$^?FnrxP6<~(gU4;h^R-zEF4Gs^!h'
    'k*o~Ud%|)nBWkcsUpB}~b-`+gEXsi$Tzrpl%16Yf8>DIs;xPGLlh#5X4f6b@j|bSJHJ1(KqLx_L>!m$9'
    'c5J%ezdF-Fp6<e<kBeCI_F9g#BU|Kxcdm2Puc(N!-||-4r5sQPB|o)1G%6o2s)MJ!$LtezH`$m}s+{Cm'
    '-93ifn*{XHXeFv2cM$d4Aq^Pww_X^^T@Y1!qSYJ^+_~7D<PwD%Dz-@?^O*X~vT$1NVVe0~={wJR!ltS!'
    ')^?U6b-x-kZzFIHrhq&;XdW~i(zO_HfI8@eii5Jd4Q52aE^aKzH5Y|<MDzvz3zmks^vh-|j_GB0=c+;%'
    'F&H)?6{WU>JOVNE`-W%hNxRWrzn`tCxKo^MRtcf7>*Z~m4ESt5$6$T-2u8{HdX4+6m;gTiZuU+*j~oCX'
    '+6>tk1ga4Au`z03fXB^Db14g|wg@Y94l(uBQ_F!qX348l%5JNhVOMW$I<aBpGi@{>))Va=F>7r{>;OfH'
    '@*??(bC4@Cw4nUpdr;mQgU4t05_RktnC=*t9u$^tneC$QM5R8ttzFVMzcxYtTJH15tqJ!6v+71~u@v9#'
    'km~u}1Ht`+=H4No2(w~QO^IW}c1st{6Te-}*oda{%`GzNKk&~NYkoVL5Jr}`>G6<vcDuQ~G%VX2kAEvS'
    'RkS;t^nH`Ao)daA+9G&dvNAdz#pOroU6WaGS1#n9l7jw`__H8^&=dI|lNo!||Ikl{CiA2Ht`ik(30pk|'
    '0e`#Q;uEaBSDe0+59;(CJb(n9fV;{eyz7qJrj6)|W$4*WO`Azs(X9o~-iKbT(reJ2ne3^zovJdO9~{U}'
    'xGtsX7A&)Uu?-GoIIBTObUnIhD@r;?^}eV^Qp<{{e<<$QIY4`5t&>|%EdX`NzaHZ6Z2uwBegf}5XBg4S'
    'vBLiP^=Ca#j!r6=d&%V!i{%!EPBrPFmYMgJA#M*2&U~mimeuR=JE6Jigv1qra!K`4knYjJ>|rbr&Dr;}'
    '1(UCLoMp}G5%CH&?${vN9X!%DKckZ5jRg~m5PW-;U4>Bs@u)_@QpigdrSEr1F8@(xG`v<$GoRq_qs8{B'
    'RQ>W4Ok^iTe*b_K&@u?7&GeSysG+d!xgki4g(<c;D?F9<<#8(B)OtqW^0G4}5{pDt$&sj9TXatof3>pn'
    'j+EiwN%Ig}R@K^<w!Ip1yUbB*15=`}vYK34%e9^xP3x-TuSE`)<XAEJAxvA;%m3r8aJ!l#)xz3ycsH3='
    'Bz<;}U&v9vZ{%e>sU6yw`@^(K_h98c=#-8sWxqygf&QBG`T{+56kg)g3R$STk=$Dk^-)7Dq1}UW>84vc'
    '8TR)Th;P4Z4{uso-llDJi~QE|*P9G>QkFeuGeBX>N*{g@ho0>@cI^5d^=+CE?kBz<^2B6*Op?H}7`5To'
    'I0#J3x4k6tJukK_PHmr>$18m}0e6$w4@}SZ00ar_#G)2qCby^;+l0C#NvPxbe&kuM7X>slgUDnq4-+SH'
    '*_lpUG}rrxY|~?$T0RS@71`VgZQ}YqkCQO57~=tr9GGrm+W{jkO+uIO(D$ij6UHLTZBy^VFW37Bs`Wm4'
    'k^AM6%hEO-3GUc_5QNm>j-SL>$%I7A^aG!IEOc1pTXy6*N$h%*xFm3FE3zy=iyzw#jY8gn;M^jX<FeRs'
    'JdgVhHT^K5v700wi(`+(G++Utrs;+u^*uLa5ivd2aUvcfme2HJqnYG1@Jv6ls2dSK;lSipkWdmuz}R67'
    '3=b2GV<&NK&Hy*Q<6FM#Q-=U6yS^KQZAk8xN$w3G`KwimJwAR)85cKxp03j6o|;1zcc|;SiR+s{P9Sn%'
    'y9BtHn=vy@+csUt_sqbu5@tJr3uJMD8<Hdn%+O0H(@=A$DV?|_b5dYBFNj>gvrmx>z$*bU6Q6{3Oajy4'
    'F1IOTF+9T@U?9faz#%aU13z+Da-2D__>u=?4m=xHYnd*0%^3E35<4dIVjB5z1iRi2eAw*1AA>kdIA^YD'
    'Q!|J?S0g4qU+p2Q%$U~x+C$ak)7kp&<x-tqjYjfT_PLS&`(m*!mA+_G9_L7wNe2*>%#Swji3Pzbc4}c1'
    'OE?Ba<k;jn@;hM8k1g)Jaq8!-JfStY&MPs1(eU5_zyi`-rE^~UI7?USH+Sd{y%0rCtak9bQ(M~D=Q&#c'
    '$}_y}3G>)L+5yzJJVctx6ojt~aaVtY1euZfFUZIFt%alK9lDu&IB)l4?VZ;uSw<b->oDBTorg*RoE89v'
    '?8MKq5zqGDLMcZc&ztk8if{KJZtt*_oz`Z0ClM3(DkXXgiLNrDMeu!kOFrPK&p}ud_0X#os9bgJN8)1i'
    'rHLo;j~@fZ$L*vW4D#&2?6*~-;5%twh{tOex7rmW5EZH`(Y@^-k1F48BV*MM)Kh}C2P4ShiNV1#JRgcv'
    'cGvk5=JtBxHgV->jO>1hf3LJZ9qEq{xN+d(IRC4<RDHDjTxAOKgTt}FWKxs1A{<uvWMCAiBRd}C#*PJk'
    'USZ^W)sSRyhoW5sLPc4*FNG*99iWc8XQ4EubddS{!FU47W(3my@nn&<OpL1kG@pmp4p_f5)zK=BClwEw'
    '!}gkhLg-P;rt=H!YgKHi&>0&|DPwyQX^O-Sl}v*dC`GlvPAlv5@N3CX<;kG9${zIKr@RQpt(0UUFuR_t'
    'Q%3GY+M8tG?N=lD-MD-Go73!)6K#^uv`6+1`|zRhJ?Be<EDZhu!wIuBT9<e#D{{0I_Ke#ZYz-`}ze;aK'
    '-uME<;NH=SobCe&+z$>+2@B7NQ8pRSJ=@OXq2QH=PlP_YC3glD*T!U{s#~(ykhx4>hk+k-#f8de&QF*`'
    '9!i~O&W$fh=hT=gLuQL?^!|pg_~oHw89^k`bZra%)42C-@zFl10h{YT>TL7C_+P*NI@%6AelQ+#4ZF&H'
    'C9r*fc4gYG&ubRz$E14K+{IJpG43)*rzFN|Ce^@%#zRu{h|=rHt)1|asG)m|r6fn)6z#jYcMC`f$PeUg'
    'Mbu@rkxE6n+LYxQviG}SRL=Tdq{0qwDsSS?e{RYv(!sGDA$=A`RU@BJaCUjNpV6q_W^8}3F1p2FtB<Ff'
    'Yz;o$N|k4QlP+geG&|XI07rZt1P*63BHW8?lepYUV%sJjd`d!_CDcyLD6&}M2EIjopNA0%JTtU{(B^dD'
    '0bDWfZHtn;QOdqHC3w7PQ_Hc<gi@cw|6<>ZZ9fWF;>3yTTAoRL&o(1!TTX07L6F$63T7pqYcWU1j6r*W'
    'g5`L2`!r2g49lFiKGKHC!~x-f7e%halQ@Y&&!I__Slp+9Z8F=VZe$VLv|JvAeh{(1c7Y@@tSk)a@l!*1'
    'G~u?xX%LtI(~SKfw5V&x4)J2ow22#f9toYujfv|Mm&IP_1)MX_cj7pR^&+GB;E;#hb^|vt!@zWt*!2Cx'
    'VU8Cj+zTBRhr~2tPB9G$P?aP$cZu(@C^T7=_yM794i3HY!C}<%L|d$}UiQBwsbl8H0Vj!AlIh!t9eIq9'
    '0P`1|kel3et;B&H1uPq3b_uqsaUIxh#J8B$CVRo9egNc)oY>=WOl;0+n82=e{g6bl<-?$E9Jxv8M~=^Y'
    'hXtPJgkI#iEFy%RX+p#2I~{h)M0O6J4$DRg<xbh6b)(3}yfofavodA7&!VrQam^PhY2#24CF4wjo0J~M'
    'j)d|<0b00B;urX0HwEu_>Sbvawfw~Lp#SleVI2l`G%j%u_&O!JbYkmJ!?;7;PE^N~mod2g?~XOYIPlfO'
    'hYv*+_lpz*3B|>m?NxIOZ=?%e)Rj>kG|D%vC*t0G@ye0W<lT9!n_v)`^!HGN4&;#-Is-|53kQb2UXjH*'
    '6FpL7Iy06>BhvUgbm#rA3Ntw6QfHW)YM@N!2Az{E+h0oLs8ObX@x|uW5VyiFjpx5_$ePGfIu!4T&lna<'
    'o97kzWQ~V&qiy93IfCkEqiUagM?fuzAzB!X3c|ME3|^Ce8Dk>V)^_d&r?fA-y-16@46RPqYj2ay`UWSA'
    'JlYF@40=5QG+c4yX7mn!ez92lZVNcOJXEPK)6~PKy;Yx6#`tQ7G-`zLBPFZ8s$})IEeuc~e*1p;YRRK2'
    'a?1}rDSy#&xLrhVA?|*6ABBV}+ej4ytZdeHg;RLBjfH9$EjDG3*PFV4_W-liHLXCj#FQFg1cu>QLqoKK'
    'pqEl|s<Il!1SMvNLOrTD%Bx{e%EWx!;k_m*c6ncx5NTP(tNdcw3ToHCsWNR@NUYs_|5`FKUR*Cy6eBsX'
    '_nf>{?VF?^95qV9AwwW^ECzTf>OcG^roEgSKcNxvm&ff`PDpBy#>beSaeNXqHxBn$)m%GL`0WTtG<cp1'
    'V<HtRgmukl3181{xv>V*CYuQo=4F4<Iop>0!Aksez7aw4Cl9}V_+-*zu&cZvknxuDWmc*ll#yG0A-gdb'
    'rW)RY0aI(WS)$lS8fN0G2<Ec6<&zF3aIHX36BnE}@0M+0xud<lEB8gz#puTF-R<rd6%D}!sDJ%SCRx-f'
    'B*E9UPx1%V-h~I$Z*A3m!`^*V<2m_ve&<VV*H)eM_O9>a?p52e?97E`>xiZ*Tvh?1>86s(RuSfYZaI`X'
    'iNk8z0@*2dRsG;mg_1cT_2^JppAE~yO%1wPtzcB8U`pO>>nn9z1HN{bu6=Dz^@2j<SNWvS{cYStrDq0W'
    '1O=1m?v;CwoXysmsFntj2xL?~l`?hCjYSGpKahL<K3%<S>G#zMu%||R6Ghb5k2_FB^2@m-vjRCjZz{A_'
    'C0d)im?e_s6IWJ>8t7>Gvx;%J{e7&Fzndy<PxHzdmqt-{y9>kbY}{&Xe^pLCm2^WMm7i$f(I?=aBbUmg'
    'iM+te?Iv6275~5+!X`q3XY*JIZWrVI4H)JIprmlBx^OAg&Y23zq~!VyV!{3NP+YH{sq`=sy$|O3D+8AZ'
    '(2mZeyu)2tP^}JM^RjlW+YaR3RuL6Cd=RN+^@k1>hz4ROuXuD)w5WjF9}6*+YtuRO6QE%yx_!PiDf8<H'
    'wUS2X`z;Q{TCZ?+*?L!%Qrov5R{3sEsI(a{<qgy9=KLa=V;+Z*&B0ud=Q0>p-r(xQ4fLB;x=1&ffmTGD'
    'GO1f@yO`vo!rIMqg1RjeUR1>k{~<hPluYN+d6p>tt$nF0#uHKC8eu%1U@4{SCNB(LOt^iD<6aKg(*InI'
    'wNv)$E7cdP${&MxL##0Eln+tVkjeTNk=a-Ftr;zne9}(Y?xO<v=STAJ_mvOpQ6+5m-h#peZk0uDub|on'
    '|3+lP7-Y2q4}T^?0~?V`lWgY05>%U~RrfCE>XL%QTlLenHSScg9GJZ#i7-f>uU2WdULAm*G5`#CV8M+{'
    '$Q7`4-px>AWO(c3kpavE1LoeydvSOJ7S*KVq(A;QWxqO|lk$C-W%bj0u4Sl#C<-<0HGR7mI;r=npq_5Y'
    'm7j2Tuxc8J-h+shs8TuL)UrCyPJR84jWMA?r#Icw)&7RKm?d|U4>V<bxk~@*;Zhcjm@MND`0Me)AYtfm'
    '*K^Dyro;(o5XFoV*GXt>n^EE>N$haTqAZEym^caJreh@zwP@t?B(RRB)+97>EI;uq?#8hfTTvV&c5L}9'
    '2?)1*i$y+7xW{=&V?VKcKjE$wN0DuD9($gBrWYH{88)8HOqxVd;<M0<1J@?DAIC}Lafi94Zzjz0Jujp#'
    'cZlg*u#m)aO*i35;&>5F+GN<+W~CYoptol#)f-r6_7F3P)Nhr<zgMf2ZNx;xw|mn6XhH(prluYHk!8l*'
    'wp}MoJUbzw9fT2MK@|9u0BK^DP{)cK>PGM+HGPLM;tovzt1m&-I>DR8uSG2>px_mPB=bY72ouYV9oJ2~'
    'Fs5-}bNIg>5+`JiYXR9z5dFjpsOx!&83U<UXa%urdM>w|C^CDkVzb0llzc;VFV@1{&?lkmMxGb@HcMdJ'
    'In*(uFiK4L%(ZNawP|P=z%MZgf(SN_83eAynZ-@F#g>brD2RP4BsL2@(+o@#6FKd~=CIq7Fb=Ia;M{^O'
    '&thT$=6Dc?uFnG!N4`tCA^@CRN!o`Z>N)!-dcLp?GjS1icefGKVs-@U1FFEh2(X`(m?jBAAXMN4Kp@Mt'
    'LW>35Vons8oY{<7Nn)8GFl_%g27Dfo5UK1^J0dJHNf^7Fg<;@$-1A+FSsqWQ=TH(_Ap6{iQOEb0<6)An'
    '*%<?pi-8e-Ud-0pU74p5tM2H}c$|W6<cC<=0=dXoY}+6n?Jx>m?zssI+z?pCa_l$&!U1i$Nqi3MVS`XI'
    'Lz{9ZV6dMpriY~))|1y<dd6wGdPA<|<+?*l;h;%Om@)}N;4nK3eeS!i!yJ>^K}_7xvO@UPP8?jBW14R4'
    'xn2@->IRX+TId!^2;m_kv1Rg*M9hzX+i7BfFk@EiSdImJ6^9H+Pdp#D1JFFA0lokNpY}sbo?89%hSRs%'
    '!!>+3r9kZ|Rpg!)PQ(<^zvffI#5K8eF<IX2;>oi}kT@*xJy;8gL8rJTCWnK3fQ=96vMk$jS-{*R!UAa)'
    'XdzBb0_cNBiB6IqUz@5DIc18On^xokF>N5XmvGC54IFr|*G-VkR_ukGnS@7C==+Wb-vaeq3d-LNC|DW}'
    'D5Bt=SG43SMV+j1F`=Je**ZH;+%UAF(DrGN#Gn{$k2%0?0T?Tw7h{)!@b=>nOH^4PU0_R6X1k|ej4Vh$'
    'm6t50d6*tJFYmatv!tKW1wSrAK}ee*784UBjG0)B`w?uhkS2*s{0J129oZnQozOKo^+AwZunTPvo<3+^'
    ';^|x9t&%*zav*x9YjQnZ3gOd4tr#pf?r_kfQ3%`0B#H01SlG?+z-Toc&;h`7J|UnFJrksk6(q3XLdzv!'
    '_a@}H&~dRep3S3xgxmv`jU6Yzn-nIqh?N8(*c+A^ny?1|Jt6UJmj<SfCCj*-a2lKdG3dba_p<KERJue>'
    'xCsbOJYm%1R>Z;b_uUwHG!*hCazV;CCZLbua{<^0jvF#qhYgHQxEZ!6w8kSa_U$P0!0hm%B%(Y>e2%i+'
    'j=}cw+yF2H3c&+IBrt;no@ZVF)};&jJ@P|+xLL~U6jK5&DOojR0|Zj!hIYh3B>54TkS1|Fn4B3qX6VK6'
    'iR)1_2?LN`p$B3h1o0JvIl;_$SJO7!Du_X@frV-^u(iRo0Pli<i1S>`*H0V=y$L5yd}LUc`e8sk$7ksF'
    'SUd#Hr5_s@B%G>vPAlDH!)z#J4tRo;@W3Y?i(-p{h3ZEj&4bA1f$MwV#hI>8DC41N*@5kb0c;H?j!rH7'
    'whKeAe5y`f8p-Vu$|K(oA`sy|%r_4GI0*t+OaQ*F2TUKu-~oG_f!>NdX45FK-N^KOuvS<bax((@&2p#>'
    'TP!Bv`0^;EKyw;dAR)jD0dtcQ%feeDmTOWVGYdj^9PCk8YG16B{lMJfd{yYQgT^MvDchm2P^`fTp1JP^'
    'c=II$;RX8326rR`q=W(3nluR`j$W^46THR-PQ9;}y7@ZF^`GiV>IYWSN~^ixWN?bMGpqs2e_}~Y*AF}%'
    ';Qx~ZHzFuI8hUtHDhfj|t3gzOUjV8t9K5!=6)h_G9CUGQ^awpdTri`-(WNjC*K%P}@Hbxav7FF>XIRW)'
    'crb{gAYu_1zLay%j#{v-$0IXgj_(EVUo^i!B>)eHjtf?fiFORfnyz4SI=}#K4Bn*)@)7R{da&R9p(rU`'
    'd^>~)&vjzvfbkWA;R_xt7+awU6A3`Mn;a|-&V0})wiA0v;K6^u?F}N6x=tATfo+|JS9=C7T=4b5s)9*+'
    'CMPZyRt}?p1!iOs?t$Y6a>%s2*a{hEUKIJ%1Gxo^3zSb1)*=Q#LFqUk+u{g$0+f~wDjbxtmk<g&m`0$T'
    'ZE%onyo?%y%mb5^d%!|g;M#Fah9YL~HIu<RI0*nHpm`W`BRj(TdZ8Usw8V%R0Dr*0K=A}DF|hGKeS4ne'
    'h6y3IOI&vJs@~4RSW2^p=rCO54#S0Vfi4Oc=$7qJIEg*q2iL|6Ou)Da78V0Ti2HaMHSv59JcMASWCB(I'
    'OTdwbM`5}avpKON>gZwDhRK(`orZabgoFV&mM$noaKu5SF`ooroW<b4lb8`Og1}czOcuJJ<>ClrDX<J!'
    'j}D;QWg6!#9h(d3*j(g}%|+qZ?9RRw1BIcFMsAc4KaRPBfnAGY@#_#=aLN+AQ|y9kinWDdb%ABNSc@1m'
    'I2gr@l3r`cP4x@m!(4z5b0K}0hqK$|oZl9A%Nj^RA_BA^u!$XFf!E=K&H|g-^0@E238-buCXok93Z!-5'
    'g?OPn#%sQI5SrkCw^0EYTLAk9+_u=XT;Fv76+B>O5CkC@@gOWffcQR0E#kUC1Ut)z@4@v2yB^e0SCp*N'
    'bPjxpc3iV*N|mYCWXMHeR-2A(#<0I=5>QZcpbpTl3BZzZ;5!c}Ylk51BG`j~2aupXn0yIn&WLE*S!xM;'
    '!afIWYSRPPD~>p0AmhUrq(~SFr3ShzqTsN4U~^d!7QH4kbh(Ka@)M5$eZheO&syUG)<Rgzpa@U^CJ&GB'
    'c`_Ae!PC4!Xu~Qjz<dIpH7MQ$e3v+kohYFu_`V4Tw-L-LF9d_hLX#4(AA`yRr`#u@1D>*LxhGo1^=v)o'
    '<ZU+1GXdqcYFGfs0rdMVZqnGY&BO*`fTNx;A9j=r+SxWK)`NG6XM;KKfdGKjm^Py}*h8^%d|QEI=|+@d'
    'SUn8z7>#klLpz53mAD{GL8-eUc5C@yrhxHHOyU!8u>#Qcyy568ozK(v>0&P)R-1(&+>B1e=4y;**$g%c'
    'rva$`FhR=#JaBXXT<}XB3|=Hw#9``Q;=z<n0<J+qqA2uya9txOXdzAl-vcj~5DvbzADgaAnd`+Al%Gez'
    '<@Epq=y8Gi_I$@89u3@>5;yW90xpr;dEF)YFGTLgaV*5#55WBcB@Bk7OF%Y&O$1y3HntOhzY9~dgMfo`'
    'WIN19{ReK53D&O<gz@|qH3dM!M<F<Q!1{Pv=zyE-S^ydkWkMJJ3z()p*kFW%D6>6Ks08CB;*bK&!?RDn'
    '{pr<{tLHzxnZ9{Befs3h^KV~X{h#T}t7p%zjIRJc`_O_YQ{rg`-odnZ4ipfBXWo|N>wjhG&gJ#pyXAEx'
    't9TQ62jW^KsZVDMP|BGI2e*S)o18kURhzXPh)l)U-*GaZk`?A3%)3vd5lSBnfe0fryo@yEq8-JQ0W6qH'
    '_bKg#)NfiEsMQ3d&txRkX}Vb=<Nm%OAlzkktPs>{p>5_RZCeC)A;Dcpa2F+T7ZTjXKz?uHkoKsnY@BAg'
    '_5!94mF0b~=3tPb?uY*_#8mqr4_>|li|Cdta~q;Bya{OZn@#)>(^(S`71={6;xA@tHo3c<x8>i>!g5SJ'
    '72&hxx|mEG?1-iw0=<8SIfxclSZ^<{+R}FT>1Ku!T1F?2y(Q|zz`!f8iI^-u#lf!0_^T~}pU!7^<)Pg)'
    'a1lAY9F%AlCO~ywPrM=vFvxP+ZZ*pwt`X)m%n60dAV7PlJp@+XT1_}AqRmuqXm&IeJFG7xq~%kw?VqNs'
    'J1^4N^cw51brAk?(ujfCY8W<Q6EJ0zPv47*gju`S_n!f%*)58)+Te(h>qVM@1=wMcM_IZJsD{LeS0D<%'
    '7O+({xo>74(5Lw>AD|o&>yL%n^b<MAb{TCYoe(hD4Xjt)$G~}}NrG&abr3c?%kIFZjqfY8y_Uvq7f8~w'
    'e7%X4Q~vzjjPZq(;#sGyv!i_r^A#_aUvHhw_F7@bQ|UaDLoUyr6g+ehN~poudt36<-+P9=Jm=q}tJ|#g'
    '>v^i?GmaGj?yxdsn^zAcbO>UgwSh7fYdcN(0<+MLE8A9iqkn3*=U-G0dBg@<tiJ&cX}!m#qNZTg;rn2U'
    '%}5tc&Gr0iF2hf4U%|7(Z8yDc!xi;WYUS*XzF6<uh(`n~)@|@QjDBw`N>#fEc740w&_BI;+V91E%@2D3'
    '=r)0T!@%#I-x0~N&lhXh^-s|hZu|aKN^ZYif%VT<odgxW_X1oRDWy8SS~|g6ydzon_nv=P&cTfDHsRMd'
    '=~A&o>vx2I&=ot<!>9|IhSH-wpuFa*ci0c7HH6wu0!X)Lw{!;ps4Fd@2Y}bxJKyE<xh)`E0Sacf98;hX'
    '!mDjOt1TVBS#d6zrf|x7h=oO*5=6jtCmzaQf1}+0C!jyFb)|V_XBe+H*Vnl1)5VpD9=#$9K5uVhfB^{D'
    ';Hz0~t93O`#EJZq4V$G;#KpjFFodI>FX_AVmiO7mN)LYr&PaD&+>){fJMKz(EkL^H_&p$cONT0NqFL1+'
    'Mx8g?L)u}kZWGyg{eOc^z991f5Z;j0HSfS*yR6+o%7H@7-)#Su+6_H8uz0hZUMh>D&U-h1@kg?H%hz2c'
    '=}*EP0~=>`_XAmU7Q`jj>S{)B1eLpaS6dJM$qSKR)?SKNwo0-5AHgr0XPp`Jg=}9Zdf9bk&hqSAZ!cW?'
    '%Osgm81(r&Fe9>FHc<scA3FecNVnId%LiNoR&ftQwJZ;E@m8)-Gzd^1rKch_T}{z40=l}&ou>IMu*Lf3'
    'DaTrXJzo4lR9X<KxtCb!i=m2*+gp{x+uyx;^Qygbkt<zUTcLwA6T|Mj-pj+-fzsKA*o6QS0AI9IgajlK'
    '&t}()ZYU_f*-4n?BzwNNhMC@W4l$_A+LtR}*Q}QkS}5a_iMpNg%3mivfa7-;hV`IMhX6-~*Yo#(+;o(L'
    'm92KWOhJiUar8{P0Fkw=zb5RuWBjh10N+=_e7{KF&p8Y&bZ9q*Eg~3Qc9~f5`vqr$-6Ym#o$yr*E1TPP'
    '^F2#h<edXVTQBpwP2BnI((y)n63eC!e<$-fU-yYkrD&miyO}ZGe_UbK^?LJ{t`5_-vrT8cb+|81r}w)n'
    'jnbMsJH91DK3{gvm;0@{IG_=YD*L>Nc0y;ImEISIWT&+^9iMLDy;4W;(qr#-q*AtRMG(4ANT?2@vz5K$'
    'zY8#3{r9?h>*E|Z_-GxE5lSU5@`-$xZdTbhGd^dXv9SZD%V}3h+gzn-_kg9EL)On8S3&Ep%CgMZvNTaY'
    'cG}ZTs_FE1H&3*3j0N7;-!|!*yx!d2lGR<ilktY*FqIFFcp-T1t_7Ot&zN5#dfh&<-UL$x`4z?9%x<}0'
    '+N>))G!JhG_8lbcvl}X}|7`;*Mjno(i?7M5D~SC5nYtX)-a_AZnvb!Ap+H__*@kbs+z)_+QUM$%x|)e5'
    'nyp349&oR*6cb-{-DeHZ)Q&A(_Y-<91xukb=JK=AyqWLp9shd1Sv^^aLf~DY72@Cr%)oq|_s8x6rYha='
    'sCG_fw|}3lZ`g{wZx^cG3rk3t{t&9Nr7tBLVOAteZ)iKdmp(`x_54wwzsN3bLvW`g=_|6y_|u!TrT#kv'
    'N(tq^&lW6w-x*j*A`f|Y2&U^&y)%HC9C$^rgEMxB>jSAQ*!v5Ex^T}Ax%&dz6`!3U3CA5n^v@8@i+<BV'
    'AXn&qFVL$XtTTYBwEbn4H)`$=2n`9e(s~i=SS7ZOKo01D9KJZw#U|s|7@usF%6n)Op&d>EyQ()%I6_5>'
    'oM4=?#62DOl4-1QkY;POH+weQtwX^z$R_<DH6pc15NZZr7Lgi3?-QP<7$O&|gJB;ijo9q?c1Z6(IznS$'
    'U&jD7PgWDix_7GsY@-a(2)HUuGy{JA0r=v{W}Rl_9oG!I=5=d^-sFjE9O95atz($OKDLe#n#8cKtyGu6'
    'y5Q~;z}n&O7_|dNsNMf4iXawcI7Huv4mX?+0I!x=j8%MkN<<%tY2MmW=NMF6tVUaV`hFX5(LKQLA_$`s'
    'YL0v=b>B%~OTv~5o9Y@OlUDCE6~c|or-|xHdWu0ZX<JV<v5va_h?k$@&3X+3fY{Up*fFPTyj=jRU^Alb'
    'k4*_9%XO=(<<&9jRqz`8%HBeu3AXSi^+C)pCrDK3gS$VbseO!!cd8Bgj#;V=@@{-lH|R>daWL?b9jyaa'
    '#eg0RaBpBy2js>;qfWq;z@sj}yLRVb$W4Zz7NBJda4^7qrk_5*J2qcu(ACO$Xt-Pm%jjZj88wv8>kC@g'
    'M4I5`#TJz{q#3HPgNizcdVnkA<YI}E_F--ZT@-fEFsRDpxj>Vr?|g?>jVi;b+!gOs$YL*)t{#Vu>P!_#'
    'Xs?A};7>VTKIy+IZI!-uGcWSG$L({CnxK3m(^^=5XP{rkLLJ)EIfyP5cIXRhdu2}~F%4Vh?p-yJ#LzY`'
    'wkc2KMi}lr?nE8|HY78n3`aw1hQxUe?Ol)cscS5`-F3x5Bz`SitDcZvi?A7IMZ#|HL-I=9@ZM1B`{(6S'
    'hQs^9Yi88Ghr?xl=yjr7Uta%nZ-n+rlrmFk#KS;crJFSuxAlh{S~sz0Umz9E?03>!XU!8FO4bQ_!Xbnb'
    'I05{cVmQH}YI)b_I8v?2(4inJw?X>@+qt@&Ck+e0n$JD!iPonWqat2Tc{;hjaobSH&F0uCMkt$TI^oxL'
    'r>feZbA)CUsq;XzZjGG?wubQJzB9(E#L)<R_m+be;D=?A&cnaG7LCq98l|1i0h%o-t%syd29~zd%m%wl'
    'BixE9rsr(*c>6qEu+>EqHYJKfPdNrfEua%}T8RJY4a$F2oms;W8PImRSW;0Ra<$qlJB6w`caItbb&pr5'
    '9sX8{>pVr<EtYfw(84;<23M<1u-lWWq_j@~^XDbD+|vcQtfGg*Jgk|uoW|@`$y%T{>S8UBo0YJh1F9zN'
    'JN!UNpW594I!xzw?(Eb9YOeGya>aTY=t8CHfw@(t7ebl#g<6h;zgT2gDjX9RZUK_Kv~-oe&w9p)-@wcO'
    '-ZP%e7PF2uR4d?0#j51h*@3t18W-9(kh;6dVG%wxxowWA{wP+%lsm?X_IrW*h_1~SY+!^_*zq$-hEl=%'
    '!3Jd`+v!s6yLi{5;LGUll@n2wTMDfgTeRwsT(Vdf9+(OkoonGY$cSc;z3=o@Ydpy$tDb`5VA-hNF<)i1'
    'P>w`KLuiwoGEUl5^GWj^jt27S7@<<RP}V-w8pAn6UX3xLGNJY5i3=H;Dhy3IqNvD_$TWER1?c69Cwzs~'
    'q_E@9ip!Kc<kO*2S}W&l!B^NuTgG0aSkdLdlv$)R%m%|UcZd3wDk+t)`Ig*r?0uz@2|K4nR7zo9@!vNy'
    '5ir@rgYRxP%&wo1Z<^f+4os_*(Qj!s;bXX|d60Cv<nTe})hOuqF|=-jSr)gzTFGE|@}Ww%mF=8&9Tu5#'
    'y#@0@YU`4u4OGx-KkLGNvo);{eIXD%#Go!=qlla4sO~3b4?!Gc|29L^=EpXI*L^Ij0%TYta<zE5S%YJ!'
    '=}=0x{mu_YdhfkM$j}uYd{H{I(FIcvMr%NO*+9AUdXi;WPIS!~#)h+jwbhhTda?#)k2m6m&9DM++t`FC'
    'fSh5-CesvWE6q|v$gVWMVWw4$BB!&iO6xz}AURG>;k56;m}a+e$9y0qzR`FNor7NqUYfqknQ5qfQp1k6'
    '1I%46(ha)0t2EgpCF<!p^2h;8x?SXS>kE9llXe;osGee{+pI$6EmwT4C&1sZW%sQ~w|4|;5mvc`iSrkX'
    'i<Wbz6bZ8m;&esitK`smVOJY&8enVMr&W|{b{?LtIO*>@?6#92?>OsxE2E)|Seh=Mk|m+yYP{ZD^aEJX'
    ';GM{QE!rJu-q8o<eTp4Tfdo^kXwWm+Y`1nmjjV&W+W`(7deIi<dXcYxSZ2T;{=UJ2=Q1RG3Jp_kxN<*X'
    'CCM^kS@4f2gW8v4PBi&OhAh!RU$R`$=T8e8iYZ=5oa#7_eR}mHRw%e4i|ZbRuB&x}OQ8A&pYj$7<x`S@'
    '3PjFIu1&A<D4Ge$z8J6R4QHFvTw2*bnr5X^CBUGw%)=65bvwnK+&3?JXaAO%Pe-JA54Lp$v77jOsC-!6'
    'ULZyXCdAc}HNIVO(etp!)#2T}_)`j&O1fIfVAY9}7HTs;1rsk|J)rCI1>sTm_O|xm)9nhf2F0_hjDoYi'
    '*v?v$A0d)me<aH#puBtXU`3H!afT&5gfoJjuZEmtl&3X}dF!(}jU!T-uht`yT>_nAORNekO%q8x4Ot#P'
    '@+>2|OKH{Vsq=iYjO&5Bb&JpoiBL^~{mqIjWckw96zhr(+Z<04m>DH2{*2RErZ;?E>Klly$9^DpfZbCn'
    'kDbMUW6<BM*r%WB1kjT4)`Y54Y;%&M2yf8|9HG01hQEf)F|mkgjH{Twhh<FXVjZnPS2s{G)r)+pI(AUO'
    'BhTN>7$&#1?PR)VJ8tU*&a&GXh`afKtgBZy={g;ha#e1*xvjI7ZRYE2h&C=yte?QCO-x1sP7wazq3>zb'
    'eFY)I)%`*4JXzuOoMSb|Hp{p<)dA*Kj&X&lX@VQMuhDW~-{`b2%BUG=Uu?x=jsYFwQ56&YVfGGunC>;6'
    '>fI%OA*&g-Zs{4JY6A6Qk?~dk)TT0_pXCka*QaYhl4J6u5v=E!l%`+M?ZLY~aaY5UCOK3?&PiGcG;p`p'
    'Li1bJ9OgW=DC0c`>`y76Uxx{ZjkBjIA|F6*TW4!1Kp-$9s)Nh$qd?B^y9jj_oZae;74B@Gfnq<eM2b|q'
    'K&oj70|^#G_4M)`);H~OrK=9;)wY~z-vm_L#aA4!=7XIAdXDLrZ@cT(61dr!xkkCOGi6=(mDD91+y_FN'
    '=zv>pJB|rkLjX6)ggp6uC6GO365BdD1^_~)HxeUKKK9G6--WyuC=uQ<{DZ0R15@|+@4Q~Qv?}8PFAl;4'
    ')m@JP?r~nCe@H#l*O>D+SEUW|4C#JpvpdUsTHKr)461A2#jQBn0d)d%v_y;3c*NDF=e;k<HW2&7=S@v4'
    's@Ws1;6_^+uU$-Ol&xIyq_E;7Q;GuNI<thaoRr2UI3hK8KD|bSOxFq{{SCy%{jD<=P+^K*!dlrHPu`I='
    'SqTl$^Ug!rV12_stcO&=E`SskZ}*bZxlOrUUDqh>E`<LLXkPT_&szZ^Yen@gQGopp3jFkK7`zwHgG_C?'
    'z7xd|wmdbo`fkIjwb|?v1t(GiRXm&maBaVxz|JNDLE5cg)GPga(A9E(BoVdU{%_i`TH^y1$_-DZEqPqM'
    'R7w>9x&388G(Z*E1N&;VnXOTfJSD5u9eS?)L{)uqr!WlbV`$t)RjywH@S$E`uQH1b;r`c~7*B%Ww->kA'
    '>S$0|pB<POR~we4uxFa5bPV<kdCEX+R*W^BiNSOQH>;%RYic6HJ(<Uw+ZVUwTBYlEHWYUhdL5#^+^ITb'
    'tzuii?F_Lj9mVv-d7wC}7>>jeEWJ3~0@l*fvC+N|nIi;8n=WxUd4@1lKGvo`NL0%E0O{(*;@wPQ0Pl3p'
    'mcxYQF4Vq}vW8Y2`(}Jfxw&`HQ%KHK4Ti0})M(<)F$_0Yb{?k85Fx5c1n0MndEc6y+fc%@&58`JAF?y8'
    'AqhkIj0TCd-5CvaA1hPSCM9>~dBRX)KKm1k;+b4hQ6PZpC@q%*U%)!1EGNT28NY*koiVx`+b6)VKtj=p'
    'U6$+bc1N=$1g>WEM%pFAgKo|625sa9aN0KCF6<L;jTH<yl}CfKVmSkucy|$lY?Ui<b4D0G-=eqKt!Pct'
    '6^c5%Q<@OFqn+l$gXjn<t<7tNr5;;vYh$YL(6F7i15T4;pf6W-ALx5@4pwS0+T4S_k-d5njo8EL;@U4m'
    '6KTr8264eIG;Lh41Ny{Vz;HYzeV1x6I#MUfOBlih7&3(UC$np1IrO|zw-4MPKG=n(uO@vR^ojWZqo-K*'
    'xU`mmY_PL}A#8xQV=44BAdR|!^mLm}DQ>9^hPO(WLt*rdRn)yj0j%#4Zw1JJQ{D=kH(0J=Js3>)^WsLA'
    '^(67p8epAn)9~o1=)Uvyh5-=<9vbCVr2_o-boDk{5_;0CqWW066CVpBHW!EQ^O3YADi(qk2?2g8QesMx'
    '6qv6wIJ#EH&}*75wIyCRF^>j+N*D@Pd<_z&Z-@AqI!zXLjit@0y1>r+Uyo^ms>9zat@i|No|`7E?`Fx)'
    '3UqdnZJ7Fr%$>ToD$U=O<UxI#ToeeCMzsh_Y4Wd{5H-}Q5=|4jUneU;dBsIbhXKHLZpR`ReI>Wcv(l>V'
    'OMo?Qhh}`9Dq_0CA@nt6&0#O)A~cNAbnCOiAH!>9=a<BAf61*iATxCrC)eVNWPam{k~P0Z$<RAhx9N`U'
    'Qw23ozSfA8p^(LWD~W>(iGzzA2Nwkn+TOBSr|DdxHAn7jJ?G?Yw(Gq9_UTWro?Jcu>CN=b%juOpefIo^'
    'H&2YOjDLJQTaxw7*`@K1Gu7vC8k02!p{49NJD2heEAD-Z(_4@Q6<2rjb^nHQJ&Sn)=mI!r)OWl%@%=ao'
    'oxr0m^CK%s5*C`C6-Q>ASgx0FkHRB<XfYZwkGZ~0SrkzoMqI4@j0ko{ctT(Bvrq7G+sT%hq3j+5SiIOg'
    '&2EV8`8zYW0+$7$W0{H1nQxn(!;+Blz$AoIYMHSeB#ikUJi;9k(m1eVGvN{SsLkTQs?R**k}J+YHEqNQ'
    'Ug8H)95|L^$AF}Wa2Sw8Zsfb1#9kO%7Igy0@mNd(X2Q;<k!!k^2M8iG2sL5hX0v#k?JOUtWd+<z97d5c'
    'QQ}*PM}jyGVIEdwTXtx}R1(YdJd4?kC&Z%;kIg9bVlOavmcN|Os3K>!CaX1k7^=V0W${Oj9AL%mTx5=t'
    '@fv6R^NU{>XZ!ZU*`e?L`XiYwo=~t74A68Nx;E-K`Oi`l)=L9F`HTF=_;?5~{%6kD#!3`uzBI_<&M1Tg'
    'N=y*<$KHQOR))F;_7l0~!c)04UJH%<7`EnOHg5xBS!v@7@9p;WMLEnrtViQE@Y2QW+4bTDU}H2I8y9~u'
    'eo1F++;T#Q6IRCPXnW~+`>_C9`uiBvzlsKJ#&R`#hyUU%Wz{2?RGFZE+ko^uzRCu0N(Rq(27HJYD}^A='
    'rTuRxD1Yk@_U;=pn{x(G5;D(t4?wGG)ri`<Yc(Z$VPKYF{rGs!2h4JoWt%Mv|GMM7N$J~Vdmq@{r`p_d'
    'anBd;W~+38j_ByuUnd#m3;ybcWPDs%@%Hm00Q(Dz;j%)rs2D0KP9iAu%86t9IXC|R?q1Vy2>i0c|Kb^p'
    '^7GFxp7jAJm#-Pz>l@D3t)<1uMVbbQ)>@!_s!Fu7#j*!Pc9Xu(WG%sLfM`{lAGDL4OmCH>0HH<#!*Rfj'
    'a$fxwKPc@3vAOWWUTSE$;!CpP?B)9fib|A@;@8K=VC6tiu&6a+bf_{l5olDk2oBHgknYk#XkB#HMP`lk'
    '&`yrC;~TI3Q{06cJ;?ImCL;23lg>d2KR7o~&0QK_&qQcubj{(9k4nHz-txQm>53Vjz*pMKBN@H||M^}%'
    'JRVQh;=0vxvwpH!!`ha!brIJdO%@!q!qF|!^fM86H`YIpn9oNOxt{Sv-Mm=CtlyCAE&M~?6Zlhp4+{B{'
    '@u}Bngi`Fq8_(vm^_^^dlFaz3j7f!`2c4HA)0bebwcP^t8;1$cafwI=xz^H%k}%nWg9N$D)?8l7xHKNj'
    'L48b|3ATOsCm1zkK4F}K36}8(<DQri(|f(XoAc3RM$^U1#r$rJ2Nt({bUR!8ea6-|mxk+}8}Qe69NV*8'
    '9+<D|j@uwRUwS8Gf0`@_6P#_?<4H{D+v`=jSuo@um^s5%bE#}zF)}A+I6gOKi$jyW!naW$(=}OK0|sci'
    '0y%I6*6RkGCd(gpnxABZ@-pRbK%2w-d{8XkzZlRh1@2V{oLUAP76Iv!t0K#pm}r~LU)kb&hwZ)h?`i96'
    '-1(>8_`~+SzHQ$^|F@Fq6S7>EYW88gygZvVe$Y<RPBL_ZMzj1r24|PXmu0m!J|05Me+rZ6o2`R2lGMLc'
    '!sxsbquTy{UJEiElHt`S5#<YzRY3nPk{b{>zmxME;p?r%ek=O4BjOr3Wi*4eu5x>HTriHZSVt|DJc!UI'
    '%O&6+0F*sOX_2&q@NAZmCLqG-epGjLClrrR=IUs3G=9{AWav;$W{Y>AN|^Ai9vPVY1@Gs>9G~pb2mXq&'
    'v9C8XRE<^NW^;XwQJ8cAyqBf7yk&?Se`bmCh4KI<vrN=HXumPO1CNBhZU20(^vio%4gLVcHRyuT<OX;K'
    '6~wrWHPJ>{43#OGL`nq_=yxsaVV|aGPzQKa#s&dUJq|WeUyVQ}7sBaIZp;n?2+{I%|0v}JJsmvay$Ic!'
    '%sua6dlWx8s2}9UzpQ_7UiqNatmK1(W(C5nI4O~6l9ZX;k|l^kFo5xdl7W_K&AfYmt~UhC@$!y1Z-_~r'
    '?{NNC`!UfNA>}AfKN>O>s+Yl7`I$B`v%uR3ZLb_f<00dKnbb<5pM55rcIUCWL^$8YA==Q(b>&9vsQk)U'
    'QgZLWy-3`_0BURhRGuqYBm>E~OR`4F92XM>!qfMQY*dxD12#+JaRM4%kBrR{&77wV=OLpL;JakMbw>HW'
    'C6bk4dQVtxWke0O>B|PW?9DSule%pHAgAXbkU<+AT6~Xj%16Yf8>DIs;xO+NQCkarG|2OpJ|19?)?7A_'
    'i&|n~ub1}d*s<w;|LRN!dAbXaJ}zR-+iN+}j%<+&9_6VB^543qxWohea|1KE-tkL0pbkoYYI$f>K3-G@'
    'PkWEqC*lEMiwRbhs4Z;VXUM%tKp%}(qWW<MQNJD1fH8mTg`wO9`8rMKZRhysKX;hq5``Knwn-xMnEK4J'
    'a9ZwRn)zPoJI{N<=3ETbdX~v%L2E(tHUj5h3do~_=0U?DU5fz+sDn<ZI4HZ@VCLaN<IN2>mgJfnWP!#r'
    'AOZdhmWHv0FW3y5p#to4Lmb-}#1L0x49qwa@(9Gt?;D=2C+$Xi{eHHlH^`aUW|a^MyB_2|jFJJL&F2`b'
    '&mO@j8DFn)pA{3p=ih-W#^;d(unlO7Asd506{0>iMhy(`xS45$S{NHG!U~;3Onvp#a-fe{^6Heb+v;Z6'
    ')mxiRY*_hB8%+o{R{w}uYdc~GC`yzU$xobvT#=y#<p<w`^41tUKD(EwW5>XB$GG&Muyo687kwux^~r7R'
    'lE(S93HsM^pFeI*xEGjJH+swOE{)wG)$_Xtg8K)}y+c3|X2qhK632$^mi`0z=iM*gu4ZgR)A{BWne-p{'
    '=ZiJJ9Zd)$OWgE$$UD2;++G@%?TyF3og0{gD-0UT?r_rgO}ctc=*?)0;Bm>y=y(*DAEkFqX2D&#kb6oB'
    '`bXl=f&@ZO<bO<N>{0(iKN*_LkM_GxRInv%^%w;F?RJY#7UY%}r|;y0I(-KZAVDYKu5t+Py5qKKBf4T4'
    'dUjLOW>QvkYr(Vkp;xQ)8g!@V7gC<8GMyhB$WOQ~rRf$dvwg7*4rMs2K}d8xx@jv)I!E=ss76xDil~1m'
    '?$|j%du6SYTTd+jb;-XT;_qz#A<}*V?>}c4(aN#H$Nk%@=gHAY1#>UCd}6WO!qBNEJ=8MuzB0t^!NHji'
    '700qXqTJ|}&|Gyw;);O0^0E`8dvq{+7;kKI_Wf+Z<m(-0S+jaXyh4pTHb`~{kF?Fts3dtCUwpL<!M9i0'
    'RTw1@k7^Vwg}gAe{ZY?La`}%kqv5r3n)w8WA1$_5rRtZbU?Mvy^7{v@fR;fpZKk&rN7BIsKP0ab#@V?c'
    'NNfD-UnQIso=R&iRQ0B0n~0JW5s5`Hzn(2d8J5Y(eeH?(tCgL{()MhEa}Zlr#FOrnZLfyhE_2k{z?A5#'
    'tR|P%a;>1K8rD_EUyB?p$+2ScLzwmxzDsY~qwM}xxLwWRP+tcQ?<UiVq|XlW3pwidjl7H}wL=?of0$P3'
    '9<00vozhXI?AItQ&|i~YU!bRs!b_Z5Aq#akl6&i+K5D2Xw0lr4-E>PQ!~VVk@$Gl*;Z6JLw=UH!@>|P!'
    'r^9M3)FYKX{2&fJ+jH#L^*!p_G$Gtid_Uxg$^4ikfoCyl!>@4=n3ivQN#uK8Y+0PzJ~fY5`fvj7Cb1uw'
    'p6>w&64;4FEy7H0Q7^U$bxD#?$MgNjvs^C<XlMqJ$y^>LPUNyPow#VO_Yv8q$2hfo7E&v+xf9yN^?e>E'
    'VPY}H0~$Fn-Nd#7MqHYNF5#i?Q_CidMV8y9-iKeV_YqX<ee@!??3{tY<Zc9aY(EG>>Tt(TVyt9BB4+x5'
    'PdyeoEb=Wo@|+}gJxW{>IJOm87NEtCZHGo7Z$WTw5zBE|>^PpseTSNUn9$fw5|72PM`9YVfKbzP!;t!('
    '8?uO)p6fUf4-v~}da=<=avFH1A6e9mh@Ws^aw|wEi6UU^Fb0N)3C6LLxHe~i8{hFQ-}R|OfR$a}4Z=1g'
    'cgrOA29W$fQQ4i!J=~$L>n5&m0y%-mf$b9DVs6IFG;P~-9p5tp%SxE-1TK)p1#U=^C@@1Wp-e-~A?$Ph'
    '`~%Qq#z6^+g1QTkw|lB2{RCegW2xL5&UqT^2Qf3?35x?Kq_$}#eiFs7FdI19vK+@`vF|WH3>?nfn0pLR'
    'VeuH)%(6V-ZKq}!Rrd_QH*E{JlO#5!3^<f<$4y}0c%dCKn+LW{L8^te6D3h(dn5rS4s4VKArC;p#dY|S'
    '3v0D~4%vidb4C{RK)i~Y#IM2Bm32K@ROqSc99e#Yf^m0glp4}siI3WY!T3y^vb(mIAogg!OsoV{Uu|t8'
    'td{onQq6QC{yI0reZ}m+y`D<kNxZpCXBp;SW9bt3eX%}xIkRDw|95-7wYL)4)~IepP)+pIL(YPlDiQ8A'
    '7d1x#%P$t|<F$@7amBqb#Xz2DVu?@tcw+BCrSb>5F=74#Ud20-VVF1%&}OrL9!_{{6KF-Tjx})LpV7EK'
    'C|IvC0*{M-0ICSQV&12urli({FE+QRr#U;EnbIa-LF9C(QtdGNr{BK9F-IRR<=~SK#{VzSGkK5E*K^}8'
    '|Kbk5XeD;><r@*D9S@r-cyt0Um^)zt`4Hg~)T^U)dRZ)DTyRIL=?NfUfBpc5ZXHhl>3(V_==$=sUY6F!'
    '(P#TOER*u^X}S@0qHf8Dk$GNaYAU|FFsxxC3FgelsYzpXh3FPzlcfor=ksYX?3d<vZ2X5|0l6MOZdgF?'
    'xi@e7HfpduhvkYVvk#*!62?7*#pjY0okhicN{YdPVy~R&r2Rgr^ZslT7f1fEvPCKaMeNz^dM1jkDc~LD'
    'P+RCNSKAIR?Vf7&(8GrhjVlhe%w1-ri}{^MyF^otvwW`_Z*FFpf%VCa8<3cb)R?DKxV)H^xyIfEn2-5>'
    'HCyvGY(dGA$ee~rt10eQ8ASW+HF?LGFw*4o2UxM&nt)Xg@^}@|Q`p2h3m+Z<T}d#x;%r0tkEz_C)jDz8'
    'Z`zO5RBsLmRkp7s>BN&AHc12McdaXDwwR?zD8@=#;+My*f#pzgE|u^1a71RTMTNk_$(omqNS>%$nLVIx'
    'gm3l_aL#_yEX~TO6Gbgmp|hs>AG&ICUTnVBE?E~vq{qjko7IX7OG_-XFL}ke3ZkW!fh(bR<C<TDTR9^0'
    '*|m@im&Rny)phpPDVEJj8<fkF`FqqYi*$91MVMq>KTU6!uo|u?hL^A2ark<1Z4g6RWGdmm6)7`H<~%cI'
    '>q+MsHpD_kIUC7;&vzpf1rg*C-(&IL76V`AM5{sUZo1X7+xr=*07T7adm{$_Jd)mc#6Zgn46UmBcapuG'
    'E$j889st+ACo2Xf_mL#Q7A7nnecga|111{{Gluho5Hass=Gl3^$u8v%uAlO2GvD@ovD%`uoU^zyuSdBi'
    '>ljPhF}SxiwvHCm+d?{6U#pQd`jKo<44}lWssj>dvgqgc{BE?fH*%@P4qPxSjkdE)at(&;0|VH82LX6+'
    '^I%-x9r)e<Y>U<oY$dyDRl@ASeKHWea!ckLP1$^-!V1gtgK`6^l|GYvHzx}jA<2f3?b9E6>r2k>xA%L!'
    'Rmr;-2YrQFUaGIojdi*v^UEQTwJHi^K}C5hp^k!l)CXf-qy2)blB4acEI~u89U&*+2vh6>2NoFxiv_D^'
    'CM$Vd`U78FuWv@?c&u&KhuCC`qh5mvRJ0NCx%tyiz^k`W#2?lkJ8u?WK4@o0?f^g+2z12|V#q)imO{b^'
    'zy#xHvT&s;x>;1O>^?@fo!af`a$$;hwXzfy-Pav%xv1c~ovYcyV3$gYr1iQe`an0AM9~L-RS6nt8lhB&'
    'Mn+&JGuB5<OM6B5NqGshuL@n=K6|?vc=_}}XlZf!kPoC3w~nKPA~OFM49xf5-k2g@%J&xOqS>7D<!C_`'
    'sodM`?2}qx<`vp0Gcb2npiF<-!Wt6fSNYlfsng#)5Ki%ysj*OcnU^08o70|T-6F<t-hAQxe1HL1x7W8E'
    '`gslad|vDwVnLh_QF*pluE@7{nkUvlDth%(YNT^^ffC7}b50hUB}{E0e#dGQbAr8Xj@O_VuH`DG((^eN'
    'F?@P6n=`=5r6KSH?&Wv@)Pr_99=ALgpD^?*6PYV|qnor-45jK;s3@}dXIn_=-I2-?=j|M{t$e7dz)lm+'
    'gLpg2>D>6D^R8_%?#F6Gr~{4KA4`7v?Nis3O?6CGZfJQdm)JBthg*~ciS4*C^CRlgD5Nguf$zoG&NAYG'
    '8F9yCPDEoTazfW5W@LGhZ8_XKo=a>Km-#^)$ENA9#PnU?iy|6X7U3ba3H7;c#!<v=k_7OPm4s2uVHA@1'
    'W@rWWnI0^BzBZ9gIfvNU-zIX;DH`7GeJ$$v^zUz^sx$Qmz*j3g6?u;TJZ{r@vCH{Rv5j9-?C;+G`POGH'
    'wmI%ru%UW<{S$~Jie`F(SqYch3yv@4C(l0+bUHf~l29T`AQo(d>VUEofI_<X=Umn%z7(YF*z+YXP_R8!'
    '?_Ry4mJv?+z-WI&7LNNt#~;;k1J&+?7c-V>S0)g&?Y&`~J&4ov?S#(35@$uZi-CUq!O1Hs{WD!~p~OVC'
    '>n&JIfR|)5|G)V8$NHW1{X-#~eA=RPJGRjPGi=neYf!;WY7RSC##S7EC-b)tbdRbK!(@Xtg&6q{XHVAo'
    'gz$TyE|LQ{3;!B0=J6BF@gUG@_9$&L9e_J8^i$8)a4pr*P;E3&866(J)CBH(e%H1IT#=9>-nultBVbpF'
    ';<GI;3YJnbl%4Ve7|SmYXE4-mz2Ac22?|H#_xrBKI;E?8S!#VndWf2JV_DMk@{EdKJ60=|CivC9l&{Ay'
    'lM>m`%}{eS9_K3UvePBu(x}hN>~v@#sjGXBQ>(_gXBhCOTGrC+Xl8Y^va}mnC%3T<n^<2}$gS1lYGZJH'
    'Rps%{Woo+FUne!c?#cQ(h4FQNwpUNn>$6y1pTY1tY8*8sCGX8rJZdwY$`<QminYzfKh_quoE<h1g??3c'
    'rh4v6_WK6EBnvhnAlTkdHcL^Fa%;)$w;H?j4(oO%t)`3>fV;O|-T!p+=1_GhUZGN^cPI1YwzUA23h(U1'
    'imc+r`sW3CM`m-hEM-x{`hp~9{x}2lF0MQHvm$5-OTHzmx3Fr}H<a;=u4YRag>A-QWx(%di}i!?_ykO`'
    'OS8$XT4Wzee5~fE$T5oQj_uic+laE&EIv&Z^%iP73K5Zzc3}N#PZ6|?1n$;%)va6{s^coVINW>twF$U5'
    'NG*b7Y}>@C+q4He?iLokfY;<pw=Z+sjgeZTx?6oGh2U0Oyf6Yq6{OrCElMJFE4n4lp9_e15Un`kCT~AJ'
    'NoFg&E@6CWPSzQE7lmJjwX=#LRi|osM!bJu;4eN;Ci%4Gzr(6!b?$zA58AGUvOBG=>!j-LQ_~$#bQRyW'
    'v)6D^b$4&t?tYb>eqGmH)oIpr2Nd1+yuX60cSfsZTNR*-M63D`?Ll``ojb9B4ysg(COw@Z?Ot&0xEk%Q'
    'MITjzYlkmwR4;{<GYABWw0QAw&Cr7-Lpy2imSf~KHuIHiV~hQ&eHUm~<w7gwLmk!mu&pYmA1xkw(sk_`'
    'HA5CNU{8GNTraSx-EYf;59(3k1(E9z*QZz}Ev7+0%)}?59h1OxxXW$ISPaiF$8<x++`u6*3j;rLSaLk!'
    'gN3H&MNu4hc0!qDy4*EmC$y8;F_{<B$d98WOzgn7;s1V|5T0<(T+^mz5PR;KK1_VRqz|i{^kE%N`q(yy'
    '1p)kWsk+OIMl!qp+{piZfvK?<e=&YZXKZ{l3qy*tgI(Y{fT(n4YxAC15Uk?cQip}VVU^5c3CEy_!=}84'
    '^$wWxV~aa)ocehy|8h;PFBRHB3_Jj%5yPujDF!zyA7|-m{pJqq6~7Qyk*#*{yHi_gvGW|Qf5n@+OPt64'
    '(GH-#rQ14{EyBJsWL*Iy$c)T?kvDxLWsdeE(aqe$dAlcT@4Qy&0@(4r4#VyABp;2sA!^7@{45)ByHA=M'
    'E-EYUyt&U|@$Eju?H#tV)7nh$Bx2%Tr9^Kb(N#vYINX@tk`LIG<shtydg#>(RIaM2C2=wO(j3dmSP$Ao'
    'Ri}7L_3Xgx3)|uud?)P-@p!Qp)bd)5Cald$_5JN1k1F48E7w;)P)`Zk9_;WSo){eL?48BA<IJ{+_1zEg'
    '@0IqaBmEHqHx691+xn_5RUhp>SDAwR;Bc+}WKxs1!hx=QGB9Y+H`}F&8#|t~zQUX5tA-|McPQFLqXH32'
    '{8EU*QiG$OS*-PzYh*ruFrI+28DT-!$s%3wUT1I3{i<pS4PTn7^%0II6%U!i_QIQk<9;cIonF`<j@lwb'
    'NrQq4ow3o>(s56tyQ1-0Et1}CWt|>=Eg7mj85CF9gC6{ppPSrDNhTtc>&ZH0vL1$F-|bf;`Q6y)d_r@Y'
    'U2>vL@|pI?-eDg;G`{D2X^@4%KVUdvwnpnx+>Iq$>>28Oz(`i<t*HOB05Q0Cw4&$of%|k14ovA~UdC{f'
    '0o}9hJRS;OdH6)=qg!%kP!U>(XJ;Awz1WbsY%dK1Kj?}J6)ev?z=%F^b)Gplz9{vPQaARp(fb>|0_A-m'
    'd@hKDvBMJhPyN%~M*F131FY0qW19!Y|N8aU(RSc*zf+~sK}m`GN?`9RVd+nwPplu4>Ro$_wmNYg&}Vd)'
    'K{_=V-E;QZui@w+DSAZd_2kx0cuCaIJ;o}I*{Y^!-_4!t&g~=x<OlK+th}*W8EM?U%FmhX8QFX9cfqKf'
    '^}R@i9o|&l#Gn7%)b~#Z$8v=9Sr}D~d_uw5<=K8lqkfyQ{Xy1KaJe2nop0i&n`{j}-AWy6ze$%fDpG&<'
    'G{_-753nl?jR^N5+axZxlGwJ12cMGAW(l<uGm0#hxPfm`-{)aO0uQefhc>4J8{`!8{ubk$3nDt?EU*Up'
    'z6LpG*nY^SmSdX<r9OxM#l9EYeiX38i4)hgJd^sKZAR3#oY;(lAhBT;%t}1hVvdd(gZ2Ui%dxl8(==Uy'
    '?jh}4PQhg2fbhVJBG=(boJ67L&?HJM?$f|Fne9<GvWRV3E{{S#h*)5|K#~|%7KXIVHSsv%w!>)<m;lp^'
    '{UEfcYsU`pV$ZaR8+slIoyd)e>l2s7Ug!m!GtYP8IEeKkqxs;Fhun4pH!;J&bd%Wh{lsC87be^b9Ttbg'
    'G+|CL4GB<{BsO=6@3AN}S(Nwzp=}Nhz4F0f)U)H1SY!3d$d6b;UT6Cz>_6pr)G=LdIss5D2qN3%h#D)5'
    'gMh_R5>QGU8aN@)GQlbW%q6asxKZf3$J#gfUgB}=dX<<KY+^4Ayu{~`ZwHadVe6PYi5RynlaT<J(*ynt'
    'Z0b-(9H4~Xu6<J_QYP9MfV1&rwIX+;qRuYMI~$Z*EsV!1Y9@Qv916#lrmzE;t<vQ;nDJ4C-M;rn%Qhh$'
    'OYz?aHnbw+^HuzRV#JtC2__Df@&~VXmWk5r8NK0bGv|*C@Z@CyX3SQ}&Xud2VWEG#6_tU1zY@x>)tJjo'
    '3^K#0_n+Dpkh(OU|GpvXW0z9vDOovK@KmX+oW5I!>eBdG+&IMpEZdx#ruhGWF;qDJ8#J1cYizeGu>KX*'
    '6##LzS#HR3DUZ~;*CQ8&E=&DoN-(<>vypjD5*$`4Q`t>&nX1otuhLmK%OuA&Hlh(@oP+5ITem`s?#1%6'
    'HD6*%n3(m$e3<_*<QT^PR}73zQ69tpJC_8N7nHHZup+fUg(?{bznh()y}tqVuipJnHSO*t;qtNN`xiO9'
    'uOvDitIt(AF2DwU+<6eWXgvJk3pS$N8LAtX6nrMf{bP$?aawmF+O4Rb7-X})0WWiXH!<GKz^TZL`RpBb'
    'qY{D4*JuF!{K8<^vwDsN@{2yglMXUJuNEKkdAhjHfX*^<3l@}0>3k>}m!H?`^Q+`fvS394trmmMX9>qV'
    'Pz@?VmP6>F7z8j?G@*}%sR?a~r5DdGjh8VtM&0__eIe%ep)Tt;yVd89`vOL%lw5OB7(t#k_XY)glgzF$'
    'rSxbb-4W~!?Tv#!|Bt<Q?TsVL62!jOugJ+649OWL74L^?s;eoAs?v1nF(j*c#*!v+pJcX@nc4Y}O05<!'
    '@E5P)HP#>2_QJb1VAwEhVAs2_4G%CdcK(a)?w$GMzu<H3jmV71j7-MkMpmg?>@JZ^Mx1-^x#xY)Jtxx+'
    'D60+cY~xd@J;=rs>s0SdsRg9cI=Lj%#ZL3dMkl%3nJaRY$6IYV0862Kd7^mwWc9}y`Xb%`%p_-L%TE(C'
    'dYN%Ot-h%r+9)iT69Q*xMfSR406p*Y4nU?R%CpLCT-E_yi&4@-`o3!V(;h0Y8f{0FJj|h?!>|aVsvxb}'
    'n!Z!qvZ_~Id7NZ*V4;Fds@fvzF_UVG9bK)uF;r!zq&-wB*;1$vu^tN6Nto%g!jblHct<XV!_?f@9ni2M'
    'DH|@-(adN(>LofG9H${@>XXLnDC~gSq;-;_$$AiU8O+Lkw6?ViYXoS;7}eWhWmN;n?#d*rs5Ut{yWe>@'
    'UQ`zt8INd5q#4gBafYmlhHmnjp3&hN>0l~ZZonh(YLZ9upSLGu6y}smU*P92Ycu7Y*R?rU9`kmA{E8U{'
    'csVOy0rpwG0<6m7?c__i;%8MA{6K20r$*`gLDJ8w^Xp$HNpG5u;Pd3C8s*D3$^Y}tBqu^YUzZ&<d;Kii'
    'z|OXJzgFuzsoeuR_j*AmYz?y3%mF3XViczStHDHfa-AhDVP~269E_2sT&M=8gDLt~`2EBxvjW&l^{`!|'
    'l=Ql)N~io~8hA-&yK3nR{<qblznr1ngmgd85pGJiOWQ6d(`$8vOt>Zo>W}}pQ_y>CX?s-a9Z*?nC}EN5'
    'pSP;1{7lzW?)@Y+8^5e2`_r1z<Fs5_GQjbjTA^Bb=8RrQ=9>z?<$zfubM^C4%g9a3SNB(KDbF?vSg(++'
    'Ys^)r<H8<@3f~pmU6x<vPx)ZRV2{y)zEB~jVqKK>pW20h5<?mz$Zbu#Qmh>({P+hMe%vHY<4pmYn0iHW'
    '<^4)gF8!D-%JTF2JhvPp!Bo)*Rvj+hPSx!(Y@TjcZ5ecERXHWco!x}|tb8f@R*CnEt;AdX=pj8Q%bY!='
    'yL+4}@2Y2ht2L$2fAU4A$d<Q`8qI%`8k6y=^41awU#w}aeW~g-p{jddmLSECgU(hsY_Y#a9)+20d*4)2'
    'e_meL{;(Y<RD#L!j#LsCE}2V2c|b!!q{^AG0!KQr&j|^GFko&ZEMa-JbVU^V7K?rA5Q{pY=f<&30-M|7'
    '?pz|*V?jv$D0ZnYC?$>%ERtL@FNjD??EnV#Xza--h~0n(E)RX*jr`d6cuWXCFocGWqvu4inW@`t-tSx`'
    'Z8ufyTZdIM7G{o!cil<U;7&4+gTs=1s6eZneDwqTVWX{6iP~(LRSZV3*ntXN9OdWu$A9`o$8K1fY!CQq'
    '6I~{;waYf$afo{`xSfor^UgCm!yJ>{zV9wL7=1>r(<i`bW^QMB??v68!MeTaVXMAkkU#hBT-}J(D|d{h'
    'Q+dEA#Jrtf;(h6R>TZg@bB)>NdI&ISVCd^9L4l1YY5KGWOUe+PUA!aOeelx+GdShVQ#v^qkzt1o$!xZ|'
    'r<z{3$3r%}et&1yZ<&*f0mnva$xVghq&m)VN2lnQC9?e4aixm+4G)Y9Pjgp%S?$I0XSYRfV_E`E7-_T?'
    '0DY_K6wq)X-l!I`X*yO3I3-Sc*R@#rwDD4hvx(434?WedCE?$FXqrQA_My}4A4(3liRcx?&A+u=8mj5('
    'Yr`|wt*>VVDDq@UcB+41TLn`a$AWhhC{c-IH9@bR$D+in&>8~Z%t4esZw960VdchqMY~w#{jx`#&CVk?'
    'r!7Xh8cdn_{xoA`JiZ={QH-R(-U{-1+4ux8cvvV2n+%~&*TFiwulmIP8P-)f?mR^!;wN90Be@a>uj+9w'
    '@JVb<3j=+5!jvs|M}f>cK%&8Ou8fJXS|MgRC#h(iIhZ!Hf!adw)WLe1VSi6`lurqJJ<A^TpWb_L@ARa^'
    'U>5>w<l-x@g_z9L)n~;Zof)|mJstgDnrffxB<1O1f?{8#SF6j&n7FtzS#HAwPR==Z>BHk<Zpj~q9+mC`'
    'G{W@3FEq=pcho5XVjw%q<5C4GJuS^o692sRNu6WWyAM<IG^c-0gTe{BmafBDxW4zDTmco#fzHa#RA`pI'
    'GMC0#vOo;z^5sEFV(zDw!{_PAm0C?%AZuH<zL&-4jAnGGVheP0@WiS5`O;b-aAm-+Mfb`V+D%?qKLAAc'
    'w~&c4&osmc3Z`$=<&MOA6np?q9d>{PNdz(~ol16hjyt0<SpBfw^S9&a>ym!o`UYeno;5#S-F~P#J6uI%'
    'H|@J>N2+BHQrG2a{`VROt(ECJiQYWV3|w%)T8-d0822o9_@sY1Nm>n;Ian=Cqo>IgBwdvwO;NvH%+d=;'
    'NoxGB6wRiw5@eU;HUyw#=~PvrQf8bo6DTJc*RK%?Zr_hP4+HBGl^H@}`yig}C-BP(-H+u{A-Ld0XGLmR'
    'o7QcG?OvS$DIMNutEspij1E=f`(%3UVn-EMXd5j_!0pF{m|Pk66nYD2*obZ)uT09c-evxvF;QZL7RRon'
    'i-Qj(t@ot+yRykjxvyGAcTSnM88A;8>o^TXPY$tANM|-2<8>lDm%*^|0#`?7??&uqIv$M|vkqDjCuKs0'
    'OKW>M$;_!@63VT%On4Eu0C4z1dCVx8j<xfwQTz%Vv66N-7g9`h4GH<>i3FE*cJo|M`EWVmql&fe3n*l@'
    '|HsK#>olT{;IZFJo<17UhFamcQo)U7M}S$<5`erVgLLkhs*#6P3XSYUi{3tMr>yvBiTvX`3O#P%v0nB4'
    'm5R&ybqOYrRYuFJd_?&-s@zJ4;H~k_K!pYts#uF$44YLzE1uT6cR5U|U~0VOKP}r@C24p7vro1}86-(V'
    '(h3s<^ke~GzysDO^!*F4b>0k6V&KgSeg7N=Oudn}>hK0Es*{S7e*Zg4e(U=zvjtZt`A^HD%upa938EyZ'
    'DX;0vy--QL=LL0twO#26cLl4aVAE@CVlJwb4LFsHo~>-FVOlD#FebFe#vXs6x>d<{C*QL%7nAAu7x(ZV'
    'kY6Vg`aS-5XKGClMXvCC*OHVGH)LT<IU}Ac8Fj2!dQwtX*f!&mQc7IOh2`4PWj2cgAw&D_)Edd8YX{P|'
    'g-5AR?U;trp?1J!NQ52OJPw!?z7P?kfwY4_3eTo-?ASt3-**noVxu_2#&@{IWE{(YM-~k|hd2SHGWM|m'
    'jTKmu+kx*#%o8rL0vi@0eb4fwkka*ICd*{lI98C&u>thftknZPh5qH93Nj6Tg^mWSdZw-#&kR-T2}DdH'
    '-xIdSoS5*~A`$fjkD}1^g&%k}w|ya*?=lkEKt5i~nHvP$^|6qaMeeHBBWdLMk;S7p3JCXrE?6L7%dt?8'
    '4ddC8N7D0vDx@2PG>AQqMbx%Dm;s9<sZ^~;aoxs`$q(w=hhzM=3$BLhSarYCwNI>WwJJDOFM?Egx<Z2I'
    'ap^}@!>-IVu@gnBu=px@iCs{tQ%zf{RsiBoAA5I?tAH6M#H>0ORGb6OVpRDZcuVulx1+(l#@p)sWX0-q'
    'Ylv9`l~$dAQGAGC^ggIMKU`P&=~jeRkp!zvw)?A_-q)nY_WTG@{hNRJ-~INV|NGzk?f>@w{{4UZn}72!'
    '{^4)`?SJ^Yzi%1aKRSjd*JLpI#PB~j!|Q$c#Om!J`5*t2|NOWA)xXmW|NF+_cwyrcga2@}cX=~@n<?t_'
    'Nu{@l>woy$|NS@r<lp_~fBmPw{V)HI-%ov>*3J0D@joEPuZ;J!#@upSK5>3a#(dt4*Q)*>{{CP7=I{Qe'
    '-#ZbYZ$*BR06(-*k1=A^-{zAy-#*HJ`)~e--~6lpS@ZpG|JA?#?Z5u-f6qPp<#pgsg5U=f1X&{>-H}f+'
    'pf&S<rTftd_$U9x?;F#r%4DAy{)Z#Mv((Yg==_sT66AY(BSxKf<3)$vjK?!^@<|Z1=MDV!U;O+3@IU^Y'
    '4h3Y*fdB9R`lrA7XaDve|C@jI+yDCi{KvofPk;NL{V!Tx{6By5AAgj>qU4jMiJ{;Gv_h4SD>0kT?qQLO'
    '<fmNIqvz8xUnoJN{<@|05tAfz9A-H*h;54s$MM`q`i>-#6Gk!TVH^gG1WZycnQO-`^YFx(S%J$r@fx;1'
    'T3^C*okM_K)h{tG?CF?;v;~l4xN8-Wv_0y2p7bNiXy^#|FNla6ao4l0z_J(<#1EP0`_iJ)^?786)U)u!'
    '-Hl_b)+!bgtdfu(vcqCdCzEsmIPb@|<XW6f$CE9S7G4yP$n#>~r-8#IaYL86Rvg9Bg3mnLVN!%Xi$eH;'
    'k}!-tO06*TY{6||c_p$z;y4azU`NE^k#AX{WnmL5M>-;Mg^Xxq(@+STGQugb0dpdxkr#-N&^Yi&RRmPb'
    'l{g@l&7Bz52fG6EB0zq&v@8-vuu-8K!Uox%9oak-Hh1ID65Qe3meR(aLrzcv15NWDDq=uWF%SZZ=M`6`'
    'E!2J{-n|`9`9pzqrkL18(l(bN=hSgzNF12HCwx!x(2Ia%Y}cV7Y#dBjSR@cY9*!R|D{`1{Lk|3Gb2B7e'
    'u%0JkiWQ{i53$1O6}i@pg?BAQa7HYcGKnIfFei!v5qO@<U5hy(C0=CP5&Y;#7gy$5mPdWhmyuvz7`wbg'
    '+7ly$h=>!|IT4YV2Qg4PlQsx5Zd2EGZJ;X}aZhmK2gnYR0m4FjfrD_UhnBRh+}Vv_uV?q>@L@l_xYI{t'
    'u|E~p10a4~$Yk=aPO{KJ99Yukk#Id3+ad6<8`*?89_Jvb9U`!|munL{5FoK7W1KUW1|U7G&<h+X4XzC+'
    'xz7?(?k{t9`$$@I(I;HBKQ3J9f$(h-N|%R$5Bo%@gw3|F=^w~G5NbdQw(Zy+4>>H;6CluqO9ZnBkOn+T'
    'Op^26YkRHvw9gYpEn1NWgz5k(`%>5r2&d2oIc9<0v8f*kZV?fK&<R{0{tA@oF%bbhGZ!=tDA{n&E1HOD'
    'vOBZF#YBO$gv}f(LG;;i<OD2~6qLT>a~C)%jAO780_t&4OaYBt5RtY3iy-8TJ6_w1xgL%w8TNJa%nXwy'
    ')pY9eR^*Wwv<wI+kPmh&JwM<CWe2F35NrxZ09HKa@_@yT9e_dMfWopUh-Kdgf;G3m+eE4Y$$?ny&&hRv'
    'q6BNvZc*X{!WCd6#2^boi^#zBoRBcrXEsO!4qNEB0U@C4eG4QiECv`ZvOU6xC&}Fc)r&zUJ0cEABzz!Q'
    '>bfCz$h0^}8W~1lOW9Ur0S`ES7?Hs7SZD>@3tizz!NL|0gL(7fZC{mh>g!D8BHV-oCoVbjg&m71as!V7'
    'jYdk|#2###YXSN=J{N-h<9ZQ?b-=#*L|Bo$8#f}BuI<FJ4<?l#%b1B!1_Je#L&2`}y$~=2%FYKP3*@zg'
    '=eZw(<qRU*j)TY?ZYH`-W}mzvb22T)1_-3si=0@1ND5*wk1gW*Fgc65R^(Io#PgXYqY$K5<bxQ9Kzva!'
    'jkrZOt%!nReiY;ySl<>0Kf?7b8E_6F&iAlPo^)MI;&rJEkYGI)L?Q9rfMd3?EwJmPd2C=<rk`A+D5aYm'
    'm<{MnS9+46J|#Ynsm;Lp4q}kzVeAM{rM}H$%L@qOBC>2Jbi618)^KUuw(wgm43pve$%V(l?e+;1aS((t'
    'i0}aBOQV3wFoeZ~)UkXZ`k1;Q@CFCH75m&_v2?uH@&mBMc$w|y1oWHjG6z_U5(!9(BL;iUz&LRjcvvn2'
    'A!FNEtkL!?2HVWT2p;!r4ofwM6>VT)$frL|&f@AR0q}7B2!tr`h3#W|UvL+|fs_LH733P2-W;}@xG+^q'
    'fH&oU{Sxt*I2H&(+pnzzvTl3oAUt2H>7Bj-h+fBKuy+wC?U;sv7h(;~2;?!SWCy&*2=+M&!8KqqiUsD+'
    '`wqd5%dQ;+W(hW3$5%>6>%uJS<?eQ@rqmvJ;1ddlt`4lhM%^r7Z-USlA^s;N$`&w_S>$71-#CiE3j*ou'
    'g9Zd_HD24g)AJCu(9Vd2gATk;hzDMeCw;UZJTNF67k<Zbp|%^j@C>J%!h<1=!<fh5r!XOWCoaK>zKAW!'
    '-M|mwU$iJe%K=+Pt_Oyjg{GNsUEc>Q+64mesElI^L_W5&_CbUNO;M8R(Yy;0zUNX7c2f|6El<Ih_r1u1'
    'iG;vXmI%O1<^d>4$ECguefS4FoG`W+I5#v19lIS`tr=(XVrenUf=T+8ARe_rhs7Zet=J~Q2R|J|t7ZGt'
    'j=11{90$w?Q4E9&J1-?K5wc;RM_mxtG)9^LJq#WmpeOJpVZgyG27|-#z~jKa=@i5`SmDA460$?jp_DX5'
    '%vvj(rhH3<fT@8c5rg^TFkn~?wCG{5MaCSRJ5GW)21lL7OoB>s98k6dOcl?wh1GaDTkCH&7DzIL9R}L~'
    '-0;|mv5;}(L=0_ZVue8N@Er(Pf{Fku91JY*7raOk;&{a4ch)f8SQsC(**$dWdZ|m-OPti+(n-DL8w4w<'
    '9|Yih`k@5`WPuIL!BiCiwt<&EY=Vty&ld#jG%h7|;8B>a%^g9Un7L-SuVC_7f3#rU5vbS@sKW!ZMKC~^'
    '%>xpG`AnTCB9s#_Q>Du#sA>=F5E_GO01g2A-UW1f+~B;m>)F$;XD@X<drQ}IbN1z2&nQ4QB$gzgRJeHK'
    '%?9$3;9B#LaS4Vfh)&-QVi#<UAhazHY-{YH4sHu)q}EzeXR4>X%pQ1|J?&-Q8{kRW?Xu`@!IqGiz+MoL'
    'NiMO$FAP8hgV$sGA_zPQR)+0>>kK*<ln)wI;Du3-1ilkSmK0@N2_K_BV4+&Xr<Uyno(rfDA-BRXjKIwT'
    '*$4742tWuE&kJMVtN{KFt~z*Lpj~UB1kK2vG9#0AcXc<^XPy;v@R<n6G!XW%3LBIdc*Jqw+7?hH^Xw2P'
    'lmeZG;8KHb4g|~`ta8tdD_h3%@puSag%)wK>%$VGxyVt7!ELi#$D$w|m<$=%9H5)gZw|q%bm4D4(4`ZB'
    '>WM*uz%GJ13&5q2V8+D6kX%TXuqCXx(`U1MaP4U<I0uCrQILUAq$~_DEMi7LVS)i{$DVM&9f>?)NpM1?'
    'Pk=hXK_|Y+1<aMI(Lp!Z0hl~IB8IZBPFnjny1i=ADr~^K^c-+Lz+MX?8c{cv%wjfhOvJ&w1D_nMR~zkn'
    'z&-{0!}q}lja=8_U{1EQitE9AD9GzsKP~XIEr5+u4C6|msu{JxA#z|dLMxCw0D0hnspMFIe+q)Ycfeir'
    'L43h#EQd1(j8p2~Efiv~AY#VwND6t$wz(i8awtd#>47Q$3(HgI9(DjWBX~l@A^`yxJ_OTC6nJOj;c)zR'
    'Jlcwf>0;E^T`~KLxeDW@4hKdNECf3&l4#~}7!ABJ&-WY`gJaT;1x($SK1|sn;HOCv$B`e{t{=N$31Jup'
    'zUzC02qzW+wLFh;&!-Gjx6fQq+JFJ{=)w5#LB0^5g&t+Zi~X2@%k5QOcV_=bs-(x=SfC;ZsSLq{0IS|3'
    'ARE9y1u6iC#|^oQog<tu6yT{kE)P(9gO6%~D-yuQ_(6$Q5n!Lhk;Qx<eY^zjdI7jq02&W8BM<%sOtSzC'
    'VgjCd;P_w;5RAvEi_>7MAAETA+4Iwj^QTw+t7rWSr~mBY;rT`93&6}agdnmK!88CTt-pK@6eovgUS}lh'
    'FJ|K%cb1c5{tfgdkxcRi1a(q%us;}KDu6m@C<kwCa>?cUgiXtVm?ft-Zv+|k$rKAp469G15K0{kf$$;&'
    'tS;Nf3XUK|IlzLsRG-pTNcE;=V7H2Z)R~Olbv9m1kZ^ywARyLtxiclAlZBR<m$u0fTu+1RX>h#^xSj^r'
    'Ye?@!6jB~_ImRj8*IK~Lp)$({a{-1lYJKbstEO59d1!}%Ep$sJsr677-U;aPn+3gx^~ofNirGCa+<SxZ'
    '?Bw0;uq^#9Mz(9=d7Bta=F7>H!477{Tq^Yb9Of{afPDTAcp+`WQ+D|NVt^7_$Gz`*OEvz1fu~>%@vAZT'
    'I2QsenwfaM+TgR{0Bcy5n+7f-g_nW?cY$cjsPcN~l#IX>OZRrASsGD|GNfTnC|nu=+OpeCU`-UZ1XnJ~'
    'U?gU<+R&W1uQ;qOB;3n0#r9`oUY!=%pnna+R}ebMq!9yyX)|mB6Y#_w@4ppTns8R`^&RIZdUhl7W^kQI'
    'z5%%&jb~u{RaoSmBwYqnLAud%5QPsE?5{QGM}zOtoB28&AREc6kA=1AOFhVH8D%A%5-_tHSZ`8b6X!XW'
    '63J{<LD+08y8@jSzMr7&QX9KfAZg3;azPV!{QS*;i;<S%vr4S9p?#O;D|QOFUb&g&wZevvQh6r3oSiL+'
    'tLP$RP=iMxWw&Sjy@z5BCgG#;^mbPI^|bcZLxC+G-aR3cQm^hv6;hjl)&|N{Y}VBmBh1~rTiKQ>1ol}u'
    'o`0M_Yf}s~nm+;xDb3?rQ8U%2RNW33kSdg#>iJ8d15agN!6V#flcWUttlDtPhBs^d3GaL{#nXeuOsT;O'
    ')pEYt;Oj8zy`AjTxiZS@zFlwVr_ayoy|~)0n$xbk-zmeu&z0X%Ddp#*IdJ_Mn!;t@$5XurQ?UNUw3490'
    '_a1{wqoq`(S2HJXqc>z${k`+=Cqppft4;XwW;{tqqVzk;Kd6cw?P077nzJ!*;9x|`(o->%OEG;jV4^&P'
    'HBJIZw`jLi2LPzcETIN~%T*D7R5BGHTmT9Nw*oH?AcW_ucvjhcd^8n86V1{ot05LfbW9Kd*Oh1}ef=tN'
    '|4%`G%;uLjLd<K!xLjOcBioNh7b<%6oQ%Y<yo~_{AYemG2dS-A)jUy&5vL127@w+2&(&ZkM>}28*W+7J'
    'hmR9I{53cu)oF3Hl{Lt5Q_33wQbosa0a05z<Y^Pls`@b2X|p_}4dSXck&V~?9BlFt88(1$MW)xH0)1_g'
    'b_FR13N?MR{96e()S$rSo7MDERvcC4-SovLWcpgnt4h+R${hn6XZr3NGO8?yGp^OefZeEFuI62>JowYc'
    'D$TFF6wk5Ba`{idFB;A&6X@g7U_Ky2bxXV=ab{;<n!RxC&!ikM81(!NcCxQ!6XihEu>*iZs=cONKA;+~'
    'ifb6ES$U9(w`|L)Mu6%ly(Cgo)fCMlpsK4}X_{XFS<G+F1U7f9@!~hCb%s*SwZuwY4CQRx+NvDh{`%_b'
    'd3om|Rl2%aMg?i6hTV9*mWQzcrLqmN2>~VmzG$Tg2}mR{8(fd7p&<KaC1I9s+4<-iW_nvW#E>L7Kbr!%'
    '&T1*4QDS^@)reJJl&z!(aQy1Ra6PC~A;6KN_4NHGi;9vk$7;8eF({D>fu3m<Ai7!k1H!K>#_zKC5b8>p'
    'pN+<EhXRIHI<y+WE+ZIKxJ<41?MQG%ZW?QYO88n1`$)CHtmb=WlKCqKh*n<a*9%(t?ac8;`7OReR+|5u'
    '42NP~CpI-k3+1cDfQ$O$DzmQEo8MJ+n9{AOp|^5x*H9gq_p2+7%$h4Zz8OP4U3Sfv>#cfuK!XCH)|+T2'
    'RK{86ePu{iT6@v)=?dQS<Op7S?A4A`vbL=XLe~iit;48nWpDWJ3QSf1eO<lPagGaow2H?FnL;t?M7|y`'
    'rn5%_G31r8u>q#aX;((uT#U!n1D44gX7%jxBxqe#S!M}a_nN9lPV0^2YpOnl!x4JT)m+^bgePQvQ|jF^'
    'Rd#mge5dEv%Pj!M@h=wRIk{Zi-jeCNa)<f_CwWN{KW-_(lmR2q&aty#dT;Bp{GmV*%;bC`A-1c*tx)_n'
    's|pV-+Z!@}Namz`Vn*)uzgU2F)aQER(E~EA3L?G1nA}Gy?_6w4M8L2|Qy`CLvxRuN%p__62?ZMXd~7<H'
    'Af(b#aSOOhY_%k&RYgPrv_#lsE{rM_Jq9DEGUn1_-RDWc^1&PNV7Qo`PE}L-s?e5_>>ErTy%fXhtdbYZ'
    'c*;B^gWI1E<~Mvw-j<89Z-u2KOnnG>*;02W3t{FYOl@czZlgI!6-|^ofqn;SgEzxnB1xZ<#Y~*tj7zHS'
    'U7!-7{PV$xkKa}XmXXL!-fe>Eb*Ww%z?vL*PNw8m%*Aw82U1qB*B1us!aY5ouM22Xd{%~}%qBctc!+2o'
    ')tipG=Z=ws5jsSKR|b%mw%-kA1AVQdJ|HwC&`PVdS$7$Q6@l!~0pDaR51+^>xyI0HsVwAOqbTjr2JF1v'
    'XmNy`7HMIeti){(e8x03I7qRzTAMtJ?bfE?3S^UckOq-jBnS<I&x%NcptlLnHik&WYGc?tYM~Z8z7=jJ'
    '+&MzwnS_Y});w85AlJQH6JQHvh(W-4X<``g`S(B<r;GU*OVt~Oz2<crhF;`}8ysSnKW$=|-9EO75sJjH'
    'DOOsS!KUDD6TrsdZy2==Mp(PLvaAfctQ{iI0;_O2dk64*?NOS9*87Ap{5Bj&f!WF?$6)GCINI9%x2u4Q'
    '=>dMJf-okbrpRYn_q76BZ)~>Ouc;ws+Uo6(m2e}&z9hpTCG2$@gUqyT-8V!!$<0l?w?!B8ISc?|(-dIW'
    '>d*0F1gwG&NOJY9PdJ&(OWlgkkFj1yvB0maEfk7iD{s;q#PnW;MwL0Z+hdx>$H;l7#-MMQrN$s{#urV4'
    '&cz!W1JBseCSc_Z=*9rI1{O^~E(|o91e^;zngYCOcQ%GxWC$7onzaBM1Kei%nFG9G^Hm0&FII?#OHWxw'
    'y_IEDP_eKsXk`-_f|u5}OspZpP?a6DEInxkcw(INCMap|rFKwnX$LifnwUI2G<oXIw|T*<ES%gm_ewQ5'
    'wnC}uahND9m4k%#S_B4uU*Nr&`l~Wlq--<uBCVWVK253!$|IfD!qe*x^)eRLp`8subR}Vjy0BKa4ORYC'
    'vt@2xvr|b7Wm9^K@<eWw;a=l9=N-VBWM*XH7)Z^~I8ULysj<G~22N^sT?i0~50q<F6Vjy$n+d+mHLiU~'
    'o~t}x8_GKWJe%lncwKnKgj)A-I7<(;PIT9oSO44_p*>es*pdwBW}s9_byaAf$)R--dDaDzqs)3I&FiGu'
    '!lC5)hPF6_QUWc&UsDV%9I9ry#>A28nhb3UGIx=+KCq2j*J-}90&Mu)b3I4AjWKfKrOngH?VTE%LM}GP'
    '+87~gqM3xh#+^yQ36moft4NavqU+XJORx=uC%2t3<|U3n;F}jTi~!#)i%cH=ZMA4j4pJ!XOb$?NNf|vP'
    'Ei$l-on{u;T?XOiOffTOqj&d|GzB}kXu|s>q0lzRV5kL5LLM*0fBy#Me^OZ5zz{Ro+x}?6RB6lUbTO$E'
    's;b<7tP#{LUZHXLD<y976m7H4QwyM#bzlsxQJY}1t64^Aw*m9p3HG5h1v#sto5S3#nT?#rY*oodpcm?5'
    'Ban-gu$cp@BJJD!K*^li-2mE5=T>f}RRe0O^m?gcZ3ntisb*lVlxa^X)4EWzk?_Z(8CE&R#D!acq%SR9'
    'jNi^`#)z+AW&rP@kb}{nV)@q`xJ;cbeRa0sZM(vS)(xa?uCiH#FPYpb$JBfjt6<6%V@2D&z-^mu%oi*m'
    'gf{H>f!>Bpt^URaWg*#_Qtg{~H>2RQ=&qF$k(XNuT6-(Bnvh(&&KMq;Dj1c^_!r2CVvx1(^ySM_=_IR~'
    'f?{XItJ*Q&#A;yzHyI6~#jMRZX;HZ<!*@6ew$H=}xuT1@Y@^W_&aUk>7$eGVw7EQSB}2yvhWY|gw9Js0'
    '8SwO%peIuy#T09KV6&pB&?$FFr%k1_QOa3?&ykI>jJ-m!V#<Tbl1OEk1%_qn4%I7FlBvG)6}eUIW0PdU'
    '%4rd~DxMeOmy3Z4m@H`HyW0h`t0&}(X4k@jX?|zSTbf1qXl`om+&WWocqj216!hB&+O)x}i(6osXD~cP'
    'Q>9zVc1~L*t4z7tf_dj|o06mjyI|CQHii9SYdS%6Pa(RAL7l<IGH#lpx}KQb1+kI+TMW^dA6p3C^s#Ib'
    'Aj9&O)6uiV92`SKhf=y%d3rEXoA-7h!&G?iapus*6ihQ1T?1On21=#Z>1>9TQ0IbUY<SkNwpyZ;PUk@E'
    'bfIq8G%EnNicP56%`*(y%nZfZGP5)gvdhe`nQ67QBkfsNnf13fNQ#p-oc1jkGwe2Qm=7dFHwMq4Q}9zo'
    'OZ_(~F*UVM*05vj0CSUyOoPsIl_8rXvwLQaJW{}V-+Jl3)djxdq>Ww)NjtRmm{qB~$yChE1o#VBcH5dv'
    'dq<!aVU-h@xOmKk>Xz50NEqZ0XDT9}-wu-(c8%et0Jb4M&7;(?^Kdp5q`vR4*$IQZ5xnxPjDj*^<MHH-'
    'ObAm~<IU!x@4$iq??m&p>eOJEqj$`^4UT581$~z6LCs{d&DsHL+uE4jc2Ho`i?%S=Ub_BfnE_kq`vz;Z'
    '>yU688YbH-W<OyiO)_d(@J*FLtxGX2O}>yIGy7mJS#H^)&<Gi-DfTo@O`OM`T|B`G1s7y=U8B%-zHV>^'
    'RNdfH+T9_0O43k)=vnEtnN=RkK1jNy$0fTFe9_LOmF=S$Rx0@oXmpmjTS824`^d?4^P)HSH$!|TBF$T{'
    'Z7PUeMCVQA!}PX?7;Tskx0bB&)l{f<jWw<gZ}Q^PF<2_&=~M@+T25M6n|T{VJc9Lru1gn$N8PL2+Ko@Q'
    'bI58G&(0GH&bqgnwIM%3CA&T$lL?@_dh%dSkz5FlB|Vfgf=#=coMdFD)r@%8XVs1)lAEv5Ba+PxYJ(-F'
    'ODy%J-aG?Y9#6z<MogE|THjBT=aX4nH{{k8LVFsah6MZ7l#F!w(o2SQMVm3lsf3v^G8GR68_djx&oeC#'
    'v1{5l<Q-tQP35t%7;p^gn-$yi)A|M&$#^S5RU2$hQWW7WI)x*2_t5Y+kU6Fn(WkhI{##f^f2h_`8g!n4'
    'mQ(GeQ#HXsOBy+UGvJuqR<;T27Is|K3mnXD2O#c-4YIDD-;C$uMk!a>ZlS9>YqQ00K5L?lvlFW)aMmWK'
    'qW~?0|2Oux9d(~WNON_+lR8@~yq;35;n-#tH*FnYuH=|VFx8jH$aRgD9eiWbzR04cp?$Fuk0}OBh{vRu'
    '=r@Bm;KNj}@wDC;^E)yfVC$Be5vn3kk4G~xt)JSI-DnkGLjP>uUIUU8ldVRu&M_&?yrA2HcXQ%y4M&FL'
    '&>C`DX(doV-9`(|uSm0*^HidY_Ykn(XMlbaCLs3w?vD}q0CLs!+du&Vg&9>HT!$YOa+=>oSSP{3t=U-N'
    '2KzJ=`)MUo+_fI=nt?EoA~94?&)#5t(;8R0)&V_Vl{2lIfQnpvA@FKG*eRgrxOw@uxo#tYn~j+plsg+!'
    'Hg#VqxrBp!ptOkzxY>^Bn6T9ZaFI+%li#Nb*?q3DZK7iUAf$hzF{0&Tz5M!3$a94f<sHK}OoeZly1$+C'
    'YUR=<84q}I5GI)1^=RN8rzQHE)I+_*oWEgG+91u4u9r5uvAnb8&AG;)s`g!6iK7irEtsR3y=ccH&i8At'
    'eMz=pvs*rIDk4$C9&rvg#>#kYV#=Uw6`CfM6{m?(6$m$(C5+{y3^u`0slmhkH6o-xPcTy7KrG~Mld*st'
    'QPdLFiLG(^hRn%SX@Ht{9<m1OmH2+%qzd*D$kO7iUUE9MDOanj8l~NY@aKT$QH}n*IUu@LRP7Q4*zaJ8'
    'pSlf$x8k{xsjb)7QVd~5Q%$Sy7OdKs&8|_<k{Zb4p$))m{MLe<O%#HRTfwMT>i3{q%l*-tXzccX5yu*h'
    '59D^Pc`|Lr<Eo`n@&L%~cMYNeNs&FUucnK^90kc4nNHuK=UPuxtxv8E!*G2JgKU(i`Z)k^>h;wsvse)B'
    'zg$o}34)&<-(styMrD0AU}9XYS(d_<X}0MYY#Fl6K<sQeR)3%dGZoy-Z$({G6AA8gNEf${Z^?C%u3y<u'
    '+)(K25Y6RItwS~{wiVpU5VO)zO;4Q%s<VpbNX)=8i^COQBP|^Z?F*GTLU6SH1c%dS2u<bV+VmTVN_`(-'
    'JbgTRGtd~oJDr0`Ghw+2wQi)WpjF4V8Mi4nw+`Bd<Qyl1VJoj>G<D|~hHET4ckfISA)1s3PH!8Fx-~mj'
    'p@fHvDQR3kWMf)Q5{A+lH4<x^GivHS=B8#$N^Z=v#ZY28`<6xVKrd-oAV8QXEtdix!8-ap-G+uTegpX?'
    'V{|FDTfneF!m<;)F4te}j%G#(TnyNawo94^-HPEgV&npF#+YvtcFU|Wg#r8eXmGGxPD3KzTtp*V<wD(@'
    'QHIY~=xtUjT2pj|VjW(aCdB4w?Ob?J9YM9Vd7WUX2J5YC%p^S2jPo|Y8FCEF<*IH2y+`L@nk>ecdr&vB'
    'x1L0!csRMZ_FdCNnk=wJRImxn7!_=QZkY-=j+aQ^NwOFdsT0{HG@$|v8N&SK;5xA!YF??^2CfkuY(g_v'
    'lYSj^%XEOzQ!IO&SxZAQ*jPamGC<og6MAZpM!ke|wo0c|x6~TLn~o<<VbqOPtb2<JSluJu9FPX5yg4{m'
    'Sgv8-7)<r^;zF0TmH6lyV3TfB^XRDRzVl$gVG|l28l_fc0{G|S>Fe2quvW8**2glP__#D;Q*rn<9m!at'
    ';!@D!Mu4A+JJDyj6_~HnIJ&lup-VQN7)!h^A|3<&lrj`9#2h3{-45}C<TP2`HP$v~(gk){|9VUjR1^MQ'
    'X1y)6c`ll?xtk>$D=^tbwqWWlnLF#=sy2V8ng-1=xhfE*jcOH^GUQ(sA*!iWrJ5#GzfP8c@?5Bv4h?{9'
    '+>S*s=1Oj7XJu5|X8;>yhhluT6)~OQ5ayb)rm!b^5eCL6y7if(kLI<q(@SE=Uz)WVWTtN7<XT;kOmAE<'
    'G8fk<8EU8M7TvKuOQ5F7*9MW&6tcQ+rE$>HIOwG~=q+(j_LkLrJRWMarpO)4hl0GG8FF5i?J6%+Uj>6y'
    'pzgp-5j5;P!md`v0blQ_*L%t9Wl^?$N-I)Sa}(DC5ROayz54Lkh0{NK_VnuF^z5pC`Sq#e2c0iE2cB(3'
    'F7s?Vk`eVIo5q0^d6I>m<pjj_d|?MRjqJep1J4SH6U8#{rNcc*SQyZQ&(2P-&cAwg@mKxJv(u+f&oBB9'
    '{_5)d5?~)5bi3VWQVs_r(aG&-=Xyb=eD--~ej_?lL53Z<7!G^MrJ~M^k<my@JJZEz))|aCXOB++(#z4o'
    'XPpB%9p82)WPURo(2mXo>O6;E^<R?@rXu$%T4K2mZpaMZ&waK4(T#}A45JAqkL;5&QXrj}UeEx{!__ls'
    'JE}f?2cYz5*?%vdJ-Y(r;hGNneU)0;KRN*mYCL=+4v$VIWD2&_?1l46KmX+P@zeg3^NX*}VSArEd5kZ2'
    'JrTNIY)1iiY|o2a-{UTo9t)^PXh67RjxU)lyBjbr&d;7*JjCrotev2TK07>Ale*WzXS-Rhm4olGwJ3;$'
    'gmZhhWH9Q1Wp*ukWWfjXo&$8$v#p-xD~q^`YazTp7vIkhkB(k+<v=NyS$A_ij~+jL`1t8pIGOjd`+oZ3'
    '<pH)X9L!$=J>OTqBPFbUn=Xc8^&8S1{?_ftF%T0{(&j=x=usa(dH(F;DuY4c#>@>u;sOIm+n2HLyP;(>'
    'O1K|zi`!Nh2Q0D@44ysv?)>5uz&^itcDbB6G8m$aG9LOK<(|#qKk9PA9fx>s;Mg|fQ7nWP(!dYzE9o#%'
    'jg5QhEscAbyTU!hUGI7dRxgN*`_}^41Rf=mLGQJAcR%#g={&YwXJam17W<(aQjhsw6xk&7Vuz8?q1?4)'
    '5W%mm<#C(adLFZ1F0g_Ej6LrS(Z_*(<pWYQuxlp+KYIMldH><#ug)*C$P9eTacShia--O%GGML@cqCZh'
    'MV2Qxl?()p#|wZwKfU@IL1?N2iD0`?(z#vbM(Y#el&Lg{Z9-X5^`ZVF3e!V7^o{{3iz#vx_Hj$>%`SZU'
    'b8&V<=3vrc0BEhyNcVUJq|;p)e~<N#<zE%Vk#1x~R4_>?@?;Qs4A|3h1dj-JB}ic&+kyb4z+!Fcaf<=z'
    'MX^N$A>E@4xI@QtVd5(AKVHl}{`J7K5zIVkU)-l;j%Uk@35wSK?1q2_!<ChA5SN(*gfaY<$)_(`yBSyn'
    '5FzZ?qMU#XWEQO0L-9c(+Yx{l9y<c$G-2>_#2w2HSnPSs<u3PPPk2jY9BtBbRx+-}1R1%>e;^Fk`RT(3'
    '|GuA&-@dRwRAzvo%pAW(sae2D`neBT#dY@V+vm@o!qooq>f4L+ty3ga_^uyWv2TY=P}d0^2Lx>_BcItG'
    '^`%cE8u0KwdZlOM#bi9XSd0+EkF>JUgtxf_6!+^3P^Jg0;L!JvJCS|dv2E+9VD9=~HYBrI=c`1OZJu`='
    'rZ&O}{(44c;^_WrJT7EM8;2?!A$WgqJpx-4C`Dft1jW^-<Hd*{&csk=U&SwsO%B8i(DedmeS)s-<nSoJ'
    'j6@H2Pf~rWhsZ0{li6ele?}@jJjxG}`5MShZX7b=ozZx%KO82X!e7aB4hRQhr2B{6qgQ!wxQ-LRnV8Pc'
    'L0JqBhhlV?Ead386FWyGo}Y>N@|{vIB@dr4z~%g~Sn~oPyCR%Tm018}D6R>6hnu8g$!d4>Pq01d76NMZ'
    'XNXVSw&FP+cZ$YT8=+svffEqhm}~WL@?eqqwDC}pC@HhGdi8)7Z+(+;c+ijC-y}VxBMo`BpvXgN58i#D'
    '{yn;1OskohT!?G&y?*DoGnL)HexI}3KHPut*Z2SA%a<=-ynOlU)t_#Nh!=J*e)YnFfBxi;x?4Cy^Xaj2'
    'F<=ZZD33M!eWBN<nd`87e;a_zbf1prk4J|fl@S;kr2y?iDyWWAa;X64<$?9`pz|jk&jK)IfEGw6G|>CX'
    'K<|t1nNUSIXMGA*IQ))&i8dPgN`CZ#bozXZHG%uewds$<+qC$@9b)YLk5`O+C_(E5j8sJUnRl<I3sLmi'
    '$zTTLo)dF-j1TThS1F@`1m_WVsQYTC6LY*3Kl<x^7f>qj@HgFFZ9id%?~NFd5ff-ijbN-dBL4_{u6!66'
    'o(?z{Ks<{yn_LAz^u%?sBp8DXyB`XKLt;v7&b^eFKwAF-ZImwl)P1FSQh$O!bzhZ`9vZjm9nIwkXTyCy'
    'ssaa@5219|M9ntgkVul00WvGvPWmr0tL*eT_N$T;OoALIdK(WFLx>SpMFPM3<VJkY2iJ&OplUTjhVRp@'
    'f3*!63kjY-ECjuBcsJ*VtKT!8xcYtRi<cC3dW6a{vTJpfc<lUX2P8E7TMo`*Gz5_*ct6>nTk`$kbcypF'
    'jECZ9nr>m|i!X9J3d7swW%~vpE^)UVx4C)OQz<2e9nWvXw1=Z^?B=!+Gb24B!<jfFqj!gi{>+HtAoN2n'
    '!2@!wC?G7dD2u$9OFs%RPQVBukz;WQ%C^wbI@+%0RNzcgcs~s>srcOO1cesH_Y!@V7kVlxSE$*h<SmfK'
    '-66eYv~1n&N?2S!q_}Q8{{o*qI^ja|Wq!mIZax?X^C*z7qs1*1(__HAI!8I~fE0q?)S|SsOt7)Vp(`bZ'
    'mC)5AZIibN2f-xsLQKEalKjdnZwu**?<as5!Ep!kaMRt=sLJnAZkUqOPB-mEvJ<afz)paQNN2DG&L4Ij'
    '0F|nMIJ~^TkhrE=jnVlyiIr>Dvh(Mc&z`~)V#tq`x$}z!>?{GnHD}oHx$}k$7osD8_1*&Wij$I)&yZR7'
    'J<89lZFMr$KXi|~DBHRpx`6ukXjm^7_n{m^W(-dZ^@DM#4M1gGYTZ2Rqx=Du1+g>hkEhxm{oVDP-|zM('
    'H$tMxpWl5rF7)P(nhm!hste+}O2r<1(B@%@IpA0+O>gl*3uMY2UV8$tz*E1&nM+>W>CWMdmGV;*w9SvZ'
    '!}RWy^4m%P(Tn+TUq`~#yi~Zm0jOjySp{DkNIHwbNb89sl=X%n{V77)rg1jalv>Xh>fdcI6`DipjnXE~'
    'rbs!Nk8g({QN;HHj27;&PEgK)>ov>x;QhfYF-Xwo#s^R);ioJ4SR6UrLFL7Pr>#U^pv*Mr(kEDVLe!J&'
    'Ry*jr6YAk=)gTHEH{3B8G4#9Ze)mdoG*%ByqdrEWJq5tfCsHQEbavb!6w~lJ3afZ1l&%_K=Z|H#5-uBH'
    '#B!Z<^GaN?(eH;E-^F^HvE3ScSN6oV65nk<*fqguuHC&ez;#FT94EW9aKLtcQGm=>1?ELFW!+d&XH=QO'
    'v)0kKye5o#+Ig!!b*;KDI)%Eomfo$VbBpL>w~d%TA?W@!M*B%mzIu;4TK{w)%@J6O-)#uayw966g<kEH'
    '(GLiFEkFQajri&8W-#e6b@;5L(k=MBN#fL0VEn!_nSxXI%LTTe2U8fhE<3^9+5qz*DU8;+MVB#wM;5RR'
    'qd5kf1+ND0{QJoOERzlf$;6xSYxt2&FsuwllA670@I75j(EDDfD?hW2n*3Ct-v}1K0OyfpPTjyOLp02j'
    'xO2foiqw)iC+;WdNLl|<bwN>PRVH$?3<!-!!*{>8K4rJ)biJGPEVrCG?sn|9y!0dU?Y67jvIz>MpeAZ}'
    'cP>LINP2~34jN3HKpM426SmCS*>@o%%R##j++_M<mN$U9AD%z>_N%)sk@R&<axV|MC{KD}_vHc5ovYvO'
    '7K^@voB4b)yMOPVmOh}O)k?tqBUl#so(?P@9H;9CVBPJ&Zpmw*y60hf)BVnS_4m$)GOz0$I{5bDn@gc8'
    '*{#3SjuVS%x>%p@-Aq?0MPaI(*U4Zs+TyF?T|DeXweEA>Ea<)TZ?gn*y}@{P@=i@=D>eLLOaWB-X3Fun'
    'P&O5FFcx6_C_i4<uU3Bq{nW!$o}Nl#T|Hy%*3lC&O)3SdcXWInb8+uu4l~za(y8oLno`W!O^<_;y1Cy0'
    'yA0QHbl2cB*pME>)|n$L>I1_{+`}?&r<=RV(<Lf6{ZnBvFO;5)sBi<}#EdiBa+n{AAY#;KR9Yh9cJUx6'
    '_|-9kjy8kre{tCT>haY#=chlr?0<KDaryY!Q*;TU6URGobJ=}czB2EhKRtc$jXsq+e|mL^aP)d>f%*3N'
    'H_uKV_D?Ua9zQxgyUIX&wOcc3*$2z~aKH2N;JsSv2apqYU_CjHL=qW{7NQ680j!|$H1}Rnn0zrDF1u^Y'
    '=3)Z8wU`N&p+Tmaza$w9u^tjQ;rrn-oJS#>;a9ISBDdmx=Muz$%H!9jtKhxyV&0)3(%4OMZ1yh0j)f!O'
    'x5j)ryAi|T{SGCw8+aZ;?q-gen0I<&G44zT6M?ub^%mL-Xr=YubW*13{Nx@NZ|;o%2c<yZvN|tccK_&b'
    '3E>U0`FL~$p8`5w9%#-{<aQ^#mj_EQ@I$AEU3T&Gu-5}wK3DyazHs2T;rO~Yp3G-obbGzry^G#$=j-#+'
    'hoJikM@v?WMsXMS;^Y_O!ALncIkR}Rhl$aPw&tC->`qS7UR^pqI(EGt84iC9^B+t>DC#>A@at%-?;gy4'
    '4SvJ$*Ke=I{MRpE>i^IFWDfR1_h>Wk6Xw_NBN6xec!uBY>m;duH^WxT)KC1A;*X=xo?kpurx<vx=KL?O'
    '`j4MJ|Mp7Xd{Oqza6!L9uSVt9V3~`|?W5ck>a^RzdOeha8k?wn3Lo2D!a~=tP6DmErU6*UPhix1`3-%2'
    '6K8$~?%^1ane;wV*T&asYpfn#Ewi9!Os-V`&i!mWo`Qi+@{3SUZA|g<MnxEwPyNLLHen#&oqUh<j5ieT'
    'CD#;BCiHv!Q9ZW0JDT3krbCgxFj{nLGrRDgiFY9I_(Op?yKMdb{jU4f55bw8UXkm<%btaGwbRZ$xL9=1'
    'Gxbc0UoX4?29xizWcGay{xzHHTS>QL%+unD^^)9GD-G$jMns<{n5g=G#%{X%)n%SNrbJBpb8?-(YufBS'
    'c-1=orTS|Tt&uVCP#x7f+jQ-!m!6PJAGMv-v!K%fzZR9>#S+^hz3f{s>GV2fmN}j;_jDV5X5U(g2ap1M'
    '!R962TW6-CR*&2I92As(Z*UENvys5Mkox-S>Ur6hp1mC@HplYg+Z&SUd!ooky_Ao72_N>Be5fyt7Co9}'
    'x$INRPKk=Udca*h&0WQf67@?7iRvS{gwoe9`zCjJmE~8=8p|tM33VkeY>`<T9JKTPSE+~cm&EeV>oW7K'
    'uY<06aQdbr_+6@)a>{OUDrPsSp?>!Zn#XoLuH|O(PI}>f_HH!45jZh?50rXo2&Jc4@K(9G?!2qL`FNUT'
    'w~lA9qE0WszthIk>SFTyT7u+$=O7Fn&#{CnnC<zY2mY-caN@+2`9e6<jzVEul;KrGTi9MK{MZXU+X`J5'
    '{$P=&IvS_o+BUahmjtnNoY=O!NXF8NY}*pj_8gz_DDuFMx5LOLlsXZ!+>qJSw}=yjZWYl6!v(G#JFZ7b'
    '7&6Z#Qn1L6g4m%fmeR6ZypI=#9`z$Z{K&V0n1s~jEVh^ke2<keAz>IVj4hi)9+fPTk~lJmIU|7`5$bUf'
    '2pSUGw`ItfV@Z%v++#G1VYQTT8pU2sodP3M&+~2J66%DW<48Y<sB1IZ_N2osCYfuwuFo9LwteOX(zZit'
    '%K&yic0${at?B{_1{GfHNWwT5+!A3B*na5PJhm*nBX2vQ8&TrLmhdf?5E|Gd6x{b>5>SVDG$PG)FiawL'
    'h;0*~S&zBQ^BgHdD#L&W4iTP+T-O#B54n$*^11Kx*p5X^JlnPG$l}a1XffhG*aG;<7K8;33rG-JaTLH%'
    '(v|`+?Q%d83rR#GM=;@Y$vNzMK!g<u&t-N=Z3QDq*Ws3JIYLk$_=B<_4yf(MZWI$=1i-JJ6*#U8{Wy$6'
    'S4tSp3!(r6STG%{y7-1ceLrv=0i5f&e&9sZ_q{NJ{RFP`VKr_LQy@6s<1nBH{4JR4;!RgziGYW~Z>shY'
    '!yusI7zUuB<@p?MgNm4mkTOfawo;H>k~yx+0va>eV$Y2v_iUg0ERJau)>H~GvI7t!9)&VyUf^@?h=2)6'
    'nQMox2Qm_bmhF-#0C_@U5yU>RVhMEa5<rX<*!64-7}(~nV-cXDzy;=wiQ_nt?GrzMjkhU7=@NuKND|BE'
    '0;WbB3wFaIvG2s8@5Tl+Da<0`uoeN>wLB6s;Q%Q)6f{Td2SmC+4Xzha>B<P$jDQ4kEh#LIQY#ejzhoA5'
    'tb7>T@;m|Kf~e#?3;@+J;5-f`&@-d34Zz<P<v<rqz<6O0Sum#<Hi?9hB%GA??{Tcq3Vav1C$wW~bMA&T'
    'VtAru+sq;XlL81J2!xcjD~T0w&=nC40@ouzjFD{YI4V+e1b3vvL0;P&Rv5<~s7TNoHV9fE!!V9PsCy)c'
    '7!j2CF|$C9guWHA2=GxhG6F-nfghkIkesm4A$};C<pWS6S!jdqqMT7XbRr%yK&NHLK=dKEB#2y3QYxBw'
    '4#>^~Bz5dkPCSB_!L1;I?F$0Ok73b1tdPc5Ac1ok=usAV@Ru--Jd3-a$X!;|P)0(wXdr0}1K2|PF{u0?'
    'AOs{SDlU+p6vQ$pj}SPSxB~VVNKW_+mJGHBa8$`q42(o#CjbM+A#sFv*Ckj{lmfjt)UjN^I81}W0;Nw_'
    'OerXB2TxFAAEX9wwoA%JkZ>ptq93?k!lqfE+88KePCXXE<`Njja%|!WhXJX^4sdb^^Kfk$NiakRah)dN'
    '3T0BdHtbpybIXrh%z+FD4MF~ZS_97U1xN)JL=ka74S`Gsdxv-~2em;#V^dN#aD^*H#<v+rTTrhk?m{36'
    '0Sv(-uxWf>Mj@zq&<d1+QV0VJY%msBo&^*gOW(T7t-&FJ$mWg%b{qu?aYL{;Bd{`n^dt#f*8)C>L+XVV'
    'NFrf@)x&He!C;kP2y~R_*7{KxG_63KGsS5^0EVyN9_%KNitA7xIA1!piziSp#Q+2@$i>LVXKi2(pNC;s'
    '&nd@^3@ijJBy6GdWawh%D)DX4mB^^Dha9L>3fO=c*a1vuD{w;_D>R5mh@fHE5M>|OaT3UvxE$OQ2P7Vt'
    'O`v4JoQ3^}?EuUT6a<k4h8_^H<$974DLs$E&&03bm81Lt8zln5i6bx-9L7EFL_lFcSDpo8H?nXlmctzq'
    'O2-3L>jxmHd;vB)(1j$`BEo1wft?)3!sVeI2sZ|a?NHE^E~rm{9H3?cZ-={)Z^Jfwu=kz^eiw65+1tXY'
    '>P0K>2gnEfE5}CH1caLlzk0ZruIq(_!-j)C19LqD4FfC$%nG&y4N%K~mE$h8$@XwP8l>Pr0-J#V<vv)l'
    'T(K!9v5Rt+2s;4n0;1RRsRjNHS~EWU7la@ed>8D~dLb_Ky1>G4K!13knp_SR7`OwL4MsM2LKc{WfeXsn'
    'hCc!G!pb7Bl6-JDZD3u-z!|LSyrY2dC3vVFuwH0MFgZQT2XW_uAhQVrHwc_$1|&o*7IBVV2vD&Del(!N'
    'VnC*iB9|~e0~a{<!0-aDbA8te0Iy&b0(^m*65OlM;UL=q-(Y{*jPa0C^pIjA2@rgh_!%0YpzU$<zybn;'
    '6Bv|(m+5ox(ZR0)3&aB62r2k51l(BSdteAtffNVG4x}aOp9Y}1mVxl1h*5xT@c<kvaGY%dtiqhgA}}P6'
    'nM2Xy21W|NLbOAW$J}#$5?ZdP70*$Y2^i4a^F7xhb_^Cl$PlZHJ3(v%>Bb@Gb_p(sZ-p=vy8Sjt5CRqg'
    'P+?-3+<mTtBT)`!jQ}BU1EGKq@5P{$L0iknf~CU}eH%nPLxo_+K0XfWLHOVa37ZCClk);3CIOZ!8YrOg'
    'Tw#fbdce9M30x@xffgmmL}^(df<jM#B$ghy*02wO1vW7Ct3|U^up+c0utIE*c@(haIUY!g&;w4fkewV5'
    'hrqrZ*bBUN&@Y~6N1z0pz!%_Nlgh^wXw`$4<^h?yA$k(F0AmSUBkBX8h7p+0p%1Q$9|bmvT#Ph<Vgb<{'
    '3l92?fC*miKoWTcL|N>@D|TQ-9MuPKJcw@LfSComB}3|iq!PphGX>D?10FyKg9BlM5h1OE4|r&Lb$)hr'
    '{;>c2!C&?-p8Z?}`@j^zs{{H@rV_YJx^^Ia8%!+fg9@XtK57SChA3{q07Pd6PzJmcND#GBfPWl=8o-!='
    'uQdsXQ!&i|HDX=eEJm+q0PRIOYlQrAuK(8!?Ne}6d^D;oP(U6yujl8XA1Arj#Z?`bZwIHRkG!)WI`_^V'
    'fCxPI&w-Xa@2uS0-l-pgk>o_-qu})Xk#C=Y+H<XvV~4SQ9z1wtIcE=D*Lh$$aeV4}WoI5n?xQmwFczGH'
    '0Exp#5B>Noe(0BbJ35DX+u&nAaN>s#9)|8|bPB$`tKQBR#?+hI6z7dl-U#EXmz`7ZQFsn^$s=$I<1;UO'
    'bPo8A+)^*s*sVsJRdTOB<Th)QLv(Ef%plR_wQ?#GTqA9dbU(k7Xp(XjS5qMrxIep|ju(@k-1+8*yB^q%'
    '*<~fOo%0&Zh?)>cw?`nTFN73Rf%R2NtZ7JQ^Pi2zZ%6p%)w_vanqDbeHi}k|b~8m|G}p%RT}VFIP5L`='
    '+yKQjFuWVk62Z0I!5<F$-lIq1L+gS6(0^cg=kBA^)AKld=$}@`{)5F}$Ptqz)*|&zsaLmdf76xK<K6wz'
    ')tw?TGmT4~#H8^2{D#a*NfC-qpQ_`9CuH^-VL4!hd664<VTt!~r)J${t<*czfgPWp#r`8aZUZCFJ$>-#'
    '6l0quO%`y`&m-`u{09#n1!n-r_s+w(tif|?+vh;Y&cg@s!!UHtA3Tg6#o#fQFdOP(xgnA(;5cJtY~$B5'
    '>bl1MG}@k$yYu1Ix+}1%N#5A@&t+z+g6EIEdG_o=)gr|b(iEH<^!*PH+}LtR;8Ae3iF89Z0QU^68%kXo'
    'P@6ay<cS<STX$>*Pf3SiA#EXTaGj{+2ggUsC(zEdA&_~*9@sWxj&Lj{Tqoj;0thB4qaL2EgIj0E7TCQJ'
    '3vKR6kA>hy+8Csu1mhVrI8al>Scu6br;c|kYwjEf6%U~pehOSzB5^G|=yWZ{z*&#MGmAY5{$?z>ZCjCN'
    '!BQRYgYlHsv3xgKv<`%*IeJcLg?L$-IZ_gfAuPdyASM7A0J@$eP7rVrT7imE3Ws~##}gwf5FR+@M;|`>'
    '3={RSqq>;Rl8c2{kV%zLJMIh#6~m+ZYAwkX$HSz25LRtU3xwtU(pSfwgKtN#QF&mB^<*gKBE5gv8H^^2'
    'IS4H*#iM{L*!sSOs<QN1dJzNNQcS;|3N<&b3e+Xe>Z@c<_@&0iGDz^3WF`l%mW7o*?`U<jd?3+It0$I#'
    '(gmu?B=@HjIJHh2R`mprQAXGIreY%SVrfU=ORuRjn~>4Q!m^9ga8-W<CN$*ZWOjH9pa{w8l@*%vK?TI~'
    'S&H8YUZcVK%~(2XjQ3BGfd$`~kv_Q4llct3{;+ed7BL}!<S9nsCt^B(2hUB&U<z-(1MH4Rs#?=>H&vmF'
    '*$rR-Pk!}9*USt~KD#)7e){;L|NP>-s7C`09UcQGI3CA{pznk(@qj!%X4#?7J%?GIZv&&rC}sf=HnZ>;'
    '-{L$ZVF&^s3;*I<)ubUKZNYa7JUoqo*Ew_D(DFhNfme&ivLPM}N=JHu?ZJRNCd3xNkuWxM;dxKypr?X2'
    '13r%NpqzUicU&y##<=BBVS$=tGN8=kp|rRk$DSM7B$Add9lW;?1rhaQ!E)dqJ%0Mt`Ni{#$4{}Y`~f(x'
    'wjWuJ6_eQUiH!onXQ3q=CkEliER5i|Fdz>pK=V9M783P{LwwIA@e=msvu`iX&ijv_;-#f?ttYaLOK--D'
    '>znyQAyw=5&4cEG02YWD%D74o33%i<0jDUmP>BJqgD7Hzve0oHFD9G^9<gnYdl3joCvYi`OZ5ZkY??Tk'
    'DG0!g@V$^?YETGb4lpY%*OAo4^JgMxU`HW#HNYSjp+0vkDs0<{WekL6)tEwIaBNjP8JHhSuzmaO<A+$c'
    'Z7^bFI#Op3_d5qw2P>Wd!p1Uq>IC<GC)q*VujF#%m&c}t8mOCi^LM#X)FIB}<S$=tw_+=fmBk^Rtm@T0'
    '9?d}}VzD}7_<Km^<mIUP))(5^TXx<MR`TGpw1mU7G02jv%z!Q+&Q?&fq*LS5ZiU*n6MGv2B<z#W{f7pG'
    'UrOewdWo0n8j>+Vv?dS+w-d~t0V%A<dG#^!a|TZzC0P}10yw>Exz^_@J@IS|-&AApY`eumv%&`N$qT>>'
    '!s9}4sKDI;PYe7nFxI3UMU)CKCn#7P9{in$AqQuOOAZbVB|eEN62gW}fywlqD?=Vd1W*0I;-Z1$aLK^w'
    '#QbB-kccc25sq2lEU>|k_w0y=k%LxG)$t1ril06qgV8A_z+tTqGVJKi9R@b>pm<+aeQ1ry(1T|boQF4f'
    'C-E7@;dUJ?R3*UKe7XRL*`}*N<Vr-#0S;+$u)Uad`?BfwX3&+e=9-#eE1BIIv+RXeT4I%ba!Q+8vwah|'
    '*#2$Fa&66QZP#XP*Rp8CTHUWURcZ2{l<6mB`bnAokgW1amwwWvpLFR~U8<e)O4qFl9CQ;Gu$l(`ZM^K@'
    'GcUq(S1XM1#z5p*F(Vd@F_}GxeGxmv3mh*FIg8Y}PRQ{X1%8lq=1}OUt7G?7T_iK%u1@!`MD?U@lZaPF'
    ';<vJdWCi7pmyT5pM<ekmL$fa%!7?`UZkc*n-6pZyoJEX>{Dx?CS-?1R-n%R{uxu7|Y-~7eDwUK2G($3o'
    '{ciV>s_O?rQMJKZO2JO=C&p&3lLJ;65IS|EBZuSh^z+UL(;7O&*l1Y1bOaFbj^YU{&@9Gq7eH7%C-a*_'
    'wIgQ14`e6Fcu>$g_l%+C>+^4(pI;QTD?94^!55}S(Mba4h;>;TcS;5`(fJN@HqNo==HbCvl24;ZxNB%Q'
    '#1D`Vill474~|SpJH5#uFm#he!+YG_y2nZ7O?vS1<>(JhVd>xzDm9@opG%L?3~x-%YI$)Fa3;9tYq@dK'
    'c{CmWN{l+mR+&N}q2o8$jcraalknsvI+tl>(rzn^uBpK&7e2ap_8*-;wS)ft*)iFbHn{OEnI#!rdUG_H'
    '4c{4O&t;i_{*qHoAx;C#v!hNsOYX4Vd;Z`rjWMWrGafF~{ol^B>EK$0HN+6~?Wl)o%I)yZV7A&J6hA$%'
    'y?XdV!c3+Xw<;Ih22-xnKnwiY2iAP@_!3KL|8R_IYB$CyeIe)DcIQS60f%{hHMOXg_&&)LUEZ-yYjw|8'
    '=9no0xYs%R=GzDTuODAtJ-hg;BBRVKVb2y5Y(8L6kS&{`9!S6zR#~Iip|qcjv`o!4t~HYZPOioLFl+C8'
    'vSK%eOL#Ed{Fba))uWi)id7?AOjb9w6^c(TPJf<k#t9glx4<8U{or<8FT_rP&y}L91p?bbWSRhs(HCs|'
    'E!yO(@ImHMgIcs%N=tSLA**uq30-5Yeq+G{4f6$#@#=SClhod%sG_=mQfoWZ8V_}=RJvK`HB&1Daya|;'
    'Le;drJUh)?w%DtRFhv+?ob2OO3(4J%i)TN-Y*#O|ZZzp@st2!5CgaJW#+s?Ucsj;5g+GKOORv6}m1GK4'
    'o#dWgtEy&s8E`s&n`}z^mcfc$47&gmYBG*drs$zz?@Tp4+8ZanfK?cFUc~ovF;ZtM<~)`2@1A}0?G;84'
    'v@pC(=53P0K>!xqZAFpNHRjMKnAsQvl!&n?V&>NDi{4O-4l~0pZ_~aqHl7l>>jT_3MpE6o1+P(O662D~'
    '^|TdwSq3Z<Mmz*+Hg|%WN^bz#YP5xmp)o;Kl4{M8RS~<l!tHDKxZ83@`ud8yx;bz5yi?hsSmQ!nz<&1g'
    'y*dQxfqK{6;RF+^*)K9XD%|V^`nDVd)md1X^WQ#y{_NsPh4U`kG33>FxTsb5U~lGdQZu0)#~wDTRa+QE'
    'S}r!yN__f-W~Ynu(}(H72ol4qj%kL?j-WZVt%Ibc=t(WkHssI6`C4s>k5m4ni9y>+c$l|3R0WW9XUvg6'
    '!&|wT97S{aYWq!BGn}nfB3aF3&dI@DxoT<b%+PSAQ`OqdRBJWTyO%t*Zu4C3`{oj0?~M2w^y6B~Y-=;I'
    'ZNGVK`$=otXI9%DlG@tNX=^*BZLb+^`%7qRIiGE>>1_MWX4`8ro7r5pJ*KklEt73uiEMk!W9zoV?R(2&'
    '+hY=2D>-a?Phs0%2HWqkecN`<TkE+Et!KQop76G}e7C)3QtdI@Z9mCwd&qU$?*{ED)2-F;$B!V-Z4YT~'
    'd&_cbFUf6BdZ5h|H}e^8KR|+8i}`JPO>f&%cH91v+xC;&W<0fRubFMe6WjKj*S3+?)^0l5Ub4~lk&L$I'
    'T(p)`(e|5()>a}~i99sJ(UbPl&<tmx?K=sr^&GT4q@e971FiK0wEg9O>@EFlpV?>oN<Q0b?%6(4&)UyC'
    '+iT)k>v?DUOgn2m>uirgXMZ_oZKj+ZH0*D&(cnU=Lp611WH9+M=X54Vhgav9TId?g^IzpW8N92tKHqiU'
    ')_CzAHB!>J>d0J5VY0oqri6iRe4FoRf1)CnjLgL~o;^;-<hDN**Mr$yM=y=_X}Z-aNVRCoWj1QN-Kca;'
    '6DW-`#lhCOx5gl?@W&nOVb-;2Lptq8I2~k(=-7C2)Vj#XRld!fDWu5(vl}s#{n;ECHBA)QTK<+WMu_X#'
    'OgfR}k|6RzX2(JVq0d7~V{QdBa&7Kf7PE;T@L1Ydcvf&OY2b^x@@u08E({;ImL1w5<pH(0EoBgRfy1a}'
    '1tPNS$ags*F^NJcIo7`o!k9%|&>)UIDr-+<XA3+-;$K@OGd3Me=3g9MJbQL^FWJ87Vr08fU#QBcePk|G'
    'DRuK8$XJqm-Visrz=LFg`rEP<XkxskJc6B7m)%K^GwoJaAKHx-V}W)wyxJepZZ4N+&;a<st$>^<uoyAI'
    'ZUkSU)UYYg8dIb^v2_K9`hla5W+i60`$J>)&Wh_l%qOj>>finIrw<K_ksZSr#Pg3Cn!!rj+B{2R^B5*X'
    '2FYhOaxy0dtG_H+qucHNOo)lf|JR+NlP=dL6$IgAf`l{6ggQEOyclsZeWy}>OzME;<t7^X821?5l51hK'
    'QuY#i^Xa?$?TD)+kkT53VV8(a0yDoB@jVlhdFONnl!ZD`?>(6rU70|jZEb`K(V2vt3HO1eaHuAKbY$LS'
    'QGi!YlCog#<t>=RTiVhxWGZgQ;5gmgIfU9mxWX2MftM11J7UEVx-im~!U=7c2e!{b5|PLeO!yqUmMHcD'
    'BCJSwF0&1&rd<w|6;q%2q3y(;=Wr5Wr*-XAQE;M|<49@oAolFY^J9lbf#rjv=Ll+ruqs;^p59J3%d{u5'
    'H7bL5NlxBQ2e84~5>GzLT|Y}ro0a{(77}0CGW(eIiV`23UY_^2&E?39(^S@#+RK(5m=+H|Qa@+6_tXAB'
    '`|+>t&^h~|r~(<V-8U<c4nH#SP)Ry~PW<rM#rgBo#~1x&GVm%Fwetn2x$=FE3Y8*f4rN?08F>MZ94Fw^'
    'ig_Gx88U$lr5T|tbR5Tv3Fm=FY}?~r6gsvOxRl4$CD?}I6Mkd~-wP@CeI62vOGik{btHA;AdZQkfgOdR'
    'Wiu979-%&WED9RWiDhhuzExuiJC$4OEh0Pn>k`@7W24AUsa}zW25Q=JvQS61(DbmgkG_YUZLJT@fNrUQ'
    'VyDF(ik-IGD0bTJq}XYvF>z-z%b-x^y%w+!m-FdhbZxF0O<o{?wFJf+tm%aw=her^&lx;@lw?)335hFS'
    'vI$|KSz$+!i0lwNX-Om74w=tc5X6>agCiR;&+(b%TX7svO9Y`465={OwJbpbLBYkXNC=x9Is;BTSB5-_'
    'h;Rt8eU}D~!zB~8&ttrN%fajbXP;XV%%8xPz76AYm@-;DRmb0IQ2bQ)1QtB$2>gajb>5M|2HnM*wCZha'
    't_}41Y9`ac8*sSPs&2t<9hzMbEaVA7HMamH`Lwveevp5XZP{#aCoVBvAh!WCF;v%j9zQg*GA$4cHW5d!'
    '<Z$1_Z>HJ$4@fgdMuvQEwii6mnmk!;C8*fdFP|Hkuo_`m2jq(-*M6=AjhT$2gVn6nYQ*>RlUuVA2fz9&'
    ')`WR0&OKBvIvJ`k`+cJ{dctnT114rCaxk6E58vL1DU4v401O3xvZDUEQ2g)&urmeB%uZBk7BqMd|HwLd'
    'gNQQ23tz0L>0~_QY70)}kj$TuN$34umt|%_AI$FUhodh~28M2jDxe1EmsNP_CSC#Crbf7FI=^0!Dc7br'
    'dD|%<95ec5>ERiYYvt$<^E`|UCx$ZtoRb^}cmMCd`RCn^VWLc6!<0`@On1Kg(x8!Z2rj@_SE^9EaNHr_'
    '5`BC1C^|ts^y6d&WC1$n;D64>x1#giK)f|g{ZGl8!L_nNKxwhpZ77jP<LPZ1aFxL+O&bY=SyCF~Fckzx'
    'ZB5>khW&<6us%3impE^xzk@;0LAiPOMocN}@U2-J1VJAuM!i&~4^YtIi5L+IGdb#fIBpMR%FDwg-#4Vn'
    '6_&b_oXM^Xtdk^%u4_gG%n><H$t~Dw-Cbdqt|6P@=*LaA+tEH_<B2ejbQ9q2*tio3%y)Rg$V54I?QMV|'
    '!MEX23})xIlli;WIZNOuA1Pn`xY-KS?KxpLhwEDlYOJGw><mWjO6LcQ`FuPwL_;~xS}y>6m(GW!4rq5R'
    '`1N&bwozL|@SU3RAsG&?N4LrtI2o$sh-+=l)INpDAHlRA``%0Fdw-GdRs!Fx#J%?)_HHYJTq1z{!y(Ru'
    'N-`7r-CN{$FM;1y<G$wn{C3@ZgO`p{s$S8v(!`fHLIA&N3&RNateY*soJkzcEcj(~&nTjm2umXf_YKo='
    'L1^N*Gsm)}KNCiBY7Pobbu~iQJf4)7*XqnuKT<gxt&WtqGsba5CX?YijB{kjKz(*N;6_&SM^;w*twLTO'
    'jyr5P#@d+gO-o}0n+dL&2~!vp$!4J3yLYd1c|)dxC)GxK<I(V4=iA389ZfmvzS$e)j~PYqtn(T#(#^z#'
    'OwoRwznj1u=45&;<}*WetwDv~lF@v?W+z6F_0uP0Fgj(rK#(@OXY=X8NEe`8n(Mx4Ws6q0Np1LIi!qr*'
    'YxMV5W}S$oy3P11e}4Jw>6b=_$!N(3<FQ#kXr&X={Kl28F_-apuu?1L(gT-kNF@KE27QFB_r4ns_);t%'
    '8u1(wsOFsL-APLZ6OJ<8;@<hq2=#2|vtz?1B=VPG(_|Ni85k!8y3S$8DO>zh%ov%V7Bw*1Rvuf8a;W}j'
    'U@U}x)M>+E*Ce`(k<JXd>ItQytDgM$xgK;$r)GTiB{=iwNeLDvn*L}GK`HG6@bt$7K`8;7!A}Y;0j_uf'
    'Agk}mXNqzSMNklw(Vf^wmfS&mxp9V5<9>k5IF%UJMn2qL)8P(27~M^S$#8}PgZoK^+nx!xOn_S@ubH61'
    '{n4AD^tbl1-*zRxZ6vN47_PP4w~sC)-b&(IOL=caX>TjjtDPb6Yg=NOi6blXxoLY%P1{Fi+MW{A_M1O*'
    'U@+dh@u4A<e=}xeIQW&|S_Ff|eVE$yN2W1u;zVNaIceKc(%Q%(+qxyGH+1wdGC^y*kfwiSvc8NtRfZDB'
    '?#>&__=!dg&bHFV_LeoahorGPbH-{{B-mD8Z2jv)yZLo3f^QMD=7~eXbU~5#rZRtZ6_F*IwRXasP2k*e'
    ')ciYhTL2r!PH#Wm7HCI6bq-GWV5Y42!)zeY%ze7iV0d&w7`BEO(7|vpf2XU-$bp#d-tLwV_o0(S9gGt#'
    '$oc6Ut9#7JPyqR~AiX~PIPW5#jFw*i6`ledZfE8s>**uBgVF*$o?tP3N~Wf$QA2w?7q^G1a^J0?umbEb'
    'BO@k;L$$}JOsCkInRTLxyIK_|19eS7-<2VS|1*36{6}}+^@F)v39TA{2m6QK9^@k95)DH$2cs+7QX7=3'
    'kIWf;KXe?<pvm{U6NfY8khW*;{m|B4o5tQAY`uearIQKLDKzv7f{1A{$VV90HBX5~&Ae?^UZI6%<V301'
    'Ks)ZF>P^{IsCs^UDG0xlDe#%BZmF(%u_2kw44(d9Vta^!8+JyxPhST`hE6VonhWG6x$W6|fcHD80>Tju'
    '2aR{vyVixOjhKA9YF(Qw{@ZTl-x4*hlOnxlhZ+hp6Q<FV7yy~;r{CZ(#wV{YnA~rVyR{j1rG_y+`;Yj}'
    'M!JMO+}rqI^oB!nslL@4@$5!*{94^TFbbUx$L#g}&Vzy4=|9V?<N^NWC+4nIJYUe^V0I&TniB{v(fmlI'
    'Nf{Vol2b%kwPg6J#+EHVHgiP1w$;b!{+PHzv2BZ6$>mS4!K?3SVt2YcQzzmHxCFdH6%47q|HxBe_o`~X'
    'Y$eH7?W{`4SxiNuqLp4YbFJ$SzUYhw!{dx%#(NLbcVF%YXNMeZG9w$L5vAZAXQlb_$Artxl*B$zuuk4i'
    '$z&puH2DEPY9ms)w;brrC7HTOpeaj>jt43`Jf9~GB-l=t^xUiwXf|z`ydi@jI&u19E1)CcK+Ti}N0W;Y'
    '>x?I2ba>Q?kjk0`7<XNY6eE!`#L4l>?=f>{X@^|R-eTC}6@-icYvC$_S@z0rc;`gfY=(PdC0nE$vOiwI'
    'J~r9YD5Zn(cnbSMREIPT-EbUYbDR{sd7ZI}M3~j9PZoN|FB166AV+dp#K34tWJ7&BUfOSo3^0x;lg|8Z'
    'Up^TLc*MN11A={;a9#K7)64$V=~vw&!#B@cwg!`13Tm*!RN|YsCk!~r%GDp^4JM_WR~4K3rfbY)OUU(p'
    'l9(E;X#>0=*~xZQfM5UkkIm8i5>Yvwy&O#m4kPLlCcQM!a0ROctyGbrGv+Od4n{S)P0JM|8qVnK3pA*q'
    'ea}#mR+z2LdpST`h))%>(G?V`W<$9DVJz3I_|Rs!;SFia|36vGWppBj>HvFo{>ud!u0&JT34Z)gJ!(o&'
    '{SJf(3eluu1wU4my}J95Mv+@o+--R6g;gRAdF{zHu*|*|SKBaCnJ}?A@YYr<Avi?J2rt|3CpM}m3vcvm'
    'oS8{D8s{wGm2b7ict85kgOOWJCB+@?xv4Pwnnrt{-3_2CMP6nxwU!<JW0j+NnpwAJP4pRY1m&Gx%6roX'
    'q@5&;YZ_s|R)Z;?|Ge)M4QF;Rs?RgG?$4K|stc|TPBXxNVp#F%K&6s<?=w|w(xn|6EA&;=9BT8-!$bn!'
    '=PAHto%B}n<!2gaz(;>%nGW$UXZ}7@nk;{<<>+@k@6mV_+q`9QJ_5tVcoEx=yc345L0T~PcG^m8OG5pW'
    'IirC8pqVrMTpJ4`g-MsBb(r;+?<YFQ9DCgA?cI^`U@qa|==ZY(Sk^``-gIQrMt2<i+PJfq88k@-Frf*L'
    '_jQBrW(;P*rweqZBABa7bAOPn=#idz+<ogUug?@owQ%X}WTraD4Cdn2beojaw^>@6=u$2Dd@yQF_b1J8'
    '%vu?&uuWCQiZ;JB7_lOwYp~U2n;9RtE&bz8-_Vw1C}8PIw}PC9z+j;GO<j{~ciulzzo@k?9|auQx_|T$'
    '`xc*?9#+EpN7wUk+d__iIJAB0c-Vf&!%v+Kn-lY=PKS3IL%#!^4%fV$kE++<+T2_1cDOdyr+$Z}Y5Ak*'
    'cW9)xYiso$?(V5<rg&UCB_H-$^Pz0f2NNUd!V$ZxKA0G1bz`H|vJVyNJ{Txe*Lrc3|G&L&?QR=668)}U'
    'fmQY_$sLNu`yofk$`UoB8;|5G$+OugS{^(a7GsL!lGJz<U;X#n)eoQ>Xn>#u%J!_2oR}hk?&|95>U!5!'
    '&&uz(I!gOv7mKa5K11CR+ybh;{W>nKk1n%^Z{#-JX8EM=m+AM*^mlZbey=q4{Vx4}mwu7E^ycw#=VJKo'
    '@bqHz?qWE)Jb!<2G#p)=|K}wpv(KHw`TP}I`PJ?0{=@C+7^S4C=xn+i5})H>`DvW4FrPS^O%dic;ycRt'
    'fb0c+ACH!|q3O85Y7E~;zTx>MN+aJeyx2)%*9~;jh)vUvZPST$M-Kuw(vj<#UKm=Y6X`k%T@=}dzahJ$'
    'JWiZH(nH(T<Jff&vZK%qB4j#Npa-^|V&I|(g-H@6zG>s%6VFR@$4b&9GW{rY!j0#@y`O$u;)$<|U0k;B'
    '1zWGmw0Bdzh$Cz}p0Mq>!qy|db!S+k7V>RO(_$O?t$Fa)<G&qw@C(vRJB@2vmh`vn3w#-8plpGLzMa3V'
    '+Vcv&Y)9|1r)&$oz1#0K^YY!j<&4{{^!a|-M&B(39&M%7cdN}$;QwBx*>_F1?~=c`wLWw072SH_#@}1)'
    '{9W7nyFDRCXdk|{-rubsg{_5&Y`OjSw)%f78-TYgB&bpwKX0!kU>oCBwI|;~Z}FFHF8<{^S+>|-{CCyK'
    'a=U2f5j@{s&%rJ97_V$Hz7>t4&5q@DTg(EdzR7d-bssC<_`JBakY>_q`|<|;%iC?6tZlD>`O9@Me~A|6'
    '>wB2D)M4`FGC;O!`u?5*@->*fx19r0V?h3Li2I%evi&TO*6qIEvq8RRgH+$?zk_TLRR{QQBNs%eM{Xq('
    'M5WGr&jV?|jlYFFkmrx`>eVal@-|$c1atNKMU3`l)5(MO{&b*G%F)7UqWwzru~reh)IK6K$G7-AT!8$#'
    'dYEGvX!*+}nY5KF{4SiX#_@9S&1A%@Zm!l-;=l18iZ9eZk%au^w<Of;Z*}baPULmG^1FtA(?%WG>{{7E'
    'PesQ0yL4#M+u)bkILX*@x2?*QFlx&+=PHAiS`0W6w8a-cZ!LEpDW0=_%OWJ4ua-rVx)at)c{w_0@r3pH'
    'vG@<PjKewHqAko;dB*Zty5z?e=7RCJQt^+Sg3Ly`Y*AHblnSak`^dUwW^~$)&Ylg|K6*I8LXC6wu{{KF'
    '+Q)<Qj|@SafZM?jAB_!8&H^5p{QFucF58j?1%_&MCte~-uCu+^xVB5wy?kUG35?rDJlu<h!*$v%XVzjc'
    '+!mYtZZ8zBIub4mfXjo|T4}ocV)WKh_}liP-|B+jN`Y%_l)2qj?AteI65mST+m_<qRAFzq=(U|G;6GJ?'
    'Wo@{u+K)|p(a^M)h)jE-z_f3_TyTpr8A18mSsYHr|3nF8!C2z%a=E_OHpbiVNW6GVT2)BeHloNXw}fj$'
    'y>IalY;6~K_?Hm%)n3E1@pP-aGm9G&^u$&K&TWN_y;#)P3j~d=jTvjDnoHetkK2u}+v4zB9J<uzpry!P'
    'TH_%*W?S<xivgS!uIArOw!mzfju&^|vjw)ppv0aIq9L)Je7fm)vc4yTa=W*LxJTYmt#zVhy~PL1RX9Pr'
    'y=`!>$FDONc`(hi{wweTbgK_Di+cJ7b5OQGkAu~0Hi=s5^nj_6j&{02cis6UjL}_7W(B;%aX5|9WJ31%'
    'FmA8Mrq*FM@h-iJ*+jc-jb0Za)mD>D!RGzd<-0z%mzA(p0kHG(qi=6ym2lZo*GoyZqylCBReM6;m$t*T'
    'DDwS&>~Jk9q}vnszO=NrO=0f^WWCOIxl<dYqZITMMnoPA@(tQ`x6q8PO);-Z%2P^ct$38w0$N|=*Bg<m'
    ';OhDMLJ)rMea^mDqZK#l3s<A<m&?bt)Ed67X!Gx(#%r-;bGuVbP`E^GqlXCqLi*`jn5K2$X@bcXyQony'
    '?21g&I`rRg&IVt?3*>D)wwmEk(aOE$T%1Bn_f|(|?Z+!yySJBC@$NpFjF-14;W2?&C0g}Jm{bc>%%zJ+'
    'yp~!{)u`C=emgGe!dAE09=>vmw-U?G)8NU!Jg}QDuPu)_8;%W6P=%)?|9<76urGSm{CO)uwzL&Agyh^W'
    '5WAwuz1&V(*S{QS)A6J)T+ER7uz2|M%iye=fK1k6&ulVYU*zW5M|R5FDT&=7V+}qnps_UzlOHF&ZCEN_'
    'EC#x~q_#2%C}mOB@rFc)%W=|}1h*3<y=qqoY&UE<{52d;K#8M?tr#8b1kyv<;%w>tG}dNwH0}1b!lXp8'
    '0PL<AOKHVY1~}>GdQUq!OEr8|%wl-K6a;~RZ6Ot*-Qy*1xHcd%Tgx4u*cKtuk>oTVTj=@J9v#eP3%oBO'
    '>3u>+Z`lq}o`(<L{+*FqBHF!If4-+Xe!<4ij2tXkq=ng-WrO_F&*V4816oH^o63B>F3)DdXQX{$2Q&5s'
    'J9WE19bS&E4u9P3wVZjrWoeLQDUiv!oa48VCya3-^3|^~gNa<udBvtt+coCI5^{TgVxq>@ZUe}W)Wog|'
    '_|Jd)xAtg0LzHx9XR{H;(aQCSfzAXpSV6v^{3>e6$6RsI;aOYVrfdc5hHDji#SPlhz6+E@FU+mMolUSU'
    '#Pf@})fFhO=9X~(Wh7UTeNZvH<qg@E{y(^1rTzd-hy!~${Ga=9lCvgJ2|hh0kG93Aeg`H3C7Ot>;A_3I'
    '^V|n+Mc(4Yy$!8hStYV1t(~QT3Hz$9w$V;yLMC%S*49=`aDbF4B-_7?ZIn<JWb{*<wG(hOlO*9>w<;XG'
    'uio^~N>)=tb_aXjmYKb9qkR^41Je~DuXZt2hz|c+`6vZbRC@}nuN6fwU8|*hZreesF*9!42*bx}ya4~t'
    'XH7L-yOTxKpINy-e{QR~VD2~-2LDsb7auiL62A9YsA9vH)^DxQm#R5b+2_$l0N!gpU{)u6EAjG6iZgtU'
    '{#9?=#GgU_Stv~=r?vEc?{SZ<SFx2Pi{TUtF0B`_{l+_C&>Ex)*tgSGqACdWd*lom{EJ4;jHEUetrRBB'
    'NUJOA%lqsOYVUa5(e14Xd1x=-q4&SD1ehozwBB@NzK!lU@Sjr7o-ip32593Z?7vh7-R%sE1>Y0s+OlBg'
    'Npt@qR`lRLkM&t^@_j}~Y70qkgC*%4GhU&)w%ep|-6oSXL8Z#h`FOguyPq|~X;;dKm2Ij7DZ2fw0gF{Q'
    '{eWflbej<$uq~s$Hfm{01PaJh>8&8=7#}cv@wb&Gw_UiuQoU$vT|N{ia_johH>_KHZ+f^9-oLq?hgA#d'
    'e>t>$?|8WVj)&hn9X_9!zjr!ZD-8V(Ivp0Yoo}kwVFC87b~`N0^}XL=V_N<u`W-&rJU;GR4Bs7|UX0#d'
    '3`dvm-@QA(xWX6H=gt*cu9mOJZ60E_c#GnX%U3J><tWCY;s;C@qs1(|8!ga>F_!1aB|n%yKs7F3PwhBD'
    'ZW@JdlDa4{T-^>)=p|l~CZ?Vyf#W5v7lbad9o^QA&<+wa^7YtBjWmRcU^Vl9n9QPZGFoC?EWQ<>LGkQY'
    'w0K}Z7;zFhf$#f9i2OKlEz^s9lv<`~SzhY-acJv_pSrObq$UQ<k9<3_1KrUR<OD{#1_*pW((wf0S;J(M'
    'hU3Zo0{*z0t<We;?#3i&l7W&2fo?}pV%v#nMR6F$iEc(ncWp0D-6*ybFVzz#2yDwULO<1=)I>=b`>r23'
    '0g4GIP^4w~DxTa&qxgQg!WZdclwiFP6sw2Ql)fHe^aoDh8YsnRK%wh~p>85w_l>~9<0g33$n#x2w2+mC'
    'iRU6G*3(cAO*8O>DOUssbm#GE@pPl*EtYIXOR$QMZt?EVGOUL&UY=zeaccUy6}moNq7fkEdQRd+QIP0v'
    '<Xc8!>3VF0j++Fj;Uz(ck|d2>2d%++)$%J49~lT)$UtH2nz0+Yo*wwFr5l*Ykm(s#;u=oug?{LpC`K41'
    'N#X~#8zS9DwiO!$n#1}06%!7wZfEx&Zdb=BCH;$L)8&wuHwMd3<8%cxCb1dC35rwSb`#$;-6Yb3B*4eO'
    'i;?I0nCzn1GfmSD!X$C+&@k-8_C3=uT`Nk0PIeyO4i8U8?+&kiy2Qt^y8#q^31p=uls(zQa~&R^o((TA'
    '@k|$&!_m><(NDwC>Dezs`0J<lXMcg&ue+V`-F&uKY5!P)0+cRhcbHYrA2jxLg3uiPW<No!0ihlK`($yC'
    '&uM%M^(QcR(qNq)Msm0FAK5eAyYRQ=_@C&&U@Wtfpi~>p!^ILM)U|`Df;4&AXAb~FV~%qebTFBP$&x(5'
    '9+3Zm@$zwIv(>@H`S}$Yt-t1X3al_6UwT&wAf6xo3j@-2u-VUaraHi@UhLiEEc^WA^eybyyZ2Y(ZgD10'
    'c7vRzfqa?<YZy7-IJ}XtB?)13<0)D$M-&_Z@kG!eUowSexALuS7ZCZ1F_y*s)Uf;!wGigd!rAQ&2wx@9'
    'Roz~1K)T_eF2>3(;BB`w?}h_Imk=@<M&=G6xf*0bXXLu2?UBHW`72UCM;=RO3yl<}>}#|DI#@av2wzQ@'
    'Jh}}|9Gi{^M$$M3^zQ+hQf%-avM;jt#wqD36wmIlFil?SK_aTLFUbvyaJ<Co7-$K@#bUPTcHU1vPG_G0'
    'T(&xmQ1xPuV27i7IS=tk*vW?hyuf@5L@IuDC9wONL7$zEr;vk*;l+$A2`7{8BHHc#`L6fhN9Si(7l%hz'
    'qsyNTO~(Z~>R#)6LAaORe0J@}Ugux2gqvZQl&hR}VLZAlEYWGn_yeZtt_TJ^aIN3;wKs==X?c<iX+1Iq'
    'dF0~#+1c=dJ+QyC9#8S?ZazUPl+llfxdp;xi$Bd43|V=%ryWXl7|?LM$YhD}bbb$#MfRRReCw#HiXpT>'
    'Obhfs_h6tdQPcrOJ!a<|86?zFV~b&gqmeafVM3hPPav9VoMl+zCvYCFZYh;0&TH-SoT}g(lFqS-uvNlS'
    'PKg9XY;P{l-(MVMC;jpo=DNA2C2X-k6=I6(+z@O+VhQ?$X(^*F07Szw*PJ7?BZG`dK|PBI9Kj=|F+wsU'
    'vRMFQzZSqgnV|VrWVat}UP$Nvm9-I7Y(?SujMVAgpx@@C0I0CQqxTmV!?P<6?Zx?jUJk&Wh_8wAPLM&b'
    'J1Lf0K|GJb6;>GN?k_tx1E^U+mIvF!=PFkt?ohv2!U>!Z_A5;1cso`PoGC75pP&%&4+6pn(_4&ZU|JNl'
    'tQ>TTWRY#t=f_L!Y&OMeDVPcCS5X)O;u7~8y+Z7r^M^qu!H}toTQHl5*cX(<O|gDI2Z<u1bQ$^V$gDf7'
    '<d)Z7Q54G}LT~eZqY$Y!t<efHEMgSxD9%6Qqm-~kP5?+OTt+hRog;qmlkt)&wc>4($)?(L29@eS|3Zm;'
    '$B<d8k7+vojjXK53HusL-pvjs+h2h>W}t&|vah-&;Hly`n6v#n{tcKK>tDw}&~mx9$g3Cv>$proXzrCb'
    'IlIwiP=Tfo)`)!h0e+^`f+s6qrMdV5cc>Ol6O9QgnW!rqi_)G{A`?r#Q|X$eOU3_R7K*B=F&B-h?lxFd'
    'fubeZsV~s5NVzhc5ZeX^w7m8FNC`X1Wt#%kQ8A*49F@J32|(T5<I~Hdb9~?Z*XXC=+jkiJlhd;whZpZI'
    'PS3y!*4f3Z;qdt9)62`#^E2tkAGF=hZm%pXk^8*y*aH5V3|^MR=vp#S>}QZmrXMo8;KCRSjwum_D1ULm'
    'i^*ZeCY#SUr`hgvsMc;jmpB@Te2mwD7A_tYr5v(eZmE$&wl9F>67>{)S|eW2ZN#c%0i?2EK`!zyAy#Az'
    'kmD1uczAp~Jm#VVHFK4*#~*HV9ShV?&{loBS1(?9!xv})Zv?<J{43^|OwoD@4b+N5cn+mzz?4pEg=MN$'
    'v=}EJP~Cd*=2K`nnNX~=?P@?1)o58q8dV}wH9R}b<uCC@xXDj}%!@V{@96OA@a_4J#qs#p!gy;XJ^pGz'
    '$`klvx|sbFO{r#gVQwnYjhKI~z_<F0rGis=kzhS9XI%vrC?C-R)5~hm0HL!HbGoJ%a{kbD2fpdtyw)i1'
    '#lKNdGb<z>avI(div>J-y}xJN?B`F@57+QWPF3WE1NuCE{531*E>BFq>qvZ#KZkGF<$N-ZQAaj<WrY#N'
    'X<utgs6Zl*PQL1p-)8gTPqVo&Z8c5M*{;b@`|#EcB@kgO)+JFq;Ss*u6MWrF#><tY@XL!3hb^<+d<L=|'
    'otvI~WTgQy*6vA+iVVJpBMdl3Z@!Ua_edHX@DC*}_^3_So1Fr(X3EQ!s|96@G6v+G2LI2m&}kBwn3A4y'
    'P9^@_7;7mJU(h6BCks$Ok61P1Um|uaugRM?WaHsW@?x)U{p1BLncanB(b6i822R>333?a5Wy=ze9GUI0'
    '8Q&6Qkc?At;HaZ-979F_&AAm3%(28Zz6(E;jq1$>_-b`*oxELVQQlB5Q>p|79sV5?axtTa{^_urXh{%;'
    'N7Pmro6IheSrftOLaU7s3S{`4&K7sHeMwPXZ=_)`@bRYz>lABRZLJ^jkHrW6ga<9yY6~{Td;$I96^#X_'
    'zNFY?Vm!rmf``CD&@`Nk@FBy?UWuf`d{j}mM6TV}{y7;(^sGWr3Mgva`TO(_8os`VKb~WFFU}8t9-UmA'
    '|8022CFM86A5YJCG{q!jZ`HpuJUixZEbmjS(!e{rf1hH8G#bH~8;uA{8jaxajz*pRzfa-e`{{TEUbg{!'
    'O?*!~YL$+FFA!k<3qZ(JJ(<>+;QI=b1{QIM#fzeiYY!ZI+FiK#i1((`D^7l$t@&#B^SihBkJ0(b$>s2B'
    '|7Jk0ndPVP>Xrk?;lgxHzbDB1fnlUq1P}A(8klC8A%MNlpyO9^6=ZC)r{g8aBXD$y$$gJ}WRNJ2(DgnU'
    '`X&Qd#T@gO*pWYccZF4!445AQkb3JK_pkC5&+b>tae~;n&(<%i!4N3Pz@!NHfvkrjexEIuu948g4O?PD'
    '3Y_9^2E@?Wg>iZV`2P}zBM%D{Hpaw*=bB=sLVhCVAsFcplhubQ-R|r~V1`uw5XO-2=JI&_jcjPh*P;U}'
    '9$^I?I_%_K;A47;1?el`xa=7I?d|EC5jgF9r_eyKGvtJpQ~f=r&IoV76k(YP|B8Q1!c~YNS+cg*4Eyv-'
    'Oc*BFvm=CWvwSInw9K(8teB0^2f+pI_-bf4B;brD;4m1tj1CNqTswD=Rk-X@MmLCjhuuYNs-6r>{usO8'
    '$vD|4Oi>5~uR6K;8Q3x^v1AvA)7g~V`q=^IW5I!y&oWy<{>}m8#`yYaxSL=*!wi<Z(HZ<>hM8ps6OC+u'
    '-!P|J@bzDh_s2i@I+m|~AR!*P;f%;ZW8x_#nN511kTJ(wU-R`|kIdAgQ^JWVaYia-)01~YY}<T!{i2Tn'
    'l{TA@8A-R5<s<P{6lEp+d7MC8Rd(~S_>cSooXu8!Ca|-c@DJJ*$P-MboMRn#kIb7vfqw)mHw_3`-4e&b'
    'YCHw$gNo>!Rk7jNwxTe;)mGy>G{7=`W>kc*_E$_)dnJgh7!Qm2Voc4B$vu|bwDD>nNO|3NSdJ&~_q11<'
    '#7SjuPJwF+2DpQDqQQ<@{}2S*L$+ehrE~c!8K)_}94VHvtz=kLQ+jDP**0dOH6LIv;fln}UnRtFq#k6>'
    't#x=&J6Z&7A}lPhcnx7TdoQrOTwq^AcmQASgS#BQrSWM6M;u20#2G<26pQF4&Ly(-bltnVyB9!_Sc1<0'
    'W~iVwmGFKb;`zeoY?4JSgwqE}5dja*0FOmif`<pYO-5xBzQ|XAU(tUh15a#k0BGm!_*awxl+n0EAYeb5'
    'j4@4;mkSaV6C(JWXPDdlLd@j<XLv*yp8|6*d-*{uBP(oyob41)$IL=N%yjn{SWqt{*H5YQrOpG!9I@Q-'
    'RF30f>k`~+MSm>4PJfHhd?kd=;A>Sw@Szx8gGCLrAjM5cgbir@<T;EMdK}@8cEX6r^6T`zzCxnr7-q<u'
    'XL@-t>Vy2gc?i;hDg>!0SjsSPYK+js45YZ#QWHW)7|B)xidj&8QR3+{P|MLx#e+}~R0>{LX*S8mke@G6'
    'uy~c+gP|_0o(KzG@nSp&^2lhC*a$LlrhMEBC$NfL0Z6A<tr-4{6;mdYsBr%lFHazYic5nXN9pX{;k$4`'
    '+>Q01aFjN>{^_7hPnyhD6(>UNyHuYGaY*r8kl_Vwf&BdxiwNggWgLpK0}QV+eNgZO>qq6<!0f?+<aQ6O'
    '=J`LuhRAk|dQDKZRAG5#!9r=+DO<%jfk+mS!tKh%Jp|rVXbeW}u(u)B3SoDs97-a?iPLZiRxT{@EwI=Z'
    'f-7|o;JXKw1_!>+223!(i#yEYiFAlbX!eP89RoRT#SD=H_U!32!CY~gkPC-SPhC-jGvjwwkW-8=Z@jTs'
    'O}L%#IB}F<ehQF+HIYQKEeAE8R%R@sJ~qZNOUBkad@Etx!9F&NoO^1VA2oHCV~Pkv4nK(|YZyNFHi962'
    'u-1po_g)d&B!!1DmuS)bxX<S)7~kOAe(C9QY@dSc;njjsm?4{4V!8jO!sot|2WSI#`V5op*Q`_W4|AIv'
    '+4aX7B9R`fw#BnGF>vVmOBU|}e`13F1chnQt;)xdWc3??$FCFO`2g8naMSRDVAl4Lq+oQ_@buKK>oq|M'
    'B^(w=s(J^>3?fyjx2%~%eBD;o9GHrI#n0rDa)rOVuvP)DxofzuiUBD-BK%o)jPyAHaB;NH#jh-8udvO^'
    'fR;u_P>!Z6dyeU=nQi{+JhyQk58qxL_M7AyDqcRnI38Z~^OH~zeltxmSLa3xQ%awa6h?-(5&a)H?kY7*'
    '$r({vZw0PI1YDSnmM*=(mWw|X7g{t4EV1N^x15nH0sG%6<SfsqXc&;qCe`XIeXoF)%sx;Sk(mWS9{=*_'
    'utKL3G=mAK$7~&CdxA0yo(Frd;q!=y0@vlEa=)2urO2p>kMrigu7;O+q}<L<CRV}zVkw&3J&*a<G$mK~'
    'c18F^@o}E&$RlMdMq^*o#~~FD|E_Z<7W16)hq^@D?rR^>L!W3k&{v=j5pv+E$l`4A&m`^w9?rQRutOkv'
    '`1Tq<a`QTmWPsnUJFtO5OhV?-|4cmScqb=Rsb9@lR6?(}&)xm=0s|$C8=znX{1=dO+wJ^&hr|HP2jk@k'
    'mf!6??o|8yKhLxABQ_+K!^zs%;yIIl6zD+ZZiYpdqXa2z)OR;dK?DRP3E&!BArLsj#ltZd=DHNk2MpUg'
    'QYZ*H05HY?9C-QN1%LIKbXNj8-y7oR<&6>X5rWrVlWzx<*9`7HVyTjG+U3F30yr7^4X<!C`$+!mvFAT6'
    '@aQ>b;O2C`=_E6oY;@K~OX~pO_;2{<ai@%*q7Ob4)n|dh(zI%=nzS3(*hoA8{uT&i`EWNGPd^gA@l(E;'
    'SqLx;G+u!*nR-Ov-3aR*8hep#I6bfAj+0L?37G@hCKKWdb2j-EY$+nA!^En1f=o4@mPVv*P3c)k4Fjf}'
    'f0J+fAGAYAdIH<UcqP#5-fW6h9==YhJN30GSToDI??4!i$1eg*7#RFA0E+*bAi;Ehi^Z7L?E~e(1lnwf'
    'BJa;k%GGy9pDeE@=u>wQm@^JY@DamYcKXZ80zeo}@$r(jJZB(mJRpKg`YU`Z9B$j&qj3@xU&1k`XizdR'
    'vcu(BDw$Je$fSOV^=QfYF1}grU{f~LU<mY&qVC4lLt}urjt?+k^^7WKmp$$OkzY$W;QR+>ALasR{?_N?'
    ';pNfA={sV<%HDgFqr5Q1P9~aTYV+HNC1tIQ9w|G3yC_EBp)Tf}yrK!93v|Ck18K}$#wQx+c$%TC%qUBu'
    'JkePXYVvyWi{aIsl=0x064|KYUeRQ$NH3yx2pR)E`17o3yB9geYweDn>OBTI#{PK8xIq-gAL;RaK28M}'
    'nP@IuoApzNd*Rsh)^1{1<6>JT9CpCScDJm!E5tF%W38m!iOn#zgFfN0d~Xa5Ty=cQ*r{lBZxktRUw&IC'
    'D(W|;7%|G{X|h{t34q-CAZ6hDG20*8V^}Xlyo#(<JxeXxo94hh8||DJc&K|_VrkJbUf!5YSSlMBg&Ytr'
    'Apz{7yPf^8{-Ud~NmMD?bnFc*fn0pnsA5oK5A6$(&wEvxiJAx=H_X<^z{*k+3Kk&w_mYJx`&mLUj3Y%*'
    '7akVertoOlXV|aEASh(!WdjydAr!ua45jP53;B`?`4Cl@X~#I0JDm8y#B5-D{XCYIsU#Y{-@-YfE>Gs_'
    ';9{f{GYzUVJ_jH_(&bBPf?%LvD_>Aw?*VzSs3dR;fUG)}l>E~3C56AkEkS!wcV&+~znACqGdT8ZbTRFR'
    '1I>`#NKA>jhShSlJzMQfR(`UO%HP+x{ZCRC`Jk-26IU0hJAt|&mn(1u?3d#UGK-TuvP70;B~+A@`P~)s'
    'I)lu)p*T~Oj*9||AcyGW?fLn|<u!p^baYd`%hM7C{!9H@lkh>VUBOEK5M&5e2o~+om17zD+W95>@E7#J'
    'K3zS`5&QUlI)+t|zj~GN5kmEmir5Hw<2Vae_{rt16ITIQG3t$%-1zb^JL)1vWETolC7611!yAmnyxN4X'
    '?$_8EN(%1!n4W?;fXEP7sqg&XdrT|i^kMKDtPHHgub8QLFpqwNkDdMOoZu0Ji?tZwzOHIPwWoqazh4cH'
    'AhP(~o4?Y4c(LM!+LS82lUY*bIxGSe<ELaRs*-6H?4W&3X<K1RFb3tZ%*mqPfQvD6H#4B(N5aYM10^JZ'
    'foyZ1OZsK*mCNs)D%*AzgTm4**#auU=9K={jjuo%W&G?3C*$Ay#NIP1dI==POMN5!lB{I6*+2qEQ|<!S'
    'Ye}r=hde6{eF)>sz_rBJ8=8Y<YP`t%EnwOi7Xk<J$b~}C8krnSZ}`w?;XNK{x+38~S#$$m5}3re!EGQF'
    'yOND|2boEiuT-$#@ttFXio>XEg$g@inJ*MAViojCOuk?!qH*t)&q>zPa$OVo+A7j3qaFfWr&mBdW>R~I'
    'ZzvjnxLxhhJ8t<f#fZmv&kJ*e(@Z-9yW<pn5(Z<Z;?)O|!2t%(5bURn`II8Z=v3r-{jiwb&qb0rpCmak'
    'VaO&ExP@Yb*S4CGsqd#*f(WH6NM<MHCrMZ{mYvo1I>A_{vec1u{)^$^)j8xj{q^eo1uLC(3B(}0%J(fd'
    '=V4@U&PFp-vcoJ|1js%!=A9{q5+fkAx|UrO13)D($POH23%NM_Pnw(33>ej06sl6ti2B(|*dSR{z!JDq'
    '7_@3b0@x2YTv@85dV7FfpHAzDj30)wRr$F#OYzv!8@=G`5X{`gqp5~Qd1Dp$SCw(}XC(`$G34Y$BgpaK'
    'oOR<9@>tlz3b~@njangH%pk$GAXTs-{JpXSp7GzWLGmu%-prc9E^zP(F8QU+h3%RPKfmqEVhtP&I-d5&'
    'b#}KS=~l><nkB&*iHcz{bCTxF5X>@+yOL{DK`1=em_YSdfe=<VnHeO$uq4Qc`lr*&E1Ft(dDS4~p?Jr_'
    'l8S=i+JL{xxhXqZFJ4x1=F*5DXjZOtXD6P7%cXY2j@t!3Z7jt6WHOsAc*)phH_KgxTCzvsGSeOLF4J9Q'
    '{-n_o5@4Zv@8}NlhDP|#88K@*6F)}_MB;Jit-%ry7(Tn;4HkGW%kZ5o3-z8hap29NE;rP-&Ejvk)j_KA'
    'rB-`seMFM?(qTV|4obl$&F}ETcla#+0;(A)-TZ@gEe6!w$oC2h91v{IueD|PD=|TlZ~$>dueCe03K?~g'
    'UqJ%u%B-EV90>^*JP9XDYMw9LP~{6j(jr9Qq<94S|JMXS2(A8a%^*2<^b2GErhKi<mV<ks0|EwSg3E(0'
    'Uj&AJ6cQSlF8iAJ?H&8JR~}DT-td304$&3x0Ive&$%DZ+n~!r>4_IkD;x!Tmy?~oz*)82i`CXFTO+AII'
    '(VTAA0FcjDIm;91p5<MKlSvb@A>^@L(f~i|{hS{Qzy-;~r@Kn-rXRG<Ko%>wTNYy=DoSLfQ$#1o^nhOJ'
    '6yuXhW~2``I9>mHDTeJ9#~2LOtBhdDhQ+s)bmNfBf)TwS$St!#Jh5T4B;5%nGpKMr#qv5P#5rE%h=&x8'
    '=HqF_RkOm<;d5>qxghzPSZ;oYFvkx88SauUAv!FoF0x49EIj9a6%tn)o9G8p<)Tw8jU$d&-bOjEhK$%W'
    'uSWS}o<`QF%1Ei`Nb}4bB`OLls0T4~`v_S*!jFY{Dl*(&H>@ZoMfbCLDYWu5+`5r@I0V0GDQlBcR%PyG'
    'h6z=sU$%ZWXHQY=GY5%yYm1b;&oJKCR0m_9uO|Chtij5bQPdtupejiI!a}4+XiR*VP<D~q@F<km@a+wc'
    'u@b75(WD(1zrbfQ4mgLM8_Z~L?{~x|(8*!w^vSFWR!H~{1bqU-82n6<(?GTCcI2)Kluu332jV2?K%6Ih'
    'GZ>K=HK-LsG~p7rPy{oexC<-}LfiNT$YWv9;i*n9{~;M;QG3*w`^&cv#xotK6jLtlaFH_?eU@1G<Yoa9'
    'K9&%6E!ugPBckoX*GwN^l7q~mpCJ1)2V`y%f70z$k`{T?H1$JPIqPc%P=qux7{w3=_Ek;vb-zyg7j9K3'
    'A0#>i)Umz%J{si}GYlOQK?(d#uy}3UWE)U}k!sNT6#V?%+<cN5uS9EUu0myAa0O|UgfjMUNpj^^tb%ux'
    '&d&w<fPU+WB3py7_A+mInlj48tEz>_G6(e?;C;T%5`zk{JEhv%eSSODW$X}+(4#@~408pg7ySF|Dg+p6'
    '>SdNO^9SuP21_3Xo%<ZXKfrxL@Qvg@5<{uLq%l~p305GVz^b5b{f5Um^vbmcpCWW?n*mT@zQp3r%Y`$~'
    'EAUmGa|CsJp!4tO)9nln8)Uu`%siRdzOIwm3n3wLm6HlrY@xPsG3tm1mpm!VsE(UMo#MW_=xe#1gK#+D'
    'z1LW#{v?0R0L@?hh#rVI1+hhN0$HBV6l(o~TWk7Z*|}i}Kw`<Y4#*J~GpyNMfL!-5=m>tO(qbTh3TDDf'
    '@#GWF=7S$;olJRVl3!9i?v%v6<sBmGFqug+m8oPoqUC(BUj4$<Mm9W{X(-=3op!}&x4u?*QT5K*3|<pK'
    'FTYmQMVWI0Y|Grx24WAjbb>fTir3KJiM!(-Zno#kH-w!uNO~%GQ~-`W0CKNG+#W0b;(o!ZvP9e<pFKhn'
    'm8gUGfIjgGq)vP^ZLgF4#uA>MAHtj6^?XupCS|u=<NT_Mk>!M|7J`KHXu>A9IUByxW<nf^Ii6Vo!9A?E'
    'hD(fX_<6ty4$F|)aCC7%gIP5L1sWO)F+#4^rt%7aR=GSDo-bVAq?;{G!qPt6hYO)>Y7|bj<--#4AfeD6'
    'jHeMqphASc!Uj%>QZ$1XFHY`E9;JAvM@$mEMXdbMd_3j0B&z$2XmNm%T-jqwMy0%hOubR5WDR;o0hJaF'
    'J)0VMK!%}_=Ven(87GBht+W2H!PO=o9s!zTx;j|8of)@bU=r&1JiVAcS8*vuh?G}vqk2L6RK0DAEI%_o'
    'No`~J1}o{d1!LA4Lsr{HtS1|=s*P7w-0z8oE7@qpcIHV&tGc_Y=rif8t=(8*&s%HgVp)D9VM?2Zzm7l9'
    'J_&4zQnwotH9pwMD*BbmzX1bGtP~|-8V4vvf#I1Zw9a<SII?5kOg!66eOnJbOZObxO+w2-b`lzv9{PIX'
    'rAgEg$1gBfKlTwqaS#TEsYj-3#3`~uH`ZM*HXYCKkrz3k6<K&TBXv^C_5(boVK}B0T3(WkUEPWp8V{c?'
    'm-px_!v*g`+~aSb9sUB^8A)Adf-vJc&>B0nJqziv;Ra5qV;G{q$A7z?lj_Ke6WhX&MZW3yNtozH<R%8j'
    'Mydyf5$T~Bkq*sL02&??Kct(!k$ACZBiD6pTeneSIYFSCX=1sa<$G2XBRxqH#|T{CO`^y#p=ots89_n@'
    'y}h4)T;kELIn*#REla(CnpnpWK0YN&-q%i{7}hu)hY==%&(;0evxd1?)X<>FvG)G`>2bH$@QpZ})3~l9'
    '`eDs$kHyN!1W`@b(bs+oF;44OwDE$Tww_Kd(M-o!e<H>maMwe;>isk(p*@pZtk_;+7J+#l|Jc*^{-nK`'
    '%_iDs4gbyxOE2iBs>vQVgM$D7WzD+d>1swkp~XIC;8<KIID}rQpV{|Nh&dWhQFom5v^5hwb{=mY`7vVk'
    '_$yD6;d_4U#I~OrNvL~)p&K6N9YGxGQDAxz!Y2#`W@x*n9e7FX$4L-|(0e^F@rP7-k}NL>lhCzI%SzqQ'
    '!DrD-oH%p>Cl2($bS*PAZ6BFd?CAKAhGF0bX{!6anZ{}2`;{kYm!#tGXxj}NobOhUb?u-vtcus-Fa2j%'
    '+X$>j2`-Uuh$WrSuT1~X+6^)<0P9`5=1>;{!xpno@(6ux_{;g*_d<E?%WM9?O^@|BS22ZFfZWYI(DZpy'
    'X0J)EP30!E*Uh}@tW_rPtmgyZMp*w;lWxQ^g4d79LSALrCl6w63RI&A*ZRSpPmuzfBOPYBc=Wm10d7l<'
    'Ahh*Lrma_NXp6Lf);fBa29fJqsqJ7f&W|k1_XE?25+|^dG)<huK&g%Fz;Kh)(F0_=cH+8N+;i}cy0K<{'
    'TAOFIMBxG}Z#guGc8BFaSg{c}c8ah>W2VSVY}YX?-;P5!G9t?iT+7FzW$5{V8{@gn5F^CY!!U^g2P13^'
    '5Zuf|w2L$xPl(ME-OX00&=Ong*t&@?BiFNG_5h2nu7iawERcB?zCt_@XKg19-9UG3gs%(~S!v*>09Y8='
    'o=!m7qziXT7a*My>vb4!BShGHUj3R)WciMb$tU$ZOkybVOcd&PXvYe5%hD4wFaj*RTVbSQVbcym<eFB5'
    'Y*Tkr1MX5XQKR(3PH16?+`!U0-a-%4jDuI?A}<IMKf(m<q`v1kiIt!z_VE8)JxJo%)v?NeRSHaJ<u!5V'
    '5GyO37Yt{Mi*<xAddtD2tDAO|#8K)Kl^}|2<i|kcaqOh2;ULS?UDFE<8<`k^_!-|by^eg6X=}glNBR3v'
    'e$k_x5n)y@5L4sH>0d`by+8X4h=$ii>8!pR^ga`tWMOITJEePH`5;_?c<>@bH60X+_i<+n9Tk*wlyWqR'
    'Pwj5A<AN+8?iL#`U<tCkN6oSL0!VCx!<R#$3WH^EpV`quUR(S9EilZ*(~}G48??Mw-_oMQ11c1N&K4SN'
    '$P?7G-KbzDO<HKHnOws+o2WSX3(cV{);*>()wQv0x{CUd6{{$`P+r6CGg>|uLMK$UB8nRFZdDzryf{79'
    '4MD7&V-@j1QSw^mm(KxT<{R8^x2`Zo^<rVQWv=+V#j4mu8>Jc5*Rfo4(GK#Oi}WIaS_Y&imvDth1s7Rx'
    'BQ3dDJ4J(ZX5~HIa!E!zpt;utDlI1?7YVr|1<fg#Y)b_+WhPov*|CbD3pF&2d_ULM&aB(YXYS-SHqtQ^'
    '8@YZTJ1tgmtlxn)iaNHt4V^8Qe3T~>D-mu=56`LxS-s<Ma8(R;gA#S>N7Z6i+m-JW0!d}Pr@96hRpp$N'
    'i)g=^luRZyz&zgUD0$xoUXx7>OT8VnzMvg!GRlrpdr-T>o^8icxx+kU*sklxRv3AHkXnIm1)dT52?CG2'
    '>Bk0^^DQ@a!7Ar^sc)dbMBr6++}KNvYIhi0_aG0Z2hH%hgTE7+e`LZ}r3b7y&WKjV?p6%M+D?$ks@+$+'
    '^GP_JV(!=Nl>n^jA_LMPxAFHX!Bq^LL98CRuL-UN3U=;1xELNDpPmgbFRSf5yh4@I?ILyIQ0fsyD3_Ev'
    '`>X=_!P#tzileBE3`baBA?=8H!?%Qups`+|M74qI>V8T<6npwbi*Sn7$)&==uv^t_wcfIw5yk)l(K<3;'
    'Q8E2IiGviS`<DZ)n7dJRFO^(QQr|9K5{v_;aS9Py0;=HQYTJnD0g059(z|B6bfek~yb^}_F^w~YEv&rW'
    '`8?!bLge)2p3>68>O_|GQ|ZZde{W2+Id9L;!{NzQ7Gw`h*GQ0;n4w`>e(Z&=?szD50yFeO(=&bBPEuV@'
    'O)Ee)W|MIgr-@;?N#Z!ZpLm!J=DZkg7An70^5Ry!7)4%e8b*pt<R&OF98b4H$2XI}vUSYhox})y*TnB5'
    '!|)?BOcGm9T;25o-_#@5PF<%u$mj1X`rlpq(D4k@F@5jEJsh4m#*t_FmLBZ(Ykc(C+vcHt;thSzKk-~Y'
    'II_Kyp=CS1)$DCAFoy1%6Wu&Iwk-3FZU(_2ex1%;<-u<Rd9x|1V;Qpd9n%>O4UE$x-#I*VFyR~zz2g&G'
    'n#8w!|HwPG{1e|h4)7j1mZ=*?!*$e6QRR}(U$(vDV^g<H^GLVfSg!rXJ3Ksc%|<WR!d;J?$Jc8%xSBNJ'
    '{H&#p-SIMnCwKALJHevv1xg`OGe*0w*S`xL&i?`hjo?j)`6MGzwgR3=D%~|12}DWqGIcXyq4E86ykb75'
    '$$fOh{5*d_51(d><QPE;WQ=G4N8?#2WLFDB0sSMX9{8uVZ?4}1`{cws*55eC&KunxS|^8x!@xUs4maO}'
    'H}~U70_beAo|JAFdAE`bp1-=vv&~jlck*ELMuV*55z=BSk20H$tf`(MG#;<+bU&{7y_#**62>#mW@|_D'
    'MNa0E4`ws$<1=t*InMCVKGq#8ICA_qhvw0du`%|WoJu8KRc(Khl{GpMOPHtIL<p$lQH?|hBN!e9&WUR~'
    'o@*G^;hU2~Hwc`g23M~HXR`qt2n@qF!z0}YPL79%L&rHh8tSfr&#x&748s#V%khz^pIGL}k!8O*It)DT'
    '%~3Ofp>B$`cYY=9HF>!f?m~bYGsg(>xT8mY9GHon#>lfgBMOq#(hWUCmY?X6ZFwfbU#7NgnOJ@XN!&^j'
    '(~AQmjx0Crur6=hpUA^XGAkHy)6st9;o>9lN<yyK<_QfP70dfH9sdTyU>y`IQ6o}v3-Utnaz-PlB{>>('
    'm{%<;AP8UQ8l}*PazKhabSZE`w{iFhO%s|5P3IJ=GSc-@(0G~$DYX!0$%Zrsmi7#V(U$Ycm`{}DVu8gM'
    'lmSxt0ug&$(yfaj5mHD96=tCT2V@-P((c>{iB0r-b}sTCN(H1TzziW|7>W;4?v>cEUoFs_wyI$3XDc61'
    '@xy6|KP~5>Sh9i+N$Q`Fv3UlT1bT)HQitk5TazIuHXJKtpA_>1cPf_$Q)R0wZ0g$n@U%ccVM*|Ne;w@V'
    'q?uBBBSr|+HzZW2D##D1{{Va`c2!8s13P<Gs2EOJzAUzDq-i3JyDoG)#pAPDs_Wte^5YH0rDBso4mYco'
    'F<p&`^N|@{s0CvWOcaGq^<ZG4XNY!8U7!KpiX@y&x{GMH`{%pfe=BmDy4U(%5bmWnpI!U0*ZJ37>htFv'
    '7$A`!#v@iE1L{KOmL#zU&XUyDs7{}f5-Q1HwN{Usvc7o_+G0iN+zuroiHDvPTB*oeRlh|S=x+8aE1XU%'
    'm;e_RCz;Jx<Gb-cLuy{cvtZ5%b})FF)S`u)((Uh09oh=#HAhxvshnp8g{4&F=j`;3Y<?7SgViTd?6tIC'
    'Dj*$x;+65UMxNx5iuc}a2!=svb0EQRnz!$)yFCgv=`GwFkZqA&pzOYox2}HsDDBmedht4;24-;=)fb6m'
    'C2r+xuix16;g-0sdYR&OSF_{N8LtnD;%9wW?8m|*2`3M)%MD@iWFRChi;;`jS?5h`Fs+qyCWIRQyjx5e'
    'bEK77)ma$wbAWQeuvk2NAT-0NYBpKIhXg!pu2q6f1=Wti;jr1dq^a{)^MC_Pj{Eg>hlrhB&S(`YDU*-~'
    'K76C#{^rxkCid!CH;J)sK6{>bSUI!Wx4X#-C5LY1Jb9LXap+pLr#z5U6d*4G#Kqp@)61jtUxrxXXNzw^'
    '`c<ntb>c5CM!{HcewF6y7P%^ydz%2?T>LHLPAq`1qfBm7N<O(N(w3-FY#T^r7Bwyff8rW6K1m#r5R|El'
    '&?BW(3kFL0xOQLr=VTly>a_Ip3c{m=SpAX_uVygf^$WU69Pk&{vgGU-_16`YQE1wkh@90}$g3)dXdUJ2'
    's63qX5uwQ}!E3?_9=Y})@*Re2Ko_J=L;X5Za*d7O*MeSeKrtm&RUR*vtIWia?a0OX;m@O!i}Sw?c_QNI'
    '&G5(5Gts;QR#@_8{d>c+WAUvvtRXo;=JasAzX!C<3?Dc6WYVQUr5^^+1zy1=rcWWga`d;ir*B4Y4ljqk'
    '!)%S@jn3d7Gd!at7j`?;U;P8bNH18UzvOznKmNhjNqv7({W50`AncCw3ZZ(RXbkK<OfkORqm_tybXtN?'
    'NsE?iBT|V?&SRB=0y2J>%V==cI=#(Qa@N4LAP*{Z@M7DXDrLMbn4HUgheA0@s02i1zdmSjQ$C@nl*^Hf'
    'nIa_$e{7*r6`tafD+_66z0b;V^9_VQ8uhRv20~Qv8dVG6mVl>Ii_qpE?h%ceHM^uu)=LuhfHf@!cC8cz'
    'CAv}v!%J~aSrmLxJ}fd%sEt7(WMsFPeNvNgO=x_1B1Qhp8ROP$?RoSbQ$AQ>8};OC?hjG)VKRn%n^Zhd'
    '4DlBhk_(xowa6C#!n#1%%}N8(Mt16zv0bE5aCubWh}I;^W>ZVE>%o#$X%3yNVP=_2xd<YBnFne&$*fZC'
    'T0U5>`7%nGRuwR_1TodT)w-~HC4FJsULB}%98nSFG8-=?hN;x}#zfE%BD#kWT>DK_KGx;x6AvG&WGdJA'
    '4LUf9PZHpfG{I{YzI0Q|K%(EO`A2cQN;VQgy&Kj_ww8k|pr))mOyl{ezXt|j>$)bg5Ba0FPsSmiE6$z_'
    'BvUqXOC1MP1z;6?s{Mw_xz#|bwt`)D_@&ZSCp!W~;e<#0nR-Ch19YPx={!>*OE@T)RcHo&xv${{)|;Bk'
    'sHBBFJ@pNgn)1!XUghMbYH8S*ALX{FULg~rq<ZI~W;u~;!^(<8?$q+>GAdfb1XPkq9ep(trbH5}kTq)z'
    'pk#__Ay}E!LhL+QNpd!a;H#QVSs^mX0H0@{P<Hd033JdpD1{EOq0~OOWE?#>C=_y38DWGL^BH7WPtB=J'
    'hgnzLEDX6Qma=WAQw~Zc^+n`1q1(Iyp%>wOO3<EgfHhK<3iL)Q=_!g47OhqalS>erZV*_WWyfw5`ibqD'
    'mf<>v@5PZGr!k6RBTY>mS#f}wQxbZi2~o8{fRGtSZfB>)G)77ux{+%pz7r)@Z1^^^B0oTp<tNAuQYZ1O'
    '7y^%-$oD)iGIbweYDgfR!iyX;F+6#K?0CS?g~XLJjG*HjKPO`}Nm%yEPKAuBZDvO;gHjm;?YdU#grQ{z'
    'z7dBQeF*U9A;7JzN1h)=e(Z;q@A#HsN2wVnp`G}a>jXh+B1;(r9qU$NMxJYiL2OxpZ3n3r1SWppa$LjL'
    'F{?I$B)~fv2fFLveTz*8>2Vmvo~JujeWgQ^-%k6cP)ZyC$qha&!ucE}#K$ra=<hX_A%TrfP=Y!28zLnf'
    'Xq9nF$KfjMlKv+5tJJS6OeWPBq%?lj9IOUKyy#%U(CVcSh=r#zz#+UxK~R;n&`MdoA}wI@aU%rb`+;HT'
    'sTZZ5ljufb`e|YtN#J1;3v{U5Vquc;<5W*m-wwji2n-kh`m|bo^=0**TBxt)<knW}Yo1HiwCG>``idK0'
    'U%jkmRc$ed&Fbv5LWj>OwPYjY*|DDLm{&P*>>8o(g|=>BZl>!Arefa=kZUEbi`iL-Zw*T~T^rePf}Ajo'
    'TC8&9dMGqJ$Mjt*c0&vezV;wZ#dAnKBP+rHnKnjGXz5lM*@0_f=Ih6f9R!Z;qE@Ot8D1I&X6!|NXka8*'
    'df>%){rD1$6U)>c&y6D6z;~n{>$Zz`Bz6o8ae#4`>Y<)AE@6f*bJsU?UpGD5M3~(C)CfF3jPNCEB$20M'
    '8cc273PMa6rfb@cg#k-aOnSEN+fGM8_SL1nzSI48y5BC{%jDR&=vSjKj;dl??S*wHGfkfY+g3nRWlXjb'
    'fKpjDY4dm#W%lJ};VBg*i5mENstBY--;Z*Njf)^{zLxDTrSlBO&>8}ImXk|0_J%$$MS-XqL+vJ4n8Ko4'
    'D7v%WuTrX(w*^O#oB`gdTd1P!+s5|L%EC%=o1U`iQ(4jDxzl&rwa!*lHCY?q|M#XXfbfI06(C!Q^;c4A'
    '!!<Mx(<-lID+{TrLDn?(?AbfhP8^zYOEzCe!`+dONabF&wlo#jR!3T`iJxi`K2>1cc{Eiej@t<MlCjrL'
    '_*V^iw_Ut#lj?2TE#LN4R^n3@aNDpF-?K}&efc_m_|eZwU%_LO3V&u!A{?*lNd?Nhemiyk%r9N%uf3v-'
    '!%`_gFLI36yz1W`F9v9mGCz_p5hX8J46uq-*H#3SM_29ewkrYxGPM`20I8H*E7~R2%Ak@;nHS4Gn@zKb'
    'kypt*sD$CFTt2(v9&QFm+i;X{Em9LF0oHw$#X#~3<BvBiLtJ`g(=_oXd7ZbBF<vk+o&Nmp?eJ&JEm#zE'
    '7VA(<>=XenCgK)DnVy`KE>5zY%=ER^&aWgrUBtwf$Wd?9#dgE&bTtXJo}#`%f>Gl<b+xOqB3WI$NuQRq'
    '-q`k9NR^D0AV_gQS@_Q$jrz^uiyr3Ta#;!pVhM+83~Z2fSb@T3DV4=I_3SL<R(WEBU-AviZLNc1c#~4F'
    'ZIW}R3R$U4xvQ|*Z8}ebB*N<CzV$cORx<pW^NtM+4<hr}VuIg>%%fqJUy~vfUntK{#Oo81{no_Aef1fC'
    '&FxSkqMne;SAQ12C-i+!=xdPBCo{oKvij<7-%8o#DJg!<6f0J9H!te4M>={?yAVsLAvZXa`+22dq2&kA'
    '2UR990<ykQJIY2;5@yJ9AoO{R`R~KsWIX*y4*Icpz=aTLuzQ3Wdy-+9SJ8){okuC3poy$RF0TVks7GJo'
    'Pyi%6CILxQDE=+{D}IG{Xg2v3e+57CGRLFUj9?)Dwbw5N?{V#;uVD;?bG-Kuy-z1C5S?VtQ$_Y??FD%7'
    'K7*~8fkl0U>w9$VG%y5kT@^!3%`c3AWR5LGpJxrGGI+(JC_9brY%)Zzohm}YSn3;_>@&M{GbUfo0m)K&'
    'RBF4TxDZX?67i6$G%9vNpRctXyq$$ffogIcLu#oe^@qzd%}7=E{3d5XsQHCH18I%{vQ>?i&QTId#Yi3Y'
    'NMrr<kAU7kQQ47<rhKxPu-D8MBPi199L~B-T%}UfQ>sg#i_|4?)|j}MvZKDLG7?n6a#IP+nhewP3E>Pe'
    'M<OFSC6s8f0ce6&R|c+eUTy>Mcm@qtdy@M&gHataQ4w9LNMn0;-kHqnRTs-q&8lkB!!`@1p*Sc2Bj>4='
    'A**GSJatZ(tSt9z0-|uaWX!%!EE6xIO_)Khz{%wZWjhl`)f!`y9F(P$+YT}FSxNF*eRSLS?(TjSM)=0T'
    '(q*YcLtR+j+A;`h6w$g`2y)0LH864DUKe9Kxfv~nCh{21E9e~0<34vba4l@Yq35&t^Efn<@YGbpGk)`$'
    '3eRLM&q(iFo1wX8pR01+CA~&bZ?ReG=0-lqHTj#Q%(nIcP46)%1@9~Km-9j#EN_$dVaq+TM7VB0gHt8('
    'H%{YR%T8)@Ihz;7+o`rK>?lkNJO3Zt@I)Q'
)
# CATEGORY_ROAM_FROZEN_SOURCE_END

if __name__ == '__main__':
    unittest.main()
