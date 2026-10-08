import Foundation

/// Labels only for exact server-supplied codes. This is not an authorization policy
/// and never fills in permissions from a role name or a locally assumed preset.
public enum MerchantOperatorPermissionDescription: String, CaseIterable, Equatable {
    case basicRead = "merchant:basic:read"
    case profileWrite = "merchant:profile:write"
    case projectManage = "merchant:project:manage"
    case verify = "merchant:verify"
    case verificationRead = "merchant:verify:record:read"
    case orderRead = "merchant:order:read"
    case customerRead = "merchant:crm:read"
    case customerSensitiveRead = "merchant:crm:sensitive:read"
    case customerSegment = "merchant:crm:segment"
    case customerExport = "merchant:crm:export"
    case financeRead = "merchant:finance:read"
    case aftercareRead = "merchant:aftercare:read"
    case aftercareRespond = "merchant:aftercare:respond"
    case aftercareDecide = "merchant:aftercare:decide"
    case aftercareEvidence = "merchant:aftercare:evidence"
    case marketingRead = "merchant:marketing:read"
    case marketingWrite = "merchant:marketing:write"
    case couponManage = "merchant:coupon:manage"
    case cooperationManage = "merchant:coop:manage"
    case operatorManage = "merchant:operator:manage"

    public var titleKey: String { localizationPrefix + ".title" }
    public var detailKey: String { localizationPrefix + ".detail" }
    private var localizationPrefix: String {
        "merchant.operatorRole.permission." + String(rawValue.dropFirst("merchant:".count)).replacingOccurrences(of: ":", with: ".")
    }
}

/// Ephemeral presentation of the selected validated role record. The original
/// record, picker selection, request and frozen confirmation remain untouched.
public struct MerchantOperatorRolePresentation: Equatable {
    public struct Entry: Equatable, Identifiable {
        public let code: String
        public let description: MerchantOperatorPermissionDescription?
        public var id: String { code }
        public var titleKey: String { description?.titleKey ?? "merchant.operatorRole.unknown.title" }
        public var detailKey: String { description?.detailKey ?? "merchant.operatorRole.unknown.detail" }
    }
    public let roleCode: String
    public let entries: [Entry]

    public init(record: MerchantBusinessRecord) throws {
        guard record.kind == .role else { throw MerchantBusinessFailure.malformed }
        roleCode = record.id
        let codes = try record.fields.mbStrings("permissions")
        var seen: Set<String> = []
        // Collapse duplicate labels, preserving server order and exact spelling.
        // Never trim, case-fold or expand a wildcard into a recognized permission.
        entries = codes.filter { seen.insert($0).inserted }.map {
            Entry(code: $0, description: MerchantOperatorPermissionDescription(rawValue: $0))
        }
    }
}
