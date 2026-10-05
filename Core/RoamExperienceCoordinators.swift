import Foundation

public enum RoamRecoveryPhase: Equatable {
    case idle, loading, active, finished, incomplete, notFound, failed
}
@MainActor public final class RoamRecoveryCoordinator {
    public private(set) var phase: RoamRecoveryPhase = .idle
    public private(set) var fact: RoamSessionFact?
    public private(set) var error: Error?
    private let reader: any RoamExperienceReading
    private var generation = 0
    public init(reader: any RoamExperienceReading) { self.reader = reader }
    public func reset() { generation += 1; phase = .idle; fact = nil; error = nil }
    public func recover(_ query: RoamRecoveryQuery) async {
        generation += 1; let ticket = generation; let identity = reader.identity
        phase = .loading; fact = nil; error = nil
        do {
            try query.validate()
            guard identity != nil else { throw APIError.unauthorized }
            let value = try await reader.sessionFact(query)
            guard !Task.isCancelled, ticket == generation, reader.identity == identity else { return }
            guard query.matches(value) else { throw APIError.malformedResponse }
            fact = value
            switch value.state {
            case .active: phase = .active
            case .notFound: phase = .notFound
            case .finished: phase = value.hasCompleteSettlement ? .finished : .incomplete
            }
        } catch {
            guard !Task.isCancelled, ticket == generation, reader.identity == identity else { return }
            self.error = error; phase = .failed
        }
    }
}
/// Pagination advances on successful responses only, deduplicates by stamp identity, and keeps
/// prior rows on retryable page errors. Refresh and account changes invalidate all older completions.
@MainActor public final class RoamAlbumPager {
    public private(set) var stamps: [RoamAlbumStamp] = []
    public private(set) var hasMore = true
    public private(set) var loading = false
    public private(set) var error: Error?
    public private(set) var loaded = false
    private let reader: any RoamExperienceReading
    private var identity: RoamExperienceIdentity?
    private var nextPage = 1
    private var generation = 0
    private let pageSize: Int
    public init(reader: any RoamExperienceReading, pageSize: Int = 20) { self.reader = reader; self.pageSize = pageSize }
    public func reset() {
        generation += 1; identity = reader.identity; nextPage = 1
        stamps = []; hasMore = true; loading = false; error = nil; loaded = false
    }
    /// Preserve rows when a detail is pushed; invalidate only unfinished work.
    public func cancelPending() { generation += 1; loading = false }
    public func loadNext() async {
        if identity != reader.identity { reset() }
        guard !loading, hasMore else { return }
        let ticket = generation, snapshot = reader.identity, page = nextPage
        loading = true; error = nil
        defer { if generation == ticket { loading = false } }
        do {
            guard snapshot != nil else { throw APIError.unauthorized }
            let result = try await reader.album(page: page, pageSize: pageSize)
            guard !Task.isCancelled, generation == ticket, reader.identity == snapshot else { return }
            guard result.pageNum == page, result.pageSize == pageSize else { throw APIError.malformedResponse }
            for stamp in result.list {
                stamps.removeAll { $0.id == stamp.id }
                if stamp.isVisible { stamps.append(stamp) }
            }
            hasMore = result.hasMore; nextPage += 1; loaded = true
        } catch {
            guard !Task.isCancelled, generation == ticket, reader.identity == snapshot else { return }
            self.error = error
        }
    }
}
/// Device integration boundary only. There is no concrete GPS implementation or permission prompt.
/// Search-area coordinates are deliberately a different type from a device fix.
public struct RoamDeviceFix: Equatable {
    public enum Datum: String { case wgs84, gcj02 }
    public let coordinate: RoamCoordinate
    public let accuracyMeters: Double
    public let measuredAt: Date
    public let datum: Datum
    public init(coordinate: RoamCoordinate, accuracyMeters: Double, measuredAt: Date, datum: Datum) throws {
        guard accuracyMeters.isFinite, accuracyMeters >= 0 else { throw APIError.invalidRequest }
        self.coordinate = coordinate; self.accuracyMeters = accuracyMeters; self.measuredAt = measuredAt; self.datum = datum
    }
}
@MainActor public protocol RoamDeviceLocationProviding: AnyObject {
    func currentFix() async throws -> RoamDeviceFix
    func stop()
}
@MainActor public final class RoamLiveCoordinator {
    public enum Phase: Equatable { case ready, unavailable }
    public private(set) var phase: Phase = .ready
    public init() {}
    /// Purpose consent is necessary but insufficient; no sample or manual coordinate bypass exists.
    public func start(purposeAccepted: Bool) throws {
        guard purposeAccepted else { throw APIError.invalidRequest }
        phase = .unavailable
        throw RoamExperienceFailure.capabilityUnavailable
    }
}
/// Ephemeral draft only: never creates a stamp, assigns a serial or implies an exchange succeeded.
public struct RoamCityStampDraft: Equatable {
    public var caption = ""
    public init() {}
    public var remaining: Int { 30 - caption.utf16.count }
    public var canReview: Bool { RoamExperienceMath.validCaption(caption) }
}

/// Owner-scoped exploration memory only; never presence, visit evidence or territory ownership.
/// Retry the same cursor on failure; overlapping pages merge as a set. Refresh starts at zero
/// so another device's server-confirmed tiles can be recovered without a local journal.
@MainActor public final class RoamTileMemoryPager {
    public private(set) var tiles: Set<String> = []
    public private(set) var hasMore = true
    public private(set) var loading = false
    public private(set) var loaded = false
    public private(set) var error: Error?
    private let reader: any RoamExperienceReading
    private var identity: RoamExperienceIdentity?
    private var cursor = 0
    private var generation = 0
    private let limit = 1000
    public init(reader: any RoamExperienceReading) { self.reader = reader; identity = reader.identity }
    public func reset() {
        generation += 1; identity = reader.identity; cursor = 0
        tiles = []; hasMore = true; loading = false; loaded = false; error = nil
    }
    public func cancelPending() { generation += 1; loading = false }
    public func loadNext() async {
        if identity != reader.identity { reset() }
        guard !loading, hasMore else { return }
        let ticket = generation, snapshot = identity, afterID = cursor
        loading = true; error = nil
        defer { if generation == ticket { loading = false } }
        do {
            guard snapshot != nil else { throw APIError.unauthorized }
            guard reader.isConfigured else { throw APIError.notConfigured }
            let page = try await reader.tilePage(afterID: afterID, limit: limit)
            guard generation == ticket else { return }
            guard reader.identity == snapshot else { reset(); return }
            guard !Task.isCancelled else { return }
            guard page.tiles.count <= limit, page.nextAfterId >= afterID,
                  !page.hasMore || page.nextAfterId > afterID else { throw APIError.malformedResponse }
            tiles.formUnion(page.tiles); cursor = page.nextAfterId; hasMore = page.hasMore; loaded = true
        } catch {
            guard generation == ticket else { return }
            guard reader.identity == snapshot else { reset(); return }
            guard !Task.isCancelled else { return }
            self.error = error
        }
    }
}
