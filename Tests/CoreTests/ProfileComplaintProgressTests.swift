import XCTest
@testable import QuestifyCore

@MainActor final class ProfileComplaintProgressTests: XCTestCase {
    private final class Reader: CoopFlowReading {
        var session: CoopFlowSession? = try? .init(accountID: 4, epoch: 1, token: "synthetic-token")
        var value: CoopFlowJSON = .array([.object(["id": .id(9), "topicId": .id(7), "topicName": .string("Test topic"), "status": .id(2),
                                                   "statusText": .string("处理中"), "reason": .string("Reason"), "handleNote": .string("Note")])])
        var error: Error?
        var resources: [CoopFlowRead] = []
        func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON {
            resources.append(resource)
            if let error { throw error }; return value
        }
        func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement { XCTFail("unrelated read"); throw APIError.notConfigured }
    }
    func testReadsOnlyTheOwnersProgressEndpointWithNoBody() throws {
        XCTAssertEqual(CoopFlowRead.complaintProgress.path, "api/coop/complaint/mine")
        XCTAssertTrue(CoopFlowRead.complaintProgress.expectsArray)
        XCTAssertEqual(try CoopFlowRead.complaintProgress.body(), .object([:]))
    }
    func testDecodesOnlyRenderedFields() throws {
        let rows = try ProfileComplaintProgressRow.decode(Reader().value)
        XCTAssertEqual(rows, [.init(id: 9, topicName: "Test topic", statusText: "处理中", reason: "Reason", handleNote: "Note")])
    }
    func testOneRowWithoutIDRejectsTheWholeArray() {
        let value: CoopFlowJSON = .array([.object(["id": .id(9)]), .object(["topicName": .string("No id")])])
        XCTAssertThrowsError(try ProfileComplaintProgressRow.decode(value))
        XCTAssertThrowsError(try ProfileComplaintProgressRow.decode(.array([.object(["id": .id(0)])])))
        XCTAssertThrowsError(try ProfileComplaintProgressRow.decode(.object(["rows": .array([])])))
        XCTAssertThrowsError(try ProfileComplaintProgressRow.decode(.array([.string("row")])))
    }
    func testMissingTextStaysUnknownInsteadOfInvented() throws {
        let rows = try ProfileComplaintProgressRow.decode(.array([.object(["id": .id(3), "statusText": .string("  "), "handleNote": .null])]))
        XCTAssertNil(rows.first?.topicName); XCTAssertNil(rows.first?.statusText); XCTAssertNil(rows.first?.handleNote)
    }
    func testAccessFailuresMatchSourceCodes() {
        XCTAssertEqual(ProfileComplaintProgressIssue(APIError.unauthorized), .signIn)
        XCTAssertEqual(ProfileComplaintProgressIssue(CoopFlowFailure.server(401, nil)), .signIn)
        for code in [400, 403, 422] {
            XCTAssertEqual(ProfileComplaintProgressIssue(CoopFlowFailure.server(code, " 无权限 ")), .denied("无权限"))
            XCTAssertEqual(ProfileComplaintProgressIssue(CoopFlowFailure.server(code, nil)), .denied(nil))
        }
        XCTAssertNil(ProfileComplaintProgressIssue(CoopFlowFailure.server(500, "busy")))
        XCTAssertNil(ProfileComplaintProgressIssue(CoopFlowFailure.malformed))
    }
    func testLoadReadsProgressAndDeniedClearsRows() async {
        let reader = Reader()
        let model = ProfileComplaintProgressController(reader: reader, isCurrent: { true })
        await model.load()
        XCTAssertEqual(reader.resources, [.complaintProgress]); XCTAssertEqual(model.rows.map(\.id), [9])
        reader.error = CoopFlowFailure.server(403, nil)
        await model.load()
        XCTAssertEqual(model.rows, []); XCTAssertEqual(model.issue, .denied(nil))
    }
    func testOtherFailureKeepsLastRowsSilently() async {
        let reader = Reader()
        let model = ProfileComplaintProgressController(reader: reader, isCurrent: { true })
        await model.load()
        reader.error = CoopFlowFailure.server(503, nil)
        await model.load()
        XCTAssertEqual(model.rows.map(\.id), [9]); XCTAssertNil(model.issue)
    }
    func testSignedOutNeverReads() async {
        let reader = Reader(); reader.session = nil
        let model = ProfileComplaintProgressController(reader: reader, isCurrent: { true })
        await model.load()
        XCTAssertEqual(reader.resources, []); XCTAssertEqual(model.issue, .signIn)
    }
    func testAccountChangeRetiresWithoutReading() async {
        let reader = Reader()
        let model = ProfileComplaintProgressController(reader: reader, isCurrent: { true })
        await model.load()
        reader.session = try? .init(accountID: 5, epoch: 2, token: "synthetic-token")
        await model.load()
        XCTAssertEqual(reader.resources, [.complaintProgress]); XCTAssertEqual(model.rows, []); XCTAssertFalse(model.contextMatches)
    }
}
