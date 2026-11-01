import Foundation

/// RPG/party roster projection. Reuses `PlayPlayerTeamState` / `PlayAdvancedTeamProjection`
/// instead of cloning a second member type. A dedicated party endpoint is not in the
/// current public iOS clients; absence is `WAITING_SOURCE`. A malformed roster is
/// `UNKNOWN`, not an empty success roster.
public struct PartyRosterProjection: Equatable {
    public let availability: WorldFactAvailability
    public let team: PlayPlayerTeamState?
    public let advanced: PlayAdvancedTeamProjection?
    public static let waitingSource = PartyRosterProjection(availability: .waitingSource, team: nil, advanced: nil)
    public static let unknown = PartyRosterProjection(availability: .unknown, team: nil, advanced: nil)
    public init(availability: WorldFactAvailability, team: PlayPlayerTeamState?, advanced: PlayAdvancedTeamProjection?) {
        self.availability = availability; self.team = team; self.advanced = advanced
    }
    public static func read(teamActions: PlayWireValue) -> Self {
        switch PlayPlayerTeamState.read(teamActions) {
        case .unconfirmed: return .unknown
        case .empty: return .init(availability: .ready, team: .empty, advanced: nil)
        case .members(let rows): return .init(availability: .ready, team: .members(rows), advanced: nil)
        }
    }
    public static func read(party: PlayWireValue) -> Self {
        if party == .null { return .waitingSource }
        if let rows = party["members"].array { return read(teamActions: .array(rows)) }
        if party.array != nil { return read(teamActions: party) }
        return .unknown
    }
    public static func read(advanced state: PlayAdvancedState, actorID: Int) -> Self {
        guard let projection = PlayAdvancedTeamProjection(state: state, actorID: actorID) else { return .unknown }
        return .init(availability: .ready, team: nil, advanced: projection)
    }
    public var members: [PlayPlayerTeamMember] {
        if case .members(let rows) = team { return rows }
        return []
    }
}

/// Equipped/inventory rows only when the signed wire names them. Missing inventory
/// APIs stay `WAITING_SOURCE`; client loadouts are never invented.
public struct WorldEquipmentProjection: Equatable {
    public struct Item: Equatable, Identifiable {
        public let id: String
        public let quantity: Int?
        public let expiry: EnvironmentExpiryClock
    }
    public let availability: WorldFactAvailability
    public let items: [Item]
    public static let waitingSource = WorldEquipmentProjection(availability: .waitingSource, items: [])
    public static let unknown = WorldEquipmentProjection(availability: .unknown, items: [])
    public init(availability: WorldFactAvailability, items: [Item]) {
        self.availability = availability; self.items = items
    }
    public static func read(_ raw: PlayWireValue) -> Self {
        let node = raw["equipment"] != .null ? raw["equipment"]
            : raw["equipped"] != .null ? raw["equipped"]
            : raw["inventory"] != .null ? raw["inventory"]
            : raw["rpg"]["equipment"] != .null ? raw["rpg"]["equipment"]
            : raw["rpg"]["inventory"] != .null ? raw["rpg"]["inventory"]
            : nil
        guard let node else { return .waitingSource }
        if let object = node.object {
            var items: [Item] = []; var ids = Set<String>()
            for (key, value) in object.sorted(by: { $0.key < $1.key }) {
                guard !key.isEmpty, key.utf16.count <= 64, ids.insert(key).inserted else { return .unknown }
                let quantity: Int?
                let expiry: EnvironmentExpiryClock
                if let fields = value.object {
                    quantity = fields["quantity"]?.integer ?? fields["count"]?.integer
                    expiry = EnvironmentExpiryClock.read(.object(fields))
                } else if let count = value.integer, count >= 0 {
                    quantity = count; expiry = .waitingSource
                } else { return .unknown }
                items.append(.init(id: key, quantity: quantity, expiry: expiry))
            }
            return .init(availability: .ready, items: items)
        }
        guard let rows = node.array else { return .unknown }
        var items: [Item] = []; var ids = Set<String>()
        for row in rows {
            let id = row["id"].text ?? row["itemId"].text ?? row.text
            guard let id, !id.isEmpty, id.utf16.count <= 64, ids.insert(id).inserted else { return .unknown }
            let quantity = row["quantity"].integer ?? row["count"].integer
            items.append(.init(id: id, quantity: quantity, expiry: EnvironmentExpiryClock.read(row)))
        }
        return .init(availability: .ready, items: items)
    }
}
