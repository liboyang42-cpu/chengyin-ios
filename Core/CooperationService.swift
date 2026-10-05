import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Allowlisted read-only JSON POST routes. No financial, contact, invite dispatch or mutation API.
public struct CooperationService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    public func invitations(token: String) async throws -> CooperationInvites {
        try await object("api/coop/list", token: token)
    }
    public func detail(key: CooperationInviteKey, token: String) async throws -> CooperationInviteDetail {
        guard key.id > 0 else { throw APIError.invalidRequest }
        let list = try await invitations(token: token)
        let matches = list.rows(key.direction).filter { $0.id == key.id }
        guard let row = matches.first else { throw CooperationReadFailure.unavailable }
        guard matches.count == 1 else { throw CooperationReadFailure.ambiguousIdentity }
        return CooperationInviteDetail(row: row, occupancy: list.occupancy(for: row))
    }
    public func applications(direction: CooperationDirection, token: String) async throws -> [CooperationApplication] {
        // Bare data array, NOT pool/list.rows. Historical processed applications must remain visible.
        try await object(direction == .sent ? "api/coop/pool/mine" : "api/coop/pool/received", token: token)
    }
    public func registrations(token: String) async throws -> CooperationRegistrations {
        // Object data.rows plus hasMore, NOT a bare list and NOT club applications.
        try await object("api/coop/candidates/received", token: token)
    }
    public func pool(token: String) async throws -> CooperationPool {
        try await object("api/coop/pool/list", token: token)
    }
    public func candidates(topicID: Int, token: String) async throws -> CooperationCandidates {
        guard topicID > 0 else { throw APIError.invalidRequest }
        return try await object("api/coop/candidates", fields: ["topicId": topicID], token: token)
    }
    public func inbox(direction: CooperationDirection, token: String) async throws -> CooperationInbox {
        async let invites = outcome { try await invitations(token: token) }
        async let applies = outcome { try await applications(direction: direction, token: token) }
        async let regs: Result<CooperationRegistrations?, Error> = outcome {
            direction == .received ? try await registrations(token: token) : nil
        }
        let results = await (invites, applies, regs)
        try Task.checkCancellation()
        // A private read may not show any successful sibling after an authentication failure.
        try requireAuthorized(results.0); try requireAuthorized(results.1); try requireAuthorized(results.2)
        let regSection: CooperationSection<CooperationRegistrations>?
        switch results.2 {
        case .success(let value): regSection = value.map { .content($0) }
        case .failure(let error): regSection = .failure(CooperationIssue(error))
        }
        return CooperationInbox(direction: direction, invitations: section(results.0), applications: section(results.1), registrations: regSection)
    }
    private func outcome<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }
    private func requireAuthorized<T>(_ result: Result<T, Error>) throws {
        if case .failure(let error) = result {
            if error is CancellationError { throw error }
            if error as? APIError == .unauthorized { throw error }
        }
    }
    private func section<T>(_ result: Result<T, Error>) -> CooperationSection<T> {
        switch result { case .success(let value): return .content(value); case .failure(let error): return .failure(CooperationIssue(error)) }
    }
    private func object<T: Decodable>(_ path: String, fields: [String: Int] = [:], token: String) async throws -> T {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        try Task.checkCancellation()
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: [:], token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        let envelope = try? JSONDecoder().decode(Status.self, from: data)
        if status == 401 || envelope?.code == 401 { throw APIError.unauthorized }
        if status == 403 || envelope?.code == 403 { throw CooperationReadFailure.forbidden(message: envelope?.msg) }
        guard (200..<300).contains(status) else { throw CooperationReadFailure.httpStatus(status, message: envelope?.msg) }
        guard let code = envelope?.code else { throw APIError.malformedResponse }
        guard code == 200 else {
            // The audited candidate-owner denial is a normal permission state even with business code 500.
            if path == "api/coop/candidates", envelope?.msg == "仅主题发布者可查看候选池" {
                throw CooperationReadFailure.forbidden(message: envelope?.msg)
            }
            throw CooperationReadFailure.rejected(code: code, message: envelope?.msg)
        }
        do { return try JSONDecoder().decode(Envelope<T>.self, from: data).data }
        catch { throw APIError.malformedResponse }
    }
    private struct Envelope<T: Decodable>: Decodable { let data: T }
    private struct Status: Decodable {
        let code: Int?
        let msg: String?
        enum CodingKeys: String, CodingKey { case code, msg }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try? c.decode(Int.self, forKey: .code); msg = try? c.decode(String.self, forKey: .msg)
        }
    }
}
