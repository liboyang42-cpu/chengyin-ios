import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independent, revocable source-operation grant for ONE published POI. No value/read grant can create it.
@available(macOS 14.0, *)
@MainActor @Observable public final class CityPlayerValueNodeApproval {
    public let context: RuntimeDependencyContext
    public let poiID: Int
    public let endpoints: OperationEndpointApproval
    public let foregroundLocation, camera: Bool
    public let expiresAt: Date
    public let revision = UUID()
    public private(set) var revoked = false
    public init(context: RuntimeDependencyContext, poiID: Int, endpoints: OperationEndpointApproval,
                foregroundLocation: Bool, camera: Bool, expiresAt: Date) throws {
        guard context.market == .china, poiID > 0, context.session.accountID > 0,
              AuthRequestBuilder.isValidToken(context.session.token), expiresAt > Date(), expiresAt.timeIntervalSinceNow <= 86400,
              endpoints.baseURL == context.baseURL, endpoints.accountID == context.session.accountID,
              endpoints.namespace == context.session.namespace,
              endpoints.paths == ["api/city/nodes/\(poiID)", "api/city/nodes/\(poiID)/complete"] else { throw APIError.invalidConfiguration }
        self.context = context; self.poiID = poiID; self.endpoints = endpoints
        self.foregroundLocation = foregroundLocation; self.camera = camera; self.expiresAt = expiresAt
    }
    public func revoke() { revoked = true }
    public func matches(_ value: RuntimeDependencyContext) -> Bool {
        !revoked && Date() < expiresAt && ContentDraftContextFence.matches(context, value)
    }
}

/// Only real device fixes enter this adapter. It preserves accuracy/time and explicitly converts WGS84, never a map/search center.
@MainActor public final class CityPlayerValueNodeLocation: RoamDeviceLocationProviding {
    private let device: any RoamDeviceLocationProviding
    private let approved: () -> Bool
    public init(device: any RoamDeviceLocationProviding, approved: @escaping () -> Bool) { self.device = device; self.approved = approved }
    public func currentFix() async throws -> RoamDeviceFix {
        guard approved(), !Task.isCancelled else { throw APIError.notConfigured }
        let fix = try await device.currentFix()
        guard approved(), !Task.isCancelled else { throw CancellationError() }
        guard (0...30).contains(Date().timeIntervalSince(fix.measuredAt)) else { throw APIError.invalidRequest }
        return try RuntimeLocationProjection.gcj02(fix)
    }
    public func stop() { device.stop() }
}

/// The existing source executor/verification-code service receive this exact-target outer boundary, never raw transport.
@available(macOS 14.0, *)
@MainActor public final class CityPlayerValueNodeTransport: HTTPTransport {
    private let underlying: any HTTPTransport
    private let approval: CityPlayerValueNodeApproval
    private let verification: VerificationCodeApproval?
    private let current: () -> Bool
    public init(underlying: any HTTPTransport, approval: CityPlayerValueNodeApproval,
                verification: VerificationCodeApproval?, current: @escaping () -> Bool) {
        self.underlying = underlying; self.approval = approval; self.verification = verification; self.current = current
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let context = approval.context
        func valid() -> Bool { current() && approval.matches(context) }
        guard valid(), request.url?.query == nil, request.url?.fragment == nil, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Authorization") == context.session.token,
              request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Proxy-Authorization") == nil else { throw APIError.notConfigured }
        let detail = "api/city/nodes/\(approval.poiID)", complete = detail + "/complete", issue = "api/verify/citynode/issue"
        var allowed = request.httpMethod == "GET" && request.httpBody == nil && request.value(forHTTPHeaderField: "Content-Type") == nil &&
            request.value(forHTTPHeaderField: "Accept") == "application/json" && request.url == context.baseURL.appendingPathComponent(detail)
        if let (path, fields) = ProfileFavoritesRequestContract.fields(request, baseURL: context.baseURL, paths: [complete, issue]) {
            if path == complete {
                allowed = approval.camera && approval.foregroundLocation && Set(fields.keys) == ["lat", "lng", "answer", "photoUrl", "code"] &&
                    fields["answer"] == "" && fields["photoUrl"] == "" && !(fields["code"] ?? "").isEmpty && (fields["code"]?.utf8.count ?? 0) <= 2048
                if let lat = Double(fields["lat"] ?? ""), let lng = Double(fields["lng"] ?? "") {
                    allowed = allowed && RoamCoordinate(latitude: lat, longitude: lng) != nil
                } else { allowed = false }
            } else {
                allowed = Set(fields.keys) == ["poiId"] && fields["poiId"] == String(approval.poiID) && verification?.allows(.cityVoucher, context: context) == true
            }
        }
        guard allowed else { throw APIError.notConfigured }; try Task.checkCancellation()
        do {
            var isolated = request; isolated.httpShouldHandleCookies = false
            let response = try await underlying.send(isolated)
            guard valid(), !Task.isCancelled else { throw CancellationError() }; return response
        } catch { guard valid(), !Task.isCancelled else { throw CancellationError() }; throw error }
    }
}

@available(macOS 14.0, *)
@MainActor public final class CityPlayerValueNodeRuntime {
    private let grant: CityPlayerValueNodeApproval
    private let verification: VerificationCodeApproval?
    private let transport: any HTTPTransport
    private let location: any RoamDeviceLocationProviding
    private let journal: any OperationPendingJournal
    private let current: () -> Bool
    private let unauthorized: () -> Void
    private let scope: RetainedImageScope
    public var isCurrent: Bool { current() && grant.matches(grant.context) }
    public var cameraEnabled: Bool { isCurrent && grant.camera && grant.foregroundLocation }
    public init(grant: CityPlayerValueNodeApproval, verification: VerificationCodeApproval?, transport: any HTTPTransport,
                location: any RoamDeviceLocationProviding, journal: any OperationPendingJournal,
                current: @escaping () -> Bool, unauthorized: @escaping () -> Void = {}) throws {
        self.grant = grant; self.verification = verification; self.transport = transport; self.location = location
        self.journal = journal; self.current = current; self.unauthorized = unauthorized
        // Image scopes use a per-runtime UUID, not the UInt64 authentication epoch.
        // isCurrent still checks the full captured authentication context through the grant.
        scope = try RetainedImageScope(accountID: grant.context.session.accountID, epoch: UUID(),
            realm: grant.context.baseURL.absoluteString, destination: .roamPoster(poiID: grant.poiID), namespace: grant.context.session.namespace)
    }
    public func detail() async throws -> RoamNodeDetail {
        guard isCurrent else { throw APIError.notConfigured }
        do {
            let result = try await RoamService(configuration: APIConfiguration(baseURL: grant.context.baseURL), transport: transport)
                .nodeDetail(id: grant.poiID, token: grant.context.session.token)
            guard isCurrent, !Task.isCancelled else { throw CancellationError() }; return result
        } catch { if isCurrent, error as? APIError == .unauthorized { unauthorized() }; throw error }
    }
    public func poster(node: RoamNodeDetail) throws -> RoamPosterCoordinator {
        guard isCurrent, node.poiId == grant.poiID else { throw APIError.notConfigured }
        let executor = RoamMediaMutationService(configuration: try APIConfiguration(baseURL: grant.context.baseURL), transport: transport,
            enabled: grant.camera && grant.foregroundLocation, approval: grant.endpoints,
            currentScope: { [weak self] in guard let self, self.isCurrent else { return nil }; return self.scope },
            token: { [weak self] in guard let self, self.isCurrent else { return nil }; return self.grant.context.session.token })
        return RoamPosterCoordinator(scope: scope, poiID: grant.poiID, node: { [weak self] in self?.isCurrent == true ? node : nil },
            location: location, executor: executor, journal: journal, refreshNode: { [weak self] in
                guard let self else { throw CancellationError() }; return try await self.detail()
            })
    }
    /// Reconcile the existing coarse source lock only on positive, actor-scoped server state. Absence is NOT proof of failure.
    public func recoverCompletion() async throws -> RoamNodeDetail {
        let node = try await detail()
        guard isCurrent, !Task.isCancelled, node.completed || node.needRedeem else { throw CityPlayerValueFailure.rejected("SOURCE_NOT_CONFIRMED") }
        let owner = "roam-poster:\(scope.namespace ?? ""):\(scope.realm):\(scope.accountID)", target = "poi:\(grant.poiID)"
        if let pending = try journal.pending(ownerKey: owner, targetKey: target) { try journal.clear(pending) }
        return node
    }
    public func voucher() -> VerificationCodeCoordinator {
        let service = VerificationCodeHTTPService(configuration: try? APIConfiguration(baseURL: grant.context.baseURL), approval: verification,
            kind: .cityVoucher, transport: transport, current: { [weak self] in self?.isCurrent == true ? self?.grant.context : nil })
        return VerificationCodeCoordinator(target: .init(kind: .cityVoucher, id: grant.poiID), service: service,
            current: { [weak self] in self?.isCurrent == true ? self?.grant.context : nil }, onUnauthorized: { [weak self] _ in
                if self?.isCurrent == true { self?.unauthorized() }
            })
    }
    public func stop() { location.stop() }
}
