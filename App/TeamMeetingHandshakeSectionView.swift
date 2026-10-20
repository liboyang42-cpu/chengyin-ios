import SwiftUI

/// Offline SwiftUI section view rendering `TeamMeetingHandshakePresentation` projections
/// for reform plan v9 §24 / W16 and decisions U02–U07:
/// - `MeetingCard`: confirmed-team eligibility without interest matching, QR-only / NFC-off
///   handshake badge, real-name verification scoped exclusively to stranger team meetings,
///   and rotating QR challenge payload status.
/// - `InviteBatchCard`: friend multi-invite selection review validity, failed-only retry status
///   with stable per-recipient request IDs, and unknown-outcome readback gate.
/// - `RevokeLedgerBadge` & `DeadlineBanner`: terminal revocation precedence and dual-zone
///   Beijing governing deadline display.
/// Uses `Text(verbatim:)` throughout so zero new `.xcstrings` keys are required.
@MainActor
public struct TeamMeetingHandshakeSectionView: View {
    public let meetingCard: TeamMeetingHandshakePresentation.MeetingCard?
    public let inviteBatchCard: TeamMeetingHandshakePresentation.InviteBatchCard?
    public let revokeBadge: TeamMeetingHandshakePresentation.RevokeLedgerBadge?
    public let deadlineBanner: TeamMeetingHandshakePresentation.DeadlineBanner?

    public var onBeginHandshake: (() -> Void)?
    public var onScanPeerQRCode: (() -> Void)?
    public var onSendReviewedInvites: (() -> Void)?
    public var onRetryFailedInvites: (([String]) -> Void)?
    public var onReadbackUnknownInvites: (([String]) -> Void)?

    public init(
        meetingCard: TeamMeetingHandshakePresentation.MeetingCard? = nil,
        inviteBatchCard: TeamMeetingHandshakePresentation.InviteBatchCard? = nil,
        revokeBadge: TeamMeetingHandshakePresentation.RevokeLedgerBadge? = nil,
        deadlineBanner: TeamMeetingHandshakePresentation.DeadlineBanner? = nil,
        onBeginHandshake: (() -> Void)? = nil,
        onScanPeerQRCode: (() -> Void)? = nil,
        onSendReviewedInvites: (() -> Void)? = nil,
        onRetryFailedInvites: (([String]) -> Void)? = nil,
        onReadbackUnknownInvites: (([String]) -> Void)? = nil
    ) {
        self.meetingCard = meetingCard
        self.inviteBatchCard = inviteBatchCard
        self.revokeBadge = revokeBadge
        self.deadlineBanner = deadlineBanner
        self.onBeginHandshake = onBeginHandshake
        self.onScanPeerQRCode = onScanPeerQRCode
        self.onSendReviewedInvites = onSendReviewedInvites
        self.onRetryFailedInvites = onRetryFailedInvites
        self.onReadbackUnknownInvites = onReadbackUnknownInvites
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let deadlineBanner {
                deadlineSection(deadlineBanner)
            }
            if let meetingCard {
                meetingSection(meetingCard)
            }
            if let inviteBatchCard {
                inviteBatchSection(inviteBatchCard)
            }
            if let revokeBadge {
                revokeLedgerSection(revokeBadge)
            }
        }
        .accessibilityIdentifier("w16.teamMeetingHandshake.section")
    }

    // MARK: - U03: Dual-Zone Beijing Deadline Banner

    @ViewBuilder
    private func deadlineSection(_ banner: TeamMeetingHandshakePresentation.DeadlineBanner) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: "截止时间与时区说明")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: banner.showsDualZone ? "双时区显示（以北京时间为准）" : "北京时间")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.blue)
                    .accessibilityIdentifier("w16.deadline.zoneBadge")
            }

            Text(verbatim: banner.headlineText)
                .font(.subheadline.weight(.medium))
                .accessibilityIdentifier("w16.deadline.headline")

            if let beijing = banner.governingBeijingTimeText {
                Text(verbatim: "设备时区：\(banner.localTimeText) · 判定基准北京时间：\(beijing)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("w16.deadline.dualZoneDetail")
            }

            HStack(spacing: 8) {
                Text(verbatim: banner.advisoryStatusText)
                    .font(.caption)
                    .foregroundStyle(banner.hint == .likelyClosed ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .accessibilityIdentifier("w16.deadline.advisory")
                Spacer()
                if banner.allowsSubmission {
                    Text(verbatim: "允许提交（由服务端最终裁定）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("w16.deadline.submissionGate")
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    // MARK: - U05–U07: Team First Meeting Card

    @ViewBuilder
    private func meetingSection(_ card: TeamMeetingHandshakePresentation.MeetingCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verbatim: "组队当面核验（\(card.teamId) · \(card.meetingId)）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: card.qrAlwaysOffered && !card.nfcOffered ? "仅动态二维码 · NFC 已禁用" : "核验方式受限")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.blue.opacity(0.15)))
                    .accessibilityIdentifier("w16.meeting.handshakeBadge")
            }

            Text(verbatim: card.phaseTitle)
                .font(.headline)
                .accessibilityIdentifier("w16.meeting.phaseTitle")

            Text(verbatim: card.phaseSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("w16.meeting.phaseSubtitle")

            HStack(spacing: 8) {
                if card.noInterestMatching {
                    Text(verbatim: "仅限已确认队伍（无兴趣匹配）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("w16.meeting.confirmedTeamOnlyBadge")
                }
                if card.realNameScopedOnlyToStrangerMeeting {
                    Text(verbatim: "实名核验仅限陌生人见面步")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("w16.meeting.realNameScopeBadge")
                }
            }

            if let payload = card.activeChallengePayload, !card.isChallengeExpired {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "当前动态二维码载荷（有效）")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                    Text(verbatim: payload)
                        .font(.caption2.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityIdentifier("w16.meeting.qrPayload")
                }
            } else if card.phase == .handshaking && card.isChallengeExpired {
                Text(verbatim: "动态二维码已过期或未签发，请刷新后再出示")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("w16.meeting.qrExpiredNotice")
            }

            HStack(spacing: 12) {
                if card.canBeginHandshake, let onBeginHandshake {
                    Button(action: onBeginHandshake) {
                        Text(verbatim: "发起当面二维码核验")
                    }
                    .accessibilityIdentifier("w16.meeting.beginHandshakeButton")
                }
                if card.canScanPeerCode, let onScanPeerQRCode {
                    Button(action: onScanPeerQRCode) {
                        Text(verbatim: "扫描队友动态二维码")
                    }
                    .accessibilityIdentifier("w16.meeting.scanQRButton")
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    // MARK: - U02 & U04: Friend Multi-Invite Batch Card

    @ViewBuilder
    private func inviteBatchSection(_ card: TeamMeetingHandshakePresentation.InviteBatchCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verbatim: "好友多选邀请（\(card.contextId)）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: "已选 \(card.selectionCounterText)")
                    .font(.caption.monospacedDigit())
                    .accessibilityIdentifier("w16.invite.counter")
            }

            Text(verbatim: card.isReviewValid ? "名单复核有效，可发送邀请" : "选择变更后需重新复核名单")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(card.isReviewValid ? AnyShapeStyle(.primary) : AnyShapeStyle(.orange))
                .accessibilityIdentifier("w16.invite.reviewStatus")

            Text(verbatim: "发送汇总：已发 \(card.summary.sent) · 待重试 \(card.summary.retryable) · 未明 \(card.summary.unknown) · 已撤回 \(card.summary.revoked)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("w16.invite.summaryText")

            if card.requiresUnknownReadbackFirst {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "存在结果未明受邀人（\(card.unknownRecipientIds.joined(separator: ", "))），重试前必须先回读服务端状态。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("w16.invite.unknownReadbackGate")
                    if let onReadbackUnknownInvites {
                        Button(action: { onReadbackUnknownInvites(card.unknownRecipientIds) }) {
                            Text(verbatim: "回读结果未明受邀状态")
                        }
                        .accessibilityIdentifier("w16.invite.readbackButton")
                    }
                }
            }

            ForEach(card.recipientRows) { row in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(row.displayName) (\(row.friendId))")
                            .font(.subheadline)
                        if let reqId = row.stableRequestId {
                            Text(verbatim: "幂等请求 ID：\(reqId)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(verbatim: row.statusBadgeText)
                        .font(.caption)
                        .foregroundStyle(row.isRetryable ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
                .accessibilityIdentifier("w16.invite.row.\(row.friendId)")
            }

            HStack(spacing: 12) {
                if card.canSendReviewed, let onSendReviewedInvites {
                    Button(action: onSendReviewedInvites) {
                        Text(verbatim: "确认发送已复核邀请")
                    }
                    .accessibilityIdentifier("w16.invite.sendReviewedButton")
                }
                if card.canRetryFailedNow, let onRetryFailedInvites {
                    Button(action: { onRetryFailedInvites(card.retryableRecipientIds) }) {
                        Text(verbatim: "仅重试失败受邀人（\(card.retryableRecipientIds.count)）")
                    }
                    .accessibilityIdentifier("w16.invite.retryFailedButton")
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    // MARK: - U04: Revoke-Wins Ledger Badge

    @ViewBuilder
    private func revokeLedgerSection(_ badge: TeamMeetingHandshakePresentation.RevokeLedgerBadge) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "撤回优先账本（\(badge.subjectId) · v\(badge.version)）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(verbatim: badge.statusText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(badge.isRevokeFinal ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                    .accessibilityIdentifier("w16.revoke.statusText")
            }
            Spacer()
            if badge.isRevokeFinal {
                Text(verbatim: "撤回终态不可逆")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.red.opacity(0.15)))
                    .accessibilityIdentifier("w16.revoke.finalBadge")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }
}
