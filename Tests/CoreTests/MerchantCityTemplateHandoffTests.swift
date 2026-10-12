import XCTest
@testable import QuestifyCore

final class MerchantCityTemplateHandoffTests: XCTestCase {
    private let scope = UUID()
    private func snapshot(rows: [MerchantContentValue], merchant: Int = 31, permissions: [String] = ["merchant:project:manage"], query: MerchantContentQuery = .cityPlacement, date: Date = Date(timeIntervalSince1970: 1)) throws -> MerchantContentSnapshot {
        let json = try JSONSerialization.data(withJSONObject: ["active": true, "merchant": ["id": merchant], "roleCode": "MERCHANT_MANAGER", "permissions": permissions])
        return .init(query: query, scope: scope, access: try JSONDecoder().decode(MerchantAccess.self, from: json), value: .object(["templates": .array(rows)]), observedAt: date)
    }
    private func row(_ config: MerchantContentValue = .null, id: Int = 73) -> MerchantContentValue { .object(["id": .integer(id), "title": .string("Returned"), "advancedConfigJson": config]) }
    private func validate(_ snapshot: MerchantContentSnapshot, id: Int = 73) throws -> MerchantContentValue {
        try MerchantCityTemplateHandoff.returnedTemplate(id: id, snapshot: snapshot, scope: scope, merchantID: 31)
    }
    func testFreshOwnedTemplateReturnsExactOriginalRow() throws {
        let row = row(); XCTAssertEqual(try validate(snapshot(rows: [row])), row)
    }
    func testAbsentCallbackIDNeverBecomesASyntheticListRow() throws { XCTAssertThrowsError(try validate(snapshot(rows: [row(id: 71)]))) }
    func testDuplicateIDsFailClosed() throws { XCTAssertThrowsError(try validate(snapshot(rows: [row(), row()]))) }
    func testZeroAndNegativeIDsFailClosed() throws {
        for id in [0, -1] { XCTAssertThrowsError(try validate(snapshot(rows: [row(id: id)]), id: id)) }
    }
    func testWrongMerchantAndWrongQueryCannotReturn() throws {
        XCTAssertThrowsError(try validate(snapshot(rows: [row()], merchant: 32)))
        XCTAssertThrowsError(try validate(snapshot(rows: [row()], query: .city)))
    }
    func testManagerNeedsActualProjectPermission() throws { XCTAssertThrowsError(try validate(snapshot(rows: [row()], permissions: []))) }
    func testAlbumObjectAndJSONStringAreBothRejected() throws {
        for config: MerchantContentValue in [.object(["album": .object(["enabled": .bool(true)])]), .string(#"{"album":{"enabled":true}}"#)] {
            XCTAssertThrowsError(try validate(snapshot(rows: [row(config)]))) { XCTAssertEqual($0 as? MerchantCityTemplateReturnFailure, .albumOnly) }
        }
    }
    func testMiniAlbumTruthinessDoesNotTreatStringFalseAsDisabled() throws {
        for enabled: MerchantContentValue in [.string("false"), .integer(1), .array([]), .object([:])] {
            XCTAssertThrowsError(try validate(snapshot(rows: [row(.object(["album": .object(["enabled": enabled])]))])))
        }
    }
    func testDisabledAndAbsentAlbumRemainUsable() throws {
        for enabled: MerchantContentValue in [.bool(false), .null, .integer(0), .string("")] {
            XCTAssertNoThrow(try validate(snapshot(rows: [row(.object(["album": .object(["enabled": enabled])]))])))
        }
    }
    func testMalformedAdvancedConfigCannotHideAnAlbum() throws {
        XCTAssertThrowsError(try validate(snapshot(rows: [row(.string("{"))]))) { XCTAssertEqual($0 as? MerchantCityTemplateReturnFailure, .invalidMetadata) }
    }
    func testIdenticalValueAfterReloadIsADifferentOpeningRevision() throws {
        let one = try snapshot(rows: [row()]), two = try snapshot(rows: [row()], date: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(one, two)
        XCTAssertFalse(MerchantCityTemplateHandoff.sameSnapshot(one, two))
    }
    func testLocalDraftEqualityProtectsRawUTF8AndAllOtherFields() {
        let original = MerchantCityTemplateLocalDraft(fields: ["name": "é", "address": "  A  "], templateID: 71, confirmedAddress: true, dirty: false)
        let changedBytes = MerchantCityTemplateLocalDraft(fields: ["name": "e\u{301}", "address": "  A  "], templateID: 71, confirmedAddress: true, dirty: false)
        XCTAssertNotEqual(original, changedBytes)
        XCTAssertNotEqual(original, .init(fields: original.fields, templateID: 71, confirmedAddress: false, dirty: false))
        XCTAssertNotEqual(original, .init(fields: original.fields, templateID: 71, confirmedAddress: true, dirty: true))
    }
}
