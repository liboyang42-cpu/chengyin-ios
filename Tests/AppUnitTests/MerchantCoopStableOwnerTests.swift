import XCTest
import SwiftUI
@testable import Questify

@MainActor final class MerchantCoopStableOwnerTests: XCTestCase {
    private func setup() async -> (MerchantOperationsViewModel, MerchantOperationsFixtureReader) {
        let reader = MerchantOperationsFixtureReader()
        let model = MerchantOperationsViewModel(reader: reader, destination: .cooperation)
        await model.load(); return (model, reader)
    }
    func testRecreatedRowsBorrowSameDirtyRoute() async throws {
        let (model, reader) = await setup()
        var route: MerchantCoopFieldSession? = .init(document: model, field: .demand)
        let binding = Binding(get: { route }, set: { route = $0 })
        let first = MerchantCoopFieldEntry(document: model, route: binding, fieldID: "demand")
        let session = try XCTUnwrap(route); XCTAssertTrue(session.update("Retained draft"))
        let next = MerchantCoopFieldEntry(document: model, route: binding, fieldID: "demand")
        XCTAssertTrue(first.route === next.route); XCTAssertTrue(next.route === session)
        XCTAssertTrue(session.isCurrent); XCTAssertEqual(session.buffer.value, "Retained draft")
        XCTAssertEqual(reader.saveCount, 0)
    }
    func testSharedRouteKeepsExplicitDirtyCancelDecision() async throws {
        let (model, reader) = await setup()
        let session = try XCTUnwrap(MerchantCoopFieldSession(document: model, field: .demand))
        XCTAssertTrue(session.update("Retained draft")); XCTAssertFalse(session.requestClose())
        XCTAssertTrue(session.asksDiscard); XCTAssertFalse(session.apply())
        session.keepEditing(); XCTAssertTrue(session.isCurrent); XCTAssertEqual(session.buffer.value, "Retained draft")
        XCTAssertFalse(session.requestClose()); XCTAssertTrue(session.discard())
        XCTAssertFalse(session.isCurrent); XCTAssertFalse(session.apply()); XCTAssertEqual(reader.saveCount, 0)
    }
    func testSignOutStillRevokesRetainedRoute() async throws {
        let (model, reader) = await setup()
        let session = try XCTUnwrap(MerchantCoopFieldSession(document: model, field: .demand))
        session.update("Cannot commit"); reader.signOut()
        XCTAssertFalse(session.isCurrent); XCTAssertFalse(session.apply()); XCTAssertEqual(reader.saveCount, 0)
    }
}
