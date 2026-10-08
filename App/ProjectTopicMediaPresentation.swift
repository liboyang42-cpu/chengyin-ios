import SwiftUI
import UIKit

@MainActor extension ProjectEditModel {
    var topicMediaContext: ProjectTopicMediaContext? {
        guard ownsVisit, fullEdit, let session = coordinator.session, let identity = coordinator.identity,
              let snapshot = coordinator.snapshot, let revision = UInt64(exactly: draftMutationRevision),
              let mode = draft.preserved["publishMode"]?.text, captureStarterLease() != nil else { return nil }
        return try? .init(session: session, identity: identity, product: draft.product, owner: draft.owner,
                          publishMode: mode, editScope: snapshot.scope, draftRevision: revision, visit: editorIncarnation)
    }
}

/// One retained editor presentation. Every callback includes its presentation ID;
/// the exact draft revision also fences same-byte replacement and field ABA.
@MainActor final class ProjectTopicMediaPresentation: ObservableObject {
    struct Opening: Identifiable {
        let id = UUID()
        let context: ProjectTopicMediaContext
        let lease: ProjectEditStarterController.Lease
        let field: ProjectTopicImageField
        let policy: ProjectTopicMediaPolicy
        let source: any ProjectTopicImageUploading
        let selection: ProjectTopicMediaSelection
    }
    struct Crop: Identifiable {
        let id = UUID()
        let image: RetainedSelectedImage
        let ticket: ProjectTopicMediaSelection.Ticket
    }
    enum State: Equatable { case idle, picking, cropping, preview, uploading, uploaded, localSaveFailed, failed, unknown }
    @Published private(set) var opening: Opening?
    @Published private(set) var state = State.idle
    @Published private(set) var crop: Crop?
    @Published private(set) var thumbnail: UIImage?
    private(set) var preview: ProjectTopicMediaSelection.Preview?
    private(set) var receipt: ProjectTopicUploadedImage?
    let pickerHost = RetainedImagePickerHost()
    private let editor: ProjectEditModel
    private let injectedPicker: (any ProjectTopicMediaPicking)?
    private var activePicker: (any ProjectTopicMediaPicking)?
    private var task: Task<Void, Never>?
    private var inspector: ProjectTopicMediaInspector?
    private var image: RetainedSelectedImage?
    init(editor: ProjectEditModel, picker: (any ProjectTopicMediaPicking)? = nil) {
        self.editor = editor; injectedPicker = picker
    }
    static func galleryCount(_ raw: String) -> Int {
        raw.split(whereSeparator: { $0 == "," || $0 == ";" }).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }
    func canOpen(_ field: ProjectTopicImageField) -> Bool {
        guard opening == nil, let context = editor.topicMediaContext, context.owner == .personal,
              let source = editor.coordinator.topicImageSource,
              source.isCurrent(context: context, field: field), source.permitsPicker(context: context, field: field),
              source.policy(context: context, field: field) != nil else { return false }
        return field != .gallery || Self.galleryCount(editor.draft.imgArr) < 9
    }
    func open(_ field: ProjectTopicImageField) {
        guard canOpen(field), let context = editor.topicMediaContext, let lease = editor.captureStarterLease(),
              let source = editor.coordinator.topicImageSource, let policy = source.policy(context: context, field: field) else { return }
        opening = .init(context: context, lease: lease, field: field, policy: policy, source: source,
                        selection: .init(context: context, policy: policy))
        state = .idle
    }
    func isCurrent(_ original: Opening) -> Bool {
        guard opening?.id == original.id, original.selection.state != .closed else { return false }
        guard editor.topicMediaContext == original.context,
              editor.isCurrentStarterLease(original.lease), let source = editor.coordinator.topicImageSource,
              ObjectIdentifier(source) == ObjectIdentifier(original.source),
              source.isCurrent(context: original.context, field: original.field),
              source.policy(context: original.context, field: original.field) == original.policy else {
            // Once withdrawal/change is observed, the old visit cannot revive if an
            // identical grant later returns. Cleanup follows through dismissal/sync.
            original.selection.retire(); return false
        }
        return true
    }
    func synchronize() { if let original = opening, !isCurrent(original) { close(original) } }
    func binding(_ original: Opening?) -> Binding<Opening?> {
        .init(get: { guard let original, self.isCurrent(original) else { return nil }; return original },
              set: { next in if next == nil, let original { self.close(original) } })
    }
    func choose(_ original: Opening) {
        guard isCurrent(original), [.idle, .failed].contains(state),
              original.source.permitsPicker(context: original.context, field: original.field),
              let ticket = original.selection.begin(visit: original.selection.visit, context: editor.topicMediaContext, policy: original.policy) else { return }
        let picker = injectedPicker ?? ProjectTopicMediaPicker(host: pickerHost, permitted: { [weak self] in
            self?.isCurrent(original) == true && original.source.permitsPicker(context: original.context, field: original.field)
        })
        activePicker = picker; state = .picking
        task = Task { [weak self] in
            do {
                let selected = try await picker.select()
                guard let self, !Task.isCancelled, self.isCurrent(original), self.state == .picking, original.selection.state == .picking(ticket) else { return }
                self.task = nil; self.activePicker = nil
                guard let selected else { original.selection.cancel(ticket); self.state = .idle; return }
                self.crop = .init(image: selected, ticket: ticket); self.state = .cropping
            } catch {
                guard let self, self.isCurrent(original), self.state == .picking, original.selection.state == .picking(ticket) else { return }
                original.selection.cancel(ticket); self.task = nil; self.activePicker = nil; self.state = .failed
            }
        }
    }
    func confirmCrop(_ candidate: Crop, rect: ProjectTopicImageCropRect, original: Opening) {
        guard isCurrent(original), state == .cropping, crop?.id == candidate.id else { return }
        do {
            let image = try ProjectTopicImageCropRenderer.render(candidate.image, rect: rect, field: original.field)
            let inspector = try ProjectTopicMediaInspector(image: image, context: original.context)
            self.inspector = inspector
            guard let requests = original.selection.prepareInspection([inspector.reference], ticket: candidate.ticket,
                    context: editor.topicMediaContext, policy: original.source.policy(context: original.context, field: original.field)), requests.count == 1 else { throw ProjectTopicMediaFailure.invalidInspection }
            let evidence = try ProjectTopicMediaInspectionEvidence.inspect(requests[0], using: inspector)
            guard let preview = original.selection.finishInspection([evidence], ticket: candidate.ticket,
                    context: editor.topicMediaContext, policy: original.source.policy(context: original.context, field: original.field)),
                  let thumbnail = UIImage(data: image.jpeg) else { throw ProjectTopicMediaFailure.invalidInspection }
            self.image = image; self.preview = preview; self.thumbnail = thumbnail; crop = nil; state = .preview
        } catch {
            original.selection.inspectionFailed(error as? ProjectTopicMediaFailure ?? .invalidInspection, ticket: candidate.ticket)
            original.selection.cancel(candidate.ticket); releaseBytes(); crop = nil; state = .failed
        }
    }
    func cancelSelection(_ original: Opening) {
        guard isCurrent(original), [.picking, .cropping, .preview, .failed].contains(state) else { return }
        // Retire the queued task before picker.cancel() can resume its continuation.
        state = .idle; task?.cancel(); task = nil; activePicker?.cancel(); activePicker = nil
        if let ticket = crop?.ticket ?? preview?.ticket { original.selection.cancel(ticket) }
        else if case .picking(let ticket) = original.selection.state { original.selection.cancel(ticket) }
        releaseBytes(); crop = nil
    }
    func upload(_ original: Opening) {
        guard isCurrent(original), state == .preview, let preview, let image,
              let intent = original.selection.confirm(preview, context: editor.topicMediaContext,
                  policy: original.source.policy(context: original.context, field: original.field)), intent.items == preview.items else { return }
        state = .uploading
        let attemptID = UUID()
        task = Task { [weak self] in
            guard let self, !Task.isCancelled, self.isCurrent(original), self.state == .uploading else { return }
            do {
                // The local intent never goes to the transport and cannot grant server authority.
                let receipt = try await original.source.upload(image, attemptID: attemptID, context: original.context, field: original.field)
                guard !Task.isCancelled, self.isCurrent(original), self.state == .uploading else { return }
                guard receipt.attemptID == attemptID, original.source.permittedURL(receipt, context: original.context, field: original.field) != nil else { throw ProjectTopicImageFailure.invalidResponse }
                self.receipt = receipt; self.task = nil; self.inspector?.remove(); self.inspector = nil; self.state = .uploaded
            } catch {
                guard self.isCurrent(original), self.state == .uploading else { return }
                self.task = nil; self.state = .unknown
                self.inspector?.remove(); self.inspector = nil
            }
        }
    }
    func apply(_ original: Opening) {
        guard isCurrent(original), [.uploaded, .localSaveFailed].contains(state), let receipt,
              let permittedURL = original.source.permittedURL(receipt, context: original.context, field: original.field) else { return }
        var next = editor.draft
        switch original.field {
        case .cover: next.imgUrl = permittedURL
        case .gallery:
            guard Self.galleryCount(next.imgArr) < 9 else { return }
            let appended = next.imgArr.isEmpty ? permittedURL : next.imgArr + "," + permittedURL
            guard appended.utf16.count <= 2000 else { state = .localSaveFailed; return }
            next.imgArr = appended
        }
        guard editor.persistLocalChange(next, lease: original.lease) else { state = .localSaveFailed; return }
        close(original)
    }
    func close(_ original: Opening) {
        guard opening?.id == original.id else { return }
        opening = nil; original.selection.retire(); task?.cancel(); task = nil
        activePicker?.cancel(); activePicker = nil; releaseBytes(); crop = nil; receipt = nil; state = .idle
    }
    func retire() { if let original = opening { close(original) } }
    private func releaseBytes() { inspector?.remove(); inspector = nil; image = nil; preview = nil; thumbnail = nil }
}
