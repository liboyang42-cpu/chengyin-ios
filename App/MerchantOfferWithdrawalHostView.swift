import SwiftUI

/// C8 host. Builds the withdrawal subject from the account's own
/// `chapterApplicationsMine` readback plus the topic detail, and — after a
/// confirmed readback — makes the host reload `.applications` before return.
/// The signed-in session mounts `MerchantOfferWithdrawalProtectedExecutor`.
/// A nil executor stays the dormant one, which throws disabled and never
/// reports success. The protected executor calls `api/coop/offer/withdraw`
/// only when `CoopFlowService.permitsDispatch` is true.
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

/// Executes C8 only through `CoopFlowMutation.withdrawOffer` (`POST api/coop/offer/withdraw`).
/// `permits` is the existing service gate. When it is shut, `withdraw` throws
/// `.disabled` before `prepare`, so nothing leaves the device.
struct MerchantOfferWithdrawalTopicFacts: Sendable {
    var productType: Int
    var lifecycle: Int
    var circleThemeCode: String?
}
@MainActor final class MerchantOfferWithdrawalProtectedExecutor: MerchantOfferWithdrawalExecuting {
    private let coordinator: CoopFlowCoordinator
    private let reader: any CoopFlowReading
    private let coopSession: () -> CoopFlowSession?
    private let permits: () -> Bool
    public init(coordinator: CoopFlowCoordinator, reader: any CoopFlowReading, coopSession: @escaping () -> CoopFlowSession?, permits: @escaping () -> Bool) {
        self.coordinator = coordinator; self.reader = reader; self.coopSession = coopSession; self.permits = permits
    }
    /// Shipping gate: `CoopFlowDormantExecutor.permitsDispatch(.withdrawOffer)`.
    /// The coordinator's `enabled` flag is that same value, captured once.
    /// Production `CoopFlowService` keeps `dormantWritesEnabled` false and
    /// `protectedDispatch` nil, and a real transport is not
    /// `CoopFlowOfflineHTTPTransport`, so this stays false.
    static func gated(service: CoopFlowService, reader: any CoopFlowReading, coopSession: @escaping () -> CoopFlowSession?,
                             locks: any CoopFlowLockStore, topic: @escaping (Int) async throws -> MerchantOfferWithdrawalTopicFacts?) -> MerchantOfferWithdrawalProtectedExecutor {
        let transport = CoopFlowDormantExecutor(service: service)
        let open = transport.permitsDispatch(.withdrawOffer(id: 1, reason: "gate"))
        let coordinator = CoopFlowCoordinator(current: coopSession, evidence: CoopFlowSourceEvidenceReader(reader: reader, additional: { operation, captured in
            guard case .withdrawOffer(let id, _) = operation, reader.session == captured else {
                return CoopFlowEvidence(baseline: .null, permitted: false)
            }
            let mine: CoopFlowJSON
            do { mine = try await reader.read(.chapterApplicationsMine) } catch { return CoopFlowEvidence(baseline: .null, permitted: false) }
            guard reader.session == captured else { return CoopFlowEvidence(baseline: .null, permitted: false) }
            let rows = mine.rows ?? mine["rows"].rows ?? []
            guard let row = rows.first(where: { $0["offerId"].integer == id }), let topicID = row["topicId"].integer, topicID > 0,
                  let facts = try? await topic(topicID) else {
                return CoopFlowEvidence(baseline: .object(["rows": mine]), permitted: false)
            }
            var topicFields: [String: CoopFlowJSON] = ["productType": .id(facts.productType), "lifecycle": .id(facts.lifecycle)]
            if let circle = facts.circleThemeCode, !circle.isEmpty { topicFields["circleThemeCode"] = .string(circle) }
            return CoopFlowEvidence(baseline: .object(["rows": mine, "topic": .object(topicFields)]), permitted: true)
        }), executor: transport, locks: locks, enabled: open)
        return MerchantOfferWithdrawalProtectedExecutor(coordinator: coordinator, reader: reader, coopSession: coopSession,
            permits: { transport.permitsDispatch(.withdrawOffer(id: 1, reason: "gate")) })
    }
    public var permitsSubmission: Bool { permits() }
    public func withdraw(_ request: MerchantOfferWithdrawalRequest, session: MerchantOfferWithdrawalSession) async throws -> MerchantOfferWithdrawalResponseHint {
        guard permits() else { throw MerchantOfferWithdrawalFailure.disabled }
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
