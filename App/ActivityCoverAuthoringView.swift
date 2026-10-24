import SwiftUI
import UIKit

/// Retained by each complete activity page, never by a lazy form row.
@MainActor final class ActivityCoverAuthoringOwner: ObservableObject {
    struct Source: Equatable {
        let session: PublishingSession?
        let target: ActivityCoverTarget
        let draft: Data?
        let reference: String
        let editable: Bool
    }
    @Published private(set) var isOpen = false
    @Published private(set) var selecting = false
    @Published private(set) var busy = false
    @Published private(set) var crop: MerchantImageCropDraft?
    @Published private(set) var review: ActivityCoverReview?
    @Published private(set) var receipt: ActivityCoverReceipt?
    @Published private(set) var preview: UIImage?
    @Published private(set) var previewReference: String?
    @Published private(set) var status = "ready"
    @Published private var visible = false
    @Published private var active = false
    private var previewSource: Source?
    private var previewService: ActivityCoverService?
    var visiblePreviewReference: String? {
        guard visible, active, let source = previewSource, source == readCurrent(), let session = source.session,
              let reference = previewReference, previewService?.permitsPreview(reference, session: session) == true else { return nil }
        return reference
    }
    private weak var attachedRoot: ActivityCoverLifetimeController?
    private var coveredByPicker = false
    private var generation = UUID()
    private var original: Source?
    private var readCurrent: () -> Source? = { nil }
    private var applyReference: (String) -> Bool = { _ in false }
    private var makeService: () -> ActivityCoverService? = { nil }
    private var service: ActivityCoverService?
    let pickerHost = RetainedImagePickerHost()
    private let injectedPicker: (any OwnedTopicCoverSelecting)?
    private var picker: (any OwnedTopicCoverSelecting)?
    init(picker: (any OwnedTopicCoverSelecting)? = nil) { injectedPicker = picker }
    private var task: Task<Void, Never>?
    var hasNativeSelection: Bool { selecting }
    var current: Bool { active && (visible || coveredByPicker) && original?.draft != nil && original == readCurrent() }
    var canOpen: Bool { visible && active && !isOpen && readCurrent()?.editable == true }
    var canChoose: Bool {
        guard current, !selecting, !busy, crop == nil, review == nil, receipt == nil, status != "unknown",
              let session = original?.session, let service else { return false }
        return service.permitsPicker(session)
    }
    func bind(read: @escaping () -> Source?, apply: @escaping (String) -> Bool,
              service: @escaping () -> ActivityCoverService?) {
        readCurrent = read; applyReference = apply; makeService = service
    }
    func appear(active: Bool) { visible = true; coveredByPicker = false; self.active = active }
    func setActive(_ value: Bool) { active = value; if !value { retire() } }
    func disappear() { visible = false; active = false; coveredByPicker = false; retire() }
    /// Identity changes invalidate callbacks; only real lifecycle events change visibility.
    func accountChanged() { retire() }
    func attach(_ root: ActivityCoverLifetimeController) { attachedRoot = root }
    func owns(_ root: ActivityCoverLifetimeController) -> Bool { attachedRoot === root }
    @discardableResult func detach(_ root: ActivityCoverLifetimeController) -> Bool {
        guard owns(root) else { return false }; attachedRoot = nil; disappear(); return true
    }
    func parentAppeared() { visible = true; coveredByPicker = false }
    func parentDisappeared(departing: Bool, covered: Bool) {
        if !departing && covered && selecting && active { visible = false; coveredByPicker = true }
        else { disappear() }
    }
    private func retire() {
        generation = UUID(); task?.cancel(); task = nil; picker?.cancel(); picker = nil
        if let review { service?.cancel(review) }
        original = nil; service = nil; review = nil; receipt = nil; crop = nil; preview = nil; previewReference = nil; previewSource = nil; previewService = nil
        selecting = false; busy = false; isOpen = false
    }
    func openAction() -> () -> Void {
        let source = readCurrent(), captured = generation
        return { [weak self] in
            guard let self, self.canOpen, self.generation == captured, let source, source.draft != nil, self.readCurrent() == source else { return }
            self.original = source; self.service = self.makeService(); self.isOpen = true; self.status = "ready"
            if let session = source.session, let service = self.service {
                do { if try service.pending(target: source.target, session: session) != nil { self.status = "unknown" } }
                catch { self.status = "unknown" }
                if self.status != "unknown" && !service.isCurrent(session) { self.status = "unavailable" }
            } else { self.status = "unavailable" }
        }
    }
    func chooseAction() -> () -> Void {
        let captured = generation
        return { [weak self] in
            guard let self, self.generation == captured, self.canChoose else { return }
            Task { await self.choose(expected: captured) }
        }
    }
    private func choose(expected captured: UUID) async {
        guard generation == captured, canChoose else { return }; selecting = true; status = "ready"
        let native = pickerHost.makePicker(selectionApproval: { [weak self] in
            guard let self, self.current, let session = self.original?.session else { return false }
            return self.service?.permitsPicker(session) == true
        }); let picker: any OwnedTopicCoverSelecting = injectedPicker ?? native; self.picker = picker
        defer { if captured == generation { selecting = false; self.picker = nil } }
        do {
            let image = try await picker.select()
            guard captured == generation, current, !Task.isCancelled else { return }
            if let image { crop = .init(source: image, aspect: .gallery) }
        } catch { if captured == generation && current { status = "selectionFailed" } }
    }
    func stageForReview(_ image: RetainedSelectedImage) {
        guard current, !busy, let original, let session = original.session, let service else { return }
        do {
            review = try service.prepare(image, target: original.target, session: session)
            preview = UIImage(data: image.jpeg); crop = nil; status = "review"
        } catch ActivityCoverFailure.locked { status = "unknown" }
        catch { status = "unavailable" }
    }
    func confirmCrop(_ id: UUID, rect: MerchantImageCropRect) {
        guard current, let crop, crop.id == id, rect.width * 9 == rect.height * 16 else { return }
        do { stageForReview(try MerchantImageCropRenderer.render(crop.source, rect: rect)) }
        catch { status = "selectionFailed" }
    }
    func cancelCrop(_ id: UUID) { guard current, crop?.id == id else { return }; crop = nil }
    func uploadAction(_ value: ActivityCoverReview) -> () -> Void {
        let captured = generation
        return { [weak self] in
            guard let self, self.current, self.generation == captured, self.review == value, !self.busy, let service = self.service else { return }
            self.busy = true; self.status = "uploading"
            self.task = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let uploaded = try await service.upload(value, current: { [weak self] in
                        self?.current == true && self?.generation == captured && self?.review == value
                    })
                    guard self.current, self.generation == captured else { return }
                    self.receipt = uploaded; self.review = nil; self.status = "uploaded"
                } catch ActivityCoverFailure.rejected(_) {
                    guard self.current, self.generation == captured else { return }
                    // A retry is a new explicit review after a definite server rejection.
                    self.review = try? service.prepare(value.image, target: value.target, session: value.session)
                    self.status = self.review == nil ? "unknown" : "rejected"
                } catch {
                    guard self.current, self.generation == captured else { return }
                    self.review = nil; self.status = "unknown"
                }
                guard self.generation == captured else { return }; self.busy = false; self.task = nil
            }
        }
    }
    func applyAction(_ value: ActivityCoverReceipt) -> () -> Void {
        let captured = generation
        return { [weak self] in
            guard let self, self.current, self.generation == captured, self.receipt == value, let service = self.service else { return }
            let applied = service.apply(value, current: { self.current && self.generation == captured }, consume: { reference in
                guard self.current else { return false }; return self.applyReference(reference)
            })
            if applied { self.retire() } else { self.status = "unknown" }
        }
    }
    func clearAction() -> () -> Void {
        let captured = generation, source = readCurrent()
        return { [weak self] in
            guard let self, self.visible, self.active, self.generation == captured, !self.isOpen,
                  let source, source.editable, source.draft != nil, self.readCurrent() == source else { return }
            _ = self.applyReference("")
        }
    }
    func previewAction() -> () -> Void {
        let captured = generation, source = readCurrent()
        return { [weak self] in
            guard let self, self.visible, self.active, self.generation == captured, !self.isOpen,
                  let source, source.draft != nil, self.readCurrent() == source, let session = source.session,
                  let service = self.makeService(), service.permitsPreview(source.reference, session: session) else { return }
            self.previewSource = source; self.previewService = service; self.previewReference = source.reference
        }
    }
    func closeAction() -> () -> Void {
        let captured = generation
        return { [weak self] in guard let self, self.generation == captured else { return }; self.close() }
    }
    func close() {
        guard visible && active && !busy else { return }
        if let receipt, let service {
            guard service.discard(receipt, current: { self.active && self.visible && self.readCurrent()?.session == receipt.review.session }) else { status = "unknown"; return }
        }
        retire()
    }
}

@MainActor struct ActivityCoverAuthoringSection: View {
    @ObservedObject var owner: ActivityCoverAuthoringOwner
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("boundary", tableName: "ActivityCoverAuthoring").font(.caption)
            if !owner.isOpen {
                Button(action: owner.openAction()) { label("open") }.disabled(!owner.canOpen)
                    .accessibilityIdentifier("activityCover.open")
                Button(action: owner.previewAction()) { label("preview") }.accessibilityIdentifier("activityCover.preview")
                Button(role: .destructive, action: owner.clearAction()) { label("remove") }.accessibilityIdentifier("activityCover.remove")
                if let reference = owner.visiblePreviewReference { DiscoveryArtwork(source: reference).accessibilityIdentifier("activityCover.remotePreview") }
            } else {
                Text(LocalizedStringKey(owner.current ? owner.status : "changed"), tableName: "ActivityCoverAuthoring")
                    .accessibilityIdentifier("activityCover.status")
                Button(action: owner.chooseAction()) { label("choose") }
                    .disabled(!owner.canChoose).accessibilityIdentifier("activityCover.choose")
                if let crop = owner.crop, owner.current {
                    MerchantImageCropView(draft: crop, confirm: owner.confirmCrop, cancel: { owner.cancelCrop(crop.id) }).id(crop.id)
                }
                if let image = owner.preview, owner.current { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240).accessibilityIdentifier("activityCover.localPreview") }
                if let review = owner.review, owner.current {
                    Button(action: owner.uploadAction(review)) { label(owner.status == "rejected" ? "retry" : "upload") }
                        .disabled(owner.busy).accessibilityIdentifier("activityCover.upload")
                }
                if let receipt = owner.receipt, owner.current {
                    Button(action: owner.applyAction(receipt)) { label("apply") }.accessibilityIdentifier("activityCover.apply")
                }
                Button(action: owner.closeAction()) { label("cancel") }.disabled(owner.busy).accessibilityIdentifier("activityCover.cancel")
            }
        }.buttonStyle(.borderless)
    }
    private func label(_ key: String) -> Text { Text(LocalizedStringKey(key), tableName: "ActivityCoverAuthoring") }
}

@MainActor struct ActivityCoverLifetime: UIViewControllerRepresentable {
    let owner: ActivityCoverAuthoringOwner
    var departure: () -> Void = {}
    func makeUIViewController(context: Context) -> ActivityCoverLifetimeController { .init(owner: owner, departure: departure) }
    func updateUIViewController(_ controller: ActivityCoverLifetimeController, context: Context) { controller.departure = departure }
    static func dismantleUIViewController(_ controller: ActivityCoverLifetimeController, coordinator: ()) { controller.detach() }
}
@MainActor final class ActivityCoverLifetimeController: UIViewController {
    weak var owner: ActivityCoverAuthoringOwner?
    var departure: () -> Void
    private var departing = false
    init(owner: ActivityCoverAuthoringOwner, departure: @escaping () -> Void) { self.owner = owner; self.departure = departure; super.init(nibName: nil, bundle: nil); owner.attach(self) }
    required init?(coder: NSCoder) { return nil }
    private var ancestry: [UIViewController] {
        var result: [UIViewController] = [], next: UIViewController? = self
        while let value = next { result.append(value); next = value.parent }; return result
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); guard owner?.owns(self) == true else { return }; departing = false; owner?.parentAppeared() }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); guard owner?.owns(self) == true else { return }; departing = ancestry.contains { $0.isMovingFromParent || $0.isBeingDismissed } }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard owner?.owns(self) == true else { return }
        let source = ancestry, leaving = departing || parent == nil || ancestry.contains { $0.isMovingFromParent || $0.isBeingDismissed }
        let ownCover = !leaving && source.contains { $0.presentedViewController != nil } && owner?.hasNativeSelection == true
        owner?.parentDisappeared(departing: leaving, covered: ownCover)
        if !ownCover { departure() }
    }
    func detach() { if owner?.detach(self) == true { departure() } }
}
