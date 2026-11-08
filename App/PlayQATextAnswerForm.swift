import SwiftUI

/// QA/TYPE form replacing only its truncating shared text binding. All writes
/// remain in PlayKitScreen.prepare -> model.review -> the original action.
@MainActor struct PlayQATextAnswerForm: View {
    @Bindable var model: PlayAdvancedCoordinator
    let enabled: Bool
    let onDirty: () -> Void
    let requestReview: PlayKitReviewRequest
    @State private var input = PlayQATextInput()
    @State private var mounted = false
    @Environment(\.scenePhase) private var scenePhase

    private var currentRevision: String? {
        guard model.isCurrent, !["stale", "disabled"].contains(model.phase), let state = model.state,
              state.playKit["qa"].object != nil,
              (state.playKit["qa"]["mode"].text ?? "TYPE").uppercased() == "TYPE" else { return nil }
        return "\(model.readLifetimeID ?? ""):\(state.sessionID):\(state.nodeID):\(state.version)"
    }
    private var visibleRevision: String? { mounted && scenePhase == .active ? currentRevision : nil }
    private var canEdit: Bool { mounted && scenePhase == .active && enabled && model.canInteract && currentRevision != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("playkit.qa.answer", text: textBinding(), axis: .vertical)
                .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                .disabled(!canEdit).accessibilityIdentifier("playkit.qa.text.input")
            if input.isOverLimit(current: visibleRevision, mountID: input.mountID) {
                Text("qaText.tooLong", tableName: "PlayQATextInput").font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("playkit.qa.text.tooLong")
            }
            Button("playkit.review") {
                guard canEdit, let text = input.reviewInput(current: currentRevision, mountID: input.mountID) else { return }
                requestReview("SUBMIT_QA", ["input": .string(text)], {})
            }.buttonStyle(.borderedProminent)
                .disabled(!canEdit || input.reviewInput(current: visibleRevision, mountID: input.mountID) == nil)
                .accessibilityIdentifier("playkit.submit.qa")
        }.onAppear { mountCurrent() }
            .onChange(of: currentRevision) { _, _ in mountCurrent() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { mountCurrent() }
                else { mounted = false; input.clear() }
            }
            .onDisappear { mounted = false; input.clear() }
    }
    private func textBinding() -> Binding<String> {
        let mount = input.mountID
        return .init(get: { input.text(current: visibleRevision, mountID: mount) }, set: { text in
            guard canEdit else { return }
            let previous = input.text(current: currentRevision, mountID: mount)
            if input.update(text, current: currentRevision, mountID: mount), !previous.utf8.elementsEqual(text.utf8) { onDirty() }
        })
    }
    private func mountCurrent() {
        guard scenePhase == .active, let revision = currentRevision else {
            mounted = false; input.clear(); return
        }
        input.mount(revision: revision); mounted = true
    }
}
