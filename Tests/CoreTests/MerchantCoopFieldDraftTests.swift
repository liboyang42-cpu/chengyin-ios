import XCTest
@testable import QuestifyCore

final class MerchantCoopFieldDraftTests: XCTestCase {
    private func settings(capacity: String = "12", time: String = "  周末 e\u{301}  ", demand: String = "Original", charge: Int? = 1) throws -> MerchantCoopSettings {
        var fields: [String: Any] = ["capacity": capacity, "availableTime": time, "demand": demand,
            "suitActivityTypes": " hidden;legacy ", "coopOpen": 0]
        fields["chargeType"] = charge.map { $0 as Any } ?? NSNull()
        return try JSONDecoder().decode(MerchantCoopSettings.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    func testOnlyThreeSourceFieldsExist() {
        XCTAssertEqual(Set(MerchantCoopField.allCases.map(\.rawValue)), ["capacity", "availableTime", "demand"])
    }
    func testOpeningPreservesExactInputAndDoesNotDirty() throws {
        let source = try settings(), draft = MerchantCoopFieldDraft(field: .availableTime, settings: source)
        XCTAssertEqual(Array(draft.value.utf8), Array(source.availableTime.utf8)); XCTAssertFalse(draft.isDirty)
    }
    func testApplyingEachFieldPreservesAllSiblingsAndHiddenFields() throws {
        let source = try settings()
        for field in MerchantCoopField.allCases {
            var draft = MerchantCoopFieldDraft(field: field, settings: source); draft.value = field == .capacity ? "0008" : "  New e\u{301}  "
            let result = try draft.applying(to: source)
            for other in MerchantCoopField.allCases where other != field {
                XCTAssertEqual(Array(other.value(in: result).utf8), Array(other.value(in: source).utf8))
            }
            XCTAssertEqual(Array(field.value(in: result).utf8), Array(draft.value.utf8))
            XCTAssertEqual(result.chargeType, source.chargeType); XCTAssertEqual(result.suitActivityTypes, source.suitActivityTypes); XCTAssertEqual(result.coopOpen, source.coopOpen)
        }
    }
    func testClearingLoadedCapacityRetainsOriginalExplicitClearIntent() throws {
        let source = try settings(); var draft = MerchantCoopFieldDraft(field: .capacity, settings: source); draft.value = ""
        let result = try draft.applying(to: source)
        XCTAssertTrue(result.clearsCapacity); XCTAssertTrue(result.fields["capacity"] is NSNull)
        XCTAssertEqual((result.fields["params"] as? [String: Bool])?["clearCapacity"], true)
    }
    func testUnchangedEmptyCapacityDoesNotInventClearRequest() throws {
        let source = try settings(capacity: ""); let draft = MerchantCoopFieldDraft(field: .capacity, settings: source)
        let result = try draft.applying(to: source); XCTAssertFalse(result.clearsCapacity); XCTAssertNil(result.fields["params"])
    }
    func testCapacityAcceptsZeroAndLeadingZerosWithoutNormalizingLocalValue() throws {
        let source = try settings()
        for text in ["0", "0007", "100"] {
            var draft = MerchantCoopFieldDraft(field: .capacity, settings: source); draft.value = text
            XCTAssertNil(draft.issueKey); XCTAssertEqual(try draft.applying(to: source).capacity, text)
        }
    }
    func testCapacityRejectsNonASCIIFractionsSignsWhitespaceAndOverflow() throws {
        let source = try settings()
        for text in ["-1", "+1", "1.2", " 2", "2 ", "١", "１２", String(repeating: "9", count: 50)] {
            var draft = MerchantCoopFieldDraft(field: .capacity, settings: source); draft.value = text
            XCTAssertEqual(draft.issueKey, "merchant.operations.capacityInvalid", text); XCTAssertThrowsError(try draft.applying(to: source))
        }
    }
    func testTimeAndDemandLimitsCountUTF16AndNeverTruncate() throws {
        let source = try settings()
        for (field, count) in [(MerchantCoopField.availableTime, 50), (.demand, 250)] {
            var draft = MerchantCoopFieldDraft(field: field, settings: source); draft.value = String(repeating: "🙂", count: count)
            XCTAssertNil(draft.issueKey); draft.value += "🙂"; XCTAssertNotNil(draft.issueKey)
            XCTAssertEqual(draft.value.utf16.count, field.limit + 2)
        }
    }
    func testCanonicalAliasIsAnExactLocalEdit() throws {
        let source = try settings(time: "é"); var draft = MerchantCoopFieldDraft(field: .availableTime, settings: source)
        draft.value = "e\u{301}"; XCTAssertTrue(draft.isDirty)
        XCTAssertEqual(Array(try draft.applying(to: source).availableTime.utf8), Array("e\u{301}".utf8))
    }
    func testChangedSourceFieldCannotBeOverwritten() throws {
        let source = try settings(); var draft = MerchantCoopFieldDraft(field: .demand, settings: source); draft.value = "Edit"
        var newer = source; newer.demand = "Newer"; XCTAssertThrowsError(try draft.applying(to: newer))
    }
    func testHistoricalInvalidOrOverlongUnchangedValueIsNoOpNotMigration() throws {
        for source in [try settings(capacity: "legacy"), try settings(time: String(repeating: "x", count: 150))] {
            for field in MerchantCoopField.allCases {
                let draft = MerchantCoopFieldDraft(field: field, settings: source)
                XCTAssertNil(draft.issueKey); XCTAssertTrue(MerchantCoopFieldDraft.sameValues(try draft.applying(to: source), source))
            }
        }
    }
    func testFieldApplyDoesNotRepairMissingChargeChoice() throws {
        let source = try settings(charge: nil); var draft = MerchantCoopFieldDraft(field: .demand, settings: source); draft.value = "New"
        let result = try draft.applying(to: source); XCTAssertNil(result.chargeType); XCTAssertEqual(result.blocker, "merchant.coopChargeChoice.required")
    }
}
