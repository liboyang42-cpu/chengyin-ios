import Foundation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct IMVideoSession: Equatable {
    public let identity: MessagingReadIdentity
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw IMVideoFailure.invalid }
        identity = .init(accountID: accountID, epoch: epoch); self.token = token
    }
}
@MainActor public final class IMVideoService {
    private let mediaTransport: any HTTPTransport
    private let approvedMediaOrigins: Set<String>
    public let policyEnabled: Bool
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let session: () -> IMVideoSession?
    private let unauthorized: (IMVideoSession) -> Void
    public let uploadEnabled: Bool
    public let receiptEnabled: Bool
    public let previewEnabled: Bool
    public let previewStatusEnabled: Bool
    public var identity: MessagingReadIdentity? { session()?.identity }
    public init(configuration: APIConfiguration, transport: any HTTPTransport, mediaTransport: any HTTPTransport, approvedMediaOrigins: Set<String>,
                uploadEnabled: Bool = false, policyEnabled: Bool = false, receiptEnabled: Bool = false, previewEnabled: Bool = false, previewStatusEnabled: Bool = false,
                session: @escaping () -> IMVideoSession?, unauthorized: @escaping (IMVideoSession) -> Void = { _ in }) {
        self.mediaTransport = mediaTransport; self.approvedMediaOrigins = approvedMediaOrigins; self.policyEnabled = policyEnabled; self.configuration = configuration; self.transport = transport; self.uploadEnabled = uploadEnabled
        self.receiptEnabled = receiptEnabled; self.previewEnabled = previewEnabled; self.previewStatusEnabled = previewStatusEnabled
        self.session = session; self.unauthorized = unauthorized
    }
    public func upload(_ pending: IMVideoJournal.Pending, scope: IMScope) async throws -> IMVideoUploadReceipt {
        guard uploadEnabled else { throw IMVideoFailure.unavailable }
        let snapshot = try current(scope)
        let boundary = "imvideo-" + UUID().uuidString
        let fields = ["conversation_id": String(scope.conversationID), "upload_request_id": pending.requestID, "source_sha256": pending.selection.sha256]
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/im/video/upload"), fields: fields, token: snapshot.token, boundary: boundary)
        guard var body = request.httpBody else { throw IMVideoFailure.invalid }
        let terminal = Data("--\(boundary)--\r\n".utf8)
        guard body.suffix(terminal.count) == terminal else { throw IMVideoFailure.invalid }
        body.removeLast(terminal.count)
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"video.mov\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(pending.selection.bytes); body.append(Data("\r\n".utf8)); body.append(terminal); request.httpBody = body
        return try await receipt(request, snapshot: snapshot, scope: scope, pending: pending)
    }
    public func recover(_ pending: IMVideoJournal.Pending, scope: IMScope) async throws -> IMVideoUploadReceipt {
        guard receiptEnabled else { throw IMVideoFailure.unavailable }
        let snapshot = try current(scope)
        var components = URLComponents(url: configuration.baseURL.appendingPathComponent("api/im/video/receipt"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "conversation_id", value: String(scope.conversationID)), URLQueryItem(name: "upload_request_id", value: pending.requestID), URLQueryItem(name: "source_sha256", value: pending.selection.sha256)]
        guard let url = components?.url else { throw IMVideoFailure.invalid }
        var request = try AuthRequestBuilder.makeFormRequest(url: url, fields: [:], token: snapshot.token, includesBody: false)
        request.httpMethod = "GET"
        return try await receipt(request, snapshot: snapshot, scope: scope, pending: pending)
    }
    public func policy(scope: IMScope) async throws -> IMVideoPolicy {
        guard policyEnabled else { throw IMVideoFailure.unavailable }
        let snapshot = try current(scope)
        var components = URLComponents(url: configuration.baseURL.appendingPathComponent("api/im/video/policy"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "conversation_id", value: String(scope.conversationID))]
        guard let url = components?.url else { throw IMVideoFailure.invalid }
        var request = try AuthRequestBuilder.makeFormRequest(url: url, fields: [:], token: snapshot.token, includesBody: false); request.httpMethod = "GET"
        struct Envelope: Decodable { let data: IMVideoPolicy }
        let value = try JSONDecoder().decode(Envelope.self, from: await response(request, snapshot: snapshot, audio: false)).data
        try value.validate(); return value
    }
    /// A fresh read, not an authorization lease. A failed or unknown result stops consumption.
    public func authorizePreview(message: MessagingMessage, scope: IMScope) async throws {
        guard previewStatusEnabled, let reference = IMVideoReference.read(message), message.conversationID == scope.conversationID else { throw IMVideoFailure.unavailable }
        let snapshot = try current(scope)
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/im/video/message/\(message.id)/authorization"), fields: [:], token: snapshot.token, includesBody: false)
        request.httpMethod = "GET"
        struct Envelope: Decodable { struct Body: Decodable { let source: String; let message: MessagingMessage }; let data: Body }
        let bytes = try await response(request, snapshot: snapshot, audio: false)
        let result = try JSONDecoder().decode(Envelope.self, from: bytes).data
        guard result.source == "original-im-video-authorization-v1", result.message.id == message.id,
              result.message.conversationID == scope.conversationID, result.message.senderID == message.senderID,
              IMVideoReference.read(result.message) == reference else { throw IMVideoFailure.unsafe }
    }
    public struct Preview {
        public let video: Data
        public let cover: Data
        public let reference: IMVideoReference
        public let deadline: ContinuousClock.Instant
    }
    public func preview(message: MessagingMessage, scope: IMScope) async throws -> Preview {
        guard previewEnabled, let reference = IMVideoReference.read(message), message.conversationID == scope.conversationID else { throw IMVideoFailure.unavailable }
        try await authorizePreview(message: message, scope: scope)
        let snapshot = try current(scope), started = ContinuousClock.now
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/im/video/message/\(message.id)/preview"), fields: [:], token: snapshot.token, includesBody: false)
        request.httpMethod = "GET"
        struct Envelope: Decodable {
            struct Body: Decodable {
                let source: String; let message_id: String; let conversation_id: String
                let reference: IMVideoReference; let state: String; let videoURL: URL; let coverURL: URL; let expires_in_seconds: Int
            }
            let data: Body
        }
        let result = try JSONDecoder().decode(Envelope.self, from: await response(request, snapshot: snapshot, audio: false)).data
        guard result.source == "original-im-video-preview-v1",result.message_id == String(message.id),result.conversation_id == String(scope.conversationID),
              result.reference == reference,result.state == "READY",result.expires_in_seconds > 0,result.expires_in_seconds <= 300 else { throw IMVideoFailure.invalid }
        let deadline = started.advanced(by: .seconds(result.expires_in_seconds))
        let cover = try await originalBytes(url: result.coverURL, size: reference.coverSize, hash: reference.coverSHA256, snapshot: snapshot, deadline: deadline)
        let video = try await originalBytes(url: result.videoURL, size: reference.size, hash: reference.sha256, snapshot: snapshot, deadline: deadline)
        try await authorizePreview(message: message, scope: scope)
        guard session() == snapshot, !Task.isCancelled, ContinuousClock.now < deadline else { throw IMVideoFailure.stale }
        return Preview(video: video, cover: cover, reference: reference, deadline: deadline)
    }
    private func originalBytes(url: URL, size: Int, hash: String, snapshot: IMVideoSession, deadline: ContinuousClock.Instant) async throws -> Data {
        guard ContinuousClock.now < deadline, session() == snapshot, !Task.isCancelled else { throw IMVideoFailure.expired }
        guard let origin = SocialMessageMediaService.origin(url),approvedMediaOrigins.contains(origin),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),parts.scheme?.lowercased() == "https",
              parts.user == nil,parts.password == nil,parts.fragment == nil else { throw IMVideoFailure.invalid }
        var request = URLRequest(url: url);request.httpMethod = "GET";request.httpShouldHandleCookies = false;request.cachePolicy = .reloadIgnoringLocalCacheData
        let (bytes,status) = try await mediaTransport.send(request)
        guard session() == snapshot,!Task.isCancelled,ContinuousClock.now < deadline else { throw IMVideoFailure.stale }
        guard status == 200,bytes.count == size,bytes.count <= 64 * 1024 * 1024,
              SHA256.hash(data: bytes).map({ String(format: "%02x",$0) }).joined() == hash else { throw IMVideoFailure.unsafe }
        return bytes
    }
    private func current(_ scope: IMScope) throws -> IMVideoSession {
        guard let snapshot = session(), snapshot.identity == scope.identity else { throw IMVideoFailure.stale }; return snapshot
    }
    private func receipt(_ request: URLRequest, snapshot: IMVideoSession, scope: IMScope, pending: IMVideoJournal.Pending) async throws -> IMVideoUploadReceipt {
        struct Envelope: Decodable { let data: IMVideoUploadReceipt }
        let data = try await response(request, snapshot: snapshot, audio: false)
        let value = try JSONDecoder().decode(Envelope.self, from: data).data
        try value.validate(scope: scope, requestID: pending.requestID, hash: pending.selection.sha256); return value
    }
    private func response(_ request: URLRequest, snapshot: IMVideoSession, audio: Bool) async throws -> Data {
        var request = request; request.httpShouldHandleCookies = false
        do {
            try Task.checkCancellation(); let (data, status) = try await transport.send(request)
            guard session() == snapshot, !Task.isCancelled else { throw IMVideoFailure.stale }
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
            guard session() == snapshot, !Task.isCancelled else { throw IMVideoFailure.stale }
            if (error as? MessagingReadFailure)?.isUnauthorized == true { unauthorized(snapshot) }
            throw error
        }
    }
}
