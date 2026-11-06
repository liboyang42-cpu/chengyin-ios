import Foundation

/// Reform plan v9 §14 / W07.3–W07.4. Proposed role matrix expressed in the server's existing
/// permission codes. This is a review aid and a client-side refusal check only: it never grants a
/// permission, never fills one in from a role name, and the server's scope check stays authoritative.
public enum MerchantStaffRole: String, CaseIterable, Sendable {
    case ownerAdmin = "OWNER_ADMIN"
    case productEditor = "PRODUCT_EDITOR"
    case redemptionStaff = "REDEMPTION_STAFF"
    case aftercareHandler = "AFTERCARE_HANDLER"
    case themeOperator = "THEME_OPERATOR"
    case financeReviewer = "FINANCE_REVIEWER"

    public typealias Permission = MerchantOperatorPermissionDescription
    /// Proposal (§14 table, 建议); pending review before any server preset uses it.
    public var proposedPermissions: Set<Permission> {
        switch self {
        case .ownerAdmin: return [.basicRead, .profileWrite, .projectManage, .orderRead, .financeRead, .operatorManage, .couponManage, .marketingRead, .marketingWrite]
        case .productEditor: return [.basicRead, .profileWrite, .projectManage]
        case .redemptionStaff: return [.basicRead, .verify, .verificationRead]
        case .aftercareHandler: return [.basicRead, .orderRead, .aftercareRead, .aftercareRespond, .aftercareEvidence]
        case .themeOperator: return [.basicRead, .projectManage]
        case .financeReviewer: return [.basicRead, .financeRead, .verificationRead, .aftercareRead, .aftercareDecide]
        }
    }
    /// Explicit prohibitions from §14 that a held code set must not include for this role.
    public var forbiddenPermissions: Set<Permission> {
        switch self {
        case .ownerAdmin: return []
        case .productEditor: return [.operatorManage, .financeRead, .aftercareDecide]
        case .redemptionStaff: return [.customerExport, .customerSensitiveRead, .aftercareDecide, .financeRead, .operatorManage, .profileWrite]
        case .aftercareHandler: return [.aftercareDecide, .financeRead, .operatorManage]
        case .themeOperator: return [.financeRead, .customerRead, .customerSensitiveRead, .customerExport]
        case .financeReviewer: return [.projectManage, .operatorManage]
        }
    }
}

/// One store-scoped grant (merchant_staff_scope proposal). Read from the server; not editable here.
public struct MerchantStaffScopeGrant: Equatable {
    public enum Status: String, Sendable { case active = "ACTIVE", suspended = "SUSPENDED", revoked = "REVOKED" }
    public let merchantID: String
    public let storeID: String
    public let userID: String
    public let role: MerchantStaffRole
    public let heldPermissions: Set<MerchantStaffRole.Permission>
    public let validFrom: Date
    public let validUntil: Date?
    public let status: Status
    public let version: Int
    public init(merchantID: String, storeID: String, userID: String, role: MerchantStaffRole, heldPermissions: Set<MerchantStaffRole.Permission>,
                validFrom: Date, validUntil: Date?, status: Status, version: Int) {
        self.merchantID = merchantID; self.storeID = storeID; self.userID = userID; self.role = role; self.heldPermissions = heldPermissions
        self.validFrom = validFrom; self.validUntil = validUntil; self.status = status; self.version = version
    }
}

public enum MerchantStaffScopeDecision: Equatable, Sendable {
    case allowed
    case denied(Reason)
    public enum Reason: String, Sendable { case otherMerchant, otherStore, notActive, notYetValid, expired, staleVersion, notHeld, forbiddenForRole }
}

public enum MerchantStaffScopeCheck {
    /// Both dimensions are required (RBAC category + data scope). `currentVersion` is the latest
    /// version the server reported; any older cached grant is treated as revoked.
    public static func decide(_ grant: MerchantStaffScopeGrant, permission: MerchantStaffRole.Permission, merchantID: String, storeID: String,
                              serverNow: Date, currentVersion: Int) -> MerchantStaffScopeDecision {
        guard grant.merchantID == merchantID else { return .denied(.otherMerchant) }
        guard grant.storeID == storeID else { return .denied(.otherStore) }
        guard grant.version == currentVersion else { return .denied(.staleVersion) }
        guard grant.status == .active else { return .denied(.notActive) }
        guard serverNow >= grant.validFrom else { return .denied(.notYetValid) }
        if let until = grant.validUntil, serverNow >= until { return .denied(.expired) }
        guard !grant.role.forbiddenPermissions.contains(permission) else { return .denied(.forbiddenForRole) }
        return grant.heldPermissions.contains(permission) ? .allowed : .denied(.notHeld)
    }
}

/// W07.4: preview and final redemption are separate server steps. The preview exposes only the
/// minimum line facts; the final step is one receipt per CAS, and a repeat returns the original.
public struct RedemptionPreviewReadback: Equatable, Sendable {
    public let previewID: String
    public let storeID: String
    public let itemTitle: String
    public let quantityRemaining: Int
    public let expiresAt: Date
    public init(previewID: String, storeID: String, itemTitle: String, quantityRemaining: Int, expiresAt: Date) {
        self.previewID = previewID; self.storeID = storeID; self.itemTitle = itemTitle; self.quantityRemaining = quantityRemaining; self.expiresAt = expiresAt
    }
    public func confirmable(forStore store: String, serverNow: Date) -> Bool {
        storeID == store && quantityRemaining > 0 && serverNow < expiresAt
    }
}

public enum RedemptionFinalOutcome: Equatable, Sendable {
    case redeemed(receiptID: String)
    /// Duplicate scan or retry: the original receipt, not a second redemption.
    case alreadyRedeemed(originalReceiptID: String)
    case rejected(reasonCode: String)
}

public enum RedemptionCredentialFormat {
    /// The scanned value must be an opaque short-lived credential: never a phone number, a bare
    /// order number or anything carrying customer data. A format pass is not validity.
    public static func looksOpaque(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard (16...256).contains(bytes.count) else { return false }
        let allowed = bytes.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }
        let digitsOnly = bytes.allSatisfy { (48...57).contains($0) }
        return allowed && !digitsOnly
    }
}
