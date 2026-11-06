import SwiftUI

/// Reform plan v9 §28 (W19.3–W19.6) and §29–35 (W20.1–W20.4, W20.11–W20.16):
/// SwiftUI section view rendering `HomeReturnAndCityDeltaCoordinator` state
/// (`HomeReturnRestoreCoordinator` phase/failure/cooldown/scope and
/// `CityActionAndDeltaCoordinator` board lifecycle, quote/consent phase, and delta stream cursor).
/// Uses `Text(verbatim:)` throughout so zero `.xcstrings` keys are introduced, and never
/// displays or exports private-home location fixes.
@MainActor public struct HomeReturnAndCityDeltaSectionView: View {
    public let coordinator: HomeReturnAndCityDeltaCoordinator

    public init(coordinator: HomeReturnAndCityDeltaCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            homeReturnCard(coordinator.homeReturn)
            cityDeltaCard(coordinator.city)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reformWorld.homeReturnAndCityDelta.section")
    }

    // MARK: - W19 Private Base Return & Restore Section

    @ViewBuilder
    private func homeReturnCard(_ homeReturn: HomeReturnRestoreCoordinator) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "私人据点返家恢复（W19）")
                .font(.headline)
                .accessibilityIdentifier("homeReturn.section.title")

            labeledRow(
                label: "当前状态",
                value: homePhaseSummary(homeReturn.phase),
                identifier: "homeReturn.section.phase"
            )

            if let scope = activeHomeScope(homeReturn) {
                labeledRow(
                    label: "恢复范围",
                    value: homeScopeDescription(scope),
                    identifier: "homeReturn.section.scope"
                )
            }

            switch homeReturn.phase {
            case .preflightReady(let check):
                labeledRow(
                    label: "预检请求",
                    value: "\(check.requestId) · 策略 \(check.policyVersion) · 据点 v\(check.homeVersion)",
                    identifier: "homeReturn.section.preflight"
                )
            case .proofVerified(let proof):
                labeledRow(
                    label: "单次凭证",
                    value: "\(proof.proofId) · 据点 v\(proof.homeVersion)",
                    identifier: "homeReturn.section.proof"
                )
            case .restoring(let request):
                labeledRow(
                    label: "恢复请求",
                    value: "\(request.requestId) · 凭证 \(request.proofId) · 账户 v\(request.expectedAccountVersion)",
                    identifier: "homeReturn.section.restoring"
                )
            case .restored(let current, let maximum, let accountVersion, _):
                labeledRow(
                    label: "恢复结果",
                    value: "\(current) / \(maximum)（账户 v\(accountVersion)）",
                    identifier: "homeReturn.section.restored"
                )
            case .disabled, .idle, .failed:
                EmptyView()
            }

            if let failurePresentation = currentFailurePresentation(homeReturn) {
                homeFailureBox(failurePresentation)
            }

            Text(verbatim: "说明：仅支持手动触发返家核验，不后台采样位置，私人据点位置已脱敏。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("homeReturn.section.privacyNote")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeReturn.section.card")
    }

    @ViewBuilder
    private func homeFailureBox(_ presentation: HomeReturnFailurePresentation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            labeledRow(
                label: "未通过原因",
                value: homeFailureDescription(presentation.failure),
                identifier: "homeReturn.section.failure"
            )
            if let seconds = presentation.retryAfterSeconds {
                labeledRow(
                    label: "冷却等待",
                    value: "\(seconds) 秒后可再次核验",
                    identifier: "homeReturn.section.cooldown"
                )
            }
            labeledRow(
                label: "后续处理",
                value: homeFailureActionGuidance(presentation),
                identifier: "homeReturn.section.failureGuidance"
            )
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeReturn.section.failureBox")
    }

    private func activeHomeScope(_ homeReturn: HomeReturnRestoreCoordinator) -> HomeResourceScope? {
        switch homeReturn.phase {
        case .preflightReady(let check):
            return check.scope
        case .proofVerified(let proof):
            return proof.scope
        case .restoring(let request):
            return request.scope
        case .restored(_, _, _, let scope):
            return scope
        case .failed(let presentation):
            return presentation.scope
        case .disabled, .idle:
            return homeReturn.pendingRequest?.scope
                ?? homeReturn.verifiedProof?.scope
                ?? homeReturn.activeCheck?.scope
                ?? homeReturn.lastFailure?.scope
        }
    }

    private func currentFailurePresentation(_ homeReturn: HomeReturnRestoreCoordinator) -> HomeReturnFailurePresentation? {
        if case .failed(let presentation) = homeReturn.phase {
            return presentation
        }
        return homeReturn.lastFailure
    }

    private func homePhaseSummary(_ phase: HomeReturnRestorePhase) -> String {
        switch phase {
        case .disabled:
            return "未开启（默认关闭）"
        case .idle:
            return "待发起返家核验"
        case .preflightReady:
            return "本地预检通过"
        case .proofVerified:
            return "服务端返家凭证已核验"
        case .restoring:
            return "正在执行资源恢复"
        case .restored(let current, let maximum, _, _):
            return "已恢复至服务端上限（\(current) / \(maximum)）"
        case .failed:
            return "核验或恢复未通过"
        }
    }

    private func homeScopeDescription(_ scope: HomeResourceScope) -> String {
        switch scope {
        case .global(let resourceType):
            return "全局资源（GLOBAL · \(resourceType)）"
        case .run(let runId, let resourceType):
            return "单局资源（RUN · \(runId) · \(resourceType)）"
        case .theme(let themeId, let resourceType):
            return "主题资源（THEME · \(themeId) · \(resourceType)）"
        }
    }

    private func homeFailureDescription(_ failure: HomeReturnFailure) -> String {
        switch failure {
        case .disabled:
            return "返家恢复功能未开启"
        case .locationOff:
            return "系统定位服务未开启"
        case .permissionDenied:
            return "未授予位置访问权限"
        case .lowAccuracy:
            return "当前定位精度不满足策略要求"
        case .staleFix:
            return "定位采样时间已过期"
        case .cooldown(let seconds):
            return "处于恢复冷却期（剩余 \(seconds) 秒）"
        case .outOfRadius:
            return "当前不在私人据点有效范围内"
        case .homeChanged:
            return "私人据点版本已变更，原凭证失效"
        case .proofExpired:
            return "单次返家凭证已过期"
        case .noHome:
            return "尚未设置有效的私人据点"
        case .network:
            return "网络通信异常"
        case .unknown:
            return "恢复结果未明，需回读收据确认"
        case .invalid:
            return "请求或收据校验未通过"
        }
    }

    private func homeFailureActionGuidance(_ presentation: HomeReturnFailurePresentation) -> String {
        if presentation.requiresSettingsAction {
            return "需在系统设置中开启定位服务并授权后再试"
        }
        if let seconds = presentation.retryAfterSeconds {
            return "请等待 \(seconds) 秒冷却结束后再发起"
        }
        if presentation.retryableNow {
            return "可立即重新发起核验或回读"
        }
        return "需重新核验据点状态后再试"
    }

    // MARK: - W20 Resident CITY Action & Delta Stream Section

    @ViewBuilder
    private func cityDeltaCard(_ city: CityActionAndDeltaCoordinator?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "常驻城市经营与增量同步（W20）")
                .font(.headline)
                .accessibilityIdentifier("cityDelta.section.title")

            if let city {
                cityBoardSummary(city)
                cityPhaseAndQuoteSummary(city)
                cityCursorSummary(city)
                if !city.challengeStates.isEmpty {
                    cityChallengesSummary(city)
                }
            } else {
                Text(verbatim: "当前未配置常驻城市棋盘实例")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("cityDelta.section.unconfigured")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cityDelta.section.card")
    }

    @ViewBuilder
    private func cityBoardSummary(_ city: CityActionAndDeltaCoordinator) -> some View {
        labeledRow(
            label: "棋盘名称",
            value: "\(city.board.title)（\(city.board.boardId)）",
            identifier: "cityDelta.section.board"
        )
        labeledRow(
            label: "棋盘生命周期",
            value: cityLifecycleDescription(city.lifecycle),
            identifier: "cityDelta.section.lifecycle"
        )
        labeledRow(
            label: "新动作准入",
            value: city.canAcceptNewActions ? "允许发起新动作" : "当前不可发起新动作",
            identifier: "cityDelta.section.canAcceptNewActions"
        )
        if let participation = city.participation {
            labeledRow(
                label: "参赛身份",
                value: "\(participation.participationId)（v\(participation.membershipVersion)）",
                identifier: "cityDelta.section.participation"
            )
        } else {
            labeledRow(
                label: "参赛身份",
                value: "未加入当前棋盘",
                identifier: "cityDelta.section.participation"
            )
        }
    }

    @ViewBuilder
    private func cityPhaseAndQuoteSummary(_ city: CityActionAndDeltaCoordinator) -> some View {
        labeledRow(
            label: "协调器阶段",
            value: cityPhaseDescription(city.phase),
            identifier: "cityDelta.section.phase"
        )

        if let quote = city.pendingQuote {
            VStack(alignment: .leading, spacing: 4) {
                labeledRow(
                    label: "待确认报价",
                    value: "\(quote.quoteId) · v\(quote.quoteVersion) · 动作 \(quote.action)",
                    identifier: "cityDelta.section.quoteId"
                )
                labeledRow(
                    label: "积分与行动消耗",
                    value: "会员积分 \(quote.memberPointsCost) · 行动点 \(quote.actionCost) · 规则 \(quote.ruleVersion)",
                    identifier: "cityDelta.section.quoteCost"
                )
                labeledRow(
                    label: "扣点确认状态",
                    value: cityConsentDescription(quote: quote, consent: city.confirmedConsent),
                    identifier: "cityDelta.section.quoteConsent"
                )
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("cityDelta.section.quoteBox")
        }

        if let inFlight = city.pendingAction.intent {
            labeledRow(
                label: "在途请求",
                value: "\(inFlight.kind.rawValue) · 目标 \(inFlight.targetId) · 回合 \(inFlight.roundSeq) · \(inFlight.requestId)",
                identifier: "cityDelta.section.inFlight"
            )
        }
    }

    @ViewBuilder
    private func cityCursorSummary(_ city: CityActionAndDeltaCoordinator) -> some View {
        let cursor = city.deltaStream.cursor
        VStack(alignment: .leading, spacing: 4) {
            labeledRow(
                label: "增量游标",
                value: "赛季 \(cursor.seasonId) · 棋盘 v\(cursor.boardVersion) · 序号 #\(cursor.sequence)",
                identifier: "cityDelta.section.cursor"
            )
            labeledRow(
                label: "规则版本",
                value: cursor.rulesReleaseId,
                identifier: "cityDelta.section.rulesRelease"
            )
            labeledRow(
                label: "最近应用增量",
                value: "\(city.lastAppliedDeltas.count) 条",
                identifier: "cityDelta.section.lastAppliedCount"
            )
            labeledRow(
                label: "快照同步状态",
                value: city.needsSnapshotReload ? "需重新拉取完整快照" : "增量流连续正常",
                identifier: "cityDelta.section.snapshotStatus"
            )
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cityDelta.section.cursorBox")
    }

    @ViewBuilder
    private func cityChallengesSummary(_ city: CityActionAndDeltaCoordinator) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "异步挑战状态")
                .font(.subheadline.bold())
            ForEach(city.challengeStates.keys.sorted(), id: \.self) { challengeId in
                if let state = city.challengeStates[challengeId] {
                    labeledRow(
                        label: challengeId,
                        value: state.rawValue,
                        identifier: "cityDelta.section.challenge.\(challengeId)"
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cityDelta.section.challenges")
    }

    private func cityLifecycleDescription(_ lifecycle: CityBoardLifecycle) -> String {
        switch lifecycle {
        case .draft:
            return "草稿（DRAFT · 不接受动作）"
        case .review:
            return "审核中（REVIEW · 不接受动作）"
        case .ready:
            return "待开放（READY · 不接受动作）"
        case .open:
            return "开放中（OPEN · 可接受新动作）"
        case .frozen:
            return "已冻结（FROZEN · 仅结算在途动作）"
        case .closing:
            return "收尾中（CLOSING · 仅结算在途动作）"
        case .closed:
            return "已关闭（CLOSED · 不接受动作）"
        case .archived:
            return "已归档（ARCHIVED · 不接受动作）"
        }
    }

    private func cityPhaseDescription(_ phase: CityCoordinatorPhase) -> String {
        switch phase {
        case .disabled:
            return "未开启（默认关闭）"
        case .idle:
            return "空闲待命"
        case .awaitingQuoteConfirmation(let quote):
            return "等待付款人本人确认报价（\(quote.quoteId)）"
        case .inFlight(let intent):
            return "动作执行中（\(intent.kind.rawValue)）"
        case .settled(let outcome):
            return cityOutcomeDescription(outcome)
        case .snapshotRequired:
            return "增量流断层，需重新拉取快照"
        }
    }

    private func cityOutcomeDescription(_ outcome: CityPendingAction.Outcome) -> String {
        switch outcome {
        case .applied(let version):
            return "动作已生效（棋盘 v\(version)）"
        case .alreadyApplied:
            return "动作此前已生效（不重复执行）"
        case .refresh(let taskAttemptKept):
            return taskAttemptKept ? "版本冲突需刷新（已完成任务进度保留）" : "版本冲突需刷新快照"
        case .requote:
            return "报价已变更，需重新获取并确认报价"
        case .rejected(let code):
            return "动作被拒绝（\(code)）"
        case .blocked(let code):
            return "当前点位暂停或受限（\(code)）"
        case .unknown:
            return "结果未明，需按原请求号回读收据"
        }
    }

    private func cityConsentDescription(quote: CityActionQuote, consent: CityPayerConsent?) -> String {
        if let consent, consent.quoteId == quote.quoteId, consent.quoteVersion == quote.quoteVersion {
            return "本人已确认（付款人 \(consent.payerMemberId) · 不扣除队友积分）"
        }
        return "待付款人 \(quote.payerMemberId) 本人确认（不扣除队友积分）"
    }

    // MARK: - Shared Row Helper

    @ViewBuilder
    private func labeledRow(label: String, value: String, identifier: String) -> some View {
        LabeledContent {
            Text(verbatim: value)
                .font(.footnote)
                .multilineTextAlignment(.trailing)
        } label: {
            Text(verbatim: label)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier(identifier)
    }
}
