import SwiftUI

@MainActor final class ProjectStoryAudioAuthorModel: ObservableObject {
    let original: ProjectStoryAudioPresentation.Presentation
    let pickerHost = RetainedImagePickerHost()
    @Published private(set) var revision = 0
    @Published private(set) var selectionFailed = false
    private let injectedPicker: (any ProjectStoryAudioSelecting)?
    private let applyDraft: (ProjectStoryAudioPresentation.Presentation) -> Void
    private lazy var nativePicker = pickerHost.makeStoryAudioPicker(selectionAllowed: { [weak self] in
        guard let self else { return false }
        return self.flow.isCurrent && self.flow.matchesCapturedDraft && self.original.opening.source.permitsPicker(session: self.original.opening.block.lease.session)
    })
    private var picker: any ProjectStoryAudioSelecting { injectedPicker ?? nativePicker }
    private var pickerTask: Task<Void, Never>?
    private var pickerID: UUID?
    var flow: ProjectStoryAudioFlow { original.flow }
    init(original: ProjectStoryAudioPresentation.Presentation, picker: (any ProjectStoryAudioSelecting)? = nil,
         apply: @escaping (ProjectStoryAudioPresentation.Presentation) -> Void) {
        self.original = original; injectedPicker = picker; applyDraft = apply
    }
    func load() { flow.load(); revision += 1 }
    func choose() async {
        guard pickerTask == nil, let id = flow.beginPicking() else { return }
        pickerID = id; selectionFailed = false; revision += 1
        let selected = picker
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if self.pickerID == id { self.pickerID = nil; self.pickerTask = nil; self.revision += 1 } }
            do {
                let audio = try await selected.select()
                guard self.pickerID == id, !Task.isCancelled, self.flow.isCurrent else { return }
                self.flow.finishPicking(audio, original: id)
            } catch {
                guard self.pickerID == id else { return }
                self.flow.finishPicking(nil, original: id); self.selectionFailed = !(error is CancellationError)
            }
        }
        pickerTask = task
        await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
    }
    func cancel(_ original: ProjectStoryAudioFlow.Review) { flow.cancelReview(original); revision += 1 }
    func upload(_ original: ProjectStoryAudioFlow.Review) {
        guard pickerTask == nil, let claim = flow.claimUpload(original) else { return }; revision += 1
        Task { [weak self, flow] in await flow.upload(claim); self?.revision += 1 }
    }
    func persistReceipt() { flow.persistReceipt(); revision += 1 }
    func apply() { guard flow.canApply else { return }; applyDraft(original); revision += 1 }
    func close() { pickerTask?.cancel(); pickerTask = nil; pickerID = nil; picker.cancel(); flow.close(); revision += 1 }
}

@MainActor struct ProjectStoryAudioAuthorView: View {
    let original: ProjectStoryAudioPresentation.Presentation
    let close: () -> Void
    @StateObject private var model: ProjectStoryAudioAuthorModel
    @Environment(\.locale) private var locale
    init(original: ProjectStoryAudioPresentation.Presentation, picker: (any ProjectStoryAudioSelecting)? = nil,
         apply: @escaping (ProjectStoryAudioPresentation.Presentation) -> Void, close: @escaping () -> Void) {
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
                    Text(verbatim: original.opening.chapterName).accessibilityIdentifier("projectStoryAudio.chapter")
                    Text(text("projectStoryAudio.scope", "Choose one mp3, m4a or aac file up to 10 MiB. Selection stays on this device until you explicitly upload it. Cancelling keeps the existing audio block and reference."))
                    Text(verbatim: original.opening.savedReference).textSelection(.enabled).accessibilityIdentifier("projectStoryAudio.savedReference")
                    if let name = original.opening.savedFilename { Text(verbatim: name).accessibilityIdentifier("projectStoryAudio.savedFilename") }
                    Button(text("projectStoryAudio.choose", "Choose an audio file")) { Task { await model.choose() } }
                        .buttonStyle(.borderless).disabled(!flow.canPick).accessibilityIdentifier("projectStoryAudio.choose")
                    if !flow.matchesCapturedDraft && !flow.alreadyApplied {
                        Text(text("projectStoryAudio.changed", "The captured story has changed. Save any received receipt, then close and reopen this audio block before choosing another file."))
                    }
                    if model.selectionFailed { Text(text("projectStoryAudio.selectionFailed", "The selected document could not be read within the supported format and size limits. The original reference is unchanged.")) }
                }
                if let review {
                    Section {
                        Text(verbatim: review.audio.filename).accessibilityIdentifier("projectStoryAudio.filename")
                        LabeledContent(text("projectStoryAudio.bytes", "Selected bytes"), value: String(review.audio.bytes.count))
                            .accessibilityIdentifier("projectStoryAudio.bytes")
                        Text(text("projectStoryAudio.inspection", "Only the filename extension and measured byte count have been checked. Playback and duration have not been verified. This file has not been uploaded."))
                            .accessibilityIdentifier("projectStoryAudio.notUploaded")
                        Button(text("projectStoryAudio.upload", "Upload this audio file")) { model.upload(review) }
                            .buttonStyle(.borderless).disabled(!flow.canUpload(review)).accessibilityIdentifier("projectStoryAudio.upload")
                        Button(text("projectStoryAudio.cancelLocal", "Cancel this local selection")) { model.cancel(review) }
                            .buttonStyle(.borderless).disabled(flow.busy).accessibilityIdentifier("projectStoryAudio.cancelLocal")
                    }
                }
                if flow.hasUnstoredReceipt {
                    Section {
                        Text(text("projectStoryAudio.unstored", "The upload returned a reference, but its receipt could not be saved on this device. Save that receipt before applying it. This recovery copy lasts only for the current app session."))
                        Button(text("projectStoryAudio.saveReceipt", "Save the received audio receipt")) { model.persistReceipt() }
                            .buttonStyle(.borderless).disabled(!flow.canPersistReceipt).accessibilityIdentifier("projectStoryAudio.saveReceipt")
                    }
                }
                if let receipt = flow.receipt {
                    Section {
                        Text(verbatim: receipt.filename).accessibilityIdentifier("projectStoryAudio.uploadedFilename")
                        Text(verbatim: receipt.reference).textSelection(.enabled).accessibilityIdentifier("projectStoryAudio.reference")
                        Text(text("projectStoryAudio.referenceScope", "This is the existing upload API's returned reference. It does not establish playback, media ownership, an immutable asset version, or release approval."))
                        if !flow.referenceFitsStory { Text(text("projectStoryAudio.referenceTooLong", "The returned reference exceeds the existing 500-character story limit. The receipt is retained and cannot be applied.")) }
                        Button(text("projectStoryAudio.apply", "Apply to this audio block and save locally")) { model.apply() }
                            .buttonStyle(.borderless).disabled(!flow.canApply).accessibilityIdentifier("projectStoryAudio.apply")
                    }
                }
                if flow.unresolvedUploadCount > 0 && !flow.hasUnstoredReceipt {
                    Text(text("projectStoryAudio.unknown", "An upload has no saved response and may have reached the server. This API has no upload-status check. A new explicitly selected upload creates another attempt; none is retried automatically."))
                        .accessibilityIdentifier("projectStoryAudio.unknown")
                }
                if flow.state == .localSaveFailed { Text(text("projectStoryAudio.localFailed", "Local saving did not complete. The received reference is retained. Retry applying it locally; no upload will be sent.")) }
                if flow.state == .failed { Text(text("projectStoryAudio.failed", "The local receipt could not be verified. Existing audio references are retained.")) }
                if flow.state == .unauthorized { Text(text("projectStoryAudio.unauthorized", "Sign in again before uploading another audio file. The unresolved attempt is retained.")) }
                if flow.state == .uploading { ProgressView().accessibilityIdentifier("projectStoryAudio.uploading") }
            }
            .navigationTitle(text("projectStoryAudio.title", "Story audio"))
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(text("projectStoryAudio.close", "Close")) { model.close(); close() }.accessibilityIdentifier("projectStoryAudio.close")
            } }
        }
        .background(RetainedImagePresenterHost(host: model.pickerHost).frame(width: 0, height: 0))
        .onAppear { model.load() }
        .onDisappear { model.close(); close() }
    }
}

/// Only references already frozen in the prepared wire payload; no editable draft recomputation.
struct ProjectStoryAudioPreparedReferences: View {
    let payload: [String: ProjectEditJSON]
    private struct Row: Identifiable { let id: String, reference: String }
    private var rows: [Row] {
        (payload["chapters"]?.array ?? []).enumerated().flatMap { chapter, raw in
            (raw.object?["blocks"]?.array ?? []).enumerated().compactMap { block, raw -> Row? in
                guard raw.object?["type"]?.text == "audio", let reference = raw.object?["url"]?.text else { return nil }
                return .init(id: "\(chapter).\(block)", reference: reference)
            }
        }
    }
    var body: some View {
        if !rows.isEmpty {
            Section("projectEdit.audioReference") {
                ForEach(rows) { row in Text(verbatim: row.reference).textSelection(.enabled).accessibilityIdentifier("projectStoryAudio.prepared." + row.id) }
            }
        }
    }
}
