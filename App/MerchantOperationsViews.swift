import SwiftUI

@MainActor
struct MerchantOperationsHomeView: View {
    let reader: any MerchantOperationsReading
    var destinationFactory: ((MerchantOperationsDestination, MerchantOperationsAccess) -> AnyView)? = nil
    @State private var access: MerchantOperationsAccess?
    @State private var issue: MerchantOperationsIssue?
    @State private var loadedScope: UUID?
    @State private var loading = false
    @State private var generation = 0
    private let destinations: [MerchantOperationsDestination] = [.profile, .decor, .gallery, .story, .cooperation, .character, .assets, .cityNodes, .templates]
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                MerchantOperationsBoundary(isExample: reader.isOfflineExample)
                if loadedScope == reader.scope, let access {
                    ForEach(destinations.filter { access.allows($0) }) { destination in
                        NavigationLink {
                            if let destinationFactory { destinationFactory(destination, access) }
                            else { MerchantOperationsDocumentView(reader: reader, destination: destination) }
                        } label: {
                            QuestifyImageEntityCard(imageSource: nil, title: "", fallbackTitle: LocalizedStringKey(destination.titleKey), fallbackSymbol: symbol(destination), minimumHeight: 180) {
                                Text("merchant.operations.entryHint")
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("merchant.operations.entry." + destination.id)
                    }
                    if !access.identity.active { Text("merchant.access.inactive").foregroundStyle(.secondary) }
                } else if let issue, loadedScope == reader.scope {
                    MerchantOperationsIssueView(issue: issue)
                    Button("action.retry") { Task { await load() } }.accessibilityIdentifier("merchant.operations.retry")
                } else { ProgressView("merchant.loading") }
            }.padding()
        }
        .appNavigationTitle("merchant.operations.title")
        .refreshable { await load() }
        .task(id: reader.scope) { await load() }
    }
    private func symbol(_ destination: MerchantOperationsDestination) -> String {
        switch destination { case .profile, .decor: return "storefront"; case .gallery: return "photo.on.rectangle"
        case .story: return "book.closed"; case .cooperation: return "person.2"; case .character: return "person.crop.circle"
        case .assets: return "waveform"; case .cityNodes: return "mappin.and.ellipse"; case .templates, .template: return "rectangle.grid.2x2" }
    }
    private func load() async {
        generation += 1; let request = generation, scope = reader.scope
        access = nil; issue = nil; loadedScope = nil; loading = true
        defer { if request == generation { loading = false } }
        do {
            guard reader.isConfigured else { throw APIError.notConfigured }
            let value = try await reader.access()
            guard !Task.isCancelled, request == generation, scope == reader.scope else { return }
            access = value; loadedScope = scope
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), request == generation, scope == reader.scope else { return }
            issue = .init(error); loadedScope = scope
        }
    }
}

@MainActor
final class MerchantOperationsViewModel: ObservableObject {
    let coordinator: MerchantOperationsCoordinator
    @Published private(set) var revision = 0
    let imageOwner: MerchantRetainedImageDocumentOwner?
    init(reader: any MerchantOperationsReading, destination: MerchantOperationsDestination, imageHost: MerchantRetainedImageHost? = nil) {
        coordinator = .init(reader: reader, destination: destination)
        imageOwner = imageHost?.document(reader: reader, destination: destination)
    }
    func load() async {
        imageOwner?.invalidate(); revision += 1
        await coordinator.load(); await imageOwner?.refresh(coordinator: coordinator); revision += 1
    }
    func edit(_ value: MerchantOperationsDraft) {
        coordinator.edit(value); imageOwner?.draftChanged(coordinator.draft); revision += 1
    }
    func imageContext(_ field: MerchantImageField) -> RetainedImageSelectionContext? { imageOwner?.context(field: field, coordinator: coordinator) }
    func prepare() { coordinator.prepare(); revision += 1 }
    func cancel() { coordinator.cancelConfirmation(); revision += 1 }
    func discard() { coordinator.discardChanges(); imageOwner?.draftChanged(coordinator.draft); revision += 1 }
    func confirm(_ value: MerchantOperationsConfirmation) async {
        imageOwner?.invalidate(); revision += 1
        await coordinator.confirm(value); await imageOwner?.refresh(coordinator: coordinator); revision += 1
    }
    func invalidate() { imageOwner?.invalidate(); coordinator.invalidate(); revision += 1 }
    func leaveImages() { imageOwner?.invalidate(); revision += 1 }
    func refreshImages() async { await imageOwner?.refresh(coordinator: coordinator); revision += 1 }
}

@MainActor
struct MerchantOperationsDocumentView: View {
    let reader: any MerchantOperationsReading
    let destination: MerchantOperationsDestination
    let imageHost: MerchantRetainedImageHost?
    var templateAssistFactory: ((MerchantOperationsCoordinator) -> MerchantTemplateAssistFlow)? = nil
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: MerchantOperationsViewModel
    @State private var confirmDiscard = false
    @State private var confirmReload = false
    init(reader: any MerchantOperationsReading, destination: MerchantOperationsDestination, imageHost: MerchantRetainedImageHost? = nil, templateAssistFactory: ((MerchantOperationsCoordinator) -> MerchantTemplateAssistFlow)? = nil) {
        self.reader = reader; self.destination = destination; self.imageHost = imageHost; self.templateAssistFactory = templateAssistFactory
        _model = StateObject(wrappedValue: .init(reader: reader, destination: destination, imageHost: imageHost))
    }
    private var coordinator: MerchantOperationsCoordinator { model.coordinator }
    var body: some View {
        Group {
            if coordinator.isCurrent, let document = coordinator.document {
                switch document {
                case .draft:
                    MerchantOperationsEditor(model: model, templateAssistFactory: templateAssistFactory, imageContext: model.imageContext)
                case .cityNodes(let catalog): MerchantOperationsCityView(catalog: catalog)
                case .templates(let rows): MerchantOperationsTemplatesView(reader: reader, rows: rows, imageHost: imageHost, templateAssistFactory: templateAssistFactory)
                case .assets(let resources): MerchantOperationsAssetsView(resources: resources)
                }
            } else if let issue = coordinator.issue, coordinator.loadedScope == reader.scope {
                VStack(spacing: 20) {
                    MerchantOperationsIssueView(issue: issue)
                    Button("action.retry") { Task { await model.load() } }.accessibilityIdentifier("merchant.operations.retry")
                }.padding()
            } else { ProgressView("merchant.loading") }
        }
        .appNavigationTitle(key: destination.titleKey)
        .navigationBarBackButtonHidden(coordinator.isDirty)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("merchant.operations.reloadSource", systemImage: "arrow.clockwise") {
                    if coordinator.isDirty { confirmReload = true } else { Task { await model.load() } }
                }.disabled(coordinator.isBusy).accessibilityIdentifier("merchant.operations.reload")
            }
            if coordinator.isDirty {
                ToolbarItem(placement: .topBarLeading) {
                    Button("action.cancel") { confirmDiscard = true }
                        .accessibilityIdentifier("merchant.operations.close")
                }
            }
        }
        .interactiveDismissDisabled(coordinator.isDirty || coordinator.isBusy)
        .confirmationDialog("merchant.operations.discardTitle", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("merchant.operations.discard", role: .destructive) { model.discard(); dismiss() }
            Button("merchant.operations.keepEditing", role: .cancel) { }
        } message: { Text("merchant.operations.discardBody") }
        .confirmationDialog("merchant.operations.discardTitle", isPresented: $confirmReload, titleVisibility: .visible) {
            Button("merchant.operations.discardReload", role: .destructive) { model.discard(); Task { await model.load() } }
            Button("merchant.operations.keepEditing", role: .cancel) { }
        } message: { Text("merchant.operations.discardBody") }
        .sheet(item: Binding(get: { coordinator.isCurrent ? coordinator.confirmation : nil }, set: { if $0 == nil { model.cancel() } })) { confirmation in
            MerchantOperationsConfirmationView(model: model, confirmation: confirmation)
        }
        .task(id: reader.scope) { await model.load() }
        .onChange(of: reader.scope) { _, _ in model.invalidate() }
        .onDisappear { model.leaveImages() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.leaveImages() }
            else { Task { await model.refreshImages() } }
        }
    }
}

struct MerchantOperationsBoundary: View {
    let isExample: Bool
    var body: some View {
        Label(LocalizedStringKey(isExample ? "merchant.operations.exampleBoundary" : "merchant.operations.liveDisabled"), systemImage: "lock.shield")
            .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("merchant.operations.boundary")
    }
}
struct MerchantOperationsIssueView: View {
    let issue: MerchantOperationsIssue
    var body: some View {
        switch issue {
        case .key(let key): Text(LocalizedStringKey(key)).foregroundStyle(.secondary).accessibilityIdentifier("merchant.operations.issue")
        case .server(let text): Text(verbatim: text).foregroundStyle(.secondary).accessibilityIdentifier("merchant.operations.issue")
        }
    }
}

@MainActor
private struct MerchantOperationsTemplatesView: View {
    let reader: any MerchantOperationsReading
    let rows: [MerchantTemplateRecord]
    let imageHost: MerchantRetainedImageHost?
    var templateAssistFactory: ((MerchantOperationsCoordinator) -> MerchantTemplateAssistFlow)? = nil
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                MerchantOperationsBoundary(isExample: reader.isOfflineExample)
                Text("merchant.operations.templatePageLimit").font(.footnote).foregroundStyle(.secondary)
                NavigationLink("merchant.operations.newTemplate") { MerchantOperationsDocumentView(reader: reader, destination: .template(nil), imageHost: imageHost, templateAssistFactory: templateAssistFactory) }
                    .accessibilityIdentifier("merchant.operations.newTemplate")
                if rows.isEmpty { ContentUnavailableView("merchant.operations.empty", systemImage: "square.grid.2x2") }
                ForEach(rows) { row in
                    NavigationLink { MerchantOperationsDocumentView(reader: reader, destination: .template(row.id), imageHost: imageHost, templateAssistFactory: templateAssistFactory) } label: {
                        QuestifyImageEntityCard(imageSource: reader.isOfflineExample ? nil : row.imgUrl, title: row.title, subtitle: row.description, fallbackTitle: "merchant.operations.untitled", minimumHeight: 230) {
                            Text(LocalizedStringKey(templateStatus(row.status)))
                            if let method = row.validationMethod.flatMap(MerchantTemplateMethod.init(rawValue:)) { Text(LocalizedStringKey(method.titleKey)) }
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("merchant.operations.template." + String(row.id))
                }
            }.padding()
        }
    }
    private func templateStatus(_ status: Int?) -> String {
        switch status { case 0: return "merchant.operations.template.unpublished"; case 1: return "merchant.operations.template.published"
        case 2: return "merchant.operations.review.pending"; default: return "merchant.operations.review.unknown" }
    }
}

private struct MerchantOperationsCityView: View {
    let catalog: MerchantCityCatalog
    var body: some View {
        List {
            Section {
                Text("merchant.operations.cityReadOnly").font(.footnote)
                if let used = catalog.used, let max = catalog.max, used >= 0, max > 0 {
                    LabeledContent("merchant.operations.quota", value: "\(used) / \(max)")
                    if catalog.quotaExhausted { Text("merchant.operations.quotaExhausted").foregroundStyle(.secondary) }
                }
            }
            Section("merchant.operations.nodes") {
                if catalog.nodes.isEmpty { Text("merchant.operations.empty") }
                ForEach(catalog.nodes) { node in
                    NavigationLink {
                        List {
                            if let name = node.name { LabeledContent("merchant.operations.name", value: name) }
                            if let address = node.address { LabeledContent("merchant.operations.address", value: address) }
                            Text(LocalizedStringKey(node.status == 1 ? "merchant.operations.node.online" : node.status == 0 ? "merchant.operations.node.offline" : "merchant.operations.review.unknown"))
                            if let template = node.templateTitle { LabeledContent("merchant.operations.template", value: template) }
                            if let tags = node.tagsText { LabeledContent("merchant.operations.tags", value: tags) }
                            Text("merchant.operations.cityReadOnly").font(.footnote).foregroundStyle(.secondary)
                        }.appNavigationTitle("merchant.operations.nodeDetail")
                    } label: {
                        if let name = node.name, !name.isEmpty { Text(verbatim: name) } else { Text("merchant.operations.untitled") }
                    }.accessibilityIdentifier("merchant.operations.node." + String(node.id))
                }
            }
            Section("merchant.operations.applications") {
                if catalog.applications.isEmpty { Text("merchant.operations.empty") }
                ForEach(catalog.applications) { application in
                    VStack(alignment: .leading, spacing: 8) {
                        if let name = application.name { Text(verbatim: name).font(.headline) }
                        Text(LocalizedStringKey(application.applicationType == 2 ? "merchant.operations.claim" : application.applicationType == 1 ? "merchant.operations.placement" : "merchant.operations.review.unknown"))
                        Text(LocalizedStringKey(application.reviewKey))
                        if application.status == 2, let reason = application.reason { Text(verbatim: reason).foregroundStyle(.secondary) }
                    }.accessibilityIdentifier("merchant.operations.application." + String(application.id))
                }
            }
        }.accessibilityIdentifier("merchant.operations.cityCatalog")
    }
}
private struct MerchantOperationsAssetsView: View {
    let resources: MerchantAssetResources
    var body: some View {
        List {
            Section { Text("merchant.operations.resourcesBoundary").font(.footnote) }
            Section("merchant.operations.voice") {
                Text(LocalizedStringKey(resources.voice.statusKey)).accessibilityIdentifier("merchant.operations.voiceStatus")
                Text("merchant.operations.voiceDisabled").font(.footnote).foregroundStyle(.secondary)
            }
            Section("merchant.operations.avatar") {
                Text(LocalizedStringKey(resources.avatar.available ? "merchant.operations.providerAvailable" : "merchant.operations.providerUnavailable"))
                ForEach(Array(resources.avatar.styles.enumerated()), id: \.offset) { _, style in Text(verbatim: style) }
                if let job = resources.avatar.job {
                    Text(LocalizedStringKey(job.statusKey)).accessibilityIdentifier("merchant.operations.avatarStatus")
                    if let style = job.style { LabeledContent("merchant.operations.style", value: style) }
                    if job.status == "FAILED", let reason = job.failReason { Text(verbatim: reason).foregroundStyle(.secondary) }
                } else { Text("merchant.operations.noAvatarJob") }
                Text("merchant.operations.avatarDisabled").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
