#if DEBUG
import SwiftUI

@MainActor final class MerchantBusinessFixtureReader: MerchantBusinessReading {
    enum Scenario: String { case ready, denied, malformed, unknown, changedSession, disabled, listTools }
    let scenario: Scenario
    var scope: MerchantBusinessScope? = .init(realm: "synthetic://merchant-business", accountID: 99001, epoch: 1)
    let isConfigured = true
    let isOfflineExample = true
    var canExecuteSyntheticMutation: Bool { scenario != .disabled }
    init(scenario: Scenario) { self.scenario = scenario }
    func access() async throws -> MerchantBusinessAccess {
        guard scope != nil else { throw APIError.unauthorized }
        if scenario == .denied { throw MerchantBusinessFailure.denied }
        return try .init(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object!)
    }
    func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
        if scenario == .malformed { throw MerchantBusinessFailure.malformed }
        let grant = try await access()
        let payload = try scenario == .listTools ? MerchantBusinessSyntheticFixtures.listToolsPayload(query) : MerchantBusinessSyntheticFixtures.payload(query)
        return try .init(access: grant, document: .init(query: query, payload: payload), roles: .init(query: .roles, payload: MerchantBusinessSyntheticFixtures.payload(.roles)))
    }
    func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt {
        if scenario == .unknown { throw URLError(.timedOut) }
        if scenario == .changedSession { self.scope = nil; throw MerchantBusinessFailure.stale }
        let data: MerchantBusinessValue
        switch mutation {
        case .aftercare(let id, let decision, _, _): data = .object(["id": .int(62099), "refundId": .int(id.rawValue), "decision": .string(decision.rawValue), "processing": .string("WAITING_PLATFORM_REVIEW"), "merchantOpinion": .string(decision == .agree ? "AGREE" : decision == .reject ? "REJECT" : "PENDING"), "refunded": .bool(false)])
        case .review(let id, let version, let action, _):
            data = .object(["reviewId": .int(id.rawValue), "version": .int(version + 1), "status": .string(action == .report ? "PENDING_PLATFORM_REVIEW" : "VISIBLE"), "auditTaskId": action == .report ? .int(63999) : .null, "replayed": .bool(false)])
        case .inviteOperator(let role):
            data = .object(["invite": .object(["id": .int(68002), "roleCode": .string(role), "status": .string("PENDING"), "expiresAt": .string("2026-10-08 09:00:00"), "version": .int(0)]), "token": .string("synthetic-invitation-token-only")])
        case .operatorRole(let id, let version, let role):
            data = .object(["id": .int(id.rawValue), "roleCode": .string(role), "status": .string("ACTIVE"), "acceptedAt": .string("2026-09-01 09:00:00"), "version": .int(version + 1), "mutationState": .string("EXACT_RESULT")])
        case .removeOperator(let id, let version, _):
            data = .object(["id": .int(id.rawValue), "roleCode": .string("MERCHANT_CHECKIN"), "status": .string("REVOKED"), "acceptedAt": .string("2026-09-01 09:00:00"), "version": .int(version + 1), "mutationState": .string("EXACT_RESULT")])
        case .revokeInvite(let id, let version, _):
            data = .object(["id": .int(id.rawValue), "roleCode": .string("MERCHANT_MARKETING"), "status": .string("REVOKED"), "expiresAt": .string("2026-10-08 09:00:00"), "version": .int(version + 1), "mutationState": .string("EXACT_RESULT")])
        default: data = .object(["exampleOnly": .bool(true)])
        }
        return try .init(mutation: mutation, message: nil, data: data)
    }
}
@MainActor struct MerchantBusinessFixtureHostView: View {
    private let reader: MerchantBusinessFixtureReader
    private let journal: MerchantBusinessMemoryIntentStore
    @State private var revision = 0
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let index = arguments.firstIndex(of: "--uitesting-merchant-business-scenario")
        let name = index.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        reader = .init(scenario: name.flatMap(MerchantBusinessFixtureReader.Scenario.init(rawValue:)) ?? .ready)
        journal = .init()
    }
    var body: some View {
        VStack {
            if reader.scenario == .changedSession {
                Button("merchant.business.fixtureSignOut") { reader.scope = nil; revision += 1 }.accessibilityIdentifier("merchant.business.fixtureSignOut")
            }
            NavigationStack { MerchantBusinessHomeView(reader: reader, journal: journal) }.id(revision)
        }
    }
}
#endif
