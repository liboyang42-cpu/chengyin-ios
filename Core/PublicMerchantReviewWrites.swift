import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct PublicMerchantReviewSession: Equatable {
    public let accountID: Int
    public let scope: UUID
    public let realm: String
    let token: String
    public init(accountID: Int, scope: UUID, realm: String, token: String) throws {
        guard accountID > 0, !realm.isEmpty, AuthRequestBuilder.isValidToken(token) else { throw PublicMerchantHomeFailure.invalid }
        self.accountID = accountID; self.scope = scope; self.realm = realm; self.token = token
    }
}
public enum PublicMerchantReviewCommand: Equatable {
    // Uploaded image proofs retain account, epoch, merchant and registration provenance.
    case create(registrationID: Int, rating: Int, content: String, images: [RetainedUploadedImage] = [])
    case report(reviewID: Int, expectedVersion: Int, reason: String)
    public var isCreate: Bool { if case .create = self { return true }; return false }
    public func body(target: PublicMerchantReviewTarget, requestID: String) throws -> [String: Any] {
        guard !requestID.isEmpty, requestID.utf16.count <= 64,
              requestID.range(of: #"^[A-Za-z0-9._:-]+$"#, options: .regularExpression) != nil else { throw PublicMerchantReviewWriteFailure.invalid }
        switch self {
        case .create(let registration, let rating, let content, let images):
            let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard registration > 0, (1...5).contains(rating), (2...1000).contains(text.utf16.count) else { throw PublicMerchantReviewWriteFailure.invalid }
            guard images.count <= 9, Set(images.map(\.id)).count == images.count,
                  images.allSatisfy({ $0.scope.destination == .publicReview(merchantRowID: target.merchantRowID.rawValue, registrationID: registration) }) else { throw PublicMerchantReviewWriteFailure.invalid }
            return ["merchantRowId": target.merchantRowID.rawValue, "registrationId": registration, "rating": rating,
                    "content": text, "imageUrls": images.map { $0.url.absoluteString }, "requestId": requestID]
        case .report(let review, let version, let reason):
            let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard review > 0, version >= 0, (2...500).contains(text.utf16.count) else { throw PublicMerchantReviewWriteFailure.invalid }
            return ["merchantMemberId": target.ownerMemberID.rawValue, "reviewId": review, "expectedVersion": version,
                    "reason": text, "requestId": requestID]
        }
    }
    public func validateImages(target: PublicMerchantReviewTarget, session: PublicMerchantReviewSession) throws {
        if case .create(let registration, _, _, let images) = self {
            for image in images { try image.validateReview(target: target, registrationID: registration, session: session) }
        }
    }
    public var path: String { isCreate ? "api/merchant/reviews/create" : "api/merchant/reviews/report" }
}
public enum PublicMerchantReviewWriteFailure: Error, Equatable {
    case invalid, notConfigured, sessionChanged, permissionChanged, unknown, storage, rejected(Int)
}
public struct PublicMerchantReviewReceipt: Decodable, Equatable {
    public let reviewId: Int
    public let status: String
    public let version: Int?
    public let replayed: Bool
    public let auditTaskId: Int?
    public func validate(_ command: PublicMerchantReviewCommand) throws {
        guard reviewId > 0, version == nil || version! >= 0, auditTaskId == nil || auditTaskId! > 0 else { throw PublicMerchantReviewWriteFailure.unknown }
        switch command {
        case .create:
            guard ["PENDING_REVIEW", "VISIBLE", "HIDDEN"].contains(status), version != nil,
                  replayed ? auditTaskId == nil : (status == "PENDING_REVIEW" && auditTaskId != nil) else { throw PublicMerchantReviewWriteFailure.unknown }
        case .report(let id, _, _):
            guard reviewId == id, status == "PENDING_PLATFORM_REVIEW", auditTaskId != nil else { throw PublicMerchantReviewWriteFailure.unknown }
        }
    }
}
@MainActor public protocol PublicMerchantReviewWriting {
    var isConfigured: Bool { get }
    var session: PublicMerchantReviewSession? { get }
    func evidence(_ target: PublicMerchantReviewTarget, page: Int, session: PublicMerchantReviewSession) async throws -> PublicMerchantReviewPage
    func execute(_ command: PublicMerchantReviewCommand, target: PublicMerchantReviewTarget, requestID: String, session: PublicMerchantReviewSession) async throws -> PublicMerchantReviewReceipt
}
@MainActor public struct DisabledPublicMerchantReviewWriter: PublicMerchantReviewWriting {
    public let isConfigured = false
    public let session: PublicMerchantReviewSession? = nil
    public init() {}
    public func evidence(_ target: PublicMerchantReviewTarget, page: Int, session: PublicMerchantReviewSession) async throws -> PublicMerchantReviewPage { throw PublicMerchantReviewWriteFailure.notConfigured }
    public func execute(_ command: PublicMerchantReviewCommand, target: PublicMerchantReviewTarget, requestID: String, session: PublicMerchantReviewSession) async throws -> PublicMerchantReviewReceipt { throw PublicMerchantReviewWriteFailure.notConfigured }
}
@MainActor public struct PublicMerchantReviewHTTPWriter: PublicMerchantReviewWriting {
    public let isConfigured = true
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let currentSession: () -> PublicMerchantReviewSession?
    public var session: PublicMerchantReviewSession? { currentSession() }
    public init(configuration: APIConfiguration, transport: any HTTPTransport, currentSession: @escaping () -> PublicMerchantReviewSession?) {
        self.configuration = configuration; self.transport = transport; self.currentSession = currentSession
    }
    public func evidence(_ target: PublicMerchantReviewTarget, page: Int, session: PublicMerchantReviewSession) async throws -> PublicMerchantReviewPage {
        guard currentSession() == session, session.realm == configuration.baseURL.absoluteString else { throw PublicMerchantReviewWriteFailure.sessionChanged }
        let reader = PublicMerchantReviewHTTPReader(configuration: configuration, transport: transport, scope: session.scope, session: session)
        let value = try await reader.page(target, page: page)
        guard currentSession() == session, session.realm == configuration.baseURL.absoluteString else { throw PublicMerchantReviewWriteFailure.sessionChanged }
        return value
    }
    public func execute(_ command: PublicMerchantReviewCommand, target: PublicMerchantReviewTarget, requestID: String, session: PublicMerchantReviewSession) async throws -> PublicMerchantReviewReceipt {
        guard currentSession() == session, session.realm == configuration.baseURL.absoluteString else { throw PublicMerchantReviewWriteFailure.sessionChanged }
        try command.validateImages(target: target, session: session)
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(command.path))
        request.httpMethod = "POST"; request.timeoutInterval = 20; request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(session.token, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: command.body(target: target, requestID: requestID))
        try Task.checkCancellation()
        // Every failure after dispatch is conservatively unknown unless a parseable rejection is received.
        do {
            let (data, status) = try await transport.send(request)
            guard currentSession() == session, session.realm == configuration.baseURL.absoluteString else { throw PublicMerchantReviewWriteFailure.unknown }
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            if envelope.code != 200, (200..<500).contains(status) { throw PublicMerchantReviewWriteFailure.rejected(envelope.code) }
            guard (200..<300).contains(status), envelope.code == 200, let value = envelope.data else { throw PublicMerchantReviewWriteFailure.unknown }
            try value.validate(command)
            return value
        } catch let failure as PublicMerchantReviewWriteFailure { throw failure }
        catch { throw PublicMerchantReviewWriteFailure.unknown }
    }
    private struct Envelope: Decodable {
        let code: Int
        let data: PublicMerchantReviewReceipt?
        enum CodingKeys: String, CodingKey { case code, data }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decode(Int.self, forKey: .code)
            data = code == 200 ? try c.decode(PublicMerchantReviewReceipt.self, forKey: .data) : nil
        }
    }
}
