import SwiftUI

@MainActor
struct ClubMembersView<Reader: ClubReading & ObservableObject>: View {
    let id: Int
    @ObservedObject var reader: Reader
    var profile: ClubEnrollmentProfileContext? = nil
    @Environment(\.clubEnrollmentProfile) private var inheritedProfile
    private struct ProfileDestination: Hashable {
        let memberID: Int
        let identity: ClubReadIdentity
    }
    @State private var destination: ProfileDestination?
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
                                    destination = .init(memberID: member.memberId, identity: reader.clubIdentity)
                                } label: { memberRow(member) }
                                .accessibilityIdentifier("club.member.\(member.memberId)")
                                .accessibilityHint(Text("social.profile"))
                            } else {
                                memberRow(member).accessibilityIdentifier("club.member.\(member.memberId)")
                            }
                        }
                    } header: { ClubName(value: directory.club.name) }
                }
            }
        }.appNavigationTitle("club.members")
        .navigationDestination(item: $destination) { target in
            if target.identity == reader.clubIdentity, let profileContext, matches(profileContext, target.identity) {
                SocialPublicProfileView(memberID: target.memberID, reader: profileContext.reader,
                                        squareReader: profileContext.squareReader, actions: profileContext.actions)
                    .id(target)
            }
        }
        .onChange(of: reader.clubIdentity) { _, _ in destination = nil }
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
