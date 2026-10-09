import SwiftUI

@MainActor final class MerchantBusinessViewModel: ObservableObject {
    let coordinator: MerchantBusinessCoordinator
    @Published private(set) var revision = 0
    @Published var listFilters = MerchantBusinessListFilters()
    private(set) var aftercareLoadedPages: MerchantAftercareLoadedPages?
    private(set) var aftercareLoadFailureKey: String?
    private(set) var reviewLoadedPages: MerchantReviewLoadedPages?
    private var loadGeneration = 0
    private var filterScope: MerchantBusinessScope?
    private var filterMerchantID: Int?
    init(reader: any MerchantBusinessReading, journal: any MerchantBusinessIntentStore) { coordinator = .init(reader: reader, journal: journal) }
    func load(_ query: MerchantBusinessQuery) async { await load(query, appendAftercare: false) }
    func loadMoreAftercare() async {
        guard !coordinator.isBusy, let snapshot = coordinator.snapshot, let pages = aftercareLoadedPages else { return }
        guard coordinator.isCurrent,
              pages.matches(scope: coordinator.reader.scope, authorizationGeneration: coordinator.reader.authorizationGeneration, access: snapshot.access) else {
            invalidate(); aftercareLoadFailureKey = "merchant.business.stale"; revision += 1; return
        }
        guard pages.hasMore, snapshot.document.query == .aftercare(pages.bucket, page: pages.page) else { return }
        await load(.aftercare(pages.bucket, page: pages.page + 1), appendAftercare: true)
    }
    func loadMoreReviews() async {
        guard !coordinator.isBusy, let snapshot = coordinator.snapshot, let pages = reviewLoadedPages else { return }
        guard coordinator.isCurrent,
              pages.matches(scope: coordinator.reader.scope, authorizationGeneration: coordinator.reader.authorizationGeneration, access: snapshot.access) else {
            invalidate(); aftercareLoadFailureKey = "merchant.business.stale"; revision += 1; return
        }
        guard pages.hasMore, snapshot.document.query == .reviews(page: pages.page) else { return }
        await load(.reviews(page: pages.page + 1), appendAftercare: false, appendReviews: true)
    }
    func reviewSourcePage(for row: MerchantBusinessRecord) -> MerchantReviewSourcePage? {
        guard coordinator.isCurrent, let snapshot = coordinator.snapshot, let pages = reviewLoadedPages,
              pages.matches(scope: coordinator.reader.scope, authorizationGeneration: coordinator.reader.authorizationGeneration, access: snapshot.access) else { return nil }
        return pages.sourcePage(for: row)
    }
    private func load(_ requested: MerchantBusinessQuery, appendAftercare: Bool, appendReviews: Bool = false) async {
        // A refresh always starts a fresh page-one generation. No old rows survive
        // a refresh, failed replacement, bucket/context change or dismissal.
        let query: MerchantBusinessQuery
        if case .aftercare = requested, !appendAftercare { query = requested.paged(1) }
        else { query = requested }
        if filterScope != coordinator.reader.scope { listFilters = .init(); filterMerchantID = nil }
        filterScope = coordinator.reader.scope
        if !appendAftercare { aftercareLoadedPages = nil }
        if !appendReviews { reviewLoadedPages = nil }
        aftercareLoadFailureKey = nil
        loadGeneration += 1
        let generation = loadGeneration, scope = coordinator.reader.scope, authorization = coordinator.reader.authorizationGeneration
        revision += 1; await coordinator.load(query)
        guard generation == loadGeneration else { return }
        defer { revision += 1 }
        guard !Task.isCancelled, scope == coordinator.reader.scope, authorization == coordinator.reader.authorizationGeneration else {
            aftercareLoadedPages = nil; reviewLoadedPages = nil; coordinator.invalidate(); return
        }
        guard coordinator.isCurrent, let snapshot = coordinator.snapshot, snapshot.document.query == query, coordinator.failureKey == nil else {
            aftercareLoadedPages = nil; reviewLoadedPages = nil; return
        }
        let currentMerchant = snapshot.access.merchantID
        if let filterMerchantID, filterMerchantID != currentMerchant { listFilters = .init() }
        filterMerchantID = currentMerchant
        if case .reviews(let page) = query, let scope {
            do {
                if appendReviews {
                    guard var pages = reviewLoadedPages else { throw MerchantBusinessFailure.stale }
                    try pages.append(snapshot, scope: scope, authorizationGeneration: authorization)
                    reviewLoadedPages = pages
                } else if page == 1 {
                    reviewLoadedPages = try .init(snapshot: snapshot, scope: scope, authorizationGeneration: authorization)
                }
            } catch {
                reviewLoadedPages = nil; coordinator.invalidate(); aftercareLoadFailureKey = "merchant.business.stale"
            }
        }
        if case .aftercare = query, let scope {
            do {
                if appendAftercare {
                    guard var pages = aftercareLoadedPages else { throw MerchantBusinessFailure.stale }
                    try pages.append(snapshot, scope: scope, authorizationGeneration: authorization)
                    aftercareLoadedPages = pages
                } else {
                    aftercareLoadedPages = try .init(snapshot: snapshot, scope: scope, authorizationGeneration: authorization)
                }
            } catch {
                aftercareLoadedPages = nil; coordinator.invalidate(); aftercareLoadFailureKey = "merchant.business.stale"
            }
        }
    }
    func unfilteredRows(in section: MerchantBusinessSection, query: MerchantBusinessQuery) -> [MerchantBusinessRecord] {
        if case .reviews = query, let pages = reviewLoadedPages {
            guard coordinator.isCurrent, let snapshot = coordinator.snapshot,
                  pages.matches(scope: coordinator.reader.scope, authorizationGeneration: coordinator.reader.authorizationGeneration, access: snapshot.access) else { return [] }
            return pages.rows
        }
        guard case .aftercare(let bucket, _) = query else { return section.rows }
        guard coordinator.isCurrent, let snapshot = coordinator.snapshot, let pages = aftercareLoadedPages,
              pages.bucket == bucket,
              pages.matches(scope: coordinator.reader.scope, authorizationGeneration: coordinator.reader.authorizationGeneration, access: snapshot.access) else { return [] }
        return pages.rows
    }
    func visibleRows(in section: MerchantBusinessSection, query: MerchantBusinessQuery) -> [MerchantBusinessRecord] {
        guard let presentation = try? MerchantBusinessSection(section.id, rows: unfilteredRows(in: section, query: query)) else { return [] }
        return listFilters.rows(in: presentation, query: query)
    }
    func prepare(_ mutation: MerchantBusinessMutation) { coordinator.prepare(mutation); revision += 1 }
    func cancel() { coordinator.cancelConfirmation(); revision += 1 }
    func confirm(_ review: MerchantBusinessConfirmation) async { revision += 1; await coordinator.confirm(review); revision += 1 }
    func invalidate() {
        loadGeneration += 1; aftercareLoadedPages = nil; reviewLoadedPages = nil; aftercareLoadFailureKey = nil
        coordinator.invalidate(); listFilters = .init(); filterScope = nil; filterMerchantID = nil; revision += 1
    }
}

@MainActor struct MerchantBusinessHomeView: View {
    @Environment(\.nativeVerificationDestination) private var nativeVerificationDestination
    let reader: any MerchantBusinessReading
    let journal: any MerchantBusinessIntentStore
    @StateObject private var accessModel = MerchantBusinessAccessModel()
    @State private var appearance = MerchantBusinessAccessAppearance()
    private var accessKey: MerchantBusinessAccessLoadKey { .init(reader: reader) }
    private let destinations: [MerchantBusinessQuery] = [.customers(.init()), .aftercare(.pending, page: 1), .reviews(page: 1), .overview,
        .redemptions(filter: "all", page: 1), .entries(source: "all", page: 1), .batches(page: 1), .verificationRecords, .operators]
    var body: some View {
        let visibleAppearance = appearance
        let renderedKey = accessKey
        let queuedRequest = accessModel.request
        List {
            if reader.isOfflineExample { Text("merchant.business.synthetic").foregroundStyle(.secondary).accessibilityIdentifier("merchant.business.synthetic") }
            Text("merchant.business.boundary").font(.footnote).foregroundStyle(.secondary)
            if let access = accessModel.access(for: reader) {
                Section {
                    Text(access.name ?? "#\(access.merchantID)").font(.title3.bold())
                    Text(LocalizedStringKey("merchant.business.role." + String(access.role)))
                }
                Section("merchant.business.workspace") {
                    ForEach(destinations, id: \.self) { query in
                        if (try? access.require(query.permissions)) != nil {
                            NavigationLink(value: MerchantBusinessHomeRoute(target: .query(query), reader: reader, journal: journal)) { Label(LocalizedStringKey(query.titleKey), systemImage: symbol(query)) }
                            .accessibilityIdentifier("merchant.business.open.\(query.titleKey.split(separator: ".").last ?? "page")")
                        }
                    }
                    if access.allows("merchant:verify") {
                        NavigationLink(value: MerchantBusinessHomeRoute(target: .scan, reader: reader, journal: journal)) {
                            Label("merchant.business.scan", systemImage: "qrcode.viewfinder")
                        }
                            .accessibilityIdentifier("merchant.business.open.scan")
                        NavigationLink(value: MerchantBusinessHomeRoute(target: .cityNode, reader: reader, journal: journal)) {
                            Label("merchant.cityRedeem.title", systemImage: "qrcode")
                        }.accessibilityIdentifier("merchant.cityRedeem.entry")
                    }
                }
            } else if accessModel.isLoading(for: reader) { ProgressView("merchant.checkingAccess") }
            if let issue = accessModel.issue(for: reader) { Text(LocalizedStringKey(issue)).foregroundStyle(.secondary) }
            Button("merchant.refreshAccess") {
                accessModel.refresh(reader: reader, appearance: visibleAppearance, context: renderedKey)
            }.disabled(accessModel.isLoading(for: reader))
        }
        .appNavigationTitle("merchant.business.title")
        // The destination host remains outside the access-dependent rows. Clearing
        // Home on push does not remove a destination already on the navigation stack.
        .navigationDestination(for: MerchantBusinessHomeRoute.self) { route in
            if route.isCurrent(reader: reader, journal: journal) {
                switch route.target {
                case .query(let query): MerchantBusinessPage(reader: route.reader, journal: route.journal, query: query)
                case .scan:
                    if let nativeVerificationDestination { nativeVerificationDestination() }
                    else { MerchantScanPreviewView() }
                case .cityNode: CityNodeRedeemView(reader: route.reader, journal: route.journal)
                }
            } else { Text("merchant.business.stale") }
        }
        .task(id: queuedRequest?.id) {
            if let queuedRequest { await accessModel.load(reader: reader, request: queuedRequest) }
        }
        .onAppear {
            guard appearance === visibleAppearance else { return }
            accessModel.begin(reader: reader, appearance: visibleAppearance)
        }
        .onChange(of: accessKey) { _, newKey in
            guard appearance === visibleAppearance, newKey == renderedKey,
                  newKey == MerchantBusinessAccessLoadKey(reader: reader),
                  accessModel.isActive(appearance: visibleAppearance) else { return }
            accessModel.end(appearance: visibleAppearance)
            let replacement = MerchantBusinessAccessAppearance()
            appearance = replacement
            accessModel.begin(reader: reader, appearance: replacement)
        }
        .onDisappear {
            accessModel.end(appearance: visibleAppearance)
            if appearance === visibleAppearance { appearance = MerchantBusinessAccessAppearance() }
        }
        .refreshable {
            accessModel.refresh(reader: reader, appearance: visibleAppearance, context: renderedKey)
        }
    }
    private func symbol(_ query: MerchantBusinessQuery) -> String {
        switch query {
        case .customers: return "person.2"; case .aftercare: return "arrow.uturn.backward.circle"
        case .reviews: return "star.bubble"; case .overview, .entries, .batches: return "chart.bar.doc.horizontal"
        case .operators: return "person.badge.key"; default: return "list.bullet.rectangle"
        }
    }
}

@MainActor struct MerchantBusinessPage: View {
    let reader: any MerchantBusinessReading
    let journal: any MerchantBusinessIntentStore
    @State private var query: MerchantBusinessQuery
    @StateObject private var model: MerchantBusinessViewModel
    @State private var keyword = ""
    @FocusState private var aftercareSearchFocused: Bool
    @State private var segment = "all"
    @State private var sourceType = 0
    @State private var sourceStart = ""
    @State private var sourceEnd = ""
    @State private var tagID = 0
    @State private var editor: MerchantBusinessEditorContext?
    @State private var selection: Set<Int> = []
    @State private var pendingMutation: MerchantBusinessMutation?
    @State private var reviewSourceDestination: MerchantReviewSourcePage?
    private let reviewSource: MerchantReviewSourcePage?
    init(reader: any MerchantBusinessReading, journal: any MerchantBusinessIntentStore, query: MerchantBusinessQuery, reviewSource: MerchantReviewSourcePage? = nil) {
        self.reader = reader; self.journal = journal; self.reviewSource = reviewSource
        _query = State(initialValue: query); _model = StateObject(wrappedValue: .init(reader: reader, journal: journal))
        if case .customers(let filter) = query {
            _keyword = State(initialValue: filter.keyword); _segment = State(initialValue: filter.segment)
            _sourceType = State(initialValue: filter.sourceType ?? 0); _tagID = State(initialValue: filter.tagID ?? 0)
            _sourceStart = State(initialValue: filter.sourceStart ?? ""); _sourceEnd = State(initialValue: filter.sourceEnd ?? "")
        }
    }
    private var state: MerchantBusinessCoordinator { model.coordinator }
    var body: some View {
        List {
            if reader.isOfflineExample { Text("merchant.business.synthetic").font(.footnote).foregroundStyle(.secondary) }
            filters
            if state.isBusy { ProgressView("merchant.loading").accessibilityIdentifier("merchant.business.loading") }
            if let key = model.aftercareLoadFailureKey ?? state.failureKey {
                Section { Text(LocalizedStringKey(key)).accessibilityIdentifier("merchant.business.error")
                    if case .rejected(_, let message) = state.failure, let message { Text(message).foregroundStyle(.secondary) }
                }
            }
            if state.isLocked { Text("merchant.business.unknownResult").accessibilityIdentifier("merchant.business.locked") }
            if let receipt = state.receipt {
                Section("merchant.business.receipt") {
                    Text(reader.isOfflineExample ? "merchant.business.syntheticSaved" : "merchant.business.productionSaved")
                    if let message = receipt.message { Text(message) }
                    if case .refund = query { Text(receipt.refundActuallyConfirmed ? "merchant.business.platformRefunded" : "merchant.business.opinionOnly") }
                    Button("action.retry") { Task { await reload() } }
                }
            }
            if let snapshot = state.snapshot, state.isCurrent {
                if sourcePageMatches(snapshot) {
                if reviewSource != nil {
                    Text("merchant.business.reviews.sourcePageNotice").font(.footnote).foregroundStyle(.secondary)
                    if !snapshot.document.rows.contains(where: { $0.id == reviewSource?.reviewID }) {
                        Text("merchant.business.reviews.sourcePageMissing").accessibilityIdentifier("merchant.business.reviews.sourcePageMissing")
                    }
                }
                summary(snapshot.document)
                if let recovery = MerchantCustomerEmptyRecovery(document: snapshot.document) {
                    let draftMatches = recovery.matchesDraft(keyword: keyword, segment: segment, sourceType: sourceType,
                                                             tagID: tagID, sourceStart: sourceStart, sourceEnd: sourceEnd)
                    MerchantCustomerEmptyRecoverySection(recovery: recovery, canApply: !state.isBusy && state.failureKey == nil && query == snapshot.document.query && draftMatches,
                                                         hasUnsubmittedFilters: !draftMatches) {
                        guard state.isCurrent, !state.isBusy, state.failureKey == nil, state.snapshot == snapshot,
                              query == snapshot.document.query,
                              recovery.matchesDraft(keyword: keyword, segment: segment, sourceType: sourceType,
                                                    tagID: tagID, sourceStart: sourceStart, sourceEnd: sourceEnd),
                              let next = recovery.recoveredQuery else { return }
                        keyword = next.keyword; segment = next.segment
                        sourceType = next.sourceType ?? 0; tagID = next.tagID ?? 0
                        sourceStart = next.sourceStart ?? ""; sourceEnd = next.sourceEnd ?? ""
                        query = .customers(next); selection = []
                        Task { await reload() }
                    }
                } else if query != .operators, snapshot.document.sections.allSatisfy({ model.unfilteredRows(in: $0, query: snapshot.document.query).isEmpty }) && (snapshot.document.summary.isEmpty || isLocalList) {
                    Text("merchant.business.empty").foregroundStyle(.secondary).accessibilityIdentifier("merchant.business.empty")
                } else if model.listFilters.isActive(for: snapshot.document.query), snapshot.document.sections.allSatisfy({ visibleRows($0, in: snapshot.document).isEmpty }) {
                    Text(LocalizedStringKey(isAftercare ? "merchant.business.aftercare.noMatches" : "merchant.business.list.noMatches")).foregroundStyle(.secondary).accessibilityIdentifier("merchant.business.list.noMatches")
                }
                if query == .operators {
                    if let roster = try? MerchantOperatorRoster(document: snapshot.document) {
                        MerchantOperatorRosterSections(roster: roster, access: snapshot.access) { row in
                            rowView(row, access: snapshot.access)
                        }
                    } else { Text("merchant.operatorRoster.unavailable").foregroundStyle(.secondary) }
                } else if case .customer = query, let detail = snapshot.document.customerDetail {
                    MerchantCustomerDetailSections(detail: detail, access: snapshot.access) { row in
                        rowActions(row, access: snapshot.access)
                    }
                } else if let progress = snapshot.document.aftercareProgress {
                    MerchantAftercareProgressView(progress: progress)
                    if let refund = snapshot.document.rows.first(where: { $0.kind == .refund }) {
                        Section { rowActions(refund, access: snapshot.access) }
                    }
                } else {
                    ForEach(snapshot.document.sections) { section in
                        let rows = visibleRows(section, in: snapshot.document)
                        if !rows.isEmpty {
                            Section(LocalizedStringKey("merchant.business.section." + String(section.id))) {
                                ForEach(rows) { row in
                                    rowView(row, access: snapshot.access)
                                }
                            }
                        }
                    }
                }
                pageActions(snapshot)
                if reviewSource == nil, case .reviews = query, let pages = model.reviewLoadedPages, pages.hasMore {
                    Button("merchant.business.reviews.loadMore") { Task { await model.loadMoreReviews() } }
                        .disabled(state.isBusy).accessibilityIdentifier("merchant.business.reviews.loadMore")
                }
                if isAftercare {
                    if snapshot.document.hasMore {
                        Button("merchant.business.aftercare.loadMore") { Task { await model.loadMoreAftercare() } }
                            .disabled(state.isBusy).accessibilityIdentifier("merchant.business.aftercare.loadMore")
                    }
                } else if reviewSource == nil, (model.reviewLoadedPages?.page ?? 1) == 1, snapshot.document.hasMore || query.page > 1 {
                    Section {
                        HStack {
                            Button("merchant.business.previous") { movePage(query.page - 1) }.disabled(query.page <= 1)
                                .accessibilityIdentifier("merchant.business.previous")
                            Spacer()
                            Text("\(query.page)").monospacedDigit().accessibilityLabel(Text("merchant.business.page"))
                            Spacer()
                            Button("merchant.business.next") { movePage(query.page + 1) }.disabled(!snapshot.document.hasMore)
                                .accessibilityIdentifier("merchant.business.next")
                        }
                    }
                }
            }
            }
            if reviewSource != nil, let snapshot = state.snapshot, !sourcePageMatches(snapshot) {
                Text("merchant.business.stale").accessibilityIdentifier("merchant.business.reviews.sourcePageStale")
            }
            if !state.isBusy { Button("merchant.business.refresh") { Task { await reload() } }.accessibilityIdentifier("merchant.business.refresh") }
        }
        .appNavigationTitle(key: query.titleKey)
        .task(id: reader.scope) { await reload() }
        .refreshable { await reload() }
        .sheet(item: $editor, onDismiss: { if let mutation = pendingMutation { pendingMutation = nil; if sourcePageCanPrepare(mutation) { model.prepare(mutation) } } }) { context in
            MerchantBusinessEditor(context: context, snapshot: state.snapshot, onReview: { mutation in
                guard sourcePageCanPrepare(mutation) else { pendingMutation = nil; editor = nil; return }
                pendingMutation = mutation; editor = nil
            })
        }
        .sheet(item: Binding(get: { state.confirmation }, set: { if $0 == nil { model.cancel() } })) { review in
            MerchantBusinessReviewSheet(review: review, canExecute: reader.canExecute(review.mutation, merchantID: review.baseline.access.merchantID), isSynthetic: reader.isOfflineExample, busy: state.isBusy,
                issue: state.failureKey, cancel: model.cancel, confirm: { Task { await model.confirm(review) } })
        }
        .sheet(item: $reviewSourceDestination) { destination in
            NavigationStack {
                MerchantBusinessPage(reader: reader, journal: journal, query: destination.query, reviewSource: destination)
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button("action.close") { reviewSourceDestination = nil }
                    } }
            }
        }
        .onChange(of: reader.scope) { _, _ in editor = nil; pendingMutation = nil; reviewSourceDestination = nil; selection = []; model.invalidate() }
        .onChange(of: reader.authorizationGeneration) { _, _ in editor = nil; pendingMutation = nil; reviewSourceDestination = nil; selection = []; model.invalidate() }
        .onDisappear { editor = nil; pendingMutation = nil; model.invalidate() }
    }
    @ViewBuilder private var filters: some View {
        if case .customers = query {
            Section("merchant.business.filters") {
                TextField("merchant.business.search", text: $keyword).submitLabel(.search).onSubmit(applyCustomerFilter)
                    .accessibilityIdentifier("merchant.business.keyword")
                Picker("merchant.business.segment", selection: $segment) {
                    ForEach(["all", "repeat", "new", "noted"], id: \.self) { Text(LocalizedStringKey("merchant.business.segment." + String($0))).tag($0) }
                }.accessibilityIdentifier("merchant.business.segment")
                Picker("merchant.business.sourceType", selection: $sourceType) {
                    Text("merchant.business.segment.all").tag(0)
                    Text("merchant.business.state.TOPIC").tag(1)
                    Text("merchant.business.state.ACTIVITY").tag(2)
                }
                Picker("merchant.business.tag", selection: $tagID) {
                    Text("merchant.business.segment.all").tag(0)
                    ForEach(availableTags, id: \.self) { id in Text(tagName(id)).tag(id) }
                }
                TextField("merchant.business.sourceStart", text: $sourceStart).textInputAutocapitalization(.never)
                TextField("merchant.business.sourceEnd", text: $sourceEnd).textInputAutocapitalization(.never)
                MerchantCRMDateRangePicker(context: state.isCurrent && !state.isBusy
                    ? .init(scope: reader.scope, authorization: reader.authorizationGeneration, merchantID: state.snapshot?.access.merchantID) : nil,
                    start: sourceStart, end: sourceEnd) { value in
                    sourceStart = value.start; sourceEnd = value.end
                }
                Button("merchant.business.applyFilter", action: applyCustomerFilter)
            }
        }
        if case .aftercare(let bucket, _) = query {
            Section {
                Picker("merchant.business.bucket", selection: Binding(get: { bucket }, set: { query = .aftercare($0, page: 1); Task { await reload() } })) {
                    ForEach(MerchantAftercareBucket.allCases, id: \.self) { Text(LocalizedStringKey("merchant.business.bucket." + String($0.rawValue))).tag($0) }
                }.accessibilityIdentifier("merchant.business.bucket")
                TextField("merchant.business.aftercare.search", text: $model.listFilters.aftercareKeyword)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                    .focused($aftercareSearchFocused).onSubmit { aftercareSearchFocused = false }
                    .accessibilityLabel(Text("merchant.business.aftercare.search"))
                    .accessibilityHint(Text("merchant.business.aftercare.searchScope"))
                    .accessibilityIdentifier("merchant.business.aftercare.keyword")
                Text("merchant.business.aftercare.searchScope").font(.footnote).foregroundStyle(.secondary)
                if !model.listFilters.aftercareKeyword.isEmpty {
                    Button("merchant.business.aftercare.clearSearch") { model.listFilters.aftercareKeyword = "" }
                        .accessibilityIdentifier("merchant.business.aftercare.clearSearch")
                }
            }
        }
        if reviewSource == nil, case .reviews = query {
            Section {
                Picker("merchant.business.reviews.filter", selection: $model.listFilters.review) {
                    ForEach(MerchantReviewFilter.allCases, id: \.self) { filter in
                        Text(LocalizedStringKey("merchant.business.reviews.filter." + filter.rawValue)).tag(filter)
                    }
                }.pickerStyle(.menu).accessibilityIdentifier("merchant.business.reviews.filter")
                Text("merchant.business.reviews.filterScope").font(.footnote).foregroundStyle(.secondary)
                if model.listFilters.review != .all {
                    Button("merchant.business.reviews.clearFilter") { model.listFilters.review = .all }
                        .accessibilityIdentifier("merchant.business.reviews.clearFilter")
                }
            }
        }
        if case .redemptions(let filter, _) = query {
            Picker("merchant.business.filter", selection: Binding(get: { filter }, set: { query = .redemptions(filter: $0, page: 1); Task { await reload() } })) {
                ForEach(["all", "pending", "settled"], id: \.self) { Text(LocalizedStringKey("merchant.business.filter." + String($0))).tag($0) }
            }
        }
    }
    @ViewBuilder private func summary(_ document: MerchantBusinessDocument) -> some View {
        if !document.summary.isEmpty {
            Section("merchant.business.summary") {
                if case .reviews = document.query {
                    Text("merchant.business.reviews.summaryScope").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(MerchantBusinessDocument.overviewMoneyKeys + ["adjustmentPendingCount", "count", "pendingAmount", "arrivedAmount", "averageRating", "pendingReplyCount", "monthNewCount", "replyRatePct", "all", "repeat", "new", "noted", "monthlyNew"], id: \.self) { key in
                    if let value = document.summary[key] {
                        MerchantBusinessField(key: key, value: value, money: MerchantBusinessDocument.overviewMoneyKeys.contains(key) || ["pendingAmount", "arrivedAmount"].contains(key))
                            .accessibilityIdentifier("merchant.business.summary." + key)
                    }
                }
            }
        }
    }
    @ViewBuilder private func rowView(_ row: MerchantBusinessRecord, access: MerchantBusinessAccess) -> some View {
        let isDirectory: Bool = { switch query { case .customers, .aftercare, .batches, .redemptions: return true; default: return false } }()
        if isDirectory, let destination = row.destination {
            HStack {
                if row.kind == .customer, access.allows("merchant:crm:segment"), let id = Int(row.id) {
                    Button { if selection.contains(id) { selection.remove(id) } else if selection.count < 100 { selection.insert(id) } } label: {
                        Image(systemName: selection.contains(id) ? "checkmark.circle.fill" : "circle").frame(minWidth: 44, minHeight: 44)
                    }.buttonStyle(.borderless).accessibilityLabel(Text("merchant.business.selectCustomer"))
                        .accessibilityValue(selection.contains(id) ? Text("merchant.business.selected") : Text("merchant.business.unselected"))
                }
                NavigationLink { MerchantBusinessPage(reader: reader, journal: journal, query: destination) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title).font(.headline)
                        MerchantBusinessRecordFields(row: row, access: access, compact: true)
                    }
                }.accessibilityIdentifier("merchant.business.row.\(row.kind.rawValue).\(row.id)")
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(row.title).font(.headline)
                MerchantBusinessRecordFields(row: row, access: access, compact: false,
                    settlementReader: reader, settlementSnapshot: {
                        guard state.isCurrent, !state.isBusy, state.failureKey == nil else { return nil }
                        return state.snapshot
                    })
                rowActions(row, access: access)
            }.accessibilityElement(children: .contain)
                .accessibilityIdentifier("merchant.business.row.\(row.kind.rawValue).\(row.id)")
        }
    }
    @ViewBuilder private func rowActions(_ row: MerchantBusinessRecord, access: MerchantBusinessAccess) -> some View {
        if row.kind == .review {
            if let snapshot = state.snapshot, sourcePageMatches(snapshot), snapshot.document.rows.contains(row) {
                ForEach(MerchantReviewReplyAction.allCases, id: \.self) { action in
                    let key = action == .reply ? "canReply" : action == .report ? "canReport" : "canEditReply"
                    if row.fields[key]?.bool == true {
                        Button(LocalizedStringKey("merchant.business.review." + String(action.rawValue))) { editor = .init(kind: .review(row, action)) }
                    }
                }
            } else if reviewSource == nil, let destination = model.reviewSourcePage(for: row) {
                Button("merchant.business.reviews.reloadSourcePage") { reviewSourceDestination = destination }
                    .accessibilityIdentifier("merchant.business.reviews.reloadSourcePage.\(row.id)")
            }
        }
        if row.kind == .refund, row.fields["canRespond"]?.bool == true, access.allows("merchant:aftercare:respond") {
            Button("merchant.business.respond") { editor = .init(kind: .aftercare(row)) }.accessibilityIdentifier("merchant.business.respond")
            Text("merchant.business.opinionOnly").font(.footnote).foregroundStyle(.secondary)
        }
        if case .customer(let customer) = query, access.allows("merchant:crm:segment") {
            if row.kind == .tag, let id = Int(row.id) {
                Button("merchant.business.removeTag") { model.prepare(.removeTag(customer: customer, tagID: id)) }
            }
            if row.kind == .timeline, ["NOTE", "NOTE_CORRECTION"].contains(row.fields.mbText("type") ?? ""),
               let note = row.fields["noteId"]?.integer, let version = row.fields["noteVersion"]?.integer {
                Button("merchant.business.correctNote") { editor = .init(kind: .note(customer, corrects: note)) }
                Button("merchant.business.hideNote") { model.prepare(.hideNote(customer: customer, noteID: note, expectedVersion: version)) }
            }
        }
        if access.canManageOperators {
            if row.kind == .operatorMember, row.fields.mbText("status") == "ACTIVE" {
                Button("merchant.business.changeRole") { editor = .init(kind: .role(row)) }
                Button("merchant.business.removeOperator") { editor = .init(kind: .removeOperator(row)) }
            }
            if row.kind == .invite, row.fields.mbText("status") == "PENDING" {
                Button("merchant.business.revokeInvite") { editor = .init(kind: .revokeInvite(row)) }
            }
        }
    }
    @ViewBuilder private func pageActions(_ snapshot: MerchantBusinessSnapshot) -> some View {
        if case .customer(let id) = query, snapshot.access.allows("merchant:crm:segment") {
            Section("merchant.business.localActions") {
                Button("merchant.business.addNote") { editor = .init(kind: .note(id, corrects: nil)) }.accessibilityIdentifier("merchant.business.addNote")
                Button("merchant.business.assignTag") { editor = .init(kind: .tag([id])) }
            }
        }
        if case .customers = query, !selection.isEmpty, snapshot.access.allows("merchant:crm:segment") {
            Button("merchant.business.batchTag") { editor = .init(kind: .tag(selection.sorted().compactMap { try? .init($0) })) }
        }
        if query == .operators, snapshot.access.canManageOperators {
            Button("merchant.business.inviteOperator") { editor = .init(kind: .invite) }
        }
    }
    private var isAftercare: Bool { if case .aftercare = query { return true }; return false }
    private var isLocalList: Bool {
        switch query { case .aftercare, .reviews: return true; default: return false }
    }
    private func visibleRows(_ section: MerchantBusinessSection, in document: MerchantBusinessDocument) -> [MerchantBusinessRecord] {
        let rows = reviewSource == nil ? model.visibleRows(in: section, query: document.query) : section.rows
        return rows.filter { reviewSource == nil || $0.id == reviewSource?.reviewID }
    }
    private func sourcePageMatches(_ snapshot: MerchantBusinessSnapshot) -> Bool {
        reviewSource?.matches(scope: reader.scope, authorizationGeneration: reader.authorizationGeneration, snapshot: snapshot) ?? true
    }
    private func sourcePageCanPrepare(_ mutation: MerchantBusinessMutation) -> Bool {
        guard let reviewSource else { return true }
        guard let snapshot = state.snapshot, state.isCurrent, sourcePageMatches(snapshot),
              case .review(let id, _, _, _) = mutation else { return false }
        return String(id.rawValue) == reviewSource.reviewID
    }
    private var availableTags: [Int] {
        state.snapshot?.document.payload.object?["availableTags"]?.array?.compactMap { $0.object?["id"]?.integer }.filter { $0 > 0 } ?? []
    }
    private func tagName(_ id: Int) -> String {
        state.snapshot?.document.payload.object?["availableTags"]?.array?.first { $0.object?["id"]?.integer == id }?.object?.mbText("tagName") ?? "#\(id)"
    }
    private func applyCustomerFilter() {
        var filter = MerchantCustomerQuery(); filter.keyword = keyword; filter.segment = segment
        filter.sourceType = sourceType == 0 ? nil : sourceType; filter.tagID = tagID == 0 ? nil : tagID
        filter.sourceStart = sourceStart.isEmpty ? nil : sourceStart; filter.sourceEnd = sourceEnd.isEmpty ? nil : sourceEnd
        query = .customers(filter); selection = []; Task { await reload() }
    }
    private func movePage(_ page: Int) { query = query.paged(page); selection = []; Task { await reload() } }
    private func reload() async { selection = []; await model.load(query) }
}
