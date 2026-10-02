import Foundation

public struct MerchantEngagementProof: Equatable {
    public let access: MerchantEngagementAccess
    public let selectedSegment: MerchantSavedSegment?
    public let selectedCoupon: MerchantCampaignCoupon?
    public let audience: MerchantAudiencePreview?
    public let campaign: MerchantCampaignTask?
    public let exportTask: MerchantExportTask?
    public let customer: MerchantBusinessDocument?
    public let refund: MerchantBusinessDocument?
    public init(access: MerchantEngagementAccess, selectedSegment: MerchantSavedSegment? = nil, selectedCoupon: MerchantCampaignCoupon? = nil,
                audience: MerchantAudiencePreview? = nil, campaign: MerchantCampaignTask? = nil, exportTask: MerchantExportTask? = nil,
                customer: MerchantBusinessDocument? = nil, refund: MerchantBusinessDocument? = nil) {
        self.access = access; self.selectedSegment = selectedSegment; self.selectedCoupon = selectedCoupon; self.audience = audience
        self.campaign = campaign; self.exportTask = exportTask; self.customer = customer; self.refund = refund
    }
}
@MainActor public protocol MerchantEngagementReading: AnyObject {
    var scope: MerchantBusinessScope? { get }
    var isConfigured: Bool { get }
    var isSyntheticEnabled: Bool { get }
    func access() async throws -> MerchantEngagementAccess
    func read(_ query: MerchantEngagementQuery) async throws -> MerchantEngagementPayload
    func proof(_ command: MerchantEngagementCommand) async throws -> MerchantEngagementProof
    func execute(_ command: MerchantEngagementCommand, requestID: String, proof: MerchantEngagementProof, scope: MerchantBusinessScope) async throws -> MerchantEngagementReceipt
}
@MainActor public final class MerchantEngagementSessionReader: MerchantEngagementReading {
    private let service: MerchantEngagementService?
    private let session: () -> MerchantBusinessSession?
    private let unauthorized: (MerchantBusinessSession) -> Void
    public var isConfigured: Bool { service != nil }
    public var isSyntheticEnabled: Bool { service?.isSyntheticEnabled == true }
    public var scope: MerchantBusinessScope? { guard let session = session(), let service else { return nil }; return .init(realm: service.realm, accountID: session.accountID, epoch: session.epoch) }
    public init(service: MerchantEngagementService?, session: @escaping () -> MerchantBusinessSession?, onUnauthorized: @escaping (MerchantBusinessSession) -> Void = { _ in }) {
        self.service = service; self.session = session; unauthorized = onUnauthorized
    }
    public func access() async throws -> MerchantEngagementAccess { try await perform { service, captured in try await service.access(token: captured.token) } }
    public func read(_ query: MerchantEngagementQuery) async throws -> MerchantEngagementPayload {
        try await perform { service, captured in
            let grant = try await service.access(token: captured.token); try check(captured)
            return try await service.read(query, access: grant, token: captured.token)
        }
    }
    public func proof(_ command: MerchantEngagementCommand) async throws -> MerchantEngagementProof {
        try await perform { service, captured in
            _ = try command.request(requestID: "local-validation")
            let grant = try await service.access(token: captured.token); try check(captured)
            if case .acceptInvitation = command { return .init(access: grant) }
            try grant.require(command.permissions)
            func fetch(_ query: MerchantEngagementQuery) async throws -> MerchantEngagementPayload {
                try check(captured); let result = try await service.read(query, access: grant, token: captured.token); try check(captured); return result
            }
            switch command {
            case .createCampaign(let draft):
                guard case .segments(let segments) = try await fetch(.segments), let segment = segments.first(where: { $0.id == draft.segmentID }) else { throw MerchantBusinessFailure.conflict }
                var coupon: MerchantCampaignCoupon?
                if draft.channel == .coupon {
                    guard case .coupons(let coupons) = try await fetch(.coupons), let match = coupons.first(where: { $0.id == draft.couponID }) else { throw MerchantBusinessFailure.conflict }; coupon = match
                }
                guard case .audience(let preview) = try await fetch(.campaignPreview(draft.segmentID, draft.channel)), preview.canSend else { throw MerchantBusinessFailure.denied }
                return .init(access: grant, selectedSegment: segment, selectedCoupon: coupon, audience: preview)
            case .dispatchCampaign(let id), .retryCampaign(let id):
                guard case .campaign(let task) = try await fetch(.campaign(id)) else { throw MerchantBusinessFailure.malformed }
                guard command.key == "dispatchCampaign" ? task.canDispatch : task.canRetry else { throw MerchantBusinessFailure.conflict }
                if task.channel == .coupon { try grant.require(["merchant:coupon:manage"]) }
                return .init(access: grant, campaign: task)
            case .broadcast(let draft):
                guard case .audience(let preview) = try await fetch(.broadcastPreview(draft.audience)), preview.canSend else { throw MerchantBusinessFailure.denied }
                return .init(access: grant, audience: preview)
            case .downloadExport(let ticket, let selectedScope, let merchantID):
                guard scope == selectedScope, grant.merchantID == merchantID else { throw MerchantBusinessFailure.stale }
                guard case .exportStatus(let task) = try await fetch(.exportStatus(ticket.task.id)), task.isDownloadable, ticket.canDownload else { throw MerchantBusinessFailure.conflict }
                return .init(access: grant, exportTask: task)
            case .contact(let id, _):
                guard case .customer(let customer) = try await fetch(.customer(id)) else { throw MerchantBusinessFailure.malformed }
                return .init(access: grant, customer: customer)
            case .uploadEvidence(let id, _, let selectedScope, let merchantID):
                guard scope == selectedScope, grant.merchantID == merchantID else { throw MerchantBusinessFailure.stale }
                let refund = try await service.refund(id, access: grant, token: captured.token); try check(captured)
                guard refund.rows.first(where: { $0.kind == .refund })?.fields["canRespond"]?.bool == true else { throw MerchantBusinessFailure.denied }
                return .init(access: grant, refund: refund)
            case .saveSegment, .createExport: return .init(access: grant)
            case .acceptInvitation: return .init(access: grant)
            }
        }
    }
    public func execute(_ command: MerchantEngagementCommand, requestID: String, proof: MerchantEngagementProof, scope: MerchantBusinessScope) async throws -> MerchantEngagementReceipt {
        guard self.scope == scope else { throw MerchantBusinessFailure.stale }
        return try await perform { service, captured in try await service.execute(command, requestID: requestID, access: proof.access, token: captured.token) }
    }
    private func check(_ captured: MerchantBusinessSession) throws { guard session() == captured, !Task.isCancelled else { throw MerchantBusinessFailure.stale } }
    private func perform<T>(_ work: (MerchantEngagementService, MerchantBusinessSession) async throws -> T) async throws -> T {
        guard let captured = session() else { throw APIError.unauthorized }; guard let service else { throw APIError.notConfigured }
        do { try check(captured); let value = try await work(service, captured); try check(captured); return value }
        catch { try check(captured); if error as? APIError == .unauthorized { unauthorized(captured) }; throw error }
    }
}
