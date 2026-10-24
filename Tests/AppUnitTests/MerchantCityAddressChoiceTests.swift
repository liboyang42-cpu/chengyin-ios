import XCTest
import SwiftUI
@testable import Questify

@MainActor final class MerchantCityAddressChoiceTests: XCTestCase {
    @MainActor private final class Places: PublishingPlaceSearching {
        var calls = 0
        func search(_ query: String) async throws -> [PublishingPlace] { calls += 1; return [] }
    }
    private func source(scope: UUID = UUID(), merchant: Int = 9) -> MerchantCityAddressChoice.Source {
        .init(scope: scope, observedAt: Date(timeIntervalSince1970: 100), merchantID: merchant, templateID: 7,
              addressGeneration: UUID(), fields: ["name": Data("Store".utf8), "tags": Data("Kept".utf8)], addressConfirmed: false)
    }
    private func place() throws -> PublishingPlace { try .init(id: "synthetic", name: "Chosen", address: "Exact address", latitude: 31.2, longitude: 121.4) }
    private func ready() -> MerchantCityAddressChoice { let value = MerchantCityAddressChoice(); value.appear(active: true); return value }
    private func open(_ owner: MerchantCityAddressChoice, _ source: MerchantCityAddressChoice.Source, _ provider: Places) throws -> MerchantCityAddressChoice.Item {
        owner.openAction(source, provider: provider, current: { source })(); return try XCTUnwrap(owner.item)
    }
    func testExplicitChoiceConfirmsOriginalSourceOnceWithoutSearchingAutomatically() throws {
        let o = ready(), s = source(), p = Places(), item = try open(o, s, p)
        var received: [PublishingPlace] = []
        XCTAssertTrue(o.confirm(try place(), original: item, current: { s }) { original, value in XCTAssertEqual(original, s); received.append(value); return true })
        XCTAssertFalse(o.confirm(try place(), original: item, current: { s }) { _, _ in XCTFail(); return true })
        XCTAssertEqual(received, [try place()]); XCTAssertEqual(p.calls, 0)
    }
    func testMissingProviderNeverPresentsOrSearches() {
        let o = ready(), s = source(); o.openAction(s, provider: nil, current: { s })(); XCTAssertNil(o.item)
    }
    func testCancelLeavesDraftAndOldOpeningCannotReopen() throws {
        let o = ready(), s = source(), p = Places(); let action = o.openAction(s, provider: p, current: { s })
        action(); let item = try XCTUnwrap(o.item); o.cancel(item); action()
        XCTAssertNil(o.item); XCTAssertEqual(p.calls, 0)
        XCTAssertFalse(o.confirm(try place(), original: item, current: { s }) { _, _ in XCTFail(); return true })
    }
    func testOldBindingAndCompletionCannotClearNewChoice() throws {
        let o = ready(), s = source(), p = Places(), a = try open(o, s, p)
        let binding = o.binding(a, current: { s }); o.cancel(a); let b = try open(o, s, p)
        binding.wrappedValue = nil; XCTAssertNil(binding.wrappedValue); XCTAssertEqual(o.item?.id, b.id)
        XCTAssertFalse(o.confirm(try place(), original: a, current: { s }) { _, _ in XCTFail(); return true })
    }
    func testSnapshotMerchantAndInputChangesRejectConfirmation() throws {
        let o = ready(), s = source(), p = Places(), item = try open(o, s, p)
        for changed in [source(scope: s.scope, merchant: 10), source(scope: s.scope), source()] {
            XCTAssertFalse(o.confirm(try place(), original: item, current: { changed }) { _, _ in XCTFail(); return true })
        }
        XCTAssertFalse(o.confirm(try place(), original: item, current: { nil }) { _, _ in XCTFail(); return true })
    }
    func testOwnModalCoveragePermitsExactExplicitConfirmation() throws {
        let o = ready(), s = source(), p = Places(), item = try open(o, s, p)
        o.cover(item.attachment)
        XCTAssertTrue(o.confirm(try place(), original: item, current: { s }) { _, _ in true })
    }
    func testBackgroundRetiresChoiceAndHiddenActiveCannotOpen() throws {
        let o = ready(), s = source(), p = Places(), item = try open(o, s, p)
        o.cover(item.attachment); o.sceneChanged(active: false); o.sceneChanged(active: true)
        XCTAssertFalse(o.confirm(try place(), original: item, current: { s }) { _, _ in XCTFail(); return true })
        o.openAction(s, provider: p, current: { s })(); XCTAssertNil(o.item)
        o.reappear(item.attachment); XCTAssertNotNil(try open(o, s, p))
    }
    func testTrueDepartureRejectsOldOpeningAndOldAttachmentCannotRetireReplacement() throws {
        let o = ready(), s = source(), p = Places(); let queued = o.openAction(s, provider: p, current: { s })
        let old = try XCTUnwrap(o.attachment); o.depart(old); o.appear(active: true); queued(); XCTAssertNil(o.item)
        let item = try open(o, s, p); o.depart(old); o.cover(old)
        XCTAssertTrue(o.matches(item, current: { s }))
    }
    func testUnrelatedCoverageCannotOpenFromOldButton() throws {
        let o = ready(), s = source(), p = Places(); let queued = o.openAction(s, provider: p, current: { s })
        o.cover(try XCTUnwrap(o.attachment)); queued(); XCTAssertNil(o.item); XCTAssertEqual(p.calls, 0)
    }
    func testRejectedParentApplyKeepsSameChoiceForExplicitRecovery() throws {
        let o = ready(), s = source(), p = Places(), item = try open(o, s, p)
        XCTAssertFalse(o.confirm(try place(), original: item, current: { s }) { _, _ in false })
        XCTAssertEqual(o.item?.id, item.id); XCTAssertEqual(p.calls, 0)
    }
    func testActualParentProjectionChangesOnlyFourAddressFields() throws {
        let fields = ["name": "Old", "address": "Before", "latitude": "0", "longitude": "0", "tags": " e\u{301} ", "coverImg": "existing", "cityCode": "310000"]
        let result = MerchantCityAddressChoice.replacingAddress(in: fields, with: try place())
        XCTAssertEqual(result["name"], "Chosen"); XCTAssertEqual(result["address"], "Exact address")
        XCTAssertEqual(result["latitude"], "31.2"); XCTAssertEqual(result["longitude"], "121.4")
        for key in ["tags", "coverImg", "cityCode"] { XCTAssertEqual(result[key]?.utf8.map { $0 }, fields[key]?.utf8.map { $0 }) }
    }

}
