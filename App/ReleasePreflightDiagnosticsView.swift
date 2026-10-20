import SwiftUI

public extension ReleasePreflightAndUIReadinessContract {
    /// Aggregated preflight report for App Store / TestFlight release readiness and CI safety checks.
    struct PreflightReport: Equatable, Sendable {
        public let coordinates: BuildCoordinates
        public let serverUserInfoRole: String?
        public let gates: EndpointAllowlistGates
        public let violations: [PreflightViolation]

        public init(
            coordinates: BuildCoordinates = .safeBaseDefaults,
            serverUserInfoRole: String? = nil,
            gates: EndpointAllowlistGates = .init(),
            violations: [PreflightViolation]? = nil
        ) {
            self.coordinates = coordinates
            self.serverUserInfoRole = serverUserInfoRole
            self.gates = gates
            self.violations = violations ?? ReleasePreflightAndUIReadinessContract.verifyReleasePreflight(
                coordinates: coordinates,
                serverUserInfoRole: serverUserInfoRole,
                gates: gates
            )
        }

        public static let ciDefault = PreflightReport()

        public var isReadyForReleaseArchive: Bool {
            violations.isEmpty
        }

        public var isSafeUnconfiguredCIDefault: Bool {
            coordinates.isSafeUnconfiguredCIDefault && gates.isFailClosedDefault
        }

        public var sessionAdmission: SessionAdmissionEvaluation {
            ReleasePreflightAndUIReadinessContract.evaluateSessionAdmission(serverRole: serverUserInfoRole)
        }
    }
}

/// Renders `ReleasePreflightAndUIReadinessContract.PreflightReport` and `[UIReadinessAnchorContract]`
/// checklist rows using `Text(verbatim:)` throughout (zero new `.xcstrings` keys).
@MainActor public struct ReleasePreflightDiagnosticsView: View {
    public let report: ReleasePreflightAndUIReadinessContract.PreflightReport
    public let anchorContracts: [UIReadinessAnchorContract]
    public let mountedAnchorIdentifiers: Set<String>
    public let offScreenRevealedSurfaces: Set<UIReadinessFlowSurface>

    public init(
        report: ReleasePreflightAndUIReadinessContract.PreflightReport = .ciDefault,
        anchorContracts: [UIReadinessAnchorContract] = UIReadinessAnchorContract.allContracts,
        mountedAnchorIdentifiers: Set<String> = [],
        offScreenRevealedSurfaces: Set<UIReadinessFlowSurface> = []
    ) {
        self.report = report
        self.anchorContracts = anchorContracts
        self.mountedAnchorIdentifiers = mountedAnchorIdentifiers
        self.offScreenRevealedSurfaces = offScreenRevealedSurfaces
    }

    public init(
        coordinates: ReleasePreflightAndUIReadinessContract.BuildCoordinates,
        serverUserInfoRole: String? = nil,
        gates: ReleasePreflightAndUIReadinessContract.EndpointAllowlistGates = .init(),
        anchorContracts: [UIReadinessAnchorContract] = UIReadinessAnchorContract.allContracts,
        mountedAnchorIdentifiers: Set<String> = [],
        offScreenRevealedSurfaces: Set<UIReadinessFlowSurface> = []
    ) {
        self.init(
            report: .init(
                coordinates: coordinates,
                serverUserInfoRole: serverUserInfoRole,
                gates: gates
            ),
            anchorContracts: anchorContracts,
            mountedAnchorIdentifiers: mountedAnchorIdentifiers,
            offScreenRevealedSurfaces: offScreenRevealedSurfaces
        )
    }

    public var body: some View {
        List {
            summarySection
            coordinatesSection
            violationsSection
            gatesSection
            uiReadinessSection
        }
        .navigationTitle(Text(verbatim: "发布预检与UI就绪诊断"))
        .accessibilityIdentifier("releasePreflight.root")
    }

    private var summarySection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: report.isReadyForReleaseArchive ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(report.isReadyForReleaseArchive ? .green : .orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        verbatim: report.isReadyForReleaseArchive
                            ? "归档预检状态：可发布归档 (PASS)"
                            : "归档预检状态：未满足发布门禁（共 \(report.violations.count) 项阻断）"
                    )
                    .font(.headline)
                    Text(
                        verbatim: report.isSafeUnconfiguredCIDefault
                            ? "CI 默认状态：Base.xcconfig 安全未配置基线（Fail-Closed）"
                            : "CI 默认状态：已加载自定义构建或签名参数"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("releasePreflight.summary.status")
        } header: {
            Text(verbatim: "预检总览")
        }
    }

    private var coordinatesSection: some View {
        Section {
            coordinateRow(
                label: "代码签名 (CODE_SIGNING_ALLOWED)",
                value: report.coordinates.codeSigningAllowed ? "YES" : "NO"
            )
            coordinateRow(
                label: "Bundle ID",
                value: report.coordinates.bundleIdentifier.isEmpty ? "（未设置）" : report.coordinates.bundleIdentifier
            )
            coordinateRow(
                label: "Development Team",
                value: report.coordinates.developmentTeam.isEmpty ? "（未设置）" : report.coordinates.developmentTeam
            )
            coordinateRow(
                label: "市场配置 (QUESTIFY_MARKET)",
                value: report.coordinates.rawMarket.isEmpty ? "（未设置）" : report.coordinates.rawMarket
            )
            coordinateRow(
                label: "会话隔离域 (QUESTIFY_SESSION_REALM)",
                value: report.coordinates.rawSessionRealm.isEmpty ? "（未设置）" : report.coordinates.rawSessionRealm
            )
            coordinateRow(
                label: "API Base URL",
                value: report.coordinates.rawAPIBaseURL.isEmpty ? "（未设置）" : report.coordinates.rawAPIBaseURL
            )
            coordinateRow(
                label: "IOS-I00-1 服务端角色校验",
                value: Self.describeSessionAdmission(report.sessionAdmission)
            )
        } header: {
            Text(verbatim: "构建与区域隔离参数")
        }
        .accessibilityIdentifier("releasePreflight.coordinates")
    }

    private var violationsSection: some View {
        Section {
            if report.violations.isEmpty {
                Text(verbatim: "0 项违规：所有发布预检门禁均已通过")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("releasePreflight.violations.empty")
            } else {
                ForEach(Array(report.violations.enumerated()), id: \.offset) { index, violation in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "阻断项 #\(index + 1)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(verbatim: Self.describeViolation(violation))
                                .font(.subheadline)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("releasePreflight.violation.row")
                }
            }
        } header: {
            Text(verbatim: "发布预检阻断清单 (\(report.violations.count))")
        }
        .accessibilityIdentifier("releasePreflight.violations")
    }

    private var gatesSection: some View {
        Section {
            Text(
                verbatim: report.gates.isFailClosedDefault
                    ? "高危写能力与支付门禁：全部保持默认关闭 (Fail-Closed)"
                    : "高危写能力与支付门禁：已开启 \(report.gates.enabledGates.count) 项（未审批 \(report.gates.unapprovedEnabledGates.count) 项）"
            )
            .font(.subheadline)
            .accessibilityIdentifier("releasePreflight.gates.summary")

            ForEach(ReleasePreflightAndUIReadinessContract.EndpointAllowlistGates.GateIdentifier.allCases, id: \.rawValue) { gate in
                let isEnabled = report.gates.enabledGates.contains(gate)
                let isApproved = report.gates.approvedGates.contains(gate)
                HStack {
                    Text(verbatim: Self.describeGateTitle(gate))
                        .font(.subheadline)
                    Spacer()
                    Text(verbatim: Self.describeGateState(enabled: isEnabled, approved: isApproved))
                        .font(.caption.monospaced())
                        .foregroundStyle(isEnabled && !isApproved ? .red : .secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("releasePreflight.gates.row")
            }
        } header: {
            Text(verbatim: "高危端点白名单门禁")
        }
        .accessibilityIdentifier("releasePreflight.gates")
    }

    private var uiReadinessSection: some View {
        Section {
            ForEach(anchorContracts, id: \.surface) { contract in
                let evaluation = contract.evaluateReadiness(
                    mountedIdentifiers: mountedAnchorIdentifiers,
                    offScreenRevealed: offScreenRevealedSurfaces.contains(contract.surface)
                )
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(verbatim: Self.describeSurfaceTitle(contract.surface))
                            .font(.headline)
                        Spacer()
                        Text(verbatim: Self.describeReadinessBadge(evaluation))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(evaluation == .ready ? .green : .secondary)
                    }
                    Text(verbatim: "Root 锚点: \(contract.rootAccessibilityIdentifier) · 主交互锚点: \(contract.primaryInteractiveAnchorIdentifier)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(verbatim: "必需锚点 (\(contract.requiredAnchorIdentifiers.count)): \(contract.requiredAnchorIdentifiers.joined(separator: ", "))")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    if contract.requiresOffScreenFormReveal {
                        Text(verbatim: "表单折叠显露要求: 需调用 \(contract.revealHelperIdentifier ?? "revealInForm") 滚动显露主输入项")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(verbatim: Self.describeReadinessDetail(evaluation))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("releasePreflight.uiReadiness.row")
            }
        } header: {
            Text(verbatim: "UI 就绪与无障碍锚点契约 (\(anchorContracts.count))")
        }
        .accessibilityIdentifier("releasePreflight.uiReadiness")
    }

    private func coordinateRow(label: String, value: String) -> some View {
        HStack {
            Text(verbatim: label)
                .font(.subheadline)
            Spacer()
            Text(verbatim: value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    public static func describeSessionAdmission(
        _ evaluation: ReleasePreflightAndUIReadinessContract.SessionAdmissionEvaluation
    ) -> String {
        switch evaluation {
        case .admitted(let role):
            return "已准入 (\(role.rawValue))"
        case .missingOrEmptyRole:
            return "阻断：缺少服务端 role 字段 (Fail-Closed)"
        case .unrecognizedRole(let raw):
            return "阻断：未知服务端角色 (\(raw))"
        }
    }

    public static func describeViolation(
        _ violation: ReleasePreflightAndUIReadinessContract.PreflightViolation
    ) -> String {
        switch violation {
        case .codeSigningDisabled:
            return "代码签名未开启 (CODE_SIGNING_ALLOWED=NO)"
        case .placeholderOrEmptyBundleIdentifier:
            return "Bundle ID 仍为占位值或为空，禁止用于正式归档"
        case .missingDevelopmentTeam:
            return "未配置 Apple Development Team (DEVELOPMENT_TEAM)"
        case .invalidOrMissingMarket:
            return "未指定合法市场配置 (QUESTIFY_MARKET 须为 CN 或 US)"
        case .crossMarketOrInvalidSessionRealm:
            return "会话存储域 (QUESTIFY_SESSION_REALM) 为空或与当前市场前缀不匹配"
        case .apiBaseURLViolation(let urlViolation):
            switch urlViolation {
            case .missingOrMalformed:
                return "QUESTIFY_API_BASE_URL 为空或格式非法"
            case .nonHTTPS:
                return "QUESTIFY_API_BASE_URL 必须使用 HTTPS 协议"
            case .legacyMiniProgramHostRejected:
                return "严禁使用旧小程序遗留 IP (47.103.124.64) 作为正式 API 地址"
            case .placeholderOrLoopbackHost:
                return "QUESTIFY_API_BASE_URL 不能为占位域名、本地回环或裸 IPv4 地址"
            case .containsCredentialsQueryOrFragment:
                return "QUESTIFY_API_BASE_URL 不能包含凭据、查询参数或 Fragment"
            }
        case .sessionAdmissionRoleRejected(let evaluation):
            return "IOS-I00-1 会话准入未通过：\(describeSessionAdmission(evaluation))"
        case .unapprovedHighRiskGates(let gates):
            return "存在未获合规签字的高危门禁：\(gates.count) 项"
        case .unreviewedWriteRoutesPresent(let routes):
            return "存在未完成幂等审计的写路径：\(routes.joined(separator: ", "))"
        }
    }

    public static func describeGateTitle(
        _ gate: ReleasePreflightAndUIReadinessContract.EndpointAllowlistGates.GateIdentifier
    ) -> String {
        switch gate {
        case .smsSend:
            return "短信验证码发送 (SMS Send)"
        case .wechatSignIn:
            return "微信登录通道 (WeChat Sign-In)"
        case .appleSignIn:
            return "Apple 登录通道 (Sign in with Apple)"
        case .paymentAndWithdrawal:
            return "支付与提现链路 (Payment & Withdrawal)"
        case .topicLikeWrite:
            return "题材点赞写操作 (I05 Topic Like)"
        case .npcChatRemoteDelete:
            return "NPC 会话远端清空 (I08 NPC Chat Delete)"
        }
    }

    public static func describeGateState(enabled: Bool, approved: Bool) -> String {
        if !enabled {
            return "OFF (默认关闭)"
        }
        return approved ? "ON (已审批)" : "ON (未审批阻断)"
    }

    public static func describeSurfaceTitle(_ surface: UIReadinessFlowSurface) -> String {
        switch surface {
        case .projectEditor:
            return "创作者工程编辑器 (Project Editor)"
        case .profileSelfEdit:
            return "个人资料编辑页 (Profile Self Edit)"
        case .roamFinishedHistory:
            return "漫游历史完成列表 (Roam Finished History)"
        case .couponRuntimeJourney:
            return "卡券核销运行态链路 (Coupon Runtime Journey)"
        case .mapCoreEntry:
            return "地图核心入口中枢 (Map Core Entry)"
        }
    }

    public static func describeReadinessBadge(
        _ evaluation: UIReadinessAnchorContract.ReadinessEvaluation
    ) -> String {
        switch evaluation {
        case .ready:
            return "已就绪 (READY)"
        case .missingAnchors(let missing):
            return "待挂载 (\(missing.count))"
        case .awaitingOffScreenReveal:
            return "待滚动显露"
        }
    }

    public static func describeReadinessDetail(
        _ evaluation: UIReadinessAnchorContract.ReadinessEvaluation
    ) -> String {
        switch evaluation {
        case .ready:
            return "当前页面所有必需无障碍锚点已挂载且可交互"
        case .missingAnchors(let missing):
            return "尚未挂载锚点: \(missing.joined(separator: ", "))"
        case .awaitingOffScreenReveal(let helper, let targetAnchor):
            return "主锚点 \(targetAnchor) 位于折叠表单下方，交互前需执行 \(helper)"
        }
    }
}
