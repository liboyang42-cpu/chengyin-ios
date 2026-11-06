import Foundation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct IMFileSession: Equatable {
    public let identity: MessagingReadIdentity
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw IMFileFailure.invalid }
        identity = .init(accountID: accountID, epoch: epoch); self.token = token
    }
}
@MainActor public final class IMFileService {
    private let mediaTransport: any HTTPTransport
    private let approvedMediaOrigins: Set<String>
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let session: () -> IMFileSession?
    private let unauthorized: (IMFileSession) -> Void
    public let scanEnabled: Bool
    public let uploadEnabled: Bool
    public let receiptEnabled: Bool
    public let previewEnabled: Bool
    public let previewStatusEnabled: Bool
    public var identity: MessagingReadIdentity? { session()?.identity }
    public init(configuration: APIConfiguration, transport: any HTTPTransport, mediaTransport: any HTTPTransport, approvedMediaOrigins: Set<String>,
                uploadEnabled: Bool = false, scanEnabled: Bool = false, receiptEnabled: Bool = false, previewEnabled: Bool = false, previewStatusEnabled: Bool = false,
                session: @escaping () -> IMFileSession?, unauthorized: @escaping (IMFileSession) -> Void = { _ in }) {
        self.mediaTransport = mediaTransport; self.approvedMediaOrigins = approvedMediaOrigins; self.scanEnabled = scanEnabled; self.configuration = configuration; self.transport = transport; self.uploadEnabled = uploadEnabled
        self.receiptEnabled = receiptEnabled; self.previewEnabled = previewEnabled; self.previewStatusEnabled = previewStatusEnabled
        self.session = session; self.unauthorized = unauthorized
    }
    public func upload(_ pending: IMFileJournal.Pending, scope: IMScope) async throws -> IMFileUploadReceipt {
        guard uploadEnabled else { throw IMFileFailure.unavailable }
        let snapshot = try current(scope)
        let boundary = "imfile-" + UUID().uuidString
        let fields = ["conversation_id": String(scope.conversationID), "upload_request_id": pending.requestID, "source_sha256": pending.selection.sha256]
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/im/file/upload"), fields: fields, token: snapshot.token, boundary: boundary)
        guard var body = request.httpBody else { throw IMFileFailure.invalid }
        let terminal = Data("--\(boundary)--\r\n".utf8)
        guard body.suffix(terminal.count) == terminal else { throw IMFileFailure.invalid }
        body.removeLast(terminal.count)
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(pending.selection.name.replacingOccurrences(of: "\"", with: "\\\""))\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(pending.selection.bytes); body.append(Data("\r\n".utf8)); body.append(terminal); request.httpBody = body
        return try await receipt(request, snapshot: snapshot, scope: scope, pending: pending)
    }
    public func recover(_ pending: IMFileJournal.Pending, scope: IMScope) async throws -> IMFileUploadReceipt {
        guard receiptEnabled else { throw IMFileFailure.unavailable }
        let snapshot = try current(scope)
        var components = URLComponents(url: configuration.baseURL.appendingPathComponent("api/im/file/receipt"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "conversation_id", value: String(scope.conversationID)), URLQueryItem(name: "upload_request_id", value: pending.requestID), URLQueryItem(name: "source_sha256", value: pending.selection.sha256)]
        guard let url = components?.url else { throw IMFileFailure.invalid }
        var request = try AuthRequestBuilder.makeFormRequest(url: url, fields: [:], token: snapshot.token, includesBody: false)
        request.httpMethod = "GET"
        return try await receipt(request, snapshot: snapshot, scope: scope, pending: pending)
    }
    public func scan(_ pending: IMFileJournal.Pending, scope: IMScope) async throws -> IMFileUploadReceipt {
        guard scanEnabled else { throw IMFileFailure.unavailable }
        let snapshot = try current(scope)
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/im/file/scan"),
            fields: ["conversation_id": String(scope.conversationID), "upload_request_id": pending.requestID, "source_sha256": pending.selection.sha256], token: snapshot.token)
        return try await receipt(request, snapshot: snapshot, scope: scope, pending: pending)
    }
    /// A fresh read, not an authorization lease. A failed or unknown result stops consumption.
    public func authorizePreview(message: MessagingMessage, scope: IMScope) async throws {
        guard previewStatusEnabled, let reference = IMFileReference.read(message), message.conversationID == scope.conversationID else { throw IMFileFailure.unavailable }
        let snapshot = try current(scope)
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/im/file/message/\(message.id)/authorization"), fields: [:], token: snapshot.token, includesBody: false)
        request.httpMethod = "GET"
        struct Envelope: Decodable { struct Body: Decodable { let source: String; let message: MessagingMessage }; let data: Body }
        let bytes = try await response(request, snapshot: snapshot, audio: false)
        let result = try JSONDecoder().decode(Envelope.self, from: bytes).data
        guard result.source == "original-im-file-authorization-v1", result.message.id == message.id,
              result.message.conversationID == scope.conversationID, result.message.senderID == message.senderID,
              IMFileReference.read(result.message) == reference else { throw IMFileFailure.unsafe }
    }
    public struct Preview {
        public let bytes: Data
        public let reference: IMFileReference
        public let deadline: ContinuousClock.Instant
    }
    public func preview(message: MessagingMessage, scope: IMScope) async throws -> Preview {
        guard previewEnabled, let reference = IMFileReference.read(message), message.conversationID == scope.conversationID else { throw IMFileFailure.unavailable }
        try await authorizePreview(message: message, scope: scope)
        let snapshot = try current(scope)
        let started = ContinuousClock.now
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/im/file/message/\(message.id)/preview"), fields: [:], token: snapshot.token, includesBody: false)
        request.httpMethod = "GET"
        struct Envelope: Decodable {
            struct Body: Decodable {
                let source: String; let message_id: String; let conversation_id: String
                let reference: IMFileReference; let state: String; let url: URL; let expires_in_seconds: Int
            }
            let data: Body
        }
        let descriptor = try JSONDecoder().decode(Envelope.self, from: await response(request, snapshot: snapshot, audio: false)).data
        guard descriptor.source == "original-im-file-preview-v1", descriptor.message_id == String(message.id),
              descriptor.conversation_id == String(scope.conversationID), descriptor.reference == reference, descriptor.state == "READY",
              descriptor.expires_in_seconds > 0, descriptor.expires_in_seconds <= 300,
              let origin = SocialMessageMediaService.origin(descriptor.url), approvedMediaOrigins.contains(origin),
              let parts = URLComponents(url: descriptor.url, resolvingAgainstBaseURL: false), parts.user == nil, parts.password == nil,
              parts.fragment == nil, parts.scheme?.lowercased() == "https" else { throw IMFileFailure.invalid }
        let deadline = started.advanced(by: .seconds(descriptor.expires_in_seconds))
        guard ContinuousClock.now < deadline else { throw IMFileFailure.linkExpired }
        var read = URLRequest(url: descriptor.url); read.httpMethod = "GET"; read.httpShouldHandleCookies = false
        read.cachePolicy = .reloadIgnoringLocalCacheData
        let (bytes, status) = try await mediaTransport.send(read)
        guard session() == snapshot, !Task.isCancelled else { throw IMFileFailure.stale }
        guard ContinuousClock.now < deadline else { throw IMFileFailure.linkExpired }
        guard status == 200, bytes.count == reference.size, bytes.count <= IMFileSelection.maximumBytes,
              SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == reference.sha256 else { throw IMFileFailure.unsafe }
        try await authorizePreview(message: message, scope: scope)
        guard session() == snapshot, !Task.isCancelled, ContinuousClock.now < deadline else { throw IMFileFailure.stale }
        return Preview(bytes: bytes, reference: reference, deadline: deadline)
    }
    private func current(_ scope: IMScope) throws -> IMFileSession {
        guard let snapshot = session(), snapshot.identity == scope.identity else { throw IMFileFailure.stale }; return snapshot
    }
    private func receipt(_ request: URLRequest, snapshot: IMFileSession, scope: IMScope, pending: IMFileJournal.Pending) async throws -> IMFileUploadReceipt {
        struct Envelope: Decodable { let data: IMFileUploadReceipt }
        let data = try await response(request, snapshot: snapshot, audio: false)
        let value = try JSONDecoder().decode(Envelope.self, from: data).data
        try value.validate(scope: scope, requestID: pending.requestID, hash: pending.selection.sha256)
        if let ref = value.reference {
            guard ref.name == pending.selection.name, ref.size == pending.selection.bytes.count,
                  ref.ext == pending.selection.fileExtension else { throw IMFileFailure.invalid }
        }
        return value
    }
    private func response(_ request: URLRequest, snapshot: IMFileSession, audio: Bool) async throws -> Data {
        var request = request; request.httpShouldHandleCookies = false
        do {
            try Task.checkCancellation(); let (data, status) = try await transport.send(request)
            guard session() == snapshot, !Task.isCancelled else { throw IMFileFailure.stale }
            guard data.count <= (audio ? 20 * 1024 * 1024 : 16 * 1024) else { throw APIError.malformedResponse }
            struct Header: Decodable { let code: Int; let msg: String?; let errorCode: String? }
            let header = try? JSONDecoder().decode(Header.self, from: data)
            guard (200..<300).contains(status) else { throw MessagingReadFailure(httpStatus: status, code: header?.code, errorCode: header?.errorCode, message: header?.msg) }
            if !audio {
                guard let header else { throw APIError.malformedResponse }
                guard header.code == 200 else { throw MessagingReadFailure(code: header.code, errorCode: header.errorCode, message: header.msg) }
            } else { guard !data.isEmpty else { throw APIError.malformedResponse } }
            return data
        } catch {
            guard session() == snapshot, !Task.isCancelled else { throw IMFileFailure.stale }
            if (error as? MessagingReadFailure)?.isUnauthorized == true { unauthorized(snapshot) }
            throw error
        }
    }
}
