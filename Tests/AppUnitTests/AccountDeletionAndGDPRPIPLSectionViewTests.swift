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
final class AccountDeletionAndGDPRPIPLSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotPassesGuideline511vAndPIPLChecks() {
        let snapshot = AccountDeletionPIPLSnapshot.defaultReady
        XCTAssertTrue(snapshot.isAllCompliant)
        XCTAssertEqual(snapshot.compliantRowCount, 4)
        XCTAssertTrue(snapshot.rows.allSatisfy(\.isStepCompliant))

        XCTAssertEqual(
            AccountDeletionAndGDPRPIPLSectionView.overallStatusText(for: snapshot),
            "整体状态：Guideline 5.1.1(v) 与 GDPR / PIPL 注销闭环全部合规（4/4）"
        )
        XCTAssertEqual(
            AccountDeletionAndGDPRPIPLSectionView.entryStatusText(for: snapshot),
            "注销入口合规：App 内 AccountCancelView 可直接发起，无强制人工客服门槛"
        )
        XCTAssertEqual(
            AccountDeletionAndGDPRPIPLSectionView.precheckStatusText(for: snapshot),
            "资产与订单预检：未完结订单、钱包余额与俱乐部职责核验已启用"
        )
        XCTAssertEqual(
            AccountDeletionAndGDPRPIPLSectionView.localPurgeStatusText(for: snapshot),
            "本地数据销毁：Keychain 令牌、Session Realm 与本地缓存即时抹除已核验"
        )
    }

    func testGuideline511vViolationOrMissingLocalPurgeTriggersWarningState() {
        var rows = AccountDeletionPIPLSnapshot.defaultReady.rows
        rows[0] = AccountDeletionStepRow(
            id: "in-app-entry-account-cancel-view",
            stepTitle: "1. App 内置账号注销入口 (w2-01 AccountCancelView)",
            inAppDirectExecution: false,
            checksUnsettledOrdersAndWallet: true,
            purgesKeychainAndLocalStoresImmediately: false,
            summary: "违规配置：仅提供拨打客服电话入口且未清除本地 Keychain"
        )
        XCTAssertFalse(rows[0].isStepCompliant)

        let warningSnapshot = AccountDeletionPIPLSnapshot(
            guideline511vInAppEntryAvailable: false,
            unsettledOrderAndWalletPrecheckEnabled: false,
            immediateKeychainAndLocalPurgeVerified: false,
            noCustomerServiceCallRequiredForDeletion: false,
            rows: rows
        )
        XCTAssertFalse(warningSnapshot.isAllCompliant)
        XCTAssertEqual(warningSnapshot.compliantRowCount, 3)
        XCTAssertEqual(
            AccountDeletionAndGDPRPIPLSectionView.overallStatusText(for: warningSnapshot),
            "整体状态：检测到违反 Guideline 5.1.1(v) 或数据清除不完整的风险（3/4）"
        )
        XCTAssertEqual(
            AccountDeletionAndGDPRPIPLSectionView.entryStatusText(for: warningSnapshot),
            "注销入口告警：缺少 App 内置注销入口或存在人工客服阻断"
        )
        XCTAssertEqual(
            AccountDeletionAndGDPRPIPLSectionView.precheckStatusText(for: warningSnapshot),
            "资产与订单预检：未完结订单或钱包预检未启用"
        )
        XCTAssertEqual(
            AccountDeletionAndGDPRPIPLSectionView.localPurgeStatusText(for: warningSnapshot),
            "本地数据销毁：Keychain 或本地缓存存在残留风险"
        )
    }

    func testMainActorViewBodyInstantiationForReadyAndEmptySnapshots() {
        let readyView = AccountDeletionAndGDPRPIPLSectionView(snapshot: .defaultReady)
        XCTAssertEqual(readyView.snapshot.rows.count, 4)
        _ = readyView.body

        let emptySnapshot = AccountDeletionPIPLSnapshot(
            guideline511vInAppEntryAvailable: true,
            unsettledOrderAndWalletPrecheckEnabled: true,
            immediateKeychainAndLocalPurgeVerified: true,
            noCustomerServiceCallRequiredForDeletion: true,
            rows: []
        )
        XCTAssertFalse(emptySnapshot.isAllCompliant)
        let emptyView = AccountDeletionAndGDPRPIPLSectionView(snapshot: emptySnapshot)
        XCTAssertTrue(emptyView.snapshot.rows.isEmpty)
        _ = emptyView.body
    }
}
