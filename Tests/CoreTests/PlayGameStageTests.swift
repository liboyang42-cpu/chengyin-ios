import XCTest
@testable import QuestifyCore

final class PlayGameStageTests: XCTestCase {
    private func nodes(_ json: String) throws -> [PlayNode] { try JSONDecoder().decode([PlayNode].self, from: Data(json.utf8)) }
    private func chapters(_ json: String) throws -> [PlayChapter] { try JSONDecoder().decode([PlayChapter].self, from: Data(json.utf8)) }
    private func projection(_ kind: PlayKitScreenKind, _ json: String) throws -> PlayKitScreenProjection {
        .init(kind: kind, segment: try JSONDecoder().decode(PlayWireValue.self, from: Data(json.utf8)))
    }

    func testStationNumberNameChapterAndLeadComeFromTheRouteRead() throws {
        let route = try nodes(#"[{"nodeId":11,"name":"钟楼","sortId":1,"chapterId":3},{"nodeId":12,"name":" 老邮局 ","sortId":2,"chapterId":3,"hookText":"\n  信封上的邮戳还是热的。\n第二行不显示"}]"#)
        let story = try chapters(#"[{"chapterId":3,"name":"第一章 · 雾起"}]"#)
        let stage = try XCTUnwrap(PlayGameStage.resolve(nodeID: 12, nodes: route, chapters: story))
        XCTAssertEqual(stage.ordinal, 2)
        XCTAssertEqual(stage.stationName, "老邮局")
        XCTAssertEqual(stage.chapterTitle, "第一章 · 雾起")
        XCTAssertEqual(stage.lead, "信封上的邮戳还是热的。")
        XCTAssertFalse(stage.isEmpty)
    }

    func testSortIDOrdersStationsOnlyWhenEveryStationHasOne() throws {
        let sorted = try nodes(#"[{"nodeId":1,"sortId":3},{"nodeId":2,"sortId":1},{"nodeId":3,"sortId":2}]"#)
        XCTAssertEqual(PlayGameStage.resolve(nodeID: 1, nodes: sorted)?.ordinal, 3)
        let partial = try nodes(#"[{"nodeId":1,"sortId":3},{"nodeId":2},{"nodeId":3,"sortId":2}]"#)
        XCTAssertEqual(PlayGameStage.resolve(nodeID: 1, nodes: partial)?.ordinal, 1)
    }

    func testExplicitChapterTitleWinsAndMissingFactsStayEmpty() throws {
        let route = try nodes(#"[{"nodeId":5,"name":"  ","hookText":"   "}]"#)
        let stage = try XCTUnwrap(PlayGameStage.resolve(nodeID: 5, nodes: route, chapterTitle: "雨夜"))
        XCTAssertEqual(stage.chapterTitle, "雨夜")
        XCTAssertNil(stage.stationName); XCTAssertNil(stage.lead)
        XCTAssertNil(PlayGameStage.resolve(nodeID: 99, nodes: route))
        XCTAssertTrue(PlayGameStage(ordinal: 0, stationName: nil, chapterTitle: " ", lead: nil).isEmpty)
    }

    func testOutcomeMirrorsAuthoritativeResultRules() throws {
        let p1 = try projection(.qa, #"{"finished":true,"passed":true}"#)
        XCTAssertEqual(PlayGameOutcome.resolve(p1), .passed)
        let p2 = try projection(.stopwatch, #"{"attempts":1,"submitted":false,"passed":false}"#)
        XCTAssertEqual(PlayGameOutcome.resolve(p2), .notPassed)
        let p3 = try projection(.qa, #"{"mode":"PICK","judge":false,"finished":true,"passed":false}"#)
        XCTAssertEqual(PlayGameOutcome.resolve(p3), .recorded)
        let p4 = try projection(.photoCheck, #"{"degraded":true,"passed":true}"#)
        XCTAssertEqual(PlayGameOutcome.resolve(p4), .noVerdict)
        let p5 = try projection(.coinFlip, #"{"flipped":true}"#)
        XCTAssertEqual(PlayGameOutcome.resolve(p5), .recorded)
        let p6 = try projection(.stopwatch, #"{"tries":3,"passed":false}"#)
        XCTAssertNil(PlayGameOutcome.resolve(p6))
        XCTAssertEqual(PlayGameOutcome.passed.key, "playkit.story.passed")
        XCTAssertEqual(PlayGameOutcome.notPassed.key(open: true), "playkit.story.tryAgain")
        XCTAssertEqual(PlayGameOutcome.notPassed.key(open: false), "playkit.story.notPassed")
        XCTAssertEqual(PlayGameOutcome.passed.key(open: true), "playkit.story.passed")
    }

    func testContinueAppearsOnlyAfterAFinishedSettledGame() {
        XCTAssertTrue(PlayGameOutcome.showsContinue(complete: true, pending: false, phase: "ready"))
        XCTAssertFalse(PlayGameOutcome.showsContinue(complete: false, pending: false, phase: "ready"))
        XCTAssertFalse(PlayGameOutcome.showsContinue(complete: true, pending: true, phase: "ready"))
        XCTAssertFalse(PlayGameOutcome.showsContinue(complete: true, pending: false, phase: "submitting"))
    }

    func testNumberKeepsItsUnitBesideIt() {
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(PlayGameNumber.text(120, unit: "米", locale: locale), "120 米")
        XCTAssertEqual(PlayGameNumber.text(12.5, unit: " km ", locale: locale), "12.5 km")
        XCTAssertEqual(PlayGameNumber.text(3.14159, unit: nil, locale: locale), "3.14")
        XCTAssertEqual(PlayGameNumber.text(7, unit: "", locale: locale), "7")
        XCTAssertEqual(PlayGameNumber.text(.nan, unit: "m", locale: locale), "—")
    }

    func testMatchLinesFollowPairsAndSkipUnknownRows() {
        let lines = PlayGameMatchLine.lines(left: ["a", "b", "c"], right: ["x", "y", "z"], placement: ["a": "z", "c": "x", "b": "gone"])
        XCTAssertEqual(lines, [PlayGameMatchLine(left: 0, right: 2), PlayGameMatchLine(left: 2, right: 0)])
        XCTAssertTrue(PlayGameMatchLine.lines(left: [], right: ["x"], placement: [:]).isEmpty)
    }
}
