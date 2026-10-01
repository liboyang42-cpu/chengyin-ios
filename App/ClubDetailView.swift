import SwiftUI

@MainActor
struct ClubDetailView<Reader: ClubReading & ObservableObject>: View {
    let id: Int
    @ObservedObject var reader: Reader
    var onSignIn: (() -> Void)? = nil
    var body: some View {
        ClubReadScreen(reader: reader, accessibilityPrefix: "club.detail", onSignIn: onSignIn,
                       load: { try await reader.clubDetail(id: id) }) { club in
            List {
                Section {
                    ClubName(value: club.name).font(.title2.bold()).accessibilityIdentifier("club.detail.name")
                    ClubOptionalRow(title: "club.style", value: club.style)
                    LabeledContent("club.members") { Text(club.memberCount, format: .number) }
                    if club.isOwner { Label("club.role.creator", systemImage: "person.crop.circle.badge.checkmark") }
                    else if club.isJoined { Label("club.membership.joined", systemImage: "checkmark.circle") }
                    else if club.joinPending { Label("club.membership.pending", systemImage: "clock") }
                    else if club.myJoinStatus == 2 { Text("club.membership.rejected") }
                    if club.viewerIsAdmin { Text("club.viewerAdministrator") }
                    if (1...5).contains(club.level) { LabeledContent("club.level") { Text(verbatim: "L\(club.level)") } }
                }
                Section("club.introduction") {
                    if let description = club.description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(verbatim: description).textSelection(.enabled)
                    } else { Text("club.noIntroduction").foregroundStyle(.secondary) }
                    ClubOptionalRow(title: "club.leader", value: club.leaderName)
                    ClubOptionalRow(title: "club.city", value: club.city)
                    ClubOptionalRow(title: "club.address", value: club.address)
                    ClubOptionalRow(title: "club.type", value: club.clubType ?? club.clubTypes)
                    ClubOptionalRow(title: "club.preferences", value: club.activityPrefs.isEmpty ? nil : club.activityPrefs.joined(separator: ", "))
                    ClubOptionalRow(title: "club.keywords", value: club.keywords)
                }
                Section("club.members") {
                    if club.canSeeMembers {
                        NavigationLink {
                            ClubMembersView(id: club.id, reader: reader, onSignIn: onSignIn)
                        } label: { Label("club.viewMembers", systemImage: "person.3") }
                            .accessibilityIdentifier("club.openMembers")
                    } else { Text("club.joinToSeeMembers").foregroundStyle(.secondary).accessibilityIdentifier("club.members.gated") }
                }
            }
        }.navigationTitle("club.detail")
    }
}
