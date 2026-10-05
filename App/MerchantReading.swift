import Foundation
import Combine

/// Session adapter must use the current credential, reject stale completions and
/// publish a revision on logout/account replacement. Entry intent is never access.
@MainActor
protocol MerchantReading: ObservableObject {
    var isConfigured: Bool { get }
    var isSignedIn: Bool { get }
    var sessionRevision: UInt64 { get }
    func merchantAccess() async throws -> MerchantAccess
    func merchantDashboard(access: MerchantAccess) async throws -> MerchantDashboard
    func merchantTodo(access: MerchantAccess) async throws -> MerchantTodo
    func merchantEvents(access: MerchantAccess) async throws -> [MerchantEvent]
    func merchantOrders(access: MerchantAccess, filter: MerchantOrderFilter) async throws -> [MerchantOrder]
    func merchantProjects(access: MerchantAccess) async throws -> MerchantProjectPage
}

@MainActor
final class MerchantLoadModel<Value>: ObservableObject {
    @Published private(set) var value: Value?
    @Published private(set) var loadedRevision: UInt64?
    @Published private(set) var isLoading = false
    @Published private(set) var errorKey: String?
    private var generation = 0

    func clear() {
        generation += 1; value = nil; loadedRevision = nil; isLoading = false; errorKey = nil
    }

    func load<Reader: MerchantReading>(reader: Reader, discardOldValue: Bool = false,
                                      operation: () async throws -> Value) async {
        generation += 1
        let request = generation, revision = reader.sessionRevision
        if discardOldValue || loadedRevision != revision { value = nil; loadedRevision = nil }
        guard reader.isConfigured else { value = nil; isLoading = false; errorKey = "auth.notConfigured"; return }
        guard reader.isSignedIn else { value = nil; isLoading = false; errorKey = "merchant.signIn"; return }
        isLoading = true; errorKey = nil
        defer { if request == generation { isLoading = false } }
        do {
            let result = try await operation()
            try Task.checkCancellation()
            guard request == generation, revision == reader.sessionRevision, reader.isSignedIn else { return }
            value = result; loadedRevision = revision
        } catch is CancellationError { }
        catch {
            guard request == generation, revision == reader.sessionRevision else { return }
            if error as? MerchantReadError == .accessDenied {
                value = nil; errorKey = "merchant.access.denied"
            } else if error as? APIError == .unauthorized {
                value = nil; errorKey = "auth.expired"
            } else if error as? APIError == .malformedResponse {
                errorKey = "merchant.invalidResponse"
            } else { errorKey = "merchant.loadFailed" }
        }
    }
}
