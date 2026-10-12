import SwiftUI

/// This adapter only narrows the existing reader to one selected customer/purpose.
/// It cannot manufacture a dispatch ticket or a device grant.
@MainActor final class MerchantSelectedContactReader: MerchantEngagementReading {
    let base: any MerchantEngagementReading
    let selection: MerchantCustomerContactSelection
    let current: () -> Bool
    init(base: any MerchantEngagementReading, selection: MerchantCustomerContactSelection, current: @escaping () -> Bool) {
        self.base = base; self.selection = selection; self.current = current
    }
    private var valid: Bool { current() && base.isConfigured && base.scope == selection.scope }
    var scope: MerchantBusinessScope? { valid ? base.scope : nil }
    var isConfigured: Bool { valid && base.isConfigured }
    var isSyntheticEnabled: Bool { valid && base.isSyntheticEnabled }
    var authorizationGeneration: UUID? { valid ? base.authorizationGeneration : nil }
    var journalRealm: String? { valid ? base.journalRealm : nil }
    private func check(_ command: MerchantEngagementCommand? = nil) throws {
        guard valid, !Task.isCancelled, command == nil || command == selection.command else { throw MerchantBusinessFailure.stale }
    }
    func canExecute(_ command: MerchantEngagementCommand, merchantID: Int) -> Bool {
        valid && command == selection.command && merchantID == selection.merchantID && base.canExecute(command, merchantID: merchantID)
    }
    func permitsDevice(_ action: MerchantEngagementDeviceGrant.Action, merchantID: Int) -> Bool {
        guard valid, merchantID == selection.merchantID, case .contact(let id, let purpose) = action,
              id == selection.customerID, purpose == selection.purpose else { return false }
        return base.permitsDevice(action, merchantID: merchantID)
    }
    func access() async throws -> MerchantEngagementAccess {
        try check(); let value = try await base.access(); try check()
        try value.require(selection.command.permissions)
        guard value.merchantID == selection.merchantID else { throw MerchantBusinessFailure.stale }
        return value
    }
    func read(_ query: MerchantEngagementQuery) async throws -> MerchantEngagementPayload { throw MerchantBusinessFailure.disabled }
    func proof(_ command: MerchantEngagementCommand) async throws -> MerchantEngagementProof {
        try check(command); let value = try await base.proof(command); try check(command)
        try value.access.require(command.permissions)
        guard value.access.merchantID == selection.merchantID else { throw MerchantBusinessFailure.stale }
        return value
    }
    func execute(_ command: MerchantEngagementCommand, requestID: String, proof: MerchantEngagementProof, scope: MerchantBusinessScope) async throws -> MerchantEngagementReceipt {
        // Never create a second dispatch path: only the existing ticketed overload is used.
        throw MerchantBusinessFailure.disabled
    }
    func execute(_ review: MerchantEngagementReview, authorization: MerchantEngagementDispatchAuthorization, check externalCheck: () throws -> Void) async throws -> MerchantEngagementReceipt {
        try check(review.command)
        guard review.proof.access.merchantID == selection.merchantID else { throw MerchantBusinessFailure.stale }
        let result = try await base.execute(review, authorization: authorization, check: {
            try self.check(review.command); try externalCheck()
        })
        try check(review.command); return result
    }
}

@MainActor extension AppSession {
    func merchantCustomerContactFlow(_ selection: MerchantCustomerContactSelection, sourceIsCurrent: @escaping () -> Bool) -> MerchantCustomerContactFlow? {
        guard selection.scope == merchantBusinessReader.scope,
              selection.authorizationGeneration == merchantBusinessReader.authorizationGeneration,
              selection.scope == merchantEngagementReader.scope, sourceIsCurrent() else { return nil }
        let revision = sessionRevision
        return MerchantCustomerContactFlow(selection: selection, reader: merchantEngagementReader,
            journal: merchantBusinessJournal, exports: merchantExportRecovery, current: {
                self.sessionRevision == revision && self.merchantBusinessReader.scope == selection.scope &&
                self.merchantBusinessReader.authorizationGeneration == selection.authorizationGeneration && sourceIsCurrent()
            })
    }
}
