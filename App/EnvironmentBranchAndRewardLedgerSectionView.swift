import SwiftUI

/// SwiftUI host section view for G-W05.5–W05.7 environment branch selection and fallback presentation.
/// Uses `Text(verbatim:)` exclusively to avoid introducing unreviewed localization table keys.
@MainActor
public struct EnvironmentBranchHostSectionView: View {
    public let presentation: EnvironmentBranchHostPresentation

    public init(presentation: EnvironmentBranchHostPresentation) {
        self.presentation = presentation
    }

    public init(
        proposedBranchID: String? = "synthetic-outdoor",
        branches: [ApprovedBranch] = [
            ApprovedBranch(
                branchID: "synthetic-indoor-fallback",
                window: nil,
                indoor: true,
                requiresOpenStore: false,
                requiredPlaceIDs: [],
                isDeterministicFallback: true
            )
        ],
        snapshot: EnvironmentSnapshot? = nil,
        serverNow: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) {
        self.presentation = EnvironmentBranchHostPresentation.resolve(
            proposedBranchID: proposedBranchID,
            branches: branches,
            snapshot: snapshot,
            serverNow: serverNow
        )
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(verbatim: presentation.statusHeadline)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(verbatim: modeBadgeText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("environmentBranch.host.headline")

                Text(verbatim: presentation.statusDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("environmentBranch.host.detail")

                if let activeBranchID = presentation.activeBranchID {
                    HStack {
                        Text(verbatim: "生效分支")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(verbatim: activeBranchID)
                            .font(.caption.monospaced())
                    }
                    .accessibilityIdentifier("environmentBranch.host.activeBranch")
                }

                if let snapshotID = presentation.snapshotID {
                    HStack {
                        Text(verbatim: "环境快照")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(verbatim: snapshotID)
                            .font(.caption.monospaced())
                    }
                    .accessibilityIdentifier("environmentBranch.host.snapshotID")
                }

                HStack {
                    Text(verbatim: "时间窗口")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(verbatim: presentation.windowDisplayText)
                        .font(.caption)
                }
                .accessibilityIdentifier("environmentBranch.host.window")

                if presentation.requiresSafeExitAction {
                    Text(verbatim: "安全保护已开启：暂停户外节点推进，请按引导撤离至安全室内点位。")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("environmentBranch.host.safeExitNotice")
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(verbatim: "环境分支与安全兜底 (W05.5–W05.7)")
        }
    }

    private var modeBadgeText: String {
        switch presentation.mode {
        case .activeBranch:
            return "已审主分支"
        case .deterministicFallback:
            return "确定性兜底"
        case .pausedForSafety:
            return "安全暂停"
        case .noBranchAvailable:
            return "无可用分支"
        }
    }
}

/// SwiftUI host section view for G-W07.5–W07.6 append-only reward ledger readback,
/// reversal pairing audit display, rebuildable season projection, and W17.4 non-cash guard.
@MainActor
public struct RewardLedgerHostSectionView: View {
    public let outcome: RewardLedgerValidationOutcome

    public init(outcome: RewardLedgerValidationOutcome) {
        self.outcome = outcome
    }

    public init(snapshot: RewardLedgerHostSnapshot) {
        self.outcome = .valid(snapshot)
    }

    public init(
        entries: [RewardLedgerEntry] = [
            RewardLedgerEntry(
                entryID: "synthetic-entry-1",
                beneficiaryID: "synthetic-player",
                rewardType: .points,
                amount: 30,
                sourceEventID: "synthetic-event-1",
                ruleVersion: "v1",
                seasonID: "season-2026-s1",
                reversalOf: nil,
                recordedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            RewardLedgerEntry(
                entryID: "synthetic-entry-2",
                beneficiaryID: "synthetic-player",
                rewardType: .points,
                amount: -30,
                sourceEventID: "synthetic-event-1",
                ruleVersion: "v1",
                seasonID: "season-2026-s1",
                reversalOf: "synthetic-entry-1",
                recordedAt: Date(timeIntervalSince1970: 1_700_000_060)
            ),
            RewardLedgerEntry(
                entryID: "synthetic-entry-3",
                beneficiaryID: "synthetic-player",
                rewardType: .points,
                amount: 50,
                sourceEventID: "synthetic-event-2",
                ruleVersion: "v1",
                seasonID: "season-2026-s1",
                reversalOf: nil,
                recordedAt: Date(timeIntervalSince1970: 1_700_000_120)
            )
        ],
        beneficiaryID: String = "synthetic-player",
        rewardType: RewardLedgerEntry.RewardType = .points,
        activeSeasonID: String? = "season-2026-s1"
    ) {
        self.outcome = RewardLedgerHostPresentation.evaluate(
            entries: entries,
            beneficiaryID: beneficiaryID,
            rewardType: rewardType,
            activeSeasonID: activeSeasonID
        )
    }

    public var body: some View {
        Section {
            switch outcome {
            case .valid(let snapshot):
                validBody(snapshot)
            case .invalid(let error):
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "奖励账本校验未通过")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    Text(verbatim: describeError(error))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("rewardLedger.host.error")
            }

            HStack {
                Text(verbatim: "非现金账本约束 (W17.4)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(
                    verbatim: RewardLedgerHostPresentation.supportsCashInLedger || RewardLedgerHostPresentation.canBridgePointsToCash
                        ? "异常开启"
                        : "仅非现金权益 · 禁兑现金"
                )
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("rewardLedger.host.nonCashPolicy")
        } header: {
            Text(verbatim: "追加式奖励账本与赛季投影 (W07.5–W07.6)")
        }
    }

    @ViewBuilder
    private func validBody(_ snapshot: RewardLedgerHostSnapshot) -> some View {
        HStack {
            Text(verbatim: "永久净额 (\(snapshot.rewardType.rawValue))")
                .font(.subheadline)
            Spacer()
            Text(verbatim: "\(snapshot.permanentNetBalance)")
                .font(.subheadline.monospaced().weight(.semibold))
        }
        .accessibilityIdentifier("rewardLedger.host.permanentNet")

        if let seasonID = snapshot.activeSeasonID, let seasonBalance = snapshot.activeSeasonBalance {
            HStack {
                Text(verbatim: "当前赛季投影 (\(seasonID))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: "\(seasonBalance)")
                    .font(.caption.monospaced())
            }
            .accessibilityIdentifier("rewardLedger.host.seasonProjection")
        }

        ForEach(snapshot.rows, id: \.entryID) { row in
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "\(row.entryID) · 事件 \(row.sourceEventID)")
                        .font(.caption.monospaced())
                    if let revOf = row.reversalOf {
                        Text(verbatim: "冲正原记录: \(revOf)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if let pairedRev = row.pairedReversalEntryID {
                        Text(verbatim: "已被追加冲正: \(pairedRev)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(verbatim: row.amount > 0 ? "+\(row.amount)" : "\(row.amount)")
                    .font(.caption.monospaced())
                    .foregroundStyle(row.isReversal ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
            }
            .accessibilityIdentifier("rewardLedger.host.row.\(row.entryID)")
        }
    }

    private func describeError(_ error: RewardLedgerReadbackError) -> String {
        switch error {
        case .duplicateEntryID:
            return "存在重复的账本记录 ID，已拒绝读回。"
        case .duplicateBusinessKey:
            return "违反业务唯一键约束 U(受益人, 源事件, 奖励类型, 规则版本)，已拒绝重复记账。"
        case .zeroAmount:
            return "账本变动数量不能为 0。"
        case .reversalWithoutOriginal:
            return "冲正记录缺少对应的原始发放记录。"
        case .reversalMismatch:
            return "冲正记录与原始记录的受益人、类型、事件或正负金额不匹配。"
        case .doubleReversal:
            return "同一原始发放记录存在重复冲正。"
        case .historyRewritten:
            return "检测到历史账本记录被篡改，违反只追加约束。"
        case .entryRemoved:
            return "检测到历史账本记录被删除，违反只追加约束。"
        }
    }
}
