import SwiftUI
import PhotosUI
import UIKit

@MainActor struct ClubProfileMediaSection: View {
    @Binding var draft: ClubOperationsDraft
    let snapshot: ClubOperationsSnapshot
    let identity: ClubReadIdentity?
    let service: ClubProfileMediaService?
    @ObservedObject var flow: ClubProfileMediaFlow
    let enabled: Bool
    @State private var showing = false
    var body: some View {
        Section(String(localized: "media.title", table: "ClubProfileMedia")) {
            ForEach(ClubProfileMediaField.allCases, id: \.rawValue) { field in
                Button(field == .logo ? String(localized: "media.selectLogo", table: "ClubProfileMedia") : String(localized: "media.selectCover", table: "ClubProfileMedia")) {
                    guard enabled, let identity, let service else { return }
                    showing = flow.open(field: field, snapshot: snapshot, identity: identity, service: service)
                }.disabled(!enabled || service == nil || flow.state == .uploading)
                    .accessibilityIdentifier("club.profile.media." + field.rawValue)
                if (field == .logo ? draft.logoUpload : draft.coverUpload) != nil {
                    Text(String(localized: "media.staged", table: "ClubProfileMedia"))
                    Button(String(localized: "media.discard", table: "ClubProfileMedia"), role: .destructive) { draft.discardMedia(field, original: snapshot.profile) }.disabled(!enabled)
                }
            }
            if service == nil { Text(String(localized: "media.disabled", table: "ClubProfileMedia")).font(.footnote) }
        }
        .sheet(isPresented: $showing, onDismiss: { flow.closeSelection() }) {
            NavigationStack { ClubProfileMediaEditor(flow: flow, apply: { receipt in
                guard enabled, identity == receipt.scope.identity else { return }
                try? draft.stageMedia(receipt)
            }) }
        }
    }
}

@MainActor private struct ClubProfileMediaEditor: View {
    @ObservedObject var flow: ClubProfileMediaFlow
    let apply: (ClubProfileMediaReceipt) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var item: PhotosPickerItem?
    @State private var crop: MerchantImageCropDraft?
    @State private var camera = false
    @State private var loading = false
    @State private var issue: String?
    @State private var selectionGeneration = UUID()
    private var canSelect: Bool { scenePhase == .active && flow.current && !loading && flow.state != .uploading && flow.state != .unknown && flow.state != .revoked }
    var body: some View {
        Form {
            if let crop {
                MerchantImageCropView(draft: crop, confirm: { id, rect in
                    guard canSelect, crop.id == id, let image = try? MerchantImageCropRenderer.render(crop.source, rect: rect), flow.accepts(image) else { return }
                    self.crop = nil; flow.prepare(image)
                }, cancel: { self.crop = nil })
            } else {
                if let preview = flow.preview, let image = UIImage(data: preview.jpeg) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240)
                    Text(String(localized: "media.uploadHint", table: "ClubProfileMedia"))
                    Button(String(localized: "media.upload", table: "ClubProfileMedia")) { flow.upload(consume: apply) }.disabled(!canSelect)
                } else if let asset = flow.pendingAsset, let scope = flow.scope, let service = flow.service {
                    Text(verbatim: String(format: String(localized: "media.asset", table: "ClubProfileMedia"), String(asset), flow.reviewState ?? String(localized: "media.pending", table: "ClubProfileMedia")))
                    Button(String(localized: "media.readReview", table: "ClubProfileMedia")) { flow.checkReview(retry: false, consume: apply) }
                        .disabled(flow.state == .uploading || !service.permitsReview(scope, retry: false))
                    if ["REJECTED", "UNAVAILABLE"].contains(flow.reviewState ?? "") {
                        Button(String(localized: "media.retryReview", table: "ClubProfileMedia")) { flow.checkReview(retry: true, consume: apply) }
                            .disabled(flow.state == .uploading || !service.permitsReview(scope, retry: true))
                    }
                    Text(String(localized: "media.reviewHint", table: "ClubProfileMedia"))
                } else if let scope = flow.scope, let service = flow.service {
                    PhotosPicker(selection: $item, matching: .images) { Label(String(localized: "media.album", table: "ClubProfileMedia"), systemImage: "photo") }
                        .disabled(!canSelect || !service.permitsAlbum(scope))
                    Button(String(localized: "media.camera", table: "ClubProfileMedia")) { guard canSelect, service.permitsCamera(scope) else { return }; camera = true }
                        .disabled(!canSelect || !service.permitsCamera(scope) || !UIImagePickerController.isSourceTypeAvailable(.camera))
                }
                if loading || flow.state == .uploading { ProgressView() }
                if flow.state == .unknown { Text(String(localized: "media.unknown", table: "ClubProfileMedia")) }
                if flow.state == .revoked { Text(String(localized: "media.revoked", table: "ClubProfileMedia")) }
                if flow.state == .notSent { Text(String(localized: "media.notSent", table: "ClubProfileMedia")) }
                if flow.state == .rejected { Text(String(localized: "media.rejected", table: "ClubProfileMedia")) }
                if flow.state == .uploaded { Text(String(localized: "media.uploaded", table: "ClubProfileMedia")) }
                if let issue { Text(verbatim: issue) }
            }
        }
        .navigationTitle(flow.field == .logo ? String(localized: "media.logo", table: "ClubProfileMedia") : String(localized: "media.cover", table: "ClubProfileMedia"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "media.done", table: "ClubProfileMedia")) { dismiss() }.disabled(flow.state == .uploading) } }
        .interactiveDismissDisabled(flow.state == .uploading)
        .sheet(isPresented: $camera) {
            MerchantEvidenceCameraCapture { bytes in
                camera = false
                guard canSelect, let scope = flow.scope, flow.service?.permitsCamera(scope) == true, let bytes else { return }
                accept(bytes)
            }
        }
        .onChange(of: item) { _, item in
            let stamp = UUID(); selectionGeneration = stamp
            guard canSelect, let item, let scope = flow.scope, flow.service?.permitsAlbum(scope) == true else { return }
            loading = true
            Task {
                defer { if selectionGeneration == stamp { loading = false } }
                let bytes = try? await item.loadTransferable(type: Data.self)
                guard selectionGeneration == stamp, scenePhase == .active, flow.current,
                      flow.service?.permitsAlbum(scope) == true, !Task.isCancelled, let bytes else { return }
                accept(bytes)
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { selectionGeneration = UUID(); crop = nil; item = nil; camera = false; flow.retire(); dismiss() } }
    }
    private func accept(_ bytes: Data) {
        guard flow.current, let field = flow.field, let image = try? RetainedImageSanitizer.sanitize(bytes) else { issue = String(localized: "media.unreadable", table: "ClubProfileMedia"); return }
        // Existing .gallery geometry is exactly 16:9; merchant .cover is 5:3.
        crop = .init(source: image, aspect: field == .logo ? .logo : .gallery); issue = nil
    }
}
/// Removal of the workspace, not presentation of its sheet, ends the upload/save lease.
@MainActor struct ClubProfileMediaOwnerAnchor: UIViewControllerRepresentable {
    let flow: ClubProfileMediaFlow
    final class Coordinator { let flow: ClubProfileMediaFlow; init(_ flow: ClubProfileMediaFlow) { self.flow = flow } }
    func makeCoordinator() -> Coordinator { Coordinator(flow) }
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: UIViewController, coordinator: Coordinator) { coordinator.flow.retire() }
}
