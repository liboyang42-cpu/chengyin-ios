#if DEBUG
import SwiftUI

/// DEBUG-only `--uitesting-roam-home` host for the 开始漫游 / 漫游护照 home. Synthetic readers only:
/// no session, location, network or write. `--uitesting-roam-home-scenario` picks the peek state.
@MainActor struct RoamHomeFixtureHostView: View {
    static var selected: Bool { ProcessInfo.processInfo.arguments.contains("--uitesting-roam-home") }
    @State private var roam = RoamFixtureReader()
    @State private var experience = RoamExperienceFixtureReader(scenario: .content)
    @State private var tools = RoamPassportToolsFixtureReader(scenario: .content)
    @State private var entry: RoamEntryNearbyFixtureReader
    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--uitesting-roam-home-scenario")
        let raw = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        _entry = State(initialValue: RoamEntryNearbyFixtureReader(scenario: raw.flatMap(RoamEntryNearbyFixtureReader.Scenario.init(rawValue:)) ?? .content))
    }
    private static var teams: [NearbyTeam] {
        struct Envelope: Decodable { let data: [NearbyTeam] }
        return (try? JSONDecoder().decode(Envelope.self, from: Data(NearbyTeamSyntheticFixtures.teams.utf8)).data) ?? []
    }
    var body: some View {
        RoamBrowserView(reader: roam, experienceReader: experience,
            nearbyTeamsDestination: { AnyView(Text(verbatim: "nearby").accessibilityIdentifier("roam.home.fixture.nearby")) },
            eventDestination: { target in AnyView(Text(verbatim: String(describing: target)).accessibilityIdentifier("roam.home.fixture.event")) },
            entryReader: entry, entryTeams: { _ in Self.teams },
            myTeamsDestination: { AnyView(Text(verbatim: "mine").accessibilityIdentifier("roam.home.fixture.mine")) },
            nearbyTeamDestination: { id in AnyView(Text(verbatim: "team \(id.rawValue)").accessibilityIdentifier("roam.home.fixture.team")) },
            toolsReader: tools)
    }
}
#endif
