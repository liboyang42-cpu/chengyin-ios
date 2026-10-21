import XCTest
@testable import QuestifyCore

final class WeChatShareCardAndPosterExportParityAuditTests: XCTestCase {

    func testCanonicalSurfacesPassSharePosterParityAudit() {
        let surfaces = WeChatShareCardAndPosterExportParityAudit.canonicalSurfaces
        XCTAssertEqual(surfaces.count, 4)
        XCTAssertEqual(
            surfaces.map(\.surfaceName),
            [
                "roam-share-snapshot-reader",
                "passport-stamp-unlock-poster",
                "exploration-monthly-recap-card",
                "club-activity-invite-poster"
            ]
        )

        let result = WeChatShareCardAndPosterExportParityAudit.evaluate()
        XCTAssertEqual(result.totalSurfaces, 4)
        XCTAssertEqual(result.compliantSurfaces, 4)
        XCTAssertTrue(result.isSharePosterReady)
    }

    func testConflating404GoneWith503ServerErrorIsRejected() {
        let conflatedReader = SharePosterSurfaceCheck(
            surfaceName: "roam-share-snapshot-reader",
            separates404GoneFrom503ServerError: false,
            rendersHighResolutionPosterLocally: true,
            embedsVerifiedShareQRCode: true
        )
        XCTAssertFalse(conflatedReader.isCompliant)

        let eval = WeChatShareCardAndPosterExportParityAudit.evaluate(surfaces: [conflatedReader])
        XCTAssertEqual(eval.totalSurfaces, 1)
        XCTAssertEqual(eval.compliantSurfaces, 0)
        XCTAssertFalse(eval.isSharePosterReady)

        XCTAssertEqual(WeChatShareCardAndPosterExportParityAudit.classifySnapshotResponse(statusCode: 200), .ready)
        XCTAssertEqual(WeChatShareCardAndPosterExportParityAudit.classifySnapshotResponse(statusCode: 404), .gone)
        XCTAssertEqual(WeChatShareCardAndPosterExportParityAudit.classifySnapshotResponse(statusCode: 410), .gone)
        XCTAssertEqual(WeChatShareCardAndPosterExportParityAudit.classifySnapshotResponse(statusCode: 503), .serverError)
    }

    func testLowResolutionOrBrokenPosterRenderingIsDetectedAndRejected() {
        let lowResPoster = SharePosterSurfaceCheck(
            surfaceName: "passport-stamp-unlock-poster",
            separates404GoneFrom503ServerError: true,
            rendersHighResolutionPosterLocally: false,
            embedsVerifiedShareQRCode: true
        )
        XCTAssertFalse(lowResPoster.isCompliant)
        XCTAssertFalse(
            WeChatShareCardAndPosterExportParityAudit.evaluate(surfaces: [lowResPoster]).isSharePosterReady
        )
        XCTAssertFalse(WeChatShareCardAndPosterExportParityAudit.isHighResolutionScale(1.0))
        XCTAssertFalse(WeChatShareCardAndPosterExportParityAudit.isHighResolutionScale(2.0))
        XCTAssertTrue(WeChatShareCardAndPosterExportParityAudit.isHighResolutionScale(3.0))
    }

    func testMissingVerifiedShareQRCodeEmbeddingIsDetectedAndRejected() {
        let missingQRPoster = SharePosterSurfaceCheck(
            surfaceName: "club-activity-invite-poster",
            separates404GoneFrom503ServerError: true,
            rendersHighResolutionPosterLocally: true,
            embedsVerifiedShareQRCode: false
        )
        XCTAssertFalse(missingQRPoster.isCompliant)

        let eval = WeChatShareCardAndPosterExportParityAudit.evaluate(
            surfaces: [
                WeChatShareCardAndPosterExportParityAudit.canonicalSurfaces[0],
                missingQRPoster
            ]
        )
        XCTAssertEqual(eval.totalSurfaces, 2)
        XCTAssertEqual(eval.compliantSurfaces, 1)
        XCTAssertFalse(eval.isSharePosterReady)
    }
}
