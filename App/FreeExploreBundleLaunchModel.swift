import Foundation
import Observation

/// Unmounted candidate. The host must retire this model on path removal, account/realm/role
/// changes or approval revocation. A catalog flag never grants transport authorization.
@MainActor @Observable final class FreeExploreBundleLaunchModel {
    struct Review: Equatable, Identifiable {
        let id: UUID
        let command: FreeExploreLaunchReservationCommand
        let generation: UInt64
    }
    let topicID: FreeExploreLaunchID
    let registrationID: FreeExploreLaunchID
    private let service: FreeExploreBundleLaunchGate
    private let coordinator: FreeExploreLaunchCoordinator
    private let dispatchAllowed: () -> Bool
    private var retired = false
    private var generation: UInt64 = 0
    private var catalogValue: FreeExploreLaunchCatalog?
    private var orderValue: FreeExploreLaunchOrder?
    private var stateValue: FreeExploreLaunchCoordinator.State = .idle
    private(set) var busy = false
    private(set) var failure: FreeExploreLaunchFailure?
    private(set) var review: Review?
    var current: Bool { !retired && service.isCurrent }
    var state: FreeExploreLaunchCoordinator.State { current ? stateValue : .staleSession }
    var catalog: FreeExploreLaunchCatalog? { current ? catalogValue : nil }
    var order: FreeExploreLaunchOrder? { current ? orderValue : nil }
    var canReserve: Bool {
        current && !busy && dispatchAllowed() && service.permitsReservationDispatch &&
        state != .outcomeUnknown && catalog?.reservationEnabled == true && order?.bundle != nil
    }
    var canRetry: Bool {
        current && !busy && state == .outcomeUnknown && dispatchAllowed() && service.permitsReservationDispatch
    }
    init(topicID: FreeExploreLaunchID, registrationID: FreeExploreLaunchID,
         service: any FreeExploreLaunchServing, pending: FreeExploreLaunchPendingStore,
         dispatchAllowed: @escaping () -> Bool = { false }) throws {
        self.topicID = topicID; self.registrationID = registrationID
        let gated = FreeExploreBundleLaunchGate(origin: service, allowed: dispatchAllowed)
        self.service = gated; self.dispatchAllowed = dispatchAllowed
        coordinator = try FreeExploreLaunchCoordinator(service: gated, pending: pending)
        stateValue = coordinator.state
    }
    /// Clears private display, never durable pending metadata. Late results cannot revive it.
    func retire() {
        retired = true; service.active = false; generation &+= 1; busy = false
        review = nil; catalogValue = nil; orderValue = nil; failure = nil
        stateValue = .staleSession
    }
    func cancelReview() { review = nil }
    func load() async {
        await perform {
            // Relaunch performs GET-only recovery, never an automatic replay.
            if self.coordinator.state == .outcomeUnknown { _ = try await self.coordinator.recover() }
            try await self.coordinator.browse(topicID: self.topicID)
            try await self.coordinator.readOrder(registrationID: self.registrationID)
        }
    }
    func recover() async { await perform { _ = try await self.coordinator.recover() } }
    func retryOriginal() async {
        guard canRetry else { failure = .disabled; return }
        await perform { try await self.coordinator.retryOriginalReservation() }
    }
    func prepare(unitID: FreeExploreLaunchID, offerID: FreeExploreLaunchID, startAt: Int64) {
        review = nil; failure = nil
        guard canReserve, let catalog, let bundle = order?.bundle,
              bundle.order.topicId == topicID,
              let unit = bundle.units.first(where: { $0.id == unitID && $0.status == "AVAILABLE" }),
              catalog.items.contains(where: { $0.chapterId == unit.chapterId && $0.stores.contains(where: { $0.offerId == offerID }) }) else {
            failure = .disabled; return
        }
        do {
            let command = try FreeExploreLaunchReservationCommand(registrationId: registrationID,
                unitId: unitID, offerId: offerID, startAt: startAt)
            review = Review(id: UUID(), command: command, generation: generation)
        } catch { failure = error as? FreeExploreLaunchFailure ?? .invalid }
    }
    func confirm(_ original: Review) async {
        guard canReserve, review == original, original.generation == generation else {
            review = nil; failure = .disabled; return
        }
        review = nil
        await perform { try await self.coordinator.reserve(original.command, topicID: self.topicID) }
    }
    private func perform(_ operation: () async throws -> Void) async {
        guard current else { retire(); return }
        guard !busy else { return }
        busy = true; failure = nil; review = nil
        // Never present stale order facts while a fresh read is unresolved.
        catalogValue = nil; orderValue = nil
        let captured = generation
        var succeeded = false
        defer {
            if generation == captured {
                busy = false
                if current {
                    stateValue = coordinator.state
                    if succeeded {
                        catalogValue = coordinator.catalog
                        if coordinator.order?.registrationId == registrationID { orderValue = coordinator.order }
                    }
                } else { retire() }
            }
        }
        do { try await operation(); succeeded = true }
        catch {
            guard current, generation == captured else { return }
            // Cancellation is not evidence that a dispatched request failed.
            failure = error as? FreeExploreLaunchFailure ??
                (coordinator.state == .outcomeUnknown ? .outcomeUnknown : .response(status: 0, code: 0, businessCode: nil))
        }
    }
}

/// Re-checks the separately supplied host grant during Core preflight, not just at button tap.
@MainActor private final class FreeExploreBundleLaunchGate: FreeExploreLaunchServing {
    let origin: any FreeExploreLaunchServing
    let allowed: () -> Bool
    var active = true
    init(origin: any FreeExploreLaunchServing, allowed: @escaping () -> Bool) {
        self.origin = origin; self.allowed = allowed
    }
    var session: FreeExploreLaunchSession { origin.session }
    var isCurrent: Bool { active && origin.isCurrent }
    var permitsReservationDispatch: Bool { isCurrent && allowed() && origin.permitsReservationDispatch }
    func catalog(topicID: FreeExploreLaunchID) async throws -> FreeExploreLaunchCatalog {
        try check(); return try await origin.catalog(topicID: topicID)
    }
    func order(registrationID: FreeExploreLaunchID) async throws -> FreeExploreLaunchOrder {
        try check(); return try await origin.order(registrationID: registrationID)
    }
    func reserve(_ command: FreeExploreLaunchReservationCommand) async throws -> FreeExploreLaunchReservation {
        try check(); guard permitsReservationDispatch else { throw FreeExploreLaunchFailure.disabled }
        return try await origin.reserve(command)
    }
    func receipt(_ command: FreeExploreLaunchReservationCommand) async throws -> FreeExploreLaunchReservation? {
        try check(); return try await origin.receipt(command)
    }
    func refundQuote(registrationID: FreeExploreLaunchID) async throws -> FreeExploreLaunchRefundQuote {
        try check(); return try await origin.refundQuote(registrationID: registrationID)
    }
    private func check() throws {
        guard isCurrent else { throw FreeExploreLaunchFailure.staleSession }
        try Task.checkCancellation()
    }
}
