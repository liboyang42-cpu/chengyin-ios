import XCTest
@testable import QuestifyCore

final class MapVisualStyleTokensTests: XCTestCase {
    func testCandidatePaletteIsMarkedCandidateAndComplete() {
        let manifest = MapVisualStyleManifest.candidate
        XCTAssertEqual(manifest.approval, .candidate)
        for appearance in MapAppearance.allCases {
            for role in MapSemanticRole.allCases { _ = manifest.color(role, appearance) }
        }
        XCTAssertEqual(manifest.color(.currentTargetRoute, .day), MapStyleColor(hex: "#006C70"))
        XCTAssertEqual(manifest.color(.currentTargetRoute, .night), MapStyleColor(hex: "#63D9D3"))
    }
    func testAppearanceFollowsSystemOnly() {
        XCTAssertEqual(MapAppearance.resolve(systemIsDark: true), .night)
        XCTAssertEqual(MapAppearance.resolve(systemIsDark: false), .day)
    }
    func testHexParsingRejectsMalformedValues() {
        for bad in ["", "#FFF", "#GGGGGG", "#1234567", "12345"] { XCTAssertNil(MapStyleColor(hex: bad), bad) }
        XCTAssertNil(MapStyleColor(hex: "#FFFFFF", opacity: 1.5))
        XCTAssertNil(MapStyleColor(hex: "#FFFFFF", opacity: .nan))
        XCTAssertNotNil(MapStyleColor(hex: "a0b1c2"))
    }
    func testContrastRatioMatchesWCAGExtremes() {
        let black = MapStyleColor(hex: "#000000")!, white = MapStyleColor(hex: "#FFFFFF")!
        XCTAssertEqual(MapStyleColor.contrastRatio(black, white), 21, accuracy: 0.01)
        XCTAssertEqual(MapStyleColor.contrastRatio(white, white), 1, accuracy: 0.0001)
    }
    func testCandidateTextAndRouteContrastArithmeticOnly() {
        // Arithmetic against the ground token; not a rendered-basemap acceptance.
        XCTAssertEqual(MapVisualStyleManifest.candidate.contrastShortfalls(), [])
    }
    func testLayerOrderKeepsRouteAboveFogAndControlsOnTop() {
        XCTAssertLessThan(MapLayerOrder.fog, .routeAndTarget)
        XCTAssertLessThan(MapLayerOrder.operationZone, .fog)
        XCTAssertLessThan(MapLayerOrder.consentedPeers, .ownLocation)
        XCTAssertEqual(MapLayerOrder.allCases.max(), .controls)
        XCTAssertEqual(MapLayerOrder.allCases.min(), .basemap)
    }
    func testMarkerStatesNeverRelyOnColorAlone() {
        let symbols = MapMarkerVisualState.allCases.map(\.symbolName)
        XCTAssertEqual(Set(symbols).count, MapMarkerVisualState.allCases.count)
        XCTAssertGreaterThan(MapMarkerVisualState.selected.strokeWidth, MapMarkerVisualState.standard.strokeWidth)
        for state in [MapMarkerVisualState.locked, .unavailable, .inReview, .completed] { XCTAssertFalse(state.allowsPrimaryAction) }
        XCTAssertTrue(MapMarkerVisualState.interactive.allowsPrimaryAction)
    }
    private func manifestJSON(extra: String = "", dropRole: Bool = false, approval: String = "approved") -> Data {
        func roles(_ hex: String) -> String {
            MapSemanticRole.allCases.filter { !(dropRole && $0 == .fogOverlay) }.map { "\"\($0.rawValue)\":\"\(hex)\"" }.joined(separator: ",")
        }
        return Data("{\"version\":\"v2\",\"approval\":\"\(approval)\",\"day\":{\(roles("#101010"))},\"night\":{\(roles("#EFEFEF"))}\(extra)}".utf8)
    }
    func testValidRemoteManifestIsUsed() {
        let manifest = MapVisualStyleManifest.resolve(manifestJSON(extra: ",\"opacity\":{\"fogOverlay\":0.4}"))
        XCTAssertEqual(manifest.version, "v2")
        XCTAssertEqual(manifest.approval, .approved)
        XCTAssertEqual(manifest.color(.fogOverlay, .day).opacity, 0.4, accuracy: 0.0001)
        XCTAssertEqual(manifest.color(.ground, .day).opacity, 1)
    }
    func testBrokenOrRuleCarryingManifestFallsBackToReadableCandidate() {
        XCTAssertEqual(MapVisualStyleManifest.resolve(nil), .candidate)
        XCTAssertEqual(MapVisualStyleManifest.resolve(Data("not json".utf8)), .candidate)
        XCTAssertEqual(MapVisualStyleManifest.resolve(manifestJSON(dropRole: true)), .candidate)
        XCTAssertEqual(MapVisualStyleManifest.resolve(manifestJSON(extra: ",\"rewardRule\":{}")), .candidate)
        XCTAssertEqual(MapVisualStyleManifest.resolve(manifestJSON(approval: "shipping")), .candidate)
        XCTAssertEqual(MapVisualStyleManifest.resolve(manifestJSON(extra: ",\"opacity\":{\"fogOverlay\":2}")), .candidate)
        XCTAssertEqual(MapVisualStyleManifest.resolve(manifestJSON(extra: ",\"opacity\":{\"unknown\":0.5}")), .candidate)
        XCTAssertEqual(MapVisualStyleManifest.resolve(Data(repeating: 32, count: 20_000)), .candidate)
    }
}
