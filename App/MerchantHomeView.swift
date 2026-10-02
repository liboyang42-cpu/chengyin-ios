import SwiftUI

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
    @StateObject private var access = MerchantLoadModel<MerchantAccess>()

    var body: some View {
        ZStack {
            if !reader.isConfigured {
                ContentUnavailableView("merchant.title", systemImage: "network.slash", description: Text("auth.notConfigured"))
            } else if !reader.isSignedIn {
                ContentUnavailableView("merchant.title", systemImage: "person.crop.circle.badge.exclamationmark", description: Text("merchant.signIn"))
            } else if access.loadedRevision == reader.sessionRevision, let identity = access.value {
                if identity.active {
                    MerchantWorkbench(reader: reader, access: identity, marketingModel: marketingModel, marketingDestination: marketingDestination, operationsReader: operationsReader, operationsDestinationFactory: operationsDestinationFactory, businessReader: businessReader, businessJournal: businessJournal, contentService: contentService, cooperationFlowReader: cooperationFlowReader, engagementReader: engagementReader, exportRecovery: exportRecovery, refreshAccess: reload)
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
    let refreshAccess: () async -> Void
    @StateObject private var dashboard = MerchantLoadModel<MerchantDashboard>()
    @StateObject private var todo = MerchantLoadModel<MerchantTodo>()
    @StateObject private var events = MerchantLoadModel<[MerchantEvent]>()

    var body: some View {
        List {
            Section {
                Text(access.merchantName.flatMap { $0.isEmpty ? nil : $0 } ?? appLocalized("merchant.store",locale:locale))
                    .font(.headline).accessibilityIdentifier("merchant.store.name")
                if let role = access.role { Text(LocalizedStringKey(role.titleKey)).foregroundStyle(.secondary) }
                Text("merchant.readOnly").font(.footnote).foregroundStyle(.secondary)
            }
            if let marketingModel {
                // Source merchant tools expose this entry. Visibility is separate from service/AI/settlement grants.
                Section { MerchantMarketingEntry(model: marketingModel, isSourceVisible: true, suggestionDestination: marketingDestination) }
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
                    NavigationLink { MerchantBusinessHomeView(reader: businessReader, journal: businessJournal).id(businessReader.scope) } label: { Label("merchant.business.title", systemImage: "building.2.crop.circle") }
                        .accessibilityIdentifier("merchant.business.open")
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
                        if value.refundCount > 0 { MerchantCountRow("merchant.todo.refunds", value: value.refundCount) }
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
            if access.allows(.orders) || access.allows(.projects) {
                Section("merchant.records") {
                    if access.allows(.orders) {
                        NavigationLink { MerchantOrdersView(reader: reader) } label: { Label("merchant.orders", systemImage: "receipt") }
                            .accessibilityIdentifier("merchant.orders.entry")
                    }
                    if access.allows(.projects) {
                        NavigationLink { MerchantProjectsView(reader: reader) } label: { Label("merchant.projects", systemImage: "calendar") }
                            .accessibilityIdentifier("merchant.projects.entry")
                    }
                }
            } else if !access.isOwner {
                Text("merchant.access.noReadSurfaces").foregroundStyle(.secondary)
            }
            Button("merchant.refreshAccess") { Task { await refreshAccess() } }
        }
        .refreshable { await refreshAccess() }
        .task {
            async let d: Void = loadDashboard()
            async let t: Void = loadTodo()
            async let e: Void = loadEvents()
            _ = await (d, t, e)
        }
    }
    private func loadDashboard() async {
        guard access.canReadDashboard else { return }
        await dashboard.load(reader: reader) { try await reader.merchantDashboard(access: access) }
    }
    private func loadTodo() async {
        guard access.isOwner else { return }
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
