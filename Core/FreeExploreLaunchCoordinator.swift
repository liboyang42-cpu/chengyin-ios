import Foundation

@MainActor public final class FreeExploreLaunchCoordinator {
    public enum State: Equatable { case idle, loading, outcomeUnknown, confirmed, staleSession }
    private let service: any FreeExploreLaunchServing
    private let pending: FreeExploreLaunchPendingStore
    private var working = false
    private var stateValue: State = .idle
    private var catalogValue: FreeExploreLaunchCatalog?
    private var orderValue: FreeExploreLaunchOrder?
    private var quoteValue: FreeExploreLaunchRefundQuote?
    public var state: State { service.isCurrent ? stateValue : .staleSession }
    public var catalog: FreeExploreLaunchCatalog? { service.isCurrent ? catalogValue : nil }
    public var order: FreeExploreLaunchOrder? { service.isCurrent ? orderValue : nil }
    public var refundQuote: FreeExploreLaunchRefundQuote? { service.isCurrent ? quoteValue : nil }
    public init(service: any FreeExploreLaunchServing, pending: FreeExploreLaunchPendingStore) throws {
        guard pending.matches(service.session) else { throw FreeExploreLaunchFailure.invalid }
        self.service = service; self.pending = pending
        if try pending.load() != nil { stateValue = .outcomeUnknown }
    }
    private func check() throws {
        guard service.isCurrent else { throw FreeExploreLaunchFailure.staleSession }
        try Task.checkCancellation()
    }
    private func begin() throws {
        try check(); guard !working else { throw FreeExploreLaunchFailure.busy }
        working = true; stateValue = .loading
    }
    private func finish() {
        working = false
        if stateValue == .loading {
            do { stateValue = try pending.load() == nil ? .idle : .outcomeUnknown }
            catch { stateValue = .outcomeUnknown }
        }
    }
    public func browse(topicID: FreeExploreLaunchID) async throws {
        try begin(); defer { finish() }; catalogValue = nil
        let result = try await service.catalog(topicID: topicID); try check()
        catalogValue = result
    }
    public func readOrder(registrationID: FreeExploreLaunchID) async throws {
        try begin(); defer { finish() }; orderValue = nil; quoteValue = nil
        let result = try await service.order(registrationID: registrationID); try check()
        try result.validate(owner: service.session.accountID, registration: registrationID)
        orderValue = result
    }
    public func readRefundQuote(registrationID: FreeExploreLaunchID) async throws {
        try begin(); defer { finish() }; quoteValue = nil; orderValue = nil
        let owned = try await service.order(registrationID: registrationID); try check()
        try owned.validate(owner: service.session.accountID, registration: registrationID)
        guard owned.bundle != nil else { throw FreeExploreLaunchFailure.disabled }
        let quote = try await service.refundQuote(registrationID: registrationID); try check()
        orderValue = owned; quoteValue = quote
    }
    public func reserve(_ command: FreeExploreLaunchReservationCommand, topicID: FreeExploreLaunchID) async throws {
        try begin(); defer { finish() }
        guard try pending.load() == nil else { stateValue = .outcomeUnknown; throw FreeExploreLaunchFailure.pendingConflict }
        try command.validate()
        let owned = try await service.order(registrationID: command.registrationId); try check()
        try owned.validate(owner: service.session.accountID, registration: command.registrationId)
        let catalog = try await service.catalog(topicID: topicID); try check()
        guard catalog.topicId == topicID, catalog.productType == 2, catalog.reservationEnabled,
              let bundle = owned.bundle, bundle.order.topicId == topicID,
              let unit = bundle.units.first(where: { $0.id == command.unitId && $0.status == "AVAILABLE" }),
              catalog.items.contains(where: { $0.chapterId == unit.chapterId && $0.stores.contains(where: { $0.offerId == command.offerId }) }) else {
            throw FreeExploreLaunchFailure.disabled
        }
        // No future-time, opening-hours, payment, quota, penalty or money decisions locally.
        try check(); try pending.save(command); stateValue = .outcomeUnknown
        orderValue = nil; quoteValue = nil
        do { _ = try await service.reserve(command); try check() }
        catch { try check(); throw FreeExploreLaunchFailure.outcomeUnknown }
        _ = try await recover(command)
    }
    /// Relaunch/network recovery only reads the original reservation key and original order.
    @discardableResult public func recover() async throws -> FreeExploreLaunchOrder? {
        try begin(); defer { finish() }
        guard let command = try pending.load() else { return nil }
        return try await recover(command)
    }
    private func recover(_ command: FreeExploreLaunchReservationCommand) async throws -> FreeExploreLaunchOrder? {
        stateValue = .outcomeUnknown; orderValue = nil; quoteValue = nil
        guard let receipt = try await service.receipt(command) else { try check(); return nil }
        try check()
        guard receipt.matches(command, owner: service.session.accountID) else { throw FreeExploreLaunchFailure.malformed }
        let owned = try await service.order(registrationID: command.registrationId); try check()
        try owned.validate(owner: service.session.accountID, registration: command.registrationId)
        try pending.acknowledge(receipt: receipt, order: owned)
        orderValue = owned; stateValue = .confirmed; return owned
    }
    /// Explicit user retry; never generates a new UUID or changes the saved payload.
    public func retryOriginalReservation() async throws {
        try begin(); defer { finish() }
        guard let command = try pending.load() else { throw FreeExploreLaunchFailure.invalid }
        if try await recover(command) != nil { return }
        try check()
        let owned = try await service.order(registrationID: command.registrationId); try check()
        try owned.validate(owner: service.session.accountID, registration: command.registrationId)
        guard let bundle = owned.bundle else { throw FreeExploreLaunchFailure.disabled }
        let catalog = try await service.catalog(topicID: bundle.order.topicId); try check()
        guard catalog.topicId == bundle.order.topicId, catalog.productType == 2, catalog.reservationEnabled else {
            throw FreeExploreLaunchFailure.disabled
        }
        do { _ = try await service.reserve(command); try check() }
        catch { try check(); throw FreeExploreLaunchFailure.outcomeUnknown }
        _ = try await recover(command)
    }
    /// No cancel POST is dispatched without the missing server quote/confirmation contract.
    public func prepareCancellation(reservationID: FreeExploreLaunchID, useWaiver: Bool) throws -> Never {
        try check(); throw FreeExploreLaunchFailure.cancellationQuoteUnavailable
    }
}
