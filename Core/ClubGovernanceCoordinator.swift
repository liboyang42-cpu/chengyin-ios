import Foundation

public struct ClubGovernanceReview: Identifiable, Equatable {
    public let id: UUID
    public let identity: ClubReadIdentity
    public let storageNamespace: String
    public let command: ClubGovernanceCommand
    public let snapshot: ClubGovernanceSnapshot
    public let supportingMembers: ClubGovernanceSnapshot?
    fileprivate init(identity: ClubReadIdentity, storageNamespace: String, command: ClubGovernanceCommand, snapshot: ClubGovernanceSnapshot, supportingMembers: ClubGovernanceSnapshot?) {
        id = UUID(); self.identity = identity; self.storageNamespace = storageNamespace; self.command = command; self.snapshot = snapshot; self.supportingMembers = supportingMembers
    }
}
public enum ClubGovernanceWriteState: Equatable { case idle, reviewing, preflighting, submitting, acknowledged, rejected, conflict, unknown }

/// A review owns exact values + account epoch + all target facts. Unknown writes are
/// locked by account/operation/scope even after same-account sign-out/sign-in.
@MainActor public final class ClubGovernanceCoordinator {
    private let access: any ClubGovernanceAccess
    private var review: ClubGovernanceReview?
    private var generation: UInt64 = 0
    private var busy = false
    private var locked: Set<Lock> = []
    public private(set) var state: ClubGovernanceWriteState = .idle
    struct Lock: Hashable { let accountID: Int; let storageNamespace: String; let operation: ClubGovernanceMutation; let scope: ClubGovernanceScope }
    public init(access: any ClubGovernanceAccess) { self.access = access }
    public func cancelReview() { generation &+= 1; review = nil; if !busy { state = .idle } }
    public func isLocked(_ command: ClubGovernanceCommand, identity: ClubReadIdentity) -> Bool {
        guard let accountID = identity.accountID else { return true }
        return locked.contains(.init(accountID: accountID, storageNamespace: access.storageNamespace, operation: command.operation, scope: command.scope))
    }
    public func prepare(_ command: ClubGovernanceCommand) async throws -> ClubGovernanceReview {
        guard !busy else { throw ClubGovernanceFailure.busy }
        guard let identity = access.identity, let accountID = identity.accountID else { throw ClubGovernanceFailure.signedOut }
        guard !isLocked(command, identity: identity) else { throw ClubGovernanceFailure.outcomeLocked }
        generation &+= 1; let revision = generation; let namespace = access.storageNamespace; review = nil
        let snapshot = try await access.read(command.operation.reviewRead, scope: command.scope, options: command.reviewOptions)
        try command.validateReview(snapshot, accountID: accountID)
        let members = try await memberProof(command)
        guard access.identity == identity, access.storageNamespace == namespace, generation == revision, !Task.isCancelled else { throw ClubGovernanceFailure.staleReview }
        let prepared = ClubGovernanceReview(identity: identity, storageNamespace: namespace, command: command, snapshot: snapshot, supportingMembers: members)
        review = prepared; state = .reviewing; return prepared
    }
    private func memberProof(_ command: ClubGovernanceCommand) async throws -> ClubGovernanceSnapshot? {
        guard [.createSeries, .updateSeries, .assignRole].contains(command.operation) else { return nil }
        let members = try await access.read(.members, scope: command.scope, options: [:])
        let target = command.fields[command.operation == .assignRole ? "targetMemberId" : "defaultLeadMemberId"]?.int
        guard let target, (members.value.array ?? []).contains(where: { $0["memberId"].int == target && (command.operation != .assignRole || $0["isOwner"] == .bool(false)) }) else { throw ClubGovernanceFailure.targetChanged }
        return members
    }
    public func confirm(_ pending: ClubGovernanceReview) async throws -> ClubGovernanceValue {
        guard access.allowsOfflineWrites else { throw ClubGovernanceFailure.notConfigured }
        guard !busy else { throw ClubGovernanceFailure.busy }
        guard review == pending, access.identity == pending.identity, access.storageNamespace == pending.storageNamespace, let accountID = pending.identity.accountID else { throw ClubGovernanceFailure.staleReview }
        guard !isLocked(pending.command, identity: pending.identity) else { throw ClubGovernanceFailure.outcomeLocked }
        busy = true; state = .preflighting; let revision = generation
        defer { busy = false }
        do {
            let fresh = try await access.read(pending.command.operation.reviewRead, scope: pending.command.scope, options: pending.command.reviewOptions)
            try pending.command.validateReview(fresh, accountID: accountID)
            let members = try await memberProof(pending.command)
            guard fresh == pending.snapshot, members == pending.supportingMembers, generation == revision, access.identity == pending.identity, access.storageNamespace == pending.storageNamespace, !Task.isCancelled else { throw ClubGovernanceFailure.staleReview }
        } catch { review = nil; state = .rejected; throw error }
        let lock = Lock(accountID: accountID, storageNamespace: pending.storageNamespace, operation: pending.command.operation, scope: pending.command.scope)
        locked.insert(lock); review = nil; state = .submitting
        do {
            let receipt = try await access.send(pending)
            guard access.identity == pending.identity, access.storageNamespace == pending.storageNamespace, !Task.isCancelled else { state = .unknown; throw ClubGovernanceFailure.unknown(message: nil) }
            state = .acknowledged
            // Keep the lock: no generic receipt proves reconciliation. Reads remain available.
            return receipt
        } catch {
            if let failure = error as? ClubGovernanceFailure {
                switch failure {
                case .notConfigured, .invalidRequest, .forbidden, .staleReview, .signedOut: locked.remove(lock); state = .rejected
                case .rejected: locked.remove(lock); state = .rejected
                case .conflict: locked.remove(lock); state = .conflict
                default: state = .unknown
                }
            } else { state = .unknown }
            throw error
        }
    }
}
