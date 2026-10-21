import SwiftUI
import UIKit

/// Three ledger sections on one page. A batch card pushes a child cover; that
/// disappearance does not retire the sections. Popping the cover refreshes batches
/// once for that presentation. Scope or permission retirement clears loading and
/// the previous error before the next read starts.
@MainActor final class MerchantLedgerSettlementModel: ObservableObject {
    let reader: any MerchantBusinessReading
    @Published private(set) var state = MerchantLedgerSettlementRead()
    private var tasks: [MerchantLedgerSettlementSection: Task<Void, Never>] = [:]
    private var started = false
    init(reader: any MerchantBusinessReading) { self.reader = reader }
    deinit { tasks.values.forEach { $0.cancel() } }

    private var currentOwner: MerchantLedgerSettlementOwner {
        .init(scope: reader.scope, authorizationGeneration: reader.authorizationGeneration)
    }
    @discardableResult private func mutate<T>(_ body: (inout MerchantLedgerSettlementRead) -> T) -> T {
        var copy = state
        let result = body(&copy)
        state = copy
        return result
    }
    private func cancelTasks() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    func appear() {
        let replaced = mutate { $0.replaceOwner(currentOwner) }
        if replaced { cancelTasks(); started = false }
        guard reader.isConfigured, reader.scope != nil, replaced || !started else { return }
        started = true
        loadAll()
    }
    func overviewDisappeared() { mutate { $0.overviewDisappeared() } }
    func leave() {
        cancelTasks()
        started = false
        mutate { $0.leave() }
    }
    func openBatch(_ batchID: Int) { mutate { $0.presentBatch(batchID) } }
    func childPopped(_ cover: MerchantLedgerBatchCover?) {
        guard let cover else { return }
        guard mutate({ $0.consumePop(cover) }) else { return }
        load(.batches, page: state.batches.page)
    }
    func loadAll() {
        load(.overview, page: 1)
        load(.entries, page: 1)
        load(.batches, page: 1)
    }
    func load(_ section: MerchantLedgerSettlementSection, page: Int) {
        guard reader.isConfigured, reader.scope != nil else { return }
        let owner = currentOwner
        if mutate({ $0.replaceOwner(owner) }) { cancelTasks() }
        guard let ticket = mutate({ $0.begin(section, page: page, owner: owner) }) else { return }
        tasks[section]?.cancel()
        let task = Task { [weak self] in await self?.perform(section, ticket: ticket, owner: owner) }
        tasks[section] = task
    }

    private func perform(_ section: MerchantLedgerSettlementSection, ticket: Int, owner: MerchantLedgerSettlementOwner) async {
        let page = state.section(section).page
        do {
            let snapshot = try await reader.snapshot(section.query(page: page), isCurrent: { [weak self] in
                guard let self else { return false }
                let slot = self.state.section(section)
                return self.state.owner == owner && slot.generation == ticket && slot.isLoading && !Task.isCancelled
            })
            guard !Task.isCancelled else { mutate { $0.cancel(section, generation: ticket) }; return }
            _ = mutate { $0.succeed(section, generation: ticket, owner: owner, snapshot: snapshot) }
        } catch is CancellationError {
            mutate { $0.cancel(section, generation: ticket) }
        } catch {
            guard !Task.isCancelled else { mutate { $0.cancel(section, generation: ticket) }; return }
            mutate { $0.fail(section, generation: ticket, owner: owner, key: MerchantLedgerSettlementFailure.key(error)) }
        }
    }
}

@MainActor struct MerchantLedgerSettlementOverview: View {
    let reader: any MerchantBusinessReading
    @StateObject private var model: MerchantLedgerSettlementModel
    init(reader: any MerchantBusinessReading) {
        self.reader = reader
        _model = StateObject(wrappedValue: MerchantLedgerSettlementModel(reader: reader))
    }
    var body: some View {
        let cover = Binding<MerchantLedgerBatchCover?>(get: { model.state.cover }, set: { model.childPopped($0 == nil ? model.state.cover : nil) })
        List {
            if reader.isOfflineExample {
                Text("merchant.business.synthetic").font(.footnote).foregroundStyle(.secondary)
            }
            section(.overview)
            section(.entries)
            section(.batches)
            Button("merchant.business.refresh") { model.loadAll() }
                .accessibilityIdentifier("merchant.ledgerSettlement.refresh")
        }
        .navigationTitle(Text("merchant.business.overview"))
        .navigationDestination(item: cover) { item in
            MerchantLedgerBatchDetailView(reader: reader, batchID: item.batchID, owner: item.owner) { model.childPopped(item) }
                .id(item.id)
        }
        .background(MerchantLedgerSettlementLeaveAnchor(coveringChild: model.state.cover != nil, leave: { model.leave() }).frame(width: 0, height: 0))
        .onAppear { model.appear() }
        .onDisappear { model.overviewDisappeared() }
        .onChange(of: reader.scope) { _, _ in model.appear() }
        .onChange(of: reader.authorizationGeneration) { _, _ in model.appear() }
    }

    @ViewBuilder private func section(_ id: MerchantLedgerSettlementSection) -> some View {
        let slot = model.state.section(id)
        Section {
            switch slot.phase {
            case .idle:
                Text("merchant.ledgerSettlement.notLoaded", tableName: "MerchantLedgerSettlement").foregroundStyle(.secondary)
            case .loading:
                ProgressView("merchant.loading").accessibilityIdentifier("merchant.ledgerSettlement.loading." + id.rawValue)
            case .failed:
                if let key = slot.failureKey { Text(LocalizedStringKey(key)) }
                Button { model.load(id, page: slot.page) } label: {
                    Text("merchant.ledgerSettlement.retrySection", tableName: "MerchantLedgerSettlement")
                }.accessibilityIdentifier("merchant.ledgerSettlement.retry." + id.rawValue)
            case .loaded:
                loaded(id, slot)
            }
        } header: { Text(LocalizedStringKey(headerKey(id))) }
    }
    private func headerKey(_ id: MerchantLedgerSettlementSection) -> String {
        switch id {
        case .overview: return "merchant.business.overview"
        case .entries: return "merchant.business.entries"
        case .batches: return "merchant.business.batches"
        }
    }
    @ViewBuilder private func loaded(_ id: MerchantLedgerSettlementSection, _ slot: MerchantLedgerReadSlot) -> some View {
        if let snapshot = slot.snapshot {
            switch id {
            case .overview:
                let summary = snapshot.document.summary
                if summary.isEmpty { Text("merchant.business.empty").foregroundStyle(.secondary) }
                if let strip = MerchantLedgerParity.summary(summary, canReadFinance: snapshot.access.allows("merchant:finance:read")) {
                    MerchantLedgerSummaryStrip(summary: strip)
                }
                ForEach(MerchantBusinessDocument.overviewMoneyKeys + ["adjustmentPendingCount"], id: \.self) { key in
                    if key == "personalArrivedThisMonthNet" {
                        MerchantLedgerNetSummary(presentation: .init(value: summary[key]))
                    } else if let value = summary[key] {
                        MerchantBusinessField(key: key, value: value, money: MerchantBusinessDocument.overviewMoneyKeys.contains(key))
                    }
                }
            case .entries:
                if snapshot.document.rows.isEmpty {
                    Text("merchant.ledgerSettlement.emptyEntries", tableName: "MerchantLedgerSettlement").foregroundStyle(.secondary)
                }
                ForEach(snapshot.document.rows) { row in
                    MerchantLedgerRowLabel(line: MerchantLedgerParity.entry(row.fields), identifier: "merchant.ledgerSettlement.entry." + row.id)
                }
                pages(id, slot)
            case .batches:
                if snapshot.document.rows.isEmpty {
                    Text("merchant.ledgerSettlement.emptyBatches", tableName: "MerchantLedgerSettlement").foregroundStyle(.secondary)
                }
                ForEach(snapshot.document.rows) { row in
                    Button { if let batchID = Int(row.id) { model.openBatch(batchID) } } label: {
                        MerchantLedgerRowLabel(line: MerchantLedgerParity.batch(row.fields), identifier: "merchant.ledgerSettlement.batch." + row.id)
                    }.buttonStyle(.plain).accessibilityIdentifier("merchant.ledgerSettlement.open." + row.id)
                }
                pages(id, slot)
            }
        }
    }
    @ViewBuilder private func pages(_ id: MerchantLedgerSettlementSection, _ slot: MerchantLedgerReadSlot) -> some View {
        if slot.hasMore || slot.page > 1 {
            HStack {
                Button("merchant.business.previous") { model.load(id, page: slot.page - 1) }.disabled(slot.page <= 1 || slot.isLoading)
                Spacer()
                Text(slot.page, format: .number).monospacedDigit().accessibilityLabel(Text("merchant.business.page"))
                Spacer()
                Button("merchant.business.next") { model.load(id, page: slot.page + 1) }.disabled(!slot.hasMore || slot.isLoading)
            }
        }
    }
}

@MainActor final class MerchantLedgerBatchDetailModel: ObservableObject {
    let reader: any MerchantBusinessReading
    let batchID: Int
    private let onReturn: () -> Void
    @Published private(set) var state: MerchantLedgerBatchDetailRead
    private var task: Task<Void, Never>?
    private var returned = false
    init(reader: any MerchantBusinessReading, batchID: Int, owner: MerchantLedgerSettlementOwner, onReturn: @escaping () -> Void) {
        self.reader = reader
        self.batchID = batchID
        self.onReturn = onReturn
        state = .init(owner: owner)
    }
    deinit { task?.cancel() }
    private var currentOwner: MerchantLedgerSettlementOwner {
        .init(scope: reader.scope, authorizationGeneration: reader.authorizationGeneration)
    }
    private func mutate<T>(_ body: (inout MerchantLedgerBatchDetailRead) -> T) -> T {
        var copy = state
        let result = body(&copy)
        state = copy
        return result
    }
    func appear() {
        let owner = currentOwner
        if mutate({ $0.replaceOwner(owner) }) { task?.cancel(); task = nil }
        guard reader.isConfigured, reader.scope != nil, let batch = try? MerchantBatchID(batchID) else { return }
        guard let ticket = mutate({ $0.begin(owner: owner) }) else { return }
        let task = Task { [weak self] in await self?.perform(batch, ticket: ticket, owner: owner) }
        self.task = task
    }
    func disappear() {
        task?.cancel()
        mutate { $0.leave() }
        guard !returned else { return }
        returned = true
        onReturn()
    }
    private func perform(_ batch: MerchantBatchID, ticket: Int, owner: MerchantLedgerSettlementOwner) async {
        do {
            let snapshot = try await reader.snapshot(.batch(batch), isCurrent: { [weak self] in
                guard let self else { return false }
                return self.state.owner == owner && self.state.slot.generation == ticket && self.state.slot.isLoading && !Task.isCancelled
            })
            guard !Task.isCancelled else { mutate { $0.cancel(generation: ticket) }; return }
            _ = mutate { $0.succeed(generation: ticket, owner: owner, batchID: batch.rawValue, snapshot: snapshot) }
        } catch is CancellationError {
            mutate { $0.cancel(generation: ticket) }
        } catch {
            guard !Task.isCancelled else { mutate { $0.cancel(generation: ticket) }; return }
            mutate { $0.fail(generation: ticket, owner: owner, key: MerchantLedgerSettlementFailure.key(error)) }
        }
    }
}

@MainActor struct MerchantLedgerBatchDetailView: View {
    let reader: any MerchantBusinessReading
    let batchID: Int
    @StateObject private var model: MerchantLedgerBatchDetailModel
    init(reader: any MerchantBusinessReading, batchID: Int, owner: MerchantLedgerSettlementOwner, onReturn: @escaping () -> Void) {
        self.reader = reader
        self.batchID = batchID
        _model = StateObject(wrappedValue: MerchantLedgerBatchDetailModel(reader: reader, batchID: batchID, owner: owner, onReturn: onReturn))
    }
    var body: some View {
        let slot = model.state.slot
        List {
            if slot.isLoading { ProgressView("merchant.loading") }
            if let key = slot.failureKey {
                Text(LocalizedStringKey(key))
                Button("action.retry") { model.appear() }.disabled(slot.isLoading)
            }
            if let snapshot = slot.snapshot, let batch = snapshot.document.sections.first(where: { $0.id == "batch" })?.rows.first {
                let count = detailCount(snapshot.document)
                Section {
                    MerchantLedgerBatchHero(hero: MerchantLedgerParity.batchHero(batch.fields))
                    MerchantLedgerBatchStatementCard(statement: MerchantLedgerParity.batchStatementSummary(batch.fields, lineCount: count))
                    if count > 0 {
                        Text(verbatim: returnedLineCount(count)).font(.footnote)
                    }
                    Text("merchant.ledgerSettlement.detailIncomplete", tableName: "MerchantLedgerSettlement")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                detailRows(snapshot.document, id: "earnings")
                detailRows(snapshot.document, id: "adjustments")
            }
        }
        .navigationTitle(Text("merchant.business.batch"))
        .onAppear { model.appear() }
        .onDisappear { model.disappear() }
        .onChange(of: reader.scope) { _, _ in model.appear() }
        .onChange(of: reader.authorizationGeneration) { _, _ in model.appear() }
    }
    private func detailCount(_ document: MerchantBusinessDocument) -> Int {
        document.sections.reduce(0) { count, section in
            section.id == "earnings" || section.id == "adjustments" ? count + section.rows.count : count
        }
    }
    private func returnedLineCount(_ count: Int) -> String {
        let format = Bundle.main.localizedString(forKey: "merchant.ledgerSettlement.returnedDetails %lld", value: "Detail lines returned in this response: %lld", table: "MerchantLedgerSettlement")
        return String(format: format, locale: Locale.current, Int64(count))
    }
    @ViewBuilder private func detailRows(_ document: MerchantBusinessDocument, id: String) -> some View {
        let rows = document.sections.first(where: { $0.id == id })?.rows ?? []
        if !rows.isEmpty {
            Section {
                ForEach(rows) { row in
                    MerchantLedgerRowLabel(line: MerchantLedgerParity.entry(row.fields), identifier: "merchant.ledgerSettlement." + id + "." + row.id)
                }
            }
        }
    }
}

/// Removing the overview retires its snapshots. A pushed batch cover is not removal:
/// `onDisappear` of the overview does not call this leave.
@MainActor struct MerchantLedgerSettlementLeaveAnchor: UIViewControllerRepresentable {
    var coveringChild: Bool
    var leave: () -> Void
    final class Coordinator {
        var coveringChild: Bool
        var leave: () -> Void
        init(coveringChild: Bool, leave: @escaping () -> Void) { self.coveringChild = coveringChild; self.leave = leave }
    }
    func makeCoordinator() -> Coordinator { Coordinator(coveringChild: coveringChild, leave: leave) }
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.coveringChild = coveringChild
        context.coordinator.leave = leave
    }
    static func dismantleUIViewController(_ controller: UIViewController, coordinator: Coordinator) {
        if coordinator.coveringChild { return }
        coordinator.leave()
    }
}
