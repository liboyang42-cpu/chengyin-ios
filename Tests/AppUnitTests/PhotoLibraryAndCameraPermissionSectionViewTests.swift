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
final class PhotoLibraryAndCameraPermissionSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotCoversPHPickerLimitedDegradationAndCameraFallback() {
        let snapshot = PhotoCameraPermissionSnapshot.defaultReady
        XCTAssertTrue(snapshot.isFullyReady)
        XCTAssertTrue(snapshot.usesOutOfProcessPHPicker)
        XCTAssertTrue(snapshot.supportsManualCodeAndAlbumFallbackOnCameraDenied)
        XCTAssertEqual(snapshot.readyCount, 3)
        XCTAssertEqual(snapshot.degradedCount, 0)
        XCTAssertEqual(snapshot.rows.map(\.id), [
            "phpicker-zero-permission",
            "limited-denied-degradation",
            "camera-manual-settings-fallback"
        ])
        XCTAssertEqual(snapshot.summaryText, "就绪 3/3 · 降级告警 0 · PHPicker 免权限 已启用")
    }

    func testPermissionDegradationWarningStateIsSurfaced() {
        var rows = PhotoCameraPermissionSnapshot.defaultReady.rows
        rows[2] = MediaPermissionFlowRow(
            id: "camera-manual-settings-fallback",
            kind: .cameraManualAndSettingsFallback,
            title: "相机扫码与拍照降级兜底",
            permissionPolicy: "相机权限被拒绝 (.denied)",
            fallbackMechanism: "已切换至手动输入核销码与系统设置引导",
            status: .degradedWarning
        )
        let snapshot = PhotoCameraPermissionSnapshot(
            usesOutOfProcessPHPicker: true,
            supportsManualCodeAndAlbumFallbackOnCameraDenied: true,
            rows: rows
        )
        XCTAssertFalse(snapshot.isFullyReady)
        XCTAssertEqual(snapshot.readyCount, 2)
        XCTAssertEqual(snapshot.degradedCount, 1)
        XCTAssertEqual(rows[2].badgeText, "DEGRADED")
        XCTAssertEqual(snapshot.summaryText, "就绪 2/3 · 降级告警 1 · PHPicker 免权限 已启用")
    }

    func testViewInstantiatesAndEvaluatesBodyOnMainActor() {
        let view = PhotoLibraryAndCameraPermissionSectionView()
        _ = view.body
        XCTAssertEqual(view.snapshot, .defaultReady)
        XCTAssertTrue(view.snapshot.isFullyReady)
    }
}
