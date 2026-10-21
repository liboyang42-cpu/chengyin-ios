import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Canonical request matcher for `ClubCommunityService.read(_:session:check:)`.
/// Admits only the 4 read endpoints (`list`, `feed`, `comment/list`, `history`) with exact
/// sorted-key JSON bodies and positive integer parameters. All write paths are rejected.
public enum ClubCommunityReadRoute: Equatable, Sendable {
    public static let postsPath = "api/club/post/list"
    public static let feedPath = "api/club/post/feed"
    public static let commentsPath = "api/club/post/comment/list"
    public static let historyPath = "api/club/post/history"

    public static let allPaths: Set<String> = [
        postsPath,
        feedPath,
        commentsPath,
        historyPath
    ]

    case posts(clubID: Int, page: Int)
    case feed(page: Int)
    case comments(postID: Int, page: Int)
    case history(postID: Int)

    public var operation: ClubCommunityRead {
        switch self {
        case let .posts(clubID, page):
            return .posts(clubID: clubID, page: page)
        case let .feed(page):
            return .feed(page: page)
        case let .comments(postID, page):
            return .comments(postID: postID, page: page)
        case let .history(postID):
            return .history(postID: postID)
        }
    }

    public var path: String {
        switch self {
        case .posts: return Self.postsPath
        case .feed: return Self.feedPath
        case .comments: return Self.commentsPath
        case .history: return Self.historyPath
        }
    }

    public init?(request: URLRequest, baseURL: URL) {
        guard baseURL.scheme == "https",
              baseURL.host != nil,
              baseURL.user == nil,
              baseURL.password == nil,
              let url = request.url,
              url.query == nil,
              url.fragment == nil,
              url.user == nil,
              url.password == nil,
              request.httpMethod == "POST",
              request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              let body = request.httpBody,
              !body.isEmpty,
              body.count <= 4096,
              let fields = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }

        let canonicalFields: [String: Any]
        let parsed: Self

        if url.absoluteString == baseURL.appendingPathComponent(Self.postsPath).absoluteString {
            guard fields.count == 3,
                  let clubID = fields["clubId"] as? Int, clubID > 0,
                  let page = fields["pageNum"] as? Int, page > 0,
                  let pageSize = fields["pageSize"] as? Int, pageSize == 20 else {
                return nil
            }
            canonicalFields = ["clubId": clubID, "pageNum": page, "pageSize": 20]
            parsed = .posts(clubID: clubID, page: page)
        } else if url.absoluteString == baseURL.appendingPathComponent(Self.feedPath).absoluteString {
            guard fields.count == 2,
                  let page = fields["pageNum"] as? Int, page > 0,
                  let pageSize = fields["pageSize"] as? Int, pageSize == 20 else {
                return nil
            }
            canonicalFields = ["pageNum": page, "pageSize": 20]
            parsed = .feed(page: page)
        } else if url.absoluteString == baseURL.appendingPathComponent(Self.commentsPath).absoluteString {
            guard fields.count == 3,
                  let postID = fields["postId"] as? Int, postID > 0,
                  let page = fields["pageNum"] as? Int, page > 0,
                  let pageSize = fields["pageSize"] as? Int, pageSize == 50 else {
                return nil
            }
            canonicalFields = ["postId": postID, "pageNum": page, "pageSize": 50]
            parsed = .comments(postID: postID, page: page)
        } else if url.absoluteString == baseURL.appendingPathComponent(Self.historyPath).absoluteString {
            guard fields.count == 1,
                  let postID = fields["id"] as? Int, postID > 0 else {
                return nil
            }
            canonicalFields = ["id": postID]
            parsed = .history(postID: postID)
        } else {
            return nil
        }

        guard let canonicalBody = try? JSONSerialization.data(withJSONObject: canonicalFields, options: [.sortedKeys]),
              canonicalBody == body else {
            return nil
        }
        self = parsed
    }
}

/// Independently issued CN Club Community read lease.
/// Grants read access only to approved `ClubCommunityReadRoute` endpoints (`list`, `feed`, `comment/list`, `history`).
/// Never grants write or upload permission. Default issuance is nil.
@available(macOS 14.0, *)
@MainActor
@Observable
public final class ClubCommunityReadApproval {
    public let context: RuntimeDependencyContext
    public let endpoints: OperationEndpointApproval
    public let expiresAt: Date
    public let revision = UUID()
    public private(set) var isRevoked = false
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    public init(
        context: RuntimeDependencyContext,
        expiresAt: Date,
        allowedPaths: Set<String> = ClubCommunityReadRoute.allPaths
    ) throws {
        let duration = expiresAt.timeIntervalSinceNow
        guard context.market == .china,
              ["player", "club", "merchant"].contains(context.role),
              context.session.accountID > 0,
              AuthRequestBuilder.isValidToken(context.session.token),
              !allowedPaths.isEmpty,
              allowedPaths.isSubset(of: ClubCommunityReadRoute.allPaths),
              duration.isFinite,
              duration > 0,
              duration <= 86_400 else {
            throw APIError.invalidConfiguration
        }
        self.endpoints = try OperationEndpointApproval(
            baseURL: context.baseURL,
            namespace: context.session.namespace,
            accountID: context.session.accountID,
            paths: allowedPaths
        )
        self.context = context
        self.expiresAt = expiresAt
        expiryTask = Task { @MainActor [weak self] in
            let remaining = max(0, min(expiresAt.timeIntervalSince(Date()), 86_400))
            do {
                if remaining > 0 {
                    try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                }
                try Task.checkCancellation()
            } catch {
                return
            }
            self?.revoke()
        }
    }

    deinit {
        expiryTask?.cancel()
    }

    public func revoke() {
        isRevoked = true
        expiryTask?.cancel()
        expiryTask = nil
    }

    public func expireIfNeeded(now: Date = Date()) {
        if now >= expiresAt {
            revoke()
        }
    }

    public func matches(_ current: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        !isRevoked && now < expiresAt && ContentDraftContextFence.matches(context, current)
    }
}

/// Read-only transport fence for `ClubCommunityService`.
/// Checks deployment/account/epoch/token/approval before dispatch and after response completion.
/// Any write endpoint or unapproved/revoked/stale context is rejected fail-closed.
@available(macOS 14.0, *)
@MainActor
public final class ClubCommunityReadRuntimeTransport: HTTPTransport {
    private let transport: any HTTPTransport
    private let currentContext: () -> RuntimeDependencyContext?
    private let selectApproval: (RuntimeDependencyContext) -> ClubCommunityReadApproval?
    private let currentSession: () throws -> ClubCommunitySession

    public init(
        transport: any HTTPTransport,
        currentContext: @escaping () -> RuntimeDependencyContext?,
        selectApproval: @escaping (RuntimeDependencyContext) -> ClubCommunityReadApproval?,
        currentSession: @escaping () throws -> ClubCommunitySession
    ) {
        self.transport = transport
        self.currentContext = currentContext
        self.selectApproval = selectApproval
        self.currentSession = currentSession
    }

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard let capturedContext = currentContext(),
              let capturedSession = try? currentSession(),
              capturedSession.identity.accountID == capturedContext.session.accountID,
              capturedSession.identity.epoch == capturedContext.session.epoch,
              capturedSession.token == capturedContext.session.token,
              let approval = selectApproval(capturedContext),
              approval.matches(capturedContext),
              let apiConfig = try? APIConfiguration(baseURL: capturedContext.baseURL),
              let route = ClubCommunityReadRoute(request: request, baseURL: capturedContext.baseURL),
              approval.endpoints.allows(
                  configuration: apiConfig,
                  namespace: capturedContext.session.namespace,
                  accountID: capturedContext.session.accountID,
                  path: route.path
              ),
              request.value(forHTTPHeaderField: "Authorization") == capturedContext.session.token else {
            throw ClubCommunityFailure.unavailable
        }

        let capturedRevision = approval.revision
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()

        guard let liveContext = currentContext(),
              ContentDraftContextFence.matches(capturedContext, liveContext),
              let liveSession = try? currentSession(),
              liveSession == capturedSession,
              let liveApproval = selectApproval(liveContext),
              liveApproval.revision == capturedRevision,
              liveApproval.matches(liveContext) else {
            throw ClubCommunityFailure.stale
        }
        return (data, status)
    }
}

/// Stateful read runtime for Club Community posts, cross-club feed, comments, and revision history.
/// Supports pagination, detail/editor return refresh, error recovery, and immediate isolation on
/// account, epoch, or read-approval revocation changes.
@available(macOS 14.0, *)
@MainActor
public final class ClubCommunityReadRuntime {
    public struct ScopeFingerprint: Equatable {
        public let identity: ClubReadIdentity
        public let context: RuntimeDependencyContext
        public let approvalRevision: UUID
    }

    private let makeService: () -> ClubCommunityService
    private let currentSession: () throws -> ClubCommunitySession
    private let currentContext: () -> RuntimeDependencyContext?
    private let selectApproval: (RuntimeDependencyContext) -> ClubCommunityReadApproval?

    public private(set) var postsSnapshot: ClubCommunitySnapshot?
    public private(set) var commentsSnapshot: ClubCommunitySnapshot?
    public private(set) var historySnapshot: ClubCommunitySnapshot?
    public private(set) var selectedPost: ClubCommunityPost?
    public private(set) var postsPage: Int = 1
    public private(set) var commentsPage: Int = 1
    public private(set) var activeClubID: Int?
    public private(set) var activePostID: Int?
    public private(set) var lastOperation: ClubCommunityRead?
    public private(set) var lastListOperation: ClubCommunityRead?
    public private(set) var lastFailedOperation: ClubCommunityRead?
    public private(set) var isLoading: Bool = false
    public private(set) var errorKey: String?
    public private(set) var activeFingerprint: ScopeFingerprint?
    private var generation: UInt64 = 0

    public init(
        makeService: @escaping () -> ClubCommunityService,
        currentSession: @escaping () throws -> ClubCommunitySession,
        currentContext: @escaping () -> RuntimeDependencyContext?,
        selectApproval: @escaping (RuntimeDependencyContext) -> ClubCommunityReadApproval?
    ) {
        self.makeService = makeService
        self.currentSession = currentSession
        self.currentContext = currentContext
        self.selectApproval = selectApproval
    }

    public var isReadApproved: Bool {
        currentScopeFingerprint() != nil
    }

    public var permitsWrites: Bool {
        makeService().allowsInjectedWrites
    }

    public func currentScopeFingerprint() -> ScopeFingerprint? {
        guard let context = currentContext(),
              let session = try? currentSession(),
              session.identity.accountID == context.session.accountID,
              session.identity.epoch == context.session.epoch,
              session.token == context.session.token,
              let approval = selectApproval(context),
              approval.matches(context) else {
            return nil
        }
        return ScopeFingerprint(
            identity: session.identity,
            context: context,
            approvalRevision: approval.revision
        )
    }

    public func invalidate() {
        generation &+= 1
        postsSnapshot = nil
        commentsSnapshot = nil
        historySnapshot = nil
        selectedPost = nil
        postsPage = 1
        commentsPage = 1
        activeClubID = nil
        activePostID = nil
        lastOperation = nil
        lastListOperation = nil
        lastFailedOperation = nil
        isLoading = false
        errorKey = nil
        activeFingerprint = nil
    }

    @discardableResult
    public func load(_ operation: ClubCommunityRead) async -> ClubCommunitySnapshot? {
        generation &+= 1
        let ticket = generation

        guard let fingerprint = currentScopeFingerprint(),
              let session = try? currentSession() else {
            invalidate()
            errorKey = "club.community.unavailable"
            lastFailedOperation = operation
            return nil
        }

        if activeFingerprint != nil && activeFingerprint != fingerprint {
            postsSnapshot = nil
            commentsSnapshot = nil
            historySnapshot = nil
            selectedPost = nil
        }
        activeFingerprint = fingerprint
        lastOperation = operation
        switch operation {
        case .posts, .feed:
            lastListOperation = operation
        case .comments, .history:
            break
        }
        isLoading = true
        errorKey = nil

        let service = makeService()
        do {
            let result = try await service.read(operation, session: session) {
                guard self.currentScopeFingerprint() == fingerprint,
                      (try? self.currentSession()) == session else {
                    throw ClubCommunityFailure.stale
                }
            }
            guard !Task.isCancelled,
                  ticket == generation,
                  currentScopeFingerprint() == fingerprint,
                  (try? currentSession()) == session else {
                if currentScopeFingerprint() != fingerprint {
                    invalidate()
                }
                return nil
            }
            isLoading = false
            lastFailedOperation = nil
            errorKey = nil
            switch operation {
            case let .posts(clubID, page):
                activeClubID = clubID
                postsPage = page
                postsSnapshot = result
                if let currentSelected = selectedPost {
                    selectedPost = result.posts.first(where: { $0.id == currentSelected.id })
                }
            case let .feed(page):
                activeClubID = nil
                postsPage = page
                postsSnapshot = result
                if let currentSelected = selectedPost {
                    selectedPost = result.posts.first(where: { $0.id == currentSelected.id })
                }
            case let .comments(postID, page):
                activePostID = postID
                commentsPage = page
                commentsSnapshot = result
            case let .history(postID):
                activePostID = postID
                historySnapshot = result
            }
            return result
        } catch {
            guard ticket == generation else { return nil }
            if currentScopeFingerprint() != fingerprint {
                invalidate()
                return nil
            }
            isLoading = false
            lastFailedOperation = operation
            errorKey = "club.community.loadError"
            switch operation {
            case .posts, .feed:
                postsSnapshot = nil
            case .comments:
                commentsSnapshot = nil
            case .history:
                historySnapshot = nil
            }
            return nil
        }
    }

    @discardableResult
    public func loadPosts(clubID: Int, page: Int = 1) async -> ClubCommunitySnapshot? {
        await load(.posts(clubID: clubID, page: max(1, page)))
    }

    @discardableResult
    public func loadFeed(page: Int = 1) async -> ClubCommunitySnapshot? {
        await load(.feed(page: max(1, page)))
    }

    @discardableResult
    public func nextPostsPage() async -> ClubCommunitySnapshot? {
        guard let current = postsSnapshot, current.posts.count >= 20 else { return postsSnapshot }
        let nextPage = postsPage + 1
        if let clubID = activeClubID {
            return await load(.posts(clubID: clubID, page: nextPage))
        }
        return await load(.feed(page: nextPage))
    }

    @discardableResult
    public func previousPostsPage() async -> ClubCommunitySnapshot? {
        guard postsPage > 1 else { return postsSnapshot }
        let prevPage = postsPage - 1
        if let clubID = activeClubID {
            return await load(.posts(clubID: clubID, page: prevPage))
        }
        return await load(.feed(page: prevPage))
    }

    @discardableResult
    public func loadComments(postID: Int, page: Int = 1) async -> ClubCommunitySnapshot? {
        await load(.comments(postID: postID, page: max(1, page)))
    }

    @discardableResult
    public func nextCommentsPage() async -> ClubCommunitySnapshot? {
        guard let postID = activePostID,
              let current = commentsSnapshot,
              current.comments.count >= 50 else { return commentsSnapshot }
        return await load(.comments(postID: postID, page: commentsPage + 1))
    }

    @discardableResult
    public func previousCommentsPage() async -> ClubCommunitySnapshot? {
        guard let postID = activePostID, commentsPage > 1 else { return commentsSnapshot }
        return await load(.comments(postID: postID, page: commentsPage - 1))
    }

    @discardableResult
    public func loadHistory(postID: Int) async -> ClubCommunitySnapshot? {
        await load(.history(postID: postID))
    }

    /// Opens a post detail from the currently loaded posts snapshot and loads page 1 of its comments.
    @discardableResult
    public func openPostDetail(_ post: ClubCommunityPost) async -> ClubCommunitySnapshot? {
        guard let fingerprint = currentScopeFingerprint(),
              activeFingerprint == fingerprint,
              let loadedPosts = postsSnapshot?.posts,
              let matched = loadedPosts.first(where: { $0.id == post.id && $0.version == post.version }) else {
            selectedPost = nil
            commentsSnapshot = nil
            historySnapshot = nil
            return nil
        }
        selectedPost = matched
        activePostID = matched.id
        commentsPage = 1
        historySnapshot = nil
        return await load(.comments(postID: matched.id, page: 1))
    }

    /// Closes the active post detail, clears child comments/history snapshots, and refreshes the parent post list.
    @discardableResult
    public func returnFromDetail() async -> ClubCommunitySnapshot? {
        selectedPost = nil
        activePostID = nil
        commentsPage = 1
        commentsSnapshot = nil
        historySnapshot = nil
        guard let listOp = lastListOperation else { return nil }
        return await load(listOp)
    }

    /// Reloads the active read operation upon returning from comments, history, or detail screens.
    @discardableResult
    public func refreshOnReturn() async -> ClubCommunitySnapshot? {
        guard let operation = lastOperation else { return nil }
        return await load(operation)
    }

    /// Retries the last failed or active read operation for error recovery.
    @discardableResult
    public func retryLastRead() async -> ClubCommunitySnapshot? {
        guard let operation = lastFailedOperation ?? lastOperation else { return nil }
        return await load(operation)
    }
}
