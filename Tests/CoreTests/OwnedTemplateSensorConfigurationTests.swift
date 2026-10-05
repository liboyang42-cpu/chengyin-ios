import XCTest
@testable import QuestifyCore

final class OwnedTemplateSensorConfigurationTests: XCTestCase {
    private func parse(_ type: String, _ raw: String) -> OwnedTemplateSensorConfiguration {
        .init(type: .value(type), config: .value(raw))
    }
    func testExactSupportedSensorTypesAndBoundaryParameters() {
        let still = parse("still", #"{"durationSec":600}"#)
        XCTAssertEqual(still.kind, .still); XCTAssertEqual(still.status, .ready)
        XCTAssertEqual(still.value(.durationSec), .value(600))
        let steps = parse("steps", #"{"targetSteps":100000,"windowSec":86400}"#)
        XCTAssertEqual(steps.parameters, [.targetSteps, .windowSec]); XCTAssertEqual(steps.status, .ready)
        XCTAssertEqual(steps.value(.targetSteps), .value(100000)); XCTAssertEqual(steps.value(.windowSec), .value(86400))
        let audio = parse("audio_clip", #"{"minDurationSec":60}"#)
        XCTAssertEqual(audio.kind, .audioClip); XCTAssertEqual(audio.value(.minDurationSec), .value(60))
        for type in ["filter_shot", "STILL", " still", "nfc", "uwb", "future", ""] {
            let unsupported = parse(type, #"{"durationSec":1}"#)
            XCTAssertNil(unsupported.kind); XCTAssertEqual(unsupported.status, .unsupportedType)
            XCTAssertTrue(unsupported.parameters.isEmpty)
        }
    }
    func testMalformedMissingNullAndInvalidNumbersNeverFabricateDefaults() {
        for (type, key, maximum) in [("still", "durationSec", 600), ("steps", "targetSteps", 100000), ("steps", "windowSec", 86400), ("audio_clip", "minDurationSec", 60)] {
            for value in ["0", "-1", "\(maximum + 1)", "1.0", "1e0", "1.5", "true", "\"1\"", "[]", "{}"] {
                let config = parse(type, "{\"\(key)\":\(value)}")
                XCTAssertEqual(config.value(.init(rawValue: key)!), .invalid, "\(type) \(key) \(value)")
                XCTAssertEqual(config.status, .invalid)
            }
        }
        XCTAssertEqual(parse("still", "{}").value(.durationSec), .missing)
        XCTAssertEqual(parse("still", #"{"durationSec":null}"#).value(.durationSec), .null)
        XCTAssertEqual(OwnedTemplateSensorConfiguration(type: .value("still"), config: .missing).status, .missing)
        XCTAssertEqual(OwnedTemplateSensorConfiguration(type: .value("still"), config: .null).status, .null)
        for raw in ["", "null", "[]", "{", "false", String(repeating: " ", count: 2001)] {
            XCTAssertEqual(parse("still", raw).status, .invalid)
        }
        XCTAssertEqual(parse("still", #"{"durationSec":1,"durationSec":2}"#).value(.durationSec), .invalid)
    }
    func testUnknownNestedFieldsStayPartialAndDoNotAffectExactWhitelistedValues() {
        let raw = #"{"durationSec":5,"secret":{"durationSec":1.5,"nested":"},\\\""},"unknown":0.5}"#
        let sensor = parse("still", raw)
        XCTAssertEqual(sensor.status, .partial); XCTAssertEqual(sensor.value(.durationSec), .value(5))
        XCTAssertEqual(sensor.parameters, [.durationSec])
        XCTAssertEqual(parse("still", #"{"duration\u0053ec":1}"#).value(.durationSec), .value(1))
    }
    func testWholeIntegerTokenAndConservativeDepthBoundBeforeRecursiveDecode() throws {
        for token in ["1\n", "1\r\n", "1 ", " 1", "1\n2", "1x", "x1", "1.0", "1e0", ""] {
            XCTAssertFalse(OwnedTemplateSensorConfiguration.isCanonicalIntegerToken(token))
        }
        XCTAssertTrue(OwnedTemplateSensorConfiguration.isCanonicalIntegerToken("123"))
        for depth in [15, 16, 800] {
            let raw = "{\"durationSec\":5,\"private\":" + String(repeating: "[", count: depth) + "0" + String(repeating: "]", count: depth) + "}"
            XCTAssertLessThan(raw.utf16.count, 2000)
            XCTAssertEqual(parse("still", raw).status, depth <= 15 ? .partial : .invalid)
            let bytes = try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["id": 101, "memberId": 7, "validationMethod": 7, "sensorType": "still", "sensorConfig": raw]])
            let snapshot = try OwnedTemplateConfigurationSnapshot(response: bytes, requestedID: MemberPlayTemplateID(rawValue: 101)!, accountID: 7)
            XCTAssertTrue(snapshot.hasExactBaseline(bytes))
        }
        for raw in [#"{"durationSec":1,"duration\u0053ec":null}"#, #"{"durationSec":null,"durationSec":1}"#] {
            XCTAssertEqual(parse("still", raw).value(.durationSec), .invalid)
        }
        let bracketsInText = "{\"durationSec\":1,\"unknown\":\"" + String(repeating: "[", count: 100) + "\"}"
        XCTAssertEqual(parse("still", bracketsInText).status, .partial)
    }
    func testOwnerSnapshotRecognizesSixSevenWithoutExpandingWritableMethods() throws {
        for method in [6, 7, 2, 99] {
            let fields: [String: Any] = ["id": 101, "memberId": 7, "validationMethod": method, "sensorType": "still", "sensorConfig": #"{"durationSec":4,"private":"keep"}"#]
            let bytes = try JSONSerialization.data(withJSONObject: ["code": 200, "data": fields])
            let id = MemberPlayTemplateID(rawValue: 101)!
            let owner = try OwnedTemplateConfigurationSnapshot(response: bytes, requestedID: id, accountID: 7)
            XCTAssertEqual(owner.validationMethod, method); XCTAssertTrue(owner.hasExactBaseline(bytes))
            XCTAssertNil(owner.supportedQAMethod)
            XCTAssertEqual(owner.specializedMethodLabel, method == 6 ? "templateOwnerSensor.preference" : (method == 7 ? "templateOwnerSensor.challenge" : nil))
            if method == 7 { XCTAssertEqual(owner.sensor?.value(.durationSec), .value(4)); XCTAssertEqual(owner.sensor?.status, .partial) }
            else { XCTAssertNil(owner.sensor) }
            XCTAssertThrowsError(try OwnedTemplateConfigurationSnapshot(response: bytes, requestedID: id, accountID: 8))
        }
        for raw in [6, 7] {
            let method = try XCTUnwrap(TemplateAuthoringMethod(rawValue: raw))
            XCTAssertTrue(method.isLocalConfigurationOnly)
            var draft = TemplateAuthoringDraft(title: "Local only")
            draft.validationMethod = method
            XCTAssertThrowsError(try TemplateAuthoringContract.payload(draft))
            for intent in TemplateAuthoringIntent.allCases {
                XCTAssertThrowsError(try TemplateAuthoringContract.request(draft, intent: intent))
            }
        }
    }
}
