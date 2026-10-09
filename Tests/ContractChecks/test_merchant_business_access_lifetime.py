"""Exact merchant Home R1 source boundary; these are not runtime/XCTest results."""
from pathlib import Path
import hashlib
from merchant_customer_empty_inverse import before_customer_empty_source
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]
VIEW = 'App/MerchantBusinessViews.swift'
MODEL = 'App/MerchantBusinessAccessModel.swift'
BASE_VIEW_SHA256 = 'ae07cfbd1250e1f9e9209c70d7bb84073ce21388c51fd25f04348f6773048af3'
CURRENT_VIEW_SHA256 = '4f08ea22b3cb52a245e9147f057f8fa9d4c0b0297286a0c560db6fd9f3269353'
MODEL_SHA256 = 'aff601f64622ef1286026eaa9646a6f1b8ebf8f468677a165e0d2a0e1eeb8724'
OLD_HOME = '@MainActor struct MerchantBusinessHomeView: View {\n    @Environment(\\.nativeVerificationDestination) private var nativeVerificationDestination\n    let reader: any MerchantBusinessReading\n    let journal: any MerchantBusinessIntentStore\n    @State private var access: MerchantBusinessAccess?\n    @State private var issue: String?\n    @State private var loading = false\n    private let destinations: [MerchantBusinessQuery] = [.customers(.init()), .aftercare(.pending, page: 1), .reviews(page: 1), .overview,\n        .redemptions(filter: "all", page: 1), .entries(source: "all", page: 1), .batches(page: 1), .verificationRecords, .operators]\n    var body: some View {\n        List {\n            if reader.isOfflineExample { Text("merchant.business.synthetic").foregroundStyle(.secondary).accessibilityIdentifier("merchant.business.synthetic") }\n            Text("merchant.business.boundary").font(.footnote).foregroundStyle(.secondary)\n            if let access {\n                Section {\n                    Text(access.name ?? "#\\(access.merchantID)").font(.title3.bold())\n                    Text(LocalizedStringKey("merchant.business.role." + String(access.role)))\n                }\n                Section("merchant.business.workspace") {\n                    ForEach(destinations, id: \\.self) { query in\n                        if (try? access.require(query.permissions)) != nil {\n                            NavigationLink {\n                                MerchantBusinessPage(reader: reader, journal: journal, query: query)\n                            } label: { Label(LocalizedStringKey(query.titleKey), systemImage: symbol(query)) }\n                            .accessibilityIdentifier("merchant.business.open.\\(query.titleKey.split(separator: ".").last ?? "page")")\n                        }\n                    }\n                    if access.allows("merchant:verify") {\n                        NavigationLink {\n                            if let nativeVerificationDestination { nativeVerificationDestination() }\n                            else { MerchantScanPreviewView() }\n                        } label: { Label("merchant.business.scan", systemImage: "qrcode.viewfinder") }\n                            .accessibilityIdentifier("merchant.business.open.scan")\n                        NavigationLink { CityNodeRedeemView(reader: reader, journal: journal) } label: {\n                            Label("merchant.cityRedeem.title", systemImage: "qrcode")\n                        }.accessibilityIdentifier("merchant.cityRedeem.entry")\n                    }\n                }\n            } else if loading { ProgressView("merchant.checkingAccess") }\n            if let issue { Text(LocalizedStringKey(issue)).foregroundStyle(.secondary) }\n            Button("merchant.refreshAccess") { Task { await load() } }.disabled(loading)\n        }\n        .appNavigationTitle("merchant.business.title")\n        .task(id: reader.scope) { await load() }\n        .refreshable { await load() }\n    }\n    private func symbol(_ query: MerchantBusinessQuery) -> String {\n        switch query {\n        case .customers: return "person.2"; case .aftercare: return "arrow.uturn.backward.circle"\n        case .reviews: return "star.bubble"; case .overview, .entries, .batches: return "chart.bar.doc.horizontal"\n        case .operators: return "person.badge.key"; default: return "list.bullet.rectangle"\n        }\n    }\n    private func load() async {\n        let scope = reader.scope; access = nil; issue = nil; loading = true\n        defer { if reader.scope == scope { loading = false } }\n        do {\n            let value = try await reader.access()\n            guard reader.scope == scope, !Task.isCancelled else { return }; access = value\n        } catch {\n            guard reader.scope == scope, !Task.isCancelled else { return }\n            issue = (error as? MerchantBusinessFailure)?.key ?? (reader.isConfigured ? "merchant.business.loadFailed" : "auth.notConfigured")\n        }\n    }\n}\n'
CURRENT_HOME = '@MainActor struct MerchantBusinessHomeView: View {\n    @Environment(\\.nativeVerificationDestination) private var nativeVerificationDestination\n    let reader: any MerchantBusinessReading\n    let journal: any MerchantBusinessIntentStore\n    @StateObject private var accessModel = MerchantBusinessAccessModel()\n    @State private var appearance = MerchantBusinessAccessAppearance()\n    private var accessKey: MerchantBusinessAccessLoadKey { .init(reader: reader) }\n    private let destinations: [MerchantBusinessQuery] = [.customers(.init()), .aftercare(.pending, page: 1), .reviews(page: 1), .overview,\n        .redemptions(filter: "all", page: 1), .entries(source: "all", page: 1), .batches(page: 1), .verificationRecords, .operators]\n    var body: some View {\n        let visibleAppearance = appearance\n        let renderedKey = accessKey\n        let queuedRequest = accessModel.request\n        List {\n            if reader.isOfflineExample { Text("merchant.business.synthetic").foregroundStyle(.secondary).accessibilityIdentifier("merchant.business.synthetic") }\n            Text("merchant.business.boundary").font(.footnote).foregroundStyle(.secondary)\n            if let access = accessModel.access(for: reader) {\n                Section {\n                    Text(access.name ?? "#\\(access.merchantID)").font(.title3.bold())\n                    Text(LocalizedStringKey("merchant.business.role." + String(access.role)))\n                }\n                Section("merchant.business.workspace") {\n                    ForEach(destinations, id: \\.self) { query in\n                        if (try? access.require(query.permissions)) != nil {\n                            NavigationLink(value: MerchantBusinessHomeRoute(target: .query(query), reader: reader, journal: journal)) { Label(LocalizedStringKey(query.titleKey), systemImage: symbol(query)) }\n                            .accessibilityIdentifier("merchant.business.open.\\(query.titleKey.split(separator: ".").last ?? "page")")\n                        }\n                    }\n                    if access.allows("merchant:verify") {\n                        NavigationLink(value: MerchantBusinessHomeRoute(target: .scan, reader: reader, journal: journal)) {\n                            Label("merchant.business.scan", systemImage: "qrcode.viewfinder")\n                        }\n                            .accessibilityIdentifier("merchant.business.open.scan")\n                        NavigationLink(value: MerchantBusinessHomeRoute(target: .cityNode, reader: reader, journal: journal)) {\n                            Label("merchant.cityRedeem.title", systemImage: "qrcode")\n                        }.accessibilityIdentifier("merchant.cityRedeem.entry")\n                    }\n                }\n            } else if accessModel.isLoading(for: reader) { ProgressView("merchant.checkingAccess") }\n            if let issue = accessModel.issue(for: reader) { Text(LocalizedStringKey(issue)).foregroundStyle(.secondary) }\n            Button("merchant.refreshAccess") {\n                accessModel.refresh(reader: reader, appearance: visibleAppearance, context: renderedKey)\n            }.disabled(accessModel.isLoading(for: reader))\n        }\n        .appNavigationTitle("merchant.business.title")\n        // The destination host remains outside the access-dependent rows. Clearing\n        // Home on push does not remove a destination already on the navigation stack.\n        .navigationDestination(for: MerchantBusinessHomeRoute.self) { route in\n            if route.isCurrent(reader: reader, journal: journal) {\n                switch route.target {\n                case .query(let query): MerchantBusinessPage(reader: route.reader, journal: route.journal, query: query)\n                case .scan:\n                    if let nativeVerificationDestination { nativeVerificationDestination() }\n                    else { MerchantScanPreviewView() }\n                case .cityNode: CityNodeRedeemView(reader: route.reader, journal: route.journal)\n                }\n            } else { Text("merchant.business.stale") }\n        }\n        .task(id: queuedRequest?.id) {\n            if let queuedRequest { await accessModel.load(reader: reader, request: queuedRequest) }\n        }\n        .onAppear {\n            guard appearance === visibleAppearance else { return }\n            accessModel.begin(reader: reader, appearance: visibleAppearance)\n        }\n        .onChange(of: accessKey) { _, newKey in\n            guard appearance === visibleAppearance, newKey == renderedKey,\n                  newKey == MerchantBusinessAccessLoadKey(reader: reader),\n                  accessModel.isActive(appearance: visibleAppearance) else { return }\n            accessModel.end(appearance: visibleAppearance)\n            let replacement = MerchantBusinessAccessAppearance()\n            appearance = replacement\n            accessModel.begin(reader: reader, appearance: replacement)\n        }\n        .onDisappear {\n            accessModel.end(appearance: visibleAppearance)\n            if appearance === visibleAppearance { appearance = MerchantBusinessAccessAppearance() }\n        }\n        .refreshable {\n            accessModel.refresh(reader: reader, appearance: visibleAppearance, context: renderedKey)\n        }\n    }\n    private func symbol(_ query: MerchantBusinessQuery) -> String {\n        switch query {\n        case .customers: return "person.2"; case .aftercare: return "arrow.uturn.backward.circle"\n        case .reviews: return "star.bubble"; case .overview, .entries, .batches: return "chart.bar.doc.horizontal"\n        case .operators: return "person.badge.key"; default: return "list.bullet.rectangle"\n        }\n    }\n}\n'

def digest(source):
    return hashlib.sha256(source.encode()).hexdigest()


# Independently approved aftercare read presentation. Undo exactly this one hunk
# before applying the original Home R1 whole-source and inverse checks unchanged.
AFTERCARE_VIEW_SHA256 = '3fe571bd94ccc4813c7a89c6f7c1a8363343fbcfa623a4a3837fd0ec3f7bc1c1'
AFTERCARE_OLD_BLOCK = '                ForEach(snapshot.document.sections) { section in\n                    let rows = visibleRows(section, in: snapshot.document)\n                    if !rows.isEmpty {\n                        Section(LocalizedStringKey("merchant.business.section." + String(section.id))) {\n                            ForEach(rows) { row in\n                                rowView(row, access: snapshot.access)\n                            }\n                        }\n                    }\n                }\n'
AFTERCARE_CURRENT_BLOCK = '                if let progress = snapshot.document.aftercareProgress {\n                    MerchantAftercareProgressView(progress: progress)\n                    if let refund = snapshot.document.rows.first(where: { $0.kind == .refund }) {\n                        Section { rowActions(refund, access: snapshot.access) }\n                    }\n                } else {\n                    ForEach(snapshot.document.sections) { section in\n                        let rows = visibleRows(section, in: snapshot.document)\n                        if !rows.isEmpty {\n                            Section(LocalizedStringKey("merchant.business.section." + String(section.id))) {\n                                ForEach(rows) { row in\n                                    rowView(row, access: snapshot.access)\n                                }\n                            }\n                        }\n                    }\n                }\n'


# Independently approved settlement detail adapter. Its exact inverse runs before
# the existing aftercare and Home layers; those original assertions stay intact.
SETTLEMENT_VIEW_SHA256 = '2a4f0c0ba5164317d66542ae8d7da9baec4ba632fcb316f8344973c135c17cdd'
SETTLEMENT_OLD_BLOCK = '                MerchantBusinessRecordFields(row: row, access: access, compact: false)'
SETTLEMENT_CURRENT_BLOCK = '                MerchantBusinessRecordFields(row: row, access: access, compact: false,\n                    settlementReader: reader, settlementSnapshot: {\n                        guard state.isCurrent, !state.isBusy, state.failureKey == nil else { return nil }\n                        return state.snapshot\n                    })'


# Independently approved customer detail presentation. Exactly invert this hunk
# before the unchanged settlement, aftercare and Home source fences.
CUSTOMER_VIEW_SHA256 = 'f046c2d5705e65575c1c014f43e688e09a790dab51f2e84d32a441e5b4c7d5a6'
CUSTOMER_OLD_BLOCK = '                summary(snapshot.document)\n                if case .customer = query, let tags = try? snapshot.document.payload.object?.mbObjects("systemTags") {\n                    Section("merchant.business.systemTags") { ForEach(Array(tags.enumerated()), id: \\.offset) { _, tag in Text(tag.mbText("label") ?? "") } }\n                }\n                if snapshot.document.sections.allSatisfy({ model.unfilteredRows(in: $0, query: snapshot.document.query).isEmpty }) && (snapshot.document.summary.isEmpty || isLocalList) {\n                    Text("merchant.business.empty").foregroundStyle(.secondary).accessibilityIdentifier("merchant.business.empty")\n                } else if model.listFilters.isActive(for: snapshot.document.query), snapshot.document.sections.allSatisfy({ visibleRows($0, in: snapshot.document).isEmpty }) {\n                    Text(LocalizedStringKey(isAftercare ? "merchant.business.aftercare.noMatches" : "merchant.business.list.noMatches")).foregroundStyle(.secondary).accessibilityIdentifier("merchant.business.list.noMatches")\n                }\n                if let progress = snapshot.document.aftercareProgress {\n                    MerchantAftercareProgressView(progress: progress)\n'
CUSTOMER_CURRENT_BLOCK = '                summary(snapshot.document)\n                if snapshot.document.sections.allSatisfy({ model.unfilteredRows(in: $0, query: snapshot.document.query).isEmpty }) && (snapshot.document.summary.isEmpty || isLocalList) {\n                    Text("merchant.business.empty").foregroundStyle(.secondary).accessibilityIdentifier("merchant.business.empty")\n                } else if model.listFilters.isActive(for: snapshot.document.query), snapshot.document.sections.allSatisfy({ visibleRows($0, in: snapshot.document).isEmpty }) {\n                    Text(LocalizedStringKey(isAftercare ? "merchant.business.aftercare.noMatches" : "merchant.business.list.noMatches")).foregroundStyle(.secondary).accessibilityIdentifier("merchant.business.list.noMatches")\n                }\n                if case .customer = query, let detail = snapshot.document.customerDetail {\n                    MerchantCustomerDetailSections(detail: detail, access: snapshot.access) { row in\n                        rowActions(row, access: snapshot.access)\n                    }\n                } else if let progress = snapshot.document.aftercareProgress {\n                    MerchantAftercareProgressView(progress: progress)\n'


# Approved read-only roster presentation. Undo both exact hunks before the
# unchanged customer, settlement, aftercare and Home boundary checks.
ROSTER_VIEW_SHA256 = '9591a8fd9cebf903e7bf4b10c914e6fa3aa907b3823d48c737c89521a94e3b05'
ROSTER_OLD_EMPTY = '                if snapshot.document.sections.allSatisfy({ model.unfilteredRows(in: $0, query: snapshot.document.query).isEmpty }) && (snapshot.document.summary.isEmpty || isLocalList) {'
ROSTER_CURRENT_EMPTY = '                if query != .operators, snapshot.document.sections.allSatisfy({ model.unfilteredRows(in: $0, query: snapshot.document.query).isEmpty }) && (snapshot.document.summary.isEmpty || isLocalList) {'
ROSTER_OLD_BLOCK = '                if case .customer = query, let detail = snapshot.document.customerDetail {\n'
ROSTER_CURRENT_BLOCK = '                if query == .operators {\n                    if let roster = try? MerchantOperatorRoster(document: snapshot.document) {\n                        MerchantOperatorRosterSections(roster: roster, access: snapshot.access) { row in\n                            rowView(row, access: snapshot.access)\n                        }\n                    } else { Text("merchant.operatorRoster.unavailable").foregroundStyle(.secondary) }\n                } else if case .customer = query, let detail = snapshot.document.customerDetail {\n'


# Approved review presentation extension. Byte-exact inversion preserves every
# older Home/aftercare/settlement/customer/roster guard. This proves preservation,
# not acceptance of new behavior; separate negative/race tests cover the extension.
REVIEW_PAGES_VIEW_SHA256 = 'a5f8c2e225acada297e818142fb300a36d2a5e89c640be7b977ff82f2bcd3cd9'
REVIEW_PAGES_PREIMAGE_SHA256 = '9591a8fd9cebf903e7bf4b10c914e6fa3aa907b3823d48c737c89521a94e3b05'
REVIEW_PAGES_BYTE_HUNKS = [(369, b'    private(set) var reviewLoadedPages: MerchantReviewLoadedPages?\n', b''), (1485, b'    func loadMoreReviews() async {\n        guard !coordinator.isBusy, let snapshot = coordinator.snapshot, let pages = reviewLoadedPages else { return }\n        guard coordinator.isCurrent,\n              pages.matches(scope: coordinator.reader.scope, authorizationGeneration: coordinator.reader.authorizationGeneration, access: snapshot.access) else {\n            invalidate(); aftercareLoadFailureKey = "merchant.business.stale"; revision += 1; return\n        }\n        guard pages.hasMore, snapshot.document.query == .reviews(page: pages.page) else { return }\n        await load(.reviews(page: pages.page + 1), appendAftercare: false, appendReviews: true)\n    }\n    func reviewSourcePage(for row: MerchantBusinessRecord) -> MerchantReviewSourcePage? {\n        guard coordinator.isCurrent, let snapshot = coordinator.snapshot, let pages = reviewLoadedPages,\n              pages.matches(scope: coordinator.reader.scope, authorizationGeneration: coordinator.reader.authorizationGeneration, access: snapshot.access) else { return nil }\n        return pages.sourcePage(for: row)\n    }\n    private func load(_ requested: MerchantBusinessQuery, appendAftercare: Bool, appendReviews: Bool = false) async {\n', b'    private func load(_ requested: MerchantBusinessQuery, appendAftercare: Bool) async {\n'), (3218, b'        if !appendReviews { reviewLoadedPages = nil }\n', b''), (3751, b'            aftercareLoadedPages = nil; reviewLoadedPages = nil; coordinator.invalidate(); return\n', b'            aftercareLoadedPages = nil; coordinator.invalidate(); return\n'), (4004, b'            aftercareLoadedPages = nil; reviewLoadedPages = nil; return\n', b'            aftercareLoadedPages = nil; return\n'), (4281, b'        if case .reviews(let page) = query, let scope {\n            do {\n                if appendReviews {\n                    guard var pages = reviewLoadedPages else { throw MerchantBusinessFailure.stale }\n                    try pages.append(snapshot, scope: scope, authorizationGeneration: authorization)\n                    reviewLoadedPages = pages\n                } else if page == 1 {\n                    reviewLoadedPages = try .init(snapshot: snapshot, scope: scope, authorizationGeneration: authorization)\n                }\n            } catch {\n                reviewLoadedPages = nil; coordinator.invalidate(); aftercareLoadFailureKey = "merchant.business.stale"\n            }\n        }\n', b''), (5803, b'        if case .reviews = query, let pages = reviewLoadedPages {\n            guard coordinator.isCurrent, let snapshot = coordinator.snapshot,\n                  pages.matches(scope: coordinator.reader.scope, authorizationGeneration: coordinator.reader.authorizationGeneration, access: snapshot.access) else { return [] }\n            return pages.rows\n        }\n', b''), (7258, b'        loadGeneration += 1; aftercareLoadedPages = nil; reviewLoadedPages = nil; aftercareLoadFailureKey = nil\n', b'        loadGeneration += 1; aftercareLoadedPages = nil; aftercareLoadFailureKey = nil\n'), (13881, b'    @State private var reviewSourceDestination: MerchantReviewSourcePage?\n    private let reviewSource: MerchantReviewSourcePage?\n    init(reader: any MerchantBusinessReading, journal: any MerchantBusinessIntentStore, query: MerchantBusinessQuery, reviewSource: MerchantReviewSourcePage? = nil) {\n        self.reader = reader; self.journal = journal; self.reviewSource = reviewSource\n', b'    init(reader: any MerchantBusinessReading, journal: any MerchantBusinessIntentStore, query: MerchantBusinessQuery) {\n        self.reader = reader; self.journal = journal\n'), (15860, b'                if sourcePageMatches(snapshot) {\n                if reviewSource != nil {\n                    Text("merchant.business.reviews.sourcePageNotice").font(.footnote).foregroundStyle(.secondary)\n                    if !snapshot.document.rows.contains(where: { $0.id == reviewSource?.reviewID }) {\n                        Text("merchant.business.reviews.sourcePageMissing").accessibilityIdentifier("merchant.business.reviews.sourcePageMissing")\n                    }\n                }\n', b''), (18848, b'                if reviewSource == nil, case .reviews = query, let pages = model.reviewLoadedPages, pages.hasMore {\n                    Button("merchant.business.reviews.loadMore") { Task { await model.loadMoreReviews() } }\n                        .disabled(state.isBusy).accessibilityIdentifier("merchant.business.reviews.loadMore")\n                }\n', b''), (19538, b'                } else if reviewSource == nil, (model.reviewLoadedPages?.page ?? 1) == 1, snapshot.document.hasMore || query.page > 1 {\n', b'                } else if snapshot.document.hasMore || query.page > 1 {\n'), (20427, b'            }\n            if reviewSource != nil, let snapshot = state.snapshot, !sourcePageMatches(snapshot) {\n                Text("merchant.business.stale").accessibilityIdentifier("merchant.business.reviews.sourcePageStale")\n            }\n', b''), (20970, b'        .sheet(item: $editor, onDismiss: { if let mutation = pendingMutation { pendingMutation = nil; if sourcePageCanPrepare(mutation) { model.prepare(mutation) } } }) { context in\n', b'        .sheet(item: $editor, onDismiss: { if let mutation = pendingMutation { pendingMutation = nil; model.prepare(mutation) } }) { context in\n'), (21255, b'                guard sourcePageCanPrepare(mutation) else { pendingMutation = nil; editor = nil; return }\n', b''), (21889, b'        .sheet(item: $reviewSourceDestination) { destination in\n            NavigationStack {\n                MerchantBusinessPage(reader: reader, journal: journal, query: destination.query, reviewSource: destination)\n                    .toolbar { ToolbarItem(placement: .cancellationAction) {\n                        Button("action.close") { reviewSourceDestination = nil }\n                    } }\n            }\n        }\n        .onChange(of: reader.scope) { _, _ in editor = nil; pendingMutation = nil; reviewSourceDestination = nil; selection = []; model.invalidate() }\n        .onChange(of: reader.authorizationGeneration) { _, _ in editor = nil; pendingMutation = nil; reviewSourceDestination = nil; selection = []; model.invalidate() }\n', b'        .onChange(of: reader.scope) { _, _ in editor = nil; pendingMutation = nil; selection = []; model.invalidate() }\n        .onChange(of: reader.authorizationGeneration) { _, _ in editor = nil; pendingMutation = nil; selection = []; model.invalidate() }\n'), (25677, b'        if reviewSource == nil, case .reviews = query {\n', b'        if case .reviews = query {\n'), (30288, b'            if let snapshot = state.snapshot, sourcePageMatches(snapshot), snapshot.document.rows.contains(row) {\n                ForEach(MerchantReviewReplyAction.allCases, id: \\.self) { action in\n                    let key = action == .reply ? "canReply" : action == .report ? "canReport" : "canEditReply"\n                    if row.fields[key]?.bool == true {\n                        Button(LocalizedStringKey("merchant.business.review." + String(action.rawValue))) { editor = .init(kind: .review(row, action)) }\n                    }\n', b'            ForEach(MerchantReviewReplyAction.allCases, id: \\.self) { action in\n                let key = action == .reply ? "canReply" : action == .report ? "canReport" : "canEditReply"\n                if row.fields[key]?.bool == true {\n                    Button(LocalizedStringKey("merchant.business.review." + String(action.rawValue))) { editor = .init(kind: .review(row, action)) }\n'), (30845, b'            } else if reviewSource == nil, let destination = model.reviewSourcePage(for: row) {\n                Button("merchant.business.reviews.reloadSourcePage") { reviewSourceDestination = destination }\n                    .accessibilityIdentifier("merchant.business.reviews.reloadSourcePage.\\(row.id)")\n', b''), (34152, b'        let rows = reviewSource == nil ? model.visibleRows(in: section, query: document.query) : section.rows\n        return rows.filter { reviewSource == nil || $0.id == reviewSource?.reviewID }\n    }\n    private func sourcePageMatches(_ snapshot: MerchantBusinessSnapshot) -> Bool {\n        reviewSource?.matches(scope: reader.scope, authorizationGeneration: reader.authorizationGeneration, snapshot: snapshot) ?? true\n    }\n    private func sourcePageCanPrepare(_ mutation: MerchantBusinessMutation) -> Bool {\n        guard let reviewSource else { return true }\n        guard let snapshot = state.snapshot, state.isCurrent, sourcePageMatches(snapshot),\n              case .review(let id, _, _, _) = mutation else { return false }\n        return String(id.rawValue) == reviewSource.reviewID\n', b'        model.visibleRows(in: section, query: document.query)\n')]


def before_review_pages_source(source):
    source = before_customer_empty_source(source)
    raw = source.encode('utf-8')
    current = hashlib.sha256(raw).hexdigest()
    if current in (REVIEW_PAGES_PREIMAGE_SHA256, CUSTOMER_VIEW_SHA256, SETTLEMENT_VIEW_SHA256, AFTERCARE_VIEW_SHA256, CURRENT_VIEW_SHA256):
        return source
    if current != REVIEW_PAGES_VIEW_SHA256:
        raise ValueError('Unknown review-page source or changed existing boundary')
    for offset, postimage, preimage in reversed(REVIEW_PAGES_BYTE_HUNKS):
        if raw[offset:offset + len(postimage)] != postimage:
            raise ValueError('Missing, moved or changed review-page hunk')
        raw = raw[:offset] + preimage + raw[offset + len(postimage):]
    if hashlib.sha256(raw).hexdigest() != REVIEW_PAGES_PREIMAGE_SHA256:
        raise ValueError('Changed source outside the review-page boundary')
    return raw.decode('utf-8')


def before_roster_source(source):
    if digest(source) in (CUSTOMER_VIEW_SHA256, SETTLEMENT_VIEW_SHA256, AFTERCARE_VIEW_SHA256, CURRENT_VIEW_SHA256):
        return source
    if digest(source) != ROSTER_VIEW_SHA256 or source.count(ROSTER_CURRENT_EMPTY) != 1 or source.count(ROSTER_CURRENT_BLOCK) != 1:
        raise ValueError('Unknown roster source or changed existing boundary')
    restored = source.replace(ROSTER_CURRENT_EMPTY, ROSTER_OLD_EMPTY, 1).replace(ROSTER_CURRENT_BLOCK, ROSTER_OLD_BLOCK, 1)
    if digest(restored) != CUSTOMER_VIEW_SHA256:
        raise ValueError('Changed source outside the roster boundary')
    return restored


def before_customer_detail_source(source):
    if digest(source) in (SETTLEMENT_VIEW_SHA256, AFTERCARE_VIEW_SHA256, CURRENT_VIEW_SHA256):
        return source
    if digest(source) != CUSTOMER_VIEW_SHA256 or source.count(CUSTOMER_CURRENT_BLOCK) != 1:
        raise ValueError('Unknown customer source or changed existing boundary')
    restored = source.replace(CUSTOMER_CURRENT_BLOCK, CUSTOMER_OLD_BLOCK, 1)
    if digest(restored) != SETTLEMENT_VIEW_SHA256:
        raise ValueError('Changed source outside the customer boundary')
    return restored


def before_settlement_source(source):
    if digest(source) in (AFTERCARE_VIEW_SHA256, CURRENT_VIEW_SHA256):
        return source
    if digest(source) != SETTLEMENT_VIEW_SHA256 or source.count(SETTLEMENT_CURRENT_BLOCK) != 1:
        raise ValueError('Unknown settlement source or changed existing boundary')
    restored = source.replace(SETTLEMENT_CURRENT_BLOCK, SETTLEMENT_OLD_BLOCK, 1)
    if digest(restored) != AFTERCARE_VIEW_SHA256:
        raise ValueError('Changed source outside the settlement boundary')
    return restored


def before_aftercare_source(source):
    if digest(source) == CURRENT_VIEW_SHA256:
        return source
    if digest(source) != AFTERCARE_VIEW_SHA256 or source.count(AFTERCARE_CURRENT_BLOCK) != 1:
        raise ValueError('Unknown aftercare source or changed Home boundary')
    restored = source.replace(AFTERCARE_CURRENT_BLOCK, AFTERCARE_OLD_BLOCK, 1)
    if digest(restored) != CURRENT_VIEW_SHA256:
        raise ValueError('Changed source outside the aftercare boundary')
    return restored


def original_home_source(source):
    source = before_review_pages_source(source)
    source = before_roster_source(source)
    source = before_customer_detail_source(source)
    source = before_settlement_source(source)
    source = before_aftercare_source(source)
    if digest(source) != CURRENT_VIEW_SHA256 or source.count(CURRENT_HOME) != 1:
        raise ValueError('Unknown current merchant Home source')
    restored = source.replace(CURRENT_HOME, OLD_HOME, 1)
    if digest(restored) != BASE_VIEW_SHA256:
        raise ValueError('Changed source outside the Home boundary')
    return restored


REQUIRED_FENCES = [
    'readerIdentity = ObjectIdentifier(reader)',
    'authorizationGeneration = reader.authorizationGeneration',
    'configured = reader.isConfigured',
    'guard !Task.isCancelled, !next.started, !next.retired else { return }',
    'guard !Task.isCancelled, appearance === expected, !expected.retired,',
    'isCurrent(reader), context == captured else { return }',
    'expected.retired = true',
    'guard appearance === expected else { return }',
    'request = nil; claimedRequestID = nil',
    'pending?.cancel(); pending = nil',
    'accessValue = nil; issueKey = nil; loading = false',
    'guard captured.configured else',
    'guard captured.scope != nil else',
    'guard !Task.isCancelled else { return }',
    'guard request == captured, appearance?.id == captured.appearanceID,',
    'isCurrent(reader), context == captured.context, claimedRequestID == nil else { return }',
    'let value = try await reader.access()',
    'await withTaskCancellationHandler',
    'guard request == captured, claimedRequestID == captured.id,',
    'appearance?.id == captured.appearanceID, owner === reader else { return }',
    'guard !Task.isCancelled, isCurrent(reader) else {',
    'self.reader === reader && self.journal === journal &&',
    'context == MerchantBusinessAccessLoadKey(reader: reader)',
]


def validate_model(source):
    if digest(source) != MODEL_SHA256 or not all(t in source for t in REQUIRED_FENCES):
        raise ValueError('Unknown model or missing lifetime fence')
    return REQUIRED_FENCES


class MerchantBusinessAccessLifetimeChecks(unittest.TestCase):
    def setUp(self):
        self.model = (ROOT / MODEL).read_text()
        self.review_pages_view = before_customer_empty_source((ROOT / VIEW).read_bytes().decode('utf-8'))
        self.roster_view = before_review_pages_source(self.review_pages_view)
        self.customer_view = before_roster_source(self.roster_view)
        self.settlement_view = before_customer_detail_source(self.customer_view)
        self.aftercare_view = before_settlement_source(self.settlement_view)
        self.view = before_aftercare_source(self.aftercare_view)

    def test_review_pages_exact_inverse_preserves_all_previous_layers(self):
        self.assertEqual(digest(self.review_pages_view), REVIEW_PAGES_VIEW_SHA256)
        self.assertEqual(digest(self.roster_view), REVIEW_PAGES_PREIMAGE_SHA256)
        self.assertEqual(digest(original_home_source(self.review_pages_view)), BASE_VIEW_SHA256)

    def test_review_pages_inverse_rejects_missing_duplicate_moved_or_unrelated_bytes(self):
        raw = self.review_pages_view.encode('utf-8')
        offset, postimage, _ = next(h for h in REVIEW_PAGES_BYTE_HUNKS if h[1])
        variants = [raw + b'\n', raw.replace(b'\n', b'\r\n'),
                    raw[:offset] + raw[offset + len(postimage):],
                    raw[:offset] + postimage + raw[offset:],
                    raw[:offset] + raw[offset + len(postimage):] + postimage,
                    raw.replace(b'snapshot.document.rows.contains(row)', b'true', 1),
                    raw.replace(b'guard sourcePageCanPrepare(mutation)', b'guard true', 1),
                    raw.replace(b'guard appearance === visibleAppearance else { return }', b'if false { return }', 1)]
        for changed in variants:
            with self.assertRaises(ValueError):
                before_review_pages_source(changed.decode('utf-8'))

    def test_roster_exact_inverse_preserves_all_four_existing_layers(self):
        self.assertEqual(digest(self.roster_view), ROSTER_VIEW_SHA256)
        self.assertEqual(digest(before_roster_source(self.roster_view)), CUSTOMER_VIEW_SHA256)
        self.assertEqual(digest(original_home_source(self.roster_view)), BASE_VIEW_SHA256)
        self.assertEqual(self.roster_view.count(ROSTER_CURRENT_EMPTY), 1)
        self.assertEqual(self.roster_view.count(ROSTER_CURRENT_BLOCK), 1)

    def test_roster_inverse_rejects_missing_duplicate_and_unrelated_edits(self):
        variants = [self.roster_view + '\n',
                    self.roster_view.replace(ROSTER_CURRENT_EMPTY, ROSTER_OLD_EMPTY, 1),
                    self.roster_view.replace(ROSTER_CURRENT_BLOCK, ROSTER_OLD_BLOCK, 1),
                    self.roster_view.replace(ROSTER_CURRENT_BLOCK, '', 1),
                    self.roster_view.replace(ROSTER_CURRENT_BLOCK, ROSTER_CURRENT_BLOCK * 2, 1),
                    self.roster_view.replace('rowView(row, access: snapshot.access)', 'Text("changed")', 1),
                    self.roster_view.replace('guard state.isCurrent, !state.isBusy', 'guard true', 1),
                    self.roster_view.replace('guard appearance === visibleAppearance else { return }', 'if false { return }', 1)]
        for source in variants:
            with self.assertRaises(ValueError):
                before_roster_source(source)

    def test_customer_exact_inverse_preserves_all_existing_layers(self):
        self.assertEqual(digest(self.customer_view), CUSTOMER_VIEW_SHA256)
        self.assertEqual(digest(before_customer_detail_source(self.customer_view)), SETTLEMENT_VIEW_SHA256)
        self.assertEqual(digest(original_home_source(self.customer_view)), BASE_VIEW_SHA256)

    def test_customer_inverse_rejects_missing_duplicate_and_unrelated_edits(self):
        for source in [self.customer_view + '\n',
                       self.customer_view.replace(CUSTOMER_CURRENT_BLOCK, '', 1),
                       self.customer_view.replace(CUSTOMER_CURRENT_BLOCK, CUSTOMER_CURRENT_BLOCK * 2, 1),
                       self.customer_view.replace('rowActions(row, access: snapshot.access)', 'Text("changed")', 1),
                       self.customer_view.replace('guard state.isCurrent, !state.isBusy', 'guard true', 1),
                       self.customer_view.replace('guard appearance === visibleAppearance else { return }', 'if false { return }', 1)]:
            with self.assertRaises(ValueError):
                before_customer_detail_source(source)

    def test_settlement_exact_inverse_preserves_both_existing_layers(self):
        self.assertEqual(digest(self.settlement_view), SETTLEMENT_VIEW_SHA256)
        self.assertEqual(digest(before_settlement_source(self.settlement_view)), AFTERCARE_VIEW_SHA256)
        self.assertEqual(self.settlement_view.count(SETTLEMENT_CURRENT_BLOCK), 1)
        self.assertEqual(digest(original_home_source(before_settlement_source(self.settlement_view))), BASE_VIEW_SHA256)

    def test_settlement_inverse_rejects_missing_duplicate_changed_gate_and_unrelated_edits(self):
        sources = [
            self.settlement_view.replace(SETTLEMENT_CURRENT_BLOCK, '', 1),
            self.settlement_view.replace(SETTLEMENT_CURRENT_BLOCK, SETTLEMENT_CURRENT_BLOCK * 2, 1),
            self.settlement_view.replace('guard state.isCurrent, !state.isBusy, state.failureKey == nil', 'guard true', 1),
            self.settlement_view.replace('MerchantAftercareProgressView(progress: progress)', 'Text("altered")', 1),
            self.settlement_view.replace('guard appearance === visibleAppearance else { return }', 'if false { return }', 1),
            self.settlement_view.replace('private var loadGeneration = 0', 'private var loadGeneration = 1', 1),
        ]
        for source in sources:
            with self.assertRaises(ValueError):
                before_settlement_source(source)

    def test_aftercare_exact_inverse_leaves_home_and_all_other_code_unchanged(self):
        self.assertEqual(digest(self.aftercare_view), AFTERCARE_VIEW_SHA256)
        self.assertEqual(digest(before_aftercare_source(self.aftercare_view)), CURRENT_VIEW_SHA256)
        self.assertEqual(self.aftercare_view.count(AFTERCARE_CURRENT_BLOCK), 1)
        self.assertEqual(original_home_source(self.aftercare_view), original_home_source(self.view))

    def test_aftercare_adapter_rejects_mutation_duplication_missing_block_and_home_edits(self):
        sources = [
            self.aftercare_view.replace('MerchantAftercareProgressView(progress: progress)', 'Text("altered")', 1),
            self.aftercare_view.replace(AFTERCARE_CURRENT_BLOCK, AFTERCARE_CURRENT_BLOCK * 2, 1),
            self.aftercare_view.replace(AFTERCARE_CURRENT_BLOCK, '', 1),
            self.aftercare_view.replace('guard appearance === visibleAppearance else { return }', 'if false { return }', 1),
            self.aftercare_view.replace('private var loadGeneration = 0', 'private var loadGeneration = 1', 1),
        ]
        for source in sources:
            with self.assertRaises(ValueError):
                original_home_source(source)

    def test_exact_inverse_preserves_all_business_source_outside_home(self):
        original = original_home_source(self.view)
        self.assertEqual(digest(original), BASE_VIEW_SHA256)
        self.assertEqual(self.view.split(CURRENT_HOME), original.split(OLD_HOME))

    def test_cancelled_late_entry_is_rejected_before_all_load_mutation(self):
        load = self.model.split('    func load(reader:', 1)[1].split('    private func finish(', 1)[0]
        first_guard = load.index('guard !Task.isCancelled else { return }')
        self.assertLess(first_guard, load.index('claimedRequestID = captured.id'))
        self.assertLess(first_guard, load.index('pending = task'))
        self.assertNotIn('cancelRead()', load)
        self.assertNotIn('owner =', load)
        self.assertNotIn('begin(', load)
        self.assertIn('claimedRequestID == nil else { return }', load)

    def test_queued_refresh_has_full_admission_before_clearing_new_owner(self):
        refresh = self.model.split('    func refresh(reader:', 1)[1].split('    func end(', 1)[0]
        for fence in ['!Task.isCancelled', 'appearance === expected', '!expected.retired',
                      'isCurrent(reader)', 'context == captured else { return }']:
            self.assertLess(refresh.index(fence), refresh.index('cancelRead()'))
        self.assertLess(refresh.index('accessValue = nil'), refresh.index('request = .init'))
        self.assertNotIn('begin(', refresh)

    def test_retired_appearance_never_reactivates(self):
        begin = self.model.split('    func begin(reader:', 1)[1].split('    func refresh(', 1)[0]
        self.assertLess(begin.index('!next.started, !next.retired'), begin.index('next.started = true'))
        self.assertNotIn('retired = false', begin)
        self.assertIn('let replacement = MerchantBusinessAccessAppearance()', CURRENT_HOME)
        self.assertIn('appearance === visibleAppearance', CURRENT_HOME)
        self.assertIn('newKey == renderedKey', CURRENT_HOME)
        self.assertIn('accessModel.isActive(appearance: visibleAppearance)', CURRENT_HOME)

    def test_stale_disappearance_cannot_clear_replacement(self):
        end = self.model.split('    func end(', 1)[1].split('    private func cancelRead', 1)[0]
        self.assertLess(end.index('guard appearance === expected'), end.index('cancelRead()'))
        self.assertIn('if appearance === visibleAppearance { appearance = MerchantBusinessAccessAppearance() }', CURRENT_HOME)

    def test_one_view_owned_task_consumes_captured_request(self):
        self.assertEqual(CURRENT_HOME.count('.task('), 1)
        self.assertNotIn('Task {', CURRENT_HOME)
        self.assertEqual(CURRENT_HOME.count('await accessModel.load(reader: reader, request: queuedRequest)'), 1)
        self.assertIn('let queuedRequest = accessModel.request', CURRENT_HOME)
        self.assertIn('let visibleAppearance = appearance', CURRENT_HOME)
        self.assertIn('let renderedKey = accessKey', CURRENT_HOME)
        self.assertEqual(CURRENT_HOME.count('accessModel.refresh(reader: reader, appearance: visibleAppearance, context: renderedKey)'), 2)
        self.assertIn('.onDisappear {\n            accessModel.end(appearance: visibleAppearance)', CURRENT_HOME)

    def test_success_error_and_cleanup_use_same_ticket_context_and_owner(self):
        validate_model(self.model)
        finish = self.model.split('    private func finish(', 1)[1]
        self.assertLess(finish.index('guard request == captured'), finish.index('loading = false'))
        self.assertLess(finish.index('guard !Task.isCancelled'), finish.index('switch result'))
        self.assertIn('case .failure(let error):\n            accessValue = nil', finish)
        self.assertEqual(self.model.count('try await reader.access()'), 1)
        self.assertIn('task.cancel()', self.model)

    def test_context_drift_finish_does_not_retire_visible_appearance_before_change(self):
        finish = self.model.split('    private func finish(', 1)[1]
        rejected = finish.split('guard !Task.isCancelled, isCurrent(reader) else {', 1)[1].split('return', 1)[0]
        self.assertIn('cancelRead()', rejected)
        self.assertIn('accessValue = nil; issueKey = nil; loading = false', rejected)
        self.assertNotIn('end(appearance:', rejected)
        self.assertNotIn('retired =', rejected)
        self.assertNotIn('appearance = nil', rejected)
        self.assertIn('accessModel.isActive(appearance: visibleAppearance)', CURRENT_HOME)

    def test_live_projection_does_not_reuse_stale_grants(self):
        for token in ['private var owner: (any MerchantBusinessReading)?',
                      'isCurrent(reader) ? accessValue : nil', 'isCurrent(reader) ? issueKey : nil',
                      'isCurrent(reader) && loading', 'appearance?.retired == false && owner === reader']:
            self.assertIn(token, self.model)

    def test_route_retains_original_dependencies_and_current_context(self):
        route = self.model.split('struct MerchantBusinessHomeRoute:', 1)[1].split('/// Owns only', 1)[0]
        for token in ['let reader: any MerchantBusinessReading', 'let journal: any MerchantBusinessIntentStore',
                      'self.reader === reader && self.journal === journal &&',
                      'context == MerchantBusinessAccessLoadKey(reader: reader)']:
            self.assertIn(token, route)
        self.assertNotIn('appearance', route)
        self.assertIn('route.isCurrent(reader: reader, journal: journal)', CURRENT_HOME)
        self.assertIn('MerchantBusinessPage(reader: route.reader, journal: route.journal, query: query)', CURRENT_HOME)
        self.assertIn('CityNodeRedeemView(reader: route.reader, journal: route.journal)', CURRENT_HOME)

    def test_stable_destination_host_is_outside_conditional_access_rows(self):
        self.assertEqual(CURRENT_HOME.count('.navigationDestination(for:'), 1)
        self.assertGreater(CURRENT_HOME.index('.navigationDestination(for:'), CURRENT_HOME.index('.appNavigationTitle'))
        self.assertEqual(CURRENT_HOME.count('NavigationLink(value:'), 3)
        for target in ['.query(query)', '.scan', '.cityNode']:
            self.assertIn('MerchantBusinessHomeRoute(target: ' + target, CURRENT_HOME)
        self.assertIn('nativeVerificationDestination()', CURRENT_HOME)
        self.assertIn('MerchantScanPreviewView()', CURRENT_HOME)
        self.assertIn('Text("merchant.business.stale")', CURRENT_HOME)

    def test_original_entry_permissions_labels_and_queries_remain(self):
        for token in ['.aftercare(.pending, page: 1)', '.redemptions(filter: "all", page: 1)',
                      '.entries(source: "all", page: 1)', '.batches(page: 1)', '.verificationRecords',
                      'access.require(query.permissions)', 'access.allows("merchant:verify")',
                      'merchant.business.open.scan', 'merchant.cityRedeem.entry',
                      '.appNavigationTitle("merchant.business.title")']:
            self.assertIn(token, OLD_HOME)
            self.assertIn(token, CURRENT_HOME)

    def test_no_new_endpoint_mutation_journal_or_privacy_side_effect(self):
        for absent in ['URLRequest', 'URLSession', '.execute(', '.reserve(', '.confirm(', '.write(',
                       'UserDefaults', 'Keychain', 'print(', 'Task.detached', 'Task.sleep', 'api/']:
            self.assertNotIn(absent, self.model)
        self.assertIn('api/merchant/access/me', (ROOT / 'Core/MerchantBusinessService.swift').read_text())

    def test_fence_mutations_and_unknown_source_fail_closed(self):
        for token in validate_model(self.model):
            with self.subTest(token=token), self.assertRaises(ValueError):
                validate_model(self.model.replace(token, '// removed', 1))
        for changed in [self.view + '\n', self.view.replace(CURRENT_HOME, OLD_HOME), self.view + CURRENT_HOME]:
            with self.assertRaises(ValueError): original_home_source(changed)

    def test_existing_bilingual_keys_are_reused(self):
        strings = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        for key in ['auth.notConfigured', 'merchant.signIn', 'merchant.business.loadFailed',
                    'merchant.business.title', 'merchant.checkingAccess', 'merchant.refreshAccess',
                    'merchant.business.stale']:
            self.assertIn(key, strings)
            self.assertEqual(set(strings[key]['localizations']), {'en', 'zh-Hans'})


if __name__ == '__main__':
    unittest.main()
