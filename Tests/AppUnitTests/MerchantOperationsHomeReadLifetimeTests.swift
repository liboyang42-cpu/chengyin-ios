import XCTest
@testable import Questify

@MainActor final class MerchantOperationsHomeReadLifetimeTests: XCTestCase {
    func testNoReadBeforeAppearanceOrWithNilPermit() {
        let owner = MerchantOperationsHomeReadLifetime()
        XCTAssertFalse(owner.allows(nil)); XCTAssertFalse(owner.allows(UUID()))
        owner.appear(active: true); XCTAssertFalse(owner.allows(nil))
        XCTAssertTrue(owner.allows(owner.permit))
    }
    func testDepartureAndReturnDoNotReviveOldQueuedRetry() throws {
        let owner = MerchantOperationsHomeReadLifetime(); owner.appear(active: true)
        let first = try XCTUnwrap(owner.permit)
        owner.disappear(); XCTAssertFalse(owner.allows(first))
        owner.appear(active: true)
        XCTAssertFalse(owner.allows(first)); XCTAssertTrue(owner.allows(owner.permit))
    }
    func testBackgroundAndForegroundRetireOriginalRead() throws {
        let owner = MerchantOperationsHomeReadLifetime(); owner.appear(active: true)
        let first = try XCTUnwrap(owner.permit)
        owner.sceneChanged(active: false); XCTAssertFalse(owner.allows(first))
        owner.sceneChanged(active: true)
        XCTAssertFalse(owner.allows(first)); XCTAssertTrue(owner.allows(owner.permit))
    }
    func testForegroundDoesNotStartHiddenPage() {
        let owner = MerchantOperationsHomeReadLifetime(); owner.appear(active: true)
        owner.disappear(); owner.sceneChanged(active: false); owner.sceneChanged(active: true)
        owner.sourceChanged()
        XCTAssertNil(owner.permit); XCTAssertFalse(owner.allows(owner.permit))
    }
    func testSourceReplacementRetiresTicketEvenForSameScopeReader() throws {
        let owner = MerchantOperationsHomeReadLifetime(); owner.appear(active: true)
        let first = try XCTUnwrap(owner.permit)
        owner.sourceChanged(); XCTAssertFalse(owner.allows(first)); XCTAssertTrue(owner.allows(owner.permit))
    }
    func testRepeatedAppearanceDoesNotDuplicateActiveRead() throws {
        let owner = MerchantOperationsHomeReadLifetime(); owner.appear(active: true)
        let first = try XCTUnwrap(owner.permit)
        owner.appear(active: true); XCTAssertEqual(owner.permit, first)
    }
    func testActualHomeWiresPermitBeforeAndAfterAwaitWithoutEditingDocumentOwner() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("App/MerchantOperationsViews.swift"), encoding: .utf8)
        let home = try XCTUnwrap(source.components(separatedBy: "final class MerchantOperationsViewModel").first)
        XCTAssertTrue(home.contains(".task(id: readPermit)"))
        XCTAssertTrue(home.contains(".onDisappear { readLifetime.disappear() }"))
        XCTAssertEqual(home.components(separatedBy: "readLifetime.allows(permit)").count - 1, 3)
    }
}
