import SwiftUI

@MainActor
struct ProfileParticipantsView: View {
    let reader: any ProfileReading
    var body: some View {
        ProfileReadScreen(reader: reader, accessibilityPrefix: "profile.participants", load: { try await reader.profileParticipants() }) { participants in
            if participants.isEmpty {
                ProfileEmptyState(title: "profile.participants.empty", hint: "profile.participants.emptyHint", symbol: "person.2", identifier: "profile.participants.empty")
            } else {
                List {
                    Section {
                        ForEach(participants) { participant in
                            NavigationLink { ProfileParticipantDetailView(id: participant.id, reader: reader) } label: {
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
        .navigationTitle("profile.participants.title")
    }
}

@MainActor
struct ProfileParticipantDetailView: View {
    let id: Int
    let reader: any ProfileReading
    var body: some View {
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
        .navigationTitle("profile.participants.detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}
