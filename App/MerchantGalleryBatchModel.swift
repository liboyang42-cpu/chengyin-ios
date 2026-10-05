import Foundation
import Combine

/// Closures are document-owned and weakly capture the document. No access grant is minted here.
@MainActor struct MerchantGalleryBatchBinding {
    let draft: () -> MerchantOperationsDraft?
    let accessFence: () -> UUID?
    let context: () -> RetainedImageSelectionContext?
    let append: (RetainedUploadedImage, RetainedImageScope, MerchantOperationsDraft, MerchantOperationsDraft) -> Bool
}

/// Survives the intentional accessRevision-keyed per-image view replacement. Only durable,
/// proof-checked local consumption permits the next item to acquire a NEW image context.
@MainActor final class MerchantGalleryBatchModel: ObservableObject {
    @Published private(set) var revision = 0
    @Published private(set) var cropDraft: MerchantImageCropDraft?
    @Published private(set) var selecting = false
    @Published private(set) var failed = false
    @Published private(set) var blocked = false
    @Published private(set) var appliedCount = 0
    private(set) var context: RetainedImageSelectionContext?
    private(set) var batchID: UUID?
    private(set) var pending: [RetainedSelectedImage] = []
    private var binding: MerchantGalleryBatchBinding?
    private var expectedDraft: MerchantOperationsDraft?
    private var accessFence: UUID?
    private var itemID: UUID?
    private var reviewSelectionID: UUID?
    private var transitioning = false
    var remainingCount: Int { pending.count + (itemID == nil ? 0 : 1) }
    var active: Bool { batchID != nil }
    var current: Bool {
        guard let binding, let context, let expectedDraft, let accessFence else { return false }
        return binding.draft() == expectedDraft && binding.accessFence() == accessFence
            && context.currentScope() == context.scope
    }
    var canChangeItem: Bool {
        guard active, current, !selecting, !blocked, let context else { return false }
        switch context.uploads.state {
        case .idle, .reviewing, .failed(.rejected): return true
        default: return false
        }
    }
    func select(binding: MerchantGalleryBatchBinding) async {
        guard !selecting, !blocked else { return }
        cancel()
        guard !blocked, case .gallery(let gallery) = binding.draft(),
              let fence = binding.accessFence(), let context = binding.context(),
              context.currentScope() == context.scope, !context.uploads.locked,
              context.picker.enabled, context.uploads.uploader.isConfigured,
              MerchantGalleryBatchLimits.remaining(currentCount: gallery.gallery.count) > 0 else { return }
        let before = MerchantOperationsDraft.gallery(gallery), id = UUID()
        batchID = id; self.binding = binding; expectedDraft = before; accessFence = fence; self.context = context
        selecting = true; failed = false; appliedCount = 0
        defer { if batchID == id { selecting = false; revision += 1 } }
        do {
            let images = try await context.picker.selectBatch(limit: MerchantGalleryBatchLimits.remaining(currentCount: gallery.gallery.count))
            guard batchID == id, current, !Task.isCancelled else { if batchID == id { cancel() }; return }
            guard let images else { cancel(); return }
            install(images, binding: binding, context: context, draft: before, fence: fence, id: id)
        } catch { if batchID == id { cancel(); failed = true } }
    }
    /// Also used by synthetic tests; rejects stale and unbounded selections before retention.
    func install(_ images: [RetainedSelectedImage], binding: MerchantGalleryBatchBinding,
                 context: RetainedImageSelectionContext, draft: MerchantOperationsDraft, fence: UUID, id: UUID = UUID()) {
        guard !blocked, case .gallery(let gallery) = draft, binding.draft() == draft,
              binding.accessFence() == fence, context.currentScope() == context.scope,
              case .merchant(_, .gallery) = context.scope.destination, !context.uploads.locked,
              MerchantGalleryBatchLimits.accepts(images, currentCount: gallery.gallery.count) else { cancel(); failed = true; return }
        batchID = id; self.binding = binding; expectedDraft = draft; accessFence = fence; self.context = context
        pending = images; failed = false; blocked = false; appliedCount = 0
        observe(context); advance()
    }
    private func observe(_ context: RetainedImageSelectionContext) {
        context.uploads.changed = { [weak self, weak uploads = context.uploads] in
            guard let self else { return }
            if !self.transitioning, let uploads, case .unknown = uploads.state { self.stopUnknown() }
            self.revision += 1
        }
    }
    private func advance() {
        guard current, let context, !context.uploads.locked else { cancel(); return }
        cropDraft = nil; itemID = nil; reviewSelectionID = nil
        guard !pending.isEmpty else { batchID = nil; binding = nil; expectedDraft = nil; revision += 1; return }
        let image = pending.removeFirst(); itemID = image.id
        context.uploads.clear(); cropDraft = .init(source: image, aspect: .gallery); revision += 1
    }
    func confirmCrop(id: UUID, rect: MerchantImageCropRect) {
        guard current else { cancel(); return }
        guard canChangeItem, let crop = cropDraft, crop.id == id, crop.source.id == itemID,
              rect.width * 9 == rect.height * 16, let context else { return }
        do {
            let image = try MerchantImageCropRenderer.render(crop.source, rect: rect)
            guard MerchantGalleryBatchLimits.accepts([image] + pending, currentCount: 0) else { failed = true; return }
            cropDraft = nil; reviewSelectionID = image.id
            context.uploads.prepare(image, scope: context.scope)
        } catch { failed = true }
    }
    func confirmUpload(_ review: RetainedImageUploadReview) async {
        guard current else { cancel(); return }
        guard current, active, !selecting, !blocked, let context,
              review.scope == context.scope, review.selection.id == reviewSelectionID else { return }
        await context.uploads.confirm(review)
        guard current else { cancel(); return }
        if case .unknown = context.uploads.state { stopUnknown() }
        revision += 1
    }
    func use(_ image: RetainedUploadedImage) {
        guard current else { cancel(); return }
        guard current, active, !selecting, !blocked, let binding, let before = expectedDraft,
              let oldContext = context, let batch = batchID, image.id == reviewSelectionID,
              image.scope == oldContext.scope,
              let after = try? image.applying(to: before, expectedScope: oldContext.scope) else { return }
        // Keep oldContext strongly held through synchronous cache invalidation. Neither a
        // changed draft nor a newly available context is proof that the journal write succeeded.
        transitioning = true
        let applied = oldContext.uploads.applyLocally(image) { candidate in
            guard self.batchID == batch, self.current, candidate == image else { return false }
            return binding.append(candidate, oldContext.scope, before, after)
        }
        transitioning = false
        guard applied, batchID == batch, binding.draft() == after, binding.accessFence() == accessFence else {
            stopUnknown(); return
        }
        appliedCount += 1; expectedDraft = after
        if pending.isEmpty {
            cropDraft = nil; itemID = nil; reviewSelectionID = nil; batchID = nil
            self.binding = nil; self.expectedDraft = nil; context = nil; revision += 1; return
        }
        // This is the only cross-revision transition. All other scope components stay exact.
        guard let next = binding.context(), next.currentScope() == next.scope, !next.uploads.locked,
              Self.sameOwner(oldContext.scope, next.scope), next.scope.accessRevision != oldContext.scope.accessRevision else {
            cancel(); return
        }
        context = next; observe(next); advance()
    }
    private static func sameOwner(_ lhs: RetainedImageScope, _ rhs: RetainedImageScope) -> Bool {
        lhs.accountID == rhs.accountID && lhs.epoch == rhs.epoch && lhs.realm == rhs.realm
            && lhs.namespace == rhs.namespace && lhs.destination == rhs.destination && lhs.resourceID == rhs.resourceID
            && lhs.accessRevision != nil && rhs.accessRevision != nil
    }
    func skip() {
        guard current else { cancel(); return }
        guard canChangeItem, let context else { return }
        context.uploads.clear(); cropDraft = nil; advance()
    }
    func replace() async {
        guard current else { cancel(); return }
        guard canChangeItem, let context, let batch = batchID else { return }
        selecting = true; failed = false
        defer { if batchID == batch { selecting = false; revision += 1 } }
        do {
            guard let image = try await context.picker.select() else { return }
            guard batchID == batch, current, !Task.isCancelled else { if batchID == batch { cancel() }; return }
            stageReplacement(image, batch: batch)
        } catch { if batchID == batch { failed = true } }
    }
    func stageReplacement(_ image: RetainedSelectedImage, batch: UUID) {
        guard current, batchID == batch, !blocked, let context else { return }
        switch context.uploads.state {
        case .idle, .reviewing, .failed(.rejected): break
        default: return
        }
        guard MerchantGalleryBatchLimits.accepts([image] + pending, currentCount: 0) else { failed = true; return }
        context.uploads.clear(); itemID = image.id; reviewSelectionID = nil
        cropDraft = .init(source: image, aspect: .gallery); revision += 1
    }
    private func stopUnknown() {
        blocked = true; pending = []; cropDraft = nil; itemID = nil; reviewSelectionID = nil
        batchID = nil; selecting = false; binding = nil; expectedDraft = nil; revision += 1
    }
    func cancel() {
        // Cancel drops local bytes only. An acknowledged or in-flight upload remains a
        // durable unresolved target; there is no deletion, retry or fabricated reconciliation.
        if let context {
            switch context.uploads.state { case .uploaded, .uploading, .unknown: blocked = true; default: break }
            context.picker.cancel(); context.uploads.clear()
        }
        pending = []; cropDraft = nil; itemID = nil; reviewSelectionID = nil
        batchID = nil; selecting = false; binding = nil; expectedDraft = nil; revision += 1
    }
}
