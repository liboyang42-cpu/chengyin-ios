import SwiftUI

private struct MerchantCouponManagementDestinationKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> AnyView)? = nil
}
extension EnvironmentValues {
    var merchantCouponManagementDestination: (@MainActor () -> AnyView)? {
        get { self[MerchantCouponManagementDestinationKey.self] }
        set { self[MerchantCouponManagementDestinationKey.self] = newValue }
    }
}
/// Source marketing → published coupons. The parent marketing screen has already refreshed
/// merchant:marketing:read; operation-specific permissions still require fresh confirmation.
@MainActor struct SessionCouponManagementView: View {
    @EnvironmentObject private var session: AppSession
    var body: some View {
        CouponManagementView(coordinator: session.couponManagementCoordinator,
                             sessionKey: session.couponManagementSession, isSourceVisible: true)
    }
}
/// Persistent storage is fail-closed; an unavailable private directory never falls back to memory.
@MainActor final class CouponManagementAppLocks: CouponManagementLocking {
    private var backing: CouponManagementFileLocks?
    private func store() throws -> CouponManagementFileLocks {
        if let backing { return backing }
        var directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Questify/CouponManagementLocks", isDirectory: true)
        let value = try CouponManagementFileLocks(directory: directory)
        var resources = URLResourceValues(); resources.isExcludedFromBackup = true
        try directory.setResourceValues(resources)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        backing = value; return value
    }
    func pending(ownerKey: String, resource: String) throws -> CouponManagementPending? { try store().pending(ownerKey: ownerKey, resource: resource) }
    func acquire(_ pending: CouponManagementPending) throws { try store().acquire(pending) }
    func release(_ pending: CouponManagementPending) throws { try store().release(pending) }
}
