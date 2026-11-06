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
final class NativeSupersetOverMiniProgramSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotCoversAllSixNativeSupersetDomains() {
        let snapshot = NativeSupersetPolicySnapshot.defaultReady
        XCTAssertTrue(snapshot.isSupersetIntact)
        XCTAssertTrue(snapshot.backendContractParityAligned)
        XCTAssertTrue(snapshot.coversAllSixDomains)
        XCTAssertEqual(snapshot.preservedCount, 6)
        XCTAssertEqual(snapshot.downgradedCount, 0)
        XCTAssertEqual(snapshot.rows.map(\.id), [
            "mapkit-3d-and-fog",
            "durable-encrypted-journal",
            "native-audio-and-tts",
            "storekit2-commerce",
            "ossignposter-60fps",
            "reform-v9-host-bridges"
        ])
        XCTAssertEqual(snapshot.summaryText, "原生超集保留 6/6 · 降级告警 0 · 接口契约 100% 对齐")
    }

    func testDowngradeWarningStateMarksSnapshotNotIntact() {
        var rows = NativeSupersetPolicySnapshot.defaultReady.rows
        rows[0] = NativeSupersetDomainRow(
            id: "mapkit-3d-and-fog",
            domain: .mapKit3DAndFog,
            title: "MapKit 3D 与个人迷雾矢量渲染",
            miniProgramContract: "api/roam/tiles/page",
            nativeSupersetCapability: "被误降级为静态切片",
            status: .downgradedWarning
        )
        let snapshot = NativeSupersetPolicySnapshot(
            backendContractParityAligned: true,
            rows: rows
        )
        XCTAssertFalse(snapshot.isSupersetIntact)
        XCTAssertEqual(snapshot.preservedCount, 5)
        XCTAssertEqual(snapshot.downgradedCount, 1)
        XCTAssertEqual(rows[0].badgeText, "DOWNGRADED")
        XCTAssertEqual(snapshot.summaryText, "原生超集保留 5/6 · 降级告警 1 · 接口契约 100% 对齐")
    }

    func testViewInstantiatesAndEvaluatesBodyOnMainActor() {
        let view = NativeSupersetOverMiniProgramSectionView()
        _ = view.body
        XCTAssertEqual(view.snapshot, .defaultReady)
        XCTAssertTrue(view.snapshot.isSupersetIntact)
    }
}
