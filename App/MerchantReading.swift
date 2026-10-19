import Foundation
import Combine
import SwiftUI

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


/// Isolated two-read adapter. It cannot borrow AppSession's broader merchant services.
@MainActor final class MerchantProjectBrowseReader: MerchantReading {
    let id = UUID()
    let sessionRevision: UInt64
    private let service: MerchantService
    private let token: String
    private let current: () -> Bool
    private let unauthorized: () -> Void
    private var access: MerchantAccess?
    private var accessGeneration: UInt64 = 0
    var isConfigured: Bool { current() }
    var isSignedIn: Bool { current() }
    init(configuration: APIConfiguration, transport: any HTTPTransport, token: String, revision: UInt64,
         current: @escaping () -> Bool, unauthorized: @escaping () -> Void) {
        service = MerchantService(configuration: configuration, transport: CookieFreeTransport(underlying: transport))
        self.token = token; sessionRevision = revision; self.current = current; self.unauthorized = unauthorized
    }
    private struct CookieFreeTransport: HTTPTransport {
        let underlying: any HTTPTransport
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            var exact = request; exact.httpShouldHandleCookies = false
            return try await underlying.send(exact)
        }
    }
    private func read<T>(accepts: () -> Bool, _ operation: () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        guard current(), accepts() else { throw APIError.notConfigured }
        do {
            let result = try await operation()
            try Task.checkCancellation(); guard current(), accepts() else { throw CancellationError() }
            return result
        } catch {
            guard !Task.isCancelled, current(), accepts() else { throw CancellationError() }
            if error as? APIError == .unauthorized { access = nil; unauthorized() }
            if error as? MerchantReadError == .accessDenied { access = nil }
            throw error
        }
    }
    func merchantAccess() async throws -> MerchantAccess {
        accessGeneration &+= 1; let generation = accessGeneration; access = nil
        let result = try await read(accepts: { generation == accessGeneration }) { try await service.access(token: token) }
        guard generation == accessGeneration else { throw CancellationError() }
        access = result; return result
    }
    func merchantProjects(access supplied: MerchantAccess) async throws -> MerchantProjectPage {
        guard access == supplied, supplied.allows(.projects), (supplied.merchantID ?? 0) > 0 else { throw MerchantReadError.accessDenied }
        let generation = accessGeneration
        let result = try await read(accepts: { generation == accessGeneration && access == supplied }) { try await service.projects(access: supplied, token: token) }
        guard generation == accessGeneration, access == supplied else { throw CancellationError() }
        return result
    }
    func merchantDashboard(access: MerchantAccess) async throws -> MerchantDashboard { throw APIError.notConfigured }
    func merchantTodo(access: MerchantAccess) async throws -> MerchantTodo { throw APIError.notConfigured }
    func merchantEvents(access: MerchantAccess) async throws -> [MerchantEvent] { throw APIError.notConfigured }
    func merchantOrders(access: MerchantAccess, filter: MerchantOrderFilter) async throws -> [MerchantOrder] { throw APIError.notConfigured }
}

@MainActor struct SessionMerchantProjectBrowseView: View {
    @ObservedObject var session: AppSession
    var body: some View {
        if let reader = session.merchantProjectBrowseReader {
            MerchantProjectsView(reader: reader, showsRecentEvents: false).id(reader.id)
        } else {
            ContentUnavailableView("merchant.projects", systemImage: "network.slash", description: Text("auth.notConfigured"))
        }
    }
}

/// Isolated aggregate reads; other MerchantReading methods remain unavailable.
@MainActor final class MerchantOverviewReader: MerchantReading {
    let id = UUID()
    let sessionRevision: UInt64
    private let service: MerchantService
    private let token: String
    private let current: () -> Bool
    private let unauthorized: () -> Void
    private var proof: MerchantAccess?
    private var generation: UInt64 = 0
    var isConfigured: Bool { current() }
    var isSignedIn: Bool { current() }
    init(configuration: APIConfiguration, transport: any HTTPTransport, token: String, revision: UInt64,
         current: @escaping () -> Bool, unauthorized: @escaping () -> Void) {
        service = MerchantService(configuration: configuration, transport: CookieFreeTransport(underlying: transport))
        self.token = token; sessionRevision = revision; self.current = current; self.unauthorized = unauthorized
    }
    private struct CookieFreeTransport: HTTPTransport {
        let underlying: any HTTPTransport
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            var exact = request; exact.httpShouldHandleCookies = false
            return try await underlying.send(exact)
        }
    }
    private func read<T>(accepts: () -> Bool, _ action: () async throws -> T) async throws -> T {
        try Task.checkCancellation(); guard current(), accepts() else { throw APIError.notConfigured }
        do {
            let result = try await action()
            try Task.checkCancellation(); guard current(), accepts() else { throw CancellationError() }
            return result
        } catch {
            guard !Task.isCancelled, current(), accepts() else { throw CancellationError() }
            if error as? APIError == .unauthorized { proof = nil; unauthorized() }
            if error as? MerchantReadError == .accessDenied { proof = nil }
            throw error
        }
    }
    func merchantAccess() async throws -> MerchantAccess {
        generation &+= 1; let captured = generation; proof = nil
        let result = try await read(accepts: { generation == captured }) { try await service.access(token: token) }
        guard !Task.isCancelled, current(), generation == captured else { throw CancellationError() }
        proof = result; return result
    }
    private func aggregate<T>(_ access: MerchantAccess, _ action: () async throws -> T) async throws -> T {
        guard proof == access, access.isOwner, access.allows(.basicRead) else { throw MerchantReadError.accessDenied }
        let captured = generation
        let result = try await read(accepts: { generation == captured && proof == access }, action)
        guard !Task.isCancelled, current(), generation == captured, proof == access else { throw CancellationError() }
        return result
    }
    func merchantDashboard(access: MerchantAccess) async throws -> MerchantDashboard {
        guard access.canReadDashboard else { throw MerchantReadError.accessDenied }
        return try await aggregate(access) { try await service.dashboard(access: access, token: token) }
    }
    func merchantTodo(access: MerchantAccess) async throws -> MerchantTodo {
        try await aggregate(access) { try await service.todo(access: access, token: token) }
    }
    func merchantEvents(access: MerchantAccess) async throws -> [MerchantEvent] {
        try await aggregate(access) { try await service.events(access: access, token: token) }
    }
    func merchantOrders(access: MerchantAccess, filter: MerchantOrderFilter) async throws -> [MerchantOrder] { throw APIError.notConfigured }
    func merchantProjects(access: MerchantAccess) async throws -> MerchantProjectPage { throw APIError.notConfigured }
}
@MainActor struct SessionMerchantOverviewView: View {
    @ObservedObject var session: AppSession
    var body: some View {
        if let reader = session.merchantOverviewReader {
            // No operational destinations, writers, image hosts, or record links.
            MerchantHomeView(reader: reader, showsRecordLinks: false).id(reader.id)
        } else {
            ContentUnavailableView("merchant.title", systemImage: "network.slash", description: Text("auth.notConfigured"))
        }
    }
}
