import Foundation

/// Source pages/merchant/index: 客户 shows only with canReadCrm, 退款售后 only with canReadAftercare and
/// 核销与退款 (settlement) only with canReadFinance. The destination still re-checks its own access.
extension MerchantWorkbenchBusinessShortcut {
    var requiredPermission: MerchantAccess.Permission {
        switch self {
        case .customers: return .crmRead
        case .finance: return .finance
        case .aftercare: return .aftercareRead
        }
    }
    func isVisible(for access: MerchantAccess) -> Bool { access.allows(requiredPermission) }
}
