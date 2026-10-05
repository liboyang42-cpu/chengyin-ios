import Foundation

public struct PublicMerchantReviewConfirmation: Equatable, Identifiable {
    public let id: UUID
    public let target: PublicMerchantReviewTarget
    public let command: PublicMerchantReviewCommand
    public let session: PublicMerchantReviewSession
    public let requestID: String
    public let page: Int
}
/// Reuses merchant-business durable intent storage. No new review-mutation engine is installed in that domain.
@MainActor public final class PublicMerchantReviewCoordinator {
    public let writer: any PublicMerchantReviewWriting
    public let journal: any MerchantBusinessIntentStore
    public private(set) var confirmation: PublicMerchantReviewConfirmation?
    public private(set) var receipt: PublicMerchantReviewReceipt?
    public private(set) var failure: PublicMerchantReviewWriteFailure?
    public private(set) var busy = false
    public private(set) var locked = false
    private var generation = 0
    public init(writer: any PublicMerchantReviewWriting, journal: any MerchantBusinessIntentStore) { self.writer = writer; self.journal = journal }
    public func invalidate() { generation += 1; confirmation = nil; receipt = nil; failure = nil; busy = false }
    public func cancel() { confirmation = nil }
    public func prepare(_ command: PublicMerchantReviewCommand, target: PublicMerchantReviewTarget, page: Int) async {
        guard !busy else { return }
        confirmation = nil; receipt = nil; failure = nil
        guard writer.isConfigured, let session = writer.session else { failure = .notConfigured; return }
        busy = true; let ticket = generation
        defer { if ticket == generation { busy = false } }
        do {
            let requestID = "mpr-" + UUID().uuidString.lowercased()
            try command.validateImages(target: target, session: session)
            _ = try command.body(target: target, requestID: requestID)
            let review = PublicMerchantReviewConfirmation(id: UUID(), target: target, command: command, session: session, requestID: requestID, page: page)
            let intent = intent(review)
            do { locked = try journal.intents().contains { $0.sameTarget(as: intent) } }
            catch { throw PublicMerchantReviewWriteFailure.storage }
            guard !locked else { throw PublicMerchantReviewWriteFailure.unknown }
            let evidence = try await writer.evidence(target, page: page, session: session)
            guard ticket == generation, writer.session == session, !Task.isCancelled else { throw PublicMerchantReviewWriteFailure.sessionChanged }
            try evidence.validate(page: page, size: 20)
            try validate(command, evidence: evidence)
            confirmation = review
        } catch { if ticket == generation { failure = (error as? PublicMerchantReviewWriteFailure) ?? .permissionChanged } }
    }
    public func confirm(_ review: PublicMerchantReviewConfirmation) async {
        guard !busy, confirmation == review, writer.session == review.session else { failure = .sessionChanged; return }
        confirmation = nil; busy = true; failure = nil
        let ticket = generation
        defer { if ticket == generation { busy = false } }
        let intent = intent(review)
        do {
            let evidence = try await writer.evidence(review.target, page: review.page, session: review.session)
            guard ticket == generation, writer.session == review.session, !Task.isCancelled else { throw PublicMerchantReviewWriteFailure.sessionChanged }
            try evidence.validate(page: review.page, size: 20)
            try review.command.validateImages(target: review.target, session: review.session)
            try validate(review.command, evidence: evidence)
            try journal.reserve(intent)
        } catch { if ticket == generation { failure = (error as? PublicMerchantReviewWriteFailure) ?? .storage }; return }
        locked = true
        do {
            let result = try await writer.execute(review.command, target: review.target, requestID: review.requestID, session: review.session)
            guard ticket == generation, writer.session == review.session, !Task.isCancelled else { return }
            try result.validate(review.command)
            try journal.complete(intent)
            locked = false; receipt = result
        } catch {
            guard ticket == generation, writer.session == review.session else { return }
            let writeFailure = (error as? PublicMerchantReviewWriteFailure) ?? .unknown
            if case .rejected = writeFailure {
                do { try journal.complete(intent); locked = false } catch { failure = .storage; return }
            }
            failure = writeFailure
        }
    }
    private func validate(_ command: PublicMerchantReviewCommand, evidence: PublicMerchantReviewPage) throws {
        switch command {
        case .create(let registration, _, _, _):
            guard evidence.eligibility.canCreate, evidence.eligibility.reasonCode == "ELIGIBLE", evidence.eligibility.registrationId == registration else { throw PublicMerchantReviewWriteFailure.permissionChanged }
        case .report(let id, let version, _):
            guard let row = evidence.items.first(where: { $0.id == id }), row.canReport, row.status == "VISIBLE", row.version == version else { throw PublicMerchantReviewWriteFailure.permissionChanged }
        }
    }
    private func intent(_ review: PublicMerchantReviewConfirmation) -> MerchantBusinessIntent {
        let target: String
        switch review.command {
        case .create(let registration, _, _, _): target = "public-review-create-\(registration)"
        case .report(let id, _, _): target = "public-review-report-\(id)"
        }
        return .init(scope: .init(realm: review.session.realm, accountID: review.session.accountID, epoch: 0),
                     merchantID: review.target.merchantRowID.rawValue, target: target, requestID: review.requestID)
    }
}
