import SwiftUI

@MainActor struct PublishingModePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: ProjectEditProduct
    let confirm: (ProjectEditProduct) -> Void
    init(current: ProjectEditProduct, confirm: @escaping (ProjectEditProduct) -> Void) {
        _selection = State(initialValue: current); self.confirm = confirm
    }
    var body: some View {
        NavigationStack {
            Form {
                Picker("contextPublish.mode.choose", selection: $selection) {
                    Text("projectEdit.city").tag(ProjectEditProduct.city)
                    Text("projectEdit.freeExplore").tag(ProjectEditProduct.freeExplore)
                }.pickerStyle(.inline)
                Text("contextPublish.mode.cityDetail")
                Text("contextPublish.mode.exploreDetail")
            }.navigationTitle("contextPublish.mode.choose")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("contextPublish.mode.use") { confirm(selection) } }
            }
        }
    }
}
@MainActor struct PublishingSubmissionResultSheet: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var lifecycle = ProjectSubmissionResultLifecycle()
    let receipt: PublishingSubmissionHandoff
    let canNavigate: Bool
    var canVerifyRelease = false
    let close: () -> Void
    var body: some View {
        let capture = lifecycle.capture
        result(capture: capture)
            .onAppear { lifecycle.appear(active: scenePhase == .active) }
            .onDisappear { lifecycle.disappear() }
            .onChange(of: scenePhase) { _, phase in lifecycle.sceneChanged(active: phase == .active) }
            .task(id: capture) {
                guard receipt.bundleAcknowledgment == nil, canNavigate, let capture else { return }
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
                guard !Task.isCancelled else { return }
                lifecycle.finish(capture, action: close)
            }
    }
    @ViewBuilder private func result(capture: UUID?) -> some View {
        if let acknowledgment = receipt.bundleAcknowledgment {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("contextPublish.result.acknowledged").font(.title2)
                    Text(verbatim: receipt.title)
                    ProjectSubmissionEvidenceView(acknowledgment: acknowledgment, currentVerificationConfigured: canVerifyRelease)
                    Button("action.done") { if let capture { lifecycle.finish(capture, action: close) } }.buttonStyle(.borderedProminent)
                        .disabled(capture == nil)
                        .accessibilityIdentifier("projectSubmission.done")
                }.padding()
            }.accessibilityIdentifier("projectSubmission.receipt")
                .interactiveDismissDisabled()
        } else { legacyResult(capture: capture) }
    }
    private func legacyResult(capture: UUID?) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle").font(.largeTitle).accessibilityHidden(true)
            Text("contextPublish.result.acknowledged").font(.title2)
            Text(verbatim: receipt.title)
            LabeledContent("contextPublish.result.chapters", value: String(receipt.chapterCount))
            Text("contextPublish.result.readStatus").font(.subheadline)
            if !canNavigate {
                Button("action.done") { if let capture { lifecycle.finish(capture, action: close) } }
                    .disabled(capture == nil)
            }
        }.padding().interactiveDismissDisabled()
    }
}

/// Presentation-only lease. Backgrounding or closing retires old timer/button captures;
/// becoming visible again starts a fresh full delay without changing the request journal.
@MainActor final class ProjectSubmissionResultLifecycle: ObservableObject {
    @Published private(set) var capture: UUID?
    private var visible = false
    private var active = false
    private var finished = false
    func appear(active: Bool) {
        guard !finished else { return }
        if !visible || self.active != active { capture = active ? UUID() : nil }
        visible = true; self.active = active
    }
    func sceneChanged(active: Bool) {
        guard !finished, self.active != active else { return }
        self.active = active; capture = visible && active ? UUID() : nil
    }
    func disappear() { visible = false; active = false; capture = nil }
    func finish(_ original: UUID, action: () -> Void) {
        guard visible, active, !finished, capture == original else { return }
        finished = true; capture = nil; action()
    }
}
