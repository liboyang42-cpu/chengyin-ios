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
    let receipt: PublishingSubmissionHandoff
    let canNavigate: Bool
    var canVerifyRelease = false
    let close: () -> Void
    @State private var finished = false
    @ViewBuilder var body: some View {
        if let acknowledgment = receipt.bundleAcknowledgment {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("contextPublish.result.acknowledged").font(.title2)
                    Text(verbatim: receipt.title)
                    ProjectSubmissionEvidenceView(acknowledgment: acknowledgment, currentVerificationConfigured: canVerifyRelease)
                    Button("action.done") { finish() }.buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("projectSubmission.done")
                }.padding()
            }.accessibilityIdentifier("projectSubmission.receipt")
                .interactiveDismissDisabled()
        } else { legacyResult }
    }
    private var legacyResult: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle").font(.largeTitle).accessibilityHidden(true)
            Text("contextPublish.result.acknowledged").font(.title2)
            Text(verbatim: receipt.title)
            LabeledContent("contextPublish.result.chapters", value: String(receipt.chapterCount))
            Text("contextPublish.result.readStatus").font(.subheadline)
            if !canNavigate { Button("action.done") { finish() } }
        }.padding().interactiveDismissDisabled()
        .task(id: receipt.id) {
            guard canNavigate else { return }
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            guard !Task.isCancelled else { return }; finish()
        }
    }
    private func finish() { guard !finished else { return }; finished = true; close() }
}
