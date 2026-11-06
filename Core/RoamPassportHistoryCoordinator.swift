import Foundation
import Observation

public struct RoamPassportHistoryOwner: Hashable {
    public let readerID: ObjectIdentifier
    public let storageKey: String?
    public let epoch: UInt64?
    public let scope: UUID
    public let configured: Bool
    @MainActor public init(_ reader: any RoamPassportHistoryReading) {
        readerID = ObjectIdentifier(reader); storageKey = reader.identity?.scope.storageKey
        epoch = reader.identity?.epoch; scope = reader.scope; configured = reader.isConfigured
    }
}

/// Independent server totals and a forward-only original cursor. Nothing here writes local history.
@MainActor @Observable public final class RoamPassportHistoryCoordinator {
    public enum Operation: Equatable { case refresh, more, summary }
    public struct Intent {
        fileprivate let owner: RoamPassportHistoryOwner
        fileprivate let generation: UUID
        fileprivate let operation: Operation
        fileprivate let cursor: String?
    }
    public let reader: any RoamPassportHistoryReading
    public let owner: RoamPassportHistoryOwner
    public private(set) var items: [RoamPassportHistoryFact] = []
    public private(set) var summary: RoamPassportServerSummary?
    public private(set) var pageError: Error?
    public private(set) var summaryError: Error?
    public private(set) var loaded = false
    public private(set) var hasMore = false
    public private(set) var busy = false
    public private(set) var retryOperation: Operation = .refresh
    private var nextBefore: String?
    private var active = false
    private var generation = UUID()
    public init(reader: any RoamPassportHistoryReading) { self.reader = reader; owner = .init(reader) }
    public var isCurrent: Bool { owner == RoamPassportHistoryOwner(reader) && owner.storageKey != nil && owner.configured }
    public var isVisible: Bool { active && isCurrent }
    public func activate() { active = true }
    public func suspend() { active = false; generation = UUID(); busy = false; clear() }
    private func clear() { items = []; summary = nil; loaded = false; hasMore = false; nextBefore = nil; pageError = nil; summaryError = nil }
    public func intent(_ operation: Operation) -> Intent {
        .init(owner: owner, generation: generation, operation: operation, cursor: operation == .more ? nextBefore : nil)
    }
    private func accepts(_ ticket: UUID) -> Bool { isVisible && generation == ticket && !Task.isCancelled }
    public func read(_ offered: Intent) async {
        guard offered.owner == owner, accepts(offered.generation), !busy else { return }
        if offered.operation == .more { guard loaded, hasMore, offered.cursor == nextBefore, offered.cursor != nil else { return } }
        generation = UUID(); let ticket = generation; busy = true
        defer { if generation == ticket { busy = false; generation = UUID() } }
        if offered.operation != .more {
            summaryError = nil
            do {
                let value = try await reader.summary()
                guard accepts(ticket) else { return }; summary = value
            } catch {
                guard accepts(ticket), !(error is CancellationError) else { return }
                if CollectionReadAccess(error) != nil { clear(); summaryError = error; pageError = error; retryOperation = .refresh; return }
                summaryError = error
            }
        }
        guard offered.operation != .summary, accepts(ticket) else { return }
        pageError = nil
        do {
            let value = try await reader.page(before: offered.cursor)
            guard accepts(ticket) else { return }
            // Service/route validation is repeated for injected readers and continuation boundaries.
            try value.validate(before: offered.cursor)
            if offered.operation == .more {
                guard Set(items.map(\.sessionID)).isDisjoint(with: value.items.map(\.sessionID)) else { throw APIError.malformedResponse }
                items += value.items
            } else { items = value.items }
            loaded = true; hasMore = value.hasMore; nextBefore = value.nextBefore
        } catch {
            guard accepts(ticket), !(error is CancellationError) else { return }
            if CollectionReadAccess(error) != nil { clear(); retryOperation = .refresh }
            else { retryOperation = offered.operation }
            pageError = error
        }
    }
}

/// Detail always rereads the exact server session. A list card is never a settlement receipt.
@MainActor @Observable public final class RoamPassportRecordCoordinator {
    public struct Intent { fileprivate let generation: UUID }
    public let reader: any RoamPassportHistoryReading
    public let owner: RoamPassportHistoryOwner
    public let sessionID: String
    public private(set) var fact: RoamPassportHistoryFact?
    public private(set) var error: Error?
    public private(set) var busy = false
    private var active = false
    private var generation = UUID()
    private let localReader: (any RoamExperienceReading)?
    private var localOwner: RoamPassportReadOwner?
    private var localRecord: RoamHistoryRecord?
    public init(reader: any RoamPassportHistoryReading, sessionID: String, localReader: (any RoamExperienceReading)? = nil) {
        self.reader = reader; self.sessionID = sessionID; self.localReader = localReader; owner = .init(reader)
    }
    public var isCurrent: Bool { owner == RoamPassportHistoryOwner(reader) && owner.storageKey != nil && owner.configured }
    public var isVisible: Bool { active && isCurrent }
    public var isMissing: Bool { error as? APIError == .httpStatus(404) || error as? APIError == .businessCode(404) }
    public var supplement: RoamHistoryRecord? {
        guard isVisible, let localReader, localOwner == RoamPassportReadOwner(reader: localReader),
              localReader.identity?.scope.storageKey == owner.storageKey, localReader.identity?.epoch == owner.epoch else { return nil }
        return localRecord
    }
    public var track: [RoamHistoryPoint] {
        guard isVisible else { return [] }
        if let supplement, !supplement.track.isEmpty { return supplement.track }
        return fact?.track ?? []
    }
    public func activate() { active = true }
    public func suspend() { active = false; generation = UUID(); busy = false; fact = nil; error = nil; localRecord = nil; localOwner = nil }
    public func intent() -> Intent { .init(generation: generation) }
    private func accepts(_ ticket: UUID) -> Bool { isVisible && generation == ticket && !Task.isCancelled }
    public func read(_ offered: Intent) async {
        guard accepts(offered.generation), !busy, RoamPassportHistoryContract.isSessionID(sessionID) else { return }
        generation = UUID(); let ticket = generation; busy = true; error = nil
        defer { if generation == ticket { busy = false; generation = UUID() } }
        do {
            let value = try await reader.record(sessionID: sessionID)
            guard accepts(ticket) else { return }
            guard value.sessionID == sessionID else { throw APIError.malformedResponse }
            fact = value; localRecord = nil; localOwner = nil
            // Only exact native provenance may supplement this same owner's server projection.
            // This is a local read, never an upload, photo read, share, or new settled record.
            if let localReader, localReader.identity?.scope.storageKey == owner.storageKey,
               localReader.identity?.epoch == owner.epoch {
                let captured = RoamPassportReadOwner(reader: localReader)
                let match = (try? localReader.history())?.first { $0.ts > 0 && $0.serverSessionID.map(String.init) == sessionID }
                if captured == RoamPassportReadOwner(reader: localReader), accepts(ticket) { localOwner = captured; localRecord = match }
            }
        } catch {
            guard accepts(ticket), !(error is CancellationError) else { return }
            // A missing or forbidden record must not keep an old visible server fact.
            if CollectionReadAccess(error) != nil || error as? APIError == .httpStatus(404) || error as? APIError == .businessCode(404) {
                fact = nil; localRecord = nil; localOwner = nil
            }
            self.error = error
        }
    }
}
