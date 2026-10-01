import SwiftUI

/// View-local PII disappears with the form; the injected coordinator retains only the
/// operation lock/readback needed to prevent a dismissed request from being sent twice.
@MainActor
final class ParticipantFormModel: ObservableObject {
    let reader: any ProfileReading
    let coordinator: ParticipantMutationCoordinator
    let id: Int?
    @Published var draft = ParticipantFormDraft()
    @Published private(set) var loading = true
    @Published private(set) var loaded = false
    @Published private(set) var issue: ParticipantScreenIssue?
    @Published private(set) var operation: ParticipantMutationState = .idle
    @Published private(set) var readback: ParticipantReadbackState = .idle
    @Published var showConfirmation = false
    private(set) var confirmationSummary = ""
    private(set) var confirmation: ParticipantConfirmation?
    private var loadedIdentity: ProfileReadIdentity?
    private var generation: UInt64 = 0

    init(id: Int?, reader: any ProfileReading, coordinator: ParticipantMutationCoordinator) {
        self.id = id; self.reader = reader; self.coordinator = coordinator
    }
    var canSave: Bool {
        canMutate && draft.validation == nil
    }
    var canMutate: Bool { loaded && coordinator.canPrepare && loadedIdentity == coordinator.identity }
    var busy: Bool { operation == .submitting || readback == .loading }
    func sync() {
        coordinator.synchronizeSession()
        operation = coordinator.state; readback = coordinator.readbackState
    }
    func load() async {
        coordinator.leaveScreen(confirmation: confirmation)
        confirmation = nil; confirmationSummary = ""; showConfirmation = false
        generation &+= 1
        let stamp = generation
        loaded = false; loading = true; issue = nil; draft = ParticipantFormDraft()
        loadedIdentity = nil; sync()
        guard reader.isConfigured, coordinator.isConfigured else { loading = false; return }
        guard let identity = reader.identity, identity == coordinator.identity else { loading = false; return }
        loadedIdentity = identity
        if case .outcomeUnknown = operation { loading = false; return }
        defer { if stamp == generation { loading = false } }
        do {
            let value: ParticipantFormDraft
            if let id {
                let detail = try await reader.profileParticipant(id: id)
                guard detail.id == id else { throw APIError.malformedResponse }
                value = ParticipantFormDraft(detail: detail)
            } else { value = ParticipantFormDraft() }
            guard stamp == generation, !Task.isCancelled, reader.identity == identity,
                  coordinator.identity == identity else { return }
            draft = value; loadedIdentity = identity; loaded = true
        } catch {
            guard stamp == generation, !Task.isCancelled, reader.identity == identity,
                  coordinator.identity == identity else { return }
            issue = ParticipantScreenIssue(error)
        }
    }
    func prepareSave() {
        guard canSave, let identity = loadedIdentity else { return }
        do {
            confirmation = try coordinator.prepare(.save(draft), expectedIdentity: identity)
            confirmationSummary = draft.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                + "\n" + draft.mobilePhone.trimmingCharacters(in: .whitespacesAndNewlines)
            showConfirmation = true; issue = nil; sync()
        } catch { issue = ParticipantScreenIssue(error) }
    }
    func prepareDelete() {
        guard canMutate, let id, let identity = loadedIdentity else { return }
        do {
            confirmation = try coordinator.prepare(.delete(id: id), expectedIdentity: identity)
            confirmationSummary = draft.fullName + "\n" + draft.mobilePhone
            showConfirmation = true; issue = nil; sync()
        } catch { issue = ParticipantScreenIssue(error) }
    }
    func cancelConfirmation() {
        if let confirmation { coordinator.cancelConfirmation(confirmation) }
        confirmation = nil; confirmationSummary = ""; showConfirmation = false; sync()
    }
    func confirmMutation() async -> Bool {
        guard let confirmation else { return false }
        showConfirmation = false; operation = .submitting
        let result = await coordinator.confirm(confirmation)
        self.confirmation = nil; confirmationSummary = ""; sync()
        if case .blocked = result { issue = ParticipantScreenIssue(ParticipantCoordinatorBlock.accountChanged) }
        return result == .applied && operation == .succeeded
    }
    func readBack() async {
        readback = .loading
        _ = await coordinator.readBackUncertainOutcome()
        sync()
    }
    func disappear() {
        generation &+= 1
        coordinator.leaveScreen(confirmation: confirmation)
        if let loadedIdentity { coordinator.discardReadback(expectedIdentity: loadedIdentity) }
        confirmation = nil; confirmationSummary = ""; showConfirmation = false
        draft = ParticipantFormDraft(); loaded = false; loadedIdentity = nil
    }
}

@MainActor
struct ParticipantFormView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ParticipantFormModel
    @FocusState private var focusedField: Field?
    private enum Field { case name, phone }
    let onSaved: () -> Void

    init(id: Int? = nil, reader: any ProfileReading, coordinator: ParticipantMutationCoordinator,
         onSaved: @escaping () -> Void = {}) {
        _model = StateObject(wrappedValue: ParticipantFormModel(id: id, reader: reader, coordinator: coordinator))
        self.onSaved = onSaved
    }

    var body: some View {
        Group {
            if !model.reader.isConfigured || !model.coordinator.isConfigured {
                ContentUnavailableView("profile.unavailable", systemImage: "network.slash", description: Text("auth.notConfigured"))
            } else if model.reader.identity == nil || model.coordinator.identity == nil {
                ContentUnavailableView("profile.signInRequired", systemImage: "person.crop.circle.badge.exclamationmark", description: Text("auth.expired"))
            } else if case .outcomeUnknown = model.operation {
                Form {
                    ParticipantOperationSections(state: model.operation, readback: model.readback) {
                        Task { await model.readBack() }
                    }
                }
            } else if model.loading {
                ProgressView("profile.loading").accessibilityIdentifier("participant.form.loading")
            } else if !model.loaded {
                ParticipantLoadFailureView(issue: model.issue) { Task { await model.load() } }
            } else {
                Form {
                    Section {
                        TextField("profile.participants.name", text: $model.draft.fullName)
                            .textContentType(.name).textInputAutocapitalization(.words)
                            .submitLabel(.next).focused($focusedField, equals: .name)
                            .onSubmit { focusedField = .phone }
                            .accessibilityIdentifier("participant.form.name")
                        TextField("profile.participants.phone", text: $model.draft.mobilePhone)
                            .textContentType(.telephoneNumber).keyboardType(.phonePad)
                            .submitLabel(.done).focused($focusedField, equals: .phone)
                            .onSubmit { model.prepareSave() }
                            .accessibilityIdentifier("participant.form.phone")
                    } footer: { Text("participant.form.purpose") }
                    .disabled(model.operation.preventsNewMutation)
                    if !model.draft.mobilePhone.isEmpty, model.draft.validation == .invalidPhone {
                        Section { Text("participant.form.phoneHint").foregroundStyle(.secondary) }
                    }
                    if let issue = model.issue {
                        Section { ParticipantIssueText(issue: issue) }
                    }
                    ParticipantOperationSections(state: model.operation, readback: model.readback) {
                        Task { await model.readBack() }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) {
                    Button { focusedField = nil; model.prepareSave() } label: {
                        Text(LocalizedStringKey(model.operation == .submitting ? "participant.form.saving" : "participant.form.save"))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).disabled(!model.canSave)
                    .accessibilityIdentifier("participant.form.save")
                    .padding().background(.regularMaterial)
                }
            }
        }
        .appNavigationTitle(key: model.id == nil ? "participant.form.add" : "participant.form.edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("action.cancel") { model.disappear(); dismiss() }
                    .disabled(model.busy).accessibilityIdentifier("participant.form.cancel")
            }
        }
        .interactiveDismissDisabled(model.busy)
        .alert("participant.form.confirmSave", isPresented: $model.showConfirmation) {
            Button("participant.form.save") {
                Task { if await model.confirmMutation() { onSaved(); dismiss() } }
            }
            Button("action.cancel", role: .cancel) { model.cancelConfirmation() }
        } message: {
            Text("participant.form.confirmSaveHint") + Text(verbatim: "\n\(model.confirmationSummary)")
        }
        .task(id: model.reader.identity) { await model.load() }
        .onDisappear { model.disappear() }
    }
}

struct ParticipantScreenIssue {
    let key: String
    let message: String?
    init(_ error: Error) {
        let failure = error as? ProfileReadFailure
        if error as? APIError == .unauthorized || failure?.isUnauthorized == true {
            key = "auth.expired"; message = nil
        } else if error is ParticipantCoordinatorBlock {
            key = "participant.form.sessionChanged"; message = nil
        } else {
            key = "profile.retryHint"
            message = failure?.message.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        }
    }
}

struct ParticipantIssueText: View {
    let issue: ParticipantScreenIssue
    var body: some View {
        if let message = issue.message { Text(verbatim: message).foregroundStyle(.red) }
        else { Text(LocalizedStringKey(issue.key)).foregroundStyle(.red) }
    }
}

struct ParticipantLoadFailureView: View {
    let issue: ParticipantScreenIssue?
    let retry: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("profile.loadFailed", systemImage: "exclamationmark.circle")
        } description: {
            if let issue { ParticipantIssueText(issue: issue) }
            else { Text("participant.form.sessionChanged") }
        } actions: {
            Button("action.retry", action: retry).accessibilityIdentifier("participant.form.reload")
        }
    }
}

/// Used in both forms and detail actions. An uncertain write exposes readback, never a
/// retry-save/delete button. Readback does not silently turn uncertainty into success.
struct ParticipantOperationSections: View {
    let state: ParticipantMutationState
    let readback: ParticipantReadbackState
    let readAgain: () -> Void
    var body: some View {
        switch state {
        case .submitting:
            Section { ProgressView("participant.form.saving") }
        case .rejected(let failure):
            Section("participant.form.rejected") {
                if let message = failure.message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(verbatim: message)
                } else { Text("participant.form.rejectedHint") }
            }
        case .notSent:
            Section { Text("participant.form.notSent") }
        case .outcomeUnknown:
            Section("participant.form.unknown") {
                Text("participant.form.unknownHint")
                Button("participant.form.readBack", action: readAgain)
                    .disabled(readback == .loading).accessibilityIdentifier("participant.form.readBack")
            }
            switch readback {
            case .loading:
                Section { ProgressView("profile.loading") }
            case .unavailable:
                Section { Text("participant.form.readBackFailed") }
            case .received(let result):
                Section("participant.form.readBackTitle") {
                    switch result {
                    case .list(let rows):
                        if rows.isEmpty { Text("profile.participants.empty") }
                        ForEach(rows) { row in ParticipantReadbackRow(row: row) }
                    case .detail(let row): ParticipantReadbackRow(row: row)
                    }
                    Text("participant.form.readBackHint").foregroundStyle(.secondary)
                }
            case .idle: EmptyView()
            }
        default: EmptyView()
        }
    }
}

private struct ParticipantReadbackRow: View {
    let row: ProfileParticipant
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: row.fullName)
            Text(verbatim: row.mobilePhone).foregroundStyle(.secondary)
            if !row.oneLineAddress.isEmpty { Text(verbatim: row.oneLineAddress).foregroundStyle(.secondary) }
        }.textSelection(.enabled)
    }
}
