import SwiftUI

@MainActor
final class ProfileEditModel: ObservableObject {
    let coordinator: ProfileEditCoordinator
    @Published var draft = ProfileEditDraft()
    @Published var confirmation: ProfileEditConfirmation?
    @Published private(set) var busy = false
    @Published private(set) var revision = 0
    private var generation = 0
    init(coordinator: ProfileEditCoordinator) { self.coordinator = coordinator }
    func resetAndLoad() async {
        generation += 1; draft = .init(); confirmation = nil; busy = false
        coordinator.synchronizeSession()
        await load()
    }
    func load() async {
        let request = generation; busy = true
        await coordinator.load()
        guard request == generation else { return }
        if let snapshot = coordinator.snapshot { draft = snapshot.draft }
        busy = false; revision += 1
    }
    func prepare() async {
        let request = generation; busy = true
        await coordinator.prepare(draft)
        guard request == generation else { return }
        confirmation = coordinator.confirmation; busy = false; revision += 1
        if coordinator.messageKey == "profile.edit.changed", let snapshot = coordinator.snapshot { draft = snapshot.draft }
    }
    func save(_ value: ProfileEditConfirmation) async {
        let request = generation; confirmation = nil; busy = true
        await coordinator.save(value)
        guard request == generation else { return }
        if coordinator.messageKey == "profile.edit.saved" || coordinator.messageKey == "profile.edit.changed",
           let snapshot = coordinator.snapshot { draft = snapshot.draft }
        busy = false; revision += 1
    }
}

/// Parent passes its live session revision and retains the coordinator outside navigation.
struct ProfileEditView: View {
    @StateObject private var model: ProfileEditModel
    let sessionRevision: UInt64
    init(coordinator: ProfileEditCoordinator, sessionRevision: UInt64) {
        _model = StateObject(wrappedValue: ProfileEditModel(coordinator: coordinator))
        self.sessionRevision = sessionRevision
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
                            .textContentType(.nickname).accessibilityIdentifier("profile.edit.name")
                        TextField("profile.edit.introduction", text: $model.draft.introduction, axis: .vertical)
                            .lineLimit(3...8).accessibilityIdentifier("profile.edit.introduction")
                    } header: { Text("profile.edit.details") }
                        .disabled(model.busy || model.coordinator.isLocked)
                    Section { Text("profile.edit.scope").foregroundStyle(.secondary) }
                    Button { Task { await model.prepare() } } label: { Text("profile.edit.review") }
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
        .navigationTitle(Text("profile.edit.title"))
        .task(id: sessionRevision) { await model.resetAndLoad() }
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
                }.navigationTitle(Text("profile.edit.reviewTitle"))
            }.interactiveDismissDisabled(model.busy)
        }
    }
}
