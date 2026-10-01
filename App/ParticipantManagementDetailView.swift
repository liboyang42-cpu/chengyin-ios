import SwiftUI

@MainActor
struct ParticipantManagementDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ParticipantFormModel
    @State private var showsEditor = false

    init(id: Int, reader: any ProfileReading, coordinator: ParticipantMutationCoordinator) {
        _model = StateObject(wrappedValue: ParticipantFormModel(id: id, reader: reader, coordinator: coordinator))
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
                ProgressView("profile.loading").accessibilityIdentifier("participant.detail.loading")
            } else if !model.loaded {
                ParticipantLoadFailureView(issue: model.issue) { Task { await model.load() } }
            } else {
                List {
                    Section("profile.participants.contact") {
                        LabeledContent("profile.participants.name") { Text(verbatim: model.draft.fullName).textSelection(.enabled) }
                        LabeledContent("profile.participants.phone") { Text(verbatim: model.draft.mobilePhone).textSelection(.enabled) }
                    }
                    if let province = model.draft.province, !province.isEmpty {
                        Section("profile.participants.savedAddress") {
                            Text(verbatim: [province, model.draft.detailAddress].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "))
                                .textSelection(.enabled)
                        }
                    } else if let address = model.draft.detailAddress, !address.isEmpty {
                        Section("profile.participants.savedAddress") { Text(verbatim: address).textSelection(.enabled) }
                    }
                    Section {
                        Button("participant.form.edit") { showsEditor = true }
                            .disabled(!model.canMutate).accessibilityIdentifier("participant.detail.edit")
                        Button("participant.form.delete", role: .destructive) { model.prepareDelete() }
                            .disabled(!model.canMutate).accessibilityIdentifier("participant.detail.delete")
                    } footer: { Text("participant.form.sharedRow") }
                    if let issue = model.issue { Section { ParticipantIssueText(issue: issue) } }
                    ParticipantOperationSections(state: model.operation, readback: model.readback) {
                        Task { await model.readBack() }
                    }
                }
            }
        }
        .appNavigationTitle("profile.participants.detail")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.busy)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("profile.refresh", systemImage: "arrow.clockwise") { Task { await model.load() } }
                    .disabled(model.loading || model.busy || model.operation == .awaitingConfirmation)
                    .accessibilityIdentifier("participant.detail.refresh")
            }
        }
        .sheet(isPresented: $showsEditor, onDismiss: { Task { await model.load() } }) {
            NavigationStack {
                ParticipantFormView(id: model.id, reader: model.reader, coordinator: model.coordinator)
            }
        }
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
