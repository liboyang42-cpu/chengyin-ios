import SwiftUI

@MainActor final class MerchantNPCVoiceSamplesModel: ObservableObject {
    let coordinator: MerchantNPCVoiceSamplesCoordinator
    @Published var revision = 0
    init(_ coordinator: MerchantNPCVoiceSamplesCoordinator) { self.coordinator = coordinator; coordinator.onChange = { [weak self] in self?.revision += 1 } }
}
@MainActor struct MerchantNPCVoiceSamplesView: View {
    @StateObject private var model: MerchantNPCVoiceSamplesModel
    @State private var ownsVoice = false
    @State private var consent = false
    @Environment(\.scenePhase) private var scenePhase
    init(coordinator: MerchantNPCVoiceSamplesCoordinator) { _model = StateObject(wrappedValue: .init(coordinator)) }
    var body: some View {
        Section("merchantVoice.title") {
            Text("merchantVoice.disclosure")
            if model.coordinator.configuration == nil { Text("merchantVoice.configurationRequired") }
            Toggle("merchantNPC.ownsVoice", isOn: $ownsVoice).disabled(model.coordinator.busy).accessibilityIdentifier("merchantVoice.ownsVoice")
            Toggle("merchantVoice.consent", isOn: $consent).disabled(model.coordinator.busy).accessibilityIdentifier("merchantVoice.consent")
            if let script = model.coordinator.resources.script, script.isUsable {
                ForEach(0..<5, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 12) {
                        if index == 0 { Label("merchantNPC.authorizationFirst", systemImage: "checkmark.shield") }
                        Text(verbatim: "\(index + 1). \(script.script[index])").textSelection(.enabled)
                        Text(model.coordinator.clips[index] == nil ? "merchantNPC.sampleMissing" : "merchantNPC.sampleReady")
                        HStack {
                            Button(model.coordinator.recording == index ? "merchantVoice.stop" : "merchantVoice.record") {
                                if model.coordinator.recording == index { model.coordinator.finish() }
                                else { Task { await model.coordinator.record(index) } }
                            }.disabled(!model.coordinator.ready || (model.coordinator.recording != nil && model.coordinator.recording != index) || !model.coordinator.uploaded.isEmpty)
                                .accessibilityIdentifier("merchantVoice.record.\(index)")
                            Button("merchantVoice.play") { model.coordinator.play(index) }
                                .disabled(!model.coordinator.ready || model.coordinator.recording != nil || model.coordinator.clips[index] == nil)
                                .accessibilityIdentifier("merchantVoice.play.\(index)")
                        }.buttonStyle(.bordered)
                    }.accessibilityElement(children: .contain)
                }
            }
            Button("merchantVoice.stopPlayback") { model.coordinator.stopPlayback() }.disabled(model.coordinator.recording != nil || model.coordinator.busy)
            Button("merchantVoice.reviewUpload") { model.coordinator.prepareUpload() }
                .disabled(!model.coordinator.ready || model.coordinator.recording != nil || model.coordinator.clips.count != 5 || model.coordinator.uploaded.count == 5)
                .accessibilityIdentifier("merchantVoice.reviewUpload")
            if let review = model.coordinator.review {
                Text("merchantVoice.uploadWarning")
                Text(verbatim: "\(review.index + 1) / 5 · \(review.byteCount) bytes · \(review.duration) s")
                Text(verbatim: review.destination).textSelection(.enabled)
                Button("merchantVoice.confirmUpload") { Task { await model.coordinator.confirmUpload(review.id) } }
                    .accessibilityIdentifier("merchantVoice.confirmUpload")
                Button("merchantNPC.cancel") { model.coordinator.discardReview() }
            }
            Button("merchantNPC.reviewEnroll") { model.coordinator.prepareEnrollment() }
                .disabled(!model.coordinator.ready || model.coordinator.uploaded.count != 5)
                .accessibilityIdentifier("merchantVoice.reviewEnroll")
            if model.coordinator.busy { ProgressView("merchantNPC.pending") }
            if model.coordinator.unresolved { Text("merchantVoice.unknown").accessibilityIdentifier("merchantVoice.unknown") }
            MerchantNPCIssue(failure: model.coordinator.failure)
        }
        .onChange(of: ownsVoice) { _, _ in model.coordinator.attest(ownsVoice: ownsVoice, consent: consent) }
        .onChange(of: consent) { _, _ in model.coordinator.attest(ownsVoice: ownsVoice, consent: consent) }
        .onDisappear { model.coordinator.invalidate() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.coordinator.invalidate(); ownsVoice = false; consent = false } }
        .privacySensitive()
    }
}
