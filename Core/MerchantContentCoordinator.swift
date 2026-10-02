import Foundation

public struct MerchantContentReview: Identifiable, Equatable {
    public let id: UUID
    public let command: MerchantContentCommand
    public let baseline: MerchantContentSnapshot
    public let scope: UUID
}
@MainActor public final class MerchantContentCoordinator {
    public let service: any MerchantContentServing
    public let query: MerchantContentQuery
    public private(set) var snapshot: MerchantContentSnapshot?
    public private(set) var review: MerchantContentReview?
    public private(set) var receipt: MerchantContentReceipt?
    public private(set) var issue: String?
    public private(set) var serverMessage: String?
    public private(set) var busy = false
    public private(set) var locked = false
    public private(set) var loadedScope: UUID?
    private var generation = 0
    public var isCurrent: Bool { loadedScope == service.scope && service.isAuthenticated }
    public init(service: any MerchantContentServing, query: MerchantContentQuery) { self.service = service; self.query = query }
    /// Keep navigation source rows while a destination is pushed. In-flight completions and
    /// reviews are invalidated; unresolved write locks and scoped display state are preserved.
    public func suspend() { generation += 1; review = nil; busy = false }
    public func invalidate() { generation += 1; snapshot = nil; review = nil; receipt = nil; issue = nil; serverMessage = nil; loadedScope = nil; busy = false; locked = false }
    public func cancelReview() { review = nil }
    public func load() async {
        guard !busy else { return }
        invalidate(); let operation = generation, captured = service.scope
        busy = true; defer { if operation == generation { busy = false } }
        do {
            let value = try await service.load(query)
            guard !Task.isCancelled, operation == generation, captured == service.scope else { return }
            snapshot = value; loadedScope = captured
            // A pending write is never resolved from a projection that merely resembles success.
            locked = try service.pending().contains { $0.merchantID == value.access.merchantID }
            if locked { issue = "merchant.content.unknown" }
        } catch { if operation == generation && captured == service.scope { loadedScope = captured; setIssue(error) } }
    }
    public func prepare(_ command: MerchantContentCommand) {
        guard isCurrent, !busy, !locked, let snapshot, receipt == nil else { return }
        do { try command.validate(against: snapshot); review = .init(id: UUID(), command: command, baseline: snapshot, scope: service.scope); issue = nil; serverMessage = nil }
        catch { setIssue(error) }
    }
    public func confirm(_ frozen: MerchantContentReview) async {
        guard isCurrent, !busy, !locked, review == frozen, service.scope == frozen.scope else { return }
        review = nil; busy = true; let operation = generation
        defer { if operation == generation { busy = false } }
        do {
            let value = try await service.perform(frozen.command, baseline: frozen.baseline)
            guard !Task.isCancelled, generation == operation, service.scope == frozen.scope else { return }
            receipt = value
            issue = value.station?.outcome == "FAILED" ? "merchant.content.stationFailed" : "merchant.content.acknowledged"
            serverMessage = value.message
        } catch {
            guard generation == operation, service.scope == frozen.scope else { return }
            do { locked = try service.pending().contains { $0.merchantID == frozen.baseline.access.merchantID } }
            catch { locked = true }
            setIssue(error)
        }
    }
    public func reconcile() async {
        guard !busy, isCurrent else { return }; let operation = generation, captured = service.scope
        busy = true; defer { if generation == operation { busy = false } }
        do {
            let records = try service.pending().filter { $0.merchantID == snapshot?.access.merchantID }
            guard !records.isEmpty, records.allSatisfy({ $0.station != nil }) else { throw MerchantContentFailure.locked }
            for record in records { _ = try await service.reconcile(record); guard generation == operation, service.scope == captured else { return } }
            locked = false; issue = "merchant.content.reconciled"; serverMessage = nil
        } catch { if generation == operation && service.scope == captured { setIssue(error) } }
    }
    public func retryStation() async {
        guard !busy, isCurrent, locked else { return }; let operation = generation, captured = service.scope
        busy = true; defer { if generation == operation { busy = false } }
        do {
            let records = try service.pending().filter { $0.merchantID == snapshot?.access.merchantID }
            guard records.count == 1, let record = records.first, record.station != nil else { throw MerchantContentFailure.locked }
            let result = try await service.retryStation(record)
            guard generation == operation, service.scope == captured else { return }
            locked = false; receipt = result; serverMessage = result.message
            issue = result.station?.outcome == "FAILED" ? "merchant.content.stationFailed" : "merchant.content.acknowledged"
        } catch { if generation == operation && service.scope == captured { setIssue(error) } }
    }
    private func setIssue(_ error: Error) {
        serverMessage = nil
        if let failure = error as? MerchantContentFailure {
            issue = failure.key
            if case .rejected(_, let text) = failure { serverMessage = text }
        } else if error as? APIError == .notConfigured { issue = "auth.notConfigured" }
        else if error as? APIError == .unauthorized { issue = "merchant.content.signedOut" }
        else { issue = "merchant.content.loadFailed" }
    }
}
