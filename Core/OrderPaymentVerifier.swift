import Foundation

public enum OrderPaymentVerificationResult: Equatable {
    case observed(OrderPaymentObservation, detail: OrderLifecycleDetail)
    case unknown
    case accessDenied
}

/// Read-only reconciliation after an independently authorized provider return. SDK outcomes
/// are deliberately not inputs. Defaults mirror Flutter: 1.5s interval, 5s request budget,
/// 20s total window. An unknown result never unlocks another payment/cancellation attempt.
@MainActor public final class OrderPaymentVerifier {
    private let read: (Int) async throws -> OrderLifecycleDetail
    private let currentScope: () -> UUID
    private let interval: TimeInterval
    private let requestTimeout: TimeInterval
    private let totalDeadline: TimeInterval
    private var generation: UInt64 = 0
    public init(interval: TimeInterval = 1.5, requestTimeout: TimeInterval = 5, totalDeadline: TimeInterval = 20,
                currentScope: @escaping () -> UUID, read: @escaping (Int) async throws -> OrderLifecycleDetail) {
        self.interval = interval.isFinite && interval > 0 ? min(interval, 60) : 1.5
        self.requestTimeout = requestTimeout.isFinite && requestTimeout > 0 ? min(requestTimeout, 300) : 5
        self.totalDeadline = max(self.requestTimeout, totalDeadline.isFinite && totalDeadline > 0 ? min(totalDeadline, 600) : 20)
        self.currentScope = currentScope; self.read = read
    }
    public func abort() { generation &+= 1 }
    public func verify(registrationID: Int) async -> OrderPaymentVerificationResult {
        guard registrationID > 0, !Task.isCancelled else { return .unknown }
        generation &+= 1
        let stamp = generation, scope = currentScope()
        let started = ProcessInfo.processInfo.systemUptime
        func remaining() -> TimeInterval { totalDeadline - (ProcessInfo.processInfo.systemUptime - started) }
        while !Task.isCancelled && stamp == generation && scope == currentScope() {
            let budget = min(requestTimeout, remaining())
            guard budget > 0 else { return .unknown }
            let result = await OrderPaymentReadRace.run(timeout: budget) { [read] in try await read(registrationID) }
            guard !Task.isCancelled, stamp == generation, scope == currentScope() else { return .unknown }
            switch result {
            case .success(let detail):
                guard detail.id == registrationID else { return .unknown }
                let observed = OrderPaymentObservation(payment: detail.paymentStatus, registration: detail.registrationStatus)
                if [.paid, .registrationAccepted, .failed].contains(observed) { return .observed(observed, detail: detail) }
            case .failure(let error):
                if error as? APIError == .unauthorized || error as? OrderLifecycleFailure == .accessDenied { return .accessDenied }
            case nil: break
            }
            let delay = min(interval, remaining())
            guard delay > 0 else { return .unknown }
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            catch { return .unknown }
        }
        return .unknown
    }
}

/// One continuation winner. A transport that ignores cancellation cannot extend the
/// readback deadline or publish its late value. No network request is retried by this race.
@MainActor private final class OrderPaymentReadRace {
    private var continuation: CheckedContinuation<Result<OrderLifecycleDetail, Error>?, Never>?
    private var operation: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var finished = false
    static func run(timeout: TimeInterval, operation: @escaping () async throws -> OrderLifecycleDetail) async -> Result<OrderLifecycleDetail, Error>? {
        let race = OrderPaymentReadRace()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                race.continuation = continuation
                if Task.isCancelled { race.finish(nil); return }
                race.operation = Task {
                    do { race.finish(.success(try await operation())) }
                    catch { race.finish(.failure(error)) }
                }
                race.deadline = Task {
                    do { try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)); race.finish(nil) }
                    catch { /* The winning read cancelled this timer. */ }
                }
            }
        } onCancel: {
            Task { @MainActor in race.finish(nil) }
        }
    }
    private func finish(_ result: Result<OrderLifecycleDetail, Error>?) {
        guard !finished else { return }
        finished = true
        let callback = continuation; continuation = nil
        operation?.cancel(); deadline?.cancel(); operation = nil; deadline = nil
        callback?.resume(returning: result)
    }
}
