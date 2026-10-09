import XCTest
@testable import QuestifyCore

final class ProjectNodeBusinessHoursTests: XCTestCase {
    private func draft(_ raw: ProjectEditJSON?) -> ProjectEditDraft {
        var d = ProjectEditSyntheticFixtures.draft(); d.chapters[0].id = "chapter"; d.chapters[0].nodes[0].id = "node"
        d.chapters[0].nodes[0].localMetadata["businessTime"] = raw
        d.chapters[0].nodes[0].localMetadata["unknown"] = .string("e\u{301}"); d.chapters[0].nodes[0].imgUrl = "a,\u{301}b,a"
        return d
    }
    private func snapshot(_ d: ProjectEditDraft) -> ProjectNodeBusinessHours { .init(draft: d, chapterID: "chapter", nodeID: "node") }
    private var replacement: ProjectNodeBusinessHours.Value { .init(startHour: 8, startMinute: 5, endHour: 22, endMinute: 59)! }
    func testCanonicalPickerTextParsesAndReplacesOnlyExistingField() throws {
        let d = draft(.string("09:00-18:00")), s = snapshot(d), next = try s.replacing(with: replacement, in: d)
        XCTAssertEqual(s.value?.startHour, 9); XCTAssertEqual(s.value?.endHour, 18)
        var expected = d; expected.chapters[0].nodes[0].localMetadata["businessTime"] = .string("08:05-22:59")
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(expected))
    }
    func testMissingNullAndEmptyRepresentationsRemainExactUntilExplicitReplacement() throws {
        for raw: ProjectEditJSON? in [nil, .null, .string("")] {
            let d = draft(raw), s = snapshot(d); XCTAssertNil(s.reason); XCTAssertNil(s.value)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(try s.replacing(with: nil, in: d)), ProjectEditPendingMaterials.exactData(d))
            let next = try s.replacing(with: replacement, in: d)
            XCTAssertEqual(next.chapters[0].nodes[0].localMetadata["businessTime"], .string("08:05-22:59"))
        }
    }
    func testUnchangedSelectionIsByteExactNoOp() throws {
        for raw in ["09:00-18:00", "23:59-00:00", "00:00-00:00"] {
            let d = draft(.string(raw)), s = snapshot(d)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(try s.replacing(with: s.value, in: d)), ProjectEditPendingMaterials.exactData(d))
        }
    }
    func testIndependentRangesPermitEqualOrDescendingValuesWithoutMeaningInference() throws {
        let d = draft(nil), s = snapshot(d)
        for value in [ProjectNodeBusinessHours.Value(startHour: 23, startMinute: 59, endHour: 0, endMinute: 0)!, .init(startHour: 8, startMinute: 30, endHour: 8, endMinute: 30)!] {
            let next = try s.replacing(with: value, in: d)
            XCTAssertEqual(next.chapters[0].nodes[0].localMetadata["businessTime"], .string(value.text))
        }
    }
    func testOnlyHourAndMinuteNumericRangesAreAccepted() {
        for values in [(-1, 0, 18, 0), (24, 0, 18, 0), (9, -1, 18, 0), (9, 60, 18, 0), (9, 0, 24, 0), (9, 0, 18, 60)] {
            XCTAssertNil(ProjectNodeBusinessHours.Value(startHour: values.0, startMinute: values.1, endHour: values.2, endMinute: values.3))
        }
        for h in 0...23 { for m in 0...59 {
            let v = ProjectNodeBusinessHours.Value(startHour: h, startMinute: m, endHour: h, endMinute: m)!
            XCTAssertEqual(v.text.utf8.count, 11); XCTAssertEqual(snapshot(draft(.string(v.text))).value, v)
        } }
    }
    func testLegacyMalformedAndUnicodeFieldsAreReadOnlyWithoutNormalization() {
        for raw: ProjectEditJSON in [.string("9:00-18:00"), .string("09:00"), .string(" 09:00-18:00 "), .string("09:00–18:00"), .string("０９:００-１８:００"), .string("09:\u{301}00-18:00"), .string("24:00-18:00"), .string("09:60-18:00"), .string("open daily"), .number(900), .object(["start": .string("09:00")])] {
            let d = draft(raw), before = ProjectEditPendingMaterials.exactData(d), s = snapshot(d)
            XCTAssertEqual(s.reason, .unsupported); XCTAssertThrowsError(try s.replacing(with: replacement, in: d)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(d), before)
        }
    }
    func testExactTargetAndDuplicateOrPendingAliasesFailClosed() {
        for kind in ["chapter", "node", "pending", "unicode"] {
            var d = draft(.string("09:00-18:00"))
            switch kind {
            case "chapter": d.chapters.append(d.chapters[0])
            case "node": d.chapters[0].nodes.append(d.chapters[0].nodes[0])
            case "pending": d.pendingMaterials = [.init(node: d.chapters[0].nodes[0])]
            default: d.chapters[0].nodes[0].id = "é"
            }
            let s = kind == "unicode" ? ProjectNodeBusinessHours(draft: d, chapterID: "chapter", nodeID: "e\u{301}") : snapshot(d)
            XCTAssertEqual(s.reason, .identity)
        }
    }
    func testStaleHoursDeletionOrderAndUnrelatedChangesRejectSnapshot() {
        let d = draft(.string("09:00-18:00")), s = snapshot(d)
        for kind in ["hours", "delete", "order", "other"] {
            var changed = d
            switch kind {
            case "hours": changed.chapters[0].nodes[0].localMetadata["businessTime"] = .string("10:00-18:00")
            case "delete": changed.chapters[0].nodes = []
            case "order": var other = ProjectEditNode(); other.id = "other"; changed.chapters[0].nodes.insert(other, at: 0)
            default: changed.name += "!"
            }
            XCTAssertFalse(s.isCurrent(in: changed)); XCTAssertThrowsError(try s.replacing(with: replacement, in: changed))
        }
    }
    func testExistingLegacyAndV2PayloadCarryOnlySelectedBusinessTime() throws {
        for pro in [false, true] {
            var d = draft(.string("09:00-18:00")); if pro { d.preserved["publishMode"] = .string("pro") }
            let next = try snapshot(d).replacing(with: replacement, in: d)
            let payload = try ProjectEditContract.payload(next, topicID: nil, scope: .full)
            let node = try XCTUnwrap(payload["chapters"]?.array?.first?.object?["nodes"]?.array?.first?.object)
            XCTAssertEqual(node["businessTime"], .string("08:05-22:59")); XCTAssertEqual(node["imgUrl"], .string(d.chapters[0].nodes[0].imgUrl)); XCTAssertEqual(node["templateId"], .number(41))
        }
    }

    func testExplicitClearWritesOnlyEmptyBusinessTimeWhileNilSelectionStillDoesNothing() throws {
        let original = draft(.string("09:00-18:00")), captured = snapshot(original)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try captured.replacing(with: nil, in: original)), ProjectEditPendingMaterials.exactData(original))
        var expected = original; expected.chapters[0].nodes[0].localMetadata["businessTime"] = .string("")
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try captured.clearing(in: original)), ProjectEditPendingMaterials.exactData(expected))
    }
    func testClearOfAlreadyMissingNullOrEmptyDoesNotNormalizeRepresentations() throws {
        for raw: ProjectEditJSON? in [nil, .null, .string("")] {
            let original = draft(raw)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(try snapshot(original).clearing(in: original)), ProjectEditPendingMaterials.exactData(original))
        }
    }
    func testUnsupportedLegacyAndStaleClearRemainReadOnly() {
        for raw: ProjectEditJSON in [.string("open daily"), .string("9:00-18:00"), .number(900)] {
            let original = draft(raw); XCTAssertThrowsError(try snapshot(original).clearing(in: original))
        }
        let original = draft(.string("09:00-18:00")), captured = snapshot(original)
        var changed = original; changed.name += "!"
        XCTAssertThrowsError(try captured.clearing(in: changed))
    }
    func testClearedEmptyStringSurvivesExistingLegacyAndV2WireSerializer() throws {
        for pro in [false, true] {
            var original = draft(.string("09:00-18:00")); if pro { original.preserved["publishMode"] = .string("pro") }
            let next = try snapshot(original).clearing(in: original)
            let payload = try ProjectEditContract.payload(next, topicID: nil, scope: .full)
            let node = try XCTUnwrap(payload["chapters"]?.array?.first?.object?["nodes"]?.array?.first?.object)
            XCTAssertEqual(node["businessTime"], .string("")); XCTAssertEqual(node["imgUrl"], .string(original.chapters[0].nodes[0].imgUrl))
        }
    }
}
