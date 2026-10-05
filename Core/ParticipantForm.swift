import Foundation

/// The participant form edits only these two visible fields. Hidden address/default
/// metadata comes from a fresh /info read, never from an empty or list-only draft.
/// This value contains personal information: keep it in memory, never log or persist it.
public struct ParticipantFormDraft: Equatable {
    public let id: Int?
    public var fullName: String
    public var mobilePhone: String
    public let province: String?
    public let detailAddress: String?
    public let isDefault: Bool

    public init() {
        id = nil; fullName = ""; mobilePhone = ""
        province = nil; detailAddress = nil; isDefault = false
    }

    public init(detail: ProfileParticipant) {
        id = detail.id; fullName = detail.fullName; mobilePhone = detail.mobilePhone
        province = detail.province; detailAddress = detail.detailAddress
        isDefault = detail.isDefault
    }

    public var validation: ParticipantFormValidation? {
        if fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .nameRequired }
        let phone = mobilePhone.trimmingCharacters(in: .whitespacesAndNewlines)
        // Current mini form-state.js and address/action require ^1[3-9]\d{9}$,
        // not the older Flutter-only ^1\d{10}$ rule. Never reconstruct masked digits.
        let bytes = Array(phone.utf8)
        if bytes.count != 11 || bytes.first != 49 || !(51...57).contains(bytes[1])
            || !bytes.allSatisfy({ (48...57).contains($0) }) {
            return .invalidPhone
        }
        return nil
    }

    /// Mirrors AddressEditPage -> AddressApi.save, including hidden metadata and the
    /// source's trim/omit-empty behavior. There are no invented city/area/address keys.
    public func fields() throws -> [String: String] {
        guard validation == nil, id == nil || id! > 0 else { throw APIError.invalidRequest }
        var result = ["fullName": fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                      "mobilePhone": mobilePhone.trimmingCharacters(in: .whitespacesAndNewlines),
                      "isDefault": isDefault ? "1" : "0"]
        if let id { result["id"] = String(id) }
        for (key, value) in [("province", province), ("detailAddress", detailAddress)] {
            if let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                result[key] = value
            }
        }
        return result
    }
}

public enum ParticipantFormValidation: Equatable { case nameRequired, invalidPhone }

public enum ParticipantMutation: Equatable {
    case save(ParticipantFormDraft)
    case delete(id: Int)
    /// Source capability only; participant screens intentionally have no default control.
    case setDefault(id: Int)

    public var recordID: Int? {
        switch self {
        case .save(let draft): return draft.id
        case .delete(let id), .setDefault(let id): return id
        }
    }

    var path: String {
        switch self {
        case .save: return "api/user/address/action"
        case .delete: return "api/user/address/delete"
        case .setDefault: return "api/user/address/setDefault"
        }
    }

    public func fields() throws -> [String: String] {
        switch self {
        case .save(let draft): return try draft.fields()
        case .delete(let id):
            guard id > 0 else { throw APIError.invalidRequest }
            return ["id": String(id)]
        case .setDefault(let id):
            guard id > 0 else { throw APIError.invalidRequest }
            // AddressApi's contract differs from ParticipantApi's older id-only wrapper.
            return ["id": String(id), "isDefault": "1"]
        }
    }
}
