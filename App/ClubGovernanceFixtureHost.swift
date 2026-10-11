#if DEBUG
import SwiftUI
import Observation

@MainActor struct ClubGovernanceFixtureHost: View {
    @StateObject private var store = ClubGovernanceFixtureStore()
    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("--club-story-scenario") { ClubStoryFixtureHost() }
        else if ProcessInfo.processInfo.arguments.contains("--club-feed-scenario") { ClubFeedFixtureHost() }
        else if ProcessInfo.processInfo.arguments.contains("--club-leaderboard-scenario") {
            VStack(spacing: 4) {
                Button("club.gov.switchAccount") { store.switchAccount() }
                    .accessibilityIdentifier("club.gov.leaderboard.fixture.switch")
                if store.profileReader.holdsProfileResponses {
                    HStack {
                        Text(verbatim: String(store.profileReader.startedCount))
                            .accessibilityIdentifier("club.gov.leaderboard.fixture.profileStarted")
                        Text(verbatim: String(store.profileReader.pendingCount))
                            .accessibilityIdentifier("club.gov.leaderboard.fixture.profilePending")
                        Text(verbatim: String(store.profileReader.returnedCount))
                            .accessibilityIdentifier("club.gov.leaderboard.fixture.profileReturned")
                        Text(verbatim: store.profileReader.returnedAccountID.map(String.init) ?? "none")
                            .accessibilityIdentifier("club.gov.leaderboard.fixture.returnedAccount")
                        Text(verbatim: store.profileReader.returnedMemberID.map(String.init) ?? "none")
                            .accessibilityIdentifier("club.gov.leaderboard.fixture.returnedMember")
                    }
                    Button("Release held profile") { store.profileReader.releasePendingProfiles() }
                        .disabled(store.profileReader.pendingCount == 0)
                        .accessibilityIdentifier("club.gov.leaderboard.fixture.releaseProfile")
                }
                legacyBody
            }
        } else { legacyBody }
    }
    private var legacyBody: some View {
        NavigationStack {
            List {
                Text("club.gov.synthetic").accessibilityIdentifier("club.gov.synthetic")
                NavigationLink { ClubOwnerRefundFixtureView(scenario: .accepted) } label: { Text("club.refund.fixtureAccepted") }.accessibilityIdentifier("club.refund.fixtureAccepted")
                NavigationLink { ClubOwnerRefundFixtureView(scenario: .unknown) } label: { Text("club.refund.fixtureUnknown") }.accessibilityIdentifier("club.refund.fixtureUnknown")
                NavigationLink { ClubOwnerRefundFixtureView(scenario: .disabled) } label: { Text("club.refund.fixtureDisabled") }.accessibilityIdentifier("club.refund.fixtureDisabled")
                NavigationLink {
                    ClubEnrollmentView(clubID: 81, focusTopicID: 91, identity: store.identity, access: store.access, coordinator: store.coordinator)
                        .environment(\.clubEnrollmentProfile, .init(reader: SocialAccountFixtureReader(.content), squareReader: SquareFixtureReader()))
                        .toolbar { ToolbarItem(placement: .bottomBar) { Button("club.gov.switchAccount") { store.switchAccount() }.accessibilityIdentifier("club.gov.switchAccount") } }
                } label: { Text("club.enroll.title") }.accessibilityIdentifier("club.enroll.fixture")
                ClubGovernanceHomeEntries(identity: store.identity, access: store.access, coordinator: store.coordinator)
                ClubGovernanceEntryButton(clubID: 81, identity: store.identity, access: store.access, coordinator: store.coordinator,
                    customerTopics: .init(destination: { id in AnyView(Text(verbatim: "Synthetic history topic \(id)").accessibilityIdentifier("club.fixture.historyTopic.\(id)")) }))
                ForEach([ClubGovernanceRead.customers, .series, .roles, .topicOverview, .editions, .dissolutionBlockers, .leaderboard, .settlement, .audienceCounts, .roster], id: \.rawValue) { operation in
                    NavigationLink {
                        ClubGovernanceReadView(operation: operation, scope: ClubGovernanceFixtures.scope, identity: store.identity, access: store.access, coordinator: store.coordinator)
                            .accessibilityIdentifier("club.gov.fixture.destination." + operation.rawValue)
                            .toolbar {
                                // Leaderboard scenarios already expose a fixed switch above the stack.
                                // A duplicate floating bottom bar can intercept the member-row tap.
                                if !ProcessInfo.processInfo.arguments.contains("--club-leaderboard-scenario") {
                                    ToolbarItem(placement: .bottomBar) { Button("club.gov.switchAccount") { store.switchAccount() }.accessibilityIdentifier("club.gov.switchAccount") }
                                }
                            }
                    } label: { Text(LocalizedStringKey("club.gov." + operation.rawValue)) }.accessibilityIdentifier("club.gov.fixture." + operation.rawValue)
                }
                Button("club.gov.switchAccount") { store.switchAccount() }.accessibilityIdentifier("club.gov.switchAccount")
                Button("club.gov.simulateUnknown") { store.access.writeFailure = .unknown(message: nil) }.accessibilityIdentifier("club.gov.simulateUnknown")
            }.accessibilityIdentifier("club.gov.fixture.root").navigationTitle("club.gov.workspace")
        }.environment(\.clubEnrollmentProfile, store.leaderboardProfile)
    }
}
@MainActor private final class ClubGovernanceFixtureStore: ObservableObject {
    let access = ClubGovernanceFixtureAccess()
    let profileReader: ClubLeaderboardFixtureProfileReader
    let squareReader = SquareFixtureReader()
    private let leaderboardScenario: String?
    var leaderboardProfile: ClubEnrollmentProfileContext? {
        guard leaderboardScenario != "missingProfile" else { return nil }
        return .init(reader: profileReader, squareReader: squareReader)
    }
    lazy var coordinator = ClubGovernanceCoordinator(access: access)
    @Published var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let index = arguments.firstIndex(of: "--club-leaderboard-scenario")
        leaderboardScenario = index.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        profileReader = ClubLeaderboardFixtureProfileReader(holdsProfileResponses: leaderboardScenario == "heldProfile")
        profileReader.identity = .init(accountID: leaderboardScenario == "wrongProfileAccount" ? 702 : 701, epoch: 1)
        if leaderboardScenario == "missingMemberID" {
            access.overrideValue[.leaderboard] = .array([.object(["nickname": .string("Unroutable fixture member")])])
        }
        var value = ClubGovernanceFixtures.value(.topicOverview).object ?? [:]
        var chapters = value["chaptersList"]?.array ?? []
        if var chapter = chapters.first?.object {
            chapter["name"] = .string("Fixture chapter"); chapters[0] = .object(chapter)
        }
        value["chaptersList"] = .array(chapters); access.overrideValue[.topicOverview] = .object(value)
    }
    func switchAccount() {
        let replacement = ClubReadIdentity(accountID: 799, epoch: (identity?.epoch ?? 0) + 1)
        profileReader.identity = .init(accountID: replacement.accountID, epoch: replacement.epoch)
        access.identity = replacement; access.readFailure = .forbidden; coordinator.cancelReview(); identity = replacement
    }
}

/// Offline-only race fixture. A profile response captures the requesting account
/// before suspension and intentionally ignores cancellation until the UI releases
/// it. This proves retirement of an actual late success, without wall-clock races.
@MainActor @Observable private final class ClubLeaderboardFixtureProfileReader: SocialAccountReading {
    var identity = SocialAccountIdentity(accountID: 701, epoch: 1)
    let isConfigured = true
    let isOfflineExample = true
    let holdsProfileResponses: Bool
    private(set) var startedCount = 0
    private(set) var returnedCount = 0
    private(set) var returnedAccountID: Int?
    private(set) var returnedMemberID: Int?
    private struct PendingProfile {
        let response: SocialPublicProfile
        let continuation: CheckedContinuation<SocialPublicProfile, Never>
    }
    private var pending: [UUID: PendingProfile] = [:]
    var pendingCount: Int { pending.count }
    private let fallback = SocialAccountFixtureReader(.content)
    init(holdsProfileResponses: Bool) { self.holdsProfileResponses = holdsProfileResponses }
    func publicProfile(memberID: Int) async throws -> SocialPublicProfile {
        guard holdsProfileResponses else {
            fallback.identity = identity
            return try await fallback.publicProfile(memberID: memberID)
        }
        let captured = identity, requestID = UUID()
        let bytes = try JSONSerialization.data(withJSONObject: ["id": memberID,
            "nickname": "Held profile from account \(captured.accountID ?? 0)"])
        let response = try JSONDecoder().decode(SocialPublicProfile.self, from: bytes)
        startedCount += 1
        let released = await withCheckedContinuation { (continuation: CheckedContinuation<SocialPublicProfile, Never>) in
            pending[requestID] = .init(response: response, continuation: continuation)
        }
        // Do not check cancellation here: the production View must reject this
        // old response after the cancelled source task resumes successfully.
        returnedAccountID = captured.accountID; returnedMemberID = memberID; returnedCount += 1
        return released
    }
    func releasePendingProfiles() {
        let waiting = pending
        pending.removeAll()
        for request in waiting.values { request.continuation.resume(returning: request.response) }
    }
    func informationList() async throws -> [SocialInformation] {
        fallback.identity = identity; return try await fallback.informationList()
    }
    func information(id: Int) async throws -> SocialInformation {
        fallback.identity = identity; return try await fallback.information(id: id)
    }
    func invitationHistory(page: Int) async throws -> SocialInviteHistory {
        fallback.identity = identity; return try await fallback.invitationHistory(page: page)
    }
}

#endif
