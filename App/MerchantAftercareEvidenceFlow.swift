import SwiftUI
import UIKit

/// Supplied by the existing workbench. Carrying dependencies never grants a device or upload action.
@MainActor struct MerchantAftercareEvidenceDependencies {
    let reader: any MerchantEngagementReading
    let journal: any MerchantBusinessIntentStore
    let recovery: any MerchantExportRecoveryStoring
}
private struct MerchantAftercareEvidenceDependenciesKey: EnvironmentKey {
    static let defaultValue: MerchantAftercareEvidenceDependencies? = nil
}
extension EnvironmentValues {
    var merchantAftercareEvidenceDependencies: MerchantAftercareEvidenceDependencies? {
        get { self[MerchantAftercareEvidenceDependenciesKey.self] }
        set { self[MerchantAftercareEvidenceDependenciesKey.self] = newValue }
    }
}

/// The page owns the editor lifetime; a matching refund ID alone is insufficient.
@MainActor struct MerchantAftercareEvidenceOwner {
    let editorID: UUID
    let document: MerchantBusinessViewModel
    let scope: MerchantBusinessScope
    let authorization: UUID?
    let snapshot: MerchantBusinessSnapshot
    let revision: Int
    let editorIsCurrent: () -> Bool
    init?(editorID: UUID, document: MerchantBusinessViewModel, editorIsCurrent: @escaping () -> Bool) {
        let c = document.coordinator
        guard c.isCurrent, !c.isBusy, !c.isLocked, c.confirmation == nil, c.failureKey == nil,
              let scope = c.reader.scope, let snapshot = c.snapshot, editorIsCurrent() else { return nil }
        self.editorID = editorID; self.document = document; self.scope = scope
        authorization = c.reader.authorizationGeneration; self.snapshot = snapshot
        revision = document.revision; self.editorIsCurrent = editorIsCurrent
    }
    var isCurrent: Bool {
        let c = document.coordinator
        return editorIsCurrent() && document.revision == revision && c.isCurrent && !c.isBusy && !c.isLocked
            && c.confirmation == nil && c.failureKey == nil && c.snapshot == snapshot
            && c.reader.scope == scope && c.reader.authorizationGeneration == authorization
    }
}

struct MerchantAftercareEvidenceDraft: Equatable {
    let decision: MerchantAftercareDecision
    let content: String
    let evidence: String
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.decision == rhs.decision && lhs.content.utf8.elementsEqual(rhs.content.utf8)
            && lhs.evidence.utf8.elementsEqual(rhs.evidence.utf8)
    }
}

/// Narrowing adapter: owner validity must reach the coordinator's dispatch authorization,
/// including a production transport's final barrier after its own suspended proof/read.
@MainActor private final class MerchantAftercareEvidenceReader: MerchantEngagementReading {
    private let base: any MerchantEngagementReading
    private let owner: MerchantAftercareEvidenceOwner
    private let original: MerchantAftercareEvidenceDraft
    private let currentDraft: () -> MerchantAftercareEvidenceDraft?
    private let authorization: UUID?
    private let refundID: MerchantRefundID
    private var retired = false
    init(base: any MerchantEngagementReading, owner: MerchantAftercareEvidenceOwner,
         refundID: MerchantRefundID, original: MerchantAftercareEvidenceDraft,
         currentDraft: @escaping () -> MerchantAftercareEvidenceDraft?) {
        self.base = base; self.owner = owner; self.refundID = refundID; self.original = original
        self.currentDraft = currentDraft; authorization = base.authorizationGeneration
    }
    private var isCurrent: Bool {
        !retired && owner.isCurrent && currentDraft() == original && base.scope == owner.scope
            && base.authorizationGeneration == authorization
    }
    // The existing coordinator-minted authorization reads this property at every check,
    // including MerchantEngagementProductionTransport's immediate pre-forward validation.
    var scope: MerchantBusinessScope? { isCurrent ? base.scope : nil }
    var authorizationGeneration: UUID? { base.authorizationGeneration }
    var journalRealm: String? { base.journalRealm }
    var isConfigured: Bool { base.isConfigured }
    var isSyntheticEnabled: Bool { base.isSyntheticEnabled }
    func retire() { retired = true }
    private func requireCurrent() throws {
        guard isCurrent, !Task.isCancelled else { throw MerchantBusinessFailure.stale }
    }
    private func requireCommand(_ command: MerchantEngagementCommand) throws {
        try requireCurrent()
        guard case .uploadEvidence(let refund, _, let scope, let merchant) = command,
              refund == refundID, scope == owner.scope, merchant == owner.snapshot.access.merchantID else {
            throw MerchantBusinessFailure.invalid
        }
    }
    func canExecute(_ command: MerchantEngagementCommand, merchantID: Int) -> Bool {
        (try? requireCommand(command)) != nil && merchantID == owner.snapshot.access.merchantID
            && base.canExecute(command, merchantID: merchantID)
    }
    func permitsDevice(_ action: MerchantEngagementDeviceGrant.Action, merchantID: Int) -> Bool {
        isCurrent && action == .selectEvidence(refundID) && merchantID == owner.snapshot.access.merchantID
            && base.permitsDevice(action, merchantID: merchantID)
    }
    func access() async throws -> MerchantEngagementAccess {
        try requireCurrent(); let result = try await base.access(); try requireCurrent(); return result
    }
    func read(_ query: MerchantEngagementQuery) async throws -> MerchantEngagementPayload { throw MerchantBusinessFailure.disabled }
    func proof(_ command: MerchantEngagementCommand) async throws -> MerchantEngagementProof {
        try requireCommand(command)
        let result = try await base.proof(command)
        try requireCommand(command); return result
    }
    func execute(_ command: MerchantEngagementCommand, requestID: String, proof: MerchantEngagementProof,
                 scope: MerchantBusinessScope) async throws -> MerchantEngagementReceipt { throw MerchantBusinessFailure.disabled }
    func execute(_ review: MerchantEngagementReview, authorization: MerchantEngagementDispatchAuthorization,
                 check: () throws -> Void) async throws -> MerchantEngagementReceipt {
        try requireCommand(review.command)
        let result = try await base.execute(review, authorization: authorization, check: {
            try self.requireCommand(review.command); try check()
        })
        // Stale after forwarding is deliberately uncertain; never translate it into .disabled.
        try requireCommand(review.command); return result
    }
}

/// A local bridge to the existing two reviews: upload first, response later.
@MainActor final class MerchantAftercareEvidenceFlow: ObservableObject, Identifiable {
    let id = UUID()
    let owner: MerchantAftercareEvidenceOwner
    let refundID: MerchantRefundID
    let original: MerchantAftercareEvidenceDraft
    let coordinator: MerchantEngagementCoordinator
    private let scopedReader: MerchantAftercareEvidenceReader
    private let authorization: UUID?
    private let currentDraft: () -> MerchantAftercareEvidenceDraft?
    private let applyKey: (String) -> Void
    private var task: Task<Void, Never>?
    private var uploadReview: MerchantEngagementReview?
    @Published private(set) var selection: MerchantEvidenceSelection?
    @Published private(set) var retired = false
    @Published private(set) var attached = false
    @Published private(set) var issue: String?
    @Published private(set) var revision = 0
    @Published private(set) var actionPending = false

    init?(owner: MerchantAftercareEvidenceOwner, dependencies: MerchantAftercareEvidenceDependencies,
          original: MerchantAftercareEvidenceDraft, currentDraft: @escaping () -> MerchantAftercareEvidenceDraft?,
          applyKey: @escaping (String) -> Void) {
        guard owner.isCurrent, case .refund(let refundID) = owner.snapshot.document.query,
              let row = owner.snapshot.document.rows.first(where: { $0.kind == .refund && $0.id == String(refundID.rawValue) }),
              row.fields["canRespond"]?.bool == true,
              (try? row.fields.mbStrings("allowedDecisions").contains("EVIDENCE")) == true,
              (try? owner.snapshot.access.require(["merchant:aftercare:read", "merchant:aftercare:evidence"])) != nil,
              dependencies.reader.scope == owner.scope, currentDraft() == original else { return nil }
        self.owner = owner; self.refundID = refundID; self.original = original
        self.currentDraft = currentDraft; self.applyKey = applyKey
        authorization = dependencies.reader.authorizationGeneration
        let scopedReader = MerchantAftercareEvidenceReader(base: dependencies.reader, owner: owner,
            refundID: refundID, original: original, currentDraft: currentDraft)
        self.scopedReader = scopedReader
        coordinator = .init(reader: scopedReader, journal: dependencies.journal, exportRecovery: dependencies.recovery)
    }
    var isCurrent: Bool {
        !retired && !attached && owner.isCurrent && currentDraft() == original
            && coordinator.reader.scope == owner.scope && coordinator.reader.authorizationGeneration == authorization
    }
    var busy: Bool { actionPending || coordinator.busy }
    var canSelect: Bool {
        isCurrent && !busy && !coordinator.locked && coordinator.review == nil && coordinator.receipt == nil
            && coordinator.reader.permitsDevice(.selectEvidence(refundID), merchantID: owner.snapshot.access.merchantID)
    }
    var review: MerchantEngagementReview? {
        guard isCurrent, let review = coordinator.review, matches(review) else { return nil }; return review
    }
    var canAttach: Bool {
        isCurrent && !busy && !coordinator.locked && coordinator.failure == nil && coordinator.review == nil
            && uploadReview.map(matches) == true && matchingReceipt != nil
    }
    private var matchingReceipt: MerchantAftercareEvidenceReceipt? {
        guard let selection, coordinator.receiptScope == owner.scope,
              coordinator.receiptMerchantID == owner.snapshot.access.merchantID,
              let returned = coordinator.receipt,
              case .evidenceUploaded(let refund, let selectedID, let receipt) = returned,
              refund == refundID, selectedID == selection.id else { return nil }
        return receipt
    }
    private func matches(_ review: MerchantEngagementReview) -> Bool {
        guard let selection, review.scope == owner.scope, review.authorizationGeneration == authorization,
              review.proof.access.identity == owner.snapshot.access,
              review.proof.refund == owner.snapshot.document,
              case .uploadEvidence(let refund, let chosen, let scope, let merchant) = review.command,
              refund == refundID, chosen == selection, scope == owner.scope,
              merchant == owner.snapshot.access.merchantID else { return false }
        return (try? review.command.validateProductionProof(review.proof)) != nil
    }
    @discardableResult func select(_ value: MerchantEvidenceSelection) -> Task<Void, Never>? {
        guard canSelect else { if !isCurrent { retire() }; return nil }
        selection = value; uploadReview = nil; issue = nil
        return prepareUpload()
    }
    @discardableResult func prepareUpload() -> Task<Void, Never>? {
        guard canSelect, let selection else { if !isCurrent { retire() }; return nil }
        let command = MerchantEngagementCommand.uploadEvidence(refundID, selection, scope: owner.scope,
                                                               merchantID: owner.snapshot.access.merchantID)
        actionPending = true
        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.actionPending = false; self.task = nil }
            guard self.isCurrent else { self.retire(); return }
            await self.coordinator.prepare(command)
            guard self.isCurrent, !Task.isCancelled else { self.retire(); return }
            if let review = self.coordinator.review, !self.matches(review) {
                self.coordinator.cancelReview(); self.issue = "merchant.business.stale"
            }
            self.revision += 1
        }
        self.task = task; revision += 1; return task
    }
    func cancelReview() { guard !busy else { return }; coordinator.cancelReview(); issue = nil; revision += 1 }
    func clearSelection() {
        guard isCurrent, !busy, !coordinator.locked, coordinator.receipt == nil else { return }
        task?.cancel(); task = nil; coordinator.cancelReview(); selection = nil; uploadReview = nil; issue = nil; revision += 1
    }
    @discardableResult func confirm(_ review: MerchantEngagementReview) -> Task<Void, Never>? {
        guard isCurrent, coordinator.review == review, matches(review), !busy, !coordinator.locked,
              coordinator.reader.canExecute(review.command, merchantID: owner.snapshot.access.merchantID) else {
            if !isCurrent { retire() }; return nil
        }
        uploadReview = review; actionPending = true
        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.actionPending = false; self.task = nil }
            guard self.isCurrent, self.coordinator.review == review else { self.retire(); return }
            await self.coordinator.confirm(review)
            guard self.isCurrent, !Task.isCancelled else { self.retire(); return }
            self.revision += 1
        }
        self.task = task; revision += 1; return task
    }
    /// Every failure returns before consumption. The remaining write is synchronous local State assignment.
    @discardableResult func attach() -> Bool {
        guard canAttach, let expected = matchingReceipt else { return false }
        guard let receipt = coordinator.takeEvidenceForResponse(refundID: refundID, scope: owner.scope,
                                                               merchantID: owner.snapshot.access.merchantID) else { return false }
        // No await, navigation or fallible callback exists between one-use consumption and local assignment.
        assert(receipt == expected)
        applyKey(receipt.objectKey); attached = true; selection = nil; uploadReview = nil; task = nil; revision += 1
        return true
    }
    func retire() {
        guard !retired else { return }
        retired = true; task?.cancel(); task = nil; actionPending = false; selection = nil; uploadReview = nil
        scopedReader.retire()
        coordinator.invalidate(); revision += 1
    }
}

@MainActor struct MerchantAftercareEvidenceSheet: View {
    @ObservedObject var model: MerchantAftercareEvidenceFlow
    @ObservedObject private var document: MerchantBusinessViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var selecting = false
    init(model: MerchantAftercareEvidenceFlow) { self.model = model; document = model.owner.document }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("merchant.business.storeID", value: String(model.owner.snapshot.access.merchantID))
                    LabeledContent("merchant.engagement.refundID", value: String(model.refundID.rawValue))
                    Text("merchant.aftercareEvidence.separateResponse").font(.footnote)
                }
                if !model.isCurrent { Text("merchant.business.stale") }
                else {
                    if let selection = model.selection {
                        Section("merchant.engagement.evidencePreview") {
                            Text(verbatim: selection.filename)
                            if let image = UIImage(data: selection.bytes) {
                                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 280)
                                    .accessibilityLabel("merchant.engagement.evidencePreview")
                            }
                            if model.coordinator.receipt == nil {
                                Button("merchant.engagement.clearSelection") { model.clearSelection() }
                                    .disabled(model.busy || model.coordinator.locked)
                            }
                        }
                    }
                    if let review = model.review {
                        Section("merchant.engagement.frozenReview") {
                            Text("merchant.aftercareEvidence.uploadReview").font(.footnote)
                            if let selection = model.selection { LabeledContent("merchant.engagement.byteCount", value: String(selection.bytes.count)) }
                            Button(model.coordinator.reader.isSyntheticEnabled ? "merchant.engagement.confirmSynthetic" : "merchant.aftercareEvidence.confirmUpload") {
                                _ = model.confirm(review)
                            }.disabled(!model.coordinator.reader.canExecute(review.command, merchantID: model.owner.snapshot.access.merchantID))
                                .accessibilityIdentifier("merchant.aftercareEvidence.confirmUpload")
                            Button("action.cancel") { model.cancelReview() }
                                .accessibilityIdentifier("merchant.engagement.cancelReview")
                        }
                    } else if model.coordinator.receipt != nil {
                        Section {
                            Text(model.canAttach ? "merchant.engagement.evidenceReady" : "merchant.business.stale")
                            if !model.original.evidence.isEmpty { Text("merchant.aftercareEvidence.replaceHint").font(.footnote) }
                            Button(model.original.evidence.isEmpty ? "merchant.aftercareEvidence.attach" : "merchant.aftercareEvidence.replace") {
                                if model.attach() { dismiss() }
                            }.disabled(!model.canAttach).accessibilityIdentifier("merchant.aftercareEvidence.attach")
                        }
                    } else if !model.busy && !model.coordinator.locked {
                        Section {
                            Button("merchant.engagement.selectEvidence") { selecting = true }
                                .disabled(!model.canSelect).accessibilityIdentifier("merchant.aftercareEvidence.select")
                            if model.selection != nil { Button("merchant.engagement.reviewUpload") { _ = model.prepareUpload() }.disabled(!model.canSelect) }
                            if !model.canSelect { Text("merchant.engagement.nativeSelectionDisabled").font(.footnote) }
                        }
                    }
                    if model.busy { ProgressView("merchant.loading") }
                    if model.coordinator.locked { Text("merchant.business.unknownResult") }
                    if let issue = model.issue ?? model.coordinator.failure?.key { Text(LocalizedStringKey(issue)).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("merchant.engagement.evidence")
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("action.cancel") { model.retire(); dismiss() }.disabled(model.busy)
            } }
            .interactiveDismissDisabled(model.busy)
            .sheet(isPresented: $selecting) {
                NavigationStack {
                    MerchantEvidenceSelectionView(refundID: model.refundID, selectedScope: model.owner.scope,
                        currentScope: { model.canSelect ? model.owner.scope : nil }, nativeSelectionEnabled: model.canSelect) { selected in
                        _ = model.select(selected)
                    }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { selecting = false } } }
                }
            }
        }
        .privacySensitive()
        .onChange(of: document.revision) { _, _ in model.retire(); selecting = false }
        .onChange(of: document.coordinator.reader.scope) { _, _ in model.retire(); selecting = false }
        .onChange(of: document.coordinator.reader.authorizationGeneration) { _, _ in model.retire(); selecting = false }
        .onChange(of: model.coordinator.reader.scope) { _, _ in model.retire(); selecting = false }
        .onChange(of: model.coordinator.reader.authorizationGeneration) { _, _ in model.retire(); selecting = false }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.retire(); selecting = false } }
        .onDisappear { model.retire() }
    }
}
