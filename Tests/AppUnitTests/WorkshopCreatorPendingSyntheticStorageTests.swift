#if DEBUG
import XCTest
@testable import Questify

/// Synthetic composition coverage only. These cases do not establish system Keychain acceptance.
@MainActor final class WorkshopCreatorPendingSyntheticStorageTests: XCTestCase {
    typealias Harness = WorkshopCreatorPendingFixtureHarness

    private struct AuthorRecoveryRecord: Codable {
        let schema: String
        var ownerKey: String
        var command: WorkshopCreatorPendingCommand
    }

    private func load(_ h: Harness, _ appearance: WorkshopCreatorPendingAppearance) async throws -> WorkshopCreatorPendingController {
        let controller = try XCTUnwrap(h.session.makeWorkshopCreatorPendingController(sourceTemplateId: 901))
        await (try XCTUnwrap(controller.appear(appearance)))()
        return controller
    }

    private func prepared(_ h: Harness, _ appearance: WorkshopCreatorPendingAppearance) async throws -> WorkshopCreatorPendingController {
        await h.login(); try h.approve()
        return try await load(h, appearance)
    }

    private func review(_ h: Harness, _ controller: WorkshopCreatorPendingController,
                        _ appearance: WorkshopCreatorPendingAppearance,
                        _ reviewAppearance: WorkshopCreatorConsentAppearance) async throws -> WorkshopCreatorConsentController {
        h.fill(controller)
        await (try XCTUnwrap(controller.offerAuthor(appearance)))()
        await (try XCTUnwrap(controller.offerReview(try XCTUnwrap(controller.items.first), appearance)))()
        let consent = try XCTUnwrap(controller.declaration)
        await (try XCTUnwrap(consent.appear(reviewAppearance)))()
        consent.select(try XCTUnwrap(consent.targets.first), appearance: reviewAppearance)
        return consent
    }

    private func storedKey(_ h: Harness, prefix: String) throws -> String {
        try XCTUnwrap(h.recoveryStorage.values.keys.first { $0.hasPrefix(prefix) })
    }

    func testDefaultFactoryHasNoSyntheticOverride() {
        // This observes the composition default without reading or writing the real vault.
        XCTAssertNil(AppScopedStorageFactory().syntheticWorkshopCreatorPendingRecoveryStorage)
    }

    func testEmptySyntheticStorageLoadsEditableSourceWithoutWrites() async throws {
        let h = Harness(); defer { h.clean() }
        let c = try await prepared(h, .init())
        XCTAssertEqual(c.phase, .editing); XCTAssertNil(c.issue); XCTAssertNotNil(c.preview)
        XCTAssertTrue(c.items.isEmpty); XCTAssertNil(c.pending); XCTAssertNil(c.declarationReceipt)
        XCTAssertTrue(c.canSubmit); XCTAssertTrue(h.recoveryStorage.values.isEmpty)
        XCTAssertTrue(h.wire.authorBodies.isEmpty); XCTAssertTrue(h.wire.declarationBodies.isEmpty)
    }

    func testAuthorReviewBackAndReopenPreserveOneHarnessStorage() async throws {
        let h = Harness(); defer { h.clean() }
        let a = WorkshopCreatorPendingAppearance(), r = WorkshopCreatorConsentAppearance()
        let c = try await prepared(h, a), consent = try await review(h, c, a, r)
        XCTAssertEqual(c.phase, .reviewing); XCTAssertEqual(consent.phase, .reviewing)
        XCTAssertTrue(consent.acknowledgments.isEmpty); XCTAssertFalse(consent.canConfirm)
        let retained = h.recoveryStorage.values
        XCTAssertEqual(retained.count, 1); XCTAssertEqual(h.wire.authorBodies.count, 1)
        await (try XCTUnwrap(c.offerBackToProposals(a)))()
        XCTAssertEqual(consent.phase, .invalidated); XCTAssertEqual(c.phase, .editing)
        XCTAssertEqual(h.recoveryStorage.values, retained); XCTAssertNotNil(c.preview)
        c.close(a)
        XCTAssertEqual(h.recoveryStorage.values, retained); XCTAssertNil(c.appear(a))
        let fresh = WorkshopCreatorPendingAppearance()
        let reopened = try await load(h, fresh)
        XCTAssertEqual(reopened.phase, .editing); XCTAssertNotNil(reopened.pending)
        XCTAssertEqual(h.recoveryStorage.values, retained)
        XCTAssertEqual(h.wire.authorBodies.count, 1); XCTAssertTrue(h.wire.declarationBodies.isEmpty)
    }

    func testUnknownAuthorReconstructionRetriesIdenticalBytesWithoutAutomaticDispatch() async throws {
        let h = Harness(); defer { h.clean() }
        let a = WorkshopCreatorPendingAppearance(), c = try await prepared(h, a)
        h.fill(c); h.wire.loseAuthorResponse = true
        await (try XCTUnwrap(c.offerAuthor(a)))()
        let original = try XCTUnwrap(h.wire.authorBodies.first), retained = h.recoveryStorage.values
        XCTAssertNil(c.receipt); XCTAssertNotNil(c.pending)
        c.close(a)
        try h.approve() // Retire the controller; recovery must outlive its presentation and binding.
        let fresh = WorkshopCreatorPendingAppearance(), replacement = try await load(h, fresh)
        XCTAssertFalse(replacement === c); XCTAssertEqual(c.phase, .invalidated)
        XCTAssertEqual(h.recoveryStorage.values, retained); XCTAssertEqual(h.wire.authorBodies.count, 1)
        XCTAssertEqual(try XCTUnwrap(replacement.pending).data(), original)
        h.wire.loseAuthorResponse = false
        await (try XCTUnwrap(replacement.offerRetry(fresh)))()
        XCTAssertEqual(h.wire.authorBodies, [original, original]); XCTAssertNotNil(replacement.receipt)
        XCTAssertEqual(h.recoveryStorage.values, retained); XCTAssertTrue(h.wire.declarationBodies.isEmpty)
        XCTAssertFalse(h.wire.requests.contains { $0.url?.path == "/native/api/workshop/creator/pending-packages/status" })
    }

    func testFailedAuthorRetentionSuppressesDispatch() async throws {
        let h = Harness(); defer { h.clean() }
        let a = WorkshopCreatorPendingAppearance(), c = try await prepared(h, a)
        h.fill(c); h.recoveryStorage.failWrites = true
        let requests = h.wire.requests.count
        XCTAssertNil(c.offerAuthor(a)); XCTAssertEqual(c.issue, .storage); XCTAssertNil(c.pending)
        XCTAssertTrue(h.recoveryStorage.values.isEmpty); XCTAssertEqual(h.wire.requests.count, requests)
        XCTAssertTrue(h.wire.authorBodies.isEmpty); XCTAssertTrue(h.wire.declarationBodies.isEmpty)
    }

    func testFailedNestedDeclarationRetentionSuppressesDispatch() async throws {
        let h = Harness(); defer { h.clean() }
        let a = WorkshopCreatorPendingAppearance(), r = WorkshopCreatorConsentAppearance()
        let c = try await prepared(h, a), consent = try await review(h, c, a, r)
        for index in 0..<3 { consent.acknowledge(index, value: true, appearance: r) }
        XCTAssertTrue(consent.canConfirm)
        let retained = h.recoveryStorage.values, requests = h.wire.requests.count
        h.recoveryStorage.failWrites = true
        XCTAssertNil(consent.offerConfirm(r)); XCTAssertEqual(consent.issue, .storage)
        XCTAssertNil(consent.pending); XCTAssertEqual(h.recoveryStorage.values, retained)
        XCTAssertEqual(h.wire.requests.count, requests); XCTAssertEqual(h.wire.authorBodies.count, 1)
        XCTAssertTrue(h.wire.declarationBodies.isEmpty)
    }

    func testNestedDeclarationHistoryUsesSameStorageAfterReconstruction() async throws {
        let h = Harness(); defer { h.clean() }
        let a = WorkshopCreatorPendingAppearance(), r = WorkshopCreatorConsentAppearance()
        let c = try await prepared(h, a), consent = try await review(h, c, a, r)
        for index in 0..<3 { consent.acknowledge(index, value: true, appearance: r) }
        await (try XCTUnwrap(consent.offerConfirm(r)))()
        XCTAssertEqual(consent.phase, .recorded)
        let retained = h.recoveryStorage.values, requestID = try XCTUnwrap(consent.pending).requestId
        XCTAssertEqual(retained.count, 2)
        c.close(a); try h.approve(authoring: false, listing: false, detailing: false, declaring: false)
        let requests = h.wire.requests.count, replacement = try await load(h, .init())
        XCTAssertEqual(replacement.declarationRequestId, requestID); XCTAssertNotNil(replacement.declarationReceipt)
        XCTAssertNil(replacement.preview); XCTAssertNil(replacement.declaration); XCTAssertFalse(replacement.canSubmit)
        XCTAssertEqual(h.wire.requests.dropFirst(requests).compactMap { $0.url?.lastPathComponent }, ["status"])
        XCTAssertEqual(h.recoveryStorage.values, retained)
        XCTAssertEqual(h.wire.authorBodies.count, 1); XCTAssertEqual(h.wire.declarationBodies.count, 1)
    }

    func testMalformedAndNoncanonicalAuthorBytesFailClosedWithoutDispatchOrRepair() async throws {
        for malformed in [true, false] {
            let h = Harness(); defer { h.clean() }
            let a = WorkshopCreatorPendingAppearance(), c = try await prepared(h, a)
            h.fill(c); _ = try XCTUnwrap(c.offerAuthor(a)) // Retain via the real store, never dispatch.
            let key = try storedKey(h, prefix: "workshop-creator-author.pending.v1.")
            let original = try XCTUnwrap(h.recoveryStorage.values[key])
            h.recoveryStorage.values[key] = malformed ? Data("{malformed".utf8) : original + Data("\n".utf8)
            let retained = h.recoveryStorage.values, requests = h.wire.requests.count
            c.close(a); let reopened = try await load(h, .init())
            XCTAssertEqual(reopened.phase, .failed); XCTAssertEqual(reopened.issue, .storage)
            XCTAssertNil(reopened.preview); XCTAssertNil(reopened.pending)
            XCTAssertEqual(h.recoveryStorage.values, retained); XCTAssertEqual(h.wire.requests.count, requests)
            XCTAssertTrue(h.wire.authorBodies.isEmpty); XCTAssertTrue(h.wire.declarationBodies.isEmpty)
        }
    }

    func testForeignOwnerAndSourceAuthorBytesFailClosedWithoutDispatchOrRepair() async throws {
        for field in ["ownerKey", "sourceTemplateId"] {
            let h = Harness(); defer { h.clean() }
            let a = WorkshopCreatorPendingAppearance(), c = try await prepared(h, a)
            h.fill(c); _ = try XCTUnwrap(c.offerAuthor(a))
            let key = try storedKey(h, prefix: "workshop-creator-author.pending.v1.")
            var record = try WorkshopCreatorPendingWire.decode(AuthorRecoveryRecord.self, data: XCTUnwrap(h.recoveryStorage.values[key]))
            if field == "ownerKey" { record.ownerKey = "foreign-owner" }
            else {
                let foreignPreview = try WorkshopCreatorWire.decode(WorkshopCreatorPreview.self,
                    data: JSONSerialization.data(withJSONObject: WorkshopCreatorPendingFixtureData.preview(sourceTemplateId: 902)))
                record.command = try c.form.command(preview: foreignPreview, now: Date())
            }
            // Keep bytes canonical so the mismatch, not JSON whitespace, must fail closed.
            h.recoveryStorage.values[key] = try WorkshopCreatorWire.encode(record)
            let retained = h.recoveryStorage.values, requests = h.wire.requests.count
            c.close(a); let reopened = try await load(h, .init())
            XCTAssertEqual(reopened.phase, .failed); XCTAssertEqual(reopened.issue, .storage)
            XCTAssertEqual(h.recoveryStorage.values, retained); XCTAssertEqual(h.wire.requests.count, requests)
            XCTAssertTrue(h.wire.authorBodies.isEmpty); XCTAssertTrue(h.wire.declarationBodies.isEmpty)
        }
    }

    func testMalformedDeclarationHistoryFailsClosedBeforeAnyReadOrWriteRequest() async throws {
        let h = Harness(); defer { h.clean() }
        let a = WorkshopCreatorPendingAppearance(), r = WorkshopCreatorConsentAppearance()
        let c = try await prepared(h, a), consent = try await review(h, c, a, r)
        for index in 0..<3 { consent.acknowledge(index, value: true, appearance: r) }
        _ = try XCTUnwrap(consent.offerConfirm(r)) // Retain but do not send the declaration.
        let key = try storedKey(h, prefix: "workshop-creator-consent.pending.v1.")
        h.recoveryStorage.values[key] = Data("{malformed".utf8)
        let retained = h.recoveryStorage.values, requests = h.wire.requests.count
        c.close(a); let reopened = try await load(h, .init())
        XCTAssertEqual(reopened.phase, .failed); XCTAssertEqual(reopened.issue, .storage)
        XCTAssertNil(reopened.declarationReceipt); XCTAssertNil(reopened.preview)
        XCTAssertEqual(h.recoveryStorage.values, retained); XCTAssertEqual(h.wire.requests.count, requests)
        XCTAssertEqual(h.wire.authorBodies.count, 1); XCTAssertTrue(h.wire.declarationBodies.isEmpty)
    }

    func testHarnessInstancesAndCleanupAreIsolated() async throws {
        let first = Harness(), second = Harness(); defer { first.clean(); second.clean() }
        XCTAssertFalse(first.recoveryStorage === second.recoveryStorage)
        let a = WorkshopCreatorPendingAppearance(), firstController = try await prepared(first, a)
        first.fill(firstController); _ = try XCTUnwrap(firstController.offerAuthor(a))
        XCTAssertFalse(first.recoveryStorage.values.isEmpty); XCTAssertTrue(second.recoveryStorage.values.isEmpty)
        let b = WorkshopCreatorPendingAppearance(), secondController = try await prepared(second, b)
        XCTAssertNil(secondController.pending); XCTAssertEqual(secondController.phase, .editing)
        second.fill(secondController); _ = try XCTUnwrap(secondController.offerAuthor(b))
        let secondValues = second.recoveryStorage.values
        XCTAssertFalse(secondValues.isEmpty)
        first.clean()
        XCTAssertTrue(first.recoveryStorage.values.isEmpty); XCTAssertEqual(second.recoveryStorage.values, secondValues)
        XCTAssertTrue(first.wire.authorBodies.isEmpty); XCTAssertTrue(second.wire.authorBodies.isEmpty)
    }
}
#endif
