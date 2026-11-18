import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// F07 / F08 / FE-STORY contract decoding, story gate truth table and the arrival
/// write path through the durable coordinator. All identifiers are synthetic.
@MainActor final class PlayArrivalContractTests: XCTestCase {
    private func result(_ json: String) throws -> PlayNodesResult { try JSONDecoder().decode(PlayNodesResult.self, from: Data(json.utf8)) }
    private func snapshot(_ json: String) throws -> PlaySnapshot { try PlaySnapshot(scope: .activity(41), result: result(json)) }
    private func freeNodes(_ node: String, extra: String = "") -> String {
        #"{"mode":2,"registered":true,"playable":true,"total":1,"doneCount":0"# + extra + #","nodes":["# + node + "]}"
    }

    // MARK: Decoding

    func testFreeExplorationVisitFieldsDecode() throws {
        let value = try result(freeNodes(#"{"nodeId":701,"name":"示例站点","visited":true,"visitTime":"2026-11-17 10:00:00","visitCheck":"SCAN","visitRadius":420,"storyLocked":false,"storyText":"Synthetic chapter"}"#,
                                         extra: #","storyUnlocked":1,"storyTotal":4,"chapters":[{"chapterId":81,"name":"Synthetic chapter","chapterLocked":false}]"#))
        let node = try XCTUnwrap(value.nodes.first)
        XCTAssertEqual(node.visited, true); XCTAssertEqual(node.visitTime, .text("2026-11-17 10:00:00"))
        XCTAssertEqual(node.visitCheck, .scan); XCTAssertEqual(node.visitRadius, 420); XCTAssertEqual(node.storyLocked, false)
        XCTAssertEqual(value.storyUnlocked, 1); XCTAssertEqual(value.storyTotal, 4)
        XCTAssertEqual(value.chapters.first?.chapterLocked, false)
    }

    func testMissingOrMalformedNewFieldsFallBackToUnknown() throws {
        let missing = try result(freeNodes(#"{"nodeId":701}"#))
        let node = try XCTUnwrap(missing.nodes.first)
        XCTAssertNil(node.visited); XCTAssertNil(node.visitTime); XCTAssertNil(node.visitCheck)
        XCTAssertNil(node.visitRadius); XCTAssertNil(node.storyLocked); XCTAssertNil(node.imgHidden)
        XCTAssertNil(missing.storyUnlocked); XCTAssertNil(missing.storyTotal)
        // Additive fields never break an otherwise valid read.
        let malformed = try result(freeNodes(#"{"nodeId":701,"visited":"maybe","storyLocked":7,"visitCheck":"BEACON","visitRadius":"far","visitTime":{"x":1}}"#,
                                            extra: #","storyUnlocked":5,"storyTotal":2,"chapters":[{"chapterId":81,"chapterLocked":"?"}]"#))
        let bad = try XCTUnwrap(malformed.nodes.first)
        XCTAssertNil(bad.visited); XCTAssertNil(bad.storyLocked); XCTAssertNil(bad.visitCheck); XCTAssertNil(bad.visitRadius); XCTAssertNil(bad.visitTime)
        XCTAssertNil(malformed.storyUnlocked); XCTAssertNil(malformed.storyTotal); XCTAssertNil(malformed.chapters.first?.chapterLocked)
    }

    func testVisitTimeEpochAndLowercaseCheck() throws {
        let node = try XCTUnwrap(try result(freeNodes(#"{"nodeId":701,"visitTime":1763344800000,"visitCheck":"gps","visitRadius":0}"#)).nodes.first)
        XCTAssertEqual(node.visitTime, .epochMilliseconds(1_763_344_800_000))
        XCTAssertEqual(node.visitTime?.date, Date(timeIntervalSince1970: 1_763_344_800))
        XCTAssertEqual(node.visitCheck, .gps); XCTAssertNil(node.visitRadius)
    }

    func testImgHiddenDecodesForLaterCityStation() throws {
        let value = try result(#"{"mode":1,"registered":true,"playable":true,"nodes":[{"nodeId":701,"imgUrl":"https://example.test/a.jpg"},{"nodeId":702,"imgUrl":null,"imgHidden":true},{"nodeId":703,"imgHidden":0}]}"#)
        XCTAssertEqual(value.nodes.map(\.imgHidden), [nil, true, false])
    }

    // MARK: Story gate truth table

    func testIsStoryLockedTruthTable() throws {
        for (field, expected) in [("", true), (#","storyLocked":true"#, true), (#","storyLocked":false"#, false), (#","storyLocked":null"#, true)] {
            let value = try snapshot(freeNodes(#"{"nodeId":701"# + field + "}"))
            XCTAssertEqual(value.isStoryLocked(value.result.nodes[0]), expected, "mode 2 \(field)")
        }
        // City routes never use the story gate, whatever the payload says.
        for field in ["", #","storyLocked":true"#, #","storyLocked":false"#] {
            let city = try snapshot(#"{"mode":1,"registered":true,"playable":true,"nodes":[{"nodeId":701"# + field + "}]}")
            XCTAssertFalse(city.isStoryLocked(city.result.nodes[0]), "mode 1 \(field)")
            XCTAssertFalse(city.isVisited(city.result.nodes[0]))
        }
    }

    func testStoryGateDoesNotChangeRouteLock() throws {
        let value = try snapshot(freeNodes(#"{"nodeId":701,"storyLocked":true,"done":false}"#))
        XCTAssertTrue(value.isStoryLocked(value.result.nodes[0])); XCTAssertFalse(value.isLocked(value.result.nodes[0]))
    }

    func testPresentationCountsAndAllVisitedEnding() throws {
        let partial = try snapshot(#"{"mode":2,"registered":true,"playable":true,"total":2,"doneCount":0,"storyUnlocked":1,"storyTotal":2,"nodes":[{"nodeId":701,"done":false,"storyLocked":false},{"nodeId":702,"done":false}]}"#)
        let presentation = try XCTUnwrap(FreeExplorationPresentation(snapshot: partial))
        XCTAssertEqual(presentation.storyUnlocked, 1); XCTAssertEqual(presentation.storyTotal, 2); XCTAssertFalse(presentation.isFullyVisited)
        let all = try snapshot(#"{"mode":2,"registered":true,"playable":true,"total":2,"doneCount":0,"nodes":[{"nodeId":701,"done":false,"visited":true,"storyLocked":false},{"nodeId":702,"done":false,"storyLocked":false}]}"#)
        XCTAssertTrue(try XCTUnwrap(FreeExplorationPresentation(snapshot: all)).isFullyVisited)
    }

    // MARK: Request and refusal contract

    func testArrivalRejectionParsing() throws {
        let envelope = try PlayExperienceSyntheticFixtures.wire(#"{"code":500,"msg":"离这里还有约 340 米","errorCode":"ARRIVE_TOO_FAR","distanceMeters":337}"#)
        let rejection = try XCTUnwrap(PlayArrivalRejection(envelope: envelope))
        XCTAssertEqual(rejection.reason, .tooFar); XCTAssertEqual(rejection.distanceMeters, 340); XCTAssertFalse(rejection.checkedLocally)
        XCTAssertTrue(rejection.provesNoCommit)
        for code in ["ARRIVE_ACCURACY_LOW", "ARRIVE_LOCATION_MISSING", "VISIT_SCAN_REQUIRED"] {
            XCTAssertEqual(PlayArrivalRejection(envelope: try PlayExperienceSyntheticFixtures.wire(#"{"code":500,"errorCode":""# + code + #""}"#))?.reason.rawValue, code)
        }
        XCTAssertNil(PlayArrivalRejection(envelope: try PlayExperienceSyntheticFixtures.wire(#"{"code":500,"errorCode":"ARRIVE_GUARD_SPEED"}"#)))
        XCTAssertNil(PlayArrivalRejection(envelope: try PlayExperienceSyntheticFixtures.wire(#"{"code":500,"msg":"plain"}"#)))
    }

    func testArrivalReadingValidationAndPersistence() throws {
        XCTAssertTrue(PlayArrivalReading.tap.isValid); XCTAssertFalse(PlayArrivalReading.tap.isLocated)
        let coordinate = try XCTUnwrap(RoamCoordinate(latitude: 31.2304, longitude: 121.4737))
        XCTAssertThrowsError(try PlayArrivalReading(gcj02: RoamDeviceFix(coordinate: coordinate, accuracyMeters: 10, measuredAt: Date(), datum: .wgs84)))
        let located = try PlayArrivalReading(gcj02: RoamDeviceFix(coordinate: coordinate, accuracyMeters: 10, measuredAt: Date(), datum: .gcj02))
        XCTAssertTrue(located.isLocated)
        for evidence in [PlayCompletionEvidence.arrival(.tap), .arrival(located)] {
            let data = try PropertyListEncoder().encode([evidence])
            XCTAssertEqual(try PropertyListDecoder().decode([PlayCompletionEvidence].self, from: data), [evidence])
        }
    }

    func testArrivalProjectionAllowsPolicyAccuracyButRejectsStaleFix() throws {
        let coordinate = try XCTUnwrap(RoamCoordinate(latitude: 31.2304, longitude: 121.4737)), now = Date()
        let projected = try RuntimeLocationProjection.gcj02ArrivalFix(RoamDeviceFix(coordinate: coordinate, accuracyMeters: 180, measuredAt: now, datum: .wgs84), now: now)
        XCTAssertEqual(projected.datum, .gcj02); XCTAssertEqual(projected.accuracyMeters, 180)
        XCTAssertNotEqual(projected.coordinate, coordinate)
        XCTAssertThrowsError(try RuntimeLocationProjection.gcj02ArrivalFix(RoamDeviceFix(coordinate: coordinate, accuracyMeters: 10, measuredAt: now.addingTimeInterval(-60), datum: .wgs84), now: now))
    }

    // MARK: Arrival service through the durable coordinator

    private func session() throws -> PlayExperienceSession { try .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic") }
    private func coordinator(_ wire: PlayRecoveryRecordingTransport, enabled: Set<PlayExperienceCapability> = [.reads, .classicCompletion]) throws -> PlayExperienceCoordinator {
        let owner = try session()
        return .init(scope: .activity(41), service: .init(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire, enabled: enabled),
                     recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(), currentSession: { owner })
    }
    private func body(_ request: URLRequest?) -> String { request?.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? "" }
    private func arrivals(_ wire: PlayRecoveryRecordingTransport) -> [URLRequest] { wire.requests.filter { $0.url?.path == "/api/play/arrive" } }
    private let startedCity = #"{"mode":1,"registered":true,"playable":true,"total":2,"doneCount":1,"nodes":[{"nodeId":701,"done":true,"validationMethod":0},{"nodeId":702,"done":false,"validationMethod":0,"latitude":31.2304,"longitude":121.4737}]}"#
    private let freshCity = #"{"mode":1,"registered":true,"playable":true,"total":1,"doneCount":0,"nodes":[{"nodeId":701,"done":false,"validationMethod":0,"latitude":31.2304,"longitude":121.4737}]}"#
    private let lockedPlace = #"{"mode":2,"registered":true,"playable":true,"total":1,"doneCount":0,"nodes":[{"nodeId":701,"name":"示例站点","done":false,"arrived":false,"visitCheck":"GPS","latitude":31.2304,"longitude":121.4737,"hookText":"Synthetic hook"}]}"#

    func testStationTapAfterStartSendsNoLocation() async throws {
        let wire = PlayRecoveryRecordingTransport()
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(startedCity), 200)
        wire.responses["/api/play/arrive"] = .reply(PlayExperienceSyntheticFixtures.envelope(#"{"nodeId":702,"firstTime":true}"#), 200)
        wire.afterCompletion["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(startedCity.replacingOccurrences(of: #""nodeId":702,"done":false"#, with: #""nodeId":702,"done":true"#)), 200)
        let runtime = try coordinator(wire); await runtime.load()
        let location = ArrivalFixSpy(fix: nil), arrival = PlayArrivalService(runtime: runtime, location: location)
        XCTAssertEqual(arrival.offer(for: 702), .stationTap); XCTAssertNil(arrival.offer(for: 701))
        await arrival.arrive(nodeID: 702, context: runtime.interactionContext)
        XCTAssertEqual(arrival.phase, .succeeded); XCTAssertEqual(location.reads, 0)
        let sent = try XCTUnwrap(arrivals(wire).first); XCTAssertEqual(arrivals(wire).count, 1)
        XCTAssertTrue(body(sent).contains("name=\"nodeId\"")); XCTAssertFalse(body(sent).contains("longitude"))
        XCTAssertFalse(runtime.unresolved)
    }

    func testStartCheckTooFarIsRejectedLocallyWithoutRequest() async throws {
        let wire = PlayRecoveryRecordingTransport()
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(freshCity), 200)
        let runtime = try coordinator(wire); await runtime.load()
        // ~1.1 km north of the start, already GCJ-02, good accuracy.
        let arrival = PlayArrivalService(runtime: runtime, location: ArrivalFixSpy(fix: try fix(latitude: 31.2404, longitude: 121.4737, accuracy: 20)))
        XCTAssertEqual(arrival.offer(for: 701), .start)
        await arrival.arrive(nodeID: 701, context: runtime.interactionContext)
        guard case .rejected(let rejection) = arrival.phase else { return XCTFail("\(arrival.phase)") }
        XCTAssertEqual(rejection.reason, .tooFar); XCTAssertTrue(rejection.checkedLocally); XCTAssertEqual(rejection.distanceMeters, 1110)
        XCTAssertTrue(arrivals(wire).isEmpty)
    }

    func testStartCheckWithinRelaxedRadiusSendsLocatedArrival() async throws {
        let wire = PlayRecoveryRecordingTransport()
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(freshCity), 200)
        wire.responses["/api/play/arrive"] = .reply(PlayExperienceSyntheticFixtures.envelope(#"{"nodeId":701,"firstTime":true}"#), 200)
        let runtime = try coordinator(wire); await runtime.load()
        // ~420 m away with 150 m accuracy passes the v2 start rule.
        let arrival = PlayArrivalService(runtime: runtime, location: ArrivalFixSpy(fix: try fix(latitude: 31.23418, longitude: 121.4737, accuracy: 150)))
        await arrival.arrive(nodeID: 701, context: runtime.interactionContext)
        XCTAssertEqual(arrival.phase, .succeeded)
        let text = body(try XCTUnwrap(arrivals(wire).first))
        for field in ["longitude", "latitude", "accuracy"] { XCTAssertTrue(text.contains("name=\"\(field)\""), field) }
    }

    func testFreeVisitServerRefusalClearsJournalAndShowsDistance() async throws {
        let wire = PlayRecoveryRecordingTransport()
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(lockedPlace), 200)
        wire.responses["/api/play/arrive"] = .reply(Data(#"{"code":500,"msg":"Synthetic refusal","errorCode":"ARRIVE_TOO_FAR","distanceMeters":337}"#.utf8), 200)
        let runtime = try coordinator(wire); await runtime.load()
        let arrival = PlayArrivalService(runtime: runtime, location: ArrivalFixSpy(fix: try fix(latitude: 31.2304, longitude: 121.4737, accuracy: 10)))
        XCTAssertEqual(arrival.offer(for: 701), .freeVisit)
        await arrival.arrive(nodeID: 701, context: runtime.interactionContext)
        guard case .rejected(let rejection) = arrival.phase else { return XCTFail("\(arrival.phase)") }
        XCTAssertEqual(rejection.reason, .tooFar); XCTAssertEqual(rejection.distanceMeters, 340); XCTAssertFalse(rejection.checkedLocally)
        XCTAssertFalse(runtime.unresolved); XCTAssertTrue(runtime.canSubmitArrival)
        XCTAssertTrue(body(try XCTUnwrap(arrivals(wire).first)).contains("name=\"accuracy\""))
    }

    func testUnknownOutcomeRereadsAndNeverResends() async throws {
        let wire = PlayRecoveryRecordingTransport()
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(lockedPlace), 200)
        wire.responses["/api/play/arrive"] = .failure(.unknownResult)
        let runtime = try coordinator(wire); await runtime.load()
        let arrival = PlayArrivalService(runtime: runtime, location: ArrivalFixSpy(fix: try fix(latitude: 31.2304, longitude: 121.4737, accuracy: 10)))
        await arrival.arrive(nodeID: 701, context: runtime.interactionContext)
        XCTAssertEqual(arrival.phase, .unknown); XCTAssertTrue(runtime.unresolved)
        await arrival.arrive(nodeID: 701, context: runtime.interactionContext)
        XCTAssertEqual(arrivals(wire).count, 1)
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(lockedPlace.replacingOccurrences(of: #""arrived":false"#, with: #""arrived":true,"visited":true,"storyLocked":false"#)), 200)
        await arrival.reread()
        XCTAssertEqual(arrival.phase, .succeeded); XCTAssertFalse(runtime.unresolved); XCTAssertEqual(arrivals(wire).count, 1)
    }

    func testScanConfiguredPlaceAndDisabledGrantOfferNoGPSWrite() async throws {
        let wire = PlayRecoveryRecordingTransport()
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(lockedPlace.replacingOccurrences(of: #""visitCheck":"GPS""#, with: #""visitCheck":"SCAN""#)), 200)
        let scanRuntime = try coordinator(wire); await scanRuntime.load()
        XCTAssertNil(PlayArrivalService(runtime: scanRuntime, location: nil).offer(for: 701))
        let other = PlayRecoveryRecordingTransport()
        other.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(lockedPlace), 200)
        let readOnly = try coordinator(other, enabled: [.reads]); await readOnly.load()
        let arrival = PlayArrivalService(runtime: readOnly, location: ArrivalFixSpy(fix: try fix(latitude: 31.2304, longitude: 121.4737, accuracy: 10)))
        await arrival.arrive(nodeID: 701, context: readOnly.interactionContext)
        XCTAssertEqual(arrival.phase, .unavailable); XCTAssertTrue(arrivals(other).isEmpty)
    }

    private func fix(latitude: Double, longitude: Double, accuracy: Double) throws -> RoamDeviceFix {
        try RoamDeviceFix(coordinate: XCTUnwrap(RoamCoordinate(latitude: latitude, longitude: longitude)), accuracyMeters: accuracy, measuredAt: Date(), datum: .gcj02)
    }
}

@MainActor private final class ArrivalFixSpy: RoamDeviceLocationProviding {
    private let fix: RoamDeviceFix?
    private(set) var reads = 0
    init(fix: RoamDeviceFix?) { self.fix = fix }
    func currentFix() async throws -> RoamDeviceFix {
        reads += 1
        guard let fix else { throw PlayExperienceError.disabled }
        return fix
    }
    func stop() {}
}
