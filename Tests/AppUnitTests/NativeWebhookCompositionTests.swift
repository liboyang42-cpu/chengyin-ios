import Foundation
import XCTest
@testable import Questify

@MainActor final class NativeWebhookCompositionTests: XCTestCase {
    func testOrdinaryCompositionHasNoManagementFactory() {
        XCTAssertNil(AppCompositionRoot().nativeWebhookRuntimeFactory)
    }
    func testRevocationClosesEditorsNavigationAndPrivateCaches() async throws {
        let (model, coordinator, provider, _, _) = try NativeWebhookAppFixtures.model(); await model.start()
        let resource = try XCTUnwrap(coordinator.resources.first)
        model.path = [.resource(resource.id), .deliveryLog]; model.edit(resource)
        XCTAssertEqual(model.sheet, .subscriptionEditor)
        provider.revoked = true; await model.foreground()
        XCTAssertNil(model.sheet); XCTAssertTrue(model.path.isEmpty); XCTAssertTrue(coordinator.resources.isEmpty)
        XCTAssertNil(coordinator.selected); XCTAssertNil(coordinator.credential); XCTAssertFalse(model.available)
    }
    func testSynchronousHostInvalidationFencesLateMutationWithoutDiscardingPending() async throws {
        let (model, coordinator, _, transport, journal) = try NativeWebhookAppFixtures.model(); await model.start()
        model.action(.rotate, resource: try XCTUnwrap(coordinator.resources.first))
        transport.onMutation = { coordinator.invalidate() }
        await model.confirm(try XCTUnwrap(coordinator.confirmation).id)
        XCTAssertNil(coordinator.credential); XCTAssertTrue(coordinator.resources.isEmpty); XCTAssertNil(model.sheet)
        XCTAssertNotNil(journal.record); XCTAssertFalse(model.canMutate)
    }
    func testBackgroundDuringReplyCannotReopenSecretSheet() async throws {
        let (model, coordinator, _, transport, _) = try NativeWebhookAppFixtures.model(); await model.start()
        model.action(.rotate, resource: try XCTUnwrap(coordinator.resources.first)); transport.onMutation = { model.background() }
        await model.confirm(try XCTUnwrap(coordinator.confirmation).id)
        XCTAssertNil(model.sheet); XCTAssertNil(coordinator.credential)
    }
}
