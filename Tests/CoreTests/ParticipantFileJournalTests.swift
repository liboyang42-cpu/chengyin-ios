import Foundation
import XCTest
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import QuestifyCore

@MainActor final class ParticipantFileJournalTests: XCTestCase {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("participant-journal-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func marker(_ owner: String = "scope-a") -> OperationPendingRecord {
        .init(operationID: UUID(), ownerKey: owner, targetKey: "profile.participants")
    }
    func testFreshInstanceReadsExactOriginalMarkerAfterCompletedBarriers() throws {
        let url = try root(), record = marker()
        let writer = ParticipantFileJournal(directory: url)
        try writer.write(record)
        XCTAssertEqual(try ParticipantFileJournal(directory: url).pending(ownerKey: record.ownerKey, targetKey: record.targetKey), record)
    }
    func testDifferentUUIDCannotReplaceUnresolvedOwnerAndOtherOwnerIsIsolated() throws {
        let url = try root(), first = marker(), other = marker("scope-b")
        let journal = ParticipantFileJournal(directory: url)
        try journal.write(first)
        XCTAssertThrowsError(try journal.write(marker()))
        try journal.write(other)
        XCTAssertEqual(try journal.pending(ownerKey: first.ownerKey, targetKey: first.targetKey), first)
        XCTAssertEqual(try journal.pending(ownerKey: other.ownerKey, targetKey: other.targetKey), other)
    }
    func testDurableTombstoneSuppressesLegacyMarkerWithoutDeletingLegacyData() throws {
        let url = try root(), record = marker(), legacy = FileJournalLegacy()
        legacy.value = record
        let journal = ParticipantFileJournal(directory: url, legacy: legacy)
        XCTAssertEqual(try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey), record)
        try journal.clear(record)
        XCTAssertEqual(legacy.value, record)
        let restarted = ParticipantFileJournal(directory: url, legacy: legacy)
        XCTAssertNil(try restarted.pending(ownerKey: record.ownerKey, targetKey: record.targetKey))
        let next = marker(); try restarted.write(next)
        XCTAssertEqual(try restarted.pending(ownerKey: next.ownerKey, targetKey: next.targetKey), next)
    }
    func testEveryCommitCheckpointFailurePreventsNetworkDispatch() async throws {
        let points: [ParticipantFileJournal.Checkpoint] = [.temporaryWritten, .fileSynced, .renamed, .directorySynced]
        for point in points {
            let url = try root(), io = FileJournalWriter()
            let journal = ParticipantFileJournal(directory: url, legacy: nil, checkpoint: { reached in
                if reached == point { throw APIError.notConfigured }
            })
            let coordinator = ParticipantMutationCoordinator(writer: io, reader: io,
                pendingJournal: journal, pendingOwner: { "scope-a" })
            var draft = ParticipantFormDraft(); draft.fullName = "Name"; draft.mobilePhone = "13900000000"
            let review = try coordinator.prepare(.save(draft), expectedIdentity: io.identity!)
            let result = await coordinator.confirm(review)
            XCTAssertEqual(result, .blocked(.unavailable)); XCTAssertEqual(io.writes, 0)
            let recovered = try ParticipantFileJournal(directory: url).pending(ownerKey: "scope-a", targetKey: "profile.participants")
            if let recovered { XCTAssertEqual(recovered.operationID, review.id) }
        }
    }
    func testFailedClearBeforeRenameKeepsPendingMarker() throws {
        let url = try root(), record = marker()
        try ParticipantFileJournal(directory: url).write(record)
        let failing = ParticipantFileJournal(directory: url, legacy: nil, checkpoint: { if $0 == .fileSynced { throw APIError.notConfigured } })
        XCTAssertThrowsError(try failing.clear(record))
        XCTAssertEqual(try ParticipantFileJournal(directory: url).pending(ownerKey: record.ownerKey, targetKey: record.targetKey), record)
    }
    func testCorruptMarkerFailsClosedInsteadOfFallingBackToEmptyLegacy() throws {
        let url = try root(), record = marker(), journal = ParticipantFileJournal(directory: url)
        try journal.write(record)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).first { $0.pathExtension == "json" })
        try Data("broken".utf8).write(to: file)
        XCTAssertThrowsError(try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey))
        XCTAssertThrowsError(try journal.write(marker()))
    }
    func testSymlinkMarkerIsRejected() throws {
        let url = try root(), record = marker(), journal = ParticipantFileJournal(directory: url)
        try journal.write(record)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).first { $0.pathExtension == "json" })
        let other = url.appendingPathComponent("other")
        try FileManager.default.moveItem(at: file, to: other)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: other)
        XCTAssertThrowsError(try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey))
    }
    func testCompetingProcessLockFailsClosedWithoutBlockingMainActor() throws {
        let url = try root(), record = marker(), journal = ParticipantFileJournal(directory: url)
        try journal.write(record)
        let fd = open(url.appendingPathComponent(".lock").path, O_RDWR)
        XCTAssertGreaterThanOrEqual(fd, 0)
        guard fd >= 0 else { return }
        defer { _ = flock(fd, LOCK_UN); _ = close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        XCTAssertThrowsError(try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey))
    }
}
@MainActor private final class FileJournalLegacy: OperationPendingJournal {
    var value: OperationPendingRecord?
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { value }
    func write(_ record: OperationPendingRecord) throws { XCTFail("Do not write legacy defaults") }
    func clear(_ record: OperationPendingRecord) throws { XCTFail("Tombstone must not delete legacy data") }
}
@MainActor private final class FileJournalWriter: ParticipantWriting, ProfileReading {
    var identity: ProfileReadIdentity? = .init(accountID: 1, epoch: 1)
    var isConfigured = true
    var writes = 0
    func perform(_ mutation: ParticipantMutation, expectedIdentity: ProfileReadIdentity) async throws { writes += 1; XCTFail("Storage barrier failed; must not dispatch") }
    func profileParticipants() async throws -> [ProfileParticipant] { [] }
    func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.notConfigured }
    func profileOrders() async throws -> [ProfileOrder] { throw APIError.notConfigured }
    func profileOrder(id: Int) async throws -> ProfileOrder { throw APIError.notConfigured }
    func profileBadges() async throws -> ProfileBadgeWall { throw APIError.notConfigured }
}
