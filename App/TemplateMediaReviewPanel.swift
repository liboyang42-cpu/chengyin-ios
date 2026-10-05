import SwiftUI

@MainActor enum TemplateMediaReviewLabels {
    static func title(_ field: TemplateAuthoringMediaField, ordinal: Int, locale: Locale) -> String {
        switch field {
        case .questionImage: return String(localized: LocalizedStringResource("templateAuthor.field.questionImg", defaultValue: "Question image reference", locale: locale))
        case .questionAudio: return String(localized: LocalizedStringResource("templateAuthor.field.questionAudio", defaultValue: "Question audio reference", locale: locale))
        case .optionImage(let letter): return String(localized: LocalizedStringResource("templateMedia.optionImage", defaultValue: "Choice image", locale: locale)) + " " + letter.rawValue
        case .optionAudio(let letter): return String(localized: LocalizedStringResource("templateMedia.optionAudio", defaultValue: "Choice audio", locale: locale)) + " " + letter.rawValue
        case .narration: return String(localized: LocalizedStringResource("templateAuthor.field.audioUrl", defaultValue: "Narration audio reference", locale: locale))
        case .storyBeatImage: return String(localized: LocalizedStringResource("templateMedia.storyImage", defaultValue: "Story image", locale: locale)) + " \(ordinal + 1)"
        }
    }
    static func identifier(_ field: TemplateAuthoringMediaField, ordinal: Int) -> String {
        switch field {
        case .questionImage: return "questionImage"
        case .questionAudio: return "questionAudio"
        case .optionImage(let letter): return "optionImage." + letter.rawValue
        case .optionAudio(let letter): return "optionAudio." + letter.rawValue
        case .narration: return "narration"
        case .storyBeatImage: return "storyImage.\(ordinal)"
        }
    }
    static func state(_ state: TemplateMediaReviewController.State, locale: Locale) -> String {
        switch state {
        case .awaitingSelection: return String(localized: LocalizedStringResource("templateMedia.awaiting", defaultValue: "No local selection yet.", locale: locale))
        case .pending: return String(localized: LocalizedStringResource("templateMedia.pending", defaultValue: "Local selection is pending. Nothing has been uploaded.", locale: locale))
        case .cropping: return String(localized: LocalizedStringResource("templateMedia.cropping", defaultValue: "Review this local image crop. The source aspect ratio is retained.", locale: locale))
        case .ready: return String(localized: LocalizedStringResource("templateMedia.ready", defaultValue: "Ready for local review only. The saved reference is unchanged.", locale: locale))
        case .failed: return String(localized: LocalizedStringResource("templateMedia.failed", defaultValue: "The local selection could not be inspected. Reselect or cancel.", locale: locale))
        }
    }
}

@MainActor struct TemplateMediaReviewFields: View {
    @Environment(\.locale) private var locale
    @ObservedObject var controller: TemplateMediaReviewController
    var beatID: UUID? = nil
    var accessibilityPrefix = "templateMedia.open"
    private var rows: [TemplateMediaReviewController.Row] {
        controller.rows.filter { row in
            if let beatID { return row.field == .storyBeatImage(beatID: beatID) }
            if case .storyBeatImage = row.field { return false }
            return true
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: LocalizedStringResource("templateMedia.scope", defaultValue: "Review a local image or audio inspection for one field. This does not upload or replace its saved reference.", locale: locale)))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(rows) { row in
                Button { controller.open(row) } label: {
                    Label(TemplateMediaReviewLabels.title(row.field, ordinal: row.ordinal, locale: locale), systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                .disabled(!controller.canOpen)
                .accessibilityIdentifier(accessibilityPrefix + "." + TemplateMediaReviewLabels.identifier(row.field, ordinal: row.ordinal))
            }
        }.buttonStyle(.borderless)
    }
}

/// Attach to a concrete editor Form, not the flattened lazy field collection.
@MainActor struct TemplateMediaReviewPresentation: ViewModifier {
    @ObservedObject var controller: TemplateMediaReviewController
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        let originalID = controller.review?.id
        content.sheet(item: Binding(get: { controller.review }, set: { next in
            if next == nil, let originalID { controller.cancel(originalID: originalID) }
        })) { original in
            NavigationStack { TemplateMediaReviewPanel(controller: controller, original: original) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { controller.retire() } else { controller.reload() }
        }
    }
}

@MainActor struct TemplateMediaReviewPanel: View {
    @Environment(\.locale) private var locale
    @ObservedObject var controller: TemplateMediaReviewController
    let original: TemplateMediaReviewController.Review
    var body: some View {
        Form {
            if let value = controller.presentation(for: original.id) {
                Section {
                    Text(String(localized: LocalizedStringResource("templateMedia.notUploaded", defaultValue: "Local only · Not uploaded", locale: locale)))
                        .accessibilityIdentifier("templateMedia.notUploaded")
                    Text(TemplateMediaReviewLabels.state(value.state, locale: locale)).accessibilityIdentifier("templateMedia.state")
                }
                Section(String(localized: LocalizedStringResource("templateMedia.saved", defaultValue: "Unchanged saved reference", locale: locale))) {
                    if let raw = value.review.savedReference { Text(verbatim: raw).textSelection(.enabled).accessibilityIdentifier("templateMedia.savedReference") }
                    else { Text(String(localized: LocalizedStringResource("templateMedia.empty", defaultValue: "No saved reference.", locale: locale))) }
                }
                Section {
                    if TemplateMediaReviewController.isImage(value.review.selection.slot.field) {
                        Button(String(localized: LocalizedStringResource("templateMedia.selectImage", defaultValue: "Select an image for local review", locale: locale))) {
                            controller.selectImage(value.review)
                        }.disabled(!value.canSelectImage).accessibilityIdentifier("templateMedia.selectImage")
                        if !value.canSelectImage && value.state != .pending {
                            Text(String(localized: LocalizedStringResource("templateMedia.imageUnavailable", defaultValue: "Native image selection is unavailable in this build.", locale: locale)))
                        }
                    } else {
                        Text(String(localized: LocalizedStringResource("templateMedia.audioUnavailable", defaultValue: "Native audio document selection is unavailable here. Inspection is not playable audio or an attachment.", locale: locale)))
                    }
                    if let draft = value.crop {
                        TemplateImageCropView(draft: draft, confirm: { id, rect in
                            controller.confirmCrop(value.review, id: id, rect: rect)
                        }, cancel: { id in controller.cancelCrop(value.review, id: id) })
                    }
                    if let selected = value.image, let image = try? TemplateImageCropRenderer.validatedImage(selected) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240)
                            .accessibilityLabel(String(localized: LocalizedStringResource("templateMedia.localImage", defaultValue: "Reviewed local image, not uploaded", locale: locale)))
                            .accessibilityIdentifier("templateMedia.image")
                    }
                    if let audio = value.audio {
                        Text(String(localized: LocalizedStringResource("templateMedia.audioEvidence", defaultValue: "Extension and byte-count inspection only. The bytes were not decoded or retained as playable audio.", locale: locale)))
                        Text(verbatim: "\(audio.format.rawValue) · \(audio.byteCount)")
                            .accessibilityIdentifier("templateMedia.audioMetadata")
                    }
                }
                Section {
                    Button(String(localized: LocalizedStringResource("templateMedia.reselect", defaultValue: "Discard selection and reselect", locale: locale))) { _ = controller.reselect(value.review) }
                        .accessibilityIdentifier("templateMedia.reselect")
                    Button(String(localized: LocalizedStringResource("templateMedia.applyUnavailable", defaultValue: "Apply unavailable: no uploaded reference", locale: locale))) {}
                        .disabled(true).accessibilityIdentifier("templateMedia.apply")
                    Button(String(localized: LocalizedStringResource("templateMedia.finish", defaultValue: "Finish review without changing the reference", locale: locale))) { controller.finish(value.review) }
                        .accessibilityIdentifier("templateMedia.finish")
                }
                #if DEBUG
                if controller.syntheticEnabled {
                    Section(String(localized: LocalizedStringResource("templateMedia.testOnly", defaultValue: "Test-only generated data · No files or network", locale: locale))) {
                        Button(String(localized: LocalizedStringResource("templateMedia.testReady", defaultValue: "Generate test selection", locale: locale))) { controller.beginSynthetic(value.review) }
                            .accessibilityIdentifier("templateMedia.synthetic.ready")
                        Button(String(localized: LocalizedStringResource("templateMedia.testHeld", defaultValue: "Hold test selection pending", locale: locale))) { controller.beginSynthetic(value.review, held: true) }
                            .accessibilityIdentifier("templateMedia.synthetic.held")
                        Button(String(localized: LocalizedStringResource("templateMedia.testFailed", defaultValue: "Show test inspection failure", locale: locale))) { controller.beginSynthetic(value.review, failed: true) }
                            .accessibilityIdentifier("templateMedia.synthetic.failed")
                        if value.state == .pending {
                            Button(String(localized: LocalizedStringResource("templateMedia.testComplete", defaultValue: "Complete pending test selection", locale: locale))) { controller.completeSynthetic(value.review) }
                                .accessibilityIdentifier("templateMedia.synthetic.complete")
                        }
                    }
                }
                #endif
            } else {
                Text(String(localized: LocalizedStringResource("templateMedia.stale", defaultValue: "This local review is no longer current. Return to the editor and open the field again.", locale: locale)))
                    .accessibilityIdentifier("templateMedia.stale")
            }
        }
        .buttonStyle(.borderless)
        .navigationTitle(TemplateMediaReviewLabels.title(original.selection.slot.field, ordinal: original.ordinal, locale: locale))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: LocalizedStringResource("templateMedia.cancel", defaultValue: "Cancel local review", locale: locale))) { controller.cancel(originalID: original.id) }
                    .accessibilityIdentifier("templateMedia.cancel")
            }
        }
        .background(RetainedImagePresenterHost(host: controller.pickerHost).frame(width: 0, height: 0))
    }
}
