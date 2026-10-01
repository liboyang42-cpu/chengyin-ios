import Foundation

/// Only registration list/info reads. No issuance, verification, payment, refund or mutation path.
public struct TicketWalletService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    public func list(lane: TicketWalletLane, token: String) async throws -> [TicketWalletTicket] {
        let data = try await post("api/registration/list", fields: ["owner_type": String(lane.rawValue)], token: token)
        switch lane {
        case .route: return try decode(RouteEnvelope.self, data).rows
        case .activity: return try decode(ActivityEnvelope.self, data).data ?? []
        }
    }
    public func wallet(token: String) async throws -> TicketWalletSnapshot {
        // Independent reads, stable merge order regardless of response timing.
        async let route = outcome(lane: .route, token: token)
        async let activity = outcome(lane: .activity, token: token)
        let results = await (route, activity)
        try Task.checkCancellation()
        // A current authorization failure always closes the private wallet, even if one half succeeds.
        for result in [results.0, results.1] {
            if case .failure(let error) = result {
                if error is CancellationError { throw error }
                if error as? APIError == .unauthorized { throw APIError.unauthorized }
            }
        }
        switch results {
        case (.success(let a), .success(let b)): return TicketWalletSnapshot(tickets: a + b)
        case (.failure(let error), .success(let b)):
            return TicketWalletSnapshot(tickets: b, partialFailure: TicketWalletLaneFailure(lane: .route, issue: TicketWalletIssue(error)))
        case (.success(let a), .failure(let error)):
            return TicketWalletSnapshot(tickets: a, partialFailure: TicketWalletLaneFailure(lane: .activity, issue: TicketWalletIssue(error)))
        case (.failure(let routeError), .failure): throw routeError
        }
    }
    public func detail(id: Int, token: String) async throws -> TicketWalletTicket {
        guard id > 0 else { throw APIError.invalidRequest }
        let data = try await post("api/registration/info", fields: ["id": String(id)], token: token)
        guard let result = try decode(DetailEnvelope.self, data).data, result.id == id else { throw TicketWalletReadFailure.unavailable }
        return result
    }
    private func outcome(lane: TicketWalletLane, token: String) async -> Result<[TicketWalletTicket], Error> {
        do { return .success(try await list(lane: lane, token: token)) }
        catch { return .failure(error) }
    }
    private func post(_ path: String, fields: [String: String], token: String) async throws -> Data {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        try Task.checkCancellation()
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: fields, token: token)
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        let envelope = try decode(StatusEnvelope.self, data)
        if envelope.code == 401 { throw APIError.unauthorized }
        guard envelope.code == 200 else { throw TicketWalletReadFailure.rejected(code: envelope.code, message: envelope.message) }
        return data
    }
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw APIError.malformedResponse }
    }
    private struct StatusEnvelope: Decodable {
        let code: Int
        let message: String?
        enum CodingKeys: String, CodingKey { case code, msg }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decode(Int.self, forKey: .code)
            // Malformed message prose must not obscure an authorization status.
            message = try? c.decode(String.self, forKey: .msg)
        }
    }
    private struct ActivityEnvelope: Decodable { let data: [TicketWalletTicket]? }
    private struct DetailEnvelope: Decodable { let data: TicketWalletTicket? }
    private struct RouteEnvelope: Decodable {
        let rows: [TicketWalletTicket]
        enum CodingKeys: String, CodingKey { case data }
        struct Page: Decodable { let rows: [TicketWalletTicket]? }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard c.contains(.data), try !c.decodeNil(forKey: .data) else { rows = []; return }
            if let array = try? c.decode([TicketWalletTicket].self, forKey: .data) { rows = array }
            else { rows = try c.decode(Page.self, forKey: .data).rows ?? [] }
        }
    }
}
