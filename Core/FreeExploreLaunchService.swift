import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct FreeExploreLaunchSession: Equatable {
    public let baseURL: URL
    public let accountID: FreeExploreLaunchID
    public let market: String
    public let namespace: String
    public let role: String
    public let epoch: UInt64
    private let token: String
    public init(baseURL: URL, accountID: Int64, market: String, namespace: String, role: String, epoch: UInt64, token: String) throws {
        _ = try APIConfiguration(baseURL: baseURL)
        guard !market.isEmpty, !namespace.isEmpty, !role.isEmpty, AuthRequestBuilder.isValidToken(token) else { throw FreeExploreLaunchFailure.invalid }
        self.baseURL = baseURL; self.accountID = try FreeExploreLaunchID(accountID)
        self.market = market; self.namespace = namespace; self.role = role; self.epoch = epoch; self.token = token
    }
    // Durable identity survives token/epoch changes, but never realm/market/account changes.
    var ownerKey: String {
        [baseURL.absoluteString, market, namespace, accountID.text].map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
    }
    fileprivate var credential: String { token }
}

@MainActor public protocol FreeExploreLaunchServing: AnyObject {
    var session: FreeExploreLaunchSession { get }
    var isCurrent: Bool { get }
    var permitsReservationDispatch: Bool { get }
    func catalog(topicID: FreeExploreLaunchID) async throws -> FreeExploreLaunchCatalog
    func order(registrationID: FreeExploreLaunchID) async throws -> FreeExploreLaunchOrder
    func reserve(_ command: FreeExploreLaunchReservationCommand) async throws -> FreeExploreLaunchReservation
    func receipt(_ command: FreeExploreLaunchReservationCommand) async throws -> FreeExploreLaunchReservation?
    func refundQuote(registrationID: FreeExploreLaunchID) async throws -> FreeExploreLaunchRefundQuote
}

public extension FreeExploreLaunchServing {
    /// Existing readers remain read-only unless their own dispatch gate explicitly permits it.
    var permitsReservationDispatch: Bool { false }
}

/// Frozen backend 58f4cc4. No checkout, payment, refund execution, redemption or passport.
@MainActor public final class FreeExploreLaunchService: FreeExploreLaunchServing {
    public let session: FreeExploreLaunchSession
    private let transport: any HTTPTransport
    private let currentSession: () -> FreeExploreLaunchSession?
    private let reservationAllowed: () -> Bool
    private let onUnauthorized: (FreeExploreLaunchSession) -> Void
    public var isCurrent: Bool { currentSession() == session }
    public var permitsReservationDispatch: Bool { isCurrent && reservationAllowed() }
    public init(session: FreeExploreLaunchSession, transport: any HTTPTransport,
                currentSession: @escaping () -> FreeExploreLaunchSession?,
                reservationAllowed: @escaping () -> Bool = { false },
                onUnauthorized: @escaping (FreeExploreLaunchSession) -> Void = { _ in }) {
        self.session = session; self.transport = transport; self.currentSession = currentSession
        self.reservationAllowed = reservationAllowed; self.onUnauthorized = onUnauthorized
    }
    private func check() throws {
        guard isCurrent else { throw FreeExploreLaunchFailure.staleSession }
        try Task.checkCancellation()
    }
    public func catalog(topicID: FreeExploreLaunchID) async throws -> FreeExploreLaunchCatalog {
        let value: FreeExploreLaunchCatalog = try await get("catalog", ["topicId": topicID.text])
        guard value.topicId == topicID, value.productType == 2,
              Set(value.items.map(\.chapterId)).count == value.items.count,
              value.items.allSatisfy({ $0.unitsPerHolder > 0 && Set($0.stores.map(\.offerId)).count == $0.stores.count }) else { throw FreeExploreLaunchFailure.malformed }
        return value
    }
    public func order(registrationID: FreeExploreLaunchID) async throws -> FreeExploreLaunchOrder {
        let value: FreeExploreLaunchOrder = try await get("order", ["registrationId": registrationID.text])
        try value.validate(owner: session.accountID, registration: registrationID); return value
    }
    public func refundQuote(registrationID: FreeExploreLaunchID) async throws -> FreeExploreLaunchRefundQuote {
        // No local threshold, price, ratio, route or approval calculation.
        try await get("order/refund-quote", ["registrationId": registrationID.text])
    }
    public func receipt(_ command: FreeExploreLaunchReservationCommand) async throws -> FreeExploreLaunchReservation? {
        try command.validate()
        let value: FreeExploreLaunchReservation? = try await getOptional("reservation/receipt", ["idempotencyKey": command.idempotencyKey])
        if let value, !value.matches(command, owner: session.accountID) { throw FreeExploreLaunchFailure.malformed }
        return value
    }
    public func reserve(_ command: FreeExploreLaunchReservationCommand) async throws -> FreeExploreLaunchReservation {
        try check(); guard permitsReservationDispatch else { throw FreeExploreLaunchFailure.disabled }
        let body = try command.wireData()
        var request = try make("reservation", fields: [:]); request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        try check(); guard permitsReservationDispatch else { throw FreeExploreLaunchFailure.disabled }
        let value: FreeExploreLaunchReservation = try await execute(request)
        guard value.matches(command, owner: session.accountID) else { throw FreeExploreLaunchFailure.malformed }
        return value
    }
    /// The frozen controller has cancel, but no cancel-quote or expectedOutcome guard.
    /// A local 12-hour calculation cannot replace a server quote/confirmation.
    public func cancellationQuote(reservationID: FreeExploreLaunchID, useWaiver: Bool) throws -> Never {
        try check(); throw FreeExploreLaunchFailure.cancellationQuoteUnavailable
    }
    private func get<T: Decodable>(_ path: String, _ fields: [String: String]) async throws -> T {
        guard let value: T = try await getOptional(path, fields) else { throw FreeExploreLaunchFailure.malformed }
        return value
    }
    private func getOptional<T: Decodable>(_ path: String, _ fields: [String: String]) async throws -> T? {
        try check(); return try await executeOptional(make(path, fields: fields))
    }
    private func make(_ path: String, fields: [String: String]) throws -> URLRequest {
        var url = URLComponents(url: session.baseURL.appendingPathComponent("api/free-explore/bundle/" + path), resolvingAgainstBaseURL: false)!
        if !fields.isEmpty { url.queryItems = fields.keys.sorted().map { URLQueryItem(name: $0, value: fields[$0]) } }
        guard let endpoint = url.url else { throw FreeExploreLaunchFailure.invalid }
        var request = URLRequest(url: endpoint); request.httpMethod = "GET"; request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(session.credential, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        return request
    }
    private struct Code: Decodable { let code: Int; let businessCode: String? }
    private struct Envelope<T: Decodable>: Decodable { let data: T? }
    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        guard let value: T = try await executeOptional(request) else { throw FreeExploreLaunchFailure.malformed }
        return value
    }
    private func executeOptional<T: Decodable>(_ request: URLRequest) async throws -> T? {
        try check()
        do {
            let (data, status) = try await transport.send(request)
            try check()
            if status == 401 { onUnauthorized(session); throw APIError.unauthorized }
            guard data.count <= 1_048_576 else { throw FreeExploreLaunchFailure.malformed }
            let decoder = JSONDecoder()
            let header = try? decoder.decode(Code.self, from: data)
            if header?.code == 401 { onUnauthorized(session); throw APIError.unauthorized }
            guard (200..<300).contains(status), header?.code == 200 else {
                throw FreeExploreLaunchFailure.response(status: status, code: header?.code ?? status, businessCode: header?.businessCode)
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object.keys.contains("data") else {
                throw FreeExploreLaunchFailure.malformed
            }
            return try decoder.decode(Envelope<T>.self, from: data).data
        } catch {
            // Expiry callback may invalidate the captured session; preserve the 401 for its caller.
            if error as? APIError == .unauthorized { throw error }
            try check(); throw error
        }
    }
}
