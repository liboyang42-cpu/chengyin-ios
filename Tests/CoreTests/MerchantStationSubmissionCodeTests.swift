import XCTest
@testable import QuestifyCore

final class MerchantStationSubmissionCodeTests: XCTestCase {
    private func rejects(_ values: [String], file: StaticString = #filePath, line: UInt = #line) {
        for value in values { XCTAssertThrowsError(try MerchantStationSubmissionCode(value), value, file: file, line: line) }
    }
    func testSourcePlainDecimalWitness() throws {
        let value = try MerchantStationSubmissionCode("300")
        XCTAssertEqual(value.submissionID, "300"); XCTAssertEqual(value.format, .decimal)
    }
    func testSourceJSONStringWitness() throws {
        let value = try MerchantStationSubmissionCode(#"{"submissionId":"301"}"#)
        XCTAssertEqual(value.submissionID, "301"); XCTAssertEqual(value.format, .json)
    }
    func testSourceJSONIntegerWitnessAndWhitespace() throws {
        let value = try MerchantStationSubmissionCode(" \n{ \t\"submissionId\" : 302 \r\n} \t")
        XCTAssertEqual(value.submissionID, "302"); XCTAssertEqual(value.format, .json)
    }
    func testStandaloneQueryWitness() throws {
        let value = try MerchantStationSubmissionCode("?submissionId=303")
        XCTAssertEqual(value.submissionID, "303"); XCTAssertEqual(value.format, .query)
    }
    func testBoundaryWhitespaceDoesNotAlterIdentifierBytes() throws {
        XCTAssertEqual(try MerchantStationSubmissionCode(" \n123\t ").submissionID, "123")
    }
    func testExactIntegerBeyondJavaScriptPrecisionIsPreserved() throws {
        for raw in ["9007199254740993", #"{"submissionId":9007199254740993}"#, #"{"submissionId":"9007199254740993"}"#] {
            XCTAssertEqual(try MerchantStationSubmissionCode(raw).submissionID, "9007199254740993")
        }
    }
    func testSignedLongMaximumIsPreserved() throws {
        XCTAssertEqual(try MerchantStationSubmissionCode("9223372036854775807").submissionID, "9223372036854775807")
    }
    func testZeroNegativeLeadingZeroAndOverflowFail() {
        rejects(["0", "-1", "+1", "001", "9223372036854775808", "9999999999999999999", "10000000000000000000"])
    }
    func testFractionExponentAndBooleanFailWithoutNumericCoercion() {
        rejects(["1.0", "1e3", #"{"submissionId":true}"#, #"{"submissionId":3.0}"#, #"{"submissionId":1e3}"#, #"{"submissionId":null}"#])
    }
    func testDuplicateJSONIDsFailEvenWhenIdentical() {
        rejects([#"{"submissionId":"3","submissionId":"4"}"#, #"{"submissionId":3,"submissionId":3}"#])
    }
    func testMultipleQueryIDsAndOtherFieldsFail() {
        rejects(["?submissionId=3&submissionId=4", "?submissionId=3&submissionId=3", "?submissionId=3&nodeId=2", "?nodeId=2&submissionId=3"])
    }
    func testUnexpectedJSONFieldsNestingAndArraysFail() {
        rejects([#"{"submissionId":"3","nodeId":2}"#, #"{"submissionId":{"submissionId":"3"}}"#, #"[{"submissionId":"3"}]"#, #"{"submissionId":[3]}"#])
    }
    func testEscapedOrConfusableKeysAndDigitsFail() {
        rejects([#"{"submission\u0049d":"3"}"#, #"{"submissionId":"\u0033"}"#, #"{"SubmissionId":"3"}"#, "１２３", "١٢٣", "1\u{200B}2"])
    }
    func testAbsoluteAndNetworkPathLinksAreUnsupportedForEveryHost() {
        for raw in ["https://example.invalid/?submissionId=3", "https://trusted.invalid.evil.invalid/?submissionId=3", "http://example.invalid/?submissionId=3", "//example.invalid/?submissionId=3", "custom://play?submissionId=3"] {
            XCTAssertThrowsError(try MerchantStationSubmissionCode(raw)) { XCTAssertEqual($0 as? MerchantStationSubmissionCode.Failure, .unsupportedLink) }
        }
    }
    func testRelativePathsEncodedQueryAndFragmentAreRejected() {
        rejects(["/play?submissionId=3", "?%73ubmissionId=3", "?submissionId=%33", "?submissionId=3#4", "#submissionId=3", "submissionId=3", "&submissionId=3"])
    }
    func testMalformedTrailingAndEmbeddedControlContentFail() {
        rejects(["", " \n ", "submission-300", "3 4", "3\n4", "3\u{0000}", #"{"submissionId":"3"}junk"#, #"{"submissionId":"3",}"#, "javascript:submissionId=3"])
    }
    func testOversizedInputIsRejectedBeforeWhitespaceTrimming() {
        XCTAssertThrowsError(try MerchantStationSubmissionCode(String(repeating: " ", count: 4_096) + "3")) {
            XCTAssertEqual($0 as? MerchantStationSubmissionCode.Failure, .oversized)
        }
    }
    func testByteBoundIncludesMultibyteInput() {
        XCTAssertThrowsError(try MerchantStationSubmissionCode(String(repeating: "界", count: 1_366))) {
            XCTAssertEqual($0 as? MerchantStationSubmissionCode.Failure, .oversized)
        }
    }
    func testBoundedWhitespaceAtLimitRemainsValid() throws {
        XCTAssertEqual(try MerchantStationSubmissionCode(String(repeating: " ", count: 4_095) + "3").submissionID, "3")
    }
}
