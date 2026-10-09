import Foundation
import XCTest
@testable import QuestifyCore

final class MerchantCoopCapacityClearTests: XCTestCase {
    private func value(_ json: String) throws -> MerchantCoopSettings { try JSONDecoder().decode(MerchantCoopSettings.self, from: Data(json.utf8)) }
    func testExplicitDeletionSendsNullAndTrueClearFlagOnExistingRoute() throws {
        var draft = try value(#"{"capacity":12,"chargeType":0}"#); draft.capacity = ""
        let preview = try XCTUnwrap(MerchantOperationsDraft.cooperation(draft).previews().first)
        XCTAssertEqual(preview.path, "api/merchant/coop-profile/save")
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: preview.json) as? [String: Any])
        XCTAssertTrue(fields["capacity"] is NSNull)
        XCTAssertEqual((fields["params"] as? [String: Bool]), ["clearCapacity": true])
    }
    func testMissingNullAndEmptySourceNeverBecomeImplicitClear() throws {
        for json in [#"{}"#, #"{"capacity":null}"#, #"{"capacity":""}"#] {
            var draft = try value(json); draft.demand = "Edited"
            XCTAssertFalse(draft.clearsCapacity); XCTAssertNil(draft.fields["capacity"]); XCTAssertNil(draft.fields["params"])
            draft.capacity = "12"; draft.capacity = ""
            XCTAssertFalse(draft.clearsCapacity); XCTAssertNil(draft.fields["params"])
        }
    }
    func testZeroRemainsZeroAndCanOnlyBeClearedByDeletingIt() throws {
        var draft = try value(#"{"capacity":0}"#)
        XCTAssertEqual(draft.fields["capacity"] as? Int, 0); XCTAssertFalse(draft.clearsCapacity); XCTAssertNil(draft.fields["params"])
        draft.capacity = ""; XCTAssertTrue(draft.clearsCapacity)
        draft.capacity = "0"; XCTAssertFalse(draft.clearsCapacity); XCTAssertEqual(draft.fields["capacity"] as? Int, 0)
    }
    func testRestoreCancelsClearAndOtherOverwriteFieldsStayIntact() throws {
        var draft = try value(#"{"capacity":12,"availableTime":"Weekends","chargeType":1,"demand":"Original","suitActivityTypes":"walk;workshop","coopOpen":99}"#)
        let original = draft; draft.capacity = ""
        XCTAssertEqual(draft.fields["suitActivityTypes"] as? String, "walk;workshop")
        XCTAssertEqual(draft.fields["coopOpen"] as? Int, 99)
        XCTAssertEqual(draft.fields["availableTime"] as? String, "Weekends")
        XCTAssertEqual(draft.fields["chargeType"] as? Int, 1); XCTAssertEqual(draft.fields["demand"] as? String, "Original")
        draft.capacity = "12"; XCTAssertEqual(draft, original); XCTAssertNil(draft.fields["params"])
    }
    func testAcknowledgementSeparatesConsumedIntentFromFreshServerBaseline() throws {
        var cleared = try value(#"{"capacity":12}"#); cleared.capacity = "  "
        XCTAssertTrue(cleared.clearsCapacity)
        let fresh = try value(#"{"capacity":null}"#)
        XCTAssertNotEqual(cleared, fresh) // Unapplied whitespace still differs from the returned field.
        cleared.capacity = ""
        XCTAssertEqual(cleared, fresh) // Freshness compares facts; clear intent is checked separately.
        XCTAssertTrue(cleared.clearsCapacity); XCTAssertFalse(fresh.clearsCapacity)
        cleared.acknowledgeCapacityEdit()
        XCTAssertEqual(cleared, fresh); XCTAssertFalse(cleared.clearsCapacity); XCTAssertNil(cleared.fields["params"])
        cleared.demand = "Next edit"; XCTAssertNil(cleared.fields["capacity"]); XCTAssertNil(cleared.fields["params"])
    }
    func testUnrelatedParamsCannotRequestClearAndInvalidCapacityStillBlocks() throws {
        var draft = try value(#"{"capacity":12,"params":{"clearCapacity":true,"other":"kept-on-server"}}"#)
        XCTAssertFalse(draft.clearsCapacity); XCTAssertNil(draft.fields["params"])
        for text in ["-1", "1.5", "invalid"] { draft.capacity = text; XCTAssertFalse(draft.clearsCapacity); XCTAssertNotNil(draft.blocker) }
    }
}

@MainActor private final class CapacityClearReader: MerchantOperationsReading {
    var scope = UUID()
    var isConfigured = true
    var isAuthenticated = true
    var isOfflineExample = true
    var canSave = true
    var failure: MerchantOperationsFailure?
    var current: MerchantCoopSettings
    var saves = 0
    var bodies: [[String: Any]] = []
    init() throws { current = try JSONDecoder().decode(MerchantCoopSettings.self, from: Data(#"{"capacity":12,"chargeType":0}"#.utf8)) }
    func access() async throws -> MerchantOperationsAccess { try JSONDecoder().decode(MerchantOperationsAccess.self, from: Data(#"{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:coop:manage"]}"#.utf8)) }
    func document(_ destination: MerchantOperationsDestination) async throws -> MerchantOperationsDocument { .draft(.cooperation(current)) }
    func saveExample(_ draft: MerchantOperationsDraft) async throws { throw MerchantOperationsFailure.liveWritesDisabled }
    func saveReviewed(_ draft: MerchantOperationsDraft, baseline: MerchantOperationsDraft) async throws {
        saves += 1
        guard case .cooperation(let value) = draft else { throw APIError.invalidRequest }
        bodies.append(value.fields)
        if let failure { throw failure }
        current = try JSONDecoder().decode(MerchantCoopSettings.self, from: JSONSerialization.data(withJSONObject: value.fields))
    }
}

@MainActor final class MerchantCoopCapacityClearCoordinatorTests: XCTestCase {
    private func setup() async throws -> (CapacityClearReader, MerchantOperationsCoordinator) {
        let reader = try CapacityClearReader(), model = MerchantOperationsCoordinator(reader: reader, destination: .cooperation)
        await model.load(); var value = reader.current; value.capacity = ""; model.edit(.cooperation(value)); model.prepare()
        return (reader, model)
    }
    private func cleared(_ model: MerchantOperationsCoordinator) -> Bool {
        guard case .cooperation(let value) = model.draft else { return false }; return value.clearsCapacity
    }
    func testCancelReviewKeepsDraftButDiscardRestoresSourceWithoutSaving() async throws {
        let (reader, model) = try await setup(); XCTAssertNotNil(model.confirmation)
        model.cancelConfirmation(); XCTAssertNil(model.confirmation); XCTAssertTrue(cleared(model)); XCTAssertEqual(reader.saves, 0)
        model.prepare(); XCTAssertNotNil(model.confirmation)
        model.discardChanges(); XCTAssertFalse(cleared(model)); XCTAssertFalse(model.isDirty); XCTAssertNil(model.confirmation); XCTAssertEqual(reader.saves, 0)
    }
    func testSuccessConsumesIntentAndNextEditUsesFreshComparableBaseline() async throws {
        let (reader, model) = try await setup()
        await model.confirm(try XCTUnwrap(model.confirmation)); XCTAssertEqual(reader.saves, 1); XCTAssertFalse(cleared(model)); XCTAssertFalse(model.isDirty)
        XCTAssertEqual(model.baseline, .cooperation(reader.current))
        guard case .cooperation(var next) = model.draft else { return XCTFail() }
        next.demand = "Next edit"; model.edit(.cooperation(next)); model.prepare()
        await model.confirm(try XCTUnwrap(model.confirmation))
        XCTAssertEqual(reader.saves, 2); XCTAssertNil(reader.bodies.last?["params"]); XCTAssertFalse(cleared(model))
    }
    func testUnknownOutcomeKeepsIntentAndBlocksAllReplay() async throws {
        let (reader, model) = try await setup(); reader.failure = .outcomeUnknown
        let review = try XCTUnwrap(model.confirmation); await model.confirm(review)
        XCTAssertTrue(cleared(model)); XCTAssertTrue(model.isLocked); XCTAssertEqual(reader.saves, 1)
        model.prepare(); XCTAssertNil(model.confirmation); await model.confirm(review); XCTAssertEqual(reader.saves, 1)
    }
    func testDefiniteFailureKeepsIntentUntilExplicitNewReviewSucceeds() async throws {
        let (reader, model) = try await setup(); reader.failure = .rejected(code: 400, message: "Synthetic")
        await model.confirm(try XCTUnwrap(model.confirmation)); XCTAssertTrue(cleared(model)); XCTAssertFalse(model.isLocked); XCTAssertEqual(reader.saves, 1)
        reader.failure = nil; model.prepare(); await model.confirm(try XCTUnwrap(model.confirmation))
        XCTAssertEqual(reader.saves, 2); XCTAssertFalse(cleared(model))
    }
    func testScopeReplacementAndChangedSourceCannotSubmitTheOldClear() async throws {
        let (reader, model) = try await setup(); let review = try XCTUnwrap(model.confirmation)
        reader.scope = UUID(); await model.confirm(review); XCTAssertEqual(reader.saves, 0)
        let (other, freshModel) = try await setup(); other.current.capacity = "24"
        await freshModel.confirm(try XCTUnwrap(freshModel.confirmation))
        XCTAssertEqual(other.saves, 0); XCTAssertTrue(cleared(freshModel)); XCTAssertEqual(freshModel.issue, .key("merchant.operations.conflict"))
    }
}
