import Foundation
import XCTest
@testable import Questify

@MainActor private final class NPCReadOnlyAppReader: MerchantOperationsReading {
    var scope = UUID(), isAuthenticated = true
    var isConfigured = true, isOfflineExample = false, canSave = true
    var permissions = ["merchant:coop:manage"]
    var roleCode = "MERCHANT_MARKETING"
    var pending = false
    var readCount = 0, accessCount = 0, saveCount = 0
    var afterRead: (() -> Void)?
    func access() async throws -> MerchantOperationsAccess {
        accessCount += 1
        let data = try JSONSerialization.data(withJSONObject: ["active": true, "merchant": ["id": 31],
                                                               "roleCode": roleCode, "permissions": permissions])
        return try JSONDecoder().decode(MerchantOperationsAccess.self, from: data)
    }
    func hasPending(_ destination: MerchantOperationsDestination) -> Bool { pending }
    func document(_ destination: MerchantOperationsDestination) async throws -> MerchantOperationsDocument {
        readCount += 1; afterRead?()
        let value = try JSONDecoder().decode(MerchantNPCMapPoint.self, from: Data(#"{"id":31,"locationLat":0,"locationLng":0,"address":"Synthetic shop"}"#.utf8))
        return .draft(.npcMapPoint(value))
    }
    func saveReviewed(_ draft: MerchantOperationsDraft, baseline: MerchantOperationsDraft) async throws { saveCount += 1 }
    func saveExample(_ draft: MerchantOperationsDraft) async throws { saveCount += 1 }
}

@MainActor final class MerchantNPCMapPointReadOnlyAppTests: XCTestCase {
    func testReadOnlyModelShowsPointAndNeverEnablesEditorOrSaves() async throws {
        let reader = NPCReadOnlyAppReader()
        let model = MerchantNPCMapPointReadOnlyModel(reader: reader); model.appear()
        await model.load(model.refreshIntent)
        XCTAssertEqual(model.coordinator.point?.address, "Synthetic shop")
        XCTAssertEqual(model.coordinator.point?.coordinate?.latitude, 0)
        XCTAssertFalse(model.coordinator.canOpenEditor)
        await model.load(model.refreshIntent); model.disappear(); model.appear(); await model.load(model.refreshIntent)
        XCTAssertEqual(reader.saveCount, 0); XCTAssertFalse(model.coordinator.canOpenEditor)
    }
    func testWriterOnlyAppearsWithBothActualPermissions() async throws {
        let reader = NPCReadOnlyAppReader(); let model = MerchantNPCMapPointReadOnlyModel(reader: reader); model.appear()
        await model.load(model.refreshIntent); XCTAssertFalse(model.coordinator.canOpenEditor)
        reader.permissions.append("merchant:profile:write")
        await model.load(model.refreshIntent); XCTAssertTrue(model.coordinator.canOpenEditor)
        XCTAssertEqual(reader.saveCount, 0)
    }
    func testBackgroundOrDismissalInvalidatesVisiblePointAndEditor() async throws {
        let reader = NPCReadOnlyAppReader(); reader.permissions.append("merchant:profile:write")
        let model = MerchantNPCMapPointReadOnlyModel(reader: reader); model.appear(); await model.load(model.refreshIntent)
        XCTAssertTrue(model.coordinator.canOpenEditor)
        model.disappear(); XCTAssertNil(model.coordinator.point); XCTAssertFalse(model.coordinator.canOpenEditor)
        model.appear(); await model.load(model.refreshIntent); XCTAssertNotNil(model.coordinator.point); XCTAssertEqual(reader.saveCount, 0)
    }
    func testAccountChangeDuringLoadDropsTheReadOnlyResult() async throws {
        let reader = NPCReadOnlyAppReader(); reader.afterRead = { reader.scope = UUID() }
        let model = MerchantNPCMapPointReadOnlyModel(reader: reader); model.appear(); await model.load(model.refreshIntent)
        XCTAssertNil(model.coordinator.point); XCTAssertFalse(model.coordinator.canOpenEditor)
        XCTAssertEqual(reader.saveCount, 0)
    }
    func testRoleCodeNeverSubstitutesForWritePermission() async throws {
        let reader = NPCReadOnlyAppReader(); reader.roleCode = "MERCHANT_OWNER"
        let model = MerchantNPCMapPointReadOnlyModel(reader: reader); model.appear(); await model.load(model.refreshIntent)
        XCTAssertNotNil(model.coordinator.point); XCTAssertFalse(model.coordinator.canOpenEditor)
        XCTAssertEqual(reader.saveCount, 0)
    }
    func testPendingStorefrontWriteAllowsReadOnlyDetailsButNoEditor() async throws {
        let reader = NPCReadOnlyAppReader(); reader.permissions.append("merchant:profile:write"); reader.pending = true
        let model = MerchantNPCMapPointReadOnlyModel(reader: reader); model.appear(); await model.load(model.refreshIntent)
        XCTAssertNotNil(model.coordinator.point); XCTAssertTrue(model.coordinator.hasPendingWrite)
        XCTAssertFalse(model.coordinator.canOpenEditor); XCTAssertTrue(reader.pending); XCTAssertEqual(reader.saveCount, 0)
    }
    func testMalformedRoleFixtureFailsClosedWithoutDocumentOrSave() async throws {
        let reader = NPCReadOnlyAppReader(); reader.roleCode = "UNKNOWN_ROLE"
        let model = MerchantNPCMapPointReadOnlyModel(reader: reader); model.appear(); await model.load(model.refreshIntent)
        XCTAssertNil(model.coordinator.point); XCTAssertNotNil(model.coordinator.issue)
        XCTAssertEqual(reader.readCount, 0); XCTAssertEqual(reader.saveCount, 0)
    }
    func testQueuedRefreshAfterCloseDoesNotDispatchEvenAccessRead() async throws {
        let reader = NPCReadOnlyAppReader(); let model = MerchantNPCMapPointReadOnlyModel(reader: reader)
        model.appear(); let intent = try XCTUnwrap(model.refreshIntent)
        let queued = Task { await model.load(intent) }
        model.disappear()
        await queued.value
        XCTAssertNil(model.refreshIntent); XCTAssertNil(model.coordinator.point)
        XCTAssertEqual(reader.accessCount, 0); XCTAssertEqual(reader.readCount, 0); XCTAssertEqual(reader.saveCount, 0)
    }
    func testSameScopeReopenRejectsOldQueuedIntentButCurrentRefreshWorks() async throws {
        let reader = NPCReadOnlyAppReader(); let model = MerchantNPCMapPointReadOnlyModel(reader: reader)
        model.appear(); let oldIntent = try XCTUnwrap(model.refreshIntent); let sameScope = reader.scope
        let queued = Task { await model.load(oldIntent) }
        model.disappear(); model.appear(); let current = try XCTUnwrap(model.refreshIntent)
        XCTAssertEqual(reader.scope, sameScope); XCTAssertNotEqual(oldIntent, current)
        await queued.value
        XCTAssertEqual(reader.accessCount, 0); XCTAssertEqual(reader.readCount, 0)
        await model.load(current)
        XCTAssertNotNil(model.coordinator.point); XCTAssertEqual(reader.accessCount, 2); XCTAssertEqual(reader.readCount, 1)
        await model.load(current)
        XCTAssertEqual(reader.readCount, 2); XCTAssertEqual(reader.saveCount, 0)
    }
    func testCancelledTaskCannotDispatchOrActivateAnAppearance() async throws {
        let reader = NPCReadOnlyAppReader(); let model = MerchantNPCMapPointReadOnlyModel(reader: reader)
        model.appear(); let intent = try XCTUnwrap(model.refreshIntent)
        let queued = Task { await model.load(intent) }
        queued.cancel(); await queued.value
        XCTAssertEqual(reader.accessCount, 0); XCTAssertEqual(reader.readCount, 0); XCTAssertNil(model.coordinator.point)
        model.disappear()
        let closed = Task { await model.load(intent) }
        closed.cancel(); await closed.value
        XCTAssertNil(model.refreshIntent); XCTAssertEqual(reader.accessCount, 0); XCTAssertEqual(reader.saveCount, 0)
    }
    func testCancelledOldTaskCannotAdoptReopenedAppearance() async throws {
        let reader = NPCReadOnlyAppReader(); let model = MerchantNPCMapPointReadOnlyModel(reader: reader)
        model.appear(); let oldIntent = try XCTUnwrap(model.refreshIntent)
        let queued = Task { await model.load(oldIntent) }
        queued.cancel(); model.disappear(); model.appear()
        let current = try XCTUnwrap(model.refreshIntent)
        await queued.value
        XCTAssertEqual(model.refreshIntent, current); XCTAssertEqual(reader.accessCount, 0)
        await model.load(current); XCTAssertEqual(reader.readCount, 1); XCTAssertEqual(reader.saveCount, 0)
    }
    func testScopeChangeBeforeDispatchRejectsOldIntentWithoutAnyRead() async throws {
        let reader = NPCReadOnlyAppReader(); let model = MerchantNPCMapPointReadOnlyModel(reader: reader)
        model.appear(); let oldIntent = try XCTUnwrap(model.refreshIntent)
        reader.scope = UUID()
        await model.load(oldIntent)
        XCTAssertEqual(reader.accessCount, 0); XCTAssertEqual(reader.readCount, 0)
        let current = try XCTUnwrap(model.scopeChanged())
        await model.load(current); XCTAssertEqual(reader.readCount, 1); XCTAssertEqual(reader.saveCount, 0)
    }
    func testQueuedResumeAfterDisappearCannotReopenTheModel() async throws {
        let reader = NPCReadOnlyAppReader(); let model = MerchantNPCMapPointReadOnlyModel(reader: reader)
        model.appear(); model.suspend(); let resumed = try XCTUnwrap(model.resume())
        let queued = Task { await model.load(resumed) }
        model.disappear()
        await queued.value
        XCTAssertNil(model.resume()); XCTAssertNil(model.refreshIntent)
        XCTAssertEqual(reader.accessCount, 0); XCTAssertEqual(reader.readCount, 0); XCTAssertEqual(reader.saveCount, 0)
    }
    func testBackgroundInvalidatesQueuedIntentAndForegroundGetsFreshIntent() async throws {
        let reader = NPCReadOnlyAppReader(); let model = MerchantNPCMapPointReadOnlyModel(reader: reader)
        model.appear(); let before = try XCTUnwrap(model.refreshIntent)
        model.suspend(); await model.load(before)
        XCTAssertEqual(reader.accessCount, 0)
        let after = try XCTUnwrap(model.resume()); XCTAssertNotEqual(before, after)
        await model.load(before); XCTAssertEqual(reader.readCount, 0)
        await model.load(after); XCTAssertEqual(reader.readCount, 1); XCTAssertEqual(reader.saveCount, 0)
    }
    func testInactiveAppearanceAndUndisplayedResumeCannotStartARead() async throws {
        let reader = NPCReadOnlyAppReader(); let model = MerchantNPCMapPointReadOnlyModel(reader: reader)
        XCTAssertNil(model.resume()); await model.load(model.refreshIntent)
        model.appear(isActive: false); await model.load(model.refreshIntent)
        XCTAssertNil(model.refreshIntent); XCTAssertEqual(reader.accessCount, 0)
        let active = try XCTUnwrap(model.resume()); await model.load(active)
        XCTAssertEqual(reader.readCount, 1); XCTAssertEqual(reader.saveCount, 0)
    }

}
