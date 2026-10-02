import SwiftUI

@MainActor final class MerchantBusinessViewModel: ObservableObject {
    let coordinator: MerchantBusinessCoordinator
    @Published private(set) var revision = 0
    init(reader: any MerchantBusinessReading, journal: any MerchantBusinessIntentStore) { coordinator = .init(reader: reader, journal: journal) }
    func load(_ query: MerchantBusinessQuery) async { revision += 1; await coordinator.load(query); revision += 1 }
    func prepare(_ mutation: MerchantBusinessMutation) { coordinator.prepare(mutation); revision += 1 }
    func cancel() { coordinator.cancelConfirmation(); revision += 1 }
    func confirm(_ review: MerchantBusinessConfirmation) async { revision += 1; await coordinator.confirm(review); revision += 1 }
    func invalidate() { coordinator.invalidate(); revision += 1 }
}

@MainActor struct MerchantBusinessHomeView: View {
    let reader: any MerchantBusinessReading
    let journal: any MerchantBusinessIntentStore
    @State private var access: MerchantBusinessAccess?
    @State private var issue: String?
    @State private var loading = false
    private let destinations: [MerchantBusinessQuery] = [.customers(.init()), .aftercare(.pending, page: 1), .reviews(page: 1), .overview,
        .redemptions(filter: "all", page: 1), .entries(source: "all", page: 1), .batches(page: 1), .verificationRecords, .operators]
    var body: some View {
        List {
            if reader.isOfflineExample { Text("merchant.business.synthetic").foregroundStyle(.secondary).accessibilityIdentifier("merchant.business.synthetic") }
            Text("merchant.business.boundary").font(.footnote).foregroundStyle(.secondary)
            if let access {
                Section {
                    Text(access.name ?? "#\(access.merchantID)").font(.title3.bold())
                    Text(LocalizedStringKey("merchant.business.role." + String(access.role)))
                }
                Section("merchant.business.workspace") {
                    ForEach(destinations, id: \.self) { query in
                        if (try? access.require(query.permissions)) != nil {
                            NavigationLink {
                                MerchantBusinessPage(reader: reader, journal: journal, query: query)
                            } label: { Label(LocalizedStringKey(query.titleKey), systemImage: symbol(query)) }
                            .accessibilityIdentifier("merchant.business.open.\(query.titleKey.split(separator: ".").last ?? "page")")
                        }
                    }
                    if access.allows("merchant:verify") {
                        NavigationLink { MerchantScanPreviewView() } label: { Label("merchant.business.scan", systemImage: "qrcode.viewfinder") }
                            .accessibilityIdentifier("merchant.business.open.scan")
                        NavigationLink { CityNodeRedeemView(reader: reader, journal: journal) } label: {
                            Label("merchant.cityRedeem.title", systemImage: "qrcode")
                        }.accessibilityIdentifier("merchant.cityRedeem.entry")
                    }
                }
            } else if loading { ProgressView("merchant.checkingAccess") }
            if let issue { Text(LocalizedStringKey(issue)).foregroundStyle(.secondary) }
            Button("merchant.refreshAccess") { Task { await load() } }.disabled(loading)
        }
        .appNavigationTitle("merchant.business.title")
        .task(id: reader.scope) { await load() }
        .refreshable { await load() }
    }
    private func symbol(_ query: MerchantBusinessQuery) -> String {
        switch query {
        case .customers: return "person.2"; case .aftercare: return "arrow.uturn.backward.circle"
        case .reviews: return "star.bubble"; case .overview, .entries, .batches: return "chart.bar.doc.horizontal"
        case .operators: return "person.badge.key"; default: return "list.bullet.rectangle"
        }
    }
    private func load() async {
        let scope = reader.scope; access = nil; issue = nil; loading = true
        defer { if reader.scope == scope { loading = false } }
        do {
            let value = try await reader.access()
            guard reader.scope == scope, !Task.isCancelled else { return }; access = value
        } catch {
            guard reader.scope == scope, !Task.isCancelled else { return }
            issue = (error as? MerchantBusinessFailure)?.key ?? (reader.isConfigured ? "merchant.business.loadFailed" : "auth.notConfigured")
        }
    }
}

@MainActor struct MerchantBusinessPage: View {
    let reader: any MerchantBusinessReading
    let journal: any MerchantBusinessIntentStore
    @State private var query: MerchantBusinessQuery
    @StateObject private var model: MerchantBusinessViewModel
    @State private var keyword = ""
    @State private var segment = "all"
    @State private var sourceType = 0
    @State private var sourceStart = ""
    @State private var sourceEnd = ""
    @State private var tagID = 0
    @State private var editor: MerchantBusinessEditorContext?
    @State private var selection: Set<Int> = []
    @State private var pendingMutation: MerchantBusinessMutation?
    init(reader: any MerchantBusinessReading, journal: any MerchantBusinessIntentStore, query: MerchantBusinessQuery) {
        self.reader = reader; self.journal = journal
        _query = State(initialValue: query); _model = StateObject(wrappedValue: .init(reader: reader, journal: journal))
    }
    private var state: MerchantBusinessCoordinator { model.coordinator }
    var body: some View {
        List {
            if reader.isOfflineExample { Text("merchant.business.synthetic").font(.footnote).foregroundStyle(.secondary) }
            filters
            if state.isBusy { ProgressView("merchant.loading").accessibilityIdentifier("merchant.business.loading") }
            if let key = state.failureKey {
                Section { Text(LocalizedStringKey(key)).accessibilityIdentifier("merchant.business.error")
                    if case .rejected(_, let message) = state.failure, let message { Text(message).foregroundStyle(.secondary) }
                }
            }
            if state.isLocked { Text("merchant.business.unknownResult").accessibilityIdentifier("merchant.business.locked") }
            if let receipt = state.receipt {
                Section("merchant.business.receipt") {
                    Text("merchant.business.syntheticSaved")
                    if let message = receipt.message { Text(message) }
                    if case .refund = query { Text(receipt.refundActuallyConfirmed ? "merchant.business.platformRefunded" : "merchant.business.opinionOnly") }
                    Button("action.retry") { Task { await reload() } }
                }
            }
            if let snapshot = state.snapshot, state.isCurrent {
                summary(snapshot.document)
                if case .customer = query, let tags = try? snapshot.document.payload.object?.mbObjects("systemTags") {
                    Section("merchant.business.systemTags") { ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in Text(tag.mbText("label") ?? "") } }
                }
                if snapshot.document.rows.isEmpty && snapshot.document.summary.isEmpty { Text("merchant.business.empty").foregroundStyle(.secondary) }
                ForEach(snapshot.document.sections) { section in
                    Section(LocalizedStringKey("merchant.business.section." + String(section.id))) {
                        ForEach(section.rows) { row in
                            rowView(row, access: snapshot.access)
                        }
                    }
                }
                pageActions(snapshot)
                if snapshot.document.hasMore || query.page > 1 {
                    Section {
                        HStack {
                            Button("merchant.business.previous") { movePage(query.page - 1) }.disabled(query.page <= 1)
                            Spacer()
                            Text("\(query.page)").monospacedDigit().accessibilityLabel(Text("merchant.business.page"))
                            Spacer()
                            Button("merchant.business.next") { movePage(query.page + 1) }.disabled(!snapshot.document.hasMore)
                        }
                    }
                }
            }
            if !state.isBusy { Button("merchant.business.refresh") { Task { await reload() } }.accessibilityIdentifier("merchant.business.refresh") }
        }
        .appNavigationTitle(key: query.titleKey)
        .task(id: reader.scope) { await reload() }
        .refreshable { await reload() }
        .sheet(item: $editor, onDismiss: { if let mutation = pendingMutation { pendingMutation = nil; model.prepare(mutation) } }) { context in
            MerchantBusinessEditor(context: context, snapshot: state.snapshot, onReview: { mutation in
                pendingMutation = mutation; editor = nil
            })
        }
        .sheet(item: Binding(get: { state.confirmation }, set: { if $0 == nil { model.cancel() } })) { review in
            MerchantBusinessReviewSheet(review: review, canExecute: reader.canExecuteSyntheticMutation, busy: state.isBusy,
                issue: state.failureKey, cancel: model.cancel, confirm: { Task { await model.confirm(review) } })
        }
        .onChange(of: reader.scope) { _, _ in editor = nil; pendingMutation = nil; selection = []; model.invalidate() }
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
                Button("merchant.business.applyFilter", action: applyCustomerFilter)
            }
        }
        if case .aftercare(let bucket, _) = query {
            Picker("merchant.business.bucket", selection: Binding(get: { bucket }, set: { query = .aftercare($0, page: 1); Task { await reload() } })) {
                ForEach(MerchantAftercareBucket.allCases, id: \.self) { Text(LocalizedStringKey("merchant.business.bucket." + String($0.rawValue))).tag($0) }
            }.accessibilityIdentifier("merchant.business.bucket")
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
                ForEach(MerchantBusinessDocument.overviewMoneyKeys + ["adjustmentPendingCount", "count", "pendingAmount", "arrivedAmount", "averageRating", "all", "repeat", "new", "noted", "monthlyNew"], id: \.self) { key in
                    if let value = document.summary[key] {
                        MerchantBusinessField(key: key, value: value, money: MerchantBusinessDocument.overviewMoneyKeys.contains(key) || ["pendingAmount", "arrivedAmount"].contains(key))
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
                MerchantBusinessRecordFields(row: row, access: access, compact: false)
                rowActions(row, access: access)
            }.accessibilityIdentifier("merchant.business.row.\(row.kind.rawValue).\(row.id)")
        }
    }
    @ViewBuilder private func rowActions(_ row: MerchantBusinessRecord, access: MerchantBusinessAccess) -> some View {
        if row.kind == .review {
            ForEach(MerchantReviewReplyAction.allCases, id: \.self) { action in
                let key = action == .reply ? "canReply" : action == .report ? "canReport" : "canEditReply"
                if row.fields[key]?.bool == true {
                    Button(LocalizedStringKey("merchant.business.review." + String(action.rawValue))) { editor = .init(kind: .review(row, action)) }
                }
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
