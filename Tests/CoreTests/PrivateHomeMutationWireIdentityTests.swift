import XCTest
@testable import QuestifyCore

/// NOT_RUN. Value-only cases for the existing raw UTF-8 label / numeric coordinate contract.
final class PrivateHomeMutationWireIdentityTests: XCTestCase {
    private let pairs = [("Caf\u{00E9}", "Cafe\u{0301}"), ("\u{00C5}", "A\u{030A}"),
                         ("\u{AC00}", "\u{1100}\u{1161}"), ("a\u{0323}\u{0301}", "a\u{0301}\u{0323}")]
    private func mutation(_ label: String?, id: String = "original-request", version: Int64 = 3,
                          latitude: Decimal = 12, longitude: Decimal = 45) throws -> PrivateHomeMutation {
        try .init(requestId: id, expectedVersion: version, label: label,
                  point: label == nil ? nil : .init(latitude: latitude, longitude: longitude))
    }
    func testValidCanonicallyEquivalentLabelsAreDifferentWireMutations() throws {
        for (a, b) in pairs {
            XCTAssertEqual(a, b) // Swift text equivalence is deliberately not command identity.
            XCTAssertFalse(a.utf8.elementsEqual(b.utf8))
            let one = try mutation(a), two = try mutation(b)
            try one.validate(); try two.validate()
            XCTAssertNotEqual(one, two); XCTAssertNotEqual(two, one)
            XCTAssertEqual(one, one); XCTAssertEqual(two, two)
        }
    }
    func testEncodingAndDecodingPreserveEachLabelWithoutNormalization() throws {
        for (a, b) in pairs {
            for label in [a, b] {
                let original = try mutation(label)
                let decoded = try JSONDecoder().decode(PrivateHomeMutation.self, from: JSONEncoder().encode(original))
                XCTAssertEqual(decoded, original)
                XCTAssertTrue(try XCTUnwrap(decoded.label).utf8.elementsEqual(label.utf8))
            }
        }
    }
    func testCoordinateScaleAndSignedZeroRemainNumericIdentity() throws {
        let locale = Locale(identifier: "en_US_POSIX")
        for pair in [("12", "12.000000"), ("0", "-0.000000"), ("-12.34", "-12.340000")] {
            let a = try XCTUnwrap(Decimal(string: pair.0, locale: locale))
            let b = try XCTUnwrap(Decimal(string: pair.1, locale: locale))
            XCTAssertEqual(try mutation("Same", latitude: a), try mutation("Same", latitude: b))
            XCTAssertEqual(try mutation("Same", longitude: a), try mutation("Same", longitude: b))
        }
    }
    func testEveryOtherOriginalCommandFieldStillParticipates() throws {
        let original = try mutation("Same")
        for changed in [try mutation("Same", id: "another-request"), try mutation("Same", version: 4),
                        try mutation("Same", latitude: 13), try mutation("Same", longitude: 46),
                        try mutation("Different"), try mutation(nil)] {
            XCTAssertNotEqual(original, changed)
        }
        XCTAssertEqual(try mutation(nil), try mutation(nil))
        XCTAssertNotEqual(try mutation(nil), try mutation(nil, version: 4))
    }
    func testDatumRemainsPartOfEqualityEvenBeforeDecodedValueValidation() throws {
        let malformed = try JSONDecoder().decode(PrivateHomeMutation.self,
            from: Data(#"{"requestId":"original-request","expectedVersion":3,"label":"Same","latitude":12,"longitude":45,"datum":"GCJ02"}"#.utf8))
        XCTAssertThrowsError(try malformed.validate())
        XCTAssertNotEqual(malformed, try mutation("Same"))
    }
    func testJsonEscapeSpellingDoesNotChangeDecodedCommandIdentity() throws {
        let a = try JSONDecoder().decode(PrivateHomeMutation.self,
            from: Data(#"{"requestId":"original-request","expectedVersion":3,"label":"Caf\u00e9","latitude":12,"longitude":45,"datum":"WGS84"}"#.utf8))
        XCTAssertEqual(a, try mutation("Caf\u{00E9}"))
        XCTAssertNotEqual(a, try mutation("Cafe\u{0301}"))
    }
}
