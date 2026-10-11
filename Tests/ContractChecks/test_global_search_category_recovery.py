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
    'SVpWhB083O(H-6HX#=b;r#pSSM+Y!<SL<tJ)T6F79FNU@AIqBSLyPq2s6TS`ku{<;S1az-@%JyEp*j8H'
    '>C>}g9DUH&N7~-w*Qck)&tIM2vUbeg4aH;jZmu4)SGRo3UXA)Od)pR}*}FvrnY~+<klEX$hRmLvA~JjH'
    'tH|taRz_y;#yT>48x)e+yIm!jz1x?P*;`vnW^emqGV7mB3Y&nE1G&P4P~Lh-2FNEOFpE2!7oHF&yH#K3'
    'Q(XVd+r8s|@apskjEI-7U*QG4GZtB?HSI}N_-$+uT_^fzXxcs7G!54sTJCV*3=BfCBwJ6Xnlp6zqp>@{'
    '9tC54Ovl93dm0w)vdz|-RJn~`OQAp4Fvg^3>!vvz_d)1swrTVRqmenJLk&I{n~pZ_^{r8FG%`k(H3m7W'
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
    '2Re28;}IpOFg1f}+DISwMphs6ETO~EKqEccbBQw?(7vs?L?Z^6-)l-a-6&WXf-{$XTWP}340iI2wd>0E'
    'J*&8TV-Nu?&@~Ief3gb{9Mtk{hjn{!)ASkHE?s4K9n9%_@U*F;Bt5ZstzNNOMvbj?5@$QQXp$^$5_NKj'
    ';<J=*xb!u$t!X-Ml+2}2c_Zdc>S{A5yOv4wGv(DKP1_l`3*XOE18?7lO`@~l<ur5_K2^YeRmdW~gvWT#'
    '8^yZ15f&Ekwu$e<ph=I_0NCCOF5n|C%GHy25C;Agul%hl&#@CLYyZo?hNxFJu+_>J{G}T?Qa0lAWPHBz'
    'o9vq1kk>A$Yb9|t!|CDF0_)j1U)mT}ho3s)pk#A~-{0ToMfQ`S)7^RSD<zd`0vuM@&-N=|h)TYmNoW{y'
    '3uatrTcn*#)0>|+R&_64C~Lx_k+~Ogc|JLg*@We@Ip)~CI6!V4$mwF)H?jJT3G0@0C5^0Bvw7|SPMnuH'
    '+jD-dveI(1gKe1pyL3PW`=Yb@sI04oe|5kmr$E1G1f*ccFC~gS5ZSzGU4%J`yz|%wET36r?0gWbqrNyj'
    '`S#@b(X;c@<D(}h&yUZ}Zgw@wML2P=HJbc3dvF84%i4j@h}Fes8*uvWs7WF*t)Qjrx7TS87m?+fc6eCR'
    'z@@Tkl0DR1N_#_!$2gWr4N3=nQ`0qb+%qhF*oRMb2YgQIXnIdKb(h-K$hK@cu!lC?q-xUA8AIP449C{6'
    'rvrq(<znTd;fRdQ@xY|S>W?g4w|m20ukTo7=-_#YJvKE{@0$aI*u&8#Fe{HB@RP6EVJ}dZ_a1+~Cv(MR'
    'jcNdWdBpwIg4Vi&x(b-!9FImYxhF~Aprro{UL1S#wke=jPYG}oHl}ki{3RU>NU((;PYQTEW$#6gqyqz$'
    'yPy;0j3o-lA07`F&=7A5S0GTm_molDWSQ{fuP35Ds}u5TFK~(g@tp?XU4|bb-U2FW42eSi11E7ZXo!6T'
    'n5X<?zp>RYm2;@1O{o|qe2aZd8xuop_+7!A%_*KDI%n8%Z=$?@ee$Fx-6f;@G)^|@Ean{#vkrHdS0wsf'
    ')mc=%nd17b&;e47!YNfyEi0eu4T-Nadmj3}tkLlG1MHjqu1$RJBA9|LG*MKa_j&6o(Tv#e%LMxq%7Q1X'
    'r4oyM+BPMy^$P2n??=h*t772S0eKH&V|LkoM|HuZZL2n!p~Z@Sf(1LrQ>e4}%BO8LqF^^WWPa7zdLGwO'
    '(ZkJE)r(%ZF50i)xMCDnBA!A%@Mnjd?-;$xq(*!pcAk3Fck(D=*N!j23!wA;E-L`P^_`a1&$-cwUGG1H'
    'bEl)?a3|>E94%sySTiqX*^n$3L1poVj@%{UON|!R)Qg`Hi~6{+xYCXq250PTpsrUWdRK$U$Oi($@NwH6'
    '<yyIxzlLqcQ;BVZhwNFN@5NUqcu4HI9-ZfRT<p%iWYmANh-2`SKb4K7c)p;3Bp<h9QUmRLKXdEg#1;Y7'
    'Mpscxrze=QzCH2oqoh!KDyH@R9;5~Fu~7!ds0ic-+v8hZAt^>fcI2Slg@3ji_iVLy7849}3Xg2-+Yzmz'
    'dsi4#{(gAT4<0b7Pn$xE96z#QH*&{b-7cKE-S~97ap~^B%eu+QdhsEk^NE7@J=m}HXkmAbR!hn}BT%Jw'
    'oUMMMV9WIw&HwF9#Z;Fg7Pv)z@?@gCU>C_V147F1QRX8{8Lx0OJyE_1Lto0c$u$KjgI-J7d#>xq5(h}w'
    'c-0HMxV?Jo#YdfPvVU8`6Yd@xq+5H|{8gfW)T2DgzuzrvXua8c(c^Ti&b^@vG*j?Ii+OL$fok#5=SnL|'
    'X+Kx)vm~O*?{N-R_GVZ49S?DH8~!foKxzn1Y6Nb_0k{U^Z}%kp*1DF78`;6PyNta_#7y1D+g$|STHk<M'
    '1RT`9pfN^RicvV_8d!{OKR7)5YZ1?DG@y4!@jQv)Jjv0#-30UQAePr~C~t#E-mR)Bt*h~x!-ZH>a^pvJ'
    'M3_yD@%Hon*7a;#1(fWwbSifa%Mxpm7{XQEIhoS-)C<0&-o<5&lK|7~tft;&6k&SOmCS%ND7ddG3^&-O'
    ')U!Xq5Lp}er$)#)qu?NnGca;@hWZi31tn3p?L+7<=ivo73lSQ2dG-?{qpIcvKtBG)bK=YGF#~>ri>|^|'
    'XA>co!fym^;Lx*h=!(r}pLOaSI&$^1tVfz!4fpo|<Xpt3`A_-S1NpzWz=S_g?~$z0uhkiGn7JZ>-zCgR'
    'C9~Oc^4_~(R?I6D)_L0G(z{dd_-D5&qY;hKsKVH>zPJ;0(TKKK!M9R3S%T`>ndaHO;#rBZX4Os;T4&u-'
    'qJYf68Q8v2NUL;Gt0p71y<k!dVRj@FFuoF1nLt&=8{PB-8P67@?Y-n|+}v<-y|U}n3iv8v$Y1<I5ZU3O'
    '5_tah<RnGWFY7ufBT29rTJmPJvArP8$pnD@6?ekh0rH0=L+pN-Uoi->wwDFkS<JtaiZ*fd+m>S8s$syp'
    'Jhnr3Qi_uy$n&m}M9sVa8Exwvu`Ch(Q5uN*>M$Ms6O5nK)R&b*28(;*ML;Y-ivR!<uhl%1txMRq@+bbK'
    'Axo(sb=Ohz@vqUo_-5f@P_>xjk%>3S$;v2=lLC8QbUdBKS8P~G-hwpVZ^@O*669!s@!4UvRIbnS#Zkf('
    '`NS(8%#<;Fp6!-WyAEU-Og0H@>c6Bs)(^b5hAp=QDUF*YoNVrlmv3ZcX^MP@G1kl=!3L0Xk-@Zoe@q8_'
    'Jq_o_1pF3(^sa)^;Kv_T?DK%KAk)S20$b_PM(LC+)y)S=!L`~tYM*z>N)aCcsdU=0Z~LMBZWmE~pqzVU'
    'LQ2w=yNgK4<}S&~c{jYZnzgbc<Al^ZQn>0)n5uc6YQQv;qO$JZL2SYua2J7{hJ(%()_!VxC0ubUyo04y'
    'r280bo+>(ZJhW7>P$Y=*r89Z3zhe)U=3N9QfxJsLj2lHtkQ;_^5XMyE!Ecinr!E#?cA~K@>p1AH-LM7>'
    'beY^$#av7A+BfC<A#XGO+Y+oicOn<26%0HNKS*F*2@U#0zTQRg+7ps}7^rw&NTW+}GE?N$b@_YJbgcA@'
    'shih%4?-gR7&1rRk||}QEL>CO@yj|Qi((=o<#J#p7H<KA%XTlki^1JmscSe0kMx6`TWN8sWDcyZ+TI*I'
    'gc*r1rJ11HrpPYw@hy2p)^^EZ6Zz)Q&aENY#!&M@bd@P2$J=NqP9edI!2|I3X;e3-$i*G*PlYS1$yw|l'
    '{;+)^1x<Y?Mk<VaEyb4*OG#NKvrdTbi|g9kr^B&B{2<O<jwmO6P=qSYqkzW)&%FZOb>Wi;bBG-p*>jKG'
    'Hkc^oYY7bacOE7~Nr|*2T1OxiRSb}Zw2)<X()`Q|Fn;1-=sVyU_o!iVe`8o=TbOAuCCycNOy&+knBaQ4'
    'inz|P{YI_0a3VF_xwZFavCtK_Xa5Ri8&DJ?;G5k0os9y5-1kv`{E_XB=X9hwi_OHGuBF_V-Jx`pFC1@@'
    'jmutKCMV&&ErIfpTsBP6gn=<vn>X8n+o@Q-BdOe+P`(41+_*??Kq5;sL7SGxwJp|%50#Vj#2r{BurKFf'
    '5H2Dgk6HrTUoer89MSVq_w~*aDfX+SSO!ChLxltiV;X)HS*@=_(|SahW^$ku^9fdDo8D=3zYuaPq*GNU'
    'Kjl)gw(p_b0@ZbpT)<$8>>x?N<bO!chbpWwNs0klv?;Glk-+IF1ZhyxVMC#&C8n+AQ}bjUI23^tVU)?Q'
    'X5yMhBUW$cpplxv$xEEH!l3zLGOThvYrKaMwi@=c81#8E5};+N-cJEAH!bdk1AVao*<D>pfe|xWgV|oC'
    '#?H22#pNYYU|d3m!49Q;lfwQ^WWB^<Crk?Fk_*!FC0<lZM&O!L>Q}|&AaxPDBNcoN44Ow+bjfdX3mre`'
    '@U;9b0T;-$ru$OZ#-;owHskxUizR(s&UKWM&A3i6AC#O@=95ZXUz57JN>%e>P(oG9stlD^(|pX__+_zC'
    '(6w6vman3Br=fSPpe06dcB-B$v~w+QOs0jMYCCDxGzQ0hCwvYrksGz9xP4%gfX57!BChYSvNhr%_Uv~Q'
    '-6rOpS@gmS+M-NY;qFg;XhmO-Aw|LxQVoJP2iACj^+7q*Wr0%=@C;WN=a|J&n`1C7u2#M=wRP~n?6k_T'
    '`JGUfr^o`#XuL4gUkS@JSv+T1w#Sn4$T)v(jQH&<yCi0~AW>ymGD=uYN~X2!zl{_raU8x8YMPAOfaBXu'
    '+FDH#=vA7wCN#+|G^$S!$Dh6s=<;e3$yvN5k0jKl*yy+OIj14l3_eKpo8{Ox4VX41%O<-*CyCzf%5rMS'
    'Ib6lciL4ySVX;nvl)+P@tn7kw`wWXSB=GAWHkVB(2}Y9?dt=AuMujl{3ZrgFlI)VFj})1*L02is;jXMJ'
    'rDg3=QHtZ9@IjG!<b?#v7{TH((It=Wbp>-wlsta6MtvTwO@=d?u)=m~gtZ!plGHW9DwsCMp__1)6v~mV'
    '6L-d0u#am5jTD%e8O)7F*c(O2QkI8t%q&TEKcB0dEupP6Qa|I%Jheh_qBHUtcH@10au=Nlzy2QR?8pXT'
    'k#xu?_X_^YCs{(ygx$*f)kMnWysT%&L?OXd=E9uvYZdj|E0*PM+S5lysEM^!Sy;Yje=kbxVH@|t8{dUf'
    'Dp<5`y+(u<20Vj)qO{xWp4Jbc=X9hj2KU0r?{hodjVJkhEC8DOTY5jxFMXFKfsxhOtD)9j&G+`&yt&tw'
    '0R}mud;8u-cOtksQjdf8-aKTN;M#aO%%%Z-c}ehawoqy&eZLmCrqo2!T4JY4qFEhr2P)zoHGaH0rCc>g'
    'Fnk}EhHP%qFTq0q24$OY@&u-ijl<-F<NL8wU}u+<#tpZC{L&e7Gv!$;`Jmx;k~``rxub@XchOODcP%A%'
    '-BXeoUUFL!f9ZsJ$24>YZAqmTH*CDae3PB7cGv3aOYi!s$G-HgZ?Jd0Y&vBq5%qsOI}Ba~{#7Ttp<J_l'
    'kZE?6;yve0h$BJjJt!xZm8{o|j%pG69j};_E0&~&SaB!5YHO-C>eM+QQd*}tHd^I&Oo9v86FZ!P9y%qC'
    'w}>W+KIn90S5VC(p8vMr$>fu~+NpBOgMR76cz?Cimrji9G*dXEfly2gH=lhE#=Xx+A>EZel69Sar`o7V'
    'Wwdi$R8~c`y`^0?tg8zr!YF0ii$rJ?o1y<aZy<MM<uj*l?b9qe+UDGobZO}p&N}Pg2k(}SF(;+Jk$&)U'
    'tkl}`KcPlG^80x--O!`?jvjZ>(nDfTk3Y8#JrX#tZnyYV1yeI=ewnlu5LF^Cfw$1Kl2BA^hpo`|?yVwP'
    '%KV;{&jG8B2c<!?`KdX8DWBA;;v>94zO^Zq49cakv{^Gf_Bfq-&B>)J&ZGWue)SD3V@D>(Ei8_%be|}F'
    'C4ioBRZyFp#5mo;!1)#NzZ+Z;DAF{~jct$M7IjKy+xx`nMH??@pap5+#S_T$LTu|x9m^>N-6bhjEyj{u'
    '^6hVv$V)+A`8t;<VHnv+zSFew1s<aWFQT;x<y4Wtmf$v{9NDa0)+$|TTP`kQ<fq@xL%LTtoTNI54K$U?'
    'd0vgu^D+_El8q(WUADEt4?)x}S{e6EHdZE%@mrKzLRieuwR~KWY}dYLG?(+nC6nET(oUK*T0>~Np_qCt'
    'Nk0RU`Mes_=DJarsDd@4KCjWKWZhm#pL{-n{xh3-F^+(9Pl}mKGTK<X5;5ebHC!o)^&92UX1g&TtWN#j'
    '5-LyPK2Vw`DcL%zBI<l&^jJ>UXDQQP(tLae+Q~H-{!@~dGQpc6T~YOGBC0HY*1h$rvZF<o>B@^3swn%o'
    'b&`V@cyVciI`Y@C^0MNmMy;$z(nik}x`c(iZD6O903oXy+ALar@rz|vouMAD;dF_T4GkbB4Pbt*m`Ox!'
    'GpPBTX~t*sms#+tm@)N9Qqk-c_rwmW4ZCf_7NSJ)ayD}9RWxQEO5C}%)>{3IeE3j#bxD;Oxu6OOF!ls{'
    '2LFOzr^N7q<ISnfo2IiwN`)xSoVZ)(5aIo1UQ}#Oe}~OXR2fS+`{2bkwk}no#oQ$}s3R~CVd@cZr|)By'
    'S9AbVk7yjDG~N<oiVOtv9_%XwgRBLRRVfw7mQGv?WdBHMS8&!NnE^qC*^eD%vcmnSy~<6E;j&dL#W-&6'
    '6fUv1Ggk#PLlz0xcKV=1R6cY^N)P5;AG1qx0GDQp8uG+_PATX~eugEhbke=+BHlzoP_d-qXO(v$HG@fN'
    '0#mL0B{^+l??v)sdD)qdSh@208EvH^JfBL{bKCFeRgLRpOA8TjmeZ<BeJ;>M?QDN*O3sDEXXN)+KYTm)'
    'oVFeMiz&*FH~8mCOs8#?IAn&(1#bm-)5Ub6=tjTOdAog;<g|6VZb(asPC6K7goLP1c0+1ba&pB)?kzzS'
    ';Q<%1+~zu9f2IUgBdVLpSJiV4n#!tXk|DijBNsVLT!6N*z($)+>Z1Ycd#0CN$VYM6MfCzKXBuCXFRw^y'
    'NP7=X6LukYtHiDdL`hPdTMqGZ9$tW{AC()qiXhYenoCL-xtcC1OJ)yBsJ6;ZwJQ{r-0aPqvRkXPB&Q90'
    'RZLgOTa-<m=AT#Ds=0hNnPpV(18476iA&PqyHVlNHF%|tx{1=Ir|7lqCQBUez%FUXENQ?h*~BQh!MND|'
    'ka49=QrjPFvH@b_EsL9Ifw;>ai1(pkvCJ-r_1hqB3-?Q_;yaAw+<B{FnT_@e*GZdfxVNKbZyDm-QhU7>'
    '@U)_(*7kRP^G*6n`(0|A$`)R`-MMs;(MbEUyT^Hkr#dI=_o2(!lIGn}Bh#8uq%RGt@5)$PZL7)a54WPR'
    'm2~g!9(BR~(xtk=h|uSdxwM-mi`Q?_Rc<|o?Ri-4C7?#w&H<!s;vk<#m&E7~Q0^MqXiRm->AR+Gk91Sl'
    '&7nbTmyT@WYOX$_eSI+QIgVk&JH4^yI8+;&rZ%?W7k#*iyysFr2efC}gQ3+QjeAy~S{5-VwMVYw+U8(H'
    '#+E)97_MoJO?L#K2hO194Ez1ws6XzT&X^EqBcPXy;9UgJ-ju@vY*+GTqu81Favpw&u+o1;D)QFaG6!=i'
    'dLyKxw_|cKQNAy~{fb;9bJ`kcZZS*apN1c#tVdAxIj6?Sa`S>^%x(>|SaF^ySQ$&e`etXPWju!Wo`()y'
    'y^yWp0tSksOJ2$m=19TMm*j%3T~L>$I!?A<$w?3|?`|r1^7D|fwg3jUuG*k($wWB~$&^Dng1;rwSUUaZ'
    '3|zK1x3XzVM(u8;&0Pqa=48!Xh#IMqrpTShgVAl|OpR5%$?gORFmENTVrSw~zO=j>VYv%gxm!`WT2kKX'
    'yrytqb6rDEJbd_2dBL(pUGF2-a1p`5NVz2MsS<>WlgJ|l90qcL!O0-R8Z7U@Vc1?{P!{No7A&X2UHGDb'
    'X{6Rz3~#KZ(2p?<BJgCET7%UH-DDlLrX*MpAF1M$;!R|1ef1g$bzp)Yt|`}Y>_d!Be4j!BCaWULM;+zU'
    '^`D!44OnDfQI1}outu{g&|7wLusz`G8umzyaN-@YSOXl^D1+TAg?|$bUe|Bl+L##Gu@t$Nc5_2A<o3;-'
    'S7zFKt`djuXn^rmcHjOh&YtQ85mD*vI5b(z){-y9!XhAxm{pOlMZ`<J$uaiK=PzN*y7Q|0ypVF+nC%jj'
    'Vx`?)+i<~GCUMS~U;vTxNCiO-9C0R2L)vVKDoTk?P4E2<2wggzH$dk1<$SY5<D2VS2_m~n-_}Pcm{}*m'
    'Z#i9q2}L7jM6tV%c%nc81*l>+n}d=_Q&MDQxY&#N9Bj3;ZLi9C4SiGwk@$&{7i>^B#idE>WII_=6QJO('
    'Vv-6jG=1aenwnAS?|5`!Yhpx+G*N!8ckUS<Hm_?MR5dlIr=C%j$6}KFaxN0LCd#W~8Vr`0U|p$M2IbaT'
    '^^<Zz13G6%rdX<jLsN5a{^A$On+!63iT?s0Yz=lf13;#^Q_9Q8FXoqrie3xWbxnh!#wKsyYw!;CSn3w<'
    'aEI%}NVb2{o6f>{th}%yI)7iQ!+f1tV2lStAP>U8zshc<WaU0US}9>b(`tyKZT;4Pm|VVw%IdGApz1Ax'
    'muSH{MGE0M=pn1t(q%U=Ft5^0Zm+<KF6Q8P!#9Jgn#qM&L7ec5bv10VuLTt#g1`Qrc)<~3Bqe_@AiiSz'
    'B#P=s@5|-l>T1m-vKB0+3aj@qQI3DNATi-}E^Vv;;yGA}+)vsC@ET9s+dy^eiWMdv#q)&?Y{;wXeMh28'
    'KJ)svgaCl4JDgUqmdgtZ4gKs6rc^LF6(V(9JGIdH?G34eqrZ#TK-ts8_^ZQ}^}#IjYN2={ikEVrSz2j;'
    'gr=0kC881&=o|=@ekdh_TF$gHS`zt_rTY~JMS`e5cP~214=869%S4r}X8E%}lbDMTl_FM9kn{Cd2-=zE'
    'Ti%CUATzlvfAn&REjc2y3?;KsWk8U#iDG{3h{m0b>alLmfN$P5GvgUIGkA5eLq$dNLe8ZLR&a_J%6r);'
    'kUVuik~eG>SxX$Amt&K2p(sCY-d7ccG$rDM7si%?jIVRv+Q~%_q83YFeW2tW1DI(4b{+3x$!utF<~V6='
    'b}(Tzo&NHN&;#TAIr>w-dL)H|nNd{#tk$785QbJ^nvX=?^Lo8R>rDv#&SU08g$%oZQ{QuG>`kc>gNGS;'
    'jHZ)%oT2a3xYH+Ud16my+h4Gpg`<bxJUmkCui-SQ<f*))bQa~Rg+^pbA24B+`RO%op@ZQtpD$*yILC;<'
    'j=Ey!Qd6qRixid0YF1g{T`2*KRK#XQ=h1!X$hv4J3REyHQLe}?<-&ZJT$Eyv{_qD(yl~Z0CDyMFB_S&X'
    'AoK_fEPj)9qjXu19F&9w|2w%{xAnTXPT|AInfuaid@9}v###V*)1-!7#%vi`hs&bkcVTY#;s!sXG!djr'
    'e6s_AV~%1;FqR4z7vDH2(ERqh#s|1JXMU_A{CRSIEKJ$l!G){?>MVR#x-lxHjWrLXu<-<C941S`gOEze'
    'yM1|kP~&{;JKaUp_|HNxD3Vw{b-XxYMae<MgYr)hkf-A=&q>&N;Q@_5g!6ZD!sTUJT+uPOia56gDTaL{'
    'kFYsEcR3@8nRdEWrO<1&AWVA@N~r3S<CX-?!jTp8msPubsd#xIl#>14xi{jls=w%YQX_4mq+Ld9p5C`U'
    'HK4SLO}0e`<&d)s%0vFnoy)8v#b;9M2rH_kg%+oaC{Fq_B$;z4!;+KCI?-e0!=(q766|jpo|Y)J?DdjL'
    'zQhqg)LaO@s8Z#Mh}9$}gx!5(-n9%Xi}CFH&um}gwGJQ{4DIvWssgr34G1!v)zqyF*UJ$odGwz)C*lrJ'
    'leEu^Y{{s|x{Do6>c>`-|F(d4vy~zl;3u@1g-RpI+^V-Ow*}iml)iOKNn%|k4X21i`|VxiVg=dmYVT1J'
    'h4ArNH>X?|FexeFM>hAzuoYDV*zxHD*T*`kO5}qp#`8!q(`kXI+Ztt<k$X80gK!Zk=%Go-EYG52DQXVV'
    'I8jnvTq^EiT+xo=4LgQGP21%sGJN;nN^6ziP?vSrL=cZuEMgm7CcRhF<#uF6*H*GjM%XnPR<I>3m0dpM'
    'h42*VH7ObTLYYkz(khYBZpuX7xFwwMxQ8XUVC(X)Irix$F~nvnWG^q0o2pASDI+GBg2dB8+x|VRdC!;3'
    '=j2N9*r`)?<u^TTQY9~{6hjvcCq<BURyVTFN0T$<q}(Q;Mo<}ZrP#e0nM?#*njas}<FMje#54~$aqm6U'
    '4H0ZMJy5*3Mh$8aLk#E##pPAzRJo}7^o7mqa|E}jWpRY8n$D6=g(M6i4iLqzN%JzKj3?8zDB3pX8JQ-R'
    'ROEScnf;#`)6$8)aA=!92bNQNKJ`eGimjh2&qnVsmGe5Q8F@6DWhEn@W{p+Xm5uE6dgf>}9BG=~Gd1e='
    '#sfps2fabh7->Vzu=^I(ETcCZQjNF+i;hORLx!V%zpopkp}yfAs-?=2&PeO`$75^QH(cA%HItf})f*YE'
    ')zh55Wse8e*d4jXaA3gy1Ir~~qEp9&8EHeSZ*B^AW%0=JtE%tbwwKFTprpEcRob^mbg;6q*G(AI@hvKq'
    'faKxM__fLWf-oH?s?&d|8j{!x)?o#2guY<-iIR)T4M4*e@3Pb0pOV=VSQk6-iPboC$QA30SO+Grdy);?'
    '=Hp7=^871l>5{c!sRPM0*R&g}MA>e4X&Qq0{GpMJ;zR$r?p1=gW)@dpd=}@6@oqoFYul;#bi*(P{{wp%'
    'fo#8+hl{{Di?4jz1`8NWZHLUS8dzNe)PM_q>QUdx%UJNw=8PcsyGpI&7zXy|D6*g6{mE?LHN=ulLsai)'
    '4>dt7WxmEM%qh5<OpQsf*`RGcD(C0!ZHKKcDbtJvv0DQ|uKlnx^PzPcEm2>WH>Ap2yU+|fR^qqX87ca^'
    'IrV)H_eX}}-l^%`fRS)-Y=mkPLBu-lC(?M2;CqQT=_597S=|T2YR7ifI<xBfwsuuHG{XuAl!VYkX}8bf'
    'IlJYP{AA_0AN)$eT!<Q1=~DEustD^Z&PoL$Ou3rn5eg$Sv;nRv%IXV5)rZ3_{&C8!sNdf$ps)_C3iNj?'
    'QP-8^k+Ax(oVb)jWgjF1)<8QAeOh`u3g_{ws~S!07+fG<7*Cfq``dF&t=WsL9zk$l(+C_9#LybjlNKvH'
    'XGMSjd1rWj*+zo&i2nl~W>3WZhfaO}Zueqn7gDG(A+$8`Gk#>!(8yA!%yK0k=aAlR%ihvvCG!pi^N!?l'
    'CfF+JDXCY`tt5&%%S#7dPZa!=QPL83s(GX+o?3e6u+Hpvt#)p!b!wZx4Azu<^rnmH3TSndsPH)ifR}U6'
    'rtrrM+yTB@?VoF4$19H>0l{@->FdNlYG6I-i8s0<{M4I)N+qG#8cAzePNK{HI4FFYwIHqow>VgG@0i_|'
    'I^=9ne_axeGqBu<6*|C^Q8=Z_4<7v>%i4QR-g_4;iw#J}e#eHD5V~)S#dgPGyI`>0@Yfx&SHs*@xvIpD'
    '$(EM9b5Jw-T?D~UQ+(qfsh?0VZ0cdKG+1qP)sO#47e#9&krZ{Ge~E}%#mV1(SM<<f7pCi-1hZgeGH|`T'
    'zlI{!%O{}3_xC$0*vf6NCm*Rn7|@0?7oLXmV`5*nGueaTQZ^s(dn_P<Y0VALRBZRnSHlfw;)7mL!CY-5'
    '*`$FX>x_4c;CM>?okkMPz9jvv9B#Kse|MIGCpitIdHF3}e6N&)O-tar62MK$-<4~6_)z&Zr88{(LqE=Z'
    '&-P*r{IFvDq<-Q9-tw7x5#B0Q+<7=<H+}F{j)YrR@Y-LqtQXj30KqLH;EPDvm#~(Hj8Px*x*%9l5Zmfq'
    ';LTYt5|x@2&IXNa7H9@>Cy4cjVfTQ`T-U9$X<uce&B{j*FNoS7F6kV+wNDD8MAp6|o4|EbT#m2yD%AzD'
    '_m{Qv4KkkHSAO>6kL_$#o&8Ryu|?sl$l*D_&49iB3=$%047YQ;?IyD=ai;HGp3Td7cmX0TLiaO|9dVIp'
    'f1~`6WR=-dP30+7Si<)+b7^Dax-qHJF#Du??uvCaso%<>pym`zV%}#9Ww7^omED>KacLQy<-|<WY*x+e'
    'iYPeJJ{#S&BwR#fvPRFjENY9UQ`)QbzDp}s7vaxONQq_LbF1geZH8M%MRIqFu|NBF9@dYzLTe^kcb`}v'
    '8v}b}TDqy}#?ZD#u4xbYgwT;rhdr(DxEB1dbl1?wW`9ggOY3WzZsGM_bJ*YHKJn6BVuP5@U}#yEru7_G'
    '8<>Oscx;b#9iZ9<u?N)9tnru{#2w;9+|k&gy^%@Wfi}{I#wIW;?-AGN4VU$p5)F7tNS@R^x5(u-Wfk)g'
    '$nnP+1<@JURFuuHS%r=rHx}AX%&8sD9ZX%zE$WoL`IZ$umkyC)`IL#ms;E4YKDwWrrb+0KBKL4Al^AFC'
    'JoJ58qv7ir`Tf-o?3k-feD5NdvP!0^pR`(tX2fRMSo)xI`y=@*gu3l)n`fcsIVhzF-+ND=&?xo-Q4Lw7'
    'njHmfB}ukfEjYVm)JFNVSvFlcI&9H#faS;z^Mv*+d3*b6Wb);LRIyM`D%|RL{HCMvTD53{_;o<ugHMh1'
    'Qh8Kn4*RIml$+H{zNgHi*soE7?<$Jv^khmd=tSA)RhiWf#D524IyAE9-mI3#D}0M}v;WQu;yRJl)mI)1'
    '&cU%ykpkNGrRO_yT4PB`47`CUZ#|`ze$Wcc*LH?lEBxnAa*@IgHWt$<DGReR{$^X~1<89+RGp8pMpO;E'
    'LEcX9Ry;H<9hw&oJC+UgMT2C?uzSI<>JTKgNw5>vix~|{U2V3e(Mu8)%+Zp4DsF^#BpDTD*|gMqX-gOx'
    'dWs`TpL7zVDQ`bcpb0_I1mYR;Q-rZTHu-*gJ0U1pon}gnX5<TwYx%O%Vl*V~*IS@|>6|(*=i$@~>a^9k'
    'd)bFut>SfY$?{L$9@Mq6?#9Tvjg2ME3zJl)_FA10hgBezU}IjZL7JES%8P-2R?(s?(_F<eqixTbq`mGL'
    'AH-J}kjF4YTUxF7Tl3rgJ?dj2Q1MAdIbFsqqGcuvBPAtYWkzT5g~jZ1@G#;dc3EH;`;DeRSyBD#8XbUH'
    'g=>B<BUu*zdAB8Hn>g2aLcxspOQBgw?w=fOAVDteR4lEKN~QQ@Wy8zu&kkF4C0udVVQ@5?QG)F^a`q>C'
    'OD2#fUPPARILW&*K|N-fs_oEid?(Jk%6W|@D6Q2F0B>)8;<6d@1vxwRF6D4^1Dm?i8&<yT$By<R6Ro+4'
    'wmtBdC(6$=ti@!0LE{<>#s`qOrG>D~6xBbC+8j(*+3kk%wio3OCA&ez(cALeo$LEVkGr$dTlHrx)kfc)'
    'iC*Xt76oJ$U50qyJ!2=<HxJL`%PO`u$T}Ua3Y2my$3hCkd{7Tt&@lXnw8=>_pCpfR`(UNmk4d^SWoahC'
    'qE?!4mufQ9_D^p8Aofjuh1Z}$ym!U3_;_O{;v=r%y~S+idq79H`ATHZDGgNRB<ZQVC0rN=(;OA%+>v>V'
    '-Mvu0!4yFDg~8T0v0BT%Vrnf<l;htmNQ|d)UFACxUE*)jl6o-4{KEPzATSf!wTF)Ea7KSkuaeqLk7|!d'
    'XQ6#LQC^<}@xZJ<oEJS#yG7TlqQ<jjGN+%FAiFVNN`|^&>kwf#*0`w<h?AhrIC;R(W%_8#l4roiNbBSR'
    'iG?41%-@R^ZS*4nhIswz>4TAiH&rpQhHfpLr)2&P?MsKw{O}5oWnpt1Y>^!<;CJf^*jlZ<o`miJXURT1'
    'QrVkow$9p67%vn+uy<;Yn`ep~LFL}PLz4~D!@TH-cWC^5TITLkhI3J*`xn0`F61s0+u9&tnlM*W28fYg'
    'G0$ltOEYAWrFP%n!gwK9WmO999ykI>U2A6eNE(o=7bvqfQ5{I}3i2@Cd*FxpROYzt2!jYX_)=<u1RB9{'
    'V?oB8oFDDpro?}y3tSkM4@jGk7o4dz`h4q-@~tX@lfcAY@SgY{Udxfh!8wO>lb~*Gn2aB>&7goQ!J=V3'
    '7p07MEs@Tuyi!&@R>^!yiL}*Kc4D4ZOS<H?B4}x`zu5+Fe<!k)(dG__Q|jI)XD^>}VjCkL2hx(jxPX>A'
    '>-?e7CmCMA%SCjFqod)U^VpS3uyG?^@#MWnKO7(rgK4FB;CgQfl_hpjOf*dczTg3X;TZ6?-`^1XU42iW'
    'q=OF{(VO+Ql<j0WZE~eZkQRzZ$;Q+rx8J2<8ia>9t2j&@fg<cW@})wUB_iyRn)gc(y0pk;UP^vmVy&D#'
    'xf{A#PM@sV(z(>pnfDGaaq?ja=+-M*mBL(JY4LAyh_xk5PF|9lQs;V!b4C=_d|S9y?8lvpyyVF7yySBf'
    '?V=h6R|SnXEd&{1X5vr$CQ}0PAyu}81%W3^(B%Q#DDSoedEdn3+MI@6QK1A^(-ms!tIgDu@`pccyRxrJ'
    '1pTSt=ib>FSUv<(+~UIYKFO1;>{vN*k=Y+>LQ4m7t`Xd|)!I-%wlXWTR>FA2?P>5%Kb&2XIhB*A+i;PF'
    'W-Cm5HYFf7y6A0a9hvu2i?aK97<)D*-MPLOY~RM9l^*82;3FM>B-5EsC0=k9_0)JS!l%+QPNHZ*+k%AH'
    'k8X{n#B(4WBzI|-4A`-nDAdKz#xW^G_O;^`cT*(a_TH>I!KkzK1~f2dd_5x;^_TO-BJ!R(yd;OLiUivZ'
    'vTudqI~BXcR#aPTq(|&pgb7;xeHc)7T#G1Dr<4S+!(avcBYc1BJua7;MkvXWV@&2ZI;s`=5-<8x^5ZAT'
    'B_gn^*l*Yk(w(kFY!#Y;*;er%)H#alE)&NE=0>suZpXhGTM5dr({K^fvv(ByXjUhHFC<B&>of>hU<|F3'
    'sClrGQFvYNvQLvn<=s>i+CecSkwJ&f(68y0oOArdgWzLI&%9_VQz983#5p+7VE#=MmQ8n0(l6!-It5-q'
    'CaNr%PT)f=WY*OS0Cn?7NPq1}T#db$&%yRO6(VY>y4WLePgYRqw(B`OOz@^WN{rSCJN=Npl;b?JmS$g='
    '#+G2Y<IvFL3$0OC&VBpnsF0J_KZOct%{#?A@rk9o#Opoc!vY^|e;?~+zgmueyoq~!SQK-TFHXtymhZ}0'
    'ZZ%V;ra@O(hNrxHN4d72{Ha#4v1Z-m=Dg%xJIQzABRAk8-{`2GF-}A``IOFlawXhk3ASrjk>vK?jkCR@'
    'f>PJA3$GRmoJHtzbEd$Kc2Yu%(eD;GC<z>ufFA##E@rH{ecr|ArB*(h`k)+5^$K6fErYwZGUQ8i8|<q)'
    '3hZW$LWD2z>3*PW)6$?^E_~11?@22i{JRC7^@jmo--3PcK>#*eLb$Mu#%c)ft{|`IhuB0(UZvRJi_IYI'
    '()GF4NfQ@&cTy*9DSEqg`}3CMl55c=rE%MfUh?!0jGX*Doh?qibWFPSyqEfk7wQBew5kIJAi?Y1mzR@7'
    '8uz)pT#`z(tMYOyia@BYH;-c81T>B?Lbol<G`6c;FPE&lx25MK76fnBZrz31y5st-GK^N4rP=R|$-2g3'
    'Ed<#m2k9EFXfMZX-Idk41Ecls%O%$~S$A!*-em#J+D6G5bM@DBm6<BL{$;MTU=FaTCAd5RS%7b8=5Boh'
    'vvf+L+|ugZI$kKjSiUP;`JNYf+rUshD4sHJyNh+3p5Y5=7)^s*VHX*7Xrz^d!}+}@{(?5_59HkeDHG?n'
    '0yETRsRXib)D=jN;i}}%NFujnE%Hj$eTIl$b_mPZm4~J~yh>AQaGN`852v#bn{KRablZ2dA$1*V*c;h~'
    'rn>`oYz_LFVd;jh_j;OR4SLRCH0)8wv}oVy^{7rQt#9gj-!l8XTe!JP4R19=AB}9{8n*42BZttQ=?;d&'
    '{>T_P1|1rPO-*-X^v3RZZ1jmca>hf$8SCbV4u^(o-3E4L<J(&Ol!ecbT|_D+)Yfi&TOg9mf~m+ulLJET'
    'g`P_N6*26H+A}$Pwc|OMP!pvtEOFk<M(ZjwpMa&41RT{_=tb(3%-TQxh`$GMrz3B5|40~tw+;L(2Y_l5'
    '<ql}Fd6G;iQdEXGqZgRj6R~vHntf!Or}|qFeUWHu0&bq>t4RKO8=7BrT3@?c<jN4jV-mb45f~cSijRJb'
    'yGrE!p4KRfzCPf>Dy@+ixBeykXm^?c12|OLUf|G=AoAEAqrY8Su`wFuRH@QnF{N|x!|EMW+!&r>ZS%s&'
    'W4FQ&mB-({#Pzg4*4GRSG3rO<FW8o=A3P_%>?*+Z{DZ6HgG=gNT*jT|mgu<(+bcAGH6TSK5Oo^9r|meD'
    'u}qG<P8Kd>0Epu}^8yYd_nl^zd0k%#HX#poCk}Qa4OaJS<GS)OD~fxlOv%T#R$H+Y<N>d@`#{l~TLk0F'
    'WC<lB05w|O^?XvMUeL~?s+(Zy=US(u{8G_@@*X{skGDop)`Su$&V4qguJ^H>?Mp|pTG&D>BvQR5;2kN2'
    'JJAWdRta)4IoH{U*W#QsT3DBqIC$%$1K0{eR$Sb9;$3*LEL%&0hLorcce8Ri3zy)>)*b*mOz_lg(PRQE'
    'Q=*ef9pRO!yaNT6rNqKYN)Xm%H$Sx5p-@)|X#63Zzr#KgALd?6G2Te{sf${BY1OrGsxsCa@cD132Kbpo'
    '7rs6Y-h1<q-55guII?L#Ujh}-PVs(r`hFu|3&(M%)LGc{`;ZIcWEM4{@{76Iz;c$cd|7+WXf7Y<;8e)I'
    'DM>C>fR$7!{pQuNj1auq%zk+!1<=xUbT+o+2$Y020F~nkziCpr;p$`lsbq)?76g2A62x!siK5GIW2ptf'
    '5>7;2__`cjyhgv`PLZUgH6I`qnH4~zVV(L2>qwLxnBz96;*GY8mu&@Pd0esCO;kg+w*+?1k^ceBoFJS}'
    '0s8MLvvuqcFGB-ea*{ZxOLuenp2FzCg+dhW4~kY?a~j#ir;*~ts??R;T&bpZWMk=sA*C5!g8C8rcTyjB'
    'jQ&c{<T{li)hStke3u*mh;_`+AVL(W_$QJ?GXa2n?sHC@s?j@dwqHN0RY>^+nec(k9hC;oev<)>=qj);'
    '!2|?0Z8sNH;OQ1(yLfwwsGWv7YXTLLGbslxD}&?4Ma{F_Z+pQc3*Dv@stK5{=O8inB%U-b1w~YMPNuXy'
    '^@8tMfT{M}O|!E;yKjks<WpZ`(R%h~y&;7xc?K>zsz`_THT*TbYA*@3L~}Yy?FjG^=E(*4?)#uomiGkv'
    'QSNsni!~hji#)rZ@=R##*t6f!oR!K5feE;}>speJVu8(30~gbY^b{U#JM|T7Lgkq1rk-HJxjqT_@k-Pj'
    '1z!JI>H#iu<SPQ{BNi@xu=Lq%`^87K<v<+9#Gf>EuvypbFKjBWACz4t%5Q3dkNwVPu#g{cEBQi}w$nv_'
    'wmwIwGdj0{2k;cr_V89i8@bNLaOg7{T*Q}ct<(7&khPALvt5_I4z@cR7*4hKNjQ^_mW?Cv5gJa?!RF1q'
    'CBW&2`}Ly$OM|mc=ll1S^mb50rE2=}bcei=)G#<=?eZ$R{1psfxiFt3UHS@O#pR?1;pT4hB^G0Lmv1Lv'
    '^XGA^VBh%}b@kNeg=4&I^0nQ%hVY)dG0M-jRL_y^B5?O@=@uLJ6Pk3l@~KhGLy(agm8?Pd98IS}r5QrM'
    '!UUm4R0XT(ffx742jazb@$(8ON{xI<XYGIlA=eX8ZS`3?RC|eDp9hZR9NdBD8Jwo_n37^6jfDlSn~B(G'
    '(g?4D=cUL&vX*-zNsIF0D@I6O^q2%T^?mAe6D?RjNS5js7V+aPWxEXp56WSyOniKv@vCG#&U@S#mPBat'
    'Bw86kt0nA|mUmB$O?*9ks5}pq(03l7QdMl9l3+2z7QO8Exk3~l)Wp30aU#>4>V3473l8hCPg$yyed+lQ'
    'Y~n;=+e*AZ-Zt*c!)C>q_dEA6^Mn;hC>n_J>;%E>iy3Qym~RBz<z0g5B;Ufh5y4zgV<i(?+Cq~9^d$?m'
    'wt)WXMh&nOp_e2g_z|Wga+8x6EH14-4(GIVYyEpnO<!|gUDsWw*SC9`NwwZ^U~9wS*f8m6sG0i68V((6'
    '><(?4^z318G#u%!Hl{ttB&P0~<B@4@mWsV}RejKR`_$E`=4$#txBH`E-yP8Lz!;7-Y7F2XckEC@*Bmmm'
    'tzq99lA&SuY=`u$5gBZFRlWL_dh#i64~%y)U`LPUb8^*AvwfW8dPeS^NvBgM->1dfWV7p}Rq&j7ID3i}'
    'J&GXfkVkz2+bY?9InRElnBG02YvZ|=wO=Q#pJntPDHcW`K{{iuy{|Z4#PW_K`x115PY)DuUz4;n;zS@>'
    'S!5=vu}7F@52`-`>urwaKpnHIHCtG|XDj7v`k6~RQI3DNAaT8RRH=cGKqE2yVClfi4)a8L&DuyQHA3kv'
    '-O$c8jr}iw(o^!$n=YnL@u(E}#4shnkeODTAD5-*=I<A>(gmIR8;UQMGk`~x+5OHusE!O6+yUoMFzh5;'
    'N{%al`{wO|4F9sQCO6q$yqw8Eca<}gkA>~;$O0F|bcR8Ew#J7E^j|6*wDKRN^TB(0kKq4F9rlniZGIIY'
    'TKKUbSGE%(vI)OyGJt#lUyX_(|5Bhw3f;0GnwTjc_CW&XknhGL@xF*Bz-H9YtT3RgS#zALcoq{lZCe_b'
    'NnxFoC;2RYy0!sJC3wK@`ia{}WD#G6bG&n>yz-`W9w|O}lXwDv3G!#?X}mtEL1PZ<JCE7$SbdUR{Zs2('
    'I7tS#Mg1_ih=3;)5-9W|_`>44$HT}DXSAE8_-_wVl%(Uu`$*uVuDtKL6szquXYKH7R`P5d21B$9m1ski'
    '%muy!Cr>8I3+uPkj<bl7WI#!yfl0X&yLkVRWO#VRl3Y;M!IS5B$c6xf?Rpm&_~3mUrSFXV8>1<l+@0IJ'
    'jhDX<yFHM~o3!243+l*I$O$=v{wUM4SRDAb2`Sd{5K8?sWGx^gTbNxk_#>4`NHzOVo&l54u&Bez8c;q?'
    '-#y>~gqj71Gs%1}%#3TfGWv0n4lG$pyI{B`A@N)v<`*?D7Oousf(Cf(&qC68!}h+Q8S@bo7DF$fSg|px'
    '&T`IJeZ(s!WVVNx<;}^OxIiv=&fqJvnn`>S;ygg%33E*WW4=dnH&2E)h2|Va-?39=#7xdbz{63F;x2qY'
    '332dp6nJ`S`wJBPH8v#(g9pO;wTbV8&8s$rugdC-wSg^Pre^#rbzpv~B%x?PMGy2`x<v!yXCg<&t^TEu'
    '6&Mz>c$u-U$Vr|kPr`*XF`tV~rQDi}QHijWCda!Lqw)E-OC*ma!V2@~C=YA!t^iUT@xCY(wx29MT@kbf'
    'w5t^{&+P%1uqta2(*;Ug5U}jTym+MjqIjf@4obI{`IbMi#?d5M?Vig`Og3%hD^WN>`NJRh+d{U%`{Flg'
    'u0n<EIZ$Q=)m-N&tjt?=FW)XTC}4%%q6P|3^LxW;bpdKgqgE92<&b1z2=)@o!U2kY@6C9%zdE<7c;VG3'
    'cZvy<7WqFBD@EtcF&KwGRSij&{ie&2-1sV+bjboAB?l*BhFML^8mpbiiN8x(d`?0L0dY_e4~cZBeRf?k'
    'cqEmY$_u*!gkStZsVF{?2147N`{V2~6_cwtljZol;5j}IewBE_k7OD~Ny?Pi{lf%qca_PsJ>b;Xs+(g}'
    'Hn#*`64jipAn$Q+4=fv{bFYXcNe?^EifcVyN)XG4XM4bCjmRN6CIc$VDly8dT?I@IlD~Gm$OhiPILIkG'
    'C95_FlbiQS{R``@bvxG#+n0(Wq;QiR=?c;LRh_70Ds+q9mNWs-fP-75M?PhSYZ}HnC`UAEph+|olZ~Bp'
    '(qb2urz|N6Kuml!d*2tqS!CesN&-I?XE7-ZtToEfcf!So4REovRGuVBFPF=cP-t3dT~aP%hPwpluMU-}'
    'K#f+u7;{Hy4#_XeoGTU}N#3P<a9A?@?x(q2(!{*R*E&OJd#GR7wqhX}P24?2h=6yIByvRisUb__pwcS1'
    'XCbZH30mR;1{lKOVs6vup(yQv*0K80j#%zTRDA_w<o5f9(<eQ*XOhvt*2knb)NE7Ni8dMx#*S;5rl}FV'
    '@Aj;o)*IT+px5t@`<Cgt<8gn}1pTE;7-LPhNS_Q1Vi`koWa~rS9Q7R69S+T&J?N311~Vhp7(||-TZY~1'
    '4abC<y5<^WG#+gXc<nWe+IL`Da>tP|O8qgeyS0bde^2ME-|$4)*HvwQtG)?UErjZ=t|fIC34_!`H5+3^'
    '6|hOoJA-18`=I|saV3`EhdVkY!GievT`A-HLRuk&NY<=z-hsTqU^p&DUk6?+b67U8z$&0Qi10qKBL}l$'
    'e3lA|<8$g@cV8TS^JQNa7+G8?Y2Ew3zkKi=kx5N|76kCefBE14>A(E<fBftJ{r~;j|L%|f=3o5XU;o?x'
    '@Hc;Z?`Yu9Su*o#v0o(f7sjlT%$z#D$mE~W*8lx~@}K|dzy5bzGJg@pyEKxqWcn9L{DmD0?09w=e#muN'
    '`C=sh<S5|p{`&v;<3Ig(fBfJ6*`NNa|MQE5ymPUfmOcI=n!hk+Q8Z_9i{w6VN-SSQ^iL{|QH)@4<N5FY'
    '_Fw+-Z~o^mvU-=YS`=~rBC5YIXhl2&PkLkQ$owVZ{8J@_KmD8k@sI!Nf8hf9Pygy)|LI@<4_~6scPFp2'
    '-WOja_7_GiO6<H@ozTe_Vf_<}d}P)%#y|e)fAK{+?@&7P=0RU1^B1lxaOLA97@f1CRYjZ_ez>H8auqJ>'
    'RF`hqmth!D^^3IssRdE~^e_JXfB2vNhKIWIM*08ufB&;T{_}tP_y6rb|I>f-fBpSG`A`4!pZ%{~Df~bG'
    '<UjtR5msn~x<k~b_KK9t>$lg}doPbpkDtFfKYQ`|^zrfe>5Jc-DTm6Z*3oSC@LNB$@FD@3+n3mgb6v4^'
    'd#JgT_J&k5$iOnGLFu4xYPx2QdxoVC`|zpmXfC0SruTGHcd2cSY|EwtduUU8gZ$5>Bw>vZ*Xf(Rv1vLz'
    ';*9mNL(HB{Oq1%`kl3~Zu*i^@hHVT+eZwG*W7~b#aERrM$R^pztMh}u=JgEo)mmK7kJ%0EJmUUpLFZRB'
    'vg}s@v*DMEaPDEzfj3XQ$PQtHuO9PvuXw50rhr~OC7#dj`_!v=vkFX7^fr%2evvbJBpsL+Mc7@oZVkj$'
    '!}}pC@7EZv`2BB2Ws_yXlfRyb`qT!s^J_0~iU9GQ2H;(WAEKv>v!ce3c*)Bx0w-}YXo!6T804PCoHn+a'
    '3;g9!;k)uZnK4TEmejiJbCX2)c84%$b2=k)>YQQGM_!AsCf()B{E1CEgMSJuV%KIwUCug-sy9<yzZE(_'
    's!=$l3aaHA24-p~o!Rry_hpTSuODFF?00SO0xyCoyBnwaNu|?hMr`<HqUfWJEO_|x+%k)8-B_o^n{7wQ'
    '?yF+p*8zDCW8>wi{mw0V=59TYYpLi-OPIcJUEd4n@kfIGqeMJ~eBjRxIo~mQl}U~GLhL;CsPE)a#A-!d'
    'hCb}Xepjh=PrdbXZgi^e=+y@-6|CZLC&6qHA1z{#STiq912JutwMyy8T_V2JXkksgn764{`AR!#7@V=U'
    'fx57@V+|tXeM<Sbc#B!NmcNE=$6MV|F57XjJNuGR|IH$fd7sask%XP90ZBe?$D{_@`F`fs!HF#bs*SFq'
    'm`+co<brNby!$9A)Sik}`+tvx!hF@CHpr+5<cD(W22aHcfje^0?!rIYjeEA*JHv`@)Da%p)>W@tMfa{S'
    'sQmr#q92Ma)#U?_;YT*?M()_F+l5oN8=r1BF5Mk?SvNUZqQeGuDX3SOdB=`cOUgWxRwl{nr4+F*)XtIL'
    'V5HdgD)W)0jE6mTaDqsYHT!xL#+B79q+YnaqQEy<;s6O7ujaamRBe6Ii=&(D-<I%%yT|(n)t)tfl_((f'
    'D39{*cMBU@Z}$0q8=ZSY7igxWoh_CF)#9Vil~$C}ey-eSNko<3<4IMcm9FwT9^&RU{9V$4)DWE12;7bX'
    'a1F-a?n(HqbuAM&vV(7T8GDn6nYxj;y9m6sz5%xgIH-L=V~nsAqj1VK_GsOHaCr9DBA(Z1K<|#?c@o2U'
    'lB0RM3Fh5FEU)2E-UgAp>)V9#s*ADlR}L3qQByj{K1;Fch%lQPdod`8t$P`?3Mkn}%|qQeENj0bJMyfu'
    'w!`hI7ko#(i_01(0jAkmO})z~g3snxG6T|};J&Ib++dqh&;A5MWbJp@a&qgCaYn&G7-wMQ?hGrq2@6W1'
    'Zrg{@Uy3`ZXxQc1PmGMJniBx|_#4lOFSo}G_z5n$3Rj&?gjfo{5wu}HQ{3wno6kP$)H!tI>StMxG_@M;'
    '@39)JJU-2T%Euna|HZ`xjacHetkJL48F84oB7xr}%n4g-KPT_K3ueW<LSdb!O)kAV^^Sjbt1=qV7>z27'
    '9qWrbQ5TJ9ixqq;b(1Bio}Fo)-7B7zC~H>jG@*6YEhP%b44i>@`vca}Nv)cU*!F@+F@)KXOu+a`RAmBH'
    '6>oIY6J$JFjJEfZvvG67$@R*vQ!C)Bgdu<N3qfRutiJd5<RnGWFY7ufBT29rTJmPJvArP8$pnD@6?ekh'
    '0rH0=L+pN-Uoi->wwDFkS<JtaiZ*fd+m>S8s$uY$H9>BN?xYkaLy+fPC5f7O0W#XwIbvBN{G&7w_tjxK'
    '`X?CwJ@Gx(1XNNE87%IJ7Xh&VEdl^cyjJs2w(cg-%Afd`hAgFm)Llo-$G=AV;+utsLDgc8M<(7RCo7{g'
    '7UuzAJ04GG@f90ZlD8m@_gix1vIIF=VEm*niaf5*^TkoZ6#2v}9?X<6e4g!=Qo9ah8B8{|m-1gy9_t6*'
    'Tf>%Hf|SP15>7UE#>+RdvNT1$!x(F3kk~%_Dl(Y%?~mz#uczVsn1J6Rkls~L8vOX9iml&J7G%0uUSKOd'
    '+9;iprMme*DY#Z!NA2@2St;TpAeBx#_H943-|Zr*50rDSOh`$(a(59a+1w>rIq!zIR<l-iWSo$CM+#Tn'
    '2~#!CQw^AAQdHL6JBUrV1FWH25)L|7SdoeCm2kzaaMos5x{tx;siITILrVn<MS>__I+F+cJN95{-bHW{'
    '$h&02xKX48xnURwVN4|+{5E-U>S6(ACmP$bj)U&n4Qs$am&sjK%(WD+eN(<4@;2kYEy2ojCvst0!NBwI'
    'g9O%X)hBt8uXj<r_Jm{~1}dHx(&$p0%oKTbUH+al9V<O!>gILcgOCV6hRl(-WJ=j63)hr+{IZV7qL_$C'
    'xg1!D#aqDOvfT^sVsN)s>KYEhBmH3KR$81YnFFh<wl@b4VMgLhX(s5lDY8p^d`n)DwOw-9M7}w+b8ASp'
    'G1R;eU1bW%@irQYQ%LY)@BsXM8r97ya&d?IQ{l>Lau)lCKWtw}K~vv}kqRSUOYtSdQc{-5tP|q<;=1<s'
    '>2T~2KZtXeBg#o16roD<DB$tHbFqT^g-;^PA$DkF&pmeAV50p0?7eH3+cvT&`h9){<C8lr-Q6wo{b=uu'
    '$FZHnCl7ntPG+4m$<hJ=uv^<|Q4uBEJs$t}Qw4w&Nl_9XP&>2N?llv4OJo74D%1;ws`|AAG5B{gOoq}D'
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
    '(L}l<*c;j#2Y*WKfXdqNXd9nS?Lqz@d+*vCN0udseXn1UlQS5SGfXPp57ksxQxsLD>C$6JR`rY}P2xVu'
    'Y$Y?Z^C6X5Enwg;Uc+mwKdkMAcWuD1Vc5W~cVQbIU|{V07u(%C^T~g~=iD2S8Ic*8jK__vQn%P$BAJXh'
    '_ug~Q`<{Ew#uV#R?@Xx$q|!RMB-6!C^T|dhx!aj5a+SwhZ8-o-p?rCwc=}}Z#~S(~-T%xaXJ^Y#6Ek|5'
    'aXqcRsUO-XESM7lXK6+Dx?%u5@AM8prY6d>%57ZM0bPqx(n9*aYWmY2DzF-DN0mIxp`pXD2%@SWt=gKt'
    'Q{1wuS6z9WWOZPnf=#O0BI+@dYKt9Rt-3K(Wv8S)R4Un0s1LCo3f4)O>9fL-_HcMdE{4O@+}9n@up%iN'
    'F4WP?XgumAIvX6PA!zE8#_K5TfZL>XlA_6a5Of*L%6+u9wF_$mXvG-S+hJu@1IX^mB&?`5IXS!Ec{pBF'
    '7Z@3jXi20Q&nR(*tcr$i@|vE};Tq{+Dp_v8Bk*dHNAsVzCu9`nluKXW=PzqB<(=2HIaeO@c7gng83uSc'
    'D_;TjS-t|S%Hr+hOSs}^RTca|YOSY6>HI;`&#Uw6Unfa#nvdY~<fj_t%QwmY^UfqELO)-Z9W{IXEZe}&'
    'ws*f)>pQ9413UM6K__etvewK2CD>vVrv9tJM0awXB`slRnfM%xk)~Xz2B(85`d9e<#457_*h}@WU89ur'
    'x~fX2{AC(=NoKoh=?nh1)uO+gq1}XZKhF_vO1DefE+^A#b%ac~CI{+||F~1odu(ZYRO%g2S!yU@k?Ehe'
    's;T@;*HrHPBsCkqtR?%?n$qL6Tv{@~@ts<sT6yM-UP$Jf3cuxmStE1x^HIylP0LsJS8XZJHVRm;kgaRX'
    'Rj1>^9*7Fx7292wU*%8vV8&pN(Sp8EA*W(pl=h$6g@6)68Y9SUO}kR89Vh(w2N{0cBu(Q@0h*Y4MRMi+'
    'N>MKTm@Ufk^ZGou93#P0(Fj%@F5XVn?J;bgZdYv?bZAvMCC8oJg#4_0Df(84_lvE>Tm9%EJt)hZJ*2yP'
    'oGS0CXMU?SrO<!!MW@J?w~iXkf0G)M@v8FH5(!_dX|8>#>NTONdta6y#gBu|Ryb_2zeXN~nQeRDR8oIl'
    'UfBMy9Vb+R$?}d=5*IF+OGJ4<LqVj<nXv*#I<e0Q34<_TZX_&WdA4*#6#Ev7ed-X4I-%#ru}uP-+v4tA'
    'BG+R<Nc|{wsV^ucju0%8Trw|+NKEYj2K8v{$tZ~3fCnxQecz4z*!Or$2tP1{hL5A?M6sEv+il+OTqSKc'
    'RqR`bRWlZ5j)-^NNz~v@GLM79l6<H@tDJoG1N>p5ty78GY?)OIMzGj{3SAuK=lI8e`bEcXSek4P_-Yef'
    'Cb6~4Hr;WEdoZ}2jHmO?GdjZ@lij}WE;tx{My}H*z-eY~XL;{M-Jij_z3E}AzG9F+_w8KWh}A21jHXk0'
    'z$e7KonPX8>3iyKioSD=+2(o(Flk`u>nTBjjVEdPv<FMd5S?ATBieoN(*!d(<;_z%IT(>)hYiVWwz{X9'
    'Ubn|XHoSg+XV!0-lZ*k!Mrz4Th2x|;&T&Vl=$9q3{Mm7(iunx>j0;b5SA1FR#qwvjMQ>wT0!|odv=#t;'
    'tLhZca3S8P7P4tNRtY#IPI}k1SoyT^QirpN&`J+I)vqPt-+gGBLvHq=)9fEg4!4Qu6~xWIwOksi>FI03'
    'GuN%JX9XzoWJz|ae_&e$Qya&EcN8d5iDWfFub;=F#H`R70^rO+ls<0;rQ~7d#(PD(Smph)N1V;hBR8il'
    'M!FhInfd-SV`MzO9*t3qq`=+^@_O0$1TlD6C<&Vkp-$JqI=ip>#Qqu9RXOfFMI+)TUzQ`e5(ls9aW3#l'
    'Y)uOTeR;x^EqF(P%sW7$!E>&RiLqKCW;rLRXq`EjHnV}+Lh#hVdYWN>Pj!?}341-u9`&EzdvNdcq{Lts'
    '0&C>rE3bu^%+%Fq#UPy-xfMMf{a>1DpX(&$>0*LnU!_;8%gC6xxHDO9!vs#wId|#9<6>^fABP^5?gKQ!'
    '^uaGQ%dU6SDFI?2JImuz1u8u)%})~ly!J_*W7WG4Q}Z;Ze@}zL3A>iA!&$h#_nlk;70iLo%Fa}1mcBBV'
    '##ypJ4CwOZK}uror<TL#>B*H^O<5poTerTK#pjG>bf{trbaU{;srvcSS|D&`z^_I3$`{&AURXZ>MEAFl'
    'i89YL#0UzeZ`9?E#CsHc08SltfCWheGAf-)c6W|DqcK?hu-)^w<LT>?e&6~AWFek4KVIE_s5(1bMPxVa'
    'yJ|<OWe-x<<!S!+8V9YF={t$uJkJbVaKKuP;5QieEO+>%e>q874VO7sEls1R$rU7Bl_O12zg^7I3rI<7'
    '{I3+vrm+%am*h4Cpk(P(RiRR5oH7$ACmGkT5eaVJk2?<o>k^e2LSp+Mp6w^_%L?6(<x?TJ;6-OeYFV4s'
    'ZH4V#odGEw-e{|-xE_oSRpa|)dhKFI6<25*ElI%b$Ay?&8TS-=3uxGgZXd5q%Cz2P{-7~YVucpRuB3~D'
    '4<)Vlr2D(F$x6AeT1IzHnYI})Pa5ku4Mk55u~0~7HXP%1B0QJDu<`;|M`rIv>}EP1jTf^HS`jB@LWWCg'
    'dpXI>sbUh!t+q^f5w`$v_(FNiD4CA6^Q=+)3LLSLb~hJNOmz(j`Q?cOmvwgYTu=FMIpL#<weAZjWVQdt'
    '$yn<&qK@FP-%Fl88qtPY;kZ)4jb%rGS<(`Kyd{Hl?wP8QhgAxV>_m&+K5eJ0_-Kjz<2wpHZs4(A_5GEK'
    '%ldT*CXiJ|%d31u`8TTEN{8UB@y<Yn1{SJVi(CwwRX{7A*1C5&OsZgNyyZVF+gc@QcmT6cwnP~uNkh^K'
    '69n{R0bsxb)+qG-3$S(G3{Ya=%?o}190p9ik+<sb1}v(Rij#i-J4$}*`z*5sS10*T%c9IsAR!5&B&aE`'
    '>C3%PNxkO<b$_*8=?QlQtEOPnYiwdJs+0{lm5ZLOY^z~fDy}dlw8zFCf1$cn$#*B;voRNw>G&7-@E?$0'
    'ClmTT{&;6<O%O${@O;;jlo2;%VN5wAo+}x3tXO(dQdihE<C0QJT*-yy+R|k<ivuA;`|i{l$)sxs(zk_2'
    'sZZ^ghSH&Sz-35;9oRe$m=wMc5u<^$gFp(;rg7}pLQvm#4$NYsIK#$wxW!}~%Ya7~4LyfA0i`nbu>g$~'
    'Sd!a;??=oNF0ld|79xGm@}!W`^<yT>WY{=Xkj=3H^wzA^13rcR<(>*M4St1=2CRCft{Tq_RqF{vOd{VC'
    'w#S^9@Yo^|^#qTi(Dj8Mcs93vA(`(o64^jLUd)*r1l;wpkd{U6s@5ZE<oS`sqc{o(_kb=~AYjX}P>&7c'
    '*^)=n^MER(8-z57J&#4ywmg^tizKO3tw(X)#*fJl>f487{I?6PhU!>#ztgo(tZua`I8`r#RC&5Wg6DDR'
    'M^(eF%r&tSMXRv*DtU=rP^wc+TdGz7;!YoXcaN)p879Q6Iu}%&1I}Vp`5kym^USxS!Mw)X>iuNJ>U3*}'
    'Sp$_;oq$n%h+y<Ss5(DfSNZ8ygjSIRt4+51tDD}}q{jCA2vPl;fBE12_MiXz-~8?W_W%C<fBTz%^DqA4'
    'Z~yIo_`APv8QVWPh9}o#F#5#sKRCndefY%c?I8Id|C9gxxBu0@(+vOn#^HEj;}e7baI|-MGk%*X>hwva'
    'w}|V1_}l;eH~-|{{pNrDr@#F#|Bv5KeV*3M_{8x)Ajhwa_q4{`a$7!eeoMxD-i+6({vZDSU;gIr{-@tN'
    '5uk5Hev$w`v{8>SV%6W~lQ-W!%76QB{)gZEtN&T^{cr!(zy9sN{_lU!J^ST#;7@|!2NVQZBOu+8Pcoo2'
    '^M9rL(Fyn`|Hbbc)2qs4pBVm!Bf+!O(a-4olTH%kdwU~Bop<9!huw_FGjZ}s5VYqF{Pth``~UDi{+$j5'
    'WX*v8@BjLzzxikX_8<S7fA-t|`v3gLzxhvp`=9+UT3-A=fAb%Il)|FqlckBF-~_Znm5(bio6qiHk&EP~'
    'T+^fH(=lHtL8Jb<rS%b$By=2RIW&lEiwei_+(`P4B#{$FG3Q|%28;wuQZAWm$1d~m#F<%v%Q^8Hwmw>4'
    '!gHNNfL+xuF)!@tn1i$hkYu=P6_K<(>Uy5^Bg$y#2>36Eh#PU&v#r3g7!$+~ndke`qSEzwWQWwV@WkDX'
    'W2@FG789(JkRGzbVooQMbOAW;$G7BKoK44*Et3{r6p+aCV&A8M!zFP;m$_CP#nOV$JlkPXgg%Qx_<@oz'
    'j6F)NF!XG}ZDDyOvO(fF4ryRV#Nm-|S)pZN6DvnLB65X{Xk^n+2%9p(DX{@_BBYTQh>*}Y@JLkzRLqq)'
    'AePOY7}f{70`nq3ezvqM5=O95p&P;m*`6KQJQOx}<Iob^;oO$e#-2k?Pyz!@^ByW<KvOXg0*dDqSEeo0'
    'ekR_%9Z&f~fpw;s*hSJdmm%lWab!pwn7$``Px8=<fMjgfp&@J>OjuYX5I`P|A2BO(m~cZ5{A_bGBwetc'
    'Ct`{fq~{N@!s!*c){TXCEk$rfESNHhBA_rQiUJXMp37Z}IUyxpWZMz^=tvh==316Veb1MXU|txzyhPd)'
    'BZP>E6WBQsk(dWDP&<=02s3U|*LH27D;jZ6aN-BZ4w3=FLVSUPaHxltw5{CPjbN{5_vY|nKfSoqM`N)+'
    '71skGeqG39@~%#@&_Ntn(&mwHJsH~}@UR=%ggGAPAgLW9u(y|M6FU$fu_a@iGnWP+J*?0R94QU14Jf(K'
    '5>oCjb9ehlT657ST(v(gT<L-EZ4yeChk+0KM5u(#wy^0R$UYEiKnk|)*d7l#EYlMp(1l9`vj~s|JW5QG'
    '^WAHEt@*Ui6Gkmskq3n804e)Y*bWG%&<8nYf!?vH9|>*|5rfbPTp#`ll<6@M0X;JpG!7`)aL+56h-tDr'
    'v%<whfwY9p94bNd*>U6qER+<KzT<NjI4O){uo435aZpSFja(3swg8JD<cvFB+l#p#jwu=Tb@R*&lO@%3'
    '>hf0Pkr=cL2q=&bb}T(V-~?p{sF)CJ3P%7|Jm&I%#f}|-LE(VHvM7jU-v@#<x4_#(sshP@Snbcrb$_A+'
    'Yte2|;snAKU?apJ3qp&?!1bJvFxO``NCOUA=(qtPpzD1LBq}Th7%s9s!iXoy-2&B%K_)vQ4oM_@AX)0V'
    'A$G{LI7k{9Mqo?XR%8JWIDQzB!0}jU1>6f=;Yh*477&AZ^Wtq^m2>LrOynZmgajupIrD`bizspfj{=QG'
    'O5VgCY?^BU`Zzupg8k!q5r=iazWPL1k-Qr>B9^Z0#IX-1l^@HPiBJXt^_D}yuJpYSFa*lZ2O|sQwS?!n'
    'AA;o!BHNCG$Q*7ax=m)EydiTkEye~2q}Yp`Sb#_hVla;_;`%T-i@H|iQ~1R5nI)qTq*vsF7>Gc8Q810T'
    'MK`U8f?|FY<QiDt76(7V^(`524kFI?uuPtGT}<M2sSJ={Jr+bE@!f!9wy`a+>!f*XU|6P~T%#zZn;e)8'
    '=uKC8lA%5&K98x*!1@kikmh0R2vDWI&11_82;(BMY$tTQC<NAUY23E(TP+Ne;rq#j$HMLQ2@`P;gfWQl'
    '0Om`hfXXn0#e~$cd?5Omx*_le2fY>h++neFyx8&su*7(o?dAmZo9!|OSd0=0NQxr{d(OZ(aTs`5E(0NB'
    '+gPm8_ACb5%)<yC_iPSJHHQ^#U}4CoKTXc!>L~&6aQz5`DDZ{tV|!n47r=p(0{9i=8kpW3wwt&xRZD<3'
    '<$(PX@t8Ok2twPhtpu`ed+H!OU#jVyz5$3{$7Qg05h(4LhJhDi4b2GTF{oq*yvGRkISRowU^0pY=Fj^M'
    '!H&zW9Ry|xHeJV8N=NI$EbHa&cC4n<9(mvs3Wlx@tieXzEMaeg&=(>8Cnd@jFq2v2V_)Amiogp3>Fa|A'
    '1Z*{4+q%>95Vg?Gh=hX<yibS+UXLezv>!Y$C>$4l$8w>z8@ccdr<}rrA&tYB$Ka<hA$%t;!HK?zEy>-$'
    '58+?5C_&2sTSl%2hMR?^nQ&d-2P@hI0`RDeV+%w+wzKv@gau7elIhXB3lYBOQVw=g5P>aE!I$^F$byN4'
    'z*3e7z)a==C`reqz6^c%2RxiGwiq}!GzcBL9a^m!XYyicG0TEU`j#LbwLyo)ArGzCCc+0l9Ym{T`_zuO'
    ';C>tj%m+~ngbO<_B`*=OVW3A{5Z5$DngBfv9v+}4@Fiiu!7K)Y!|}l5z`p4e#5h>t!UqzvL(id<G)2r>'
    'E1RZ#OND@`fh7@x`QtEPSPr!4VX#HU9GyE(f;a|8oyJUpN^%@fwggNS&$ETqcsX0^Z#EW4GK3ul+W_3~'
    '*om=_apXh{ZDnGGK<@Az2v~xO04p2}Ebte+ND|_B#N&6?Fy2@gAG6s#bm@AjOV>-B)ZWrbz2zGOE2$p@'
    ';C%X_1q5V)4a~t*6#=$^mp*KQjcU&q1ne{}C3WCYn6AwoL7bSmX1K3l@>zehVBQg^*bu101G7aiK$y(~'
    '5`y_mohTxd6EIVy%O$9459|;cgK7W{0Q=qrbbH+3ytV7u)2?SPbv=7a*K>3B<y_AwKsO|oB%oBdc;n3m'
    '@{!<L^N?`~hA4<m-wt9IY>gnaEe~vK?4b^B3umO(T2g1Kr@YJ_c$q!zW!@X$N!snQ=x)K5keI+;5RgeO'
    'vB574Km~)>WBVcqJPB5Y?SShHIv11=8dTtgQI7<^6GoO4Wn2j#qd#DwTEwT8?FF6-s1PBy!Z3`$%>vm6'
    '@-PTM2oui>W8ka+{tm7>cwV4gYoP?q$euDIlXiD?H`HgI6?5>J2*@-L_OJ>Ylo)u#ap2k(P$l#15Ga%a'
    'ord62gKiE4%p9z8&y6cv#`E!b2wa60ak1;e5~I1uQHa59vs}lbARU+t8Q2`4o6&C$!K`%QZ$8ka6M^c9'
    'L4v?8f;tPprI298#Ke$XNS3fAthm!>vwU#vX)HJgg&R?jfl;I^3@|KWMnGYL0c^*faKIgjJYh+2LZwfD'
    'I>A9FzR3m5m8#J}H`oD~JUk+Xvae2B`!~A1YSAiez`XPva6Z6Z3nCg(H<rv|HgHVD!Mp>X9IRIx?R&sJ'
    '1^dJI!3T|8*WzGKwzP`t!F(vl>sdc7@U$&}jZzHbN}#G4wZS2BU^7B1kURi+;DM>+Sb%>Dg1~pcUGzbG'
    '!D=jrGY5=Q>fS9BVz3}$#_&iAdC9i9AR=-oNC)YGDgX=1Q|BIb05&6dLc}5g0T(_5(@PY1XXD{;{B}Ir'
    'iihc9)Yn}x`--^=<E0J<MiDFoJ1mlD=5ZJeyfM%B92bLQ(vAg8-IqR0*&^VlNfO7AAK0!RyI~1o7zV!U'
    'dxQul76G+9k8#hZ3{<zzTu|D80rcp>`0zo#5TAt}WyFj9n1IXeRbF>y|3|8%$K6<<A_%Dr!Gr*--XkCz'
    'z(55m0Efp7xr?16oG=vNsX8tXP<w-qYJn>fz{dDNiB=I{pTv>Hd?0<i1nznPxK#ie4>ThW{sm0401RRR'
    'o_XN-U=9$B$El0cV5=W|c=g%y(~I+`SN*GJ{R^l6?Be11Mdu5^%r=A|vJ$~G04J@#d=3;Rhi6`AB<n9`'
    ';~jUFlVko3^d^x^@&*KTQgyID7-1@aI%p^dZ*6kP<@<z9%Ym3Br#Ei|8TQE(3rY;DPoxk^9Sni+A_J^0'
    '+s6uyAVfL9g1J<m(pE_Ire$Eaih$IajNWxNUQCd1f4Lwa)^)ivC8CpsmYJ8f$q`&ngX?K<y$raX2G?sy'
    '??n_+9(6g!Dc;vwz|5gC%Lj7-hBRt@><p`>S_gS(hk`A1OD3uHP#4|_=<=Hdy@&P5B#4UHJuTdOgYoR-'
    '-R-a}{VqnfYvFmD7)<8N$&|qkX2o18^!^;?Fq?pU{tkE{ZNpP``2J#m5?aT-?|Mr${(*s~U=8uBG59za'
    '0xX)Dc)r@;v*7@1SeBaxE+U1Of&zDeXv?Vbdgzplz!XdOcBNSwQH?UBVNNJq8Ufm}+f86i6t)CcF3Mme'
    'X0zJRoVc$ztS%(n%QMCHXJcNS7TKVG4Z~LuI?1FF1A}QZYyuPT#2oLx6<C^ZR_^s3=O}u1Bl2c&ok+d`'
    'xgL#YVEa{A<eem422?@1(Q^=m4;1XLHRwl!@6nt2IvpSz$*YfrwdqSe$Z8p7C7lv5vm01%QeYG3IhGR1'
    'Y*s<oY%IG1off{IpzTr{yHy}*%kpwT6L<Xl&47!Mmg2KYth1qgm*y*W3b<amndP;@hL2KtCcB)SEs3k>'
    'B4kj5M<8XlXZ^j0Vh$$Zqw(~1R{Hg{_SQpzEgs%IA(K+C?no6<n}OB_%2aID)fXeo-Mm}bmMR4HSvj76'
    'oIh(*3^bZQ0tzY3<62QO)u&Y54j7Osl$z@KOQ8c#WnaM~+-H-d1p2JnaLa}_YyAoDd@;q-gT+j#!3))L'
    'zS`jHFzUUX?9{n3%Im&eZ|JAb&+5In+OC?@uDjnU!@$p#-%%;$=c74r{TZ6VW#7kBy$4gU{>8MCpu+ba'
    'gG-~ORHaulCvT%SWLEvX^Y14^FypID`0{2vNl2pfJIX((iXH7?tP7g6F>v5uM9R`rF_cR&eKTO9JcKn)'
    '0!X)Lw^RoJsLL#&27t>|5r0%N6(C#y3I?|VFAgAt=c{;D*?oL86+#ou(kZJU7DjYT5CPYfXefRCDslf$'
    'L4VBVmp4MpYs0u)Twf#Gk4G0Odi0!(#IU@L0R|voLre#$tya}MQHc?!3qBa1s!Gq*U?@jBUDDU%TTzFP'
    '6FvMjI3v|*akZ5-$Z=E38v#;9$8P~qTRP-v6V0mnFxF|aJfsccsy300*Z&-B@(~#}fN({o*P;S_ZIX5c'
    'DF+HQeY5;q2{+WBz~!6O^iozFRp#CF#V2I?TFk3T(x=KD0~=@h?i(_yEQm9%)y06_s9mn+U9CL$)5j{!'
    'ue=n`vC4A!Prxr4&MFh=<I!L~AVYOaydrUCXJ4AVaP7~e955L4{0(-puVoYEK-94VfJ3Uird>Xu8nB9M'
    '7^+!$kczi#%c(|y>L|S=Qd89w%_5+xt6XWCUjbRnZ_WfZcdYT^H>!1pQq8r*N?i=)Y~0$a9Nzx=>gsuU'
    '=OR_Qx>-gAX{LtVc)gZ~u>qyB4Y3IUCIG%@r3eW~BrzLYkE)>{`(`C!mTuYk=o)5vTRFs#Bsf2t0=dp='
    'DWOqfd~(%@RbP~?qz7>P>cVh6s8b=pk)!qW{U?ixk}$_=x05j_kqd#IX%!&4S@{FPuPesyviA_`N|>LG'
    '#&3rLhE_VX8o@3j7*)7Tt@!Ooa7At!YlBMoS`Pb2wZW|BduEdPD+h>HUgp;eTKVnF@kaSAzCu=-|C|hm'
    'VqPaUHAV~NtHpqe`r|6IuGX91Rdtxst*N26a&OmA9hvv5D~-&WD?7d!Lq1)0&6n$~dU-&D0-)BLXeU(0'
    'S>}CZNLE^V(eddD-t*)LUVH4-j#RR?tqMZd2??#ksBC3#`0ol#RsVfmz14A!3w*SS#|W81G3i9U9xtY|'
    'M*}hBm9en_rpjqoM%!GB$JGOt$sA_&?C~UMT~%3T30wD?sz*-ijpS>pK83>(dd<~b-4%o<WPVfX-7-~n'
    'cISMj=hw?E0LSq!7UMa&T-@H0>AP}=`UNL>NfJM9DZ!KhBhb#VvtW8}>$3czKoQL3d?F#XtHG^M{5Go!'
    '4=vjpGJi<sq<msV?)AS|fOgd9dgIXpGOY?Cy}_8=M=I}JY)eGIut!rMk7u)mc)H9aY5)lZ8u)x{I+!4&'
    '(o%5?xJzucB&JnGL;<u!*kmq@Diu8jBd0Rv(qrA{Nx|~L8}VScn4V5mQ~IjVmXhonOdh=y!|JS(7tDCd'
    'JS2nLpAY6Yd`jMyi?VNpr6f#!2zl93cP9&B<|IsQXd7;$IY<>vlskcb2Wo>i!(AdtpOeK*oZXB|s_tE&'
    '5~2L_!HAFFRtA=l$W7jDg6VasUKzle9C%Kq<W|hZbXEsaR<PF>2J6B-J)f@&Xj6PvhNR3UJY9H*Xdcy@'
    'j=JZLk%JLBM1)rcke9aK4Q2y<t)o65G$hbUtF>8o8HE*r?9c(<WGfG!$SJwT&}ykH<XxjE?a&77yxwSW'
    'gq#*>VVtbQZ4Z3LG&VR$v9(&8Jd5qtrr-)>lX;K^ky<1O4TH~$NQ0oa3C}i$NX2Sn*gI;W7CXKbZYJD0'
    'LgAT&i2>F;SwkS#y;~Dt3uTBwz<Ft681VV`Ko_Tr`4~&p8-~5+bsL6W<cS*`VwXQ{Vwl}Nwuupn#IPw='
    'T9?75;BFJZ#^G-mwGBpCySlQh47#ixBG3Y>a5;Mi@O<r2nuON-gfaX!97uuL$|lEP>P|S?+WohyfQ#t?'
    'eyM^mCZVRtXIl5Q0$Xovw%V_$A!gd@?T?jkBg4KV!yzT?bsK}sv~ArtL^{dMO}w{77xOs`0AkY=VAtx;'
    '@nQt5f)7Y?^{r1hnaoSwiqDU+UPrOOudFQ;ieM{m(j3I}UWG=LIk?+nn#RY-d8fvpZ<wXVAaBMOO@q$G'
    '8yf@9*wH3n<qYV?0JjDfO+YRTG@1mQ3p|<vylHnfhFoL_8UdQM02>3`X8M@}ykYZI2AwZfh=xl~Sw_8;'
    'WmHhHur6q26B&Y+*0)ToA;VCW9keVxX$E*=ob)CrY44?WP;Y4mHG`U%JUujd>dv=$!K*Bs+%@+~H8{3H'
    'sp@f<C@htOg!Wnl27X`Qy_x!}GFGH)GxH*?oLxRmstC#>oz}wB>kjoY7S^Gi4MB7zVTZb~R<{jR{#CPO'
    'ZeFufNepFEdW-TzZj|9(<2vUZz?x)cWZ@V{&Cobcp}ncGzT^f@YIj`-5Qz_zYgH4{r3#w~zRWeQeMp|G'
    'JYO5iI{!SI=x}&lc*TTT_i#8%54BEo*OyoS+#8`iS5?@O4CrQ{R7rJJXrRfVbrE^i1(Ku8dMC~6q}jru'
    '<obrTID}FHEx=z>3@se0X1T`1k?NWZZ3;4Xk+nXsja%1gzOw>s_}p_nN4$+Oa^j`U)5-0f8k<5cHpki+'
    'A#0+Ugulj}Nx=z|BNVGhlLw;f)>uoh4TLARoiXMmjzQp?7c`6j-z|$w9{z2$XiN@LDD6xRP;5yVJtQqM'
    'u#BB%7T8?|;pR*+GiRfB_mngRJGp4W`y`>zHpgJ71x!L7FU5cV2IYTJSlYl4GuYeyXu?!!%jtA6sT8WJ'
    '+<&YQ)Gc12ari4GZt@guv(8fspp|uC46ad|V6&@PMrpSJ^V<pbp)>_KtD>93+^w07oW^Wb$wr_T>S801'
    'i<PjM1F9nJ+x$SuoZ8(0+DzwGZl+ZOYO3^lsbXyhx>BiTV6K#DPbt&7P_vQn$D<imImg6>TY#i5EnSS?'
    '&T7VpuV7{X@1c-`(V$}a*BrP^oh^NJw&88N!iCliq;9UVS%fc{+$zV^d=#r-$`xZp+r7YTn{Lb(EFgq7'
    '?D&D+hD@#g#s*~}*_l%9n|L>);Irtil@pPdTM1fwE3}%BT)NH}9+)Z^mCN`S$cSQ)weR%h%TwtjtD1sh'
    'XT_`9G2g^$VFEW94WY%X%{XaMxhlhVI10AU#0a^fi@I#1(HPFI?KK!9%5Jo|JaHvM#|eh|0#UTgkeC_p'
    '^p~I~Qz69^Yk6R^qN&g+cSxsArL<AXS%J@yjj@cqLa}1XgUOOeWtatqW$F&qD^-%IzVj8iRqbPwWWvg6'
    '5xFX!7vh(TfeM%`Xyd!v1+%Ls<cnt4!hvaiXUtogMfhlLYVO=RQ*wAG@fsBL+X&jU!K{m0V3}tyJVjHb'
    'TgrA$TP3SZx!Qtx=Wd&lqy@WR)P6RF{bFl6L3B?cx`{!Z!NxLfnxeX%nB4`jk^Nf?(U>1w2;TIuY!V>D'
    '@|M%lv&9@7LqmsBx>tF6FjAZMb|J%5c<^!N(8d%@GZ<Y1TFVAXrPt|fhLup~f@5rW*08o(qLfbOK<sp('
    'ZrC&{0Jn-wsM^gl4B5;K#o02mG!U}O%&(bgwYDSeSy!3$w>L<NlQx|8Ef_QGHg1>?Bttg_&!JQBQ$<Vt'
    'Hz_eSwNKWtW9$HPlZs4(&U2L^n<TS)W{x~kz<S?$>AuwkzT%{fUI|G%wDy=)sl3Tl%*_P&3s`pBnoN5~'
    'pcY}36PUPo%!TTf*QQ7q<Pc{nBA?$5lNWZ4;idq#AwJEc)Ufk#HWj44@37ekgS-*E@~w=5GGgQL<cv%R'
    'Q&;27=A!Swf&uSD^R?>KV3?zK%)1SaX0Qc)mh3^zWV6lM0c+dZnB8_zVAG4XFxOtX{$`m0Tj=`+Yqjf;'
    'a2pyX+bd>2VI@s6YFY42l|ijbF)dBLkRUVrU@lp1*`m-08LBDvG)_&N$DUn0!3qTzWOQAl&~?6Ua0XP}'
    ';8WV&A$v;FP=V-K>9v_v9?L#Rx~0b@yAgcR&ZU*@qZw8z`3-1vmbqI(OmF+h$#wIhH~2S0d?q5zTd-{^'
    'h+RbIP36P%wucyPm=L#?tnt-UsCJDtt`2YV;?pr$D&y%?2di36T3DNT8$>*U^?<HR7lcRMtJ~U*Pq%Z('
    'Y821T6AI3{x0<yfKSCwDJ|U9{puBqWU`~--2#zH^lrw@&yPBM2WT(}Pc-Lpujw6zruhAot%?)aUC8kR('
    '^`+iC16dwV#B4@Pm(p6_Pm|}9SzI^d))hi~8li>+`_+_;botUthIK`oF~_NdnK3dI4+R^{%!bc1Ef2A4'
    '+Bf7KV7E=>v9TC%4C<Q|+w{}=1{leBD?(KpY)(=X;Vn9aBXsxB@Hdb-rWVnsxQhN;SVn)S)=?UCo`IHA'
    '?WI#S!9hzJIe#<YnA}#j3F{ViT-6I4%x(uD?uHGruAbkF=i^2xSJ`f%t2%45#c)1rqK&f?t0!>QCZ?kR'
    'ErkC!_O~5%pF>D<b-$B3TPwVtQmo<FW)?SX9bm5Hm`E_ym&nL<jg}pJW759JqNbsJu@a9d226;@q?qV8'
    'gE!#ARIl;0-Wc;cG96&+mYNZ&B2bS<Gcm27+LYaB6<<RCY~Ef2k`$AzMzGE?Db2i~+k$s<;%*H`hUCy1'
    'a$0F6P(a;A3(c=cvzhZ$qKx+tu-|8ZeiJ4j_WbUT5%~ae)%Dvz0Rn{?RUKT19~E+%-$hs_!NINBSm6fy'
    'G!*-3B~skA9`2ffFpwfKR8P;|V13gXSGv{#JzteGt($;~Tznz$YChO0py#-G`L?-kBY~TZnH!Wl8&fuQ'
    'Un#kSgM6U0i3zybj_H`N)dX;nOh}X8rwZA9uCZ;RV*ntef1@#?<zv14`c24lg%af*!#7NYZ<xBjo%3qt'
    '(k2-XcySOWnB4Vf;2x(X`kT~4y~LcqVN%*4&5*8_HoLLBv*pdX#-OV9U0jKy4NxtZqnW*E$0N@7Yp;Dt'
    'wqUbcK5r@_QNtc_4mZZicx__JpllVICY2SZiBc5^H<=}j<)jQY!BMHf!~QiQq(4tEQr|!<<ZqL)fE-cO'
    '64r^War%bL$y8~8ns*+u2J4mhe%_=C_7cd_;;mkCI<+ZRtE(EN-GuPxfaXz+{=7LLx>i)}5(U`rV2Pi)'
    '4THDhxsj=@*Vj@EVMS9-tM3-9+L+C*QP7ea$m5|6z-#>0f}Kqif{a_is8{Oupj*rR(VJ-O_J0w_8jTO+'
    'cCL9cZN}rOrBd<$$nAFxq5(;fJ+QB)i@_WP$r+hW-=XJPPgJc>t_{O*eGG$al&AVR0B`E`)he@C5bnQR'
    'P&^5OpB~?0tD{C`eKufXT&-D_!j@^a=@@Jovduv3Y&lkcpawG)+{|x9T~iYY?sP~Ow~uehb&{@M*-+e2'
    '=<5*8<xZ_bHY&Ci+{zHM(os!Mod>G3isnenz%q-&6<{MR9SiLXl{rFiwEhH#(`N`x<>T7)8;MGNA7DIv'
    'JbE+G7{EK7gGn=Cxe2vyq^zJ-$F>=_DL1zc+J@vDCxc-tuVgfJ=NN`-EIW7aOcNoRln7358;iO%J6EBE'
    'hl?p`Tt8%ET1^s$(it@pYnwA_>OSVCW=u+M%(KN%VmkYlMe#r{X;~mZm?$lm0w2LT`aIo+hBAHw`6gp@'
    'DYjd{utLJJ6T2?gU+s=&MhILC*p0SJng`vA;Wc990&vEdZxeRQtTBZF`}$~buv|_<BHmm?BU|M{-JDT|'
    '&sXSeRx4UlbcJFaUYjPw=4kC)cu*ZdwY7PjV5tV{t!&IBJk*TyHozHj49w-KZUenX=U|#F#+Z9hH?p^$'
    'M5A~(xw!US(?psqutrp{3C$Q4Y=CZ=3OJ6JNZ(1a7!#=z*(Efg0t^|#{N>;}u^eh%soMsw5glwoGgp&-'
    '9dyfdfYDPddz@KILo(P{K@&1S+c6V*YLG^~gmkt_r&PDp8pE58Crx40ja96BiwaoXBi<a42B*9^I9FJ%'
    'Vcr-__4DFFm$jAn=o(;?Zd3E<sOrA+V8LM%8Xg*@R%HVC=i}+?*@UoGvx?ToGM)IiG-6Y6_%<EMSfb)m'
    '(BejbpNc!tXSfxZuhTfXwvM4oHl7$uye=Xh1OAjU6fVRZBuw27@q^?vS=}|(HfPcWc3A&<Oc7KQ{$6Ii'
    'Ewp(qnzXr_B^xU+*+sTs>MfZ&>)xt1f2W!T%`v$u5T=c46_zsOUlk#$sa2(#CRD#pmVxqIsFn^5fNk84'
    'MKI<{Zf9p@RNH3&8)S!Ke6|%ao!}7WnzE*_CwdVE#wfb=nWK;9wX)MoV#r^bwHjomZsO!xU6D+0Trn~i'
    '*C-ikr|K5nu{}$mrpea^k<t{hx^Ja%(9<~Rr8wv<aZvV_)qFf2YP6=v9n6P<yq+0yUYG4EFH~OzgH)jI'
    'z)TS|>^#D*R>lEe@2S^&$?IiNwtY$~QdDyj*8>oaOZ>h1@Y#jaKYRA{>f-e5s(<<QspAKoFFFUFZAC8g'
    'Y&((>^&^|cffad@g`VXE#Pxh(2R4oD!1n{s3W*cNGVrCtJxN#?(1Xv;POr|tdUo+w{mZk{r%%r>`Vao<'
    '>iiO5A0BkO-Dgq`2P4tR?P%wEL8g56d1rnjI#WT09l00|d&#Au&Ww@KNK8A^#c0+Uj5=qJPXN-((ZOe('
    '134Yvb|z$gGaS&4&IIZ_hhOzylMkjM_bXarxesp04ByXvwgAzMh|CP52_}#1lQL2uotR$G0L;VHGif`j'
    'K79wE^k~_CFP=TS0_5SE4*PwTTG~H40Sjt8d?OBzP9|guw$$u}^GZMe<n-~={*&{Iug+n6pFDYtFLyl='
    'x?XHY0e5WAi(KF1E|ne&s7Gi(xMYqmnJv2;FfPu|o?Se|?L(}cpocy?JXDjq*THAIS+13X@3FNgh=hc5'
    'd$(jT>Vai;EqY|Z2lJi-bkwu0p5-fxxQlBcygwJ;&kv7|UUcO^DVJGyb3Kn9KYjT4=~p<J_p<wb`r_pQ'
    'wk{mZUjjYfSHB}AtbUs=hGO*_(jETR?Z`0@6H?OVLO<wHA3u5i?BXheLE*;C4MO4q14!GKvG2Q~Wiv{+'
    'A8?D?Ru~5?vJwoQJ^Swb;uOF>zj$`JoH;TWqKq;g`X1$;&EY@la>5;lcy8d>Hset&gcs7l5AQ4KFj0+-'
    'd+9BWdzrh!J;Yt_dJ0xAh>ZK!0@wr|C6ht#wRm?w^wa4)wq0jqE?pM;p&L?<`Cb&+B=lm3k<g*swPg^&'
    'udd~Bo7;LGvtKT-f&z>^?+ww%fqmrzQZ%q@Cj&ov{LOj);p4B)FSE!De9LiZ<iT>I*rzgJt_*l2Sl~sL'
    'CpeW11dYcFfIL6F`WiuKsso8&yHV1)UFAmW6XKMqG>L6OSyA<&{v!(0Lp$`20V#_qauoJ)OYF@qeEM^7'
    'c0=Z1(qRB-t<XsKcm<@>T^WCm^^fIW6~vKlWJOdkNh$JV5P1yP({col2zMn&VIJFp0HwfUZR&B00qI4t'
    'MFb(;qYSu1$8%xgD)2vE%s&40z_Ss|JZWFtr(}+2%Zmw$*8c2<fCj^rm2eQ3nFNF}{Fce5FIu}9SOgFu'
    '?AW55fDB|7tk^^GK_c4`fEOM+0^~Gd@N>i+%MMuVdCcW5_hL_YOJp2v(sNcauEqozxygSZ4A=ST!v_Dp'
    'pN`+Yus~F1fT7GBzeTB8z)AYK4_U=^_Uzl|&z{26{_^VEi}S5hBvkmWA6c<)hfGk{2^|LnZ7d_7*&g+!'
    'Pa_)e@IHE_XXC|WJi1tn5W|nOveAUMxdasV>kCk(2dv=G_m4Y~ecZ8a>!@Jv`d>CAvsve>M3rrxcO0fR'
    '!U_I*MrPvZ{%SlfWJeo^DjXqre{eklTNEfoUljz!)u-ddh#$_xP-b7nFN{qN#0=2&0%v`KuI=RTD8GzE'
    '4|h*eeXEDaE7g<PWC(voDm^^P50d#B$WCq?GUA=lc&<MjCZEDz$#f0~2V<oBhux!Bd2qOn6Tq36&d)(v'
    '3=fB5beJsU=(rO*M<t%0iTU!KQZFSBpD@7X{IFQ_0wB90oK2Nk0Awhx344c|q+-cxcl1xNJ?Rz#YV~J`'
    'Pu#ZRIUaY4##9@jU&nzH5Zjn*^>FfFk@>XoP?0Dpv$cBlfEI6klX7^_kKNxSJ)|QIdA6X)LuwD+eWCt6'
    'x?fDInVDROYw^8)=eRSK-M@aHv)ex0fAQD%|K!V;FJHWT`Rdi5Zit8%b}xSQ!h(PP<d3>rI79R4v2rnB'
    '3@|8<HT!*`*Qc55uzP<SfXsBCj^~d@hai;^7#gJj?L#W4j#F}}0O#d__41(eCmqiMFlB%iNGCMV`^rG?'
    'i|?6GML1`D3RXD$j(&+Y8v06p^nrBxe2g`L`^vTHkHp)w_`@Ay?EQ~djD09U>jjKdMEIF^ucix8^xDZ_'
    '2IQU-b9amn?n_rGqk#nH5qGHjYNr!(ycIwC>wOncD)8_(-Ck`!VTkXI7?BYZXiAM>tT!V62z;)57#N-o'
    'I2S-Xi!_^D1wiz~b+IHEgABVL3WP&qN^H)(l$bzT{{n54F8<VgrFl|+f<JX%m5?49x9T0u<p^iPeLkuJ'
    '2bm9{bk{`9HsO#+l9T~5E80%_FEXp_^g8ydk`qjV94C4k4;4d*5mrS4zx(7ye9s5hh+Cj)HA05()2)BC'
    '4H*jwo<A%Ey>fUr=ZCA`GoHBmed&vr6n1)q$}+NRb(MJR{AmXyH2hl*&SEqKktTRQ*`HhT{o!<p^Bs(b'
    ';%Ay}Vdsl4aytsc+vR2Z1|cqSw;i{+dDl}ZC59c(Z^X2Rqi*cxwh=QUJtD)II3%NYhl&2oh~gmhLoUGs'
    'a;+#JEV3wzyqHTr3NcQ=2qBSUaS6({(9$~EuI5zWOjCG24Kb<s-0cK~7RL7yeU}${Dk@i~*{0+zkjC91'
    'y=Am)-R(+PTtB3^Zan`2pFKL^Li1&Q#1w8m7zgtxkgub~Efv#az`Qy~IqrZIg5T7lw6sjHvBjY)C5DyI'
    ')gx__w+RQqB=bT{ztxib$}DdS>5K0tfEdAX2lH^#-O{Ma?@?};lG9E%?M1Q^uU^1TfQm?Gum#Q^b{+tg'
    's(?7WyugsSrdo~B`8bJ{YuB>#=a<i(!V_Z1kCnOeiv{c~0l_tA*zmdYh71>?BY^eZ0`rQKl9SJnS@%84'
    '&#Y~AGSxqHkGm+_x*xiL`uAv9FBkWr97ARdPYm^gaj6YJWnF6BJnN(U0hR@^GwYA1+8+Jg^_<`D_9r(&'
    'qRF4%eK;=k=8l>Tw;`$v;<`%39(~Z}VTn25SSd|!@j(k@${k*N0<geSzr&eJUfk)<;f$5?Qxvq#kGsS4'
    '?v(P|N&wM|`EXxH!qvP~xVr(UWG-0+UmHj|i@`|ii6fNth9LbZLfWQrHr13`&ll?7Z7&s?L+XvvCe5Zu'
    'Ihl`dhageJ_XCU;?yyc!&VlPS%lP2^!7MRI(C5YnP$uE0EBRO)Iov_z#et`-L|>rHH0aVNSa(9ylk8SI'
    '=(-c?;cC?&3Jy2iF&HuQyX$`UN^vw+4^5*!Mxs3hz|bdBCc|`g+#wXx@Hz^scqo*v8e!*;Ww#P88(_q8'
    'opkd`T(QybhZ^6-dYiG`8hlsw#I_ROZ9mvG!Dz1Cy)(ddNAw&gyR>k?c79QS%vS~GMKfjHSW#zGnZmQy'
    '(YL%NjC$I6t3GwDx-U9~y0@0zt)_E}=wr8ym_H%t{xwGXNl(6dk2_lbbRf+USc~6n2+q9En=^%8?Ud0E'
    '2zxC+0AY>z>Fj1O=`eNptfbN{_`FHt)Kp;nzB8GEQ}@dSwx9=77`QGw!QI*b^C2mW*11KOF@Z-GunnU*'
    '2Ac)12Jig)$p9>q4hG4@oAGP-kxVeG3`UZgy=w41T};sXUZ^WSvyPhlRG{Ao7Qg`Kkz`KYz$-&E%#*lt'
    '!9<GGk~$~uC+SF8|59~9QD#*pa<dEwjYq?GzqdYRx9D`eoAoTWoI37y?6$o0BlGRHtK6~)3Z<YXYIk=o'
    'Ln%mlg=G#JOq@U(wMP@S%-Y#^AtcK|yARxC`eK$hfVv-^Klt{myDgFQbxm?F54tE%dSUnF0nnYR-|iNR'
    'zJr_jd@{R#@1B-EprX}E!2Kgw7WtkIEFT=F>jz-n?Z9ryYoWU5VS3a3&U^Lu&WAFu>m54y_TrmMp(@#}'
    'ztoNsi)p%8pYPpFS1Cnds+`x!U^Lp|tKwZe>_xTibKNZHz4ULh1arN?cy{tmO=c@K{9;T2RQhJh@wiYn'
    '6>~5aVErgRUf8cze+2#1!&IK0N@86-W9`<_6ERIH1*&&+d>(Ug?_&-#*I?4A>{gmm%-KzkgOa+r-vPS}'
    '*Ku^$;4|2e9>dm|BP{9z!%E!4GH<7wyUNogDmeX9VKFb1o{Xq)1L4GsGuv{QABrGi)Mr#$BI0)OASn3N'
    'F@ugagY18C*!}A9)i>v-KfCOIcYbmC_}No*38E9nJ8^T_eOtaV@1H+CeejJwl{$ZVb%}8FdTW9C_W3u@'
    'P9OG9FRmUxIz79}Kzp@YGilie%lvS^^YY-mTIvUo6L(-eIgdmV8H^U92l4@|pz$>KUQw8QF&r+tYs}_i'
    '0=%`D36-HirkcMb84R%=5;)=e;WC^@A)Db>uQMXI;(q56#DU7=*QTrBz42n+p&-)OO>%7ZF2jz6BjC5j'
    'd^)=k!{Pl7C9@lN9zpJAj+vNudSWr|Oa>EyxGnV-+6!o<_1<(+rt19U9v5%!jQ|IwK;W`EFJE^5=x_<)'
    '4YK)obOfIQI$j=V&QaucC%l&jOEB<5r-xm3@$|6Q16e*-{gA$J;J4xUx;LK8XJ2%Cz1+Qv-fidW^V5f*'
    '`wB-(R*Xh*7x&`i7vsT5IXF49c(sR#(Tld`own>wPSRdoIzBpfy&f43e+}~=OhG8>I}z~fXsquZ%zh1i'
    '!|>N{uf_b=FJJ2a&;Dc%_Coh)Gw&1T*Y6_{_xpH;-|g!pseU)ZR?E~+{FCC3qtBjSJX5C_c&+CAFR%KK'
    'pFaQgO5c1@_RVlXze2A@<=0@Di_Gn#+!gAy+rfH0l!6+YsC^0_+g-v!*RM_jt-7WGSjbOc)O`63eSH&W'
    'eg^L07?7FtK2q1l*J^959$qc8pl3|3RRGTYY&@QVfll&^P)}`4@$yDR7?w}{#R4{AAm5#QkMxW;6z?V1'
    '6i+7fd;C#7wz@l--p-~&k-sonbZaxa@SllyAn^D@fjPTu{r>%~`_&J@nVnvd>%z;Pg>|*l&ONwTbkH;P'
    'Op0GGya5K2@3Um~eGdLLo9kOiw`0uH;)(T=+*K<L>9s~gpC_28`hLc4y8G2-o;{{SO#5?koxf|^>^^wa'
    'I{u~lYZ0xHG4N0w)jQjC?W&iakW3%7oz%0S(*eI0mEXk@+akT}TQKSLI%SqQo-g-w8+~TqT8Rgc0(`;d'
    'CEi<SrlMAl+xi?7lzwk;4S%zdz`Bt7`s(U=*_WQZ9Vs@)^5feZlIeS*$Va`Dk9r9o_Lh98FO3#Gnq|4{'
    'Q_D_?io1HiT|LcR#f=j6O9_eUBe{gq*Dw1fcX^fNSIipAD_RM4B`<7|SsNU*^Zr+<hw_)i^3Urs^Q^Cf'
    'u6c0!rX%=Ws+e-hZgMJSH>sh1_Y0cGc08`-X7WyY;ePgRG`|rzF?<h{dT9uyr&;h;xw-DVtG)Snnq{|+'
    'XRxA9FTlUk#?$Iz^7~qX<bLNM3?0w0ge#cs`Jo5?tsQXU#FY6$IMj|pVOx~pRYY6ZUM&3B3q9KkT^Igf'
    'k)}Etr{LN)w_=wBv2>i+w!BEj(u!=`64Le@pYbU2z>l}X$R?CJ5wqNo+0?g)6NGLR(FVf>t{pqBM@bkm'
    '&m~f@$d7{9p)8itvRu567lt17BSHMgw}P02)a5L;m<W82l`$b<7%z-1n?xR!ERvEqGKe`NfgKU*aS;d_'
    '65F?B$e3eEkWt)YG>l=jlyMrxUQL|>BU8`wZQ&B?gr4I_KZvMnGu!s0!z?D5Yq_q^9M86W<_6NXLu$(a'
    'c0YDP+mEg40tyBdUhGK1I2YU!VG!7U=-52AEW9IcJE0p<;>DKmEte1)*d!F(_hJ%Ihj=t1&2=zLB6f&v'
    '6QEg-xy<t%DMKp5fCml{o`_u678Vb=kC*bf@AKG>MNB-~wd}~^%rj^);y%~{_{tW91r7^H5L$5*z);eb'
    '0x<1zKoSc{L?TBp;d9A3?0Z0j6$#H}c1djoBT3icmTfsgP#^e%vLFtq?Z$2t6JG?tubve+t_=M+j6+vS'
    '7|si#00USs9jm(dhCzKla2)}h>$ra4MAY}aFoOLAuJmCwZV*!-IN#$ipa=XdnCs$AS73>Nhr(~F_7TG%'
    'pyC(?prPgY9B+e)n2C@wOTe~LkX({EuFC=%GuUF!jU@MMpZhG1X%yB}3NW$*5F;LiGG<=jbMA<M2}zl2'
    'hpq=Q5`>oRk|+RqLShlbKCxm6bnX&Bj1}1RYz!FK=B{HAprXJ9=8cKtIFaoWKY)$5DMRTJgg!_T%jW{7'
    'MjQ)v!y>Wo#G&uT1~e(mBI2+X0ob)X5;EZcDLE80N9+egx<C!C7g6cT2-u8(1ad7YERRwv6!5=f7ImzA'
    '7~AqZ0po(G<U9-j)iK~a4kgetqp%IY-xlRS7fir-VGvm`rx-Sggpnkil=km&tk4R47q}<1V`_8mhBRV$'
    'qGj96A_0>E2p|ZAl(s906>!iM5e)*@BS4IiZ0tBHQgZ}%q{Bg8+Z<LH#~!Fi&>J=gS|GzPjzOq<B#0Oh'
    'l=v~TK#qjI6|o5LQ8qFHL%D$;peB%<u+SlXD4FF0P$F4qgYKf7Q9E=Z9x_0uWye7DA-5!mTu)Lens^S#'
    '&IBZN>{3oVf|tRqAcE}+0>_VG(LSt@##SJKa~bGS7J2ZOFpfNnyP(KjR@G2OLbhliX$%9{Li#bN{2(9%'
    'Bq=H`ke?L9GANG_IGMNt_83S`_zac|wg+%j$xsZ8L}DiZ1I8h7gm>2^SW%P$y*SjdT);R?gTex(PgqPT'
    'C~XH%P-7pY25`1Z%0`fIC=Q|@xL(4hS)ke&C}K`M7QyBc7{+pJ;t7WVsm2a)atQNqZ5c^0L<n)6CgBQY'
    'Qo1(mS`>53k6g@w3<wQD{(xEo&hZ6E1r|gRaX<}$Oa^<0crFLEK|y0vQZ{gfD@De)8Aw}DuPE+9APNBt'
    '!6UF~d|yT(sCm!|lz~zR0}E_07FeDI6dg<7y34J>A%e)}jstca1qyLPus9>IGJy0X30&6#K8Qo=g%(I6'
    'VS&}dY$Cy6m0<{Ul<3y_Q5ZC>K%6thX+Z#nuizf+CXkBjP#-v7I<|`^P%y;+1TM(M$j4`GU=E*$VOY;8'
    '$Bhgu1S}+Mq4Z?vV&*FGZO@g+sIZ3|s8kBrfEd^TOlK=_LmMkJh)9T_Vb~C5AJ}mc$d|Yr+!F^R9+*v_'
    'WWbz-{fO-V%ncL-kp+ex5V7TYk`XCAkHXKyui%xV`~e#!0>X(SFcloeJ?=z6VL(@&1!6a{a4MF=9TG~%'
    '16At>AgFu+HapOTB-J9qXhMOV9LK`tp&bY}28r!Z(3CEyPk<btW&>}ByOD3hHhZx5o(Fyxb5Ysb!l~*-'
    'EAI!$2mC9?M%M&{n+v~sxR<W$g@nU~gFXXuJp>H{ECkF7wge4O%Yc>RF15+_a6KBN;6MVKfdJ(`Sh8HP'
    'DJQXua+U}?0PO;z*Yl|b{tj9*KKvJiAQyZW?9+N7F7&#<!f-%;c%YhG4i*@=1C|X&Hh4l7n1q1~%GriL'
    '0rSGjBCwKta5!yXUB<u}tm?d@fbb=Fs2;FhXh|?RJ<A7i=Yk-!2?I9>oMZ+hL@X9@j$Q~*u>*cIpu=K7'
    'ri~((Fg^npIQGEs0<Lp?*9riyU=;#<ftnKBtI**f+X3HTf7*=kkW%!JVj>9;e3kea8la%<ar3|e0)rD6'
    'l!KS)bMVo@uK^3h0^SHI_%H<ASmJwN2vdO+2gnYjCF-9Bpt_cU@S=!OfNk*r94l~~Z33*qoX8?DB#)Ux'
    '(c%V13cy0NLy*VZbA1w8uBa8yQI-i9(A@Jq*CKWd7D31mtBgBAYy;`WA?S7qE{Jc1FciA|Hb@Wx76MRV'
    'Vwv21u7e{{4rYx2A#VerfDiA*pp-#d%gBPI!xDWPL_9-<V8=c_4(dVp;0Xzv24R!)0wg8@mMa=4pz&N`'
    'iHLf@x*!Q$DFT5OCCEf+Ss;Q!Pk<zr9=O)94}k?XF!ifNvsADmv?H)WY>;^ru;n=(NQ%${PO*@k91w@V'
    'z8u&Kymrtpo@Ym(1f0MZ;9ir;#}sJQgO}z3nYtl*61D(i30x!U1EGcyn9rdPu8SW9Hi=w}G=X9P(Hsj7'
    '`i+1IUhY5=c?CpS?7}N{U_~6&2XH)yZsCBL1-m6f>Vu>b#04`2(Cq^rKnQ~aVS^DNt%DDEXnJ*ic6I)+'
    '|NOyU_Aj3OTm}2U6v3+l`c9@2xJ<fsAblH5Eb4;_qp&_|2V90IZovRVX9Z9Oyc0+ewNik89D^Fbn1Qb~'
    '35ZiM%>XrGUEM53uV(=5MLKJQ{Bo}U*A4Aca8!IWsw_}I9yqV(=b;}bx!1*29hYwhr>Bp+vmiS6&K`gW'
    'JonFmmOSsQ+}qx%AA*tOMB$_0^!$-;pMlzQt&(Ghv3(vqcw{+e4_()JU^#Jo>Uw2o9!Bn?GaoP(oPz*~'
    '!$%MO_$+?tmwP)phk4uJV?S`>hYucx?rC%izP+p7&KJhio7xoTjZoeQ<ExjQQ}0oD4tB{Sa0=ryFMM<k'
    '_>SCCFW1<uMw?Y~uRi29Ym-BCZ3N69(dD&rDid5IZI5(6zmsT^auruoAr!bjyPl30lb_uA=7+l;*pAs{'
    'C9|FL8qA2A5J<O2AgC{d6jOoqRZ6UBNM`e&jmB?B_~zBSiC&ssDO)y*R*-fxMPoGA#`0ZAKG;qAJ8|3q'
    '#WgUz8_*KLwcWuV4*TAtN8v;3f&b8dV0q{6qtny#IDF`zR>uB=#bC%0lO@(7^-if*w{CyamDS_j{nFK)'
    'A~G|LOP$1|@cjIS%t}cSicg=a<Ao<=_8MV1V1;>+8+c)f_i?9Y-DR!RJJf+4pP$A4BRp;cBhNj3@aPm{'
    'n<Y&aaM8~r@TvR<4;}?)0Lb^w!?>)$b86e?K*-L+2l2x&bj}|<j2^|{F_$nK>SDPek}KdiV`XgP*D~t5'
    '#{M+go|3!s;nlh;u&PPk*!It5W~zeckG^^K>_XKd#S+pKoE!B04-eefa!BA&aJ7kaLpK2T46GYUT^dlE'
    'I2h!K96VchYz9wBhhZUYA#HG-sN@I7N6IJA&b1+sdBh&rHe-%(EGAqh;*0_aCMlyHo~?shXU7)Uy%7s-'
    '?n#e@;6~aQq@V=j88kRhQ^Z(^$t9<bcPne|90(N;p%{J&Tv#G;Ej;LSEyloEkHIsGJqiA1EV*r4k!QhD'
    '9q@zkl-99)H(9g}gs3@sPH2UAS(-Ug5{n@$!Ga(r02u(fo+M5Xa1mO8ic$)Pd)&tpBP$RdIOazmKKl$4'
    '^|7P6n9h=mg;<bDl~6nG3<(v(qx)(t$rZ=Lq<j!oZAuG-<^9rE$DM<3N3T(NV2br*DCQ!)f7uy~CW|=;'
    'EiA>OfGgPgzJ;o?^jUfl1Km<gzn%&;H?9iQCC=)rWKQ^{#>O&8@RwvJ2d|cel|Juib+mjS(N3!;mVnX)'
    's>vkxrxZA~P8(MB1dmZh*Y~DkBJg5qN8wAasWY39(Z<5Ei_>sbe*`8p<l|&^cnhEi$?BCAn)5*g#PeB-'
    '-w9r$!TQZuI%|ygPmzHI-<Xj;xX_dN48H!bbFLOKA%Ns5M&T!7I)4YxO~_yhZ@vTUjz_9m({eXep^MoK'
    'U;s~k^+ngr3{F0~IDdZn_@e*(;=HIw0}UM>11C5h$B3Zsgf8)bJUwRFq0c>sS)OkLqsb^{0T4E`@EG6X'
    'JS1TV0w4?j;#<|EAtP<UcMCi`je*xWbKTJLLJ@&ii^sAd9t=uHdV%f1fIKF|7Qm4(Hgn;5Pv)Sff;R&`'
    'j`5(JdmeXOEa}F$<xpXPnq)Gd%;TZ7xF5%!8`>n2mM<N=w-5yp^<%+u;2%AH`qlZx^NYt%v9A09IIp%J'
    'S&kKx*zt*t0>WpZB^)OP;m0hD;J7d#4=F(NJWv)A^@u}!&n58^_T{s0FV4>UkDubDrE{$(vW-h`#*6El'
    '`9mR9>-Wur=7Ingh#AVbN)HKm<TwGRD6~+C0j`56VuZ5LaU3ruoChAUZI62q2uLSzDUVC_1L<s<IGHI3'
    'z>V;|kYZ|32x1N}D=pWN)W!2>B4}VoA$B#uAQz!NcPuJw+lgfigk{y3LSb-hRXiD(A4{-(`|ab0ShsC3'
    'Vq`i}XAk!~2UQ0vo&mzfGI;6)_kJhYLENw8a^#oCriL1*n|Skgxlz<1&g0}SUv9TzD~^@LA)c)2)jb}~'
    'K_+6cI%D{INap0_sQT6y+S*%o-Vj#u;Ip)Z!?ZETlB~>tE+EcUP_v{{<I`@1+P4#X8v`WllhFN#283Tq'
    '=Bav#m+BglF+sE@5C*ps%%1@%tjBrvG4gW;Pah>&6>S1Iy=%GF=PEt%Yz*I2WAJRd#X_^f2JguWzzf3T'
    'LU5?S-2qPv{4X%pq#Z?+3NR-qSR5YworfU@XNXG<4h<zfi7FDphE0LV^qwn29z_IC{lMa)f#Yz=!0E*N'
    'W6Y3<ED{lpS>P<N!H@Ush=-AbR!`OO3k`~&J|TnADJH;Stq(Hn=*}GmHu0c%Usio+jmXf0XB3==H+U!U'
    '8O7mt9V}EOz}bAd0EpS9t3c#RM9TpVX>zc=n05QI>Go#Om9XZTnqe!M-5Rs(g;!c)m3?wbn_9Dd6S&y^'
    'ZOL+N&1`MgW^LE9Xv13FuQpX_@}HFHCuRCcnf{Qh@=2F|(xsnt=~i8;o%2f9tqL4;6Bn?W2L5fl?BFvm'
    '!gE(EjPb@m<XJHz7L75PJ&1h~JH!hdFAh12)VWT`@fZbukagxz=%}k>_f=gaGvTgI_pn6uq;8XlS4QHu'
    'vV>#><&Kw*RSicY@hL;IFB`!!HuG+odRg5jvD=(QjEDS&Xmwe@ICI{+EH$uf7IbWEIBY7Flmj$FGKl?d'
    '_mQgW2SQP`!CFeePVXniX0DS1Rv8dFb)zGP<MH(K&Ir>QI>gv$SiE!u5b=)U2`tbo#&8!vSUe~5n?toD'
    'X2B0+C&_qF&^z~xq2=rIZ=RoD6tpWl>ioeMrbp390_KQySsQms1~bw54s$lnvFPUE!C8_|qe!@GXgI_V'
    'kPwQbYrzkWOi4Sv$sjOvlSRXO+}*mzN##v?@bcy84^3g|;1Mb{p)sFJkI@WoOwMX~aSw1NxaVuRangA-'
    '9sf#<I>}a<LLs5!H`tABPB4@3<Rv<nX=T!GD~ztG!6+9#x_I^<oj<jM{{Go9*_Af9@hzDp8C`mFG?@+G'
    '8E4OBnSlP1Q%xaG1I)9dPCHBPu-<$A;4h6asCY9TF4X<s&a>&@T7@;l5cKV+hiS^~@Xlbi+94D_J+Qrc'
    '_(Q@>rWUs<7u*I@uG2sZ{MiTAeDe4bOKJabjB08(#wmRv=i7GYMhpRmd44susFwIX$rN4Qu}*7s&sXM{'
    'DFV3HIs4|@2mP-fUtT@C_^TqL%q(Hg787hfU{H`Po1q>^z!p|nqu8OepNzCj%{8tylL1by#r!a9?|iai'
    'H-<}iFx~u?tXb8gnB0n0BV0^YH?<XtPcBY>o@~Ym7@W7jABO$lc3m&TPJz#rqN@c0+d^cT0F2QWZ2T?S'
    '<g4&O=2C-Nv{_0^b_pS?a`XvZW37H;!2=ER1&;CRcVd&&-lV9ax_?q@JJcEvb*ogmS?4uVD+F>l`}RWB'
    'w7on#&0MzFtBNp17-^jB<5dgE-HwZAKfi2OFSKqn>1(P7uTCc8$)U!Ysl9kQ#x{jNgd|I^zL}L|3RRut'
    'o?fe}W_cNKI)0mMO8b_<id_u502695j!~xQp<(Y#H9guJC%%AH7<OL7_j55)XDjABmGkeOee>-VMi8_x'
    'yiDe8lEXm&7Tj$`k<vBh&?lJL7zC7vu_$8Z*6fSkP>c>U!!B>rzA`qR61nRG+&4y2-Ma;^QD+k4lFRk9'
    '6?$0)EE7gN1Zp;Sf|^Qi0NQG_g^QsvK~<7!&5~6SySKvaYxlU@az^_4io3cwZ}z-X*`ZkDLS4Xq_Vc|u'
    '1nGf#*WBR*6RO!SGCL~V>;?L^90b)_Sef(RK7an~;!1_{F55BW)p)q5Rrp|U=5SIop&iE_Hmg-z7)4qx'
    'HquIb`h{kvi}TZm>A?sR!>f*IhRu$kIkv5Xq^0OdEzUON&&By#ZHbRl{-lXP+e&ztw>ne>kaTCvkwC*+'
    'xtSbAbNOofO;<CVtyUsg&1BBW!Ckp(Y3$6<aHdn$+RapJHPXA6Jhg7~T<-hk5@7F)_!{)%TFY!}GqG*I'
    'd2RbiYujg5+a8kI+RkZfJEd)}8EyMZXlps2ZLjHU`^{$CYciYJT(&)?vh6LCZC{COd(30&w!`gv%VOJO'
    '5?d=dY<o{(+g}FT@3DQ`cFtStxecvnytSV2wzqt@y=GGFG23lF$!>edb=&U-?J3i()$qrUAkS?NX>NPV'
    'a%(TiZBKfj%@jBD8E!v7f?JFEZF@~`+f#Pi{*v4FliOxIwQaANZN?MZ_MF$Yk=E93I@(^c(e{yyw&z^5'
    'mQ&I8n~By|B3g+&G{e!8_R`P{XQAyo39a=Uv^}Jt?I{DT^#rv2<$vrg{cNAvXZuP%+iULGK2p!x&pg{}'
    ';#uo?XZuV$Yd!01k3wgEIcIIAoE<dmZ?VzfLaIYGb!cQT`7-BpCP#-?=a*XO8qD)w<vba@tF=Dgb>G%_'
    '@g6l&(zxo#TuNcGy|<=>fo^=8?`VIbBA1NJ#WkKiPRHc7KNZ)5*<432jrD1|)hbA}Xv<|bYP;R2bWIZ|'
    'jWWf-*15OFAg%Dn9qeJ&wP`~-?MFBrWQpk5cyiRb$jDW`&73Ku$pNz)F_it;92hlC6xdq+mM}($>)A{?'
    'k>!#g@<L|ELIk1DLrP<A1vGMP?phYJi68J-+E{p2a4u=!i@Ne_qXsSvAGnqs+9BluwYV*15O{&ZsAUBr'
    'vh2urIUzBLLMb`czYW5eMO@Gzjy)=CPh@8cJVWANTO~6#9Zcq599}$oc6Be=zUg9QyHQ`L%BX#0E>$UY'
    '^B~Arl6>9}H@U!rWP$qIvK44zyrw*YomH3JNslw_R#zX|jTK{ob~L=&AJJ|umuJub_`$7!oGGvvF~V*H'
    'U!l~nDbN~Iq&%^81&8{9qmO1KX1M!9WA@I9>p#pVt*PqY{qv^}4U3T-!x+T#j~SZ5O555zOJnmGCPW6w'
    'XEt&&CkCs(ELo%5?fy)NiOT=iouQL1*CrJN;bek@Gs}cJI&{1kaWZ|UQhrS8faT>T8u}Rb7~GO;VYE{A'
    '5_|LMyZh~kt0a)p8iiq(h)n`BzZUU56O(!8bOw}#I#KUEnHgP~K%i}HgbLA_gq#WYfu(S$CVzBf-eggL'
    'S5A_$VD9BDn8aJ!(lTT!ZpYv_-Q78a+CsR(7KDM95`a5m#SywN(w4#rZI=hO&q5NB$PrBV9K4n&_5vcT'
    'NO&%@4XCDF4wV&CpZTHf#GdDH5@4rw?Nm{4qL|}IY4ITT?8x(Dhem<rgQMpNYK5>WTNs|+PB+W6C$cpv'
    'gLg?z-cARw!P*i}KFVD`OHG@V{k|3wU)eJInDvShADmvE_qWaE$c)oe)|J}JmK~TD4?j{rXSes${y_Wj'
    'ukO$}`=O`;8L-_qE07L9GVxGJI)G06@Y%)r^V7!{{be%nDi^i$1*p05eU1v1B4-X|Tre4V0goIf;M9tF'
    '9B>&jfeob@p)7P9$BPN)fk$lH<6aaxwiCFN$JHg+hT;=`WC`C3DffLI5{pYmNXvC3b>kq8iJ*ZUg`s6L'
    '7FZskK6fk%8qbMkY=^#8V+uQ!Tk9<%JNxSr+1X>G$WEzVk%k6p+H$f`N4C)Pu(OZ8hn;P$56ysXsexjr'
    '#U6^Cw%aIn+U}&-X{Rx9XEV#7Q0BcBun(8>>0oqit{P2VAb_<5#v82Zg&ybC$H>naJbjd8RkR6-D_*h*'
    'VWC-JN0Er^5Iku~Bijy{&sh+}mSck>8!^xEndMt?98gOHp%W6~IzF{5K>|U+#jQvPn;kj>PCQqJJc@{L'
    '2(f*a29Coe6SmJ|ynM^S>;Pw<TN2Elz?QxZ<8qiXT0K?A-)d0&RQCiHJn0DhhD>$dk--Mt#hbM1ZEUU$'
    '^!jQh)4>~XxYVj{!EPOzT@Wnf2|_iu03`XexWImpf0Aw4Y;Y$oF<l_H0W&dF*Log5G_x`-5DYdEN3Y~?'
    '-^6dG+4>JiGe<^-d~dcFJkXjvS#2e#*wrte8=0^gVOa;{izU~7t_6*mjH83qtkr77_w$omvl0it`YYCi'
    'c`MF6R4zIhsxbR~qcnQLZpH&9W+!qmoy`y5-iRrTV3+_51%I-l{<%>6@C2|k1<cG&RB0A8cn|-`I(dVL'
    'GQ$gBtf=W^JmhK%PUMixpO8uC{a%-4W<ej!?(K)8FHZ)BZigzM2IrSmc<Cly0o$fVxM@1SUXUr*rZ{=q'
    'DIgp(`eo_i8Io(|=nwNej0`7+GXb2F90zy*@4xxy-Hu_ROkl&5Pf$#EzWmalk#h(xz*twRP`hy4A>a~y'
    'd-W(fK|S>2WCdgaI_BVi&c?T*^W8waHBJ3b$(zBovO+*<vDa-Vkw@d{Z5wcv!6{7}34>Wu8sjh(1V?R6'
    '-js&@hET9RI9iuDZ>GP4LC`_DdH6<5DeUmASsMgFA1Ow?RHhG5(BX*~5ehRo>U=nE4`s^B!zJH0q{<bR'
    'x|5vAt_-Y`B!{kRMg`0fIZw$g*lOKfVVABUo8jokO}5+7K4asFFpqQ-;O^MC6A8?Bc*4j;Id<)BfFZ%R'
    ';ZY1`=eLvjyVf~N;3yv{U;Vh*3e@d6VK;~CTMKHeqkrrSM(s-H2aEZ9JTgQ>InP=z0DPCuhouf^cP;q!'
    'b!)a!TSV}kn(-kS4z5SH${08qs^o}kZOzm^g~=bmv>*H4OXz!lk?&Rl->t;G_aF9dD}r1ifc(QD&V))b'
    '6Z+j-<aaND-&W(k=KTD2-F$<Wj#8>#(X-OTmp4KHziJD^2=}a;Ex?>f9L_BGWpvLdqLm0sBMA2m({Vv)'
    ';<z)%vZX&0MsjKn3Qcu2Lf1T=l$Y1)%u_#7IUB8xl(;j-aYQDQ;X90TWXM2$b~xZhR`W+zR{O0&ULTG-'
    'Y&gc+nD0$XV+5NCu9*o_7!=87pxnE6uXA}rrh+HcMtkGY@LlKI$0r?4IqJUI8|9A~MewZi8ZXk##Dq-I'
    'ex1LYz#QgedM)NNLv^h|h2N6Ve86TWMv(Q>CuA@>Wx7C+HoIr@>B2}Cpk12lzG-EPR=7!R_+pDOnM7;!'
    '_g7|}h^4yC_$q&X`RwVJMu*90$p_=HSwCo{6Vv?0m98<D@p!OOE9TMzmupBQ|Dgtbgsu0!8xQzWEFT*2'
    '91^JJoao(2O9m5;GT!3e`OOIRZ0ECM!zLv1mtoUn7l#=bCk49BVaF+3{8Y>snV=RmFxplgTa9w4{%Bw<'
    'gn!g&!(rDXx{Q&|47%zGrJ}2z{P?*ZbV;XXeD)<c^XN$l7ABhhXbwRs?E~=i#{@ws0h_^33M~PycmW`*'
    '@5yJ1at%dL5R}oK*hiM!L3_DzhEwByfXq0R7}rKV++Ne+4n7#&O@qmBh6989Nrl^<3AapuTP3fVpuzpo'
    'o1yf#_Ojo0CBJPXt{E7vwcNLlE+pPc;#*63Z$)WuE7Pl;A@FNkVws5}EAzQ&dreK-M`qfd64UmZKXYI('
    '-n;RkA(VeJW@I?{mEc+ggT;NA+Vw}KF>c~SV(&R=+fvfn$RgXiC8;-b^f59)YrBx9e`T`1j5$??636b&'
    '8_W2KMhwoj(#H0dHMWPOu{(3dYF8xKR$pxW>qEQwbuEH#5wzxsL&9`Hk@u!De{~g+C7ZQ&!kkUu+;Y_X'
    'J9AqA8^=y>Kiw8+M?iHBPWWJ^toXxhAkoZyy3t^GbV3-mh8WPna4>(TtI5cLnC{;0mJs)$lSCbi6D`R3'
    '=^U$j%*jvy`LrOtKKwZEBA<+wUjG%I0vv8<<|OOsBfNvs0zIB!F?~v=rl?UvdpsAnhpKYlt)Z|2>@XuE'
    'CWb?`$EQrE*qWJjqKUg&6(<9AO+nw4A%*`ld;$DNci;7cxmyXX8h{7;hu$9KBI6PbLo)}XE89{Vl&g=-'
    '8GS!=9L}K0_q!8^GvtuAXYT#b)?S;&-X3hdgLb8p3DPMv^a_HAX)?%17}qsViAK%5ZB|~Pg=XYLsn|d}'
    '?xgBX*;S}|etanizmqBOnXGQ9u6nT{navEI{$FByh=Ln-Mz~L32StWXE`*v3<R-c8*?WNZJE;P~5e)~8'
    'ch|etg{qC1e7kC0n=Jm@Zsp$+HLjB)y=I3R3NjO>(UTYend_(D;4sD~uP>O~Z;!jR8Fr<HF+Tf`_|8VU'
    'ggxBb_+a#gLvpFU)f@5bMs@sJ-90c0oeszB_5IF+f!gUm%dF%9{^cj;u2no=(BWWqBY2t<2rkk5NTo>`'
    '7-EuBL|L_D_^QU1Ek8DMM7_4v$Lao<xI(dQi(AR%Pp`qN?`dLpx;#@S;t99}yh0TWslNZnQ(^b2YQAhG'
    '$yV*GO37JFMWUjWUN&>B>kq!@j0VHwjAF)n57T#F?gwXw9Bncq8>A7X;2meB`SQnv%gvO;K2Weu-cHG6'
    'B9b)u0Y7RZQn|Mr=*=aWx=ElZON)*NDmy%%Ck-UnPL}lCtPyB7ZJE3wgCRO``eG}fBjG^Jlm<tWixKOL'
    'Ct`GX)QXVGngtklU5XSVkut=|@yhQpb7yIXT+QBM*y9z1i~wulDuP+|%5Qk*MA>YHdt)VAq#Lq7Uco*#'
    '+0!VcgYkF@`$ANQG!5Nw9Aa~v6ufzzv5G{P)vHeyddDvk_{$(ia#_T{Xh~#4eLG&-Z;1>rjwqAP{BB=9'
    '83}mAys-m<eVTAx_v_Qk{?+MM-6O*{&s(+zlUoXEu)|d1o46+oILXS@AL9)srJPq4oBF0}%w<c+^?s6='
    '8m(yqydl}ic2$61|M-v1(fkroIi0;6O$iPo>JuitG|+Gbs|Br8k)bo@Es73CHM&j96(kzY=<EwLsG)t&'
    'P?A=dt<8HmKwF4U6|>P56sl%Jxc^}+*R1%^X1L)EY0LjVS<Gd0B8KV!dv^ZI1sSeHQ`QN7{7^k=N>Kd{'
    'ga``Jq+$g>R+YWF`;bPFTU6X_c<qH%A`N-%$u+Rdz7|*8FjJW@u{rS8Rx2SmM9K&++wUhfswfL@^lO}%'
    'NjMtkEa8=JwZ?cq`p|=sTTLa!9qzfQF#DQDd!OA6pesdQW-+yv9sXmLqk5WIw`WcC8F2*VonFd&(+8xT'
    'B#dhsVZc^{DW3nl?-UJZb}*{XGq>)~m!_%<t`1H!z<**`@##RNl6&tnRcz9w9UCk3Rn#16^UT9U0^a8-'
    'z-68ER`TU%8fU;qe`J{s@h@loK2w@3f34-{cRlaXcoo~cWpO?N!^L<J+mE~xhOR+cF!y%aN^DC){ggSQ'
    'fd8PGGyPl}3nPU|m!x%=^_TA_I>;P*-0JP!k@8?J;o<1_vjkYyMljxVWYR`=9Q@k2vzHk(Nd_>X36J-6'
    'gYISwX2GWmbfzMht4ni#kge#Eo_XAT>n*R(6iKyk>Fs2uI>!v=;?{JVl+?FbTAJumE%|&fYEAbi&2Y?G'
    '8LY5PRmO@ozcm=KBBN`t)n%I*AGj_3<4)humSiYk=}NbPoQJ?*p!iK)lWTY0KT^M_wJsk89ND^m^bz|O'
    'pPC+4!uv<p^Kjcjj(<3`ed>7Fe#gU4oerB5^QTUScN#;#1Dy`nyq%A#*WudSTkUqZHrA(phox!xqv&^N'
    'q_%5o^&al-scfcrTstKn_FD6yY|#f3Bk95syQ@B!7-w~3qt&tx73w}1C{)*aag<hh<#)I`ih0=U#a90R'
    '_P({dZRAMwyM6_u>{*f-n#TJfM@eLfn$eBN_Lbz>Y&2RPJQ_B4D3VK3<57I|-)~nxfNr4ipajVFth0N@'
    '6bW=!S65fpyIP;2>Iim#s;|F}OY5V{?BOf9O}i|g^zAbJcA5T;F4J$7#=hO9-|o`Sa+hA;-|wAI-X5Ku'
    'Pv4$TrWbGCogYu8=WqVw0+ZRN{?TgnoUQ!w!}9k1hwTYUNK?_}VlyE=$MNRlEZJf{@p`#HnA?c&DB}at'
    '7x;ZV-FyfP+W}Uidmi$1*E3KOdb;jLb{sj5uNit|7+z!<cBI*w?>nJ}9M^Dzz%=Yo(@@}`(9*pf*&XF^'
    ';{2f&SdJD&j*XBN296&h!!~`*x3mNU7ltT^<1qFN3;!OwZmij6oW!Bwg@GOHJpYH=#V;E?@m0QyOZQ%|'
    'dR3;qo9am%VcmGbx^acoBfoWLSfdv5ZA{Z*8~V;Xc=h;iM;`o)G}BJwnwBN~u6=<|;|!E7(9pN@w{3e~'
    '!Kdx$UG$W7(A&HHUNcYM-CNGM?WE85(>D5UDe$P1R^P2QKY{-|O|$QcZr=reach0%+AF&C#Eri@?EGEX'
    '`nx?LM`$13S?}-Gk3wf*A|1E??yCQ{vH^I@LV_x_@l$s#0oxe2tUY-Ly~Urlx%lVrWZ7bS@!wS^%Wl!m'
    'BY3{Po`W6q7%y!y-ib!hX2<fXEoOmJU*);_vX2#Se4gK0NHb}*eR+fa<?Xgj?seC|{OLNFKSc}k`X1&j'
    'b(nm*43JJu-``R|z67&(*Et{+2IS9&xNlh?-DiQcZuk9`4e~7;r2J0*9b|*3I>3J&xgbhCvXe{@l{)h+'
    '52OJ%{u=T?9zV+S=g)f=AA&WCF;~A`N9fsdF~94*I~(^X<@AC@-20X2W33{1)B6RX6~4t+!5ZY(?cEB)'
    'K+9il$fT`Y;WxozJBv2suO=g2b#t|z691L=P<*2Pi6rDNyCtD!f2(6>cOtLjmEAS`n>Omerq@abJrx<}'
    'AJCymZ-bwfvp8kTgSIMD!l*6RoGT4lYBAtQ&=#NkytUkYB!A9EEsKzFzFHPds!mud<>lz0`4cwc$Kr2j'
    '69p@{MO&Dy^o(V*49Jfy%mw3jQt^+Sg49O3X;D>YlnSak`^dUwrgYkl&Ylj}K6*I8LXC6wu{{KF+Q)<Q'
    'j|@SafZM?jAB_!8&H^5p{QE*EF58j?1%_&MC!QiouHRj3T-zn;o<1^;1jcm{5BH?uaQ$}6nY9=U*I~2Y'
    '?n2?pBjM5jxGZ?Bm8Q#2MsF>JzjYV=Ru%kK2wZEU%xzb(Z(p5BypzDUj^f@_VQ-n})y)*}zp}uxHe6Qi'
    '$EH1LXxdXmrae($+Sgw$xJ8+ap#0S`3g)wap_sB@EO8IGTt93Z<862(o;)V4EF`UqD6-Nm;o8vfYdi#<'
    '?E(+~5~9A^Yj`$Wbjmx^xG_ObY(?PgDs1e@qQ;&eXskA7td(jmRnOgb8(-Jq@Es0aXmij~<S(u9kRG$n'
    'Jj`MMXNjx%catr!TqLvg&9`iUZWxr<(?K*Owv$h{n9b{ZLMXSpBgEbFj%uwFE$b~l-fV+8+8=hoz3#uv'
    'T;%a0)%q{N3os}@%q;5ZE6hRZfF8%&<#Haj)ae0JBOUE*i*5$1c@UwSmdpxxhofK-q4}Kb@ln)XkIi16'
    '-NgI!DrOVyw>5fIgj8EiHU*pa7nkpP-(FTirvhOA=|}HwWR-B)QrAmKwxj}O_EmdA-{-c&wJ7rae(Z29'
    'DWu(rd!Jj{>r&Wz0$H!$Eq7{zbd-Xg!idO&LB2w}ZU@ci+7$E3q&%gB)`~|-Euf8h{CXpD6<j@EUI@bP'
    'z0cXVYP8}eedcPkqhk5kmRiGC6>a`K)OgL8Y;Jd|ISMwYZS*h!KuAA*1=F++JWVj^u!|ZM!!F4*twaA6'
    '=WOsLJVD;ZeXAJ`C9T|B&c(^KbZ>QZ)_%OSwR?MM6>o3D`E2t6#XKeut3=x&36pAJij{N`iPuugsTw6)'
    'K5EBBo!ja*+ryV`aVN3-JPn@w%LBXl^4ju<v*FnA1XXxS^6wWO3j3s2&0jkSvZbw{AtdK^jo1}U?&WsU'
    'y8dw3Tg>Jo;bMlohxOfGp9W`x7-X^*duEgIMj|&)KeAKaPD$)O8EgD;4UMf?nEWgrc44V}vKZ*%lG@57'
    'pp->f$4e3&F2_k@66_{QdfToL*lyTz@M|!egAzv*TQNG=38aUz#o3bEMbula&|)y`gh`2F0oYwrmePu)'
    '3~(~a^qzKdmMZwFn8omfDF^}s>mU`O-Qy*1cyCN(ww60Qu`NQRBgt7dw$SsbJvvw}*LYt7())yt-m)E{'
    'I1eAb{W~MGM6`Ra{&-7w{G5%S8aY_9NDH$u%Le&pl*(_62egi;HkJ8mU7pQ^&q({i4rc6YcIx(jIJ%f#'
    '9(}(*Y&rA1V`-3ODUitqoa48VCya3-^3^XfgNa<uS;eMl+coCI5^~S}!bFYEZUe}W?1^0!@Sp$w@9oii'
    'iYV#MPG=*Gqm}Cu1Dy(Ju!3ws*;Uk%kGbTc!?U)!P3a2Q4c994iW{`0eHSQ+UYMQ1olejd;`zng>I#%s'
    'b4$4YJd&%(KBySp@`iM!|Br9Ci8n@b;=tZa{^vHBXRJw7g3nIKqir#&-+_rhi6&wz_)@RzEcbz1kvqJ&'
    'yU^N|RU%u`+F2Tyu&?TB8|_pkWHJY2ZFORT1Eee<+5Ty4qlB^`qo3leoq(gIBnfA_Rqo(@@ur7XvYHyQ'
    'JJ|EK%<Q=v?UT40n63zUwTr1-boiIbM=6-1+LL2_ttf&?t(NksZ3k(OnQ_}j7(Q0BHTZu%^;FZfJ6TBm'
    'nWg*l*S4w)W{y)~@V~Tt@liu1;d`HiDmHv+qt*(2shUF-eI9KD;Jx4jrghRgiI?9{oZ)lyZ(7?X{uJ_0'
    'LTNHNt!4Ook9%yrimfbJOcq#hX}yT;SKbMO)*w~D-c4JHvLMuNkuzlQ&l)*1mD*UeQkXO)t%0a7AFw;9'
    'z2k91x3?nXp}l~I;s4GOV4{rBdef0r7u|8-e}$YqVNw<h(8f(Tda4Y%4@)c-d`qBf%YvCD&HX{F=)rv+'
    '^;vK7eMU&CgQU0dhIEdZZP88JZBn>ylS-PPQl;m7w&?8cXU%Zhl`<k_n<_zyZhvdQVihdjV_7}vGU5Za'
    'Wjg9jTiOzV0#a4F6XcxW1BNgDw$kLfh5HNDi#qG_p*WG9>qlR)Zt<<@;ZAt}>UtiQEoAih(Dtq4VfP&m'
    'zjZo%JTZUkbXY44{SG=E=Cqx!s@Gu-_D;JU=H~j=@31i~e--@>@2~Ig_s%D8kIv4gZ_g*wi+69|zB#|d'
    '7t^QyCE9E^&&h2bV7B-HMZavGZ}FGY2#bpEF<ng8%iw0ZM(<}>o+p?5cy$NWxI8Vfq7XSr7&vj_pjdY_'
    'D?ou8yKxd5S`z!V8#}HaILNX!OVb0(kB!jNB0JHO04jo2%>RDA41@V}gLSd!g8&VRmcOF)9Ros-;=uMj'
    '&(j0sMX_TVZs?)JGz`;p6W5CZON+h4i3~q6Flb)rS)t`?wiYAX*OM9`@Bv9?bA)FN;%O4h=C^D3<7T-<'
    '(;&W?k)TNiO5*#P6^5~8#fBM1K@i275hBg8+$eFv$co)Wi*4VxOji%QM6(kE#X;mbUTFI$BA`H#md*2M'
    'ej84s+szhVr0Z#n^+r&v?g~?ST8Po_+rFct1fu~3juQl$fi%t2eG`ux<5eTqbF{!jW)j4%gX~C40xd8M'
    '-xa3Z5**N-$E(HDO*bE~WHa4>RebsZ@BT8ydJy5|nU)?UhNqc<<KZRhK0=Ob$8H$<vF3!HsmG?KMS5U6'
    'v7hK}><1{0lhCnI4c5z+UxN5hN617v3L?jdoWOB4-*Ze&$3%t<S2trvw<9<30?$AZ!YGMj&$pZaX&$o7'
    'NGH%7tya&OaB%rydHepu_5>xQf6;QWnGo~Fc=K_VY+=SYGQucEQQ}!n>=}j=hngSz_!zhmavcwoT^PBB'
    'VOV|;$Bq@~x)ocVYv_h!hOysI&*Q7f(dqQ<(d7>p_&5%BfMO(pth9u(Cx>{hqm#4OlZy*H)A_|@dVF;J'
    '!(@8)`lku}^~1Z@e}~zx2L0L1YPsI_{(A!oP_ka$U{<}l>#?t6gjVo3`w3zV2<`CS=j&U1PNNS{e*%Li'
    '4b~rGBoF$3OP?9s1ix)&|3Zg4W10OJCB5k?SZ`2FT|1a6NRyWX_5d(6<~WBz$Ma<nZ^#qu0r?*oFB@mM'
    '+#a64d2>ld8`b<yffeTCOCKl!#Ph@d!GN?KZ2B{usS5D27l+pw%YJiu_6qjv?Ym2Hw>Xn0yFpIVSUyeT'
    '8b;1H4sRrENle(>Y=JhLDFsJBJP~xrmrSAAFMVq;07O1#jAebh&`objEri*#aCV1d!dFRj)nGUrlWsU@'
    'fU&X<c-t?`yW_ynC4`KIk+}y*E(e*=8M$t0dnB-8{)*Jkk;jtdx<?9Aj(W5JI#@c_2wzQ@JO&L;9Gi{^'
    'M$$Nk^zSiRP;BrY(l65YW(nyj6fJMDFil<>LL#buAju8uV79^P7-$KT^?JD;^xrLhSu8&SxNLPjLe=YM'
    '1Unqvn^k~M!d^BE;05MeBU15eAb~yV>GavvYyml#7+%b{;$S`>ti%1mUvGy0b^PY_<@wR^<@Dl*Bg1xp'
    'js{oSGe3BiTz_(``(gjzu!Ngpn3Str3}8IEEG*IW;@Nvl(*qF<c;HIA9`#-x0jA|iQlt&Z803-jcduVh'
    '&e;P8d-ZsVmN%<8+M<+xM9i%bCR_Yzxn{`9x;^bts>6T=vvn#<%oeL#kSx;o1mdfssxpSq0x_-8|J;Is'
    'x<FBf81<N)b7YWE%N|<{Bb**tQ!j{#6Z-)~Q;xF~OZ)_`g6#)NC5rP}`8=m8_=co&>>_Lx@RU&^K@r=V'
    'i#PAikJFQWaRqZ-U(ph_SfC0p#r3ZVHX*SDeZ;hsQWpTy!!p;3BeXArj7dQ~iwGRSBc?GzGE=fy0OP0<'
    'z!90C`BtR2A8lSp=l_+p5mjtO?)j9|>E58<R-^!^u)yPY=jW5xmmJ#jH~(=l26rO9CW<>j2EFPhSZW3F'
    'JPfv2VW7Le>0ghbW(8RuY!jcWSdF+({bDgEa6;J6F`eV>*xqrbxL$sQLd4$*2qR2yJzIilQPi?B&?%Bd'
    'woRX(ZF;Yl3#^ucnXq~lxgj7f@u1Nw#NN5O8>bQsnL57(%ejbsK}p;d>$fYAC{jw7k<X4y-B~5KeD66$'
    'u`D7Cci%S(k!sT#tsuoBM$w+){4+jE30vd@fW+KoBm>_+<_ABXZKzT!-X^JR+FLB4QXS}DD3<RSGHdxU'
    'O=iE5mE}3%sK=6b(}T(OS744Q=%Ab&sBQ^(DnAb9Y(LI^1E$9M*D(-!nOvLaRSbbuTqY+p4-1@}-RLr?'
    'K+}gcB42iZA1Srq$%<ELCceNO+6xwOj|nTOs4E<c!k&~O6HC4e>6)cW#s4h|Mdj3(iAH628!ReE(UR;m'
    '5@=YYTp3P?ZG!_^+<Jbbgq`HFO^)iQ7|}$IO5aHZpuzsh*~Rf2eBb@&^oPl-w;24>v)A8G&flJ&y#^~-'
    'e;>1kqmv)cE-udAyq13auD9Rc9~Olra-TOITfkqF!Hbd@T}vv8{Rnc&;(baNTo_})F$Ka9<u5LHF*!`%'
    'W%K#wG~0a+Rqgh3iKBtY$9NrR;o?zI$|3b~ONAWLy#SI))C=^nM!cZgh*ilPNJYVdT;!iatVkIk$0uO%'
    '=;UN_!bJ&c<|<;3Kiud#7O0<~t^9T`U%c{$&(Q+j2!Ltw56m%{qV*6Os1%3r97@fADV@{`%T%jyJ&WI?'
    's`cW{r_gdTp;%|z)qp0-(NaemWg=5KJbTUMFY!jW&Q5{Mi*^|A_~`QJ)tm40<MFSB@oFVK{%TIj6Zm4X'
    'Uj7R$sAhL=>?+btnSU<Fw?>Smf>U`NV?8fpT{#vgAJH7sOKZ>op|cS)x~3O$_Rv)yzUg1T=uzH_f1{wL'
    'R!BVLBDf(I3wZSE;F*4XkUdR5T)`t5Rgo7C>GSyU7p$DSJTd*QFY!749KK;UtNAQKec9-h7Dg1OebL)M'
    '1rm95@>QSwwp`_ZTCRj?%V~nnc14CdfVZwGfe2%<E{Wm^5Aod|<LhQV+iWF;UtWYbY?19|Gm!1*Uk~LY'
    'D-DRTc1vPZWbj2CVZbqZvyCLXN7CSce<*RmM{T;^^c0XaQ(m^&t|?=bF(B_W_<w$dPLsgIl=PHwD)HyW'
    'SWAfbg61(hS%3n1#L5}}2C-v#Mc%w78xLQS7l&2rColBk<xMaXEv@2c;G|uUpm*_Gwk+|;k=gE>@hw3H'
    'NjVh<jyn2g5mfZwom&yX97|lYo8W!XsNP(FFIUIv<n1bp@{W3$QYFag@Nb!riy1xiPlw$^8-g%AVsDGF'
    '$?OuTH4&UHwAu)vK!(r7a(zSFm*nO3Mj8eKAAbt5PEpfptA5Bo=O6eB9yDjG&Dj{U1&s1nG!~pjl46&N'
    '@f6!J9s&zNi(o#*hYT-!E0PZLQH8+<Io7E6ulX#bXBCQ4KvCoV&x=3y@bx|U{tbrr{LRsi)6?@e|D3$$'
    'lJd*R_h+wpG{rn%Z&klDd40m)*xV*qrGa<$e_mjQG@Zhkn@$N!noi;HPN)5YpBM1(?P9hCuiF^DCcdXV'
    'wMs|87YH!>1t4Uqo=j^@@O_R+1B*Ds;ziNMwFi#9-c7Ln1@BFNn4kPAUGwGS$G5NWAJaFdrx%mUgX=N5'
    'W;P#Z+YcN#4i~0t`aMD3cMK!LJb0KlSHQGP4FT+Z1|7eW%OGQ$y_ju49)Y7vOzzLfM+S-V2wfeJp|4Yb'
    'Rm?Gai5>Z)x0hIDNrCwu0I9a#asMh`@$z=NnZ<~m`*i)X8VrGw3`~lE@5p*6;t$wz=^6<=T(c#{q`)cu'
    'W=ss70~lvGhW{2g9C=uvuo)&EJl6s<74j1?55Y)Bn5^C}=ys<s0yCuYhcJeGHy6j_Z=^#*z7`!=@dzvE'
    '&}S#_93RsQEJ$Ah$7RRxpRdkdPQhvC*|`RS{Rt<ujOuSOb%uBY76{8!_*eX69Bcy&$%eJPX4t1!V$3kf'
    'o}D6mn`KK8q-Bm(Va05O5eP1D$CpFHApvJJ0f)iBWprR@<l4D`tisKJGP-f-+3YT2Qw?QUvd7r{PR2<`'
    'VTyt;c-6_x&%l;Zi6y%zSS%Oh)=v*G9}5nwe3sb?vUd&{H^$db!`%ei8D_BLjsEz*mzY_mFww{c_ziQq'
    'HDCYL>|pktr(yZ(I}+lN8P13tG$Wo;lG&t<2pMy{je4Fo9Fm!abV@i;1<pvNY<lvpiEW!NZ<O~jpu%Po'
    'G9&4>vV0`oilVH9KhI)_t4eP^7XOi5fXn4}!~}MB6aKMx3GxKfDOXs>eMaU@p};?am74~HY(Egk!gjU*'
    '>4S>soK>;m*tVh|`q10XZqOLZ_^DA5!rGrRQSG@PvSK`}SL+!yJI1$Ia_h~uV?oLryv1@nfq&S0-jg_~'
    '?9It>ZNUI{SSK3nsr3&*usvcc=3F|Hzv5Yv;LDL>DcwqjRW+p-c9U&m8d~!n_7bj0%=}eC3`go=>fEZs'
    'i`vm5XcIwhf%$6)v)NmL<z)hU4dDTNnGfz_@`}c%<s5Mw0T5>d;ZQ81n>d%q*3)(G@9&=jMPdm)1(>0N'
    ')>Oj#fr#e|pR;)ywGb@sBt--~IAc5(T?rl@>^3QtN%$gP0e(gQl?*(wy#b*8SF>MH3Q$Vp5`lpIXg<R<'
    'NnXxLR7{BAbH2vh?k8d<|38ys!uS-JBVxw!<(qTyIV>V8Oo5#1<S@sqLO{!O^B7c6E+kV=sqdxA0ml5W'
    '-0xHj<6_GaylZ)PEWJ&Ci_mH-M9$z_wTIwCKDY);8fZ;wn~(q-Q2NPp7%TKN!XNEK5s~FrseL1bK+Q4C'
    'khe<J@_f(-`F-~Yq(fB%QeLi<Vc^6VqPrysaobH#h#X-QTMj7ZK-oQsr%ypG1~=u;K~7G|Ibo&QBojk+'
    'yhOR;d3+0Yx}bcb0K#rkY9z*iRF28cIhM|%^=t)1RQqhnF)ib10Qec!JtjY5?Ue~GsvUZTksuID$<4wJ'
    't#m?f@P#=iKFMlOIN}@02y{@UOwE_ul5?YWaH>y_IHY)b$nb(nLH>S-*@SbpA`V3X1BO@GM<{rLiKKLG'
    'U>o5;a^py^;`u+rhRDW_YIRYyRAG5V=|gG#DVokWfk<YP+!f4aLIf^X=pIImwI2ekI>PQyVU>iB6VKuX'
    'Okr3oTw~cV0DtQ<fbSL<AFzcH8!*NIuW#^8KtxDPLd%b&H5mwdTV|~svuDp1G3K3%m|RPAdg`wt{2RZs'
    'g~Vfg!{d#`y2OV$4<<)3=DGkWm>fyS+h$zhj%5}l>WE`}wP2CG!FLzN9qePX@VbWv15$f<G4P16?ck$m'
    '*M{LUmn2B*hqaDwzW0jwCn<)E`Azda$^$-6&O!&@jtWl~0{|6d53lAd#|+ubT+5w2C64*MEQ%Yr(<hkh'
    'pkkep6PX+4$gba45Q+3)xxt>TiGf4cUoea3_!H9(<|s(=zE?huB+y?AJiboS=L4j7!F9t6f|=x}k`^*h'
    '!!uO-w`(F73OLM>RQV2)8APg5Z&@?1dEHi49GH@Q#m{8&bcs_vw^jkKng4jC3KS_kBK%qOo{TsFaG`a?'
    'g|sxVFSpIgsFy}ZP!72(x|ivzsR94;O=bu^nY_9@8Z}8sRJ{D={A6-I%1%N~L{8PoOy`@f4JpS)(kdC='
    'ru6^8yH~1)N*;^CdP{I6BH-L;v~=kOwp{!vztFthV1wmjyyc8s3D|$4kh5f@y!Ak~t(5Dy^t~KfQX@i9'
    'L}q3NdHjpxqY}+e&>!ZYL$h@hjSk9Kc^(nMhR?z#a$J{>%AISnDI=vOKF-VkyqsKQ;dFa@saOU3i=}9C'
    '_uOY+)4W~b+b!V}`Nw%aBoC)88I65SABTKB{JX|IUCh189~uyyeAN2|-HnJI1kDFV5Jm^?j5HV*|4f22'
    ';Ngt>0Xqbuhi|X&BiApoa0mG9st+3|1TLg*|4+otj(2iSRsZdhg)R(-2RtTVm1CfUaRU^r%KsV?a|iuD'
    '^+}+>YCPLaVflmM{a$%sz^7F@e#nNzayVHVTRdm-_W~WLeA2M!VkjYnjXL;d35bB8BmrFGO9TREu)aIt'
    '!rXwO`H*3IPl^{I2LQ$xgO@M6yWp=8lkN&YXM01O!MuASK0@%?3-axl@|y9@FIcK%oOW|~xdu*#e#0xA'
    'E`K3^4%zb`*Ld`dGjN+b-*l3`O*T4hw$<wc;P`L&=YFq<pS+_!5Y=aa!P4C8UO8zuFvO9d0sJix$mZ^5'
    'K3n`k_{I;}W~On%FwkrZ7H8@<fp<f!d-T|gY{Th!C3l>Bf=OH*&^DP6Uzp4JuV8TzIUOce#S>(z*`hEa'
    '^?gduLjD*q<?Nem+yB@*g3KteaLl#>y*^tmu*$>NNp+`DZviIHqV78uhT}nw022lVzYKulzvf7=?|;Bz'
    '%=W__<-r8nbcj6fPwmd-cgBb;Zz$+fHzAla4oQR(!(4j$i^>8(7%cGdlD0f!AZ$D!f(!a9d@CGo%Y8<J'
    'DJZ^#V@}baWME{6i?ft6r_|g@ofY+H$@nh5S#DrccGX}A^!K9f#@0gvg}9CnFktnJDrXnN-v1-N781qz'
    '56s%k1<>rRPbZU$<MXq(#DbN+H)2-j^ox5rHVl*SeBQIo-s;2MhVoiQpp-wr<rE?CYv(gnp3}6^HM-rP'
    'u{35T^b?hIwn%YU<eUZBo+z=071==9P4WCj%9F57iH=m!vS|K!cA<du2`CqsN37B&@Rsr1HeU2@C<l1P'
    '7KJxvwqcwj45D8sD|kG*1)m!=z}6-ZRc(lHxQ4YmThz<gK8h>>kntHevVObV(AJB)Wput<q9Odt+B3jN'
    'w_BFq72+4?p?1>lL`INU{)pV3d~fs~cxw5UG4|H#-Y7C0KmWE+R8((FK46&7(`2{QvK^7<Kz_uMPr5&r'
    '%dnmccor{B^(>WWZ<+%6XtZ-;;F%6pdBu63M{#3PF}P?t7E*w?><h4q(H887dJ(3=+Eivjp=0l0<K>D`'
    'kE(nXmhO=N`D$3EbE=8pe#c~;6s$BeC1=}{e=pcB)1M_2!#Gj^eePkwZ4QqXea54b1d?20W;$R#6Gq`R'
    'N>N(pH_DcjONS}LOgm=J%$3LoCI%tP9c7`^Oxf(=`z=@@>hfkzEUq9(A@g7)!RG)p1G;=k0TfJ6Y~^d}'
    '>pvtf=G8xL+mVd|1@lee`GP5@&ux6qpzO{w_WZM~qyvNFphC;;eRtT?Wd|WsPp@FL+#r*#_ByRTnych6'
    '>T%1iWC-Acvf^Ic5I`M8)VaLbf|KW<7+;dw66KL4vMibxL>-9VT@f!c$=p_oGga!6%CQJ?h)!R<d2@bo'
    'MIaXg9Vp-BS*Zg5r5?+9a3_~8VU?c<G6ee)i*^~vu`HwBn+x{g@92(wy1ZK<_VL|f2CE`}4NK!=gyJ(L'
    'u`%+-aTctIfRMLNTm>XWsW)B<<B*5hQ`fK}yO5(Q!HA!kRADR@uR!?fL4^gWV7jOe>B<>;hz#+E!(RXY'
    '-eOvrC3oZBU}a$cf6kl$<5l<@eC!{j=LC-+T&(&0hPt8^<vu8q{BSurhQRW-FaJUFA;f|!Y9qPyPHH2U'
    '%kT(PjGvP2<4UHLvv7}kN~;+&Z(vaFi<~U{4Y(L{WH8e>ek7PL-%~;o7)Y1<Trd=5{?_c?Df3#SF-R=S'
    'mMx$pYEtP*-}wrZQO3`na5DZhB9^>q-v1*pUh4JYmt-lsO$QP<nsOJoUQ0rS-)BjQ=zS2Srppb!-p~qc'
    'j<a>vZUfWKEEf`z#iZnd7RlsbRK<s;7u@2J7F!Yymd35{C4sS%n^MP8tuxsidzc#Q`AP-LEZ;dcs5p$u'
    '3aqdI7x_Zo)>%TY#F!5zK$`YY`kZ7JFP62DudO`2GU_3~^@lmsV<z<s@eM_@_aC;;=pDDYTVTXvyk~V;'
    'f<>yGfkk<NJ_>`eQ}O&gN#Frfb^w-f#(WBqgLEo#y}n;BZ&xBoyqU)tF=5E&bGU^fgx9uRlBsVOX?_r;'
    'E2w2as*jSWb}T!qEwO?bR%L@F)f~<zM_~IrJ^RPyyK`1K?E;8Fc$M#4W~jx;;GB&nD5Zy4v<Q%WX3RTP'
    '3?)WDXtkDI<O6^uFvt!ZrVBYg`VX3#)C?HaTNJ87IFS0;QrI9@SillE${4h2Lju?jI9zF_ta^KZU7szg'
    'h>RbGqQBs=#%J-^(i=VJ#S$DC`J<_ZMtNi9_*a>g`$r`Us4(PYHABep;GA{m6LO#1!xFio%t2lvT`VEL'
    'Iww`IA-rcr2|VS$UxMVFzrC3?g<as_?cMN8n+w|&7k+lz7sVPl7<9bepX=;y$I`8kDK#5{GZOE_q9G;C'
    'nIV`Zm=7eUwSrK1syTt`z62qxY&J7Ud}c|I5%mve7nd}%^y0EXFiZZ9g(c+$!`e{J(zz)+suwRyIdfq|'
    '5Hw3yy0;h2gUzOQ%#PbRK5Z<;;B>xRu6f1a%^*!(hEl@E!6wxm@h;O{Wsbq=2J)Ywc=PlI(#EFv&Y3c6'
    'Iuk#qYeXWg=&ivLP#8W3;O7^3FH7)VZgS<mc5%(Fpe#F-H%=p~xYa=_@}^dMX?aYN_S9!TiLPhCCe82g'
    'qqq1h{sgKSsoect?@A1nx|Z)177`-ZoL}@d!LP&wMFKs<6}{-)pl!gYi~I@_&_HJGq~lCLxZr6p-%#^>'
    '?uIH}2$B{d0w+b9(EnZ$03m4pzj``Jxujp{2iL`GZMhlW0v!-AFcaJy4)`K4^wWUQ$YL|<iQnF^Z->S4'
    'gyl{C2kQ_60T1vhP@X&(e6#yFH`Ra@#v@)MVbF89IW~jBeU#lL>D@F`$QsS*wg!M~zS3D9K=&-|KA6v&'
    'kPRV^Zb<|DsJAPAEC3gz5Ch#+ayNa~>yKrzg1cog2Ex2VRyaj;f>aL}7EUofsbog_V1v{3zn5azZgGsk'
    'V8hbbq;yz(TS+$#$r+i_3xeD-Ys6DlrW?|nV!ng|_X{kqV?tcvMNWCJ=yWw(lw37iEFC`Pwvp@6*F@>_'
    'JA^rY2*_}k3<%L-QFWchaHoM+x7&cY+So+jks>Gkd}SnY#Nsx}8B=7$rWsSpAG0*VMnz@{HD{XVTq#kJ'
    'TR}C5soO`$*Ajlr%~O)$_@ZG!IVo?0%}b$`r{UI()Wae8O$%AOoU%%DZ&OUDGCkAvvpI)~TCW*M#9N!E'
    '<O7EBQBQR+4)|))pT!cqY#Dj&k%S<F<S#5ldW2>>1Tke7nGKIZc?I8I^XNIDXdO+*g7I^FCgp%D*tzkN'
    'wswC@Yy$lZhW?1ms$hkL|3Ek|FpTk!B<&DX%RygmszLeG0=*|rf<8p>!Z+h7i9Uo<K|~WSa0^8+1BwQ~'
    ';vi^|Z-6`&1|6R253?WQ85Xstjk&*k`(QlNaSGW2;tuCIbKYl(g->o4AaQ^(Vb`LacQYm0E_}`O0VX-f'
    'EcyYmKXX84Ch-T|UIl59$HP-UWSO(RVgN<3DuYoBabRCn#MO_gw144Nh3ZkFLqHw1&F`aWRxm}^FcB2M'
    '-vx_T`gOVi6&NW8ZA8J(-p$M>sqsp*mS!qc>IGMjMnNcJ4;Lg?e#I(yN8$XOqxa~yfhe*yNLVQHmWL^$'
    'T)Zk<h%9qZ-vQp|t2E^+7rRp^tv=$nQ&lb&;Rr*T4#6;&Q+mO_&#pp%p`u)B5i@`69YtX2!=Q7Y1NaBH'
    'PYAw|{6}Ia6__-}^_pM_@(HX8>ejA#oWrnKYVsjMcW*ZUa?F=l+<CQl=6MCa%CpI!Y!ftoo__qWgu@0o'
    '%>*+KX0|V?WcFN0h+O2R#1)$>ZJm!g;=v^k3NxzW=1``3q^|i}?B*dH4tVbcmZ?9=Uo$|nSARiwM4W=y'
    'A~=C8gKGh$p24lPc)#giv(zrJ;$9!*i1Q`ZY|cThyBqffKU85c5I_Yp;ib6piD&b{kF-pxJTu80Dj#=2'
    ';@+|bAyt@6rJ2$s!3@!Irr)r7VQM2A9?Z~{Z=Nj%Vzk?+mwQq5&g&(-CW2mkEw76*=LXo8xuFfj9%|_X'
    'afZ|`qQ4V&$1U7!kC$%<J86*4mh-3p9M1sAXMN)K*zy+-a#ocM;s*Kj5t4#N9mI$9iRU17;-hJ~{q#4M'
    '%J%pW-t?~LlX5dDyX6{Z&XtTTr_!|$B%DPPHo48&@TE2r;z-Q!%<4xz!+LA5!PthM$DH7>44Do`7Y8($'
    ')~QgSp|KDnWZ~^9uK;MJ%VXjB!u3s>8PoK--uv5NEmX}7gGFz1w}A{-sIv&;^#~$RE<#^n1E)kOn!)oI'
    'CwC@K6TH(?CW(GPto+q#w&1oTs{2f7*@vlIv!x@WQdS$N+Ne~p20fxQPK$<~T@5@S!_dg{qN%2cliafE'
    'tUqjUwaJG^fM%F350-9c#x4v@LWQP>_fp_0F2x9u@~UlAPiUX2woQ@cr^Y9#YY^XHCEd1Q%&IYDwQa<D'
    'umP*wcvZ&z9%#6djaF=D9%Qttx~uX&lYVXK&JufGt)Yu$`H_UF-Xi#Q_MW!MU`v#m9g(Q<@m^Z_u~7aG'
    '7+`EBC=QayM+x$E*D#=Sx@|<E6?sPNT1MhoTHu<RYg<knm^QNFKsU9((_%M?!@f9vj=6e~hY*VVz}F2e'
    'G#oujkQq3U=D3kzySj(m&<@Pd#Ixy%otT#A<1uyJHq5|u<8<uuPSntM`fRhgMXys_@Fvtl{`TvmpFle!'
    'MG2T7%(xD8Mo%o)L|UXfz8z>7hS2x$-;Qf18gir9GBISKXV_jG#F`#Dv5v8kXuht8T402vLAMluh6lwD'
    'X@;lAZsc0XaU9FiEEJoz?`uX9n~rOGt{Fy1i{seVeaCa+FtiQmS?-&<ACo~p+%A6E;L)x))G#uwO1_3_'
    'XD1Loz936J=$%2Cvsp3=LQDjo@(vjxbTbv~uuuy%u6ys^ot+GZ4c~}@6^-jUrXOlvyU!QKCWvafj#2N2'
    '0OPcJMLRF(Ve9E<63t?U^(SK70e3ybtKKdm652EWfEC*d%px$);~$5;XMgFvTrTImPd)rQt1G^ypUNh?'
    '-wh4|02Hhn%of`v`GnR7n1N$)o!}5!<$hw{LmlpLwm^efJnYp>bl<<fzURk?wPPqfNxJ8HksVoHqQ`;e'
    '`nsmOn0NS5poPBSh6tZ9<QswI7?$tGkr%~&5V-h1zJWg^%9CWeeh>$aWte8-1U5d4Mr=oc?c0&B`G#W}'
    'iD7xjFe6*ThcpO$&rcG~^Nb`)V$Ul*N&6%fhezA)*x!D?gsdwEtzcEW6+_{F`@NmOx|iS*`G#1m3;oLU'
    '|FqjA^8&Ee#WjaI9~ib?ew0TT^(H^PdG$`Hu6}XFAGjW}7WXQq&<c?IsRx=qPYNhD$+aong!Y=*mz}lJ'
    '1fF_60B(f(r<ydQmJwV(CJT9$WuGjFwJA`IB3!Endpt!7Y>qS-=Hk((W(T+}IfBsEbD6fD*U%Q}0N(3s'
    'LE?vwXC{`7#W*iCP0#ZUJ&bMNjFTj`V;v<HvV7f%6I=6<<yf)fU~$jJKWci-{Iu%Qbc2F5R^Bpb5N!_3'
    'fiNT8x2*(WiN;8f5nGO}o1PT~PN;{b;X9^>Ma#hTd?&(l8v#a$p#?!4`Zh*b4G`SSL$r$|n9YgJ6WuJg'
    'DAy6a*S9nSUq+5=!R$U3T^$<>TUa1-O?-v8AkJEL5;(r*SO{MkC^Qq_O8~GSv|NpVvP%>8mM%a#CD!XO'
    '-lmAK_pJIko5=KR3zJXcx|qaJ=o%={@X)pyXr`&fhOhfrcsGMk!@{QJ2gotZ5Lt%iBs$!sWTHmthyB3B'
    '61k40b-aZxrWqTr$U&~}$6kmD+D<&zwqr9!VdUcfcQikaB1gk216C<8ofX%_okOf(bXG8)EiTd!zUWOG'
    'ldfi1VH|~tM^u6^w2&78jYpB4B)W}ES91(E&@E(O1mb5r*KqstNv540za8aoNBK#Qa!Q10B}hz-r)U3|'
    '{_yVg-$69I%1dX}&A<<s*dz-}weJ+}edU920ph{)5LGnL$lu5P4jO7G=P2Z8<e%E_vf+j-Anxb;Z(s?s'
    'xJS*g_ykC7gu|ypp$daVa39&wL|$9*wa4~1!7%4fPbQe}(DJ0drAdJYlqdlG4jQe<6I8TaDPbl}I;g9e'
    'T*Eh;s5sdR&7sU!w5Bsvbun(bit3RStH`}jT*Lk&I)3LuCsef}@*47fSskgY?EuydL9AS174c3{%v|P|'
    'j{#ri8{BVKR~Vywv9Q`ASA5)JRcxY-qMPdLST3Gv`C0KydXYda1JaUBxI(1LnJl=G*3PV)qCq;d@}6$F'
    'wx;FN-0K{b7L$?lgxr^c<`hh}rP8P}6RoK1SjNzWVyJqypY=shtG4oyJK4oX+PY#R>-VwWVim{g9cZJd'
    'W4qhX@3`cnJegRDa94VGR6WS@9fyOfVz4`us8c_x7Q5Q6e5VjdO6xsUwKgd$=cHUj`_-gmGN}OO{(4Wz'
    '`*!e}>|$6N?y2>K-r+8z>?ySewL9$5b}W@U%tgB8I9_B1q3ijH>1(F%>VX#{@W>lpq+>bXbRq|=a*msL'
    'I`Rz!US->f+(a*Thp}~!vtWAA46pk5JE5&hDtwiC!1CivY0dLN$v~{32$`(heYL-u2a5&feuH5Fz_R{8'
    'ARTfW|F9HX#lR`V>XAo1!L>la&YTD5lcSTf*OQBjayt*NP^EOcNc~lmdPE+|4W-Tzt1W-{dbvRPQB+2T'
    'W2~=`Zq&S$U(816u~xA}wSnvEc0oWCdpd^eV1d=ijl#mPU)F55+OnMz#ux(8`Z8ZpG5suwgA}Fv!(lI<'
    'yHR#86<khIM>bv(j04u=6e6^QRKdg5wkgpAVks$Qc*S<<TD2K?B@FX38fOYySbDwldC0$n$mz>NrKN|}'
    'i7e=+(vx+6?@YBBZ_m!d(dlIxWDiVNkC7W2fo_;y<OYsryC|`JBk%&lH9X6T6HQAD(?=F&lTjEYv2HqX'
    'Y}=j}yO<4Tyclj4D!-NT;#RyEd0uSjdV&n(#3<HnSF-}!Gh*MgG|b@bSob~0!0#hn_d+9xV@r!2&2fFt'
    '&_c&b9J@To=jSc`zkTb-c6GxxJonT&nw;ADv1@v!=I@UxeDvwt#*uaEPCVB;bsf(?w%pT+Y1y9H>}}WA'
    'C(g@L%{V?WP2;6z`2G=ooz7k6!EXe4vnk4B8PfM{!=6lZjMHP!K02~7;hap|lT%BY#4|nb*gY}5Q_nr|'
    '@gCWxq3L?VbyQ7J=911{w%n5wL$eIyShHT5j`h+#Iy!cYMlV;wU5%Xk7d0DPP8x82YN=y?wh7?LeSG##'
    'v8a2F5{T4{(Ef}1ccH=k-=Uxpya_R%WF*Q~z!OQOyCx%nC`n$XZYC@=zFW+;%;z+}4Ud_h=kMt5<8mFJ'
    'AV`6X5DnmHJPU>Fa*ZgUe<sxf|5E#A{T^7Sr|yaN(mt_YYSzR&Jvy5B?umW0`yRZ!oy}uFXOs0Lbi>HI'
    'rDX8<)s>!Ywz{g52ctI{q>e{Oi!D9MY&No{YKG8wysFcEU-Nr8+o&XrN1V;pj^>k`%m*LLX4uDP;K;P?'
    '$&q!U*`|MNdoPcS<70hi>^C`;O1diB{w6DHbRsq|&!CAAP|Bkki4eL!Iri;S$Ff~V*Uh7sr$>(O+s6&A'
    'UJ1@-12zyCCNC$)n(m*TOpYeDeRMq0937uuLlPJ!r+Ai=V?#SNjniY(dU<^0yY9>5W&%Ui6t#DLDeX0R'
    'xf1SNfEzQ%2=chCg<j+vv6V!~HC;XQ<HXc-EkLFhYoTSj2Etz^mSq}Peg;Y0jAO%%d_4+HC+V~PecYeO'
    '!%9*s7;)3lPV>R~7vhzKT(R8~8aOI8w@EVl4TixwC|07Tq~sRlh2Z5(r%+3BI_)#BT3SF5zRomCp~dK!'
    '6nPj>;DkQ%@Dp0ZG!>f8DOP2q>!qOaG!Ig0AxM)AX$~yy1`DHYR`VI3D9yzJi!Uexr1AwK_PBUZ6+<GV'
    'kPs?NLjexSILxKpzZMdk==bbgWIq%NNK=3rLdY-_AEewXv0*=7qZMsc!Pd`KK3m|2lK_9(tOBuQ1s#&q'
    'KOtlD3@i!s6d9xr)nTtDLr`pDmdifL=LznWE)S+kSC`w=G%5&cTf9f>)p`b<U*~CAYg!;6w<P#|R0q2{'
    'X{M0gh!Fzy4GGn$3i3nhKLB5dT@@1Zz|Ni)Duz>*EsO0MX@^PUu5*2C@%XHkYF(T_cD%v3ly4u&;bzq`'
    '7TXzdJ~E>VwO~906GczXX9WWjJwvn??i!8pR>Z-4K3IqQgTLMk|4Wh6G`P~9`N6Z~`jcbb5BvYNPksKp'
    '0|O-T!+6AMq(fck%#tMbz}b-68s+IzQbHvetkUXHQPwx>E}X9@o!Oy8B=OLbTq_lMtE#u?9NjE`Wrfpe'
    '1ry-H;v~z}c6KxSS3u2+coxh#!43vblUlTpQ`-IhRG}?*UNdB+mdaIHP*_Sue#}nq$>v8PH&}fV#a>GX'
    'g#yySM_w5}ZP7{&sd(>w2*5BXZ4M+DF0#g~RkugZCf&ik0ofMm1<LLVdF!gTkJ4Thspqc~YG4+3QGJm}'
    'R^nF9cKyZ{54Xg9)yovOyPO>t&UkfD6hG^ed_NW*NjSfIQEc^#Cj%jAlaE|X&pK~ngK4dpGa=OY=iOq8'
    'm?N#s%Fe=sp97Q$hWX;*W1$&NS+mIkJ|y5-bFBhwDya4p4u{>=B~6{ZngtwSay+Q6J4Ed4az?9INtuK^'
    '@ZlQ;_cxzTHnEq_x=W08^Vze!!_t}6zTI6`C^>XX=gG4C^FvpvJ;i~fq5xSDATIWvoLwBh`DubBezy1)'
    'q+hkVQzicLVib%8XIE*qZjq~Uxwi@M&Bfm$?!*EJd&=ZCrR0;TB5jE(`L=;nW>Mo(@F&)w@j>E<grHPi'
    'gdQn{S};(`$FWAef6Zs1qE5>ws~|j$iPbNj@@fWCUcX?V!~uV?mL;dhXjE5FMxkk^B63<|A*-q&qIH_B'
    'qx5jnM}#J`1g|kGc;r~)(6bq?0bP(f4fX3t$u&0qsOJxdV~Q!Us`6~T*`_9rbVttL9Q`;wJ%97h2~R|v'
    'zMOo2_F6RWfEAX!S^eJR^@;da8`hAFATxTnI(P=O%?uyc_+-+hL8TuC&^cbg1*T6Sy>j}`S7$G$FOM!J'
    'p3Q8H<c<FLzn6GMNiH1pslWO=h>>2iMt||u>|pktr;+;pr21vX96;EeWfelT5z!dfdzfN8ZAdE-4e7K5'
    'p^_FY*G8lgo1Dig1qG!1Fq6^Xto4VxspPDIYfc_i=-~ObIc3UtRWLc1{f>lklu!wX%6=oz;ud^DQ7M-r'
    '8B;|{6#m#kr7Ar6C6^Y`OnaXd<K`O(e>Cc0PYi@8<29-lz%2n!rxu~jKzv3tYS!$MHd!x7*kjhT7}&K^'
    '6qM*n9SkqUIi*qXdHFEUJfSuQg^-cmdihaJ#ucIQ#fcR8Gp`x9W^2!)_n7j*3frhBuem=&(TB+x@@-P`'
    'Kt9A@SV$&h7S<wL{B!F9VK*%eNE_LySH^acM!{uKg;QFSD4k6$&DMh@tI`}gS;I^-mogDV`0@}^otDZx'
    '8?|_yp}SEkmTI4~>4(i1UdYWVStUy;Q_WkhJ(n$2fV2u!Ir1pKNiyRvq>`x=|Hfp~5F)zkAqWahltk7S'
    '>mv_1D`i7h_zgNZiD(kwk#xr^7Vvak$#TNq$~jJcyi&#!K!qIEe72J3tf306JWS*HsD}s!VC%Xf(h~V&'
    'ctFM>pG!`w3?x%eGus{qR0Uuee5(D1TD#>ys<wh%kNBm+<tV!jMRA752pXDC)&q2-An7c(Ax%-p8DeP8'
    'ez6nc4)&gk>#Lx*JUm$r)S%*B$6n>+rfP!Nm>*@<t6?s8qM)p2!f7$}Y{y!RL{jZ#)1_2Y!vs{aOci}K'
    '62C+eE0InsOr~Uta<N&N2SY4FX%TZahv3~>E?DU@$z-49t5A0Hf{B07Z76}BvVqiaxL{5_Jj|7TRGDpr'
    'rt~RfX&26gOowS7-867HFUYcOs8S~iMfgSJHlf?BW}zG6eTvaD;Q;qYAuG@{scfhyUzoRZDU39JWH`QW'
    'x~3I5Vc^A<W0<;Q>z*5hT9ia6jPxWiG-O6TW=?V71_s38`aVKN6gvIA3S$~6lIVnv5qowRo00BW$P7In'
    'g{BuH$4~6oH6sXBwnNW#-O$iHgsCBh1PnK{jaYZ(3DV;ML+4UmUSkBEWcWFqp?S>mUG_?(+TL!K*CHsT'
    'VbhLdCUy{*mhb6NfYFBle=Y*tT3YCOVdzC(V0yM^>Q<N-Q5;yYXF9g;Ck8T=VbhUj#zyEmM&L)L>06ec'
    'xV~@T_f6Z;Jq@#J-H&~|laa4EHr}_$u#px8VdT1+ZC2MtBpLCv(+Z`;F_7H&<2qQaP)xisV}br&U>OqF'
    '=p4nEQ@<oq!eOs8vgst)1_RO&<#wBRRi(_Ns)UrrFPnqapzIeNOc+|d6aumER0=o*1Strrlonbk#FwW9'
    'Og>JCAmHEEbuDqj#I<8hj}0%0Ej{*KOk%zUwO&k2GG3HuN#a?45a_<{;9nnB-LJY3-$P6LRh-<)`hLx`'
    '&zhDAtX^M!<E!hPRjjHl2C-XZo>u7aF~ylIgj_4q5)JbzJBl1V@Z7-Cbj-~(Eyh&r89s8%*l{pB3-GOB'
    'YKCJWD~gdFBw>qnksKEVx@#MrV@6JZp~2T4B(}IVseojL7$C#K=m|{C3_{Cy49tAJ$hLgnwj9(-ohaQ+'
    '0^f+-&<k{o1XJ_f2(KSsf>CT5n(aDaXzBQl^dil2@Qy^bjv@9j?h-A~;>JbK@MZ3Jy5?zyYZ(ZWo0sUm'
    '>jfdcWc4_7HB5tvrI~(!3Bzy<%Qi7!ae_(D(mc!VE6BdQIM_G3|3>%S(!ETMjmv~J3j8Q5&(&Tah%z_z'
    'A+U7<nkvV#m5`OvLQA_xuqg92cME7KDPq*XJ5)v>EqaTTQ|w$eY4^2szm)zXTuC(q^eDHOYU~}oWQvkf'
    '6^7bft}ul~H&>>o-V;-(uh)U=NX{8=)sa+EC~jwaXlW@Xxv@{t^r@@?^4RJ7?OJC`>Y&tS1pM5zX%K#}'
    'vSwr}*#SyQZMcTUfnCLwbh41Ls%1^1)gHYw?L@9Aw`BKqG~6Beh?MSCYfDpcZFOu`O~h4`fU6wi&f>31'
    'aok3Tn2f!40>&!HyX|ssyVQH@w&2?rS-VeJ@@>c3eUC2s_W3LS;YU9yeFgVTY62P=iEzBulL{1u{dy_`'
    '8lSr|V0&d8CxzmHZfNT-c%8s!ynLWR3Ij>LL=-<^`M@$(U0Fj=9$mG=UDpr<WcHr4W~5SbEorb=DT7KX'
    'WmaDM^>UF$j69ETK_v{f#e&-<_i!^n+J>WmYmu5b39x>xENYV1B)`9AIpxwTyC#-D$m`rij(N_+baZ_A'
    '=Da*(H=htHf}c;|%?C6+IGJ6Xq??TPTASw=lGZL_;&bG-XVlSNR=b*nT2F1?Au*|Oe!JRXS(4-~-lq>s'
    'c5iHf&81jIN)V)Ipfm{R8I2as;0y0o!Dge%vMh1eD(u!Jc-kf35(8Y7ZCM&5T%BjB25g69%SWv&AD*8c'
    '<;=A}90?mvf0@B}oR85`O6N^d4OMYBrJ05$hR0p!X^=Zvp3_)=?RJvb*qrt4U_B9eUx#^(JMzAU$&F2F'
    'Z+xcoMiH+M$Z@O*?)%~s9ZR|4!%`eYY(5~*vHHM%OLqL0?ARdLQRbApWIR?~(WUa)L((6csgSH5u`&^o'
    'We$<!%S~iV&me*T)VX18T{y6o!2|*>pcUF^Nw^^kf-vtHX47{!^V#ATV%9nlkGK#H4mO^k$DU+(W>6mX'
    '8Z_bJFMv;1Mv0*B(*cJ}#g@`2i=0e$4U6wkNl-ElG}Ckyk^M~1#oIs)IBd-_CzRsXdFKTP+q#!BN}33o'
    '<mNx@2|Wx7>>aia9+S3?NZb5d_*eW2Q|@y9EB*?8<fXBv+a=kz?API_5WdMZ&ruIAI9O3kut{@=QL^Z&'
    'ay!zN6g+*SMpkE_7jpD?)39_rvCz$4BY}hrF>I$YlrWZB93lI_M2hrsDrV`VNmnY9ilSf?O|cX4kg1z0'
    'a;MKXu<g9UXEC?8nHDHD%cCraa~=lQbd*X0)v`+pw<ITB%c#tTI%F%x5Kj2KB8;gV!dQ0tCIh+Ot$l+6'
    'SCH{VEtoyh*jn*t*p|OgQ9QSA!jt(V&SsW5!K|Xr1g^^GR_d5TrS=J`T~#V@h1rwoj_ON2B_1U#*QLPJ'
    '<SD<I6Al+~Br=|+gc7ZH08LPmi@-I`?rs1c&#J;&WPBT?Fsj37N+OOGsf~}$MU=U}>Z&=eSXD*J;BEm{'
    '6bCtA<lMy~WR<L$r&9`(6(z)7KoqXC^m?fhV8!ci7iN&@!*Wqe+3LtqRbzToNn?2l7c-wN7oZwMJkD-z'
    'Znr^*?>H=n7Ycn;g=*Fo)2Pwwt14>9VZhX0$ANp1kN4$9)hI$MED^%;H=Mr550-Bmx~O*H>Z|4Iaa^6r'
    'iE2vYnd4bCk4LhjN2CeYX8P99Mp?}SNo!P8`fQd0ypu1xCJ&etc<;SOi(3pz&Wq2KN?rnn<^S>yfSG5X'
    '$l&c~0;}|f#_7PdET}RkxOq9oG%*+pnww>W@BALLz9ww}m};)b2QJknL85b#z)fP^3vEr)V$-wC#ENWB'
    '^J5!Yw7ZEGT3Q@yp&43w5c{TSdu9+ghOOC#fvo<XQUrvdBg6Im$T3kId3Y?>Ol)7n)7oKZB4kIlAG)?1'
    'S$Z5>acCJHav=T1L7MNIPNMUn3)#OHWa;1E&SG@QMCuEc^v4o^>5Gp@`4wg^P4G-yKeWxrOSB-gP=r?z'
    '7<y#HhM6EI&?7h0HA{<Z&G9e>ozRJN%{QYs3eCib>`<BDsUh8pBG-vr!_u87(QPB~Pz){cOwTlIJv1Cw'
    '_wl#B?FG6QB%13X&%@i6B$2JxC;Ni5IG7TKfUsNuO>9qQ8=9(fPPoMTVP(S+{>|Th3}%ZXW)NyPCgf5|'
    'n^TJ2Rx(`+-2g))3<JxxeaCf?rujPNJoqIyi7ZF+9mCT?-wq-?BJwRvv##aofnnLM79^o*KRkW5CfRkT'
    '9NJp?-zD$02C!_y9@hu5Fh=Rdx6-jOzwxGzS(@g?T42Vei7YKK49uGn&vt^y^`PIRj;Y5(0j8(KiX%*C'
    'v1xe@K7Apkit>#YOFA<<)_AiG)>|4f($5;YoY9Z{At+1({LFh|L+DdOa-ZnsCEEs#zUkQHjocRggkNV{'
    '24QNY#MCaRDMV$YhQ+5(6`+nvU+gQI;0R;9h0gH!nmZ@J2rY1`hCIgGB@S}DT&^)&3NZI#FW(c~iS%Ab'
    '^R7L3ZQTmHWxBS)Dj$*Q3LOArWZ}7E6ep2uIl5&dH}E}3Hco;VU;ln&JCImw8&=>rnEwWDtj8WgMi8}_'
    '>1tz<!b&VH#EZq8+%&N8kwnO`Y<ySRcHk#YplKwrRWmTqHs<gahCGRVj5616CDYYIE|zC7FT(%9a*XR@'
    '8o)wR5=NMJC0KNdO^hKE-$agWg~$smKMrkVMFs}Va{R^_-k4(iFg6k9USSkKVsGMOSvo?A?}Z79^)Ruu'
    '*w%IAhOv&n#TQ=?V!RlErYE){mAsOPx51pH)0N96|8~5-9j~W2UYrISrI4$#Ihil4Q58pWZz}UPcdgpU'
    ')zU&4#FFskR-xWk32={vSrz>)71-RRUZyfvvz>CCa%g@d1eRo)H;<F7u1L^Q+@vyt{J}7G1!7fkf|epZ'
    'A5^A575G_Rq@Y0@XtQK;zM!)o-@cmsIC*`^LTmC70yX}&T;5n2E7|WlB418Ss^Jb_QdV=*=<vs+HaGD4'
    'K02v+hjn~Snay<ptSzNCKYWMUT}v1F%*yD>9N$pq2sce?ZYdm8!tKt%p(TXfJnyQUi#*E7l}p=I`n;4<'
    '&yFrU)t&XQ#doy!(xumlShcZ^Wm48TdImJcvVTPnG0W>>HPm?wBv`y5HkM)@0wN$uxU{NIAri8Zh#nak'
    'sm%YDVgi*gHi!`{O_MLi43?K*c}NUlZmiux3Tu<|TL>{M&ABgx92Q~<)dWKe)zn9|J|s(aw~$ih(yBus'
    'l}l<E5~+N5mk`OHb1{-Xi$Ri==xRS`GIw{%F_cQgR>f3S0$+@=EYla7M_1;-XT;B9EtT+NTARiAmd&Cq'
    'nQ1Xg7+FHlA%j!7+noyi{f<K><;i|#A(TIhF_fxTtGU#JVk-0dv)^rurE<DQ#9UT_-*yaUHSoK}WU5)_'
    'Lt->@G|@0*^U<p*hHxsE^spGJT1BtD5YI|PJRsz=^qOxy1higgc|=HP6Z(8;h-klDi7AU1eFW<(k032s'
    'qZCnEV+`F@o9K6tNTswd)@TzQDii%(v#wO|@0NsBRkZUF3a=tXs|t-RXKcwv(CT_HRjS(qHMi!9TZ?+z'
    '<J7h%(AxU#<%uaNZWo>D5h_!s8q-rMOx60*uIkc$=NW0al548`G}Rg&ovv23&^EKzRKR!X*LX@*O|7XZ'
    'v)!r~QyYrf)9Pt0t7%WErM0T0wWOmxP(^EBLu*e#dpiBBW%caIw6iXiv(9w0hp1*<Xl6>q>`SOQ+`Q84'
    'Q<R$hGHVhWpT8#YPGzLO;QGa*UM~HqQ9)z#_g~Q1{E7-1Ke#$|vDC3;JhzQvtz+{u*E%k$!j)Byl^ZS1'
    ')peC)g2&#MS^&E;0I=;U$DNlhR$BJTiWakncP&@EOD^maR4Hy8l}TajtTHhjzMGoF72)$=NHt=*`p;5_'
    'xZVrBa~<M5skB~!xKVMT#<hoQ!h(x&;rIwYsOoTokm~w+!`vA6;CjQXU~hiaJCy1zAnfUj^yXyECS`Nw'
    '9Qo36xrJQ(=3_S~#;eRtZa#yY&+>qhzg3r3H^qJ%^Oqgsi}`)oS()F)4Cd=E@Jn&|fYQFDKEyA+sBiO#'
    'a*CV>RO&4|XWwe{eyh>jphj;|A*ip;tG<;>C76fQ<*n0?a`no1RC+L<%W))WR66YeECi*COBTb@A5oB('
    'mVBuz#amr;wp>`MC^x%;QWYFtYDgeo6*v>Hcz~YAqmUQ=M4r7mz&g|Qa43f>0BHF8j3RYPk>nMiL|s{m'
    '_JR&T_}OwnZEc*z)zzN;0&C|sguFh4JtY9J3{2%6m12Vm^d`MjL`mUiiW_O6#pfC$tk*wVkbq_RbfsYj'
    '1SNg3q;r0v91b2BcrQ=e|6f*RIEVCB>I>JzzULKeDe65J=DzoUu=Y;v2TxMxR~e&TQ`)n_Y_WTV-<*Ov'
    '%qgvPRegiBPT9`&d~-8jE2e%}k=z_iwbgqInzRVYV=MMjU`lHB=Jp9cPh@ajTVYD+E1glPnAbxl?^r5e'
    '5E)La<dAWMYE0#<0@uR_!c~H?B4A1rE`zPqR;7ehh&L!%OT}X3l4{rW^+B=pT3n360H+QgDHQbiGKw`b'
    '6L8})%{9iv#};Uoz}cZRb17J*Q5^-nWtVcydFzF;5VNRMRMa~b4BY(j>U7|pc|5Q2n+vLMR@=7$-Bv-~'
    'sJ5>(Kt0=RcAzV&1`G2IYXZ|{Odcr(-gt?%Nr4em+0QGBbT<pkZ>>BxhN<21+@)x2uP`^;(2Xo_j`te*'
    'QFpDZ{os?9V-zi(wH7L9cPpN76f_r48pHGGbKiti8_EF>tP|ca4&;Fq!fDV(qY~j}S0%z_^GM_3;1#T|'
    'vMhL$zM*xf|A6Kzv>qsU>*Tl95}#YblQy&8dUJdp*O<-nWwD?!q5uPn4TKyvLMU|T6wUO(yA|4S$HN5?'
    '9bN}FXtTmfXNAF0(Pz6sCRxGE*pNw97vn1ESOrO3(!X}<S6zHxFn?HSOcFz_WNrEwENHmZr#^QcoSa=='
    '^uZi^axyvLY!$wca0XvYetPrjonYF($bFf;Dwdn>-)EbXv*JQ~aANA*Y{3G%p$?*PxQy=v|5MVN;e)x^'
    '28#%cdokVyc;N^i*Y^u*&jW)I{4(AKYb^DPhNIlO{0ZVIgJFQMgxiCfzitrmd`ORvXR-7YhKoFi;ip(V'
    '*eeSwBhNASKE(sZ(K(MX5n{?zJ4fYu7-CqMfDU#AKazAZydHJ{rwIQ>SFDhvA#jYoOE5*@CuYm^Uao;E'
    'C#K~N>EKU)V#Dw4m3yG}6b`7p{||zp_#^'
)
# CATEGORY_ROAM_FROZEN_SOURCE_END

if __name__ == '__main__':
    unittest.main()
