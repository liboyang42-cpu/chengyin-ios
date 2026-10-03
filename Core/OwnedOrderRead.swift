import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independently issued owner-only CN read lease. Production issuance remains blocked
/// until the backend null-principal guard is independently accepted and deployed.
/// Revoke an old lease before removing/replacing it. Revocation cannot be reversed.
/// Authentication, display values, roles and other read grants cannot issue this lease.
@available(macOS 14.0, *)
@MainActor @Observable public final class OwnedOrderReadApproval {
    public let context: RuntimeDependencyContext
    public let expiresAt: Date
    public let revision = UUID()
    public private(set) var isRevoked = false
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    public init(context: RuntimeDependencyContext, expiresAt: Date) throws {
        let duration = expiresAt.timeIntervalSinceNow
        guard context.market == .china, ["player", "club", "merchant"].contains(context.role),
              context.session.accountID > 0, AuthRequestBuilder.isValidToken(context.session.token),
              duration.isFinite, duration > 0, duration <= 86_400 else { throw APIError.invalidConfiguration }
        self.context = context; self.expiresAt = expiresAt
        expiryTask = Task { @MainActor [weak self] in
            // A queued MainActor task must not start the original duration again.
            // Wall-clock request checks remain authoritative throughout suspension.
            let remaining = Self.expiryDelay(until: expiresAt, now: Date())
            do {
                if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
                try Task.checkCancellation()
            }
            catch { return }
            self?.revoke()
        }
    }
    deinit { expiryTask?.cancel() }
    static func expiryDelay(until deadline: Date, now: Date) -> TimeInterval {
        max(0, min(deadline.timeIntervalSince(now), 86_400))
    }
    public func revoke() { isRevoked = true; expiryTask?.cancel(); expiryTask = nil }
    public func matches(_ current: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        !isRevoked && now < expiresAt && ContentDraftContextFence.matches(context, current)
    }
    /// Deterministic expiry seam for tests and foreground reconciliation. Never renews a lease.
    public func expireIfNeeded(now: Date = Date()) { if now >= expiresAt { revoke() } }
}

/// Exact unpaginated server subset. There is no member override or client pagination.
public enum OwnedOrderReadRoute: Equatable {
    case list, detail(Int)
    public init?(request: URLRequest, baseURL: URL) {
        guard let url = request.url, url.query == nil, url.fragment == nil,
              request.httpMethod == "POST", request.httpBodyStream == nil,
              let body = request.httpBody, body.count <= 512, let text = String(data: body, encoding: .utf8),
              let type = request.value(forHTTPHeaderField: "Content-Type"),
              type.hasPrefix("multipart/form-data; boundary=") else { return nil }
        let boundary = String(type.dropFirst("multipart/form-data; boundary=".count))
        guard !boundary.isEmpty, boundary.count <= 70,
              boundary.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        let key: String
        if url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent("api/registration/list").absoluteString.utf8) { key = "owner_type" }
        else if url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent("api/registration/info").absoluteString.utf8) { key = "id" }
        else { return nil }
        let prefix = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n", suffix = "\r\n--\(boundary)--\r\n"
        guard text.hasPrefix(prefix), text.hasSuffix(suffix), text.count > prefix.count + suffix.count else { return nil }
        let value = String(text.dropFirst(prefix.count).dropLast(suffix.count))
        guard let id = Int(value), id > 0, String(id) == value,
              let canonical = try? AuthRequestBuilder.makeFormRequest(url: url, fields: [key:value], token: nil, boundary: boundary),
              canonical.httpBody == body else { return nil }
        if key == "owner_type" { guard id == 3 else { return nil }; self = .list }
        else { self = .detail(id) }
    }
}

public struct OwnedOrderReadSession: Equatable {
    public let context: RuntimeDependencyContext
    public let viewerRevision: UInt64
    public let approvalRevision: UUID
    public init(context: RuntimeDependencyContext, viewerRevision: UInt64, approvalRevision: UUID) {
        self.context = context; self.viewerRevision = viewerRevision; self.approvalRevision = approvalRevision
    }
    public var identity: ProfileReadIdentity {
        .init(accountID: context.session.accountID, epoch: context.session.epoch, viewerRevision: viewerRevision, approvalRevision: approvalRevision)
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        ContentDraftContextFence.matches(lhs.context, rhs.context) && lhs.viewerRevision == rhs.viewerRevision && lhs.approvalRevision == rhs.approvalRevision
    }
}

/// Reuses normal Profile screens, exposing only orders. Response owner checks are defense
/// in depth; they do not establish or replace server authorization.
@MainActor public final class OwnedOrderSessionReader: ProfileReading {
    private let service: ProfileService?
    private let current: () -> OwnedOrderReadSession?
    private let signedInIdentity: () -> ProfileReadIdentity?
    private let onUnauthorized: (OwnedOrderReadSession) -> Void
    public var identity: ProfileReadIdentity? { current()?.identity ?? signedInIdentity() }
    public var isConfigured: Bool { service != nil && current() != nil }
    public init(service: ProfileService?, current: @escaping () -> OwnedOrderReadSession?, signedInIdentity: @escaping () -> ProfileReadIdentity?, onUnauthorized: @escaping (OwnedOrderReadSession) -> Void = { _ in }) {
        self.service = service; self.current = current; self.signedInIdentity = signedInIdentity; self.onUnauthorized = onUnauthorized
    }
    public func profileOrders() async throws -> [ProfileOrder] {
        try await read { try await $0.orders(token: $1.context.session.token, expectedAccountID: $1.context.session.accountID) }
    }
    public func profileOrder(id: Int) async throws -> ProfileOrder {
        try await read { try await $0.order(id: id, token: $1.context.session.token, expectedAccountID: $1.context.session.accountID) }
    }
    public func profileParticipants() async throws -> [ProfileParticipant] { throw APIError.notConfigured }
    public func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.notConfigured }
    public func profileBadges() async throws -> ProfileBadgeWall { throw APIError.notConfigured }
    private func read<Value>(_ operation: (ProfileService, OwnedOrderReadSession) async throws -> Value) async throws -> Value {
        guard signedInIdentity() != nil else { throw APIError.unauthorized }
        guard let service, let captured = current() else { throw APIError.notConfigured }
        try Task.checkCancellation()
        do {
            let result = try await operation(service, captured)
            guard !Task.isCancelled, current() == captured else { throw CancellationError() }
            return result
        } catch {
            guard !Task.isCancelled, current() == captured else { throw CancellationError() }
            if (error as? ProfileReadFailure)?.isUnauthorized == true || error as? APIError == .unauthorized {
                onUnauthorized(captured); throw APIError.unauthorized
            }
            throw error
        }
    }
}

/// Decimal-only rendering; no NumberFormatter/Double rounding, scaling, inferred currency
/// or points conversion. The server amount remains inspectable as an invariant decimal.
public enum OwnedOrderMoneyText {
    public static func string(_ amount: Decimal) -> String { NSDecimalNumber(decimal: amount).stringValue }
}
