import SwiftUI

/// Single-page settlement read: overview, income entries and transfer batches
/// load, page and retry independently through the existing finance reader.
/// No section derives totals from another section's paged rows.
@MainActor final class MerchantSettlementOverviewModel: ObservableObject {
    let reader: any MerchantBusinessReading
    @Published private(set) var state = MerchantSettlementOverviewState()
    private var visible = false
    private var sceneActive = false
    init(reader: any MerchantBusinessReading) { self.reader = reader }

    var context: MerchantSettlementOverviewContext {
        .init(scope: reader.scope, authorizationGeneration: reader.authorizationGeneration)
    }
    var isLive: Bool { visible && sceneActive }

    func appear(active: Bool) {
        visible = true; sceneActive = active
        if active { state.bind(context) }
    }
    func sceneChanged(active: Bool) {
        sceneActive = visible && active
        if !sceneActive { state.invalidateAll() }
    }
    func disappear() { visible = false; sceneActive = false; state.invalidateAll() }
    func ownerChanged() { state.invalidateAll(); state.bind(context) }
    func refreshBatchesAfterReturn() {
        guard isLive else { return }
        let page = state.section(.batches).page
        Task { await load(.batches, page: page) }
    }

    func loadAll() async {
        guard isLive else { return }
        async let overview: Void = load(.overview, page: 1)
        async let entries: Void = load(.entries, page: 1)
        async let batches: Void = load(.batches, page: 1)
        _ = await (overview, entries, batches)
    }

    func load(_ section: MerchantSettlementOverviewSection, page: Int) async {
        guard isLive, reader.isConfigured, reader.scope != nil else { return }
        let expected = context
        guard let generation = state.begin(section, page: page, context: expected) else { return }
        do {
            let snapshot = try await reader.snapshot(section.query(page: page))
            guard isLive, !Task.isCancelled else { return }
            _ = state.succeed(section, generation: generation, context: expected, snapshot: snapshot)
        } catch {
            guard isLive, !Task.isCancelled else { return }
            _ = state.fail(section, generation: generation, context: expected, key: Self.failureKey(error))
        }
    }

    func retry(_ section: MerchantSettlementOverviewSection) {
        let page = state.section(section).page
        Task { await load(section, page: page) }
    }
    func move(_ section: MerchantSettlementOverviewSection, by delta: Int) {
        let current = state.section(section)
        let next = current.page + delta
        guard next >= 1, delta < 0 || current.hasMore else { return }
        Task { await load(section, page: next) }
    }

    static func failureKey(_ error: Error) -> String {
        if let failure = error as? MerchantBusinessFailure { return failure.key }
        if error as? APIError == .unauthorized { return "auth.expired" }
        if error as? APIError == .notConfigured { return "auth.notConfigured" }
        if error is CancellationError { return "merchant.business.stale" }
        return "merchant.business.loadFailed"
    }
}

@MainActor struct MerchantSettlementOverviewView: View {
    let reader: any MerchantBusinessReading
    @StateObject private var model: MerchantSettlementOverviewModel
    @Environment(\.scenePhase) private var scenePhase
    init(reader: any MerchantBusinessReading) {
        self.reader = reader
        _model = StateObject(wrappedValue: MerchantSettlementOverviewModel(reader: reader))
    }

    var body: some View {
        List {
            if reader.isOfflineExample {
                Text("merchant.business.synthetic").font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("merchant.settlementOverview.synthetic")
            }
            sectionView(.overview)
            sectionView(.entries)
            sectionView(.batches)
            if !model.state.section(.overview).isLoading {
                Button("merchant.business.refresh") { Task { await model.loadAll() } }
                    .accessibilityIdentifier("merchant.settlementOverview.refresh")
            }
        }
        .navigationTitle(Text("merchant.settlementOverview.title", tableName: "MerchantSettlementOverview"))
        .task { model.appear(active: scenePhase == .active); await model.loadAll() }
        .refreshable { await model.loadAll() }
        .onAppear { model.appear(active: scenePhase == .active) }
        .onDisappear { model.disappear() }
        .onChange(of: scenePhase) { _, phase in
            model.sceneChanged(active: phase == .active)
            if phase == .active { Task { await model.loadAll() } }
        }
        .onChange(of: reader.scope) { _, _ in model.ownerChanged() }
        .onChange(of: reader.authorizationGeneration) { _, _ in model.ownerChanged() }
    }

    @ViewBuilder private func sectionView(_ section: MerchantSettlementOverviewSection) -> some View {
        let content = model.state.section(section)
        Section {
            switch content.phase {
            case .notLoaded:
                Text("merchant.settlementOverview.notLoaded", tableName: "MerchantSettlementOverview")
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView("merchant.loading")
                    .accessibilityIdentifier("merchant.settlementOverview.loading.\(section.rawValue)")
            case .failed:
                if let key = content.failureKey { Text(LocalizedStringKey(key)) }
                Button {
                    model.retry(section)
                } label: { Text("merchant.settlementOverview.retrySection", tableName: "MerchantSettlementOverview") }
                    .accessibilityIdentifier("merchant.settlementOverview.retry.\(section.rawValue)")
            case .loaded:
                loaded(section, content)
            }
        } header: { header(section) }
    }

    private func header(_ section: MerchantSettlementOverviewSection) -> Text {
        switch section {
        case .overview: return Text("merchant.business.overview")
        case .entries: return Text("merchant.settlementOverview.entries", tableName: "MerchantSettlementOverview")
        case .batches: return Text("merchant.settlementOverview.batches", tableName: "MerchantSettlementOverview")
        }
    }

    @ViewBuilder private func loaded(_ section: MerchantSettlementOverviewSection,
                                     _ content: MerchantSettlementOverviewSectionState) -> some View {
        if let snapshot = content.snapshot {
            switch section {
            case .overview:
                if snapshot.document.summary.isEmpty {
                    Text("merchant.business.empty").foregroundStyle(.secondary)
                }
                ForEach(MerchantBusinessDocument.overviewMoneyKeys + ["adjustmentPendingCount"], id: \.self) { key in
                    if let value = snapshot.document.summary[key] {
                        if key == "personalArrivedThisMonthNet" {
                            MerchantLedgerNetSummary(presentation: .init(value: value))
                        } else {
                            MerchantBusinessField(key: key, value: value,
                                                  money: MerchantBusinessDocument.overviewMoneyKeys.contains(key))
                        }
                    }
                }
            case .entries:
                if content.rows.isEmpty {
                    Text("merchant.settlementOverview.emptyEntries", tableName: "MerchantSettlementOverview")
                        .foregroundStyle(.secondary)
                }
                ForEach(content.rows) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.title).font(.headline)
                        MerchantBusinessRecordFields(row: row, access: snapshot.access, compact: false, settlementEntries: true)
                    }.accessibilityIdentifier("merchant.settlementOverview.entry.\(row.id)")
                }
                pageControls(section, content)
            case .batches:
                if content.rows.isEmpty {
                    Text("merchant.settlementOverview.emptyBatches", tableName: "MerchantSettlementOverview")
                        .foregroundStyle(.secondary)
                }
                ForEach(content.rows) { row in
                    if let id = Int(row.id) {
                        NavigationLink {
                            MerchantSettlementBatchDetailView(reader: reader, batchID: id) {
                                model.refreshBatchesAfterReturn()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.title).font(.headline)
                                MerchantBusinessRecordFields(row: row, access: snapshot.access, compact: true)
                            }
                        }.accessibilityIdentifier("merchant.settlementOverview.batch.\(row.id)")
                    }
                }
                pageControls(section, content)
            }
        }
    }

    @ViewBuilder private func pageControls(_ section: MerchantSettlementOverviewSection,
                                           _ content: MerchantSettlementOverviewSectionState) -> some View {
        if content.hasMore || content.page > 1 {
            HStack {
                Button("merchant.business.previous") { model.move(section, by: -1) }
                    .disabled(content.page <= 1)
                    .accessibilityIdentifier("merchant.settlementOverview.previous.\(section.rawValue)")
                Spacer()
                Text("\(content.page)").monospacedDigit().accessibilityLabel(Text("merchant.business.page"))
                Spacer()
                Button("merchant.business.next") { model.move(section, by: 1) }
                    .disabled(!content.hasMore)
                    .accessibilityIdentifier("merchant.settlementOverview.next.\(section.rawValue)")
            }
        }
    }
}
