import XCTest
import SwiftUI
@testable import Questify

@MainActor final class MerchantFieldStableOwnerTests: XCTestCase {
    func testStoreRowRecreationKeepsSameOwnerAndDirtyBuffer() async throws {
        let reader = MerchantOperationsFixtureReader()
        let document = MerchantOperationsViewModel(reader: reader, destination: .profile)
        await document.load()
        let owner = MerchantStoreFieldPresentation(); owner.activate()
        let first = MerchantStoreFieldEntry(document: document, presentation: owner, field: .name)
        owner.open(permit: owner.generation, document: document, field: .name)
        let session = try XCTUnwrap(owner.session); XCTAssertTrue(session.update("Kept local draft"))
        let replacement = MerchantStoreFieldEntry(document: document, presentation: owner, field: .name)
        XCTAssertTrue(first.presentation === replacement.presentation)
        XCTAssertTrue(owner.session === session); XCTAssertTrue(session.isCurrent)
        XCTAssertEqual(session.buffer.value, "Kept local draft"); XCTAssertEqual(reader.saveCount, 0)
    }
    func testStoreFreshSessionBindingOpensAndOldDismissCannotCloseReopen() async throws {
        let reader = MerchantOperationsFixtureReader()
        let document = MerchantOperationsViewModel(reader: reader, destination: .profile)
        await document.load()
        let owner = MerchantStoreFieldPresentation(); owner.activate()
        let initial = owner.presentationBinding(); XCTAssertNil(initial.wrappedValue)
        owner.open(permit: owner.generation, document: document, field: .name)
        let first = try XCTUnwrap(owner.session), shown = owner.presentationBinding()
        XCTAssertTrue(shown.wrappedValue === first)
        initial.wrappedValue = nil; XCTAssertTrue(owner.session === first)
        owner.close(first.id)
        owner.open(permit: owner.generation, document: document, field: .name)
        let second = try XCTUnwrap(owner.session)
        XCTAssertNotEqual(first.id, second.id); shown.wrappedValue = nil
        XCTAssertTrue(owner.session === second); XCTAssertNil(shown.wrappedValue)
        XCTAssertTrue(owner.presentationBinding().wrappedValue === second)
    }
    func testStoreRealHostLeaveRevokesWithoutApplyingDirtyBuffer() async throws {
        let reader = MerchantOperationsFixtureReader()
        let document = MerchantOperationsViewModel(reader: reader, destination: .profile)
        await document.load(); let original = try XCTUnwrap(document.coordinator.draft)
        let owner = MerchantStoreFieldPresentation(); owner.activate()
        owner.open(permit: owner.generation, document: document, field: .name)
        let session = try XCTUnwrap(owner.session); session.update("Never applied")
        XCTAssertFalse(session.requestClose()); session.keepEditing()
        XCTAssertTrue(session.isCurrent); owner.deactivate()
        XCTAssertNil(owner.session); XCTAssertFalse(session.isCurrent); XCTAssertFalse(session.apply())
        XCTAssertEqual(session.buffer.value, "")
        XCTAssertTrue(MerchantStoreFieldDraft.sameDraft(try XCTUnwrap(document.coordinator.draft), original))
        XCTAssertEqual(reader.saveCount, 0)
    }
    func testNPCRowRecreationKeepsSameOwnerAndDirtyBuffer() async throws {
        let reader = MerchantOperationsFixtureReader()
        let document = MerchantOperationsViewModel(reader: reader, destination: .character)
        await document.load()
        let owner = MerchantNPCFieldPresentation(); owner.activate()
        let first = MerchantNPCFieldEntry(document: document, presentation: owner, field: .name)
        owner.open(permit: owner.generation, document: document, field: .name)
        let session = try XCTUnwrap(owner.session); XCTAssertTrue(session.update("Kept local draft"))
        let replacement = MerchantNPCFieldEntry(document: document, presentation: owner, field: .name)
        XCTAssertTrue(first.presentation === replacement.presentation)
        XCTAssertTrue(owner.session === session); XCTAssertTrue(session.isCurrent)
        XCTAssertEqual(session.buffer.value, "Kept local draft"); XCTAssertEqual(reader.saveCount, 0)
    }
    func testNPCFreshSessionBindingOpensAndOldDismissCannotCloseReopen() async throws {
        let reader = MerchantOperationsFixtureReader()
        let document = MerchantOperationsViewModel(reader: reader, destination: .character)
        await document.load()
        let owner = MerchantNPCFieldPresentation(); owner.activate()
        let initial = owner.presentationBinding(); XCTAssertNil(initial.wrappedValue)
        owner.open(permit: owner.generation, document: document, field: .name)
        let first = try XCTUnwrap(owner.session), shown = owner.presentationBinding()
        XCTAssertTrue(shown.wrappedValue === first)
        initial.wrappedValue = nil; XCTAssertTrue(owner.session === first)
        owner.close(first.id)
        owner.open(permit: owner.generation, document: document, field: .name)
        let second = try XCTUnwrap(owner.session)
        XCTAssertNotEqual(first.id, second.id); shown.wrappedValue = nil
        XCTAssertTrue(owner.session === second); XCTAssertNil(shown.wrappedValue)
        XCTAssertTrue(owner.presentationBinding().wrappedValue === second)
    }
    func testNPCRealHostLeaveRevokesWithoutApplyingDirtyBuffer() async throws {
        let reader = MerchantOperationsFixtureReader()
        let document = MerchantOperationsViewModel(reader: reader, destination: .character)
        await document.load(); let original = try XCTUnwrap(document.coordinator.draft)
        let owner = MerchantNPCFieldPresentation(); owner.activate()
        owner.open(permit: owner.generation, document: document, field: .name)
        let session = try XCTUnwrap(owner.session); session.update("Never applied")
        XCTAssertFalse(session.requestClose()); session.keepEditing()
        XCTAssertTrue(session.isCurrent); owner.deactivate()
        XCTAssertNil(owner.session); XCTAssertFalse(session.isCurrent); XCTAssertFalse(session.apply())
        XCTAssertEqual(session.buffer.value, "")
        XCTAssertTrue(MerchantNPCFieldDraft.sameDraft(try XCTUnwrap(document.coordinator.draft), original))
        XCTAssertEqual(reader.saveCount, 0)
    }
}
