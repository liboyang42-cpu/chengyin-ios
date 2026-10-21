import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif
#else
@testable import Questify
#endif

@MainActor
final class PlayRuntimeAndAuxiliaryBindingSectionViewTests: XCTestCase {
    func testCompliantSampleSnapshotCoversAllFivePlayRuntimePillars() {
        let snapshot = PlayRuntimeAndAuxiliaryBindingSnapshot.compliantSample
        XCTAssertTrue(snapshot.isAllCompliant)
        XCTAssertEqual(snapshot.verifiedRowCount, 5)
        XCTAssertEqual(snapshot.rows.map(\.kind), PlayRuntimeAuditPillarRow.PillarKind.allCases)

        let view = PlayRuntimeAndAuxiliaryBindingSectionView(snapshot: snapshot)
        XCTAssertEqual(
            PlayRuntimeAndAuxiliaryBindingSectionView.overallStatusText(for: snapshot),
            "整体状态：五大游玩运行态与权威状态支柱全部达标（5/5）"
        )
        XCTAssertEqual(
            PlayRuntimeAndAuxiliaryBindingSectionView.lifecycleStatusText(for: snapshot),
            "w2-11 游玩生命周期：章节推进与服务端回读已对齐"
        )
        XCTAssertEqual(
            PlayRuntimeAndAuxiliaryBindingSectionView.idempotencyStatusText(for: snapshot),
            "I01 节点提交幂等：requestId 锁定与防重放已启用"
        )
        XCTAssertEqual(
            PlayRuntimeAndAuxiliaryBindingSectionView.auxiliaryBindingStatusText(for: snapshot),
            "I02 辅助传感器边界：步数仅作参考且不解锁奖励已核验"
        )
        XCTAssertEqual(
            PlayRuntimeAndAuxiliaryBindingSectionView.pauseRecoveryStatusText(for: snapshot),
            "I09 暂停与恢复：前后台冻结与权威快照重读已核验"
        )
        XCTAssertEqual(
            PlayRuntimeAndAuxiliaryBindingSectionView.runAuthorityStatusText(for: snapshot),
            "H-W03 权威进度 CAS：expectedStateVersion 与恢复日志已核验"
        )
        _ = view.body
    }

    func testUnverifiedAuxiliaryBindingOrRunAuthorityFailsClosed() {
        let rows: [PlayRuntimeAuditPillarRow] = [
            PlayRuntimeAuditPillarRow(
                kind: .w211PlaySessionLifecycle,
                title: "w2-11 游玩运行态与章节推进对齐",
                summary: "已核验",
                verificationEvidence: "OK",
                isVerified: true
            ),
            PlayRuntimeAuditPillarRow(
                kind: .i01NodeSubmissionIdempotency,
                title: "I01 节点提交幂等与防重放锁定",
                summary: "已核验",
                verificationEvidence: "OK",
                isVerified: true
            ),
            PlayRuntimeAuditPillarRow(
                kind: .i02AuxiliarySensorNonProof,
                title: "I02 步数/传感器辅助绑定（非通关证明）",
                summary: "未声明非证明约束",
                verificationEvidence: "missing-disclaimer",
                isVerified: false
            ),
            PlayRuntimeAuditPillarRow(
                kind: .i09PauseClockAndRecovery,
                title: "I09 暂停计时、前后台切换与冷启动恢复",
                summary: "已核验",
                verificationEvidence: "OK",
                isVerified: true
            ),
            PlayRuntimeAuditPillarRow(
                kind: .hW03RunAuthorityCasAndJournal,
                title: "H-W03 权威进度 CAS 版本校验与恢复日志",
                summary: "缺少 CAS 冲突处理",
                verificationEvidence: "missing-cas",
                isVerified: false
            )
        ]

        let nonCompliant = PlayRuntimeAndAuxiliaryBindingSnapshot(
            playSessionLifecycleParityVerified: true,
            nodeSubmissionIdempotencyVerified: true,
            auxiliaryStepAndAudioBoundAsNonProof: false,
            pauseClockAndRelaunchRecoveryVerified: true,
            runAuthorityCasAndJournalVerified: false,
            rows: rows
        )
        XCTAssertFalse(nonCompliant.isAllCompliant)
        XCTAssertEqual(nonCompliant.verifiedRowCount, 3)
        XCTAssertEqual(
            PlayRuntimeAndAuxiliaryBindingSectionView.overallStatusText(for: nonCompliant),
            "整体状态：存在未达标的游玩运行态或权威状态支柱（3/5）"
        )
        XCTAssertEqual(
            PlayRuntimeAndAuxiliaryBindingSectionView.auxiliaryBindingStatusText(for: nonCompliant),
            "I02 辅助传感器边界：存在将步数视为证明的风险"
        )
        XCTAssertEqual(
            PlayRuntimeAndAuxiliaryBindingSectionView.runAuthorityStatusText(for: nonCompliant),
            "H-W03 权威进度 CAS：expectedStateVersion 或恢复日志未就绪"
        )

        let view = PlayRuntimeAndAuxiliaryBindingSectionView(snapshot: nonCompliant)
        _ = view.body
    }

    func testEmptyRowsSnapshotIsNotCompliantAndRendersEmptyState() {
        let emptySnapshot = PlayRuntimeAndAuxiliaryBindingSnapshot(
            playSessionLifecycleParityVerified: true,
            nodeSubmissionIdempotencyVerified: true,
            auxiliaryStepAndAudioBoundAsNonProof: true,
            pauseClockAndRelaunchRecoveryVerified: true,
            runAuthorityCasAndJournalVerified: true,
            rows: []
        )
        XCTAssertFalse(emptySnapshot.isAllCompliant)
        XCTAssertEqual(emptySnapshot.verifiedRowCount, 0)

        let view = PlayRuntimeAndAuxiliaryBindingSectionView(snapshot: emptySnapshot)
        XCTAssertTrue(view.snapshot.rows.isEmpty)
        _ = view.body
    }
}
