import XCTest
@testable import Questify

@MainActor final class MerchantNPCMapPointManualTests: XCTestCase {
    private func setup() async -> (MerchantOperationsViewModel, MerchantOperationsFixtureReader) {
        let reader = MerchantOperationsFixtureReader()
        let document = MerchantOperationsViewModel(reader: reader, destination: .npcMapPoint)
        await document.load(); return (document, reader)
    }
    func testOpenAndCancelKeepServerPointAndMakeNoWrite() async throws {
        let (document, reader) = await setup()
        let before = document.coordinator.draft
        let model = try XCTUnwrap(MerchantNPCMapPointManualModel(document: document))
        XCTAssertNil(model.confirmedDatum); XCTAssertFalse(model.canApply)
        model.setLatitude("32"); model.confirmDatum(.gcj02); XCTAssertTrue(model.canApply)
        model.cancel(); XCTAssertFalse(model.apply())
        XCTAssertEqual(document.coordinator.draft, before); XCTAssertEqual(reader.saveCount, 0)
    }
    func testExplicitApplyCreatesOnlyLocalPointDraftAndReviewIsSeparate() async throws {
        let (document, reader) = await setup()
        let model = try XCTUnwrap(MerchantNPCMapPointManualModel(document: document))
        model.setLatitude("32"); model.setLongitude("122"); model.setAddress("Synthetic new point"); model.confirmDatum(.gcj02)
        XCTAssertTrue(model.apply()); XCTAssertTrue(document.coordinator.isDirty)
        XCTAssertNil(document.coordinator.confirmation); XCTAssertEqual(reader.saveCount, 0); XCTAssertFalse(model.apply())
        document.prepare(); XCTAssertNotNil(document.coordinator.confirmation)
        XCTAssertEqual(reader.saveCount, 0)
    }
    func testUnchangedPointDoesNotCreateDirtyDraft() async throws {
        let (document, _) = await setup()
        let model = try XCTUnwrap(MerchantNPCMapPointManualModel(document: document)); model.confirmDatum(.gcj02)
        XCTAssertFalse(model.canApply); XCTAssertFalse(document.coordinator.isDirty)
    }
    func testEditingAfterDatumConfirmationRequiresConfirmationAgain() async throws {
        let (document, _) = await setup(); let model = try XCTUnwrap(MerchantNPCMapPointManualModel(document: document))
        model.setLatitude("32"); model.confirmDatum(.gcj02); XCTAssertTrue(model.canApply)
        model.setLongitude("122"); XCTAssertNil(model.confirmedDatum); XCTAssertFalse(model.canApply)
        model.confirmDatum(.gcj02); model.setAddress("Changed"); XCTAssertNil(model.confirmedDatum)
    }
    func testUnknownAndWGS84AreRejectedWithoutConversion() async throws {
        let (document, _) = await setup(); let model = try XCTUnwrap(MerchantNPCMapPointManualModel(document: document))
        model.setLatitude("32"); XCTAssertFalse(model.canApply)
        model.confirmDatum(.wgs84); XCTAssertNil(model.candidate); XCTAssertFalse(model.apply())
    }
    func testInvalidAndHalfCoordinatesCannotApply() async throws {
        let (document, _) = await setup(); let model = try XCTUnwrap(MerchantNPCMapPointManualModel(document: document))
        for text in ["", "nan", "91", "abc"] {
            model.setLatitude(text); model.confirmDatum(.gcj02); XCTAssertFalse(model.canApply)
        }
    }
    func testZeroCoordinatesRemainAnExplicitValidChoice() async throws {
        let (document, _) = await setup(); let model = try XCTUnwrap(MerchantNPCMapPointManualModel(document: document))
        model.setLatitude("0"); model.setLongitude("0"); model.confirmDatum(.gcj02)
        XCTAssertTrue(model.apply())
        guard case .npcMapPoint(let point) = document.coordinator.draft else { return XCTFail() }
        XCTAssertEqual(point.coordinate?.latitude, 0); XCTAssertEqual(point.coordinate?.longitude, 0)
    }
    func testConcurrentEditRejectsOldSheet() async throws {
        let (document, _) = await setup(); let model = try XCTUnwrap(MerchantNPCMapPointManualModel(document: document))
        guard case .npcMapPoint(let point) = document.coordinator.draft else { return XCTFail() }
        document.edit(.npcMapPoint(try point.replacing(latitude: "33", longitude: "123", address: "Newer", confirmedDatum: .gcj02)))
        model.setLatitude("32"); model.confirmDatum(.gcj02); XCTAssertFalse(model.apply())
    }
    func testReloadSamePointInvalidatesOldSheet() async throws {
        let (document, _) = await setup(); let model = try XCTUnwrap(MerchantNPCMapPointManualModel(document: document))
        model.setLatitude("32"); model.confirmDatum(.gcj02); await document.load()
        XCTAssertFalse(model.isCurrent); XCTAssertFalse(model.apply())
    }
    func testAccountSwitchAndScopeChangeRejectSheet() async throws {
        let (document, reader) = await setup(); let model = try XCTUnwrap(MerchantNPCMapPointManualModel(document: document))
        model.setLatitude("32"); model.confirmDatum(.gcj02); reader.switchAccount()
        XCTAssertFalse(model.apply()); XCTAssertEqual(reader.saveCount, 0)
    }
    func testUnknownWriteLockPreventsNewManualSheet() async throws {
        let (document, reader) = await setup(); let model = try XCTUnwrap(MerchantNPCMapPointManualModel(document: document))
        model.setLatitude("32"); model.confirmDatum(.gcj02); XCTAssertTrue(model.apply())
        document.prepare(); reader.saveFailure = .outcomeUnknown
        await document.confirm(try XCTUnwrap(document.coordinator.confirmation))
        XCTAssertTrue(document.coordinator.isLocked); XCTAssertNil(MerchantNPCMapPointManualModel(document: document))
    }
    func testCancellationClearsInputAndDisallowsLateApply() async throws {
        let (document, _) = await setup(); let model = try XCTUnwrap(MerchantNPCMapPointManualModel(document: document))
        model.setLatitude("32"); model.confirmDatum(.gcj02); model.cancel()
        XCTAssertEqual(model.latitude, ""); XCTAssertEqual(model.longitude, ""); XCTAssertEqual(model.address, "")
        XCTAssertNil(model.confirmedDatum); XCTAssertFalse(model.apply())
    }
}
