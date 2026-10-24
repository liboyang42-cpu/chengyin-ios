import XCTest
@testable import QuestifyCore

final class OfflinePackOperationTests: XCTestCase {
    private let checksum = String(repeating: "ab", count: 32)
    private let later = Date(timeIntervalSince1970: 2_000_000_000)
    private func manifest(version: String = "pack-v1", operationID: String = "op-1") throws -> OfflinePackManifest {
        try XCTUnwrap(OfflinePackManifest(
            packID: "pack-a", operationID: operationID, version: version, byteSize: 2048,
            checksum: checksum, publicPlaceIDs: [11, 22], expiresAt: later))
    }
    func testDownloadPauseResumeSameOperationIdThenReady() throws {
        var pack = OfflinePackOperation()
        try pack.startDownload(try manifest())
        XCTAssertEqual(pack.phase, .downloading)
        XCTAssertEqual(pack.operationID, "op-1")
        try pack.pause()
        XCTAssertEqual(pack.phase, .paused)
        XCTAssertThrowsError(try pack.resume(operationID: "op-other")) { error in
            XCTAssertEqual(error as? OfflinePackFailure, .operationMismatch)
        }
        try pack.resume(operationID: "op-1")
        XCTAssertEqual(pack.phase, .downloading)
        XCTAssertEqual(pack.snapshot?.operationID, "op-1")
        try pack.finishDownload()
        XCTAssertEqual(pack.phase, .ready)
    }
    func testCorruptFullDiskExpireDeleteAndKeepOld() throws {
        var pack = OfflinePackOperation()
        try pack.startDownload(try manifest())
        XCTAssertThrowsError(try pack.recordFullDisk()) { error in
            XCTAssertEqual(error as? OfflinePackFailure, .fullDisk)
        }
        XCTAssertEqual(pack.phase, .fullDisk)
        pack = OfflinePackOperation()
        try pack.startDownload(try manifest())
        try pack.finishDownload()
        try pack.applyUpdate(try manifest(version: "pack-v2"), keepOld: true)
        XCTAssertEqual(pack.phase, .updating)
        XCTAssertEqual(pack.snapshot?.retainedPriorVersion, "pack-v1")
        try pack.recordCorrupt()
        XCTAssertEqual(pack.phase, .ready)
        XCTAssertEqual(pack.manifest?.version, "pack-v1")
        try pack.applyUpdate(try manifest(version: "pack-v2"), keepOld: false)
        try pack.finishUpdate()
        XCTAssertEqual(pack.manifest?.version, "pack-v2")
        XCTAssertNil(pack.snapshot?.retainedPriorVersion)
        try pack.expire(at: later)
        XCTAssertEqual(pack.phase, .expired)
        try pack.delete()
        XCTAssertEqual(pack.phase, .deleted)
        XCTAssertThrowsError(try pack.delete()) { error in
            XCTAssertEqual(error as? OfflinePackFailure, .alreadyDeleted)
        }
    }
    func testOtherOperationIdDoesNotRewriteOriginalDownload() throws {
        var pack = OfflinePackOperation()
        try pack.startDownload(try manifest())
        XCTAssertEqual(pack.operationID, "op-1")
        XCTAssertThrowsError(try pack.startDownload(try manifest(operationID: "op-other"))) { error in
            XCTAssertEqual(error as? OfflinePackFailure, .invalidManifest)
        }
        XCTAssertEqual(pack.operationID, "op-1")
        try pack.pause()
        XCTAssertThrowsError(try pack.resume(operationID: "")) { error in
            XCTAssertEqual(error as? OfflinePackFailure, .operationMismatch)
        }
        XCTAssertEqual(pack.operationID, "op-1")
        XCTAssertNotEqual(pack.operationID, "")
        let restarted = OfflinePackOperation()
        XCTAssertNil(restarted.operationID)
        XCTAssertEqual(restarted.phase, .idle)
    }
    func testUnusedResumeDoesNotOccupyThenUniqueStartDownloadApplies() throws {
        var pack = OfflinePackOperation()
        XCTAssertNil(pack.operationID)
        XCTAssertEqual(pack.phase, .idle)
        XCTAssertThrowsError(try pack.resume(operationID: "op-class-never")) { error in
            XCTAssertEqual(error as? OfflinePackFailure, .notPaused)
        }
        XCTAssertNil(pack.operationID, "未见 resume 不得占 operationID")
        XCTAssertEqual(pack.phase, .idle)
        try pack.startDownload(try manifest(operationID: "op-class"))
        XCTAssertEqual(pack.operationID, "op-class")
        try pack.pause()
        XCTAssertThrowsError(try pack.resume(operationID: "op-other")) { error in
            XCTAssertEqual(error as? OfflinePackFailure, .operationMismatch)
        }
        XCTAssertEqual(pack.operationID, "op-class")
        try pack.resume(operationID: "op-class")
        try pack.finishDownload()
        XCTAssertEqual(pack.operationID, "op-class")
        XCTAssertEqual(pack.phase, .ready)
        let restarted = OfflinePackOperation()
        XCTAssertNil(restarted.operationID)
        XCTAssertEqual(restarted.phase, .idle)
    }
    func testAnswersAndHiddenCoordinatesAreNotShipped() throws {
        XCTAssertThrowsError(try OfflinePackOperation.inspect(["answer": "42"])) { error in
            XCTAssertEqual(error as? OfflinePackFailure, .answersOrHiddenCoordinatesForbidden)
        }
        XCTAssertThrowsError(try OfflinePackOperation.inspect(["hiddenCoordinate": "31.2,121.5"])) { error in
            XCTAssertEqual(error as? OfflinePackFailure, .answersOrHiddenCoordinatesForbidden)
        }
        XCTAssertThrowsError(try OfflinePackOperation.decodeManifest(
            ["packID": "p", "operationID": "op-1", "version": "v1", "checksum": checksum,
             "byteSize": "10", "hiddenLat": "31.2"],
            publicPlaceIDs: [1], expiresAt: later)) { error in
            XCTAssertEqual(error as? OfflinePackFailure, .answersOrHiddenCoordinatesForbidden)
        }
        let allowed = try OfflinePackOperation.decodeManifest(
            ["packID": "pack-a", "operationID": "op-1", "version": "pack-v1",
             "checksum": checksum, "byteSize": "2048"],
            publicPlaceIDs: [11, 22], expiresAt: later)
        XCTAssertEqual(allowed.publicPlaceIDs, [11, 22])
        XCTAssertNil(allowed.version.range(of: "answer"))
    }
    func testMissingQmodAndVol12ContractsAreWaitingSource() {
        var pack = OfflinePackOperation()
        XCTAssertFalse(OfflinePackSourceInventory.qmodFinalOpsContractPresent)
        XCTAssertFalse(OfflinePackSourceInventory.vol12ResumeWriterPresent)
        XCTAssertFalse(OfflinePackSourceInventory.t41ScoringWriterPresent)
        XCTAssertFalse(OfflinePackSourceInventory.t41FullLoopProven)
        XCTAssertEqual(OfflinePackSourceInventory.originalPauseOpsOwner, "PlayExperienceCoordinator.paused")
        XCTAssertEqual(waiting { try pack.commitOriginalWriter() },
                       .waitingSource(capability: OfflinePackSourceInventory.qmodFinalOpsContract))
        XCTAssertEqual(pack.phase, .waitingSource)
        pack = OfflinePackOperation()
        XCTAssertEqual(waiting { try pack.resumeViaVol12Writer() },
                       .waitingSource(capability: OfflinePackSourceInventory.vol12ResumeWriter))
        pack = OfflinePackOperation()
        XCTAssertEqual(waiting { try pack.scoreT41() },
                       .waitingSource(capability: OfflinePackSourceInventory.t41ScoringWriter))
        pack = OfflinePackOperation()
        XCTAssertEqual(waiting { try pack.proveT41FullLoop() },
                       .waitingSource(capability: OfflinePackSourceInventory.t41FullLoop))
        pack = OfflinePackOperation()
        XCTAssertEqual(waiting { try pack.hijackOriginalPauseOps() }, .pauseOpsReserved)
    }
    private func waiting(_ body: () throws -> Never) -> OfflinePackFailure? {
        do { try body(); return nil } catch let error as OfflinePackFailure { return error } catch { return nil }
    }
}
