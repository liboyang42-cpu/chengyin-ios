#if DEBUG
import SwiftUI

enum ParticipantFixtureScenario: String {
    case success, empty, loadError, rejection, timeoutAfterSave, unauthorized, unconfigured
}

/// Synthetic memory-only store. It has no configuration, transport, credential or network
/// path. Timeout-after-save deliberately mutates the fake row then loses the response.
@MainActor
final class ParticipantFixtureStore: ProfileReading, ParticipantWriting {
    let scenario: ParticipantFixtureScenario
    var isConfigured: Bool { scenario != .unconfigured }
    var identity: ProfileReadIdentity? {
        scenario == .unauthorized ? nil : .init(accountID: 9001, epoch: 1)
    }
    private var rows: [ProfileParticipant]
    init(_ scenario: ParticipantFixtureScenario) {
        self.scenario = scenario
        rows = (try? JSONDecoder().decode([ProfileParticipant].self, from: Data(#"[{"id":911,"fullName":"Fixture Person","mobilePhone":"13800000000","province":"Fixture Region","detailAddress":"Fixture Street","isDefault":true}]"#.utf8))) ?? []
        if scenario == .empty { rows = [] }
    }
    func profileParticipants() async throws -> [ProfileParticipant] {
        try prepareRead(); return rows
    }
    func profileParticipant(id: Int) async throws -> ProfileParticipant {
        try prepareRead()
        guard let row = rows.first(where: { $0.id == id }) else {
            throw ProfileReadFailure(code: 403, message: "Synthetic record unavailable")
        }
        return row
    }
    private func prepareRead() throws {
        if !isConfigured { throw APIError.notConfigured }
        if identity == nil { throw APIError.unauthorized }
        if scenario == .loadError { throw ProfileReadFailure(code: 503, message: "Synthetic load failure") }
    }
    func perform(_ mutation: ParticipantMutation, expectedIdentity: ProfileReadIdentity) async throws {
        guard isConfigured, expectedIdentity == identity else { throw ParticipantWriteError.notSent(.unauthorized) }
        if scenario == .rejection {
            throw ParticipantWriteError.rejected(.init(code: 403, message: "Synthetic save rejection"))
        }
        switch mutation {
        case .save(let draft):
            let id = draft.id ?? ((rows.map(\.id).max() ?? 910) + 1)
            if let existing = draft.id, !rows.contains(where: { $0.id == existing }) {
                throw ParticipantWriteError.rejected(.init(code: 403, message: "Synthetic record unavailable"))
            }
            var fields: [String: Any] = try draft.fields()
            fields["id"] = id
            let value = try JSONDecoder().decode(ProfileParticipant.self, from: JSONSerialization.data(withJSONObject: fields))
            rows.removeAll { $0.id == id }; rows.append(value)
        case .delete(let id): rows.removeAll { $0.id == id }
        case .setDefault(let id):
            guard rows.contains(where: { $0.id == id }) else {
                throw ParticipantWriteError.rejected(.init(code: 403, message: "Synthetic record unavailable"))
            }
            rows = try rows.map { row in
                var fields: [String: Any] = ["id": row.id, "fullName": row.fullName,
                                            "mobilePhone": row.mobilePhone, "isDefault": row.id == id]
                fields["province"] = row.province; fields["detailAddress"] = row.detailAddress
                return try JSONDecoder().decode(ProfileParticipant.self, from: JSONSerialization.data(withJSONObject: fields))
            }
        }
        if scenario == .timeoutAfterSave { throw ParticipantWriteError.outcomeUnknown(.transport) }
    }
    func profileOrders() async throws -> [ProfileOrder] { [] }
    func profileOrder(id: Int) async throws -> ProfileOrder { throw APIError.invalidRequest }
    func profileBadges() async throws -> ProfileBadgeWall { .init(identities: [], medals: []) }
}

@MainActor
private final class ParticipantFixtureModel: ObservableObject {
    let store: ParticipantFixtureStore
    let coordinator: ParticipantMutationCoordinator
    init(scenario: ParticipantFixtureScenario) {
        let store = ParticipantFixtureStore(scenario)
        self.store = store
        coordinator = ParticipantMutationCoordinator(writer: store, reader: store)
    }
}

@MainActor
struct ParticipantFixtureHostView: View {
    @StateObject private var model: ParticipantFixtureModel
    init(scenario: ParticipantFixtureScenario = .success) {
        _model = StateObject(wrappedValue: ParticipantFixtureModel(scenario: scenario))
    }
    var body: some View {
        NavigationStack { ProfileParticipantsView(reader: model.store, coordinator: model.coordinator) }
    }
}

#Preview("Participant forms · offline") { ParticipantFixtureHostView() }
#Preview("Participant timeout · offline") { ParticipantFixtureHostView(scenario: .timeoutAfterSave) }
#endif
