import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class MerchantCircleSupplyDraftTests: XCTestCase {
    private func complete() -> CoopCircleSupplyDraft {
        var d = CoopCircleSupplyDraft(); d.name = "Store service"; d.price = "0"; d.duration = "20"; d.hours = "By appointment"
        d.maxPeople = "2"; d.actionValue = "Store desk"; d.merchantRules = "Ask before arrival"; return d
    }
    func testCompleteDraftBuildsLocalProfileWithoutAnyRequest() {
        let d = complete(); XCTAssertEqual(d.profile?.supplyName, "Store service"); XCTAssertEqual(d.profile?.regularPrice, 0)
        XCTAssertEqual(d.profile?.minPeople, 1); XCTAssertEqual(d.profile?.maxPeople, 2)
    }
    func testEmptyAndPartiallyEditedCardCannotProducePreview() {
        XCTAssertNil(CoopCircleSupplyDraft().profile)
        var d = complete(); d.hours = ""; XCTAssertNil(d.profile); d.hours = "Open hours"; d.actionValue = ""; XCTAssertNil(d.profile)
    }
    func testPriceUsesWholeInputInsteadOfAcceptingNumericPrefix() {
        for price in ["", "1garbage", "NaN", "Infinity", "-1", "1,2", "1.2.3"] {
            var d = complete(); d.price = price; XCTAssertNil(d.profile, price)
        }
        var d = complete(); d.price = "12.50"; XCTAssertEqual(d.profile?.regularPrice, Decimal(string: "12.50"))
    }
    func testIntegerOverflowFractionAndNonpositiveCapacityFailClosed() {
        for value in ["0", "-1", "1.5", String(repeating: "9", count: 100)] {
            var d = complete(); d.duration = value; XCTAssertNil(d.profile)
        }
    }
    func testSingleParticipantRequiresExplicitSplitAndBenefitRequiresTerms() {
        var d = complete(); d.maxPeople = "1"; XCTAssertNil(d.profile)
        d.split = true; XCTAssertNotNil(d.profile); d.benefit = "Tea"; XCTAssertNil(d.profile)
        d.benefitRules = "One serving while valid"; XCTAssertNotNil(d.profile)
    }
    func testFrozenProfileAndReturningLocalDraftKeepExactInputIndependent() throws {
        var d = complete(); d.benefit = " e\u{301} "; d.benefitRules = " Exact terms "
        let original = d, frozen = try XCTUnwrap(d.profile)
        d.name = "Changed"
        XCTAssertEqual(frozen.supplyName, "Store service"); XCTAssertEqual(original.name, "Store service")
        XCTAssertEqual(original.benefit.utf8.map { $0 }, " e\u{301} ".utf8.map { $0 })
    }
    func testExistingEditorConstructsBothCircleAndOriginalModesWithoutDispatch() throws {
        for circle in [true, false] {
            let host = UIHostingController(rootView: CoopFlowOfferEditor(context: try .init(chapterID: 7, termsMode: .traffic), eligibleTemplates: [], circleMode: circle, sourceIsCurrent: { false }))
            host.loadViewIfNeeded(); XCTAssertNotNil(host.view)
        }
    }
}

@MainActor private final class SupplyContextReader: CoopFlowReading {
    var session: CoopFlowSession? = try! .init(accountID: 7, epoch: 1, token: "synthetic-supply-token")
    func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON { .array([]) }
    func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement { throw CoopFlowFailure.disabled }
}
extension MerchantCircleSupplyDraftTests {
    private func source(mode: String = "TRAFFIC", active: Bool = false) throws -> MerchantContentSupplyContext {
        let bytes = Data("{\"id\":1,\"chapterId\":7,\"status\":1,\"offerId\":9,\"offerActive\":\(active ? "true" : "false"),\"circleThemeCode\":\"LOCAL\"}".utf8)
        let application = try JSONDecoder().decode(MerchantContentValue.self, from: bytes)
        let chapter = try JSONDecoder().decode(MerchantContentValue.self, from: Data("{\"id\":7,\"recruitStatus\":{\"termsMode\":\"\(mode)\"}}".utf8))
        return try .init(application: application, recruitmentChapters: [chapter])
    }
    func testSameSessionTermsOrOfferReplacementRejectsCapturedPreview() throws {
        let owner = MerchantSupplyContextOwner(), reader = SupplyContextReader()
        let a = owner.bind(try source(), reader: reader)
        let oldPreview = { owner.accepts(a, reader: reader) }
        let b = owner.bind(try source(mode: "PERK"), reader: reader)
        XCTAssertFalse(oldPreview()); XCTAssertTrue(owner.accepts(b, reader: reader))
        let c = owner.bind(try source(mode: "PERK", active: true), reader: reader)
        XCTAssertFalse(owner.accepts(b, reader: reader)); XCTAssertTrue(owner.accepts(c, reader: reader))
    }
    func testSameCompleteContextReturnKeepsRevisionAndLocalCard() throws {
        let owner = MerchantSupplyContextOwner(), reader = SupplyContextReader(), context = try source()
        let a = owner.bind(context, reader: reader), draft = complete()
        XCTAssertEqual(owner.bind(context, reader: reader), a)
        XCTAssertTrue(owner.accepts(a, reader: reader)); XCTAssertEqual(draft.profile?.supplyName, "Store service")
    }
    func testReaderReplacementAndSessionChangeRejectOriginalContext() throws {
        let owner = MerchantSupplyContextOwner(), reader = SupplyContextReader(), replacement = SupplyContextReader(), context = try source()
        let a = owner.bind(context, reader: reader)
        let b = owner.bind(context, reader: replacement)
        XCTAssertFalse(owner.accepts(a, reader: reader)); XCTAssertFalse(owner.accepts(a, reader: replacement))
        XCTAssertTrue(owner.accepts(b, reader: replacement))
        replacement.session = try .init(accountID: 8, epoch: 2, token: "synthetic-supply-new")
        XCTAssertFalse(owner.accepts(b, reader: replacement))
    }
}
