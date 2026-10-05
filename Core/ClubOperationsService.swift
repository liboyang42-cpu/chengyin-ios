import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exact Flutter routes. Mutation dispatch requires separate scoped approval and a durable journal.
public struct ClubOperationsService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    func snapshot(target: ClubOperationsTarget, token: String, accountID: Int, checkSession: () throws -> Void) async throws -> ClubOperationsSnapshot {
        try checkSession()
        switch target {
        case .create:
            let account = try await AuthService(configuration: configuration, transport: transport).currentAccount(token: token)
            try checkSession()
            guard account.id == accountID else { throw APIError.unauthorized }
            var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/club/my"), fields: [:], token: token)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = Data("{}".utf8)
            let (data, status) = try await transport.send(request)
            try checkSession(); try Self.validateRead(data: data, status: status)
            let owned: [ClubRecord]
            do { owned = try JSONDecoder().decode(OwnedEnvelope.self, from: data).data.owned }
            catch { throw APIError.malformedResponse }
            try checkSession()
            guard Set(owned.map(\.id)).count == owned.count, owned.allSatisfy(\.isOwner) else { throw APIError.malformedResponse }
            return .init(target: target, accountRole: account.effectiveRole, ownedClubIDs: owned.map(\.id))
        case .club(let id):
            guard id > 0 else { throw APIError.invalidRequest }
            let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/club/detail"), fields: ["id": String(id)], token: token)
            let (data, status) = try await transport.send(request)
            try checkSession(); try Self.validateRead(data: data, status: status)
            let profile: ClubOperationsProfile
            do { profile = try JSONDecoder().decode(ProfileEnvelope.self, from: data).data }
            catch { throw APIError.malformedResponse }
            guard profile.club.id == id else { throw APIError.malformedResponse }
            guard profile.club.canGovern else { throw ClubReadFailure.forbidden(message: nil) }
            let members: [ClubMember]
            if profile.club.isOwner {
                let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/club/members"), fields: ["clubId": String(id)], token: token)
                let (data, status) = try await transport.send(request)
                try checkSession(); try Self.validateRead(data: data, status: status)
                do { members = try JSONDecoder().decode(MembersEnvelope.self, from: data).data.map(\.member) }
                catch { throw APIError.malformedResponse }
            } else { members = [] }
            try checkSession()
            guard Set(members.map(\.id)).count == members.count else { throw APIError.malformedResponse }
            return .init(target: target, profile: profile, members: members)
        }
    }
    /// Exact JSON request construction shared by review tests and dormant dispatch.
    func makeReviewRequest(_ command: ClubOperationsCommand, snapshot: ClubOperationsSnapshot,
                           identity: ClubReadIdentity, token: String) throws -> URLRequest {
        let fields = try command.fields(snapshot: snapshot, identity: identity)
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(command.path), fields: [:], token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        return request
    }
    /// Dispatch must classify all post-dispatch transport/cancellation failures
    /// as unknown and must NOT retry. Kept standalone to test exact acknowledgment shape.
    static func decodeReceipt(command: ClubOperationsCommand, data: Data, status: Int) throws -> ClubOperationsReceipt {
        let envelope = try? JSONDecoder().decode(StatusEnvelope.self, from: data)
        let failure = ClubActionResponseFailure(httpStatus: (200..<300).contains(status) ? nil : status, code: envelope?.code, message: envelope?.msg)
        if status == 401 || status == 403 { throw ClubActionWriteError.rejected(failure) }
        guard (200..<300).contains(status) else { throw ClubActionWriteError.outcomeUnknown(.response(failure)) }
        guard let code = envelope?.code else { throw ClubActionWriteError.outcomeUnknown(.malformedResponse) }
        guard code == 200 else { throw ClubActionWriteError.rejected(failure) }
        switch command {
        case .create:
            let result = try? JSONDecoder().decode(CreateEnvelope.self, from: data)
            let id = result?.data?.clubId ?? result?.data?.id
            // Source acknowledges creation even when no ID is returned. Never invent one.
            if let id, id <= 0 { throw ClubActionWriteError.outcomeUnknown(.malformedResponse) }
            return .init(clubID: id, message: envelope?.msg)
        case .openSetting(let setting, _, _):
            guard let values = try? JSONDecoder().decode(SettingEnvelope.self, from: data),
                  let value = values.data.value(setting), [0, 1].contains(value) else {
                throw ClubActionWriteError.outcomeUnknown(.malformedResponse)
            }
            return .init(message: envelope?.msg, settingValue: value == 1)
        case .update, .memberRole: return .init(message: envelope?.msg)
        }
    }
    func isApproved(_ approval: OperationEndpointApproval, session: ClubOperationsSession, path: String) -> Bool {
        guard let accountID = session.identity.accountID else { return false }
        return approval.allows(configuration: configuration, namespace: session.storageNamespace, accountID: accountID, path: path)
    }
    /// No automatic retry. Any ambiguous post-dispatch failure retains the local replay lock.
    func dispatch(_ command: ClubOperationsCommand, snapshot: ClubOperationsSnapshot, session: ClubOperationsSession,
                  checkSession: () throws -> Void) async throws -> ClubOperationsReceipt {
        let request: URLRequest
        do { try checkSession(); request = try makeReviewRequest(command, snapshot: snapshot, identity: session.identity, token: session.token); try checkSession() }
        catch { throw ClubActionWriteError.notSent(.invalidRequest) }
        do {
            let (data, status) = try await transport.send(request)
            try checkSession()
            return try Self.decodeReceipt(command: command, data: data, status: status)
        } catch let error as ClubActionWriteError { throw error }
        catch { throw ClubActionWriteError.outcomeUnknown(error is CancellationError ? .cancelled : .transport) }
    }
    private static func validateRead(data: Data, status: Int) throws {
        let envelope = try? JSONDecoder().decode(StatusEnvelope.self, from: data)
        if status == 401 || envelope?.code == 401 { throw ClubReadFailure.unauthorized(message: envelope?.msg) }
        if status == 403 || envelope?.code == 403 { throw ClubReadFailure.forbidden(message: envelope?.msg) }
        guard (200..<300).contains(status) else { throw ClubReadFailure.httpStatus(status, message: envelope?.msg) }
        guard let code = envelope?.code else { throw APIError.malformedResponse }
        guard code == 200 else { throw ClubReadFailure.rejected(code: code, message: envelope?.msg) }
    }
    /// Membership writes require explicit role and owner facts, not legacy decoder defaults.
    private struct MembersEnvelope: Decodable {
        let data: [Row]
        struct Row: Decodable {
            let member: ClubMember
            enum CodingKeys: String, CodingKey { case role, isOwner }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                _ = try c.decode(Int.self, forKey: .role)
                _ = try c.decode(Bool.self, forKey: .isOwner)
                member = try ClubMember(from: decoder)
            }
        }
    }
    private struct ProfileEnvelope: Decodable { let data: ClubOperationsProfile }
    private struct StatusEnvelope: Decodable {
        let code: Int?; let msg: String?
        enum CodingKeys: String, CodingKey { case code, msg }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try? c.decode(Int.self, forKey: .code); msg = try? c.decode(String.self, forKey: .msg)
        }
    }
    private struct CreateEnvelope: Decodable {
        let data: Created?
        struct Created: Decodable { let id: Int?; let clubId: Int? }
    }
    private struct OwnedEnvelope: Decodable { let data: Owned; struct Owned: Decodable { let owned: [ClubRecord] } }
    private struct SettingEnvelope: Decodable {
        let data: Values
        struct Values: Decodable {
            let publicVisible: Int?; let memberPostAllowed: Int?; let merchantUndertakeOpen: Int?
            func value(_ setting: ClubOpenSetting) -> Int? {
                switch setting { case .publicVisible: return publicVisible; case .memberPostAllowed: return memberPostAllowed; case .merchantUndertakeOpen: return merchantUndertakeOpen }
            }
        }
    }
}

public struct ClubOperationsSession: Equatable {
    public let identity: ClubReadIdentity
    private(set) var token: String
    public let storageNamespace: String
    public var ownerKey: String { "\(storageNamespace.utf8.count):\(storageNamespace):\(identity.accountID ?? 0)" }
    public init(accountID: Int, epoch: UInt64, token: String, storageNamespace: String = "") throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.identity = .init(accountID: accountID, epoch: epoch); self.token = token; self.storageNamespace = storageNamespace
    }
}
@MainActor public final class ClubOperationsSessionAccess: ClubOperationsAccess {
    private let service: ClubOperationsService?
    private let currentSession: () -> ClubOperationsSession?
    private let onUnauthorized: (ClubOperationsSession) -> Void
    private let approval: OperationEndpointApproval?
    private let journal: (any OperationPendingJournal)?
    public var identity: ClubReadIdentity? { currentSession()?.identity }
    public var isConfigured: Bool { service != nil }
    public var writeAvailability: ClubOperationsWriteAvailability { approval != nil && journal != nil ? .approved : .unverified }
    public init(service: ClubOperationsService?, currentSession: @escaping () -> ClubOperationsSession?, approval: OperationEndpointApproval? = nil, journal: (any OperationPendingJournal)? = nil, onUnauthorized: @escaping (ClubOperationsSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized; self.approval = approval; self.journal = journal
    }
    public func snapshot(target: ClubOperationsTarget) async throws -> ClubOperationsSnapshot {
        guard let service else { throw APIError.notConfigured }
        guard let session = currentSession(), let accountID = session.identity.accountID else { throw APIError.unauthorized }
        do {
            return try await service.snapshot(target: target, token: session.token, accountID: accountID) { try self.check(session) }
        } catch {
            try check(session)
            if (error as? ClubReadFailure)?.isUnauthorized == true || (error as? APIError) == .unauthorized { onUnauthorized(session) }
            throw error
        }
    }
    private func check(_ session: ClubOperationsSession) throws {
        try Task.checkCancellation()
        guard currentSession() == session else { throw CancellationError() }
    }
    private func targetKey(_ target: ClubOperationsTarget) -> String {
        switch target { case .create: return "club:create"; case .club(let id): return "club:\(id)" }
    }
    public func hasPending(target: ClubOperationsTarget) -> Bool {
        guard let session = currentSession(), let journal else { return false }
        do { return try journal.pending(ownerKey: session.ownerKey, targetKey: targetKey(target)) != nil }
        catch { return true }
    }
    public func perform(_ command: ClubOperationsCommand, target: ClubOperationsTarget, expectedIdentity: ClubReadIdentity) async throws -> ClubOperationsReceipt {
        guard let service, let approval, let journal, let session = currentSession(), session.identity == expectedIdentity,
              service.isApproved(approval, session: session, path: command.path) else { throw ClubActionWriteError.notSent(.notConfigured) }
        let fresh: ClubOperationsSnapshot
        var record = OperationPendingRecord(ownerKey: session.ownerKey, targetKey: targetKey(target))
        do {
            try check(session)
            guard try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == nil else { throw ClubOperationsBlock.pending }
            fresh = try await snapshot(target: target); try check(session)
            guard fresh.target == target else { throw ClubOperationsBlock.changed }
            try command.validate(snapshot: fresh, identity: expectedIdentity)
            guard try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == nil else { throw ClubOperationsBlock.pending }
            try journal.write(record); try check(session)
        } catch { throw ClubActionWriteError.preflightFailed }
        do {
            let receipt = try await service.dispatch(command, snapshot: fresh, session: session) { try self.check(session) }
            try check(session)
            record.acknowledgedSteps = 1; try journal.write(record); try journal.clear(record)
            return receipt
        } catch {
            // Changed credentials/cancellation after dispatch cannot be declared not sent.
            guard currentSession() == session, !Task.isCancelled else { throw ClubActionWriteError.outcomeUnknown(.accountChanged) }
            if let failure = error as? ClubActionWriteError {
                switch failure {
                case .rejected(let response):
                    do { try journal.clear(record) } catch { throw ClubActionWriteError.outcomeUnknown(.transport) }
                    if response.isUnauthorized { onUnauthorized(session) }
                case .notSent, .cancelledBeforeDispatch:
                    do { try journal.clear(record) } catch { throw ClubActionWriteError.outcomeUnknown(.transport) }
                default: break
                }
                throw failure
            }
            throw ClubActionWriteError.outcomeUnknown(.transport)
        }
    }
}
