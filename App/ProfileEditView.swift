import SwiftUI

@MainActor
final class ProfileEditModel: ObservableObject {
    let coordinator: ProfileEditCoordinator
    @Published var draft = ProfileEditDraft()
    @Published var confirmation: ProfileEditConfirmation?
    @Published private(set) var busy = false
    @Published private(set) var revision = 0
    private var generation = 0
    private var contextIdentity: ProfileReadIdentity?
    private var contextViewerRevision: UInt64?
    init(coordinator: ProfileEditCoordinator) {
        self.coordinator = coordinator
        contextIdentity = coordinator.identity; contextViewerRevision = coordinator.viewerRevision
    }
    private func synchronizeContext() {
        guard contextIdentity != coordinator.identity || contextViewerRevision != coordinator.viewerRevision else { return }
        generation += 1; draft = .init(); confirmation = nil; busy = false
        contextIdentity = coordinator.identity; contextViewerRevision = coordinator.viewerRevision
        coordinator.synchronizeSession()
    }
    func resetAndLoad() async {
        generation += 1; draft = .init(); confirmation = nil; busy = false
        coordinator.synchronizeSession()
        await load()
    }
    func load() async {
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
        synchronizeContext()
        let identity = coordinator.identity, viewerRevision = coordinator.viewerRevision
        let request = generation; busy = true
        await coordinator.prepare(draft)
        guard request == generation else { return }
        guard retainContext(identity: identity, viewerRevision: viewerRevision) else { return }
        confirmation = coordinator.confirmation; busy = false; revision += 1
        if coordinator.messageKey == "profile.edit.changed", let snapshot = coordinator.snapshot { draft = snapshot.draft }
    }
    func save(_ value: ProfileEditConfirmation) async {
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
    @StateObject private var model: ProfileEditModel
    let sessionRevision: UInt64
    let categoryReader: (any DiscoveryReading)?
    @State private var showPreferences = false
    private var selectedPreferences: [Int] {
        model.draft.routePreferenceIDs ?? (model.coordinator.snapshot?.tagIds ?? "").split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
    init(coordinator: ProfileEditCoordinator, sessionRevision: UInt64, categoryReader: (any DiscoveryReading)? = nil) {
        _model = StateObject(wrappedValue: ProfileEditModel(coordinator: coordinator))
        self.sessionRevision = sessionRevision; self.categoryReader = categoryReader
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
                Button { Task { await model.load() } } label: {
                    Text(LocalizedStringKey(model.coordinator.isLocked ? "profile.edit.check" : "profile.edit.reload"))
                }.disabled(model.busy).accessibilityIdentifier("profile.edit.reload")
                if model.busy { ProgressView().accessibilityIdentifier("profile.edit.busy") }
            }
        }
        .appNavigationTitle("profile.edit.title")
        .task(id: sessionRevision) { showPreferences = false; await model.resetAndLoad() }
        .sheet(isPresented: $showPreferences) {
            NavigationStack { ProfileRoutePreferencePicker(reader: categoryReader, selected: selectedPreferences,
                currentIdentity: { model.coordinator.identity }) { model.draft.routePreferenceIDs = $0 } }
        }
        .onDisappear {
            if let value = model.confirmation { model.coordinator.cancel(value) }
        }
        .sheet(item: $model.confirmation) { value in
            NavigationStack {
                Form {
                    Section {
                        LabeledContent { Text(verbatim: value.payload.name) } label: { Text("profile.edit.name") }
                        LabeledContent { Text(verbatim: value.payload.introduction) } label: { Text("profile.edit.introduction") }
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
