import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct IMVoiceSession: Equatable {
    public let identity: MessagingReadIdentity
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw IMVoiceFailure.invalid }
        identity = .init(accountID: accountID, epoch: epoch); self.token = token
    }
}
@MainActor public final class IMVoiceService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let session: () -> IMVoiceSession?
    private let unauthorized: (IMVoiceSession) -> Void
    public let uploadEnabled: Bool
    public let receiptEnabled: Bool
    public let playbackEnabled: Bool
    public let playbackStatusEnabled: Bool
    public var identity: MessagingReadIdentity? { session()?.identity }
    public init(configuration: APIConfiguration, transport: any HTTPTransport,
                uploadEnabled: Bool = false, receiptEnabled: Bool = false, playbackEnabled: Bool = false, playbackStatusEnabled: Bool = false,
                session: @escaping () -> IMVoiceSession?, unauthorized: @escaping (IMVoiceSession) -> Void = { _ in }) {
        self.configuration = configuration; self.transport = transport; self.uploadEnabled = uploadEnabled
        self.receiptEnabled = receiptEnabled; self.playbackEnabled = playbackEnabled; self.playbackStatusEnabled = playbackStatusEnabled
        self.session = session; self.unauthorized = unauthorized
    }
    public func upload(_ pending: IMVoiceJournal.Pending, scope: IMScope) async throws -> IMVoiceUploadReceipt {
        guard uploadEnabled else { throw IMVoiceFailure.unavailable }; try pending.clip.validate()
        let snapshot = try current(scope)
        let boundary = "imvoice-" + UUID().uuidString
        let fields = ["conversation_id": String(scope.conversationID), "upload_request_id": pending.requestID, "source_sha256": pending.clip.sha256]
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/im/voice/upload"), fields: fields, token: snapshot.token, boundary: boundary)
        guard var body = request.httpBody else { throw IMVoiceFailure.invalid }
        let terminal = Data("--\(boundary)--\r\n".utf8)
        guard body.suffix(terminal.count) == terminal else { throw IMVoiceFailure.invalid }
        body.removeLast(terminal.count)
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"voice.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".utf8))
        body.append(pending.clip.bytes); body.append(Data("\r\n".utf8)); body.append(terminal); request.httpBody = body
        return try await receipt(request, snapshot: snapshot, scope: scope, pending: pending)
    }
    public func recover(_ pending: IMVoiceJournal.Pending, scope: IMScope) async throws -> IMVoiceUploadReceipt {
        guard receiptEnabled else { throw IMVoiceFailure.unavailable }
        let snapshot = try current(scope)
        var components = URLComponents(url: configuration.baseURL.appendingPathComponent("api/im/voice/receipt"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "conversation_id", value: String(scope.conversationID)), URLQueryItem(name: "upload_request_id", value: pending.requestID), URLQueryItem(name: "source_sha256", value: pending.clip.sha256)]
        guard let url = components?.url else { throw IMVoiceFailure.invalid }
        var request = try AuthRequestBuilder.makeFormRequest(url: url, fields: [:], token: snapshot.token, includesBody: false)
        request.httpMethod = "GET"
        return try await receipt(request, snapshot: snapshot, scope: scope, pending: pending)
    }
    public func audio(messageID: Int, scope: IMScope) async throws -> Data {
        guard playbackEnabled, messageID > 0 else { throw IMVoiceFailure.unavailable }
        let snapshot = try current(scope)
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/im/voice/message/\(messageID)"), fields: [:], token: snapshot.token, includesBody: false)
        request.httpMethod = "GET"; request.setValue("audio/mp4", forHTTPHeaderField: "Accept")
        return try await response(request, snapshot: snapshot, audio: true)
    }
    /// A fresh read, not an authorization lease. A failed or unknown result stops consumption.
    public func authorizePlayback(message: MessagingMessage, scope: IMScope) async throws {
        guard playbackStatusEnabled, let reference = IMVoiceReference.read(message), message.conversationID == scope.conversationID else { throw IMVoiceFailure.unavailable }
        let snapshot = try current(scope)
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/im/voice/message/\(message.id)/authorization"), fields: [:], token: snapshot.token, includesBody: false)
        request.httpMethod = "GET"
        struct Envelope: Decodable { struct Body: Decodable { let source: String; let message: MessagingMessage }; let data: Body }
        let bytes = try await response(request, snapshot: snapshot, audio: false)
        let result = try JSONDecoder().decode(Envelope.self, from: bytes).data
        guard result.source == "original-im-voice-authorization-v1", result.message.id == message.id,
              result.message.conversationID == scope.conversationID, result.message.senderID == message.senderID,
              IMVoiceReference.read(result.message) == reference else { throw IMVoiceFailure.notApproved }
    }
    private func current(_ scope: IMScope) throws -> IMVoiceSession {
        guard let snapshot = session(), snapshot.identity == scope.identity else { throw IMVoiceFailure.stale }; return snapshot
    }
    private func receipt(_ request: URLRequest, snapshot: IMVoiceSession, scope: IMScope, pending: IMVoiceJournal.Pending) async throws -> IMVoiceUploadReceipt {
        struct Envelope: Decodable { let data: IMVoiceUploadReceipt }
        let data = try await response(request, snapshot: snapshot, audio: false)
        let value = try JSONDecoder().decode(Envelope.self, from: data).data
        try value.validate(scope: scope, requestID: pending.requestID, hash: pending.clip.sha256); return value
    }
    private func response(_ request: URLRequest, snapshot: IMVoiceSession, audio: Bool) async throws -> Data {
        var request = request; request.httpShouldHandleCookies = false
        do {
            try Task.checkCancellation(); let (data, status) = try await transport.send(request)
            guard session() == snapshot, !Task.isCancelled else { throw IMVoiceFailure.stale }
            guard data.count <= (audio ? 2 * 1024 * 1024 : 16 * 1024) else { throw APIError.malformedResponse }
            struct Header: Decodable { let code: Int; let msg: String?; let errorCode: String? }
            let header = try? JSONDecoder().decode(Header.self, from: data)
            guard (200..<300).contains(status) else { throw MessagingReadFailure(httpStatus: status, code: header?.code, errorCode: header?.errorCode, message: header?.msg) }
            if !audio {
                guard let header else { throw APIError.malformedResponse }
                guard header.code == 200 else { throw MessagingReadFailure(code: header.code, errorCode: header.errorCode, message: header.msg) }
            } else { guard !data.isEmpty else { throw APIError.malformedResponse } }
            return data
        } catch {
            guard session() == snapshot, !Task.isCancelled else { throw IMVoiceFailure.stale }
            if (error as? MessagingReadFailure)?.isUnauthorized == true { unauthorized(snapshot) }
            throw error
        }
    }
}
