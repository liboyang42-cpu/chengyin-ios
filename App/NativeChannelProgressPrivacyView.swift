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
            } else if owner.attempted {
                ContentUnavailableView { Label { Text("d7.channelProgress.closed", tableName: "NativeChannelProgress") } icon: { Image(systemName: "hand.raised") } }
            }
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
            if model.busy { ProgressView() }
            if !model.isCurrent { Text("d7.channelProgress.closed", tableName: "NativeChannelProgress") }
            if model.isCurrent, let values = draft {
                NativeChannelProgressScopePickers(values: Binding(get: { draft ?? values }, set: { draft = $0 }))
                    .disabled(!model.canSavePrivacy)
            }
            if let current = model.privacy {
                Section {
                    if let effective = current.effective {
                        LabeledContent { Text(LocalizedStringKey(effective.aggregateScope.rawValue), tableName: "NativeChannelProgress") } label: { Text("d7.channelProgress.aggregate", tableName: "NativeChannelProgress") }
                        LabeledContent { Text(LocalizedStringKey(effective.detailScope.rawValue), tableName: "NativeChannelProgress") } label: { Text("d7.channelProgress.detailScope", tableName: "NativeChannelProgress") }
                    }
                    if let at = current.updatedAt {
                        LabeledContent { Text(verbatim: NativeChannelProgressDateText.text(at)) } label: { Text("d7.channelProgress.updatedLabel", tableName: "NativeChannelProgress") }
                    }
                } header: { Text("d7.channelProgress.effective", tableName: "NativeChannelProgress") }
            }
            Section {
                if model.pendingCommand != nil {
                    Text("d7.channelProgress.originalPending", tableName: "NativeChannelProgress")
                    Button { actions.run { await model.recoverOriginal() } } label: { Text("d7.channelProgress.checkOriginal", tableName: "NativeChannelProgress") }
                        .disabled(model.busy).accessibilityIdentifier("channelProgress.checkOriginal")
                    Button { actions.run { await model.recoverOriginal(retryOriginal: true) } } label: { Text("d7.channelProgress.retryOriginal", tableName: "NativeChannelProgress") }
                        .disabled(model.busy).accessibilityIdentifier("channelProgress.retryOriginal")
                }
                if model.privacyPhase == .unresolved { Text("d7.channelProgress.outcomeUnknown", tableName: "NativeChannelProgress").nativeChannelNotice(systemImage: "clock") }
                if model.privacyPhase == .conflict { Text("d7.channelProgress.privacyConflict", tableName: "NativeChannelProgress") }
                if model.privacyPhase == .persistenceFailed { Text("d7.channelProgress.persistenceFailed", tableName: "NativeChannelProgress") }
                if let receipt = model.receipt, receipt.status == "APPLIED" {
                    Label { Text("d7.channelProgress.applied", tableName: "NativeChannelProgress") } icon: { Image(systemName: "checkmark.circle") }
                        .accessibilityIdentifier("channelProgress.applied")
                }
                Button {
                    confirmation.prepare(current: model.privacy, draft: draft, canSave: model.canSavePrivacy)
                    showsConfirmation = confirmation.review != nil
                } label: { Text("d7.channelProgress.save", tableName: "NativeChannelProgress") }.nativeChannelPrimaryAction().disabled(!model.canSavePrivacy || draft == nil)
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
        .confirmationDialog(Text("d7.channelProgress.confirmPrivacy", tableName: "NativeChannelProgress"), isPresented: $showsConfirmation, titleVisibility: .visible) {
            Button { confirmSave() } label: { Text("d7.channelProgress.save", tableName: "NativeChannelProgress") }
            Button(role: .cancel) { confirmation.invalidate() } label: { Text("cancel", tableName: "NativeChannelProgress") }
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
            } label: { Text("d7.channelProgress.aggregate", tableName: "NativeChannelProgress") }.accessibilityIdentifier("channelProgress.aggregateScope")
            Picker(selection: $values.detailScope) {
                ForEach(NativeChannelProgressScope.allCases.filter { $0 != .publicAccess }, id: \.self) { Text(LocalizedStringKey($0.rawValue), tableName: "NativeChannelProgress").tag($0) }
            } label: { Text("d7.channelProgress.detailScope", tableName: "NativeChannelProgress") }.accessibilityIdentifier("channelProgress.detailScope")
            Picker(selection: $values.photoScope) {
                ForEach(NativeChannelProgressPhotoScope.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue), tableName: "NativeChannelProgress").tag($0) }
            } label: { Text("d7.channelProgress.photo", tableName: "NativeChannelProgress") }.accessibilityIdentifier("channelProgress.photoScope")
            Picker(selection: $values.leaderboardScope) {
                ForEach(NativeChannelProgressLeaderboardScope.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue), tableName: "NativeChannelProgress").tag($0) }
            } label: { Text("d7.channelProgress.leaderboard", tableName: "NativeChannelProgress") }.accessibilityIdentifier("channelProgress.leaderboardScope")
        } header: { Text("d7.channelProgress.whoCanSee", tableName: "NativeChannelProgress") }
    }
}
