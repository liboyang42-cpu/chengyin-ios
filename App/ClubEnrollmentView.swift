import SwiftUI

struct ClubEnrollmentProfileContext {
    let reader: any SocialAccountReading
    let squareReader: any SquareReading
    var actions: SocialActionCoordinator? = nil
}
private struct ClubEnrollmentProfileKey: EnvironmentKey {
    static let defaultValue: ClubEnrollmentProfileContext? = nil
}
extension EnvironmentValues {
    var clubEnrollmentProfile: ClubEnrollmentProfileContext? {
        get { self[ClubEnrollmentProfileKey.self] }
        set { self[ClubEnrollmentProfileKey.self] = newValue }
    }
}

/// Club-wide roster. Financial actions are intentionally absent from roster rows.
@MainActor struct ClubEnrollmentView: View {
    let clubID: Int
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    @Environment(\.clubEnrollmentProfile) private var profile
    @State private var reader: ClubEnrollmentReader
    @State private var returningFromCheckin = false
    init(clubID: Int, focusTopicID: Int? = nil, identity: ClubReadIdentity?, access: any ClubGovernanceAccess, coordinator: ClubGovernanceCoordinator) {
        self.clubID = clubID; self.identity = identity; self.access = access; self.coordinator = coordinator
        _reader = State(initialValue: ClubEnrollmentReader(clubID: clubID, focusTopicID: focusTopicID, access: access))
    }
    var body: some View {
        List {
            if reader.loading { ProgressView("club.enroll.loading").accessibilityIdentifier("club.enroll.loading") }
            if let issue = reader.failure {
                Section {
                    if reader.hasLoaded { Text("club.enroll.stale").accessibilityIdentifier("club.enroll.stale") }
                    Text(LocalizedStringKey(issue.localizationKey))
                    if let message = issue.message { Text(verbatim: message) }
                    Button("club.enroll.retry") { Task { await reader.refresh() } }.disabled(reader.loading)
                }
            }
            if identity == reader.identity, identity == access.identity, reader.hasLoaded {
                Section {
                    LabeledContent("club.enroll.teamCount") { Text(reader.teams.count, format: .number) }
                    Text("club.enroll.readOnly").font(.footnote).foregroundStyle(.secondary)
                }
                if reader.teams.isEmpty { Text("club.enroll.emptyTeams").accessibilityIdentifier("club.enroll.emptyTeams") }
                ForEach(reader.teams) { team in
                    Section {
                        Button { Task { await reader.toggle(topicID: team.id) } } label: {
                            HStack(alignment: .top) {
                                if let image = team.image { SquareImage(source: image).frame(width: 52, height: 52).clipped().accessibilityHidden(true) }
                                VStack(alignment: .leading, spacing: 6) {
                                    title(team.name, fallback: "club.enroll.unnamedTeam").font(.headline)
                                    title(team.date, fallback: "club.enroll.dateUnknown").font(.caption)
                                    LabeledContent("club.enroll.signups") { number(team.signupCount) }.font(.caption)
                                }
                                Image(systemName: reader.expanded.contains(team.id) ? "chevron.down" : "chevron.right").accessibilityHidden(true)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).disabled(reader.loading)
                        .accessibilityValue(Text(reader.expanded.contains(team.id) ? "club.enroll.expanded" : "club.enroll.collapsed"))
                        .accessibilityIdentifier("club.enroll.team.\(team.id)")
                        if reader.expanded.contains(team.id) { detail(team) }
                    }
                }
            }
        }
        .navigationTitle("club.enroll.title")
        .accessibilityIdentifier("club.enroll.screen")
        .refreshable { await reader.refresh() }
        .task(id: identity) {
            await reader.activate(identity: identity)
            if returningFromCheckin { returningFromCheckin = false; await reader.refresh() }
        }
        .onDisappear { reader.suspend() }
    }
    @ViewBuilder private func detail(_ team: ClubEnrollmentTeam) -> some View {
        if reader.detailLoading.contains(team.id) { ProgressView("club.enroll.detailLoading") }
        if let issue = reader.detailFailures[team.id] {
            if reader.rosters[team.id] != nil { Text("club.enroll.stale").font(.footnote) }
            Text(LocalizedStringKey(issue.localizationKey))
            Button("club.enroll.retry") { Task { await reader.loadDetail(topicID: team.id) } }
                .disabled(reader.detailLoading.contains(team.id)).accessibilityIdentifier("club.enroll.retry.\(team.id)")
        }
        if let roster = reader.rosters[team.id] {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("club.enroll.paid") { Text(roster.paidCount, format: .number) }
                LabeledContent("club.enroll.refundable") { number(roster.refundableCount) }
                if let deadline = roster.deadline { LabeledContent("club.enroll.deadline") { Text(verbatim: deadline) } }
                if let status = roster.teamStatus {
                    LabeledContent("club.enroll.teamStatus") { Text(LocalizedStringKey("club.enroll.teamStatus." + String(status))) }
                }
            }.font(.subheadline).accessibilityIdentifier("club.enroll.summary.\(team.id)")
            if roster.tickets.isEmpty { Text("club.enroll.emptyTickets") }
            ForEach(roster.tickets) { ticket in
                VStack(alignment: .leading, spacing: 8) {
                    title(ticket.name, fallback: "club.enroll.unnamedTicket").font(.headline)
                        .accessibilityIdentifier("club.enroll.ticket.\(ticket.id)")
                    HStack {
                        Text(ticket.registrants.count, format: .number)
                        if let capacity = ticket.capacity, capacity > 0 { Text(verbatim: "/"); Text(capacity, format: .number) }
                        else { Text("club.enroll.registrants") }
                    }.accessibilityIdentifier("club.enroll.capacity.\(ticket.id)")
                    if ticket.registrants.isEmpty { Text("club.enroll.emptyRegistrants").foregroundStyle(.secondary) }
                    ForEach(ticket.registrants) { registrant in row(registrant) }
                }.padding(.vertical, 6)
            }
        }
    }
    @ViewBuilder private func row(_ registrant: ClubEnrollmentRegistrant) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let memberID = registrant.memberID, let profile {
                NavigationLink {
                    SocialPublicProfileView(memberID: memberID, reader: profile.reader, squareReader: profile.squareReader, actions: profile.actions)
                } label: { attendee(registrant) }.accessibilityIdentifier("club.enroll.profile.\(registrant.id)")
            } else { attendee(registrant) }
            NavigationLink {
                ClubGovernanceReadView(operation: .checkin, scope: .init(clubID: clubID, registrationID: registrant.id), identity: identity, access: access, coordinator: coordinator)
                    .onAppear { returningFromCheckin = true }
            } label: {
                Label(LocalizedStringKey("club.enroll.checkin." + registrant.checkin.rawValue), systemImage: registrant.checkin == .done ? "checkmark.circle" : "ticket")
            }
            .accessibilityIdentifier("club.enroll.checkin.\(registrant.id)")
        }.padding(.vertical, 4)
    }
    private func attendee(_ value: ClubEnrollmentRegistrant) -> some View {
        HStack {
            if let avatar = value.avatar { SquareImage(source: avatar).frame(width: 32, height: 32).clipShape(Circle()).accessibilityHidden(true) }
            title(value.nickname, fallback: "club.enroll.player")
        }
    }
    @ViewBuilder private func title(_ text: String?, fallback: LocalizedStringKey) -> some View {
        if let text { Text(verbatim: text) } else { Text(fallback) }
    }
    @ViewBuilder private func number(_ count: Int?) -> some View {
        if let count { Text(count, format: .number) } else { Text("club.enroll.unknown") }
    }
}
