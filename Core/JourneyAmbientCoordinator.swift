import Foundation
import Observation

public struct JourneyAmbientScope: Hashable {
    public let accountID: Int; public let region: String; public let session: PlaySessionScope
    public init(accountID: Int, region: String, session: PlaySessionScope) {
        self.accountID = accountID; self.region = region; self.session = session
    }
}
/// Storage is injectable; production integration may wrap approved secure local storage.
/// Keys include account + operational region + activity/topic discriminator, never UI locale.
@MainActor public protocol JourneyEggSeenStorage {
    func seen(in scope: JourneyAmbientScope) throws -> Set<Int>
    func save(_ ids: Set<Int>, in scope: JourneyAmbientScope) throws
}
@MainActor public final class JourneyMemoryEggSeenStorage: JourneyEggSeenStorage {
    private var records: [JourneyAmbientScope: Set<Int>] = [:]
    public init() {}
    public func seen(in scope: JourneyAmbientScope) throws -> Set<Int> { records[scope] ?? [] }
    public func save(_ ids: Set<Int>, in scope: JourneyAmbientScope) throws { records[scope] = ids }
}
/// A location owner supplies only already-authorized positions. This package requests
/// no GPS permission, starts no tracking, and does not transmit coordinates.
public struct JourneyAmbientPosition {
    public let latitude: Double; public let longitude: Double
    public init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
    var valid: Bool { latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180 }
    func distance(to egg: JourneyEgg) -> Double {
        let radians = Double.pi / 180
        let dlat = (egg.latitude - latitude) * radians, dlon = (egg.longitude - longitude) * radians
        let a = pow(sin(dlat / 2), 2) + cos(latitude * radians) * cos(egg.latitude * radians) * pow(sin(dlon / 2), 2)
        return 6_371_000 * 2 * atan2(sqrt(min(1, max(0, a))), sqrt(max(0, 1 - a)))
    }
}
@MainActor public protocol JourneyAmbientLocationSource {
    /// This source must be supplied by an already-consented location owner.
    func positions() -> AsyncThrowingStream<JourneyAmbientPosition, Error>
}
@MainActor @Observable public final class JourneyAmbientCoordinator {
    public let scope: PlaySessionScope
    public private(set) var line: String?
    public private(set) var eggBubble: JourneyEgg?
    public private(set) var collected: Set<Int> = []
    public private(set) var unknownCollections: Set<Int> = []
    private let service: JourneyContentService
    private let store: any JourneyEggSeenStorage
    private let currentSession: () -> PlayExperienceSession?
    private var identity: PlayExperienceSession?
    private var eggs: [JourneyEgg] = []
    private var topicID: Int?
    private var seen: Set<Int> = []
    private var lastEggAt: Date?
    private var bubbleUntil: Date?
    private var lineUntil: Date?
    private var hits: Set<Int> = []
    private var navigationNode: Int?
    private var generation: UInt64 = 0
    private var lineGeneration: UInt64 = 0
    private var loaded = false
    public init(scope: PlaySessionScope, service: JourneyContentService, store: any JourneyEggSeenStorage,
                currentSession: @escaping () -> PlayExperienceSession?) {
        self.scope = scope; self.service = service; self.store = store; self.currentSession = currentSession
        identity = currentSession()
    }
    private var storageScope: JourneyAmbientScope? {
        identity.map { JourneyAmbientScope(accountID: $0.accountID, region: $0.namespace, session: scope) }
    }
    public func synchronize() {
        guard identity != currentSession() else { return }
        generation &+= 1; lineGeneration &+= 1; identity = currentSession(); seen = []; loaded = false
        line = nil; eggBubble = nil; lastEggAt = nil; bubbleUntil = nil; lineUntil = nil
        collected = []; unknownCollections = []; hits = []; navigationNode = nil; eggs = []; topicID = nil
    }
    public func project(eggs: [JourneyEgg], topicID: Int?) {
        synchronize(); self.eggs = eggs; self.topicID = topicID
        if case .topic(let id) = scope, topicID != id { self.eggs = []; return }
        guard !loaded, let key = storageScope else { return }
        do { seen = try store.seen(in: key); loaded = true } catch { self.eggs = [] }
    }
    public func tick(now: Date) {
        synchronize()
        if let end = bubbleUntil, now >= end { eggBubble = nil; bubbleUntil = nil }
        if let end = lineUntil, now >= end { line = nil; lineUntil = nil }
    }
    public func track(source: any JourneyAmbientLocationSource) async {
        synchronize()
        guard let session = identity else { return }
        let stamp = generation
        do {
            for try await position in source.positions() {
                guard !Task.isCancelled, currentSession() == session, generation == stamp else { synchronize(); return }
                await accept(position: position, now: Date())
            }
        } catch { /* Location denial/unavailability never blocks the main task. */ }
    }
    public func accept(position: JourneyAmbientPosition, now: Date) async {
        synchronize(); tick(now: now)
        guard position.valid, loaded, let session = identity, let key = storageScope,
              lastEggAt.map({ now.timeIntervalSince($0) >= 180 }) ?? true,
              let egg = eggs.first(where: { !seen.contains($0.id) && position.distance(to: $0) <= $0.radius }) else { return }
        seen.insert(egg.id); lastEggAt = now; eggBubble = egg; bubbleUntil = now.addingTimeInterval(6)
        try? store.save(seen, in: key)
        // Display/seen does not imply server collection. No collection without capability.
        guard service.collectEnabled else { return }
        let stamp = generation
        do {
            try await service.collect(topicID: topicID, egg: egg, token: session.token)
            guard currentSession() == session, generation == stamp else { synchronize(); return }
            collected.insert(egg.id)
        } catch {
            guard currentSession() == session, generation == stamp else { synchronize(); return }
            unknownCollections.insert(egg.id) // No blind retry or invented reward.
        }
    }
    public func navigationProgress(nodeID: Int, fraction: Double, now: Date) async {
        synchronize()
        guard nodeID > 0, fraction.isFinite, (0...1).contains(fraction), let session = identity else { return }
        if navigationNode != nodeID { navigationNode = nodeID; hits = []; line = nil; lineGeneration &+= 1 }
        let milestone: Int
        if fraction >= 0.9 && !hits.contains(90) { milestone = 90 }
        else if fraction >= 0.5 && !hits.contains(50) { milestone = 50 }
        else { return }
        hits.insert(milestone); lineGeneration &+= 1
        let stamp = generation, request = lineGeneration
        do {
            let text = try await service.companion(scope: scope, token: session.token)
            guard currentSession() == session, generation == stamp, lineGeneration == request else { synchronize(); return }
            if let text { line = text; lineUntil = now.addingTimeInterval(3.5) }
        } catch { /* Ambient failure never interrupts navigation. */ }
    }
    public func dismissBubble() { eggBubble = nil; line = nil }
}

@MainActor public final class JourneyPersistentEggSeenStorage: JourneyEggSeenStorage {
    private let read: (String) throws -> Data?
    private let write: (Data, String) throws -> Void
    public init(read: @escaping (String) throws -> Data?, write: @escaping (Data, String) throws -> Void) {
        self.read = read; self.write = write
    }
    private func key(_ scope: JourneyAmbientScope) -> String {
        let kind = scope.session.fields.keys.sorted().joined()
        let owner = "\(scope.region.utf8.count):\(scope.region):\(scope.accountID):\(kind):\(scope.session.id)"
        return "journey-eggs.v1." + Data(owner.utf8).base64EncodedString()
    }
    public func seen(in scope: JourneyAmbientScope) throws -> Set<Int> {
        guard let data = try read(key(scope)) else { return [] }
        return Set(try JSONDecoder().decode([Int].self, from: data).filter { $0 > 0 })
    }
    public func save(_ ids: Set<Int>, in scope: JourneyAmbientScope) throws {
        try write(JSONEncoder().encode(ids.filter { $0 > 0 }.sorted()), key(scope))
    }
}
