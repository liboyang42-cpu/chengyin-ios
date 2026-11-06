import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Host-level trigger reasons for revalidating a displayed Square post via
/// `SquareWorkspaceCoordinator.revalidate(postID:lane:)`.
public enum SquareRevalidationTrigger: Equatable, Sendable {
    case foregroundReturn
    case communityLeave
    case shareRevocation
    case externalEdit
}

/// Host adapter bridging `TopicLikeLedger`, `TopicLikeDirection`, and `TopicLikeWriteOutcome`
/// with `SquareWorkspaceCoordinator.revalidate(postID:lane:)` trigger policies.
/// Default keeps `likeGrantEnabled == false` and `transport == nil` so no unapproved
/// network call can fire unless explicitly configured by an authorized host or test.
@MainActor @Observable public final class TopicLikeHostController {
    public typealias RequestBuilder = (Int, TopicLikeDirection, String) throws -> URLRequest

    public let ledger: TopicLikeLedger
    public weak var workspace: SquareWorkspaceCoordinator?
    public var likeGrantEnabled: Bool

    public private(set) var hasEnteredBackground = false
    public private(set) var lastRevalidationTrigger: SquareRevalidationTrigger?
    public private(set) var revalidationCount = 0

    private let requestBuilder: RequestBuilder?
    private let transport: (any HTTPTransport)?
    private let currentScope: () -> TopicLikeScope?
    private let token: () -> String?

    public init(
        ledger: TopicLikeLedger? = nil,
        workspace: SquareWorkspaceCoordinator? = nil,
        likeGrantEnabled: Bool = false,
        requestBuilder: RequestBuilder? = nil,
        transport: (any HTTPTransport)? = nil,
        currentScope: @escaping () -> TopicLikeScope? = { nil },
        token: @escaping () -> String? = { nil }
    ) {
        self.ledger = ledger ?? TopicLikeLedger()
        self.workspace = workspace
        self.likeGrantEnabled = likeGrantEnabled
        self.requestBuilder = requestBuilder
        self.transport = transport
        self.currentScope = currentScope
        self.token = token
    }

    // MARK: - Square Revalidation Trigger Policy

    /// Marks that the host scene moved to background so the next `.foregroundReturn`
    /// trigger is permitted to revalidate the active post.
    public func noteDidEnterBackground() {
        hasEnteredBackground = true
    }

    /// Evaluates whether the given trigger should execute `workspace.revalidate(postID:lane:)`.
    /// `.foregroundReturn` is gated on a prior `noteDidEnterBackground()` transition;
    /// `.communityLeave`, `.shareRevocation`, and `.externalEdit` always revalidate when a target post exists.
    public func shouldRevalidate(for trigger: SquareRevalidationTrigger, targetPostID: Int?) -> Bool {
        guard let postID = targetPostID, postID > 0, workspace != nil else { return false }
        switch trigger {
        case .foregroundReturn:
            return hasEnteredBackground
        case .communityLeave, .shareRevocation, .externalEdit:
            return true
        }
    }

    /// Runs `SquareWorkspaceCoordinator.revalidate(postID:lane:)` when the trigger policy
    /// allows it. Defaults `postID` to `workspace?.lastPost?.id`.
    @discardableResult
    public func revalidateIfNeeded(
        postID: Int? = nil,
        lane: SquareWorkspaceLane = .communityV1,
        trigger: SquareRevalidationTrigger
    ) async throws -> SquareWorkspacePost? {
        let resolvedPostID = postID ?? workspace?.lastPost?.id
        guard shouldRevalidate(for: trigger, targetPostID: resolvedPostID),
              let workspace,
              let targetID = resolvedPostID else {
            return nil
        }
        if trigger == .foregroundReturn {
            hasEnteredBackground = false
        }
        lastRevalidationTrigger = trigger
        revalidationCount += 1
        return try await workspace.revalidate(postID: targetID, lane: lane)
    }

    // MARK: - Topic Like Direction Host Adapter

    public func state(for topicID: Int) -> TopicLikeLedger.State? {
        ledger.states[topicID]
    }

    public func confirmedLiked(topicID: Int) -> Bool? {
        ledger.confirmedLiked(topicID: topicID)
    }

    public func resetLikes() {
        ledger.reset()
    }

    /// Dispatches an explicit `type=1` or `type=0` topic like intent through `TopicLikeLedger`
    /// and the injected `RequestBuilder`, optionally chaining a fresh topic detail readback
    /// when the write is acknowledged.
    @discardableResult
    public func setLikeDirection(
        topicID: Int,
        direction: TopicLikeDirection,
        readback: ((Int, String) async throws -> Bool)? = nil
    ) async throws -> TopicLikeLedger.State? {
        guard likeGrantEnabled, let requestBuilder, let transport else {
            throw SquareWorkspaceFailure.disabled
        }
        let scope = currentScope()
        guard let ticket = ledger.begin(topicID: topicID, direction: direction, scope: scope) else {
            return ledger.states[topicID]
        }
        guard let authToken = token(), AuthRequestBuilder.isValidToken(authToken) else {
            _ = ledger.complete(ticket, outcome: .unauthorized, scope: currentScope())
            throw APIError.invalidRequest
        }
        let request = try requestBuilder(topicID, direction, authToken)
        let outcome: TopicLikeWriteOutcome
        do {
            let (data, status) = try await transport.send(request)
            outcome = TopicLikeWriteOutcome.decode(data: data, status: status)
        } catch {
            outcome = .unknown
        }
        let settled = ledger.complete(ticket, outcome: outcome, scope: currentScope())
        if settled, outcome == .acknowledged, let readback {
            _ = try await performReadback(topicID: topicID, using: readback)
        }
        return ledger.states[topicID]
    }

    /// Issues a fresh readback ticket and observes the server's `isLike` state into `TopicLikeLedger`.
    @discardableResult
    public func performReadback(
        topicID: Int,
        using readback: (Int, String) async throws -> Bool
    ) async throws -> Bool {
        guard likeGrantEnabled else { throw SquareWorkspaceFailure.disabled }
        let scope = currentScope()
        guard let ticket = ledger.beginReadback(topicID: topicID, scope: scope) else {
            return false
        }
        guard let authToken = token(), AuthRequestBuilder.isValidToken(authToken) else {
            ledger.reset()
            throw APIError.invalidRequest
        }
        let liked = try await readback(topicID, authToken)
        return ledger.observe(ticket, liked: liked, scope: currentScope())
    }
}
