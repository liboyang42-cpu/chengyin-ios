import Foundation
import Observation

@MainActor @Observable public final class NativeFriendTeamInviteFlow: NativeFriendPickerSource {
    public let mode: NativeFriendTeamInviteMode
    @ObservationIgnored private let service: NativeFriendTeamInviteService
    @ObservationIgnored private let journal: NativeFriendTeamInviteJournal?
    @ObservationIgnored private var authorityTask: Task<Void, Never>?
    private var active = false
    private var retired = false
    private var journalFailed = false
    private var generation: UInt64 = 0
    private var rawItems: [NativeFriendPickerItem] = []
    private var rawSelected: [NativeFriendPickerItem] = []
    private var rawOffers: [NativeFriendTeamOffer] = []
    private var rawReview: NativeFriendTeamInviteReviewContext?
    private var rawReceipt: NativeFriendTeamInviteReceipt?
    private var rawPending: NativeFriendTeamInviteCommand?
    private var rawName = ""
    private var cursor = "0"
    public private(set) var section: NativeFriendDirectorySection = .all
    public private(set) var busy = false
    public private(set) var issue: String?
    public var isCurrent: Bool { active && !retired && service.isCurrent }
    public var items: [NativeFriendPickerItem] { isCurrent ? rawItems : [] }
    public var selected: [NativeFriendPickerItem] { isCurrent ? rawSelected : [] }
    public var offers: [NativeFriendTeamOffer] { isCurrent ? rawOffers : [] }
    public var name: String { isCurrent ? rawName : "" }
    public var review: NativeFriendTeamInviteCommand? { isCurrent ? rawReview?.command : nil }
    public var reviewContext: NativeFriendTeamInviteReviewContext? { isCurrent ? rawReview : nil }
    public var receipt: NativeFriendTeamInviteReceipt? { isCurrent ? rawReceipt : nil }
    public var pending: NativeFriendTeamInviteCommand? { isCurrent ? rawPending : nil }
    public var hasPickerReview: Bool { review != nil }
    public var alreadyMemberLabel: String { "原成员/申请状态当前不可邀请" }
    public var canWrite: Bool { isCurrent && !busy && !journalFailed && journal != nil && rawPending == nil && service.canWrite }
    public var canRecover: Bool { isCurrent && !busy && rawPending != nil && !journalFailed }
    public var canMore: Bool { isCurrent && !busy && mode == .mine && cursor != "0" }
    public init(service: NativeFriendTeamInviteService, journal: NativeFriendTeamInviteJournal?) {
        self.service = service; self.journal = journal; mode = service.mode
        // Same foreground authority-liveness check as the original friend flows; no new network polling.
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
        do { rawPending = try journal?.restore() } catch { journalFailed = true; issue = "原请求保护记录不可确认，未发送新操作。" }
        await refresh()
    }
    public func refresh() async {
        guard isCurrent, !busy else { return }; rawReview = nil; rawSelected = []
        switch mode {
        case .team: await chooseSection(section)
        case .mine: await loadMine(more: false)
        case .offer(let id):
            generation &+= 1; let stamp = generation; busy = true; rawOffers = []
            defer { if stamp == generation { busy = false } }
            do { let r = try await service.landing(offer: id); guard isCurrent, stamp == generation, !Task.isCancelled else { return }; rawOffers = [r]; issue = nil }
            catch { if stamp == generation { rawOffers = []; issue = "原邀请或当前资格不可读；历史卡不恢复权限。" } }
        }
    }
    public func chooseSection(_ next: NativeFriendDirectorySection) async {
        guard isCurrent, !busy, case .team(let team) = mode else { return }
        generation &+= 1; let stamp = generation; busy = true; section = next; rawItems = []; rawSelected = []; rawOffers = []; rawReview = nil; rawName = ""
        defer { if stamp == generation { busy = false } }
        do {
            var loaded: [NativeFriendPickerItem] = [], cursor: String?, revision: String?, seen: Set<String> = []
            for _ in 0..<10 {
                let p = try await service.picker(team: team, section: next, cursor: cursor)
                guard isCurrent, stamp == generation, !Task.isCancelled else { return }
                guard revision == nil || revision == p.directory.revision, Set(loaded.map(\.id)).isDisjoint(with: p.items.map(\.id)) else { throw NativeFriendFailure.invalid }
                revision = p.directory.revision; loaded += p.items
                guard loaded.count <= 500 else { throw NativeFriendFailure.invalid }
                if !p.directory.hasMore { guard loaded.count == p.directory.total else { throw NativeFriendFailure.invalid }; rawItems = loaded; rawName = p.name; issue = nil; return }
                guard let c = p.directory.nextCursor, seen.insert(c).inserted, !p.items.isEmpty else { throw NativeFriendFailure.invalid }; cursor = c
            }
            throw NativeFriendFailure.invalid
        } catch { if stamp == generation { rawItems = []; rawName = ""; issue = "原好友或队长/成员来源已变化，未沿用旧名单。" } }
    }
    public func toggle(_ item: NativeFriendPickerItem) {
        guard canWrite, rawReview == nil, rawItems.contains(item), !item.alreadyMember else { return }
        if rawSelected.contains(item) { rawSelected.removeAll { $0.id == item.id } } else if rawSelected.count < 10 { rawSelected.append(item) }
    }
    public func prepareCreate() {
        guard canWrite, rawReview == nil, case .team(let team) = mode, !rawSelected.isEmpty,
              rawSelected.allSatisfy({ rawItems.contains($0) && !$0.alreadyMember }) else { return }
        let peers = rawSelected.sorted { $0.id < $1.id }
        guard let command = try? NativeFriendTeamInviteCommand(action: "FRIEND_OFFER", body: .init(teamId: team, peers: peers.map { .init(id: $0.id, version: $0.friend.version) })) else { return }
        rawReview = .init(command: command, teamName: rawName, peers: peers)
    }
    public func prepare(_ offer: NativeFriendTeamOffer, action: String) {
        guard canWrite, rawReview == nil, rawOffers.contains(offer), offer.canAct, let team = Int64(offer.teamID), team > 0,
              offer.recipient ? ["FRIEND_CONFIRM", "FRIEND_DECLINE"].contains(action) : action == "FRIEND_REVOKE" else { return }
        if case .mine = mode, action != "FRIEND_REVOKE" { return }
        if case .team = mode { return }
        guard let command = try? NativeFriendTeamInviteCommand(action: action, body: .init(teamId: team, offerId: offer.offerID, joinMode: action == "FRIEND_CONFIRM" ? offer.joinMode : nil)) else { return }
        rawReview = .init(command: command, teamName: offer.name, peers: [])
    }
    public func cancelReview() { if !busy { rawReview = nil } }
    public func confirm() async {
        guard canWrite, let command = rawReview?.command, let journal, journal.acquire() else { return }; defer { journal.release() }
        generation &+= 1; let stamp = generation; busy = true; rawReview = nil; rawSelected = []; rawReceipt = nil
        defer { if stamp == generation { busy = false } }
        do {
            guard try journal.restore() == nil else { throw NativeFriendFailure.unknown }
            if let id = command.body.offerId {
                let current = try await service.landing(offer: id)
                guard current.canAct, current.teamID == String(command.teamID), current.recipient == (command.action != "FRIEND_REVOKE"),
                      command.action != "FRIEND_CONFIRM" || current.joinMode == command.body.joinMode else { throw NativeFriendFailure.notSent }
            }
            guard isCurrent, stamp == generation, !Task.isCancelled else { throw NativeFriendFailure.notSent }
            try journal.save(command); rawPending = command
            let receipt = try await service.write(command)
            guard isCurrent, stamp == generation, !Task.isCancelled else { return }
            try settle(receipt, command: command, journal: journal)
        } catch {
            if isCurrent, stamp == generation {
                // No automatic resend, even after an HTTP rejection without an exact original receipt.
                do { rawPending = try journal.restore() } catch { journalFailed = true }
                issue = rawPending == nil ? "未发送；请重新读取当前资格后再确认。" : "原请求结果未知，保留同一请求，仅回读，不重发。"
            }
        }
        guard stamp == generation else { return }; busy = false
        if isCurrent, rawPending == nil { await refreshAfterTerminal(command) }
    }
    private func settle(_ receipt: NativeFriendTeamInviteReceipt, command: NativeFriendTeamInviteCommand, journal: NativeFriendTeamInviteJournal) throws {
        guard receipt.outcome == "APPLIED" || receipt.outcome == "REJECTED" else { throw NativeFriendFailure.unknown }
        try journal.clear(command); rawPending = nil; rawReceipt = receipt
        issue = receipt.outcome == "APPLIED" ? "原请求已记录；以下状态仍以当前原成员来源为准。" : "原请求已被拒绝；未替你重试或扩大资格。"
    }
    private func refreshAfterTerminal(_ command: NativeFriendTeamInviteCommand) async {
        // Current eligibility and original terminal identity are independent; refresh never replaces the receipt.
        await refresh()
        if isCurrent, case .team(let team) = mode, command.action == "FRIEND_OFFER", team == command.teamID {
            await loadMine(more: false)
        }
    }
    public func recover() async {
        guard canRecover, let command = rawPending, let journal, journal.acquire() else { return }; defer { journal.release() }
        generation &+= 1; let stamp = generation; busy = true
        defer { if stamp == generation { busy = false } }
        do { let r = try await service.recover(command); guard isCurrent, stamp == generation, !Task.isCancelled else { return }; try settle(r, command: command, journal: journal) }
        catch { if isCurrent, stamp == generation { issue = "原回执仍不可确认，保护记录继续保留，不重发。" } }
        guard stamp == generation else { return }; busy = false
        if isCurrent, rawPending == nil { await refreshAfterTerminal(command) }
    }
    public func loadMine(more: Bool) async {
        guard isCurrent, !busy, !more || cursor != "0" else { return }
        generation &+= 1; let stamp = generation; busy = true; if !more { rawOffers = []; cursor = "0" }
        let before = cursor
        defer { if stamp == generation { busy = false } }
        do { let r = try await service.mine(before: before); guard isCurrent, stamp == generation, !Task.isCancelled else { return }
            if more { guard Set(rawOffers.map(\.id)).isDisjoint(with: r.items.map(\.id)) else { throw NativeFriendFailure.invalid } }
            rawOffers = more ? rawOffers + r.items : r.items; cursor = r.nextBefore
        } catch { if stamp == generation { rawOffers = []; cursor = "0"; issue = "本人原邀请历史不可确认，未保留旧私有投影。" } }
    }
    public func deactivate() {
        generation &+= 1; active = false; retired = true; busy = false; rawItems = []; rawSelected = []; rawOffers = []; rawName = ""; rawReview = nil; rawPending = nil; rawReceipt = nil; issue = nil
        authorityTask?.cancel(); authorityTask = nil
        // Account/approval revocation clears projections, not the protected original request journal.
    }
}
