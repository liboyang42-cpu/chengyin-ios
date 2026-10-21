import SwiftUI

@MainActor
struct ProfileParticipantsView: View {
    let reader: any ProfileReading
    let coordinator: ParticipantMutationCoordinator?
    @State private var showsCreate = false
    @State private var refreshID = UUID()
    @State private var editing: ParticipantRowTarget?
    @State private var deleting: ParticipantRowTarget?
    init(reader: any ProfileReading, coordinator: ParticipantMutationCoordinator? = nil) {
        self.reader = reader; self.coordinator = coordinator
    }
    var body: some View {
        ProfileReadScreen(reader: reader, accessibilityPrefix: "profile.participants", load: { try await reader.profileParticipants() }) { participants in
            if participants.isEmpty {
                ProfileEmptyState(title: "profile.participants.empty", hint: "profile.participants.emptyHint", symbol: "person.2", identifier: "profile.participants.empty")
            } else {
                List {
                    Section {
                        ForEach(participants) { participant in
                            NavigationLink { ProfileParticipantDetailView(id: participant.id, reader: reader, coordinator: coordinator) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    if participant.fullName.isEmpty { Text("profile.participants.unnamed").font(.headline) }
                                    else { Text(verbatim: participant.fullName).font(.headline) }
                                    if !participant.mobilePhone.isEmpty { Text(verbatim: participant.mobilePhone).foregroundStyle(.secondary) }
                                    // Mini-program address list repeats the purpose on every row.
                                    Text("participant.form.purpose").font(.caption).foregroundStyle(.tertiary)
                                }.padding(.vertical, 4)
                            }.accessibilityIdentifier("profile.participant.\(participant.id)")
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if let coordinator, coordinator.isConfigured, reader.identity != nil {
                                    // Direct list entry only opens the existing review/confirm flows; nothing is written here.
                                    Button("participant.form.delete", role: .destructive) { deleting = ParticipantRowTarget(id: participant.id) }
                                        .accessibilityIdentifier("participant.list.delete.\(participant.id)")
                                    Button("participant.form.edit") { editing = ParticipantRowTarget(id: participant.id) }
                                        .tint(.blue).accessibilityIdentifier("participant.list.edit.\(participant.id)")
                                }
                            }
                        }
                    } footer: { Text("participant.form.purpose") }
                }
            }
        }
        .id(refreshID)
        .appNavigationTitle("profile.participants.title")
        .toolbar {
            if let coordinator, coordinator.isConfigured, reader.identity != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("participant.form.add", systemImage: "person.badge.plus") { showsCreate = true }
                        .accessibilityIdentifier("participant.list.add")
                }
            }
        }
        .sheet(isPresented: $showsCreate, onDismiss: { refreshID = UUID() }) {
            if let coordinator {
                NavigationStack { ParticipantFormView(reader: reader, coordinator: coordinator) }
            }
        }
        .sheet(item: $editing, onDismiss: { refreshID = UUID() }) { target in
            if let coordinator {
                NavigationStack { ParticipantFormView(id: target.id, reader: reader, coordinator: coordinator) }
            }
        }
        .sheet(item: $deleting, onDismiss: { refreshID = UUID() }) { target in
            if let coordinator {
                NavigationStack { ParticipantListDeleteView(id: target.id, reader: reader, coordinator: coordinator) }
            }
        }
    }
}

private struct ParticipantRowTarget: Identifiable { let id: Int }

/// List-initiated delete: loads the row, shows it, and requires the existing confirmation
/// alert. Cancel writes nothing; an unknown outcome offers readback only (no resend).
@MainActor
struct ParticipantListDeleteView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ParticipantFormModel
    init(id: Int, reader: any ProfileReading, coordinator: ParticipantMutationCoordinator) {
        _model = StateObject(wrappedValue: ParticipantFormModel(id: id, reader: reader, coordinator: coordinator))
    }
    var body: some View {
        Group {
            if case .outcomeUnknown = model.operation {
                Form { ParticipantOperationSections(state: model.operation, readback: model.readback) { Task { await model.readBack() } } }
            } else if model.loading {
                ProgressView("profile.loading")
            } else if !model.loaded {
                ParticipantLoadFailureView(issue: model.issue) { Task { await model.load() } }
            } else {
                Form {
                    Section("profile.participants.contact") {
                        Text(verbatim: model.draft.fullName)
                        Text(verbatim: model.draft.mobilePhone).foregroundStyle(.secondary)
                    }
                    Section {
                        Button("participant.form.delete", role: .destructive) { model.prepareDelete() }
                            .disabled(!model.canMutate || model.busy || model.showConfirmation)
                            .accessibilityIdentifier("participant.list.delete.review")
                    } footer: { Text("participant.form.sharedRow") }
                    if let issue = model.issue { Section { ParticipantIssueText(issue: issue) } }
                    ParticipantOperationSections(state: model.operation, readback: model.readback) { Task { await model.readBack() } }
                }
            }
        }
        .appNavigationTitle(key: "participant.form.delete")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("action.cancel") { model.disappear(); dismiss() }.disabled(model.busy)
            }
        }
        .interactiveDismissDisabled(model.busy)
        .alert("participant.form.confirmDelete", isPresented: $model.showConfirmation) {
            Button("participant.form.delete", role: .destructive) {
                Task { if await model.confirmMutation() { dismiss() } }
            }
            Button("action.cancel", role: .cancel) { model.cancelConfirmation() }
        } message: {
            Text(verbatim: model.confirmationSummary + "\n") + Text("participant.form.confirmDeleteHint")
        }
        .task(id: model.reader.identity) { await model.load() }
        .onDisappear { model.disappear() }
    }
}

@MainActor
struct ProfileParticipantDetailView: View {
    let id: Int
    let reader: any ProfileReading
    let coordinator: ParticipantMutationCoordinator?
    init(id: Int, reader: any ProfileReading, coordinator: ParticipantMutationCoordinator? = nil) {
        self.id = id; self.reader = reader; self.coordinator = coordinator
    }
    var body: some View {
        if let coordinator {
            ParticipantManagementDetailView(id: id, reader: reader, coordinator: coordinator)
        } else {
        ProfileReadScreen(reader: reader, accessibilityPrefix: "profile.participant.detail", load: { try await reader.profileParticipant(id: id) }) { participant in
            List {
                Section("profile.participants.contact") {
                    LabeledContent("profile.participants.name") {
                        if participant.fullName.isEmpty { Text("profile.valueUnknown") }
                        else { Text(verbatim: participant.fullName).textSelection(.enabled) }
                    }
                    LabeledContent("profile.participants.phone") {
                        if participant.mobilePhone.isEmpty { Text("profile.valueUnknown") }
                        else { Text(verbatim: participant.mobilePhone).textSelection(.enabled) }
                    }
                }
                if !participant.oneLineAddress.isEmpty {
                    Section("profile.participants.savedAddress") {
                        Text(verbatim: participant.oneLineAddress).textSelection(.enabled)
                    }
                }
                // Same stored row can contain an address. No invented shipping purpose,
                // default badge, default switch, editing, add, or delete in this read slice.
                Section { Text("participant.form.purpose").foregroundStyle(.secondary) }
                Section { Text("profile.readOnly").foregroundStyle(.secondary) }
            }
        }
        .appNavigationTitle("profile.participants.detail")
        .navigationBarTitleDisplayMode(.inline)
        }
    }
}
