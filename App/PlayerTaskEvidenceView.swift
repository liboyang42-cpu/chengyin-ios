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
    @State private var manualCode = ""
    @State private var command: PlayPlayerCommand?
    @State private var review = false
    @State private var uploadReview = false
    @State private var issue: PlayExperienceError?
    @State private var submitted = false
    private var valid: Bool { !submitted && player.acceptsEvidence(target) }
    var body: some View {
        Group {
            Form {
                Section {
                    Text(target.kind == .scan ? "playerEvidence.scan.detail" : "playerEvidence.photo.detail")
                    Text("playerEvidence.serverAuthority").font(.footnote)
                    if !valid { Text("playerEvidence.stale") }
                    if let issue = issue ?? device?.issue { PlayExperienceIssueView(issue: issue) }
                }
                if target.kind == .scan { scanFields } else { photoFields }
            }.navigationTitle(target.kind == .scan ? "playerEvidence.scan.title" : "playerEvidence.photo.title")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("nativeNav.close") { clear(); dismiss() } } }
                .confirmationDialog("playx.review", isPresented: $review, titleVisibility: .visible) {
                    Button("playx.submit") {
                        guard valid, let command, player.projection?.allows(command) == true else { issue = .staleSession; return }
                        submitted = true
                        Task { await player.submit(command); clear(); dismiss() }
                    }
                    Button("playx.cancel", role: .cancel) { command = nil }
                } message: { Text("playerEvidence.review.detail") }
                .confirmationDialog("playerEvidence.photo.upload", isPresented: $uploadReview, titleVisibility: .visible) {
                    Button("playerEvidence.photo.upload") { guard valid else { return }; Task { await device?.uploadPhoto() } }
                } message: { Text("playerEvidence.photo.uploadDetail") }
        }.privacySensitive().accessibilityIdentifier("playerEvidence.sheet")
            .onDisappear { clear() }
            .onChange(of: scenePhase) { _, phase in if phase == .background { clear(); dismiss() } }
    }
    private var scanFields: some View {
        Section("playerEvidence.scan.title") {
            Button("playerEvidence.scan.camera") { Task { await device?.capture(.scan) } }
                .disabled(!valid || device?.supports(.scan) != true || device?.busy == true)
            if device?.supports(.scan) != true { Text("playerEvidence.deviceOff").font(.footnote) }
            if case .scan = device?.output {
                Label("playerEvidence.scan.captured", systemImage: "checkmark.viewfinder")
                Button("playx.review") { prepareCapturedScan() }.disabled(!valid || device?.busy == true)
            }
            TextField("playerEvidence.scan.manual", text: $manualCode, axis: .vertical)
                .textInputAutocapitalization(.never).autocorrectionDisabled().disabled(!valid)
                .accessibilityIdentifier("playerEvidence.manual")
            Text("playerEvidence.scan.manualDetail").font(.footnote)
            Button("playerEvidence.scan.reviewManual") { prepare(scan: manualCode) }
                .disabled(!valid || manualCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("playerEvidence.manual.review")
        }
    }
    private var photoFields: some View {
        Section("playerEvidence.photo.title") {
            Button("playerEvidence.photo.capture") { Task { await device?.capture(.photo) } }
                .disabled(!valid || device?.supports(.photo) != true || device?.busy == true)
            Button("playerEvidence.photo.library") { Task { await device?.capture(.photo, usePhotoLibrary: true) } }
                .disabled(!valid || device?.supportsLibraryPhotos != true || device?.busy == true)
            if device?.supports(.photo) != true { Text("playerEvidence.deviceOff").font(.footnote) }
            if valid, case .photo(let bytes, _) = device?.output, let image = UIImage(data: bytes) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240)
                    .accessibilityLabel("playerEvidence.photo.preview")
                Button("playerEvidence.photo.upload") { uploadReview = true }.disabled(!valid || device?.canUpload != true)
            }
            if device?.busy == true { ProgressView("playerEvidence.working") }
            if valid, let photo = device?.reviewedPhoto() {
                Label("playerEvidence.photo.uploaded", systemImage: "checkmark.circle")
                Button("playx.review") { prepare(photo: photo) }.disabled(!valid)
            }
        }
    }
    private func prepareCapturedScan() {
        guard case .scan(let code) = device?.output, device?.busy == false else { return }; prepare(scan: code)
    }
    private func prepare(scan: String? = nil, photo: PlayCompletionEvidence? = nil) {
        do { command = try player.reviewEvidence(target, scan: scan, photo: photo); issue = nil; review = true }
        catch { issue = error as? PlayExperienceError ?? .invalidAction }
    }
    private func clear() { device?.cancel(); manualCode = ""; command = nil; review = false; uploadReview = false }
}
