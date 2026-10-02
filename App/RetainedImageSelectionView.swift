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
    private var generation = 0
    init(context: RetainedImageSelectionContext) {
        self.context = context
        context.uploads.changed = { [weak self] in self?.revision += 1 }
    }
    var current: Bool { context.currentScope() == context.scope }
    func select() async {
        guard current, !selecting, !context.uploads.locked else { return }
        selecting = true; failed = false; generation += 1; let stamp = generation
        defer { if stamp == generation { selecting = false } }
        do {
            guard let image = try await context.picker.select() else { return }
            guard stamp == generation, current, !Task.isCancelled else { return }
            context.uploads.prepare(image, scope: context.scope)
        } catch { if stamp == generation, current { failed = true } }
    }
    func leave() { generation += 1; context.picker.cancel(); context.uploads.clear(); selecting = false; revision += 1 }
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
                switch model.context.uploads.state {
                case .reviewing(let review):
                    if let image = UIImage(data: review.selection.jpeg) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240).accessibilityLabel("image.retained.preview")
                    }
                    Text(verbatim: review.scope.realm)
                    Text("\(review.selection.jpeg.count) bytes").font(.caption)
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
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.leave() } }
    }
}
