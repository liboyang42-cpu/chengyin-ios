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

@MainActor
final class ProfileEditModel: ObservableObject {
    let coordinator: ProfileEditCoordinator
    @Published var draft = ProfileEditDraft() { didSet { avatarDraftRevision &+= 1; if draft.avatarReplacement == nil { avatarPreview = nil }; retireReload() } }
    @Published var confirmation: ProfileEditConfirmation?
    @Published private(set) var reloadConfirmation: ProfileEditReloadConfirmation?
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
    }
    private static func sameSnapshot(_ lhs: ProfileEditSnapshot, _ rhs: ProfileEditSnapshot) -> Bool {
        lhs.id == rhs.id && zip([lhs.nickname, lhs.introduction, lhs.avatar, lhs.wechat, lhs.casePics, lhs.tagIds],
                              [rhs.nickname, rhs.introduction, rhs.avatar, rhs.wechat, rhs.casePics, rhs.tagIds])
            .allSatisfy { $0.0.utf8.elementsEqual($0.1.utf8) }
    }
    private var hasUnsavedDraft: Bool {
        guard let snapshot = coordinator.snapshot else { return false }
        let sameText = draft.name.utf8.elementsEqual(snapshot.nickname.utf8)
            && draft.introduction.utf8.elementsEqual(snapshot.introduction.utf8)
        let samePreferences = draft.routePreferenceIDs.map { $0.map(String.init).joined(separator: ",").utf8.elementsEqual(snapshot.tagIds.utf8) } ?? true
        return !sameText || !samePreferences || draft.avatarReplacement != nil
    }
    func ownsAvatarScope(_ scope: ProfileAvatarScope) -> Bool {
        avatarActive && scope.editorID == avatarEditorID && scope.lifetimeID == avatarLifetimeID &&
            coordinator.identity == scope.identity && coordinator.viewerRevision == scope.viewerRevision
    }
    func avatarTarget(source: ProfileAvatarUploadClient) -> ProfileAvatarTarget? {
        guard avatarActive, !busy, confirmation == nil, reloadConfirmation == nil, draft.avatarReplacement == nil,
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
        draft = .init(name: draft.name, introduction: draft.introduction, routePreferenceIDs: draft.routePreferenceIDs)
    }
    func observeAvatarRetirement(_ action: @escaping () -> Void) { avatarRetirement = action }
    func retireAvatar() { avatarActive = false; avatarLifetimeID = UUID(); avatarPreview = nil; avatarRetirement?() }
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
    func cancelReload() { reloadConfirmation = nil }
    func retireReload() { reloadContextRevision &+= 1; cancelReload() }
    func requestReload() async {
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
        retireReload(); retireAvatar(); activateAvatar()
        generation += 1; draft = .init(); confirmation = nil; busy = false
        contextIdentity = coordinator.identity; contextViewerRevision = coordinator.viewerRevision
        coordinator.synchronizeSession()
    }
    func resetAndLoad() async {
        retireReload(); retireAvatar(); activateAvatar()
        generation += 1; draft = .init(); confirmation = nil; busy = false
        coordinator.synchronizeSession()
        await load()
    }
    func load() async {
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
        retireReload()
        synchronizeContext()
        let identity = coordinator.identity, viewerRevision = coordinator.viewerRevision
        let request = generation; busy = true
        await coordinator.prepare(draft, avatarValidity: avatarSaveValidity(for: draft))
        guard request == generation else { return }
        guard retainContext(identity: identity, viewerRevision: viewerRevision) else { return }
        confirmation = coordinator.confirmation; busy = false; revision += 1
        if coordinator.messageKey == "profile.edit.changed", let snapshot = coordinator.snapshot { draft = snapshot.draft }
    }
    func save(_ value: ProfileEditConfirmation) async {
        retireReload()
        synchronizeContext()
        let identity = coordinator.identity, viewerRevision = coordinator.viewerRevision
        let request = generation; confirmation = nil; busy = true
        await coordinator.save(value)
        guard request == generation else { return }
        guard retainContext(identity: identity, viewerRevision: viewerRevision) else { return }
        if coordinator.messageKey == "profile.edit.saved" || coordinator.messageKey == "profile.edit.changed",
           let snapshot = coordinator.snapshot { draft = snapshot.draft }
        busy = false; revision += 1
    }
}

/// Parent passes its live session revision and retains the coordinator outside navigation.
struct ProfileEditView: View {
    private enum Field: Hashable { case name, introduction }
    @FocusState private var focusedField: Field?
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: ProfileEditModel
    let sessionRevision: UInt64
    let categoryReader: (any DiscoveryReading)?
    let avatarDependencies: ProfileAvatarDependencies?
    @State private var showPreferences = false
    @State private var showReloadConfirmation = false
    private var selectedPreferences: [Int] {
        model.draft.routePreferenceIDs ?? (model.coordinator.snapshot?.tagIds ?? "").split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
    init(coordinator: ProfileEditCoordinator, sessionRevision: UInt64, categoryReader: (any DiscoveryReading)? = nil, avatarDependencies: ProfileAvatarDependencies? = nil) {
        _model = StateObject(wrappedValue: ProfileEditModel(coordinator: coordinator))
        self.sessionRevision = sessionRevision; self.categoryReader = categoryReader; self.avatarDependencies = avatarDependencies
    }
    var body: some View {
        Form {
            if model.coordinator.identity == nil {
                Text("profile.edit.signIn")
            } else if !model.coordinator.isConfigured {
                Text("profile.edit.unavailable")
            } else {
                if model.coordinator.snapshot != nil {
                    Section {
                        TextField("profile.edit.name", text: $model.draft.name)
                            .textContentType(.nickname).focused($focusedField,equals:.name)
                            .accessibilityIdentifier("profile.edit.name")
                        TextField("profile.edit.introduction", text: $model.draft.introduction, axis: .vertical)
                            .lineLimit(3...8).focused($focusedField,equals:.introduction)
                            .accessibilityIdentifier("profile.edit.introduction")
                    } header: { Text("profile.edit.details") }
                        .disabled(model.busy || model.coordinator.isLocked)
                    ProfileAvatarDraftSection(model: model, dependencies: avatarDependencies)
                    Section("context.preferences.title") {
                        LabeledContent("context.preferences.selected", value: String(selectedPreferences.count))
                        Button("context.preferences.edit") { focusedField = nil; showPreferences = true }
                            .disabled(model.busy || model.coordinator.isLocked).accessibilityIdentifier("profile.edit.preferences")
                    }
                    Button { focusedField=nil; Task { await model.prepare() } } label: { Text("profile.edit.review") }
                        .disabled(model.busy || model.coordinator.isLocked || !model.draft.isValid
                                  || model.draft.normalized == model.coordinator.snapshot?.draft.normalized)
                        .accessibilityIdentifier("profile.edit.review")
                }
                if let key = model.coordinator.messageKey {
                    Text(LocalizedStringKey(key)).accessibilityIdentifier("profile.edit.status")
                }
                if let remote = model.coordinator.remoteMessage { Text(verbatim: remote) }
                Button { focusedField = nil; Task { await model.requestReload() } } label: {
                    Text(LocalizedStringKey(model.coordinator.isLocked ? "profile.edit.check" : "profile.edit.reload"))
                }.disabled(model.busy).accessibilityIdentifier("profile.edit.reload")
                if model.busy { ProgressView().accessibilityIdentifier("profile.edit.busy") }
            }
        }
        .background(ProfileAvatarOwnerAnchor(model: model).frame(width: 0, height: 0))
        .appNavigationTitle("profile.edit.title")
        .confirmationDialog("profile.reloadDiscard.title", isPresented: $showReloadConfirmation,
                            titleVisibility: .visible, presenting: model.reloadConfirmation) { value in
            Button("profile.reloadDiscard.confirm", role: .destructive) { _ = model.confirmReload(value) }
                .accessibilityIdentifier("profile.reloadDiscard.confirm")
            Button("action.cancel", role: .cancel) { model.cancelReload() }
        } message: { _ in Text("profile.reloadDiscard.message") }
        .onChange(of: model.reloadConfirmation?.id) { _, id in showReloadConfirmation = id != nil }
        .onChange(of: showReloadConfirmation) { _, showing in if !showing { model.cancelReload() } }
        .onChange(of: model.confirmation?.id) { _, _ in model.retireReload() }
        .onChange(of: sessionRevision) { _, _ in model.retireReload() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.retireReload(); model.retireAvatar() } else { model.activateAvatar() }
        }
        .task(id: sessionRevision) { showPreferences = false; await model.resetAndLoad() }
        .sheet(isPresented: $showPreferences) {
            NavigationStack { ProfileRoutePreferencePicker(reader: categoryReader, selected: selectedPreferences,
                currentIdentity: { model.coordinator.identity }) { model.draft.routePreferenceIDs = $0 } }
        }
        .onDisappear {
            if !showPreferences, model.confirmation == nil, !model.avatarPresentationActive { model.retireAvatar() }
            model.retireReload()
            if let value = model.confirmation { model.coordinator.cancel(value) }
        }
        .sheet(item: $model.confirmation) { value in
            NavigationStack {
                Form {
                    Section {
                        LabeledContent { Text(verbatim: value.payload.name) } label: { Text("profile.edit.name") }
                        LabeledContent { Text(verbatim: value.payload.introduction) } label: { Text("profile.edit.introduction") }
                        if value.payload.avatarReplacement != nil { Text("profile.avatar.confirmChange") }
                        Text("profile.edit.confirmHint")
                    }
                    Button { Task { await model.save(value) } } label: { Text("profile.edit.confirm") }
                        .accessibilityIdentifier("profile.edit.confirm")
                    Button(role: .cancel) {
                        model.coordinator.cancel(value); model.confirmation = nil
                    } label: { Text("profile.edit.cancel") }
                }.appNavigationTitle("profile.edit.reviewTitle")
            }.interactiveDismissDisabled(model.busy)
        }
    }
}
