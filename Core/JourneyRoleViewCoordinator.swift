import Foundation
import Observation

/// Read-only and memory-only. Account/scope/node identity and request generations
/// fence delayed replies; leaving a node clears content before the next read.
@MainActor @Observable public final class JourneyRoleViewCoordinator {
    public enum Status: Equatable { case idle, loading, absent, ready, unavailable, closed }
    public let scope: PlaySessionScope; public let topicID: Int; public let nodeID: Int
    public private(set) var status: Status = .idle
    public private(set) var projection: JourneyRoleProjection?
    private let service: JourneyContentService
    private let currentSession: () -> PlayExperienceSession?
    private let unauthorized: (PlayExperienceSession) -> Void
    private var identity: PlayExperienceSession?
    private var generation: UInt64 = 0
    private var loaded = false
    private var expectedRunID: Int?
    private var minimumStateVersion: Int?
    public init(scope: PlaySessionScope, topicID: Int, nodeID: Int, service: JourneyContentService,
                currentSession: @escaping () -> PlayExperienceSession?, onUnauthorized: @escaping (PlayExperienceSession) -> Void = { _ in }) {
        self.scope = scope; self.topicID = topicID; self.nodeID = nodeID; self.service = service
        self.currentSession = currentSession; unauthorized = onUnauthorized; identity = currentSession()
    }
    public func synchronize() {
        guard identity != currentSession() else { return }
        close(); identity = currentSession()
    }
    public func close() { generation &+= 1; projection = nil; status = .idle; loaded = false }
    public func dismiss() { close(); status = .closed }
    public func load(expectedRunID: Int? = nil, minimumStateVersion: Int? = nil) async {
        synchronize()
        if self.expectedRunID != expectedRunID || self.minimumStateVersion != minimumStateVersion {
            close(); self.expectedRunID = expectedRunID; self.minimumStateVersion = minimumStateVersion
        }
        guard expectedRunID.map({ $0 > 0 }) ?? true, minimumStateVersion.map({ $0 >= 0 }) ?? true else { projection = nil; status = .unavailable; return }
        guard !loaded, status != .loading, service.readsEnabled, scope.isValid, topicID > 0, nodeID > 0,
              let session = identity else { return }
        if case .topic(let id) = scope, id != topicID { return }
        projection = nil; status = .loading; loaded = true
        let stamp = generation
        do {
            let result = try await service.roleView(scope: scope, topicID: topicID, nodeID: nodeID, token: session.token)
            guard generation == stamp, currentSession() == session else { synchronize(); return }
            if let result {
                guard expectedRunID.map({ $0 == result.runID }) ?? true,
                      minimumStateVersion.map({ result.stateVersion >= $0 }) ?? true else { projection = nil; status = .unavailable; return }
            }
            projection = result; status = result == nil ? .absent : .ready
        } catch {
            guard generation == stamp, currentSession() == session else { synchronize(); return }
            projection = nil
            if (error as? PlayExperienceError) == .unauthorized { unauthorized(session); synchronize(); status = .unavailable }
            else if (error as? PlayExperienceError) == .disabled { status = .absent }
            else { status = .unavailable }
        }
    }
    public func refresh() async {
        guard status != .loading else { return }
        let run = expectedRunID, version = minimumStateVersion
        close(); await load(expectedRunID: run, minimumStateVersion: version)
    }
}
