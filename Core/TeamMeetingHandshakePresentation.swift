import Foundation

/// Presentation projections for reform plan v9 §24 / W16 (decisions U02–U07):
/// - `TeamFirstMeeting`: confirmed-team eligibility without interest matching, real-name verification
///   scoped exclusively to `.strangerTeamMeeting`, rotating QR handshake with NFC permanently off,
///   and zero location point fields (MV38).
/// - `FriendMultiInvite` & `RevokeWinsLedger`: review invalidation on selection change, partial-failure
///   retry restricted to failed/unsent recipients with stable request IDs, and terminal revocation precedence.
/// - `BeijingDeadline`: dual-zone display (device zone + governing Asia/Shanghai time when offsets differ)
///   and server-offset-driven advisory hints that never block submission.
public enum TeamMeetingHandshakePresentation {

    // MARK: - U05–U07: Team First Meeting Eligibility & Handshake Presentation

    public enum EligibilityVerdict: Equatable, Sendable {
        case eligible(TeamMeetingEligibility)
        case teamNotConfirmed
        case invalidBinding
    }

    public struct MeetingCard: Equatable, Sendable {
        public let teamId: String
        public let meetingId: String
        public let phase: TeamFirstMeeting.Phase
        public let phaseTitle: String
        public let phaseSubtitle: String
        public let noInterestMatching: Bool
        public let realNameScopedOnlyToStrangerMeeting: Bool
        public let availableHandshakes: [TeamMeetingHandshake]
        public let qrAlwaysOffered: Bool
        public let nfcOffered: Bool
        public let requiresRealNameCheck: Bool
        public let canBeginHandshake: Bool
        public let canScanPeerCode: Bool
        public let awaitingServerDecision: Bool
        public let isTerminal: Bool
        public let activeChallengePayload: String?
        public let isChallengeExpired: Bool
    }

    /// Evaluates whether server team facts open the stranger team-meeting step (U05).
    public static func evaluateEligibility(
        teamId: String,
        meetingId: String,
        selfMemberId: String,
        peerMemberId: String,
        formation: String,
        teamStatus: TeamStatus
    ) -> EligibilityVerdict {
        do {
            let eligibility = try TeamMeetingEligibility(
                teamId: teamId,
                meetingId: meetingId,
                selfMemberId: selfMemberId,
                peerMemberId: peerMemberId,
                formation: formation,
                teamStatus: teamStatus
            )
            return .eligible(eligibility)
        } catch let issue as TeamMeetingIssue {
            return issue == .teamNotConfirmed ? .teamNotConfirmed : .invalidBinding
        } catch {
            return .invalidBinding
        }
    }

    /// Verifies U06: only `.strangerTeamMeeting` requires real-name verification; every other flow is false.
    public static func isRealNameStrictlyScoped() -> Bool {
        let nonMeetingFlows: [RealNameScope.Flow] = [
            .ordinaryPlay,
            .friendInvite,
            .mapRead,
            .teamJoin,
            .publish
        ]
        return RealNameScope.requiresRealName(.strangerTeamMeeting)
            && nonMeetingFlows.allSatisfy { !RealNameScope.requiresRealName($0) }
    }

    /// Formats the opaque rotating QR payload for local rendering when issued by `selfMemberId` for this meeting.
    public static func challengePayload(
        for challenge: TeamMeetingChallenge?,
        eligibility: TeamMeetingEligibility,
        deviceNow: Date,
        serverOffset: TimeInterval
    ) -> (payload: String?, isExpired: Bool) {
        guard let challenge,
              challenge.meetingId == eligibility.meetingId,
              challenge.teamId == eligibility.teamId,
              challenge.issuerMemberId == eligibility.selfMemberId,
              challenge.receiverMemberId == eligibility.peerMemberId else {
            return (nil, true)
        }
        let estimatedNow = deviceNow.addingTimeInterval(serverOffset)
        guard estimatedNow < challenge.expiresAt else {
            return (nil, true)
        }
        let joined = [
            challenge.meetingId,
            challenge.issuerMemberId,
            challenge.nonce,
            challenge.keyVersion,
            challenge.signature
        ].joined(separator: ".")
        return (joined, false)
    }

    /// Builds the meeting presentation card for `TeamFirstMeeting` (U05–U07).
    public static func presentMeeting(
        _ meeting: TeamFirstMeeting,
        myChallenge: TeamMeetingChallenge? = nil,
        capabilities: ReformWorldCapabilities = .disabled,
        deviceReportsNFC: Bool = false,
        deviceNow: Date = Date(),
        serverOffset: TimeInterval = 0
    ) -> MeetingCard {
        let handshakes = TeamMeetingHandshake.available(
            capabilities: capabilities,
            deviceReportsNFC: deviceReportsNFC
        )
        let codeState = challengePayload(
            for: myChallenge,
            eligibility: meeting.eligibility,
            deviceNow: deviceNow,
            serverOffset: serverOffset
        )
        let title: String
        let subtitle: String
        switch meeting.phase {
        case .realNameRequired:
            title = "需完成实名核验"
            subtitle = "仅陌生人组队见面步需要实名核验，普通游玩与好友邀请无需实名"
        case .readyToMeet:
            title = "队伍已确认，准备当面核验"
            subtitle = "仅对已确认成团的队友开放，无兴趣匹配，出示动态二维码完成核验"
        case .handshaking:
            title = "出示或扫描动态二维码"
            subtitle = codeState.isExpired ? "当前二维码已过期，请刷新动态码" : "请向队友出示动态二维码，或扫描对方动态码"
        case .confirmationPending:
            title = "正在等待服务端确认"
            subtitle = "核验请求已提交，结果未明时可通过原请求回读确认"
        case .met:
            title = "已完成当面核验"
            subtitle = "服务端已确认本次组队见面"
        case .cancelled:
            title = "见面已取消"
            subtitle = "任一方取消或撤回后本次见面终止，后续迟到响应不再生效"
        case .expired:
            title = "见面已过期"
            subtitle = "超出有效时段，本次组队见面已结束"
        }

        let isTerminal = [.met, .cancelled, .expired].contains(meeting.phase)
        return MeetingCard(
            teamId: meeting.eligibility.teamId,
            meetingId: meeting.eligibility.meetingId,
            phase: meeting.phase,
            phaseTitle: title,
            phaseSubtitle: subtitle,
            noInterestMatching: true,
            realNameScopedOnlyToStrangerMeeting: isRealNameStrictlyScoped(),
            availableHandshakes: handshakes,
            qrAlwaysOffered: handshakes.contains(.dynamicQR),
            nfcOffered: handshakes.contains(.nfcUnverified),
            requiresRealNameCheck: meeting.phase == .realNameRequired,
            canBeginHandshake: meeting.phase == .readyToMeet,
            canScanPeerCode: meeting.phase == .handshaking,
            awaitingServerDecision: meeting.phase == .confirmationPending,
            isTerminal: isTerminal,
            activeChallengePayload: meeting.phase == .handshaking ? codeState.payload : nil,
            isChallengeExpired: codeState.isExpired
        )
    }

    // MARK: - U02 & U04: Friend Multi-Invite & Revoke-Wins Presentation

    public struct RecipientRow: Equatable, Identifiable, Sendable {
        public let friendId: String
        public let displayName: String
        public let delivery: FriendMultiInvite.Delivery
        public let stableRequestId: String?
        public let statusBadgeText: String
        public let isRetryable: Bool
        public var id: String { friendId }
    }

    public struct InviteBatchCard: Equatable, Sendable {
        public let contextId: String
        public let phase: FriendMultiInvite.Phase
        public let selectedCount: Int
        public let maximumCount: Int
        public let selectionCounterText: String
        public let isReviewValid: Bool
        public let canSendReviewed: Bool
        public let canRetryFailedNow: Bool
        public let requiresUnknownReadbackFirst: Bool
        public let retryableRecipientIds: [String]
        public let unknownRecipientIds: [String]
        public let summary: FriendMultiInvite.Summary
        public let recipientRows: [RecipientRow]
    }

    /// Projects a `FriendMultiInvite` batch into a presentation card highlighting review invalidation,
    /// stable per-recipient request IDs, and failed-only retry rules (U02, U04).
    public static func presentInviteBatch(_ batch: FriendMultiInvite) -> InviteBatchCard {
        let rows: [RecipientRow] = batch.selected.map { target in
            let delivery = batch.deliveries[target.friendId] ?? .notSent
            let badge: String
            let retryable: Bool
            switch delivery {
            case .notSent:
                badge = "待发送"
                retryable = true
            case .sent:
                badge = "已发送"
                retryable = false
            case .rejected(let code):
                badge = "已拒绝（\(code)）"
                retryable = false
            case .failed:
                badge = "发送失败，可重试"
                retryable = true
            case .unknown:
                badge = "结果未明，需先回读"
                retryable = false
            case .revoked:
                badge = "已撤回"
                retryable = false
            }
            return RecipientRow(
                friendId: target.friendId,
                displayName: target.displayName,
                delivery: delivery,
                stableRequestId: batch.requestIds[target.friendId],
                statusBadgeText: badge,
                isRetryable: retryable
            )
        }

        let summary = batch.summary
        let retryableIds = rows.filter(\.isRetryable).map(\.friendId)
        let unknownIds = rows.filter { $0.delivery == .unknown }.map(\.friendId)
        let isReviewValid = batch.phase == .reviewed
        let canSendReviewed = batch.phase == .reviewed && !batch.selected.isEmpty
        let canRetryFailedNow = batch.phase == .finished && summary.retryable > 0 && summary.unknown == 0

        return InviteBatchCard(
            contextId: batch.contextId,
            phase: batch.phase,
            selectedCount: batch.selected.count,
            maximumCount: batch.maximum,
            selectionCounterText: "\(batch.selected.count) / \(batch.maximum)",
            isReviewValid: isReviewValid,
            canSendReviewed: canSendReviewed,
            canRetryFailedNow: canRetryFailedNow,
            requiresUnknownReadbackFirst: summary.unknown > 0,
            retryableRecipientIds: retryableIds,
            unknownRecipientIds: unknownIds,
            summary: summary,
            recipientRows: rows
        )
    }

    public struct RevokeLedgerBadge: Equatable, Sendable {
        public let subjectId: String
        public let display: RevokeWinsState.Display
        public let version: Int64
        public let isRevokeFinal: Bool
        public let statusText: String
        public let pendingToast: RevokeWinsState.Display?
    }

    /// Applies an ordered sequence of `RevokeWinsEvent` updates to a `RevokeWinsState` and formats
    /// the resulting terminal revocation state and notification gate (U04).
    public static func evaluateRevokeLedger(
        subjectId: String,
        events: [RevokeWinsEvent]
    ) throws -> RevokeLedgerBadge {
        var state = try RevokeWinsState(subjectId: subjectId)
        for event in events {
            _ = try state.apply(event)
        }
        let toast = state.notificationToShow()
        return presentRevokeState(state, pendingToast: toast)
    }

    public static func presentRevokeState(
        _ state: RevokeWinsState,
        pendingToast: RevokeWinsState.Display? = nil
    ) -> RevokeLedgerBadge {
        let text: String
        switch state.display {
        case .pending:
            text = "待回应"
        case .accepted:
            text = "已接受"
        case .declined:
            text = "已婉拒"
        case .revoked:
            text = "已撤回（终态）"
        case .expired:
            text = "已过期"
        case .unknown:
            text = "状态待确认"
        }
        return RevokeLedgerBadge(
            subjectId: state.subjectId,
            display: state.display,
            version: state.version,
            isRevokeFinal: state.display == .revoked,
            statusText: text,
            pendingToast: pendingToast
        )
    }

    // MARK: - U03: Beijing Deadline Dual-Zone Banner Presentation

    public struct DeadlineBanner: Equatable, Sendable {
        public let localTimeText: String
        public let governingBeijingTimeText: String?
        public let showsDualZone: Bool
        public let headlineText: String
        public let hint: BeijingDeadline.Hint
        public let advisoryStatusText: String
        public let allowsSubmission: Bool
    }

    /// Formats a `BeijingDeadline` for `phoneZone` and `locale`, displaying both the phone-zone time
    /// and the governing Beijing time when the offsets differ, while keeping submission enabled (U03).
    public static func presentDeadlineBanner(
        _ deadline: BeijingDeadline,
        phoneZone: TimeZone,
        locale: Locale = Locale(identifier: "zh_Hans_CN"),
        deviceNow: Date,
        serverOffset: TimeInterval,
        uncertainty: TimeInterval = 2
    ) -> DeadlineBanner {
        let pair = deadline.display(phoneZone: phoneZone, locale: locale)
        let hint = deadline.hint(deviceNow: deviceNow, serverOffset: serverOffset, uncertainty: uncertainty)
        let headline: String
        if let beijing = pair.beijing {
            headline = "截止时间：\(pair.local)（北京时间 \(beijing)）"
        } else {
            headline = "截止时间：\(pair.local)"
        }

        let advisory: String
        switch hint {
        case .open(let remainingSeconds):
            advisory = "距离截止还有 \(remainingSeconds) 秒"
        case .boundary:
            advisory = "临近截止时间，提交结果以服务端为准"
        case .likelyClosed:
            advisory = "已过截止时间（仍可提交由服务端裁定）"
        }

        return DeadlineBanner(
            localTimeText: pair.local,
            governingBeijingTimeText: pair.beijing,
            showsDualZone: pair.beijing != nil,
            headlineText: headline,
            hint: hint,
            advisoryStatusText: advisory,
            allowsSubmission: true
        )
    }
}
