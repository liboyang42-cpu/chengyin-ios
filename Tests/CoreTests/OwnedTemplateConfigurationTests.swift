import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 14.0, *)
@MainActor final class OwnedTemplateConfigurationTests: XCTestCase {
    private let id = MemberPlayTemplateID(rawValue: 101)!
    private func response(_ extra: [String: Any] = [:]) throws -> Data {
        var fields: [String: Any] = ["id": 101, "memberId": 7, "title": "Exact owner title", "validationMethod": 1, "questionName": "Question", "questionAnswer": "Exact secret"]
        fields.merge(extra) { _, new in new }
        return try JSONSerialization.data(withJSONObject: ["code": 200, "data": fields], options: [.sortedKeys])
    }
    func testPreferenceAndMedalAreOwnerOnlyExactPresence() throws {
        let raw = #"{"code":200,"data":{"id":42,"memberId":7,"preferenceJson":"  {invalid}  ","medalStyle":"future"}}"#
        let id = try XCTUnwrap(MemberPlayTemplateID(rawValue: 42))
        let snapshot = try OwnedTemplateConfigurationSnapshot(response: Data(raw.utf8), requestedID: id, accountID: 7)
        XCTAssertEqual(snapshot.preferenceJson, .value("  {invalid}  "))
        XCTAssertEqual(snapshot.medalStyle, .value("future"))
        XCTAssertTrue(snapshot.hasExactBaseline(Data(raw.utf8)))
        XCTAssertThrowsError(try OwnedTemplateConfigurationSnapshot(response: Data(raw.utf8), requestedID: id, accountID: 8))
        let missing = try OwnedTemplateConfigurationSnapshot(response: Data(#"{"code":200,"data":{"id":42,"memberId":7,"medalStyle":null}}"#.utf8), requestedID: id, accountID: 7)
        XCTAssertEqual(missing.preferenceJson, .missing); XCTAssertEqual(missing.medalStyle, .null)
        let wrongTypes = Data(#"{"code":200,"data":{"id":42,"memberId":7,"preferenceJson":{"steps":[]},"medalStyle":true}}"#.utf8)
        let unsupported = try OwnedTemplateConfigurationSnapshot(response: wrongTypes, requestedID: id, accountID: 7)
        XCTAssertEqual(unsupported.preferenceJson, .unsupported); XCTAssertEqual(unsupported.medalStyle, .unsupported)
        XCTAssertTrue(unsupported.hasExactBaseline(wrongTypes))

    }
    func testFreshOwnerOnlyProjectionKeepsExactBaselineAndDistinctProvenance() throws {
        let bytes = try response(["originalTemplateId": 72, "futureSecret": ["unknown": [1, 2]], "advancedConfigJson": "{\"future\":{\"answer\":\"retain\"}}"])
        let snapshot = try OwnedTemplateConfigurationSnapshot(response: bytes, requestedID: id, accountID: 7)
        XCTAssertEqual(snapshot.id, id); XCTAssertEqual(snapshot.provenance, .value(72))
        XCTAssertEqual(snapshot.field(.questionAnswer), .value("Exact secret")); XCTAssertEqual(snapshot.supportedQAMethod, .text)
        XCTAssertTrue(snapshot.hasExactBaseline(bytes)); XCTAssertTrue(snapshot.unsupportedFields.contains("futureSecret"))
        XCTAssertTrue(snapshot.unsupportedFields.contains("advancedConfigJson"))
        let publicDetail = try JSONDecoder().decode(PlayWireValue.self, from: bytes)["data"].decoded(MemberTemplateDetail.self)
        XCTAssertFalse(Mirror(reflecting: publicDetail).children.contains { $0.label == "questionAnswer" || $0.label == "advancedConfigJson" })
    }
    func testChoiceOptionMediaIsOwnerOnlyExactReadWithMissingAndUnsupportedStates() throws {
        let raw = "\n{\"A\":{\"img\":\" exact-image \",\"future\":true}}\n"
        let bytes = try response(["validationMethod": 3, "questionOptionMediaJson": raw])
        let snapshot = try OwnedTemplateConfigurationSnapshot(response: bytes, requestedID: id, accountID: 7)
        XCTAssertEqual(snapshot.questionOptionMediaJson, .value(raw))
        XCTAssertEqual(snapshot.choiceOptionMedia?.text(.a, .image), " exact-image ")
        XCTAssertEqual(snapshot.choiceOptionMedia?.isSupported, false)
        XCTAssertTrue(snapshot.unsupportedFields.contains("questionOptionMediaJson"))
        XCTAssertTrue(snapshot.hasExactBaseline(bytes))
        XCTAssertThrowsError(try OwnedTemplateConfigurationSnapshot(response: bytes, requestedID: id, accountID: 8))
        let missing = try OwnedTemplateConfigurationSnapshot(response: response(), requestedID: id, accountID: 7)
        XCTAssertEqual(missing.questionOptionMediaJson, .missing); XCTAssertNil(missing.choiceOptionMedia)
        let null = try OwnedTemplateConfigurationSnapshot(response: response(["questionOptionMediaJson": NSNull()]), requestedID: id, accountID: 7)
        XCTAssertEqual(null.questionOptionMediaJson, .null); XCTAssertNil(null.choiceOptionMedia)
        let unsupported = try OwnedTemplateConfigurationSnapshot(response: response(["questionOptionMediaJson": ["A": "wrong"]]), requestedID: id, accountID: 7)
        XCTAssertEqual(unsupported.questionOptionMediaJson, .unsupported); XCTAssertNil(unsupported.choiceOptionMedia)
        let malformed = try OwnedTemplateConfigurationSnapshot(response: response(["questionOptionMediaJson": "{unfinished"]), requestedID: id, accountID: 7)
        XCTAssertEqual(malformed.questionOptionMediaJson, .value("{unfinished"))
        XCTAssertEqual(malformed.choiceOptionMedia?.isSupported, false)
        let valid = try OwnedTemplateConfigurationSnapshot(response: response(["validationMethod": 3, "questionOptionMediaJson": #"{"D":{"audio":"audio-d"}}"#]), requestedID: id, accountID: 7)
        XCTAssertEqual(valid.choiceOptionMedia?.text(.d, .audio), "audio-d")
        XCTAssertFalse(valid.unsupportedFields.contains("questionOptionMediaJson"))
    }
    func testWrongMissingOwnerIDAndNoncanonicalOwnerCannotConstructSnapshot() throws {
        let invalid: [[String: Any]] = [["memberId": 8], ["memberId": NSNull()], ["memberId": "7"], ["memberId": true], ["id": 102], ["id": 0]]
        for extra in invalid {
            XCTAssertThrowsError(try OwnedTemplateConfigurationSnapshot(response: response(extra), requestedID: id, accountID: 7))
        }
        XCTAssertThrowsError(try OwnedTemplateConfigurationSnapshot(response: response(), requestedID: id, accountID: 0))
        var missing = try XCTUnwrap(JSONSerialization.jsonObject(with: response()) as? [String: Any])
        var fields = try XCTUnwrap(missing["data"] as? [String: Any]); fields.removeValue(forKey: "memberId"); missing["data"] = fields
        XCTAssertThrowsError(try OwnedTemplateConfigurationSnapshot(response: JSONSerialization.data(withJSONObject: missing), requestedID: id, accountID: 7))
    }
    func testMissingNullEmptyAndUnsupportedValuesNeverBecomeEditorDefaults() throws {
        let snapshot = try OwnedTemplateConfigurationSnapshot(response: response(["validationMethod": 3, "questionA": NSNull(), "questionB": "", "questionC": ["unexpected": true]]), requestedID: id, accountID: 7)
        XCTAssertEqual(snapshot.field(.correctAnswer), .missing)
        XCTAssertEqual(snapshot.field(.questionA), .null); XCTAssertEqual(snapshot.field(.questionB), .value(""))
        XCTAssertEqual(snapshot.field(.questionC), .unsupported); XCTAssertEqual(snapshot.provenance, .missing)
        XCTAssertEqual(snapshot.supportedQAMethod, .choice)
        let emptySource = try OwnedTemplateConfigurationSnapshot(response: response(["originalTemplateId": 0]), requestedID: id, accountID: 7)
        XCTAssertEqual(emptySource.provenance, .value(0))
    }
    func testUnsupportedMethodsAndAdvancedDataAreNotRewrittenOrApplied() throws {
        for method in [0, 2, 4, 5, 6, 7, 99] {
            let bytes = try response(["validationMethod": method, "preferenceJson": "raw", "sensorConfig": "raw", "medalStyle": "enamel", "advancedConfigJson": "unparsed source bytes"])
            let snapshot = try OwnedTemplateConfigurationSnapshot(response: bytes, requestedID: id, accountID: 7)
            XCTAssertEqual(snapshot.validationMethod, method); XCTAssertNil(snapshot.supportedQAMethod)
            XCTAssertTrue(snapshot.hasExactBaseline(bytes)); XCTAssertTrue(snapshot.unsupportedFields.contains("validationMethod"))
            XCTAssertTrue(snapshot.unsupportedFields.contains("preferenceJson")); XCTAssertTrue(snapshot.unsupportedFields.contains("advancedConfigJson"))
        }
    }
    func testStoryReadKeepsWhitespaceLegacyImagesUnknownFieldsAndRejectsCorruption() throws {
        let rows: [[String: Any]] = [["text": "  exact text  ", "tag": "", "img": "https://images.test/old.jpg", "future": "unchanged"], ["text": NSNull(), "imgs": [], "img": "https://images.test/ignored.jpg"]]
        let story = String(decoding: try JSONSerialization.data(withJSONObject: rows), as: UTF8.self)
        let snapshot = try OwnedTemplateConfigurationSnapshot(response: response(["storyJson": story]), requestedID: id, accountID: 7)
        XCTAssertEqual(snapshot.story.first?.text, .value("  exact text  "))
        XCTAssertEqual(snapshot.story.first?.images, ["https://images.test/old.jpg"])
        XCTAssertEqual(snapshot.story.first?.unsupportedFields, ["future"])
        XCTAssertEqual(snapshot.story.last?.images, []); XCTAssertEqual(snapshot.story.last?.text, .null)
        for invalid in ["[1]", "{}", "not JSON"] {
            XCTAssertThrowsError(try OwnedTemplateConfigurationSnapshot(response: response(["storyJson": invalid]), requestedID: id, accountID: 7))
        }
        XCTAssertThrowsError(try OwnedTemplateConfigurationSnapshot(response: response(["future": String(repeating: "x", count: 1_048_576)]), requestedID: id, accountID: 7))
    }
    func testHostRevocationClearsOwnerSnapshotWithoutGivingAnyWriteCapability() async throws {
        let base = URL(string: "https://example.test/native")!, wire = Wire()
        wire.bytes = try response(["validationMethod": 7, "sensorType": "still", "sensorConfig": #"{"durationSec":5}"#])
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "scope", token: "synthetic"))
        let lease = try TemplateShelfReadApproval(context: context, expiresAt: Date().addingTimeInterval(600))
        let transport = TemplateShelfReadTransport(configuration: try .init(baseURL: base), http: wire, approval: lease, current: { context })
        let host = OwnedTemplateConfigurationHost(transport: transport)
        await host.load(id: id); XCTAssertEqual(host.snapshot?.field(.questionAnswer), .value("Exact secret"))
        XCTAssertEqual(wire.requests.count, 1)
        XCTAssertEqual(host.snapshot?.sensor?.value(.durationSec), .value(5))
        lease.revoke(); XCTAssertNil(host.snapshot)
        await host.load(id: id); XCTAssertNil(host.snapshot); XCTAssertEqual(wire.requests.count, 1)
        let adapter = TemplateAuthoringAdapter(shelfReadTransport: transport); XCTAssertFalse(adapter.canSubmit)
        let unavailable = OwnedTemplateConfigurationHost(transport: nil); await unavailable.load(id: id); XCTAssertNil(unavailable.snapshot)
    }
    func testNewSelectionWinsWhilePriorTemplateSuccess401OrErrorIsPending() async throws {
        for outcome in ["success", "401", "error"] {
            let base = URL(string: "https://example.test/native")!, wire = SelectionWire()
            let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "scope", token: "synthetic"))
            let lease = try TemplateShelfReadApproval(context: context, expiresAt: Date().addingTimeInterval(600))
            var unauthorized = 0
            let transport = TemplateShelfReadTransport(configuration: try .init(baseURL: base), http: wire, approval: lease, current: { context }, onUnauthorized: { unauthorized += 1 })
            let host = OwnedTemplateConfigurationHost(transport: transport)
            let started = expectation(description: "first template pending"); wire.onPending = { started.fulfill() }
            let first = Task { await host.load(id: id) }
            await fulfillment(of: [started], timeout: 2)
            let secondID = try XCTUnwrap(MemberPlayTemplateID(rawValue: 102))
            await host.load(id: secondID)
            XCTAssertEqual(host.snapshot?.id, secondID); XCTAssertEqual(host.snapshot?.field(.questionAnswer), .value("Second answer"))
            wire.finishFirst(outcome == "401" ? Data(#"{"code":401}"#.utf8) : try response(["validationMethod": 7, "sensorType": "steps", "sensorConfig": #"{"targetSteps":8,"windowSec":20}"#]), failure: outcome == "error")
            await first.value
            XCTAssertEqual(host.snapshot?.id, secondID); XCTAssertEqual(host.snapshot?.field(.questionAnswer), .value("Second answer"))
            XCTAssertNil(host.snapshot?.sensor)
            XCTAssertEqual(unauthorized, 0, "Obsolete A must not expire B's current session")
            lease.revoke(); XCTAssertNil(host.snapshot)
        }
    }
    private final class SelectionWire: HTTPTransport {
        var onPending: (() -> Void)?
        var pending: CheckedContinuation<(Data, Int), Error>?
        func finishFirst(_ data: Data, failure: Bool) {
            let continuation = pending; pending = nil
            if failure { continuation?.resume(throwing: APIError.httpStatus(503)) }
            else { continuation?.resume(returning: (data, 200)) }
        }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            if String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("\r\n\r\n101\r\n") {
                return try await withCheckedThrowingContinuation { pending = $0; onPending?() }
            }
            return (Data(#"{"code":200,"data":{"id":102,"memberId":7,"validationMethod":1,"questionAnswer":"Second answer"}}"#.utf8), 200)
        }
    }
    private final class Wire: HTTPTransport {
        var bytes = Data(), requests: [URLRequest] = []
        func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (bytes, 200) }
    }
}
