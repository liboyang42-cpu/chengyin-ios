import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Keep actionable server text without displaying arbitrary networking/debug descriptions.
public struct ProfileReadFailure: Error, Equatable {
    public let httpStatus: Int?
    public let code: Int?
    public let message: String?
    public var isUnauthorized: Bool { httpStatus == 401 || code == 401 }
    public init(httpStatus: Int? = nil, code: Int? = nil, message: String? = nil) {
        self.httpStatus = httpStatus; self.code = code; self.message = message
    }
}

/// Own-account reads only. No production host, mutations, payment, player-code issuance,
/// retry loop, credential storage, or redirection. Inject the existing no-redirect transport.
public struct ProfileService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }

    public func orders(token: String, expectedAccountID: Int? = nil) async throws -> [ProfileOrder] {
        if let expectedAccountID, expectedAccountID <= 0 { throw APIError.invalidRequest }
        let result: OrderRows = try await execute(form("api/registration/list", fields: ["owner_type": "3"], token: token))
        if let expectedAccountID {
            guard result.isTable, result.total == result.rows.count,
                  result.rows.allSatisfy({ $0.memberID == expectedAccountID }),
                  Set(result.rows.map(\.id)).count == result.rows.count else { throw APIError.malformedResponse }
        }
        return result.rows
    }
    public func order(id: Int, token: String, expectedAccountID: Int? = nil) async throws -> ProfileOrder {
        if let expectedAccountID, expectedAccountID <= 0 { throw APIError.invalidRequest }
        guard id > 0 else { throw APIError.invalidRequest }
        let result: ProfileOrder = try await execute(form("api/registration/info", fields: ["id": String(id)], token: token))
        guard result.id == id else { throw APIError.malformedResponse }
        if let expectedAccountID, result.memberID != expectedAccountID { throw APIError.malformedResponse }
        return result
    }
    public func participants(token: String) async throws -> [ProfileParticipant] {
        let result: ParticipantRows = try await execute(bodyless("api/user/address/list", token: token))
        return result.rows
    }
    public func participant(id: Int, token: String) async throws -> ProfileParticipant {
        guard id > 0 else { throw APIError.invalidRequest }
        let result: ProfileParticipant = try await execute(form("api/user/address/info", fields: ["id": String(id)], token: token))
        guard result.id == id else { throw APIError.malformedResponse }
        return result
    }
    public func badgeWall(token: String) async throws -> ProfileBadgeWall {
        // Identity is the source's required primary collection. A medal failure must not
        // erase those cards or silently present an incomplete wall as a complete result.
        let identities: IdentityWall = try await execute(jsonEmpty("api/badge/wall-v2", token: token))
        do {
            let medals: MedalWall = try await execute(jsonEmpty("api/medal/wall", token: token))
            return ProfileBadgeWall(identities: identities.identity, medals: medals.medals)
        } catch is CancellationError { throw CancellationError() }
        catch let failure as ProfileReadFailure where failure.isUnauthorized { throw failure }
        catch {
            try Task.checkCancellation()
            return ProfileBadgeWall(identities: identities.identity, medals: nil,
                                    medalFailureMessage: (error as? ProfileReadFailure)?.message)
        }
    }

    private func form(_ path: String, fields: [String: String], token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        return try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: fields, token: token)
    }
    private func bodyless(_ path: String, token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        return try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: [:], token: token, includesBody: false)
    }
    private func jsonEmpty(_ path: String, token: String) throws -> URLRequest {
        var request = try bodyless(path, token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        return request
    }
    private func execute<Value: Decodable>(_ request: URLRequest) async throws -> Value {
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if !(200..<300).contains(status) {
            let failure = try? JSONDecoder().decode(FailureEnvelope.self, from: data)
            throw ProfileReadFailure(httpStatus: status, code: failure?.code, message: failure?.msg)
        }
        do { return try JSONDecoder().decode(Envelope<Value>.self, from: data).data }
        catch let error as ProfileReadFailure { throw error }
        catch { throw APIError.malformedResponse }
    }
    private struct FailureEnvelope: Decodable {
        let code: Int?
        let msg: String?
        private enum CodingKeys: String, CodingKey { case code, msg }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = (try? c.decode(Int.self, forKey: .code))
                ?? (try? c.decode(String.self, forKey: .code)).flatMap(Int.init)
            msg = try? c.decode(String.self, forKey: .msg)
        }
    }
    private struct Envelope<Value: Decodable>: Decodable {
        let data: Value
        private enum CodingKeys: String, CodingKey { case code, data, msg }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let code = try? c.decode(Int.self, forKey: .code)
            guard code == 200 else {
                let text = try? c.decode(String.self, forKey: .code)
                throw ProfileReadFailure(code: code ?? text.flatMap(Int.init), message: try? c.decode(String.self, forKey: .msg))
            }
            // An absent/null data object is malformed, not a fabricated empty collection.
            data = try c.decode(Value.self, forKey: .data)
        }
    }
    private struct OrderRows: Decodable {
        let rows: [ProfileOrder]
        let total: Int?
        let isTable: Bool
        private enum CodingKeys: String, CodingKey { case rows, total }
        init(from decoder: Decoder) throws {
            if let array = try? decoder.singleValueContainer().decode([ProfileOrder].self) { rows = array; total = nil; isTable = false }
            else {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                rows = try c.decode([ProfileOrder].self, forKey: .rows)
                total = try c.decodeIfPresent(Int.self, forKey: .total); isTable = true
            }
        }
    }
    private struct ParticipantRows: Decodable { let rows: [ProfileParticipant] }
    private struct IdentityWall: Decodable { let identity: [ProfileIdentityBadge] }
    private struct MedalWall: Decodable { let medals: [ProfileMedal] }
}
