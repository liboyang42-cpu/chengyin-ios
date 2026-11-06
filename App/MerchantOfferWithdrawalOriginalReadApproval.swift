import Foundation

/// Explicit read-only issuance. Neither login, COOP_MANAGE, a pending UUID nor the
/// old legacy execution approval creates this grant. No shipped issuer is installed.
struct MerchantOfferWithdrawalOriginalReadApproval {
    let context: RuntimeDependencyContext
    let merchantID: Int
    let ownerID: Int
    let revision = UUID()
    init(context: RuntimeDependencyContext, merchantID: Int, ownerID: Int) throws {
        guard context.market == .china, merchantID > 0, ownerID > 0,
              context.role.utf8.elementsEqual(context.session.role.utf8) else { throw APIError.invalidRequest }
        self.context = context; self.merchantID = merchantID; self.ownerID = ownerID
    }
    func matches(_ live: RuntimeDependencyContext) -> Bool {
        ContentDraftContextFence.matches(context, live)
            && context.session.role.utf8.elementsEqual(live.session.role.utf8)
    }
    func accepts(_ access: MerchantAccess) -> Bool {
        // c6 access/me deliberately omits owner/principal identifiers. Do not invent
        // them from a role. Authenticated context binds actor; original current/result
        // must independently match the explicitly issued ownerID in Flow.accept.
        access.active && access.allows(.coopManage) && access.merchantID == merchantID
            && (access.principalMemberID == nil || access.principalMemberID == context.session.accountID)
            && (access.ownerMemberID == nil || access.ownerMemberID == ownerID)
    }
}

/// Defense at the transport boundary: exact current/result GET only, never the
/// legacy withdraw path, original POST, unrelated merchant or inferred offer.
@MainActor final class MerchantOfferWithdrawalOriginalReadTransport: HTTPTransport {
    private let api: APIConfiguration
    private let approval: MerchantOfferWithdrawalOriginalReadApproval
    private let underlying: any HTTPTransport
    private let current: () -> Bool
    init(api: APIConfiguration, approval: MerchantOfferWithdrawalOriginalReadApproval,
         underlying: any HTTPTransport, current: @escaping () -> Bool) {
        self.api = api; self.approval = approval; self.underlying = underlying; self.current = current
    }
    static func accepts(_ request: URLRequest, api: APIConfiguration, merchantID: Int) -> Bool {
        guard let url = request.url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              let raw = parts.queryItems?.first(where: { $0.name == "offerId" })?.value,
              let offerID = Int(raw), offerID > 0, raw == String(offerID) else { return false }
        parts.query = nil
        return ["current", "result"].contains { leaf in
            let path = MerchantOfferWithdrawalOriginalFlow.base + leaf
            return parts.url == api.baseURL.appendingPathComponent(path)
                && MerchantOfferWithdrawalOriginalFlow.accepts(request, path: path, merchantID: merchantID, offerID: offerID)
        }
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard current(), request.value(forHTTPHeaderField: "Authorization") == approval.context.session.token,
              Self.accepts(request, api: api, merchantID: approval.merchantID) else { throw APIError.notConfigured }
        let result = try await underlying.send(request)
        try Task.checkCancellation()
        guard current() else { throw APIError.notConfigured }
        return result
    }
}
