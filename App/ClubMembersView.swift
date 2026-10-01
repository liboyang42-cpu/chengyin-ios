import SwiftUI

@MainActor
struct ClubMembersView<Reader: ClubReading & ObservableObject>: View {
    let id: Int
    @ObservedObject var reader: Reader
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
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.fill").font(.title).foregroundStyle(.secondary).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    if let nickname = member.trimmedNickname { Text(verbatim: nickname) }
                                    else { Text("club.memberNumber \(member.memberId)") }
                                    if member.isOwner { Text("club.role.creator").font(.caption).foregroundStyle(.secondary) }
                                    else if member.isAdmin { Text("club.role.administrator").font(.caption).foregroundStyle(.secondary) }
                                }
                            }.padding(.vertical, 4).accessibilityIdentifier("club.member.\(member.memberId)")
                        }
                    } header: { ClubName(value: directory.club.name) }
                }
            }
        }.navigationTitle("club.members")
    }
}
