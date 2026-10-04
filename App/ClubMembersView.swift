import SwiftUI

@MainActor
struct ClubMembersView<Reader: ClubReading & ObservableObject>: View {
    let id: Int
    @ObservedObject var reader: Reader
    var profile: ClubEnrollmentProfileContext? = nil
    var governance: ClubGovernanceContext? = nil
    @Environment(\.clubEnrollmentProfile) private var inheritedProfile
    private struct ProfileDestination: Hashable {
        let selectionID = UUID()
        let clubID: Int
        let viewerRevision: UInt64?
        let memberID: Int
        var customer = false
        let identity: ClubReadIdentity
    }
    @State private var destination: ProfileDestination?
    @State private var choice: ProfileDestination?
    @State private var choosing = false
    private func matchesGovernance(_ identity: ClubReadIdentity) -> Bool {
        identity.isSignedIn && governance?.access.identity == identity && governance?.access.isConfigured == true
    }
    private var profileContext: ClubEnrollmentProfileContext? { profile ?? inheritedProfile }
    private func matches(_ context: ClubEnrollmentProfileContext, _ identity: ClubReadIdentity) -> Bool {
        identity.isSignedIn && context.reader.identity.accountID == identity.accountID && context.reader.identity.epoch == identity.epoch
    }
    var onSignIn: (() -> Void)? = nil
    var body: some View {
        // The reader re-fetches detail before members, rather than inheriting the previous page's gate.
        ClubReadScreen(reader: reader, accessibilityPrefix: "club.members", requiresSignIn: true,
                       onSignIn: onSignIn, load: { try await reader.clubMembers(id: id) }) { directory in
            if directory.members.isEmpty {
                ClubEmptyState(title: directory.isReportedListUnavailable ? "club.membersUnavailable" : "club.emptyMembers",
                               hint: directory.isReportedListUnavailable ? "club.membersUnavailableHint" : "club.emptyMembersHint",
                               identifier: "club.members.empty")
            } else {
                List {
                    Section {
                        ForEach(Array(directory.members.enumerated()), id: \.offset) { _, member in
                            if member.memberId > 0, let profileContext, matches(profileContext, reader.clubIdentity) {
                                Button {
                                    let target = ProfileDestination(clubID: id, viewerRevision: governance?.viewerRevision, memberID: member.memberId, identity: reader.clubIdentity)
                                    if directory.club.id == id, directory.club.canGovern, matchesGovernance(target.identity) {
                                        choice = target; choosing = true
                                    } else { destination = target }
                                } label: { memberRow(member) }
                                .accessibilityIdentifier("club.member.\(member.memberId)")
                                .accessibilityHint(Text(directory.club.canGovern && matchesGovernance(reader.clubIdentity) ? "club.members" : "social.profile"))
                            } else {
                                memberRow(member).accessibilityIdentifier("club.member.\(member.memberId)")
                            }
                        }
                    } header: { ClubName(value: directory.club.name) }
                }
            }
        }.appNavigationTitle("club.members")
        .confirmationDialog("club.members", isPresented: $choosing, titleVisibility: .hidden, presenting: choice) { target in
            Button("social.profile") { select(target, customer: false) }
                .accessibilityIdentifier("club.member.choice.public")
            if target.viewerRevision == governance?.viewerRevision, matchesGovernance(target.identity) {
                Button("club.gov.customer") { select(target, customer: true) }
                    .accessibilityIdentifier("club.member.choice.customer")
            }
            Button("action.cancel", role: .cancel) { choice = nil }
        }
        .navigationDestination(item: $destination) { target in
            if target.clubID == id, target.viewerRevision == governance?.viewerRevision, target.identity == reader.clubIdentity {
                if target.customer, let governance, matchesGovernance(target.identity) {
                    // This existing reader rechecks access/me and exact member scope before exposing CRM data.
                    ClubGovernanceReadView(operation: .customer, scope: .init(clubID: target.clubID, memberID: target.memberID),
                                           identity: target.identity, access: governance.access, coordinator: governance.coordinator)
                        .id(target)
                } else if !target.customer, let profileContext, matches(profileContext, target.identity) {
                    SocialPublicProfileView(memberID: target.memberID, reader: profileContext.reader,
                                            squareReader: profileContext.squareReader, actions: profileContext.actions)
                        .id(target)
                }
            }
        }
        .onChange(of: reader.clubIdentity) { _, _ in destination = nil; choice = nil; choosing = false }
        .onChange(of: id) { _, _ in destination = nil; choice = nil; choosing = false }
        .onChange(of: governance?.viewerRevision) { _, _ in destination = nil; choice = nil; choosing = false }
    }
    private func select(_ target: ProfileDestination, customer: Bool) {
        guard choice == target else { return }
        choice = nil; choosing = false
        guard target.clubID == id, target.viewerRevision == governance?.viewerRevision, target.identity == reader.clubIdentity, target.memberID > 0, id > 0 else { return }
        if customer { guard matchesGovernance(target.identity) else { return } }
        else { guard let profileContext, matches(profileContext, target.identity) else { return } }
        var selected = target; selected.customer = customer; destination = selected
    }
    private func memberRow(_ member: ClubMember) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill").font(.title).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if let nickname = member.trimmedNickname { Text(verbatim: nickname) }
                else { Text("club.memberNumber \(member.memberId)") }
                if member.isOwner { Text("club.role.creator").font(.caption).foregroundStyle(.secondary) }
                else if member.isAdmin { Text("club.role.administrator").font(.caption).foregroundStyle(.secondary) }
            }
        }.padding(.vertical, 4)
    }
}
