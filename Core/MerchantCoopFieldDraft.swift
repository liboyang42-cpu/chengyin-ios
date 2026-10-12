import Foundation

public enum MerchantCoopField: String, CaseIterable {
    case capacity, availableTime, demand
    public var titleKey: String { "merchant.operations." + rawValue }
    public var limit: Int { self == .demand ? 500 : 100 }
    public func value(in settings: MerchantCoopSettings) -> String {
        switch self { case .capacity: return settings.capacity; case .availableTime: return settings.availableTime; case .demand: return settings.demand }
    }
}

/// Field buffer only. Full-form review, charge choice and write policy remain with the existing draft.
public struct MerchantCoopFieldDraft: Equatable {
    public let field: MerchantCoopField
    public let original: String
    public var value: String
    public init(field: MerchantCoopField, settings: MerchantCoopSettings) {
        self.field = field; original = field.value(in: settings); value = original
    }
    public var isDirty: Bool { !value.utf8.elementsEqual(original.utf8) }
    public var issueKey: String? {
        // Do not normalize or silently truncate historical values on open or no-op apply.
        guard isDirty else { return nil }
        if value.utf16.count > field.limit { return field == .demand ? "merchant.coopField.limit500" : "merchant.coopField.limit100" }
        if field == .capacity, !value.isEmpty,
           (!value.utf8.allSatisfy({ (48...57).contains($0) }) || Int(value) == nil) {
            return "merchant.operations.capacityInvalid"
        }
        return nil
    }
    public func applying(to settings: MerchantCoopSettings) throws -> MerchantCoopSettings {
        guard field.value(in: settings).utf8.elementsEqual(original.utf8), issueKey == nil else { throw APIError.invalidRequest }
        guard isDirty else { return settings }
        var result = settings
        switch field { case .capacity: result.capacity = value; case .availableTime: result.availableTime = value; case .demand: result.demand = value }
        return result
    }
    public static func sameValues(_ a: MerchantCoopSettings, _ b: MerchantCoopSettings) -> Bool {
        a.capacity.utf8.elementsEqual(b.capacity.utf8)
            && a.availableTime.utf8.elementsEqual(b.availableTime.utf8)
            && a.demand.utf8.elementsEqual(b.demand.utf8)
            && a.suitActivityTypes.map({ Data($0.utf8) }) == b.suitActivityTypes.map({ Data($0.utf8) })
            && a.chargeType == b.chargeType && a.coopOpen == b.coopOpen && a.clearsCapacity == b.clearsCapacity
    }
}
