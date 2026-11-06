import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class RoamSubpagePresentationTests: XCTestCase {
    func testRoamLiveMomentShareTokenAndPOIMediaParity() throws {
        // 1. RoamLiveMomentFeedState & RoamNearbyDistanceCopy
        XCTAssertEqual(RoamLiveMomentFeedState.resolve(nil), .hiddenWhenEmpty)
        XCTAssertEqual(RoamLiveMomentFeedState.resolve([]), .hiddenWhenEmpty)
        let embeddedCredMoment = "https://" + "u:p@" + "cdn.example.com/moment2.jpg"
        XCTAssertEqual(
            RoamLiveMomentFeedState.resolve([
                "http://insecure.example.com/moment1.jpg",
                embeddedCredMoment,
                "   ",
                "https://cdn.example.com/moments/valid-1.jpg",
                "https://cdn.example.com/moments/valid-1.jpg",
                "https://cdn.example.com/moments/valid-2.jpg"
            ]),
            .moments([
                "https://cdn.example.com/moments/valid-1.jpg",
                "https://cdn.example.com/moments/valid-2.jpg"
            ])
        )
        XCTAssertEqual(RoamNearbyDistanceCopy.prefix(usesManualArea: true), "距所选地点")
        XCTAssertEqual(RoamNearbyDistanceCopy.prefix(usesManualArea: false), "距当前位置")
        XCTAssertEqual(RoamNearbyDistanceCopy.label(usesManualArea: true, distanceKilometers: 1.5), "距所选地点 1.5km")
        XCTAssertEqual(RoamNearbyDistanceCopy.label(usesManualArea: false, distanceKilometers: 0.8), "距当前位置 0.8km")

        // 2. RoamShareTokenValidator
        let validHex = String(repeating: "01", count: 8) + String(repeating: "AB", count: 4) + String(repeating: "cd", count: 4)
        let expectedLowerHex = validHex.lowercased()
        let validated = RoamShareTokenValidator.validate(validHex)
        XCTAssertEqual(validated.normalizedToken?.rawValue, expectedLowerHex)
        XCTAssertNotNil(validated.normalizedToken?.shareToken)
        XCTAssertNil(validated.errorMessage)

        let urlValidated = RoamShareTokenValidator.validate(
            url: URL(string: "https://example.com/roam/session?shareToken=\(validHex)")!
        )
        XCTAssertEqual(urlValidated, validated)

        for invalidRaw in ["", "short", String(repeating: "01", count: 15) + "0g"] {
            let invalid = RoamShareTokenValidator.validate(invalidRaw)
            XCTAssertEqual(invalid, .invalidToken)
            XCTAssertEqual(invalid.errorMessage, "分享链接无效或已过期")
        }

        // 3. RoamPOIMediaPresentation
        let embeddedCredLogo = "https://" + "u:p@" + "cdn.example.com/logo.png"
        let emptyMedia = RoamPOIMediaPresentation(
            coverUrl: "http://insecure.example.com/cover.jpg",
            logoUrl: embeddedCredLogo
        )
        XCTAssertNil(emptyMedia.coverUrl)
        XCTAssertNil(emptyMedia.logoUrl)
        XCTAssertEqual(emptyMedia.fallbackTitle, "据点实景待补充")
        XCTAssertEqual(emptyMedia.placeholderTitle, "据点实景待补充")

        let validMedia = RoamPOIMediaPresentation(
            coverUrl: " https://cdn.example.com/poi/cover.jpg ",
            logoUrl: "https://cdn.example.com/poi/logo.png"
        )
        XCTAssertEqual(validMedia.coverUrl, "https://cdn.example.com/poi/cover.jpg")
        XCTAssertEqual(validMedia.logoUrl, "https://cdn.example.com/poi/logo.png")
        XCTAssertNil(validMedia.placeholderTitle)
    }
}
