import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independent CN read lease for one endpoint. No AppSession issuance is supplied by this module.
/// A caller must separately approve it; login, order-read approval and response fields cannot create it.
@available(macOS 14.0, *)
@MainActor @Observable public final class ExploreCompletionReadApproval {
    public let context: RuntimeDependencyContext
    public let expiresAt: Date
    public let revision = UUID()
    public private(set) var isRevoked = false
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    public init(context: RuntimeDependencyContext, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        let duration = expiresAt.timeIntervalSinceNow
        guard context.market == .china, ["player", "club", "merchant"].contains(context.role),
              context.session.accountID > 0, AuthRequestBuilder.isValidToken(context.session.token),
              duration.isFinite, duration > 0, duration <= 86_400 else { throw APIError.invalidConfiguration }
        self.context = context; self.expiresAt = expiresAt
        expiryTask = Task { @MainActor [weak self] in
            let remaining = max(0, min(expiresAt.timeIntervalSinceNow, 86_400))
            do {
                if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
                try Task.checkCancellation()
            } catch { return }
            self?.revoke()
        }
    }
    deinit { expiryTask?.cancel() }
    public func revoke() { isRevoked = true; expiryTask?.cancel(); expiryTask = nil }
    public func expireIfNeeded(now: Date = Date()) { if now >= expiresAt { revoke() } }
    public func matches(_ current: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        !isRevoked && now < expiresAt && ContentDraftContextFence.matches(context, current)
    }
}

/// Canonical POST multipart form containing only the positive registration id.
public struct ExploreCompletionReadRoute: Equatable {
    public let registrationID: Int
    public static let path = "api/registration/explore-completion"
    public init?(request: URLRequest, baseURL: URL) {
        guard let url = request.url, url.query == nil, url.fragment == nil,
              url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent(Self.path).absoluteString.utf8),
              request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              let body = request.httpBody, body.count <= 1_024, let text = String(data: body, encoding: .utf8),
              let type = request.value(forHTTPHeaderField: "Content-Type"),
              type.hasPrefix("multipart/form-data; boundary=") else { return nil }
        let boundary = String(type.dropFirst("multipart/form-data; boundary=".count))
        guard !boundary.isEmpty, boundary.count <= 70,
              boundary.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        let prefix = "--\(boundary)\r\nContent-Disposition: form-data; name=\"id\"\r\n\r\n"
        let suffix = "\r\n--\(boundary)--\r\n"
        guard text.hasPrefix(prefix), text.hasSuffix(suffix), text.count > prefix.count + suffix.count else { return nil }
        let raw = String(text.dropFirst(prefix.count).dropLast(suffix.count))
        guard let id = Int(raw), id > 0, String(id) == raw,
              let canonical = try? AuthRequestBuilder.makeFormRequest(url: url, fields: ["id": raw], token: nil, boundary: boundary),
              canonical.httpBody == body else { return nil }
        registrationID = id
    }
}
public struct ExploreCompletionReadIdentity: Hashable {
    public let readerScope: UUID
    public let approvalRevision: UUID
    public let accountID: Int
    public let epoch: UInt64
}
@MainActor public protocol ExploreCompletionReading: AnyObject {
    var identity: ExploreCompletionReadIdentity? { get }
    var isConfigured: Bool { get }
    func matches(context: RuntimeDependencyContext) -> Bool
    func read(_ target: ExploreCompletionTarget, isCurrent: @escaping @MainActor () -> Bool) async throws -> ExploreCompletionSnapshot
}

/// No arbitrary request entry point and no default production transport/approval.
@available(macOS 14.0, *)
@MainActor public final class ExploreCompletionSessionReader: ExploreCompletionReading {
    public static let maximumResponseBytes = 2 * 1_024 * 1_024
    private let configuration: APIConfiguration
    private let http: any HTTPTransport
    private let approval: ExploreCompletionReadApproval?
    private let current: () -> RuntimeDependencyContext?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private let readerScope = UUID()
    public init(configuration: APIConfiguration, http: any HTTPTransport,
                approval: ExploreCompletionReadApproval? = nil,
                current: @escaping () -> RuntimeDependencyContext?,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.configuration = configuration; self.http = http; self.approval = approval
        self.current = current; self.onUnauthorized = onUnauthorized
    }
    public var isConfigured: Bool {
        guard let approval, let current = current() else { return false }
        return approval.matches(current)
            && current.baseURL.absoluteString.utf8.elementsEqual(configuration.baseURL.absoluteString.utf8)
    }
    public var identity: ExploreCompletionReadIdentity? {
        guard isConfigured, let context = current(), let approval else { return nil }
        return .init(readerScope: readerScope, approvalRevision: approval.revision,
                     accountID: context.session.accountID, epoch: context.session.epoch)
    }
    public func matches(context: RuntimeDependencyContext) -> Bool {
        isConfigured && ContentDraftContextFence.matches(current(), context)
    }
    public func read(_ target: ExploreCompletionTarget, isCurrent: @escaping @MainActor () -> Bool = { true }) async throws -> ExploreCompletionSnapshot {
        guard isConfigured, let captured = current(), let approval else { throw APIError.notConfigured }
        guard target.registrationID > 0, target.accountID == captured.session.accountID else { throw APIError.invalidRequest }
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(ExploreCompletionReadRoute.path),
            fields: ["id": String(target.registrationID)], token: captured.session.token)
        guard let route = ExploreCompletionReadRoute(request: request, baseURL: configuration.baseURL), route.registrationID == target.registrationID,
              request.value(forHTTPHeaderField: "Authorization")?.utf8.elementsEqual(captured.session.token.utf8) == true else { throw APIError.invalidRequest }
        func active() -> Bool {
            guard !Task.isCancelled, isCurrent(), let now = current(), approval.matches(now) else { return false }
            return ContentDraftContextFence.matches(captured, now)
        }
        do {
            guard active() else { throw CancellationError() }
            let (data, status) = try await http.send(request)
            guard active() else { throw CancellationError() }
            if status == 401 { throw APIError.unauthorized }
            guard (200...299).contains(status) else { throw APIError.httpStatus(status) }
            guard data.count <= Self.maximumResponseBytes else { throw APIError.malformedResponse }
            let envelope: CompletionEnvelope
            do { envelope = try JSONDecoder().decode(CompletionEnvelope.self, from: data) }
            catch { throw APIError.malformedResponse }
            if envelope.code == 401 { throw APIError.unauthorized }
            if envelope.code == 403 { throw APIError.businessCode(403) }
            guard envelope.code == 200 else { throw ExploreCompletionFailure.rejected(code: envelope.code, message: envelope.message) }
            guard let value = envelope.value, value.registrationID == target.registrationID else { throw APIError.malformedResponse }
            guard active() else { throw CancellationError() }
            return value
        } catch {
            guard active() else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(captured) }
            throw error
        }
    }
}

private struct CompletionEnvelope: Decodable {
    let code: Int
    let message: String?
    let value: ExploreCompletionSnapshot?
    private enum CodingKeys: String, CodingKey { case code, msg, data }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? c.decode(Int.self, forKey: .code) { code = value }
        else if let raw = try? c.decode(String.self, forKey: .code), let value = Int(raw), String(value) == raw { code = value }
        else { throw APIError.malformedResponse }
        message = try c.decodeIfPresent(String.self, forKey: .msg)
        guard message.map({ $0.utf8.count <= 4_096 }) ?? true else { throw APIError.malformedResponse }
        // Error payloads are not completion DTOs; do not let a malformed error data field hide 401/403.
        value = code == 200 ? try c.decodeIfPresent(ExploreCompletionSnapshot.self, forKey: .data) : nil
    }
}

@available(macOS 14.0, *)
@MainActor @Observable public final class ExploreCompletionReadModel {
    @ObservationIgnored private let reader: any ExploreCompletionReading
    private var generation = UUID()
    public private(set) var presentationID: UUID?
    private var acceptedIdentity: ExploreCompletionReadIdentity?
    private var snapshot: ExploreCompletionSnapshot?
    public private(set) var isLoading = false
    public private(set) var error: Error?
    public var value: ExploreCompletionSnapshot? {
        guard presentationID != nil, let acceptedIdentity, acceptedIdentity == reader.identity else { return nil }
        return snapshot
    }
    public init(reader: any ExploreCompletionReading) { self.reader = reader }
    /// A fresh local ticket is required for every appearance; queued work cannot re-open a departed view.
    @discardableResult public func beginPresentation() -> UUID {
        invalidate()
        let ticket = UUID(); presentationID = ticket
        return ticket
    }
    public func endPresentation() {
        presentationID = nil; invalidate()
    }
    public func matchesPresentation(_ ticket: UUID) -> Bool { presentationID == ticket }
    public func invalidate() {
        generation = UUID(); acceptedIdentity = nil; snapshot = nil; error = nil; isLoading = false
    }
    public func load(_ target: ExploreCompletionTarget, expectedIdentity: ExploreCompletionReadIdentity, presentationID: UUID,
                     isCurrent: @escaping @MainActor () -> Bool = { true }) async {
        // Reject a retired ticket before invalidating a newer presentation or creating a request generation.
        guard !Task.isCancelled, matchesPresentation(presentationID) else { return }
        invalidate()
        let ticket = generation
        guard reader.isConfigured, reader.identity == expectedIdentity, isCurrent() else { return }
        isLoading = true
        defer { if generation == ticket { isLoading = false } }
        do {
            let value = try await reader.read(target, isCurrent: { self.generation == ticket && self.matchesPresentation(presentationID) && isCurrent() })
            guard !Task.isCancelled, generation == ticket, matchesPresentation(presentationID), reader.identity == expectedIdentity, isCurrent() else { return }
            guard value.registrationID == target.registrationID else { throw APIError.malformedResponse }
            snapshot = value; acceptedIdentity = expectedIdentity
        } catch {
            guard !Task.isCancelled, generation == ticket, matchesPresentation(presentationID), reader.identity == expectedIdentity, isCurrent() else { return }
            self.error = error
        }
    }
}
