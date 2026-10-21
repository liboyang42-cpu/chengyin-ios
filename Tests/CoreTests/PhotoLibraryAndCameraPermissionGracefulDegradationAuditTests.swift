import XCTest
@testable import QuestifyCore

final class PhotoLibraryAndCameraPermissionGracefulDegradationAuditTests: XCTestCase {
    func testCanonicalFlowsPassGracefulDegradationAudit() {
        let result = PhotoLibraryAndCameraPermissionGracefulDegradationAudit.evaluate()
        XCTAssertEqual(result.totalFlows, 4)
        XCTAssertEqual(result.compliantFlows, 4)
        XCTAssertTrue(result.isMediaPermissionGraceful)
        XCTAssertEqual(
            PhotoLibraryAndCameraPermissionGracefulDegradationAudit.canonicalFlows.map(\.id),
            [
                "avatar-and-profile-photo-picker",
                "publish-9grid-media-picker",
                "merchant-shop-apply-license-upload",
                "qr-scan-and-stamp-poster-save"
            ]
        )
    }

    func testFullLibraryPermissionOverreachIsDetected() {
        var flows = PhotoLibraryAndCameraPermissionGracefulDegradationAudit.canonicalFlows
        flows[1] = MediaCapturePermissionFlowCheck(
            id: "publish-9grid-media-picker",
            flowName: "广场九宫格图文发布选图",
            usesOutOfProcessPHPickerForSelection: false,
            handlesLimitedAndDeniedWithoutCrash: true,
            providesManualOrSettingsFallbackOnDenial: true
        )
        let result = PhotoLibraryAndCameraPermissionGracefulDegradationAudit.evaluate(flows: flows)
        XCTAssertFalse(result.isMediaPermissionGraceful)
        XCTAssertEqual(result.compliantFlows, 3)
    }

    func testUngracefulLimitedOrDeniedHandlingIsDetected() {
        let ungraceful = MediaCapturePermissionFlowCheck(
            id: "qr-scan-and-stamp-poster-save",
            flowName: "二维码扫码与印章海报保存",
            usesOutOfProcessPHPickerForSelection: true,
            handlesLimitedAndDeniedWithoutCrash: false,
            providesManualOrSettingsFallbackOnDenial: true
        )
        XCTAssertFalse(ungraceful.isCompliant)
        let result = PhotoLibraryAndCameraPermissionGracefulDegradationAudit.evaluate(flows: [ungraceful])
        XCTAssertFalse(result.isMediaPermissionGraceful)
        XCTAssertEqual(result.compliantFlows, 0)
    }

    func testMissingManualOrSettingsFallbackOnDenialIsDetected() {
        let missingFallback = MediaCapturePermissionFlowCheck(
            id: "qr-scan-and-stamp-poster-save",
            flowName: "二维码扫码与印章海报保存",
            usesOutOfProcessPHPickerForSelection: true,
            handlesLimitedAndDeniedWithoutCrash: true,
            providesManualOrSettingsFallbackOnDenial: false
        )
        XCTAssertFalse(missingFallback.isCompliant)
        let result = PhotoLibraryAndCameraPermissionGracefulDegradationAudit.evaluate(flows: [missingFallback])
        XCTAssertFalse(result.isMediaPermissionGraceful)
        XCTAssertEqual(result.compliantFlows, 0)
    }
}
