import Foundation

/// Server-owned ordering and partitioning. Filtering never sorts or invents client presence.
@MainActor public final class NativeFriendDirectoryFlow {
    public enum Phase: Equatable { case closed, loading, ready, failed }
    private var savedFilter = NativeFriendDirectoryFilter()
    private var savedPhase: Phase = .closed
    private var savedItems: [NativeFriendItem] = []
    private var savedGroups: [NativeFriendMetadataGroup] = []
    private var savedCounts: [String: Int] = [:]
    private var savedCursor: String?
    private var savedRevision: String?
    // Reads fail closed immediately, including between a grant withdrawal and the local observer tick.
    public var isCurrent: Bool { !authorityRetired && service?.isCurrent == true }
    public var filter: NativeFriendDirectoryFilter { isCurrent ? savedFilter : .init() }
    public var phase: Phase { isCurrent ? savedPhase : .closed }
    public var items: [NativeFriendItem] { isCurrent ? savedItems : [] }
    public var groups: [NativeFriendMetadataGroup] { isCurrent ? savedGroups : [] }
    public var counts: [String: Int] { isCurrent ? savedCounts : [:] }
    public var nextCursor: String? { isCurrent ? savedCursor : nil }
    public var revision: String? { isCurrent ? savedRevision : nil }
    public private(set) var issue: String?
    public private(set) var busy = false
    public private(set) var paginationFailed = false
    public var onChange: (() -> Void)?
    private let service: (any NativeFriendDirectoryServing)?
    private var generation: UInt64 = 0
    private var readTask: Task<NativeFriendDirectoryPage, Error>?
    private var authorityRetired = false
    private var authorityTask: Task<Void, Never>?
    public init(service: (any NativeFriendDirectoryServing)?) {
        self.service = service
        // Only inspects captured local account/context/approval/expiry; never polls a server.
        // It remains active under a child destination so silent revocation also dismisses that child.
        authorityTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                guard let self, self.validateAuthority() else { return }
            }
        }
    }
    deinit { authorityTask?.cancel(); readTask?.cancel() }
    public func makeDetail(peerID: Int64) -> NativeFriendDirectoryDetailFlow { .init(peerID: peerID, service: isCurrent ? service : nil) }
    private func clear() { savedItems = []; savedCounts = [:]; savedCursor = nil; savedRevision = nil }
    private func changed() { onChange?() }
    @discardableResult public func validateAuthority() -> Bool {
        guard isCurrent else {
            if !authorityRetired { authorityRetired = true; savedFilter = .init(); invalidate() }
            return false
        }
        return true
    }
    public func invalidate() {
        readTask?.cancel(); readTask = nil; paginationFailed = false
        generation &+= 1; clear(); savedGroups = []; busy = false; savedPhase = .closed; issue = nil; changed()
    }
    public func select(_ value: NativeFriendDirectoryFilter) async {
        guard validateAuthority() else { return }; savedFilter = value; await load()
    }
    public func load() async {
        guard validateAuthority(), let service else { return }
        readTask?.cancel(); paginationFailed = false
        generation &+= 1; let stamp = generation; let selected = filter
        clear(); savedGroups = []; issue = nil; busy = true; savedPhase = .loading; changed()
        do {
            let work = Task { try await service.page(filter: selected, cursor: nil) }; readTask = work
            let page = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            guard stamp == generation, isCurrent, !Task.isCancelled else { finish(stamp); return }
            guard page.viewerID == service.viewerID, page.section == selected.section, page.groupID == selected.groupID,
                  page.starredOnly == selected.starredOnly else { throw NativeFriendFailure.invalid }
            savedItems = page.items; savedGroups = page.groups.list; savedCounts = page.counts; savedCursor = page.nextCursor; savedRevision = page.revision
            savedPhase = .ready
        } catch NativeFriendDirectoryFailure.missingGroup {
            guard stamp == generation, isCurrent, selected.groupID != nil else { if stamp == generation { savedPhase = .failed; issue = "friendDirectory.loadFailure" }; finish(stamp); return }
            // Deleted group retires only that filter, then re-reads authority for the same section/star choice.
            savedFilter.groupID = nil; await load(); if phase == .ready { issue = "friendDirectory.groupGone"; changed() }; return
        } catch NativeFriendDirectoryFailure.readUnavailable {
            if stamp == generation { clear(); savedGroups = []; savedPhase = .failed; issue = "friendDirectory.readUnavailable" }
        } catch { if stamp == generation { clear(); savedPhase = .failed; issue = "friendDirectory.loadFailure" } }
        finish(stamp)
    }
    public func loadMore() async {
        guard validateAuthority() else { return }
        guard !busy, phase == .ready, let cursor = nextCursor, let revision, let service else { return }
        let stamp = generation; let selected = filter; busy = true; paginationFailed = false; issue = nil; changed()
        do {
            let work = Task { try await service.page(filter: selected, cursor: cursor) }; readTask = work
            let page = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            guard stamp == generation, isCurrent, !Task.isCancelled else { finish(stamp); return }
            guard page.viewerID == service.viewerID, page.section == selected.section, page.groupID == selected.groupID,
                  page.starredOnly == selected.starredOnly, page.revision == revision,
                  page.groups.list == savedGroups, page.counts == savedCounts,
                  items.count + page.items.count <= page.total,
                  page.hasMore || items.count + page.items.count == page.total,
                  Set(items.map(\.peerID)).isDisjoint(with: page.items.map(\.peerID)), page.nextCursor != cursor else { throw NativeFriendDirectoryFailure.changed }
            savedItems += page.items; savedCounts = page.counts; savedCursor = page.nextCursor
        } catch NativeFriendDirectoryFailure.changed {
            if stamp == generation { clear(); savedPhase = .failed; issue = "friendDirectory.changed" }
        } catch NativeFriendDirectoryFailure.missingGroup {
            if stamp == generation { savedFilter.groupID = nil; await load(); if phase == .ready { issue = "friendDirectory.groupGone"; changed() }; return }
        } catch NativeFriendDirectoryFailure.readUnavailable {
            if stamp == generation { clear(); savedGroups = []; savedPhase = .failed; issue = "friendDirectory.readUnavailable" }
        } catch { if stamp == generation { paginationFailed = true; issue = "friendDirectory.pageFailure" } }
        finish(stamp)
    }
    public func retry() async {
        if paginationFailed { await loadMore() } else { await load() }
    }
    private func finish(_ stamp: UInt64) {
        guard validateAuthority(), stamp == generation else { return }
        readTask = nil; busy = false; changed()
    }
}

/// Detail re-reads current friendship at every re-entry; stale list rows never grant edit/chat access.
@MainActor public final class NativeFriendDirectoryDetailFlow {
    public let peerID: Int64
    private var savedDetail: NativeFriendDirectoryDetail?
    public var isCurrent: Bool { !authorityRetired && service?.isCurrent == true }
    public var detail: NativeFriendDirectoryDetail? { isCurrent ? savedDetail : nil }
    public private(set) var issue: String?
    public private(set) var busy = false
    public var onChange: (() -> Void)?
    private let service: (any NativeFriendDirectoryServing)?
    private var generation: UInt64 = 0
    private var readTask: Task<NativeFriendDirectoryDetail, Error>?
    private var authorityRetired = false
    private var authorityTask: Task<Void, Never>?
    public init(peerID: Int64, service: (any NativeFriendDirectoryServing)?) {
        self.peerID = peerID; self.service = service
        authorityTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                guard let self, self.validateAuthority() else { return }
            }
        }
    }
    deinit { authorityTask?.cancel(); readTask?.cancel() }
    public var canOpen: Bool { !busy && isCurrent && detail != nil }
    @discardableResult public func validateAuthority() -> Bool {
        guard isCurrent else {
            if !authorityRetired { authorityRetired = true; invalidate() }
            return false
        }
        return true
    }
    public func invalidate() { readTask?.cancel(); readTask = nil; generation &+= 1; savedDetail = nil; busy = false; issue = nil; onChange?() }
    public func load() async { _ = await readDetail() }
    private func readDetail() async -> NativeFriendDirectoryDetail? {
        guard validateAuthority(), let service else { return nil }
        readTask?.cancel()
        generation &+= 1; let stamp = generation; savedDetail = nil; issue = nil
        busy = true; onChange?()
        do {
            let work = Task { try await service.detail(peerID: peerID) }; readTask = work
            let value = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            guard generation == stamp, isCurrent, !Task.isCancelled else { finish(stamp); return nil }
            guard value.viewerID == service.viewerID, value.item.peerID == peerID, value.item.state == .friend else { throw NativeFriendFailure.invalid }
            savedDetail = value
            finish(stamp); return value
        } catch NativeFriendDirectoryFailure.unavailablePeer { if generation == stamp { issue = "friendDirectory.unavailablePeer" } }
        catch { if generation == stamp { issue = "friendDirectory.loadFailure" } }
        finish(stamp); return nil
    }
    public func existingConversation() async -> Int? { await readDetail()?.conversationID }
    public func currentFriend() async -> NativeFriendItem? { await readDetail()?.item }
    private func finish(_ stamp: UInt64) {
        guard validateAuthority(), generation == stamp else { return }
        readTask = nil; busy = false; onChange?()
    }
}
