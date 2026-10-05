import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exact source AI operations. Only source-provided values are forwarded.
public enum PublishingAssistance: Equatable {
    case theme(idea: String)
    case themeForProduct(idea: String, product: ProjectEditProduct)
    case template(shopName: String, extraNote: String, category: String, reward: String, playStyle: String, validationMethod: Int?)
    case club(idea: String, style: String?, minutes: Int?)
    case safety([String: ProjectEditJSON])
    var request: PublishingRequest {
        switch self {
        case .theme(let idea): return PublishingContracts.aiThemeDraft(idea: idea)
        case .themeForProduct(let idea, let product):
            return PublishingRequest(path: "api/ai/theme/draft", encoding: .json, fields: ["idea": .string(idea.trimmingCharacters(in: .whitespacesAndNewlines)), "productType": .number(Decimal(product.rawValue))])
        case .template(let name, let note, let category, let reward, let style, let method):
            return PublishingContracts.aiTemplateFill(shopName: name, extraNote: note, category: category, reward: reward, playStyle: style, validationMethod: method)
        case .club(let idea, let style, let minutes): return PublishingContracts.aiClubDesign(idea: idea, style: style, minutes: minutes)
        case .safety(let fields): return PublishingContracts.safetyPrecheck(fields)
        }
    }
}
public struct PublishingAuxiliaryReview: Identifiable, Equatable {
    public let id: UUID
    public let session: PublishingSession
    /// Ephemeral memory only. Identity payloads must never be logged or serialized to disk.
    public let request: PublishingRequest
    fileprivate init(session: PublishingSession, request: PublishingRequest) { id = UUID(); self.session = session; self.request = request }
    var targetKey: String { "publishingAuxiliary:" + request.path }
    var isIdentity: Bool { request.path == "api/publisher/identity" }
    var isSafety: Bool { request.path == "api/ai/safety/precheck" }
}
public enum PublishingAuxiliaryOutcome: Equatable {
    case acknowledged(ProjectEditJSON)
    case rejected(String)
    /// Source safety precheck is a soft gate. Provider failure must not be mislabeled a content violation.
    case unavailable(String)
    case notSent, unknown
}
public struct PublishingSafetyIssue: Equatable {
    public let level: String
    public let type: String
    public let message: String
    public var blocksPublication: Bool { level == "error" && type != "parse_error" }
    public static func decode(_ data: ProjectEditJSON) throws -> [Self] {
        guard let object = data.object else { throw PublishModesError.invalidContract }
        let issues = object["issues"]?.array ?? []
        return issues.compactMap { value in
            guard let row = value.object, let message = row["message"]?.text, !message.isEmpty else { return nil }
            return Self(level: row["level"]?.text ?? "", type: row["type"]?.text ?? "", message: message)
        }
    }
}
/// Executable but unmounted, independently approved auxiliary adapter. There is no ambient
/// live grant. The default constructor cannot dispatch. Tests inject an in-memory transport.
@MainActor public final class PublishingAuxiliaryService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let credentials: () -> PublishingCredentials?
    private let approval: OperationEndpointApproval?
    private let journal: (any OperationPendingJournal)?
    private var reviews: [UUID: PublishingAuxiliaryReview] = [:]
    private var busy = false
    public init(configuration: APIConfiguration, transport: any HTTPTransport,
                approval: OperationEndpointApproval? = nil, journal: (any OperationPendingJournal)? = nil,
                credentials: @escaping () -> PublishingCredentials?) {
        self.configuration = configuration; self.transport = transport; self.approval = approval
        self.journal = journal; self.credentials = credentials
    }
    public var themeConfigured: Bool {
        guard let credential = credentials(), let approval, journal != nil else { return false }
        return credential.session.region == .china && ["player", "club", "merchant"].contains(credential.session.role) && approval.allows(configuration: configuration, namespace: credential.session.namespace, accountID: credential.session.accountID, path: "api/ai/theme/draft")
    }
    public var templateSession: PublishingSession? { credentials()?.session }
    public var templateConfigured: Bool {
        guard let credential = credentials(), let approval, journal != nil else { return false }
        return credential.session.region == .china && ["club", "merchant"].contains(credential.session.role) && approval.allows(configuration: configuration, namespace: credential.session.namespace, accountID: credential.session.accountID, path: "api/ai/template/fill")
    }
    private func check(_ credential: PublishingCredentials) throws {
        try Task.checkCancellation()
        guard credentials() == credential else { reviews.removeAll(); throw PublishModesError.changedSession }
    }
    public func prepare(_ assistance: PublishingAssistance, session: PublishingSession) throws -> PublishingAuxiliaryReview {
        guard let credential = credentials(), credential.session == session else { throw PublishModesError.changedSession }
        try check(credential)
        guard (assistance.request.path == "api/ai/theme/draft" && ["player", "club", "merchant"].contains(session.role)) || session.role == "club" || session.role == "merchant" else { throw PublishModesError.forbidden }
        if case .template(let name, let note, _, _, _, _) = assistance {
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PublishModesError.invalidDraft }
        }
        let review = PublishingAuxiliaryReview(session: session, request: assistance.request); reviews[review.id] = review; return review
    }
    /// Calling this does not transmit the data. Inputs are held only in the returned review.
    /// The caller must obtain the secure, destination-specific identity consent before confirm.
    public func prepareIdentity(name: String, idCard: String, consent: Bool, source: String,
                                registered: Bool, currentYear: Int, session: PublishingSession) throws -> PublishingAuxiliaryReview {
        guard let credential = credentials(), credential.session == session else { throw PublishModesError.changedSession }
        try check(credential)
        let request = try PublishingIdentity.registration(name: name, idCard: idCard, consent: consent, source: source,
                                                          region: session.region, registered: registered, currentYear: currentYear)
        let review = PublishingAuxiliaryReview(session: session, request: request); reviews[review.id] = review; return review
    }
    public func cancel(_ review: PublishingAuxiliaryReview) { reviews.removeValue(forKey: review.id) }
    public func invalidate() { reviews.removeAll() }
    private func identityAlreadyRegistered(_ credential: PublishingCredentials) async throws -> Bool {
        let request = try OperationAdapterHTTP.json(configuration: configuration, path: "api/publisher/identity/status", body: Data("{}".utf8), token: credential.token)
        let (data, status) = try await transport.send(request); try check(credential)
        let body = try OperationAdapterHTTP.envelope(data)
        guard (200..<300).contains(status), body["code"]?.integer == 200, let object = body["data"]?.object,
              let value = object["registered"], case .bool(let registered) = value else { throw PublishModesError.invalidContract }
        return registered
    }
    public func confirm(_ review: PublishingAuxiliaryReview) async -> PublishingAuxiliaryOutcome {
        guard !busy, reviews[review.id] == review, let credential = credentials(), credential.session == review.session,
              let approval, let journal, approval.allows(configuration: configuration, namespace: review.session.namespace,
                                                        accountID: review.session.accountID, path: review.request.path) else { return .notSent }
        if review.isIdentity {
            guard review.session.region == .china else { return .notSent }
        } else {
            // Conservative US provider gate remains closed pending an approved regional contract.
            guard review.session.region == .china, (review.request.path == "api/ai/theme/draft" && ["player", "club", "merchant"].contains(review.session.role)) || ["club", "merchant"].contains(review.session.role) else { return .notSent }
        }
        busy = true; defer { busy = false }
        let record = OperationPendingRecord(operationID: review.id, ownerKey: review.session.storageKey, targetKey: review.targetKey)
        let request: URLRequest
        do {
            try check(credential)
            guard try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == nil else { return review.isSafety ? .unavailable("") : .unknown }
            if review.isIdentity {
                guard try await identityAlreadyRegistered(credential) == false else { return .notSent }
            }
            try check(credential)
            guard reviews[review.id] == review else { return .notSent }
            request = try OperationAdapterHTTP.json(configuration: configuration, path: review.request.path,
                                                    body: JSONEncoder().encode(review.request.fields), token: credential.token)
            // Only the opaque operation/owner/target marker is persisted, never request fields.
            try journal.write(record)
            guard try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == record else { return review.isSafety ? .unavailable("") : .unknown }
            reviews.removeValue(forKey: review.id)
        } catch { return review.isSafety ? .unavailable("") : .notSent }
        do {
            let (data, status) = try await transport.send(request); try check(credential)
            // Template-specific auth responses are definitive rejections, not provider outages.
            if review.request.path == "api/ai/template/fill" {
                let body = try? OperationAdapterHTTP.envelope(data), code = body?["code"]?.integer
                if status == 401 || code == 401 { try journal.clear(record); return .rejected("请先登录") }
                if status == 403 || code == 403 { try journal.clear(record); return .rejected("当前身份暂不支持AI创作") }
            }
            guard (200..<300).contains(status), let body = try? OperationAdapterHTTP.envelope(data), let code = body["code"]?.integer else { return review.isSafety ? .unavailable("") : .unknown }
            try journal.clear(record)
            if code == 200 { return .acknowledged(body["data"] ?? .null) }
            return review.isSafety ? .unavailable(body["msg"]?.text ?? "") : .rejected(body["msg"]?.text ?? "")
        } catch { return review.isSafety ? .unavailable("") : .unknown }
    }
}
