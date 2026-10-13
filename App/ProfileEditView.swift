import SwiftUI

struct ProfileEditReloadConfirmation: Identifiable {
    let id = UUID()
    fileprivate let identity: ProfileReadIdentity
    fileprivate let viewerRevision: UInt64?
    fileprivate let generation: Int
    fileprivate let modelRevision: Int
    fileprivate let reloadContextRevision: UInt64
    fileprivate let snapshot: ProfileEditSnapshot
    fileprivate let draft: ProfileEditDraft
}

/// A local navigation decision, never permission to save or retry a write.
struct ProfileEditExitConfirmation: Identifiable {
    let id = UUID()
    fileprivate let identity: ProfileReadIdentity
    fileprivate let viewerRevision: UInt64?
    fileprivate let generation: Int
    fileprivate let modelRevision: Int
    fileprivate let contextRevision: UInt64
    fileprivate let snapshot: ProfileEditSnapshot
    fileprivate let draft: ProfileEditDraft
    fileprivate let writeWasLocked: Bool
}

@MainActor
final class ProfileEditModel: ObservableObject {
    let coordinator: ProfileEditCoordinator
    @Published var draft = ProfileEditDraft() { didSet { retireSavedReturn(); retireTextEdit(); avatarDraftRevision &+= 1; if draft.avatarReplacement == nil { avatarPreview = nil }; retireReload() } }
    @Published var confirmation: ProfileEditConfirmation?
    @Published private(set) var reloadConfirmation: ProfileEditReloadConfirmation?
    @Published private(set) var exitConfirmation: ProfileEditExitConfirmation?
    @Published private(set) var textEdit: ProfileTextFieldEdit?
    private struct ReviewedDraft {
        let reviewID: UUID
        let generation: Int
        let modelRevision: Int
        let draftRevision: UInt64
        let draft: ProfileEditDraft
        let identity: ProfileReadIdentity?
        let viewerRevision: UInt64?
    }
    private var reviewedDraft: ReviewedDraft?
    private var savedReturnRevision: UInt64 = 0
    private struct SavedReturnOwner {
        let receipt: ProfileSavedReturn
        let generation: Int
        let revision: UInt64
        let draft: ProfileEditDraft
    }
    private var savedReturnOwner: SavedReturnOwner?
    func retireSavedReturn() { savedReturnRevision &+= 1; savedReturnOwner = nil }
    /// The view invokes its navigation callback only after this synchronous fence.
    func consumeSavedReturn(_ value: ProfileSavedReturn) -> Bool {
        guard let owner = savedReturnOwner, owner.receipt == value else { return false }
        savedReturnOwner = nil
        guard !Task.isCancelled, !exitCommitted, !busy, !coordinator.isBusy,
              owner.generation == generation, owner.revision == savedReturnRevision,
              Self.sameDraft(draft, owner.draft), coordinator.consumeSavedReturn(value) else { return false }
        return true
    }
    private var exitCommitted = false
    @Published private(set) var busy = false
    @Published private(set) var revision = 0
    let avatarEditorID = UUID()
    @Published private(set) var avatarLifetimeID = UUID()
    @Published private(set) var avatarPreview: RetainedSelectedImage?
    private(set) var avatarDraftRevision: UInt64 = 0
    var avatarPresentationActive = false
    private var avatarActive = true
    private var avatarRetirement: (() -> Void)?
    private var generation = 0
    private var reloadContextRevision: UInt64 = 0
    private var contextIdentity: ProfileReadIdentity?
    private var contextViewerRevision: UInt64?
    init(coordinator: ProfileEditCoordinator) {
        self.coordinator = coordinator
        contextIdentity = coordinator.identity; contextViewerRevision = coordinator.viewerRevision
    }
    /// Compare the typed bytes, including whitespace and Unicode normalization.
    private static func sameDraft(_ lhs: ProfileEditDraft, _ rhs: ProfileEditDraft) -> Bool {
        lhs.name.utf8.elementsEqual(rhs.name.utf8) && lhs.introduction.utf8.elementsEqual(rhs.introduction.utf8)
        && lhs.routePreferenceIDs == rhs.routePreferenceIDs && lhs.avatarReplacement == rhs.avatarReplacement
        && ProfileCasePortfolio.sameText(lhs.caseIntroduction, rhs.caseIntroduction)
        && lhs.removesContactQR == rhs.removesContactQR
        && lhs.removesCasePictures == rhs.removesCasePictures
    }
    private static func sameSnapshot(_ lhs: ProfileEditSnapshot, _ rhs: ProfileEditSnapshot) -> Bool {
        lhs.id == rhs.id && ProfileCasePortfolio.sameText(lhs.caseIntroduction, rhs.caseIntroduction) && zip([lhs.nickname, lhs.introduction, lhs.avatar, lhs.wechat, lhs.casePics, lhs.tagIds],
                              [rhs.nickname, rhs.introduction, rhs.avatar, rhs.wechat, rhs.casePics, rhs.tagIds])
            .allSatisfy { $0.0.utf8.elementsEqual($0.1.utf8) }
    }
    private var hasUnsavedDraft: Bool {
        guard let snapshot = coordinator.snapshot else { return false }
        let sameText = draft.name.utf8.elementsEqual(snapshot.nickname.utf8)
            && draft.introduction.utf8.elementsEqual(snapshot.introduction.utf8)
        let samePreferences = draft.routePreferenceIDs.map { $0.map(String.init).joined(separator: ",").utf8.elementsEqual(snapshot.tagIds.utf8) } ?? true
        return !sameText || !samePreferences || draft.avatarReplacement != nil
            || (draft.caseIntroduction.map { !ProfileCasePortfolio.sameText($0, snapshot.caseIntroduction) } ?? false)
            || (draft.removesContactQR && !snapshot.wechat.isEmpty)
            || (draft.removesCasePictures && ProfileCasePortfolio(casePics: snapshot.casePics).imageCount > 0)
    }
    /// This is local scratch editing, never an independent server save.
    var canBeginTextEdit: Bool {
        !exitCommitted && !busy && !coordinator.isBusy && !coordinator.isLocked
            && coordinator.isConfigured && coordinator.snapshot != nil
            && confirmation == nil && coordinator.confirmation == nil
            && reloadConfirmation == nil && exitConfirmation == nil
            && textEdit == nil && !avatarPresentationActive
    }
    func beginTextEdit(_ field: ProfileTextField) {
        guard !exitCommitted else { return }
        synchronizeContext()
        guard canBeginTextEdit, let identity = coordinator.identity,
              let snapshot = coordinator.snapshot else { return }
        textEdit = .init(field: field, identity: identity, viewerRevision: coordinator.viewerRevision,
            generation: generation, modelRevision: revision, draftRevision: avatarDraftRevision,
            snapshot: snapshot, draft: draft)
    }
    func cancelTextEdit(_ value: ProfileTextFieldEdit) {
        guard textEdit?.id == value.id else { return }
        retireTextEdit()
    }
    private func retireTextEdit() { textEdit = nil }
    @discardableResult func confirmTextEdit(_ value: ProfileTextFieldEdit, text: String) -> Bool {
        guard textEdit?.id == value.id else { return false }
        guard !exitCommitted, !busy, !coordinator.isBusy, !coordinator.isLocked,
              confirmation == nil, coordinator.confirmation == nil,
              reloadConfirmation == nil, exitConfirmation == nil, !avatarPresentationActive,
              coordinator.identity == value.identity, coordinator.viewerRevision == value.viewerRevision,
              generation == value.generation, revision == value.modelRevision,
              avatarDraftRevision == value.draftRevision, Self.sameDraft(draft, value.draft),
              let snapshot = coordinator.snapshot, Self.sameSnapshot(snapshot, value.snapshot) else {
            cancelTextEdit(value); return false
        }
        // Consume before assigning: a repeated or late action cannot touch a newer field.
        retireTextEdit()
        var next = draft
        switch value.field {
        case .name: next.name = text
        case .introduction: next.introduction = text
        case .caseIntroduction:
            guard snapshot.caseIntroduction != nil else { return false }
            next.caseIntroduction = ProfileCasePortfolio.sameText(text, snapshot.caseIntroduction) ? nil : text
        case .contactQR:
            // A QR editor may retain original bytes or clear them, never supply a replacement URL.
            guard text.isEmpty || text.utf8.elementsEqual(snapshot.wechat.utf8) else { return false }
            next.removesContactQR = text.isEmpty && !snapshot.wechat.isEmpty
        case .casePictures:
            guard text.isEmpty || text.utf8.elementsEqual(snapshot.casePics.utf8) else { return false }
            next.removesCasePictures = text.isEmpty && ProfileCasePortfolio(casePics: snapshot.casePics).imageCount > 0
        case .preferences:
            guard let original = ProfilePreferenceRemoval.selection(draft: draft, snapshot: snapshot),
                  let selected = ProfilePreferenceRemoval.parse(text),
                  ProfilePreferenceRemoval.isOrderedSubset(selected, of: original) else { return false }
            // No-op confirmation must keep nil/raw preservation and existing staged edits.
            if selected != original { next.routePreferenceIDs = selected }
        }
        draft = next
        return true
    }
    @discardableResult func confirmContactQR(_ value: ProfileTextFieldEdit, remove: Bool) -> Bool {
        guard value.field == .contactQR else { return false }
        return confirmTextEdit(value, text: remove ? "" : value.snapshot.wechat)
    }
    @discardableResult func confirmPreferenceRemoval(_ value: ProfileTextFieldEdit, selectedIDs: [Int]) -> Bool {
        guard value.field == .preferences,
              ProfilePreferenceRemoval.validIDs(selectedIDs) else { return false }
        return confirmTextEdit(value, text: selectedIDs.map(String.init).joined(separator: ","))
    }
    @discardableResult func confirmCasePictureRemoval(_ value: ProfileTextFieldEdit, remove: Bool) -> Bool {
        guard value.field == .casePictures else { return false }
        return confirmTextEdit(value, text: remove ? "" : value.snapshot.casePics)
    }
    func ownsAvatarScope(_ scope: ProfileAvatarScope) -> Bool {
        avatarActive && scope.editorID == avatarEditorID && scope.lifetimeID == avatarLifetimeID &&
            coordinator.identity == scope.identity && coordinator.viewerRevision == scope.viewerRevision
    }
    func avatarTarget(source: ProfileAvatarUploadClient) -> ProfileAvatarTarget? {
        guard avatarActive, !busy, confirmation == nil, reloadConfirmation == nil, exitConfirmation == nil, textEdit == nil, draft.avatarReplacement == nil,
              let snapshot = coordinator.snapshot,
              let scope = coordinator.avatarScope(source: source, editorID: avatarEditorID, lifetimeID: avatarLifetimeID) else { return nil }
        return try? .init(scope: scope, snapshot: snapshot, draft: draft, draftRevision: avatarDraftRevision)
    }
    func stageAvatar(_ replacement: ProfileAvatarReplacement, preview: RetainedSelectedImage?) {
        // Flow checked this exact owner, snapshot, draft and revision immediately before calling.
        draft = draft.stagingAvatar(replacement); avatarPreview = preview
    }
    func discardAvatar(id: UUID) {
        guard !busy, !coordinator.isLocked, draft.avatarReplacement?.id == id else { return }
        draft = .init(name: draft.name, introduction: draft.introduction, routePreferenceIDs: draft.routePreferenceIDs, caseIntroduction: draft.caseIntroduction, removesContactQR: draft.removesContactQR, removesCasePictures: draft.removesCasePictures)
    }
    func observeAvatarRetirement(_ action: @escaping () -> Void) { avatarRetirement = action }
    func retireAvatar() { retireSavedReturn(); cancelExit(); reviewedDraft = nil; avatarActive = false; avatarLifetimeID = UUID(); avatarPreview = nil; avatarRetirement?() }
    func activateAvatar() { avatarActive = true }
    private func avatarSaveValidity(for captured: ProfileEditDraft) -> ProfileAvatarSaveValidity? {
        guard let replacement = captured.avatarReplacement else { return nil }
        let revision = avatarDraftRevision, fingerprint = ProfileAvatarExact.draft(captured)
        return ProfileAvatarSaveValidity { [weak self] in
            guard let self else { return false }
            return self.ownsAvatarScope(replacement.receipt.target.scope) && self.avatarDraftRevision == revision &&
                ProfileAvatarExact.draft(self.draft) == fingerprint
        }
    }
    /// Disable unreviewed modal dismissal while local changes or an operation exist.
    /// The explicit Back action remains available after an unknown save has settled.
    var blocksInteractiveExit: Bool { !exitCommitted && (hasUnsavedDraft || textEdit != nil || busy || coordinator.isBusy) }
    var canRequestExit: Bool {
        !exitCommitted && !busy && !coordinator.isBusy && confirmation == nil
            && coordinator.confirmation == nil && reloadConfirmation == nil && textEdit == nil && !avatarPresentationActive
    }
    func cancelExit() { exitConfirmation = nil }
    /// True means the caller may dismiss now; false either presents a review or blocks
    /// a competing operation. Nothing in this path dispatches a read or a write.
    @discardableResult func requestExit() -> Bool {
        synchronizeContext()
        guard canRequestExit else { return false }
        cancelExit()
        guard hasUnsavedDraft else { return commitExit() }
        guard let identity = coordinator.identity, let snapshot = coordinator.snapshot else { return false }
        exitConfirmation = .init(identity: identity, viewerRevision: coordinator.viewerRevision,
            generation: generation, modelRevision: revision, contextRevision: reloadContextRevision,
            snapshot: snapshot, draft: draft, writeWasLocked: coordinator.isLocked)
        return false
    }
    private func canExit(_ value: ProfileEditExitConfirmation) -> Bool {
        guard canRequestExit, coordinator.identity == value.identity,
              coordinator.viewerRevision == value.viewerRevision, generation == value.generation,
              revision == value.modelRevision, reloadContextRevision == value.contextRevision,
              coordinator.isLocked == value.writeWasLocked,
              Self.sameDraft(draft, value.draft), let snapshot = coordinator.snapshot else { return false }
        return Self.sameSnapshot(snapshot, value.snapshot)
    }
    /// Validate and consume synchronously, so a stale or repeated dialog action cannot
    /// navigate a newer editor. The coordinator's pending-write lock is never cleared.
    @discardableResult func confirmExit(_ value: ProfileEditExitConfirmation) -> Bool {
        guard exitConfirmation?.id == value.id else { return false }
        guard canExit(value) else { cancelExit(); return false }
        return commitExit()
    }
    private func commitExit() -> Bool {
        guard !exitCommitted else { return false }
        exitCommitted = true
        retireReload(); retireAvatar()
        coordinator.leaveScreen()
        draft = .init()
        return true
    }
    func cancelReload() { reloadConfirmation = nil }
    func retireReload() { reloadContextRevision &+= 1; cancelReload(); cancelExit() }
    func requestReload() async {
        retireSavedReturn()
        guard !exitCommitted else { return }
        guard textEdit == nil else { return }
        synchronizeContext()
        guard !busy, !coordinator.isBusy, confirmation == nil, coordinator.confirmation == nil else { return }
        retireReload()
        // A locked write uses the original read-only reconciliation path unchanged.
        guard !coordinator.isLocked, hasUnsavedDraft else { await load(); return }
        guard let identity = coordinator.identity, let snapshot = coordinator.snapshot,
              coordinator.isConfigured else { return }
        reloadConfirmation = .init(identity: identity, viewerRevision: coordinator.viewerRevision,
            generation: generation, modelRevision: revision, reloadContextRevision: reloadContextRevision,
            snapshot: snapshot, draft: draft)
    }
    private func canReload(_ value: ProfileEditReloadConfirmation) -> Bool {
        guard !busy, !coordinator.isBusy, !coordinator.isLocked, coordinator.isConfigured,
              confirmation == nil, coordinator.confirmation == nil,
              coordinator.identity == value.identity, coordinator.viewerRevision == value.viewerRevision,
              generation == value.generation, revision == value.modelRevision,
              reloadContextRevision == value.reloadContextRevision,
              Self.sameDraft(draft, value.draft), let snapshot = coordinator.snapshot else { return false }
        return Self.sameSnapshot(snapshot, value.snapshot)
    }
    /// Consume the dialog synchronously before SwiftUI dismisses it; recheck again
    /// when the task starts so a queued action cannot reload another context.
    @discardableResult func confirmReload(_ value: ProfileEditReloadConfirmation) -> Task<Void, Never>? {
        guard reloadConfirmation?.id == value.id else { return nil }
        guard canReload(value) else { cancelReload(); return nil }
        reloadConfirmation = nil
        return Task { [weak self] in
            guard let self, !Task.isCancelled, self.canReload(value) else { return }
            await self.load()
        }
    }
    private func synchronizeContext() {
        guard contextIdentity != coordinator.identity || contextViewerRevision != coordinator.viewerRevision else { return }
        retireTextEdit()
        retireReload(); retireAvatar(); activateAvatar()
        generation += 1; draft = .init(); confirmation = nil; busy = false
        contextIdentity = coordinator.identity; contextViewerRevision = coordinator.viewerRevision
        coordinator.synchronizeSession()
    }
    func resetAndLoad() async {
        // A committed exit ends this model's lifetime. Only a new navigation
        // destination/model may reopen; a delayed or cancelled .task may not.
        guard !exitCommitted, !Task.isCancelled else { return }
        retireTextEdit()
        retireReload(); retireAvatar(); activateAvatar()
        generation += 1; draft = .init(); confirmation = nil; busy = false
        coordinator.synchronizeSession()
        await load()
    }
    func load() async {
        retireSavedReturn()
        guard !exitCommitted else { return }
        guard textEdit == nil else { return }
        retireReload()
        synchronizeContext()
        guard !busy else { return }
        let identity = coordinator.identity, viewerRevision = coordinator.viewerRevision
        let request = generation; busy = true
        let loaded = await coordinator.load()
        guard request == generation else { return }
        guard retainContext(identity: identity, viewerRevision: viewerRevision) else { return }
        // Failed refresh keeps all unsaved fields, including route preferences.
        if loaded, let snapshot = coordinator.snapshot { draft = snapshot.draft }
        busy = false; revision += 1
    }
    // Retain drafts only within the exact viewer context, including role/token ABA fences.
    private func retainContext(identity: ProfileReadIdentity?, viewerRevision: UInt64?) -> Bool {
        guard coordinator.identity == identity, coordinator.viewerRevision == viewerRevision else {
            synchronizeContext(); revision += 1
            return false
        }
        return true
    }
    func prepare() async {
        retireSavedReturn()
        guard !exitCommitted else { return }
        guard textEdit == nil else { return }
        retireReload()
        synchronizeContext()
        let identity = coordinator.identity, viewerRevision = coordinator.viewerRevision
        let request = generation; busy = true
        let captured = draft, capturedRevision = avatarDraftRevision
        reviewedDraft = nil
        await coordinator.prepare(draft, avatarValidity: avatarSaveValidity(for: draft))
        guard request == generation else { return }
        guard retainContext(identity: identity, viewerRevision: viewerRevision) else { return }
        confirmation = coordinator.confirmation; busy = false; revision += 1
        if coordinator.messageKey == "profile.edit.changed", let snapshot = coordinator.snapshot { draft = snapshot.draft }
        if let value = confirmation, avatarDraftRevision == capturedRevision, Self.sameDraft(draft, captured) {
            reviewedDraft = .init(reviewID: value.id, generation: generation, modelRevision: revision,
                draftRevision: capturedRevision, draft: captured, identity: identity, viewerRevision: viewerRevision)
        }
    }
    func canRestoreReviewedDraft(_ value: ProfileEditConfirmation) -> Bool {
        guard !exitCommitted, !busy, !coordinator.isBusy, !coordinator.isLocked,
              textEdit == nil, !avatarPresentationActive, reloadConfirmation == nil, exitConfirmation == nil,
              confirmation == value, coordinator.confirmation == value,
              let captured = reviewedDraft, captured.reviewID == value.id,
              captured.generation == generation, captured.modelRevision == revision,
              captured.draftRevision == avatarDraftRevision, Self.sameDraft(draft, captured.draft),
              captured.identity == coordinator.identity, captured.viewerRevision == coordinator.viewerRevision else { return false }
        return true
    }
    /// Restore every field atomically from the latest reviewed self read and remain here.
    @discardableResult func restoreReviewedDraft(_ value: ProfileEditConfirmation) -> Bool {
        guard canRestoreReviewedDraft(value), let snapshot = coordinator.discardReviewedDraft(value) else { return false }
        reviewedDraft = nil; confirmation = nil
        retireReload(); retireAvatar(); activateAvatar()
        draft = snapshot.draft; revision += 1
        return true
    }
    @discardableResult func save(_ value: ProfileEditConfirmation) async -> ProfileSavedReturn? {
        let returnsReviewedDraft = canRestoreReviewedDraft(value)
        retireSavedReturn()
        guard !exitCommitted else { return nil }
        guard textEdit == nil else { return nil }
        retireReload()
        synchronizeContext()
        let identity = coordinator.identity, viewerRevision = coordinator.viewerRevision
        let request = generation, returnRevision = savedReturnRevision
        let capturedDraft = draft, capturedDraftRevision = avatarDraftRevision
        reviewedDraft = nil; confirmation = nil; busy = true
        let receipt = await coordinator.save(value)
        guard request == generation else { return nil }
        guard retainContext(identity: identity, viewerRevision: viewerRevision) else { return nil }
        let mayReturn = returnsReviewedDraft && !Task.isCancelled && !exitCommitted && returnRevision == savedReturnRevision
            && capturedDraftRevision == avatarDraftRevision && Self.sameDraft(draft, capturedDraft)
        if coordinator.messageKey == "profile.edit.saved" || coordinator.messageKey == "profile.edit.changed",
           let snapshot = coordinator.snapshot { draft = snapshot.draft }
        busy = false; revision += 1
        guard mayReturn, let receipt else { return nil }
        savedReturnOwner = .init(receipt: receipt, generation: generation,
            revision: savedReturnRevision, draft: draft)
        return receipt
    }
}

/// Parent passes its live session revision and retains the coordinator outside navigation.
struct ProfileEditView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ProfileEditModel
    let sessionRevision: UInt64
    let categoryReader: (any DiscoveryReading)?
    let avatarDependencies: ProfileAvatarDependencies?
    let caseImageReader: (any RetainedPublicImageReading)?
    private let onSaved: (() -> Void)?
    @State private var showPreferences = false
    @State private var showReloadConfirmation = false
    @State private var showExitConfirmation = false
    private var selectedPreferences: [Int] {
        model.draft.routePreferenceIDs ?? (model.coordinator.snapshot?.tagIds ?? "").split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
    init(coordinator: ProfileEditCoordinator, sessionRevision: UInt64, categoryReader: (any DiscoveryReading)? = nil, avatarDependencies: ProfileAvatarDependencies? = nil, caseImageReader: (any RetainedPublicImageReading)? = nil, onSaved: (() -> Void)? = nil) {
        _model = StateObject(wrappedValue: ProfileEditModel(coordinator: coordinator))
        self.onSaved = onSaved
        self.sessionRevision = sessionRevision; self.categoryReader = categoryReader; self.avatarDependencies = avatarDependencies; self.caseImageReader = caseImageReader
    }
    private var editorForm: some View {
        Form {
            if model.coordinator.identity == nil {
                Text("profile.edit.signIn")
            } else if !model.coordinator.isConfigured {
                Text("profile.edit.unavailable")
            } else {
                if model.coordinator.snapshot != nil {
                    if let phone = model.coordinator.phoneDisplay {
                        Section {
                            LabeledContent("profile.phone.title") {
                                switch phone {
                                case .masked(let value): Text(verbatim: value).monospacedDigit()
                                case .unbound: Text("profile.phone.unbound")
                                case .unavailable: Text("profile.phone.unavailable")
                                }
                            }.privacySensitive().accessibilityIdentifier("profile.phone.value")
                            Text("profile.phone.readOnly").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        textFieldRow(.name, value: model.draft.name)
                        textFieldRow(.introduction, value: model.draft.introduction)
                    } header: { Text("profile.edit.details") }
                        .disabled(!model.canBeginTextEdit)
                    Section("profile.case.title") {
                        textFieldRow(.caseIntroduction, value: model.draft.caseIntroduction ?? model.coordinator.snapshot?.caseIntroduction ?? "")
                            .disabled(!model.canBeginTextEdit)
                        Button("profile.caseRemoval.open") { model.beginTextEdit(.casePictures) }
                            .disabled(!model.canBeginTextEdit).accessibilityIdentifier("profile.caseRemoval.open")
                        if model.draft.removesCasePictures { Text("profile.caseRemoval.staged") }
                    }
                    ProfileContactQRSection(wechat: model.coordinator.snapshot?.wechat ?? "", removes: model.draft.removesContactQR) {
                        model.beginTextEdit(.contactQR)
                    }.disabled(!model.canBeginTextEdit)
                    ProfileAvatarDraftSection(model: model, dependencies: avatarDependencies)
                    Section("context.preferences.title") {
                        LabeledContent("context.preferences.selected", value: String(selectedPreferences.count))
                        Button("profile.preferenceRemoval.open") { model.beginTextEdit(.preferences) }
                            .disabled(!model.canBeginTextEdit)
                            .accessibilityIdentifier("profile.preferenceRemoval.open")
                        Button("context.preferences.edit") { showPreferences = true }
                            .disabled(model.busy || model.coordinator.isLocked || model.textEdit != nil).accessibilityIdentifier("profile.edit.preferences")
                    }
                    Button { Task { await model.prepare() } } label: { Text("profile.edit.review") }
                        .disabled(model.busy || model.coordinator.isLocked || !model.draft.isValid
                                  || model.textEdit != nil || !(model.coordinator.snapshot.map { model.draft.hasChanges(comparedTo: $0) } ?? false))
                        .accessibilityIdentifier("profile.edit.review")
                }
                if let key = model.coordinator.messageKey {
                    Text(LocalizedStringKey(key)).accessibilityIdentifier("profile.edit.status")
                }
                if let remote = model.coordinator.remoteMessage { Text(verbatim: remote) }
                Button { Task { await model.requestReload() } } label: {
                    Text(LocalizedStringKey(model.coordinator.isLocked ? "profile.edit.check" : "profile.edit.reload"))
                }.disabled(model.busy || model.textEdit != nil).accessibilityIdentifier("profile.edit.reload")
                if model.busy { ProgressView().accessibilityIdentifier("profile.edit.busy") }
            }
        }
    }
    private var editorNavigation: some View {
        editorForm
        .background(ProfileAvatarOwnerAnchor(model: model).frame(width: 0, height: 0))
        .appNavigationTitle("profile.edit.title")
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(model.blocksInteractiveExit)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if model.requestExit() { dismiss() }
                } label: { Label("action.back", systemImage: "chevron.left") }
                .disabled(!model.canRequestExit)
                .accessibilityIdentifier("profile.exitDiscard.back")
                .confirmationDialog("profile.exitDiscard.title", isPresented: $showExitConfirmation,
                                    titleVisibility: .visible, presenting: model.exitConfirmation) { value in
                    Button("profile.exitDiscard.confirm", role: .destructive) {
                        if model.confirmExit(value) { dismiss() }
                    }.accessibilityIdentifier("profile.exitDiscard.confirm")
                    Button("action.cancel", role: .cancel) { model.cancelExit() }
                } message: { _ in Text("profile.exitDiscard.message") }
            }
        }
        .onChange(of: model.exitConfirmation?.id) { _, id in showExitConfirmation = id != nil }
        .onChange(of: showExitConfirmation) { _, showing in if !showing { model.cancelExit() } }
        .onChange(of: showPreferences) { _, _ in model.cancelExit() }
        .confirmationDialog("profile.reloadDiscard.title", isPresented: $showReloadConfirmation,
                            titleVisibility: .visible, presenting: model.reloadConfirmation) { value in
            Button("profile.reloadDiscard.confirm", role: .destructive) { _ = model.confirmReload(value) }
                .accessibilityIdentifier("profile.reloadDiscard.confirm")
            Button("action.cancel", role: .cancel) { model.cancelReload() }
        } message: { _ in Text("profile.reloadDiscard.message") }
        .onChange(of: model.reloadConfirmation?.id) { _, id in showReloadConfirmation = id != nil }
        .onChange(of: showReloadConfirmation) { _, showing in if !showing { model.cancelReload() } }
        .onChange(of: model.confirmation?.id) { _, _ in model.retireReload() }
        .onChange(of: sessionRevision) { _, _ in model.retireSavedReturn(); model.retireReload() }
        .onChange(of: sessionRevision) { _, _ in
            if let value = model.textEdit { model.cancelTextEdit(value) }
        }
    }
    var body: some View {
        editorNavigation
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.retireReload(); model.retireAvatar() } else { model.activateAvatar() }
        }
        .task(id: sessionRevision) { showPreferences = false; await model.resetAndLoad() }
        .sheet(item: textEditPresentation) { value in
            NavigationStack {
                if value.field == .contactQR {
                    ProfileContactQREditor(edit: value, reader: caseImageReader,
                        cancel: { model.cancelTextEdit(value) },
                        confirm: { _ = model.confirmContactQR(value, remove: $0) })
                        .id(value.id)
                } else if value.field == .casePictures {
                    ProfileCasePictureRemovalEditor(edit: value,
                        cancel: { model.cancelTextEdit(value) },
                        confirm: { _ = model.confirmCasePictureRemoval(value, remove: $0) })
                        .id(value.id)
                } else if value.field == .preferences {
                    ProfilePreferenceRemovalEditor(edit: value,
                        cancel: { model.cancelTextEdit(value) },
                        confirm: { _ = model.confirmPreferenceRemoval(value, selectedIDs: $0) })
                        .id(value.id)
                } else {
                    ProfileTextFieldEditor(edit: value, caseImageReader: caseImageReader,
                        cancel: { model.cancelTextEdit(value) },
                        confirm: { _ = model.confirmTextEdit(value, text: $0) })
                        .id(value.id)
                }
            }.interactiveDismissDisabled(false)
        }
        .sheet(isPresented: $showPreferences) {
            NavigationStack { ProfileRoutePreferencePicker(reader: categoryReader, selected: selectedPreferences,
                currentIdentity: { model.coordinator.identity }) { model.draft.routePreferenceIDs = $0 } }
        }
        .onDisappear(perform: handleEditorDisappear)
        .sheet(item: $model.confirmation) { value in
            NavigationStack {
                Form {
                    ProfileDraftReviewSection(summary: value.reviewSummary,
                        canRestore: model.canRestoreReviewedDraft(value),
                        restore: { _ = model.restoreReviewedDraft(value) })
                        .id(value.id)
                    Section {
                        LabeledContent { Text(verbatim: value.payload.name) } label: { Text("profile.edit.name") }
                        LabeledContent { Text(verbatim: value.payload.introduction) } label: { Text("profile.edit.introduction") }
                        if let text = value.payload.caseIntroduction {
                            LabeledContent { Text(verbatim: text) } label: { Text("profile.case.description") }
                        }
                        if value.payload.removesContactQR { Text("profile.contactQR.reviewRemoval") }
                        if value.payload.removesCasePictures { Text("profile.caseRemoval.review") }
                        if let ids = value.payload.preferenceIDs {
                            ProfilePreferenceRemovalReview(ids: ids)
                        }
                        if value.payload.avatarReplacement != nil { Text("profile.avatar.confirmChange") }
                        Text("profile.edit.confirmHint")
                    }
                    Button {
                        Task {
                            guard let receipt = await model.save(value), model.consumeSavedReturn(receipt) else { return }
                            if let onSaved { onSaved() } else { dismiss() }
                        }
                    } label: { Text("profile.edit.confirm") }
                        .accessibilityIdentifier("profile.edit.confirm")
                    Button(role: .cancel) {
                        model.coordinator.cancel(value); model.confirmation = nil
                    } label: { Text("profile.edit.cancel") }
                }.appNavigationTitle("profile.edit.reviewTitle")
            }.interactiveDismissDisabled(model.busy)
        }
    }
    /// Capture this presentation's token so a delayed swipe-dismissal cannot cancel its successor.
    private var textEditPresentation: Binding<ProfileTextFieldEdit?> {
        let presented = model.textEdit
        return .init(get: { model.textEdit }, set: { value in
            if value == nil, let presented { model.cancelTextEdit(presented) }
        })
    }
    private func textFieldRow(_ field: ProfileTextField, value: String) -> some View {
        Button { model.beginTextEdit(field) } label: {
            HStack {
                LabeledContent {
                    if field == .caseIntroduction, model.coordinator.snapshot?.caseIntroduction == nil {
                        Text("profile.case.descriptionUnavailable").font(.caption).foregroundStyle(.secondary)
                    } else if value.isEmpty { Text("profile.fieldEdit.empty").foregroundStyle(.secondary) }
                    else { Text(verbatim: value).lineLimit(3) }
                } label: { Text(LocalizedStringKey(field.titleKey)) }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile.fieldEdit.open.\(field.rawValue)")
    }

    private func handleEditorDisappear() {
        if !showPreferences, model.textEdit == nil, model.confirmation == nil, !model.avatarPresentationActive { model.retireAvatar() }
        model.retireReload()
        if let value = model.confirmation { model.coordinator.cancel(value) }
    }

}
