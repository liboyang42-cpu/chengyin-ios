import Foundation

/// Source official-inbox (pages/activity/official-inbox) row rules over decoded inbox rows.
/// Display/eligibility only: the coordinator, server snapshot and the dormant production
/// approval still decide whether any reviewed command may be dispatched.
public enum OfficialInboxPresentation {
    /// Source `organizerInvite`: an OFFICIAL party with the ORGANIZER role.
    public static func isOrganizerInvite(_ invite: OfficialPartyInvite) -> Bool {
        invite.partyType == "OFFICIAL" && invite.role == "ORGANIZER"
    }
    /// Source wxml: every INVITED row offers decline then accept; ACCEPTED/ACTIVE rows offer
    /// withdraw unless the row is the organizer, which must transfer first.
    public static func actions(for invite: OfficialPartyInvite) -> [OfficialResponseAction] {
        switch invite.status {
        case "INVITED": return [.decline, .accept]
        case "ACCEPTED", "ACTIVE": return isOrganizerInvite(invite) ? [] : [.withdraw]
        default: return []
        }
    }
    /// Source wxml shows the organizer transfer explanation instead of a withdraw button.
    public static func showsOrganizerTransferNotice(_ invite: OfficialPartyInvite) -> Bool {
        isOrganizerInvite(invite) && ["ACCEPTED", "ACTIVE"].contains(invite.status ?? "")
    }
    /// Source `act`: an organizer withdrawal never builds a request ("主办需先完成转交才能退出").
    /// OFFICIAL withdrawals are rejected by the backend's dedicated organizer commands, so the
    /// same hint is used for any OFFICIAL party instead of building an invalid request.
    public static func requiresOrganizerTransfer(_ invite: OfficialPartyInvite, action: OfficialResponseAction) -> Bool {
        action == .withdraw && (isOrganizerInvite(invite) || invite.partyType == "OFFICIAL")
    }
    public static func buttonKey(_ action: OfficialResponseAction) -> String {
        switch action {
        case .accept: return "official.privateParity.inbox.accept"
        case .decline: return "official.privateParity.inbox.decline"
        case .withdraw: return "official.privateParity.inbox.withdraw"
        }
    }
    /// Source modal titles.
    public static func confirmationTitleKey(_ invite: OfficialPartyInvite, action: OfficialResponseAction) -> String {
        switch action {
        case .accept: return isOrganizerInvite(invite) ? "official.privateParity.inbox.confirm.acceptOrganizerTitle" : "official.privateParity.inbox.confirm.acceptTitle"
        case .decline: return "official.privateParity.inbox.confirm.declineTitle"
        case .withdraw: return "official.privateParity.inbox.confirm.withdrawTitle"
        }
    }
    /// Source modal content.
    public static func confirmationBodyKey(_ invite: OfficialPartyInvite, action: OfficialResponseAction) -> String {
        if isOrganizerInvite(invite) {
            return action == .accept ? "official.privateParity.inbox.confirm.organizerAcceptBody" : "official.privateParity.inbox.confirm.organizerDeclineBody"
        }
        return action == .accept ? "official.privateParity.inbox.confirm.acceptBody" : "official.privateParity.inbox.confirm.changeBody"
    }
    /// Source official-inbox load failure title and detail copy.
    public static let loadFailureTitle = "邀约没有加载出来"
    public static let loadFailureDetail = "邀约加载失败"
    public static let loadFailureTitleKey = "official.w206.inbox.failed.title"
    public static let loadFailureDetailKey = "official.w206.inbox.failed.detail"
    public static func serviceWindow(start: OfficialEventTime?, end: OfficialEventTime?) -> OfficialServiceWindow {
        OfficialServiceWindow(start: start, end: end)
    }
    public static func serviceWindowText(start: OfficialEventTime?, end: OfficialEventTime?) -> String {
        OfficialServiceWindow(start: start, end: end).sourceText
    }
}

public extension OfficialResponseAction {
    /// Source `_submitAction` fixed audit reasons; accept sends an empty reason.
    var sourceReason: String {
        switch self {
        case .accept: return ""
        case .decline: return "主体拒绝本场邀约"
        case .withdraw: return "主体退出本场职责"
        }
    }
}

public extension OfficialActionCommand {
    /// The only inbox request shape: the current server row's party ID/type and the
    /// source's fixed reason. User text never reaches the audited reason.
    static func sourceInboxResponse(to invite: OfficialPartyInvite, action: OfficialResponseAction) -> OfficialActionCommand {
        .respond(partyID: invite.id, type: invite.partyType ?? "", action: action, reason: action.sourceReason)
    }
}

/// Source `timeRange(windowStart, windowEnd)`. Numeric (or all-digit) values are epoch
/// milliseconds shown in Asia/Shanghai; text dates are kept verbatim, never reinterpreted.
public enum OfficialServiceWindow: Equatable {
    public enum Bound: Equatable {
        /// Source "不限".
        case open
        case time(month: Int, day: Int, hour: Int, minute: Int)
        case text(String)
    }
    /// Source "未限定服务时段".
    case unbounded
    case range(Bound, Bound)

    public init(start: OfficialEventTime?, end: OfficialEventTime?) {
        if start == nil && end == nil { self = .unbounded; return }
        self = .range(Self.bound(start), Self.bound(end))
    }
    static func bound(_ value: OfficialEventTime?) -> Bound {
        switch value {
        case nil: return .open
        case .milliseconds(let ms)?: return clock(ms) ?? .open
        case .text(let text)?:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed.allSatisfy({ $0.isASCII && $0.isNumber }), let ms = Double(trimmed), let value = clock(ms) { return value }
            return .text(text)
        }
    }
    private static func clock(_ ms: Double) -> Bound? {
        guard ms.isFinite, abs(ms) < 1e15 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(secondsFromGMT: 8 * 3600)!
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: Date(timeIntervalSince1970: ms / 1000))
        guard let month = parts.month, let day = parts.day, let hour = parts.hour, let minute = parts.minute else { return nil }
        return .time(month: month, day: day, hour: hour, minute: minute)
    }
    /// Exact source zh-Hans text, e.g. "9月22日 09:00 — 不限".
    public var sourceText: String {
        switch self {
        case .unbounded: return "未限定服务时段"
        case let .range(start, end): return Self.text(start) + " — " + Self.text(end)
        }
    }
    private static func text(_ bound: Bound) -> String {
        switch bound {
        case .open: return "不限"
        case let .time(month, day, hour, minute): return "\(month)月\(day)日 " + String(format: "%02d:%02d", hour, minute)
        case .text(let value): return value
        }
    }
}

/// Additional party-inbox fields the shared OfficialPartyInvite does not decode yet.
/// Kept separate so the shared contract stays untouched; hosts must decode the same row.
public struct OfficialInboxWindowFacts: Decodable, Equatable {
    public let windowStart: OfficialEventTime?
    public let windowEnd: OfficialEventTime?
    private enum CodingKeys: String, CodingKey { case windowStart, windowEnd }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        windowStart = try? c.decode(OfficialEventTime.self, forKey: .windowStart)
        windowEnd = try? c.decode(OfficialEventTime.self, forKey: .windowEnd)
    }
    public var window: OfficialServiceWindow { OfficialServiceWindow(start: windowStart, end: windowEnd) }
}

/// Source official-mine publisher view (activityStatusText(status, 'owner')).
public enum OfficialPublishedPresentation {
    public static func ownerStatusKey(_ status: Int?) -> String {
        switch status {
        case 0?: return "official.privateParity.published.status.draft"
        case 1?: return "official.privateParity.published.status.pending"
        case 2?: return "official.privateParity.published.status.registration"
        case 3?: return "official.privateParity.published.status.live"
        case 4?: return "official.privateParity.published.status.settling"
        case 5?, 6?: return "official.privateParity.published.status.ended"
        case 9?: return "official.privateParity.published.status.offline"
        default: return "official.privateParity.published.status.unknown"
        }
    }
    /// Source `nonBlank`: trimmed text, or nil for the localized fallback.
    public static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
    /// Source official-mine category suffix: `" · \(category)"` when non-blank.
    public static func categorySuffix(_ category: String?) -> String? {
        guard let trimmed = nonBlank(category) else { return nil }
        return " · \(trimmed)"
    }
    /// Source official-mine city + optional category suffix line.
    public static func cityAndCategoryLine(city: String?, category: String?, cityFallback: String = "城市待确认") -> String {
        let cityText = nonBlank(city) ?? cityFallback
        return cityText + (categorySuffix(category) ?? "")
    }
    /// Source official-mine broadcast summary line (`"一起发/分开发 · 发给 … · 城市"` with `"待确认"` fallbacks).
    public static func broadcastSummaryLine(_ facts: OfficialPublishedBroadcastFacts) -> String {
        facts.sourceLine
    }
}

/// Source official-mine `_decoBc` over broadcast fields the shared OfficialBroadcast does not
/// decode (copyMode, audience, status, city). Unknown values stay explicit, never guessed.
public struct OfficialPublishedBroadcastFacts: Decodable, Equatable {
    public enum Mode: Equatable { case together, separate, unknown }
    public enum Status: Equatable { case draft, pending, sent, withdrawn, unknown }
    public let id: Int?
    public let mode: Mode
    public let status: Status
    /// nil when empty or containing any role outside player/club/merchant (source "对象待确认").
    public let audience: [OfficialAudience]?
    /// nil when blank (source "范围待确认").
    public let city: String?
    private enum CodingKeys: String, CodingKey { case id, copyMode, audience, status, city }
    public init(id: Int? = nil, mode: Mode, status: Status = .unknown, audience: [OfficialAudience]?, city: String?) {
        self.id = id
        self.mode = mode
        self.status = status
        self.audience = (audience?.isEmpty == false) ? audience : nil
        self.city = OfficialPublishedPresentation.nonBlank(city)
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try? c.decode(Int.self, forKey: .id)
        switch try? c.decode(Int.self, forKey: .copyMode) {
        case 1?: mode = .together
        case 2?: mode = .separate
        default: mode = .unknown
        }
        switch try? c.decode(Int.self, forKey: .status) {
        case 0?: status = .draft
        case 1?: status = .pending
        case 2?: status = .sent
        case 3?: status = .withdrawn
        default: status = .unknown
        }
        let raw = ((try? c.decode(String.self, forKey: .audience)) ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let roles = raw.compactMap(OfficialAudience.init(rawValue:))
        audience = !raw.isEmpty && roles.count == raw.count ? roles : nil
        city = OfficialPublishedPresentation.nonBlank(try? c.decode(String.self, forKey: .city))
    }
    /// Exact source zh-Hans row: "一起发 · 发给 玩家 / 商家 · 杭州".
    public var sourceLine: String {
        let modeText: String
        switch mode { case .together: modeText = "一起发"; case .separate: modeText = "分开发"; case .unknown: modeText = "发送方式待确认" }
        let names: [OfficialAudience: String] = [.player: "玩家", .club: "俱乐部", .merchant: "商家"]
        let audienceText = audience.map { $0.compactMap { names[$0] }.joined(separator: " / ") } ?? "对象待确认"
        return modeText + " · 发给 " + audienceText + " · " + (city ?? "范围待确认")
    }
    /// Exact source zh-Hans badge (BC_ST).
    public var sourceStatusText: String {
        switch status { case .draft: return "草稿"; case .pending: return "待发"; case .sent: return "已发"; case .withdrawn: return "已撤"; case .unknown: return "状态待确认" }
    }
}
