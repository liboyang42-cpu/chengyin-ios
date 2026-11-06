import XCTest
import SwiftUI
import Combine
@testable import Questify

@MainActor private final class SheetLocks: OfficialActionLockStore {
    var values = Set<String>()
    func contains(_ key: String) throws -> Bool { values.contains(key) }
    func insert(_ key: String) throws { values.insert(key) }
    func remove(_ key: String) throws { values.remove(key) }
}
@MainActor private final class SheetAccess: OfficialActionAccess {
    var identity: OfficialActionIdentity? = .init(accountID: 71, epoch: UUID(), namespace: "synthetic")
    var enabled = true
    var reads = 0, writes = 0
    var pauseRead = false, pauseWrite = false
    var onRead: (() -> Void)?, onWrite: (() -> Void)?
    var readContinuation: CheckedContinuation<OfficialActionSnapshot, Error>?
    var writeContinuation: CheckedContinuation<OfficialActionReceipt, Error>?
    func facts() throws -> OfficialActionSnapshot {
        let event = try JSONDecoder().decode(OfficialEvent.self, from: Data(#"{"id":8,"title":"Synthetic","status":3,"signed":false}"#.utf8))
        return .init(identity: try XCTUnwrap(identity), event: event)
    }
    func snapshot(for command: OfficialActionCommand) async throws -> OfficialActionSnapshot {
        reads += 1
        if pauseRead { return try await withCheckedThrowingContinuation { readContinuation = $0; onRead?() } }
        onRead?(); return try facts()
    }
    func send(_ command: OfficialActionCommand) async throws -> OfficialActionReceipt {
        writes += 1
        if pauseWrite { return try await withCheckedThrowingContinuation { writeContinuation = $0; onWrite?() } }
        onWrite?(); return .acknowledged
    }
}
@MainActor private final class SheetZeroWire: HTTPTransport {
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); throw APIError.notConfigured
    }
}
@MainActor final class OfficialActionPresentationModelTests: XCTestCase {
    private func settle(_ model: OfficialActionPresentationModel, action: () -> Void) async {
        let finished = expectation(description: "sheet operation finished")
        let token = model.$busy.dropFirst().filter { !$0 }.prefix(1).sink { _ in finished.fulfill() }
        action()
        await fulfillment(of: [finished], timeout: 1)
        withExtendedLifetime(token) {}
    }
    private func noRequests(_ access: SheetAccess, action: () -> Void) async {
        let unexpected = expectation(description: "no synthetic dispatch"); unexpected.isInverted = true
        access.onRead = { unexpected.fulfill() }; access.onWrite = { unexpected.fulfill() }
        action()
        await fulfillment(of: [unexpected], timeout: 0.05)
        access.onRead = nil; access.onWrite = nil
    }
    func testConstructionAndInactiveAppearanceAreRequestFree() async {
        let access = SheetAccess(), coordinator = OfficialActionCoordinator(access: access, locks: SheetLocks())
        let model = OfficialActionPresentationModel(coordinator: coordinator, command: .signup(8))
        await noRequests(access) { model.appear(isActive: false) }
        XCTAssertNil(model.review); XCTAssertFalse(model.canConfirm); XCTAssertEqual(access.reads, 0)
        model.disappear()
    }
    func testActiveAppearanceReadsBeforeExplicitConfirmation() async throws {
        let access = SheetAccess(), coordinator = OfficialActionCoordinator(access: access, locks: SheetLocks())
        let model = OfficialActionPresentationModel(coordinator: coordinator, command: .signup(8))
        await settle(model) { model.appear(isActive: true) }
        let review = try XCTUnwrap(model.review)
        XCTAssertTrue(model.canConfirm); XCTAssertEqual(access.reads, 1); XCTAssertEqual(access.writes, 0)
        await settle(model) { model.submit(review) }
        XCTAssertEqual(model.receipt, .acknowledged); XCTAssertEqual(access.reads, 2); XCTAssertEqual(access.writes, 1)
        XCTAssertFalse(model.canConfirm)
    }
    func testDuplicateConfirmationTapQueuesOnlyOneOriginalWrite() async throws {
        let access = SheetAccess(), coordinator = OfficialActionCoordinator(access: access, locks: SheetLocks())
        let model = OfficialActionPresentationModel(coordinator: coordinator, command: .signup(8))
        await settle(model) { model.appear(isActive: true) }
        let review = try XCTUnwrap(model.review)
        await settle(model) {
            model.submit(review); XCTAssertTrue(model.busy); model.submit(review)
        }
        XCTAssertEqual(access.writes, 1); XCTAssertEqual(access.reads, 2)
    }
    func testBackgroundBeforeQueuedConfirmationHasNoDispatchAndRequiresFreshReview() async throws {
        let access = SheetAccess(), coordinator = OfficialActionCoordinator(access: access, locks: SheetLocks())
        let model = OfficialActionPresentationModel(coordinator: coordinator, command: .signup(8))
        await settle(model) { model.appear(isActive: true) }
        let original = try XCTUnwrap(model.review)
        await noRequests(access) { model.submit(original); model.sceneChanged(isActive: false) }
        XCTAssertNil(model.review); XCTAssertNil(model.receipt); XCTAssertEqual(access.writes, 0)
        await settle(model) { model.sceneChanged(isActive: true) }
        XCTAssertNotEqual(model.review?.id, original.id); XCTAssertEqual(access.reads, 2)
        await noRequests(access) { model.submit(original) }
        XCTAssertEqual(access.writes, 0)
    }
    func testDisappearanceBeforeQueuedPrepareCannotReappearAndDispatch() async {
        let access = SheetAccess(), coordinator = OfficialActionCoordinator(access: access, locks: SheetLocks())
        let model = OfficialActionPresentationModel(coordinator: coordinator, command: .signup(8))
        await noRequests(access) {
            model.appear(isActive: true); model.disappear(); model.appear(isActive: true)
        }
        XCTAssertNil(model.review); XCTAssertFalse(model.busy); XCTAssertEqual(access.reads, 0)
    }
    func testOldSheetDisappearanceDoesNotCancelReplacementReview() async throws {
        let access = SheetAccess(), coordinator = OfficialActionCoordinator(access: access, locks: SheetLocks())
        let old = OfficialActionPresentationModel(coordinator: coordinator, command: .signup(8))
        await settle(old) { old.appear(isActive: true) }
        let current = OfficialActionPresentationModel(coordinator: coordinator, command: .signup(8))
        await settle(current) { current.appear(isActive: true) }
        old.disappear()
        let review = try XCTUnwrap(current.review); XCTAssertTrue(current.canConfirm)
        await settle(current) { current.submit(review) }
        XCTAssertEqual(current.receipt, .acknowledged); XCTAssertEqual(access.writes, 1)
    }
    func testOldForegroundCannotStealNewSheetOwner() async throws {
        let access = SheetAccess(), coordinator = OfficialActionCoordinator(access: access, locks: SheetLocks())
        let old = OfficialActionPresentationModel(coordinator: coordinator, command: .signup(8))
        await settle(old) { old.appear(isActive: true) }
        old.sceneChanged(isActive: false)
        let current = OfficialActionPresentationModel(coordinator: coordinator, command: .signup(8))
        await settle(current) { current.appear(isActive: true) }
        await noRequests(access) { old.sceneChanged(isActive: true) }
        XCTAssertEqual(old.message, "officialAction.stale"); XCTAssertTrue(current.canConfirm)
        let review = try XCTUnwrap(current.review)
        await settle(current) { current.submit(review) }
        XCTAssertEqual(access.writes, 1)
    }
    func testIdentityChangeBetweenTapAndTaskCannotDispatchOrRebind() async throws {
        let access = SheetAccess(), coordinator = OfficialActionCoordinator(access: access, locks: SheetLocks())
        let model = OfficialActionPresentationModel(coordinator: coordinator, command: .signup(8))
        await settle(model) { model.appear(isActive: true) }
        let review = try XCTUnwrap(model.review)
        await noRequests(access) {
            model.submit(review)
            access.identity = .init(accountID: 72, epoch: UUID(), namespace: "synthetic")
            model.synchronizeIdentity(); model.sceneChanged(isActive: true)
        }
        XCTAssertNil(model.review); XCTAssertNil(model.receipt); XCTAssertEqual(model.message, "officialAction.stale")
        XCTAssertEqual(access.writes, 0)
    }
    func testCancelledInFlightReadCannotOverwriteNewOwnerAndExplicitReadCanRecover() async throws {
        let access = SheetAccess(), coordinator = OfficialActionCoordinator(access: access, locks: SheetLocks())
        let old = OfficialActionPresentationModel(coordinator: coordinator, command: .signup(8))
        access.pauseRead = true; let started = expectation(description: "old snapshot started")
        access.onRead = { started.fulfill() }; old.appear(isActive: true)
        await fulfillment(of: [started], timeout: 1)
        old.disappear(); access.onRead = nil
        let current = OfficialActionPresentationModel(coordinator: coordinator, command: .signup(8))
        // The coordinator remains busy until the original read unwinds; do not poll/retry it.
        await settle(current) { current.appear(isActive: true) }
        XCTAssertNil(current.review); XCTAssertNotNil(current.message); XCTAssertTrue(current.canReview)
        let unexpected = expectation(description: "retired read cannot publish"); unexpected.isInverted = true
        let token = old.$review.compactMap { $0 }.sink { _ in unexpected.fulfill() }
        access.readContinuation?.resume(returning: try access.facts()); access.readContinuation = nil
        await fulfillment(of: [unexpected], timeout: 0.05); withExtendedLifetime(token) {}
        access.pauseRead = false
        await settle(current) { current.readAgain() }
        XCTAssertNotNil(current.review); XCTAssertNil(current.message); XCTAssertEqual(access.reads, 2)
        XCTAssertEqual(access.writes, 0); XCTAssertNil(old.review)
    }
    func testBackgroundAfterDispatchedWriteKeepsLockWithoutRenderingLateReceipt() async throws {
        let access = SheetAccess(), locks = SheetLocks(), coordinator = OfficialActionCoordinator(access: access, locks: locks)
        let model = OfficialActionPresentationModel(coordinator: coordinator, command: .signup(8))
        await settle(model) { model.appear(isActive: true) }
        let review = try XCTUnwrap(model.review), started = expectation(description: "original write started")
        access.pauseWrite = true; access.onWrite = { started.fulfill() }; model.submit(review)
        await fulfillment(of: [started], timeout: 1)
        model.sceneChanged(isActive: false)
        let unexpected = expectation(description: "no late receipt"); unexpected.isInverted = true
        let token = model.$receipt.compactMap { $0 }.sink { _ in unexpected.fulfill() }
        access.writeContinuation?.resume(returning: .acknowledged); access.writeContinuation = nil
        await fulfillment(of: [unexpected], timeout: 0.05); withExtendedLifetime(token) {}
        XCTAssertEqual(coordinator.state, .unknown); XCTAssertEqual(locks.values.count, 1)
        await settle(model) { model.sceneChanged(isActive: true) }
        XCTAssertEqual(model.message, "officialAction.locked"); XCTAssertNil(model.receipt)
        XCTAssertEqual(access.writes, 1)
    }
    func testDefaultProductionFactoryStillMakesZeroRequests() async {
        let wire = SheetZeroWire()
        let access = OfficialActionProductionFactory(api: nil, transport: wire, current: { nil }, identity: { nil })
        let coordinator = OfficialActionCoordinator(access: access, locks: SheetLocks())
        let model = OfficialActionPresentationModel(coordinator: coordinator, command: .signup(8))
        await settle(model) { model.appear(isActive: true) }
        XCTAssertEqual(model.message, "officialAction.forbidden"); XCTAssertFalse(model.canConfirm)
        XCTAssertFalse(model.canReview); XCTAssertTrue(wire.requests.isEmpty)
    }
    func testModelBindingRequiresOriginalCoordinatorAndCommand() {
        let access = SheetAccess(), coordinator = OfficialActionCoordinator(access: access, locks: SheetLocks())
        let other = OfficialActionCoordinator(access: access, locks: SheetLocks())
        let model = OfficialActionPresentationModel(coordinator: coordinator, command: .signup(8))
        XCTAssertTrue(model.isBound(to: coordinator, command: .signup(8)))
        XCTAssertFalse(model.isBound(to: other, command: .signup(8)))
        XCTAssertFalse(model.isBound(to: coordinator, command: .signup(9)))
    }
    func testFinishedSheetDoesNotRetainModelThroughCoordinator() {
        let coordinator = OfficialActionCoordinator(access: SheetAccess(), locks: SheetLocks())
        weak var weakModel: OfficialActionPresentationModel?
        autoreleasepool {
            let model = OfficialActionPresentationModel(coordinator: coordinator, command: .signup(8))
            weakModel = model; model.disappear()
        }
        XCTAssertNil(weakModel)
    }
    func testSharedSheetWiresSceneIdentityAndOriginalConfirmation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("App/OfficialActionViews.swift"))
        let sheet = String(try XCTUnwrap(text.components(separatedBy: "@MainActor struct OfficialPublishEditor").first))
        for value in ["model.appear(isActive: scenePhase == .active)", "model.sceneChanged(isActive: phase == .active)",
                      "model.synchronizeIdentity()", "model.submit(review)", ".disabled(!model.canConfirm)",
                      "model.disappear()", "model.readAgain()", "model.isBound(to: coordinator, command: command)",
                      "officialAction.reviewPayload", "officialAction.refreshFacts", "officialAction.noOutcomePromise"] {
            XCTAssertTrue(sheet.contains(value), value)
        }
        XCTAssertFalse(sheet.contains("coordinator.cancelReview()")); XCTAssertFalse(sheet.contains("Task {"))
    }
}
