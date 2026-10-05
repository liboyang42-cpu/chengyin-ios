import SwiftUI

/// Inspect the source narrative state machine locally. No location, camera, microphone,
/// physical challenge, reward, payment, synchronization, or production gameplay occurs.
@MainActor struct PrefabPreviewView: View {
    let store: PrefabPreviewStore
    let identity: PrefabPreviewIdentity
    let sessionRevision: UInt64
    let currentSession: () -> TemplateAuthoringSession?
    @State private var captured: TemplateAuthoringSession?
    @State private var state = PrefabPreviewState()
    @State private var profile = PrefabPreviewProfile()
    @State private var observation = ""
    @State private var message: String?
    @State private var loaded = false
    var body: some View {
        Form {
            Section {
                QuestifyStatusBadge(title: "templateAuthor.prefab.badge", systemImage: "book.pages")
                Text("templateAuthor.prefab.notice").foregroundStyle(.secondary)
                Text(LocalizedStringKey("templateAuthor.prefab.scene." + state.scene.rawValue)).font(.title2)
            }
            if state.scene == .register {
                Section("templateAuthor.prefab.profile") {
                    TemplateAuthoringField("profileName", text: $profile.name)
                    TemplateAuthoringField("profilePlace", text: $profile.place)
                    TemplateAuthoringField("profileDream", text: $profile.dream)
                    Text("templateAuthor.prefab.profileScope").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("templateAuthor.prefab.state") {
                LabeledContent("templateAuthor.prefab.hp", value: String(state.hp))
                LabeledContent("templateAuthor.prefab.luck", value: String(state.luck))
                LabeledContent("templateAuthor.prefab.dreams", value: String(state.dreams))
                ForEach(state.skills.keys.sorted(), id: \.self) { key in LabeledContent(LocalizedStringKey("templateAuthor.prefab.skill." + key), value: String(state.skills[key] ?? 0)) }
            }
            Section("templateAuthor.prefab.observations") {
                TextField("templateAuthor.prefab.observation", text: $observation, axis: .vertical)
                Button("templateAuthor.prefab.addObservation") { state.observe(where: state.scene.rawValue, text: observation); observation = ""; save() }
                    .disabled(observation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                ForEach(Array(state.observations.enumerated()), id: \.offset) { _, row in Text(verbatim: row.text) }
            }
            Section {
                Button("templateAuthor.prefab.next") {
                    guard canEdit else { return }
                    if state.scene == .register { state.applyProfile(profile) }
                    state.advance(); save()
                }.disabled(state.scene == .flow).accessibilityIdentifier("templateAuthor.prefab.next")
                Button("templateAuthor.saveLocal") { save() }
                if let message { Text(LocalizedStringKey(message)) }
            }
        }.disabled(!canEdit).navigationTitle("templateAuthor.prefab.title")
            .task(id: sessionRevision) { load() }
            .onDisappear { save() }
    }
    private var canEdit: Bool { loaded && captured != nil && captured == currentSession() }
    private func load() {
        state = .init(); profile = .init(); observation = ""; loaded = false; captured = currentSession()
        guard let session = captured else { message = "templateAuthor.signIn"; return }
        do { state = try store.load(identity: identity, session: session) ?? .init(); profile = state.profile; loaded = true }
        catch { message = "templateAuthor.storageFailed" }
    }
    private func save() {
        guard canEdit, let session = captured else { return }
        do { try store.save(state, identity: identity, session: session); message = "templateAuthor.localSaved" }
        catch { message = "templateAuthor.storageFailed" }
    }
}
