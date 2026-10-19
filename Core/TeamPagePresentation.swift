import Foundation

/// Mini-program `pages/team/detail` and `pages/team/join` page facts, projected from the
/// existing coordinator state. Presentation only: no transport, no write, no persisted state.
/// Every visibility rule mirrors the source wxml; writes still go through `TeamAction.isAllowed`.
public enum TeamPageKind: Equatable, Sendable { case detail, invitation }

/// Source `cy-state-shell` facts for a page with no snapshot, or a banner when one is retained.
public struct TeamPageState: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case missingParameter, legacyLink, signIn, noPermission, network, unavailable, unconfigured, changed }
    public enum Action: Equatable, Sendable { case goBack, signIn, reload, none }
    public let kind: Kind
    public let titleKey: String
    public let detailKey: String
    public let action: Action
    public var actionKey: String? {
        switch action { case .goBack: return "team.page.goBack"; case .signIn: return "team.page.signIn"; case .reload: return "team.refresh"; case .none: return nil }
    }
}

/// Source join page bottom CTA: 查看队伍 / 接受邀请并加入 / 队伍已满 / 队伍已结束.
public enum TeamInvitationCTA: Equatable, Sendable {
    case openDetail, join, full, ended
    public var key: String {
        switch self { case .openDetail: return "team.page.openTeam"; case .join: return "team.join"; case .full: return "team.page.full"; case .ended: return "team.page.ended" }
    }
}

public enum TeamPagePresentation {
    /// `team.status < 2` renders the live chip in the source.
    public static func statusIsLive(_ status: TeamStatus) -> Bool { status == .recruiting || status == .full }

    /// `{{team.joinMode == 2 ? '公开招募' : '仅邀请'}} · 组队与否不影响活动举行`. Unknown stays unknown.
    public static func modeKey(_ mode: TeamJoinMode) -> String { mode.key }

    /// Leader-only join-mode explanation under the 公开招募 switch.
    public static func joinModeHelpKey(_ mode: TeamJoinMode) -> String {
        switch mode {
        case .publicApplication: return "team.page.modeHelp.public"
        case .invitation: return "team.page.modeHelp.invitation"
        case .unknown: return "team.mode.unknown"
        }
    }

    /// Source detail action row (`team.status == 0`): 邀请队友 for everyone, 加入队伍 when not joined.
    public static func showsInviteEntry(_ detail: TeamDetail) -> Bool { detail.team.status == .recruiting }
    /// The source routes a non-member to the join page with the team's own invite code.
    /// Membership must be an explicit `false`; an omitted fact never offers a join.
    public static func joinRouteCode(_ detail: TeamDetail) -> String? {
        guard detail.team.status == .recruiting, detail.joined == false,
              let code = detail.team.inviteCode, TeamLookup.validInvite(code) else { return nil }
        return code
    }
    /// 退出并移交队长 for the leader, 退出队伍 otherwise. Only the label differs; the action is the same.
    public static func leaveLabelKey(_ detail: TeamDetail) -> String {
        detail.leader == true ? "team.page.leaveAndTransfer" : TeamAction.leave(teamID: detail.team.id).key
    }
    /// 退队不会退款；如需退票，请在订单中单独处理。 shown to members only.
    public static func showsRefundNote(_ detail: TeamDetail) -> Bool { detail.joined == true }

    public static func invitationCTA(_ detail: TeamDetail) -> TeamInvitationCTA {
        if detail.joined == true { return .openDetail }
        switch detail.team.status {
        case .recruiting: return .join
        case .full: return .full
        default: return .ended
        }
    }

    /// Mirrors source `formatTime`: `M月D日 HH:mm`. A wall-clock server string without a zone is
    /// shown as written (the source parses it as device local and formats it back unchanged);
    /// an ISO value with an offset is shown in `displayZone`. Unparseable text is returned verbatim.
    public static func startText(_ raw: String?, chinese: Bool, displayZone: TimeZone = .current) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let utc = TimeZone(identifier: "UTC")!
        var date: Date?
        var zone = utc
        if raw.contains("T") {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            date = iso.date(from: raw)
            if date == nil { iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; date = iso.date(from: raw) }
            zone = displayZone
        } else {
            for pattern in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm"] {
                let parser = DateFormatter()
                parser.locale = Locale(identifier: "en_US_POSIX"); parser.timeZone = utc; parser.dateFormat = pattern
                if let value = parser.date(from: raw) { date = value; break }
            }
        }
        guard let date else { return raw }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        guard let month = parts.month, let day = parts.day, let hour = parts.hour, let minute = parts.minute else { return raw }
        let clock = String(format: "%02d:%02d", hour, minute)
        if chinese { return "\(month)月\(day)日 \(clock)" }
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(names[month - 1]) \(day), \(clock)"
    }

    /// Full-page state when there is no snapshot. `legacyTeamID` is the old `?teamId=` join link.
    public static func blockingState(kind page: TeamPageKind, messageKey: String?, hasDetail: Bool, legacyTeamID: Bool = false, failure: TeamReadFailureKind? = nil) -> TeamPageState? {
        guard !hasDetail, let messageKey else { return nil }
        let join = page == .invitation
        switch messageKey {
        case "team.invalidLink":
            if join && legacyTeamID { return .init(kind: .legacyLink, titleKey: "team.page.legacyLink", detailKey: "team.page.legacyLink.detail", action: .goBack) }
            return .init(kind: .missingParameter, titleKey: join ? "team.page.inviteIncomplete" : "team.page.linkIncomplete",
                         detailKey: join ? "team.page.inviteIncomplete.detail" : "team.page.linkIncomplete.detail", action: .goBack)
        case "team.signIn":
            return .init(kind: .signIn, titleKey: join ? "team.page.signInInvite" : "team.page.signInTeam",
                         detailKey: join ? "team.page.signInInvite.detail" : "team.page.signInTeam.detail", action: .signIn)
        case "team.unconfigured":
            return .init(kind: .unconfigured, titleKey: "team.unconfigured", detailKey: "team.writesDisabled", action: .none)
        case "team.changed":
            return .init(kind: .changed, titleKey: "team.changed", detailKey: "team.page.changed.detail", action: .goBack)
        default:
            // Source: a 403 keeps the 登录后查看… explanation with 重新加载; a transport failure is 网络没连上.
            if failure == .forbidden {
                return .init(kind: .noPermission, titleKey: join ? "team.page.signInInvite" : "team.page.signInTeam",
                             detailKey: join ? "team.page.signInInvite.detail" : "team.page.signInTeam.detail", action: .reload)
            }
            if failure == .network {
                return .init(kind: .network, titleKey: "team.page.offline", detailKey: "team.page.offline.detail", action: .reload)
            }
            return .init(kind: .unavailable, titleKey: join ? "team.page.inviteUnavailable" : "team.page.teamUnavailable",
                         detailKey: join ? "team.page.inviteUnavailable.detail" : "team.page.teamUnavailable.detail", action: .reload)
        }
    }

    /// Banner over a retained snapshot after a failed refresh (source `hasTeam` branch).
    public static func staleBanner(kind page: TeamPageKind, messageKey: String?, hasDetail: Bool) -> (title: String, detail: String)? {
        guard hasDetail, messageKey == "team.refreshFailed" else { return nil }
        return page == .invitation ? ("team.page.inviteStale", "team.page.inviteStale.detail") : ("team.page.teamStale", "team.page.teamStale.detail")
    }

    /// Source join page `cy-inline-error` 暂时无法加入 after a refused or unsent join. Its 重试加入 opens a
    /// fresh explicit review; nothing is resubmitted automatically. An unknown outcome never qualifies.
    public static func showsJoinRetry(_ writeState: TeamCoordinator.WriteState, page: TeamPageKind) -> Bool {
        page == .invitation && (writeState == .rejected || writeState == .notSent)
    }

    public static func loadingKey(_ page: TeamPageKind, hasDetail: Bool) -> String {
        if hasDetail { return page == .invitation ? "team.page.checkingInvite" : "team.loading" }
        return page == .invitation ? "team.page.readingInvite" : "team.page.loadingDetail"
    }
}
