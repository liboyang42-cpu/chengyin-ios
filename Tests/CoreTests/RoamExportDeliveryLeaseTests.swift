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
        model.renewDelivery()
        XCTAssertNil(model.deliveryLease, "Cold start does not restore a deliverable lease")
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
        // Returning to the foreground rechecks the file and does not make it deliverable again.
        model.renewDelivery()
        XCTAssertTrue(model.deliveryLease?.isRevoked == true)
        XCTAssertNil(model.fileForDelivery(foreground: true), "A revoked file stays revoked across foreground return")
        model.restart()
        XCTAssertNil(model.deliveryLease)
        XCTAssertNil(model.file)
    }

    func testHandoffUsesLiveContextNotTheLeaseIdentity() {
        let lease = RoamExportDeliveryLease(file: file(), identity: identity)!
        let context = RoamExportDeliveryContext()
        XCTAssertNil(RoamExportHandoff.contents(file: file(), lease: lease, context: context), "An unbound context writes nothing")
        var moment = now
        var who: RoamExperienceIdentity? = identity
        var front = false
        context.bind(clock: { moment }, identity: { who }, foreground: { front })
        XCTAssertNil(RoamExportHandoff.contents(file: file(), lease: lease, context: context), "A backgrounded page writes nothing")
        who = RoamExperienceIdentity(scope: scope, epoch: 2)
        front = true
        XCTAssertNil(RoamExportHandoff.contents(file: file(), lease: lease, context: context), "The lease identity is not the current identity")
        who = identity
        XCTAssertEqual(RoamExportHandoff.contents(file: file(), lease: lease, context: context), Data(file().content.utf8))
        moment = Date(timeIntervalSince1970: 1_792_468_800)
        XCTAssertNil(RoamExportHandoff.contents(file: file(), lease: lease, context: context), "Expiry is the clock at the write, not the last refresh")
        moment = now
        front = false
        XCTAssertNil(RoamExportHandoff.contents(file: file(), lease: lease, context: context), "Foreground is read again at the write")
        front = true
        lease.revoke()
        XCTAssertNil(RoamExportHandoff.contents(file: file(), lease: lease, context: context), "Revocation is seen at the actual write")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("c6-handoff-\(UUID().uuidString).jsonl")
        try? Data("temp".utf8).write(to: url)
        context.rememberTemporary(url)
        context.cleanupTemporary()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        context.cleanupTemporary()
    }

    func testCancelIsNotSaveAndOlderCallbackKeepsTheNewerLease() throws {
        XCTAssertFalse(RoamExportHandoff.recordsSave(completed: false, errorIsSet: false))
        XCTAssertFalse(RoamExportHandoff.recordsSave(completed: false, errorIsSet: true))
        XCTAssertFalse(RoamExportHandoff.recordsSave(completed: true, errorIsSet: true), "An error is not a successful save")
        XCTAssertTrue(RoamExportHandoff.recordsSave(completed: true, errorIsSet: false))

        let older = try XCTUnwrap(RoamExportDeliveryLease(file: file(), identity: identity))
        let newer = try XCTUnwrap(RoamExportDeliveryLease(file: file(), identity: identity))
        XCTAssertFalse(RoamExportHandoff.callbackMatches(older, current: newer))
        XCTAssertTrue(RoamExportHandoff.callbackMatches(newer, current: newer))
        if RoamExportHandoff.callbackMatches(older, current: newer), !RoamExportHandoff.recordsSave(completed: false, errorIsSet: true) {
            newer.revoke()
        }
        XCTAssertFalse(newer.isRevoked, "An older share callback must not revoke the newer lease")

        let context = RoamExportDeliveryContext()
        let oldURL = FileManager.default.temporaryDirectory.appendingPathComponent("roam-export-\(UUID().uuidString)/a.jsonl")
        let newURL = FileManager.default.temporaryDirectory.appendingPathComponent("roam-export-\(UUID().uuidString)/b.jsonl")
        defer {
            context.cleanupTemporary()
            try? FileManager.default.removeItem(at: oldURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: newURL.deletingLastPathComponent())
        }
        try FileManager.default.createDirectory(at: oldURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("a".utf8).write(to: oldURL)
        try Data("b".utf8).write(to: newURL)
        let oldToken = UUID(), newToken = UUID()
        context.rememberTemporary(oldURL, token: oldToken)
        context.rememberTemporary(newURL, token: newToken)
        context.releaseTemporary(token: oldToken)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path), "Releasing the older hand-off leaves the newer file")
        context.releaseTemporary(token: oldToken)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
        context.cleanupTemporary()
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path))
    }
}
