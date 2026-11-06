import Foundation
import Observation

/// One complete normal author/recipient/history flow, using only original admission receipts and the protected intent.
@MainActor @Observable public final class NativeFriendChannelInviteFlow: NativeFriendPickerSource {
    public let mode: NativeFriendChannelInviteMode
    @ObservationIgnored private let service: NativeFriendChannelInviteService
    @ObservationIgnored private let journal: NativeFriendChannelInviteJournal?
    @ObservationIgnored private var authorityTask: Task<Void, Never>?
    private var active = false
    private var retired = false
    private var generation: UInt64 = 0
    private var journalFailed = false
    private var rawItems: [NativeFriendPickerItem] = []
    private var rawSelected: [NativeFriendPickerItem] = []
    private var rawName = ""
    private var rawTargetChannel = false
    private var rawGuildKind = 0
    private var rawReview: NativeFriendChannelInviteCommand?
    private var rawPending: NativeFriendChannelInviteCommand?
    private var rawBatch: NativeFriendChannelInviteBatch?
    private var rawLanding: NativeFriendChannelInviteLanding?
    private var rawMine: [NativeFriendChannelInviteMine.Item] = []
    private var rawReceipt: NativeFriendChannelInviteReceipt?
    private var mineCursor = "0"
    public private(set) var section: NativeFriendDirectorySection = .all
    public private(set) var busy = false
    private var latestIssue: String?
    private var journalIssue: String?
    public var issue: String? {
        guard isCurrent else { return nil }
        return journalIssue ?? latestIssue
    }
    public var isCurrent: Bool { active && !retired && service.isCurrent }
    public var items: [NativeFriendPickerItem] { isCurrent ? rawItems : [] }
    public var selected: [NativeFriendPickerItem] { isCurrent ? rawSelected : [] }
    public var name: String { isCurrent ? rawName : "" }
    public var originalSpaceLabel: String { isCurrent && rawGuildKind == 3 ? "原队伍" : "原俱乐部" }
    public var isTargetChannel: Bool { isCurrent && rawTargetChannel }
    public var hasPickerReview: Bool { review != nil }
    public var alreadyMemberLabel: String { isTargetChannel ? "当前已可访问目标频道" : (rawGuildKind == 3 ? "原队伍状态当前不可重复邀请" : "已在原俱乐部") }
    public var review: NativeFriendChannelInviteCommand? { isCurrent ? rawReview : nil }
    public var pending: NativeFriendChannelInviteCommand? { isCurrent ? rawPending : nil }
    public var batch: NativeFriendChannelInviteBatch? { isCurrent ? rawBatch : nil }
    public var landing: NativeFriendChannelInviteLanding? { isCurrent ? rawLanding : nil }
    public var mine: [NativeFriendChannelInviteMine.Item] { isCurrent ? rawMine : [] }
    public var receipt: NativeFriendChannelInviteReceipt? { isCurrent ? rawReceipt : nil }
    public var canMore: Bool { isCurrent && !busy && mode == .mine && mineCursor != "0" }
    public var canWrite: Bool { isCurrent && !busy && !journalFailed && journal != nil && rawPending == nil && service.canWrite }
    public var canRecover: Bool { isCurrent && !busy && rawPending != nil && !journalFailed }
    public init(service: NativeFriendChannelInviteService, journal: NativeFriendChannelInviteJournal?) {
        self.service = service; self.journal = journal; mode = service.mode
        authorityTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                guard let self else { return }; if self.active && !self.isCurrent { self.deactivate(); return }
            }
        }
    }
    deinit { authorityTask?.cancel() }
    public func activate() async {
        guard !retired else { return }; active = true
        do { rawPending = try journal?.restore() } catch { journalFailed = true; journalIssue = "原请求保护记录暂不可确认，不发送新操作。" }
        await refresh()
    }
    public func refresh() async {
        guard isCurrent, !busy else { return }
        rawReview = nil; rawSelected = []
        switch mode {
        case .channel: await chooseSection(section)
        case .mine: await loadMine(more: false)
        case .invite(let id, let joined):
            generation &+= 1; let stamp = generation; busy = true; rawBatch = nil; rawLanding = nil
            defer { if generation == stamp { busy = false } }
            do {
                if joined { let value = try await service.notice(invite: id); guard isCurrent, stamp == generation, !Task.isCancelled else { return }; rawBatch = value }
                else { let value = try await service.landing(invite: id); guard isCurrent, stamp == generation, !Task.isCancelled else { return }; rawLanding = value }
                latestIssue = nil
            } catch { if stamp == generation { rawBatch = nil; rawLanding = nil; latestIssue = "当前原邀请/准入来源不可确认；保留原请求号，可在本人入口回读。" } }
        }
    }
    public func chooseSection(_ next: NativeFriendDirectorySection) async {
        guard isCurrent, !busy, case .channel(let channel) = mode else { return }
        generation &+= 1; let stamp = generation; section = next; busy = true; rawItems = []; rawSelected = []; rawReview = nil; rawName = ""; rawTargetChannel = false; rawGuildKind = 0
        defer { if generation == stamp { busy = false } }
        do {
            var loaded: [NativeFriendPickerItem] = [], cursor: String?, revision: String?, seen: Set<String> = []; var name = ""; var target: Bool?; var guildKind: Int?
            for _ in 0..<10 {
                let page = try await service.picker(channel: channel, section: next, cursor: cursor)
                guard isCurrent, stamp == generation, !Task.isCancelled else { return }
                guard revision == nil || revision == page.directory.revision,
                      Set(loaded.map(\.id)).isDisjoint(with: page.items.map(\.id)) else { throw NativeFriendFailure.invalid }
                guard target == nil || target == (page.targetChannel == true) else { throw NativeFriendFailure.invalid }
                guard guildKind == nil || guildKind == page.guildKind else { throw NativeFriendFailure.invalid }
                guildKind = page.guildKind; target = page.targetChannel == true; revision = page.directory.revision; name = page.name; loaded += page.items
                guard loaded.count <= 500 else { throw NativeFriendFailure.invalid }
                if !page.directory.hasMore { guard loaded.count == page.directory.total else { throw NativeFriendFailure.invalid }; rawItems = loaded; rawName = name; rawTargetChannel = target == true; rawGuildKind = page.guildKind; latestIssue = nil; return }
                guard let next = page.directory.nextCursor, seen.insert(next).inserted, !page.items.isEmpty else { throw NativeFriendFailure.invalid }; cursor = next
            }
            throw NativeFriendFailure.invalid
        } catch { if stamp == generation { rawItems = []; rawSelected = []; rawName = ""; rawTargetChannel = false; rawGuildKind = 0; latestIssue = "原好友分区/成员资格已变化或不可读，未用旧名单代替。" } }
    }
    public func toggle(_ item: NativeFriendPickerItem) {
        guard canWrite, rawReview == nil, rawItems.contains(item), !item.alreadyMember else { return }
        if rawSelected.contains(item) { rawSelected.removeAll { $0.id == item.id } }
        else if rawSelected.count < 10 { rawSelected.append(item) }
    }
    public func prepareCreate() {
        guard canWrite, rawReview == nil, case .channel(let channel) = mode, !rawSelected.isEmpty,
              rawSelected.count <= 10, rawSelected.allSatisfy({ rawItems.contains($0) && !$0.alreadyMember }) else { return }
        rawReview = try? .init(action: "CREATE", objectID: channel, peers: rawSelected.map { .init(id: $0.id, version: $0.friend.version) })
    }
    public func prepareRecipient(message: String, checked: Set<String>) {
        guard canWrite, rawReview == nil, case .invite(let id, false) = mode, let landing = rawLanding else { return }
        if landing.isTargetChannel, landing.channelReady == true { rawReview = try? .init(action: "ACCEPT_CHANNEL", objectID: id) }
        else if landing.joinState == "NOT_MEMBER" {
            guard !landing.isTargetChannel || (landing.inviteAvailable == true && landing.parentInviteAvailable == true) else { return }
            rawReview = try? .init(action: landing.isTargetChannel ? "PARENT_SUBMIT" : "SUBMIT", objectID: id, message: message)
        }
        else if landing.joinState == "SCREENING_REQUIRED" {
            guard checked.isSubset(of: Set(landing.rules.map(\.key))), landing.rules.allSatisfy({ !$0.required || $0.accepted || checked.contains($0.key) }) else { return }
            rawReview = try? .init(action: "ACCEPT_RULES", objectID: id, accepted: landing.rules.filter { checked.contains($0.key) && !$0.accepted }.map { .init(key: $0.key, hash: $0.hash) })
        }
    }
    public func prepareRevoke(_ item: NativeFriendChannelInviteBatch.Item) {
        guard canWrite, rawReview == nil, rawBatch?.items.contains(item) == true, ["INVITED", "PENDING_REVIEW"].contains(item.state),
              let id = NativeFriendChannelInviteService.id(item.inviteID) else { return }
        rawReview = try? .init(action: "REVOKE", objectID: id)
    }
    public func cancelReview() { guard !busy else { return }; rawReview = nil }
    public func confirm() async {
        guard canWrite, let command = rawReview, let journal, journal.acquire() else { return }
        defer { journal.release() }
        do { try journal.save(command) } catch { journalFailed = true; rawReview = nil; journalIssue = "原请求未能可靠保存，本次未发送。"; return }
        if command.action == "CREATE" { rawBatch = nil }
        rawPending = command; rawReview = nil; rawSelected = []; rawReceipt = nil; generation &+= 1; let stamp = generation; busy = true
        do {
            let result = try await service.write(command)
            guard isCurrent, stamp == generation, !Task.isCancelled else { throw NativeFriendFailure.unknown }
            try settle(result, command: command, journal: journal)
        } catch {
            if stamp == generation, isCurrent {
                // A bare HTTP/Ajax rejection is not an actor/request/payload-bound terminal receipt.
                if let failure = error as? NativeFriendFailure, failure == .notSent {
                    do { try journal.clear(command); rawPending = nil; latestIssue = "本次未发送。" } catch { journalFailed = true; journalIssue = "原保护记录待核对。" }
                } else { latestIssue = "原操作结果未确认；保留同一请求，只回读，不重发。" }
            }
        }
        guard stamp == generation else { return }; busy = false
        if isCurrent, rawPending == nil { await refreshAfterTerminal(command) }
    }
    private var isChannel: Bool { if case .channel = mode { return true }; return false }
    private func settle(_ result: NativeFriendChannelInviteReceipt, command: NativeFriendChannelInviteCommand, journal: NativeFriendChannelInviteJournal) throws {
        guard ["APPLIED", "REJECTED"].contains(result.outcome) else { throw NativeFriendFailure.unknown }
        try journal.clear(command); rawPending = nil; rawReceipt = result
        if result.outcome == "REJECTED" { rawBatch = nil }
        latestIssue = result.outcome == "APPLIED" ? "已确认同一原请求；当前成员权限仍需单独读取。" : "原请求已明确拒绝并回滚；没有自动重发或创建邀请。"
    }
    private func refreshAfterTerminal(_ command: NativeFriendChannelInviteCommand) async {
        guard isCurrent, !busy else { return }
        if rawReceipt?.outcome == "APPLIED", command.action == "CREATE", mode == .mine || isChannel {
            await loadBatch(channel: command.objectID, request: command.requestID, preservingReceipt: true)
        } else {
            let retained = rawBatch; await refresh()
            if rawReceipt?.outcome == "APPLIED", let retained, mode == .mine || isChannel {
                await loadBatch(channel: Int64(retained.channelID) ?? 0, request: retained.requestID, preservingReceipt: true)
            }
        }
    }
    public func recover() async {
        guard canRecover, let command = rawPending, let journal, journal.acquire() else { return }
        defer { journal.release() }
        generation &+= 1; let stamp = generation; busy = true
        defer { if generation == stamp { busy = false } }
        do {
            let result = try await service.recover(command)
            guard isCurrent, stamp == generation, !Task.isCancelled else { return }
            if result.outcome == "UNKNOWN" { rawReceipt = result; latestIssue = "原记录仍为 UNKNOWN；不会改请求号或自动重发。" }
            else { try settle(result, command: command, journal: journal) }
        } catch { if isCurrent, stamp == generation { latestIssue = "原请求仍待核对；保护记录保留。" } }
        guard stamp == generation else { return }; busy = false
        if isCurrent, rawPending == nil { await refreshAfterTerminal(command) }
    }
    public func loadBatch(channel: Int64, request: String, preservingReceipt: Bool = false) async {
        guard isCurrent, !busy, channel > 0 else { return }
        generation &+= 1; let stamp = generation; busy = true; rawBatch = nil
        defer { if generation == stamp { busy = false } }
        do {
            let historical = try await service.receipt(request: request)
            guard isCurrent, stamp == generation else { return }; if !preservingReceipt { rawReceipt = historical }
            let value = try await service.batch(channel: channel, request: request)
            guard isCurrent, stamp == generation else { return }; rawBatch = value; latestIssue = nil
        } catch { if stamp == generation { rawBatch = nil; latestIssue = "原请求回执与当前频道/好友权限是两回事；当前明细不可读时不保留旧名单。" } }
    }
    public func loadMine(more: Bool) async {
        guard isCurrent, !busy, mode == .mine, !more || canMore else { return }
        generation &+= 1; let stamp = generation; busy = true; if !more { rawMine = []; mineCursor = "0" }
        let cursor = mineCursor
        defer { if generation == stamp { busy = false } }
        do {
            let value = try await service.mine(before: cursor)
            guard isCurrent, stamp == generation else { return }
            guard !more || Set(rawMine.map(\.id)).isDisjoint(with: value.items.map(\.id)), rawMine.count + value.items.count <= 500 else { throw NativeFriendFailure.invalid }
            rawMine += value.items; mineCursor = value.nextBefore; latestIssue = nil
        } catch { if stamp == generation { rawMine = []; mineCursor = "0"; latestIssue = "本人原邀请记录暂不可读。" } }
    }
    public func deactivate() {
        authorityTask?.cancel(); authorityTask = nil; active = false; retired = true; generation &+= 1; busy = false
        rawItems = []; rawSelected = []; rawName = ""; rawTargetChannel = false; rawGuildKind = 0; rawReview = nil; rawPending = nil; rawBatch = nil; rawLanding = nil; rawMine = []; rawReceipt = nil
        // No durable journal deletion, retry, unsubscribe, membership or provider call.
    }
}
