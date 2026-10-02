import SwiftUI

@MainActor struct PublicMerchantReviewWriteContext {
    let writer: any PublicMerchantReviewWriting
    let journal: any MerchantBusinessIntentStore
    var imageContext: ((PublicMerchantReviewTarget, Int) -> RetainedImageSelectionContext?)? = nil
    var invalidateImages: ((PublicMerchantReviewTarget) -> Void)? = nil
}
@MainActor final class PublicMerchantReviewEditorModel: ObservableObject {
    let coordinator: PublicMerchantReviewCoordinator
    @Published private(set) var revision = 0
    init(context: PublicMerchantReviewWriteContext) { coordinator = .init(writer: context.writer, journal: context.journal) }
    func prepare(_ command: PublicMerchantReviewCommand, target: PublicMerchantReviewTarget, page: Int) async {
        revision += 1; await coordinator.prepare(command, target: target, page: page); revision += 1
    }
    func confirm(_ value: PublicMerchantReviewConfirmation) async { revision += 1; await coordinator.confirm(value); revision += 1 }
    func cancel() { coordinator.cancel(); revision += 1 }
    func invalidate() { coordinator.invalidate(); revision += 1 }
}
@MainActor struct PublicMerchantReviewEditor: View {
    let target: PublicMerchantReviewTarget
    let registrationID: Int?
    let reportItem: PublicMerchantReviewPage.Item?
    let page: Int
    @StateObject private var model: PublicMerchantReviewEditorModel
    @State private var content = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var rating = 0
    @State private var images: [RetainedUploadedImage] = []
    private let imageContext: RetainedImageSelectionContext?
    private let invalidateImages: ((PublicMerchantReviewTarget) -> Void)?
    private var state: PublicMerchantReviewCoordinator { model.coordinator }
    init(target: PublicMerchantReviewTarget, registrationID: Int? = nil, reportItem: PublicMerchantReviewPage.Item? = nil, page: Int = 1, context: PublicMerchantReviewWriteContext) {
        self.target = target; self.registrationID = registrationID; self.reportItem = reportItem; self.page = page
        imageContext = registrationID.flatMap { context.imageContext?(target, $0) }
        invalidateImages = context.invalidateImages
        _model = StateObject(wrappedValue: .init(context: context))
    }
    private var command: PublicMerchantReviewCommand? {
        if let reportItem { return .report(reviewID: reportItem.id, expectedVersion: reportItem.version, reason: content) }
        if let registrationID { return .create(registrationID: registrationID, rating: rating, content: content, images: images) }
        return nil
    }
    var body: some View {
        Form {
            Section {
                Text("image.retained.reviewBoundary").font(.footnote)
                if reportItem == nil {
                    Picker("merchant.publicHome.rating", selection: $rating) {
                        Text("merchant.publicHome.selectRating").tag(0)
                        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                    }.accessibilityIdentifier("merchant.publicHome.ratingPicker")
                }
                TextField(reportItem == nil ? "merchant.publicHome.reviewContent" : "merchant.publicHome.reportReason", text: $content, axis: .vertical)
                    .lineLimit(4...10).accessibilityIdentifier("merchant.publicHome.editorText")
            }.disabled(state.busy || state.locked || state.confirmation != nil || state.receipt != nil)
            if reportItem == nil, let imageContext {
                Section("image.retained.photos") {
                    ForEach(images) { image in
                        HStack {
                            Label("image.retained.uploaded", systemImage: "photo")
                            Button("image.retained.remove", role: .destructive) { images.removeAll { $0.id == image.id } }
                        }
                    }
                    if images.count < 9 { RetainedImageSelectionView(context: imageContext) { image in
                        guard !state.busy, !state.locked, state.confirmation == nil, state.receipt == nil,
                              imageContext.currentScope() == imageContext.scope, image.scope == imageContext.scope,
                              images.count < 9, !images.contains(where: { $0.id == image.id }) else { return false }
                        images.append(image); return images.contains(image)
                    } }
                }.disabled(state.busy || state.locked || state.confirmation != nil || state.receipt != nil)
            }
            if let review = state.confirmation {
                Section("merchant.publicHome.confirmTitle") {
                    LabeledContent("merchant.publicHome.merchantRowID", value: String(review.target.merchantRowID.rawValue))
                    if reportItem != nil { LabeledContent("merchant.publicHome.ownerMemberID", value: String(review.target.ownerMemberID.rawValue)) }
                    if case .create(let registration, let stars, _, let frozenImages) = review.command {
                        LabeledContent("merchant.publicHome.registrationID", value: String(registration))
                        LabeledContent("merchant.publicHome.rating", value: String(stars))
                        LabeledContent("image.retained.photos", value: String(frozenImages.count))
                    }
                    if case .report(let id, let version, _) = review.command {
                        LabeledContent("merchant.publicHome.reviewID", value: String(id))
                        LabeledContent("merchant.publicHome.version", value: String(version))
                    }
                    Text(verbatim: content)
                    Text(review.command.isCreate ? "merchant.publicHome.createConsequence" : "merchant.publicHome.reportConsequence")
                    Button("merchant.publicHome.confirm") { Task { await model.confirm(review) } }.disabled(state.busy).accessibilityIdentifier("merchant.publicHome.confirm")
                    Button("merchant.publicHome.cancel", role: .cancel) { model.cancel() }.disabled(state.busy)
                }
            } else if state.receipt == nil {
                Button("merchant.publicHome.prepare") {
                    guard let command else { return }
                    Task { await model.prepare(command, target: target, page: page) }
                }.disabled(command == nil || state.busy || state.locked).accessibilityIdentifier("merchant.publicHome.prepare")
            }
            if state.busy { ProgressView("merchant.publicHome.loading") }
            if state.locked { Text("merchant.publicHome.unknown").accessibilityIdentifier("merchant.publicHome.unknown") }
            if let failure = state.failure {
                Text(LocalizedStringKey(failureKey(failure))).accessibilityIdentifier("merchant.publicHome.writeFailure")
            }
            if let receipt = state.receipt {
                Text(reportItem == nil ? "merchant.publicHome.createReceipt" : "merchant.publicHome.reportReceipt")
                LabeledContent("merchant.publicHome.status", value: receipt.status)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("merchant.publicHome.status"))
                    .accessibilityValue(Text(verbatim: receipt.status))
                    .accessibilityIdentifier("merchant.publicHome.status")
                LabeledContent("merchant.publicHome.reviewID", value: String(receipt.reviewId))
                if let audit = receipt.auditTaskId { LabeledContent("merchant.publicHome.auditTaskID", value: String(audit)) }
            }
        }
        .navigationTitle(reportItem == nil ? "merchant.publicHome.createReview" : "merchant.publicHome.report")
        .onChange(of: state.writer.session) { _, _ in clearImageState() }
        .onDisappear { clearImageState() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { clearImageState() } }
    }
    private func clearImageState() {
        images = []; imageContext?.uploads.clear(); imageContext?.picker.cancel()
        invalidateImages?(target); model.invalidate()
    }
    private func failureKey(_ failure: PublicMerchantReviewWriteFailure) -> String {
        switch failure {
        case .invalid: return "merchant.publicHome.invalidDraft"
        case .notConfigured: return "merchant.publicHome.notConfigured"
        case .unknown: return "merchant.publicHome.unknown"
        case .storage: return "merchant.publicHome.storage"
        case .sessionChanged, .permissionChanged: return "merchant.publicHome.changed"
        case .rejected: return "merchant.publicHome.rejected"
        }
    }
}
