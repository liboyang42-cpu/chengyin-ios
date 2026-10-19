import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 我的收藏 → 主题 → 取消点赞 (mini-program `mylike.topicUnlike`).
/// `POST /api/topic/like {id, type:0}` sets liked=false on the server (idempotent),
/// so an uncertain outcome is resolved by reading `like_list`, never by resending.
public struct TopicUnlikeApproval: Equatable {
    public static let paths: Set<String> = ["api/topic/like", "api/topic/like_list"]
    public let endpoint: OperationEndpointApproval
    public let accountID: Int
    public let expiresAt: Date
    public init(endpoint: OperationEndpointApproval, accountID: Int, expiresAt: Date) throws {
        guard endpoint.paths == Self.paths, endpoint.accountID == accountID, accountID > 0,
              expiresAt.timeIntervalSince1970.isFinite else { throw APIError.invalidConfiguration }
        self.endpoint = endpoint; self.accountID = accountID; self.expiresAt = expiresAt
    }
}

public struct TopicUnlikeSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    public let namespace: String
    public let market: RegionalMarket
    let token: String
    public init(accountID: Int, epoch: UInt64, namespace: String, market: RegionalMarket, token: String) throws {
        guard accountID > 0, !namespace.isEmpty, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; self.namespace = namespace; self.market = market; self.token = token
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.accountID == rhs.accountID && lhs.epoch == rhs.epoch && lhs.namespace == rhs.namespace &&
            lhs.market == rhs.market && lhs.token.utf8.elementsEqual(rhs.token.utf8)
    }
}

public enum TopicUnlikeFailure: Error, Equatable { case disabled, stale, rejected(String?) }

@MainActor @Observable public final class TopicUnlikeController {
    public enum Phase: Equatable {
        case idle
        /// Waiting for the explicit 确定要取消点赞吗？ confirmation.
        case confirming(topicID: Int, requestID: UUID)
        case working(topicID: Int)
        case removed(topicID: Int)
        case failed(topicID: Int, message: String?)
        /// The request may have reached the server; only a readback is offered.
        case unknown(topicID: Int)
        case checking(topicID: Int)
    }
    public private(set) var phase: Phase = .idle
    /// Topics whose last command outcome is unresolved; never re-sent until read back.
    public private(set) var unresolved: Set<Int> = []
    public var maxReadbackPages = 20
    private let configuration: APIConfiguration
    private let approvals: [TopicUnlikeApproval]
    private let transport: any HTTPTransport
    private let current: () -> TopicUnlikeSession?
    private let onUnauthorized: () -> Void
    private let now: () -> Date
    private var pendingSession: TopicUnlikeSession?

    public init(configuration: APIConfiguration, approvals: [TopicUnlikeApproval], transport: any HTTPTransport,
                current: @escaping () -> TopicUnlikeSession?, onUnauthorized: @escaping () -> Void = {},
                now: @escaping () -> Date = Date.init) {
        self.configuration = configuration; self.approvals = approvals; self.transport = transport
        self.current = current; self.onUnauthorized = onUnauthorized; self.now = now
    }

    public var isAvailable: Bool { current().map(approved) ?? false }
    private func approved(_ session: TopicUnlikeSession) -> Bool {
        session.market == .china && approvals.filter { approval in
            approval.accountID == session.accountID && now() < approval.expiresAt &&
                TopicUnlikeApproval.paths.allSatisfy {
                    approval.endpoint.allows(configuration: configuration, namespace: session.namespace,
                                             accountID: session.accountID, path: $0)
                }
        }.count == 1
    }
    private var isBusy: Bool {
        switch phase { case .working, .checking: return true; default: return false }
    }

    /// Opens the confirmation; nothing is sent yet. One topic at a time.
    @discardableResult public func request(topicID: Int) -> UUID? {
        guard topicID > 0, !isBusy, let session = current(), approved(session) else { return nil }
        if unresolved.contains(topicID) { phase = .unknown(topicID: topicID); return nil }
        let id = UUID(); pendingSession = session
        phase = .confirming(topicID: topicID, requestID: id)
        return id
    }
    public func cancel() {
        if case .confirming = phase { phase = .idle; pendingSession = nil }
    }
    public func dismissResult() {
        switch phase { case .removed, .failed: phase = .idle; default: break }
    }

    /// Sends exactly one request for the confirmed intent.
    public func confirm(_ requestID: UUID) async {
        guard case .confirming(let topicID, let id) = phase, id == requestID,
              let session = pendingSession, current() == session, approved(session) else { return }
        phase = .working(topicID: topicID)
        let request: URLRequest
        do {
            request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/topic/like"),
                fields: ["id": String(topicID), "type": "0"], token: session.token)
        } catch { phase = .failed(topicID: topicID, message: nil); return }
        unresolved.insert(topicID)
        let data: Data, status: Int
        do { (data, status) = try await transport.send(request) }
        catch { phase = current() == session ? .unknown(topicID: topicID) : .idle; return }
        guard current() == session else { phase = .idle; return }
        let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        if status == 401 || envelope?.code == 401 || envelope?.code == 2 {
            unresolved.remove(topicID); phase = .failed(topicID: topicID, message: nil); onUnauthorized(); return
        }
        guard (200..<300).contains(status), let envelope else { phase = .unknown(topicID: topicID); return }
        if envelope.code == 200 {
            unresolved.remove(topicID); phase = .removed(topicID: topicID)
        } else {
            // A business rejection (参数不合规, 请先登录…) is a definite non-change.
            unresolved.remove(topicID); phase = .failed(topicID: topicID, message: envelope.msg)
        }
    }

    /// Read-only resolution: scans the liked-topics list for the target.
    public func checkUnresolved(topicID: Int) async {
        guard unresolved.contains(topicID), !isBusy, let session = current(), approved(session) else { return }
        phase = .checking(topicID: topicID)
        do {
            var page = 1
            while page <= maxReadbackPages {
                let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/topic/like_list"),
                    fields: ["pageNum": String(page), "pageSize": "10"], token: session.token)
                let (data, status) = try await transport.send(request)
                guard current() == session else { phase = .idle; return }
                guard (200..<300).contains(status), let list = try? JSONDecoder().decode(ListEnvelope.self, from: data),
                      list.code == 200 else { throw TopicUnlikeFailure.stale }
                let rows = list.data?.rows ?? list.rows ?? []
                if rows.contains(where: { $0.id == topicID }) {
                    // Still liked: the earlier command did not take effect; a new confirmation may follow.
                    unresolved.remove(topicID); phase = .failed(topicID: topicID, message: nil); return
                }
                if rows.count < 10 { unresolved.remove(topicID); phase = .removed(topicID: topicID); return }
                page += 1
            }
            phase = .unknown(topicID: topicID)
        } catch { phase = current() == session ? .unknown(topicID: topicID) : .idle }
    }

    private struct Envelope: Decodable { let code: Int; let msg: String? }
    private struct ListEnvelope: Decodable {
        struct Row: Decodable { let id: Int? }
        struct Page: Decodable { let rows: [Row]? }
        let code: Int
        let rows: [Row]?
        let data: Page?
    }
}
