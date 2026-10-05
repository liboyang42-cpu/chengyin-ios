import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct MerchantPredictionLock: Codable, Equatable {
    public let namespace: String, accountID: Int, merchantID: Int, nodeID: String, playDay: String
    public var key: String { [namespace, String(accountID), String(merchantID), nodeID, playDay].map { "\($0.utf8.count):\($0)" }.joined() }
    init(_ review: MerchantPredictionReview) throws {
        guard let merchantID = review.access.merchantID else { throw MerchantMarketingFailure.invalid }
        namespace = review.scope.namespace; accountID = review.scope.accountID; self.merchantID = merchantID
        nodeID = review.round.nodeID; playDay = review.round.playDay
    }
}
@MainActor public protocol MerchantPredictionLockStore: AnyObject {
    func contains(_ record: MerchantPredictionLock) throws -> Bool
    func acquire(_ record: MerchantPredictionLock) throws
    /// Only definitive rejection before server acceptance allows removal; never unknown or success.
    func releaseRejected(_ record: MerchantPredictionLock) throws
}
@MainActor public final class MerchantPredictionFileLocks: MerchantPredictionLockStore {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    private func file(_ record: MerchantPredictionLock) -> URL {
        let namespace = record.namespace.utf8.map { String(format: "%02x", $0) }.joined()
        let day = record.playDay.utf8.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(namespace).appendingPathComponent("\(record.accountID)-\(record.merchantID)").appendingPathComponent("\(record.nodeID)-\(day).json")
    }
    public func contains(_ record: MerchantPredictionLock) throws -> Bool {
        let path = file(record)
        guard FileManager.default.fileExists(atPath: path.path) else { return false }
        do {
            guard try JSONDecoder().decode(MerchantPredictionLock.self, from: Data(contentsOf: path)) == record else { throw MerchantMarketingFailure.storage }
            return true
        } catch { throw MerchantMarketingFailure.storage }
    }
    public func acquire(_ record: MerchantPredictionLock) throws {
        guard !(try contains(record)) else { throw MerchantMarketingFailure.locked }
        do {
            try FileManager.default.createDirectory(at: file(record).deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // Exclusive creation prevents two coordinators from claiming the same round.
            try JSONEncoder().encode(record).write(to: file(record), options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file(record).path)
        } catch { throw MerchantMarketingFailure.storage }
    }
    public func releaseRejected(_ record: MerchantPredictionLock) throws {
        do { try FileManager.default.removeItem(at: file(record)) } catch { throw MerchantMarketingFailure.storage }
    }
}

/// Concrete injectable request adapter. All endpoint grants are off by default.
/// The host must independently approve profile/host, reads, AI processing and one-shot settlement.
@MainActor public final class MerchantMarketingService {
    public struct Gates {
        public let reads: Bool, insight: Bool, settlement: Bool
        public init(reads: Bool = false, insight: Bool = false, settlement: Bool = false) { self.reads = reads; self.insight = insight; self.settlement = settlement }
    }
    private let configuration: APIConfiguration?, transport: any HTTPTransport, gates: Gates
    private let currentSession: () -> MerchantMarketingScope?
    private let onUnauthorized: (MerchantMarketingScope) -> Void
    private let locks: (any MerchantPredictionLockStore)?
    private var issued: MerchantPredictionReview?
    private var submitting = false
    public var scope: MerchantMarketingScope? { currentSession() }
    public var permitsReads: Bool { configuration != nil && gates.reads }
    public var permitsInsight: Bool { permitsReads && gates.insight }
    public var permitsSettlement: Bool { permitsReads && gates.settlement && locks != nil }
    public init(configuration: APIConfiguration?, transport: any HTTPTransport,
                gates: Gates = Gates(), locks: (any MerchantPredictionLockStore)? = nil,
                currentSession: @escaping () -> MerchantMarketingScope?, onUnauthorized: @escaping (MerchantMarketingScope) -> Void = { _ in }) {
        self.configuration = configuration; self.transport = transport; self.gates = gates; self.locks = locks
        self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
    }
    private struct Envelope: Decodable { let code: MerchantMarketingValue; let msg: String?; let data: MerchantMarketingValue? }
    private func captured() throws -> MerchantMarketingScope {
        guard permitsReads else { throw MerchantMarketingFailure.unavailable }
        guard let scope else { throw MerchantMarketingFailure.signIn }; return scope
    }
    private func ensure(_ session: MerchantMarketingScope) throws {
        guard !Task.isCancelled, currentSession() == session else { throw MerchantMarketingFailure.stale }
    }
    private func request(_ path: String, body: [String: MerchantMarketingValue]? = nil, session: MerchantMarketingScope) async throws -> MerchantMarketingValue {
        try ensure(session)
        guard let configuration, permitsReads else { throw MerchantMarketingFailure.unavailable }
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: [:], token: session.token, includesBody: false)
        request.httpMethod = "POST"
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONEncoder().encode(body) }
        let (bytes, status) = try await transport.send(request)
        try ensure(session)
        if status == 401 { onUnauthorized(session); throw MerchantMarketingFailure.signIn }
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(Envelope.self, from: bytes))?.msg
            throw MerchantMarketingFailure.rejected(status, message)
        }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: bytes) } catch { throw MerchantMarketingFailure.malformed }
        guard let code = envelope.code.integer else { throw MerchantMarketingFailure.malformed }
        if code == 401 { onUnauthorized(session); throw MerchantMarketingFailure.signIn }
        guard code == 200 else { throw MerchantMarketingFailure.rejected(code, envelope.msg) }
        return envelope.data ?? .null
    }
    private func access(_ session: MerchantMarketingScope) async throws -> MerchantMarketingAccess {
        try MerchantMarketingAccess(await request("api/merchant/access/me", session: session))
    }
    public func dashboard() async throws -> MerchantMarketingDashboard {
        let session = try captured(), access = try await access(session)
        guard access.canReadMarketing else { throw MerchantMarketingFailure.denied }
        return try MerchantMarketingDashboard(await request("api/merchant/marketing-home", session: session))
    }
    public func insight() async throws -> MerchantMarketingInsight {
        guard permitsInsight else { throw MerchantMarketingFailure.unavailable }
        let session = try captured()
        // This source endpoint resolves merchant identity from the session; no merchantId payload.
        return try MerchantMarketingInsight(await request("api/ai/merchant/insight", session: session))
    }
    public func subscriptions() async throws -> [MerchantMarketingEntitlement] {
        let session = try captured(), raw = try await request("api/merchant/subscription", body: [:], session: session)
        guard let rows = raw.array else { throw MerchantMarketingFailure.malformed }
        return try rows.map(MerchantMarketingEntitlement.init)
    }
    public func commerce() async throws -> MerchantMarketingCommerce {
        let session = try captured()
        return try MerchantMarketingCommerce(await request("api/merchant/commerce/capabilities", body: [:], session: session))
    }
    private func rounds(_ session: MerchantMarketingScope) async throws -> [MerchantPredictionRound] {
        let raw = try await request("api/merchant/predict/inbox", body: [:], session: session)
        guard let rows = raw.array else { throw MerchantMarketingFailure.malformed }
        let rounds = try rows.map(MerchantPredictionRound.init)
        guard Set(rounds.map(\.id)).count == rounds.count else { throw MerchantMarketingFailure.malformed }
        return rounds
    }
    public func inbox() async throws -> [MerchantPredictionRound] {
        let session = try captured(), access = try await access(session)
        guard access.canSettlePrediction else { throw MerchantMarketingFailure.denied }
        return try await rounds(session)
    }
    public func prepare(round: MerchantPredictionRound, optionKey: String) async throws -> MerchantPredictionReview {
        guard !submitting else { throw MerchantMarketingFailure.locked }
        issued = nil
        guard permitsSettlement else { throw MerchantMarketingFailure.unavailable }
        let session = try captured(), access = try await access(session)
        guard access.canSettlePrediction else { throw MerchantMarketingFailure.denied }
        let current = try await rounds(session)
        guard current.contains(round), let option = round.options.first(where: { $0.key == optionKey }) else { throw MerchantMarketingFailure.stale }
        let review = MerchantPredictionReview(scope: session, access: access, round: round, option: option)
        guard let locks, !(try locks.contains(MerchantPredictionLock(review))) else { throw MerchantMarketingFailure.locked }
        try ensure(session); issued = review; return review
    }
    public func discardReview() { issued = nil }
    public func settle(_ review: MerchantPredictionReview, acknowledgedCouponEffects: Bool) async throws -> MerchantPredictionAcknowledgement {
        guard permitsSettlement else { throw MerchantMarketingFailure.unavailable }
        guard acknowledgedCouponEffects, issued == review else { throw MerchantMarketingFailure.invalid }
        guard !submitting else { throw MerchantMarketingFailure.locked }
        submitting = true; defer { submitting = false }
        try ensure(review.scope)
        let freshAccess = try await access(review.scope)
        guard freshAccess == review.access, freshAccess.canSettlePrediction else { issued = nil; throw MerchantMarketingFailure.stale }
        let current = try await rounds(review.scope)
        guard current.contains(review.round), issued == review else { issued = nil; throw MerchantMarketingFailure.stale }
        guard let locks else { throw MerchantMarketingFailure.storage }
        let record = try MerchantPredictionLock(review)
        try ensure(review.scope)
        try locks.acquire(record) // Durable intent BEFORE dispatch; survives epoch changes and relaunch.
        issued = nil
        do {
            let data = try await request("api/merchant/predict/settle", body: [
                "nodeId": .string(review.round.nodeID), "playDay": .string(review.round.playDay), "settledOption": .string(review.option.key)
            ], session: review.scope)
            guard let winners = data["winners"].integer, winners >= 0 else { throw MerchantMarketingFailure.malformed }
            // Keep a terminal replay lock. Inbox disappearance is not a settlement receipt.
            return MerchantPredictionAcknowledgement(winners: winners)
        } catch let error as MerchantMarketingFailure {
            if case .rejected(let code, _) = error, (400..<500).contains(code), code != 408 {
                try locks.releaseRejected(record); throw error
            }
            // 401 can revoke/change the session; conservatively retain lock and hide its outcome.
            if error == .stale || error == .signIn { throw error }
            throw MerchantMarketingFailure.unknown
        } catch { throw MerchantMarketingFailure.unknown }
    }
}
