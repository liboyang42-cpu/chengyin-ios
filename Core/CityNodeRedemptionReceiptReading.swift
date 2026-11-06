import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independent original-receipt capability, not permission to redeem or issue a code.
@MainActor public final class CityNodeRedemptionReceiptApproval {
    public let context: RuntimeDependencyContext
    public let merchantID: Int
    public let expiresAt: Date
    public private(set) var revoked = false
    public init(context: RuntimeDependencyContext, merchantID: Int, expiresAt: Date) throws {
        guard context.market == .china, context.session.accountID > 0, merchantID > 0,
              AuthRequestBuilder.isValidToken(context.session.token), expiresAt > Date(),
              expiresAt.timeIntervalSinceNow <= 86400 else { throw APIError.invalidConfiguration }
        self.context = context; self.merchantID = merchantID; self.expiresAt = expiresAt
    }
    public func revoke() { revoked = true }
    public func matches(_ current: RuntimeDependencyContext?) -> Bool {
        guard let current else { return false }
        return !revoked && Date() < expiresAt && ContentDraftContextFence.matches(context, current) && context.session == current.session
    }
}

/// Only the original POST receipt route. No public arbitrary request/transport access.
/// Caller supplies the code transiently; it is never persisted or logged here.
@MainActor public final class CityNodeRedemptionReceiptReader {
    private let approval: CityNodeRedemptionReceiptApproval?
    private let transport: any HTTPTransport
    private let context: () -> RuntimeDependencyContext?
    private let selected: () -> CityNodeRedemptionReceiptApproval?
    public var isCurrent: Bool {
        guard let approval else { return false }
        return selected() === approval && approval.matches(context())
    }
    public init(approval: CityNodeRedemptionReceiptApproval? = nil, transport: any HTTPTransport,
                context: @escaping () -> RuntimeDependencyContext?, selected: @escaping () -> CityNodeRedemptionReceiptApproval?) {
        self.approval = approval; self.transport = transport; self.context = context; self.selected = selected
    }
    public func read(_ raw: String, session: MerchantBusinessSession, merchantID: Int, realm: String) async throws -> CityNodeRedemptionResult {
        guard isCurrent, let approval, approval.merchantID == merchantID,
              approval.context.baseURL.absoluteString.utf8.elementsEqual(realm.utf8),
              approval.context.session.accountID == session.accountID,
              approval.context.session.epoch == session.epoch,
              approval.context.session.token == session.token else { throw MerchantBusinessFailure.disabled }
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.utf8.count <= 16_384, let target = CityNodeRedemptionTarget(code: code) else { throw MerchantBusinessFailure.invalid }
        var request = try AuthRequestBuilder.makeFormRequest(url: approval.context.baseURL.appendingPathComponent("api/verify/citynode/receipt"),
            fields: ["code": code], token: session.token, includesBody: true)
        request.httpShouldHandleCookies = false
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        guard isCurrent, !Task.isCancelled else { throw CancellationError() }
        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status),
              let body = try JSONDecoder().decode(MerchantBusinessValue.self, from: data).object else { return .unknown() }
        if body["code"]?.integer == 401 { throw APIError.unauthorized }
        let value = try CityNodeRedemptionResult(body: body, target: target)
        // A read refusal/absence is never proof that the original command failed.
        return value.redeemed ? value : .unknown(serverMessage: body["msg"]?.string)
    }
}
