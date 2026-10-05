import XCTest
@testable import QuestifyCore

final class PrivateHomeMapSelectionTests: XCTestCase {
    private let source = PrivateHomeMapSource(providerID: "synthetic", region: "ZZ", datum: .wgs84, contractRevision: "fixture-1")
    private func candidate(_ latitude: String = "12.345678", _ longitude: String = "-45.678901", source: PrivateHomeMapSource? = nil) -> PrivateHomeMapCandidate {
        .init(latitude: latitude, longitude: longitude, source: source ?? self.source)
    }
    func testExactSixPlacePointAndMutationUseSameNumbersWithoutRounding() throws {
        let point = try candidate().reviewedPoint(approvedSource: source)
        XCTAssertEqual(point.latitude, Decimal(string: "12.345678")); XCTAssertEqual(point.longitude, Decimal(string: "-45.678901"))
        let mutation = try PrivateHomeMutation(requestId: "synthetic-map-review", expectedVersion: 5, label: "Synthetic", point: point)
        XCTAssertEqual(mutation.latitude, point.latitude); XCTAssertEqual(mutation.longitude, point.longitude)
        XCTAssertEqual(mutation.datum, "WGS84"); XCTAssertEqual(mutation.expectedVersion, 5)
        XCTAssertEqual(String(describing: candidate()), "PrivateHome[redacted]")
    }
    func testUnknownGCJ02RegionProviderAndRevisionCannotBeRelabelled() throws {
        let sources: [PrivateHomeMapSource?] = [nil,
            .init(providerID: "synthetic", region: "ZZ", datum: nil, contractRevision: "fixture-1"),
            .init(providerID: "synthetic", region: "ZZ", datum: .gcj02, contractRevision: "fixture-1"),
            .init(providerID: "synthetic", region: "CN", datum: .wgs84, contractRevision: "fixture-1"),
            .init(providerID: "other", region: "ZZ", datum: .wgs84, contractRevision: "fixture-1"),
            .init(providerID: "synthetic", region: "ZZ", datum: .wgs84, contractRevision: "fixture-2")]
        for value in sources {
            let candidate = PrivateHomeMapCandidate(latitude: "12", longitude: "45", source: value)
            XCTAssertThrowsError(try candidate.reviewedPoint(approvedSource: source))
        }
        XCTAssertThrowsError(try candidate().reviewedPoint(approvedSource: nil))
    }
    func testMalformedSourceContractsFailClosed() {
        for bad in [PrivateHomeMapSource(providerID: "", region: "ZZ", datum: .wgs84, contractRevision: "1"),
                    .init(providerID: "s", region: "zh-Hans", datum: .wgs84, contractRevision: "1"),
                    .init(providerID: "s", region: "ZZ", datum: .wgs84, contractRevision: ""),
                    .init(providerID: "s", region: "ZZ", datum: .gcj02, contractRevision: "1")] {
            XCTAssertThrowsError(try candidate(source: bad).reviewedPoint(approvedSource: bad))
        }
    }
    func testPrecisionNeverSilentlyTruncatesIncludingTrailingZero() {
        for value in ["12.3456789", "12.3456780", "-0.0000001"] {
            XCTAssertThrowsError(try candidate(value).reviewedPoint(approvedSource: source)) { XCTAssertEqual($0 as? PrivateHomeMapIssue, .precisionUnsupported) }
        }
    }
    func testNonfiniteScientificLocaleWhitespaceAndRangeValuesRejected() {
        for value in ["nan", "inf", "1e1", "12,34", " 12", "12\n", "91", "-91", "１２", String(repeating: "1", count: 65)] {
            XCTAssertThrowsError(try candidate(value).reviewedPoint(approvedSource: source), value)
        }
        XCTAssertThrowsError(try candidate("12", "181").reviewedPoint(approvedSource: source))
        XCTAssertNoThrow(try candidate("-90", "180").reviewedPoint(approvedSource: source))
    }
    func testInvalidSelectionClearsPreviouslyValidPoint() {
        var state = PrivateHomeMapSelection(); let ticket = state.open(approvedSource: source)
        XCTAssertTrue(state.select(candidate(), generation: ticket)); XCTAssertNotNil(state.point)
        XCTAssertFalse(state.select(candidate("12.3456789"), generation: ticket)); XCTAssertNil(state.point)
        XCTAssertEqual(state.issue, .precisionUnsupported)
    }
    func testCancelReopenAndLateSelectionCannotResurrectPoint() {
        var state = PrivateHomeMapSelection(); let old = state.open(approvedSource: source)
        XCTAssertTrue(state.select(candidate(), generation: old)); state.close()
        XCTAssertNil(state.point); XCTAssertNil(state.generation)
        XCTAssertFalse(state.select(candidate(), generation: old))
        let new = state.open(approvedSource: source); XCTAssertNotEqual(old, new)
        XCTAssertFalse(state.select(candidate(), generation: old)); XCTAssertNil(state.point)
        XCTAssertTrue(state.select(candidate(), generation: new))
        XCTAssertEqual(String(reflecting: state), "PrivateHome[redacted]")
    }
    func testUnavailableOpenHasNoPointAndManualEntryRemainsIndependent() throws {
        var state = PrivateHomeMapSelection(); let ticket = state.open(approvedSource: nil)
        XCTAssertEqual(state.issue, .providerUnverified)
        XCTAssertFalse(state.select(candidate(), generation: ticket)); XCTAssertNil(state.point)
        XCTAssertEqual(try PrivateHomePoint.parse(latitude: "12.345678", longitude: "45.678901").datum, "WGS84")
    }
}
