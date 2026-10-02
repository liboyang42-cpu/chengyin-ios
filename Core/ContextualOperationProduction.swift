import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum ContextualOperationCommand: Equatable {
    case clubTime(ClubOpsTimeRequest), review(ContextualReviewTarget, ContextualReviewDraft)
}
/// Issued only by a coordinator after its durable record was written. Carries no reusable
/// capability: one exact command, one scoped owner and one physical dispatch attempt.
@MainActor public final class ContextualOperationAuthorization {
    private let command: ContextualOperationCommand
    private let owner: String
    private let pending: () throws -> Bool
    private var consumed = false
    init(command: ContextualOperationCommand, owner: String, pending: @escaping () throws -> Bool) {
        self.command = command; self.owner = owner; self.pending = pending
    }
    func validate(_ command: ContextualOperationCommand, owner: String) throws {
        guard !consumed, self.command == command, self.owner == owner, try pending(), !Task.isCancelled else { throw APIError.invalidRequest }
    }
    func consume(_ command: ContextualOperationCommand, owner: String) throws {
        try validate(command, owner: owner); consumed = true
    }
}

/// Reviewed composition input, not a role, server feature flag or account-login grant.
public struct ClubOpsTimeTarget: Hashable {
    public let activityID: Int
    public let clubID: Int
    public init(activityID: Int, clubID: Int) throws {
        guard activityID > 0, clubID > 0 else { throw APIError.invalidConfiguration }
        self.activityID = activityID; self.clubID = clubID
    }
}
public struct ClubOpsTimeApproval {
    public let market: RegionalMarket
    public let endpoints: OperationEndpointApproval
    public let targets: Set<ClubOpsTimeTarget>
    public init(market: RegionalMarket, endpoints: OperationEndpointApproval, targets: Set<ClubOpsTimeTarget>) throws {
        guard Set(targets.map(\.activityID)).count == targets.count else { throw APIError.invalidConfiguration }
        self.market = market; self.endpoints = endpoints; self.targets = targets
    }
    public func permits(_ target: ClubOpsTimeTarget, context: RuntimeDependencyContext) -> Bool {
        ContextualOperationBoundary.matches(market, endpoints, context) && targets.contains(target) &&
        Set(["api/activity/info", "api/club/lead/team-progress", "api/club/lead/edit-ops"]).isSubset(of: endpoints.paths)
    }
}
public struct ContextualReviewApproval {
    public let market: RegionalMarket
    public let endpoints: OperationEndpointApproval
    public let targets: Set<ContextualReviewTarget>
    public init(market: RegionalMarket, endpoints: OperationEndpointApproval, targets: Set<ContextualReviewTarget>) throws {
        guard targets.allSatisfy({ $0.ownerID > 0 }) else { throw APIError.invalidConfiguration }
        self.market = market; self.endpoints = endpoints; self.targets = targets
    }
    public func permits(_ target: ContextualReviewTarget, context: RuntimeDependencyContext) -> Bool {
        ContextualOperationBoundary.matches(market, endpoints, context) && targets.contains(target) &&
        Set(["api/comment/add", target.detailPath]).isSubset(of: endpoints.paths)
    }
}
extension ContextualReviewTarget {
    var detailPath: String {
        switch self { case .topic: return "api/topic/info-to-user"; case .activity: return "api/activity/info" }
    }
}
private enum ContextualOperationBoundary {
    static func matches(_ market: RegionalMarket, _ endpoints: OperationEndpointApproval, _ context: RuntimeDependencyContext) -> Bool {
        market == .china && context.market == market && endpoints.baseURL == context.baseURL &&
        endpoints.namespace == context.session.namespace && endpoints.accountID == context.session.accountID
    }
    static func data(_ result: (Data, Int)) throws -> ClubGovernanceValue {
        let value = try JSONDecoder().decode(ClubGovernanceValue.self, from: result.0)
        if result.1 == 401 || value["code"].int == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(result.1), value["code"].int == 200, value["data"].object != nil else { throw APIError.malformedResponse }
        return value["data"]
    }
}

/// The normal host retains this dynamic service across navigation and sign-ins. Each call
/// captures all of deployment/namespace/account/role/epoch/token; no stale review is reused.
@MainActor public struct ClubOpsTimeConfiguredService: ClubOpsTimeServing {
    private let configuration: APIConfiguration
    private let approval: ClubOpsTimeApproval?
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    public init(configuration: APIConfiguration, approval: ClubOpsTimeApproval? = nil, transport: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?, onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.configuration = configuration; self.approval = approval; self.transport = transport; self.current = current; self.onUnauthorized = onUnauthorized
    }
    public var session: ClubOpsTimeSession? { current().flatMap { try? .init(context: $0) } }
    public var isConfigured: Bool {
        guard let captured = current(), captured.baseURL == configuration.baseURL, let approval else { return false }
        return approval.targets.contains { approval.permits($0, context: captured) }
    }
    private func capture(_ session: ClubOpsTimeSession, activityID: Int) throws -> (RuntimeDependencyContext, ClubOpsTimeTarget, RuntimeDependencyTransport) {
        guard let captured = current(), captured == session.runtimeContext, self.session == session,
              captured.baseURL == configuration.baseURL, let approval,
              let target = approval.targets.first(where: { $0.activityID == activityID }), approval.permits(target, context: captured),
              !Task.isCancelled else { throw ClubOpsTimeFailure.disabled }
        return (captured, target, RuntimeDependencyTransport(configuration: .init(market: approval.market, endpoints: approval.endpoints),
            captured: captured, transport: transport, current: current))
    }
    private func check(_ captured: RuntimeDependencyContext) throws {
        guard current() == captured, !Task.isCancelled else { throw ClubOpsTimeFailure.stale }
    }
    private func detail(_ target: ClubOpsTimeTarget, captured: RuntimeDependencyContext, transport: RuntimeDependencyTransport) async throws -> ClubGovernanceValue {
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/activity/info"),
            fields: ["id": String(target.activityID)], token: captured.session.token)
        let data = try ContextualOperationBoundary.data(await transport.send(request))
        try check(captured)
        guard data["id"].int == target.activityID, data["clubId"].int == target.clubID, data["gate"].bool != true,
              let date = data["startDate"].string, ClubOpsTimeRequest.date(date) != nil else { throw ClubOpsTimeFailure.malformed }
        return data
    }
    public func read(activityID: Int, session: ClubOpsTimeSession) async throws -> String {
        let (captured, target, scoped) = try capture(session, activityID: activityID)
        do {
            let data = try await detail(target, captured: captured, transport: scoped)
            guard let date = data["startDate"].string else { throw ClubOpsTimeFailure.malformed }
            return date
        } catch {
            if error as? APIError == .unauthorized, current() == captured { onUnauthorized(captured) }
            throw error
        }
    }
    public let requiresDurableJournal = true
    public func save(_ request: ClubOpsTimeRequest, session: ClubOpsTimeSession) async throws { throw ClubOpsTimeFailure.disabled }
    public func save(_ request: ClubOpsTimeRequest, session: ClubOpsTimeSession, authorization: ContextualOperationAuthorization) async throws {
        do { try authorization.validate(.clubTime(request), owner: session.replayOwnerKey) }
        catch { throw ClubOpsTimeFailure.disabled }
        let (captured, target, scoped) = try capture(session, activityID: request.activityId)
        // This read includes pending/unpaid sales. Paid-count == 0 is NOT proof of an unlocked time.
        do {
            let data = try await detail(target, captured: captured, transport: scoped)
            guard data["timeLocationLocked"].bool == false else { throw ClubOpsTimeFailure.rejected }
            var components = URLComponents(url: configuration.baseURL.appendingPathComponent("api/club/lead/team-progress"), resolvingAgainstBaseURL: false)!
            components.queryItems = [.init(name: "activityId", value: String(target.activityID))]
            var leaderRequest = URLRequest(url: components.url!); leaderRequest.httpMethod = "GET"
            leaderRequest.setValue(captured.session.token, forHTTPHeaderField: "Authorization")
            let leader = try ContextualOperationBoundary.data(await scoped.send(leaderRequest))
            guard leader["exists"].bool == true, leader["isLeader"].bool == true,
                  leader["leaderMemberId"].int == captured.session.accountID else { throw ClubOpsTimeFailure.rejected }
            try check(captured)
        } catch {
            if error as? APIError == .unauthorized, current() == captured { onUnauthorized(captured) }
            if error as? ClubOpsTimeFailure == .rejected { throw ClubOpsTimeFailure.rejected }
            throw ClubOpsTimeFailure.stale // No mutation was dispatched; retry requires all fresh reads.
        }
        // Backend still enforces current leader and sold-session lock atomically at its boundary.
        // The acknowledgment is an edit/log result, never proof of notification delivery.
        do { try authorization.consume(.clubTime(request), owner: session.replayOwnerKey) }
        catch { throw ClubOpsTimeFailure.stale }
        let writer = ClubOpsTimeHTTPService(configuration: configuration, transport: scoped, enabled: true,
            current: { current() == captured ? session : nil })
        try await writer.save(request, session: session)
    }
}

/// No paid-registration prerequisite is invented: source permits any authenticated user
/// to review an existing topic/activity. Participation only controls first-review rewards.
@MainActor public struct ContextualReviewConfiguredWriter: ContextualReviewWriting {
    private let configuration: APIConfiguration
    private let approval: ContextualReviewApproval?
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    public init(configuration: APIConfiguration, approval: ContextualReviewApproval? = nil, transport: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?, onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.configuration = configuration; self.approval = approval; self.transport = transport; self.current = current; self.onUnauthorized = onUnauthorized
    }
    public var session: ContextualReviewSession? { current().flatMap { try? .init(context: $0) } }
    public var isConfigured: Bool {
        guard let captured = current(), captured.baseURL == configuration.baseURL, let approval else { return false }
        return approval.targets.contains { approval.permits($0, context: captured) }
    }
    public let requiresDurableJournal = true
    public func submit(_ draft: ContextualReviewDraft, target: ContextualReviewTarget, session: ContextualReviewSession) async throws { throw ContextualReviewFailure.notSent }
    public func submit(_ draft: ContextualReviewDraft, target: ContextualReviewTarget, session: ContextualReviewSession, authorization: ContextualOperationAuthorization) async throws {
        do { try authorization.validate(.review(target, draft), owner: session.replayOwnerKey) }
        catch { throw ContextualReviewFailure.notSent }
        guard let captured = current(), captured == session.runtimeContext, self.session == session,
              captured.baseURL == configuration.baseURL, let approval, approval.permits(target, context: captured),
              draft.isValid, !Task.isCancelled else { throw ContextualReviewFailure.notSent }
        let scoped = RuntimeDependencyTransport(configuration: .init(market: approval.market, endpoints: approval.endpoints),
            captured: captured, transport: transport, current: current)
        let request: URLRequest
        do {
            let read = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(target.detailPath),
                fields: ["id": String(target.ownerID)], token: captured.session.token)
            let data = try ContextualOperationBoundary.data(await scoped.send(read))
            guard data["id"].int == target.ownerID, data["gate"].bool != true,
                  let name = data["name"].string, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  current() == captured, !Task.isCancelled else { throw ContextualReviewFailure.notSent }
            request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/comment/add"),
                fields: draft.fields(target: target), token: captured.session.token)
        } catch {
            if error as? APIError == .unauthorized, current() == captured { onUnauthorized(captured) }
            throw ContextualReviewFailure.notSent
        }
        // No suspension occurs between the final context guard and dispatch.
        guard current() == captured, !Task.isCancelled else { throw ContextualReviewFailure.notSent }
        do { try authorization.consume(.review(target, draft), owner: session.replayOwnerKey) }
        catch { throw ContextualReviewFailure.notSent }
        do {
            let (data, status) = try await scoped.send(request)
            guard current() == captured, !Task.isCancelled else { throw ContextualReviewFailure.unknown }
            let result = try JSONDecoder().decode(ClubGovernanceValue.self, from: data)
            if status == 401 || result["code"].int == 401 { onUnauthorized(captured) }
            guard (200..<300).contains(status), let code = result["code"].int else { throw ContextualReviewFailure.unknown }
            guard code == 200 else { throw ContextualReviewFailure.rejected(code) }
            // add returns the authoritative inserted row. A bare code or a different target
            // cannot acknowledge this review. The normal detail screen independently reloads.
            let receipt = result["data"]
            guard let id = receipt["id"].int, id > 0, receipt["memberId"].int == captured.session.accountID,
                  receipt["ownerType"].int == target.ownerType, receipt["ownerId"].int == target.ownerID,
                  receipt["replyId"].int == 0, receipt["rating"].int == draft.rating,
                  receipt["contents"].string == draft.contents.trimmingCharacters(in: .whitespacesAndNewlines) else { throw ContextualReviewFailure.unknown }
        } catch let error as ContextualReviewFailure { throw error }
        catch { throw ContextualReviewFailure.unknown }
    }
}
