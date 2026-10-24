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
    private let destinations: [MerchantOperationsDestination] = [.profile, .businessStatus, .decor, .gallery, .story, .cooperation, .character, .assets, .cityNodes, .templates]
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
        switch destination { case .profile, .decor, .businessStatus: return "storefront"; case .gallery: return "photo.on.rectangle"
        case .story: return "book.closed"; case .cooperation: return "person.2"; case .character: return "person.crop.circle"
        case .npcMapPoint: return "mappin.and.ellipse"
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
    @Published var brandImagesPresentation: MerchantBrandImagesModel?
    let galleryBatch = MerchantGalleryBatchModel()
    @Published private(set) var decorNavigation: MerchantDecorEditorRoute?
    private var decorReturn: MerchantDecorEditorRoute?
    private(set) var decorNavigationGeneration = UUID()
    func openDecorEditor(_ route: MerchantDecorEditorRoute) {
        guard decorNavigation == nil, route.isCurrent(document: self) else { return }
        decorReturn = route; decorNavigation = route
    }
    func decorNavigationBinding() -> Binding<MerchantDecorEditorRoute?> {
        let original = decorNavigation
        return Binding(get: { [weak self] in
            guard let self, let original, self.decorNavigation?.id == original.id,
                  original.isCurrent(document: self) else { return nil }
            return original
        }, set: { [weak self] value in
            guard value == nil, let self, let original, self.decorNavigation?.id == original.id else { return }
            self.decorNavigation = nil
        })
    }
    /// Called by the actual document task when its navigation host appears again.
    func loadForAppearance() async {
        if let returning = decorReturn, returning.isCurrent(document: self) {
            retireDecorNavigation()
            await refreshImages()
            return
        }
        retireDecorNavigation()
        await load()
    }
    func documentDisappeared() {
        let returningFromChild = decorReturn?.isCurrent(document: self) == true
        leaveImages()
        if coordinator.destination == .decor, !returningFromChild { invalidate() }
    }
    func retireDecorNavigation() { decorNavigation = nil; decorReturn = nil; decorNavigationGeneration = UUID() }

    private let imageHost: MerchantRetainedImageHost?
    private(set) var imageOwner: MerchantRetainedImageDocumentOwner?
    init(reader: any MerchantOperationsReading, destination: MerchantOperationsDestination, imageHost: MerchantRetainedImageHost? = nil) {
        coordinator = .init(reader: reader, destination: destination)
        self.imageHost = imageHost
        imageOwner = imageHost?.document(reader: reader, destination: destination)
    }
    func load() async {
        retireDecorNavigation()
        galleryBatch.cancel(); imageOwner?.invalidate(); revision += 1
        await coordinator.load(); await imageOwner?.refresh(coordinator: coordinator); revision += 1
    }
    func edit(_ value: MerchantOperationsDraft) {
        galleryBatch.cancel(); coordinator.edit(value); imageOwner?.draftChanged(coordinator.draft); revision += 1
    }
    /// The assist flow already committed one guarded field; only refresh UI here.
    func templateAssistChanged() { revision += 1 }
    var galleryBatchBinding: MerchantGalleryBatchBinding {
        .init(draft: { [weak self] in self?.coordinator.draft },
              accessFence: { [weak self] in self?.imageOwner?.galleryBatchAccessFence },
              context: { [weak self] in self?.imageContext(.gallery) },
              append: { [weak self] image, scope, before, after in
            guard let self, self.coordinator.isCurrent, !self.coordinator.isBusy, !self.coordinator.isLocked,
                  self.coordinator.confirmation == nil, self.coordinator.draft == before,
                  self.imageOwner?.validatesGalleryBatchScope(scope, coordinator: self.coordinator) == true,
                  image.scope == scope, case .merchant(_, .gallery) = scope.destination,
                  let verified = try? image.applying(to: before, expectedScope: scope), verified == after else { return false }
            // Only this verified append bypasses generic edit's batch cancellation. The
            // batch still waits for applyLocally's durable result before reacquiring scope.
            self.coordinator.edit(after); self.imageOwner?.draftChanged(self.coordinator.draft); self.revision += 1
            return self.coordinator.draft == after
        })
    }
    func imageContext(_ field: MerchantImageField) -> RetainedImageSelectionContext? { imageOwner?.context(field: field, coordinator: coordinator) }
    func prepare() { galleryBatch.cancel(); coordinator.prepare(); revision += 1 }
    func cancel() { coordinator.cancelConfirmation(); revision += 1 }
    func discard() { galleryBatch.cancel(); coordinator.discardChanges(); imageOwner?.draftChanged(coordinator.draft); revision += 1 }
    func confirm(_ value: MerchantOperationsConfirmation) async {
        galleryBatch.cancel(); imageOwner?.invalidate(); revision += 1
        let previousDestination = coordinator.destination
        await coordinator.confirm(value)
        if previousDestination != coordinator.destination {
            imageOwner?.invalidate()
            imageOwner = imageHost?.document(reader: coordinator.reader, destination: coordinator.destination)
        }
        await imageOwner?.refresh(coordinator: coordinator); revision += 1
    }
    func invalidate() { retireDecorNavigation(); galleryBatch.cancel(); imageOwner?.invalidate(); coordinator.invalidate(); revision += 1 }
    func leaveImages() { galleryBatch.cancel(); imageOwner?.invalidate(); revision += 1 }
    func refreshImages() async { galleryBatch.cancel(); await imageOwner?.refresh(coordinator: coordinator); revision += 1 }
}

@MainActor
struct MerchantOperationsDocumentView: View {
    let reader: any MerchantOperationsReading
    let destination: MerchantOperationsDestination
    let imageHost: MerchantRetainedImageHost?
    var templateAssistFactory: ((MerchantOperationsCoordinator) -> MerchantTemplateAssistFlow)? = nil
    var templateReturn: MerchantCityTemplateReturnAction? = nil
    var authorFlow: MerchantNPCKnowledgeAuthorFlow? = nil
    var draftReadMemberID: Int64? = nil
    var draftReadRequestID: String? = nil
    var draftRead: ((Int64, String) -> MerchantNPCDraftReadFact?)? = nil
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: MerchantOperationsViewModel
    @State private var confirmDiscard = false
    @State private var confirmReload = false
    init(reader: any MerchantOperationsReading, destination: MerchantOperationsDestination, imageHost: MerchantRetainedImageHost? = nil, templateAssistFactory: ((MerchantOperationsCoordinator) -> MerchantTemplateAssistFlow)? = nil, templateReturn: MerchantCityTemplateReturnAction? = nil, authorFlow: MerchantNPCKnowledgeAuthorFlow? = nil, draftReadMemberID: Int64? = nil, draftReadRequestID: String? = nil, draftRead: ((Int64, String) -> MerchantNPCDraftReadFact?)? = nil) {
        self.templateReturn = templateReturn
        self.reader = reader; self.destination = destination; self.imageHost = imageHost; self.templateAssistFactory = templateAssistFactory
        self.authorFlow = authorFlow
        self.draftReadMemberID = draftReadMemberID
        self.draftReadRequestID = draftReadRequestID
        self.draftRead = draftRead
        _model = StateObject(wrappedValue: .init(reader: reader, destination: destination, imageHost: imageHost))
    }
    private var coordinator: MerchantOperationsCoordinator { model.coordinator }
    var body: some View {
        if destination == .templates {
            MerchantTemplateBrowserView(reader: reader, imageHost: imageHost, templateAssistFactory: templateAssistFactory)
        } else { documentBody }
    }
    private var documentBody: some View {
        Group {
            if coordinator.isCurrent, let document = coordinator.document {
                switch document {
                case .draft:
                    MerchantOperationsEditor(model: model, templateAssistFactory: templateAssistFactory, imageContext: model.imageContext, authorFlow: authorFlow, draftReadMemberID: draftReadMemberID, draftReadRequestID: draftReadRequestID, draftRead: draftRead)
                case .cityNodes(let catalog): MerchantOperationsCityView(catalog: catalog)
                case .templates: MerchantTemplateBrowserView(reader: reader, imageHost: imageHost, templateAssistFactory: templateAssistFactory)
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
        .safeAreaInset(edge: .bottom) {
            if let templateReturn { MerchantCityTemplateReturnFooter(coordinator: coordinator, action: templateReturn) }
        }
        .navigationDestination(item: model.decorNavigationBinding()) { route in
            if route.isCurrent(document: model) {
                MerchantOperationsDocumentView(reader: route.reader, destination: route.destination,
                    imageHost: imageHost, templateAssistFactory: templateAssistFactory).id(route.id)
            } else { Text("merchant.business.stale") }
        }
        .navigationBarBackButtonHidden(coordinator.isDirty)
        .toolbar {
            if destination == .decor {
                ToolbarItemGroup(placement: .bottomBar) {
                    ForEach(MerchantDecorEditorTarget.allCases, id: \.self) { target in
                        if let route = MerchantDecorEditorRoute(document: model, target: target) {
                            Button { model.openDecorEditor(route) } label: {
                                Text(LocalizedStringKey(target.destination.titleKey))
                            }.accessibilityIdentifier("merchant.decor.open." + target.rawValue)
                        }
                    }
                }
            }
            if templateReturn != nil, !coordinator.isDirty {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }.disabled(coordinator.isBusy)
                        .accessibilityIdentifier("merchant.cityTemplate.cancelEditor")
                }
            }
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
        .alert("merchant.operations.discardTitle", isPresented: $confirmDiscard) {
            Button("merchant.operations.discard", role: .destructive) { model.discard(); dismiss() }
            Button("merchant.operations.keepEditing", role: .cancel) { }
                .accessibilityIdentifier("merchant.operations.keepEditing")
        } message: { Text("merchant.operations.discardBody") }
        .alert("merchant.operations.discardTitle", isPresented: $confirmReload) {
            Button("merchant.operations.discardReload", role: .destructive) { model.discard(); Task { await model.load() } }
                .accessibilityIdentifier("merchant.operations.discardReload")
            Button("merchant.operations.keepEditing", role: .cancel) { }
                .accessibilityIdentifier("merchant.operations.keepEditing")
        } message: { Text("merchant.operations.discardBody") }
        .sheet(item: Binding(get: { coordinator.isCurrent ? coordinator.confirmation : nil }, set: { if $0 == nil { model.cancel() } })) { confirmation in
            MerchantOperationsConfirmationView(model: model, confirmation: confirmation)
        }
        .task(id: reader.scope) { await model.loadForAppearance() }
        .onChange(of: reader.scope) { _, _ in model.invalidate() }
        .onDisappear { model.documentDisappeared() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.retireDecorNavigation(); model.leaveImages() }
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


/// Value navigation freezes an existing editor target and never mutates the source draft.
enum MerchantDecorEditorTarget: String, CaseIterable {
    case gallery, cooperation
    var destination: MerchantOperationsDestination {
        switch self { case .gallery: return .gallery; case .cooperation: return .cooperation }
    }
}
@MainActor struct MerchantDecorEditorRoute: Hashable, Identifiable {
    let id = UUID()
    let reader: any MerchantOperationsReading
    let destination: MerchantOperationsDestination
    private let source: ObjectIdentifier
    private let scope: UUID
    private let draftIdentity: UUID
    private let navigationGeneration: UUID
    init?(document: MerchantOperationsViewModel, target: MerchantDecorEditorTarget) {
        let coordinator = document.coordinator
        guard coordinator.destination == .decor, coordinator.isCurrent,
              coordinator.reader.isConfigured, !coordinator.isBusy, !coordinator.isLocked,
              coordinator.confirmation == nil, case .decor = coordinator.draft else { return nil }
        reader = coordinator.reader; destination = target.destination
        source = ObjectIdentifier(document); scope = reader.scope; draftIdentity = coordinator.draftIdentity
        navigationGeneration = document.decorNavigationGeneration
    }
    func isCurrent(document: MerchantOperationsViewModel) -> Bool {
        let coordinator = document.coordinator
        return navigationGeneration == document.decorNavigationGeneration
            && !reader.hasPending(.decor)
            && source == ObjectIdentifier(document) && ObjectIdentifier(reader) == ObjectIdentifier(coordinator.reader)
            && reader.scope == scope && reader.isConfigured && reader.isAuthenticated
            && coordinator.destination == .decor && coordinator.isCurrent && coordinator.draftIdentity == draftIdentity
            && !coordinator.isBusy && !coordinator.isLocked && coordinator.confirmation == nil
    }
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
