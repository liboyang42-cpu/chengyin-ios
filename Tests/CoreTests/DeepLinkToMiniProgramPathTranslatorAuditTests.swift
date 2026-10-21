import XCTest
@testable import QuestifyCore

final class DeepLinkToMiniProgramPathTranslatorAuditTests: XCTestCase {
    func testCanonicalFiveRouteMappingsAreCompliantAndReady() {
        let result = DeepLinkToMiniProgramPathTranslatorAudit.evaluate()
        XCTAssertEqual(result.totalMappings, 5)
        XCTAssertEqual(result.compliantMappings, 5)
        XCTAssertTrue(result.isPathTranslatorReady)
        XCTAssertEqual(
            DeepLinkToMiniProgramPathTranslatorAudit.canonicalMappings.map(\.miniProgramPath),
            [
                "pages/roam/index",
                "pages/merchant/store/index",
                "pages/club/detail/index",
                "pages/play/index",
                "pages/coop/list/index"
            ]
        )
        XCTAssertEqual(
            DeepLinkToMiniProgramPathTranslatorAudit.requiredPreservedQueryKeys,
            ["cityCode", "merchantId", "clubId", "projectId", "topicId"]
        )
    }

    func testQueryParameterLossIsDetected() {
        var mappings = DeepLinkToMiniProgramPathTranslatorAudit.canonicalMappings
        mappings[0] = MiniProgramPathRouteMapping(
            id: "route-roam-index",
            miniProgramPath: "pages/roam/index",
            nativeUniversalLinkPath: "/roam",
            preservesQueryParametersLosslessly: false,
            rejectsUnknownOrUnallowedHost: true
        )
        let result = DeepLinkToMiniProgramPathTranslatorAudit.evaluate(mappings: mappings)
        XCTAssertFalse(result.isPathTranslatorReady)
        XCTAssertEqual(result.compliantMappings, 4)
    }

    func testUnallowedHostAcceptanceIsDetected() {
        let unsafeHostMapping = MiniProgramPathRouteMapping(
            id: "route-merchant-store",
            miniProgramPath: "pages/merchant/store/index",
            nativeUniversalLinkPath: "/merchant/store",
            preservesQueryParametersLosslessly: true,
            rejectsUnknownOrUnallowedHost: false
        )
        XCTAssertFalse(unsafeHostMapping.isCompliant)
        let result = DeepLinkToMiniProgramPathTranslatorAudit.evaluate(mappings: [unsafeHostMapping])
        XCTAssertFalse(result.isPathTranslatorReady)
        XCTAssertEqual(result.compliantMappings, 0)
    }

    func testEmptyPathsOrEmptyMappingListAreRejected() {
        let blankMiniProgramPath = MiniProgramPathRouteMapping(
            id: "route-blank-mp",
            miniProgramPath: "   ",
            nativeUniversalLinkPath: "/play"
        )
        XCTAssertFalse(blankMiniProgramPath.isCompliant)

        let blankNativePath = MiniProgramPathRouteMapping(
            id: "route-blank-native",
            miniProgramPath: "pages/play/index",
            nativeUniversalLinkPath: ""
        )
        XCTAssertFalse(blankNativePath.isCompliant)

        let emptyListResult = DeepLinkToMiniProgramPathTranslatorAudit.evaluate(mappings: [])
        XCTAssertEqual(emptyListResult.totalMappings, 0)
        XCTAssertFalse(emptyListResult.isPathTranslatorReady)
    }
}
