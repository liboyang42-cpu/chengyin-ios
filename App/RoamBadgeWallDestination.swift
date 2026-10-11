import SwiftUI

@MainActor struct RoamBadgeWallDestination: View {
    let roamReader: any RoamExperienceReading
    var body: some View {
        if roamReader.isOfflineExample {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--uitesting-roam-experience") {
                RoamBadgeWallFixtureDestination(roamReader: roamReader)
            } else { changed }
            #else
            changed
            #endif
        } else { SessionRoamBadgeWallDestination(roamReader: roamReader) }
    }
    private var changed: some View { ContentUnavailableView("roam.badgeWall.changed", systemImage: "person.crop.circle.badge.exclamationmark") }
}
@MainActor private struct SessionRoamBadgeWallDestination: View {
    @EnvironmentObject private var session: AppSession
    let roamReader: any RoamExperienceReading
    var body: some View {
        if ObjectIdentifier(roamReader) == ObjectIdentifier(session.roamExperienceReader) {
            RoamBadgeWallOwnedView(roam: roamReader, profile: session.profileReader,
                currentOwner: .init(roam: roamReader, profile: session.profileReader))
        } else { ContentUnavailableView("roam.badgeWall.changed", systemImage: "person.crop.circle.badge.exclamationmark") }
    }
}
@MainActor private struct RoamBadgeWallOwnedView: View {
    let currentOwner: RoamBadgeWallReadOwner
    @State private var reader: RoamBadgeWallReader
    init(roam: any RoamExperienceReading, profile: any ProfileReading, currentOwner: RoamBadgeWallReadOwner) {
        self.currentOwner = currentOwner; _reader = State(initialValue: .init(roam: roam, profile: profile))
    }
    var body: some View {
        if currentOwner == reader.origin, reader.isCurrent {
            ObjectBadgeWallView(reader: reader)
        } else {
            ContentUnavailableView("roam.badgeWall.changed", systemImage: "person.crop.circle.badge.exclamationmark")
                .accessibilityIdentifier("roam.badgeWall.changed")
        }
    }
}
#if DEBUG
/// Only the already-selected synthetic Roam host can construct this paired identity fixture.
/// Its badge payload is the existing synthetic Profile fixture, never a production account read.
@MainActor private struct RoamBadgeWallFixtureDestination: View {
    let roamReader: any RoamExperienceReading
    @State private var profile: RoamBadgeWallFixtureReader
    init(roamReader: any RoamExperienceReading) {
        self.roamReader = roamReader
        let args = ProcessInfo.processInfo.arguments, index = args.firstIndex(of: "--uitesting-roam-badges-scenario")
        let raw = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        let identity = roamReader.identity.map { ProfileReadIdentity(accountID: $0.scope.accountID, epoch: $0.epoch) }
        _profile = State(initialValue: .init(identity: identity, scenario: raw.flatMap(ProfileFixtureScenario.init(rawValue:)) ?? .success))
    }
    var body: some View {
        RoamBadgeWallOwnedView(roam: roamReader, profile: profile, currentOwner: .init(roam: roamReader, profile: profile))
    }
}
@MainActor private final class RoamBadgeWallFixtureReader: ProfileReading {
    let identity: ProfileReadIdentity?
    private let fixture: ProfileFixtureReader
    var isConfigured: Bool { fixture.isConfigured }
    init(identity: ProfileReadIdentity?, scenario: ProfileFixtureScenario) {
        self.identity = scenario == .unauthorized ? nil : identity; fixture = .init(scenario)
    }
    func profileBadges() async throws -> ProfileBadgeWall { try await fixture.profileBadges() }
    func profileOrders() async throws -> [ProfileOrder] { throw APIError.notConfigured }
    func profileOrder(id: Int) async throws -> ProfileOrder { throw APIError.notConfigured }
    func profileParticipants() async throws -> [ProfileParticipant] { throw APIError.notConfigured }
    func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.notConfigured }
}
#endif
