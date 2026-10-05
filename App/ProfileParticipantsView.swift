import SwiftUI

@MainActor
struct ProfileParticipantsView: View {
    let reader: any ProfileReading
    let coordinator: ParticipantMutationCoordinator?
    @State private var showsCreate = false
    @State private var refreshID = UUID()
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
                                }.padding(.vertical, 4)
                            }.accessibilityIdentifier("profile.participant.\(participant.id)")
                        }
                    } footer: { Text("profile.participants.hint") }
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
                Section { Text("profile.participants.hint").foregroundStyle(.secondary) }
                Section { Text("profile.readOnly").foregroundStyle(.secondary) }
            }
        }
        .appNavigationTitle("profile.participants.detail")
        .navigationBarTitleDisplayMode(.inline)
        }
    }
}
