import Foundation

/// Fixed58 PLAYER /game/session/view only. Public map, personal inventory and CLUB
/// control are never authority for this WORLD_SHARED team exchange.
public struct PlaySharedPlanAmount: Codable, Equatable {
    static func validKey(_ value: String) -> Bool { value.range(of: "^[a-z][a-z0-9_]{0,31}$", options: .regularExpression) != nil }
    public let itemID: String
    public let quantity: Int
    var wire: PlayWireValue { .object(["itemId": .string(itemID), "quantity": .int(quantity)]) }
    static func read(_ raw: PlayWireValue) throws -> [Self] {
        guard let rows = raw.array, rows.count <= 200 else { throw PlayExperienceError.malformed }
        var seen = Set<String>()
        return try rows.map { row in
            guard let fields = row.object, Set(fields.keys) == ["itemId", "quantity"],
                  let id = row["itemId"].text, PlaySharedPlanAmount.validKey(id), seen.insert(id).inserted,
                  let quantity = row["quantity"].integer, (1...999).contains(quantity) else { throw PlayExperienceError.malformed }
            return Self(itemID: id, quantity: quantity)
        }
    }
}
public struct PlaySharedPlanTeamProjection: Equatable {
    public struct Item: Equatable, Identifiable {
        public let id, name: String
        public let slotCost: Int
        public let available, locked: Int?
    }
    public let activityID, sessionID, teamID, revision, authorityEpoch: Int
    public let captain, writable: Bool
    public let items: [Item]
    public let status, operationStatus, authorityMode: String
    public init(_ raw: PlayWireValue, activityID: Int) throws {
        let player = raw["player"], world = player["world"], run = player["run"]
        guard raw["perspective"].text == "PLAYER", raw["activityId"].integer == activityID, activityID > 0,
              player["scope"].text == "TEAM", player["playMode"].text == "ROUTE", player["worldMode"].text == "WORLD_SHARED",
              let session = raw["sessionId"].integer, session > 0, let team = player["teamId"].integer, team > 0,
              let revision = raw["revision"].integer, (0..<Int(Int32.max)).contains(revision),
              let epoch = player["authorityEpoch"].integer, epoch > 0, run["authorityEpoch"].integer == epoch,
              let captain = player["isCaptain"].bool, let status = raw["status"].text,
              let operation = run["operationStatus"].text, let mode = run["authorityMode"].text,
              let actions = raw["availableActions"].array, actions.allSatisfy({ $0.text != nil }),
              let naturallyCompleted = player["naturallyCompleted"].bool,
              let catalog = world["itemCatalog"].array, catalog.count <= 200,
              let materials = world["ownMaterials"].array, materials.count <= 200,
              world["locked"] == .null || world["locked"].object != nil,
              player.object != nil else { throw PlayExperienceError.malformed }
        let inventoryPublished = world["locked"].object != nil
        let locked = world["locked"].object ?? [:]
        guard inventoryPublished || materials.isEmpty else { throw PlayExperienceError.malformed }
        self.activityID = activityID; sessionID = session; teamID = team; self.revision = revision; authorityEpoch = epoch
        self.captain = captain; self.status = status; operationStatus = operation; authorityMode = mode
        writable = inventoryPublished && captain && status == "RUNNING" && operation == "RUNNING" && mode == "ONLINE"
            && run["exitedTeams"][String(team)] == .null && !naturallyCompleted && player["result"] == .null && world["result"] == .null
        var ids = Set<String>(), materialIDs = Set<String>()
        var byID: [String: (Int, Int)] = [:]
        for row in materials {
            guard let id = row["itemId"].text, PlaySharedPlanAmount.validKey(id), materialIDs.insert(id).inserted,
                  let available = row["available"].integer, available >= 0,
                  let reserved = row["locked"].integer, reserved >= 0,
                  (locked[id]?.integer ?? 0) == reserved else { throw PlayExperienceError.malformed }
            byID[id] = (available, reserved)
        }
        for (id, value) in locked {
            guard PlaySharedPlanAmount.validKey(id), let quantity = value.integer, quantity >= 0 else { throw PlayExperienceError.malformed }
        }
        items = try catalog.map { row in
            guard let id = row["id"].text, PlaySharedPlanAmount.validKey(id), ids.insert(id).inserted,
                  let name = row["name"].text, name.utf8.count <= 1024,
                  let slots = row["slotCost"].integer, slots >= 0, !inventoryPublished || byID[id] != nil else { throw PlayExperienceError.malformed }
            return Item(id: id, name: name.isEmpty ? id : name, slotCost: slots, available: byID[id]?.0, locked: byID[id]?.1)
        }
        guard (inventoryPublished ? ids == materialIDs : materialIDs.isEmpty), Set(locked.keys).isSubset(of: ids) else { throw PlayExperienceError.malformed }
    }
}
