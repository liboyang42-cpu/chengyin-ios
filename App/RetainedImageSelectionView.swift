import SwiftUI
import UIKit

@MainActor struct RetainedImageSelectionContext {
    let scope: RetainedImageScope
    let currentScope: () -> RetainedImageScope?
    let picker: RetainedNativeImagePicker
    let uploads: RetainedImageUploadCoordinator
}
@MainActor final class RetainedImageSelectionModel: ObservableObject {
    let context: RetainedImageSelectionContext
    @Published private(set) var revision = 0
    @Published private(set) var selecting = false
    @Published private(set) var failed = false
    @Published private(set) var cropDraft: MerchantImageCropDraft?
    private var generation = 0
    init(context: RetainedImageSelectionContext) {
        self.context = context
        context.uploads.changed = { [weak self] in self?.revision += 1 }
    }
    var current: Bool { context.currentScope() == context.scope }
    func select() async {
        guard current, !selecting, !context.uploads.locked else { return }
        selecting = true; failed = false; cropDraft = nil
        if MerchantImageCropAspect.forDestination(context.scope.destination) != nil { context.uploads.clear() }
        generation += 1; let stamp = generation
        defer { if stamp == generation { selecting = false } }
        do {
            guard let image = try await context.picker.select() else { return }
            guard stamp == generation, current, !Task.isCancelled else { return }
            stage(image)
        } catch { if stamp == generation, current { failed = true } }
    }
    func stage(_ image: RetainedSelectedImage) {
        guard current, !context.uploads.locked else { return }
        if let aspect = MerchantImageCropAspect.forDestination(context.scope.destination) {
            context.uploads.clear(); cropDraft = nil
            cropDraft = .init(source: image, aspect: aspect)
        } else { context.uploads.prepare(image, scope: context.scope) }
    }
    func confirmCrop(id: UUID, rect: MerchantImageCropRect) {
        guard current, !context.uploads.locked, let draft = cropDraft, draft.id == id,
              rect.width * draft.aspect.heightUnits == rect.height * draft.aspect.widthUnits else { return }
        do {
            let cropped = try MerchantImageCropRenderer.render(draft.source, rect: rect)
            cropDraft = nil; context.uploads.prepare(cropped, scope: context.scope)
        } catch { failed = true }
    }
    func cancelCrop() { cropDraft = nil; failed = false }
    func leave() { generation += 1; cropDraft = nil; context.picker.cancel(); context.uploads.clear(); selecting = false; revision += 1 }
}
/// Selection, transmission review and applying the uploaded result are separate user actions.
@MainActor struct RetainedImageSelectionView: View {
    @StateObject private var model: RetainedImageSelectionModel
    let apply: (RetainedUploadedImage) -> Bool
    @Environment(\.scenePhase) private var scenePhase
    init(context: RetainedImageSelectionContext, apply: @escaping (RetainedUploadedImage) -> Bool) {
        _model = StateObject(wrappedValue: .init(context: context)); self.apply = apply
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("image.retained.boundary").font(.footnote)
            Button("image.retained.select") { Task { await model.select() } }
                .disabled(!model.current || !model.context.picker.enabled || !model.context.uploads.uploader.isConfigured || model.selecting || model.context.uploads.locked)
                .accessibilityIdentifier("image.retained.select")
            if model.selecting { ProgressView("image.retained.loading") }
            if model.current {
                if let draft = model.cropDraft {
                    MerchantImageCropView(draft: draft, confirm: model.confirmCrop, cancel: model.cancelCrop).id(draft.id)
                }
                switch model.context.uploads.state {
                case .reviewing(let review):
                    if let image = UIImage(data: review.selection.jpeg) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240).accessibilityLabel("image.retained.preview")
                    }
                    Text(verbatim: review.scope.realm)
                    Text("image.retained.byteCount \(review.selection.jpeg.count)").font(.caption)
                        .accessibilityIdentifier("image.retained.byteCount")
                    Button("image.retained.confirmUpload") { Task { await model.context.uploads.confirm(review) } }
                        .accessibilityIdentifier("image.retained.confirmUpload")
                    Button("image.retained.cancel", role: .cancel) { model.context.uploads.clear() }
                case .uploading: ProgressView("image.retained.loading")
                case .uploaded(let image):
                    Text("image.retained.uploaded")
                    Button("image.retained.use") {
                        guard model.current, image.scope == model.context.scope else { return }
                        model.context.uploads.applyLocally(image, consume: apply)
                    }.accessibilityIdentifier("image.retained.use")
                case .unknown: Text("image.retained.unknown").accessibilityIdentifier("image.retained.unknown")
                case .failed(let failure):
                    Text("image.retained.failed")
                    if case .rejected(_, let message) = failure, let message { Text(verbatim: message) }
                case .idle: EmptyView()
                }
            } else { Text("image.retained.changed") }
            if model.failed { Text("image.retained.failed") }
        }
        // In a Form/List row, these are distinct selection/upload/use/cancel actions.
        .buttonStyle(.borderless)
        .onDisappear { model.leave() }
        .onChange(of: model.current) { _, current in if !current { model.leave() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.leave() } }
    }
}
