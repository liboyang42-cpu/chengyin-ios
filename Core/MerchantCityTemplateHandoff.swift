import Foundation

/// In-memory values only. A template return must not reseed or normalize the placement draft.
public struct MerchantCityTemplateLocalDraft: Equatable {
    public let fields: [String: String]
    public let templateID: Int
    public let confirmedAddress: Bool
    public let dirty: Bool
    public init(fields: [String: String], templateID: Int, confirmedAddress: Bool, dirty: Bool) {
        self.fields = fields; self.templateID = templateID; self.confirmedAddress = confirmedAddress; self.dirty = dirty
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.templateID == rhs.templateID && lhs.confirmedAddress == rhs.confirmedAddress && lhs.dirty == rhs.dirty &&
        lhs.fields.count == rhs.fields.count && lhs.fields.allSatisfy { key, value in
            guard let other = rhs.fields[key] else { return false }
            return value.utf8.elementsEqual(other.utf8)
        }
    }
}

public enum MerchantCityTemplateReturnFailure: Error, Equatable {
    case contextChanged, unavailable, missingTemplate, albumOnly, invalidMetadata, readFailed
    public var key: String {
        switch self {
        case .contextChanged: return "merchant.cityTemplate.contextChanged"
        case .unavailable: return "merchant.cityTemplate.unavailable"
        case .missingTemplate: return "merchant.cityTemplate.missingTemplate"
        case .albumOnly: return "merchant.cityTemplate.albumOnly"
        case .invalidMetadata: return "merchant.cityTemplate.invalidMetadata"
        case .readFailed: return "merchant.cityTemplate.readFailed"
        }
    }
}

public enum MerchantCityTemplateHandoff {
    /// Snapshot equality deliberately omits observedAt elsewhere; an opening does not.
    public static func sameSnapshot(_ lhs: MerchantContentSnapshot?, _ rhs: MerchantContentSnapshot?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (let lhs?, let rhs?): return lhs == rhs && lhs.observedAt == rhs.observedAt
        default: return false
        }
    }
    public static func validates(_ snapshot: MerchantContentSnapshot, scope: UUID, merchantID: Int) -> Bool {
        snapshot.query == .cityPlacement && snapshot.scope == scope && merchantID > 0 &&
        snapshot.access.merchantID == merchantID && snapshot.access.allows(.projects)
    }
    /// Must be a freshly read owned-template row. Never manufacture or append a callback row.
    public static func returnedTemplate(id: Int, snapshot: MerchantContentSnapshot, scope: UUID, merchantID: Int) throws -> MerchantContentValue {
        guard validates(snapshot, scope: scope, merchantID: merchantID) else { throw MerchantCityTemplateReturnFailure.contextChanged }
        guard id > 0, id <= 9_007_199_254_740_991, let rows = snapshot.value["templates"].array else { throw MerchantCityTemplateReturnFailure.missingTemplate }
        let matches = rows.filter { $0["id"].integer == id }
        guard matches.count == 1, let row = matches.first, row.object != nil else { throw MerchantCityTemplateReturnFailure.missingTemplate }
        let raw = row["advancedConfigJson"]
        let config: MerchantContentValue
        switch raw {
        case .null: config = .null
        case .string(let value):
            if value.isEmpty { config = .null }
            else {
                guard let parsed = try? JSONDecoder().decode(MerchantContentValue.self, from: Data(value.utf8)) else { throw MerchantCityTemplateReturnFailure.invalidMetadata }
                config = parsed
            }
        case .object: config = raw
        default: throw MerchantCityTemplateReturnFailure.invalidMetadata
        }
        // Mini's actual gate is advancedConfigJson.album.enabled (JavaScript truthiness).
        if truthy(config["album"]["enabled"]) { throw MerchantCityTemplateReturnFailure.albumOnly }
        return row
    }
    private static func truthy(_ value: MerchantContentValue) -> Bool {
        switch value {
        case .null: return false
        case .bool(let value): return value
        case .integer(let value): return value != 0
        case .decimal(let value): return value != 0
        case .string(let value): return !value.isEmpty
        case .array, .object: return true
        }
    }
}
