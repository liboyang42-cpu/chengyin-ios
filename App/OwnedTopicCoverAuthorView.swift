import SwiftUI
import UIKit

@MainActor protocol OwnedTopicCoverSelecting: AnyObject {
    func select() async throws -> RetainedSelectedImage?
    func cancel()
}
extension RetainedNativeImagePicker: OwnedTopicCoverSelecting {}

@MainActor final class OwnedTopicCoverAuthorModel: ObservableObject {
    let original: OwnedTopicCoverAuthorPresentation.Presentation
    let pickerHost = RetainedImagePickerHost()
    @Published private(set) var revision = 0
    @Published private(set) var image: UIImage?
    @Published private(set) var renderedAsset: OwnedTopicCoverAsset?
    private let selected: (OwnedTopicCoverAuthorPresentation.Presentation) -> Void
    private let injectedPicker: (any OwnedTopicCoverSelecting)?
    private lazy var nativePicker = pickerHost.makePicker(selectionApproval: { [weak self] in
        guard let self else { return false }
        return self.original.flow.isCurrent && self.original.opening.source.permitsNativePicker(session:self.original.opening.session)
    })
    private var picker: any OwnedTopicCoverSelecting { injectedPicker ?? nativePicker }
    private var pickerTask: Task<Void,Never>?
    private var pickerID: UUID?
    var flow: OwnedTopicCoverAuthorFlow { original.flow }
    init(original: OwnedTopicCoverAuthorPresentation.Presentation, picker: (any OwnedTopicCoverSelecting)? = nil,
         selected: @escaping (OwnedTopicCoverAuthorPresentation.Presentation) -> Void) {
        self.original = original; injectedPicker = picker; self.selected = selected
    }
    func load() async { await flow.load(); revision += 1 }
    func loadCurrentDetails() async { guard flow.canReadCurrentDetails else { return }; await load() }
    func choose() async {
        guard pickerTask == nil, let id = flow.beginPicking() else { return }; pickerID = id; revision += 1
        let selectedPicker = picker
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if self.pickerID == id { self.pickerTask = nil; self.pickerID = nil; self.revision += 1 } }
            do {
                let picked = try await selectedPicker.select()
                guard self.pickerID == id, !Task.isCancelled, self.flow.isCurrent else { return }
                self.flow.finishPicking(picked,original:id); self.image = nil; self.renderedAsset = nil
            } catch { guard self.pickerID == id else { return }; self.flow.finishPicking(nil,original:id) }
        }
        pickerTask = task
        await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
    }
    func cancelPicked(_ original: OwnedTopicCoverAuthorFlow.Review) { flow.cancelPicked(original); revision += 1 }
    func upload(_ original: OwnedTopicCoverAuthorFlow.Review) {
        guard pickerTask == nil, let claim = flow.claimUpload(original) else { return }; image = nil; renderedAsset = nil; revision += 1
        Task { [weak self,flow] in await flow.upload(claim); self?.revision += 1 }
    }
    func persistReceipt() { flow.persistUploadReceipt(); revision += 1 }
    func persistSelectionReceipt() { flow.persistSelectionReceipt(); revision += 1; finishIfSelected() }
    func read(_ asset: OwnedTopicCoverAsset) async {
        image = nil; renderedAsset = nil; revision += 1; await flow.readImage(asset)
        guard flow.isCurrent, flow.checkedAsset == asset, let bytes = flow.checkedImage else { revision += 1; return }
        if let safe = try? RetainedImageSanitizer.sanitize(bytes), let decoded = UIImage(data:safe.jpeg), flow.isCurrent {
            image = decoded; renderedAsset = asset
        }
        revision += 1
    }
    func review(_ asset: OwnedTopicCoverAsset) {
        guard image != nil, renderedAsset == asset else { return }; _ = flow.reviewSelection(asset); revision += 1
    }
    func cancel(_ original: OwnedTopicCoverAuthorFlow.SelectionReview) { flow.cancelSelection(original); revision += 1 }
    func confirm(_ review: OwnedTopicCoverAuthorFlow.SelectionReview) {
        guard image != nil, renderedAsset == review.command.asset, let claim = flow.claimSelection(review) else { return }; revision += 1
        Task { [weak self,flow] in await flow.select(claim); self?.revision += 1; self?.finishIfSelected() }
    }
    private func finishIfSelected() { if case .selected = flow.state { selected(original) } }
    func check(_ snapshot: OwnedTopicCoverJournal.Snapshot) {
        guard !flow.isBusy, !flow.hasUnstoredReceipt else { return }; revision += 1
        Task { [weak self,flow] in await flow.checkSelection(snapshot); self?.revision += 1; self?.finishIfSelected() }
    }
    func retry(_ snapshot: OwnedTopicCoverJournal.Snapshot) {
        guard !flow.isBusy, !flow.hasUnstoredReceipt else { return }; revision += 1
        Task { [weak self,flow] in await flow.retrySelection(snapshot); self?.revision += 1; self?.finishIfSelected() }
    }
    func binding(_ original: OwnedTopicCoverAuthorFlow.SelectionReview?) -> Binding<OwnedTopicCoverAuthorFlow.SelectionReview?> {
        .init(get:{ guard let original,self.flow.isCurrent,self.flow.selectionReview?.id == original.id else { return nil };return original },set:{ next in
            guard next == nil,let original else { return };self.cancel(original)
        })
    }
    func close() { pickerTask?.cancel(); pickerTask = nil; pickerID = nil; picker.cancel(); flow.close(); image = nil; renderedAsset = nil; revision += 1 }
}

@MainActor struct OwnedTopicCoverAuthorView: View {
    let original: OwnedTopicCoverAuthorPresentation.Presentation
    let mayChange: () -> Bool
    let close: () -> Void
    @StateObject private var model: OwnedTopicCoverAuthorModel
    @Environment(\.locale) private var locale
    init(original: OwnedTopicCoverAuthorPresentation.Presentation, mayChange: @escaping () -> Bool,
         selected: @escaping (OwnedTopicCoverAuthorPresentation.Presentation) -> Void, close: @escaping () -> Void, picker: (any OwnedTopicCoverSelecting)? = nil) {
        self.original = original; self.mayChange = mayChange; self.close = close
        _model = StateObject(wrappedValue:.init(original:original,picker:picker,selected:selected))
    }
    private func text(_ key:StaticString,_ english:String.LocalizationValue) -> String { String(localized:LocalizedStringResource(key,defaultValue:english,locale:locale)) }
    var body: some View {
        let flow = original.flow, local = flow.localReview, selection = flow.selectionReview, saved = flow.snapshot
        NavigationStack {
            Form {
                Section {
                    Text(text("ownedCover.scope","Choose a cover for a future reviewed release. Picking a photo stays local. Uploading and selecting are separate explicit actions; existing releases keep their original image."))
                        .accessibilityIdentifier("ownedCover.scope")
                    if let current = flow.current {
                        LabeledContent(text("ownedCover.topic","Saved topic"),value:String(current.topicID))
                        LabeledContent(text("ownedCover.config","Current content revision"),value:String(current.configVersion))
                        LabeledContent(text("ownedCover.selectionRevision","Current cover revision"),value:String(current.selectionVersion))
                        if let asset = current.asset { assetFields(asset,prefix:"ownedCover.saved") }
                        if current.selection == .stale { Text(text("ownedCover.stale","The saved cover selection belongs to an earlier content or ownership revision. Review an explicit replacement before applying it.")) }
                        if current.availability == .unavailable { Text(text("ownedCover.savedUnavailable","The current cover bytes are unavailable. The saved selection has not been cleared.")) }
                        if let asset = current.asset {
                            Button(text("ownedCover.readSaved","Read the saved cover image")) { Task { await model.read(asset) } }
                                .buttonStyle(.borderless).disabled(flow.isBusy).accessibilityIdentifier("ownedCover.readSaved")
                        }
                    }
                    Button(text("ownedCover.reload","Read current cover details")) { Task { await model.loadCurrentDetails() } }
                        .buttonStyle(.borderless).disabled(!flow.canReadCurrentDetails).accessibilityIdentifier("ownedCover.reload")
                }
                if !mayChange() {
                    Text(text("ownedCover.editBeforeChange","An unresolved review or release must be recovered first. After requesting review, continue editing and save a new server version before changing its cover."))
                        .accessibilityIdentifier("ownedCover.editBeforeChange")
                }
                Section {
                    Button(text("ownedCover.choose","Choose an image")) { Task { await model.choose() } }
                        .buttonStyle(.borderless).disabled(!flow.canPick).accessibilityIdentifier("ownedCover.choose")
                    if let local {
                        if let image = UIImage(data:local.image.jpeg) { Image(uiImage:image).resizable().scaledToFit().accessibilityIdentifier("ownedCover.localPreview") }
                        Text(text("ownedCover.localOnly","This preview uses only the selected, sanitized image on this device. It has not been uploaded."))
                            .accessibilityIdentifier("ownedCover.localOnly")
                        Button(text("ownedCover.upload","Upload this image for checks")) { model.upload(local) }
                            .buttonStyle(.borderless).disabled(!flow.canUpload(local)).accessibilityIdentifier("ownedCover.upload")
                        Button(text("ownedCover.cancelLocal","Cancel this local image")) { model.cancelPicked(local) }
                            .buttonStyle(.borderless).disabled(flow.isBusy).accessibilityIdentifier("ownedCover.cancelLocal")
                    }
                    if let count = saved?.unresolvedUploadCount, count > 0, !flow.hasUnstoredUploadReceipt {
                        Text(text("ownedCover.uploadUnknown","An upload has no saved asset receipt. It may have reached the server, and no upload-status API is available. Choosing and uploading another image creates a separate upload; no automatic retry will occur."))
                            .accessibilityIdentifier("ownedCover.uploadUnknown")
                    }
                    if flow.hasUnstoredUploadReceipt {
                        Text(text("ownedCover.receiptUnstored","The server returned an asset receipt, but this device could not save it. Keep this screen open and retry saving the receipt before selecting the cover."))
                        Button(text("ownedCover.saveReceipt","Save the received asset receipt")) { model.persistReceipt() }
                            .buttonStyle(.borderless).disabled(!flow.canPersistUploadReceipt).accessibilityIdentifier("ownedCover.saveReceipt")
                    }
                    if let asset = flow.uploadedAsset {
                        assetFields(asset,prefix:"ownedCover.uploaded")
                        Button(text("ownedCover.readUploaded","Read the checked uploaded image")) { Task { await model.read(asset) } }
                            .buttonStyle(.borderless).disabled(flow.isBusy).accessibilityIdentifier("ownedCover.readUploaded")
                    }
                }
                if let image = model.image, let asset = model.renderedAsset, flow.isCurrent {
                    Section {
                        Image(uiImage:image).resizable().scaledToFit().accessibilityIdentifier("ownedCover.serverPreview")
                        Text(text("ownedCover.verifiedBytes","These bytes were read through this account's exact asset reference and matched its SHA-256. This does not approve or publish the topic."))
                        if flow.current == nil {
                            if flow.hasUnstoredReceipt {
                                Text(text("ownedCover.receiptBeforeCurrent","Save the received receipt on this device before reading current cover details."))
                                    .accessibilityIdentifier("ownedCover.receiptBeforeCurrent")
                            } else {
                                Text(text("ownedCover.currentRequired","Read current cover details before reviewing this image. No content or ownership revision has been inferred."))
                                    .accessibilityIdentifier("ownedCover.currentRequired")
                            }
                            Button(text("ownedCover.reload","Read current cover details")) { Task { await model.loadCurrentDetails() } }
                                .buttonStyle(.borderless).disabled(!flow.canReadCurrentDetails).accessibilityIdentifier("ownedCover.readForSelection")
                        }
                        Button(text("ownedCover.reviewSelection","Review this cover selection")) { model.review(asset) }
                            .buttonStyle(.borderless).disabled(!flow.canReviewSelection(asset)).accessibilityIdentifier("ownedCover.reviewSelection")
                    }
                }
                if flow.hasUnstoredSelectionReceipt {
                    Section {
                        Text(text("ownedCover.selectionReceiptUnstored","The server confirmed this selection, but its receipt could not be saved on this device. Save that exact receipt before continuing to review."))
                        Button(text("ownedCover.saveSelectionReceipt","Save the received selection receipt")) { model.persistSelectionReceipt() }
                            .buttonStyle(.borderless).disabled(!flow.canPersistSelectionReceipt).accessibilityIdentifier("ownedCover.saveSelectionReceipt")
                    }
                } else if !flow.hasUnstoredReceipt, flow.hasUnknownSelection, let saved {
                    Section {
                        Text(text("ownedCover.selectionUnknown","The cover selection is unconfirmed. Its original request is saved. A different current revision does not prove it failed."))
                            .accessibilityIdentifier("ownedCover.selectionUnknown")
                        Button(text("ownedCover.checkSelection","Check the original selection request")) { model.check(saved) }
                            .buttonStyle(.borderless).disabled(flow.isBusy).accessibilityIdentifier("ownedCover.checkSelection")
                        Button(text("ownedCover.retrySelection","Retry exactly the original selection")) { model.retry(saved) }
                            .buttonStyle(.borderless).disabled(flow.isBusy || !mayChange()).accessibilityIdentifier("ownedCover.retrySelection")
                    }
                }
                if flow.isWorking { ProgressView().accessibilityIdentifier("ownedCover.working") }
                if case .failed = flow.state { Text(text("ownedCover.failed","The action could not be verified. Existing cover and submission records are retained.")) }
                if flow.state == .unauthorized { Text(text("ownedCover.unauthorized","Sign in again before reading or changing the cover.")) }
            }
            .navigationTitle(text("ownedCover.title","Author cover"))
            .toolbar { ToolbarItem(placement:.cancellationAction) {
                Button(text("ownedCover.close","Close")) { model.close();close() }.accessibilityIdentifier("ownedCover.close")
            } }
        }
        .background(RetainedImagePresenterHost(host:model.pickerHost).frame(width:0,height:0))
        .task(id:original.id) { await model.load() }
        .sheet(item:model.binding(selection)) { captured in selectionConfirmation(captured) }
        .onDisappear { model.close();close() }
    }
    @ViewBuilder private func assetFields(_ asset:OwnedTopicCoverAsset,prefix:String) -> some View {
        Text(verbatim:asset.assetID).textSelection(.enabled).accessibilityIdentifier(prefix + ".asset")
        Text(verbatim:asset.sourceVersion).textSelection(.enabled).accessibilityIdentifier(prefix + ".version")
        Text(verbatim:asset.contentHash).textSelection(.enabled).accessibilityIdentifier(prefix + ".hash")
    }
    private func selectionConfirmation(_ captured:OwnedTopicCoverAuthorFlow.SelectionReview) -> some View {
        NavigationStack {
            Form {
                Text(text("ownedCover.confirmScope","Apply exactly this asset to the captured topic, content revision and CONTENT ownership record. This changes the next review input, not existing releases."))
                assetFields(captured.command.asset,prefix:"ownedCover.confirm")
                LabeledContent(text("ownedCover.topic","Saved topic"),value:String(captured.command.topicID))
                LabeledContent(text("ownedCover.contentSlot","Captured CONTENT ownership record"),value:String(captured.command.expectedContentSlotID))
                LabeledContent(text("ownedCover.config","Current content revision"),value:String(captured.command.expectedConfigVersion))
                LabeledContent(text("ownedCover.selectionRevision","Current cover revision"),value:String(captured.command.expectedSelectionVersion))
                Button(text("ownedCover.confirm","Apply this exact cover selection")) { model.confirm(captured) }
                    .buttonStyle(.borderless).accessibilityIdentifier("ownedCover.confirm")
            }
            .navigationTitle(text("ownedCover.confirmTitle","Confirm cover selection"))
            .toolbar { ToolbarItem(placement:.cancellationAction) {
                Button(text("ownedCover.cancel","Cancel")) { model.cancel(captured) }.accessibilityIdentifier("ownedCover.cancel")
            } }
        }.onDisappear { model.cancel(captured) }
    }
}
