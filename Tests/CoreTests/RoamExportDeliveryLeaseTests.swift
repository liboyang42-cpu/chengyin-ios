import XCTest
@testable import QuestifyCore

@MainActor final class RoamExportDeliveryLeaseTests: XCTestCase {
    private let scope = try! RoamHistoryScope(market: "cn", deployment: URL(string: "https://example.com/synthetic-roam")!, accountID: 900)
    private var identity: RoamExperienceIdentity { RoamExperienceIdentity(scope: scope, epoch: 1) }
    private let now = Date(timeIntervalSince1970: 1_792_382_400)
    private func file(rows: Int = 3, expiresAtMs: Int64 = 1_792_468_800_000) -> RoamExportFile {
        RoamExportFile(fileName: "chengyin-exploration-20260920-20261020.jsonl", content: "{}\n", expiresAtMs: expiresAtMs, rows: rows)
    }

    func testLeaseRequiresCompleteNonEmptyFile() {
        XCTAssertNil(RoamExportDeliveryLease(file: file(rows: 0), identity: identity))
        XCTAssertNotNil(RoamExportDeliveryLease(file: file(), identity: identity))
    }

    func testDeliveryIsRevalidatedAtHandOffMoment() {
        let lease = RoamExportDeliveryLease(file: file(), identity: identity)!
        XCTAssertTrue(lease.canDeliver(now: now, currentIdentity: identity, foreground: true))
        XCTAssertFalse(lease.canDeliver(now: now, currentIdentity: identity, foreground: false), "Background delivers nothing")
        XCTAssertFalse(lease.canDeliver(now: now, currentIdentity: RoamExperienceIdentity(scope: scope, epoch: 2), foreground: true),
                       "A changed identity delivers nothing")
        XCTAssertFalse(lease.canDeliver(now: Date(timeIntervalSince1970: 1_792_468_800), currentIdentity: identity, foreground: true),
                       "At the expiry instant the file is no longer deliverable")
        XCTAssertEqual(lease.validatedFile(file(), now: now, currentIdentity: identity, foreground: true), file())
        XCTAssertNil(lease.validatedFile(file(rows: 2), now: now, currentIdentity: identity, foreground: true),
                     "A file that is not the leased one delivers nothing")
        lease.revoke()
        XCTAssertTrue(lease.isRevoked)
        XCTAssertFalse(lease.canDeliver(now: now, currentIdentity: identity, foreground: true), "Revocation is one-way for this lease")
        XCTAssertNil(lease.validatedFile(file(), now: now, currentIdentity: identity, foreground: true))
    }

    func testCoordinatorIssuesLeaseOnlyAfterFinalChunkAndRevocationHidesFile() async {
        let model = RoamExportCoordinator(tools: RoamPrivateToolsFixture(), pageSize: RoamPrivateToolsFixture.fixturePageSize)
        let range = model.presets[0]
        await model.prepare(startDate: range.startDate, endDateExclusive: range.endDateExclusive)
        await model.readNext()
        XCTAssertNil(model.deliveryLease, "An unread remainder means no delivery lease and no file")
        XCTAssertNil(model.fileForDelivery(foreground: true))
        await model.readNext()
        XCTAssertEqual(model.phase, .complete)
        XCTAssertNotNil(model.deliveryLease)
        XCTAssertEqual(model.fileForDelivery(foreground: true)?.rows, 3)
        XCTAssertNil(model.fileForDelivery(foreground: false))
        model.revokeDelivery()
        XCTAssertNil(model.shareableFile, "A revoked lease offers nothing to save or share")
        XCTAssertNil(model.fileForDelivery(foreground: true))
        // Return to the page is a fresh validation, not a revival of the revoked lease.
        model.renewDelivery()
        XCTAssertEqual(model.fileForDelivery(foreground: true)?.rows, 3)
        model.restart()
        XCTAssertNil(model.deliveryLease)
        XCTAssertNil(model.file)
    }

    func testHandoffUsesLiveContextNotTheLeaseIdentity() {
        let lease = RoamExportDeliveryLease(file: file(), identity: identity)!
        let context = RoamExportDeliveryContext()
        context.update(now: now, identity: identity, foreground: false)
        XCTAssertNil(RoamExportHandoff.contents(file: file(), lease: lease, context: context), "A backgrounded page writes nothing")
        context.update(now: now, identity: RoamExperienceIdentity(scope: scope, epoch: 2), foreground: true)
        XCTAssertNil(RoamExportHandoff.contents(file: file(), lease: lease, context: context), "The lease identity is not the current identity")
        context.update(now: now, identity: identity, foreground: true)
        XCTAssertEqual(RoamExportHandoff.contents(file: file(), lease: lease, context: context), Data(file().content.utf8))
        lease.revoke()
        XCTAssertNil(RoamExportHandoff.contents(file: file(), lease: lease, context: context), "Revocation is seen at the actual write")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("c6-handoff-\(UUID().uuidString).jsonl")
        try? Data("temp".utf8).write(to: url)
        context.rememberTemporary(url)
        context.cleanupTemporary()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        context.cleanupTemporary()
    }
}
