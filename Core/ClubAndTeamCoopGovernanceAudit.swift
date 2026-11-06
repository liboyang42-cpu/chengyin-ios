import Foundation

/// Pure value-type governance audit across the 4 club, team & co-op pillars:
/// 1. `w2-12`: `TeamPagePresentation` & `ClubTabPresentation` + `social.incompleteLink` fallback.
/// 2. `w2-14/15/16`: `ClubGovernanceCoordinator` permission checks, `ClubEnrollmentReader` payment/refund summary,
///    `ClubOpsJoinNotifyPresentation`, and `ClubOpsSettlementPresentation`.
/// 3. `I09`: `ClubSeriesScheduleReadback` (`BK-SCHEDULE` dates fixture) & `PlayLeadProgressPolling`.
/// 4. `H-W16 / U02–U07`: `TeamMeetingHandshakePresentation` confirmed-team QR-only handshake (NFC off),
///    stranger-meeting-only real-name scope, per-recipient multi-invite request IDs, terminal revocation
///    precedence, and dual-zone Beijing governing time (`Asia/Shanghai`).
public enum ClubAndTeamGovernancePillarID: String, CaseIterable, Sendable, Equatable {
    case w2_12_teamAndClubEntry = "w2-12"
    case w2_14_15_16_clubGovernanceOps = "w2-14/15/16"
    case i09_seriesScheduleAndLeadPolling = "I09"
    case h_w16_u02_u07_teamHandshakeAndSafety = "H-W16/U02-U07"
}

public struct ClubAndTeamGovernancePillarRecord: Identifiable, Equatable, Sendable {
    public let pillar: ClubAndTeamGovernancePillarID
    public let coveredComponents: [String]
    public let fallbackOrFixtureKey: String
    public let invariantSummary: String
    public let isCompliant: Bool

    public var id: String { pillar.rawValue }

    public init(
        pillar: ClubAndTeamGovernancePillarID,
        coveredComponents: [String],
        fallbackOrFixtureKey: String,
        invariantSummary: String,
        isCompliant: Bool = true
    ) {
        self.pillar = pillar
        self.coveredComponents = coveredComponents
        self.fallbackOrFixtureKey = fallbackOrFixtureKey
        self.invariantSummary = invariantSummary
        self.isCompliant = isCompliant
    }
}

public enum TeamHandshakeChannelMode: String, Sendable, Equatable {
    case qrOnly = "QR_ONLY"
    case nfcDisabled = "NFC_DISABLED"
}

public enum TeamInviteLifecycleState: String, Sendable, Equatable {
    case pending = "PENDING"
    case accepted = "ACCEPTED"
    case expired = "EXPIRED"
    case revoked = "REVOKED"

    public var isTerminal: Bool {
        self == .revoked || self == .expired
    }
}

public struct ClubAndTeamCoopGovernanceAudit: Equatable, Sendable {
    public static let incompleteLinkFallbackKey = "social.incompleteLink"
    public static let scheduleDatesFixtureTag = "BK-SCHEDULE"
    public static let governingTimeZoneID = "Asia/Shanghai"
    public static let nfcHandshakeEnabled = false
    public static let qrHandshakeForConfirmedTeamOnly = true

    public static let defaultPillars: [ClubAndTeamGovernancePillarRecord] = [
        ClubAndTeamGovernancePillarRecord(
            pillar: .w2_12_teamAndClubEntry,
            coveredComponents: [
                "TeamPagePresentation",
                "ClubTabPresentation"
            ],
            fallbackOrFixtureKey: incompleteLinkFallbackKey,
            invariantSummary: "小队页与俱乐部页入口参数缺失时稳定回退至 social.incompleteLink，不发起越界请求。"
        ),
        ClubAndTeamGovernancePillarRecord(
            pillar: .w2_14_15_16_clubGovernanceOps,
            coveredComponents: [
                "ClubGovernanceCoordinator",
                "ClubEnrollmentReader",
                "ClubOpsJoinNotifyPresentation",
                "ClubOpsSettlementPresentation"
            ],
            fallbackOrFixtureKey: "club.ops.readOnly",
            invariantSummary: "俱乐部管理权限先验、报名支付/退款只读聚合、入社通知与结算展示分离。"
        ),
        ClubAndTeamGovernancePillarRecord(
            pillar: .i09_seriesScheduleAndLeadPolling,
            coveredComponents: [
                "ClubSeriesScheduleReadback",
                "PlayLeadProgressPolling"
            ],
            fallbackOrFixtureKey: scheduleDatesFixtureTag,
            invariantSummary: "系列活动排期采用 BK-SCHEDULE 日期读回契约，领队进度轮询遵循单飞与退避约束。"
        ),
        ClubAndTeamGovernancePillarRecord(
            pillar: .h_w16_u02_u07_teamHandshakeAndSafety,
            coveredComponents: [
                "TeamMeetingHandshakePresentation"
            ],
            fallbackOrFixtureKey: governingTimeZoneID,
            invariantSummary: "已确认小队仅启用当面二维码握手（NFC 恒关），仅陌生人线下组局要求实名校验，多收件人独立 requestID，终端撤销优先于迟到接受，北京时间主裁。"
        )
    ]

    public let pillars: [ClubAndTeamGovernancePillarRecord]
    public let handshakeChannel: TeamHandshakeChannelMode
    public let isNFCHandshakeEnabled: Bool
    public let realNameRequiredOnlyForStrangerMeeting: Bool

    public init(
        pillars: [ClubAndTeamGovernancePillarRecord] = ClubAndTeamCoopGovernanceAudit.defaultPillars,
        handshakeChannel: TeamHandshakeChannelMode = .qrOnly,
        isNFCHandshakeEnabled: Bool = ClubAndTeamCoopGovernanceAudit.nfcHandshakeEnabled,
        realNameRequiredOnlyForStrangerMeeting: Bool = true
    ) {
        self.pillars = pillars
        self.handshakeChannel = handshakeChannel
        self.isNFCHandshakeEnabled = isNFCHandshakeEnabled
        self.realNameRequiredOnlyForStrangerMeeting = realNameRequiredOnlyForStrangerMeeting
    }

    public var isAllCompliant: Bool {
        pillars.count == ClubAndTeamGovernancePillarID.allCases.count
            && pillars.allSatisfy(\.isCompliant)
            && handshakeChannel == .qrOnly
            && !isNFCHandshakeEnabled
            && realNameRequiredOnlyForStrangerMeeting
    }

    /// Evaluates whether a team meeting handshake may proceed: requires confirmed team membership, QR channel, and NFC disabled.
    public static func canStartMeetingHandshake(
        teamConfirmed: Bool,
        usingNFC: Bool
    ) -> Bool {
        guard teamConfirmed, !usingNFC, !nfcHandshakeEnabled else {
            return false
        }
        return qrHandshakeForConfirmedTeamOnly
    }

    /// Evaluates real-name verification requirement (U02): required only for offline stranger meetings, never for solo roam or private friend browsing.
    public static func requiresRealNameVerification(
        isOfflineStrangerMeeting: Bool,
        isConfirmedFriendTeam: Bool
    ) -> Bool {
        isOfflineStrangerMeeting && !isConfirmedFriendTeam
    }

    /// Builds deterministic per-recipient request IDs for multi-invite batches so each recipient tracks independent idempotency (U04).
    public static func perRecipientInviteRequestIDs(
        batchSeed: String,
        recipientAccountIDs: [Int]
    ) -> [Int: String] {
        let trimmed = batchSeed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [:] }
        var result: [Int: String] = [:]
        for recipientID in Set(recipientAccountIDs) where recipientID > 0 {
            result[recipientID] = "\(trimmed)-recipient-\(recipientID)"
        }
        return result
    }

    /// Enforces terminal revocation precedence (U04): once an invite is `.revoked` or `.expired`, a late `.accepted` readback cannot resurrect it.
    public static func resolveInviteState(
        current: TeamInviteLifecycleState,
        incoming: TeamInviteLifecycleState
    ) -> TeamInviteLifecycleState {
        if current == .revoked || incoming == .revoked {
            return .revoked
        }
        if current == .expired {
            return .expired
        }
        return incoming
    }

    /// Formats a server cutoff timestamp with dual-zone display when the viewer's time zone differs from Beijing time (`Asia/Shanghai`, U03).
    public static func formatBeijingGoverningCutoff(
        cutoff: Date,
        viewerTimeZone: TimeZone
    ) -> (beijingText: String, viewerText: String, requiresDualZoneDisplay: Bool) {
        let beijingZone = TimeZone(identifier: governingTimeZoneID) ?? TimeZone(secondsFromGMT: 8 * 3600)!
        let beijingFormatter = makeFormatter(timeZone: beijingZone)
        let viewerFormatter = makeFormatter(timeZone: viewerTimeZone)

        let beijingString = "\(beijingFormatter.string(from: cutoff)) (北京时间)"
        let viewerString = "\(viewerFormatter.string(from: cutoff)) (\(viewerTimeZone.identifier))"
        let differs = beijingZone.secondsFromGMT(for: cutoff) != viewerTimeZone.secondsFromGMT(for: cutoff)
        return (beijingString, viewerString, differs)
    }

    /// Judges whether the cutoff has passed strictly against server-supplied `serverNow` (never device wall clock).
    public static func isCutoffPassed(cutoff: Date, serverNow: Date) -> Bool {
        serverNow >= cutoff
    }

    private static func makeFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }
}
