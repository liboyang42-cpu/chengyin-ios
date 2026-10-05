import SwiftUI
import UIKit

@MainActor struct MerchantGalleryBatchView: View {
    @ObservedObject var batch: MerchantGalleryBatchModel
    let binding: MerchantGalleryBatchBinding
    let available: Bool
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("image.retained.boundary").font(.footnote)
            Text("image.galleryBatch.boundary").font(.footnote)
            Button("image.galleryBatch.select") { Task { await batch.select(binding: binding) } }
                .disabled(!available || batch.selecting || batch.blocked || batch.active)
                .accessibilityIdentifier("image.galleryBatch.select")
            if batch.selecting { ProgressView("image.retained.loading") }
            if batch.active && batch.current {
                Text("image.galleryBatch.remaining \(batch.remainingCount)").font(.caption)
                if let draft = batch.cropDraft {
                    MerchantImageCropView(draft: draft, confirm: batch.confirmCrop, cancel: batch.skip).id(draft.id)
                }
                if let context = batch.context {
                    switch context.uploads.state {
                    case .reviewing(let review):
                        if let image = UIImage(data: review.selection.jpeg) {
                            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240).accessibilityLabel("image.retained.preview")
                        }
                        Text(verbatim: review.scope.realm)
                        Text("image.retained.byteCount \(review.selection.jpeg.count)").font(.caption)
                        .accessibilityIdentifier("image.retained.byteCount")
                        Button("image.retained.confirmUpload") { Task { await batch.confirmUpload(review) } }
                            .disabled(!batch.current || batch.selecting)
                            .accessibilityIdentifier("image.galleryBatch.confirmUpload")
                    case .uploading: ProgressView("image.retained.loading")
                    case .uploaded(let image):
                        Text("image.retained.uploaded")
                        Button("image.retained.use") { batch.use(image) }.disabled(!batch.current)
                            .accessibilityIdentifier("image.galleryBatch.use")
                    case .failed: Text("image.retained.failed")
                    case .unknown: Text("image.retained.unknown")
                    case .idle: EmptyView()
                    }
                }
                if batch.canChangeItem {
                    Button("image.galleryBatch.skip") { batch.skip() }
                        .accessibilityIdentifier("image.galleryBatch.skip")
                    Button("image.galleryBatch.replace") { Task { await batch.replace() } }
                        .accessibilityIdentifier("image.galleryBatch.replace")
                }
                Button("image.galleryBatch.cancelAll", role: .cancel) { batch.cancel() }
                    .accessibilityIdentifier("image.galleryBatch.cancelAll")
            }
            if batch.appliedCount > 0 { Text("image.galleryBatch.applied \(batch.appliedCount)").font(.caption) }
            if batch.blocked { Text("image.galleryBatch.blocked").accessibilityIdentifier("image.galleryBatch.blocked") }
            if batch.failed { Text("image.retained.failed") }
        }
        .buttonStyle(.borderless)
        .onDisappear { batch.cancel() }
        .onChange(of: batch.current) { _, value in if batch.active && !value { batch.cancel() } }
        .onChange(of: scenePhase) { _, value in if value != .active { batch.cancel() } }
    }
}
