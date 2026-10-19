#if DEBUG
import SwiftUI

@MainActor final class TeamFixtureEnvironment: ObservableObject {
    let service: TeamSyntheticService
    let journal = TeamMemoryJournal()
    @Published var session: TeamSession?
    @Published var routeIdentity = UUID()
    private var epoch: UInt64 = 1
    init(scenario: TeamSyntheticService.Scenario) throws {
        service = try TeamSyntheticService(scenario: scenario)
        if scenario == .guest { session = nil } else { session = try TeamSyntheticFixtures.session() }
    }
    func makeCoordinator() -> TeamCoordinator {
        TeamCoordinator(service: service, journal: journal, currentSession: { [weak self] in self?.session })
    }
    func becomeGuest() { epoch &+= 1; session = nil; routeIdentity = UUID() }
    func reauthenticate() { epoch &+= 1; session = try? TeamSyntheticFixtures.session(epoch: epoch); routeIdentity = UUID() }
    func switchAccount() { epoch &+= 1; session = try? TeamSyntheticFixtures.session(epoch: epoch, accountID: 903); routeIdentity = UUID() }
}
@MainActor struct TeamFixtureHostView: View {
    @State private var environment: TeamFixtureEnvironment?
    private let destination: String
    private let reformHooks: TeamReformHooks?
    init() {
        let args = ProcessInfo.processInfo.arguments
        func arg(_ name: String) -> String? { guard let i = args.firstIndex(of: name), args.indices.contains(i + 1) else { return nil }; return args[i + 1] }
        _environment = State(initialValue: try? TeamFixtureEnvironment(scenario: arg("--uitesting-team-scenario").flatMap(TeamSyntheticService.Scenario.init(rawValue:)) ?? .content))
        destination = arg("--uitesting-team-destination") ?? "list"
        reformHooks = arg("--uitesting-team-reform").map(TeamFixtureHostView.reformHooks)
    }
    /// Offline-only switches for the dormant U02 / U05–U07 flows: "<invite>,<meeting>" scenario names.
    private static func reformHooks(_ value: String) -> TeamReformHooks {
        let parts = value.split(separator: ",").map(String.init)
        let invite = TeamSyntheticFriendInviteSender.Scenario(rawValue: parts.first ?? "") ?? .content
        let meeting = TeamSyntheticMeetingService.Scenario(rawValue: parts.count > 1 ? parts[1] : "") ?? .content
        return TeamReformHooks(capabilities: .syntheticFixture([.friendMultiInvite, .teamFirstMeeting]),
                               inviteSender: { TeamSyntheticFriendInviteSender(scenario: invite) },
                               meetingService: { TeamSyntheticMeetingService(scenario: meeting) },
                               simulatedPeerCode: { try? TeamSyntheticMeetingService.peerChallenge(teamID: $0) })
    }
    var body: some View {
        if let environment { TeamFixtureContent(environment: environment, destination: destination).environment(\.teamReformHooks, reformHooks) }
        else { ContentUnavailableView("team.loadFailed", systemImage: "exclamationmark.triangle") }
    }
}
@MainActor private struct TeamFixtureContent: View {
    @ObservedObject var environment: TeamFixtureEnvironment
    let destination: String
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("team.fixture.guest") { environment.becomeGuest() }.accessibilityIdentifier("team.fixture.guest")
                Button("team.fixture.account") { environment.reauthenticate() }.accessibilityIdentifier("team.fixture.account")
                Button("team.fixture.otherAccount") { environment.switchAccount() }.accessibilityIdentifier("team.fixture.otherAccount")
            }.font(.caption).buttonStyle(.bordered).frame(minHeight: 44)
            NavigationStack {
                switch destination {
                case "detail": TeamDetailView(lookup: .id(4101), coordinator: environment.makeCoordinator(), makeCoordinator: { environment.makeCoordinator() })
                case "invitation": TeamDetailView(lookup: .invitation("SYNTHETIC-TEAM"), coordinator: environment.makeCoordinator(), makeCoordinator: { environment.makeCoordinator() })
                case "missing": TeamDetailView(lookup: .invitation(""), coordinator: environment.makeCoordinator(), makeCoordinator: { environment.makeCoordinator() })
                case "legacy": TeamDetailView(lookup: .invitation(""), coordinator: environment.makeCoordinator(), makeCoordinator: { environment.makeCoordinator() }, legacyTeamID: true)
                case "create": TeamCreateView(activityID: 5101, coordinator: environment.makeCoordinator())
                default: TeamHomeView(coordinator: environment.makeCoordinator(), makeCoordinator: environment.makeCoordinator)
                }
            }.id(environment.routeIdentity)
        }
    }
}
#endif
