import XCTest
@testable import QuestifyCore

final class TemplateSensorDraftTests: XCTestCase {
    func testNoDefaultsAndAllPolicyBoundaries() throws {
        for kind in TemplateSensorDraft.Kind.allCases {
            var draft = TemplateSensorDraft(); draft.select(kind)
            XCTAssertFalse(draft.isValid)
            for field in kind.parameters {
                XCTAssertEqual(draft.input(field), "")
                for valid in [1, field.maximum] {
                    draft.set(field, text: String(valid)); XCTAssertEqual(draft.integer(field), valid)
                }
                for invalid in ["", "0", "-1", String(field.maximum + 1), "1.0", "1e0", "true", "１", " 1", "1\n", "999999999999999999999999"] {
                    draft.set(field, text: invalid); XCTAssertNil(draft.integer(field), invalid)
                    XCTAssertThrowsError(try draft.configurationJSON())
                }
                draft.set(field, text: "1")
            }
            XCTAssertTrue(draft.isValid)
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(draft.configurationJSON().utf8)) as? [String: Int])
            XCTAssertEqual(Set(fields.keys), Set(kind.parameters.map(\.rawValue)))
        }
    }
    func testTypeSwitchRetainsInputsWithoutCrossTypeSerialization() throws {
        var draft = TemplateSensorDraft(); draft.select(.still); draft.set(.durationSec, text: "15")
        draft.select(.steps); draft.set(.targetSteps, text: "99"); draft.set(.windowSec, text: "8")
        XCTAssertEqual(try draft.configurationJSON(), #"{"targetSteps":99,"windowSec":8}"#)
        draft.select(.still); XCTAssertEqual(draft.input(.durationSec), "15")
        XCTAssertEqual(try draft.configurationJSON(), #"{"durationSec":15}"#)
        draft.set(.targetSteps, text: "5"); XCTAssertEqual(draft.input(.targetSteps), "99")
    }
    func testOriginalIsExactButInvalidCurrentInputNeverFallsBack() throws {
        let raw = "  { \"durationSec\" : 15 }\n"
        var draft = TemplateSensorDraft(type: "still", config: raw)
        XCTAssertTrue(draft.canEdit); XCTAssertEqual(try draft.configurationJSON(), raw)
        draft.select(.still); draft.set(.durationSec, text: "15")
        XCTAssertNil(draft.working); XCTAssertEqual(try draft.configurationJSON(), raw)
        draft.set(.durationSec, text: "invalid")
        XCTAssertEqual(draft.originalConfig, raw); XCTAssertEqual(draft.input(.durationSec), "invalid")
        XCTAssertFalse(draft.isValid); XCTAssertThrowsError(try draft.configurationJSON())
        draft.set(.durationSec, text: "16")
        XCTAssertEqual(try draft.configurationJSON(), #"{"durationSec":16}"#)
        XCTAssertEqual(draft.originalConfig, raw)
    }
    func testUnknownAmbiguousAndInvalidHistoryIsPreservedReadOnly() throws {
        let rawValues = [#"{"durationSec":1,"future":{"x":true}}"#, #"{"durationSec":1,"durationSec":2}"#,
            #"{"durationSec":1,"\u0064urationSec":2}"#, #"{"durationSec":null}"#, #"{"durationSec":1.0}"#,
            #"{"durationSec":1e0}"#, #"{"durationSec":"1"}"#, #"{"durationSec":true}"#, #"{"durationSec":601}"#,
            "[]", "null", "{", ""]
        for raw in rawValues {
            var draft = TemplateSensorDraft(type: "still", config: raw)
            let original = draft; XCTAssertFalse(draft.canEdit, raw)
            draft.select(.steps); draft.set(.durationSec, text: "2")
            XCTAssertEqual(draft, original); XCTAssertThrowsError(try draft.configurationJSON())
            XCTAssertEqual(try JSONDecoder().decode(TemplateSensorDraft.self, from: JSONEncoder().encode(draft)), original)
        }
        for type in ["future", "filter_shot", "STILL", " still "] {
            var draft = TemplateSensorDraft(type: type, config: #"{"durationSec":1}"#)
            XCTAssertFalse(draft.canEdit); draft.select(.still); XCTAssertEqual(draft.originalType, type); XCTAssertNil(draft.working)
        }
    }
    func testMissingKnownConfigEditableAndUTF16Boundary() throws {
        var missing = TemplateSensorDraft(type: "audio_clip")
        XCTAssertTrue(missing.canEdit); XCTAssertFalse(missing.isValid)
        missing.set(.minDurationSec, text: "60"); XCTAssertTrue(missing.isValid)
        var incomplete = TemplateSensorDraft(type: "steps", config: #"{"targetSteps":15}"#)
        XCTAssertTrue(incomplete.canEdit); XCTAssertFalse(incomplete.isValid)
        XCTAssertEqual(incomplete.input(.windowSec), "")
        incomplete.set(.windowSec, text: "10"); XCTAssertTrue(incomplete.isValid)
        var empty = TemplateSensorDraft(type: "still", config: "{}")
        XCTAssertTrue(empty.canEdit); empty.set(.durationSec, text: "2"); XCTAssertTrue(empty.isValid)
        let raw = #"{"durationSec":1}"#
        let atLimit = raw + String(repeating: " ", count: 2_000 - raw.utf16.count)
        XCTAssertTrue(TemplateSensorDraft(type: "still", config: atLimit).isValid)
        XCTAssertFalse(TemplateSensorDraft(type: "still", config: atLimit + " ").canEdit)
        let unknownUnicode = #"{"durationSec":1,"future":""# + String(repeating: "😀", count: 1_000) + #""}"#
        XCTAssertFalse(TemplateSensorDraft(type: "still", config: unknownUnicode).canEdit)
    }
    func testOptionalFieldBackwardCompatibilityAndHiddenConfigPayloadUnchanged() throws {
        var draft = TemplateAuthoringDraft(title: "Local")
        let oldData = try JSONEncoder().encode(draft)
        XCTAssertNil(try JSONDecoder().decode(TemplateAuthoringDraft.self, from: oldData).sensorDraft)
        for method in TemplateAuthoringMethod.allCases where (0...5).contains(method.rawValue) {
            draft.validationMethod = method; draft.sensorDraft = nil
            let prior = try TemplateAuthoringContract.payload(draft)
            draft.sensorDraft = .init(type: "future", config: #"{"private":"retained"}"#)
            XCTAssertEqual(try TemplateAuthoringContract.payload(draft), prior)
        }
    }
    @MainActor func testLocalStorePipelineRoundTripAndOwnerSeparation() throws {
        let session = try TemplateAuthoringSession(accountID: 901, namespace: "sensor-local", epoch: 1, authorizationRevision: "fixture")
        let storage = TemplateAuthoringMemoryStorage(); let store = TemplateAuthoringLocalStore(storage: storage)
        let identity = TemplateAuthoringIdentity(); var draft = TemplateAuthoringDraft(title: "Local")
        var sensor = TemplateSensorDraft(); sensor.select(.steps); sensor.set(.targetSteps, text: "unfinished"); sensor.set(.windowSec, text: "")
        draft.sensorDraft = sensor; try store.save(draft, session: session, identity: identity)
        guard case .ready(let restored) = store.load(session: session, identity: identity) else { return XCTFail("Expected local restore") }
        XCTAssertEqual(restored.draft, draft); XCTAssertFalse(try XCTUnwrap(restored.draft.sensorDraft).isValid)
        let another = try TemplateAuthoringSession(accountID: 902, namespace: "sensor-local", epoch: 1, authorizationRevision: "fixture")
        XCTAssertEqual(store.load(session: another, identity: identity), .missing)
        let region = try TemplateAuthoringSession(accountID: 901, namespace: "sensor-other", epoch: 1, authorizationRevision: "fixture")
        XCTAssertEqual(store.load(session: region, identity: identity), .missing)
        draft.id = AuthoringPlayTemplateID(rawValue: 42)
        try store.save(draft, session: session, identity: identity)
        XCTAssertEqual(store.load(session: session, identity: identity), .incompatible)
    }
}
