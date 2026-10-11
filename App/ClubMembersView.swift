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
    @State private var memberReport: ClubMemberReportTarget?
    @State private var reportDirectory: ClubMemberDirectory?
    @State private var reportReadGeneration: UInt64 = 0
    @State private var reportRefreshRevision: UInt64 = 0
    @State private var reportSourceActive = true
    private var reportContext: ClubGovernanceReadContext {
        .init(operation: .members, scope: .init(clubID: id), identity: reader.clubIdentity,
              viewerRevision: governance?.viewerRevision ?? 0, authorizationGeneration: governance?.access.authorizationGeneration,
              accessIdentity: governance.map { ObjectIdentifier($0.access) })
    }
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
        ClubReadScreen(reader: reader, accessibilityPrefix: "club.members", requiresSignIn: true, refreshRevision: reportRefreshRevision,
                       onSignIn: onSignIn, load: {
                           reportReadGeneration &+= 1
                           let revision = reportReadGeneration, expected = reportContext
                           reportDirectory = nil; memberReport = nil
                           let directory = try await reader.clubMembers(id: id, isCurrent: {
                               revision == reportReadGeneration && expected == reportContext && reportSourceActive
                           })
                           guard revision == reportReadGeneration, expected == reportContext, reportSourceActive, !Task.isCancelled else { throw CancellationError() }
                           reportDirectory = directory
                           return directory
                       }) { directory in
            if directory.members.isEmpty {
                ClubEmptyState(title: directory.isReportedListUnavailable ? "club.membersUnavailable" : "club.emptyMembers",
                               hint: directory.isReportedListUnavailable ? "club.membersUnavailableHint" : "club.emptyMembersHint",
                               identifier: "club.members.empty")
            } else {
                List {
                    Section {
                        ForEach(Array(directory.members.enumerated()), id: \.offset) { _, member in
                            HStack(spacing: 12) {
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
                                Spacer(minLength: 0)
                                reportButton(member, directory: directory)
                            }.buttonStyle(.borderless)
                        }
                    } header: { ClubName(value: directory.club.name) }
                }
            }
        }.appNavigationTitle("club.members")
        .sheet(item: $memberReport) { target in
            if let governance, currentReport(target) {
                NavigationStack { ClubMemberReportView(target: target, identity: reader.clubIdentity, governance: governance) }
            } else {
                Color.clear.onAppear { if memberReport?.id == target.id { memberReport = nil } }
            }
        }
        .onChange(of: reportContext) { _, _ in
            reportReadGeneration &+= 1; reportDirectory = nil; memberReport = nil; reportRefreshRevision &+= 1
        }
        .onAppear {
            if !reportSourceActive { reportSourceActive = true; reportRefreshRevision &+= 1 }
        }
        .onDisappear { reportSourceActive = false; reportReadGeneration &+= 1 }
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
                        .environment(\.clubCustomerTopics, governance.customerTopics)
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
    @ViewBuilder private func reportButton(_ member: ClubMember, directory: ClubMemberDirectory) -> some View {
        if let governance, governance.access.isConfigured, governance.access.identity == reader.clubIdentity,
           let target = ClubMemberReportTarget(member: member, directory: directory, context: reportContext) {
            Button {
                guard reportSourceActive, memberReport == nil, destination == nil, !choosing, choice == nil,
                      reportDirectory == directory, currentReport(target) else { return }
                memberReport = target
            } label: { Image(systemName: "flag").frame(minWidth: 44, minHeight: 44) }
            .accessibilityLabel(reportLabel(target))
            .disabled(reportDirectory != directory || !reportSourceActive || memberReport != nil || destination != nil || choosing)
            .accessibilityIdentifier("club.memberReport.open.\(member.memberId)")
        }
    }
    private func reportLabel(_ target: ClubMemberReportTarget) -> Text {
        if let name = target.displayName { return Text("club.memberReport.actionNamed \(name)") }
        return Text("club.memberReport.action")
    }
    private func currentReport(_ target: ClubMemberReportTarget) -> Bool {
        governance?.access.isConfigured == true && governance?.access.identity == reader.clubIdentity &&
        target.isCurrent(directory: reportDirectory, context: reportContext)
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
                if let level = member.displayedLevel {
                    Text("club.memberLevel \(level)").font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("club.member.level.\(member.memberId)")
                }
                if let joined = member.displayedJoinTime {
                    Text("club.memberJoined \(joined)").font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("club.member.joined.\(member.memberId)")
                }
            }
        }.padding(.vertical, 4)
    }
}
