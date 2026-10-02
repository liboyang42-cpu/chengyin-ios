import SwiftUI

/// Synthetic only: never falls back to a live transport, location provider or payment SDK.
@MainActor final class CoopFlowFixtureReader: ObservableObject, CoopFlowReading {
    @Published var session: CoopFlowSession? = try? CoopFlowSession(accountID: 101, epoch: 1, token: "synthetic-cooperation-only")
    func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON {
        if ProcessInfo.processInfo.arguments.contains("--cooperation-flow-denied") { throw CoopFlowFailure.permission }
        switch resource {
        case .finance: return .object(["topics": .array([.object(["topicId": .id(8), "topicName": .string("Synthetic organizer route"), "myIncome": .null, "settled": .bool(false), "merchantTotal": .number(20)])])])
        case .myBusiness: return .object(["credit": .object(["fulfillmentRate": .id(92), "violationCount": .id(1)]), "review": .object(["reviewCount": .id(0), "avgRating": .id(0)]), "settlements": .array([.object(["id": .id(4), "topicId": .id(8), "topicName": .string("Synthetic merchant route"), "payeeType": .string("merchant"), "amount": .number(12), "status": .id(0)])])])
        case .templates: return .array([.object(["id": .id(3), "name": .string("Synthetic perk"), "perkType": .id(0), "retailValue": .number(10), "unitCost": .null, "quota": .id(5)])])
        case .pool: return .object(["hasClub": .bool(true), "rows": .array([.object(["topicId": .id(8), "name": .string("Synthetic pool route"), "state": .string("open")])])])
        case .applications: return .array([.object(["applyId": .id(7), "topicId": .id(8), "topicName": .string("Synthetic application"), "status": .id(0)])])
        case .receivedApplications: return .array([.object(["applyId": .id(7), "topicId": .id(8), "topicName": .string("Synthetic club application"), "clubId": .id(103), "clubName": .string("Synthetic club"), "status": .id(0), "scope": .string("MERCHANT")])])
        case .registrations: return .object(["rows": .array([.object(["id": .id(6), "topicId": .id(8), "memberId": .id(102), "merchantName": .string("Synthetic merchant"), "auditStatus": .id(0)])])])
        case .invitations: return .object(["sent": .array([]), "received": .array([.object(["id": .id(2), "inviteType": .id(0), "topicId": .id(8), "fromId": .id(102), "toId": .id(101), "toType": .string("merchant"), "status": .id(0), "partner": .object(["name": .string("Synthetic partner")])])]), "slots": .object([:])])
        case .complaintTopics: return .array([.object(["topicId": .id(8), "topicName": .string("Synthetic eligible topic")])])
        case .relations: return .object(["relations": .array([]), "discovery": .object(["merchants": .array([])]), "stats": .object(["merchantCount": .id(0), "clubCount": .id(0)])])
        case .clubs, .nearby, .perks: return .array([])
        case .reviewSummary, .credit: return .object([:])
        case .depositStatus: return .object(["paymentStatus": .string("unknown")])
        }
    }
    func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement {
        let value = try await read(source == .finance ? .finance : .myBusiness)
        let rows = value[source == .finance ? "topics" : "settlements"].rows ?? []
        guard let row = rows.first(where: { $0[source == .finance ? "topicId" : "id"].integer == id }) else { throw CoopFlowFailure.unavailable }
        return CoopFlowSettlement(source: source, record: row)
    }
}
@MainActor struct CoopFlowFixtureHost: View {
    @StateObject private var reader = CoopFlowFixtureReader()
    var body: some View {
        NavigationStack {
            CooperationFlowWorkbench(reader: reader)
                .safeAreaInset(edge: .top) { Text("cooperation.offline").font(.caption).padding(8) }
                .toolbar { ToolbarItem(placement: .bottomBar) {
                    Button("coopflow.fixture.signOut") { reader.session = nil }
                        .accessibilityIdentifier("coopflow.fixture.signOut")
                } }
        }.id(reader.session == nil)
    }
}
