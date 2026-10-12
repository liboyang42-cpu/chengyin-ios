#if DEBUG
import SwiftUI
import Observation

@MainActor @Observable final class ProfileSelfOrdersFixtureSocial: SocialAccountReading {
    var identity = SocialAccountIdentity(accountID: 81, epoch: 1, role: "player")
    var presentationRevision: UInt64 = 1
    var isConfigured = true
    let isOfflineExample = true
    func publicProfile(memberID: Int) async throws -> SocialPublicProfile { throw APIError.notConfigured }
    func informationList() async throws -> [SocialInformation] { [] }
    func information(id: Int) async throws -> SocialInformation { throw APIError.notConfigured }
    func invitationHistory(page: Int) async throws -> SocialInviteHistory { throw APIError.notConfigured }
}
@MainActor @Observable final class ProfileSelfOrdersFixtureReader: ProfileReading {
    var identity: ProfileReadIdentity? = .init(accountID: 81, epoch: 1)
    var isConfigured = true
    var listReads = 0
    var detailReads = 0
    var scenario: String
    init(_ scenario: String = "content") { self.scenario = scenario }
    func profileOrders() async throws -> [ProfileOrder] {
        listReads += 1
        if scenario == "failure" && listReads == 1 { throw APIError.httpStatus(503) }
        if scenario == "refreshFailure" && listReads == 2 { throw APIError.httpStatus(503) }
        if scenario == "unauthorized" && listReads > 1 { throw APIError.unauthorized }
        if scenario == "empty" || (scenario == "becomesEmpty" && listReads > 1) { return [] }
        return try (1...10).map { try row($0) }
    }
    func profileOrder(id: Int) async throws -> ProfileOrder { detailReads += 1; return try row(id) }
    private func row(_ id: Int) throws -> ProfileOrder {
        let value: [String: Any] = ["id": id, "memberId": 81, "registrationNo": "SYNTHETIC-\(id)",
            "cmsTopic": ["name": "Synthetic order \(id)"], "createTime": "2026-10-11T12:30:00"]
        return try JSONDecoder().decode(ProfileOrder.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func profileParticipants() async throws -> [ProfileParticipant] { throw APIError.notConfigured }
    func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.notConfigured }
    func profileBadges() async throws -> ProfileBadgeWall { throw APIError.notConfigured }
}
/// Standalone component host; the ordinary public-profile mount remains a central fragment.
/// No production services, credentials, transport or read-approval construction.
@MainActor struct ProfileSelfOrdersFixtureHost: View {
    private let social: ProfileSelfOrdersFixtureSocial
    private let orders: ProfileSelfOrdersFixtureReader
    private let access: ProfileSelfOrdersAccess
    private let memberID: Int
    init(scenario: String = "content") {
        let social = ProfileSelfOrdersFixtureSocial(), orders = ProfileSelfOrdersFixtureReader(scenario)
        if scenario == "guest" { social.identity = .init(accountID: nil, epoch: 1) }
        if scenario == "unapproved" { orders.isConfigured = false }
        self.social = social; self.orders = orders
        access = .init(reader: orders, owner: social.identity)
        memberID = scenario == "other" ? 92 : 81
    }
    var body: some View {
        NavigationStack {
            List { ProfileSelfOrdersEntry(memberID: memberID, social: social, access: access) }
                .navigationTitle("Synthetic profile orders")
        }
        .safeAreaInset(edge: .bottom) {
            VStack {
                Text(verbatim: "Standalone preview; normal profile mount and production read permission are pending.")
                HStack {
                    Text(verbatim: String(orders.listReads)).accessibilityIdentifier("profile.selfOrdersFixture.listReads")
                    Text(verbatim: String(orders.detailReads)).accessibilityIdentifier("profile.selfOrdersFixture.detailReads")
                    Button("Retire account") { social.presentationRevision += 1 }
                        .accessibilityIdentifier("profile.selfOrdersFixture.retire")
                    Button("Revoke") { orders.isConfigured = false }
                        .accessibilityIdentifier("profile.selfOrdersFixture.revoke")
                }
            }.font(.caption)
        }
    }
}
#endif
