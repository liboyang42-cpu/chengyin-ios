import SwiftUI
import UIKit

@MainActor final class ProjectStoryImageAuthorModel: ObservableObject {
    let original: ProjectStoryImagePresentation.Presentation
    let pickerHost = RetainedImagePickerHost()
    @Published private(set) var revision = 0
    @Published private(set) var preview: UIImage?
    let crop: TemplateImageCropSession
    private let injectedPicker: (any OwnedTopicCoverSelecting)?
    private let applyDraft: (ProjectStoryImagePresentation.Presentation) -> Void
    private lazy var nativePicker = pickerHost.makePicker(selectionApproval: { [weak self] in
        guard let self else { return false }
        return self.flow.isCurrent && self.flow.matchesCapturedDraft && self.original.opening.source.permitsPicker(session: self.original.opening.lease.session)
    })
    private var picker: any OwnedTopicCoverSelecting { injectedPicker ?? nativePicker }
    private var pickerTask: Task<Void, Never>?
    private var pickerID: UUID?
    private var cropPickerID: UUID?
    var flow: ProjectStoryImageFlow { original.flow }
    var canChoose: Bool { flow.canPick && crop.draft == nil && pickerTask == nil }
    init(original: ProjectStoryImagePresentation.Presentation, picker: (any OwnedTopicCoverSelecting)? = nil,
         apply: @escaping (ProjectStoryImagePresentation.Presentation) -> Void) {
        self.original = original; injectedPicker = picker; applyDraft = apply
        crop = .init(isCurrent: { original.flow.isCurrent && original.flow.matchesCapturedDraft })
    }
    func load() { flow.load(); revision += 1 }
    func choose() async {
        guard canChoose, let id = flow.beginPicking() else { return }
        pickerID = id; revision += 1
        let selected = picker
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if self.pickerID == id { self.pickerID = nil; self.pickerTask = nil; self.revision += 1 } }
            do {
                let image = try await selected.select()
                guard self.pickerID == id, !Task.isCancelled, self.flow.isCurrent else { return }
                if let image, self.flow.matchesCapturedDraft {
                    self.crop.stage(image)
                    if self.crop.draft != nil { self.cropPickerID = id }
                    else { self.flow.finishPicking(nil, original: id) }
                } else { self.flow.finishPicking(nil, original: id) }
            } catch { if self.pickerID == id { self.flow.finishPicking(nil, original: id) } }
        }
        pickerTask = task
        await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
    }
    func confirmCrop(_ id: UUID, _ rect: TemplateImageCropRect) {
        guard let pickerID = cropPickerID, let image = crop.confirm(id: id, rect: rect) else { revision += 1; return }
        flow.finishPicking(image, original: pickerID); cropPickerID = nil
        if flow.review?.image.jpeg == image.jpeg { preview = UIImage(data: image.jpeg) }
        revision += 1
    }
    func cancelCrop(_ id: UUID) {
        guard crop.draft?.id == id else { return }
        crop.cancel(id: id)
        if let pickerID = cropPickerID { flow.finishPicking(nil, original: pickerID); cropPickerID = nil }
        revision += 1
    }
    func cancel(_ review: ProjectStoryImageFlow.Review) { flow.cancelReview(review); if flow.review == nil { preview = nil }; revision += 1 }
    func upload(_ review: ProjectStoryImageFlow.Review) {
        guard crop.draft == nil, pickerTask == nil, let claim = flow.claimUpload(review) else { return }
        revision += 1
        Task { [weak self, flow] in await flow.upload(claim); self?.revision += 1 }
    }
    func persistReceipt() { flow.persistReceipt(); revision += 1 }
    func apply() { guard flow.canApply else { return }; applyDraft(original); revision += 1 }
    func close() { pickerTask?.cancel(); pickerTask = nil; pickerID = nil; cropPickerID = nil; picker.cancel(); crop.invalidate(); flow.close(); preview = nil; revision += 1 }
}

/// Reads only the already captured prepared request, in its final serialized story order.
struct ProjectStoryImagePreparedReferences: View {
    let payload: [String: ProjectEditJSON]
    private struct Row: Identifiable { let id: String, reference: String }
    private var rows: [Row] {
        (payload["chapters"]?.array ?? []).enumerated().flatMap { chapter, raw in
            (raw.object?["blocks"]?.array ?? []).enumerated().flatMap { block, raw -> [Row] in
                if raw.object?["type"]?.text == "image", let reference = raw.object?["url"]?.text {
                    return [.init(id: "\(chapter).\(block)", reference: reference)]
                }
                guard raw.object?["type"]?.text == "dream" else { return [] }
                return (raw.object?["images"]?.array ?? []).enumerated().compactMap { index, image in
                    guard let reference = image.object?["url"]?.text else { return nil }
                    return .init(id: "\(chapter).\(block).album.\(index)", reference: reference)
                }
            }
        }
    }
    var body: some View {
        if !rows.isEmpty {
            Section("projectEdit.imageReference") {
                ForEach(rows) { row in
                    Text(verbatim: row.reference).textSelection(.enabled)
                        .accessibilityIdentifier("projectStoryImage.prepared." + row.id)
                }
            }
        }
    }
}

@MainActor struct ProjectStoryImageAuthorView: View {
    let original: ProjectStoryImagePresentation.Presentation
    let close: () -> Void
    @StateObject private var model: ProjectStoryImageAuthorModel
    @Environment(\.locale) private var locale
    init(original: ProjectStoryImagePresentation.Presentation, picker: (any OwnedTopicCoverSelecting)? = nil,
         apply: @escaping (ProjectStoryImagePresentation.Presentation) -> Void, close: @escaping () -> Void) {
        self.original = original; self.close = close
        _model = StateObject(wrappedValue: .init(original: original, picker: picker, apply: apply))
    }
    private func text(_ key: StaticString, _ fallback: String.LocalizationValue) -> String {
        String(localized: LocalizedStringResource(key, defaultValue: fallback, locale: locale))
    }
    var body: some View {
        let flow = original.flow, review = flow.review
        NavigationStack {
            Form {
                Section {
                    if flow.target.isAlbumAppend {
                        Text("projectAlbumImage.uploadScope", tableName: "ProjectAlbumImageAuthor")
                    } else {
                        Text(text("projectStoryImage.scope", "Choose and crop a local story image, then explicitly upload it. Apply the returned reference to this captured chapter and save the local draft. This does not publish or approve the story."))
                    }
                    Text(verbatim: original.opening.chapterName).accessibilityIdentifier("projectStoryImage.chapter")
                    if let saved = original.opening.savedReference {
                        LabeledContent {
                            Text(verbatim: saved).textSelection(.enabled).accessibilityIdentifier("projectStoryImage.savedReference")
                        } label: { Text("projectEdit.imageReference") }
                    }
                    if !flow.matchesCapturedDraft && !flow.alreadyApplied {
                        Text(text("projectStoryImage.changed", "The draft has changed. Save any received receipt, then close and reopen this field before choosing another image."))
                            .accessibilityIdentifier("projectStoryImage.changed")
                    }
                    Button(text("projectStoryImage.choose", "Choose an image")) { Task { await model.choose() } }
                        .buttonStyle(.borderless).disabled(!model.canChoose).accessibilityIdentifier("projectStoryImage.choose")
                    if let draft = model.crop.draft {
                        TemplateImageCropView(draft: draft, confirm: { model.confirmCrop($0, $1) }, cancel: { model.cancelCrop($0) })
                    }
                    if let preview = model.preview {
                        Image(uiImage: preview).resizable().scaledToFit().accessibilityIdentifier("projectStoryImage.localPreview")
                        Text(text("projectStoryImage.previewScope", "Preview of the selected, sanitized image on this device. The uploaded bytes are not fetched through this preview."))
                    }
                    if let review {
                        Text(text("projectStoryImage.notUploaded", "This selection has not been uploaded."))
                            .accessibilityIdentifier("projectStoryImage.notUploaded")
                        Button(text("projectStoryImage.upload", "Upload this story image")) { model.upload(review) }
                            .buttonStyle(.borderless).disabled(!flow.canUpload(review) || model.crop.draft != nil).accessibilityIdentifier("projectStoryImage.upload")
                        Button(text("projectStoryImage.cancelLocal", "Cancel this local selection")) { model.cancel(review) }
                            .buttonStyle(.borderless).disabled(flow.busy).accessibilityIdentifier("projectStoryImage.cancelLocal")
                    }
                }
                if flow.hasUnstoredReceipt {
                    Section {
                        Text(text("projectStoryImage.unstored", "The server returned this reference, but this device could not save its receipt. Save the receipt locally before applying it. This recovery is held only while this app session remains open."))
                        Button(text("projectStoryImage.saveReceipt", "Save the received reference receipt")) { model.persistReceipt() }
                            .buttonStyle(.borderless).disabled(!flow.canPersistReceipt).accessibilityIdentifier("projectStoryImage.saveReceipt")
                    }
                }
                if let receipt = flow.receipt {
                    Section {
                        Text(verbatim: receipt.reference).textSelection(.enabled).accessibilityIdentifier("projectStoryImage.reference")
                        Text(text("projectStoryImage.referenceScope", "This is the existing upload API's reference. It does not prove media ownership, a frozen asset version, or eligibility for an approved release."))
                        if !flow.referenceFitsStory { Text(text("projectStoryImage.referenceTooLong", "The returned reference exceeds the story's existing 500-character limit. Its receipt is retained, but it cannot be applied.")) }
                        Button { model.apply() } label: {
                            if flow.target.isAlbumAppend { Text("projectAlbumImage.append", tableName: "ProjectAlbumImageAuthor") }
                            else { Text(text("projectStoryImage.apply", "Apply to this chapter and save locally")) }
                        }.buttonStyle(.borderless).disabled(!flow.canApply).accessibilityIdentifier("projectStoryImage.apply")
                    }
                }
                if flow.unresolvedUploadCount > 0 && !flow.hasUnstoredReceipt {
                    Text(text("projectStoryImage.unknown", "An upload has no saved response. It may have reached the server. This API has no upload-status check; a new explicit upload creates another attempt."))
                        .accessibilityIdentifier("projectStoryImage.unknown")
                }
                if flow.state == .localSaveFailed {
                    Text(text("projectStoryImage.localFailed", "Local draft or application receipt saving did not complete. The original upload receipt is retained. Retry the local save; no upload will be sent."))
                        .accessibilityIdentifier("projectStoryImage.localFailed")
                }
                if flow.state == .failed { Text(text("projectStoryImage.failed", "The local record could not be verified. Existing story references remain available.")) }
                if flow.state == .unauthorized { Text(text("projectStoryImage.unauthorized", "Sign in again before uploading another story image. The unresolved attempt is retained.")) }
                if flow.state == .uploading { ProgressView().accessibilityIdentifier("projectStoryImage.busy") }
            }
            .navigationTitle(flow.target.isAlbumAppend ? Text("projectAlbumImage.title", tableName: "ProjectAlbumImageAuthor") : Text(text("projectStoryImage.title", "Story image")))
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(text("projectStoryImage.close", "Close")) { model.close(); close() }.accessibilityIdentifier("projectStoryImage.close")
            } }
        }
        .background(RetainedImagePresenterHost(host: model.pickerHost).frame(width: 0, height: 0))
        .onAppear { model.load() }
        .onDisappear { model.close(); close() }
    }
}
