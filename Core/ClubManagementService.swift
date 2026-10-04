import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// All management bodies are JSON, including numeric IDs. No inferred routes or retries.
public struct ClubManagementService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let clubs: ClubService
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
        clubs = ClubService(configuration: configuration, transport: transport)
    }
    func snapshot(clubID: Int, token: String, checkSession: () throws -> Void) async throws -> ClubManagementSnapshot {
        let club = try await clubs.detail(id: clubID, token: token)
        try checkSession()
        guard club.canGovern else { throw ClubReadFailure.forbidden(message: nil) }
        do {
            let request = try makeRequest(path: "api/club/join-requests", fields: ["clubId": clubID], token: token)
            let (data, status) = try await transport.send(request)
            try checkSession()
            try validateRead(data, status)
            let requests: [ClubManagementRequest]
            do { requests = try JSONDecoder().decode(Rows.self, from: data).data }
            catch { throw APIError.malformedResponse }
            // Admins may review applications but may not remove members. Avoid requesting
            // a member list when server membership facts do not permit that read.
            let members = club.isOwner ? try await clubs.members(in: club, token: token) : []
            try checkSession()
            guard Set(requests.map(\.id)).count == requests.count,
                  Set(members.map(\.id)).count == members.count else { throw APIError.malformedResponse }
            return ClubManagementSnapshot(club: club, requests: requests, members: members)
        } catch {
            try checkSession()
            try Task.checkCancellation()
            if let transient = ClubManagementListConnectionFailure(freshClub: club, error: error) { throw transient }
            throw error
        }
    }
    func perform(_ action: ClubManagementAction, clubID: Int, memberID: Int, token: String) async throws -> ClubActionReceipt {
        let request: URLRequest
        do {
            guard clubID > 0, memberID > 0 else { throw APIError.invalidRequest }
            request = try makeRequest(path: action.path, fields: ["clubId": clubID, "memberId": memberID], token: token)
        } catch { throw ClubActionWriteError.notSent(.invalidRequest) }
        guard !Task.isCancelled else { throw ClubActionWriteError.cancelledBeforeDispatch }
        let data: Data, status: Int
        do { (data, status) = try await transport.send(request) }
        catch is CancellationError { throw ClubActionWriteError.outcomeUnknown(.cancelled) }
        catch let error as URLError where error.code == .cancelled { throw ClubActionWriteError.outcomeUnknown(.cancelled) }
        catch { throw ClubActionWriteError.outcomeUnknown(.transport) }
        guard !Task.isCancelled else { throw ClubActionWriteError.outcomeUnknown(.cancelled) }
        let envelope = try? JSONDecoder().decode(Status.self, from: data)
        let failure = ClubActionResponseFailure(httpStatus: (200..<300).contains(status) ? nil : status, code: envelope?.code, message: envelope?.msg)
        if status == 401 || status == 403 { throw ClubActionWriteError.rejected(failure) }
        guard (200..<300).contains(status) else { throw ClubActionWriteError.outcomeUnknown(.response(failure)) }
        guard let code = envelope?.code else { throw ClubActionWriteError.outcomeUnknown(.malformedResponse) }
        guard code == 200 else { throw ClubActionWriteError.rejected(failure) }
        return ClubActionReceipt(state: nil, message: envelope?.msg)
    }
    private func makeRequest(path: String, fields: [String: Int], token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: [:], token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        return request
    }
    private func validateRead(_ data: Data, _ status: Int) throws {
        let envelope = try? JSONDecoder().decode(Status.self, from: data)
        if status == 401 { throw ClubReadFailure.unauthorized(message: envelope?.msg) }
        if status == 403 { throw ClubReadFailure.forbidden(message: envelope?.msg) }
        guard (200..<300).contains(status) else { throw ClubReadFailure.httpStatus(status, message: envelope?.msg) }
        guard let code = envelope?.code else { throw APIError.malformedResponse }
        if code == 401 { throw ClubReadFailure.unauthorized(message: envelope?.msg) }
        if code == 403 { throw ClubReadFailure.forbidden(message: envelope?.msg) }
        guard code == 200 else { throw ClubReadFailure.rejected(code: code, message: envelope?.msg) }
    }
    private struct Rows: Decodable { let data: [ClubManagementRequest] }
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

@MainActor
public final class ClubManagementSessionAccess: ClubManagementAccess {
    private let service: ClubManagementService?
    private let currentSession: () -> ClubManagementSession?
    private let onUnauthorized: (ClubManagementSession) -> Void
    public var identity: ClubReadIdentity? { currentSession()?.identity }
    public var isConfigured: Bool { service != nil }
    public init(service: ClubManagementService?, currentSession: @escaping () -> ClubManagementSession?,
                onUnauthorized: @escaping (ClubManagementSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
    }
    public func snapshot(clubID: Int) async throws -> ClubManagementSnapshot {
        guard let service else { throw APIError.notConfigured }
        guard let session = currentSession() else { throw APIError.unauthorized }
        do {
            try check(session)
            return try await service.snapshot(clubID: clubID, token: session.token) { try self.check(session) }
        } catch {
            try check(session)
            if (error as? ClubReadFailure)?.isUnauthorized == true { onUnauthorized(session) }
            throw error
        }
    }
    private func check(_ session: ClubManagementSession) throws {
        try Task.checkCancellation()
        guard currentSession() == session else { throw CancellationError() }
    }
    public func perform(_ action: ClubManagementAction, clubID: Int, memberID: Int, expectedIdentity: ClubReadIdentity) async throws -> ClubActionReceipt {
        guard let service else { throw ClubActionWriteError.notSent(.notConfigured) }
        guard let session = currentSession(), session.identity == expectedIdentity else { throw ClubActionWriteError.notSent(.unauthorized) }
        let fresh: ClubManagementSnapshot
        do { fresh = try await snapshot(clubID: clubID); try check(session) }
        catch { throw ClubActionWriteError.preflightFailed }
        guard fresh.allows(action, memberID: memberID), action != .remove || memberID != session.identity.accountID else { throw ClubActionWriteError.eligibilityChanged }
        do {
            let receipt = try await service.perform(action, clubID: clubID, memberID: memberID, token: session.token)
            guard currentSession() == session else { throw ClubActionWriteError.outcomeUnknown(.accountChanged) }
            return receipt
        } catch {
            guard currentSession() == session else { throw ClubActionWriteError.outcomeUnknown(.accountChanged) }
            if let writeError = error as? ClubActionWriteError, case .rejected(let failure) = writeError, failure.isUnauthorized { onUnauthorized(session) }
            throw error
        }
    }
}
