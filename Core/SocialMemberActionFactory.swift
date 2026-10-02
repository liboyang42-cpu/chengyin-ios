import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Member actions are separate from both Square ID domains. No post/comment command
/// can acquire a grant through this factory, even if it happens to use the same integer.
public enum SocialMemberActionOperation: String, CaseIterable {
    case follow, startChat
    var path: String { self == .follow ? "api/user/follow/action" : "api/im/start" }
    var paths: Set<String> {
        var result: Set<String> = [path, "api/user/public-info"]
        if self == .startChat { result.insert("api/im/conversations") }
        return result
    }
    init?(_ command: SocialActionCommand) {
        switch command { case .toggleFollow: self = .follow; case .startChat: self = .startChat; default: return nil }
    }
}

/// One reviewed operation, member, account/session, CN deployment and expiry. An API
/// origin alone, an Info.plist switch or a grant for a different action is insufficient.
public struct SocialMemberActionApproval: Equatable {
    public let endpoint: OperationEndpointApproval
    public let identity: SocialAccountIdentity
    public let market: RegionalMarket
    public let operation: SocialMemberActionOperation
    public let memberID: Int
    public let expiresAt: Date
    public init(endpoint: OperationEndpointApproval, identity: SocialAccountIdentity, market: RegionalMarket,
                operation: SocialMemberActionOperation, memberID: Int, expiresAt: Date) throws {
        guard market == .china, endpoint.accountID == identity.accountID, identity.accountID != memberID,
              identity.role?.isEmpty == false, memberID > 0, endpoint.paths == operation.paths,
              expiresAt.timeIntervalSince1970.isFinite else { throw APIError.invalidConfiguration }
        self.endpoint = endpoint; self.identity = identity; self.market = market
        self.operation = operation; self.memberID = memberID; self.expiresAt = expiresAt
    }
    func matches(_ context: RuntimeDependencyContext, now: Date) -> Bool {
        context.market == market && context.baseURL == endpoint.baseURL &&
        context.session.namespace == endpoint.namespace && context.session.accountID == identity.accountID &&
        context.session.epoch == identity.epoch && context.role == identity.role && now < expiresAt
    }
}

@MainActor public enum SocialMemberActionFactory {
    /// The normal composition uses this same path. Tests inject only the transport and
    /// session source; there is no synthetic receipt or alternate successful writer.
    public static func make(configuration: APIConfiguration?, approvals: [SocialMemberActionApproval] = [],
                            transport: any HTTPTransport, journal: any OperationPendingJournal,
                            reader: any SquareReading, accountReader: any SocialAccountReading,
                            current: @escaping () -> RuntimeDependencyContext?,
                            now: @escaping () -> Date = Date.init) -> any SocialActionAccess {
        SocialMemberActionAccess(configuration: configuration, approvals: approvals, transport: transport,
            journal: journal, fallback: SocialDisabledActionAccess(reader: reader, accountReader: accountReader),
            current: current, now: now)
    }
}

@MainActor private final class SocialMemberActionAccess: SocialActionAccess {
    private let configuration: APIConfiguration?
    private let approvals: [SocialMemberActionApproval]
    private let transport: any HTTPTransport
    private let journal: any OperationPendingJournal
    private let fallback: SocialDisabledActionAccess
    private let current: () -> RuntimeDependencyContext?
    private let now: () -> Date
    var identity: SocialAccountIdentity { fallback.identity }
    var availability: SocialActionAvailability {
        approvals.contains { valid($0) } ? .approved : .disabled
    }
    init(configuration: APIConfiguration?, approvals: [SocialMemberActionApproval], transport: any HTTPTransport,
         journal: any OperationPendingJournal, fallback: SocialDisabledActionAccess,
         current: @escaping () -> RuntimeDependencyContext?, now: @escaping () -> Date) {
        self.configuration = configuration; self.approvals = approvals; self.transport = transport
        self.journal = journal; self.fallback = fallback; self.current = current; self.now = now
    }
    private func valid(_ approval: SocialMemberActionApproval) -> Bool {
        guard let configuration, let context = current() else { return false }
        return configuration.baseURL == approval.endpoint.baseURL && approval.identity == identity && approval.matches(context, now: now())
    }
    private func approval(_ command: SocialActionCommand, target: SocialActionTarget) -> SocialMemberActionApproval? {
        guard let operation = SocialMemberActionOperation(command), let member = target.memberID else { return nil }
        let matches = approvals.filter { $0.operation == operation && $0.memberID == member && valid($0) }
        // Ambiguous deployment configuration is not authorization.
        return matches.count == 1 ? matches[0] : nil
    }
    func availability(for command: SocialActionCommand, target: SocialActionTarget) -> SocialActionAvailability {
        approval(command, target: target) == nil ? .disabled : .approved
    }
    private func owner(_ context: RuntimeDependencyContext) -> String {
        // Epoch/role/token intentionally excluded so a relogin cannot erase an uncertain write.
        let parts = ["social-member-v1", context.market.rawValue, context.baseURL.absoluteString,
                     context.session.namespace, String(context.session.accountID)]
        return parts.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
    }
    private func target(_ memberID: Int) -> String { "member|\(memberID)" }
    func hasPending(target: SocialActionTarget) -> Bool {
        guard let member = target.memberID, let context = current(), context.session.accountID == identity.accountID else { return false }
        do { return try journal.pending(ownerKey: owner(context), targetKey: self.target(member)) != nil }
        catch { return true } // Corrupt/unreadable persistence cannot authorize a retry.
    }
    private func fence(_ context: RuntimeDependencyContext, approval: SocialMemberActionApproval,
                       isCurrent: () -> Bool = { true }) throws {
        try Task.checkCancellation()
        guard current() == context, valid(approval), isCurrent() else { throw SocialActionBlock.cancelled }
    }
    private func profile(_ member: Int, context: RuntimeDependencyContext, approval: SocialMemberActionApproval,
                         isCurrent: @escaping () -> Bool = { true }) async throws -> SocialPublicProfile {
        guard let configuration else { throw SocialActionBlock.disabled }
        try fence(context, approval: approval, isCurrent: isCurrent)
        let guarded = guardedTransport(context, approval: approval, isCurrent: isCurrent)
        let result = try await SocialAccountService(configuration: configuration, transport: guarded)
            .profile(memberID: member, token: context.session.token)
        try fence(context, approval: approval, isCurrent: isCurrent)
        return result
    }
    private func guardedTransport(_ context: RuntimeDependencyContext, approval: SocialMemberActionApproval,
                                  isCurrent: @escaping () -> Bool = { true }) -> any HTTPTransport {
        SocialMemberActionGuardedTransport(transport: transport, approval: approval, context: context) { [weak self] in
            guard let self else { throw SocialActionBlock.cancelled }
            try self.fence(context, approval: approval, isCurrent: isCurrent)
        }
    }
    func snapshot(target: SocialActionTarget) async throws -> SocialActionSnapshot {
        try await snapshot(target: target, generation: nil)
    }
    func snapshot(target: SocialActionTarget, generation: SquareContentGeneration?) async throws -> SocialActionSnapshot {
        guard let member = target.memberID,
              let grant = approvals.first(where: { $0.memberID == member && valid($0) }), let context = current() else {
            return try await fallback.snapshot(target: target, generation: generation)
        }
        let value = try await profile(member, context: context, approval: grant)
        var snapshot = SocialActionSnapshot(target: target, profile: value)
        snapshot.memberContext = context
        return snapshot
    }
    func perform(_ command: SocialActionCommand, snapshot: SocialActionSnapshot,
                 expectedIdentity: SocialAccountIdentity) async throws -> SocialActionReceipt {
        try await perform(command, snapshot: snapshot, expectedIdentity: expectedIdentity, isCurrent: { true })
    }
    func perform(_ command: SocialActionCommand, snapshot: SocialActionSnapshot, expectedIdentity: SocialAccountIdentity,
                 isCurrent: @escaping () -> Bool) async throws -> SocialActionReceipt {
        let grant: SocialMemberActionApproval, context: RuntimeDependencyContext, configuration: APIConfiguration
        let member: Int, record: OperationPendingRecord
        do {
            guard identity == expectedIdentity, let approved = approval(command, target: snapshot.target),
                  let captured = current(), snapshot.memberContext == captured,
                  let api = self.configuration, let id = snapshot.target.memberID else { throw SocialActionBlock.disabled }
            grant = approved; context = captured; configuration = api; member = id
            try fence(context, approval: grant, isCurrent: isCurrent)
            try snapshot.validate(); try command.validate(target: snapshot.target, snapshot: snapshot, identity: expectedIdentity)
            guard !hasPending(target: snapshot.target) else { throw SocialActionBlock.pending }
            let freshProfile = try await profile(member, context: context, approval: grant, isCurrent: isCurrent)
            var fresh = SocialActionSnapshot(target: snapshot.target, profile: freshProfile)
            fresh.memberContext = context
            guard fresh.sameContext(as: snapshot) else { throw SocialActionBlock.changed }
            try fence(context, approval: grant, isCurrent: isCurrent)
            // Recheck after every await; two reviews cannot both cross the write boundary.
            guard try journal.pending(ownerKey: owner(context), targetKey: target(member)) == nil else { throw SocialActionBlock.pending }
            _ = try SocialActionRequestBuilder(configuration: configuration).make(command, snapshot: snapshot, identity: expectedIdentity, token: context.session.token)
            record = OperationPendingRecord(ownerKey: owner(context), targetKey: target(member))
            try journal.write(record)
        } catch { throw SocialActionWriteFailure.notSent }
        do {
            try fence(context, approval: grant, isCurrent: isCurrent)
            let guarded = guardedTransport(context, approval: grant, isCurrent: isCurrent)
            let receipt = try await SocialActionService(configuration: configuration, transport: guarded)
                .perform(command, snapshot: snapshot, identity: expectedIdentity, token: context.session.token)
            try fence(context, approval: grant, isCurrent: isCurrent)
            switch grant.operation {
            case .follow:
                guard let before = snapshot.profile?.isFollowed, receipt.followed == !before else { throw SocialActionBlock.changed }
                let fresh = try await profile(member, context: context, approval: grant, isCurrent: isCurrent)
                guard fresh.isFollowed == !before else { throw SocialActionBlock.changed }
            case .startChat:
                guard let id = receipt.conversationID else { throw SocialActionBlock.changed }
                let rows = try await MessagingService(configuration: configuration, transport: guarded).conversations(token: context.session.token)
                try fence(context, approval: grant, isCurrent: isCurrent)
                guard rows.contains(where: { $0.id == id && $0.kind == .direct && $0.counterparty?.id == member }) else { throw SocialActionBlock.changed }
            }
            try fence(context, approval: grant, isCurrent: isCurrent)
            try journal.clear(record)
            return receipt
        } catch {
            // Even a server error can follow a committed side effect. Do not clear or
            // resend, and never turn a later unrelated read into an acknowledged action.
            throw SocialActionWriteFailure.outcomeUnknown
        }
    }
}

/// Fence at the actual transport boundary as well as after decoding. Calling a
/// nonisolated async service can suspend before it builds/sends its request.
@MainActor private final class SocialMemberActionGuardedTransport: HTTPTransport {
    private let transport: any HTTPTransport
    private let approval: SocialMemberActionApproval
    private let context: RuntimeDependencyContext
    private let check: () throws -> Void
    init(transport: any HTTPTransport, approval: SocialMemberActionApproval,
         context: RuntimeDependencyContext, check: @escaping () throws -> Void) {
        self.transport = transport; self.approval = approval; self.context = context; self.check = check
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try check()
        guard request.httpMethod == "POST", request.value(forHTTPHeaderField: "Authorization") == context.session.token,
              let url = request.url, approval.endpoint.paths.contains(where: { approval.endpoint.baseURL.appendingPathComponent($0) == url }) else {
            throw SocialActionBlock.disabled
        }
        let result = try await transport.send(request)
        try check()
        return result
    }
}
