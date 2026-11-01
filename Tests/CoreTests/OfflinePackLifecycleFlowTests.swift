import XCTest
@testable import QuestifyCore

final class OfflinePackLifecycleFlowTests: XCTestCase {
    private let payload = Data((0..<2048).map { UInt8($0 & 0xff) })
    private var checksum: String { OfflinePackOperation.sha256Hex(payload) }
    private let later = Date(timeIntervalSince1970: 2_000_000_000)

    private func manifest(version: String = "pack-v1", operationID: String) throws -> OfflinePackManifest {
        try XCTUnwrap(OfflinePackManifest(
            packID: "pack-a", operationID: operationID, version: version, byteSize: payload.count,
            checksum: checksum, publicPlaceIDs: [11, 22], expiresAt: later))
    }

    func testOrderedLifecycleKeepsMachineOutcomesAndDoesNotInstall() throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let manifest = try manifest(operationID: "op-life")
        var prior = OfflinePackOperation()
        try prior.startDownload(try manifest(operationID: "op-prior"), at: now)
        try prior.finishDownload(payload: payload)
        try prior.applyUpdate(try manifest(version: "pack-v2", operationID: "op-prior"), keepOld: true, at: now)

        let report = try OfflinePackLifecycleFlow.walk(manifest: manifest, at: now, keepOldUpdate: prior)

        XCTAssertEqual(report.steps, OfflinePackLifecycleFlow.stepOrder)
        XCTAssertEqual(report.afterResume.phase, .downloading)
        XCTAssertEqual(report.afterResume.operationID, "op-life")
        XCTAssertEqual(report.afterResume.manifestVersion, "pack-v1")
        XCTAssertNil(report.afterResume.retainedPriorVersion)

        XCTAssertEqual(report.corruptFailure.phase, .corrupt)
        XCTAssertEqual(report.corruptFailure.failure, .some(.corrupt))
        XCTAssertEqual(report.corruptFailure.operationID, "op-life")
        XCTAssertEqual(report.fullDiskFailure.phase, .fullDisk)
        XCTAssertEqual(report.fullDiskFailure.failure, .some(.fullDisk))
        XCTAssertEqual(report.expireKept.phase, .downloading)
        XCTAssertEqual(report.expireKept.failure, .some(.invalidManifest))
        XCTAssertEqual(report.expireKept.manifestVersion, "pack-v1")
        XCTAssertEqual(report.expireFailure.phase, .expired)
        XCTAssertEqual(report.expireFailure.failure, .some(.expired))

        XCTAssertEqual(report.corruptKeptPrior.phase, .ready)
        XCTAssertNil(report.corruptKeptPrior.failure)
        XCTAssertEqual(report.corruptKeptPrior.manifestVersion, "pack-v1")
        XCTAssertEqual(report.corruptKeptPrior.retainedPriorVersion, "pack-v1")
        XCTAssertEqual(report.corruptKeptPrior.operationID, "op-prior")
        XCTAssertEqual(report.fullDiskKeptPrior.phase, .ready)
        XCTAssertNil(report.fullDiskKeptPrior.failure)
        XCTAssertEqual(report.fullDiskKeptPrior.manifestVersion, "pack-v1")
        XCTAssertEqual(report.expireKeptPrior.phase, .updating)
        XCTAssertEqual(report.expireKeptPrior.failure, .some(.invalidManifest))
        XCTAssertEqual(report.expireKeptPrior.manifestVersion, "pack-v2")
        XCTAssertEqual(report.expireKeptPrior.retainedPriorVersion, "pack-v1")
        XCTAssertEqual(report.expirePriorWhenDue.phase, .expired)
        XCTAssertEqual(report.expirePriorWhenDue.failure, .some(.expired))
        XCTAssertNotEqual(report.expirePriorWhenDue.phase, .ready)

        XCTAssertEqual(report.afterDelete.phase, .deleted)
        XCTAssertEqual(report.afterDelete.operationID, "op-life")
        XCTAssertNil(report.afterDelete.failure)
        XCTAssertNil(report.afterDelete.retainedPriorVersion)
        XCTAssertEqual(report.afterExit.phase, .deleted)
        XCTAssertFalse(report.claimsInstalled)
        XCTAssertNotEqual(report.afterExit.phase, .ready)

        XCTAssertEqual(report.blockedAction, OfflinePackSourceInventory.payloadConsumer)
        XCTAssertEqual(report.blockedPayload, .waitingSource(capability: OfflinePackSourceInventory.payloadConsumer))
        XCTAssertEqual(report.blockedPayloadPhase, .downloading)
        XCTAssertEqual(
            report.payloadConsumerAccept,
            .waitingSource(capability: OfflinePackPayloadConsumer.missingArtifact))
        XCTAssertEqual(report.payloadConsumerAcceptPhase, .downloading)
        XCTAssertEqual(
            report.qmodFinalOps,
            .waitingSource(capability: OfflinePackSourceInventory.qmodFinalOpsContract))
        XCTAssertEqual(
            report.t41ScoringWriter,
            .waitingSource(capability: OfflinePackSourceInventory.t41ScoringWriter))
        XCTAssertEqual(
            report.vol12ResumeWriter,
            .waitingSource(capability: OfflinePackSourceInventory.vol12ResumeWriter))
        XCTAssertTrue(report.writersLeftWaitingSource)
        XCTAssertFalse(OfflinePackSourceInventory.qmodFinalOpsContractPresent)
        XCTAssertFalse(OfflinePackSourceInventory.vol12ResumeWriterPresent)
        XCTAssertFalse(OfflinePackSourceInventory.t41ScoringWriterPresent)
        XCTAssertFalse(OfflinePackSourceInventory.t41FullLoopProven)

        XCTAssertEqual(prior.phase, .updating)
        XCTAssertEqual(prior.manifest?.version, "pack-v2")
        XCTAssertEqual(prior.retainedPrior?.version, "pack-v1")
    }
}
