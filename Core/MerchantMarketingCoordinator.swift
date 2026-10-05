import Foundation
import Observation

@MainActor @Observable public final class MerchantMarketingCoordinator {
    public enum Surface: String, CaseIterable, Identifiable {
        case dashboard, insight, subscriptions, predictions
        public var id: String { rawValue }
        public var titleKey: String { "merchantMarketing." + rawValue }
    }
    public let service: MerchantMarketingService
    public private(set) var surface: Surface = .dashboard
    public private(set) var busy = false
    public private(set) var dashboard: MerchantMarketingDashboard?
    public private(set) var insight: MerchantMarketingInsight?
    public private(set) var subscriptions: [MerchantMarketingEntitlement]?
    public private(set) var commerce: MerchantMarketingCommerce?
    public private(set) var rounds: [MerchantPredictionRound]?
    public private(set) var review: MerchantPredictionReview?
    public private(set) var acknowledgement: MerchantPredictionAcknowledgement?
    public private(set) var failure: MerchantMarketingFailure?
    public private(set) var commerceFailure: MerchantMarketingFailure?
    private var generation = UUID()
    private var observedScope: MerchantMarketingScope?
    public init(service: MerchantMarketingService) { self.service = service; observedScope = service.scope }
    public var scopeIdentity: String {
        guard let s = service.scope else { return "signed-out" }
        return "\(s.namespace.utf8.count):\(s.namespace):\(s.accountID):\(s.epoch)"
    }
    /// Host MUST invoke on session/token/epoch/profile changes, including while a sheet is visible.
    public func sessionChanged() {
        generation = UUID(); observedScope = service.scope; busy = false
        dashboard = nil; insight = nil; subscriptions = nil; commerce = nil; rounds = nil
        review = nil; acknowledgement = nil; failure = nil; commerceFailure = nil; service.discardReview()
    }
    private func valid(_ ticket: UUID, _ scope: MerchantMarketingScope?) -> Bool {
        guard generation == ticket else { return false }
        guard service.scope == scope else { sessionChanged(); return false }; return true
    }
    private func normalize(_ error: Error) -> MerchantMarketingFailure { (error as? MerchantMarketingFailure) ?? .malformed }
    public func load(_ next: Surface) async {
        if observedScope != service.scope { sessionChanged() }
        generation = UUID(); let ticket = generation, scope = service.scope
        surface = next; busy = true; failure = nil; commerceFailure = nil; acknowledgement = nil; review = nil
        dashboard = nil; insight = nil; subscriptions = nil; commerce = nil; rounds = nil; service.discardReview()
        do {
            switch next {
            case .dashboard:
                let value = try await service.dashboard(); guard valid(ticket, scope) else { return }; dashboard = value
            case .insight:
                let value = try await service.insight(); guard valid(ticket, scope) else { return }; insight = value
            case .subscriptions:
                let value = try await service.subscriptions(); guard valid(ticket, scope) else { return }; subscriptions = value
                do { let caps = try await service.commerce(); guard valid(ticket, scope) else { return }; commerce = caps }
                catch { guard valid(ticket, scope) else { return }; commerceFailure = normalize(error) }
            case .predictions:
                let value = try await service.inbox(); guard valid(ticket, scope) else { return }; rounds = value
            }
        } catch { guard valid(ticket, scope) else { return }; failure = normalize(error) }
        guard valid(ticket, scope) else { return }; busy = false
    }
    public func prepare(_ round: MerchantPredictionRound, option: String) async {
        guard !busy, rounds?.contains(round) == true else { return }
        let ticket = generation, scope = service.scope; busy = true; failure = nil; acknowledgement = nil
        do { let value = try await service.prepare(round: round, optionKey: option); guard valid(ticket, scope) else { return }; review = value }
        catch { guard valid(ticket, scope) else { return }; failure = normalize(error) }
        guard valid(ticket, scope) else { return }; busy = false
    }
    public func cancelReview() { guard !busy else { return }; review = nil; service.discardReview() }
    public func confirm(couponEffectsAcknowledged: Bool) async {
        guard !busy, let accepted = review else { return }
        let ticket = generation, scope = service.scope; busy = true; failure = nil
        do {
            let result = try await service.settle(accepted, acknowledgedCouponEffects: couponEffectsAcknowledged)
            guard valid(ticket, scope) else { return }
            acknowledgement = result; rounds?.removeAll { $0 == accepted.round }; review = nil
        } catch { guard valid(ticket, scope) else { return }; failure = normalize(error); review = nil }
        guard valid(ticket, scope) else { return }; busy = false
    }
}
