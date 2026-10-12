import XCTest
import SwiftUI
@testable import Questify

@MainActor final class MerchantPerkStableOwnerTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-12T15:59:00Z")!
    private func context(_ value: String = "") throws -> MerchantPerkValidityContext {
        .init(session: try .init(accountID: 41, epoch: 1, token: "synthetic-token"), value: value, siblingFields: ["original", "0", "10", "", "3"])
    }
    func testRecreatedRowKeepsAppliedResult() throws {
        let c = try context("2026-10-15")
        var value = c.value; var session: MerchantPerkValiditySession?
        var appliedValue: String? = value; var appliedContext: MerchantPerkValidityContext? = c
        let first = MerchantPerkValidityEntry(value: .init(get: { value }, set: { value = $0 }), session: .init(get: { session }, set: { session = $0 }), appliedValue: .init(get: { appliedValue }, set: { appliedValue = $0 }), appliedContext: .init(get: { appliedContext }, set: { appliedContext = $0 }), context: { c })
        let second = MerchantPerkValidityEntry(value: first.$value, session: first.$session, appliedValue: first.$appliedValue, appliedContext: first.$appliedContext, context: { c })
        XCTAssertEqual(second.appliedValue, c.value); XCTAssertEqual(second.appliedContext, c)
        XCTAssertEqual(value, c.value); XCTAssertNil(session)
    }
    func testRecreatedRowRetainsPendingCalendarChoice() throws {
        let c = try context(); var value = ""; var session = MerchantPerkValiditySession(current: { c }, now: now)
        var appliedValue: String?; var appliedContext: MerchantPerkValidityContext?
        let selected = try XCTUnwrap(session); selected.choose(try XCTUnwrap(MerchantPerkValidityDraft.parse("2026-10-15")))
        let row = MerchantPerkValidityEntry(value: .init(get: { value }, set: { value = $0 }), session: .init(get: { session }, set: { session = $0 }), appliedValue: .init(get: { appliedValue }, set: { appliedValue = $0 }), appliedContext: .init(get: { appliedContext }, set: { appliedContext = $0 }), context: { c })
        XCTAssertTrue(row.session === selected); XCTAssertTrue(selected.isCurrent)
        XCTAssertEqual(value, ""); XCTAssertEqual(selected.apply(now: now), "2026-10-15")
    }
    func testActualRetirementStillRejectsApply() throws {
        let c = try context(); let session = try XCTUnwrap(MerchantPerkValiditySession(current: { c }, now: now))
        session.choose(try XCTUnwrap(MerchantPerkValidityDraft.parse("2026-10-15")))
        session.cancel(); XCTAssertFalse(session.isCurrent); XCTAssertNil(session.apply(now: now))
    }
}
