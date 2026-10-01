#if DEBUG
import SwiftUI

/// Explicit offline harness. Never selected by release code and never issues HTTP requests.
enum ProfileFixtureScenario: String {
    case success, empty, error, partial, unauthorized, unconfigured
}

@MainActor
final class ProfileFixtureReader: ProfileReading {
    let scenario: ProfileFixtureScenario
    var isConfigured: Bool { scenario != .unconfigured }
    var identity: ProfileReadIdentity? {
        scenario == .unauthorized ? nil : ProfileReadIdentity(accountID: 9001, epoch: 1)
    }
    init(_ scenario: ProfileFixtureScenario) { self.scenario = scenario }
    private func prepare() async throws {
        try Task.checkCancellation()
        if scenario == .error { throw ProfileReadFailure(code: 503, message: "Synthetic service error") }
        if scenario == .unauthorized { throw APIError.unauthorized }
        if scenario == .unconfigured { throw APIError.notConfigured }
    }
    private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
    func profileOrders() async throws -> [ProfileOrder] {
        try await prepare()
        if scenario == .empty { return [] }
        return try decode([ProfileOrder].self, #"[{"id":901,"ownerType":2,"registrationNo":"FIXTURE-901","registrationStatus":1,"cmsActivity":{"name":"Fixture city walk","startDate":"2026-10-03 10:00:00","addressName":"Fixture meeting point"},"payableAmount":12.5},{"id":902,"ownerType":1,"registrationStatus":99,"cmsTopic":{"name":"Fixture route with unknown price"}}]"#)
    }
    func profileOrder(id: Int) async throws -> ProfileOrder {
        try await prepare()
        guard id == 901 || id == 902 else { throw APIError.invalidRequest }
        if id == 902 { return try decode(ProfileOrder.self, #"{"id":902,"ownerType":1,"registrationStatus":99,"cmsTopic":{"name":"Fixture route with unknown price"}}"#) }
        return try decode(ProfileOrder.self, #"{"id":901,"ownerType":2,"registrationNo":"FIXTURE-901","registrationStatus":1,"cmsActivity":{"name":"Fixture city walk","startDate":"2026-10-03 10:00:00","addressName":"Fixture meeting point"},"payableAmount":12.5,"realName":"Fixture Person","phone":"000****0000","ticketName":"Fixture ticket","orderNum":1,"createTime":"2026-10-01 10:00:00"}"#)
    }
    func profileParticipants() async throws -> [ProfileParticipant] {
        try await prepare()
        if scenario == .empty { return [] }
        return try decode([ProfileParticipant].self, #"[{"id":911,"fullName":"Fixture Person","mobilePhone":"00000000000"}]"#)
    }
    func profileParticipant(id: Int) async throws -> ProfileParticipant {
        try await prepare()
        guard id == 911 else { throw APIError.invalidRequest }
        return try decode(ProfileParticipant.self, #"{"id":911,"fullName":"Fixture Person","mobilePhone":"00000000000","province":"Fixture region","detailAddress":"Fixture street"}"#)
    }
    func profileBadges() async throws -> ProfileBadgeWall {
        try await prepare()
        if scenario == .empty { return ProfileBadgeWall(identities: [], medals: []) }
        let identities = try decode([ProfileIdentityBadge].self, #"[{"badgeCode":"FIXTURE-ID","badgeName":"Fixture identity","category":"EXPLORE","statement":"Synthetic identity card","unlockHint":"Synthetic unlock condition","unlocked":false}]"#)
        if scenario == .partial { return ProfileBadgeWall(identities: identities, medals: nil, medalFailureMessage: "Synthetic medals unavailable") }
        let medals = try decode([ProfileMedal].self, #"[{"templateId":921,"medalName":"Fixture city medal","condition":"Synthetic city condition","getTime":"2026-10-01 10:00:00"},{"templateId":922,"kind":"achievement","medalName":"Fixture achievement","getTime":"2026-10-01 10:00:00"}]"#)
        return ProfileBadgeWall(identities: identities, medals: medals)
    }
}

@MainActor
struct ProfileFixtureHostView: View {
    private let reader: ProfileFixtureReader
    init(scenario: ProfileFixtureScenario = .success) { reader = ProfileFixtureReader(scenario) }
    var body: some View {
        NavigationStack {
            Form { ProfileAccountLinks(reader: reader) }
                .navigationTitle("account.title")
        }
    }
}
#endif
