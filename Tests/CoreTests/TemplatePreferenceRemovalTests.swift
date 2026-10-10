import XCTest
@testable import QuestifyCore

final class TemplatePreferenceRemovalTests: XCTestCase {
    private let a = #"{"key":"A","text":"首项 e\u0301","scores":{"a":2},"future":9007199254740993}"#
    private let b = #"{"key":"B","text":"B","scores":{"a":1},"future":0.1234567890123456789}"#
    private let c = #"{"key":"C","text":"C","scores":{"a":0},"future":-0e+00}"#
    private let preserved = #", "results" : {"a":{"body":"{{choices}}","opaque":9007199254740993}}, "tiebreak":{"untouched":true}, "future":{"é":1,"e\u0301":2} }"#
    private func question(_ options: [String], title: String = "问题") -> String {
        #"{"key":"q","title":""# + title + #"","type":"single","options":["# + options.joined(separator: ", \n  ") + #"],"futureQuestion":{"precise":1e1000}}"#
    }
    private func source(_ questions: [String]) -> String { " \n{\"steps\" : [" + questions.joined(separator: ",\r\n ") + "]" + preserved + "\r\n" }
    private func assertBytes(_ actual: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Array(actual.utf8), Array(expected.utf8), file: file, line: line)
    }
    func testProjectionIsNoOpAndDoesNotValidateOrRewriteResults() throws {
        let raw = source([question([a, b, c])]), document = try TemplatePreferenceRemoval(source: raw)
        assertBytes(document.source, raw)
        XCTAssertEqual(document.questions.count, 1); XCTAssertEqual(document.questions[0].options.count, 3)
        XCTAssertFalse(document.canRemoveQuestion); XCTAssertTrue(document.questions[0].canRemoveOption)
        XCTAssertEqual(document.questions[0].title, "问题")
    }
    func testOptionFirstMiddleLastPreserveEverySurvivingByteAndUnknownResults() throws {
        for index in 0..<3 {
            let raw = source([question([a, b, c])]), document = try TemplatePreferenceRemoval(source: raw)
            var remaining = [a, b, c]; remaining.remove(at: index)
            let next = try document.removing(.option(question: 0, index: index), from: raw)
            assertBytes(next, source([question(remaining)]))
            XCTAssertTrue(next.contains(preserved))
            XCTAssertEqual(try TemplatePreferenceRemoval(source: next).questions[0].options.count, 2)
        }
    }
    func testQuestionFirstMiddleLastKeepUnrelatedRowsAndTiebreakExact() throws {
        let rows = (0..<3).map { question([a, b], title: String($0)) }, raw = source(rows)
        let document = try TemplatePreferenceRemoval(source: raw)
        for index in rows.indices {
            var remaining = rows; remaining.remove(at: index)
            assertBytes(try document.removing(.question(index), from: raw), source(remaining))
        }
    }
    func testMinimumOneQuestionAndTwoOptionsNeverChangesSource() throws {
        let raw = source([question([a, b])]), document = try TemplatePreferenceRemoval(source: raw)
        for target in [TemplatePreferenceRemoval.Target.question(0), .option(question: 0, index: 0)] {
            XCTAssertThrowsError(try document.removing(target, from: raw)) { XCTAssertEqual($0 as? TemplatePreferenceRemoval.Failure, .minimum) }
        }
        assertBytes(document.source, raw)
    }
    func testExactSourceRejectsWhitespaceAndCanonicalEquivalentABA() throws {
        let raw = source([question([a, b, c], title: "é")]), document = try TemplatePreferenceRemoval(source: raw)
        for changed in [raw + " ", raw.replacingOccurrences(of: "é", with: "e\u{301}")] {
            XCTAssertThrowsError(try document.removing(.option(question: 0, index: 0), from: changed)) {
                XCTAssertEqual($0 as? TemplatePreferenceRemoval.Failure, .stale)
            }
        }
    }
    func testNegativeAndOutOfRangeTargetsAreRejected() throws {
        let raw = source([question([a, b, c])]), document = try TemplatePreferenceRemoval(source: raw)
        for target in [TemplatePreferenceRemoval.Target.question(-1), .question(1), .option(question: -1, index: 0), .option(question: 0, index: -1), .option(question: 0, index: 3)] {
            XCTAssertThrowsError(try document.removing(target, from: raw)) { XCTAssertEqual($0 as? TemplatePreferenceRemoval.Failure, .stale) }
        }
    }
    func testDuplicateEscapedKeysAndMalformedJSONFailClosed() {
        let valid = source([question([a, b])])
        for raw in ["", "[]", "{}", #"{"steps":[]}"#, valid + "false",
                    valid.replacingOccurrences(of: #""steps" :"#, with: #""steps":[],"st\u0065ps" :"#),
                    valid.replacingOccurrences(of: #""futureQuestion":{"precise":1e1000}"#, with: #""futureQuestion":{"x":1,"\u0078":2}"#),
                    valid.replacingOccurrences(of: "1e1000", with: "01"),
                    valid.replacingOccurrences(of: "1e1000", with: "NaN"),
                    valid.replacingOccurrences(of: "1e1000", with: "true false"),
                    valid.replacingOccurrences(of: "\"问题\"", with: "\"bad\ntext\""),
                    source([question([a])])] {
            XCTAssertThrowsError(try TemplatePreferenceRemoval(source: raw), raw)
        }
    }
    func testEscapedKnownKeyAndCanonicalDistinctUnknownKeysArePreserved() throws {
        let raw = source([question([a, b, c])]).replacingOccurrences(of: #""steps""#, with: #""st\u0065ps""#)
        let next = try TemplatePreferenceRemoval(source: raw).removing(.option(question: 0, index: 1), from: raw)
        XCTAssertTrue(next.contains(#""st\u0065ps""#)); XCTAssertTrue(next.contains(preserved))
    }
    func testDepthBytesAndProjectionBudgetsAreBounded() {
        let valid = source([question([a, b])])
        for raw in [String(repeating: " ", count: 1_048_577),
                    valid.replacingOccurrences(of: "1e1000", with: String(repeating: "[", count: 65) + "0" + String(repeating: "]", count: 65)),
                    source(Array(repeating: question([a, b]), count: 129)),
                    source([question(Array(repeating: a, count: 65))]),
                    source(Array(repeating: question(Array(repeating: a, count: 64)), count: 9))] {
            XCTAssertThrowsError(try TemplatePreferenceRemoval(source: raw))
        }
    }
    func testSequentialDeletionNeedsFreshProjectionAndStillKeepsMinimum() throws {
        let raw = source([question([a, b, c]), question([a, b], title: "next")])
        let old = try TemplatePreferenceRemoval(source: raw)
        let next = try old.removing(.question(1), from: raw)
        XCTAssertThrowsError(try old.removing(.question(0), from: next))
        let updated = try TemplatePreferenceRemoval(source: next)
        XCTAssertThrowsError(try updated.removing(.question(0), from: next))
        let final = try updated.removing(.option(question: 0, index: 1), from: next)
        XCTAssertEqual(try TemplatePreferenceRemoval(source: final).questions[0].options.count, 2)
    }
}
