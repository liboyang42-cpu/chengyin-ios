import Foundation

/// Normal composition keeps concrete read/write clients dormant behind separate grants.
/// Merely obtaining a session, context or evidence cache never sends a request.
@MainActor public struct PublicMerchantReviewGatedWriter: PublicMerchantReviewWriting {
    private let base: any PublicMerchantReviewWriting
    private let enabled: Bool
    private let record: (PublicMerchantReviewPage, PublicMerchantReviewTarget, PublicMerchantReviewSession) -> Void
    private let discard: (PublicMerchantReviewTarget) -> Void
    public var isConfigured: Bool { enabled && base.isConfigured }
    public var session: PublicMerchantReviewSession? { base.session }
    public init(base: any PublicMerchantReviewWriting, enabled: Bool = false,
                record: @escaping (PublicMerchantReviewPage, PublicMerchantReviewTarget, PublicMerchantReviewSession) -> Void = { _, _, _ in },
                discard: @escaping (PublicMerchantReviewTarget) -> Void = { _ in }) {
        self.base = base; self.enabled = enabled; self.record = record; self.discard = discard
    }
    public func evidence(_ target: PublicMerchantReviewTarget, page: Int, session: PublicMerchantReviewSession) async throws -> PublicMerchantReviewPage {
        guard isConfigured else { throw PublicMerchantReviewWriteFailure.notConfigured }
        discard(target)
        let result = try await base.evidence(target, page: page, session: session)
        guard base.session == session, !Task.isCancelled else { throw PublicMerchantReviewWriteFailure.sessionChanged }
        try result.validate(page: page, size: 20)
        record(result, target, session)
        return result
    }
    public func execute(_ command: PublicMerchantReviewCommand, target: PublicMerchantReviewTarget, requestID: String, session: PublicMerchantReviewSession) async throws -> PublicMerchantReviewReceipt {
        guard isConfigured else { throw PublicMerchantReviewWriteFailure.notConfigured }
        guard base.session == session else { throw PublicMerchantReviewWriteFailure.sessionChanged }
        // Dispatch invalidates eligibility even if the outcome is unknown. The durable journal
        // remains the only review-write recovery authority.
        discard(target)
        return try await base.execute(command, target: target, requestID: requestID, session: session)
    }
}

/// Cached validated eligibility is tied to the full target and exact authenticated session.
/// UUIDs are local invalidation fences, never server versions or permission grants.
@MainActor public final class PublicMerchantReviewImageEvidence {
    private struct Entry {
        let target: PublicMerchantReviewTarget
        let session: PublicMerchantReviewSession
        let eligibility: PublicMerchantReviewPage.Eligibility
        let revision: UUID
    }
    private var entries: [Entry] = []
    private var suspended: Set<PublicMerchantReviewTarget> = []
    public init() {}
    public func record(_ page: PublicMerchantReviewPage, target: PublicMerchantReviewTarget, session: PublicMerchantReviewSession) throws {
        try page.validate(page: page.pageNum, size: 20)
        let old = entries.first { $0.target == target && $0.session == session }
        let revision = old?.eligibility == page.eligibility ? old!.revision : UUID()
        entries.removeAll { $0.target == target }
        entries.append(.init(target: target, session: session, eligibility: page.eligibility, revision: revision))
        suspended.remove(target)
    }
    public func revision(target: PublicMerchantReviewTarget, registrationID: Int, session: PublicMerchantReviewSession) -> UUID? {
        guard !suspended.contains(target), let value = entries.first(where: { $0.target == target && $0.session == session }),
              registrationID > 0, value.eligibility.canCreate,
              value.eligibility.reasonCode == "ELIGIBLE", value.eligibility.registrationId == registrationID else { return nil }
        return value.revision
    }
    public func suspend(_ target: PublicMerchantReviewTarget) { suspended.insert(target) }
    public func invalidate(_ target: PublicMerchantReviewTarget) { entries.removeAll { $0.target == target }; suspended.remove(target) }
    public func invalidate() { entries.removeAll(); suspended.removeAll() }
}
