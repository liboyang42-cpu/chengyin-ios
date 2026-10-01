import SwiftUI

@MainActor
struct ClubDetailView<Reader: ClubReading & ObservableObject>: View {
    let id: Int
    @ObservedObject var reader: Reader
    var onSignIn: (() -> Void)? = nil
    var actionCoordinator: ClubActionCoordinator? = nil
    var management:ClubManagementContext? = nil
    @State private var actionDetail: ClubRecord? = nil
    @State private var actionIdentity: ClubReadIdentity? = nil
    @State private var detailGeneration: UInt64 = 0
    var body: some View {
        ClubReadScreen(reader: reader, accessibilityPrefix: "club.detail", onSignIn: onSignIn,
                       load: {
                           detailGeneration &+= 1
                           let revision = detailGeneration, identity = reader.clubIdentity
                           let detail = try await reader.clubDetail(id: id)
                           // Neither an older refresh nor a pre-mutation read can
                           // replace a newer refresh or action readback.
                           guard !Task.isCancelled, revision == detailGeneration, identity == reader.clubIdentity else { throw CancellationError() }
                           // Clear on every accepted read, even if its value equals the
                           // older pre-action snapshot (for example after removal).
                           actionDetail = nil; actionIdentity = nil
                           return detail
                       }) { loadedClub in
            let club = actionIdentity == reader.clubIdentity && actionDetail?.id == id ? (actionDetail ?? loadedClub) : loadedClub
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
                if let actionCoordinator {
                    ClubActionPanel(club: club, identity: reader.clubIdentity, coordinator: actionCoordinator,
                                    onReadbackStarted: { detailGeneration &+= 1; return detailGeneration }) { detail, identity, generation in
                        guard identity == reader.clubIdentity, detail.id == id, generation == detailGeneration else { return }
                        actionDetail = detail; actionIdentity = identity
                    }
                }
                if (club.isOwner || club.viewerIsAdmin),let management {
                    Section {
                        NavigationLink {
                            ClubManagementView(clubID:id,identity:reader.clubIdentity,access:management.access,coordinator:management.coordinator)
                        } label: { Label("club.management.title",systemImage:"person.2.badge.gearshape") }
                        .accessibilityIdentifier("club.openManagement")
                    }
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
            .id(id)
            .onChange(of: reader.clubIdentity) { _, _ in actionDetail = nil; actionIdentity = nil }
    }
}
