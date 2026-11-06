import SwiftUI
import UIKit

/// Native task/review ownership. Camera capture remains a sheet owned by the runtime host. The existing device coordinator supplies
/// context-bound capture/upload receipts; no URL field can fabricate a photo receipt.
@MainActor struct PlayerTaskEvidenceView: View {
    let target: PlayerTaskEvidenceTarget
    @Bindable var player: PlayPlayerGameCoordinator
    var device: PlayDeviceCaptureCoordinator?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var manualFocused: Bool
    @StateObject private var reviewOwner: PlayerTaskEvidenceReviewController
    private var sameTarget: Bool { reviewOwner.target.id == target.id }
    private var valid: Bool { sameTarget && reviewOwner.canInteract }
    init(target: PlayerTaskEvidenceTarget, player: PlayPlayerGameCoordinator, device: PlayDeviceCaptureCoordinator? = nil) {
        self.target = target; self.player = player; self.device = device
        _reviewOwner = StateObject(wrappedValue: .init(target: target, player: player, device: device))
    }
    var body: some View {
        let opening = sameTarget ? reviewOwner.captureInput() : nil, outputID = device?.outputID
        Group {
            Form {
                Section {
                    Text(target.kind == .scan ? "playerEvidence.scan.detail" : "playerEvidence.photo.detail")
                    Text("playerEvidence.serverAuthority").font(.footnote)
                    if !player.acceptsEvidence(target) { Text("playerEvidence.stale") }
                    if let issue = reviewOwner.issue ?? device?.issue { PlayExperienceIssueView(issue: issue) }
                }
                if target.kind == .scan { scanFields(opening, outputID: outputID) } else { photoFields(opening, outputID: outputID) }
                if sameTarget, let offered = reviewOwner.review {
                    PlayerTaskEvidenceReviewCard(owner: reviewOwner, offered: offered) { clear(); dismiss() }.id(offered.id)
                }
                if reviewOwner.working { ProgressView("playerEvidence.working") }
            }.navigationTitle(target.kind == .scan ? "playerEvidence.scan.title" : "playerEvidence.photo.title")
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("nativeNav.close") { clear(); dismiss() } }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("action.done") { manualFocused = false }.accessibilityIdentifier("playerEvidence.keyboard.done")
                    }
                }
        }.privacySensitive().accessibilityIdentifier("playerEvidence.sheet")
            .background { PlayerTaskEvidenceRoot(owner: reviewOwner).frame(width: 0, height: 0) }
            .onAppear { reviewOwner.appear(active: scenePhase == .active) }
            .onDisappear { reviewOwner.disappear() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { clear(); dismiss() }
                else { reviewOwner.sceneChanged(active: phase == .active) }
            }
            .onChange(of: target.id) { _, _ in clear(); dismiss() }
            .onChange(of: player.hasCurrentProjection) { _, current in if !current { clear() } }
    }
    private func scanFields(_ opening: PlayerTaskEvidenceReviewController.InputTicket?, outputID: UUID?) -> some View {
        Section("playerEvidence.scan.title") {
            Button("playerEvidence.scan.camera") { Task { await reviewOwner.captureDevice(.scan, offered: opening) } }
                .disabled(!valid || device?.supports(.scan) != true || device?.busy == true)
            if device?.supports(.scan) != true { Text("playerEvidence.deviceOff").font(.footnote) }
            if case .scan = device?.output {
                Label("playerEvidence.scan.captured", systemImage: "checkmark.viewfinder")
                Button("playx.review") { reviewOwner.prepareCapturedScan(outputID: outputID, offered: opening) }.disabled(!valid || device?.busy == true)
            }
            TextField("playerEvidence.scan.manual", text: Binding(get: { sameTarget ? reviewOwner.manualText : "" }, set: { reviewOwner.updateManual($0, offered: opening) }), axis: .vertical)
                .textInputAutocapitalization(.never).autocorrectionDisabled().disabled(!valid).focused($manualFocused)
                .accessibilityIdentifier("playerEvidence.manual")
            Text("playerEvidence.scan.manualDetail").font(.footnote)
            Button("playerEvidence.scan.reviewManual") { manualFocused = false; reviewOwner.prepareManual(reviewOwner.manualText, offered: opening) }
                .disabled(!valid || reviewOwner.manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("playerEvidence.manual.review")
        }
    }
    private func photoFields(_ opening: PlayerTaskEvidenceReviewController.InputTicket?, outputID: UUID?) -> some View {
        Section("playerEvidence.photo.title") {
            Button("playerEvidence.photo.capture") { Task { await reviewOwner.captureDevice(.photo, offered: opening) } }
                .disabled(!valid || device?.supports(.photo) != true || device?.busy == true)
            Button("playerEvidence.photo.library") { Task { await reviewOwner.captureDevice(.photo, library: true, offered: opening) } }
                .disabled(!valid || device?.supportsLibraryPhotos != true || device?.busy == true)
            if device?.supports(.photo) != true { Text("playerEvidence.deviceOff").font(.footnote) }
            if valid, case .photo(let bytes, _) = device?.output, let image = UIImage(data: bytes) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240)
                    .accessibilityLabel("playerEvidence.photo.preview")
                Button("playerEvidence.photo.upload") { reviewOwner.prepareUpload(outputID: outputID, offered: opening) }.disabled(!valid || device?.canUpload != true)
            }
            if device?.busy == true { ProgressView("playerEvidence.working") }
            if valid, device?.reviewedPhoto(expectedOutputID: outputID) != nil {
                Label("playerEvidence.photo.uploaded", systemImage: "checkmark.circle")
                Button("playx.review") { reviewOwner.prepareUploadedPhoto(outputID: outputID, offered: opening) }.disabled(!valid)
            }
        }
    }
    private func clear() { manualFocused = false; reviewOwner.retire() }
}
