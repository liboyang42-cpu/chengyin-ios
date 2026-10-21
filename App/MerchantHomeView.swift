import SwiftUI
import UIKit

/// Inject an observable session adapter; this view deliberately does not own root navigation.
@MainActor
struct MerchantHomeView<Reader: MerchantReading>: View {
    @ObservedObject var reader: Reader
    var marketingModel: MerchantMarketingCoordinator? = nil
    var marketingDestination: ((MerchantInsightDestination) -> AnyView)? = nil
    var openApplication: (() -> Void)? = nil
    var operationsReader: (any MerchantOperationsReading)? = nil
    var operationsDestinationFactory: ((MerchantOperationsDestination, MerchantOperationsAccess) -> AnyView)? = nil
    var businessReader: (any MerchantBusinessReading)? = nil
    var businessJournal: (any MerchantBusinessIntentStore)? = nil
    var contentService: (any MerchantContentServing)? = nil
    var cooperationFlowReader: (any CoopFlowReading)? = nil
    var engagementReader: (any MerchantEngagementReading)? = nil
    var exportRecovery: (any MerchantExportRecoveryStoring)? = nil
    var showsRecordLinks = true
    var predictionReader: MerchantPredictionReader? = nil
    @StateObject private var access = MerchantLoadModel<MerchantAccess>()

    var body: some View {
        ZStack {
            if !reader.isConfigured {
                ContentUnavailableView("merchant.title", systemImage: "network.slash", description: Text("auth.notConfigured"))
            } else if !reader.isSignedIn {
                ContentUnavailableView("merchant.title", systemImage: "person.crop.circle.badge.exclamationmark", description: Text("merchant.signIn"))
            } else if access.loadedRevision == reader.sessionRevision, let identity = access.value {
                if identity.active {
                    MerchantWorkbench(reader: reader, access: identity, marketingModel: marketingModel, marketingDestination: marketingDestination, operationsReader: operationsReader, operationsDestinationFactory: operationsDestinationFactory, businessReader: businessReader, businessJournal: businessJournal, contentService: contentService, cooperationFlowReader: cooperationFlowReader, engagementReader: engagementReader, exportRecovery: exportRecovery, showsRecordLinks: showsRecordLinks, predictionReader: predictionReader, refreshAccess: reload)
                        .id("\(reader.sessionRevision):\(identity.merchantID ?? 0):\(identity.role?.rawValue ?? "")")
                } else {
                    List {
                        Section {
                            if let name = identity.merchantName, !name.isEmpty { Text(name).font(.headline) }
                            Text(LocalizedStringKey(identity.application?.titleKey ?? "merchant.access.inactive"))
                                .accessibilityIdentifier("merchant.access.inactive")
                            Text("merchant.access.inactiveHint").foregroundStyle(.secondary)
                        }
                        if let openApplication {
                            Button("merchant.onboarding.openApplication", action: openApplication)
                                .accessibilityIdentifier("merchant.onboarding.entry")
                        }
                        Button("merchant.refreshAccess") { Task { await reload() } }
                            .accessibilityIdentifier("merchant.access.refresh")
                    }.refreshable { await reload() }
                }
            } else if let error = access.errorKey {
                MerchantFailureView(errorKey: error, identifier: "merchant.access", retry: { Task { await reload() } })
            } else {
                ProgressView("merchant.checkingAccess").accessibilityIdentifier("merchant.access.loading")
            }
        }
        .appNavigationTitle("merchant.title")
        .task(id: reader.sessionRevision) { await reload() }
    }
    private func reload() async {
        // The old grant is not usable while access is being checked again.
        await access.load(reader: reader, discardOldValue: true) { try await reader.merchantAccess() }
    }
}

@MainActor
private struct MerchantWorkbench<Reader: MerchantReading>: View {
    @Environment(\.locale) private var locale
    @Environment(\.merchantCoopCenterDestination) private var coopCenterDestination
    @ObservedObject var reader: Reader
    let access: MerchantAccess
    let marketingModel: MerchantMarketingCoordinator?
    let marketingDestination: ((MerchantInsightDestination) -> AnyView)?
    let operationsReader: (any MerchantOperationsReading)?
    let operationsDestinationFactory: ((MerchantOperationsDestination, MerchantOperationsAccess) -> AnyView)?
    let businessReader: (any MerchantBusinessReading)?
    let businessJournal: (any MerchantBusinessIntentStore)?
    let contentService: (any MerchantContentServing)?
    let cooperationFlowReader: (any CoopFlowReading)?
    let engagementReader: (any MerchantEngagementReading)?
    let exportRecovery: (any MerchantExportRecoveryStoring)?
    let showsRecordLinks: Bool
    let predictionReader: MerchantPredictionReader?
    let refreshAccess: () async -> Void
    @StateObject private var dashboard = MerchantLoadModel<MerchantDashboard>()
    @StateObject private var todo = MerchantLoadModel<MerchantTodo>()
    @StateObject private var events = MerchantLoadModel<[MerchantEvent]>()

    private func customerQueryDestination(source: any MerchantBusinessReading, journal: any MerchantBusinessIntentStore)
        -> (@MainActor (MerchantCustomerAppliedQuery) -> AnyView)? {
        guard let engagementReader, let exportRecovery else { return nil }
        let revision = reader.sessionRevision, merchant = access.merchantID
        return { selection in
            AnyView(MerchantCustomerQueryDestinationView(root: reader, source: source, engagement: engagementReader,
                journal: journal, exports: exportRecovery, selection: selection, revision: revision, merchantID: merchant))
        }
    }
    var body: some View {
        List {
            Section {
                Text(access.merchantName.flatMap { $0.isEmpty ? nil : $0 } ?? appLocalized("merchant.store",locale:locale))
                    .font(.headline).accessibilityIdentifier("merchant.store.name")
                if let role = access.role { Text(LocalizedStringKey(role.titleKey)).foregroundStyle(.secondary) }
                Text("merchant.readOnly").font(.footnote).foregroundStyle(.secondary)
            }
            MerchantWorkbenchReminders(todo: todo, access: access,
                aftercareRoute: businessReader.flatMap { reader in businessJournal.flatMap {
                    MerchantWorkbenchBusinessRoute(shortcut: .aftercare, reader: reader, journal: $0) } },
                predictionReader: predictionReader)
            if let marketingModel {
                // Source merchant tools expose this entry. Visibility is separate from service/AI/settlement grants.
                Section { MerchantMarketingEntry(model: marketingModel, isSourceVisible: true, suggestionDestination: marketingDestination,
                    recommendationOrigin: .init(merchantID: access.merchantID, readerScope: operationsReader?.scope)) }
            }
            if let operationsReader {
                Section {
                    NavigationLink {
                        MerchantOperationsHomeView(reader: operationsReader, destinationFactory: operationsDestinationFactory).id(operationsReader.scope)
                    } label: { Label("merchant.operations.title", systemImage: "slider.horizontal.3") }
                    .accessibilityIdentifier("merchant.operations.open")
                }
            }
            if let businessReader, let businessJournal {
                Section {
                    NavigationLink {
                        MerchantBusinessHomeView(reader: businessReader, journal: businessJournal)
                            .environment(\.merchantAftercareEvidenceDependencies, aftercareEvidenceDependencies(journal: businessJournal))
                            .environment(\.merchantCustomerQueryDestination, customerQueryDestination(source: businessReader, journal: businessJournal))
                            .id(businessReader.scope)
                    } label: { Label("merchant.business.title", systemImage: "building.2.crop.circle") }
                        .accessibilityIdentifier("merchant.business.open")
                    ForEach(MerchantWorkbenchBusinessShortcut.allCases) { shortcut in
                        if shortcut.isVisible(for: access), let route = MerchantWorkbenchBusinessRoute(shortcut: shortcut, reader: businessReader, journal: businessJournal) {
                            NavigationLink(value: route) {
                                Label(LocalizedStringKey(shortcut.query.titleKey), systemImage: shortcut.symbol)
                            }.accessibilityIdentifier("merchant.workbench.direct." + shortcut.rawValue)
                        }
                    }
                }
            }
            if let engagementReader, let businessJournal, let exportRecovery {
                Section {
                    NavigationLink {
                        MerchantEngagementHomeView(reader: engagementReader, journal: businessJournal,
                            exportRecovery: exportRecovery, businessReader: businessReader)
                            .id(engagementReader.scope)
                    } label: { Label("merchant.engagement.title", systemImage: "person.2.crop.square.stack") }
                    .accessibilityIdentifier("merchant.engagement.open")
                }
            }
            if let contentService {
                Section {
                    NavigationLink { MerchantContentHomeView(service: contentService)
                        .environment(\.merchantContentSupplyDestination, cooperationFlowReader.map { flowReader in
                            { source in AnyView(MerchantCooperationSupplyView(source: source, reader: flowReader)) }
                        }).id(contentService.scope) } label: { Label("merchant.content.title", systemImage: "map") }
                        .accessibilityIdentifier("merchant.content.open")
                }
            }
            if let coopCenterDestination {
                Section {
                    NavigationLink { coopCenterDestination(.plaza, nil) } label: { Label(mcc("merchantCoopCenter.title", locale), systemImage: "person.2.wave.2") }
                        .accessibilityIdentifier("merchant.coopCenter.open")
                }
            }
            if let cooperationFlowReader {
                Section {
                    NavigationLink { CooperationFlowWorkbench(reader: cooperationFlowReader, operationScope: "MERCHANT") } label: { Label("coopflow.title", systemImage: "person.2") }
                        .accessibilityIdentifier("merchant.cooperationFlows.open")
                }
            }
            if access.canReadDashboard {
                Section("merchant.revenue") {
                    MerchantSectionState(model: dashboard, retry: { Task { await loadDashboard() } }) { value in
                        Text(MerchantMoney.display(value.revenue)).font(.largeTitle).monospacedDigit()
                            .accessibilityIdentifier("merchant.dashboard.revenue")
                        if !value.revenue7d.isEmpty {
                            Text("merchant.revenue7d").font(.headline)
                            ForEach(Array(value.revenue7d.enumerated()), id: \.offset) { _, point in
                                LabeledContent(point.date, value: MerchantMoney.display(point.amount))
                            }
                        }
                    }
                }
            }
            if access.isOwner {
                Section("merchant.todo") {
                    MerchantSectionState(model: todo, retry: { Task { await loadTodo() } }) { value in
                        if !value.hasPendingWork { Text("merchant.todo.empty").foregroundStyle(.secondary) }
                        if value.pendingVerify > 0 { MerchantCountRow("merchant.todo.verify", value: value.pendingVerify) }
                        if value.pendingScanConfirm > 0 { MerchantCountRow("merchant.todo.scan", value: value.pendingScanConfirm) }
                        if value.pendingOrders > 0 { MerchantCountRow("merchant.todo.orders", value: value.pendingOrders) }
                        if access.canReadAftercare, value.refundCount > 0 { MerchantCountRow("merchant.todo.refunds", value: value.refundCount) }
                        if access.allows(.projects), value.pendingPredict > 0 { MerchantPredictionWorkbenchAlert(pending: value.pendingPredict) }
                        if value.verifiedCount > 0 { MerchantCountRow("merchant.todo.verified", value: value.verifiedCount) }
                    }
                }
                Section("merchant.events") {
                    MerchantSectionState(model: events, retry: { Task { await loadEvents() } }) { values in
                        if values.isEmpty { Text("merchant.events.empty").foregroundStyle(.secondary) }
                        ForEach(Array(values.enumerated()), id: \.offset) { _, event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.content)
                                Text(event.time).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if showsRecordLinks && (access.allows(.orders) || access.allows(.projects)) {
                Section("merchant.records") {
                    if access.allows(.orders) {
                        NavigationLink { MerchantOrdersView(reader: reader) } label: { Label("merchant.orders", systemImage: "receipt") }
                            .accessibilityIdentifier("merchant.orders.entry")
                    }
                    if access.allows(.projects) {
                        NavigationLink { MerchantProjectsView(reader: reader, contentService: contentService) } label: { Label("merchant.projects", systemImage: "calendar") }
                            .accessibilityIdentifier("merchant.projects.entry")
                    }
                }
            } else if !access.isOwner {
                Text("merchant.access.noReadSurfaces").foregroundStyle(.secondary)
            }
            Button("merchant.refreshAccess") { Task { await refreshAccess() } }
        }
        .navigationDestination(for: MerchantWorkbenchBusinessRoute.self) { route in
            if let businessReader, let businessJournal,
               route.isCurrent(reader: businessReader, journal: businessJournal) {
                MerchantBusinessPage(reader: route.reader, journal: route.journal, query: route.shortcut.query)
                    .environment(\.merchantAftercareEvidenceDependencies, aftercareEvidenceDependencies(journal: route.journal))
                    .environment(\.merchantCustomerQueryDestination, customerQueryDestination(source: route.reader, journal: route.journal))
                    .id(route)
            } else {
                Text("merchant.business.stale")
            }
        }
        .refreshable { await refreshAccess() }
        .task {
            async let d: Void = loadDashboard()
            async let t: Void = loadTodo()
            async let e: Void = loadEvents()
            _ = await (d, t, e)
        }
    }
    private func aftercareEvidenceDependencies(journal: any MerchantBusinessIntentStore) -> MerchantAftercareEvidenceDependencies? {
        guard let engagementReader, let exportRecovery else { return nil }
        return .init(reader: engagementReader, journal: journal, recovery: exportRecovery)
    }
    private func loadDashboard() async {
        guard access.canReadDashboard else { return }
        await dashboard.load(reader: reader) { try await reader.merchantDashboard(access: access) }
    }
    private func loadTodo() async {
        guard access.isOwner || access.canReadAftercare else { return }
        await todo.load(reader: reader) { try await reader.merchantTodo(access: access) }
    }
    private func loadEvents() async {
        guard access.isOwner else { return }
        await events.load(reader: reader) { try await reader.merchantEvents(access: access) }
    }
}

struct MerchantCountRow: View {
    let title: LocalizedStringKey
    let value: Int
    init(_ title: LocalizedStringKey, value: Int) { self.title = title; self.value = value }
    var body: some View { LabeledContent { Text(value, format: .number).monospacedDigit() } label: { Text(title) } }
}

@MainActor
struct MerchantSectionState<Value, Content: View>: View {
    @ObservedObject var model: MerchantLoadModel<Value>
    let retry: () -> Void
    let content: (Value) -> Content
    init(model: MerchantLoadModel<Value>, retry: @escaping () -> Void, @ViewBuilder content: @escaping (Value) -> Content) {
        self.model = model; self.retry = retry; self.content = content
    }
    var body: some View {
        if let value = model.value {
            if model.isLoading { ProgressView("merchant.refreshing") }
            if let error = model.errorKey {
                Text("merchant.stale").font(.footnote).foregroundStyle(.secondary)
                MerchantInlineFailure(errorKey: error, retry: retry)
            }
            content(value)
        } else if let error = model.errorKey {
            MerchantInlineFailure(errorKey: error, retry: retry)
        } else { ProgressView("merchant.loading") }
    }
}

struct MerchantInlineFailure: View {
    let errorKey: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(errorKey)).foregroundStyle(.secondary)
            if errorKey != "merchant.access.denied" && errorKey != "auth.expired" {
                Button("action.retry", action: retry)
            }
        }
    }
}

struct MerchantFailureView: View {
    let errorKey: String
    let identifier: String
    let retry: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label { Text(LocalizedStringKey(errorKey)).accessibilityIdentifier(identifier + ".error") }
                icon: { Image(systemName: errorKey == "merchant.access.denied" ? "lock" : "exclamationmark.triangle") }
        } actions: {
            if errorKey != "merchant.access.denied" && errorKey != "auth.expired" {
                Button("action.retry", action: retry).accessibilityIdentifier(identifier + ".retry")
            }
        }
    }
}

/// Entry choices carry no grant. The existing page performs its own fresh authorization read.
enum MerchantWorkbenchBusinessShortcut: String, CaseIterable, Identifiable {
    case customers, finance, aftercare
    var id: String { rawValue }
    var query: MerchantBusinessQuery {
        switch self {
        case .customers: return .customers(.init())
        case .finance: return .overview
        case .aftercare: return .aftercare(.pending, page: 1)
        }
    }
    var symbol: String {
        switch self {
        case .customers: return "person.2"
        case .finance: return "list.bullet.rectangle"
        case .aftercare: return "arrow.uturn.backward.circle"
        }
    }
}

/// Freeze the original dependencies, including authorization generation, before navigation.
/// Leaving Home for a child does not replace this route; a changed context invalidates it.
struct MerchantWorkbenchBusinessRoute: Hashable {
    let shortcut: MerchantWorkbenchBusinessShortcut
    private let value: MerchantBusinessHomeRoute
    var reader: any MerchantBusinessReading { value.reader }
    var journal: any MerchantBusinessIntentStore { value.journal }
    @MainActor init?(shortcut: MerchantWorkbenchBusinessShortcut, reader: any MerchantBusinessReading,
                     journal: any MerchantBusinessIntentStore) {
        guard reader.isConfigured, reader.scope != nil else { return nil }
        self.shortcut = shortcut
        value = .init(target: .query(shortcut.query), reader: reader, journal: journal)
    }
    @MainActor func isCurrent(reader: any MerchantBusinessReading, journal: any MerchantBusinessIntentStore) -> Bool {
        value.isCurrent(reader: reader, journal: journal)
    }
}

@MainActor private struct MerchantCustomerQueryDestinationView<Reader: MerchantReading>: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var root: Reader
    let selection: MerchantCustomerAppliedQuery
    let journal: any MerchantBusinessIntentStore
    let exports: any MerchantExportRecoveryStoring
    @StateObject private var reader: MerchantCustomerQueryReader
    init(root: Reader, source: any MerchantBusinessReading, engagement: any MerchantEngagementReading,
         journal: any MerchantBusinessIntentStore, exports: any MerchantExportRecoveryStoring,
         selection: MerchantCustomerAppliedQuery, revision: UInt64, merchantID: Int?) {
        self.root = root; self.selection = selection; self.journal = journal; self.exports = exports
        _reader = StateObject(wrappedValue: .init(selection: selection, base: engagement, source: source, originCurrent: {
            root.isConfigured && root.isSignedIn && root.sessionRevision == revision && merchantID == selection.merchantID
        }))
    }
    var body: some View {
        Group {
            if reader.isCurrent {
                MerchantEngagementHomeView(reader: reader, journal: journal, exportRecovery: exports,
                    filter: selection.filter).id(selection.id)
            } else { Text("merchant.business.stale") }
        }
        .background(MerchantCustomerQueryOwnerAnchor(reader: reader).frame(width: 0, height: 0))
        .onAppear { if scenePhase != .active { reader.retire() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { reader.retire() } }
    }
}


/// Navigation into an existing child does not end this captured query owner.
/// Actual owner removal does, including when a modal covers the parent.
@MainActor struct MerchantCustomerQueryOwnerAnchor: UIViewControllerRepresentable {
    let reader: MerchantCustomerQueryReader
    final class Coordinator {
        weak var reader: MerchantCustomerQueryReader?
        init(_ reader: MerchantCustomerQueryReader) { self.reader = reader }
    }
    func makeCoordinator() -> Coordinator { Coordinator(reader) }
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: UIViewController, coordinator: Coordinator) { coordinator.reader?.retire() }
}

