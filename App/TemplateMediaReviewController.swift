import SwiftUI
import UIKit

@MainActor final class WeakTemplateMediaReviewController {
    weak var value: TemplateMediaReviewController?
    init(_ value: TemplateMediaReviewController) { self.value = value }
}

/// One editor-local media inspection lease. No uploader, URL proof or draft writer.
@MainActor final class TemplateMediaReviewController: ObservableObject {
    struct Row: Identifiable {
        let id: UUID
        let field: TemplateAuthoringMediaField
        let ordinal: Int
        let savedReference: String?
        let target: TemplateAuthoringMediaTargetIdentity
    }
    struct Review: Identifiable, Equatable {
        let id: UUID
        let selection: TemplateAuthoringMediaSelectionIdentity
        let savedReference: String?
        let ordinal: Int
    }
    enum State: String { case awaitingSelection, pending, cropping, ready, failed }
    struct Presentation {
        let review: Review
        let state: State
        let crop: TemplateImageCropDraft?
        let image: RetainedSelectedImage?
        let audio: TemplateAudioDocumentMetadata?
        let canSelectImage: Bool
    }
    private struct Entry {
        let slot: TemplateAuthoringMediaSlot
        let ordinal: Int
        let raw: String?
    }
    let pickerHost = RetainedImagePickerHost()
    private let model: TemplateAuthoringModel
    private weak var story: TemplateStoryEditor?
    private let isStory: Bool
    private let imageSelectionApproved: () -> Bool
    private let fixtureMode: String?
    private var generation: UUID?
    private var owner: TemplateAuthoringMediaOwner?
    private var scope: TemplateAuthoringMediaIdentityScope?
    private var entries: [Entry] = []
    private var storyOrder: [UUID] = []
    private var context = ""
    private var crop: TemplateImageCropSession?
    private var picker: RetainedNativeImagePicker?
    private var task: Task<Void, Never>?
    private var state: State = .awaitingSelection
    private var audio: TemplateAudioDocumentMetadata?
    @Published private(set) var review: Review?
    @Published private(set) var revision = 0

    init(model: TemplateAuthoringModel, story: TemplateStoryEditor? = nil,
         imageSelectionApproved: @escaping () -> Bool = { false }, fixtureMode: String? = nil) {
        self.model = model; self.story = story; isStory = story != nil
        self.imageSelectionApproved = imageSelectionApproved; self.fixtureMode = fixtureMode
        model.mediaReviewControllers.append(.init(self))
    }
    private var currentOwner: TemplateAuthoringMediaOwner? {
        guard model.canReadStoryDraft, let session = model.coordinator.session else { return nil }
        return .init(session: session, draft: model.coordinator.identity)
    }
    private var hasLease: Bool {
        generation != nil && generation == model.mediaReviewGeneration && owner == currentOwner &&
            (!isStory || story?.canRead == true)
    }
    private var editable: Bool { hasLease && model.canEdit && (!isStory || story?.canEdit == true) }
    private var currentContext: String {
        "\(model.draft.validationMethod.rawValue):\(model.draft.finishEnabled):\(model.draft.voiceEnabled):\(model.draft.storyEnabled)"
    }
    private func inventory() -> [(TemplateAuthoringMediaField, Int, String?)]? {
        guard let value = try? TemplateAuthoringMediaReferenceSnapshot(draft: model.draft,
            loadedStoryBeats: isStory ? story?.visibleBeats : nil) else { return nil }
        var rows: [(TemplateAuthoringMediaField, Int, String?)] = []
        for reference in value.references {
            let field = reference.slot.field
            if case .storyBeatImage = field {
                guard isStory else { continue }
            } else if isStory { continue }
            let ordinal = rows.filter { $0.0 == field }.count
            rows.append((field, ordinal, reference.raw))
        }
        if isStory, let story, value.supportsStory {
            for beat in story.visibleBeats where beat.imgs.count < TemplateAuthoringStory.maximumImagesPerBeat {
                rows.append((.storyBeatImage(beatID: beat.id), beat.imgs.count, nil))
            }
        }
        return rows
    }
    private func exact(_ a: String?, _ b: String?) -> Bool { a.map { Data($0.utf8) } == b.map { Data($0.utf8) } }
    private var inventoryIsCurrent: Bool {
        guard hasLease, context == currentContext, storyOrder == (story?.visibleBeats.map(\.id) ?? []),
              let rows = inventory(), rows.count == entries.count else { return false }
        return zip(rows, entries).allSatisfy { row, entry in
            row.0 == entry.slot.field && row.1 == entry.ordinal && exact(row.2, entry.raw)
        }
    }
    private func available(_ field: TemplateAuthoringMediaField) -> Bool {
        switch field {
        case .questionImage, .questionAudio: return model.draft.finishEnabled && [.text, .choice].contains(model.draft.validationMethod)
        case .optionImage, .optionAudio: return model.draft.finishEnabled && model.draft.validationMethod == .choice
        case .narration: return model.draft.voiceEnabled
        case .storyBeatImage: return isStory && model.draft.storyEnabled
        }
    }
    var rows: [Row] {
        guard inventoryIsCurrent, let scope else { return [] }
        return entries.compactMap { entry in
            guard available(entry.slot.field), let target = scope.visibleTargets.first(where: { $0.slot == entry.slot }) else { return nil }
            return .init(id: entry.slot.id, field: entry.slot.field, ordinal: entry.ordinal, savedReference: entry.raw, target: target)
        }
    }
    var canOpen: Bool { editable && inventoryIsCurrent }
    func reload() {
        retire()
        guard let owner = currentOwner, !isStory || story?.canRead == true, let inventory = inventory() else { return }
        self.owner = owner; generation = model.mediaReviewGeneration
        entries = inventory.map { .init(slot: .init(field: $0.0), ordinal: $0.1, raw: $0.2) }
        storyOrder = story?.visibleBeats.map(\.id) ?? []; context = currentContext
        scope = try? .init(owner: owner, slots: entries.map(\.slot), currentOwner: { [weak self] in self?.currentOwner })
        revision += 1
    }
    /// Called synchronously by explicit reference/topology setters, even for an ABA edit.
    func referencesWillChange() {
        dropCandidate()
        try? scope?.topologyDidChange()
        revision += 1
    }
    /// Read-only refresh after a draft edit; stable slots survive beat moves.
    func refresh() {
        guard hasLease, let scope, let inventory = inventory() else { retire(); return }
        let next = inventory.map { row -> Entry in
            if let previous = entries.first(where: { $0.slot.field == row.0 && $0.ordinal == row.1 }) {
                if !exact(previous.raw, row.2) { try? scope.referenceDidChange(slotID: previous.slot.id, reason: row.2 == nil ? .cleared : .replaced) }
                return .init(slot: previous.slot, ordinal: row.1, raw: row.2)
            }
            return .init(slot: .init(field: row.0), ordinal: row.1, raw: row.2)
        }
        if storyOrder != (story?.visibleBeats.map(\.id) ?? []) || context != currentContext { referencesWillChange() }
        try? scope.synchronizeSlots(next.map(\.slot))
        entries = next; storyOrder = story?.visibleBeats.map(\.id) ?? []; context = currentContext
        if let review, !isCurrent(review) { dropCandidate() }
        revision += 1
    }
    func open(_ row: Row) {
        guard canOpen, available(row.field), let scope,
              let current = entries.first(where: { $0.slot.id == row.id }), exact(current.raw, row.savedReference),
              let selection = try? scope.beginSelection(target: row.target) else { return }
        dropCandidate()
        review = .init(id: UUID(), selection: selection, savedReference: row.savedReference, ordinal: row.ordinal)
        state = .awaitingSelection; revision += 1
    }
    func isCurrent(_ value: Review) -> Bool {
        editable && inventoryIsCurrent && review == value && available(value.selection.slot.field) && scope?.isCurrent(value.selection) == true
    }
    /// An old panel may refresh a same-ID reselect token, never acquire a different panel's review.
    func presentation(for originalID: UUID) -> Presentation? {
        guard let value = review, value.id == originalID, isCurrent(value) else { return nil }
        return .init(review: value, state: state, crop: crop?.draft, image: crop?.selection, audio: audio,
                     canSelectImage: Self.isImage(value.selection.slot.field) && imageSelectionApproved() && state != .pending)
    }
    static func isImage(_ field: TemplateAuthoringMediaField) -> Bool {
        switch field { case .questionImage, .optionImage, .storyBeatImage: return true; default: return false }
    }
    @discardableResult func reselect(_ value: Review) -> Review? {
        guard isCurrent(value), let selection = try? scope?.beginSelection(target: value.selection.target) else { return nil }
        dropCandidate()
        let next = Review(id: value.id, selection: selection, savedReference: value.savedReference, ordinal: value.ordinal)
        review = next; state = .awaitingSelection; revision += 1; return next
    }
    func selectImage(_ value: Review) {
        guard isCurrent(value), Self.isImage(value.selection.slot.field), imageSelectionApproved(),
              state != .pending, let next = reselect(value) else { return }
        let picker = pickerHost.makePicker(selectionApproval: { [weak self] in
            self?.isCurrent(next) == true && self?.imageSelectionApproved() == true
        })
        self.picker = picker; state = .pending; revision += 1
        task = Task { [weak self] in
            do {
                let image = try await picker.select()
                guard let self, self.isCurrent(next), !Task.isCancelled else { return }
                if let image { self.stage(image, for: next) }
                else { self.state = .awaitingSelection; self.revision += 1 }
            } catch {
                guard let self, self.isCurrent(next), !Task.isCancelled else { return }
                self.state = .failed; self.revision += 1
            }
        }
    }
    func stage(_ image: RetainedSelectedImage, for value: Review) {
        guard isCurrent(value), Self.isImage(value.selection.slot.field) else { return }
        let session = TemplateImageCropSession(isCurrent: { [weak self] in self?.isCurrent(value) == true })
        session.stage(image); crop = session; audio = nil
        state = session.failed ? .failed : .cropping; revision += 1
    }
    func confirmCrop(_ value: Review, id: UUID, rect: TemplateImageCropRect) {
        guard isCurrent(value), let crop else { return }
        if crop.confirm(id: id, rect: rect) != nil { state = .ready }
        else if crop.failed { state = .failed }
        revision += 1
    }
    func cancelCrop(_ value: Review, id: UUID) {
        guard isCurrent(value), crop?.draft?.id == id else { return }
        crop?.cancel(id: id); state = .awaitingSelection; revision += 1
    }
    func stageAudio(_ metadata: TemplateAudioDocumentMetadata, for value: Review) {
        guard isCurrent(value), !Self.isImage(value.selection.slot.field) else { return }
        crop?.invalidate(); crop = nil; audio = metadata; state = .ready; revision += 1
    }
    func finish(_ value: Review) {
        guard isCurrent(value), scope?.finishSelection(value.selection) == true else { return }
        dropCandidate(); revision += 1 // Refresh captured row targets after consumption.
    }
    func cancel(originalID: UUID) {
        guard let value = review, value.id == originalID else { return }
        if isCurrent(value) { _ = scope?.cancelSelection(value.selection) }
        dropCandidate(); revision += 1
    }
    private func dropCandidate() {
        task?.cancel(); task = nil; picker?.cancel(); picker = nil
        crop?.invalidate(); crop = nil; audio = nil; review = nil; state = .awaitingSelection
    }
    func retire() {
        dropCandidate(); scope?.retire(); scope = nil; owner = nil; generation = nil
        entries = []; storyOrder = []; revision += 1
    }
    #if DEBUG
    var syntheticEnabled: Bool { fixtureMode != nil }
    func beginSynthetic(_ value: Review, held: Bool = false, failed: Bool = false) {
        guard syntheticEnabled, isCurrent(value), let next = reselect(value) else { return }
        state = failed ? .failed : .pending; revision += 1
        if !held && !failed { completeSynthetic(next) }
    }
    func completeSynthetic(_ value: Review) {
        guard syntheticEnabled, isCurrent(value), state == .pending else { return }
        do {
            if Self.isImage(value.selection.slot.field) {
                let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                let image = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 48), format: format).image { context in
                    UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
                    UIColor.green.setFill(); context.fill(CGRect(x: 48, y: 0, width: 48, height: 48))
                }
                guard let data = image.jpegData(compressionQuality: 0.9) else { throw RetainedImageFailure.invalid }
                stage(try RetainedImageSanitizer.sanitize(data), for: value)
            } else {
                var consumed = false
                let metadata = try TemplateAudioDocumentInspection.inspect(fileExtension: "m4a", reportedByteCount: 128) { _ in
                    defer { consumed = true }; return consumed ? Data() : Data(repeating: 0, count: 128)
                }
                stageAudio(metadata, for: value)
            }
        } catch { guard isCurrent(value) else { return }; state = .failed; revision += 1 }
    }
    #endif
}
