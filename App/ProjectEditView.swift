import SwiftUI

@MainActor final class ProjectEditModel: ObservableObject {
    let coordinator: ProjectEditCoordinator
    @Published var draft = ProjectEditDraft()
    @Published var confirmation: ProjectEditConfirmation?
    @Published private(set) var submittedHandoff: PublishingSubmissionHandoff?
    @Published private(set) var revision = 0
    @Published private(set) var busy = false
    private var loadedSnapshot = false
    private var loadedSession: ProjectEditSession?
    private var generation = 0
    private var autosave: Task<Void, Never>?
    @Published private(set) var incomingSeed: ProjectEditDraft?
    private let seedSession: ProjectEditSession?
    init(coordinator: ProjectEditCoordinator, seed: ProjectEditDraft? = nil) {
        self.coordinator = coordinator; incomingSeed = seed; seedSession = coordinator.session
    }
    func applyIncomingSeed() {
        guard let seed = incomingSeed, seedSession == coordinator.session, fullEdit,
              coordinator.snapshot?.topicID == nil, seed.product == draft.product, seed.owner == draft.owner else { return }
        draft = seed; incomingSeed = nil; changed()
    }
    var rewards: Binding<PublishingTopicRewards> {
        Binding(get: { PublishingTopicRewards(draft: self.draft) }, set: { value in
            guard self.fullEdit else { return }; self.draft = value.updatingDraft(self.draft)
        })
    }
    var canEdit: Bool { loadedSnapshot && loadedSession == coordinator.session && coordinator.snapshot != nil && !busy && !coordinator.isLocked && coordinator.state != .simulated && coordinator.state != .acknowledged && coordinator.state != .blocked && !hasRestore }
    var canSaveLocal: Bool { canEdit && coordinator.session != nil }
    var fullEdit: Bool { canEdit && coordinator.snapshot?.scope == .full }
    var hasRestore: Bool { switch coordinator.restore { case .missing: return false; default: return true } }
    var canRestore: Bool { if case .ready = coordinator.restore { return true }; return false }
    var restoreKey: String {
        switch coordinator.restore {
        case .ready: return "projectEdit.restoreAvailable"
        case .revisionConflict: return "projectEdit.revisionConflict"
        case .memberMismatch: return "projectEdit.memberMismatch"
        case .incompatible: return "projectEdit.incompatible"
        case .unavailable: return "projectEdit.localFailed"
        case .missing: return "projectEdit.localEmpty"
        }
    }
    func load(force: Bool = false) async {
        if !force, loadedSnapshot, loadedSession == coordinator.session, coordinator.snapshot != nil { return }
        generation += 1; let stamp = generation; autosave?.cancel(); draft = .init(); confirmation = nil; submittedHandoff = nil; loadedSession = nil; loadedSnapshot = false; busy = true
        if seedSession != coordinator.session { incomingSeed = nil }
        coordinator.synchronizeSession(); await coordinator.load()
        guard generation == stamp else { return }
        if let snapshot = coordinator.snapshot { draft = snapshot.draft; loadedSession = coordinator.session; loadedSnapshot = true }
        busy = false; applyIncomingSeed(); revision += 1
    }
    func changed() {
        confirmation = nil; coordinator.cancelReview(); autosave?.cancel()
        guard canEdit else { return }
        autosave = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 400_000_000) } catch { return }
            guard !Task.isCancelled else { return }; self?.saveLocal()
        }
    }
    func saveLocal() { guard canSaveLocal else { return }; coordinator.saveLocal(draft); revision += 1 }
    func restore() { if let value = coordinator.restoredDraft() { draft = value }; revision += 1 }
    func discard() { coordinator.discardLocalDraft(); revision += 1 }
    func review() { autosave?.cancel(); saveLocal(); coordinator.prepare(draft); confirmation = coordinator.confirmation; revision += 1 }
    func cancelReview() { confirmation = nil; coordinator.cancelReview() }
    func submit(_ value: ProjectEditConfirmation) async {
        let stamp = generation; autosave?.cancel(); confirmation = nil; busy = true
        await coordinator.confirm(value); guard generation == stamp else { return }; busy = false
        if coordinator.state == .acknowledged { submittedHandoff = PublishingSubmissionHandoff(pending: coordinator.pending, draft: value.draft) }
        revision += 1
    }
    func check() async { let stamp = generation; busy = true; await coordinator.checkOutcome(); guard generation == stamp else { return }; busy = false; revision += 1 }
    func leave() { autosave?.cancel(); saveLocal(); coordinator.leaveScreen(); confirmation = nil; revision += 1 }
    func chapter(_ id: String) -> Binding<ProjectEditChapter> {
        Binding(get: { self.draft.chapters.first { $0.id == id } ?? .init() }, set: { value in
            guard self.fullEdit, let i = self.draft.chapters.firstIndex(where: { $0.id == id }) else { return }; self.draft.chapters[i] = value
        })
    }
    func ticket(_ id: String) -> Binding<ProjectEditTicket> {
        Binding(get: { self.draft.tickets.first { $0.id == id } ?? .init() }, set: { value in
            guard self.fullEdit, let i = self.draft.tickets.firstIndex(where: { $0.id == id }) else { return }; self.draft.tickets[i] = value
        })
    }
}

/// Present in a NavigationStack. The parent owns/retains the coordinator and supplies a
/// live account+credential epoch. Sessions changing dismiss all child editor destinations.
@MainActor struct ProjectEditView: View {
    @StateObject private var model: ProjectEditModel
    @State private var discardConfirmation = false
    @State private var choosingMode = false
    @State private var chosenMode: ProjectEditProduct?
    @State private var confirmModeCopy = false
    @State private var copiedCoordinator: ProjectEditCoordinator?
    @State private var showingCopy = false
    @State private var modeCopyFailed = false
    @State private var submission: PublishingSubmissionHandoff?
    @State private var submittedResource: PublishedResource?
    @State private var handledSubmission: UUID?
    @FocusState private var focusedField: String?
    let sessionRevision: UInt64
    var publisherClient: PublisherLifecycleHTTP? = nil
    var publisherHost: ((PublishedResource) -> AnyView)? = nil
    init(coordinator: ProjectEditCoordinator, sessionRevision: UInt64, seed: ProjectEditDraft? = nil, publisherClient: PublisherLifecycleHTTP? = nil, publisherHost: ((PublishedResource) -> AnyView)? = nil) {
        self.publisherClient = publisherClient; self.publisherHost = publisherHost
        _model = StateObject(wrappedValue: ProjectEditModel(coordinator: coordinator, seed: seed)); self.sessionRevision = sessionRevision
    }
    var body: some View {
        Form {
            Section {
                QuestifyStatusBadge(title: LocalizedStringKey(model.coordinator.canSimulate ? "projectEdit.fixtureBadge" : "projectEdit.localBadge"), systemImage: "square.and.pencil")
                Text(LocalizedStringKey(model.coordinator.canSimulate ? "projectEdit.fixtureNotice" : "projectEdit.unconfigured"))
                    .foregroundStyle(.secondary)
            }
            if model.coordinator.session == nil {
                Section { Text("projectEdit.signIn").accessibilityIdentifier("projectEdit.signIn") }
            }
            if let topicID = model.coordinator.snapshot?.topicID, let publisherClient {
                PublisherXPBudgetSection(topicID: topicID, client: publisherClient)
            }
            if model.coordinator.snapshot != nil {
                Section {
                    Button("contextPublish.mode.choose") { choosingMode = true }
                        .disabled(!model.fullEdit || model.coordinator.session == nil || model.draft.owner == .merchant).accessibilityIdentifier("contextPublish.mode.open")
                    if model.draft.owner == .merchant { Text("contextPublish.mode.merchantLocked").font(.caption) }
                    if modeCopyFailed { Text("contextPublish.mode.failed") }
                }
                if model.hasRestore {
                    Section("projectEdit.restoreTitle") {
                        Text(LocalizedStringKey(model.restoreKey)).accessibilityIdentifier("projectEdit.restoreStatus")
                        if model.canRestore { Button("projectEdit.restore") { model.restore() }.accessibilityIdentifier("projectEdit.restore") }
                        Button("projectEdit.discardLocal", role: .destructive) { discardConfirmation = true }
                            .disabled(model.coordinator.isLocked).accessibilityIdentifier("projectEdit.discardLocal")
                    }
                }
                if model.coordinator.snapshot?.scope == .whitelist {
                    Section { Text("projectEdit.whitelistHint").accessibilityIdentifier("projectEdit.whitelistHint") }
                }
                if model.incomingSeed != nil {
                    Section {
                        Text("publishModes.seedPending")
                        Button("publishModes.applySeed") { model.applyIncomingSeed() }
                            .disabled(!model.fullEdit).accessibilityIdentifier("publishModes.applySeed")
                    }
                }
                basicFields
                Section("projectEdit.structure") {
                    ForEach(model.draft.chapters) { chapter in
                        NavigationLink {
                            ProjectEditChapterView(model: model, chapterID: chapter.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                ProjectEditName(value: chapter.name, fallback: "projectEdit.untitledChapter")
                                Text(verbatim: String(chapter.nodes.count)).font(.caption).foregroundStyle(.secondary)
                                    .accessibilityLabel(Text("projectEdit.nodeCount") + Text(verbatim: ": \(chapter.nodes.count)"))
                            }
                        }.accessibilityIdentifier("projectEdit.chapter." + chapter.id)
                    }
                    .onDelete { if model.fullEdit { model.draft.chapters.remove(atOffsets: $0) } }
                    .onMove { if model.fullEdit { model.draft.chapters.move(fromOffsets: $0, toOffset: $1) } }
                    Button("projectEdit.addChapter", systemImage: "plus") { model.draft.chapters.append(.init()) }
                        .disabled(!model.fullEdit).accessibilityIdentifier("projectEdit.addChapter")
                }
                Section("projectEdit.tickets") {
                    ForEach(model.draft.tickets) { ticket in
                        NavigationLink { ProjectEditTicketView(model: model, ticketID: ticket.id) } label: {
                            ProjectEditName(value: ticket.name, fallback: "projectEdit.untitledTicket")
                        }.accessibilityIdentifier("projectEdit.ticket." + ticket.id)
                    }.onDelete { if model.fullEdit { model.draft.tickets.remove(atOffsets: $0) } }
                    Button("projectEdit.addTicket", systemImage: "plus") { model.draft.tickets.append(.init()) }
                        .disabled(!model.fullEdit).accessibilityIdentifier("projectEdit.addTicket")
                }
                PublishingTopicRewardsForm(rewards: model.rewards, fullEdit: model.fullEdit)
                Section("projectEdit.visibility") {
                    Toggle("projectEdit.publishToCreative", isOn: $model.draft.publishToCreative)
                        .disabled(!model.fullEdit || model.coordinator.snapshot?.topicID != nil)
                    Text("projectEdit.advancedPreserved").foregroundStyle(.secondary)
                }
                if !model.coordinator.issues.isEmpty {
                    Section("projectEdit.fixBeforeReview") {
                        ForEach(model.coordinator.issues) { issue in
                            Label(LocalizedStringKey(issue.key), systemImage: "exclamationmark.circle")
                                .accessibilityIdentifier("projectEdit.issue." + issue.id)
                        }
                    }
                }
                if model.coordinator.isLocked {
                    Section("projectEdit.unknownTitle") {
                        Text("projectEdit.unknown")
                        Button("projectEdit.checkOutcome") { Task { await model.check() } }
                            .disabled(model.busy).accessibilityIdentifier("projectEdit.checkOutcome")
                    }
                }
            }
            if let key = model.coordinator.messageKey {
                Section { Text(LocalizedStringKey(key)).accessibilityIdentifier("projectEdit.status") }
            }
            if model.coordinator.state == .blocked { Button("projectEdit.reload") { Task { await model.load(force: true) } }.accessibilityIdentifier("projectEdit.reload") }
            if model.busy { ProgressView("projectEdit.loading").accessibilityIdentifier("projectEdit.loading") }
        }
        .disabled(model.busy)
        .appNavigationTitle("projectEdit.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton().disabled(!model.fullEdit) }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("projectEdit.saveLocal") { focusedField = nil; model.saveLocal() }
                    .buttonStyle(.bordered).disabled(!model.canSaveLocal).accessibilityIdentifier("projectEdit.saveLocal")
                Button("projectEdit.review") { focusedField = nil; model.review() }
                    .buttonStyle(.borderedProminent).disabled(!model.canEdit).accessibilityIdentifier("projectEdit.review")
            }.frame(maxWidth: .infinity, minHeight: 44).padding().background(.regularMaterial)
        }
        .task(id: sessionRevision) { await model.load() }
        .onChange(of: model.draft) { _, _ in model.changed() }
        .onChange(of: model.revision) { _, _ in
            if model.coordinator.state == .acknowledged, let next = model.submittedHandoff, next.id != handledSubmission {
                handledSubmission = next.id; submission = next
            }
        }
        .onChange(of: sessionRevision) { _, _ in choosingMode = false; confirmModeCopy = false; showingCopy = false; copiedCoordinator = nil; submission = nil; submittedResource = nil; handledSubmission = nil }
        .navigationDestination(isPresented: $showingCopy) {
            if let copiedCoordinator { AnyView(ProjectEditView(coordinator: copiedCoordinator, sessionRevision: sessionRevision, publisherClient: publisherClient, publisherHost: publisherHost)) }
        }
        .navigationDestination(item: $submittedResource) { resource in
            if let publisherHost { publisherHost(resource) }
        }
        .sheet(isPresented: $choosingMode) {
            PublishingModePickerSheet(current: model.draft.product) { product in
                choosingMode = false
                if product != model.draft.product { chosenMode = product; confirmModeCopy = true }
            }
        }
        .confirmationDialog("contextPublish.mode.confirmTitle", isPresented: $confirmModeCopy, titleVisibility: .visible) {
            Button("contextPublish.mode.copy") {
                guard model.fullEdit, let chosenMode else { return }
                do { copiedCoordinator = try model.coordinator.copyForMode(model.draft, to: chosenMode); showingCopy = true; modeCopyFailed = false }
                catch { modeCopyFailed = true }
                self.chosenMode = nil
            }
            Button("action.cancel", role: .cancel) { chosenMode = nil }
        } message: { Text("contextPublish.mode.confirmBody") }
        .sheet(item: $submission) { receipt in
            PublishingSubmissionResultSheet(receipt: receipt, canNavigate: publisherHost != nil) {
                submission = nil
                if publisherHost != nil { submittedResource = receipt.resource }
            }
        }
        .onDisappear { model.leave() }
        .sheet(item: $model.confirmation, onDismiss: { model.coordinator.cancelReview() }) { confirmation in
            ProjectEditReviewView(confirmation: confirmation, canSimulate: model.coordinator.canSimulate, canSubmit: model.coordinator.canSubmit, busy: model.busy,
                                  cancel: model.cancelReview, confirm: { Task { await model.submit(confirmation) } })
        }
        .alert("projectEdit.discardTitle", isPresented: $discardConfirmation) {
            Button("projectEdit.discardLocal", role: .destructive) { model.discard() }
            Button("action.cancel", role: .cancel) {}
        } message: { Text("projectEdit.discardHint") }
    }
    private var basicFields: some View {
        Group {
            Section("projectEdit.basics") {
                TextField("projectEdit.name", text: $model.draft.name).focused($focusedField, equals: "name")
                    .accessibilityIdentifier("projectEdit.name")
                TextField("projectEdit.subtitle", text: $model.draft.subtitle).accessibilityIdentifier("projectEdit.subtitle")
                TextField("projectEdit.description", text: $model.draft.description, axis: .vertical).lineLimit(3...8)
                    .accessibilityIdentifier("projectEdit.description")
                ProjectEditReferenceField(title: "projectEdit.cover", value: $model.draft.imgUrl, identifier: "projectEdit.cover")
                ProjectEditReferenceField(title: "projectEdit.gallery", value: $model.draft.imgArr, identifier: "projectEdit.gallery")
                ProjectEditCategoryField(selection: $model.draft.categoryIDs)
            }.disabled(!model.canEdit)
            Section("projectEdit.schedule") {
                Text(LocalizedStringKey(model.draft.product == .city ? "projectEdit.city" : "projectEdit.freeExplore"))
                ProjectEditDateField(title: "projectEdit.startDate", value: $model.draft.startDate, identifier: "projectEdit.startDate")
                ProjectEditDateField(title: "projectEdit.endDate", value: $model.draft.endDate, identifier: "projectEdit.endDate")
                if model.draft.product == .freeExplore {
                    ProjectEditDateField(title: "projectEdit.deadline", value: $model.draft.recruitDeadline, identifier: "projectEdit.deadline")
                }
            }.disabled(!model.fullEdit)
        }
    }
}

struct ProjectEditReferenceField: View {
    let title: LocalizedStringKey
    @Binding var value: String
    let identifier: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(title, text: $value).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier(identifier)
            Text("projectEdit.mediaDeferred").font(.caption).foregroundStyle(.secondary)
        }
    }
}
/// Placeholder manual IDs are explicitly called out; a live category picker awaits contract integration.
struct ProjectEditCategoryField: View {
    @Binding var selection: [Int]
    @State private var text = ""
    @State private var invalid = false
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading) {
            TextField("projectEdit.categories", text: $text).keyboardType(.numbersAndPunctuation).focused($focused)
                .accessibilityIdentifier("projectEdit.categories")
                .onChange(of: text) { _, value in
                    let parts = value.split(separator: ",", omittingEmptySubsequences: false)
                    let ids = parts.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    invalid = !value.isEmpty && (ids.count != parts.count || ids.contains { $0 <= 0 })
                    // Invalid text clears selection; review must not silently send old IDs.
                    selection = invalid ? [] : ids
                }
            Text(LocalizedStringKey(invalid ? "projectEdit.validation.categories" : "projectEdit.categoriesHint")).font(.caption).foregroundStyle(.secondary)
        }.onAppear { text = selection.map(String.init).joined(separator: ",") }
            .onChange(of: selection) { _, value in if !focused { text = value.map(String.init).joined(separator: ",") } }
    }
}
struct ProjectEditDateField: View {
    let title: LocalizedStringKey
    @Binding var value: String
    let identifier: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(title, text: $value).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier(identifier)
            Text("projectEdit.dateFormat").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ProjectEditName: View {
    let value: String
    let fallback: LocalizedStringKey
    var body: some View { if value.isEmpty { Text(fallback) } else { Text(verbatim: value) } }
}
