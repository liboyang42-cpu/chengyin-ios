import Foundation

/// One ordered lifecycle on the existing `OfflinePackOperation` machine.
/// begin / pause / resume do not create payload bytes.
/// corrupt, full disk, and expire only call that machine: a verified prior stays
/// the previous good pack, and every other case keeps the failure it already defines.
/// delete / exit does not report the pack as installed.
/// The payload consumer, qmod final ops, T41 scoring writer, and volume-12 resume
/// writer stay WAITING_SOURCE.
public enum OfflinePackLifecycleFlow {
    public static let stepOrder = ["begin", "pause", "resume", "corrupt", "fullDisk", "expire", "deleteExit"]
    public static let blockedAction = OfflinePackSourceInventory.payloadConsumer

    public struct Observation: Equatable {
        public let operationID: String?
        public let phase: OfflinePackPhase
        public let failure: OfflinePackFailure?
        public let manifestVersion: String?
        public let retainedPriorVersion: String?
    }

    public struct Report: Equatable {
        public let steps: [String]
        public let afterResume: Observation
        public let corruptFailure: Observation
        public let fullDiskFailure: Observation
        public let expireKept: Observation
        public let expireFailure: Observation
        public let corruptKeptPrior: Observation
        public let fullDiskKeptPrior: Observation
        public let expireKeptPrior: Observation
        public let expirePriorWhenDue: Observation
        public let afterDelete: Observation
        public let afterExit: Observation
        public let claimsInstalled: Bool
        public let blockedAction: String
        public let blockedPayload: OfflinePackFailure
        public let blockedPayloadPhase: OfflinePackPhase
        public let payloadConsumerAccept: OfflinePackFailure
        public let payloadConsumerAcceptPhase: OfflinePackPhase
        public let qmodFinalOps: OfflinePackFailure
        public let t41ScoringWriter: OfflinePackFailure
        public let vol12ResumeWriter: OfflinePackFailure
        public let writersLeftWaitingSource: Bool
    }

    /// `keepOldUpdate` must already be the machine's keep-old update. This entry does not
    /// supply payload bytes, a published locator, or a stand-in for the missing writers.
    public static func walk(
        manifest: OfflinePackManifest,
        at now: Date,
        keepOldUpdate: OfflinePackOperation
    ) throws -> Report {
        var operation = OfflinePackOperation()
        try operation.startDownload(manifest, at: now)
        try operation.pause()
        try operation.resume(operationID: manifest.operationID)
        let resumed = operation
        let afterResume = snapshot(resumed)

        let beforeDue = manifest.expiresAt.addingTimeInterval(-1)
        let corruptFailure = observe(resumed) { try $0.recordCorrupt() }
        let fullDiskFailure = observe(resumed) { try $0.recordFullDisk() }
        let expireKept = observe(resumed) { try $0.expire(at: beforeDue) }
        let expireFailure = observe(resumed) { try $0.expire(at: manifest.expiresAt) }

        let priorDue = keepOldUpdate.manifest?.expiresAt ?? manifest.expiresAt
        let priorBefore = priorDue.addingTimeInterval(-1)
        let corruptKeptPrior = observe(keepOldUpdate) { try $0.recordCorrupt() }
        let fullDiskKeptPrior = observe(keepOldUpdate) { try $0.recordFullDisk() }
        let expireKeptPrior = observe(keepOldUpdate) { try $0.expire(at: priorBefore) }
        let expirePriorWhenDue = observe(keepOldUpdate) { try $0.expire(at: priorDue) }

        try operation.delete()
        let afterDelete = snapshot(operation)
        try exitWithoutInstalling(&operation)
        let afterExit = snapshot(operation)
        let claimsInstalled = operation.phase == .ready

        var blockedCopy = resumed
        var blockedPayload: OfflinePackFailure?
        var blockedPayloadPhase = blockedCopy.phase
        do {
            try blockedCopy.finishDownload()
            blockedPayloadPhase = blockedCopy.phase
        } catch let error as OfflinePackFailure {
            blockedPayload = error
            blockedPayloadPhase = blockedCopy.phase
        } catch {
            blockedPayloadPhase = blockedCopy.phase
        }

        var consumerCopy = resumed
        var payloadConsumerAccept: OfflinePackFailure?
        var payloadConsumerAcceptPhase = consumerCopy.phase
        do {
            try OfflinePackPayloadConsumer.accept(&consumerCopy, from: NoPublishedArtifact())
            payloadConsumerAcceptPhase = consumerCopy.phase
        } catch let error as OfflinePackFailure {
            payloadConsumerAccept = error
            payloadConsumerAcceptPhase = consumerCopy.phase
        } catch {
            payloadConsumerAcceptPhase = consumerCopy.phase
        }

        guard let blockedPayload,
              blockedPayload == .waitingSource(capability: OfflinePackSourceInventory.payloadConsumer),
              blockedPayloadPhase != .ready,
              let payloadConsumerAccept,
              payloadConsumerAccept.isWaitingSource,
              payloadConsumerAcceptPhase != .ready,
              let qmodFinalOps = refused(resumed, { try $0.commitOriginalWriter() }),
              qmodFinalOps == .waitingSource(capability: OfflinePackSourceInventory.qmodFinalOpsContract),
              let t41ScoringWriter = refused(resumed, { try $0.scoreT41() }),
              t41ScoringWriter == .waitingSource(capability: OfflinePackSourceInventory.t41ScoringWriter),
              let vol12ResumeWriter = refused(resumed, { try $0.resumeViaVol12Writer() }),
              vol12ResumeWriter == .waitingSource(capability: OfflinePackSourceInventory.vol12ResumeWriter)
        else { throw OfflinePackFailure.invalidManifest }

        let writersLeftWaitingSource =
            !OfflinePackSourceInventory.qmodFinalOpsContractPresent &&
            !OfflinePackSourceInventory.vol12ResumeWriterPresent &&
            !OfflinePackSourceInventory.t41ScoringWriterPresent &&
            !OfflinePackSourceInventory.t41FullLoopProven

        return Report(
            steps: stepOrder,
            afterResume: afterResume,
            corruptFailure: corruptFailure,
            fullDiskFailure: fullDiskFailure,
            expireKept: expireKept,
            expireFailure: expireFailure,
            corruptKeptPrior: corruptKeptPrior,
            fullDiskKeptPrior: fullDiskKeptPrior,
            expireKeptPrior: expireKeptPrior,
            expirePriorWhenDue: expirePriorWhenDue,
            afterDelete: afterDelete,
            afterExit: afterExit,
            claimsInstalled: claimsInstalled,
            blockedAction: blockedAction,
            blockedPayload: blockedPayload,
            blockedPayloadPhase: blockedPayloadPhase,
            payloadConsumerAccept: payloadConsumerAccept,
            payloadConsumerAcceptPhase: payloadConsumerAcceptPhase,
            qmodFinalOps: qmodFinalOps,
            t41ScoringWriter: t41ScoringWriter,
            vol12ResumeWriter: vol12ResumeWriter,
            writersLeftWaitingSource: writersLeftWaitingSource)
    }

    private static func exitWithoutInstalling(_ operation: inout OfflinePackOperation) throws {
        guard operation.phase != .deleted else { return }
        guard operation.phase != .idle else { throw OfflinePackFailure.invalidManifest }
        try operation.delete()
    }

    private static func snapshot(_ operation: OfflinePackOperation, thrown: OfflinePackFailure? = nil) -> Observation {
        Observation(
            operationID: operation.operationID,
            phase: operation.phase,
            failure: operation.failure ?? thrown,
            manifestVersion: operation.manifest?.version,
            retainedPriorVersion: operation.retainedPrior?.version)
    }

    private static func observe(
        _ source: OfflinePackOperation,
        _ body: (inout OfflinePackOperation) throws -> Void
    ) -> Observation {
        var copy = source
        var thrown: OfflinePackFailure?
        do {
            try body(&copy)
        } catch let error as OfflinePackFailure {
            thrown = error
        } catch {
            thrown = nil
        }
        return snapshot(copy, thrown: thrown)
    }

    private static func refused(
        _ source: OfflinePackOperation,
        _ body: (inout OfflinePackOperation) throws -> Never
    ) -> OfflinePackFailure? {
        var copy = source
        do {
            try body(&copy)
            return nil
        } catch let error as OfflinePackFailure {
            return error
        } catch {
            return nil
        }
    }

    private struct NoPublishedArtifact: OfflinePackArtifactSource {
        func publishedContract(operationID: String) -> OfflinePackPublishedContract? { nil }
        func bytes(matching contract: OfflinePackPublishedContract) -> Data? { nil }
    }
}
