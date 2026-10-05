import Foundation

public struct CouponCodeApproval {
    public let market: RegionalMarket
    public let endpoints: OperationEndpointApproval
    public let imageOrigins: Set<String>
    public init(market: RegionalMarket, endpoints: OperationEndpointApproval, imageOrigins: Set<String> = []) {
        self.market = market; self.endpoints = endpoints; self.imageOrigins = imageOrigins
    }
    public func matches(_ context: RuntimeDependencyContext) -> Bool {
        let required: Set<String> = ["api/coupon/qr-token", "api/coupon/status"]
        return market == .china && context.market == market && endpoints.baseURL == context.baseURL &&
            endpoints.namespace == context.session.namespace && endpoints.accountID == context.session.accountID && required.isSubset(of: endpoints.paths)
    }
}
/// Normal-app factory, separate from the generic coupon client. API requests are scoped;
/// media uses exact approved origins, an ephemeral bounded loader and no credentials/redirects.
@MainActor public struct CouponCodeApprovedService: CouponCodeServing {
    private let client: CouponCodeHTTPService
    private let approval: CouponCodeApproval?
    private let captured: RuntimeDependencyContext?
    private let current: () -> RuntimeDependencyContext?
    private let media: any ObjectCardImageLoading
    public init(configuration: APIConfiguration?, approval: CouponCodeApproval? = nil, transport: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?, imageLoader: (any ObjectCardImageLoading)? = nil) {
        let captured = current()
        self.captured = captured; self.current = current
        let accepted = captured.flatMap { approval?.matches($0) == true && configuration?.baseURL == $0.baseURL ? approval : nil }
        self.approval = accepted
        let policy = ObjectCardMediaPolicy(approvedOrigins: accepted?.imageOrigins ?? [])
        self.media = imageLoader ?? ObjectCardBoundedImageLoader(policy: policy)
        let scoped = RuntimeDependencyTransport(configuration: accepted.map { .init(market: $0.market, endpoints: $0.endpoints) },
            captured: captured, transport: transport, current: current)
        client = CouponCodeHTTPService(configuration: configuration, transport: scoped, enabled: accepted != nil,
            approvedImageHosts: Set((accepted?.imageOrigins ?? []).compactMap { URL(string: $0)?.host }))
    }
    public var enabled: Bool { approval != nil && captured != nil && current() == captured }
    private func check(_ session: CouponCodeSession? = nil) throws {
        guard enabled, let captured else { throw CouponCodeFailure.disabled }
        if let session {
            guard session.accountID == captured.session.accountID, session.epoch == captured.session.epoch,
                  session.namespace == captured.session.namespace, session.role == captured.role,
                  session.token == captured.session.token else { throw CouponCodeFailure.stale }
        }
        try Task.checkCancellation()
    }
    public func issue(historyID: Int, session: CouponCodeSession) async throws -> CouponCodeReceipt {
        try check(session); let receipt = try await client.issue(historyID: historyID, session: session); try check(session); return receipt
    }
    public func status(historyID: Int, session: CouponCodeSession) async throws -> OrderCouponStatus {
        try check(session); let result = try await client.status(historyID: historyID, session: session); try check(session); return result
    }
    public func image(_ receipt: CouponCodeReceipt) async throws -> Data {
        try check()
        guard let url = receipt.imageURL, let approval else { throw CouponCodeFailure.mediaUnavailable }
        _ = try ObjectCardMediaPolicy(approvedOrigins: approval.imageOrigins).validate(url.absoluteString)
        let bytes = try await media.image(url: url.absoluteString)
        try check()
        guard !bytes.isEmpty, bytes.count <= 5 * 1024 * 1024 else { throw CouponCodeFailure.mediaUnavailable }
        return bytes
    }
}
