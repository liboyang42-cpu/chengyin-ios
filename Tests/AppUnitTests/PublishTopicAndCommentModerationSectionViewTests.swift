import SwiftUI
import XCTest
#if canImport(QuestifyApp)
@testable import QuestifyApp
import QuestifyCore
#elseif canImport(Core)
@testable import Questify
import Core
#else
@testable import Questify
#endif

@MainActor
final class PublishTopicAndCommentModerationSectionViewTests: XCTestCase {

    func testDefaultReadySnapshotCompliance() {
        let snapshot = PublishTopicModerationSnapshot.defaultReady
        XCTAssertEqual(snapshot.nineGridMediaCount, 9)
        XCTAssertTrue(snapshot.isNineGridWithinLimit)
        XCTAssertTrue(snapshot.guideline12TermsAccepted)
        XCTAssertFalse(snapshot.hasActiveUgcViolationBanner)
        XCTAssertTrue(snapshot.isAppStoreGuideline12Compliant)
        XCTAssertEqual(snapshot.checks.count, 4)
        XCTAssertTrue(snapshot.checks.allSatisfy { $0.status == .passed })
    }

    func testUgcViolationBannerAndNineGridOverflowState() {
        let blockedRow = PublishModerationCheckRow(
            id: "comment-blocked",
            domainCode: "COMMENT_MOD",
            title: "敏感词命中",
            detail: "命中高危违规词库，已自动拦截并触发举报工单",
            status: .blocked
        )
        let violationSnapshot = PublishTopicModerationSnapshot(
            nineGridMediaCount: 12,
            guideline12TermsAccepted: false,
            hasActiveUgcViolationBanner: true,
            ugcViolationBannerText: "检测到违规内容，已拦截发布并冻结展示",
            checks: [blockedRow]
        )

        XCTAssertFalse(violationSnapshot.isNineGridWithinLimit)
        XCTAssertTrue(violationSnapshot.hasActiveUgcViolationBanner)
        XCTAssertFalse(violationSnapshot.isAppStoreGuideline12Compliant)
        XCTAssertEqual(blockedRow.statusBadgeText, "已拦截")
    }

    func testMainActorViewBodyInstantiation() {
        let readyView = PublishTopicAndCommentModerationSectionView(snapshot: .defaultReady)
        XCTAssertEqual(readyView.snapshot, .defaultReady)
        _ = readyView.body

        let warningRow = PublishModerationCheckRow(
            id: "w2-13-review",
            domainCode: "w2-13",
            title: "九宫格视频封面抽帧复核",
            detail: "等待人工审核确认",
            status: .warning
        )
        let warningSnapshot = PublishTopicModerationSnapshot(
            nineGridMediaCount: 6,
            hasActiveUgcViolationBanner: true,
            ugcViolationBannerText: "正在人工复核配图与评论内容",
            checks: [warningRow]
        )
        let warningView = PublishTopicAndCommentModerationSectionView(snapshot: warningSnapshot)
        XCTAssertEqual(warningRow.statusBadgeText, "待人工复核")
        _ = warningView.body
    }
}
