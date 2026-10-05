import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor public protocol DoorReferralServing {
    var scanEnabled: Bool { get }
    var bindingEnabled: Bool { get }
    func scan(code: String, session: DoorReferralSession) async throws -> DoorScanResult
    func bind(inviter: Int, session: DoorReferralSession) async throws
}

/// Injectable dormant HTTP adapter. No transport factory or shared session; both capabilities default OFF.
@MainActor public struct DoorReferralService: DoorReferralServing {
    public let scanEnabled: Bool
    public let bindingEnabled: Bool
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let currentSession: () -> DoorReferralSession
    public init(configuration: APIConfiguration, transport: any HTTPTransport,
                scanEnabled: Bool = false, bindingEnabled: Bool = false,
                currentSession: @escaping () -> DoorReferralSession) {
        self.configuration = configuration; self.transport = transport
        self.scanEnabled = scanEnabled; self.bindingEnabled = bindingEnabled; self.currentSession = currentSession
    }
    private struct Envelope: Decodable { let code: Int; let msg: String?; let data: DoorScanResult? }
    private struct Acknowledgement: Decodable { let code: Int; let msg: String? }
    private func request(path: String, field: String, value: String, session: DoorReferralSession) throws -> URLRequest {
        guard session.restored, session == currentSession() else { throw DoorReferralFailure.stale }
        let boundary = "DoorReferral-" + UUID().uuidString
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"; request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = session.token {
            guard AuthRequestBuilder.isValidToken(token) else { throw DoorReferralFailure.invalid }
            request.setValue(token, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(field)\"\r\n\r\n\(value)\r\n--\(boundary)--\r\n".utf8)
        return request
    }
    public func scan(code: String, session: DoorReferralSession) async throws -> DoorScanResult {
        guard scanEnabled else { throw DoorReferralFailure.disabled }
        guard DoorParsing.scene(code) == code else { throw DoorReferralFailure.invalid }
        let request = try request(path: "api/play/scan-entry", field: "code", value: code, session: session)
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        guard session == currentSession() else { throw DoorReferralFailure.stale }
        guard (200..<300).contains(status), let ack = try? JSONDecoder().decode(Acknowledgement.self, from: data) else { throw DoorReferralFailure.unknown }
        guard ack.code == 200 else { throw DoorReferralFailure.rejected(ack.msg ?? "") }
        guard let body = try? JSONDecoder().decode(Envelope.self, from: data), let result = body.data else { throw DoorReferralFailure.unknown }
        return result
    }
    public func bind(inviter: Int, session: DoorReferralSession) async throws {
        guard bindingEnabled else { throw DoorReferralFailure.disabled }
        guard let account = session.accountID, account > 0, inviter > 0, inviter != account, session.token != nil else { throw DoorReferralFailure.invalid }
        let request = try request(path: "api/user/setInviter", field: "inviter_id", value: String(inviter), session: session)
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        guard session == currentSession() else { throw DoorReferralFailure.stale }
        guard (200..<300).contains(status), let body = try? JSONDecoder().decode(Acknowledgement.self, from: data) else { throw DoorReferralFailure.unknown }
        guard body.code == 200 else { throw DoorReferralFailure.rejected("door.inviter.remoteFailure") }
    }
}
