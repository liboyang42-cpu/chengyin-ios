import XCTest
@testable import QuestifyCore

final class AppStoreConnectMetadataAndScreenshotMatrixContractTests: XCTestCase {

    func testCanonicalRequirementsPassAppStoreConnectMetadataAudit() {
        let requirements = AppStoreConnectMetadataAndScreenshotMatrixContract.canonicalRequirements
        XCTAssertEqual(requirements.count, 4)
        XCTAssertEqual(
            requirements.map(\.id),
            [
                "iphone-69-and-65-screenshot-sets",
                "bilingual-store-listing-and-keywords",
                "privacy-policy-and-support-https-urls",
                "export-compliance-and-age-rating"
            ]
        )
        XCTAssertTrue(requirements.allSatisfy(\.isCompliant))

        let result = AppStoreConnectMetadataAndScreenshotMatrixContract.evaluate()
        XCTAssertEqual(result.totalRequirements, 4)
        XCTAssertEqual(result.compliantRequirements, 4)
        XCTAssertTrue(result.isASCMetadataReady)
    }

    func testMissingLocaleListingOrScreenshotSetIsRejected() {
        var requirements = AppStoreConnectMetadataAndScreenshotMatrixContract.canonicalRequirements
        requirements[1] = ASCMetadataRequirementCheck(
            id: "bilingual-store-listing-and-keywords",
            requirementName: "Bilingual Store Listing, Subtitle, Description & Keywords",
            isConfiguredForZhHansAndEnUS: false,
            usesHTTPSVerifiedURLs: true,
            declaresNonExemptEncryptionFalse: true
        )
        XCTAssertFalse(requirements[1].isCompliant)

        let result = AppStoreConnectMetadataAndScreenshotMatrixContract.evaluate(requirements: requirements)
        XCTAssertEqual(result.totalRequirements, 4)
        XCTAssertEqual(result.compliantRequirements, 3)
        XCTAssertFalse(result.isASCMetadataReady)
    }

    func testNonHTTPSSupportOrPrivacyPolicyURLIsRejected() {
        var requirements = AppStoreConnectMetadataAndScreenshotMatrixContract.canonicalRequirements
        requirements[2] = ASCMetadataRequirementCheck(
            id: "privacy-policy-and-support-https-urls",
            requirementName: "Verified HTTPS Support, Marketing & Privacy Policy URLs",
            isConfiguredForZhHansAndEnUS: true,
            usesHTTPSVerifiedURLs: false,
            declaresNonExemptEncryptionFalse: true
        )
        XCTAssertFalse(requirements[2].isCompliant)

        let result = AppStoreConnectMetadataAndScreenshotMatrixContract.evaluate(requirements: requirements)
        XCTAssertEqual(result.totalRequirements, 4)
        XCTAssertEqual(result.compliantRequirements, 3)
        XCTAssertFalse(result.isASCMetadataReady)
    }

    func testMissingExportComplianceDeclarationOrEmptyRequirementsIsRejected() {
        var requirements = AppStoreConnectMetadataAndScreenshotMatrixContract.canonicalRequirements
        requirements[3] = ASCMetadataRequirementCheck(
            id: "export-compliance-and-age-rating",
            requirementName: "Age Rating Questionnaire & ITSAppUsesNonExemptEncryption=false",
            isConfiguredForZhHansAndEnUS: true,
            usesHTTPSVerifiedURLs: true,
            declaresNonExemptEncryptionFalse: false
        )
        XCTAssertFalse(requirements[3].isCompliant)

        let result = AppStoreConnectMetadataAndScreenshotMatrixContract.evaluate(requirements: requirements)
        XCTAssertEqual(result.totalRequirements, 4)
        XCTAssertEqual(result.compliantRequirements, 3)
        XCTAssertFalse(result.isASCMetadataReady)

        let emptyResult = AppStoreConnectMetadataAndScreenshotMatrixContract.evaluate(requirements: [])
        XCTAssertEqual(emptyResult.totalRequirements, 0)
        XCTAssertEqual(emptyResult.compliantRequirements, 0)
        XCTAssertFalse(emptyResult.isASCMetadataReady)
    }
}
