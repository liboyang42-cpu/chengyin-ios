import SwiftUI

/// A settings host may inject a privacy-only coordinator. Returning from the
/// background resolves a new owner; the original command remains in its journal.
@MainActor struct NativeChannelProgressPrivacyEntry: View {
    let makeFlow: () throws -> NativeChannelProgressCoordinator?
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var owner = NativeChannelProgressVisitOwner()
    @State private var isVisible = false
    var body: some View {
        Group {
            if let model = owner.model {
                NativeChannelProgressPrivacyView(model: model, loadsOnAppear: false).id(owner.visitID)
            } else if owner.attempted { Text("closed", tableName: "NativeChannelProgress") }
            else { ProgressView() }
        }
        .onAppear { isVisible = true; reopen() }
        .onDisappear { isVisible = false; owner.retire() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reopen() } else { owner.retire() }
        }
    }
    private func reopen() {
        guard isVisible, scenePhase == .active else { return }
        let makeFlow = makeFlow, visibility = $isVisible
        owner.open(parentCurrent: { visibility.wrappedValue }, privacyOnly: true) { sourceCurrent in
            guard sourceCurrent() else { return nil }
            return try makeFlow()
        }
    }
}

/// A confirmation binds the exact settings read, draft and visible visit. A
/// dismissed, refreshed or edited review cannot be reused by a queued Task.
@MainActor final class NativeChannelProgressPrivacyConfirmation: ObservableObject {
    struct Review: Equatable {
        let current: NativeChannelProgressPrivacy
        let values: NativeChannelProgressPrivacyValues
        let generation: UUID
    }
    @Published private(set) var review: Review?
    private var generation = UUID()
    private var visible = false
    func enter() { visible = true; invalidate() }
    func leave() { visible = false; invalidate() }
    func invalidate() { generation = UUID(); review = nil }
    func prepare(current: NativeChannelProgressPrivacy?, draft: NativeChannelProgressPrivacyValues?, canSave: Bool) {
        invalidate()
        guard visible, canSave, let current, let draft else { return }
        review = Review(current: current, values: draft, generation: generation)
    }
    func validates(_ review: Review, current: NativeChannelProgressPrivacy?,
                   draft: NativeChannelProgressPrivacyValues?, canSave: Bool) -> Bool {
        visible && canSave && generation == review.generation && current == review.current && draft == review.values
    }
    func consume(current: NativeChannelProgressPrivacy?, draft: NativeChannelProgressPrivacyValues?, canSave: Bool) -> Review? {
        guard let selected = review, validates(selected, current: current, draft: draft, canSave: canSave) else {
            invalidate(); return nil
        }
        review = nil
        return selected
    }
}

@MainActor struct NativeChannelProgressPrivacyView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var model: NativeChannelProgressCoordinator
    var loadsOnAppear = true
    @State private var draft: NativeChannelProgressPrivacyValues?
    @StateObject private var confirmation = NativeChannelProgressPrivacyConfirmation()
    @StateObject private var actions = NativeChannelProgressActionLifetime()
    @State private var showsConfirmation = false
    var body: some View {
        Form {
            Section { Text("privacyExplanation", tableName: "NativeChannelProgress") }
            if model.busy { ProgressView() }
            if !model.isCurrent { Text("closed", tableName: "NativeChannelProgress") }
            if model.isCurrent, let values = draft {
                NativeChannelProgressScopePickers(values: Binding(get: { draft ?? values }, set: { draft = $0 }))
                    .disabled(!model.canSavePrivacy)
            }
            if let current = model.privacy {
                Section {
                    if let effective = current.effective {
                        LabeledContent { Text(verbatim: effective.aggregateScope.rawValue) } label: { Text("aggregate", tableName: "NativeChannelProgress") }
                        LabeledContent { Text(verbatim: effective.detailScope.rawValue) } label: { Text("detailScope", tableName: "NativeChannelProgress") }
                    }
                    if let at = current.updatedAt { Text(verbatim: at).font(.caption) }
                } header: { Text("effective", tableName: "NativeChannelProgress") } footer: { Text("effectiveExplanation", tableName: "NativeChannelProgress") }
            }
            Section {
                if let command = model.pendingCommand {
                    Text("originalPending", tableName: "NativeChannelProgress")
                    Text(verbatim: command.requestId).font(.caption.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: "\(command.aggregateScope.rawValue) · \(command.detailScope.rawValue) · \(command.photoScope.rawValue) · \(command.leaderboardScope.rawValue)").font(.caption)
                    Button { actions.run { await model.recoverOriginal() } } label: { Text("checkOriginal", tableName: "NativeChannelProgress") }
                        .disabled(model.busy).accessibilityIdentifier("channelProgress.checkOriginal")
                    Button { actions.run { await model.recoverOriginal(retryOriginal: true) } } label: { Text("retryOriginal", tableName: "NativeChannelProgress") }
                        .disabled(model.busy).accessibilityIdentifier("channelProgress.retryOriginal")
                }
                if model.privacyPhase == .unresolved { Text("outcomeUnknown", tableName: "NativeChannelProgress").nativeChannelNotice(systemImage: "clock") }
                if model.privacyPhase == .conflict { Text("privacyConflict", tableName: "NativeChannelProgress") }
                if model.privacyPhase == .persistenceFailed { Text("persistenceFailed", tableName: "NativeChannelProgress") }
                if let receipt = model.receipt, receipt.status == "APPLIED" {
                    Text("applied", tableName: "NativeChannelProgress").accessibilityIdentifier("channelProgress.applied")
                    if let id = receipt.requestId { Text(verbatim: id).font(.caption.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                    // Historical receipt is shown separately from the current effective settings.
                    Text(verbatim: "\(receipt.aggregateScope.rawValue) · \(receipt.detailScope.rawValue) · \(receipt.photoScope.rawValue) · \(receipt.leaderboardScope.rawValue)").font(.caption)
                }
                Button {
                    confirmation.prepare(current: model.privacy, draft: draft, canSave: model.canSavePrivacy)
                    showsConfirmation = confirmation.review != nil
                } label: { Text("save", tableName: "NativeChannelProgress") }.nativeChannelPrimaryAction().disabled(!model.canSavePrivacy || draft == nil)
                    .accessibilityIdentifier("channelProgress.savePrivacy")
            }
            NativeChannelProgressIssueView(model: model, part: "privacy")
        }.nativeChannelScreen().navigationTitle(Text("privacy", tableName: "NativeChannelProgress")).privacySensitive()
        .onAppear { confirmation.enter(); actions.activate() }
        .task {
            if loadsOnAppear { await model.loadPrivacy() }
            guard !Task.isCancelled, model.isCurrent else { return }
            synchronizeDraft()
        }
        .onChange(of: model.privacy) { _, _ in synchronizeDraft() }
        .onChange(of: draft) { _, _ in confirmation.invalidate(); showsConfirmation = false }
        .onChange(of: model.isCurrent) { _, current in
            if !current { confirmation.leave(); actions.retire(); draft = nil; showsConfirmation = false }
        }
        .onDisappear { confirmation.leave(); actions.retire(); draft = nil; showsConfirmation = false }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { confirmation.leave(); actions.retire(); draft = nil; showsConfirmation = false }
        }
        .refreshable { confirmation.invalidate(); showsConfirmation = false; await model.loadPrivacy() }
        .confirmationDialog(Text("confirmPrivacy", tableName: "NativeChannelProgress"), isPresented: $showsConfirmation, titleVisibility: .visible) {
            Button { confirmSave() } label: { Text("confirm", tableName: "NativeChannelProgress") }
            Button(role: .cancel) { confirmation.invalidate() } label: { Text("cancel", tableName: "NativeChannelProgress") }
        } message: {
            if let values = confirmation.review?.values { Text(verbatim: "\(values.aggregateScope.rawValue) · \(values.detailScope.rawValue) · \(values.photoScope.rawValue) · \(values.leaderboardScope.rawValue)") }
        }
    }
    private func synchronizeDraft() {
        confirmation.invalidate(); showsConfirmation = false
        draft = try? model.privacy?.values()
    }
    private func confirmSave() {
        guard let review = confirmation.consume(current: model.privacy, draft: draft, canSave: model.canSavePrivacy) else { return }
        actions.run {
            // Recheck at execution, not just when the confirmation button was tapped.
            guard !Task.isCancelled, confirmation.validates(review, current: model.privacy, draft: draft, canSave: model.canSavePrivacy) else { return }
            await model.savePrivacy(review.values)
            // Current settings are synchronized by their observation, never by a
            // completion retained from a view that has already disappeared.
        }
    }
}
private struct NativeChannelProgressScopePickers: View {
    @Binding var values: NativeChannelProgressPrivacyValues
    var body: some View {
        Section {
            Picker(selection: $values.aggregateScope) {
                ForEach(NativeChannelProgressScope.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue), tableName: "NativeChannelProgress").tag($0) }
            } label: { Text("aggregate", tableName: "NativeChannelProgress") }.accessibilityIdentifier("channelProgress.aggregateScope")
            Picker(selection: $values.detailScope) {
                ForEach(NativeChannelProgressScope.allCases.filter { $0 != .publicAccess }, id: \.self) { Text(LocalizedStringKey($0.rawValue), tableName: "NativeChannelProgress").tag($0) }
            } label: { Text("detailScope", tableName: "NativeChannelProgress") }.accessibilityIdentifier("channelProgress.detailScope")
            Picker(selection: $values.photoScope) {
                ForEach(NativeChannelProgressPhotoScope.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue), tableName: "NativeChannelProgress").tag($0) }
            } label: { Text("photo", tableName: "NativeChannelProgress") }.accessibilityIdentifier("channelProgress.photoScope")
            Picker(selection: $values.leaderboardScope) {
                ForEach(NativeChannelProgressLeaderboardScope.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue), tableName: "NativeChannelProgress").tag($0) }
            } label: { Text("leaderboard", tableName: "NativeChannelProgress") }.accessibilityIdentifier("channelProgress.leaderboardScope")
        }
    }
}
