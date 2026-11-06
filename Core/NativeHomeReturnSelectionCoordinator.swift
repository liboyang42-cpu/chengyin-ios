import Foundation
import Observation

/// The Account private-home route obtains actual eligible server runs. It never guesses a run ID.
@available(macOS 14.0, *) @MainActor @Observable public final class NativeHomeReturnSelectionCoordinator {
    public enum Phase { case idle, loading, ready, unavailable, blocked, invalidated }
    public private(set) var phase: Phase = .idle
    public private(set) var runs: [NativeHomeReturnRun] = []
    public private(set) var truncated = false
    public private(set) var loadingMore = false
    public private(set) var paginationUnavailable = false
    private var nextBeforeRunId: String?
    public private(set) var selected: NativeHomeReturnCoordinator?
    private let service: any NativeHomeReturnRunServing
    private let journal: any NativeHomeReturnSecureJournaling
    private let owner: PlayExperienceSession
    private let isCurrent: () -> Bool
    private let makeModel: (NativeHomeResourceScope) -> NativeHomeReturnCoordinator
    private var generation = UUID()
    public init(service: any NativeHomeReturnRunServing, journal: any NativeHomeReturnSecureJournaling, owner: PlayExperienceSession,
                isCurrent: @escaping () -> Bool, makeModel: @escaping (NativeHomeResourceScope) -> NativeHomeReturnCoordinator) {
        self.service = service; self.journal = journal; self.owner = owner; self.isCurrent = isCurrent; self.makeModel = makeModel
    }
    public var isAuthorized: Bool { isCurrent() }
    public var canSelect: Bool { phase == .ready && !loadingMore && selected?.hasPendingRestore != true && selected?.isBusy != true && isCurrent() }
    public func invalidate() {
        generation = UUID(); selected?.invalidate(); selected = nil; runs = []; truncated = false; nextBeforeRunId = nil; loadingMore = false; phase = .invalidated
    }
    private func gate() -> Bool {
        guard phase != .invalidated else { return false }
        guard isCurrent() else { invalidate(); return false }; return true
    }
    public func load() async {
        guard gate(), phase != .loading, !loadingMore, selected?.isBusy != true else { return }
        selected?.cancelVerification()
        let ticket = generation; phase = .loading; runs = []; truncated = false; nextBeforeRunId = nil; paginationUnavailable = false
        do {
            guard journal.scope == PrivateHomeJournalScope(owner: owner) else { throw NativeHomeReturnFailure.storageUnavailable }
            if let existing = selected, existing.hasPendingRestore {
                // Keep the original UNKNOWN identity. Its load checks that the durable slot
                // still matches; rebuilding here would let a replacement record adopt it.
                await existing.load()
                guard ticket == generation, gate() else { return }
                phase = .ready; return
            }
            let pending = try await journal.read()
            guard ticket == generation, gate() else { return }
            try pending?.validateNative()
            if let pending {
                // Recovery always uses the original scope, even if that run is no longer eligible.
                selected?.invalidate(); selected = makeModel(pending.scope)
                await selected?.load()
                guard ticket == generation, gate() else { return }
                phase = .ready; return
            }
            guard selected?.hasPendingRestore != true else { throw NativeHomeReturnFailure.storageUnavailable }
        } catch {
            guard ticket == generation, gate() else { return }; phase = .blocked; return
        }
        selected?.invalidate(); selected = nil
        do {
            let value = try await service.runs(beforeRunId: nil)
            guard ticket == generation, gate() else { return }; try value.validate()
            runs = value.runs; truncated = value.truncated; nextBeforeRunId = value.nextBeforeRunId; phase = .ready
        } catch {
            guard ticket == generation, gate() else { return }; phase = .unavailable
        }
    }
    public func loadMore() async {
        guard gate(), canSelect, let cursor = nextBeforeRunId, let boundary = Int64(cursor) else { return }
        let ticket = generation; loadingMore = true; paginationUnavailable = false
        defer { if ticket == generation { loadingMore = false } }
        do {
            let value = try await service.runs(beforeRunId: cursor)
            guard ticket == generation, gate() else { return }; try value.validate()
            guard value.runs.allSatisfy({ (Int64($0.runId) ?? Int64.max) < boundary }),
                  value.nextBeforeRunId.flatMap(Int64.init).map({ $0 < boundary }) ?? true,
                  Set(runs.map(\.runId)).isDisjoint(with: Set(value.runs.map(\.runId))) else { throw NativeHomeReturnFailure.invalid }
            runs += value.runs; truncated = value.truncated; nextBeforeRunId = value.nextBeforeRunId
        } catch {
            guard ticket == generation, gate() else { return }
            paginationUnavailable = true
            // Keep the proven partial shelf and original cursor for an explicit retry.
        }
    }
    public func select(_ run: NativeHomeReturnRun) async {
        guard gate(), canSelect, runs.contains(run) else { return }
        let ticket = generation
        selected?.invalidate()
        let model = makeModel(run.scope); selected = model
        await model.load() // independent authoritative account read, not a shelf balance
        guard ticket == generation, gate() else { return }
    }
    public func cancelVerification() { selected?.cancelVerification() }
}
