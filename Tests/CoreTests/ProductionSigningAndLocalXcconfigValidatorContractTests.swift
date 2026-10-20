import XCTest
@testable import QuestifyCore

final class ProductionSigningAndLocalXcconfigValidatorContractTests: XCTestCase {

    func testCanonicalFiveCoordinatesPassSigningValidatorAudit() {
        let coordinates = ProductionSigningAndLocalXcconfigValidatorContract.canonicalCoordinates
        XCTAssertEqual(coordinates.count, 5)
        XCTAssertEqual(
            coordinates.map(\.keyName),
            [
                "CODE_SIGNING_ALLOWED",
                "DEVELOPMENT_TEAM",
                "PRODUCT_BUNDLE_IDENTIFIER",
                "QUESTIFY_API_BASE_URL",
                "QUESTIFY_MARKET_AND_REALM"
            ]
        )

        let result = ProductionSigningAndLocalXcconfigValidatorContract.evaluate()
        XCTAssertEqual(result.totalCoordinates, 5)
        XCTAssertEqual(result.compliantCoordinates, 5)
        XCTAssertTrue(result.isSigningValidatorReady)
    }

    func testUnsafeBaseDefaultIsDetectedAndRejected() {
        let unsafeBase = XcconfigSigningCoordinateCheck(
            keyName: "QUESTIFY_API_BASE_URL",
            baseDefaultIsFailClosedSafe: false,
            validatesNonPlaceholderInReleaseArchive: true,
            blocksLegacyMiniProgramHostInRelease: true
        )
        XCTAssertFalse(unsafeBase.isCompliant)

        let eval = ProductionSigningAndLocalXcconfigValidatorContract.evaluate(coordinates: [unsafeBase])
        XCTAssertEqual(eval.totalCoordinates, 1)
        XCTAssertEqual(eval.compliantCoordinates, 0)
        XCTAssertFalse(eval.isSigningValidatorReady)
    }

    func testPlaceholderBundleOrTeamIDInReleaseArchiveIsRejected() {
        let unvalidatedArchiveCoord = XcconfigSigningCoordinateCheck(
            keyName: "PRODUCT_BUNDLE_IDENTIFIER",
            baseDefaultIsFailClosedSafe: true,
            validatesNonPlaceholderInReleaseArchive: false,
            blocksLegacyMiniProgramHostInRelease: true
        )
        XCTAssertFalse(unvalidatedArchiveCoord.isCompliant)
        XCTAssertFalse(
            ProductionSigningAndLocalXcconfigValidatorContract.evaluate(coordinates: [unvalidatedArchiveCoord]).isSigningValidatorReady
        )

        XCTAssertFalse(
            ProductionSigningAndLocalXcconfigValidatorContract.isValidReleaseBundleIdentifier("invalid.example.questify.ios")
        )
        XCTAssertFalse(
            ProductionSigningAndLocalXcconfigValidatorContract.isValidReleaseBundleIdentifier("com.example.questify")
        )
        XCTAssertTrue(
            ProductionSigningAndLocalXcconfigValidatorContract.isValidReleaseBundleIdentifier("com.chengyin.questify")
        )

        XCTAssertFalse(ProductionSigningAndLocalXcconfigValidatorContract.isValidDevelopmentTeam(""))
        XCTAssertFalse(ProductionSigningAndLocalXcconfigValidatorContract.isValidDevelopmentTeam("short"))
        XCTAssertTrue(ProductionSigningAndLocalXcconfigValidatorContract.isValidDevelopmentTeam("9A8B7C6D5E"))
    }

    func testLegacyMiniProgramHostAndNonHTTPSReleaseURLAreRejected() {
        let allowsLegacyHostCoord = XcconfigSigningCoordinateCheck(
            keyName: "QUESTIFY_API_BASE_URL",
            baseDefaultIsFailClosedSafe: true,
            validatesNonPlaceholderInReleaseArchive: true,
            blocksLegacyMiniProgramHostInRelease: false
        )
        XCTAssertFalse(allowsLegacyHostCoord.isCompliant)
        XCTAssertFalse(
            ProductionSigningAndLocalXcconfigValidatorContract.evaluate(coordinates: [allowsLegacyHostCoord]).isSigningValidatorReady
        )

        XCTAssertFalse(
            ProductionSigningAndLocalXcconfigValidatorContract.isAllowedReleaseAPIBaseURL("https://47.103.124.64")
        )
        XCTAssertFalse(
            ProductionSigningAndLocalXcconfigValidatorContract.isAllowedReleaseAPIBaseURL("http://api.chengyin.example")
        )
        XCTAssertTrue(
            ProductionSigningAndLocalXcconfigValidatorContract.isAllowedReleaseAPIBaseURL("https://api.chengyinhub.cn")
        )
    }
}
