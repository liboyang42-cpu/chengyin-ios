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
    private var reviewGeneration = UUID()
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
    private func request(_ path: String, query: [URLQueryItem] = [], body: [String: MerchantMarketingValue]? = nil, session: MerchantMarketingScope, isCurrent: () -> Bool = { true }) async throws -> MerchantMarketingValue {
        guard isCurrent() else { throw MerchantMarketingFailure.stale }
        try ensure(session)
        guard let configuration, permitsReads else { throw MerchantMarketingFailure.unavailable }
        var url = configuration.baseURL.appendingPathComponent(path)
        if !query.isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw MerchantMarketingFailure.invalid }
            components.queryItems = query
            guard let built = components.url else { throw MerchantMarketingFailure.invalid }
            url = built
        }
        var request = try AuthRequestBuilder.makeFormRequest(url: url, fields: [:], token: session.token, includesBody: false)
        request.httpMethod = "POST"
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONEncoder().encode(body) }
        let result: (Data, Int)
        do { result = try await transport.send(request) }
        catch {
            guard isCurrent() else { throw MerchantMarketingFailure.stale }
            try ensure(session); throw error
        }
        guard isCurrent() else { throw MerchantMarketingFailure.stale }
        try ensure(session)
        return try response(result.0, status: result.1, session: session)
    }
    private func response(_ bytes: Data, status: Int, session: MerchantMarketingScope) throws -> MerchantMarketingValue {
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
    private func access(_ session: MerchantMarketingScope, isCurrent: () -> Bool = { true }) async throws -> MerchantMarketingAccess {
        try MerchantMarketingAccess(await request("api/merchant/access/me", session: session, isCurrent: isCurrent))
    }
    public func dashboard() async throws -> MerchantMarketingDashboard {
        let session = try captured(), access = try await access(session)
        guard access.canReadMarketing else { throw MerchantMarketingFailure.denied }
        return try MerchantMarketingDashboard(await request("api/merchant/marketing-home", session: session))
    }
    /// Source marketing/index.js: the window is a query parameter (`@RequestParam windowDays`), fixed at 30 days.
    public func home(isCurrent: () -> Bool = { true }) async throws -> (MerchantMarketingAccess, MerchantMarketingHome) {
        let session = try captured(), access = try await access(session, isCurrent: isCurrent)
        guard access.canReadMarketing else { throw MerchantMarketingFailure.denied }
        let raw = try await request("api/merchant/marketing-home", query: [URLQueryItem(name: "windowDays", value: String(MerchantMarketingHome.windowDays))],
                                    session: session, isCurrent: isCurrent)
        return (access, try MerchantMarketingHome(raw))
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
    private func rounds(_ session: MerchantMarketingScope, isCurrent: () -> Bool = { true }) async throws -> [MerchantPredictionRound] {
        let raw = try await request("api/merchant/predict/inbox", session: session, isCurrent: isCurrent)
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
        issued = nil; reviewGeneration = UUID(); let generation = reviewGeneration
        guard permitsReads else { throw MerchantMarketingFailure.unavailable }
        let currentReview = { [self] in reviewGeneration == generation }
        let session = try captured(), access = try await access(session, isCurrent: currentReview)
        guard access.canSettlePrediction else { throw MerchantMarketingFailure.denied }
        let current = try await rounds(session, isCurrent: currentReview)
        guard current.contains(round), let option = round.options.first(where: { $0.key.utf8.elementsEqual(optionKey.utf8) }) else { throw MerchantMarketingFailure.stale }
        let review = MerchantPredictionReview(scope: session, access: access, round: round, option: option)
        if let locks, try locks.contains(MerchantPredictionLock(review)) { throw MerchantMarketingFailure.locked }
        try ensure(session); guard currentReview() else { throw MerchantMarketingFailure.stale }
        issued = review; return review
    }
    public func discardReview() { issued = nil; reviewGeneration = UUID() }
    private func settlementRequest(_ review: MerchantPredictionReview, isCurrent: () -> Bool) async throws -> MerchantMarketingValue {
        guard permitsSettlement, let configuration else { throw MerchantMarketingFailure.unavailable }
        guard isCurrent() else { throw MerchantMarketingFailure.stale }
        try ensure(review.scope)
        let fields = ["nodeId": review.round.nodeID, "playDay": review.round.playDay, "settledOption": review.option.key]
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func encode(_ value: String) throws -> String {
            guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else { throw MerchantMarketingFailure.invalid }
            return encoded
        }
        let form = try fields.keys.sorted().map { try encode($0) + "=" + encode(fields[$0]!) }.joined(separator: "&")
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/merchant/predict/settle"),
            fields: [:], token: review.scope.token, includesBody: false)
        request.httpMethod = "POST"; request.httpShouldHandleCookies = false
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(form.utf8)
        guard isCurrent() else { throw MerchantMarketingFailure.stale }
        try ensure(review.scope)
        let result: (Data, Int)
        do { result = try await transport.send(request) }
        catch {
            guard isCurrent() else { throw MerchantMarketingFailure.stale }
            try ensure(review.scope); throw error
        }
        guard isCurrent() else { throw MerchantMarketingFailure.stale }
        try ensure(review.scope)
        return try response(result.0, status: result.1, session: review.scope)
    }
    public func settle(_ review: MerchantPredictionReview, acknowledgedCouponEffects: Bool) async throws -> MerchantPredictionAcknowledgement {
        guard permitsSettlement else { throw MerchantMarketingFailure.unavailable }
        guard acknowledgedCouponEffects, issued == review else { throw MerchantMarketingFailure.invalid }
        guard !submitting else { throw MerchantMarketingFailure.locked }
        let generation = reviewGeneration
        let currentReview = { [self] in reviewGeneration == generation }
        issued = nil // Consume once before the first suspension.
        submitting = true; defer { submitting = false }
        try ensure(review.scope)
        let freshAccess = try await access(review.scope, isCurrent: currentReview)
        guard freshAccess == review.access, freshAccess.canSettlePrediction else { throw MerchantMarketingFailure.stale }
        let current = try await rounds(review.scope, isCurrent: currentReview)
        guard current.contains(review.round), currentReview() else { throw MerchantMarketingFailure.stale }
        guard let locks else { throw MerchantMarketingFailure.storage }
        let record = try MerchantPredictionLock(review)
        try ensure(review.scope); guard currentReview() else { throw MerchantMarketingFailure.stale }
        try locks.acquire(record) // Exclusive pre-dispatch intent; no claim of fsync/power-loss durability.
        do {
            let data = try await settlementRequest(review, isCurrent: currentReview)
            // Keep a terminal replay lock. Inbox disappearance is not a settlement receipt.
            return try MerchantPredictionAcknowledgement(data, expectedOption: review.option.key)
        } catch let error as MerchantMarketingFailure {
            // Every potentially dispatched non-success remains locked. Generic HTTP or
            // business rejection never establishes safe retry, including 4xx responses.
            if error == .stale || error == .signIn { throw error }
            throw MerchantMarketingFailure.unknown
        } catch { throw MerchantMarketingFailure.unknown }
    }
}
