import Foundation

public struct ClubGovernanceReview: Identifiable, Equatable {
    public let id: UUID
    public let identity: ClubReadIdentity
    public let storageNamespace: String
    public let journalRealm: String
    public let authorizationGeneration: UUID?
    public let command: ClubGovernanceCommand
    public let snapshot: ClubGovernanceSnapshot
    public let supportingMembers: ClubGovernanceSnapshot?
    fileprivate init(identity: ClubReadIdentity, storageNamespace: String, journalRealm: String, authorizationGeneration: UUID?, command: ClubGovernanceCommand, snapshot: ClubGovernanceSnapshot, supportingMembers: ClubGovernanceSnapshot?) {
        id = UUID(); self.identity = identity; self.storageNamespace = storageNamespace; self.journalRealm = journalRealm; self.authorizationGeneration = authorizationGeneration; self.command = command; self.snapshot = snapshot; self.supportingMembers = supportingMembers
    }
}
/// Only the retained coordinator can mint a ticket after reserving its journal.
/// Prepared reviews and public access APIs cannot manufacture or reuse one.
@MainActor public final class ClubGovernanceDispatchAuthorization {
    private let review: ClubGovernanceReview
    private var consumed = false
    private let validity: () throws -> Void
    fileprivate init(_ review: ClubGovernanceReview, check: @escaping () throws -> Void) { self.review = review; validity = check }
    func consume(_ review: ClubGovernanceReview) throws {
        guard !consumed, self.review == review else { throw ClubGovernanceFailure.staleReview }
        consumed = true; try validity()
    }
    func validate(_ command: ClubGovernanceCommand) throws {
        guard consumed, review.command == command else { throw ClubGovernanceFailure.staleReview }
        try validity()
    }
}
public enum ClubGovernanceWriteState: Equatable { case idle, reviewing, preflighting, submitting, acknowledged, rejected, conflict, unknown }

/// A review owns exact values + account epoch + all target facts. Unknown writes are
/// locked by account/operation/scope even after same-account sign-out/sign-in.
@MainActor public final class ClubGovernanceCoordinator {
    private let access: any ClubGovernanceAccess
    private let journal: (any ClubGovernanceIntentStoring)?
    /// Optional exact original-role recovery. Missing configuration keeps role writes closed.
    public let roleAssignment: ClubRoleAssignmentRecovery?
    public let roleRevocation: ClubRoleRevocationRecovery?
    private let seriesRequests: (any ClubSeriesOriginalRequestStoring)?
    private let seriesResults: ClubSeriesOriginalResultReader?
    private var review: ClubGovernanceReview?
    private var generation: UInt64 = 0
    private var busy = false
    private var locked: Set<String> = []
    public private(set) var state: ClubGovernanceWriteState = .idle
    public init(access: any ClubGovernanceAccess, journal: (any ClubGovernanceIntentStoring)? = nil,
                roleAssignment: ClubRoleAssignmentRecovery? = nil, roleRevocation: ClubRoleRevocationRecovery? = nil,
                seriesRequests: (any ClubSeriesOriginalRequestStoring)? = nil,
                seriesResults: ClubSeriesOriginalResultReader? = nil) {
        self.access = access; self.journal = journal
        self.roleAssignment = roleAssignment; self.roleRevocation = roleRevocation
        self.seriesRequests = seriesRequests; self.seriesResults = seriesResults
    }
    private func journalKey(_ command: ClubGovernanceCommand, accountID: Int, namespace: String) -> String {
        // Navigation scopes can carry unrelated IDs. They must not create another
        // replay identity for the same source entity/action.
        let keys: [String]
        switch command.operation {
        case .hostApply: keys = []
        case .saveCustomer: keys = ["clubId", "memberId"]
        case .createSeries: keys = ["clubId", "topicId"]
        case .updateSeries: keys = ["clubId", "seriesId"]
        case .cancelOccurrence, .issueGroupCode: keys = ["clubId", "activityId"]
        case .correctAttendance: keys = ["clubId", "activityId", "memberId"]
        case .ban: keys = ["clubId", "targetMemberId"]
        case .unban: keys = ["clubId", "banId"]
        case .transferOwner, .appeal, .dissolve: keys = ["clubId"]
        case .report: keys = ["clubId", "targetType", "targetId"]
        case .assignRole: keys = ["clubId", "activityId", "targetMemberId"]
        case .revokeRole: keys = ["clubId", "assignmentId"]
        case .sendNotification: keys = ["clubId", "activityId"]
        case .retryNotification: keys = ["clubId", "campaignId"]
        case .saveTopicSettings, .endTopic, .reportHours, .submitEvidence: keys = ["clubId", "topicId"]
        case .chapterRecruit, .chapterFinish: keys = ["clubId", "chapterId"]
        }
        let fields = command.scope.ids.merging(command.fields) { _, value in value }
        let target = keys.sorted().map { "\($0)=\(fields[$0]?.text ?? "")" }.joined(separator: "&")
        return "\(namespace)|\(accountID)|\(command.operation.rawValue)|\(target)"
    }
    public func canReadOriginalSeriesResult(scope: ClubGovernanceScope, identity: ClubReadIdentity?) -> Bool {
        let originalScope = ClubGovernanceScope(clubID: scope.clubID, topicID: scope.topicID)
        return seriesRequests != nil && seriesResults?.canRead(scope: originalScope, identity: identity, realm: access.journalRealm) == true
    }
    /// Reads the retained ORIGINAL, never the new form draft. All generic/typed locks remain intact.
    public func readOriginalSeriesResult(scope: ClubGovernanceScope, identity: ClubReadIdentity?,
                                         check externalCheck: () throws -> Void) async throws -> ClubSeriesOriginalResult {
        guard let identity, let account = identity.accountID, account > 0,
              let club = scope.clubID, club > 0, let topic = scope.topicID, topic > 0,
              access.identity == identity,
              canReadOriginalSeriesResult(scope: scope, identity: identity), let seriesRequests, let seriesResults else {
            throw ClubSeriesOriginalResultFailure.unavailable
        }
        let originalScope = ClubGovernanceScope(clubID: club, topicID: topic)
        let realm = access.journalRealm, namespace = access.storageNamespace, authorization = access.authorizationGeneration
        func check() throws {
            try externalCheck()
            guard access.identity == identity, access.journalRealm == realm, access.storageNamespace == namespace,
                  access.authorizationGeneration == authorization,
                  canReadOriginalSeriesResult(scope: scope, identity: identity), !Task.isCancelled else {
                throw ClubSeriesOriginalResultFailure.stale
            }
        }
        try check()
        let fresh = try await access.read(.access, scope: .init(clubID: club), options: [:], check: check)
        try check()
        guard let permissions = fresh.permissions, permissions.allows(ClubGovernanceMutation.createSeries.permission, scope: originalScope),
              permissions.roleCodes.contains("CLUB_OWNER") || permissions.roleCodes.contains("CLUB_CO_OWNER") else {
            throw ClubSeriesOriginalResultFailure.forbidden
        }
        // Same monotonic key as createSeries, independent of replacement form request IDs.
        let key = "\(realm)|\(account)|createSeries|clubId=\(club)&topicId=\(topic)"
        guard let original = try seriesRequests.read(lockKey: key, realm: realm, accountID: account) else {
            return .legacyUnknown
        }
        guard original.fields["clubId"] == .integer(club), original.fields["topicId"] == .integer(topic) else {
            throw ClubSeriesOriginalResultFailure.malformed
        }
        try check()
        let result = try await seriesResults.read(original, identity: identity, check: check)
        try check(); return result
    }
    public func canDispatch(_ command: ClubGovernanceCommand) -> Bool {
        guard access.canDispatch(command) else { return false }
        if access.allowsOfflineWrites { return true }
        if command.operation == .assignRole { return roleAssignment?.canDispatch(command) == true }
        if command.operation == .revokeRole { return roleRevocation?.canDispatch(command) == true }
        return true
    }
    public func cancelReview() { generation &+= 1; review = nil; if !busy { state = .idle } }
    public func isLocked(_ command: ClubGovernanceCommand, identity: ClubReadIdentity) -> Bool {
        guard let accountID = identity.accountID else { return true }
        if !access.allowsOfflineWrites, command.operation == .assignRole,
           roleAssignment?.isLocked(command) == true { return true }
        if !access.allowsOfflineWrites, command.operation == .revokeRole,
           roleRevocation?.isLocked(command) == true { return true }
        if locked.contains(journalKey(command, accountID: accountID, namespace: access.journalRealm)) { return true }
        do {
            if command.operation == .createSeries,
               try seriesRequests?.contains(lockKey: journalKey(command, accountID: accountID, namespace: access.journalRealm)) == true { return true }
        } catch { return true }
        do { return try journal?.contains(journalKey(command, accountID: accountID, namespace: access.journalRealm)) == true }
        catch { return true }
    }
    public func prepare(_ command: ClubGovernanceCommand) async throws -> ClubGovernanceReview {
        guard !busy else { throw ClubGovernanceFailure.busy }
        guard let identity = access.identity, let accountID = identity.accountID else { throw ClubGovernanceFailure.signedOut }
        guard !isLocked(command, identity: identity) else { throw ClubGovernanceFailure.outcomeLocked }
        generation &+= 1; let revision = generation; let namespace = access.storageNamespace; let authorization = access.authorizationGeneration; review = nil
        let snapshot = try await access.read(command.operation.reviewRead, scope: command.scope, options: command.reviewOptions)
        try command.validateReview(snapshot, accountID: accountID)
        let members = try await memberProof(command)
        guard access.identity == identity, access.storageNamespace == namespace, access.authorizationGeneration == authorization, generation == revision, !Task.isCancelled else { throw ClubGovernanceFailure.staleReview }
        let prepared = ClubGovernanceReview(identity: identity, storageNamespace: namespace, journalRealm: access.journalRealm, authorizationGeneration: authorization, command: command, snapshot: snapshot, supportingMembers: members)
        review = prepared; state = .reviewing; return prepared
    }
    private func memberProof(_ command: ClubGovernanceCommand) async throws -> ClubGovernanceSnapshot? {
        guard [.createSeries, .updateSeries, .assignRole].contains(command.operation) else { return nil }
        let members = try await access.read(.members, scope: command.scope, options: [:])
        let target = command.fields[command.operation == .assignRole ? "targetMemberId" : "defaultLeadMemberId"]?.int
        if command.operation == .createSeries, command.fields["defaultLeadMemberId"] == .null {
            // Explicit owner default: the fresh member list must still show the owner the server will resolve.
            guard (members.value.array ?? []).contains(where: { ($0["memberId"].int ?? 0) > 0 && $0["isOwner"] == .bool(true) }) else { throw ClubGovernanceFailure.targetChanged }
            return members
        }
        guard let target, (members.value.array ?? []).contains(where: { $0["memberId"].int == target && (command.operation != .assignRole || $0["isOwner"] == .bool(false)) }) else { throw ClubGovernanceFailure.targetChanged }
        return members
    }
    public func confirm(_ pending: ClubGovernanceReview) async throws -> ClubGovernanceValue {
        guard canDispatch(pending.command), access.allowsOfflineWrites || journal?.isDurable == true else { throw ClubGovernanceFailure.notConfigured }
        guard !busy else { throw ClubGovernanceFailure.busy }
        guard review == pending, access.identity == pending.identity, access.storageNamespace == pending.storageNamespace, access.authorizationGeneration == pending.authorizationGeneration, let accountID = pending.identity.accountID else { throw ClubGovernanceFailure.staleReview }
        guard !isLocked(pending.command, identity: pending.identity) else { throw ClubGovernanceFailure.outcomeLocked }
        busy = true; state = .preflighting; let revision = generation
        defer { busy = false }
        do {
            let fresh = try await access.read(pending.command.operation.reviewRead, scope: pending.command.scope, options: pending.command.reviewOptions)
            guard let permissions = fresh.permissions, permissions.allows(pending.command.operation.permission, scope: pending.command.scope) else {
                throw ClubGovernanceFailure.forbidden
            }
            try pending.command.validateReview(fresh, accountID: accountID)
            let members = try await memberProof(pending.command)
            guard fresh == pending.snapshot, members == pending.supportingMembers, generation == revision, access.identity == pending.identity, access.storageNamespace == pending.storageNamespace, access.authorizationGeneration == pending.authorizationGeneration, !Task.isCancelled else { throw ClubGovernanceFailure.staleReview }
        } catch { review = nil; state = .rejected; throw error }
        if !access.allowsOfflineWrites, pending.command.operation == .assignRole {
            guard let roleAssignment else { throw ClubGovernanceFailure.notConfigured }
            func check() throws {
                guard self.generation == revision, self.access.identity == pending.identity,
                      self.access.storageNamespace == pending.storageNamespace, self.access.journalRealm == pending.journalRealm,
                      self.access.authorizationGeneration == pending.authorizationGeneration,
                      self.canDispatch(pending.command), !Task.isCancelled else { throw ClubGovernanceFailure.staleReview }
            }
            review = nil; state = .submitting
            do {
                let result = try await roleAssignment.execute(pending, check: check) {
                    try await self.access.send(pending, authorization: ClubGovernanceDispatchAuthorization(pending, check: check), check: check)
                }
                try check(); state = .acknowledged; return result
            } catch { state = .unknown; throw error }
        }
        if !access.allowsOfflineWrites, pending.command.operation == .revokeRole {
            guard let roleRevocation else { throw ClubGovernanceFailure.notConfigured }
            func check() throws {
                guard self.generation == revision, self.access.identity == pending.identity,
                      self.access.storageNamespace == pending.storageNamespace, self.access.journalRealm == pending.journalRealm,
                      self.access.authorizationGeneration == pending.authorizationGeneration,
                      self.canDispatch(pending.command), !Task.isCancelled else { throw ClubGovernanceFailure.staleReview }
            }
            review = nil; state = .submitting
            do {
                let result = try await roleRevocation.execute(pending, check: check) {
                    try await self.access.send(pending, authorization: ClubGovernanceDispatchAuthorization(pending, check: check), check: check)
                }
                try check(); state = .acknowledged; return result
            } catch { state = .unknown; throw error }
        }
        let lock = journalKey(pending.command, accountID: accountID, namespace: pending.journalRealm)
        if !access.allowsOfflineWrites {
            guard let journal else { throw ClubGovernanceFailure.notConfigured }
            do {
                if pending.command.operation == .createSeries, let seriesRequests {
                    try seriesRequests.reserve(.init(realm: pending.journalRealm, accountID: accountID,
                        lockKey: lock, command: pending.command))
                }
                try await journal.reserve(lock)
            }
            catch { review = nil; state = .rejected; throw error }
            // Reservation can suspend. Dismissal, role/account/token changes and cancellation
            // during persistence must never be followed by a write.
            guard generation == revision, review == pending, access.identity == pending.identity,
                  access.storageNamespace == pending.storageNamespace, access.authorizationGeneration == pending.authorizationGeneration,
                  access.canDispatch(pending.command), !Task.isCancelled else { review = nil; state = .rejected; throw ClubGovernanceFailure.staleReview }
        }
        locked.insert(lock); review = nil; state = .submitting
        do {
            func check() throws {
                guard self.generation == revision, self.access.identity == pending.identity,
                      self.access.storageNamespace == pending.storageNamespace, self.access.authorizationGeneration == pending.authorizationGeneration,
                      !Task.isCancelled else { throw ClubGovernanceFailure.staleReview }
            }
            let receipt = try await access.send(pending, authorization: ClubGovernanceDispatchAuthorization(pending, check: check), check: check)
            guard access.identity == pending.identity, access.storageNamespace == pending.storageNamespace, access.authorizationGeneration == pending.authorizationGeneration, !Task.isCancelled else { state = .unknown; throw ClubGovernanceFailure.unknown(message: nil) }
            state = .acknowledged
            // Keep the lock: no generic receipt proves reconciliation. Reads remain available.
            return receipt
        } catch {
            if !access.allowsOfflineWrites { state = .unknown; throw error }
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
