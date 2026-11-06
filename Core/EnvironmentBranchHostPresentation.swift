import Foundation

/// G-W05.5–W05.7 host presentation layer for play and merchant surfaces.
/// Projects `EnvironmentBranchSelector` decisions into deterministic UI state without
/// computing deadlines from the device clock or inventing unreviewed branches.
public enum EnvironmentBranchHostMode: String, Equatable, Sendable {
    case activeBranch
    case deterministicFallback
    case pausedForSafety
    case noBranchAvailable
}

public struct EnvironmentBranchHostPresentation: Equatable, Sendable {
    public let decision: EnvironmentBranchDecision
    public let mode: EnvironmentBranchHostMode
    public let activeBranchID: String?
    public let snapshotID: String?
    public let fallbackReason: EnvironmentBranchDecision.FallbackReason?
    public let allowsProgression: Bool
    public let requiresSafeExitAction: Bool
    public let isIndoorBranch: Bool?
    public let windowDisplayText: String
    public let statusHeadline: String
    public let statusDetail: String

    public static func resolve(
        proposedBranchID: String?,
        branches: [ApprovedBranch],
        snapshot: EnvironmentSnapshot?,
        serverNow: Date,
        fallbackTimeZoneID: String = "Asia/Shanghai"
    ) -> EnvironmentBranchHostPresentation {
        let decision = EnvironmentBranchSelector.decide(
            proposedBranchID: proposedBranchID,
            branches: branches,
            snapshot: snapshot,
            serverNow: serverNow
        )
        return project(
            decision: decision,
            branches: branches,
            snapshot: snapshot,
            fallbackTimeZoneID: fallbackTimeZoneID
        )
    }

    public static func project(
        decision: EnvironmentBranchDecision,
        branches: [ApprovedBranch],
        snapshot: EnvironmentSnapshot?,
        fallbackTimeZoneID: String = "Asia/Shanghai"
    ) -> EnvironmentBranchHostPresentation {
        let timeZoneID = snapshot?.runTimeZoneID ?? fallbackTimeZoneID
        switch decision {
        case let .selected(branchID, snapshotID):
            let branch = branches.first { $0.branchID == branchID }
            return EnvironmentBranchHostPresentation(
                decision: decision,
                mode: .activeBranch,
                activeBranchID: branchID,
                snapshotID: snapshotID,
                fallbackReason: nil,
                allowsProgression: true,
                requiresSafeExitAction: false,
                isIndoorBranch: branch?.indoor,
                windowDisplayText: formatAbsoluteWindow(branch?.window, runTimeZoneID: timeZoneID),
                statusHeadline: "已启用已审环境分支",
                statusDetail: "基于服务端环境快照（\(snapshotID)）匹配分支 \(branchID)。"
            )

        case let .fallback(branchID, reason):
            let branch = branches.first { $0.branchID == branchID }
            return EnvironmentBranchHostPresentation(
                decision: decision,
                mode: .deterministicFallback,
                activeBranchID: branchID,
                snapshotID: snapshot?.snapshotID,
                fallbackReason: reason,
                allowsProgression: true,
                requiresSafeExitAction: false,
                isIndoorBranch: branch?.indoor,
                windowDisplayText: formatAbsoluteWindow(branch?.window, runTimeZoneID: timeZoneID),
                statusHeadline: "已切换确定性兜底分支",
                statusDetail: describeFallbackReason(reason)
            )

        case .pausedForSafety:
            return EnvironmentBranchHostPresentation(
                decision: decision,
                mode: .pausedForSafety,
                activeBranchID: nil,
                snapshotID: snapshot?.snapshotID,
                fallbackReason: nil,
                allowsProgression: false,
                requiresSafeExitAction: true,
                isIndoorBranch: nil,
                windowDisplayText: "服务端安全暂停期间不开放限时窗口",
                statusHeadline: "恶劣天气或高风险路线安全暂停",
                statusDetail: "当前户外环境触发安全保护，已暂停节点推进并提供安全撤离引导，不临时生成挑战。"
            )

        case .noBranchAvailable:
            return EnvironmentBranchHostPresentation(
                decision: decision,
                mode: .noBranchAvailable,
                activeBranchID: nil,
                snapshotID: snapshot?.snapshotID,
                fallbackReason: nil,
                allowsProgression: false,
                requiresSafeExitAction: false,
                isIndoorBranch: nil,
                windowDisplayText: "无可用时间窗口",
                statusHeadline: "当前无可用已审分支",
                statusDetail: "未匹配到满足条件的已审分支或确定性兜底分支，系统不会由模型临时编造新分支。"
            )
        }
    }

    /// Formats the server-supplied absolute window in the run's time zone without referencing the device clock.
    public static func formatAbsoluteWindow(_ window: DateInterval?, runTimeZoneID: String) -> String {
        guard let window else {
            return "长期有效（无限时窗口）"
        }
        let resolvedZone = TimeZone(identifier: runTimeZoneID)
            ?? TimeZone(identifier: "Asia/Shanghai")
            ?? TimeZone(secondsFromGMT: 8 * 3600)!
        let effectiveZoneID = TimeZone(identifier: runTimeZoneID) != nil ? runTimeZoneID : "Asia/Shanghai"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = resolvedZone
        formatter.calendar = calendar
        formatter.timeZone = resolvedZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "\(formatter.string(from: window.start)) ~ \(formatter.string(from: window.end)) (\(effectiveZoneID))"
    }

    public static func describeFallbackReason(_ reason: EnvironmentBranchDecision.FallbackReason) -> String {
        switch reason {
        case .snapshotMissing:
            return "环境快照缺失，已回退至唯一已审确定性兜底分支。"
        case .snapshotStale:
            return "环境快照已过期或时区无效，已回退至唯一已审确定性兜底分支。"
        case .proposalNotApproved:
            return "候选分支不在已审分支集合内，已回退至唯一已审确定性兜底分支。"
        case .proposalConditionsUnmet:
            return "候选分支的天气、营业状态或可达点位条件未满足，已回退至唯一已审确定性兜底分支。"
        }
    }
}
