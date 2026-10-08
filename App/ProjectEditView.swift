import SwiftUI

@MainActor final class ProjectEditModel: ObservableObject {
    let coordinator: ProjectEditCoordinator
    let storyImagePicker: (() -> any OwnedTopicCoverSelecting)?
    let storyAudioPicker: (() -> any ProjectStoryAudioSelecting)?
    @Published var draft = ProjectEditDraft() {
        didSet {
            draftMutationRevision += 1 // Every setter retires prior chooser captures, including same-byte replacement.
            if confirmation != nil {
                let before = ProjectEditPendingMaterials.exactData(oldValue), after = ProjectEditPendingMaterials.exactData(draft)
                if before == nil || after == nil || before != after { cancelReview() }
            }
            if ProjectEditPendingMaterials.exactData(oldValue.pendingMaterials) != ProjectEditPendingMaterials.exactData(draft.pendingMaterials) { materialRevision += 1 }
            if oldValue.chapters.map({ $0.blocks?.map(\.id) }) != draft.chapters.map({ $0.blocks?.map(\.id) }) { storyTopologyRevision += 1 }
            // Captured media gaps retire on exact chapter-content changes as well as order.
            // This monotonic stamp rejects replacing an anchor and restoring the same bytes (ABA).
            let oldStory = ProjectEditPendingMaterials.exactData(oldValue.chapters), newStory = ProjectEditPendingMaterials.exactData(draft.chapters)
            if oldStory == nil || newStory == nil || oldStory != newStory { storyGapRevision += 1 }
            if oldValue.product != draft.product || oldValue.owner != draft.owner ||
                !oldValue.baseRevision.utf8.elementsEqual(draft.baseRevision.utf8) ||
                oldValue.chapters.map(\.id) != draft.chapters.map(\.id) {
                structureRevision += 1
            }
        }
    }
    @Published private(set) var editorIncarnation = UUID()
    /// In-memory ABA fence for a node draft chooser; not saved or sent to the server.
    private(set) var draftMutationRevision = 0
    private(set) var structureRevision = 0
    private(set) var materialRevision = 0
    private(set) var storyTopologyRevision = 0
    private(set) var storyGapRevision = 0
    @Published var confirmation: ProjectEditConfirmation?
    private(set) var reviewLease: ProjectEditPreparedReviewLease?
    private(set) var reviewLocalSaveConfirmed = false
    @Published private(set) var submittedHandoff: PublishingSubmissionHandoff?
    @Published private(set) var revision = 0
    @Published private(set) var busy = false
    private var visit: UUID?
    private var leftBeforeInitialLoad = false
    var ownsVisit: Bool { visit.map(coordinator.ownsEditorVisit) == true }
    private var loadedSnapshot = false
    private var loadedSession: ProjectEditSession?
    private var generation = 0
    private var autosave: Task<Void, Never>?
    @Published private(set) var incomingSeed: ProjectEditDraft?
    private let seedSession: ProjectEditSession?
    init(coordinator: ProjectEditCoordinator, seed: ProjectEditDraft? = nil, storyImagePicker: (() -> any OwnedTopicCoverSelecting)? = nil, storyAudioPicker: (() -> any ProjectStoryAudioSelecting)? = nil) {
        self.storyAudioPicker = storyAudioPicker; self.storyImagePicker = storyImagePicker; self.coordinator = coordinator; incomingSeed = seed; seedSession = coordinator.session
    }
    func applyIncomingSeed() {
        guard let seed = incomingSeed, seedSession == coordinator.session, fullEdit,
              coordinator.snapshot?.topicID == nil, seed.product == draft.product, seed.owner == draft.owner else { return }
        editorIncarnation = UUID(); draft = seed; incomingSeed = nil; changed()
    }
    var completionRules: Binding<ProjectEditCompletionRules> {
        Binding(get: { (self.draft.completionRules ?? .init(raw: self.draft.preserved["completeRuleJson"])).forProduct(self.draft.product) }, set: { value in
            guard self.fullEdit, !self.completionRules.wrappedValue.readOnly else { return }
            self.draft.completionRules = value
        })
    }
    var rewards: Binding<PublishingTopicRewards> {
        Binding(get: { PublishingTopicRewards(draft: self.draft) }, set: { value in
            guard self.fullEdit else { return }; self.draft = value.updatingDraft(self.draft)
        })
    }
    var canEdit: Bool { ownsVisit && loadedSnapshot && loadedSession == coordinator.session && coordinator.snapshot != nil && !busy && !coordinator.isLocked && coordinator.state != .simulated && coordinator.state != .acknowledged && coordinator.state != .blocked && !hasRestore }
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
        guard !Task.isCancelled, !leftBeforeInitialLoad else { return }
        if let visit { guard coordinator.ownsEditorVisit(visit) else { return } }
        else { let claimed = UUID(); visit = claimed; coordinator.beginEditorVisit(claimed) }
        if !force, loadedSnapshot, loadedSession == coordinator.session, coordinator.snapshot != nil { return }
        editorIncarnation = UUID(); generation += 1; let stamp = generation; autosave?.cancel(); draft = .init(); cancelReview(); submittedHandoff = nil; loadedSession = nil; loadedSnapshot = false; busy = true
        if seedSession != coordinator.session { incomingSeed = nil }
        coordinator.synchronizeSession(); await coordinator.load()
        guard generation == stamp, ownsVisit else { return }
        if let snapshot = coordinator.snapshot { draft = snapshot.draft; loadedSession = coordinator.session; loadedSnapshot = true }
        busy = false; applyIncomingSeed(); revision += 1
    }
    var submissionEvidence: PublishingSubmissionHandoff? {
        guard ownsVisit, loadedSession == coordinator.session, let session = coordinator.session,
              coordinator.state == .acknowledged, coordinator.pending?.ownerKey == session.ownerKey else { return nil }
        return PublishingSubmissionHandoff(pending: coordinator.pending, draft: draft)
    }
    @Published private var lastCoverSelection: (operationID: UUID, receipt: OwnedTopicCoverSelectionReceipt)?
    var coverSelectionNotice: OwnedTopicCoverSelectionReceipt? {
        guard let value = lastCoverSelection, submissionEvidence?.operationID == value.operationID,
              coordinator.session?.accountID == value.receipt.asset.ownerMemberID else { return nil }; return value.receipt
    }
    func recordCoverSelection(_ receipt: OwnedTopicCoverSelectionReceipt, operationID: UUID) {
        guard submissionEvidence?.operationID == operationID, coordinator.session?.accountID == receipt.asset.ownerMemberID else { return }
        lastCoverSelection = (operationID,receipt)
    }
    var coverSelectionIsResolved: Bool {
        guard let journal = coordinator.ownedCoverJournal else { return true }
        guard let session = coordinator.session, let topic = coordinator.pending?.completedTopicID,
              let snapshot = try? journal.read(session: session, topicID: topic) else { return false }
        return snapshot.currentSelection == nil || snapshot.currentSelection?.receipt != nil
    }
    func approvedReleaseReadScope() -> (target: ApprovedTopicReleaseReadTarget, reviewSnapshot: ApprovedTopicReviewJournal.Snapshot?)? {
        guard submissionEvidence != nil, coverSelectionIsResolved, let pending = coordinator.pending, let session = coordinator.session else { return nil }
        if let journal = coordinator.releaseReviewJournal {
            guard let saved = try? journal.read(session: session, topicID: pending.completedTopicID ?? 0),
                  let target = ApprovedTopicReleaseReadTarget(pending: pending, session: session, reviewSnapshot: saved) else { return nil }
            return (target, saved)
        }
        guard let target = ApprovedTopicReleaseReadTarget(pending: pending, session: session) else { return nil }; return (target, nil)
    }
    var approvedReleaseReadTarget: ApprovedTopicReleaseReadTarget? { approvedReleaseReadScope()?.target }
    var approvedReleaseReadIsConfigured: Bool {
        guard submissionEvidence != nil, let session = coordinator.session,
              approvedReleaseReadTarget != nil,
              let source = coordinator.releasePreparationSource else { return false }
        return source.isCurrent(session: session)
    }
    func submissionIsCurrent(_ receipt: PublishingSubmissionHandoff, incarnation: UUID) -> Bool {
        editorIncarnation == incarnation && submissionEvidence == receipt && submittedHandoff?.id == receipt.id
    }
    func invalidateStarterLease() { editorIncarnation = UUID() }
    func changed() {
        cancelReview(); autosave?.cancel()
        guard canEdit else { return }
        autosave = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 400_000_000) } catch { return }
            guard !Task.isCancelled else { return }; self?.saveLocal()
        }
    }
    func persistLocalChange(_ value: ProjectEditDraft, lease: ProjectEditStarterController.Lease) -> Bool {
        guard isCurrentStarterLease(lease), value.product == draft.product, value.owner == draft.owner,
              value.baseRevision.utf8.elementsEqual(draft.baseRevision.utf8) else { return false }
        autosave?.cancel(); cancelReview()
        guard coordinator.saveLocal(value) else { revision += 1; return false }
        draft = value; revision += 1; return true
    }
    func canReplaceExistingStoryDraft() -> Bool { fullEdit && coordinator.canReplaceExistingStoryDraft(draft) }
    func persistExistingStoryChange(_ value: ProjectEditDraft, lease: ProjectEditStarterController.Lease) -> Bool {
        guard isCurrentStarterLease(lease), canReplaceExistingStoryDraft(), value.product == draft.product, value.owner == draft.owner,
              value.baseRevision.utf8.elementsEqual(draft.baseRevision.utf8) else { return false }
        autosave?.cancel(); cancelReview()
        guard coordinator.replaceExistingStoryDraft(value, replacing: draft) else { revision += 1; return false }
        draft = value; revision += 1; return true
    }
    func saveLocal() { guard canSaveLocal else { return }; coordinator.saveLocal(draft); revision += 1 }
    func restore() { guard ownsVisit else { return }; cancelReview(); editorIncarnation = UUID(); if let value = coordinator.restoredDraft() { draft = value }; revision += 1 }
    func discard() { guard ownsVisit else { return }; cancelReview(); editorIncarnation = UUID(); coordinator.discardLocalDraft(); revision += 1 }
    func review() {
        guard let lease = currentReviewLease() else { return }
        autosave?.cancel(); let saved = coordinator.saveLocal(draft); coordinator.prepare(draft)
        guard currentReviewLease() == lease else { cancelReview(); return }
        reviewLease = lease; reviewLocalSaveConfirmed = saved; confirmation = coordinator.confirmation; revision += 1
    }
    func cancelReview() { confirmation = nil; reviewLease = nil; reviewLocalSaveConfirmed = false; if ownsVisit { coordinator.cancelReview() } }
    func submit(_ value: ProjectEditConfirmation) async {
        guard reviewIsCurrent(value), canEdit, !busy else { return }
        let stamp = generation; autosave?.cancel(); confirmation = nil; busy = true
        await coordinator.confirm(value); guard generation == stamp, ownsVisit else { return }; busy = false
        if coordinator.state == .acknowledged { submittedHandoff = PublishingSubmissionHandoff(pending: coordinator.pending, draft: value.draft) }
        revision += 1
    }
    func continueAcknowledged(_ expected: ProjectEditContinuation) async {
        guard ownsVisit, !busy, coordinator.canContinueAcknowledged else { return }
        let stamp = generation; busy = true; autosave?.cancel(); cancelReview()
        let success = await coordinator.continueAcknowledged(expected)
        guard generation == stamp, ownsVisit else { return }; busy = false
        if success, let snapshot = coordinator.snapshot {
            editorIncarnation = UUID(); draft = snapshot.draft; loadedSnapshot = true
            loadedSession = coordinator.session; submittedHandoff = nil
        }
        revision += 1
    }
    func check() async { guard ownsVisit else { return }; let stamp = generation; busy = true; await coordinator.checkOutcome(); guard generation == stamp, ownsVisit else { return }; busy = false; revision += 1 }
    func leave() { if visit == nil { leftBeforeInitialLoad = true }; guard ownsVisit else { return }; generation += 1; editorIncarnation = UUID(); autosave?.cancel(); saveLocal(); coordinator.leaveScreen(); cancelReview(); busy = false; revision += 1 }
    func chapter(_ id: String) -> Binding<ProjectEditChapter> {
        Binding(get: { self.draft.chapters.first { $0.id == id } ?? .init() }, set: { value in
            guard self.fullEdit, let i = self.draft.chapters.firstIndex(where: { $0.id == id }) else { return }; self.draft.chapters[i] = value
        })
    }
    func ticketDateSync(_ id: String) -> Binding<Bool> {
        Binding(get: { self.draft.product == .freeExplore && self.ticket(id).wrappedValue.syncsWithThemeDates }, set: { enabled in
            guard self.fullEdit, let index = self.draft.tickets.firstIndex(where: { $0.id == id }) else { return }
            var value = self.draft.tickets[index]
            guard (try? value.setThemeDateSync(enabled, in: self.draft)) != nil else { return }
            self.draft.tickets[index] = value
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
    @StateObject private var starter: ProjectEditStarterController
    @StateObject private var pending: ProjectEditPendingController
    @StateObject private var modeReview: ProjectEditModeReviewController
    private let ownedCoverPicker: (() -> any OwnedTopicCoverSelecting)?
    @StateObject private var ownedCover: OwnedTopicCoverAuthorPresentation
    @StateObject private var approvedRelease: ApprovedReleaseAuthorPresentation
    @StateObject private var reviewRequest: ApprovedTopicReviewPresentation
    @Environment(\.locale) private var locale
    @State private var discardConfirmation = false
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
    init(coordinator: ProjectEditCoordinator, sessionRevision: UInt64, seed: ProjectEditDraft? = nil, publisherClient: PublisherLifecycleHTTP? = nil, publisherHost: ((PublishedResource) -> AnyView)? = nil, ownedCoverPicker: (() -> any OwnedTopicCoverSelecting)? = nil, storyImagePicker: (() -> any OwnedTopicCoverSelecting)? = nil, storyAudioPicker: (() -> any ProjectStoryAudioSelecting)? = nil) {
        self.publisherClient = publisherClient; self.publisherHost = publisherHost; self.ownedCoverPicker = ownedCoverPicker
        let value = ProjectEditModel(coordinator: coordinator, seed: seed, storyImagePicker: storyImagePicker, storyAudioPicker: storyAudioPicker)
        _model = StateObject(wrappedValue: value); _starter = StateObject(wrappedValue: .init(model: value)); _pending = StateObject(wrappedValue: .init(model: value)); _modeReview = StateObject(wrappedValue: .init(model: value)); _ownedCover = StateObject(wrappedValue: .init(model: value)); _approvedRelease = StateObject(wrappedValue: .init(model: value)); _reviewRequest = StateObject(wrappedValue: .init(model: value)); self.sessionRevision = sessionRevision
    }
    var body: some View {
        let opening = model.captureStarterLease()
        let modePresentation = modeReview.presentation
        let coverPresentation = ownedCover.presentation
        let releasePresentation = approvedRelease.presentation
        let reviewRequestPresentation = reviewRequest.presentation
        let presentedSubmission = submission
        let submissionIncarnation = model.editorIncarnation
        let copiedTarget = copiedCoordinator
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
                if let id = model.coordinator.snapshot?.topicID {
                    Section("projectRemote.readback") {
                        LabeledContent("projectRemote.topicID", value: String(id))
                        LabeledContent("projectRemote.version") {
                            Text(verbatim: model.draft.baseRevision).accessibilityIdentifier("projectRemote.version.value")
                                .accessibilityLabel(Text(verbatim: model.draft.baseRevision))
                        }.accessibilityElement(children: .contain)
                        Text(LocalizedStringKey(model.draft.product == .city ? "projectEdit.city" : "projectEdit.freeExplore"))
                            .accessibilityIdentifier("projectRemote.mode")
                        Text("projectRemote.freshSource").font(.caption)
                    }
                }
                ProjectSubmissionEvidenceSection(model: model)
                OwnedTopicCoverEntrySection(model: model, controller: ownedCover)
                ApprovedReleaseAuthorReadSection(model: model, controller: approvedRelease)
                ApprovedTopicReviewEntrySection(model: model, controller: reviewRequest)
                if let completed = model.coordinator.acknowledgedContinuation {
                    Section {
                        Text("projectRemote.completedExplanation")
                        Button("projectRemote.continue") { Task { await model.continueAcknowledged(completed) } }
                            .accessibilityIdentifier("projectRemote.continue")
                    }
                }
                Section {
                    Button("contextPublish.mode.choose") { modeReview.open() }
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
                ProjectEditPendingSection(model: model, controller: pending)
                chapterStructure(opening: opening)
                Section("projectEdit.tickets") {
                    ForEach(model.draft.tickets) { ticket in
                        NavigationLink { ProjectEditTicketView(model: model, ticketID: ticket.id) } label: {
                            ProjectEditName(value: ticket.name, fallback: "projectEdit.untitledTicket")
                        }.accessibilityIdentifier("projectEdit.ticket." + ticket.id)
                    }.onDelete { if model.fullEdit { model.draft.tickets.remove(atOffsets: $0) } }
                    Button("projectEdit.addTicket", systemImage: "plus") { model.draft.tickets.append(.init()) }
                        .disabled(!model.fullEdit).accessibilityIdentifier("projectEdit.addTicket")
                }
                ProjectEditCompletionRulesForm(rules: model.completionRules, city: model.draft.product == .city, fullEdit: model.fullEdit, totalNodes: model.draft.chapters.reduce(0) { $0 + $1.nodes.count })
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
                        if model.coordinator.canSimulate {
                            Button("projectEdit.checkOutcome") { Task { await model.check() } }
                                .disabled(model.busy).accessibilityIdentifier("projectEdit.checkOutcome")
                        } else { Text("projectRemote.unknownNoReceipt") }
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
        .onChange(of: sessionRevision) { _, _ in if let modePresentation { modeReview.dismiss(modePresentation) }; showingCopy = false; copiedCoordinator = nil; submission = nil; submittedResource = nil; handledSubmission = nil }
        .navigationDestination(isPresented: Binding(get: { showingCopy && copiedCoordinator === copiedTarget }, set: { showing in
            guard let copiedTarget, copiedCoordinator === copiedTarget else { return }; showingCopy = showing
        })) {
            if let copiedTarget { AnyView(ProjectEditView(coordinator: copiedTarget, sessionRevision: sessionRevision, publisherClient: publisherClient, publisherHost: publisherHost)) }
        }
        .navigationDestination(item: $submittedResource) { resource in
            if let publisherHost { publisherHost(resource) }
        }
        .sheet(item: modeReview.binding(modePresentation)) { original in
            ProjectEditModeReviewSheet(controller: modeReview, original: original, finished: { created in
                copiedCoordinator = created; showingCopy = true; modeCopyFailed = false
            }, failed: { modeCopyFailed = true })
        }
        .sheet(item: submissionBinding(presentedSubmission: presentedSubmission, submissionIncarnation: submissionIncarnation)) { receipt in
            submissionResult(receipt: receipt, submissionIncarnation: submissionIncarnation)
        }
        .sheet(item: ownedCover.binding(coverPresentation)) { original in
            OwnedTopicCoverAuthorView(original: original, mayChange: { ownedCover.mayChange(original.opening) },
                selected: { ownedCover.acceptedSelection($0); reviewRequest.retire(); approvedRelease.retire() }, close: { ownedCover.close(original) }, picker: ownedCoverPicker?())
        }
        .sheet(item: approvedRelease.binding(releasePresentation)) { original in
            if approvedRelease.isPresented(original) {
                ApprovedReleasePreparationView(original: original) { approvedRelease.close(original) }
            }
        }
        .sheet(item: reviewRequest.binding(reviewRequestPresentation)) { original in
            if reviewRequest.isPresented(original) { ApprovedTopicReviewRequestView(original: original) { reviewRequest.close(original) } }
        }
        .modifier(ProjectEditStarterPresentation(model: model, controller: starter))
        .modifier(ProjectEditPendingPresentation(model: model, controller: pending))
        .onDisappear { if let coverPresentation { ownedCover.close(coverPresentation) }; reviewRequest.retire(); approvedRelease.retire(); starter.retire(); pending.retire(); model.leave() }
        .modifier(ProjectEditPreparedReviewPresentation(model: model))
        .alert("projectEdit.discardTitle", isPresented: $discardConfirmation) {
            Button("projectEdit.discardLocal", role: .destructive) { model.discard() }
            Button("action.cancel", role: .cancel) {}
        } message: { Text("projectEdit.discardHint") }
    }
    private func submissionBinding(presentedSubmission: PublishingSubmissionHandoff?, submissionIncarnation: UUID) -> Binding<PublishingSubmissionHandoff?> {
        Binding<PublishingSubmissionHandoff?>(get: { () -> PublishingSubmissionHandoff? in
            guard let original = presentedSubmission, model.submissionIsCurrent(original, incarnation: submissionIncarnation), submission?.id == original.id else { return nil }
            return submission
        }, set: { (next: PublishingSubmissionHandoff?) in
            guard model.editorIncarnation == submissionIncarnation, next == nil, let presentedSubmission, submission?.id == presentedSubmission.id else { return }; submission = nil
        })
    }
    @ViewBuilder private func submissionResult(receipt: PublishingSubmissionHandoff, submissionIncarnation: UUID) -> some View {
        if model.submissionIsCurrent(receipt, incarnation: submissionIncarnation) {
            PublishingSubmissionResultSheet(receipt: receipt, canNavigate: publisherHost != nil, canVerifyRelease: model.approvedReleaseReadIsConfigured) {
                guard model.submissionIsCurrent(receipt, incarnation: submissionIncarnation), submission?.id == receipt.id else { return }
                submission = nil
                if publisherHost != nil { submittedResource = receipt.resource }
            }
        }
    }
    private func chapterStructure(opening: ProjectEditStarterController.Lease?) -> some View {
        Section("projectEdit.structure") {
            ForEach(model.draft.chapters) { chapter in
                NavigationLink {
                    ProjectEditChapterView(model: model, chapterID: chapter.id)
                } label: {
                    chapterLabel(chapter)
                }.accessibilityIdentifier("projectEdit.chapter." + chapter.id)
            }
            .onDelete { if model.fullEdit { model.draft.chapters.remove(atOffsets: $0) } }
            .onMove { if model.fullEdit { model.draft.chapters.move(fromOffsets: $0, toOffset: $1) } }
            Button("projectStarter.createChapter", systemImage: "plus") {
                let ordinal = model.draft.chapters.filter { $0.preserved["opening"] != .bool(true) }.count + 1
                let name = String(localized: LocalizedStringResource("projectStarter.defaultChapter", defaultValue: "Chapter \(ordinal)", locale: locale))
                starter.createChapter(lease: opening, name: name)
            }.buttonStyle(.borderless)
                .disabled(!model.fullEdit).accessibilityIdentifier("projectEdit.addChapter")
        }
    }
    private func chapterLabel(_ chapter: ProjectEditChapter) -> some View {
        let nodeCount = chapter.nodes.count
        let nodeCountLabel: Text = Text("projectEdit.nodeCount") + Text(verbatim: ": \(nodeCount)")
        return VStack(alignment: .leading, spacing: 4) {
            ProjectEditName(value: chapter.name, fallback: "projectEdit.untitledChapter")
            Text(verbatim: String(nodeCount)).font(.caption).foregroundStyle(.secondary)
                .accessibilityLabel(nodeCountLabel)
        }
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
    var showsDeferredHint = true
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(title, text: $value).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier(identifier)
            if showsDeferredHint { Text("projectEdit.mediaDeferred").font(.caption).foregroundStyle(.secondary) }
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
