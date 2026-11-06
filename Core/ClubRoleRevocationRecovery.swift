import Foundation

public struct ClubRoleRevocationHistory: Identifiable {
    public var id: String { entry.requestID }
    public let entry: ClubRoleRevocationEntry
    public let receipt: ClubRoleRevocationReceipt?
}
/// Session-owned durable recovery; current role lists can never settle this historical journal.
@MainActor public final class ClubRoleRevocationRecovery {
    private let current: () -> RuntimeDependencyContext?
    private let approval: (RuntimeDependencyContext) -> ClubRoleRevocationApproval?
    private let client: ClubRoleRevocationClient
    private let journal: ClubRoleRevocationJournal
    public init(current: @escaping () -> RuntimeDependencyContext?, approval: @escaping (RuntimeDependencyContext) -> ClubRoleRevocationApproval?, client: ClubRoleRevocationClient, journal: ClubRoleRevocationJournal) {
        self.current = current; self.approval = approval; self.client = client; self.journal = journal
    }
    public func canDispatch(_ command: ClubGovernanceCommand) -> Bool {
        guard command.operation == .revokeRole, let context = current(), let issued = approval(context), issued.permits(context, scope: command.scope, writing: true) else { return false }
        return issued.productionApproval?.permits(command, context: context) == true
    }
    public func canRead(scope: ClubGovernanceScope, identity: ClubReadIdentity?) -> Bool {
        guard let context = current(), context.session.accountID == identity?.accountID, context.session.epoch == identity?.epoch else { return false }
        return approval(context)?.permits(context, scope: scope, writing: false) == true
    }
    func isLocked(_ command: ClubGovernanceCommand) -> Bool {
        guard let context = current(), let club = command.scope.clubID, let assignment = command.fields["assignmentId"]?.int else { return true }
        do { return try journal.read(context, clubID: club).contains { $0.assignmentID == assignment && $0.outcome != "NOT_SENT" } }
        catch { return true }
    }
    /// The closure remains the existing coordinator ticket -> access.send -> original factory/writer.
    func execute(_ review: ClubGovernanceReview, check: () throws -> Void, send: () async throws -> ClubGovernanceValue) async throws -> ClubGovernanceValue {
        guard canDispatch(review.command), let context = current(), let issued = approval(context) else { throw ClubGovernanceFailure.notConfigured }
        let entry = try ClubRoleRevocationEntry(review: review, context: context)
        try check(); try journal.reserve(entry, context: context)
        do {
            try check()
            guard current() == context, approval(context) == issued, canDispatch(review.command), !Task.isCancelled else { throw ClubGovernanceFailure.staleReview }
        } catch { try journal.settle(entry, outcome: "NOT_SENT", context: context); throw error }
        // From this point any failure stays UNKNOWN: neither a success message nor a missing
        // current assignment is historical evidence. Never retry the writer, including on restart.
        _ = try await send()
        try check()
        let receipt = try await client.receipt(entry, context: context)
        guard current() == context, approval(context) == issued, receipt.state == "APPLIED", !Task.isCancelled else { throw ClubGovernanceFailure.unknown(message: nil) }
        try journal.settle(entry, outcome: "APPLIED", context: context)
        return .object(["requestId": .string(receipt.requestId), "auditId": .integer(receipt.auditId!), "state": .string("APPLIED")])
    }
    public func history(scope: ClubGovernanceScope, identity: ClubReadIdentity?, access: any ClubGovernanceAccess, check: () throws -> Void) async throws -> [ClubRoleRevocationHistory] {
        guard canRead(scope: scope, identity: identity), let context = current(), let club = scope.clubID, let issued = approval(context) else { throw ClubRoleRevocationFailure.unavailable }
        try check()
        // Original current owner authority is required even when the local history is empty.
        let fresh = try await access.read(.roles, scope: scope, options: [:], check: check)
        guard fresh.permissions?.allows(ClubGovernanceRead.roles.permission, scope: scope) == true, access.identity == identity,
              current() == context, approval(context)?.sameReadAuthority(as: issued) == true else { throw ClubRoleRevocationFailure.forbidden }
        var result: [ClubRoleRevocationHistory] = []
        for entry in try journal.read(context, clubID: club) where entry.scope == scope {
            try check()
            if entry.outcome == "NOT_SENT" { result.append(.init(entry: entry, receipt: nil)); continue }
            let receipt = try await client.receipt(entry, context: context)
            try check()
            guard current() == context, approval(context)?.sameReadAuthority(as: issued) == true, access.identity == identity else { throw ClubRoleRevocationFailure.stale }
            if receipt.state == "APPLIED" { try journal.settle(entry, outcome: "APPLIED", context: context) }
            result.append(.init(entry: entry, receipt: receipt))
        }
        try check(); guard current() == context, approval(context)?.sameReadAuthority(as: issued) == true else { throw ClubRoleRevocationFailure.stale }; return result
    }
}
