import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// FE-STORY 7.10 author 「到访方式」 contract. Synthetic places and transport only.
@MainActor final class FreeExplorationVisitConfigTests: XCTestCase {
    private let list = #"{"code":200,"data":[{"nodeId":701,"name":"示例站点 A","chapterId":81,"visitCheck":"GPS","visitRadius":null,"hasCoordinates":true},{"nodeId":702,"name":"示例站点 B","chapterId":82,"visitCheck":"scan","visitRadius":null,"hasCoordinates":false},{"nodeId":703,"name":"示例站点 C","chapterId":83,"visitCheck":"ONLINE","visitRadius":null,"hasCoordinates":false}]}"#
    private func service(_ wire: VisitConfigWire, writes: Bool = true) throws -> FreeExplorationVisitConfigService {
        .init(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire, authorWrites: writes, token: { "synthetic" })
    }
    private func row(_ json: String) throws -> FreeExplorationVisitConfigRow { try .init(raw: PlayExperienceSyntheticFixtures.wire(json)) }
    private func json(_ request: URLRequest?) throws -> [String: PlayWireValue] {
        try XCTUnwrap(JSONDecoder().decode(PlayWireValue.self, from: XCTUnwrap(request?.httpBody)).object)
    }

    func testRowsDecodeAndRejectUnknownCheck() throws {
        let gps = try row(#"{"nodeId":701,"visitCheck":"GPS","visitRadius":null,"hasCoordinates":true}"#)
        XCTAssertEqual(gps.visitCheck, .gps); XCTAssertNil(gps.visitRadius); XCTAssertEqual(gps.effectiveRadius, 300)
        XCTAssertEqual(try row(#"{"nodeId":701,"visitCheck":"GPS","visitRadius":450,"hasCoordinates":true}"#).effectiveRadius, 450)
        XCTAssertNil(try row(#"{"nodeId":702,"visitCheck":"SCAN","visitRadius":null,"hasCoordinates":false}"#).effectiveRadius)
        for bad in [#"{"nodeId":701,"visitCheck":"BEACON","hasCoordinates":true}"#, #"{"nodeId":701,"visitCheck":"GPS"}"#,
                    #"{"nodeId":0,"visitCheck":"GPS","hasCoordinates":true}"#, #"{"nodeId":701,"visitCheck":"GPS","visitRadius":"far","hasCoordinates":true}"#] {
            XCTAssertThrowsError(try row(bad), bad)
        }
    }

    func testChangeValidationAndExactBody() throws {
        for radius in [300, 400, 500] { XCTAssertNoThrow(try FreeExplorationVisitConfigChange(nodeID: 701, visitCheck: .gps, visitRadius: radius)) }
        for radius in [nil, 250, 350, 600] as [Int?] {
            XCTAssertThrowsError(try FreeExplorationVisitConfigChange(nodeID: 701, visitCheck: .gps, visitRadius: radius)) { XCTAssertEqual($0 as? FreeExplorationVisitConfigError, .radiusInvalid) }
        }
        XCTAssertThrowsError(try FreeExplorationVisitConfigChange(nodeID: 701, visitCheck: .scan, visitRadius: 300))
        let scan = try FreeExplorationVisitConfigChange(nodeID: 701, visitCheck: .scan, visitRadius: nil)
        XCTAssertEqual(scan.body, ["nodeId": .integer(701), "visitCheck": .string("SCAN"), "visitRadius": .null])
        XCTAssertEqual(try FreeExplorationVisitConfigChange(nodeID: 701, visitCheck: .gps, visitRadius: 400).body["visitRadius"], .integer(400))
    }

    func testLoadReadsTopicListWithGet() async throws {
        let wire = VisitConfigWire(); wire.replies = [(Data(list.utf8), 200)]
        let rows = try await service(wire).load(topicID: 71)
        XCTAssertEqual(rows.map(\.id), [701, 702, 703]); XCTAssertEqual(rows.map(\.visitCheck), [.gps, .scan, .online])
        let request = try XCTUnwrap(wire.requests.first)
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.url?.path, "/api/topic/free-explore/visit-config")
        XCTAssertEqual(request.url?.query, "topicId=71"); XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic")
    }

    func testWritesStayOffByDefaultAndLocalPrecheckSendsNothing() async throws {
        let wire = VisitConfigWire(), rows = [try row(#"{"nodeId":702,"visitCheck":"SCAN","visitRadius":null,"hasCoordinates":false}"#)]
        let dormant = FreeExplorationVisitConfigService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire, token: { "synthetic" })
        XCTAssertFalse(dormant.authorWrites)
        let change = try FreeExplorationVisitConfigChange(nodeID: 702, visitCheck: .gps, visitRadius: 300)
        do { try await dormant.save(change, current: rows[0]); XCTFail() } catch { XCTAssertEqual(error as? FreeExplorationVisitConfigError, .disabled) }
        do { try await service(wire).save(change, current: rows[0]); XCTFail() } catch { XCTAssertEqual(error as? FreeExplorationVisitConfigError, .gpsCoordinatesRequired) }
        XCTAssertTrue(wire.requests.isEmpty)
    }

    func testSavePostsJSONAndMapsServerRefusals() async throws {
        let current = try row(#"{"nodeId":701,"visitCheck":"GPS","visitRadius":null,"hasCoordinates":true}"#)
        let change = try FreeExplorationVisitConfigChange(nodeID: 701, visitCheck: .gps, visitRadius: 500)
        let wire = VisitConfigWire(); wire.replies = [(Data(#"{"code":200,"data":null}"#.utf8), 200)]
        try await service(wire).save(change, current: current)
        let request = try XCTUnwrap(wire.requests.first)
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(try json(request), ["nodeId": .integer(701), "visitCheck": .string("GPS"), "visitRadius": .integer(500)])
        let cases: [(String, Int, FreeExplorationVisitConfigError)] = [
            (#"{"code":400,"msg":"Synthetic","errorCode":"VISIT_RADIUS_INVALID"}"#, 200, .radiusInvalid),
            (#"{"code":400,"msg":"VISIT_GPS_COORD_REQUIRED"}"#, 200, .gpsCoordinatesRequired),
            (#"{"code":400,"data":{"errorCode":"VISIT_CHECK_INVALID"}}"#, 200, .checkInvalid),
            (#"{"code":403,"msg":"Synthetic"}"#, 200, .forbidden), (#"{}"#, 403, .forbidden),
            (#"{"code":500,"msg":"Synthetic other"}"#, 200, .rejected("Synthetic other")),
            (#"<html>"#, 502, .unknownResult), (#"{"code":401}"#, 200, .unauthorized)
        ]
        for (body, status, expected) in cases {
            let wire = VisitConfigWire(); wire.replies = [(Data(body.utf8), status)]
            do { try await service(wire).save(change, current: current); XCTFail(body) }
            catch { XCTAssertEqual(error as? FreeExplorationVisitConfigError, expected, body) }
            XCTAssertEqual(wire.requests.count, 1)
        }
    }

    func testUnknownSaveRereadsListAndNeverResends() async throws {
        let wire = VisitConfigWire()
        wire.replies = [(Data(list.utf8), 200), (Data(), 0), (Data(list.utf8), 200)]
        wire.failAt = 1
        let model = FreeExplorationVisitConfigModel(topicID: 71, service: try service(wire))
        await model.load(); XCTAssertEqual(model.phase, .ready); XCTAssertTrue(model.canWrite)
        await model.save(nodeID: 701, visitCheck: .gps, visitRadius: 400)
        // The list was read again (never the POST); a fresh list resolves the unknown save.
        XCTAssertEqual(wire.requests.map(\.httpMethod), ["GET", "POST", "GET"])
        XCTAssertEqual(model.saves[701], nil)
        XCTAssertEqual(model.rows.first?.visitRadius, nil)
        await model.save(nodeID: 701, visitCheck: .gps, visitRadius: 400)
        XCTAssertEqual(wire.requests.filter { $0.httpMethod == "POST" }.count, 2)
    }

    func testUnknownSaveStaysBlockedWhileRereadFails() async throws {
        let wire = VisitConfigWire()
        wire.replies = [(Data(list.utf8), 200), (Data(), 0), (Data("{}".utf8), 500)]
        wire.failAt = 1
        let model = FreeExplorationVisitConfigModel(topicID: 71, service: try service(wire))
        await model.load()
        await model.save(nodeID: 701, visitCheck: .scan, visitRadius: nil)
        XCTAssertEqual(model.saves[701], .unknown); XCTAssertFalse(model.canWrite)
        await model.save(nodeID: 702, visitCheck: .online, visitRadius: nil)
        XCTAssertEqual(wire.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }

    func testModelWithoutWriteGrantNeverWrites() async throws {
        let wire = VisitConfigWire(); wire.replies = [(Data(list.utf8), 200)]
        let model = FreeExplorationVisitConfigModel(topicID: 71, service: try service(wire, writes: false))
        await model.load(); XCTAssertEqual(model.rows.count, 3); XCTAssertFalse(model.canWrite)
        await model.save(nodeID: 702, visitCheck: .online, visitRadius: nil)
        XCTAssertEqual(wire.requests.count, 1); XCTAssertNil(model.saves[702])
    }
}

@MainActor private final class VisitConfigWire: HTTPTransport {
    var replies: [(Data, Int)] = []
    var failAt: Int?
    private(set) var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let index = requests.count; requests.append(request)
        if index == failAt { throw URLError(.networkConnectionLost) }
        guard index < replies.count else { throw URLError(.badServerResponse) }
        return replies[index]
    }
}
