import SwiftUI

/// C8 host (integration-owned composition). Builds the withdrawal subject from the
/// account's own `chapterApplicationsMine` readback plus the topic detail, and —
/// after a confirmed readback — makes the host reload `.applications` before return.
/// Shipped composition injects no approved executor, so submission stays dormant;
/// `MerchantOfferWithdrawalProtectedExecutor` below is the approved-composition
/// adapter and is deliberately not mounted here.
@MainActor struct MerchantOfferWithdrawalHostView: View {
    let source: MerchantContentSupplyContext
    let reader: any CoopFlowReading
    var contentService: (any MerchantContentServing)? = nil
    private let coordinator: MerchantOfferWithdrawalCoordinator
    @State private var subject: MerchantOfferWithdrawalSubject?
    @State private var failed = false
    @State private var loadedSession: CoopFlowSession?

    init(source: MerchantContentSupplyContext, reader: any CoopFlowReading,
         contentService: (any MerchantContentServing)? = nil,
         executor: (any MerchantOfferWithdrawalExecuting)? = nil) {
        self.source = source; self.reader = reader; self.contentService = contentService
        coordinator = MerchantOfferWithdrawalCoordinator(
            currentSession: { reader.session.flatMap { try? MerchantOfferWithdrawalSession(accountID: $0.accountID, epoch: $0.epoch) } },
            executor: executor ?? MerchantOfferWithdrawalDormantExecutor())
    }

    var body: some View {
        Group {
            if reader.session == nil { Text("cooperation.login") }
            else if let subject {
                MerchantOfferWithdrawalView(subject: subject, coordinator: coordinator) { _ in
                    Task { await syncReturn() }
                }
            } else if failed { Text("merchant.content.supplyLoadFailed").accessibilityIdentifier("merchant.offerWithdrawal.loadFailed") }
            else { ProgressView("merchant.loading") }
        }
        .task(id: reader.session?.accountID ?? 0) { await load() }
    }

    private func load() async {
        subject = nil; failed = false; loadedSession = nil
        guard let session = reader.session else { return }
        do {
            let mine = try await reader.read(.chapterApplicationsMine)
            guard !Task.isCancelled, reader.session == session else { return }
            guard let row = (mine.rows ?? []).first(where: { $0["offerId"].integer == source.offerID }) else { failed = true; return }
            let converted = Self.merchantValue(row)
            var topic: MerchantContentValue? = nil, required: Bool? = nil
            if let contentService, let topicID = converted["topicId"].integer, topicID > 0 {
                let snapshot = try? await contentService.load(.chapters(topicID: topicID))
                if let snapshot {
                    topic = snapshot.value["topic"]
                    if let chapter = (snapshot.value["chapters"].array ?? []).first(where: { $0["id"].integer == source.chapterID }) {
                        required = chapter["required"].flag ?? chapter["required"].integer.map { $0 == 1 }
                    }
                }
            }
            guard !Task.isCancelled, reader.session == session else { return }
            let built = MerchantOfferWithdrawalSubject(mineRow: converted, topic: topic, chapterRequired: required)
            subject = built
            loadedSession = session
        } catch { if !Task.isCancelled, reader.session == session { failed = true } }
    }

    /// Return sync: the host re-reads `.applications`, then this host refreshes its subject.
    private func syncReturn() async {
        if let contentService { _ = try? await contentService.load(.applications) }
        await load()
    }

    static func merchantValue(_ value: CoopFlowJSON) -> MerchantContentValue {
        switch value {
        case .null: return .null
        case .bool(let v): return .bool(v)
        case .string(let v): return .string(v)
        case .number(let v):
            if let exact = Int(exactly: NSDecimalNumber(decimal: v)) { return .integer(exact) }
            return .decimal(v)
        case .array(let rows): return .array(rows.map(merchantValue))
        case .object(let fields): return .object(fields.mapValues(merchantValue))
        }
    }
}

/// Approved-composition adapter: executes C8 only through the protected-dispatch
/// coordinator (`CoopFlowMutation.withdrawOffer`, separate enablement + endpoint grant).
/// Not constructed by shipped Home composition — no coordinator/evidence composition
/// exists there — so the shipped path remains the dormant executor above.
@MainActor final class MerchantOfferWithdrawalProtectedExecutor: MerchantOfferWithdrawalExecuting {
    private let coordinator: CoopFlowCoordinator
    private let reader: any CoopFlowReading
    private let coopSession: () -> CoopFlowSession?
    public init(coordinator: CoopFlowCoordinator, reader: any CoopFlowReading, coopSession: @escaping () -> CoopFlowSession?) {
        self.coordinator = coordinator; self.reader = reader; self.coopSession = coopSession
    }
    public var permitsSubmission: Bool { true }
    public func withdraw(_ request: MerchantOfferWithdrawalRequest, session: MerchantOfferWithdrawalSession) async throws -> MerchantOfferWithdrawalResponseHint {
        guard let current = coopSession(), current.accountID == session.accountID, current.epoch == session.epoch else {
            throw MerchantOfferWithdrawalFailure.changedSession
        }
        do {
            let review = try await coordinator.prepare(.withdrawOffer(id: request.offerID, reason: request.reason.value))
            let result = try await coordinator.confirm(review)
            guard coopSession() == current else { throw MerchantOfferWithdrawalFailure.changedSession }
            return try MerchantOfferWithdrawalResponseHint(data: MerchantOfferWithdrawalHostView.merchantValue(result))
        } catch let error as MerchantOfferWithdrawalFailure { throw error }
        catch CoopFlowFailure.server(let code, let message) { throw MerchantOfferWithdrawalFailure.rejected(code: code, message: message) }
        catch CoopFlowFailure.disabled { throw MerchantOfferWithdrawalFailure.disabled }
        catch CoopFlowFailure.permission { throw MerchantOfferWithdrawalFailure.denied }
        catch CoopFlowFailure.stale { throw MerchantOfferWithdrawalFailure.changedSession }
        catch { throw MerchantOfferWithdrawalFailure.unknown }
    }
    public func mineRows(session: MerchantOfferWithdrawalSession) async throws -> [MerchantContentValue] {
        guard let current = coopSession(), current.accountID == session.accountID, current.epoch == session.epoch else {
            throw MerchantOfferWithdrawalFailure.changedSession
        }
        let value = try await reader.read(.chapterApplicationsMine)
        guard coopSession() == current else { throw MerchantOfferWithdrawalFailure.changedSession }
        return (value.rows ?? []).map(MerchantOfferWithdrawalHostView.merchantValue)
    }
}
