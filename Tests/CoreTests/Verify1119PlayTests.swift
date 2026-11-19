import XCTest
@testable import QuestifyCore

/// verify-1119 player-side items, aligned to hengyin #866: hangman fill note, reference picture
/// entry, RECORD photo stations, completion/start-mode labels and the stage event pipeline.
final class Verify1119PlayTests: XCTestCase {
    private func wire(_ json: String) throws -> PlayWireValue { try JSONDecoder().decode(PlayWireValue.self, from: Data(json.utf8)) }
    private let slots = #""slots":[{"i":0,"kind":"BLANK"},{"i":1,"kind":"BLANK"}]"#

    // CG-01-P2-5
    func testHangmanHowToIsDecodedAndHiddenWhenAbsentOrBlank() throws {
        let note = try PlayHangmanProjection(wire("{\(slots),\"howTo\":\"一格一个字母，V＝ü\"}"))
        XCTAssertEqual(note.howTo, "一格一个字母，V＝ü")
        XCTAssertNil(try PlayHangmanProjection(wire("{\(slots)}")).howTo)
        XCTAssertNil(try PlayHangmanProjection(wire("{\(slots),\"howTo\":\"  \"}")).howTo)
    }

    // CG-09-P2-5 / CG-10-D-3
    func testReferenceImageSourceAcceptsBothKeysAndIgnoresBlank() throws {
        XCTAssertEqual(PlayKitReferenceImage.source(in: try wire(#"{"referenceImage":"https://a.example/r.png"}"#)), "https://a.example/r.png")
        XCTAssertEqual(PlayKitReferenceImage.source(in: try wire(#"{"referenceImageUrl":" https://a.example/s.png "}"#)), "https://a.example/s.png")
        XCTAssertNil(PlayKitReferenceImage.source(in: try wire(#"{"referenceImage":""}"#)))
        XCTAssertNil(PlayKitReferenceImage.source(in: try wire(#"{"prompt":"x"}"#)))
    }

    // CG-ALL-12 / CG-02-D-4 — hengyin #866: photoCheck.mode == "RECORD" + SUBMIT_PHOTO_RECORD
    func testRecordStationTakesSubmitPhotoRecordWithPhotoOrTextConfirmation() throws {
        let record = try wire(#"{"mode":"RECORD","passed":false,"tries":0}"#)
        XCTAssertTrue(PlayKitPhotoRecordMode.applies(record))
        XCTAssertEqual(PlayKitPhotoRecordMode.submitAction(for: record), "SUBMIT_PHOTO_RECORD")
        XCTAssertEqual(PlayKitPhotoRecordMode.textConfirmedPayload, ["textConfirmed": .bool(true)])
        XCTAssertNoThrow(try PlayKitInputContract.validate(kind: "photoCheck", action: "SUBMIT_PHOTO_RECORD", payload: ["textConfirmed": .bool(true)], segment: record))
        XCTAssertNoThrow(try PlayKitInputContract.validate(kind: "photoCheck", action: "SUBMIT_PHOTO_RECORD", payload: ["imageUrl": .string("https://a.example/p.jpg")], segment: record))
        // The server refuses SUBMIT_PHOTO_CHECK on a RECORD station ("这一站拍照只做记录").
        XCTAssertThrowsError(try PlayKitInputContract.validate(kind: "photoCheck", action: "SUBMIT_PHOTO_CHECK", payload: ["imageUrl": .string("https://a.example/p.jpg")], segment: record))
        XCTAssertThrowsError(try PlayKitInputContract.validate(kind: "photoCheck", action: "SUBMIT_PHOTO_RECORD", payload: ["textConfirmed": .bool(false)], segment: record))
        XCTAssertThrowsError(try PlayKitInputContract.validate(kind: "photoCheck", action: "SUBMIT_PHOTO_RECORD", payload: ["skipped": .bool(true)], segment: record))
        let long = "https://a.example/" + String(repeating: "a", count: 500)
        XCTAssertThrowsError(try PlayKitInputContract.validate(kind: "photoCheck", action: "SUBMIT_PHOTO_RECORD", payload: ["imageUrl": .string(long)], segment: record))
        XCTAssertEqual(try PlayKitActionCatalog.payload(kind: "photoCheck", action: "SUBMIT_PHOTO_RECORD", detail: ["textConfirmed": .bool(true)]), ["textConfirmed": .bool(true)])
    }
    func testOnlyExactRecordModeIsRecordAndOldGuessedKeysAreIgnored() throws {
        for json in [#"{"photoMode":"record"}"#, #"{"photo_mode":"RECORD"}"#, #"{"mode":"record"}"#, #"{"mode":"CARD"}"#, #"{"passed":false}"#] {
            let segment = try wire(json)
            XCTAssertFalse(PlayKitPhotoRecordMode.applies(segment), json)
            XCTAssertEqual(PlayKitPhotoRecordMode.submitAction(for: segment), "SUBMIT_PHOTO_CHECK", json)
        }
    }
    func testOrdinaryPhotoCheckStillRequiresAPhoto() throws {
        let ordinary = try wire(#"{"passed":false}"#)
        XCTAssertNoThrow(try PlayKitInputContract.validate(kind: "photoCheck", action: "SUBMIT_PHOTO_CHECK", payload: ["imageUrl": .string("https://a.example/p.jpg")], segment: ordinary))
        XCTAssertThrowsError(try PlayKitInputContract.validate(kind: "photoCheck", action: "SUBMIT_PHOTO_CHECK", payload: ["textConfirmed": .bool(true)], segment: ordinary))
        XCTAssertThrowsError(try PlayKitInputContract.validate(kind: "photoCheck", action: "SUBMIT_PHOTO_RECORD", payload: ["imageUrl": .string("https://a.example/p.jpg")], segment: ordinary))
    }

    // CG-07-P2-2: per-node completionMode is assisted-or-solved only.
    func testCompletionModesMapToPlayerLabels() {
        XCTAssertEqual(PlayCompletionModePresentation(raw: "SOLVED"), .solved)
        XCTAssertEqual(PlayCompletionModePresentation(raw: "SKIPPED"), .assisted)
        XCTAssertEqual(PlayCompletionModePresentation(raw: "REVEALED"), .assisted)
        XCTAssertEqual(PlayCompletionModePresentation(raw: "ASSISTED_COMPLETION"), .assisted)
        XCTAssertNil(PlayCompletionModePresentation(raw: "DESK"))
        XCTAssertNil(PlayCompletionModePresentation(raw: "ALT"))
        XCTAssertNil(PlayCompletionModePresentation(raw: "CUSTOM_SERVER_TEXT"))
        XCTAssertNil(PlayCompletionModePresentation(raw: nil))
        XCTAssertEqual(PlayCompletionModePresentation.assisted.labelKey, "playx.completion.assisted")
        XCTAssertFalse(PlayCompletionModePresentation.solved.isAssisted)
    }
    func testCompletedBadgeShowsAssistedOnlyForCompletedNodes() {
        XCTAssertEqual(PlayTaskStatusPresentation.completed.labelKey(completionMode: "SKIPPED"), "playx.completion.assisted")
        XCTAssertEqual(PlayTaskStatusPresentation.completed.labelKey(completionMode: "DESK"), "referenceTask.status.completed")
        XCTAssertEqual(PlayTaskStatusPresentation.completed.labelKey(completionMode: "SOLVED"), "referenceTask.status.completed")
        XCTAssertEqual(PlayTaskStatusPresentation.completed.labelKey(completionMode: nil), "referenceTask.status.completed")
        XCTAssertEqual(PlayTaskStatusPresentation.available.labelKey(completionMode: "SKIPPED"), "referenceTask.status.available")
    }

    // CG-ALL-11 — hengyin #866: runStartMode / altStations / perkOnly / addressHidden on /api/play/nodes
    private func nodes(_ extra: String, node: String = #"{"nodeId":1}"#) throws -> PlayNodesResult {
        try JSONDecoder().decode(PlayNodesResult.self, from: Data("{\"nodes\":[\(node)]\(extra)}".utf8))
    }
    func testRunStartModeIsRunLevelAndLabelsDeskAndAlt() throws {
        XCTAssertEqual(try nodes(#","runStartMode":"DESK""#).runStartMode, .desk)
        XCTAssertEqual(try nodes(#","runStartMode":"ALT""#).runStartMode, .alt)
        XCTAssertNil(try nodes(#","runStartMode":null"#).runStartMode)
        XCTAssertNil(try nodes(#","runStartMode":"REMOTE""#).runStartMode)
        XCTAssertNil(try nodes(#","runStartMode":7"#).runStartMode)
        XCTAssertNil(try nodes("").runStartMode)
        XCTAssertEqual(PlayRunStartMode.desk.labelKey, "playx.completion.desk")
        XCTAssertEqual(PlayRunStartMode.alt.labelKey, "playx.completion.alternate")
    }
    func testAltStationsPerkOnlyAndAddressHiddenAreAdditive() throws {
        let result = try nodes(#","altStations":[{"id":3,"name":"东门","longitude":121.5,"latitude":31.2},{"id":3,"name":"dup"},{"id":0},{"name":"no id"}],"perkOnly":true"#,
                               node: #"{"nodeId":1,"address":null,"addressHidden":true,"perk":{"name":"咖啡","included":false,"extraSpendText":" 另付 10 元 ","reserveRequired":true}}"#)
        XCTAssertEqual(result.altStations, [PlayAltStation(id: 3, name: "东门", longitude: 121.5, latitude: 31.2)])
        XCTAssertEqual(result.perkOnly, true)
        let node = try XCTUnwrap(result.nodes.first)
        XCTAssertEqual(node.addressHidden, true); XCTAssertNil(node.address)
        XCTAssertEqual(node.perk?.name, "咖啡"); XCTAssertEqual(node.perk?.included, false)
        XCTAssertEqual(node.perk?.extraSpendText, "另付 10 元"); XCTAssertEqual(node.perk?.reserveRequired, true)
        let plain = try nodes(#","altStations":"bad","perkOnly":"yes""#, node: #"{"nodeId":1,"addressHidden":"maybe","perk":{"included":"yes"}}"#)
        XCTAssertTrue(plain.altStations.isEmpty); XCTAssertNil(plain.perkOnly)
        XCTAssertNil(plain.nodes.first?.addressHidden); XCTAssertNil(plain.nodes.first?.perk?.included)
    }
    func testArriveStartModeFieldsMatchTheOptionalParameters() throws {
        let offered = [PlayAltStation(id: 3, name: nil, longitude: nil, latitude: nil)]
        XCTAssertEqual(try PlayRunStartRequest(mode: .desk).fields, ["startMode": "DESK"])
        XCTAssertEqual(try PlayRunStartRequest(mode: .alt, altStationID: 3, offered: offered).fields, ["startMode": "ALT", "altStationId": "3"])
        XCTAssertThrowsError(try PlayRunStartRequest(mode: .alt, altStationID: 4, offered: offered))
        XCTAssertThrowsError(try PlayRunStartRequest(mode: .alt, offered: offered))
        XCTAssertThrowsError(try PlayRunStartRequest(mode: .desk, altStationID: 3, offered: offered))
    }

    // CG-01-P2-9 / CG-09-P2-6 / CG-10-P2-6 — hengyin #866 ApiAnalyticsController whitelist
    func testStageEventNamesMatchTheServerWhitelist() {
        XCTAssertEqual(Set(PlayStageEvent.allCases.map(\.rawValue)),
                       ["stage_enter", "hint_open", "stage_skip", "assisted_complete", "wrong_answer", "stage_issue_report", "material_view"])
        XCTAssertEqual(Set(PlayStageIssueKind.allCases.map(\.rawValue)), ["ALT_MATERIAL", "NOT_FOUND", "UNREADABLE", "LOGIC_ERROR"])
    }
    func testStageEventLogIsBoundedAndCarriesNoAnswerText() {
        let log = PlayStageEventLog()
        for index in 0..<(PlayStageEventLog.capacity + 5) { log.record(.stageEnter, nodeID: index, kind: "qa") }
        XCTAssertEqual(log.entries.count, PlayStageEventLog.capacity)
        XCTAssertEqual(log.entries.first?.nodeID, 5)
        log.record(.wrongAnswer, nodeID: 9, kind: "hangman")
        let last = log.entries.last
        XCTAssertEqual(last?.event, .wrongAnswer); XCTAssertEqual(last?.nodeID, 9); XCTAssertEqual(last?.kind, "hangman"); XCTAssertNil(last?.issueKind)
        log.removeAll(); XCTAssertTrue(log.entries.isEmpty)
    }
    func testIssueReportNeedsACategoryAndOtherEventsDropIt() {
        let log = PlayStageEventLog()
        log.record(.stageIssueReport, nodeID: 1)
        XCTAssertTrue(log.entries.isEmpty)
        log.record(.stageIssueReport, nodeID: 1, issueKind: .unreadable)
        log.record(.hintOpen, nodeID: 1, issueKind: .notFound)
        XCTAssertEqual(log.entries.map(\.issueKind), [.unreadable, nil])
    }
    func testBatchBodyUsesServerFieldsAndOnlyCodes() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let issue = PlayStageEventRecord(event: .stageIssueReport, nodeID: 42, kind: "qa", issueKind: .notFound, occurredAt: now)
        let body = try JSONSerialization.jsonObject(with: PlayStageAnalyticsBatch.body([issue])) as? [String: Any]
        let event = try XCTUnwrap((body?["events"] as? [[String: Any]])?.first)
        XCTAssertEqual(event["eventName"] as? String, "stage_issue_report")
        XCTAssertEqual(event["bizType"] as? String, "topic_node"); XCTAssertEqual((event["bizId"] as? NSNumber)?.intValue, 42)
        XCTAssertEqual((event["occurredAt"] as? NSNumber)?.int64Value, 1_800_000_000_000)
        XCTAssertTrue((event["idempotencyKey"] as? String)?.hasPrefix("ios-stage-") == true)
        XCTAssertNil(event["actorScope"])
        let properties = try JSONSerialization.jsonObject(with: Data(try XCTUnwrap(event["propertiesJson"] as? String).utf8)) as? [String: Any]
        XCTAssertEqual(properties?["issueKind"] as? String, "NOT_FOUND"); XCTAssertEqual((properties?["nodeId"] as? NSNumber)?.intValue, 42); XCTAssertEqual(properties?["kit"] as? String, "qa")
        XCTAssertEqual(Set(properties?.keys.map { $0 } ?? []), ["issueKind", "nodeId", "kit"])
        XCTAssertThrowsError(try PlayStageAnalyticsBatch.body([]))
        let many = (0..<60).map { PlayStageEventRecord(event: .stageEnter, nodeID: $0 + 1, kind: nil, occurredAt: now) }
        let stale = PlayStageEventRecord(event: .stageEnter, nodeID: 1, kind: nil, occurredAt: now.addingTimeInterval(-15 * 24 * 3600))
        let split = PlayStageAnalyticsBatch.sendable(many + [stale], now: now)
        XCTAssertEqual(split.send.count, PlayStageAnalyticsBatch.maxBatch); XCTAssertEqual(split.stale.map(\.id), [stale.id])
        XCTAssertEqual(PlayStageAnalyticsBatch.path, "api/analytics/events/batch")
    }
    @MainActor func testUploaderRemovesSentEventsAndKeepsThemOnTransportFailure() async throws {
        let api = try APIConfiguration(baseURL: URL(string: "https://example.com/")!)
        let log = PlayStageEventLog(); log.record(.stageEnter, nodeID: 1); log.record(.materialView, nodeID: 1)
        let failing = Verify1119Transport { _ in throw URLError(.notConnectedToInternet) }
        let offline = await PlayStageAnalyticsUploader(configuration: api, transport: failing, token: { "synthetic" }).flush(log)
        XCTAssertEqual(offline, 0); XCTAssertEqual(log.entries.count, 2)
        let signedOut = await PlayStageAnalyticsUploader(configuration: api, transport: failing, token: { nil }).flush(log)
        XCTAssertEqual(signedOut, 0); XCTAssertEqual(failing.requests.count, 1)
        let ok = Verify1119Transport { _ in (Data(#"{"code":200,"data":{"accepted":2}}"#.utf8), 200) }
        let sent = await PlayStageAnalyticsUploader(configuration: api, transport: ok, token: { "synthetic" }).flush(log)
        XCTAssertEqual(sent, 2)
        XCTAssertTrue(log.entries.isEmpty)
        let request = try XCTUnwrap(ok.requests.first)
        XCTAssertEqual(request.url, URL(string: "https://example.com/api/analytics/events/batch")); XCTAssertEqual(request.httpMethod, "POST")
    }

    // OR-028 — hengyin #866 RegistrationQuoteResult.validFrom/validTo (java.util.Date)
    func testQuoteValidityReadsServerDateAsCalendarDay() throws {
        func quote(_ fields: String) throws -> RegistrationQuote { try JSONDecoder().decode(RegistrationQuote.self, from: Data("{\"payAmount\":0,\"quoteSign\":\"s\"\(fields)}".utf8)) }
        let iso = try quote(#","validFrom":"2026-11-19T10:00:00.000+08:00","validTo":"2027-02-17T23:59:59.000+08:00""#)
        XCTAssertEqual(iso.validFrom, "2026-11-19"); XCTAssertEqual(iso.validTo, "2027-02-17")
        let millis = try quote(#","validFrom":1795000000000"#)
        XCTAssertEqual(millis.validFrom, "2026-11-18")
        XCTAssertNil(try quote(#","validFrom":"soon""#).validFrom)
        XCTAssertNil(try quote("").validTo)
    }
}

private final class Verify1119Transport: HTTPTransport {
    private let handler: (URLRequest) throws -> (Data, Int)
    private(set) var requests: [URLRequest] = []
    init(_ handler: @escaping (URLRequest) throws -> (Data, Int)) { self.handler = handler }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return try handler(request) }
}
